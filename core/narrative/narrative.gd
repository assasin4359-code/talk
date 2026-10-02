extends Node
## Autoload "Narrative": the game's single story authority (in fiction, the narrator's desk).
## Owns the engine and the save. Presentation scenes talk to this node and react to
## its signals; they never decide story state themselves.

signal cue_emitted(cue: String)
signal cycle_started(cycle: int, stage: String)

const DATA_ROOT := "res://GameData"
const SAVE_BASE := "user://saves/slot0"

var db: BTGNarrativeDB
var engine: BTGNarrativeEngine


func _ready() -> void:
	db = BTGNarrativeDB.load_from(DATA_ROOT)
	for e in db.errors:
		push_error("GameData: " + e)
	var loaded := BTGSaveSystem.load_newest(SAVE_BASE)
	_use_engine(BTGNarrativeEngine.new(db, loaded["state"]))


func _use_engine(e: BTGNarrativeEngine) -> void:
	engine = e
	engine.cue_emitted.connect(func(cue): cue_emitted.emit(cue))


func new_game() -> void:
	_use_engine(BTGNarrativeEngine.new(db))
	checkpoint()


## Saves the start-of-cycle checkpoint (the only save point in the vertical slice).
func checkpoint() -> void:
	var err := BTGSaveSystem.write(SAVE_BASE, engine.state)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))


func trigger(verb: String, target: String) -> BTGDialogueSession:
	return engine.trigger(verb, target)


func world_value(target: String, prop: String) -> Variant:
	return engine.world_value(target, prop)


## Called by the presentation layer once the faint sequence has finished playing.
func complete_cycle() -> Dictionary:
	var result := engine.complete_cycle()
	checkpoint()
	cycle_started.emit(engine.cycle, engine.state.stage)
	return result
