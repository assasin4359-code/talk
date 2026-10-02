class_name BTGEffect
extends RefCounted
## What a beat or choice does: set/clear a flag, record a relationship event,
## emit a presentation cue, or request a faint. Mirrors btg_narrative/effects.py.

const _ID := "[A-Za-z][A-Za-z0-9_]*"

static var last_error := ""
static var _patterns: Array = []

var kind := ""  # set | clear | rel | cue | faint
var key := ""
var sub := ""
var source := ""


func _to_string() -> String:
	return source


static func parse(text: String) -> BTGEffect:
	if _patterns.is_empty():
		for d in [
			["set", "^set:(%s)$" % _ID],
			["clear", "^clear:(%s)$" % _ID],
			["rel", r"^rel:(%s)\.(%s)$" % [_ID, _ID]],
			["cue", "^cue:(%s)$" % _ID],
			["faint", "^faint:(%s)$" % _ID],
		]:
			_patterns.append([d[0], RegEx.create_from_string(d[1])])
	var atom := text.strip_edges()
	for p in _patterns:
		var m: RegExMatch = p[1].search(atom)
		if m == null:
			continue
		var e := BTGEffect.new()
		e.kind = p[0]
		e.key = m.get_string(1)
		e.sub = m.get_string(2) if m.get_group_count() > 1 else ""
		e.source = text
		return e
	last_error = "unrecognised effect: '%s'" % text
	return null


static func parse_list(items: Variant, where: String, errors: PackedStringArray) -> Array:
	var out: Array = []
	if items == null:
		return out
	for t in items:
		var e := parse(str(t))
		if e == null:
			errors.append("%s: %s" % [where, last_error])
		else:
			out.append(e)
	return out
