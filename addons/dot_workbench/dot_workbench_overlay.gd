class_name DotWorkbenchOverlay
extends PanelContainer

## The in-game workbench window: a title bar over dot-menu's profile editor, bound to a [DotWorkbenchApi].
## dot-ui and dot-menu are loaded by path, so a build without them gets null from [method create].

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
var _status_pill: PanelContainer
var _wearable_card: Control


## Builds the window, or null when dot-menu or dot-ui is not linked. [param labels] is {kind: heading}; [param animate] false makes every transition instant (tests, screenshots).
static func create(p_api: DotWorkbenchApi, actor: Variant, labels: Dictionary = {}, animate := true) -> DotWorkbenchOverlay:
	if not ResourceLoader.exists(EDITOR_SCRIPT) or not ResourceLoader.exists(TOKENS_SCRIPT):
		return null
	var o := DotWorkbenchOverlay.new()
	o.api = p_api
	o.exporter = DotWorkbenchExport.new(p_api)
	o.panel = DotWorkbenchPanel.new(p_api, actor)
	var tk_script: GDScript = load(TOKENS_SCRIPT)
	o.tokens = DotWorkbenchStyle.apply(tk_script.call("dark"))
	o.tokens.set("animate", animate)
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
	_extra_theme()
	add_theme_stylebox_override("panel", tokens.call("box", tokens.get("bg"), 0))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	col.add_child(_bar())
	_import_row = _build_import()
	_import_row.visible = false
	col.add_child(_import_row)
	wearable_form = DotWorkbenchWearableForm.new()
	wearable_form.status.connect(_say)
	_wearable_card = _card_around(wearable_form)
	_wearable_card.visible = false
	col.add_child(_wearable_card)
	col.add_child(editor)
	for kind in api.kinds():
		var set := api.get_set(kind)
		editor.call("add_set", set, String(labels.get(kind, kind.capitalize())))
	panel.attach(editor)


## Theme bits the stock form kit lacks: a text edit, tooltips and the header looks.
func _extra_theme() -> void:
	var t := tokens
	var acc: Color = t.get("accent")
	theme.set_stylebox("normal", "TextEdit", t.call("_pad", t.call("box", t.get("field"), 10, t.get("border"), 1), 12, 10))
	theme.set_stylebox("focus", "TextEdit", t.call("_pad", t.call("box", t.get("field"), 10, acc, 2), 12, 10))
	theme.set_color("font_color", "TextEdit", t.get("text"))
	theme.set_color("caret_color", "TextEdit", acc)
	theme.set_stylebox("panel", "TooltipPanel", t.call("_pad", t.call("box", t.get("card_inner"), 8, t.get("border"), 1, 1), 10, 6))
	theme.set_color("font_color", "TooltipLabel", t.get("text"))
	theme.set_type_variation("WbChip", "Button")
	theme.set_stylebox("normal", "WbChip", t.call("_pad", t.call("box", Color(1, 1, 1, 0.05), 99, t.get("border"), 1), 14, 7))
	theme.set_stylebox("hover", "WbChip", t.call("_pad", t.call("box", Color(1, 1, 1, 0.11), 99, Color(acc, 0.5), 1), 14, 7))
	theme.set_stylebox("pressed", "WbChip", t.call("_pad", t.call("box", Color(acc, 0.25), 99, acc, 1), 14, 7))
	theme.set_stylebox("focus", "WbChip", t.call("_pad", t.call("box", Color.TRANSPARENT, 99, acc, 2), 14, 7))
	theme.set_color("font_color", "WbChip", t.get("text_dim"))
	theme.set_color("font_hover_color", "WbChip", t.get("text"))
	theme.set_color("font_pressed_color", "WbChip", t.get("text"))
	theme.set_type_variation("WbSave", "FormPrimary")
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = theme.get_stylebox(st, "FormPrimary").duplicate()
		sb.set_corner_radius_all(99)
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if st != "disabled":
			sb.shadow_color = Color(acc, 0.4)
			sb.shadow_size = 8
		theme.set_stylebox(st, "WbSave", sb)
	theme.set_type_variation("WbClose", "FormGhost")
	for st in ["normal", "hover", "pressed"]:
		var cb: StyleBoxFlat = theme.get_stylebox(st, "FormGhost").duplicate()
		cb.set_corner_radius_all(99)
		cb.content_margin_left = 8
		cb.content_margin_right = 8
		theme.set_stylebox(st, "WbClose", cb)
	theme.set_type_variation("WbSub", "Label")
	theme.set_font_size("font_size", "WbSub", 12)
	theme.set_color("font_color", "WbSub", t.get("text_faint"))
	theme.set_type_variation("WbStatus", "Label")
	theme.set_font_size("font_size", "WbStatus", 12)


func _card_around(inner: Control) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", DotWorkbenchStyle.card(tokens, false, 18))
	pc.add_child(inner)
	return pc


func _bar() -> Control:
	var wrap := PanelContainer.new()
	var sb := DotWorkbenchStyle.card(tokens, true, 14)
	sb.content_margin_left = 20
	sb.content_margin_right = 14
	wrap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	wrap.add_child(row)
	row.add_child(DotWorkbenchStyle.badge("W", 42))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(names)
	var title := Label.new()
	title.text = "Workbench"
	title.theme_type_variation = &"FormTitle"
	title.add_theme_font_size_override("font_size", 22)
	names.add_child(title)
	var sub := Label.new()
	sub.text = "Live tuning  ·  the workbench key closes"
	sub.theme_type_variation = &"WbSub"
	names.add_child(sub)
	var slot := HBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.alignment = BoxContainer.ALIGNMENT_END
	_status_pill = PanelContainer.new()
	_status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_pill.visible = false
	_status = Label.new()
	_status.theme_type_variation = &"WbStatus"
	_status_pill.add_child(_status)
	slot.add_child(_status_pill)
	row.add_child(slot)
	row.add_child(_chip("Import", _on_import_toggle, "Apply a received export"))
	row.add_child(_chip("Make wearable", _on_wearable_toggle, "Publish a GLB as a wearable with a creator token"))
	row.add_child(_chip("Export changes as defaults", _on_export, "Writes only what differs from the shipped defaults, in cfg/ layout"))
	var save := _button("Save to server", _on_save, "Writes the open profile's edits to cfg/server")
	save.theme_type_variation = &"WbSave"
	_lift(save)
	row.add_child(save)
	var close_btn := _button("✕", close, "Close")
	close_btn.theme_type_variation = &"WbClose"
	close_btn.custom_minimum_size = Vector2(38, 38)
	row.add_child(close_btn)
	return wrap


func _chip(text: String, cb: Callable, tip: String) -> Button:
	var b := _button(text, cb, tip)
	b.theme_type_variation = &"WbChip"
	_lift(b)
	return b


func _lift(b: Button) -> void:
	if bool(tokens.get("animate")):
		DotWorkbenchStyle.lift(b)


func _build_import() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var head := Label.new()
	head.text = "Import an export"
	head.theme_type_variation = &"FormName"
	box.add_child(head)
	var hint := Label.new()
	hint.text = "Paste an export bundle, or the path of an export folder or .zip, then Apply."
	hint.theme_type_variation = &"FormCaption"
	box.add_child(hint)
	_import_box = TextEdit.new()
	_import_box.custom_minimum_size.y = 90
	box.add_child(_import_box)
	var go := _button("Apply import", _on_import_apply, "")
	go.theme_type_variation = &"FormPrimary"
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(go)
	return _card_around(box)


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
	_pop(self)


func close() -> void:
	visible = false
	closed.emit()


func _say(text: String, bad: bool) -> void:
	if _status == null:
		return
	_status.text = text
	var c: Color = tokens.get("danger") if bad else tokens.get("good")
	_status.add_theme_color_override("font_color", c)
	_status_pill.add_theme_stylebox_override("panel", DotWorkbenchStyle.pill(c))
	_status_pill.visible = not text.is_empty()


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
	_wearable_card.visible = not _wearable_card.visible
	_pop(_wearable_card)


func _on_import_toggle() -> void:
	_import_row.visible = not _import_row.visible
	_pop(_import_row)


func _on_import_apply() -> void:
	var res := exporter.import_source(panel.actor, _import_box.text)
	if not res.ok:
		_say(res.error.message, true)
		return
	var skipped: Array = res.value["skipped"]
	_say("Imported %d values live%s" % [res.value["applied"], ", %d skipped" % skipped.size() if not skipped.is_empty() else ""], not skipped.is_empty())
	editor.call("open", editor.call("current_kind"), editor.call("current_id")) if not str(editor.call("current_kind")).is_empty() else null


func _pop(c: Control) -> void:
	if not c.visible or not c.is_inside_tree() or not bool(tokens.get("animate")):
		return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.16)
