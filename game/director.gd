class_name BTGDirector
extends Node
## Scene-level presentation coordinator for the village (one per village scene):
##   player action -> Narrative.trigger() -> dialogue box -> (faint -> next day -> wake)
## It owns presentation only; every story decision comes from the Narrative autoload.
## A new day reloads the whole scene, so nothing here survives the night.

signal conversation_finished
signal day_started
## Emitted instead of reloading when reload_on_new_day is false (tests drive the next day).
signal day_ended(result: Dictionary)

@export var player: BTGPlayer

var hud: BTGHud
var dialogue: BTGDialogueBox
var voice: BTGFakeVoice
var fx: BTGFaintFx
var busy := true  # a conversation, the faint or the wake-up is running
var speed := 1.0  # >1 plays every presentation faster (tests)
var reload_on_new_day := true
var end_card: Label


func _ready() -> void:
	add_to_group("btg_director")
	hud = BTGHud.new()
	add_child(hud)
	dialogue = BTGDialogueBox.new()
	add_child(dialogue)
	voice = BTGFakeVoice.new()
	add_child(voice)
	dialogue.character_revealed.connect(voice.on_character)
	dialogue.pace = voice.chars_per_second
	fx = BTGFaintFx.new()
	add_child(fx)
	fx.black()
	player.focus_changed.connect(hud.show_target)
	Narrative.cue_emitted.connect(_on_cue)
	_begin_day.call_deferred()


func _seconds(s: float) -> float:
	return s / speed


func _wait(s: float) -> void:
	await get_tree().create_timer(_seconds(s)).timeout


func _lock(locked: bool) -> void:
	busy = locked
	player.input_locked = locked
	hud.set_visible_all(not locked)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_new_game"):
		Narrative.new_game()  # wipes the checkpoint to day 1
		get_tree().reload_current_scene()


# --- day start ----------------------------------------------------------------

func _begin_day() -> void:
	_lock(true)
	var spawn: Variant = Narrative.world_value("player", "spawn")
	var anchor := BTGAnchor.find(get_tree(), spawn if spawn is String else "", "player")
	if anchor != null:
		player.place_at(anchor)
	if Narrative.just_woke:
		Narrative.just_woke = false
		player.lie_down()
		var rise := player.get_up(_seconds(3.4))
		await fx.play_wake(_seconds(3.0))
		await BTGTweens.done(rise)
	else:
		await fx.fade_in(_seconds(1.6))
	_lock(false)
	day_started.emit()
	if Narrative.db.stages[Narrative.engine.state.stage].terminal:
		_watch_for_slice_end()


# --- conversations ------------------------------------------------------------

## Entry point for the player (interaction) and for volumes (enter:<id>).
func request(verb: String, target_id: String) -> void:
	if busy:
		return
	var session := Narrative.trigger(verb, target_id)
	if session == null:
		return
	_lock(true)
	if verb == "talk":
		_turn_to_player(target_id)
		player.look_toward(_target_head(target_id), _seconds(0.5))
	var faint: String = await dialogue.run(session)
	conversation_finished.emit()
	if faint != "":
		await _faint(faint)
		return
	_lock(false)


func _target_node(id: String) -> BTGNarrativeTarget:
	for t in get_tree().get_nodes_in_group("btg_targets"):
		if t.target_id == id:
			return t
	return null


func _target_head(id: String) -> Vector3:
	var t := _target_node(id)
	return t.global_position + Vector3(0, 1.5, 0) if t != null else player.global_position


func _turn_to_player(id: String) -> void:
	var t := _target_node(id)
	if t == null:
		return
	var d := player.global_position - t.global_position
	var yaw := atan2(-d.x, -d.z)
	create_tween().tween_property(t, "rotation:y", t.rotation.y + angle_difference(t.rotation.y, yaw), _seconds(0.35))


## Presentation for cues named in GameData/registry.json.
func _on_cue(cue: String) -> void:
	match cue:
		"GuardStare":
			_turn_to_player("guard")
			player.look_toward(_target_head("guard"), _seconds(0.8))
		"GuardTurnsToPlayer":
			_turn_to_player("guard")
			player.look_toward(_target_head("guard"), _seconds(0.5))
		"GateTouch":
			var gate := _target_node("gate")
			if gate != null:
				player.look_toward(gate.global_position + Vector3(0, 2.0, 0), _seconds(0.6))
		"BartenderGlancesAtHearth":
			var b := _target_node("bartender")
			if b != null:
				var base := b.rotation.y
				var t := create_tween()
				t.tween_property(b, "rotation:y", base + 0.9, _seconds(0.4))
				t.tween_interval(_seconds(0.8))
				t.tween_property(b, "rotation:y", base, _seconds(0.4))
		_:
			pass  # PickUpFirewood / HandOverFirewood are shown through world state (player.carrying)


# --- the faint ------------------------------------------------------------------

func _faint(reason: String) -> void:
	_lock(true)
	var duration := _seconds(3.4 if reason == "GateTouch" else 4.4)
	player.collapse(duration)
	await fx.play_faint(duration)
	await _wait(1.4)  # black, silence
	var result := Narrative.complete_cycle()
	if reload_on_new_day:
		get_tree().reload_current_scene()
	else:
		day_ended.emit(result)


# --- slice end (temporary) ---------------------------------------------------------

## The last stage of the vertical slice has no content yet. Let the player find the one
## change (the tavern sign) first, then say so — quietly.
func _watch_for_slice_end() -> void:
	var square := BTGAnchor.find(get_tree(), "square", "")
	var waited := 0.0
	while is_inside_tree() and waited < 90.0:
		if square != null and player.global_position.distance_to(square.global_position) < 16.0:
			break
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if not is_inside_tree():
		return
	await _wait(6.0)
	if not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	end_card = Label.new()
	end_card.text = "MILESTONE 01 — THE FIRST RETURN\n\n여기까지. 둘러보는 건 자유."
	end_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	end_card.position = Vector2(-300, 90)
	end_card.size = Vector2(600, 120)
	end_card.add_theme_font_size_override("font_size", 24)
	end_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	end_card.add_theme_constant_override("outline_size", 8)
	end_card.modulate.a = 0.0
	end_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(end_card)
	var t := create_tween()
	t.tween_property(end_card, "modulate:a", 1.0, _seconds(2.0))
	t.tween_interval(_seconds(7.0))
	t.tween_property(end_card, "modulate:a", 0.0, _seconds(2.0))
