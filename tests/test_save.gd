extends BTGTest
## A/B slot saves: roundtrip, crash mid-write, tampering, versions.

const BASE := "user://test_saves/slot"


func _clean() -> void:
	for p in BTGSaveSystem.slot_paths(BASE):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _state(c: int) -> BTGStoryState:
	var s := BTGStoryState.new_game("S01_Arrival")
	s.cycle = c
	s.stage = "S02_GateClosed"
	s.flags = {"EnteredCastle": true, "GuardRecognizesPlayer": true}
	s.mark_seen("guard.c2.recognize")
	s.record_rel("bartender", "HelpedWithoutReward")
	s.history.append({"cycle": 1, "stage": "S01_Arrival", "ended": "CastleInterior"})
	return s


func _envelope(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _put(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data))
	f.close()


func test_roundtrip() -> void:
	_clean()
	assert_eq(BTGSaveSystem.write(BASE, _state(2)), OK)
	var r := BTGSaveSystem.load_newest(BASE)
	assert_true(r["state"] != null, "loads")
	if r["state"] != null:
		assert_eq(r["state"].to_dict(), _state(2).to_dict())


func test_slots_alternate_and_newest_wins() -> void:
	_clean()
	for c in [2, 3, 4]:
		BTGSaveSystem.write(BASE, _state(c))
	var paths := BTGSaveSystem.slot_paths(BASE)
	assert_eq(int(_envelope(paths[0])["seq"]), 2, "A holds writes 0 and 2")
	assert_eq(int(_envelope(paths[1])["seq"]), 1, "B holds write 1")
	assert_eq(BTGSaveSystem.load_newest(BASE)["state"].cycle, 4)


func test_crash_mid_write_falls_back_to_other_slot() -> void:
	_clean()
	BTGSaveSystem.write(BASE, _state(2))  # -> A
	BTGSaveSystem.write(BASE, _state(3))  # -> B
	var b := BTGSaveSystem.slot_paths(BASE)[1]
	_put(b, FileAccess.get_file_as_string(b).substr(0, 40))  # truncated write
	var r := BTGSaveSystem.load_newest(BASE)
	assert_eq(r["state"].cycle, 2)
	assert_eq(r["problems"].size(), 1)
	BTGSaveSystem.write(BASE, _state(5))  # must overwrite the broken slot, not the good one
	assert_eq(BTGSaveSystem.read_slot(BTGSaveSystem.slot_paths(BASE)[0])["state"].cycle, 2)
	assert_eq(BTGSaveSystem.load_newest(BASE)["state"].cycle, 5)


func test_tampered_payload_rejected() -> void:
	_clean()
	BTGSaveSystem.write(BASE, _state(2))
	var a := BTGSaveSystem.slot_paths(BASE)[0]
	var env := _envelope(a)
	env["payload"]["cycle"] = 99
	_put(a, env)
	assert_true(BTGSaveSystem.load_newest(BASE)["state"] == null)


func test_versions() -> void:
	_clean()
	BTGSaveSystem.write(BASE, _state(2))
	var a := BTGSaveSystem.slot_paths(BASE)[0]
	var env := _envelope(a)
	var payload: Dictionary = env["payload"]
	# future version: refused even with a valid checksum
	env["version"] = BTGSaveSystem.VERSION + 1
	env["checksum"] = BTGSaveSystem._checksum(env["version"], int(env["seq"]), payload)
	_put(a, env)
	assert_true("unsupported version" in BTGSaveSystem.read_slot(a)["problem"])
	# old version: upgraded through the migration chain
	env["version"] = 0
	env["checksum"] = BTGSaveSystem._checksum(0, int(env["seq"]), payload)
	_put(a, env)
	BTGSaveSystem.migrations[0] = func(p): p["flags"].append("Migrated"); return p
	var r := BTGSaveSystem.read_slot(a)
	BTGSaveSystem.migrations.erase(0)
	assert_true(r["state"] != null and r["state"].flags.has("Migrated"), "migrated: %s" % r["problem"])
	_clean()
