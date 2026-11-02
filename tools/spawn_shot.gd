extends SceneTree

## Renders the spawn authoring gizmos over a floor to docs/spawn-editor.png (dev only).
## Run: xvfb-run -a godot --path . --resolution 1280x800 --script tools/spawn_shot.gd

const BASE := "user://workbench_spawn_shot"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var s := DotProfileSet.create("dot_spawn", "demo", "spawn", [DotProfileSet.field("points", "dict", {})])
	s.roots = PackedStringArray([BASE])
	var api := DotWorkbenchApi.new()
	api.runtime.save_root = BASE
	api.add_set(s)
	var world := Node3D.new()
	root.add_child(world)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 28, 26)
	cam.look_at(Vector3(0, 0, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 30, 0)
	world.add_child(light)
	var ed := DotWorkbenchSpawnEditor.new()
	world.add_child(ed)
	ed.api = api
	ed.actor = DotWorkbenchApi.TOKEN_ACTOR
	ed.map_id = "demo_map"
	ed.camera = cam
	ed.load_points([])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var id := ed.add_point(Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24)), rng.randf() * TAU, ["", "1", "2"][i % 3])
		if i == 5:
			ed.edit(id, "enabled", false)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/spawn-editor.png"))
	quit(0)
