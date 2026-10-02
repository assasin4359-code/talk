class_name BTGStoryState
extends RefCounted
## Everything that survives a faint, plus the current cycle's scratch flags.
## Serialised shape is identical to btg_narrative/state.py (and is the save payload).

var cycle := 1
var stage := ""
var flags := {}  # persistent flag id -> true
var cycle_flags := {}  # cleared when the cycle ends
var seen := {}  # beat id -> Array[int] of cycles it was started in
var rel := {}  # "npc.Event" -> Array[int] of cycles it happened in
var history: Array = []  # [{cycle, stage, ended}]


static func new_game(start_stage: String) -> BTGStoryState:
	var s := BTGStoryState.new()
	s.stage = start_stage
	return s


static func _add_cycle(table: Dictionary, key: String, c: int) -> void:
	if not table.has(key):
		table[key] = []
	if not table[key].has(c):
		table[key].append(c)
		table[key].sort()


func mark_seen(beat_id: String) -> void:
	_add_cycle(seen, beat_id, cycle)


## One record per (npc, event, cycle): counts mean "on how many days".
func record_rel(npc: String, event: String) -> void:
	_add_cycle(rel, "%s.%s" % [npc, event], cycle)


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


func to_dict() -> Dictionary:
	var seen_out := {}
	for k in _sorted_keys(seen):
		seen_out[k] = seen[k].duplicate()
	var rel_out := {}
	for k in _sorted_keys(rel):
		rel_out[k] = rel[k].duplicate()
	return {
		"cycle": cycle,
		"stage": stage,
		"flags": _sorted_keys(flags),
		"cycleFlags": _sorted_keys(cycle_flags),
		"seen": seen_out,
		"rel": rel_out,
		"history": history.duplicate(true),
	}


static func _int_list(v: Variant) -> Array:
	var out: Array = []
	for x in v:
		out.append(int(x))
	out.sort()
	return out


## Returns null if the dictionary is not a valid state.
static func from_dict(d: Variant) -> BTGStoryState:
	if not d is Dictionary:
		return null
	var c: Variant = d.get("cycle")
	var st: Variant = d.get("stage")
	if not (c is int or c is float) or int(c) < 1 or not st is String or st == "":
		return null
	var s := BTGStoryState.new()
	s.cycle = int(c)
	s.stage = st
	for f in d.get("flags", []):
		s.flags[str(f)] = true
	for f in d.get("cycleFlags", []):
		s.cycle_flags[str(f)] = true
	var seen_in: Variant = d.get("seen", {})
	for k in seen_in:
		s.seen[k] = _int_list(seen_in[k])
	var rel_in: Variant = d.get("rel", {})
	for k in rel_in:
		s.rel[k] = _int_list(rel_in[k])
	for h in d.get("history", []):
		s.history.append({"cycle": int(h.get("cycle", 0)), "stage": str(h.get("stage", "")), "ended": str(h.get("ended", ""))})
	return s
