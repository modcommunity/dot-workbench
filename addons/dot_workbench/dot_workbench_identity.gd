class_name DotWorkbenchIdentity
extends DotAdminIdentity

## Admin-only identity gate for [DotWorkbenchApi]: [DotAdminIdentity] (GameSpice Core) with the `workbench` log channel, the `cvar` and `root` flags by default, and [method attach]. Duck-typed, so GameSpice Auth and GameSpice Console stay optional.

const CHANNEL := "workbench"


func _init() -> void:
	channel = CHANNEL
	flags = PackedStringArray(["cvar", "root"])


## Installs this gate on [param api]; the token still works if the host set one.
func attach(api: DotWorkbenchApi) -> void:
	api.identity = authenticate
	api.permit = permit
	api.runtime.actor_name = func(actor: Variant) -> String: return str(actor)
