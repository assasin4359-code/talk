extends SceneTree
## Renders the village at a given story stage from a named viewpoint and saves a PNG.
## Used by the AI to check layout/sightlines without a GPU; never touches the save.
## Note: --script entry points are compiled before autoloads exist, so they must not
## reference game classes that use the Narrative autoload (e.g. BTGPlayer) by type.
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tests/visual/capture.gd -- --stage S02_GateClosed --cycle 2 --view spawn --out shot.png
## Optional: --talk guard --hold 4  -> start that conversation and photograph its 4th line.
##           --flags EnteredCastle,MetGuard  -> persistent flags in the story state.

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
	"guard_talk": [Vector3(4.8, 6, -38.6), Vector3(5.6, 7.5, -41.0)],
	"bartender_talk": [Vector3(-21.8, 0, -1.6), Vector3(-24.6, 1.5, -2)],
}


func _initialize() -> void:
	var args := _args()
	await process_frame
	var narrative := root.get_node("Narrative")
	narrative.autosave = false
	var state := BTGStoryState.new_game(narrative.db.start_stage)
	state.stage = args.get("stage", state.stage)
	state.cycle = int(args.get("cycle", "1"))
	for f in str(args.get("flags", "")).split(",", false):
		state.flags[f] = true
	narrative.use_state(state)
	var village: Node = load("res://scenes/village.tscn").instantiate()
	var director = village.get_node("Director")  # untyped: see note at top
	director.speed = 100.0
	director.reload_on_new_day = false
	root.add_child(village)
	await director.day_started
	var view: Array = VIEWS[args.get("view", "spawn")]
	var player = village.get_node("Player")
	player.set_physics_process(false)
	player.global_position = view[0]
	player.rotation = Vector3.ZERO
	player.look_toward(view[1], 0.01)  # same camera rig as gameplay (body yaw + head pitch)
	for i in 3:
		await process_frame
	if args.has("talk"):
		director.dialogue.instant = true
		director.dialogue.autoplay = []
		director.dialogue.autoplay_hold_at = int(args.get("hold", "1"))
		director.request("talk", args["talk"])
	for i in 12:
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
