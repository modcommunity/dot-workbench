class_name DotWorkbenchWearableForm
extends VBoxContainer

## The workbench's "Make wearable" form: a GLB, a name, a slot and a licence, published to the site
## with a creator token read from a file. [DotWorkbenchPublish] does the checks and the upload.

signal status(text: String, bad: bool)

## Where the token is read from; never typed into the window, so it cannot be shoulder-surfed or logged.
var token_path := "user://creator_token"
## The site's base url; empty until the host or the user fills it.
var site_url := ""
## A [DotHttp]-shaped node for tests; null builds a real one per upload.
var http: Node = null

var _file: LineEdit
var _site: LineEdit
var _token: LineEdit
var _name: LineEdit
var _slot: OptionButton
var _licence: OptionButton
var _credit: LineEdit
var _go: Button
var _busy := false


func _init() -> void:
	_file = _row("GLB file", "path to a .glb, origin at the attachment point")
	_name = _row("Name", "")
	_slot = _options("Slot", DotWorkbenchPublish.SLOTS)
	_licence = _options("Licence", DotWorkbenchPublish.LICENCES)
	_credit = _row("Credit", "required unless CC0-1.0")
	_site = _row("Site", "https://...")
	_token = _row("Token file", "")
	_go = Button.new()
	_go.text = "Publish wearable"
	_go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_go.pressed.connect(func() -> void: var _r := await submit())
	add_child(_go)


func _enter_tree() -> void:
	_site.text = site_url
	_token.text = token_path


## The query parameters the form currently describes.
func params() -> Dictionary:
	return {"kind": "wearable", "name": _name.text.strip_edges(), "slot": _slot.get_item_text(_slot.selected), "licence": _licence.get_item_text(_licence.selected), "credit": _credit.text.strip_edges()}


func set_values(file: String, wearable_name: String, slot: String, licence: String, credit := "") -> void:
	_file.text = file
	_name.text = wearable_name
	_select(_slot, slot)
	_select(_licence, licence)
	_credit.text = credit


## Reads, checks and uploads. Succeeds with the site's reply; reports on [signal status] either way.
func submit() -> DotResult:
	if _busy:
		return DotResult.fail(DotError.CODE_STATE, "an upload is already running")
	_busy = true
	_go.disabled = true
	var res := await _submit()
	_busy = false
	_go.disabled = false
	if res.ok:
		status.emit("Published wearable #%s%s" % [res.value["id"], " (awaiting review)" if res.value.get("held") else ""], false)
	else:
		status.emit("%s %s" % [res.error.message, res.error.detail], true)
	return res


func _submit() -> DotResult:
	var path := _file.text.strip_edges()
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "no such file", path)
	var token := DotWorkbenchPublish.read_token(_token.text.strip_edges())
	if not token.ok:
		return token
	var bytes := FileAccess.get_file_as_bytes(path)
	var own := http == null
	var client: Node = http
	if own:
		var site := DotWorkbenchPublish.check_site(_site.text)
		if not site.ok:
			return site
		var real := DotHttp.new()
		real.base_url = site.value
		real.max_retries = 0
		real.timeout_sec = 120.0
		add_child(real)
		client = real
	var res: DotResult = await DotWorkbenchPublish.new().publish(client, token.value, bytes, params())
	if own:
		client.queue_free()
	return res


func set_token_file(path: String) -> void:
	_token.text = path


func _row(label: String, hint: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 90
	row.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	add_child(row)
	return e


func _options(label: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 90
	row.add_child(l)
	var o := OptionButton.new()
	for i in items:
		o.add_item(String(i))
	row.add_child(o)
	add_child(row)
	return o


func _select(o: OptionButton, text: String) -> void:
	for i in o.item_count:
		if o.get_item_text(i) == text:
			o.select(i)
