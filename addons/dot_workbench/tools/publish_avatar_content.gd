extends SceneTree

## Publishes one GLB to the site with a creator token (made on the site's Avatars > Wearables tab).
## godot --headless --path . --script res://addons/dot_workbench/tools/publish_avatar_content.gd -- \
##     --site https://example.org --token-file ~/.config/tmc/creator.token --file hat.glb \
##     kind=wearable name="Top hat" slot=hat licence=CC0-1.0
## Prints the site's reply as JSON; exits 1 on failure. The token is read from a file only.


func _init() -> void:
	_main.call_deferred()


func _main() -> void:
	var args := OS.get_cmdline_user_args()
	var site := ""
	var token_file := ""
	var file := ""
	var params := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a in ["--help", "-h"]:
			print(_usage())
			quit(0)
			return
		if a in ["--site", "--token-file", "--file"] and i + 1 < args.size():
			match a:
				"--site": site = args[i + 1]
				"--token-file": token_file = args[i + 1].replace("~", OS.get_environment("HOME"))
				"--file": file = args[i + 1]
			i += 2
			continue
		if a.contains("="):
			params[a.get_slice("=", 0)] = a.substr(a.find("=") + 1)
		else:
			printerr("unexpected argument: %s" % a)
			quit(2)
			return
		i += 1
	if site == "" or token_file == "" or file == "":
		printerr(_usage())
		quit(2)
		return

	var token := DotWorkbenchPublish.read_token(token_file)
	if not token.ok:
		_fail(token)
		return
	if not FileAccess.file_exists(file):
		printerr("no such file: %s" % file)
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(file)
	var http := DotHttp.new()
	http.base_url = site.trim_suffix("/")
	http.max_retries = 0
	http.timeout_sec = 120.0
	root.add_child(http)
	var res := await DotWorkbenchPublish.new().publish(http, token.value, bytes, params)
	http.queue_free()
	if not res.ok:
		_fail(res)
		return
	print(JSON.stringify(res.value))
	quit(0)


func _fail(res: DotResult) -> void:
	printerr("publish failed: %s %s" % [res.error.message, res.error.detail])
	quit(1)


func _usage() -> String:
	return "usage: -- --site URL --token-file PATH --file MODEL.glb kind=wearable|action|avatar name=NAME [slot= bone= licence= credit= source= sharing=PRIVATE|PUBLIC description= id= actionKind= loop=1]"
