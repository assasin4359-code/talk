extends BTGTest
## Loads the real village scene and checks it shows what the story state says.
## (Headless: no pixels, but transforms, physics and signals all run.)

const VILLAGE := "res://scenes/village.tscn"


func _narrative() -> Node:
	return tree.root.get_node("Narrative")


func _open(stage: String, cycle: int) -> Node:
	var narrative := _narrative()
	narrative.autosave = false  # never touch the player's save
	var st := BTGStoryState.new_game(narrative.db.start_stage)
	st.stage = stage
	st.cycle = cycle
	narrative.use_state(st)
	var v: Node = load(VILLAGE).instantiate()
	var director = v.get_node("Director")
	director.speed = 50.0  # presentation 50x faster
	director.reload_on_new_day = false
	tree.root.add_child(v)
	await director.day_started
	await frames(1)
	return v


func _close(v: Node) -> void:
	v.queue_free()
	await frames(1)


func _target(v: Node, id: String) -> Node3D:
	for t in v.find_children("*", "Node3D", true, false):
		if t is BTGNarrativeTarget and t.target_id == id:
			return t
	return null


func _at_anchor(v: Node, node: Node3D, anchor_id: String, who: String) -> bool:
	var a := BTGAnchor.find(tree, anchor_id, who)
	return a != null and node.global_position.distance_to(a.global_position) < 0.05


func test_scene_covers_gamedata() -> void:
	var v: Node = await _open("S01_Arrival", 1)
	var db: BTGNarrativeDB = _narrative().db
	for anchor in db.anchors:
		assert_true(BTGAnchor.find(tree, anchor, "") != null, "no anchor '%s' in village" % anchor)
	for key in db.world_baseline:
		var target: String = key.get_slice(".", 0)
		if target != "player":
			assert_true(_target(v, target) != null, "no node for target '%s'" % target)
	await _close(v)


func test_day1_normal_world() -> void:
	var v: Node = await _open("S01_Arrival", 1)
	assert_true(_at_anchor(v, v.get_node("Player"), "entrance", "player"), "player spawns at the entrance")
	assert_true(_at_anchor(v, _target(v, "guard"), "gate", "guard"), "guard at his post")
	assert_true(_at_anchor(v, _target(v, "bartender"), "tavern", "bartender"), "bartender behind the counter")
	assert_true(_at_anchor(v, _target(v, "firewood"), "smithy", "firewood"), "firewood at the smithy")
	var gate := _target(v, "gate")
	assert_true(absf(gate.get_node("HingeL").rotation_degrees.y) > 80.0, "gate open on day 1")
	assert_eq(_target(v, "tavern_sign").get_node("Board").rotation_degrees.z, 0.0, "sign upright")
	await _close(v)


func test_day2_gate_closed() -> void:
	var v: Node = await _open("S02_GateClosed", 2)
	var gate := _target(v, "gate")
	assert_eq(gate.get_node("HingeL").rotation_degrees.y, 0.0, "left leaf closed")
	assert_eq(gate.get_node("HingeR").rotation_degrees.y, 0.0, "right leaf closed")
	await _close(v)


func test_day3_sign_flipped() -> void:
	var v: Node = await _open("S03_SliceEnd", 3)
	assert_eq(_target(v, "tavern_sign").get_node("Board").rotation_degrees.z, 180.0, "sign upside down")
	await _close(v)


func test_looking_at_the_guard_focuses_him() -> void:
	var v: Node = await _open("S01_Arrival", 1)
	var player = v.get_node("Player")
	var guard := _target(v, "guard")
	player.global_position = guard.global_position + Vector3(0, 0, 1.8)
	player.rotation = Vector3.ZERO
	player.camera.look_at(guard.global_position + Vector3(0, 1.3, 0))
	await physics_frames(3)
	assert_true(player.focus == guard, "focus is %s" % [player.focus])
	await _close(v)


func test_walking_into_the_castle_ends_day1() -> void:
	var v: Node = await _open("S01_Arrival", 1)
	var player = v.get_node("Player")
	var volume: Area3D = v.get_node("CastleFoyerVolume")
	player.global_position = volume.global_position - Vector3(0, 1.4, -2.5)  # just outside, on the floor
	await physics_frames(2)
	player.global_position = volume.global_position - Vector3(0, 1.4, 0)
	await physics_frames(4)
	assert_eq(_narrative().engine.pending_faint, "CastleInterior")
	await _close(v)
