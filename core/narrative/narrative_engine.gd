class_name BTGNarrativeEngine
extends RefCounted
## The narrative core: picks beats, applies effects, resolves world state, ends cycles.
## Knows nothing about rendering — it emits cue names and dialogue events.
## Behaviour must match Tools/narrative/btg_narrative/engine.py (shared scenario tests).

signal cue_emitted(cue: String)

var db: BTGNarrativeDB
var state: BTGStoryState
var pending_faint := ""  # "" = none
var cue_log := PackedStringArray()

var cycle: int:
	get:
		return state.cycle


func _init(p_db: BTGNarrativeDB, p_state: BTGStoryState = null) -> void:
	db = p_db
	state = p_state if p_state != null else BTGStoryState.new_game(db.start_stage)
	if not db.stages.has(state.stage):
		push_error("Story state refers to unknown stage '%s'; starting over." % state.stage)
		state = BTGStoryState.new_game(db.start_stage)


# --- condition context ------------------------------------------------------

func has_flag(flag: String) -> bool:
	return state.flags.has(flag) or state.cycle_flags.has(flag)


func current_stage_index() -> int:
	return db.stages[state.stage].index


func stage_index(stage_id: String) -> int:
	return db.stages[stage_id].index


func seen_cycles(beat_id: String) -> Array:
	return state.seen.get(beat_id, [])


func rel_cycles(npc: String, event: String) -> Array:
	return state.rel.get("%s.%s" % [npc, event], [])


## Baseline, then every matching rule in file order: later rules win.
## World rules may not use world: atoms (validator enforces), so no recursion.
func world_value(target: String, prop: String) -> Variant:
	var key := "%s.%s" % [target, prop]
	var value: Variant = db.world_baseline.get(key)
	for rule in db.world_rules:
		if rule.target == target and rule.prop == prop and check(rule.when):
			value = rule.value
	return value


# --- queries ----------------------------------------------------------------

func check(conds: Array) -> bool:
	return BTGCondition.all_true(conds, self)


func is_available(beat: BTGNarrativeDB.Beat) -> bool:
	var seen := seen_cycles(beat.id)
	if beat.once == "story" and not seen.is_empty():
		return false
	if beat.once == "cycle" and seen.has(cycle):
		return false
	return check(beat.when)


## Highest priority first; ties go to whichever was written first.
func candidates(verb: String, target: String) -> Array:
	var list := db.beats_for(verb, target)
	list.sort_custom(func(a, b): return a.priority > b.priority or (a.priority == b.priority and a.order < b.order))
	return list


func select_beat(verb: String, target: String) -> BTGNarrativeDB.Beat:
	for beat in candidates(verb, target):
		if is_available(beat):
			return beat
	return null


## Debug: why does (verb, target) pick the beat it picks?
func explain(verb: String, target: String) -> PackedStringArray:
	var out := PackedStringArray()
	var chosen := select_beat(verb, target)
	for beat in candidates(verb, target):
		var why := "ok"
		var seen := seen_cycles(beat.id)
		if beat.once == "story" and not seen.is_empty():
			why = "already seen (once: story)"
		elif beat.once == "cycle" and seen.has(cycle):
			why = "already seen this cycle (once: cycle)"
		else:
			var bad := BTGCondition.failing(beat.when, self)
			if not bad.is_empty():
				why = "fails " + ", ".join(bad.map(func(c): return c.source))
		out.append("%s [%3d] %s: %s" % [">>" if beat == chosen else "  ", beat.priority, beat.id, why])
	if out.is_empty():
		out.append("   (no beats for %s:%s)" % [verb, target])
	return out


# --- actions ----------------------------------------------------------------

func trigger(verb: String, target: String) -> BTGDialogueSession:
	if pending_faint != "":
		return null  # the cycle is already ending
	var beat := select_beat(verb, target)
	if beat == null:
		return null
	if verb == "talk":
		state.record_rel(target, "Talked")
	return BTGDialogueSession.new(self, beat)


func emit_cue(cue: String) -> void:
	cue_log.append(cue)
	cue_emitted.emit(cue)


func apply_effects(effects: Array) -> void:
	for e in effects:
		match e.kind:
			"set":
				if db.flags.get(e.key, "persistent") == "cycle":
					state.cycle_flags[e.key] = true
				else:
					state.flags[e.key] = true
			"clear":
				state.flags.erase(e.key)
				state.cycle_flags.erase(e.key)
			"rel":
				state.record_rel(e.key, e.sub)
			"cue":
				emit_cue(e.key)
			"faint":
				if pending_faint == "":
					pending_faint = e.key


## Call after the faint presentation has finished. Advances to the next day.
## Returns {ended_cycle, reason, from_stage, to_stage, terminal}.
func complete_cycle() -> Dictionary:
	if pending_faint == "":
		push_error("complete_cycle() called without a pending faint")
		return {}
	var reason := pending_faint
	var from_stage := state.stage
	var to_stage := from_stage
	for t in db.stages[from_stage].transitions:
		if t.reason != "" and t.reason != reason:
			continue
		if check(t.when):  # evaluated in the dying cycle, cycle flags still set
			to_stage = t.to
			break
	state.history.append({"cycle": state.cycle, "stage": from_stage, "ended": reason})
	var ended := state.cycle
	state.cycle += 1
	state.cycle_flags.clear()
	state.stage = to_stage
	pending_faint = ""
	return {
		"ended_cycle": ended,
		"reason": reason,
		"from_stage": from_stage,
		"to_stage": to_stage,
		"terminal": db.stages[to_stage].terminal,
	}
