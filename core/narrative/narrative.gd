extends Node
## Autoload "Narrative": the game's single story authority (in fiction, the narrator's desk).
## Owns the engine and the save. Presentation scenes talk to this node and react to
## its signals; they never decide story state themselves.

signal cue_emitted(cue: String)
## World values may have changed (flags/relationships/cycle changed). Targets re-read them.
signal world_changed
signal cycle_started(cycle: int, stage: String)

const DATA_ROOT := "res://GameData"
const SAVE_BASE := "user://saves/slot0"

var db: BTGNarrativeDB
var engine: BTGNarrativeEngine
## Set by complete_cycle(); the next village scene plays the wake-up instead of the arrival.
var just_woke := false
## Tests and capture tools turn this off so they never touch the player's save.
var autosave := true


func _ready() -> void:
	db = BTGNarrativeDB.load_from(DATA_ROOT)
	for e in db.errors:
		push_error("GameData: " + e)
	var loaded := BTGSaveSystem.load_newest(SAVE_BASE)
	_use_engine(BTGNarrativeEngine.new(db, loaded["state"]))
	just_woke = engine.cycle > 1  # continuing a saved game starts at a wake-up


func _use_engine(e: BTGNarrativeEngine) -> void:
	engine = e
	engine.cue_emitted.connect(func(cue): cue_emitted.emit(cue))
	engine.state_changed.connect(func(): world_changed.emit())


## Replaces the story state (new game, debug jumps, tests). Does not save.
func use_state(state: BTGStoryState) -> void:
	_use_engine(BTGNarrativeEngine.new(db, state))
	just_woke = false
	world_changed.emit()


func new_game() -> void:
	use_state(null)
	checkpoint()


## Saves the start-of-cycle checkpoint (the only save point in the vertical slice).
func checkpoint() -> void:
	if not autosave:
		return
	var err := BTGSaveSystem.write(SAVE_BASE, engine.state)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))


func trigger(verb: String, target: String) -> BTGDialogueSession:
	return engine.trigger(verb, target)


func world_value(target: String, prop: String) -> Variant:
	return engine.world_value(target, prop)


func target_name(target_id: String) -> String:
	return db.targets.get(target_id, {}).get("name", target_id)


## Called by the presentation layer once the faint sequence has finished playing.
func complete_cycle() -> Dictionary:
	var result := engine.complete_cycle()
	just_woke = true
	checkpoint()
	cycle_started.emit(engine.cycle, engine.state.stage)
	return result
