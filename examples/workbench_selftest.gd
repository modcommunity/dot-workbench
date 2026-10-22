extends Node

## Exercises [DotWorkbenchApi]: list, get, set, reset, save, permission refusal and bad input.
##
## [codeblock]
## godot --headless --path . res://examples/workbench_selftest.tscn
## [/codeblock]

const SECTIONS := 6
const CHECKS := 33
const BASE := "user://workbench_selftest"

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_line("dot-workbench self-test")
	_clean()
	_test_read()
	_test_set_reset()
	_test_save()
	_test_permission()
	_test_bad_input()
	_test_json()
	_clean()
	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		_line("ERROR: %d sections, %d checks ran; expected %d and %d." % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _api() -> DotWorkbenchApi:
	_clean()
	_w("addons/dot-npc/npc/zombie.yml", "health: 50\nspeed: 2.5\n")
	_w("addons/dot-npc/npc/ghoul.yml", "health: 20\n")
	var s := DotProfileSet.create("dot-npc", "mygame", "npc", [
		DotProfileSet.field("health", "int", 100, {"min": 1, "max": 1000}),
		DotProfileSet.field("speed", "float", 3.0, {"min": 0.0, "max": 50.0}),
		DotProfileSet.field("mode", "string", "melee", {"enum": ["melee", "ranged"]}),
	])
	s.roots = PackedStringArray([BASE])
	s.override_prefix = "wbt"
	var api := DotWorkbenchApi.new()
	api.runtime.save_root = BASE
	api.add_set(s)
	api.set_admin_token("s3cret")
	api.permit = func(actor: Variant, flag: String) -> bool: return actor == "mod" and flag == "cvar"
	return api


func _req(op: String, kind: String = "npc", id: String = "zombie", key: String = "", value: Variant = null) -> Dictionary:
	return {"op": op, "kind": kind, "id": id, "key": key, "value": value}


func _code(res: DotResult) -> String:
	return "" if res.ok else res.error.code


func _test_read() -> void:
	_section("list and get")
	var api := _api()
	var a := DotWorkbenchApi.TOKEN_ACTOR
	var kinds := api.handle(a, {"op": "list"})
	_check(kinds.ok and kinds.value["kinds"] == ["npc"], "list without a kind returns the kinds")
	var ids := api.handle(a, {"op": "list", "kind": "npc"})
	_check(ids.ok and ids.value["ids"].size() == 2 and ids.value["ids"].has("ghoul"), "list with a kind returns its ids")
	var got := api.handle(a, _req("get"))
	_check(got.ok and got.value["values"]["health"] == 50, "get returns the effective values")
	_check(got.value["rev"] == 0 and got.value["runtime"].is_empty(), "an unedited profile has revision 0 and no runtime layer")
	_check(_code(api.handle(a, _req("get", "npc", "nobody"))) == DotError.CODE_INVALID, "get of a missing profile is invalid")
	_check(_code(api.handle(a, {"op": "list", "kind": "weapon"})) == DotError.CODE_INVALID, "list of an unknown kind is invalid")


func _test_set_reset() -> void:
	_section("set and reset")
	var api := _api()
	var a := DotWorkbenchApi.TOKEN_ACTOR
	var r := api.handle(a, _req("set", "npc", "zombie", "health", 400))
	_check(r.ok, "set succeeds")
	var got := api.handle(a, _req("get"))
	_check(got.value["values"]["health"] == 400, "get shows the new value")
	_check(got.value["rev"] == 1 and got.value["runtime"]["health"] == 400, "revision bumped and runtime layer listed")
	_check(api.handle(a, _req("reset_key", "npc", "zombie", "health")).ok, "reset_key succeeds")
	_check(api.handle(a, _req("get")).value["values"]["health"] == 50, "reset_key restores the file value")
	api.handle(a, _req("set", "npc", "zombie", "speed", 9.0))
	_check(api.handle(a, _req("reset")).ok, "reset succeeds")
	_check(api.handle(a, _req("get")).value["runtime"].is_empty(), "reset drops the whole runtime layer")


func _test_save() -> void:
	_section("save")
	var api := _api()
	var a := DotWorkbenchApi.TOKEN_ACTOR
	api.handle(a, _req("set", "npc", "zombie", "health", 321))
	var r := api.handle(a, _req("save"))
	_check(r.ok, "save succeeds for the token")
	_check(FileAccess.file_exists(BASE.path_join("server/npc/zombie.yml")), "the server-tier file is written")
	api.handle(a, _req("reset"))
	_check(api.handle(a, _req("get")).value["values"]["health"] == 321, "the saved value survives a reset")


func _test_permission() -> void:
	_section("permission")
	var api := _api()
	_check(api.handle("mod", _req("set", "npc", "zombie", "health", 5)).ok, "a mod with cvar may edit")
	_check(_code(api.handle("mod", _req("save"))) == DotError.CODE_FORBIDDEN, "a mod without root may not save")
	_check(_code(api.handle("stranger", _req("set", "npc", "zombie", "health", 6))) == DotError.CODE_FORBIDDEN, "a stranger may not edit")
	_check(_code(api.handle("stranger", {"op": "list"})) == DotError.CODE_FORBIDDEN, "a stranger may not list")
	_check(api.handle("mod", _req("get")).value["values"]["health"] == 5, "a refused edit changed nothing")
	_check(_code(api.authenticate("wrong")) == DotError.CODE_FORBIDDEN, "a wrong token is refused")
	_check(_code(api.authenticate("")) == DotError.CODE_FORBIDDEN, "an empty token is refused")
	var bare := DotWorkbenchApi.new()
	_check(_code(bare.authenticate("anything")) == DotError.CODE_FORBIDDEN, "no configured token refuses everyone")


func _test_bad_input() -> void:
	_section("bad input")
	var api := _api()
	var a := DotWorkbenchApi.TOKEN_ACTOR
	_check(_code(api.handle(a, _req("set", "npc", "zombie", "health", 99999))) == DotError.CODE_INVALID, "out of range is invalid")
	_check(_code(api.handle(a, _req("set", "npc", "zombie", "nope", 1))) == DotError.CODE_INVALID, "unknown key is invalid")
	_check(_code(api.handle(a, _req("explode"))) == DotError.CODE_INVALID, "unknown op is invalid")
	_check(_code(api.handle(a, {"op": "set", "kind": 5, "id": "zombie"})) == DotError.CODE_INVALID, "a non-string kind is invalid")
	_check(api.handle(a, _req("get")).value["rev"] == 0, "bad requests bump no revision")


func _test_json() -> void:
	_section("JSON entry point")
	var api := _api()
	var ok: Dictionary = JSON.parse_string(api.handle_json("s3cret", '{"op":"get","kind":"npc","id":"zombie"}'))
	_check(ok["ok"] == true and ok["value"]["id"] == "zombie", "a good token and body gives an ok reply")
	var denied: Dictionary = JSON.parse_string(api.handle_json("bad", '{"op":"list"}'))
	_check(denied["ok"] == false and denied["error"]["code"] == DotError.CODE_FORBIDDEN, "a bad token gives an error reply with a code")
	var junk: Dictionary = JSON.parse_string(api.handle_json("s3cret", "[1,2"))
	_check(junk["ok"] == false and junk["error"]["code"] == DotError.CODE_INVALID, "a malformed body is invalid, not a crash")
	var set: Dictionary = JSON.parse_string(api.handle_json("s3cret", '{"op":"set","kind":"npc","id":"ghoul","key":"mode","value":"ranged"}'))
	_check(set["ok"] == true and set["value"]["paths"]["mode"] == "ranged", "set over JSON returns the changed row")


func _w(rel: String, text: String) -> void:
	var path := BASE.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean() -> void:
	_rm(BASE)


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("== %s ==" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
