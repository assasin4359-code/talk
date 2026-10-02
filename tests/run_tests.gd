extends SceneTree
## Headless test runner. Usage (from the repo root):
##   godot --headless --path . --script res://tests/run_tests.gd
## Runs every test_* method of every tests/test_*.gd; exits 1 on any failure.


func _initialize() -> void:
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	var total := 0
	var failures := PackedStringArray()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		var suite: BTGTest = script.new()
		for m in suite.get_method_list():
			if not m["name"].begins_with("test_"):
				continue
			total += 1
			suite.current_test = "%s::%s" % [file.get_basename(), m["name"]]
			var before := suite.failures.size()
			suite.call(m["name"])
			print("%s %s" % ["ok  " if suite.failures.size() == before else "FAIL", suite.current_test])
		failures.append_array(suite.failures)
	print("")
	for f in failures:
		printerr("FAIL " + f)
	print("%d tests, %d failure(s)" % [total, failures.size()])
	quit(1 if failures.size() > 0 else 0)
