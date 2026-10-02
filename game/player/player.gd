class_name BTGPlayer
extends CharacterBody3D
## First-person walker. Looks at narrative targets through a short ray and asks the
## scene director to act on them. Knows nothing about the story.

signal focus_changed(target: BTGNarrativeTarget)

@export var walk_speed := 4.2
@export var sprint_speed := 6.5
@export var acceleration := 14.0
@export var mouse_sensitivity := 0.0025
@export var interact_range := 2.6

var input_locked := false:
	set(v):
		input_locked = v
		if v:
			_set_focus(null)
var focus: BTGNarrativeTarget = null

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay


func _ready() -> void:
	add_to_group("player")
	BTGInput.ensure_actions()
	ray.target_position = Vector3(0, 0, -interact_range)
	ray.add_exception(self)
	capture_mouse(true)


func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func place_at(anchor: Node3D) -> void:
	global_position = anchor.global_position
	rotation.y = anchor.global_rotation.y
	head.rotation.x = 0.0
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		return
	if input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sensitivity, -1.45, 1.45)
	elif event.is_action_pressed("interact") and focus != null:
		get_viewport().set_input_as_handled()
		interact(focus)


func interact(target: BTGNarrativeTarget) -> void:
	var director := get_tree().get_first_node_in_group("btg_director")
	if director != null:
		director.request(target.verb, target.target_id)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var wish := Vector3.ZERO
	if not input_locked:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = (transform.basis * Vector3(v.x, 0.0, v.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_update_focus()


func _update_focus() -> void:
	var t: BTGNarrativeTarget = null
	if not input_locked and ray.is_colliding():
		t = BTGNarrativeTarget.from_collider(ray.get_collider())
	_set_focus(t)


func _set_focus(t: BTGNarrativeTarget) -> void:
	if t != focus:
		focus = t
		focus_changed.emit(t)
