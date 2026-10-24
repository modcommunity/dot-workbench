class_name DotWorkbenchOverlay
extends PanelContainer

## The in-game workbench window: a title bar (Save to server, Export changes as defaults, Import, Close)
## over dot-menu's profile editor, bound to a [DotWorkbenchApi] by [DotWorkbenchPanel].
##
## dot-ui and dot-menu are loaded by path, so a build without them gets [code]null[/code] from [method create].

const EDITOR_SCRIPT := "res://addons/dot_menu/ui/dot_profile_editor_screen.gd"
const TOKENS_SCRIPT := "res://addons/dot_ui/form/dot_form_tokens.gd"

signal closed

var api: DotWorkbenchApi
var panel: DotWorkbenchPanel
var exporter: DotWorkbenchExport
var editor: Control = null
var tokens: Object = null
var last_export: Dictionary = {}

var _status: Label
var _import_box: TextEdit
var _import_row: Control
var wearable_form: DotWorkbenchWearableForm


## Builds the window, or null when dot-menu or dot-ui is not linked. [param labels] is {kind: heading}.
static func create(p_api: DotWorkbenchApi, actor: Variant, labels: Dictionary = {}) -> DotWorkbenchOverlay:
	if not ResourceLoader.exists(EDITOR_SCRIPT) or not ResourceLoader.exists(TOKENS_SCRIPT):
		return null
	var o := DotWorkbenchOverlay.new()
	o.api = p_api
	o.exporter = DotWorkbenchExport.new(p_api)
	o.panel = DotWorkbenchPanel.new(p_api, actor)
	var tk_script: GDScript = load(TOKENS_SCRIPT)
	o.tokens = tk_script.call("dark")
	o.tokens.set("animate", false)
	var ed_script: GDScript = load(EDITOR_SCRIPT)
	o.editor = ed_script.new()
	o.editor.set("tokens", o.tokens)
	o.editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	o.panel.status.connect(o._say)
	o._build(labels)
	return o


func _build(labels: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = tokens.call("build_theme")
	var bg: StyleBox = tokens.call("box", tokens.get("bg"), 0)
	add_theme_stylebox_override("panel", bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.add_child(_bar())
	_import_row = _build_import()
	_import_row.visible = false
	col.add_child(_import_row)
	wearable_form = DotWorkbenchWearableForm.new()
	wearable_form.visible = false
	wearable_form.status.connect(_say)
	col.add_child(wearable_form)
	col.add_child(editor)
	for kind in api.kinds():
		var set := api.get_set(kind)
		editor.call("add_set", set, String(labels.get(kind, kind.capitalize())))
	panel.attach(editor)


func _bar() -> Control:
	var wrap := PanelContainer.new()
	var sb: StyleBoxFlat = tokens.call("box", tokens.get("card"), 0, tokens.get("border"), 1, 1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	wrap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)
	var title := Label.new()
	title.text = "Workbench"
	title.add_theme_font_size_override("font_size", 20)
	row.add_child(title)
	var sub := Label.new()
	sub.text = "live tuning  -  F9 closes"
	sub.add_theme_color_override("font_color", tokens.get("text_faint"))
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sub)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	row.add_child(_status)
	row.add_child(_button("Save to server", _on_save, "Writes the open profile's edits to cfg/server"))
	row.add_child(_button("Export changes as defaults", _on_export, "Writes only what differs from the shipped defaults, in cfg/ layout"))
	row.add_child(_button("Import", _on_import_toggle, "Apply a received export"))
	row.add_child(_button("Make wearable", _on_wearable_toggle, "Publish a GLB as a wearable with a creator token"))
	row.add_child(_button("Close", close, ""))
	return wrap


func _build_import() -> Control:
	var box := VBoxContainer.new()
	var hint := Label.new()
	hint.text = "Paste an export bundle, or the path of an export folder or .zip, then Apply."
	hint.add_theme_color_override("font_color", tokens.get("text_faint"))
	box.add_child(hint)
	_import_box = TextEdit.new()
	_import_box.custom_minimum_size.y = 90
	box.add_child(_import_box)
	var go := _button("Apply import", _on_import_apply, "")
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(go)
	return box


func _button(text: String, cb: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _say(text: String, bad: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", tokens.get("danger") if bad else tokens.get("good"))


func _on_save() -> void:
	var _r := panel.save_to_server()


func _on_export() -> void:
	var res := exporter.export_changes()
	if not res.ok:
		_say(res.error.message, true)
		return
	last_export = res.value
	DisplayServer.clipboard_set(res.value["bundle"])
	var shown := ProjectSettings.globalize_path(res.value["dir"])
	_say("Exported %d files to %s (zip beside it, text on the clipboard)" % [res.value["files"].size() - 1, shown], false)


func _on_wearable_toggle() -> void:
	wearable_form.visible = not wearable_form.visible


func _on_import_toggle() -> void:
	_import_row.visible = not _import_row.visible


func _on_import_apply() -> void:
	var res := exporter.import_source(panel.actor, _import_box.text)
	if not res.ok:
		_say(res.error.message, true)
		return
	var skipped: Array = res.value["skipped"]
	_say("Imported %d values live%s" % [res.value["applied"], ", %d skipped" % skipped.size() if not skipped.is_empty() else ""], not skipped.is_empty())
	editor.call("open", editor.call("current_kind"), editor.call("current_id")) if not str(editor.call("current_kind")).is_empty() else null
