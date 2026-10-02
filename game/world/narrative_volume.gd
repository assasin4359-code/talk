class_name BTGNarrativeVolume
extends Area3D
## Fires `enter:<volume_id>` when the player walks in (e.g. the castle foyer).

@export var volume_id := ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		var director := get_tree().get_first_node_in_group("btg_director")
		if director != null:
			director.request("enter", volume_id)
