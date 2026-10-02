extends BTGTest
## Mouse-look through real input events. Motion is sent at the screen centre because
## that is where a captured mouse lives — and where the HUD crosshair sits.

const VILLAGE := "res://scenes/village.tscn"

var village: Node
var director
var player


func _open() -> void:
	var narrative := tree.root.get_node("Narrative")
	narrative.autosave = false
	narrative.use_state(null)
	village = load(VILLAGE).instantiate()
	director = village.get_node("Director")
	director.speed = 50.0
	director.scene_changes = false
	tree.root.add_child(village)
	await director.day_started
	player = village.get_node("Player")


func _close() -> void:
	village.queue_free()
	await frames(3)


func _move_mouse(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	var centre: Vector2 = tree.root.get_visible_rect().size / 2
	ev.position = centre
	ev.global_position = centre
	ev.relative = rel
	ev.screen_relative = rel
	Input.parse_input_event(ev)
	await frames(2)


func _click() -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		var centre: Vector2 = tree.root.get_visible_rect().size / 2
		ev.position = centre
		ev.global_position = centre
		Input.parse_input_event(ev)
		await frames(2)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		ev.keycode = k
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(2)


func test_mouse_turns_the_view() -> void:
	await _open()
	assert_true(BTGInput.mouse_captured, "mouse-look is on once the day starts")
	var yaw: float = player.rotation.y
	var pitch: float = player.head.rotation.x
	await _move_mouse(Vector2(120, 0))
	assert_true(absf(player.rotation.y - yaw) > 0.1, "horizontal mouse turns the body (yaw %s -> %s)" % [yaw, player.rotation.y])
	await _move_mouse(Vector2(0, -80))
	assert_true(player.head.rotation.x - pitch > 0.1, "vertical mouse tilts the head (pitch %s -> %s)" % [pitch, player.head.rotation.x])
	await _close()


## A real click on a button: the pointer has to arrive first (buttons only take presses
## while hovered).
func _click_at(pos: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	await frames(2)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await frames(2)


func test_escape_opens_the_menu_and_resume_takes_the_mouse_back() -> void:
	await _open()
	var menu: BTGGameMenu = director.menu
	await _key(KEY_ESCAPE)
	assert_true(menu.is_open, "Esc opens the game menu")
	assert_false(BTGInput.mouse_captured, "the cursor is free while the menu is up")
	var yaw: float = player.rotation.y
	await _move_mouse(Vector2(120, 0))
	assert_eq(player.rotation.y, yaw, "a free cursor does not turn the view")
	await _click_at(menu.resume_button.get_global_rect().get_center())
	assert_false(menu.is_open, "clicking 계속하기 closes the menu")
	assert_true(BTGInput.mouse_captured, "and takes the mouse back")
	assert_false(director.busy, "that click did not start an interaction")
	await _move_mouse(Vector2(120, 0))
	assert_true(absf(player.rotation.y - yaw) > 0.1, "mouse-look works again")
	await _close()


func test_click_recaptures_a_refused_capture() -> void:
	await _open()
	BTGInput.capture_mouse(false)  # e.g. a browser refused pointer lock (no recent click)
	var yaw: float = player.rotation.y
	await _move_mouse(Vector2(120, 0))
	assert_eq(player.rotation.y, yaw, "no mouse-look without the capture")
	await _click()
	assert_true(BTGInput.mouse_captured, "clicking into the game takes the mouse back")
	assert_false(director.busy, "that click did not start an interaction")
	assert_false(director.menu.is_open, "no menu for that")
	await _close()


func test_choices_free_the_cursor_then_take_it_back() -> void:
	await _open()
	var box: BTGDialogueBox = director.dialogue
	box.instant = true
	director.request("talk", "guard")  # 3 lines, then two options
	for i in 3:
		await frames(2)
		await _key(KEY_E)
	await frames(2)
	assert_false(BTGInput.mouse_captured, "cursor visible while choosing")
	await _key(KEY_2)
	await frames(3)
	assert_true(BTGInput.mouse_captured, "mouse-look back after choosing")
	assert_false(director.busy, "conversation over")
	await _close()
