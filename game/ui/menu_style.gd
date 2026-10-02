class_name BTGMenuStyle
extends RefCounted
## Shared look for the title screen and the in-game menu (placeholder art direction:
## the dialogue box's warm-on-dark palette).

const TEXT := Color(0.93, 0.88, 0.8)
const ACCENT := Color(0.95, 0.78, 0.48)
const DIM := Color(0.93, 0.88, 0.8, 0.45)
const PANEL := Color(0.07, 0.06, 0.05, 0.92)
const TITLE_FONT := "res://assets/fonts/Pretendard-SemiBold.otf"


static func button(text: String, font_size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, ACCENT)
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.set_content_margin_all(10)
	idle.content_margin_left = 18
	var lit := idle.duplicate() as StyleBoxFlat
	lit.bg_color = Color(ACCENT, 0.12)
	lit.border_color = Color(ACCENT, 0.6)
	lit.border_width_left = 3
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("focus", lit)
	b.add_theme_stylebox_override("pressed", lit)
	b.add_theme_stylebox_override("hover_pressed", lit)
	return b


static func label(text: String, font_size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	style.border_color = Color(ACCENT, 0.35)
	style.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", style)
	return p
