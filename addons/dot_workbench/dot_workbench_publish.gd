class_name DotWorkbenchPublish
extends RefCounted

## Publishes a GLB (a wearable, an action or an avatar) to the site with a creator token: one
## POST of the raw file to [code]/api/avatar/v1/publish[/code], the same path the site's form saves
## through, so validation and moderation are the site's.
##
## [codeblock]
## var pub := DotWorkbenchPublish.new()
## var token := DotWorkbenchPublish.read_token("user://creator.token")   # a file, never env or argv
## var res := await pub.publish(http, token.value, glb_bytes, {"kind": "wearable", "name": "Top hat",
##         "slot": "hat", "licence": "CC0-1.0"})
## # res.value: {id, held, url}
## [/codeblock]
##
## CLI: [code]godot --headless --path . --script res://addons/dot_workbench/tools/publish_avatar_content.gd -- --help[/code]

const CHANNEL := "workbench.publish"
const PATH := "/api/avatar/v1/publish"
const TOKEN_PATTERN := "^tmcc_[A-Za-z0-9_-]{43}$"
const KINDS := ["wearable", "action", "avatar"]
const SLOTS := ["hat", "face", "neck", "back", "waist", "hand_right", "hand_left"]
const LICENCES := ["CC0-1.0", "CC-BY-4.0", "MIT", "OWN"]
const SHARINGS := ["PRIVATE", "PUBLIC"]
## The site's caps per kind (AVATAR_WEARABLE_MAX_BYTES, AVATAR_ACTION_MAX_BYTES, AVATAR_MODEL_MAX_BYTES).
const MAX_BYTES := {"wearable": 4 * 1024 * 1024, "action": 8 * 1024 * 1024, "avatar": 25 * 1024 * 1024}
## Query parameters passed through as given; anything else in params is refused.
const FIELDS := ["kind", "name", "description", "sharing", "slot", "bone", "licence", "credit", "source", "id", "actionKind", "loop"]


## The token in [param path], trimmed and checked. Files only: env and argv end up in shell
## history and process listings.
static func read_token(path: String) -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "no creator token file", path)
	var token := FileAccess.get_file_as_string(path).strip_edges()
	if not is_token(token):
		return DotResult.fail(DotError.CODE_INVALID, "the file does not hold a creator token (tmcc_...)", path)
	return DotResult.success(token)


static func is_token(s: String) -> bool:
	return RegEx.create_from_string(TOKEN_PATTERN).search(s) != null


## The query string for [param params], or a failure naming the first bad field. Mirrors the
## route's own checks so a mistake is reported before uploading megabytes.
static func build_query(params: Dictionary) -> DotResult:
	var kind := String(params.get("kind", ""))
	if not KINDS.has(kind):
		return DotResult.fail(DotError.CODE_INVALID, "kind must be one of %s" % ", ".join(KINDS))
	if String(params.get("name", "")).strip_edges() == "":
		return DotResult.fail(DotError.CODE_INVALID, "name is required")
	for k in params:
		if not FIELDS.has(String(k)):
			return DotResult.fail(DotError.CODE_INVALID, "unknown field", String(k))
	if params.has("sharing") and not SHARINGS.has(String(params["sharing"])):
		return DotResult.fail(DotError.CODE_INVALID, "sharing must be PRIVATE or PUBLIC")
	if kind == "wearable":
		if not SLOTS.has(String(params.get("slot", ""))):
			return DotResult.fail(DotError.CODE_INVALID, "slot must be one of %s" % ", ".join(SLOTS))
		var licence := String(params.get("licence", ""))
		if not LICENCES.has(licence):
			return DotResult.fail(DotError.CODE_INVALID, "licence must be one of %s" % ", ".join(LICENCES))
		if licence != "CC0-1.0" and String(params.get("credit", "")).strip_edges() == "":
			return DotResult.fail(DotError.CODE_INVALID, "credit is required for %s" % licence)
	var parts := PackedStringArray()
	for k in FIELDS:
		if params.has(k) and String(params[k]) != "":
			parts.append("%s=%s" % [k, String(params[k]).uri_encode()])
	return DotResult.success("&".join(parts))


## Checks the bytes are a binary glTF under the kind's cap.
## A site URL the token may be sent to: https, or plain http only to this machine (a local site).
static func check_site(url: String) -> DotResult:
	var u := url.strip_edges().to_lower()
	if u.begins_with("https://") and u.length() > 8:
		return DotResult.success(url.strip_edges().trim_suffix("/"))
	if u.begins_with("http://"):
		var authority := u.substr(7).split("/")[0]
		var host := authority.substr(0, authority.find("]") + 1) if authority.begins_with("[") else authority.split(":")[0]
		if host in ["localhost", "127.0.0.1", "[::1]"]:
			return DotResult.success(url.strip_edges().trim_suffix("/"))
	return DotResult.fail(DotError.CODE_INVALID, "the site must be https (plain http only to localhost)", url.left(128))


static func check_file(kind: String, bytes: PackedByteArray) -> DotResult:
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "glTF":
		return DotResult.fail(DotError.CODE_INVALID, "not a binary glTF (.glb)")
	if bytes.size() > int(MAX_BYTES.get(kind, 0)):
		return DotResult.fail(DotError.CODE_INVALID, "larger than the site's %d MB cap for %s" % [int(MAX_BYTES.get(kind, 0)) / 1048576, kind])
	return DotResult.success(bytes.size())


## Uploads [param bytes]. [param http] is a [DotHttp] whose base url is the site; give it
## [code]max_retries = 0[/code], or a timed-out upload that did land is published twice.
## Succeeds with the site's [code]{id, held, url}[/code].
func publish(http: Node, token: String, bytes: PackedByteArray, params: Dictionary) -> DotResult:
	if http == null or not http.has_method("request"):
		return DotResult.fail(DotError.CODE_STATE, "no HTTP client")
	if not is_token(token):
		return DotResult.fail(DotError.CODE_AUTH, "not a creator token")
	var base: Variant = http.get(&"base_url")
	if base is String and not check_site(base).ok:
		return check_site(base)
	var query := build_query(params)
	if not query.ok:
		return query
	var file := check_file(String(params["kind"]), bytes)
	if not file.ok:
		return file
	var headers := {"Authorization": "Bearer %s" % token, "Content-Type": "model/gltf-binary"}
	var res: DotResult = await http.request(HTTPClient.METHOD_POST, "%s?%s" % [PATH, query.value], bytes, headers)
	if not res.ok:
		return res.wrap("publishing %s" % params["name"])
	var json := JSON.new()
	var body: Variant = json.data if json.parse(String(res.value.get("body_text", ""))) == OK else null
	if not body is Dictionary or not body.has("id"):
		return DotResult.fail(DotError.CODE_PARSE, "the site's reply has no id")
	DotLog.info(CHANNEL, "published %s %s as #%s%s" % [params["kind"], params["name"], body["id"], " (awaiting review)" if body.get("held") else ""])
	return DotResult.success(body)


func describe() -> Dictionary:
	return {"path": PATH, "kinds": KINDS}
