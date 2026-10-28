class_name DotWorkbenchTrails
extends RefCounted

## The trail form's server side: list, upload and delete a server's trails for owners and admins holding the `trail` flag. Everything is validated by dot-trail's store (duck-typed, so this addon does not depend on it); the result is saved to the store directory, which is the pack source.

const CHANNEL := "workbench.trails"
const FLAG := "trail"
const OP_LIST := "trail_list"
const OP_UPLOAD := "trail_upload"
const OP_DELETE := "trail_delete"

var api: DotWorkbenchApi
## A dot-trail DotTrailStore: `submit(meta, bytes, name)`, `save()`, `registry`.
var store: Object
## Called with no arguments after a change is saved, e.g. to rebuild the pack or tell connected players.
var changed: Callable = Callable()


func _init(p_api: DotWorkbenchApi, p_store: Object) -> void:
	api = p_api
	store = p_store


## [param req]: `{op: "trail_upload", meta: {id, title, width, lifetime, color, blend, access, groups, price, licence, author, url}, image: <base64>, file: "x.png"}`, `{op: "trail_delete", id}` or `{op: "trail_list"}`. Value on success is JSON-able.
func handle(actor: Variant, req: Dictionary) -> DotResult:
	if not api.permits(actor, FLAG):
		DotLog.warn(CHANNEL, "trail request refused", {"op": str(req.get("op", ""))})
		return DotResult.fail(DotError.CODE_FORBIDDEN, "trails need the '%s' permission" % FLAG)
	match str(req.get("op", "")):
		OP_LIST:
			return DotResult.success(_list())
		OP_UPLOAD:
			return _upload(req)
		OP_DELETE:
			return _delete(str(req.get("id", "")))
	return DotResult.fail(DotError.CODE_INVALID, "unknown trail op")


func _list() -> Dictionary:
	var out: Array = []
	var registry: Object = store.get("registry")
	for id: String in registry.call("ids"):
		out.append((registry.call("get_def", id) as Object).call("to_dict"))
	return {"trails": out}


func _upload(req: Dictionary) -> DotResult:
	var meta: Variant = req.get("meta")
	var b64: Variant = req.get("image")
	if not (meta is Dictionary) or not (b64 is String) or (b64 as String).is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "an upload needs meta (object) and image (base64)")
	var limit := int(store.get("registry").get("config").get("max_upload_bytes"))
	if (b64 as String).length() > limit * 4 / 3 + 16:
		return DotResult.fail(DotError.CODE_QUOTA, "image is larger than %d bytes" % limit)
	var bytes := Marshalls.base64_to_raw(b64)
	var made: DotResult = store.call("submit", meta, bytes, str(req.get("file", "")))
	if not made.ok:
		return made
	return _persist({"id": str((meta as Dictionary).get("id", ""))})


func _delete(id: String) -> DotResult:
	if not bool((store.get("registry") as Object).call("remove", id)):
		return DotResult.fail(DotError.CODE_INVALID, "no such trail", id)
	return _persist({"id": id, "deleted": true})


func _persist(reply: Dictionary) -> DotResult:
	var saved: DotResult = store.call("save")
	if not saved.ok:
		return saved
	if changed.is_valid():
		changed.call()
	return DotResult.success(reply)
