extends Node3D
## Generic world-value presenter: shows only the child named after the current value
## of `prop` (falls back to a child named "default"). Child of a BTGNarrativeTarget.
##   e.g. prop "state", children "low" and "full"  ->  tavern_basket.state picks one.

@export var prop := "state"


func _ready() -> void:
	get_parent().world_value_changed.connect(_on_value)


func _on_value(p: String, value: String) -> void:
	if p != prop:
		return
	var match_found := has_node(NodePath(value))
	for c in get_children():
		if c is Node3D:
			c.visible = c.name == value or (not match_found and c.name == "default")
