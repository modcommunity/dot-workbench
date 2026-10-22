class_name DotWorkbenchIdentity
extends RefCounted

## Admin-only identity gate for [DotWorkbenchApi], duck-typed so dot-auth and dot-console stay optional.

const CHANNEL := "workbench"
const ACTOR_PREFIX := "id:"

## Callable(token) -> identity or null; the host backs it with dot-auth. An identity is an Object (DotAuthIdentity) or a Dictionary with `uid`.
var resolver: Callable = Callable()
## Uids allowed in. Deny by default: with no uid and no group listed, nobody is admitted.
var admin_uids := PackedStringArray()
## Groups (the identity's `groups`) allowed in.
var admin_groups := PackedStringArray()
## Flags an admitted identity holds when no [member fallback_permit] decides.
var flags := PackedStringArray(["cvar", "root"])
## Optional Callable(uid, flag) -> bool (dot-server's admin manager or console permissions); when valid it decides every flag instead of [member flags].
var fallback_permit: Callable = Callable()

var _admitted: Dictionary = {}


## Installs this gate on [param api]; the token still works if the host set one.
func attach(api: DotWorkbenchApi) -> void:
	api.identity = authenticate
	api.permit = permit
	api.runtime.actor_name = func(actor: Variant) -> String: return str(actor)


## The api's identity hook: an actor string for an admitted identity, null otherwise (the token path still gets its turn).
func authenticate(token: String) -> Variant:
	if token.is_empty() or not resolver.is_valid():
		return null
	var who: Variant = resolver.call(token)
	if who == null:
		return null
	var uid := _uid_of(who)
	if uid.is_empty() or _is_guest(who) or _is_expired(who):
		DotLog.warn(CHANNEL, "workbench identity refused", {"why": "anonymous, guest or expired"})
		return null
	if not (admin_uids.has(uid) or _in_admin_group(who)):
		DotLog.warn(CHANNEL, "workbench identity refused", {"uid": uid, "why": "not an admin"})
		return null
	var actor := ACTOR_PREFIX + uid
	_admitted[actor] = true
	DotLog.info(CHANNEL, "workbench identity admitted", {"uid": uid})
	return actor


## The api's permit hook; only actors this gate admitted get anything.
func permit(actor: Variant, flag: String) -> bool:
	if not (actor is String) or not _admitted.has(actor):
		return false
	if fallback_permit.is_valid():
		return bool(fallback_permit.call((actor as String).substr(ACTOR_PREFIX.length()), flag))
	return flags.has(flag)


static func _uid_of(who: Variant) -> String:
	if who is Dictionary:
		return str((who as Dictionary).get("uid", ""))
	if who is Object and "uid" in who:
		return str(who.get("uid"))
	return ""


static func _is_guest(who: Variant) -> bool:
	if who is Dictionary:
		return bool((who as Dictionary).get("is_guest", false))
	return who is Object and "is_guest" in who and bool(who.get("is_guest"))


static func _is_expired(who: Variant) -> bool:
	if who is Object and who.has_method("is_expired"):
		return bool(who.call("is_expired"))
	if who is Dictionary:
		var exp := int((who as Dictionary).get("expires_at", 0))
		return exp > 0 and int(Time.get_unix_time_from_system()) >= exp
	return false


func _in_admin_group(who: Variant) -> bool:
	var groups: Variant = null
	if who is Object and who.has_method("groups"):
		groups = who.call("groups")
	elif who is Dictionary:
		groups = (who as Dictionary).get("groups", [])
	if not (groups is Array or groups is PackedStringArray):
		return false
	for g in groups:
		if admin_groups.has(str(g)):
			return true
	return false
