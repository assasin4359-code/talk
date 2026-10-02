extends BTGTest
## Milestone 01 story checks — the same scenario files the Python reference runs.

const SCENARIOS := "res://GameData/tests/scenarios"


func test_gamedata_loads_cleanly() -> void:
	var db := BTGNarrativeDB.load_from("res://GameData")
	assert_eq(db.errors, PackedStringArray(), "load errors")
	assert_true(db.beats.size() > 0, "no beats loaded")


func test_all_scenarios() -> void:
	var db := BTGNarrativeDB.load_from("res://GameData")
	var files := Array(DirAccess.get_files_at(SCENARIOS)).filter(func(f): return f.ends_with(".json"))
	assert_true(files.size() > 0, "no scenarios found")
	for file in files:
		var scenario: Dictionary = load_json(SCENARIOS.path_join(file))
		for f in BTGScenarioRunner.run(db, scenario):
			fail("%s: %s" % [file, f])


func test_runner_reports_failures() -> void:
	var db := BTGNarrativeDB.load_from("res://GameData")
	var bad := {"steps": [{"act": "talk:guard", "pick": ["고마워"]}, {"said": "guard: 이런 말은 안 함"}]}
	var failures := BTGScenarioRunner.run(db, bad)
	assert_eq(failures.size(), 1)
	assert_true(failures.size() == 1 and "never said" in failures[0], "wrong failure: %s" % failures)


func test_every_npc_answers_in_every_stage() -> void:
	var db := BTGNarrativeDB.load_from("res://GameData")
	var engine := BTGNarrativeEngine.new(db)
	for stage in db.stage_order:
		for c in [1, 2, 5]:
			engine.state.stage = stage
			engine.state.cycle = c
			for id in db.targets:
				if db.targets[id]["kind"] == "npc":
					assert_true(engine.select_beat("talk", id) != null, "%s silent in %s cycle %d" % [id, stage, c])
