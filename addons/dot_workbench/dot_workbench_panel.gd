class_name DotWorkbenchPanel
extends RefCounted

## Binds an in-game profile editor screen (dot-menu's DotProfileEditorScreen, duck-typed) to a [DotWorkbenchApi].
## Edits take the HTTP page's permission, validation and audit path.
## Usage: [code]DotWorkbenchPanel.new(api, admin_uid).attach(editor_screen)[/code], after add_set on the screen.

signal status(text: String, bad: bool)

const TARGET_LABEL := "Server runtime layer (live, replicated)"

var api: DotWorkbenchApi
## Who the edits are made as; checked by the api's permit, like a console command.
var actor: Variant
var screen: Object = null


func _init(p_api: DotWorkbenchApi, p_actor: Variant) -> void:
	api = p_api
	actor = p_actor


## Points the screen's save, reset and has-override hooks at the api.
func attach(p_screen: Object) -> void:
	screen = p_screen
	screen.set("save_target", _save_changes)
	screen.set("reset_target", _reset)
	screen.set("has_override", _has_override)
	screen.set("target_label", TARGET_LABEL)


## Writes the runtime layer of the open profile to the server tier (cfg/server). Needs the save flag.
func save_to_server() -> DotResult:
	if screen == null:
		return DotResult.fail(DotError.CODE_STATE, "no screen attached")
	var kind: String = screen.call("current_kind")
	var id: String = screen.call("current_id")
	if kind.is_empty():
		return DotResult.fail(DotError.CODE_STATE, "no profile is open")
	var res := api.handle(actor, {"op": "save", "kind": kind, "id": id})
	status.emit("Saved to the server tier" if res.ok else res.error.message, not res.ok)
	return res


## Makes a new profile [param id] of [param kind], starting from [param start] (`{path: value}`). Needs the cvar flag.
func add_profile(kind: String, id: String, start: Dictionary = {}) -> DotResult:
	var res := api.handle(actor, {"op": "add", "kind": kind, "id": id, "value": start})
	status.emit("Added %s/%s" % [kind, id] if res.ok else res.error.message, not res.ok)
	return res


## Deletes profile [param id] of [param kind]: its server-tier file goes, and a shipped one is hidden. Needs the cvar flag.
func delete_profile(kind: String, id: String) -> DotResult:
	var res := api.handle(actor, {"op": "delete", "kind": kind, "id": id})
	status.emit("Deleted %s/%s" % [kind, id] if res.ok else res.error.message, not res.ok)
	return res


func _save_changes(set: DotProfileSet, id: String, changes: Dictionary) -> DotResult:
	var before := set.runtime_paths(id)
	var done: Array = []
	for key in changes:
		var res := api.handle(actor, {"op": "set", "kind": set.rel_path, "id": id, "key": key, "value": changes[key]})
		if not res.ok:
			for d in done:
				var back := {"op": "reset_key", "kind": set.rel_path, "id": id, "key": d}
				if before.has(d):
					back = {"op": "set", "kind": set.rel_path, "id": id, "key": d, "value": before[d]}
				api.handle(actor, back)
			status.emit(res.error.message, true)
			return res
		done.append(key)
	status.emit("Applied live", false)
	return DotResult.success(changes)


func _reset(set: DotProfileSet, id: String) -> DotResult:
	return api.handle(actor, {"op": "reset", "kind": set.rel_path, "id": id})


func _has_override(set: DotProfileSet, id: String) -> bool:
	return not set.runtime_paths(id).is_empty()
