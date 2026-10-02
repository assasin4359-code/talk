class_name BTGInput
extends RefCounted
## Registers the game's input actions in code, so the project runs without hand-editing
## the Input Map. Rebinding UI can later read/write the same action names.


## Whether the game WANTS mouse-look. Tracked here, not read back from Input.mouse_mode,
## so headless runs (tests) behave like a real window and every caller shares one truth.
static var mouse_captured := false
## The OS/browser has actually granted the capture since the last request. Browsers
## grant pointer lock asynchronously (and only after a click), so "wanted" and "have"
## can differ for a while.
static var _granted := false


static func capture_mouse(on: bool) -> void:
	mouse_captured = on
	_granted = false
	if not _headless():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## Mouse-look is wanted AND really in effect.
static func is_captured() -> bool:
	return mouse_captured and (_headless() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


## True when a capture we had was taken away from outside the game: in a browser, Esc
## exits pointer lock without the game ever seeing the key. Poll once per frame.
static func capture_lost() -> bool:
	if not mouse_captured or _headless():
		return false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_granted = true
		return false
	return _granted


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func ensure_actions() -> void:
	_add("move_forward", [KEY_W, KEY_UP])
	_add("move_back", [KEY_S, KEY_DOWN])
	_add("move_left", [KEY_A, KEY_LEFT])
	_add("move_right", [KEY_D, KEY_RIGHT])
	_add("sprint", [KEY_SHIFT])
	_add("interact", [KEY_E, KEY_SPACE, KEY_ENTER], [MOUSE_BUTTON_LEFT])
	_add("menu", [KEY_ESCAPE])
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
