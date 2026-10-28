class_name DotWorkbenchApi
extends RefCounted

## Maps JSON-able request dictionaries onto DotProfileRuntime and returns JSON-able replies; no transport.

const CHANNEL := "workbench"
const TOKEN_ACTOR := "workbench-token"
const OP_LIST := "list"
const OP_GET := "get"

## Flag a caller needs for list and get; edits use the runtime's own edit_flag and save_flag.
var read_flag := "cvar"
## Flags the admin token holds; the token is a full admin by default.
var token_flags := PackedStringArray(["cvar", "root"])
## Optional Callable(token) -> actor or null, for dot-auth style identities (duck-typed).
var identity: Callable = Callable()
## Optional Callable(req) called with each write request this api applied, to repeat it elsewhere: a client's panel edits its local copy and forwards here to the server, which checks it again.
var forward: Callable = Callable()

## The host's Callable(actor, flag) -> bool (dot-server's DotAdminManager); set it here, not on the runtime.
var permit: Callable = Callable():
	set(v):
		_inner_permit = v
		permit = v

var runtime: DotProfileRuntime
var _token := ""
var _inner_permit: Callable = Callable()
var _sets: Dictionary = {}
## "kind/id" -> {dotted path: value before the first edit of this session}.
var _baseline: Dictionary = {}


func _init(p_runtime: DotProfileRuntime = null) -> void:
	runtime = p_runtime if p_runtime != null else DotProfileRuntime.new()
	if runtime.permit.is_valid():
		permit = runtime.permit
	runtime.permit = _permit


## Registers a set with the runtime and with the list/get surface.
func add_set(set: DotProfileSet) -> void:
	runtime.add_set(set)
	_sets[set.rel_path] = set


## Sets the admin token (read from a secrets file by the host, never from env or argv).
func set_admin_token(token: String) -> void:
	_token = token


## Value on success: the actor to pass to [method handle]. An empty configured token refuses everything.
func authenticate(token: String) -> DotResult:
	if token.is_empty():
		return DotResult.fail(DotError.CODE_FORBIDDEN, "missing token")
	if identity.is_valid():
		var who: Variant = identity.call(token)
		if who != null:
			return DotResult.success(who)
	if not _token.is_empty() and _safe_equal(token, _token):
		return DotResult.success(TOKEN_ACTOR)
	DotLog.warn(CHANNEL, "workbench auth refused", {})
	return DotResult.fail(DotError.CODE_FORBIDDEN, "bad token")


## Handles one request; value on success is a JSON-able Dictionary.
func handle(actor: Variant, req: Dictionary) -> DotResult:
	var op := str(req.get("op", ""))
	if op == OP_LIST or op == OP_GET:
		if not _permit(actor, read_flag):
			return DotResult.fail(DotError.CODE_FORBIDDEN, "reading profiles needs '%s'" % read_flag)
		return _read_list(req) if op == OP_LIST else _read_get(req)
	for k in ["kind", "id", "key"]:
		if req.has(k) and not (req[k] is String):
			return DotResult.fail(DotError.CODE_INVALID, "'%s' must be a string" % k)
	var before: Variant = _value_before(req)
	var res := runtime.handle_request(actor, req)
	if res.ok and forward.is_valid():
		forward.call(req)
	if res.ok and before != null and not (res.value is Dictionary and res.value.get("changed", true) == false):
		var bkey := "%s/%s" % [req["kind"], req["id"]]
		if not _baseline.has(bkey):
			_baseline[bkey] = {}
		if not (_baseline[bkey] as Dictionary).has(req["key"]):
			_baseline[bkey][req["key"]] = before[0]
	return res


## The shipped value of [param path] before this session's first edit, for "export changes as defaults":
## Dictionary {found: bool, value}. Falls back to the profile without its runtime layer.
func baseline_value(kind: String, id: String, path: String) -> Dictionary:
	var rec: Dictionary = _baseline.get("%s/%s" % [kind, id], {})
	if rec.has(path):
		return {"found": true, "value": rec[path]}
	return _lookup_without_runtime(kind, id, path)


## The kinds registered with [method add_set].
func kinds() -> Array:
	return _sets.keys()


## The set behind [param kind], or null.
func get_set(kind: String) -> DotProfileSet:
	return _sets.get(kind)


## Turns a result into the wire reply: {ok: true, value} or {ok: false, error: {code, message}}.
static func to_reply(res: DotResult) -> Dictionary:
	if res.ok:
		return {"ok": true, "value": res.value}
	return {"ok": false, "error": {"code": res.error.code, "message": res.error.message}}


## Token + JSON text in, JSON text out; the whole API for a transport that only moves strings.
func handle_json(token: String, text: String) -> String:
	var auth := authenticate(token)
	if not auth.ok:
		return JSON.stringify(to_reply(auth))
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not (parsed is Dictionary):
		return JSON.stringify(to_reply(DotResult.fail(DotError.CODE_INVALID, "body must be a JSON object")))
	return JSON.stringify(to_reply(handle(auth.value, parsed)))


## `[value]` of a `set` request's path as it is now (without the runtime layer), or null when not a set.
func _value_before(req: Dictionary) -> Variant:
	if str(req.get("op", "")) != "set" or not req.has("key"):
		return null
	var found := _lookup_without_runtime(str(req.get("kind", "")), str(req.get("id", "")), str(req["key"]))
	return [found["value"]] if found["found"] else null


func _lookup_without_runtime(kind: String, id: String, path: String) -> Dictionary:
	if not _sets.has(kind) or not (_sets[kind] as DotProfileSet).has_id(id):
		return {"found": false, "value": null}
	var set: DotProfileSet = _sets[kind]
	var held := set.runtime_paths(id)
	set.set_runtime(id, {})
	var loaded := set.load_profile(id)
	set.set_runtime(id, held)
	if not loaded.ok:
		return {"found": false, "value": null}
	var d: Dictionary = (loaded.value as DotProfile).to_dictionary()
	var tree: Dictionary = (d["values"] as Dictionary).duplicate(true)
	tree["extra"] = d["extra"]
	var parts := path.split(".")
	var node: Variant = tree
	for part in parts:
		if not (node is Dictionary) or not (node as Dictionary).has(part):
			return {"found": false, "value": null}
		node = node[part]
	return {"found": true, "value": node}


## Lets the admin token hold [param flag], for an extension that gates its own routes on it. Idempotent.
func add_flag(flag: String) -> void:
	if not token_flags.has(flag):
		token_flags.append(flag)


## True when [param actor] holds [param flag] (the token's flags, or the host's permit callable). For extensions mounted with [method DotWorkbenchHttp.mount_extension].
func permits(actor: Variant, flag: String) -> bool:
	return _permit(actor, flag)


func _permit(actor: Variant, flag: String) -> bool:
	if actor is String and actor == TOKEN_ACTOR:
		return token_flags.has(flag)
	return _inner_permit.is_valid() and bool(_inner_permit.call(actor, flag))


func _read_list(req: Dictionary) -> DotResult:
	var kind := str(req.get("kind", ""))
	if kind.is_empty():
		return DotResult.success({"kinds": _sets.keys()})
	if not _sets.has(kind):
		return DotResult.fail(DotError.CODE_INVALID, "unknown profile kind '%s'" % kind)
	var ids: Array = []
	for id in (_sets[kind] as DotProfileSet).list_ids():
		ids.append(String(id))
	return DotResult.success({"kind": kind, "ids": ids})


func _read_get(req: Dictionary) -> DotResult:
	var kind := str(req.get("kind", ""))
	var id := str(req.get("id", ""))
	if not _sets.has(kind):
		return DotResult.fail(DotError.CODE_INVALID, "unknown profile kind '%s'" % kind)
	var set: DotProfileSet = _sets[kind]
	if not set.has_id(id):
		return DotResult.fail(DotError.CODE_INVALID, "%s/%s: no such profile" % [kind, id])
	var loaded := set.load_profile(id)
	if not loaded.ok:
		return loaded
	return DotResult.success({
		"kind": kind, "id": id, "rev": runtime.revision(kind, id),
		"values": (loaded.value as DotProfile).to_dictionary()["values"],
		"extra": (loaded.value as DotProfile).to_dictionary()["extra"],
		"runtime": set.runtime_paths(id),
	})


static func _safe_equal(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	var diff := x.size() ^ y.size()
	for i in mini(x.size(), y.size()):
		diff |= x[i] ^ y[i]
	return diff == 0
