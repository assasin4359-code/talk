extends BTGTest
## Runs GameData/tests/condition_vectors.json — the same file the Python reference runs.


class VectorContext:
	var cycle := 0
	var _order: Array = []
	var _stage := ""
	var _flags := {}
	var _seen := {}
	var _rel := {}
	var _world := {}

	func _init(c: Dictionary) -> void:
		cycle = int(c["cycle"])
		_order = c["stageOrder"]
		_stage = c["stage"]
		for f in c["flags"] + c["cycleFlags"]:
			_flags[f] = true
		for k in c["seen"]:
			_seen[k] = c["seen"][k].map(func(x): return int(x))
		for k in c["rel"]:
			_rel[k] = c["rel"][k].map(func(x): return int(x))
		_world = c["world"]

	func has_flag(f: String) -> bool:
		return _flags.has(f)

	func current_stage_index() -> int:
		return _order.find(_stage)

	func stage_index(s: String) -> int:
		return _order.find(s)

	func seen_cycles(b: String) -> Array:
		return _seen.get(b, [])

	func rel_cycles(npc: String, ev: String) -> Array:
		return _rel.get("%s.%s" % [npc, ev], [])

	func world_value(t: String, p: String) -> Variant:
		return _world.get("%s.%s" % [t, p])


func test_vectors() -> void:
	var v: Dictionary = load_json("res://GameData/tests/condition_vectors.json")
	var ctx := VectorContext.new(v["context"])
	for case in v["cases"]:
		var c := BTGCondition.parse(case["atom"])
		if c == null:
			fail("%s did not parse: %s" % [case["atom"], BTGCondition.last_error])
			continue
		assert_eq(c.evaluate(ctx), case["expect"], case["atom"])


func test_invalid_atoms_rejected() -> void:
	var v: Dictionary = load_json("res://GameData/tests/condition_vectors.json")
	for atom in v["invalid"]:
		assert_true(BTGCondition.parse(atom) == null, "should reject '%s'" % atom)


func test_effects() -> void:
	var rel := BTGEffect.parse("rel:bartender.HelpedWithoutReward")
	assert_eq([rel.kind, rel.key, rel.sub], ["rel", "bartender", "HelpedWithoutReward"])
	assert_eq(BTGEffect.parse("faint:GateTouch").key, "GateTouch")
	for bad in ["set", "set:", "rel:bartender", "explode:everything", "cue:has space"]:
		assert_true(BTGEffect.parse(bad) == null, "should reject '%s'" % bad)
