extends Node

## Exercises [DotWorkbenchApi] and its HTTP adapter: list, get, set, reset, save, permission refusal and bad input.
## Run: godot --headless --path . res://examples/workbench_selftest.tscn

const SECTIONS := 13
const CHECKS := 121
const BASE := "user://workbench_selftest"
const OUT := "user://workbench_selftest_out"

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
	_test_http()
	_test_extension()
	_test_panel()
	_test_identity()
	_test_export()
	_test_add_delete()
	_test_schema_field()
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
	_check(FileAccess.file_exists(BASE.path_join("server/game/mygame/npc/zombie.yml")), "the server-tier file is written")
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


func _http_call(h: DotWorkbenchHttp, method: String, path: String, token: String = "s3cret", body: String = "") -> Dictionary:
	var head := "%s %s HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\n" % [method, path, body.to_utf8_buffer().size()]
	if token != "":
		head += "Authorization: Bearer %s\r\n" % token
	var c := StreamPeerTCP.new()
	c.connect_to_host("127.0.0.1", h.server.port())
	var out := PackedByteArray()
	var sent := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		c.poll()
		if not sent and c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			c.put_data((head + "\r\n" + body).to_utf8_buffer())
			sent = true
		h.poll()
		c.poll()
		if c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			var n := c.get_available_bytes()
			if n > 0:
				out.append_array(c.get_data(n)[1])
		elif sent:
			break
		OS.delay_msec(1)
	var text := out.get_string_from_utf8()
	var i := text.find("\r\n\r\n")
	var payload := text.substr(i + 4) if i >= 0 else ""
	var parsed: Variant = JSON.parse_string(payload) if payload.begins_with("{") else null
	return {"status": int(text.split(" ")[1]) if text.length() > 12 else -1, "json": parsed if parsed is Dictionary else {}, "text": payload}


func _test_http() -> void:
	_section("HTTP adapter")
	if not DotPlatform.can_listen():
		_line("  skipped: this platform cannot listen on a socket (the checks below are desktop only)")
		return
	var api := _api()
	var h := DotWorkbenchHttp.new(api)
	var off := h.start_from_config({"enabled": false})
	_check(off.ok and not h.server.is_listening(), "disabled by default opens nothing")
	_check(not DotWorkbenchHttp.new(_api()).start_from_config({"enabled": true}).ok, "enabled with no token source refuses to start")
	_check(not DotWorkbenchHttp.new(_api()).start_from_config({"enabled": true, "token_file": BASE + "/missing.token"}).ok, "a missing token file refuses to start")
	_w("workbench.token", "  s3cret\n")
	var res := h.start_from_config({"enabled": true, "port": 0, "token_file": BASE + "/workbench.token"})
	_check(res.ok and h.server.is_listening(), "enabled with a token file listens on loopback")
	if not res.ok:
		return
	var page := _http_call(h, "GET", "/", "")
	_check(page["status"] == 200 and str(page["text"]).contains("<title>Workbench</title>"), "the page is served without a token")
	_check(_http_call(h, "GET", "/api/profiles", "")["status"] == 401, "no token is 401")
	var wrong := _http_call(h, "GET", "/api/profiles", "wrong")
	_check(wrong["status"] == 401 and not str(wrong["text"]).contains("wrong") and not str(wrong["text"]).contains("s3cret"), "a wrong token is 401 and the reply echoes no token")
	var kinds := _http_call(h, "GET", "/api/profiles")
	_check(kinds["status"] == 200 and kinds["json"]["value"]["kinds"] == ["npc"], "GET /api/profiles lists kinds")
	var ids := _http_call(h, "GET", "/api/profiles/npc")
	_check(ids["json"]["value"]["ids"].has("zombie"), "GET kind lists ids")
	var set := _http_call(h, "PUT", "/api/profiles/npc/zombie/health", "s3cret", '{"value": 77}')
	_check(set["status"] == 200, "PUT sets a field")
	var got := _http_call(h, "GET", "/api/profiles/npc/zombie")
	_check(got["json"]["value"]["values"]["health"] == 77 and got["json"]["value"]["rev"] == 1, "GET shows the edit and revision")
	_check(_http_call(h, "PUT", "/api/profiles/npc/zombie/health", "s3cret", '{"value": 99999}')["status"] == 400, "an invalid value is 400 with the runtime's message")
	_check(_http_call(h, "PUT", "/api/profiles/npc/zombie/health", "s3cret", "{nope")["status"] == 400, "a malformed body is 400")
	var env := _http_call(h, "POST", "/api", "s3cret", '{"op":"get","kind":"npc","id":"zombie"}')
	_check(env["json"]["ok"] == true and env["json"]["value"]["id"] == "zombie", "POST /api envelope works")
	_check(_http_call(h, "DELETE", "/api/profiles/npc/zombie/health")["status"] == 200, "DELETE key resets it")
	api.handle(DotWorkbenchApi.TOKEN_ACTOR, _req("set", "npc", "zombie", "speed", 4.0))
	_check(_http_call(h, "POST", "/api/profiles/save/npc/zombie")["json"]["ok"] == true, "POST save writes the server layer")
	_check(_http_call(h, "DELETE", "/api/profiles/npc/zombie")["status"] == 200, "DELETE profile resets all")
	api.token_flags = PackedStringArray(["cvar"])
	_check(_http_call(h, "POST", "/api/profiles/save/npc/zombie")["status"] == 403, "a token without root cannot save (403)")
	var now := [100.0]
	h.clock = func() -> float: return now[0]
	h.max_failures = 3
	h.window_sec = 10.0
	h.lockout_sec = 30.0
	_http_call(h, "GET", "/api/profiles", "bad")
	_http_call(h, "GET", "/api/profiles", "bad")
	_check(_http_call(h, "GET", "/api/profiles")["status"] == 200, "a good token between failures still works and resets the count")
	for i in 3:
		_http_call(h, "GET", "/api/profiles", "bad")
	var locked := _http_call(h, "GET", "/api/profiles")
	_check(locked["status"] == 429, "failures at the limit lock the address out with 429")
	_check(h.locked_addresses().has("127.0.0.1") and h.describe()["rate_limit"]["locked"].has("127.0.0.1"), "describe shows the locked address")
	now[0] = 140.0
	_check(_http_call(h, "GET", "/api/profiles")["status"] == 200, "the lockout lifts after lockout_sec")
	_http_call(h, "GET", "/api/profiles", "bad")
	_http_call(h, "GET", "/api/profiles", "bad")
	now[0] = 160.0
	_http_call(h, "GET", "/api/profiles", "bad")
	_check(_http_call(h, "GET", "/api/profiles", "bad")["status"] == 401, "failures older than window_sec do not count")
	h.max_failures = 0
	for i in 5:
		_http_call(h, "GET", "/api/profiles", "bad")
	_check(_http_call(h, "GET", "/api/profiles")["status"] == 200, "max_failures 0 disables the limit")
	h.stop()


func _test_extension() -> void:
	_section("extension routes")
	if not DotPlatform.can_listen():
		_line("  skipped: this platform cannot listen on a socket")
		return
	var api := _api()
	var h := DotWorkbenchHttp.new(api)
	var seen := []
	h.mount_extension("/api/things", func(actor: Variant, req: DotHttpRequest) -> DotResult:
		seen.append([actor, req.method, req.rest])
		return DotResult.success({"echo": req.rest.trim_prefix("/")}), "thing", PackedStringArray(["GET", "POST"]))
	_w("ext.token", "s3cret")
	var res := h.start_from_config({"enabled": true, "port": 0, "token_file": BASE + "/ext.token"})
	if not res.ok:
		for i in 7:
			_check(false, "adapter did not start")
		return
	_check(_http_call(h, "GET", "/api/things", "")["status"] == 401, "an extension route needs the bearer token")
	_check(_http_call(h, "GET", "/api/things/a")["status"] == 403 and seen.is_empty(), "a flag the token lacks is 403 and the handler is not called")
	api.add_flag("thing")
	api.add_flag("thing")
	_check(api.token_flags.count("thing") == 1, "add_flag is idempotent")
	var ok := _http_call(h, "GET", "/api/things/a")
	_check(ok["status"] == 200 and ok["json"]["value"]["echo"] == "a", "once the token holds the flag the handler answers")
	_check(seen.size() == 1 and seen[0][0] == DotWorkbenchApi.TOKEN_ACTOR and seen[0][1] == "GET", "the handler is given the actor and the request")
	_check(_http_call(h, "DELETE", "/api/things/a")["status"] != 200, "a method outside the mounted list is not routed")
	for i in 5:
		_http_call(h, "GET", "/api/things", "bad")
	_check(_http_call(h, "GET", "/api/things")["status"] == 429, "the profile routes' lockout covers extension routes")
	h.stop()


## Stands in for DotProfileEditorScreen so the binding is tested without dot-ui or dot-menu.
class FakeScreen extends RefCounted:
	var save_target: Callable
	var reset_target: Callable
	var has_override: Callable
	var target_label := ""
	var kind := "npc"
	var id := "zombie"
	func current_kind() -> String:
		return kind
	func current_id() -> String:
		return id


func _test_panel() -> void:
	_section("in-game panel binding")
	var api := _api()
	var set: DotProfileSet = api._sets["npc"]
	var scr := FakeScreen.new()
	var panel := DotWorkbenchPanel.new(api, DotWorkbenchApi.TOKEN_ACTOR)
	panel.attach(scr)
	_check(scr.target_label == DotWorkbenchPanel.TARGET_LABEL and scr.save_target.is_valid(), "attach sets the hooks and label")
	_check(not scr.has_override.call(set, "zombie"), "no override before an edit")
	var r: DotResult = scr.save_target.call(set, "zombie", {"health": 222, "speed": 7.5})
	_check(r.ok and api.runtime.revision("npc", "zombie") == 2, "Apply writes each key through the runtime (revision 2)")
	_check(api.handle(DotWorkbenchApi.TOKEN_ACTOR, _req("get")).value["values"]["health"] == 222, "the edit is live")
	_check(scr.has_override.call(set, "zombie"), "override reported after an edit")
	var bad: DotResult = scr.save_target.call(set, "zombie", {"health": 300, "speed": 9999.0})
	_check(not bad.ok and _code(bad) == DotError.CODE_INVALID, "an invalid value is refused")
	_check(api.handle(DotWorkbenchApi.TOKEN_ACTOR, _req("get")).value["values"]["health"] == 222, "a refused Apply leaves the earlier keys unchanged")
	_check(panel.save_to_server().ok and FileAccess.file_exists(BASE.path_join("server/game/mygame/npc/zombie.yml")), "save_to_server writes the server tier")
	_check(scr.reset_target.call(set, "zombie").ok and not scr.has_override.call(set, "zombie"), "reset drops the runtime layer")
	var plain := DotWorkbenchPanel.new(api, "nobody")
	var scr2 := FakeScreen.new()
	plain.attach(scr2)
	_check(_code(scr2.save_target.call(set, "zombie", {"health": 5})) == DotError.CODE_FORBIDDEN, "an actor without the cvar flag is refused")
	_check(_code(plain.save_to_server()) == DotError.CODE_FORBIDDEN, "an actor without root cannot save to the server")


func _test_add_delete() -> void:
	_section("profiles are added and deleted through the api and the panel")
	var api := _api()
	var a := DotWorkbenchApi.TOKEN_ACTOR
	var set: DotProfileSet = api._sets["npc"]
	var r := api.handle(a, _req("add", "npc", "wraith", "", {"health": 90}))
	_check(r.ok and api.handle(a, _req("list", "npc")).value["ids"].has("wraith"), "add through the api lists the new profile")
	_check(api.handle(a, _req("get", "npc", "wraith")).value["values"]["health"] == 90, "and it carries the start values")
	_check(_code(api.handle(a, _req("add", "npc", "wraith"))) == DotError.CODE_INVALID, "a taken id is refused")
	var envelope: Variant = JSON.parse_string(api.handle_json("s3cret", JSON.stringify({"op": "delete", "kind": "npc", "id": "wraith"})))
	_check(envelope != null and envelope.get("ok", false) and not set.has_id("wraith"), "delete through the json envelope removes it")
	_check(not api.handle(a, _req("list", "npc")).value["ids"].has("wraith"), "and it no longer lists")
	var scr := FakeScreen.new()
	var panel := DotWorkbenchPanel.new(api, a)
	panel.attach(scr)
	_check(panel.add_profile("npc", "golem", {"health": 500}).ok and set.has_id("golem"), "the panel adds a profile")
	_check(panel.delete_profile("npc", "golem").ok and not set.has_id("golem"), "the panel deletes it")
	_check(panel.delete_profile("npc", "ghoul").ok and not set.list_ids().has("ghoul"), "the panel deletes a shipped profile too")
	_check(_code(panel.delete_profile("npc", "ghoul")) == DotError.CODE_INVALID, "deleting it twice is refused")
	var plain := DotWorkbenchPanel.new(api, "nobody")
	_check(_code(plain.add_profile("npc", "x")) == DotError.CODE_FORBIDDEN and _code(plain.delete_profile("npc", "zombie")) == DotError.CODE_FORBIDDEN, "an actor without the cvar flag can do neither")
	_check(api.handle(a, _req("get", "npc", "zombie")).ok, "the others are untouched")


func _test_schema_field() -> void:
	_section("a schema field shows in the editor form with its range, unwired")
	_clean()
	_w("addons/dot-weapon/weapon/pistol.yml", "")
	var s := DotProfileSet.create("dot-weapon", "mygame", "weapon", [
		DotProfileSet.field("crosshair_scale", "float", 0.0, {"min": 0.0, "max": 4.0}),
	])
	s.roots = PackedStringArray([BASE])
	var api := DotWorkbenchApi.new()
	api.runtime.save_root = BASE
	api.add_set(s)
	api.set_admin_token("s3cret")
	var a := DotWorkbenchApi.TOKEN_ACTOR
	var form := DotUiForm.new()
	var built := form.build(s.schema, api.handle(a, _req("get", "weapon", "pistol")).value["values"])
	_check(built.ok, "the form builds from the set's schema alone")
	var row: DotFormRow = form.row("crosshair_scale")
	_check(row != null, "crosshair_scale has a row without any wiring")
	_check(row != null and is_equal_approx(float(row.field["min"]), 0.0) and is_equal_approx(float(row.field["max"]), 4.0), "the row carries the range 0 to 4")
	_check(row != null and row.field["slider"] == true and row._slider != null, "a ranged float gets a slider")
	_check(api.handle(a, _req("set", "weapon", "pistol", "crosshair_scale", 1.5)).ok, "an in-range value is accepted")
	_check(_code(api.handle(a, _req("set", "weapon", "pistol", "crosshair_scale", 5.0))) == DotError.CODE_INVALID, "a value above the range is refused")
	_check(form.set_value("crosshair_scale", 2.0).ok and not form.set_value("crosshair_scale", 9.0).ok, "the form refuses a value outside the range")
	form.free()
	_check(api.handle(a, _req("get", "weapon", "pistol")).value["values"]["crosshair_scale"] == 1.5, "the refused edit left the live value")


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


class FakeIdentity extends RefCounted:
	var uid := ""
	var is_guest := false
	var expires_at := 0
	var group_list: Array = []
	func is_expired() -> bool:
		return expires_at > 0 and expires_at <= int(Time.get_unix_time_from_system())
	func groups() -> Array:
		return group_list


func _fake(uid: String, guest := false, grp: Array = [], exp := 0) -> FakeIdentity:
	var f := FakeIdentity.new()
	f.uid = uid
	f.is_guest = guest
	f.group_list = grp
	f.expires_at = exp
	return f


func _test_identity() -> void:
	_section("identity wiring")
	var api := _api()
	api.permit = Callable()
	var table := {"t-admin": _fake("backbone:a"), "t-user": _fake("backbone:u"), "t-guest": _fake("guest:g", true),
		"t-group": _fake("backbone:m", false, ["workbench"]), "t-old": _fake("backbone:a", false, [], 1),
		"t-dict": {"uid": "backbone:a"}, "t-nouid": _fake("")}
	var gate := DotWorkbenchIdentity.new()
	gate.resolver = func(t: String) -> Variant: return table.get(t)
	_check(not gate.authenticate("t-admin") is String, "with no admins configured nobody is admitted (deny by default)")
	gate.admin_uids = PackedStringArray(["backbone:a"])
	gate.admin_groups = PackedStringArray(["workbench"])
	gate.attach(api)
	var ok := api.authenticate("t-admin")
	_check(ok.ok and ok.value == "id:backbone:a", "a listed admin is admitted with an id: actor")
	_check(api.handle(ok.value, _req("set", "npc", "zombie", "health", 12)).ok, "an admitted admin may edit")
	_check(api.handle(ok.value, _req("save")).ok, "an admitted admin holds root by default")
	_check(api.authenticate("t-group").ok, "a member of an admin group is admitted")
	_check(_code(api.authenticate("t-user")) == DotError.CODE_FORBIDDEN, "a signed-in non-admin is refused")
	_check(_code(api.authenticate("t-guest")) == DotError.CODE_FORBIDDEN, "a guest is refused")
	_check(_code(api.authenticate("t-old")) == DotError.CODE_FORBIDDEN, "an expired identity is refused")
	_check(_code(api.authenticate("t-nouid")) == DotError.CODE_FORBIDDEN, "an identity with no uid is refused")
	_check(_code(api.authenticate("nobody")) == DotError.CODE_FORBIDDEN and _code(api.authenticate("")) == DotError.CODE_FORBIDDEN, "an unknown or empty token (anonymous) is refused")
	_check(api.authenticate("t-dict").ok, "a Dictionary identity with a uid works")
	_check(not gate.permit("id:backbone:u", "cvar") and not gate.permit("stranger", "cvar"), "an actor the gate did not admit holds nothing")
	gate.fallback_permit = func(uid: String, flag: String) -> bool: return uid == "backbone:a" and flag == "cvar"
	_check(api.handle(ok.value, _req("set", "npc", "zombie", "health", 13)).ok and _code(api.handle(ok.value, _req("save"))) == DotError.CODE_FORBIDDEN, "a fallback permit decides the flags instead")


func _test_export() -> void:
	_section("export changes as defaults, and import")
	var api := _api()
	var a := DotWorkbenchApi.TOKEN_ACTOR
	var ex := DotWorkbenchExport.new(api)
	ex.root = OUT
	_check(ex.export_changes("t0").error.code == DotError.CODE_STATE, "nothing edited: no export")
	var _r1 := api.handle(a, _req("set", "npc", "zombie", "health", 400))
	var _r2 := api.handle(a, _req("set", "npc", "zombie", "speed", 2.5))
	var _r3 := api.handle(a, _req("set", "npc", "ghoul", "mode", "ranged"))
	var files := ex.collect()
	_check(files.size() == 2, "only profiles with a real difference are written (speed 2.5 equals the shipped value)")
	var zf: String = files.get("cfg/game/mygame/npc/zombie.yml", "")
	_check(zf == "health: 400\n", "the yml holds just the changed key, in the cfg layout")
	var _r4 := api.handle(a, _req("set", "npc", "zombie", "health", 50))
	_check(not ex.collect().has("cfg/game/mygame/npc/zombie.yml"), "an edit set back to the shipped value drops out")
	var _r5 := api.handle(a, _req("set", "npc", "zombie", "health", 400))
	var done := ex.export_changes("t1")
	_check(done.ok and FileAccess.file_exists(OUT.path_join("t1/cfg/game/mygame/npc/ghoul.yml")), "export writes the folder")
	_check(done.ok and FileAccess.file_exists(OUT.path_join("t1.zip")), "export writes the zip")
	var bundle: String = done.value["bundle"]
	_check(bundle.contains("# ---- file: cfg/game/mygame/npc/zombie.yml"), "the clipboard bundle names each file")
	# a fresh api (a second machine) takes the diff back
	var api2 := _api()
	var ex2 := DotWorkbenchExport.new(api2)
	var imp := ex2.import_source(a, bundle)
	_check(imp.ok and imp.value["applied"] == 2, "import of the bundle applies both keys")
	_check(api2.handle(a, _req("get", "npc", "zombie")).value["runtime"] == {"health": 400}, "import lands in the runtime layer")
	var api3 := _api()
	var imp2 := DotWorkbenchExport.new(api3).import_source(a, OUT.path_join("t1.zip"))
	_check(imp2.ok and imp2.value["applied"] == 2, "import of the zip works")
	var api4 := _api()
	var imp3 := DotWorkbenchExport.new(api4).import_source(a, OUT.path_join("t1"))
	_check(imp3.ok and imp3.value["applied"] == 2, "import of the folder works")
	var bad := DotWorkbenchExport.new(_api()).import_files(a, {"cfg/game/mygame/npc/zombie.yml": "health: 99999\n", "cfg/addons/other/npc/x.yml": "health: 1\n"})
	_check(bad.ok and bad.value["applied"] == 0 and bad.value["skipped"].size() == 2, "out-of-range values and foreign files are skipped, not applied")
	var api5 := _api()
	api5.permit = Callable()
	var denied := DotWorkbenchExport.new(api5).import_files("nobody", {"cfg/game/mygame/npc/zombie.yml": "health: 5\n"})
	_check(not denied.ok and denied.error.code == DotError.CODE_FORBIDDEN, "import needs the edit permission")
	ex.cvars_provider = func() -> Dictionary: return {"arena_scorelimit": 30}
	_check(ex.collect().get("game-cvars.yml", "") == "cvars:\n  arena_scorelimit: 30\n", "changed cvars come out as a game.yml block")
