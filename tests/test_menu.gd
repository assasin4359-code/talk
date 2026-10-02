extends BTGTest
## Title screen and in-game menu: continue / start over / progress reset / pause.
## Uses a throwaway save location, never the player's save.

const TITLE := "res://scenes/main_menu.tscn"
const VILLAGE := "res://scenes/village.tscn"
const TEST_SAVES := "user://test_menu/slot0"

var narrative: Node
var village: Node
var director
var player
var _old_base := ""
var _old_autosave := false


func _with_test_saves(cycle: int) -> void:
	narrative = tree.root.get_node("Narrative")
	_old_base = narrative.save_base
	_old_autosave = narrative.autosave
	narrative.save_base = TEST_SAVES
	narrative.autosave = true
	BTGSaveSystem.erase(TEST_SAVES)
	if cycle > 0:
		var st := BTGStoryState.new_game(narrative.db.start_stage)
		st.cycle = cycle
		st.stage = "S02_GateClosed" if cycle == 2 else "S03_SliceEnd" if cycle >= 3 else st.stage
		BTGSaveSystem.write(TEST_SAVES, st)


func _restore_saves() -> void:
	BTGSaveSystem.erase(TEST_SAVES)
	narrative.save_base = _old_base
	narrative.autosave = _old_autosave


func _title() -> BTGMainMenu:
	var m: BTGMainMenu = load(TITLE).instantiate()
	m.scene_changes = false
	tree.root.add_child(m)
	await frames(2)
	return m


func _open_village() -> void:
	village = load(VILLAGE).instantiate()
	director = village.get_node("Director")
	director.speed = 50.0
	director.scene_changes = false
	tree.root.add_child(village)
	await director.day_started
	player = village.get_node("Player")


func _close_village() -> void:
	Input.action_release("move_forward")
	village.queue_free()
	await frames(3)
	tree.paused = false


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		ev.keycode = k
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(2)


## Keyboard activation, like a player tabbing to a button and pressing Enter.
func _press(b: Button) -> void:
	b.grab_focus()
	await frames(1)
	await _key(KEY_ENTER)


func _record(sig: Signal) -> Array:
	var got := []
	sig.connect(func(x = null): got.append(x))
	return got


# --- title screen -------------------------------------------------------------------

func test_title_without_a_save_starts_day_one() -> void:
	_with_test_saves(0)
	var m := await _title()
	assert_false(m.continue_button.visible, "nothing to continue")
	assert_eq(m.get_viewport().gui_get_focus_owner(), m.new_button, "처음부터 has focus")
	var got := _record(m.chosen)
	await _press(m.new_button)
	assert_eq(got, ["new"], "one press starts (no progress to lose)")
	assert_eq(narrative.engine.cycle, 1, "day 1")
	assert_false(narrative.just_woke, "arrival, not a wake-up")
	assert_eq(narrative.saved_cycle(), 1, "day 1 checkpoint written")
	m.queue_free()
	_restore_saves()


func test_title_continues_the_saved_day() -> void:
	_with_test_saves(2)
	narrative.use_state(null)  # whatever is in memory must not matter; the disk does
	var m := await _title()
	assert_true(m.continue_button.visible, "이어하기 shown")
	assert_true("2일째" in m.continue_button.text, "shows the saved day: %s" % m.continue_button.text)
	assert_eq(m.get_viewport().gui_get_focus_owner(), m.continue_button, "이어하기 has focus")
	var got := _record(m.chosen)
	await _press(m.continue_button)
	assert_eq(got, ["continue"], "continued")
	assert_eq(narrative.engine.cycle, 2, "day 2 from disk")
	assert_eq(narrative.engine.state.stage, "S02_GateClosed", "stage from disk")
	assert_true(narrative.just_woke, "a continued day starts with waking up")
	m.queue_free()
	_restore_saves()


func test_starting_over_asks_twice_when_there_is_progress() -> void:
	_with_test_saves(3)
	var m := await _title()
	var got := _record(m.chosen)
	await _press(m.new_button)
	assert_eq(got, [], "first press only asks")
	assert_true("지워" in m.new_button.text, "says progress will be erased: %s" % m.new_button.text)
	assert_eq(narrative.saved_cycle(), 3, "nothing erased yet")
	await _press(m.continue_button)  # changing your mind...
	got.clear()
	m.queue_free()
	m = await _title()
	got = _record(m.chosen)
	await _press(m.new_button)
	m.continue_button.grab_focus()  # ...moving away cancels the question
	await frames(1)
	assert_eq(m.new_button.text, "처음부터", "question withdrawn")
	await _press(m.new_button)
	await _press(m.new_button)
	assert_eq(got, ["new"], "second press starts over")
	assert_eq(narrative.saved_cycle(), 1, "save wiped back to day 1")
	assert_eq(narrative.engine.cycle, 1, "day 1 in memory")
	for path in BTGSaveSystem.slot_paths(TEST_SAVES):
		var r := BTGSaveSystem.read_slot(path)
		assert_true(r["state"] == null or r["state"].cycle == 1, "no old day left in %s" % path)
	m.queue_free()
	_restore_saves()


# --- in-game menu -------------------------------------------------------------------

func test_menu_pauses_the_game() -> void:
	_with_test_saves(1)
	narrative.continue_game()
	await _open_village()
	var menu: BTGGameMenu = director.menu
	var box: BTGDialogueBox = director.dialogue
	box.pace = func(_s): return 12.0
	director.request("talk", "guard")
	for i in 200:
		if box._text.visible_characters > 2:
			break
		await frames(1)
	await _key(KEY_ESCAPE)
	assert_true(menu.is_open, "Esc opens the menu mid-conversation")
	assert_true(tree.paused, "game paused")
	var shown: int = box._text.visible_characters
	var pos: Vector3 = player.global_position
	await physics_frames(40)
	assert_eq(box._text.visible_characters, shown, "typewriter frozen")
	await _key(KEY_ESCAPE)
	assert_false(menu.is_open, "Esc again resumes")
	assert_false(tree.paused, "unpaused")
	await physics_frames(20)
	assert_true(box._text.visible_characters > shown, "typewriter running again")
	assert_eq(player.global_position, pos, "nobody walked during the pause")
	await _close_village()
	_restore_saves()


func test_menu_restart_wipes_progress() -> void:
	_with_test_saves(2)
	narrative.continue_game()
	await _open_village()
	var menu: BTGGameMenu = director.menu
	var left := _record(director.left)
	await _key(KEY_ESCAPE)
	await _press(menu.restart_button)
	assert_eq(left, [], "first press only asks")
	assert_true(menu.is_open, "still in the menu")
	assert_eq(narrative.saved_cycle(), 2, "nothing erased yet")
	await _press(menu.restart_button)
	assert_eq(left, [VILLAGE], "village reloads")
	assert_false(menu.is_open, "menu closed")
	assert_false(tree.paused, "unpaused before leaving")
	assert_eq(narrative.saved_cycle(), 1, "save back to day 1")
	assert_eq(narrative.engine.cycle, 1, "day 1 in memory")
	assert_false(narrative.just_woke, "day 1 is an arrival")
	await _close_village()
	_restore_saves()


func test_menu_back_to_title() -> void:
	_with_test_saves(2)
	narrative.continue_game()
	await _open_village()
	var left := _record(director.left)
	await _key(KEY_ESCAPE)
	await _press(director.menu.title_button)
	assert_eq(left, ["res://scenes/main_menu.tscn"], "to the title")
	assert_false(tree.paused, "unpaused before leaving")
	assert_eq(narrative.saved_cycle(), 2, "progress kept")
	await _close_village()
	_restore_saves()


func test_menu_during_a_choice_keeps_the_cursor_free() -> void:
	_with_test_saves(1)
	narrative.continue_game()
	await _open_village()
	var box: BTGDialogueBox = director.dialogue
	box.instant = true
	director.request("talk", "guard")  # 3 lines, then two options
	for i in 3:
		await frames(2)
		await _key(KEY_E)
	await frames(2)
	assert_false(BTGInput.mouse_captured, "choosing: cursor free")
	await _key(KEY_ESCAPE)
	assert_true(director.menu.is_open, "menu over the choice")
	await _press(director.menu.resume_button)
	assert_false(BTGInput.mouse_captured, "back to the choice with the cursor still free")
	await _key(KEY_2)
	await frames(3)
	assert_false(director.busy, "the choice still works")
	await _close_village()
	_restore_saves()


func test_title_buttons_take_real_clicks() -> void:
	_with_test_saves(2)
	var m := await _title()
	var got := _record(m.chosen)
	var pos := m.continue_button.get_global_rect().get_center()
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
	assert_eq(got, ["continue"], "clicking 이어하기 continues")
	m.queue_free()
	_restore_saves()
