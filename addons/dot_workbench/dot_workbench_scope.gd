class_name DotWorkbenchScope
extends RefCounted

## Who a profile set belongs to and where it lives, so the overlay lists only what is loaded and says which side each section edits.
## The scope rides on the set as metadata, so a host that only passes `(set, label)` keeps working; an untagged set is always shown.
## Use: [code]DotWorkbenchScope.tag(set, {"owner": "my-game", "side": DotWorkbenchScope.SIDE_SERVER, "requires": func(): return mode_on})[/code].

const META := &"dot_workbench_scope"
## Lives on the server only; a client edits it through the server.
const SIDE_SERVER := "server"
## Server-owned and sent to every client (clients predict with it).
const SIDE_REPLICATED := "replicated"
## Lives on this machine only.
const SIDE_CLIENT := "client"
const SIDE_LABELS := {
	SIDE_SERVER: "server",
	SIDE_REPLICATED: "server, replicated",
	SIDE_CLIENT: "client only",
}


## Tags [param set] with [param info], merged over any earlier tag: `owner` (the game, mode or addon it belongs to), `side`
## (a SIDE_ constant), `requires` (Callable() -> bool; false hides the section, e.g. a mode that is off) and `listed` (false
## keeps it off the overlay but editable through the api, e.g. a group shown through per-pack views). Returns the set.
static func tag(set: Object, info: Dictionary) -> Object:
	var had := of(set)
	had.merge(info, true)
	set.set_meta(META, had)
	return set


## The tag of [param set]; empty when untagged.
static func of(set: Object) -> Dictionary:
	if set == null or not set.has_meta(META):
		return {}
	return (set.get_meta(META) as Dictionary).duplicate()


## The owner of [param set]: its tag, else its game, else its addon.
static func owner_of(set: Object) -> String:
	var s := of(set)
	if str(s.get("owner", "")) != "":
		return str(s["owner"])
	var game: Variant = set.get("game")
	if game is String and game != "":
		return game
	var addon: Variant = set.get("addon_name")
	return addon if addon is String else ""


## True when [param set] should be on the overlay now: listed, and its `requires` (if any) holds.
static func active(set: Object) -> bool:
	if set == null:
		return false
	var s := of(set)
	if not bool(s.get("listed", true)):
		return false
	var req: Variant = s.get("requires")
	if req is Callable and (req as Callable).is_valid():
		return bool((req as Callable).call())
	return true


## [param label] with the set's side appended (`Weapons  ·  server`); unchanged for an untagged set.
static func heading(set: Object, label: String) -> String:
	var side := str(of(set).get("side", ""))
	if not SIDE_LABELS.has(side):
		return label
	return "%s  ·  %s" % [label, SIDE_LABELS[side]]


## The sections an overlay over [param api] lists now: [kind, heading] for every active set, in the order added;
## [param labels] is {kind: label}, a kind without one is capitalised.
static func sections(api: DotWorkbenchApi, labels: Dictionary = {}) -> Array:
	var out: Array = []
	for kind: String in api.all_kinds():
		var set := api.get_set(kind)
		if active(set):
			out.append([kind, heading(set, String(labels.get(kind, kind.capitalize())))])
	return out


## The owners of [param listed] ([method sections]' pairs), in order, once each: what is loaded.
static func owners(api: DotWorkbenchApi, listed: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for pair: Array in listed:
		var who := owner_of(api.get_set(pair[0]))
		if who != "" and not out.has(who):
			out.append(who)
	return out
