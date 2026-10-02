class_name BTGInput
extends RefCounted
## Registers the game's input actions in code, so the project runs without hand-editing
## the Input Map. Rebinding UI can later read/write the same action names.


static func ensure_actions() -> void:
	_add("move_forward", [KEY_W, KEY_UP])
	_add("move_back", [KEY_S, KEY_DOWN])
	_add("move_left", [KEY_A, KEY_LEFT])
	_add("move_right", [KEY_D, KEY_RIGHT])
	_add("sprint", [KEY_SHIFT])
	_add("interact", [KEY_E, KEY_SPACE, KEY_ENTER], [MOUSE_BUTTON_LEFT])
	_add("release_mouse", [KEY_ESCAPE])
	_add("debug_new_game", [KEY_F9])  # playtest helper: back to day 1
	for i in range(1, 10):
		_add("choice_%d" % i, [KEY_0 + i])


static func _add(action: StringName, keys: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)
