class_name DotWorkbenchHttp
extends RefCounted

## Mounts a DotWorkbenchApi on a DotHttpServer: bearer-token JSON routes under /api and the static page at /. Off by default.

const CHANNEL := "workbench"
const PAGE := "res://addons/dot_workbench/web/index.html"

var api: DotWorkbenchApi
var server := DotHttpServer.new()
## Override to serve a different page; loaded once at start.
var page_path := PAGE

## Failed tokens per address inside `window_sec` before `lockout_sec` of 429s; 0 disables.
var max_failures := 5
var window_sec := 60.0
var lockout_sec := 300.0
## Override for tests: Callable() -> seconds.
var clock := Callable()

var _page := ""
## address -> {"times": Array[float] of recent failures, "until": float lockout end}
var _fails: Dictionary = {}


func _init(p_api: DotWorkbenchApi = null) -> void:
	api = p_api if p_api != null else DotWorkbenchApi.new()
	server.route("GET", "/", _on_page)
	server.route("GET", "/index.html", _on_page)
	server.route("POST", "/api", _on_envelope)
	for m in ["GET", "PUT", "DELETE", "POST"]:
		server.route_prefix(m, "/api/profiles", _on_profiles)


## Serves [param prefix] (e.g. "/api/things") behind the same bearer token and lockout as the profile routes. [param handler] is `func(actor, req: DotHttpRequest) -> DotResult`, called only when the actor holds [param flag] (checked here; empty skips the check). Register the flag on the token with [method DotWorkbenchApi.add_flag].
func mount_extension(prefix: String, handler: Callable, flag: String = "", methods: PackedStringArray = PackedStringArray(["GET", "POST", "PUT", "DELETE"])) -> void:
	var route := func(req: DotHttpRequest) -> DotHttpResponse:
		var auth: Variant = _gate(req)
		if auth is DotHttpResponse:
			return auth
		if not flag.is_empty() and not api.permits(auth.value, flag):
			return _reply(DotResult.fail(DotError.CODE_FORBIDDEN, "needs the '%s' permission" % flag))
		return _reply(handler.call(auth.value, req))
	for m in methods:
		server.route_prefix(m, prefix, route)


## Reads the `workbench:` block of cfg/server.yml (defaults when absent).
static func read_config(path: String = "res://cfg/server.yml") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var res := DotYaml.parse_file(path)
	if not res.ok or not (res.value is Dictionary):
		return {}
	var block: Variant = (res.value as Dictionary).get("workbench", {})
	return block if block is Dictionary else {}


## Starts the HTTP side from the `workbench:` block. Disabled (the default) is a success that opens nothing.
## The admin token comes from [code]token_file[/code] only; there is no environment or command-line path for it.
func start_from_config(cfg: Dictionary) -> DotResult:
	if not bool(cfg.get("enabled", false)):
		return DotResult.success(0)
	var token_file := str(cfg.get("token_file", ""))
	if not token_file.is_empty():
		var tok := DotHttpServer.read_secret_file(token_file)
		if not tok.ok:
			return tok.wrap("workbench token")
		api.set_admin_token(tok.value)
	elif not api.identity.is_valid():
		return DotResult.fail(DotError.CODE_INVALID, "workbench enabled with no token_file and no identity; refusing to start")
	max_failures = int(cfg.get("max_failures", max_failures))
	window_sec = float(cfg.get("window_sec", window_sec))
	lockout_sec = float(cfg.get("lockout_sec", lockout_sec))
	var tls: Dictionary = cfg.get("tls", {}) if cfg.get("tls", {}) is Dictionary else {}
	var native := str(tls.get("mode", "proxy")) == "native"
	_load_page()
	return server.start(int(cfg.get("port", 8790)), str(cfg.get("bind", DotHttpServer.LOOPBACK)),
		str(tls.get("cert", "")) if native else "", str(tls.get("key", "")) if native else "")


## Call from the host's _process.
func poll() -> void:
	server.poll()


func stop() -> void:
	server.stop()


func describe() -> Dictionary:
	return {"server": server.describe(), "page_loaded": not _page.is_empty(), "rate_limit": {"max_failures": max_failures, "window_sec": window_sec, "lockout_sec": lockout_sec, "locked": locked_addresses()}}


## Addresses currently locked out after failed tokens.
func locked_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	var t := _now()
	for a in _fails:
		if float(_fails[a]["until"]) > t:
			out.append(a)
	return out


## Lifts a lockout, for an operator who locked themselves out.
func clear_lockout(address: String) -> void:
	_fails.erase(address)


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() / 1000.0


# Returns a refusal response, or null when the token is good. Counts failures per address.
func _gate(req: DotHttpRequest) -> Variant:
	var addr := req.remote_address
	var t := _now()
	var rec: Dictionary = _fails.get(addr, {"times": [], "until": 0.0})
	if max_failures > 0 and float(rec["until"]) > t:
		var r := DotHttpResponse.json(DotWorkbenchApi.to_reply(DotResult.fail(DotError.CODE_FORBIDDEN, "too many failed tokens; try again later")), 429)
		r.headers["Retry-After"] = str(int(ceil(float(rec["until"]) - t)))
		return r
	var auth := api.authenticate(req.bearer_token())
	if auth.ok:
		_fails.erase(addr)
		return auth
	if max_failures > 0:
		var times: Array = (rec["times"] as Array).filter(func(x: float) -> bool: return t - x < window_sec)
		times.append(t)
		rec["times"] = times
		if times.size() >= max_failures:
			rec["until"] = t + lockout_sec
			rec["times"] = []
			DotLog.warn(CHANNEL, "address locked out after failed tokens", {"address": addr, "seconds": lockout_sec})
		_fails[addr] = rec
	return _unauthorized()


func _load_page() -> void:
	_page = FileAccess.get_file_as_string(page_path) if FileAccess.file_exists(page_path) else ""
	if _page.is_empty():
		DotLog.warn(CHANNEL, "workbench page missing; the API still works", {"path": page_path})


func _on_page(_req: DotHttpRequest) -> DotHttpResponse:
	if _page.is_empty():
		return DotHttpResponse.error(404, "no page installed")
	var r := DotHttpResponse.html(_page)
	r.headers["Cache-Control"] = "no-store"
	r.headers["Content-Security-Policy"] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
	r.headers["Referrer-Policy"] = "no-referrer"
	return r


# Generic envelope: POST /api with the request object, the reply object back.
func _on_envelope(req: DotHttpRequest) -> DotHttpResponse:
	var auth: Variant = _gate(req)
	if auth is DotHttpResponse:
		return auth
	var body := req.json_body()
	if not body.ok or not (body.value is Dictionary):
		return _reply(DotResult.fail(DotError.CODE_INVALID, "body must be a JSON object"))
	return _reply(api.handle(auth.value, body.value))


# REST sugar over the same ops: /api/profiles[/kind[/id[/key]]] and POST /api/profiles/{save,add,delete}/kind/id.
func _on_profiles(req: DotHttpRequest) -> DotHttpResponse:
	var auth: Variant = _gate(req)
	if auth is DotHttpResponse:
		return auth
	var seg := PackedStringArray()
	for s in req.rest.split("/", false):
		seg.append(s)
	var body: Dictionary = {}
	if not req.body.is_empty():
		var parsed := req.json_body()
		if not parsed.ok or not (parsed.value is Dictionary):
			return _reply(DotResult.fail(DotError.CODE_INVALID, "body must be a JSON object"))
		body = parsed.value
	var op := {}
	match req.method:
		"GET":
			if seg.size() > 2:
				return DotHttpResponse.error(404)
			op = {"op": "list" if seg.size() < 2 else "get", "kind": _at(seg, 0), "id": _at(seg, 1)}
		"PUT":
			if seg.size() != 3 or not body.has("value"):
				return _reply(DotResult.fail(DotError.CODE_INVALID, "PUT /api/profiles/<kind>/<id>/<key> with {\"value\": ...}"))
			op = {"op": "set", "kind": seg[0], "id": seg[1], "key": seg[2], "value": body["value"]}
		"DELETE":
			if seg.size() < 2 or seg.size() > 3:
				return DotHttpResponse.error(404)
			op = {"op": "reset_key" if seg.size() == 3 else "reset", "kind": seg[0], "id": seg[1], "key": _at(seg, 2)}
		"POST":
			if seg.size() != 3 or not ["save", "add", "delete"].has(seg[0]):
				return DotHttpResponse.error(404)
			op = {"op": seg[0], "kind": seg[1], "id": seg[2]}
			if seg[0] == "add" and body.has("value"):
				op["value"] = body["value"]
	return _reply(api.handle(auth.value, op))


static func _at(seg: PackedStringArray, i: int) -> String:
	return seg[i] if i < seg.size() else ""


func _unauthorized() -> DotHttpResponse:
	var r := DotHttpResponse.json(DotWorkbenchApi.to_reply(DotResult.fail(DotError.CODE_AUTH, "a valid bearer token is required")), 401)
	r.headers["WWW-Authenticate"] = "Bearer"
	return r


func _reply(res: DotResult) -> DotHttpResponse:
	var status := 200
	if not res.ok:
		match res.error.code:
			DotError.CODE_AUTH: status = 401
			DotError.CODE_FORBIDDEN: status = 403
			DotError.CODE_CONFLICT: status = 409
			DotError.CODE_INTERNAL, DotError.CODE_IO: status = 500
			_: status = 400
	var r := DotHttpResponse.json(DotWorkbenchApi.to_reply(res), status)
	r.headers["Cache-Control"] = "no-store"
	return r
