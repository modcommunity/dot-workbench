class_name DotWorkbenchSetView
extends DotProfileSet

## A second heading over part of a registered set: the ids of [member inner], edited as [member base_kind].
## For a set that groups several sources under one kind (dot-weapon's weapon group, one member per pack): register the group
## (scoped `listed: false`) and one view per member, so the overlay lists each pack's profiles under its own heading.
## [DotWorkbenchApi] keeps a view out of the runtime and turns its kind back into [member base_kind] for every edit.

const SEP := "@"

## The kind the runtime knows (the group's `rel_path`).
var base_kind := ""
## The set that holds the profiles shown here (a group member).
var inner: DotProfileSet = null
## The registered set behind [member base_kind] (the group); its runtime layer is the one edited.
var base: DotProfileSet = null


## A view named `<base kind>@<part>` over [param p_inner], edited through [param p_base].
static func make(p_base: DotProfileSet, p_inner: DotProfileSet, part: String) -> DotWorkbenchSetView:
	var v := DotWorkbenchSetView.new()
	v.base = p_base
	v.inner = p_inner
	v.base_kind = p_base.rel_path
	v.rel_path = "%s%s%s" % [p_base.rel_path, SEP, part]
	v.addon_name = p_inner.addon_name
	v.game = p_inner.game
	v.schema = p_inner.schema
	v.strict = p_inner.strict
	v.runtime = p_base.runtime
	return v


## The kind a request should name: a view's base kind, else [param kind] itself.
static func base_of(kind: String) -> String:
	var at := kind.find(SEP)
	return kind.substr(0, at) if at > 0 else kind


func list_ids() -> PackedStringArray:
	return inner.list_ids()


func has_id(id: String) -> bool:
	return inner.has_id(id)


func load_profile(id: String) -> DotResult:
	return inner.load_profile(id)


func check_edit(id: String, path: String, value: Variant) -> DotResult:
	return inner.check_edit(id, path, value)


func clear_cache() -> void:
	inner.clear_cache()


func set_runtime(id: String, paths: Dictionary) -> void:
	base.set_runtime(id, paths)


func runtime_paths(id: String) -> Dictionary:
	return base.runtime_paths(id)


func describe() -> String:
	return "%s (view of %s)" % [rel_path, base_kind]
