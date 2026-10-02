extends SceneTree
## Headless test runner. Usage (from the repo root):
##   godot --headless --path . --script res://tests/run_tests.gd
## Runs every test_* method of every tests/test_*.gd; exits 1 on any failure.
## Tests may be coroutines (await tree.process_frame) — scene tests need real frames.
##
## GDScript has no exceptions: a runtime error just aborts the test function. So any
## engine/script error logged while a test runs counts as a failure of that test.


class ErrorCounter extends Logger:
	var errors := PackedStringArray()
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
		_lock.unlock()

	func take() -> PackedStringArray:
		_lock.lock()
		var out := errors
		errors = PackedStringArray()
		_lock.unlock()
		return out


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	await process_frame  # let autoloads (Narrative) finish _ready
	counter.take()
	var only := OS.get_environment("BTG_TEST_FILTER")  # e.g. BTG_TEST_FILTER=test_routes
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f): return f.begins_with("test_") and f.ends_with(".gd") and (only == "" or only in f))
	files.sort()
	var total := 0
	var failures := PackedStringArray()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		var suite: BTGTest = script.new()
		suite.tree = self
		for m in suite.get_method_list():
			if not m["name"].begins_with("test_"):
				continue
			total += 1
			suite.current_test = "%s::%s" % [file.get_basename(), m["name"]]
			var before := suite.failures.size()
			await Callable(suite, m["name"]).call()  # tests may await frames
			for e in counter.take():
				suite.fail("error logged: " + e)
			print("%s %s" % ["ok  " if suite.failures.size() == before else "FAIL", suite.current_test])
		failures.append_array(suite.failures)
	print("")
	for f in failures:
		printerr("FAIL " + f)
	print("%d tests, %d failure(s)" % [total, failures.size()])
	OS.remove_logger(counter)
	quit(1 if failures.size() > 0 else 0)
