class_name BTGHud
extends CanvasLayer
## Crosshair + interaction prompt. Deliberately minimal: no quest text, no counters.

const VERB_LABEL := {"talk": "말 걸기", "use": "살펴보기"}

var _prompt: Label
var _dot: ColorRect


func _ready() -> void:
	layer = 5
	_dot = ColorRect.new()
	_dot.color = Color(1, 1, 1, 0.75)
	_dot.size = Vector2(4, 4)
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.position -= _dot.size / 2
	add_child(_dot)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position += Vector2(-200, 40)
	_prompt.size = Vector2(400, 30)
	add_child(_prompt)
	show_target(null)


func show_target(t: BTGNarrativeTarget) -> void:
	if t == null:
		_prompt.text = ""
		return
	_prompt.text = "[E] %s · %s" % [t.display_name(), VERB_LABEL.get(t.verb, t.verb)]


func set_visible_all(v: bool) -> void:
	_dot.visible = v
	_prompt.visible = v
