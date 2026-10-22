extends SceneTree

## Renders the in-game panel (DotProfileEditorScreen bound by DotWorkbenchPanel) to docs/.
## Needs dot-ui, dot-menu and dot-settings linked into addons/ (dev only).
##
##   xvfb-run -a godot --path . --resolution 1280x800 --script tools/panel_shot.gd

const BASE := "user://workbench_panel_shot"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BASE.path_join("addons/dot-npc/npc"))
	for n in ["zombie", "ghoul"]:
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
	s.override_prefix = "wbs"
	var api := DotWorkbenchApi.new()
	api.runtime.save_root = BASE
	api.add_set(s)
	root.get_window().size = Vector2i(1280, 800)
	await _frames(3)
	var tokens := DotFormTokens.dark()
	tokens.animate = false
	var ed := DotProfileEditorScreen.new()
	ed.tokens = tokens
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ed)
	ed.add_set(s, "NPCs")
	var panel := DotWorkbenchPanel.new(api, "admin")
	api.permit = func(actor: Variant, _f: String) -> bool: return actor == "admin"
	panel.attach(ed)
	await _frames(3)
	var _o := ed.open("npc", "zombie")
	await _frames(2)
	var _a := ed.form.set_value("health", 420)
	var _b := ed.apply()
	await _frames(1)
	var _c := ed.form.set_value("speed", 4.5)
	await _frames(4)
	print("rev ", api.runtime.revision("npc", "zombie"), " override ", s.runtime_paths("zombie"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/workbench-ingame-dark.png"))
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
