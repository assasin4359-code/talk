extends BTGTest
## Audio wiring. The container has no sound card, so this checks everything up to the
## speaker: which sound fires, when, on which bus, from which file. How it SOUNDS is
## the owner's call.

const VILLAGE := "res://scenes/village.tscn"
const BUSES := {
	"World": "Master", "Ambient": "World", "Footsteps": "World", "SFX": "World",
	"Voice": "Master", "NPCVoice": "Voice", "Narrator": "Voice", "UI": "Master", "Music": "Master",
}

var village: Node
var director
var player


func _open(stage := "S01_Arrival", cycle := 1) -> void:
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
	village.queue_free()
	await frames(3)


func test_buses_exist_and_route_correctly() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		assert_true(i >= 0, "bus %s missing" % bus)
		if i >= 0:
			assert_eq(String(AudioServer.get_bus_send(i)), BUSES[bus], "%s sends to" % bus)


func test_every_npc_has_a_voice_profile() -> void:
	var db: BTGNarrativeDB = tree.root.get_node("Narrative").db
	for id in db.targets:
		var t: Dictionary = db.targets[id]
		if t["kind"] != "npc":
			continue
		var path := BTGFakeVoice.VOICE_DIR % t["voice"]
		assert_true(ResourceLoader.exists(path), "%s: no voice profile %s" % [id, path])
		var p = load(path) if ResourceLoader.exists(path) else null
		assert_true(p is BTGVoiceProfile, "%s: not a BTGVoiceProfile" % path)
		if p is BTGVoiceProfile:
			assert_eq(p.samples.size(), 5, "%s: five vowel blips (a e i o u)" % path)
			assert_eq(p.bus, &"NPCVoice", "%s bus" % path)


func test_hangul_vowels_pick_blips() -> void:
	var cases := {"가": 0, "개": 1, "기": 2, "고": 3, "구": 4, "그": 4, "어": 3, "의": 2, "왜": 1, "쉬": 2}
	for ch in cases:
		assert_eq(BTGFakeVoice.vowel_of(ch), cases[ch], "vowel of %s" % ch)
	for silent in [" ", "…", "?", ".", ",", "!", ""]:
		assert_eq(BTGFakeVoice.vowel_of(silent), -1, "'%s' is silent" % silent)
	assert_eq(BTGFakeVoice.vowel_of("a"), BTGFakeVoice.vowel_of("a"), "latin letters are stable")


func test_speech_rates_follow_profiles() -> void:
	await _open()
	var v: BTGFakeVoice = director.voice
	assert_true(v.chars_per_second("guard") < v.chars_per_second("bartender"), "guard talks slower than the bartender")
	assert_eq(v.chars_per_second("player"), BTGFakeVoice.DEFAULT_CPS, "the player has no voice")
	await _close()


func test_one_blip_per_spoken_syllable() -> void:
	await _open("S02_GateClosed", 2)
	tree.root.get_node("Narrative").engine.state.flags["EnteredCastle"] = true
	var box: BTGDialogueBox = director.dialogue
	box.pace = func(_s): return 4000.0  # typewriter as fast as frames allow
	box.autoplay = ["……아무것도"]
	var blips := {}
	director.voice.blipped.connect(func(speaker, _v): blips[speaker] = blips.get(speaker, 0) + 1)
	var done := [false]
	director.conversation_finished.connect(func(): done[0] = true, CONNECT_ONE_SHOT)
	director.request("talk", "guard")
	for i in 3000:
		if done[0]:
			break
		await frames(1)
	assert_true(done[0], "conversation finished")
	var expected := 0
	for line in box.transcript:
		if line[0] == "guard":
			for ch in line[1]:
				if BTGFakeVoice.vowel_of(ch) >= 0:
					expected += 1
	assert_true(expected > 10, "guard said something")
	assert_eq(blips.get("guard", 0), expected, "one blip per guard syllable")
	assert_eq(blips.get("player", 0), 0, "the player's line is silent")
	await _close()


func test_surfaces_under_feet() -> void:
	await _open()
	var steps = player.get_node("Footsteps")
	player.set_physics_process(false)
	var spots := {
		"dirt": Vector3(1.5, 0.1, 40),  # main road
		"stone": Vector3(6, 0.1, 6),  # plaza
		"wood": Vector3(-19, 0.1, 0),  # tavern floor
	}
	for surface in spots:
		player.global_position = spots[surface]
		await physics_frames(2)
		assert_eq(steps.surface_under(), surface, "surface at %s" % spots[surface])
	player.global_position = Vector3(0, 6.1, -51)  # castle foyer
	await physics_frames(2)
	assert_eq(steps.surface_under(), "stone", "foyer floor")
	await _close()


## Average seconds between footsteps while holding forward (+ optional sprint).
func _step_interval(sprint: bool) -> float:
	var frames_at: Array[int] = []
	var tick := [0]
	var steps = player.get_node("Footsteps")
	var on_step := func(_s): frames_at.append(tick[0])
	steps.stepped.connect(on_step)
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	for i in 180:  # 3 s
		await physics_frames(1)
		tick[0] += 1
	Input.action_release("move_forward")
	Input.action_release("sprint")
	steps.stepped.disconnect(on_step)
	var gaps := frames_at.slice(2)  # skip the start-up steps
	if gaps.size() < 2:
		return INF
	return float(gaps[-1] - gaps[0]) / (gaps.size() - 1) / Engine.physics_ticks_per_second


func test_walking_cadence() -> void:
	await _open()
	var walk := await _step_interval(false)
	assert_true(walk >= 0.4 and walk <= 0.6, "a walking step every ~0.5 s, not 탁탁탁탁 (got %.2f s)" % walk)
	await physics_frames(30)
	var run := await _step_interval(true)
	assert_true(run < walk * 0.6, "running steps come much faster (walk %.2f s, run %.2f s)" % [walk, run])
	await _close()


func test_standing_still_is_silent() -> void:
	await _open()
	Input.action_press("move_forward")
	await physics_frames(60)
	Input.action_release("move_forward")
	await physics_frames(20)  # coming to a stop
	var count := [0]
	player.get_node("Footsteps").stepped.connect(func(_s): count[0] += 1)
	await physics_frames(120)
	assert_eq(count[0], 0, "no steps while standing")
	await _close()


func test_ambience_files_loop() -> void:
	for path in ["res://assets/audio/placeholder/ambience/wind_loop.wav", "res://assets/audio/placeholder/ambience/fire_loop.wav"]:
		var s: AudioStreamWAV = load(path)
		assert_true(s != null and s.loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s loops" % path)
