extends Node

## DotWorkbenchPublish, offline: token file, query checks, file checks, and the POST it sends.
## godot --headless --path . res://examples/publish_selftest.tscn

const SECTIONS := 6
const CHECKS := 36
const TOKEN := "tmcc_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

var _entered := 0
var _completed := 0
var _passed := 0
var _failed := 0


class FakeHttp extends Node:
	var calls: Array = []
	var reply: DotResult = DotResult.success({"body_text": "{\"id\": 7, \"held\": true, \"url\": \"/avatars/wearables/7\"}"})

	func request(method: int, path: String, body: PackedByteArray = PackedByteArray(), headers: Dictionary = {}, _decode := true) -> DotResult:
		calls.append({"method": method, "path": path, "size": body.size(), "headers": headers})
		await get_tree().process_frame
		return reply


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	print("dot-workbench publish self-test")
	_test_token()
	_test_query()
	_test_file()
	await _test_site()
	await _test_publish()
	await _test_form()
	_check(_completed == _entered and _entered == SECTIONS, "every section ran (%d of %d)" % [_completed, SECTIONS])
	_check(_passed + _failed + 1 == CHECKS, "every check ran (%d of %d)" % [_passed + _failed + 1, CHECKS])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL %s" % what)


func _glb(size: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	b.encode_u32(0, 0x46546C67)
	return b


func _test_token() -> void:
	_entered += 1
	print("token file")
	var path := "user://publish_test.token"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("  %s\n" % TOKEN)
	f.close()
	var t := DotWorkbenchPublish.read_token(path)
	_check(t.ok and t.value == TOKEN, "a token file is read and trimmed")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("tmcc_short")
	f.close()
	_check(not DotWorkbenchPublish.read_token(path).ok, "a malformed token is refused")
	_check(not DotWorkbenchPublish.read_token("user://nope.token").ok, "a missing file fails")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_completed += 1


func _test_query() -> void:
	_entered += 1
	print("query")
	var q := DotWorkbenchPublish.build_query({"kind": "wearable", "name": "Top hat", "slot": "hat", "licence": "CC0-1.0"})
	_check(q.ok and q.value == "kind=wearable&name=Top%20hat&slot=hat&licence=CC0-1.0", "fields encode in a fixed order")
	_check(not DotWorkbenchPublish.build_query({"kind": "skin", "name": "x"}).ok, "an unknown kind is refused")
	_check(not DotWorkbenchPublish.build_query({"kind": "avatar"}).ok, "a name is required")
	_check(not DotWorkbenchPublish.build_query({"kind": "wearable", "name": "x", "slot": "tail", "licence": "MIT", "credit": "a"}).ok, "an unknown slot is refused")
	_check(not DotWorkbenchPublish.build_query({"kind": "wearable", "name": "x", "slot": "hat", "licence": "CC-BY-NC"}).ok, "a non-free licence is refused")
	_check(not DotWorkbenchPublish.build_query({"kind": "wearable", "name": "x", "slot": "hat", "licence": "MIT"}).ok, "credit is required for MIT")
	_check(not DotWorkbenchPublish.build_query({"kind": "avatar", "name": "x", "token": TOKEN}).ok, "an unknown field is refused")
	_check(not DotWorkbenchPublish.build_query({"kind": "avatar", "name": "x", "sharing": "APPROVAL"}).ok, "sharing is PRIVATE or PUBLIC")
	_check(DotWorkbenchPublish.build_query({"kind": "action", "name": "Wave", "actionKind": "GESTURE"}).ok, "an action needs no slot")
	_completed += 1


func _test_site() -> void:
	_entered += 1
	print("site")
	_check(DotWorkbenchPublish.check_site("https://site.test/").value == "https://site.test", "https is accepted, trailing slash dropped")
	_check(not DotWorkbenchPublish.check_site("http://site.test").ok, "plain http to a remote host is refused")
	_check(DotWorkbenchPublish.check_site("http://localhost:3002").ok and DotWorkbenchPublish.check_site("http://127.0.0.1").ok,
		"plain http to this machine is allowed")
	_check(not DotWorkbenchPublish.check_site("http://localhost.evil.test").ok and not DotWorkbenchPublish.check_site("http://127.0.0.1.evil.test:80").ok,
		"a host that only starts like localhost is refused")
	_check(not DotWorkbenchPublish.check_site("ftp://site.test").ok and not DotWorkbenchPublish.check_site("https://").ok, "other schemes and empty hosts are refused")
	var http := DotHttp.new()
	http.base_url = "http://site.test"
	add_child(http)
	var res := await DotWorkbenchPublish.new().publish(http, "tmcc_" + "a".repeat(43), _glb(100), {"kind": "wearable", "name": "Hat", "slot": "hat"})
	_check(not res.ok and res.error.code == DotError.CODE_INVALID, "publish refuses a client pointed at plain http")
	http.queue_free()
	_completed += 1


func _test_file() -> void:
	_entered += 1
	print("file")
	_check(DotWorkbenchPublish.check_file("wearable", _glb(1000)).ok, "a small glb passes")
	_check(not DotWorkbenchPublish.check_file("wearable", "not a model at all!!".to_utf8_buffer()).ok, "non-glTF is refused")
	_check(not DotWorkbenchPublish.check_file("wearable", _glb(4 * 1024 * 1024 + 1)).ok, "a wearable over 4 MB is refused")
	_check(DotWorkbenchPublish.check_file("avatar", _glb(4 * 1024 * 1024 + 1)).ok, "an avatar may be larger")
	_completed += 1


func _test_publish() -> void:
	_entered += 1
	print("publish")
	var http := FakeHttp.new()
	add_child(http)
	var pub := DotWorkbenchPublish.new()
	var params := {"kind": "wearable", "name": "Top hat", "slot": "hat", "licence": "CC0-1.0"}
	var res: DotResult = await pub.publish(http, TOKEN, _glb(500), params)
	_check(res.ok and res.value["id"] == 7 and res.value["held"] == true, "the site's reply comes back")
	var call: Dictionary = http.calls[0] if http.calls.size() > 0 else {}
	_check(call.get("method") == HTTPClient.METHOD_POST and String(call.get("path", "")).begins_with("/api/avatar/v1/publish?kind=wearable"), "one POST to the publish route")
	_check(call.get("headers", {}).get("Authorization") == "Bearer " + TOKEN and call.get("size") == 500, "bearer token and raw body")
	res = await pub.publish(http, "tmcc_bad", _glb(500), params)
	_check(not res.ok and http.calls.size() == 1, "a bad token sends nothing")
	http.reply = DotResult.failure(DotError.from_http(403, "{\"error\":\"no\"}"))
	res = await pub.publish(http, TOKEN, _glb(500), params)
	_check(not res.ok and res.error.http_status == 403, "a refusal keeps its status")
	http.reply = DotResult.success({"body_text": "<html>"})
	_check(not (await pub.publish(http, TOKEN, _glb(500), params)).ok, "a reply without an id fails")
	http.queue_free()
	_completed += 1


func _test_form() -> void:
	_entered += 1
	print("make wearable form")
	var dir := "user://wb_form_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var glb := FileAccess.open(dir + "/hat.glb", FileAccess.WRITE)
	glb.store_buffer(_glb(300))
	glb.close()
	var tok := FileAccess.open(dir + "/token", FileAccess.WRITE)
	tok.store_string(TOKEN + "\n")
	tok.close()
	var http := FakeHttp.new()
	add_child(http)
	var form := DotWorkbenchWearableForm.new()
	form.token_path = dir + "/token"
	form.http = http
	add_child(form)
	var statuses: Array = []
	form.status.connect(func(t: String, bad: bool) -> void: statuses.append([t, bad]))
	form.set_values(dir + "/hat.glb", "Top hat", "hat", "CC0-1.0")
	var res: DotResult = await form.submit()
	var call: Dictionary = http.calls[0] if http.calls.size() > 0 else {}
	_check(res.ok and String(call.get("path", "")).contains("slot=hat") and call.get("size") == 300, "the form posts the chosen file and slot")
	_check(statuses.size() == 1 and not statuses[0][1] and String(statuses[0][0]).contains("#7"), "success is reported with the id")
	form.set_values(dir + "/hat.glb", "Top hat", "hat", "MIT")
	res = await form.submit()
	_check(not res.ok and http.calls.size() == 1 and statuses[1][1], "a licence needing credit is refused before any upload")
	form.set_values(dir + "/missing.glb", "Top hat", "hat", "CC0-1.0")
	res = await form.submit()
	_check(not res.ok and http.calls.size() == 1, "a missing file sends nothing")
	form.set_values(dir + "/hat.glb", "Top hat", "face", "CC0-1.0")
	form.set_token_file(dir + "/none")
	res = await form.submit()
	_check(not res.ok and http.calls.size() == 1, "a missing token file sends nothing")
	var overlay_ok := true
	if ResourceLoader.exists(DotWorkbenchOverlay.EDITOR_SCRIPT):
		overlay_ok = DotWorkbenchOverlay.create(DotWorkbenchApi.new(), null) != null
	_check(overlay_ok, "the overlay builds with the form in it")
	form.queue_free()
	http.queue_free()
	_completed += 1
