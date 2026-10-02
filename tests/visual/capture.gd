extends SceneTree
## Renders the village at a given story stage from a named viewpoint and saves a PNG.
## Used by the AI to check layout/sightlines without a GPU; never touches the save.
## Note: --script entry points are compiled before autoloads exist, so they must not
## reference game classes that use the Narrative autoload (e.g. BTGPlayer) by type.
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tests/visual/capture.gd -- --stage S02_GateClosed --cycle 2 --view spawn --out shot.png

## view -> [feet position, point to look at]
const VIEWS := {
	"spawn": [Vector3(0, 0, 63), Vector3(0, 8, -46)],
	"square": [Vector3(0, 0, 12), Vector3(0, 8, -46)],
	"gate": [Vector3(0, 6, -32), Vector3(0, 10, -46)],
	"foyer": [Vector3(0, 6, -41), Vector3(0, 8, -60)],
	"tavern": [Vector3(-16.4, 0, -0.5), Vector3(-25, 1.3, -2)],
	"smithy": [Vector3(-7, 0, 27), Vector3(-14.2, 0.6, 24.5)],
	"sign": [Vector3(-4, 0, 9), Vector3(-13.7, 3.9, 1.6)],
	"overview": [Vector3(34, 14, 48), Vector3(-2, 2, -12)],
}


func _initialize() -> void:
	var args := _args()
	await process_frame
	var narrative := root.get_node("Narrative")
	narrative.autosave = false
	var state := BTGStoryState.new_game(narrative.db.start_stage)
	state.stage = args.get("stage", state.stage)
	state.cycle = int(args.get("cycle", "1"))
	narrative.use_state(state)
	var village: Node = load("res://scenes/village.tscn").instantiate()
	root.add_child(village)
	for i in 5:
		await process_frame
	var view: Array = VIEWS[args.get("view", "spawn")]
	var player = village.get_node("Player")  # untyped: see note at top
	player.set_physics_process(false)
	player.global_position = view[0]
	player.rotation = Vector3.ZERO
	player.camera.look_at(view[1])
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var out: String = args.get("out", "user://capture.png")
	var err := root.get_viewport().get_texture().get_image().save_png(out)
	print("captured %s (%s, %s) -> %s" % [args.get("view", "spawn"), state.stage, error_string(err), out])
	quit(0 if err == OK else 1)


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in range(0, a.size() - 1, 2):
		out[a[i].trim_prefix("--")] = a[i + 1]
	return out
