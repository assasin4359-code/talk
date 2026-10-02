extends BTGTest
## Engine semantics on the shared synthetic fixture — mirrors Tools/narrative/tests/test_engine.py.

const FIXTURE := "res://GameData/tests/fixtures/semantics"


func _engine() -> BTGNarrativeEngine:
	var db := BTGNarrativeDB.load_from(FIXTURE)
	assert_eq(db.errors, PackedStringArray(), "fixture load errors")
	return BTGNarrativeEngine.new(db)


func _drain(session: BTGDialogueSession, picks: Array = []) -> Array:
	var out: Array = []
	while true:
		var ev := session.advance()
		out.append(ev)
		if ev["type"] == "choices":
			session.choose(picks.pop_front())
		elif ev["type"] == "end":
			return out
	return out


func _lines(events: Array) -> Array:
	return events.filter(func(e): return e["type"] == "line").map(func(e): return e["text"])


func test_priority_once_and_ties() -> void:
	var e := _engine()
	var evs := _drain(e.trigger("talk", "bob"), [1])  # "숨김" is hidden, so index 1 is "끝"
	var choices: Array = evs.filter(func(x): return x["type"] == "choices")
	assert_eq(choices[0]["options"], ["다음", "끝"], "conditional choice hidden")
	assert_eq(evs[0], {"type": "pause", "seconds": 0.5}, "pause comes first")
	assert_eq(e.cue_log, PackedStringArray(["Wave"]))
	assert_true(e.has_flag("Today"))
	# once:cycle used up; two beats tie at priority 5 -> the first written wins
	assert_eq(_lines(_drain(e.trigger("talk", "bob"))), ["먼저 쓴 것"])


func test_chain_effects_and_transition() -> void:
	var e := _engine()
	var evs := _drain(e.trigger("talk", "bob"), [0])
	assert_eq(evs[-1], {"type": "end", "faint": "Boom"})
	assert_true(e.trigger("talk", "bob") == null, "no new conversations while fainting")
	var r := e.complete_cycle()
	assert_eq([r["from_stage"], r["to_stage"], r["ended_cycle"]], ["A", "B", 1])
	assert_eq(e.cycle, 2)
	assert_false(e.has_flag("Today"), "cycle flags cleared")
	assert_true(e.has_flag("Known"), "persistent flags kept")
	assert_eq(e.state.history, [{"cycle": 1, "stage": "A", "ended": "Boom"}])
	assert_eq(e.select_beat("talk", "bob").id, "bob.once", "once:cycle beat available again")


func test_transition_reason_filter_and_fallthrough() -> void:
	var e := _engine()
	e.pending_faint = "Fizz"
	assert_eq(e.complete_cycle()["to_stage"], "C")
	var e2 := _engine()
	e2.pending_faint = "Boom"  # Known not set -> unconditional "stay in A"
	assert_eq(e2.complete_cycle()["to_stage"], "A")


func test_world_rules_later_wins() -> void:
	var e := _engine()
	assert_eq(e.world_value("door", "state"), "open")
	e.state.stage = "B"
	assert_eq(e.world_value("door", "state"), "closed")
	e.state.stage = "C"
	assert_eq(e.world_value("door", "state"), "gone")
	assert_eq(e.world_value("door", "nope"), null)


func test_talked_is_recorded_once_per_cycle() -> void:
	var e := _engine()
	for i in 3:
		_drain(e.trigger("talk", "bob"), [1])
	assert_eq(e.rel_cycles("bob", "Talked"), [1])


func test_explain() -> void:
	var report := "\n".join(_engine().explain("talk", "bob"))
	assert_true(">> [  9] bob.once: ok" in report, report)
	assert_true("bob.tie1: fails flag:Today" in report, report)
