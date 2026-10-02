class_name BTGDirector
extends Node
## Scene-level presentation coordinator for the village:
##   player action -> Narrative.trigger() -> conversation -> (faint -> next day)
## It owns presentation only. Every story decision comes from the Narrative autoload.

@export var player: BTGPlayer

var hud: BTGHud
var busy := false  # a conversation or the faint sequence is running


func _ready() -> void:
	add_to_group("btg_director")
	hud = BTGHud.new()
	add_child(hud)
	player.focus_changed.connect(hud.show_target)
	_spawn_player.call_deferred()


func _spawn_player() -> void:
	var spawn: Variant = Narrative.world_value("player", "spawn")
	var anchor := BTGAnchor.find(get_tree(), spawn if spawn is String else "", "player")
	if anchor != null:
		player.place_at(anchor)


## Entry point for the player and for volumes.
func request(verb: String, target_id: String) -> void:
	if busy:
		return
	var session := Narrative.trigger(verb, target_id)
	if session == null:
		return
	_run_session(session)


## Placeholder until the dialogue box lands: logs the conversation and takes the
## first option. Replaced in the next step.
func _run_session(session: BTGDialogueSession) -> void:
	while true:
		var ev := session.advance()
		match ev["type"]:
			"line":
				print("%s: %s" % [Narrative.target_name(ev["speaker"]), ev["text"]])
			"choices":
				session.choose(0)
			"end":
				if ev["faint"] != "":
					print("(faint: %s)" % ev["faint"])
				return
