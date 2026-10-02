class_name BTGNarrativeTarget
extends Node3D
## Gives a scene node a GameData target id ("guard", "gate", "firewood").
## - The player's interaction ray finds it through any collision child.
## - World values for it are pushed in: `location` moves it to an anchor (if
##   follow_location), `visible` hides it, everything else goes out through
##   world_value_changed for presenter scripts to show.
## It never decides anything: values come from the Narrative autoload.

signal world_value_changed(prop: String, value: String)

@export var target_id := ""
@export var verb := "talk"  ## talk | use
@export var follow_location := false
@export var watched_props := PackedStringArray()


func _ready() -> void:
	add_to_group("btg_targets")
	Narrative.world_changed.connect(refresh)
	refresh.call_deferred()  # anchors elsewhere in the scene may not be ready yet


func display_name() -> String:
	return Narrative.target_name(target_id)


func refresh() -> void:
	if not is_inside_tree():
		return
	if follow_location:
		var loc: Variant = Narrative.world_value(target_id, "location")
		if loc is String:
			var anchor := BTGAnchor.find(get_tree(), loc, target_id)
			if anchor != null:
				global_transform = anchor.global_transform
	var vis: Variant = Narrative.world_value(target_id, "visible")
	if vis is String:
		_set_present(vis != "false")
	for prop in watched_props:
		var v: Variant = Narrative.world_value(target_id, prop)
		world_value_changed.emit(prop, v if v is String else "")


func _set_present(present: bool) -> void:
	visible = present
	for shape in find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", not present)


## Walks up from whatever a ray hit to the target that owns it.
static func from_collider(collider: Object) -> BTGNarrativeTarget:
	var n := collider as Node
	while n != null:
		if n is BTGNarrativeTarget:
			return n
		n = n.get_parent()
	return null
