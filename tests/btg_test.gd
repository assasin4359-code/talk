class_name BTGTest
extends RefCounted
## Minimal test base for tests/run_tests.gd. Every method named test_* is a test.
## Assertions record failures instead of aborting, so one run reports everything.

var failures := PackedStringArray()
var current_test := ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg := "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%s expected %s, got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func load_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
