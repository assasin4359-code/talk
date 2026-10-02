class_name BTGScenarioRunner
extends RefCounted
## Plays a GameData/tests/scenarios/*.json file against the engine.
## Must agree step for step with Tools/narrative/btg_narrative/scenario.py.


static func _split_said(text: String) -> PackedStringArray:
	var i := text.find(": ")
	return PackedStringArray([text.substr(0, i).strip_edges(), text.substr(i + 2)]) if i >= 0 else PackedStringArray([text, ""])


## Returns failure messages; empty means the scenario passed. Stops at the first failing step.
static func run(db: BTGNarrativeDB, scenario: Dictionary) -> PackedStringArray:
	var engine := BTGNarrativeEngine.new(db)
	var transcript: Array = []  # [cycle, speaker, text]
	var last_act := PackedStringArray()
	var steps: Array = scenario.get("steps", [])
	for i in steps.size():
		var step: Dictionary = steps[i]
		var where := "step %d %s" % [i, JSON.stringify(step)]
		if step.has("check"):
			for atom in step["check"]:
				var c := BTGCondition.parse(atom)
				if c == null:
					return PackedStringArray(["%s: %s" % [where, BTGCondition.last_error]])
				if not c.evaluate(engine):
					return PackedStringArray(["%s: %s is false" % [where, atom]])
		elif step.has("act"):
			var parts: PackedStringArray = str(step["act"]).split(":", true, 1)
			var picks: Array = step.get("pick", []).duplicate()
			var session := engine.trigger(parts[0], parts[1])
			if session == null:
				if step.get("nothing", false):
					continue
				return PackedStringArray(["%s: nothing happened" % where])
			if step.get("nothing", false):
				return PackedStringArray(["%s: expected nothing, got beat %s" % [where, session.beat.id]])
			last_act = PackedStringArray()
			while true:
				var ev := session.advance()
				if ev["type"] == "line":
					transcript.append([engine.cycle, ev["speaker"], ev["text"]])
					last_act.append("%s: %s" % [ev["speaker"], ev["text"]])
				elif ev["type"] == "choices":
					if picks.is_empty():
						return PackedStringArray(["%s: unanswered choice %s" % [where, ev["options"]]])
					var want: String = picks.pop_front()
					var idx := -1
					for k in ev["options"].size():
						if ev["options"][k].begins_with(want):
							idx = k
							break
					if idx < 0:
						return PackedStringArray(["%s: choice '%s' not offered in %s" % [where, want, ev["options"]]])
					session.choose(idx)
				elif ev["type"] == "end":
					break
			if not picks.is_empty():
				return PackedStringArray(["%s: unused picks %s" % [where, picks]])
		elif step.has("said") or step.has("notSaid"):
			var negative := step.has("notSaid")
			var sf := _split_said(step["notSaid"] if negative else step["said"])
			var found := false
			for t in transcript:
				if t[0] == engine.cycle and t[1] == sf[0] and sf[1] in t[2]:
					found = true
					break
			if found == negative:
				return PackedStringArray(["%s: %s this cycle" % [where, "unexpectedly said" if negative else "never said"]])
		elif step.has("saidInOrder"):
			var pos := 0
			for want in step["saidInOrder"]:
				while pos < last_act.size() and last_act[pos] != want:
					pos += 1
				if pos == last_act.size():
					return PackedStringArray(["%s: '%s' missing or out of order in %s" % [where, want, last_act]])
				pos += 1
		elif step.has("faint"):
			if engine.pending_faint != step["faint"]:
				return PackedStringArray(["%s: pending faint is '%s'" % [where, engine.pending_faint]])
			engine.complete_cycle()
		elif step.has("noFaint"):
			if engine.pending_faint != "":
				return PackedStringArray(["%s: pending faint is '%s'" % [where, engine.pending_faint]])
		else:
			return PackedStringArray(["%s: unknown step" % where])

	var failures := PackedStringArray()
	for rule in scenario.get("never", []):
		for t in transcript:
			if rule.has("speaker") and t[1] != rule["speaker"]:
				continue
			if rule.get("npcOnly", false) and t[1] in ["player", "narrator"]:
				continue
			if rule.has("cycle") and t[0] != int(rule["cycle"]):
				continue
			if rule.has("maxCycle") and t[0] > int(rule["maxCycle"]):
				continue
			if rule["text"] in t[2]:
				failures.append("never %s: cycle %d %s: %s" % [rule, t[0], t[1], t[2]])
	return failures
