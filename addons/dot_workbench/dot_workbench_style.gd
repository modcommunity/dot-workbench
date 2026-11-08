class_name DotWorkbenchStyle
extends RefCounted

## The workbench's slick look: a deeper palette, softer corners and pill controls over dot-ui's [DotFormTokens].
## Pure styling, no behaviour; a game menu (the Playground spawn menu) can call [method apply] to share the language.

const BG := Color(0.043, 0.050, 0.075)
const CARD := Color(0.075, 0.086, 0.125)
const CARD_INNER := Color(0.102, 0.116, 0.165)
const FIELD := Color(0.118, 0.134, 0.188)
const FIELD_HOVER := Color(0.157, 0.176, 0.247)
const BORDER := Color(1, 1, 1, 0.075)
const ACCENT := Color(0.40, 0.46, 1.0)


## Re-colours [param t] (a DotFormTokens, dark) in place and returns it.
static func apply(t: Object) -> Object:
	t.set("bg", BG)
	t.set("card", CARD)
	t.set("card_inner", CARD_INNER)
	t.set("field", FIELD)
	t.set("field_hover", FIELD_HOVER)
	t.set("border", BORDER)
	t.set("text", Color(0.94, 0.95, 0.99))
	t.set("text_dim", Color(0.64, 0.68, 0.78))
	t.set("text_faint", Color(0.42, 0.46, 0.57))
	t.set("accent", ACCENT)
	t.set("accent_ink", Color(0.03, 0.04, 0.12))
	t.set("danger", Color(1.0, 0.45, 0.50))
	t.set("good", Color(0.36, 0.88, 0.62))
	t.set("shadow", Color(0, 0, 0, 0.5))
	t.set("radius", 14)
	t.set("font_body", 14)
	t.set("font_small", 12)
	t.set("font_title", 26)
	return t


## A rounded card; [param glow] tints the border with the accent.
static func card(t: Object, glow := false, pad := 16) -> StyleBoxFlat:
	var edge: Color = Color(ACCENT, 0.35) if glow else t.get("border")
	var b: StyleBoxFlat = t.call("box", t.get("card"), 18, edge, 1, 2)
	b.set_content_margin_all(pad)
	return b


## A small rounded pill background tinted with [param color].
static func pill(color: Color, fill_alpha := 0.16) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(color, fill_alpha)
	b.border_color = Color(color, 0.45)
	b.set_border_width_all(1)
	b.set_corner_radius_all(99)
	b.anti_aliasing = true
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	return b


## The accent brand badge.
static func badge(letter: String, size := 40) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(int(size * 0.32))
	sb.anti_aliasing = true
	sb.shadow_color = Color(ACCENT, 0.45)
	sb.shadow_size = 10
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = letter
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size * 0.5))
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


## Gives a button a hover lift: a quick scale around its centre.
static func lift(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _scale_to(b, Vector2(1.04, 1.04)))
	b.mouse_exited.connect(func() -> void: _scale_to(b, Vector2.ONE))


static func _scale_to(b: Control, to: Vector2) -> void:
	if not b.is_inside_tree():
		return
	var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", to, 0.12)
