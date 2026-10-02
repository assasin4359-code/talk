class_name BTGCondition
extends RefCounted
## One condition atom. A condition list is a flat AND of atoms.
## Grammar: docs/03_Narrative_Data_Spec.md — must match Tools/narrative/btg_narrative/conditions.py.
## Conformance: GameData/tests/condition_vectors.json.

const _OP := "(==|!=|<=|>=|<|>)"
const _ID := "[A-Za-z][A-Za-z0-9_]*"
const _BEAT := "[A-Za-z][A-Za-z0-9_.]*"
const _VALUE := "[A-Za-z0-9_]+"
const _SCOPE := "(?:@(cycle|prev|past))?"

static var last_error := ""
static var _patterns: Array = []  # [[kind, RegEx], ...] in match order
static var _around_op: RegEx

var kind := ""  # flag | cycle | stage | seen | rel | world
var negate := false
var key := ""
var sub := ""
var op := ""
var value: Variant = ""
var scope := ""  # "" | cycle | prev | past
var source := ""


func _to_string() -> String:
	return source


static func _compile() -> void:
	if not _patterns.is_empty():
		return
	_around_op = RegEx.create_from_string(r"\s*(==|!=|<=|>=|<|>|=)\s*")
	var defs := [
		["flag", "^flag:(%s)$" % _ID],
		["cycle", r"^cycle%s(\d+)$" % _OP],
		["stage_eq", "^stage:(%s)$" % _ID],
		["stage", "^stage%s(%s)$" % [_OP, _ID]],
		["seen", "^seen:(%s)%s$" % [_BEAT, _SCOPE]],
		["rel", r"^rel:(%s)\.(%s)%s(?:%s(\d+))?$" % [_ID, _ID, _SCOPE, _OP]],
		["world", r"^world:(%s)\.(%s)=(%s)$" % [_ID, _ID, _VALUE]],
	]
	for d in defs:
		_patterns.append([d[0], RegEx.create_from_string(d[1])])


## Returns null (and sets last_error) when the text is not a valid atom.
static func parse(text: String) -> BTGCondition:
	_compile()
	# Spaces are allowed only around operators ("cycle >= 2"); anything else is a typo.
	var atom := _around_op.sub(text.strip_edges(), "$1", true)
	var c := BTGCondition.new()
	c.source = text
	if atom.begins_with("!"):
		c.negate = true
		atom = atom.substr(1)
	for p in _patterns:
		var m: RegExMatch = p[1].search(atom)
		if m == null:
			continue
		match p[0]:
			"flag":
				c.kind = "flag"
				c.key = m.get_string(1)
			"cycle":
				c.kind = "cycle"
				c.op = m.get_string(1)
				c.value = int(m.get_string(2))
			"stage_eq":
				c.kind = "stage"
				c.op = "=="
				c.value = m.get_string(1)
			"stage":
				c.kind = "stage"
				c.op = m.get_string(1)
				c.value = m.get_string(2)
			"seen":
				c.kind = "seen"
				c.key = m.get_string(1)
				c.scope = m.get_string(2)
			"rel":
				c.kind = "rel"
				c.key = m.get_string(1)
				c.sub = m.get_string(2)
				c.scope = m.get_string(3)
				c.op = m.get_string(4)
				c.value = int(m.get_string(5)) if c.op != "" else ""
			"world":
				c.kind = "world"
				c.key = m.get_string(1)
				c.sub = m.get_string(2)
				c.value = m.get_string(3)
		return c
	last_error = "unrecognised condition atom: '%s'" % text
	return null


## Parses a JSON list of atoms. Unparseable atoms are appended to `errors` and skipped.
static func parse_list(items: Variant, where: String, errors: PackedStringArray) -> Array:
	var out: Array = []
	if items == null:
		return out
	for t in items:
		var c := parse(str(t))
		if c == null:
			errors.append("%s: %s" % [where, last_error])
		else:
			out.append(c)
	return out


static func compare(a: int, op: String, b: int) -> bool:
	match op:
		"==": return a == b
		"!=": return a != b
		"<": return a < b
		"<=": return a <= b
		">": return a > b
		">=": return a >= b
	return false


static func scoped_count(cycles: Array, scope: String, now: int) -> int:
	var n := 0
	for c in cycles:
		match scope:
			"cycle":
				if c == now: n += 1
			"prev":
				if c == now - 1: n += 1
			"past":
				if c < now: n += 1
			_:
				n += 1
	return n


## ctx: any object with `cycle`, has_flag(), current_stage_index(), stage_index(),
## seen_cycles(), rel_cycles(), world_value() — BTGNarrativeEngine in the game.
func evaluate(ctx: Object) -> bool:
	var result := false
	match kind:
		"flag":
			result = ctx.has_flag(key)
		"cycle":
			result = compare(ctx.cycle, op, value)
		"stage":
			result = compare(ctx.current_stage_index(), op, ctx.stage_index(value))
		"seen":
			result = scoped_count(ctx.seen_cycles(key), scope, ctx.cycle) > 0
		"rel":
			var n := scoped_count(ctx.rel_cycles(key, sub), scope, ctx.cycle)
			result = compare(n, op, value) if op != "" else n > 0
		"world":
			var v: Variant = ctx.world_value(key, sub)
			result = v is String and v == value
	return result != negate


static func all_true(conds: Array, ctx: Object) -> bool:
	for c in conds:
		if not c.evaluate(ctx):
			return false
	return true


static func failing(conds: Array, ctx: Object) -> Array:
	return conds.filter(func(c): return not c.evaluate(ctx))
