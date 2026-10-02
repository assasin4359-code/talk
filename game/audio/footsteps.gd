class_name BTGFootsteps
extends Node
## Every player footstep goes through here (handoff §16): one place to later delay
## steps, add an extra step after the player stops, mix in laughter, or drop them
## entirely inside the castle. Child of the player's CharacterBody3D.
##
## Surface comes from a "surface" meta on whatever is under the feet (set by the
## blockout generator); anything unmarked counts as dirt.

signal stepped(surface: String)

@export var sets: Dictionary = {}  ## surface name -> BTGSoundSet
## Metres travelled per footstep. Game walking (4.2 m/s) is ~3x real walking speed,
## so this is a feel number, not a real stride: 2.0 m -> one step every ~0.48 s.
## (0.62 gave ~7 steps/s at a walk — "탁탁탁탁", owner playtest.)
@export var stride := 2.0
@export var sprint_stride := 0.9  ## ~7 steps/s at 6.5 m/s; the owner found running fine
@export var sprint_threshold := 5.0  ## m/s

var _travel := 0.0
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer
@onready var _body: CharacterBody3D = get_parent()


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.max_polyphony = 2
	add_child(_player)


func _physics_process(delta: float) -> void:
	if not _body.is_on_floor():
		return
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if speed < 0.3:
		_travel = stride * 0.5  # the first step after standing comes quickly
		return
	_travel += speed * delta
	var length := sprint_stride if speed > sprint_threshold else stride
	if _travel >= length:
		_travel -= length
		step()


func step() -> void:
	var surface := surface_under()
	stepped.emit(surface)
	var set: BTGSoundSet = sets.get(surface, sets.get("dirt"))
	if set != null:
		set.play_on(_player, _rng)


func surface_under() -> String:
	var from := _body.global_position + Vector3(0, 0.3, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -0.8, 0))
	query.exclude = [_body.get_rid()]
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	var n: Node = hit.get("collider") if not hit.is_empty() else null
	while n != null:
		if n.has_meta("surface"):
			return str(n.get_meta("surface"))
		n = n.get_parent()
	return "dirt"
