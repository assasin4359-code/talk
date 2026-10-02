class_name BTGAnchor
extends Marker3D
## A place that world values `location` / `spawn` can point to (GameData/world.json anchors).
## GameData stays coarse ("gate"); `for_target` gives each character its own exact spot
## at that place (the guard's post vs. the gate itself).

@export var anchor_id := ""
@export var for_target := ""


func _ready() -> void:
	add_to_group("btg_anchors")


static func find(tree: SceneTree, id: String, target_id: String) -> BTGAnchor:
	var fallback: BTGAnchor = null
	for a in tree.get_nodes_in_group("btg_anchors"):
		if a.anchor_id != id:
			continue
		if a.for_target == target_id:
			return a
		if a.for_target == "" and fallback == null:
			fallback = a
	return fallback
