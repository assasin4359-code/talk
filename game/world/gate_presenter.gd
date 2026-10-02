extends Node
## Shows world value gate.state: the two leaves swing inward when open, meet when closed.
## Child of the gate's BTGNarrativeTarget.

@export var left_hinge: Node3D
@export var right_hinge: Node3D
@export var open_angle := 95.0


func _ready() -> void:
	get_parent().world_value_changed.connect(_on_value)


func _on_value(prop: String, value: String) -> void:
	if prop != "state":
		return
	var open := value != "closed"
	left_hinge.rotation_degrees.y = open_angle if open else 0.0
	right_hinge.rotation_degrees.y = -open_angle if open else 0.0
