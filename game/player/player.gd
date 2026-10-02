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


var _head_height := 1.62


func _ready() -> void:
	add_to_group("player")
	BTGInput.ensure_actions()
	_head_height = head.position.y
	ray.target_position = Vector3(0, 0, -interact_range)
	ray.add_exception(self)
	capture_mouse(true)


# --- camera moves the director uses (presentation only) -------------------------

func look_toward(point: Vector3, seconds: float) -> void:
	var d := point - camera.global_position
	var yaw := atan2(-d.x, -d.z)
	var pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.45, 1.45)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, yaw), seconds)
	t.tween_property(head, "rotation:x", pitch, seconds)


## Unsteady, then down onto one side.
func collapse(duration: float) -> void:
	var t := create_tween()
	for i in 4:
		t.tween_property(head, "rotation:z", 0.06 * (1 if i % 2 == 0 else -1), duration * 0.08)
	t.set_parallel()
	t.tween_property(head, "position:y", 0.32, duration * 0.4).set_delay(duration * 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(head, "rotation:z", 1.2, duration * 0.4).set_delay(duration * 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(head, "rotation:x", -0.25, duration * 0.4).set_delay(duration * 0.32)


func lie_down() -> void:
	head.position.y = 0.32
	head.rotation = Vector3(0.45, 0.0, 1.2)


func get_up(seconds: float) -> Tween:
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(head, "position:y", _head_height, seconds * 0.7).set_delay(seconds * 0.3)
	t.tween_property(head, "rotation:z", 0.0, seconds * 0.6).set_delay(seconds * 0.2)
	t.tween_property(head, "rotation:x", 0.0, seconds)
	return t


func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func place_at(anchor: Node3D) -> void:
	global_position = anchor.global_position
	rotation.y = anchor.global_rotation.y
	head.rotation = Vector3.ZERO
	head.position.y = _head_height
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
