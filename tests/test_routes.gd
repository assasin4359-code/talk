extends BTGTest
## Every route the story needs must be WALKABLE with the real controller — no
## teleporting. A bot steers the player through waypoints by turning and holding
## move_forward; if it stops making progress, the route is blocked (a step it can't
## climb, a wall, a collider in the way).

const VILLAGE := "res://scenes/village.tscn"
const SPEEDUP := 4.0  # Engine.time_scale while walking

var village: Node
var director
var player


func _open(stage: String, cycle: int) -> void:
	var narrative := tree.root.get_node("Narrative")
	narrative.autosave = false
	var st := BTGStoryState.new_game(narrative.db.start_stage)
	st.stage = stage
	st.cycle = cycle
	narrative.use_state(st)
	village = load(VILLAGE).instantiate()
	director = village.get_node("Director")
	director.speed = 50.0
	director.scene_changes = false
	tree.root.add_child(village)
	await director.day_started
	player = village.get_node("Player")


func _close() -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Engine.time_scale = 1.0
	village.queue_free()
	await frames(3)  # let the audio server process the stopped faint tone


## Walks through `points` (feet positions). Returns "" on success, else where it got stuck.
func _walk(points: Array, stop_when := Callable()) -> String:
	Engine.time_scale = SPEEDUP
	Input.action_press("sprint")
	for target in points:
		var best := INF
		var stalled := 0.0
		while true:
			if stop_when.is_valid() and stop_when.call():
				return ""
			var to: Vector3 = target - player.global_position
			var flat := Vector2(to.x, to.z)
			if flat.length() < 0.7:
				break
			player.rotation.y = atan2(-to.x, -to.z)
			Input.action_press("move_forward")
			await tree.physics_frame
			if flat.length() < best - 0.05:
				best = flat.length()
				stalled = 0.0
			else:
				stalled += get_physics_dt()
				if stalled > 2.0:  # two game-seconds without getting closer
					Input.action_release("move_forward")
					return "stuck at %s heading for %s" % [player.global_position.snapped(Vector3.ONE * 0.01), target]
	Input.action_release("move_forward")
	return ""


func _settle() -> void:
	Input.action_release("move_forward")
	for i in 240:
		await tree.physics_frame
		if Vector2(player.velocity.x, player.velocity.z).length() < 0.05:
			return


## The real check for "can I talk to them from here": stand still, look at them
## (at `height` above their origin), see if they get focus.
func _can_focus(id: String, height: float) -> bool:
	await _settle()
	var t = director._target_node(id)
	player.look_toward(t.global_position + Vector3(0, height, 0), 0.01)
	await physics_frames(4)
	return player.focus == t


func get_physics_dt() -> float:
	return 1.0 / Engine.physics_ticks_per_second * Engine.time_scale


func test_entrance_to_castle_foyer_day1() -> void:
	await _open("S01_Arrival", 1)
	var narrative := tree.root.get_node("Narrative")
	var fainted := func(): return narrative.engine.pending_faint != ""
	var stuck := await _walk([
		Vector3(2.5, 0, 50),  # through the entrance arch
		Vector3(2.5, 0, -10),  # past the well, east of it
		Vector3(2.5, 6, -42),  # up the ramp to the gate
		Vector3(2.5, 6, -52),  # into the foyer
	], fainted)
	assert_eq(stuck, "", "route blocked")
	assert_eq(narrative.engine.pending_faint, "CastleInterior", "walking in ends day 1")
	await _close()


func test_square_to_bartender() -> void:
	await _open("S01_Arrival", 1)
	var stuck := await _walk([Vector3(-8, 0, -2), Vector3(-16, 0, -2), Vector3(-22.6, 0, -2)])
	assert_eq(stuck, "", "tavern route blocked")
	assert_true(await _can_focus("bartender", 1.3), "bartender reachable across the counter")
	await _close()


func test_square_to_firewood() -> void:
	await _open("S01_Arrival", 1)
	var stuck := await _walk([Vector3(-6, 0, 22), Vector3(-12.4, 0, 24.5)])
	assert_eq(stuck, "", "smithy route blocked")
	assert_true(await _can_focus("firewood", 0.5), "firewood in reach")
	await _close()


func test_square_to_guard_day2() -> void:
	await _open("S02_GateClosed", 2)
	var stuck := await _walk([Vector3(2.5, 0, 50), Vector3(2.5, 0, -10), Vector3(3.8, 6, -40.3)])
	assert_eq(stuck, "", "gate route blocked")
	assert_true(await _can_focus("guard", 1.3), "guard reachable")
	stuck = await _walk([Vector3(1.5, 6, -42.4)])
	assert_eq(stuck, "", "can walk up to the closed gate")
	assert_true(await _can_focus("gate", 2.0), "closed gate reachable (day 2 faint trigger)")
	await _close()


func _obstacle(height: float, z: float) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = Vector3(5, height, 2)
	b.position = Vector3(2.5, height / 2, z)
	b.use_collision = true
	village.add_child(b)
	return b


func test_low_ledge_is_climbed_without_jumping() -> void:
	await _open("S01_Arrival", 1)
	_obstacle(0.2, 40.0)  # a 20 cm kerb across the road
	await physics_frames(2)
	var stuck := await _walk([Vector3(2.5, 0, 50), Vector3(2.5, 0.2, 40), Vector3(2.5, 0, 30)])
	assert_eq(stuck, "", "a 20 cm ledge must not strand the player")
	await _close()


func test_waist_high_obstacle_still_blocks() -> void:
	await _open("S01_Arrival", 1)
	_obstacle(0.9, 40.0)  # counter / fence height
	await physics_frames(2)
	var stuck := await _walk([Vector3(2.5, 0, 50), Vector3(2.5, 0, 30)])
	assert_true(stuck != "", "the player must not climb waist-high things")
	await _close()
