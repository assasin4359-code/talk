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
## There is no jump (by design). Ledges up to this height are climbed automatically,
## so a stray kerb or stair never strands the player; waist-high things still block.
@export var max_step_height := 0.3

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
	BTGInput.capture_mouse(true)


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


func place_at(anchor: Node3D) -> void:
	global_position = anchor.global_position
	rotation.y = anchor.global_rotation.y
	head.rotation = Vector3.ZERO
	head.position.y = _head_height
	velocity = Vector3.ZERO


## Esc / alt-tab / losing the mouse open the game menu (game/ui/game_menu.gd), which
## releases the cursor; closing it takes the mouse back.
func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseMotion:
		if BTGInput.is_captured():
			rotate_y(-event.relative.x * mouse_sensitivity)
			head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sensitivity, -1.45, 1.45)
		return
	if event is InputEventMouseButton and event.pressed and not BTGInput.is_captured():
		BTGInput.capture_mouse(true)  # click into the window: mouse-look again, not an interaction
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and focus != null:
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
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and wish != Vector3.ZERO:
		_step_up(horizontal * delta)
	_update_focus()


## If a low ledge stopped us: lift by max_step_height, move on, drop back down onto it.
func _step_up(motion: Vector3) -> void:
	var blocked := false
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().y < 0.7:
			blocked = true
	if not blocked or motion.length() < 0.0001:
		return
	var up := Vector3(0, max_step_height, 0)
	var start := global_transform
	if test_move(start, up):
		return  # no headroom
	var raised := start.translated(up)
	if test_move(raised, motion):
		return  # still blocked one step higher: a real wall
	var moved := raised.translated(motion)
	var landing := KinematicCollision3D.new()
	if not test_move(moved, -up, landing) or landing.get_normal().y < 0.7:
		return  # nothing to stand on (or too steep)
	var target := moved.origin + landing.get_travel()
	if target.y - start.origin.y > 0.01:
		global_position = target


func _update_focus() -> void:
	var t: BTGNarrativeTarget = null
	if not input_locked and ray.is_colliding():
		t = BTGNarrativeTarget.from_collider(ray.get_collider())
	_set_focus(t)


func _set_focus(t: BTGNarrativeTarget) -> void:
	if t != focus:
		focus = t
		focus_changed.emit(t)
