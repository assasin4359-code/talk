extends BTGTest
## Milestone 01 end to end through the real game layer: village scene, director,
## dialogue box, faint presentation, wake-up, next day. The story rules themselves are
## covered by the shared scenarios; this checks the wiring a player actually goes through.

const VILLAGE := "res://scenes/village.tscn"

var village: Node
var director


func _start_day() -> void:
	village = load(VILLAGE).instantiate()
	director = village.get_node("Director")
	director.speed = 50.0
	director.scene_changes = false
	var started := _flag(director.day_started)
	tree.root.add_child(village)
	director.dialogue.instant = true
	await _until(started)


func _end_day() -> void:
	village.queue_free()
	await frames(1)
	await _start_day()


## Connects before acting, so signals emitted synchronously are not missed.
func _flag(sig: Signal) -> Array:
	var holder := [false, null]
	sig.connect(func(arg = null): holder[0] = true; holder[1] = arg, CONNECT_ONE_SHOT)
	return holder


func _until(holder: Array, max_frames := 600) -> Variant:
	for i in max_frames:
		if holder[0]:
			return holder[1]
		await frames(1)
	fail("timed out waiting for a signal")
	return null


func _act(verb: String, target: String, picks: Array = []) -> PackedStringArray:
	director.dialogue.autoplay = picks.duplicate()
	var before: int = director.dialogue.transcript.size()
	var done := _flag(director.conversation_finished)
	director.request(verb, target)
	await _until(done)
	var lines := PackedStringArray()
	for l in director.dialogue.transcript.slice(before):
		lines.append("%s: %s" % l)
	return lines


func _visible(path: String) -> bool:
	return village.get_node(path).is_visible_in_tree()


func test_milestone_01() -> void:
	var narrative := tree.root.get_node("Narrative")
	narrative.autosave = false
	narrative.use_state(null)
	await _start_day()

	# ── day 1: the normal world ──
	var player = village.get_node("Player")
	assert_true(not player.input_locked, "player can move after the fade-in")
	await _act("use", "firewood")
	assert_true(_visible("Player/Head/Camera3D/Held/Variants/firewood"), "firewood in hand")
	var said := await _act("talk", "bartender", ["(장작을"])
	assert_true("bartender: ……장작이 얼마 안 남았네." in said, "hint muttered: %s" % said)
	assert_true("bartender: 고마워. 오늘 밤은 안 춥겠네." in said, "thanks: %s" % said)
	assert_false(_visible("Player/Head/Camera3D/Held/Variants/firewood"), "firewood handed over")
	assert_true(_visible("Targets/TavernBasket/Variants/full"), "basket full after helping")
	await _act("talk", "guard", ["고마워"])

	var day_end := _flag(director.day_ended)
	var volume: Area3D = village.get_node("CastleFoyerVolume")
	player.global_position = volume.global_position - Vector3(0, 1.4, 0)
	var result: Variant = await _until(day_end)
	assert_eq(result["to_stage"] if result else "", "S02_GateClosed")

	# ── day 2: the gate is closed and the guard remembers ──
	await _end_day()
	player = village.get_node("Player")
	var spawn := BTGAnchor.find(tree, "entrance", "player")
	assert_true(player.global_position.distance_to(spawn.global_position) < 0.1, "woke up at the entrance")
	assert_eq(village.get_node("Targets/Gate/HingeL").rotation_degrees.y, 0.0, "gate closed")
	assert_true(_visible("Targets/TavernBasket/Variants/low"), "yesterday's firewood burned")
	said = await _act("talk", "bartender", ["들어가자마자"])
	assert_true("bartender: 어, 왔어? 어제 장작 가져다준 거 고맙더라." in said, "remembers: %s" % said)
	said = await _act("talk", "guard", ["성문 앞?", "문은 왜", "……아무것도"])
	assert_eq(said.slice(0, 4), PackedStringArray([
		"player: 어제는 들어갈 수 있었잖아.",
		"guard: 어제?",
		"guard: ……어디서 본 것 같은데.",
		"guard: 아. 어제 성문 앞에서 쓰러진 사람이 자네였나?",
	]))
	day_end = _flag(director.day_ended)
	await _act("use", "gate")
	result = await _until(day_end)
	assert_eq(result["to_stage"] if result else "", "S03_SliceEnd")

	# ── day 3: one thing is off; the slice ends quietly once the player reaches the square ──
	await _end_day()
	assert_eq(village.get_node("Targets/TavernSign/Board").rotation_degrees.z, 180.0, "sign upside down")
	player = village.get_node("Player")
	player.global_position = BTGAnchor.find(tree, "square", "").global_position
	for i in 120:
		if director.end_card != null:
			break
		await frames(1)
	assert_true(director.end_card != null, "slice end card shown")
	village.queue_free()
	await frames(1)


func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


func test_dialogue_keyboard() -> void:
	var narrative := tree.root.get_node("Narrative")
	narrative.autosave = false
	narrative.use_state(null)
	await _start_day()
	var box: BTGDialogueBox = director.dialogue
	# first talk: 3 lines, then [왕은 어떤 분이야? / 고마워.]; "2" picks 고마워 and ends it
	var done := _flag(director.conversation_finished)
	director.request("talk", "guard")
	for i in 3:
		await frames(2)
		await _press(KEY_E)
	await _press(KEY_2)
	await _until(done, 120)
	assert_eq(box.transcript.size(), 3, "three lines, no reply after 고마워")
	assert_false(director.busy, "control returns to the player")
	# second talk: repeat line; then E on the first option of the next conversation is
	# covered by the bartender's first talk: [성에는 누가 살아? / 그냥 둘러보는 중이야.]
	done = _flag(director.conversation_finished)
	director.request("talk", "bartender")
	for i in 4:
		await frames(2)
		await _press(KEY_E)
	await frames(2)
	await _press(KEY_E)  # focused first option: 성에는 누가 살아?
	for i in 5:
		await frames(2)
		await _press(KEY_E)
	await _until(done, 120)
	var last: Array = box.transcript[box.transcript.size() - 1]
	assert_eq(last[1], "성문도 웬만하면 열려 있어. 한번 올라가 봐. 운 좋으면 차 한잔 얻어 마실걸?", "picked the focused option")
	village.queue_free()
	await frames(1)
