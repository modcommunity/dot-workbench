extends Node

## Exercises the trail form's server side ([DotWorkbenchTrails]) and its HTTP routes. Needs dot-trail linked into addons/.
##
## [codeblock]
## godot --headless --path . res://examples/trails_selftest.tscn
## [/codeblock]

const SECTIONS := 3
const CHECKS := 26
const BASE := "user://workbench_trails_selftest"

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_line("dot-workbench trails self-test")
	_test_ops()
	_test_http()
	_test_permission()
	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		_line("ERROR: %d sections, %d checks ran; expected %d and %d." % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _png(w: int) -> String:
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _meta(id: String) -> Dictionary:
	return {"id": id, "title": id, "licence": "CC0-1.0", "author": "Me", "url": "https://example.com", "access": "public"}


func _make() -> Array:
	DirAccess.remove_absolute(BASE.path_join("trails.json"))
	var api := DotWorkbenchApi.new()
	api.set_admin_token("s3cret")
	api.permit = func(actor: Variant, flag: String) -> bool: return actor == "owner" and flag == "trail"
	var store := DotTrailStore.new(null, BASE)
	return [api, store, DotWorkbenchTrails.new(api, store)]


func _test_ops() -> void:
	_section("ops")
	var m := _make()
	var t: DotWorkbenchTrails = m[2]
	var store: DotTrailStore = m[1]
	var calls := [0]
	t.changed = func() -> void: calls[0] += 1
	var up := t.handle("owner", {"op": "trail_upload", "meta": _meta("spark"), "image": _png(16), "file": "spark.png"})
	_check(up.ok and store.registry.count() == 1, "an owner uploads a trail")
	_check(FileAccess.file_exists(BASE.path_join("trails.json")) and FileAccess.file_exists(BASE.path_join("spark.png")), "the upload is saved to the store directory")
	_check(calls[0] == 1, "the changed hook fires once")
	var gold := _meta("gold")
	gold["access"] = "groups"
	gold["groups"] = ["donator"]
	_check(t.handle("owner", {"op": "trail_upload", "meta": gold, "image": _png(16)}).ok, "a group-restricted trail is accepted")
	_check(store.registry.get_def("gold").access == "groups", "the access setting is kept")
	var listed := t.handle("owner", {"op": "trail_list"})
	_check(listed.ok and listed.value["trails"].size() == 2, "list returns both")
	_check(t.handle("owner", {"op": "trail_upload", "meta": _meta("x"), "image": ""}).code() == "invalid", "an empty image is refused")
	var script := _meta("evil")
	_check(t.handle("owner", {"op": "trail_upload", "meta": script, "image": Marshalls.raw_to_base64("#!/bin/sh".to_utf8_buffer())}).code() == "invalid", "a script is refused")
	var bad := _meta("nolic")
	bad["licence"] = "CC-BY-NC-4.0"
	_check(t.handle("owner", {"op": "trail_upload", "meta": bad, "image": _png(16)}).code() == "invalid", "a non-commercial licence is refused")
	_check(t.handle("owner", {"op": "trail_upload", "meta": _meta("huge"), "image": _png(600)}).code() == "invalid", "an image over the dimension limit is refused")
	var fat := "A".repeat(400000)
	_check(t.handle("owner", {"op": "trail_upload", "meta": _meta("fat"), "image": fat}).code() == "quota", "an oversized body is refused before decoding")
	_check(store.registry.count() == 2, "refused uploads add nothing")
	_check(t.handle("owner", {"op": "trail_delete", "id": "gold"}).ok and store.registry.count() == 1, "delete removes it")
	var back := DotTrailStore.new(null, BASE)
	_check(back.load_dir().ok and back.registry.count() == 1 and back.registry.get_def("spark") != null, "the saved store reloads")
	_check(t.handle("owner", {"op": "trail_delete", "id": "nope"}).code() == "invalid", "deleting an unknown id is invalid")
	_check(t.handle("owner", {"op": "frobnicate"}).code() == "invalid", "an unknown op is invalid")


func _test_http() -> void:
	_section("HTTP routes")
	if not DotPlatform.can_listen():
		_line("  skipped: this platform cannot listen on a socket")
		for i in 6:
			_check(true, "skipped (no sockets)")
		return
	var m := _make()
	var h := DotWorkbenchHttp.new(m[0])
	h.mount_trails(m[2])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE))
	var f := FileAccess.open(BASE.path_join("t.token"), FileAccess.WRITE)
	f.store_string("s3cret")
	f.close()
	var started := h.start_from_config({"enabled": true, "port": 0, "token_file": BASE + "/t.token"})
	_check(started.ok, "the adapter starts")
	if not started.ok:
		for i in 5:
			_check(false, "adapter did not start")
		return
	_check(_http_call(h, "GET", "/api/trails", "")["status"] == 401, "no token is 401")
	var body := JSON.stringify({"meta": _meta("beam"), "image": _png(16), "file": "beam.png"})
	var up := _http_call(h, "POST", "/api/trails", "s3cret", body)
	_check(up["status"] == 200 and (m[1] as DotTrailStore).registry.count() == 1, "POST uploads a trail")
	_check(_http_call(h, "GET", "/api/trails")["json"]["value"]["trails"].size() == 1, "GET lists it")
	_check(_http_call(h, "POST", "/api/trails", "s3cret", "{nope")["status"] == 400, "a malformed body is 400")
	_check(_http_call(h, "DELETE", "/api/trails/beam")["status"] == 200 and (m[1] as DotTrailStore).registry.count() == 0, "DELETE removes it")
	h.stop()


func _test_permission() -> void:
	_section("permission")
	var m := _make()
	var t: DotWorkbenchTrails = m[2]
	var up := {"op": "trail_upload", "meta": _meta("a"), "image": _png(16)}
	_check(t.handle("stranger", up).code() == "forbidden", "an actor without the trail flag is refused")
	_check(t.handle("stranger", {"op": "trail_list"}).code() == "forbidden", "listing needs the flag too")
	_check(t.handle(DotWorkbenchApi.TOKEN_ACTOR, up).ok, "the admin token holds the trail flag")
	_check((m[1] as DotTrailStore).registry.count() == 1, "only the permitted upload landed")


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


func _section(name: String) -> void:
	_section_count += 1
	_line("")
	_line("== " + name)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		_line("  ok   " + label)
	else:
		_failed += 1
		_line("  FAIL " + label)


func _line(s: String) -> void:
	print(s)
