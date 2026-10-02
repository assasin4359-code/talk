class_name BTGMainMenu
extends Control
## Title screen: continue from the last checkpoint, or start over.
## [임시] Placeholder look and wording. What the real title screen shows (and whether
## the narrator ever comments on "처음부터") is undecided.

signal chosen(action: String)  ## "continue" | "new" | "quit"

const VILLAGE := "res://scenes/village.tscn"

var scene_changes := true  ## tests turn this off and listen to `chosen` instead
var continue_button: Button
var new_button: Button
var quit_button: Button
var _saved_cycle := 0
var _confirming := false


func _ready() -> void:
	BTGInput.ensure_actions()
	BTGInput.capture_mouse(false)
	_saved_cycle = Narrative.saved_cycle()
	_build()
	(continue_button if continue_button.visible else new_button).grab_focus()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.05, 0.045)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.position = Vector2(140, -190)
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var title := BTGMenuStyle.label("Back to the Gates", 58, BTGMenuStyle.TEXT)
	title.add_theme_font_override("font", load(BTGMenuStyle.TITLE_FONT))
	column.add_child(title)
	column.add_child(BTGMenuStyle.label("MILESTONE 01 — THE FIRST RETURN", 17, BTGMenuStyle.DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 48)
	column.add_child(gap)

	continue_button = BTGMenuStyle.button("이어하기  ·  %d일째" % _saved_cycle)
	continue_button.visible = _saved_cycle > 0
	continue_button.pressed.connect(_on_continue)
	column.add_child(continue_button)
	new_button = BTGMenuStyle.button("처음부터")
	new_button.pressed.connect(_on_new)
	new_button.focus_exited.connect(_set_confirming.bind(false))
	column.add_child(new_button)
	quit_button = BTGMenuStyle.button("종료")
	quit_button.visible = not OS.has_feature("web")  # a browser tab can't quit itself
	quit_button.pressed.connect(_on_quit)
	column.add_child(quit_button)

	var footer := BTGMenuStyle.label("임시 메뉴 · 플레이테스트 빌드", 14, BTGMenuStyle.DIM)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(140, -56)
	add_child(footer)


func _set_confirming(on: bool) -> void:
	_confirming = on
	new_button.text = "정말 처음부터? 진행이 지워져요" if on else "처음부터"


func _on_continue() -> void:
	Narrative.continue_game()
	_go("continue")


func _on_new() -> void:
	if _saved_cycle > 1 and not _confirming:
		_set_confirming(true)
		return
	Narrative.new_game()
	_go("new")


func _on_quit() -> void:
	chosen.emit("quit")
	if scene_changes:
		get_tree().quit()


func _go(action: String) -> void:
	chosen.emit(action)
	if scene_changes:
		get_tree().change_scene_to_file(VILLAGE)
