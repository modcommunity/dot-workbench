class_name DotWorkbenchExport
extends RefCounted

## "Export changes as defaults" and "Import": the tuning round trip.
##
## Export writes only the values whose live edit differs from the shipped value, one yml per profile in
## the repo's own cfg/ layout (`cfg/game/<game>/<kind>/<id>.yml`, or `cfg/addons/<addon>/...` for an addon
## set), so the folder can be copied over a repository's cfg/ as new defaults. The same files come as a
## zip and as one text bundle for the clipboard. Import takes any of the three back and applies it
## through the api, so it is validated and permission-checked like any other edit.

const CHANNEL := "workbench"
const ROOT := "user://workbench-export"
const BUNDLE_MARK := "# ---- file: "
const README_NAME := "README.txt"

var api: DotWorkbenchApi
## Optional Callable() -> {cvar name: value} of cvars changed from their shipped default, written to
## `game-cvars.yml` for pasting into the game's `game.yml` `cvars:` block.
var cvars_provider: Callable = Callable()
## Where exports go; tests point it elsewhere.
var root := ROOT


func _init(p_api: DotWorkbenchApi) -> void:
	api = p_api


## The diff as {relative file path: yml text}; empty when nothing differs.
func collect() -> Dictionary:
	var files := {}
	for kind in api.kinds():
		var set: DotProfileSet = api.get_set(kind)
		for id in set.runtime.keys():
			var tree := {}
			var paths: Dictionary = set.runtime_paths(id)
			for path in paths:
				var base := api.baseline_value(kind, id, path)
				if base["found"] and _same(base["value"], paths[path]):
					continue
				_put(tree, String(path).split("."), paths[path])
			if tree.is_empty():
				continue
			var text: Variant = _emit(tree, 0)
			if text == null:
				DotLog.warn(CHANNEL, "export skipped a profile with an unwritable value", {"kind": kind, "id": id})
				continue
			files[_file_for(set, id)] = text
	if cvars_provider.is_valid():
		var cv: Variant = cvars_provider.call()
		if cv is Dictionary and not (cv as Dictionary).is_empty():
			var tree := {"cvars": cv}
			var text: Variant = _emit(tree, 0)
			if text != null:
				files["game-cvars.yml"] = text
	return files


## Writes the diff under `<root>/<timestamp>/` plus a zip beside it. Value: {dir, zip, files: [...], bundle}.
func export_changes(stamp: String = "") -> DotResult:
	var files := collect()
	if files.is_empty():
		return DotResult.fail(DotError.CODE_STATE, "no changes differ from the shipped defaults")
	if stamp.is_empty():
		stamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dir := root.path_join(stamp)
	files[README_NAME] = _readme(files.keys())
	for rel in files:
		var wrote := DotPaths.write_text(dir.path_join(rel), files[rel])
		if not wrote.ok:
			return wrote.wrap("exporting %s" % rel)
	var zip_path := dir + ".zip"
	var zipper := ZIPPacker.new()
	if zipper.open(zip_path) != OK:
		return DotResult.fail(DotError.CODE_IO, "cannot write %s" % zip_path)
	for rel in files:
		var _s := zipper.start_file(rel)
		var _w := zipper.write_file((files[rel] as String).to_utf8_buffer())
		var _c := zipper.close_file()
	var _z := zipper.close()
	DotWeb.sync_filesystem()
	DotLog.info(CHANNEL, "workbench changes exported", {"dir": dir, "files": files.size()})
	var names: Array = files.keys()
	names.sort()
	return DotResult.success({"dir": dir, "zip": zip_path, "files": names, "bundle": bundle(files)})


## One text for the clipboard: every file behind a `# ---- file: <path>` line.
static func bundle(files: Dictionary) -> String:
	var out := ""
	var names: Array = files.keys()
	names.sort()
	for rel in names:
		if rel == README_NAME:
			continue
		out += "%s%s\n%s" % [BUNDLE_MARK, rel, files[rel]]
		if not (files[rel] as String).ends_with("\n"):
			out += "\n"
	return out


## {relative path: text} from a bundle (see [method bundle]); a text with no marker is one file named "pasted.yml".
static func parse_bundle(text: String) -> Dictionary:
	var files := {}
	var name := ""
	var buf := ""
	for line in text.split("\n"):
		if line.begins_with(BUNDLE_MARK):
			if not name.is_empty():
				files[name] = buf
			name = line.substr(BUNDLE_MARK.length()).strip_edges()
			buf = ""
		else:
			buf += line + "\n"
	if name.is_empty():
		name = "pasted.yml"
	if not buf.strip_edges().is_empty():
		files[name] = buf
	return files


## {relative path: text} read from an export folder or zip; unreadable pieces are skipped.
static func read_package(path: String) -> DotResult:
	var files := {}
	if path.to_lower().ends_with(".zip"):
		var reader := ZIPReader.new()
		if reader.open(path) != OK:
			return DotResult.fail(DotError.CODE_IO, "cannot open %s" % path)
		for rel in reader.get_files():
			if not rel.ends_with("/"):
				files[rel] = reader.read_file(rel).get_string_from_utf8()
		reader.close()
		return DotResult.success(files)
	for rel in DotPaths.list_files_recursive(path):
		if not rel.ends_with(".yml") and not rel.ends_with(".txt"):
			continue
		var text := DotPaths.read_text(path.path_join(rel))
		if text.ok:
			files[rel] = text.value
	return DotResult.success(files)


## Applies files (as from [method read_package] or [method parse_bundle]) to the api as [param actor].
## Value: {applied: n, skipped: [reasons]}. A file for a profile this game does not have is skipped, not an error.
func import_files(actor: Variant, files: Dictionary) -> DotResult:
	var applied := 0
	var skipped: Array = []
	var names: Array = files.keys()
	names.sort()
	for rel in names:
		if rel == README_NAME or not String(rel).ends_with(".yml") or String(rel) == "game-cvars.yml":
			if String(rel) == "game-cvars.yml":
				skipped.append("game-cvars.yml: cvars are edited in the console, not imported here")
			continue
		var target := _target_of(String(rel))
		if target.is_empty():
			skipped.append("%s: not a profile file under cfg/game or cfg/addons" % rel)
			continue
		var parsed := DotYaml.parse(files[rel], String(rel))
		if not parsed.ok:
			return parsed.wrap("importing %s" % rel)
		var leaves := {}
		_flatten(parsed.value if parsed.value is Dictionary else {}, "", leaves)
		leaves.erase(DotProfileSet.EXTENDS_KEY)
		for path in leaves:
			var res := api.handle(actor, {"op": "set", "kind": target["kind"], "id": target["id"], "key": path, "value": leaves[path]})
			if not res.ok:
				if res.error.code == DotError.CODE_FORBIDDEN:
					return res
				skipped.append("%s: %s: %s" % [rel, path, res.error.message])
			else:
				applied += 1
	DotLog.info(CHANNEL, "workbench defaults imported", {"applied": applied, "skipped": skipped.size()})
	return DotResult.success({"applied": applied, "skipped": skipped})


## Imports an export folder, zip or pasted bundle text, whichever [param source] is.
func import_source(actor: Variant, source: String) -> DotResult:
	var files: Dictionary
	var s := source.strip_edges()
	if s.contains("\n") or s.begins_with("#"):
		files = parse_bundle(s)
	else:
		var read := read_package(s)
		if not read.ok:
			return read
		files = read.value
	if files.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "nothing to import")
	return import_files(actor, files)


func _file_for(set: DotProfileSet, id: String) -> String:
	var tier := "cfg/game/%s" % set.game if set.game != "" else "cfg/addons/%s" % set.addon_name
	return "%s/%s/%s.%s" % [tier, set.rel_path, id, DotProfileSet.EXTENSION]


## {kind, id} for a file path, matched against the registered sets; empty when none fits.
func _target_of(rel: String) -> Dictionary:
	var parts := rel.trim_suffix(".yml").split("/")
	if parts.size() < 4 or parts[0] != "cfg" or (parts[1] != "game" and parts[1] != "addons"):
		return {}
	var owner := parts[2]
	var id := parts[parts.size() - 1]
	var kind := "/".join(parts.slice(3, parts.size() - 1))
	var set: DotProfileSet = api.get_set(kind)
	if set == null:
		return {}
	var own := set.game if parts[1] == "game" else set.addon_name
	if own != owner:
		return {}
	return {"kind": kind, "id": id}


static func _flatten(tree: Dictionary, prefix: String, out: Dictionary) -> void:
	for k in tree:
		var path := String(k) if prefix.is_empty() else prefix + "." + String(k)
		if tree[k] is Dictionary and not (tree[k] as Dictionary).is_empty():
			_flatten(tree[k], path, out)
		else:
			out[path] = tree[k]


static func _put(tree: Dictionary, parts: PackedStringArray, value: Variant) -> void:
	var node := tree
	for i in parts.size() - 1:
		if not (node.get(parts[i]) is Dictionary):
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = value


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


static func _emit(tree: Dictionary, depth: int) -> Variant:
	var out := ""
	var pad := "  ".repeat(depth)
	for k in tree:
		var v: Variant = tree[k]
		if v is Dictionary:
			var inner: Variant = _emit(v, depth + 1)
			if inner == null:
				return null
			out += "%s%s:\n%s" % [pad, k, inner]
			continue
		var s: Variant = _scalar(v)
		if s == null:
			return null
		out += "%s%s: %s\n" % [pad, k, s]
	return out


static func _scalar(v: Variant) -> Variant:
	if v is Array:
		var parts := PackedStringArray()
		for e in v:
			var one: Variant = _scalar(e)
			if e is Array or e is Dictionary or one == null:
				return null
			parts.append(one)
		return "[" + ", ".join(parts) + "]"
	if v is bool or v is int:
		return str(v)
	if v is float:
		var t := str(v)
		return t if t.contains(".") or t.contains("e") else t + ".0"
	if v is String or v is StringName:
		return "\"" + String(v).replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
	return null


static func _readme(names: Array) -> String:
	var out := "dot-workbench export: only values that differ from the shipped defaults.\n\n"
	out += "Send this folder (or the zip) back. To adopt it as new defaults, copy the cfg/ folder over the\nrepository's cfg/ and commit it.\n\nFiles:\n"
	var sorted := names.duplicate()
	sorted.sort()
	for n in sorted:
		out += "  %s\n" % n
	out += "\ngame-cvars.yml, when present, goes into the cvars: block of game.yml.\n"
	return out
