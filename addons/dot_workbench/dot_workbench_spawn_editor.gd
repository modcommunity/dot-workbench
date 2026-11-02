class_name DotWorkbenchSpawnEditor
extends Node3D

## Point-and-click spawn authoring: aim, click to add, select, move, turn, edit, delete. Every edit goes through [DotWorkbenchApi] into the `spawn` profile of [member map_id] and is saved at once.
##
## Duck-typed to dot-spawn: points are plain Dictionaries in the override entry format (pos, yaw, team, enabled, weight, tags).

const KIND := "spawn"
const PICK_RADIUS := 1.2
const TEAM_COLORS := [Color(0.95, 0.95, 0.95), Color(0.9, 0.25, 0.25), Color(0.25, 0.45, 0.95), Color(0.3, 0.8, 0.35), Color(0.95, 0.8, 0.2)]

signal changed(id: String)
signal selected_changed(id: String)

var api: DotWorkbenchApi
var actor: Variant
var map_id := ""
## (from: Vector3, dir: Vector3) -> Dictionary {position, normal} or {}; the game supplies its physics ray.
var ray_fn: Callable
var camera: Camera3D
var selected := ""
## id -> entry, everything shown (map points merged with the saved overrides).
var points: Dictionary = {}

var _next := 1
var _gizmos: Dictionary = {}


## Loads [param shown], an Array of {id, pos, yaw, team, enabled, weight, tags} (the map's points with overrides applied).
func load_points(shown: Array) -> void:
	points.clear()
	for e: Variant in shown:
		var d: Dictionary = (e as Dictionary).duplicate(true)
		points[str(d["id"])] = d
		d.erase("id")
	_rebuild()


## Adds an authored point at [param pos]; returns its id, or "" when the write was refused.
func add_point(pos: Vector3, yaw := 0.0, team := "") -> String:
	var id := "auth_%d" % _next
	while points.has(id):
		_next += 1
		id = "auth_%d" % _next
	var entry := {"pos": _vec(pos), "yaw": yaw, "team": team, "enabled": true, "weight": 1.0, "tags": []}
	if not _write(id, entry).ok:
		return ""
	points[id] = entry
	select(id)
	_rebuild()
	return id


## Moves a point; true when stored.
func move_point(id: String, pos: Vector3) -> bool:
	return edit(id, "pos", _vec(pos))


## Sets one entry key (yaw, team, enabled, weight, tags, pos).
func edit(id: String, key: String, value: Variant) -> bool:
	if not points.has(id):
		return false
	var entry: Dictionary = (points[id] as Dictionary).duplicate(true)
	entry[key] = value
	if not _write(id, entry).ok:
		return false
	points[id] = entry
	_rebuild()
	return true


## Deletes a point: a map point is marked removed, so the override survives a map reload.
func delete_point(id: String) -> bool:
	if not points.has(id):
		return false
	if not _write(id, {"removed": true}).ok:
		return false
	points.erase(id)
	if selected == id:
		select("")
	_rebuild()
	return true


func select(id: String) -> void:
	if selected == id:
		return
	selected = id
	_rebuild()
	selected_changed.emit(id)


## The id of the point nearest the ray within [constant PICK_RADIUS], or "".
func pick(from: Vector3, dir: Vector3) -> String:
	var best := ""
	var best_d := PICK_RADIUS
	for id: String in points:
		var p := _pos(points[id])
		var d := _ray_distance(from, dir.normalized(), p + Vector3.UP * 0.9)
		if d < best_d:
			best_d = d
			best = id
	return best


## What a click at the aim does: select a point under it, else add one facing away from the camera.
func click(from: Vector3, dir: Vector3) -> String:
	var hit := pick(from, dir)
	if not hit.is_empty():
		select(hit)
		return hit
	if not ray_fn.is_valid():
		return ""
	var r: Dictionary = ray_fn.call(from, dir)
	if r.is_empty():
		return ""
	var flat := Vector3(dir.x, 0.0, dir.z)
	return add_point(r["position"], atan2(-flat.x, -flat.z) if flat.length() > 0.01 else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := (event as InputEventMouseButton).position
		click(camera.project_ray_origin(m), camera.project_ray_normal(m))
	elif event is InputEventKey and event.pressed and not selected.is_empty():
		_key((event as InputEventKey).keycode)


func _key(code: Key) -> void:
	var e: Dictionary = points[selected]
	match code:
		KEY_DELETE, KEY_X:
			delete_point(selected)
		KEY_Q:
			edit(selected, "yaw", float(e.get("yaw", 0.0)) + deg_to_rad(15.0))
		KEY_E:
			edit(selected, "yaw", float(e.get("yaw", 0.0)) - deg_to_rad(15.0))
		KEY_T:
			var teams := ["", "1", "2"]
			edit(selected, "team", teams[(teams.find(str(e.get("team", ""))) + 1) % teams.size()])
		KEY_V:
			edit(selected, "enabled", not bool(e.get("enabled", true)))
		KEY_BRACKETLEFT:
			edit(selected, "weight", maxf(float(e.get("weight", 1.0)) - 0.5, 0.0))
		KEY_BRACKETRIGHT:
			edit(selected, "weight", float(e.get("weight", 1.0)) + 0.5)
		KEY_M:
			if ray_fn.is_valid() and camera != null:
				var c := get_viewport().get_visible_rect().size / 2.0
				var r: Dictionary = ray_fn.call(camera.project_ray_origin(c), camera.project_ray_normal(c))
				if not r.is_empty():
					move_point(selected, r["position"])


func _write(id: String, entry: Dictionary) -> DotResult:
	if api == null:
		return DotResult.fail(DotError.CODE_INVALID, "no api")
	var listed := api.handle(actor, {"op": "list", "kind": KIND})
	if not listed.ok:
		return listed
	if not (listed.value["ids"] as Array).has(map_id):
		var made := api.handle(actor, {"op": "add", "kind": KIND, "id": map_id, "key": "", "value": {}})
		if not made.ok:
			return made
	var res := api.handle(actor, {"op": "set", "kind": KIND, "id": map_id, "key": "points.%s" % id, "value": entry})
	if not res.ok:
		return res
	var saved := api.handle(actor, {"op": "save", "kind": KIND, "id": map_id, "key": "", "value": null})
	if saved.ok:
		changed.emit(id)
	return saved


func _rebuild() -> void:
	for g: Node in _gizmos.values():
		remove_child(g)
		g.queue_free()
	_gizmos.clear()
	for id: String in points:
		var g := _gizmo(id, points[id])
		add_child(g)
		_gizmos[id] = g


func _gizmo(id: String, e: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = _pos(e)
	root.rotation.y = float(e.get("yaw", 0.0))
	var color := _color(e)
	var sel := id == selected
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.8
	body.mesh = cyl
	body.position.y = 0.9
	body.material_override = _mat(color, 0.35 if bool(e.get("enabled", true)) else 0.12)
	root.add_child(body)
	var arrow := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.18, 0.9)
	arrow.mesh = box
	arrow.position = Vector3(0, 1.0, -0.6)
	arrow.material_override = _mat(Color.YELLOW if sel else color, 1.0)
	root.add_child(arrow)
	if sel:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.7
		ring.mesh = torus
		ring.position.y = 0.05
		ring.material_override = _mat(Color.YELLOW, 1.0)
		root.add_child(ring)
	return root


func _color(e: Dictionary) -> Color:
	var t := str(e.get("team", ""))
	return TEAM_COLORS[0] if t.is_empty() else TEAM_COLORS[clampi(int(t), 1, TEAM_COLORS.size() - 1)]


func _mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _pos(e: Dictionary) -> Vector3:
	var p: Array = e.get("pos", [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func _ray_distance(from: Vector3, dir: Vector3, p: Vector3) -> float:
	var t := maxf((p - from).dot(dir), 0.0)
	return p.distance_to(from + dir * t)
