class_name BTGGameMenu
extends CanvasLayer
## In-game menu (Esc). Pauses the whole game while open: gameplay timers are created
## with process_always = false and tweens are node-bound, so dialogue, the faint and
## footsteps all freeze. Also opens by itself when the mouse capture is lost (a
## browser's Esc never reaches the game; alt-tab), so the cursor never floats over a
## running game.
## [임시] "처음부터 다시" is a playtest helper. Whether the finished game lets the player
## wipe progress mid-game (and whether the narrator notices) is undecided.

signal opened
signal resumed
signal restart_requested
signal title_requested

## A browser may deliver Esc right after it already released the mouse (which opened
## the menu); don't let that same press close it again.
const REOPEN_GUARD_MS := 250

var is_open := false
var resume_button: Button
var restart_button: Button
var title_button: Button
var _root: Control
var _restore_capture := true
var _opened_at := -REOPEN_GUARD_MS
var _confirming := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0, 0, 0, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var centre := CenterContainer.new()  # stays centred however wide the text gets
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var box := BTGMenuStyle.panel()
	box.custom_minimum_size = Vector2(520, 0)
	centre.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	column.add_child(BTGMenuStyle.label("메뉴", 18, BTGMenuStyle.DIM))
	resume_button = BTGMenuStyle.button("계속하기")
	resume_button.pressed.connect(resume)
	column.add_child(resume_button)
	restart_button = BTGMenuStyle.button("처음부터 다시")
	restart_button.pressed.connect(_on_restart)
	restart_button.focus_exited.connect(_set_confirming.bind(false))
	column.add_child(restart_button)
	title_button = BTGMenuStyle.button("타이틀로")
	title_button.pressed.connect(_on_title)
	column.add_child(title_button)
	var hint := BTGMenuStyle.label("저장은 하루가 시작될 때만 돼요. 타이틀로 나가면 그날 아침부터 다시.", 15, BTGMenuStyle.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(460, 0)
	column.add_child(hint)


func _process(_delta: float) -> void:
	if not is_open and BTGInput.capture_lost():
		open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not is_open:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu"):
		return
	get_viewport().set_input_as_handled()
	if not is_open:
		open()
	elif Time.get_ticks_msec() - _opened_at > REOPEN_GUARD_MS:
		resume()


func open() -> void:
	if is_open:
		return
	is_open = true
	_opened_at = Time.get_ticks_msec()
	_restore_capture = BTGInput.mouse_captured  # false while a dialogue choice is up
	BTGInput.capture_mouse(false)
	get_tree().paused = true
	_set_confirming(false)
	_root.visible = true
	resume_button.grab_focus()
	opened.emit()


func resume() -> void:
	if not is_open:
		return
	_close()
	BTGInput.capture_mouse(_restore_capture)
	resumed.emit()


func _close() -> void:
	is_open = false
	_root.visible = false
	get_tree().paused = false


func _exit_tree() -> void:
	if is_open:
		_close()  # never leave the tree paused behind a freed menu


func _set_confirming(on: bool) -> void:
	_confirming = on
	restart_button.text = "정말 처음부터? 진행이 지워져요" if on else "처음부터 다시"


func _on_restart() -> void:
	if not _confirming:
		_set_confirming(true)
		return
	_close()
	restart_requested.emit()


func _on_title() -> void:
	_close()
	title_requested.emit()
