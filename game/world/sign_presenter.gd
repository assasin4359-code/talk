extends Node
## Shows world value tavern_sign.state: "upside_down" flips the board.

@export var board: Node3D


func _ready() -> void:
	get_parent().world_value_changed.connect(_on_value)


func _on_value(prop: String, value: String) -> void:
	if prop == "state":
		board.rotation_degrees.z = 180.0 if value == "upside_down" else 0.0
