extends SceneTree

## Renders the redesigned workbench overlay (main state, import and wearable drawers) to docs/. Dev only.
## Run: xvfb-run -a godot --path . --resolution 1280x800 --script tools/menu_shot.gd

const BASE := "user://workbench_menu_shot"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BASE.path_join("addons/dot-npc/npc"))
	for n in ["zombie", "ghoul", "skeleton"]:
		var f := FileAccess.open(BASE.path_join("addons/dot-npc/npc/%s.yml" % n), FileAccess.WRITE)
		f.store_string("health: 50\nspeed: 2.5\n")
		f.close()
	var s := DotProfileSet.create("dot-npc", "mygame", "npc", [
		DotProfileSet.field("health", "int", 100, {"min": 1, "max": 1000}),
		DotProfileSet.field("speed", "float", 3.0, {"min": 0.0, "max": 50.0}),
		DotProfileSet.field("mode", "string", "melee", {"enum": ["melee", "ranged"]}),
		DotProfileSet.field("aggressive", "bool", true),
	])
	s.roots = PackedStringArray([BASE])
	s.override_prefix = "wbm"
	var api := DotWorkbenchApi.new()
	api.runtime.save_root = BASE
	api.add_set(s)
	root.get_window().size = Vector2i(1280, 800)
	await _frames(3)
	api.permit = func(actor: Variant, _f: String) -> bool: return actor == "admin"
	var ov := DotWorkbenchOverlay.create(api, "admin", {"npc": "NPCs"}, false)
	root.add_child(ov)
	var ed: DotProfileEditorScreen = ov.editor
	await _frames(3)
	var _o := ed.open("npc", "zombie")
	await _frames(2)
	var _a := ed.form.set_value("health", 420)
	var _b := ed.apply()
	await _frames(3)
	ov.panel.save_to_server()
	await _frames(4)
	_shot("workbench-menu-main")
	ov._on_import_toggle()
	await _frames(4)
	_shot("workbench-menu-import")
	ov._on_import_toggle()
	ov._on_wearable_toggle()
	await _frames(4)
	_shot("workbench-menu-wearable")
	quit(0)


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://docs/")
	root.get_texture().get_image().save_png(dir + name + ".png")


func _frames(n: int) -> void:
	for i in n:
		await process_frame
