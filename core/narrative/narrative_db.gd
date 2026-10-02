class_name BTGNarrativeDB
extends RefCounted
## Loads GameData/*.json. Mirrors btg_narrative/data.py.
## Only syntax errors are reported here; cross-reference validation runs in CI
## (python Tools/narrative/btg.py validate), so the runtime trusts references.

const VERBS := ["talk", "use", "enter"]


class Line:
	var speaker := ""  # "" for a pure pause / cue-only line
	var text := ""
	var pause := 0.0  # seconds of silence *before* the line
	var cue := ""


class Choice:
	var text := ""
	var when: Array = []
	var next := ""
	var effects: Array = []


class Beat:
	var id := ""
	var verb := ""  # "" when the beat is only reachable through next/choices
	var target := ""
	var when: Array = []
	var once := ""  # "" | cycle | story
	var priority := 0
	var lines: Array = []
	var choices: Array = []
	var effects: Array = []
	var next := ""
	var order := 0


class Transition:
	var to := ""
	var when: Array = []
	var reason := ""


class Stage:
	var id := ""
	var index := 0
	var terminal := false
	var transitions: Array = []


class WorldRule:
	var target := ""
	var prop := ""
	var value := ""
	var when: Array = []


var root := ""
var errors := PackedStringArray()
var flags := {}  # id -> "persistent" | "cycle"
var rel_events := {}
var cues := {}
var faint_reasons := {}
var targets := {}  # id -> {kind, name, voice}
var stages := {}  # id -> Stage
var stage_order: Array[String] = []
var start_stage := ""
var beats := {}  # id -> Beat, in file order
var anchors := {}
var world_baseline := {}  # "target.prop" -> value
var world_rules: Array = []


static func load_from(root_path: String) -> BTGNarrativeDB:
	var db := BTGNarrativeDB.new()
	db.root = root_path
	db._load_registry()
	db._load_targets()
	db._load_stages()
	db._load_world()
	db._load_beats()
	return db


func ok() -> bool:
	return errors.is_empty()


func beats_for(verb: String, target: String) -> Array:
	var out: Array = []
	for b in beats.values():
		if b.verb == verb and b.target == target:
			out.append(b)
	return out


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: invalid JSON: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_registry() -> void:
	var data: Variant = _read_json(root.path_join("registry.json"))
	if data == null:
		return
	for f in data.get("flags", []):
		if not f.get("scope") in ["persistent", "cycle"]:
			errors.append("registry.json: flag %s has invalid scope" % f.get("id"))
			continue
		flags[f["id"]] = f["scope"]
	rel_events["Talked"] = true
	for e in data.get("relationshipEvents", []):
		rel_events[e["id"]] = true
	for c in data.get("cues", []):
		cues[c["id"]] = true
	for r in data.get("faintReasons", []):
		faint_reasons[r["id"]] = true


func _load_targets() -> void:
	var data: Variant = _read_json(root.path_join("targets.json"))
	if data == null:
		return
	for t in data.get("targets", []):
		targets[t["id"]] = {"kind": t.get("kind", ""), "name": t.get("name", t["id"]), "voice": t.get("voice", "")}


func _load_stages() -> void:
	var data: Variant = _read_json(root.path_join("stages.json"))
	if data == null:
		return
	start_stage = data.get("start", "")
	for s in data.get("stages", []):
		var st := Stage.new()
		st.id = s["id"]
		st.index = stage_order.size()
		st.terminal = bool(s.get("terminal", false))
		for t in s.get("transitions", []):
			var tr := Transition.new()
			tr.to = t.get("to", "")
			tr.reason = t.get("reason", "") if t.get("reason") != null else ""
			tr.when = BTGCondition.parse_list(t.get("when"), "stages.json %s" % st.id, errors)
			st.transitions.append(tr)
		stages[st.id] = st
		stage_order.append(st.id)


func _load_world() -> void:
	var data: Variant = _read_json(root.path_join("world.json"))
	if data == null:
		return
	for a in data.get("anchors", []):
		anchors[a] = true
	for b in data.get("baseline", []):
		world_baseline["%s.%s" % [b["target"], b["prop"]]] = str(b["value"])
	for r in data.get("rules", []):
		var rule := WorldRule.new()
		rule.target = r["target"]
		rule.prop = r["prop"]
		rule.value = str(r["value"])
		rule.when = BTGCondition.parse_list(r.get("when"), "world.json %s.%s" % [rule.target, rule.prop], errors)
		world_rules.append(rule)


func _load_beats() -> void:
	var dir := root.path_join("beats")
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".json"))
	files.sort()
	if files.is_empty():
		errors.append("%s: no beat files" % dir)
	var order := 0
	for file in files:
		var data: Variant = _read_json(dir.path_join(file))
		if data == null:
			continue
		for raw in data.get("beats", []):
			var b := Beat.new()
			b.id = raw.get("id", "")
			var where := "%s beat %s" % [file, b.id]
			if b.id == "" or beats.has(b.id):
				errors.append("%s: missing or duplicate id" % where)
				continue
			if raw.get("on") != null:
				var parts: PackedStringArray = str(raw["on"]).split(":", true, 1)
				if parts.size() != 2 or not parts[0] in VERBS or parts[1] == "":
					errors.append("%s: bad \"on\"" % where)
				else:
					b.verb = parts[0]
					b.target = parts[1]
			b.when = BTGCondition.parse_list(raw.get("when"), where, errors)
			b.once = raw.get("once", "") if raw.get("once") != null else ""
			b.priority = int(raw.get("priority", 0))
			b.effects = BTGEffect.parse_list(raw.get("effects"), where, errors)
			b.next = raw.get("next", "") if raw.get("next") != null else ""
			for i in raw.get("lines", []).size():
				var line := _parse_line(raw["lines"][i])
				if line == null:
					errors.append("%s line #%d: bad line" % [where, i])
				else:
					b.lines.append(line)
			for rc in raw.get("choices", []):
				var ch := Choice.new()
				ch.text = rc.get("text", "")
				ch.when = BTGCondition.parse_list(rc.get("when"), where, errors)
				ch.next = rc.get("next", "") if rc.get("next") != null else ""
				ch.effects = BTGEffect.parse_list(rc.get("effects"), where, errors)
				b.choices.append(ch)
			b.order = order
			order += 1
			beats[b.id] = b


## A line is "speaker: text" or {speaker, text, pause, cue}.
static func _parse_line(raw: Variant) -> Line:
	var line := Line.new()
	if raw is String:
		var i: int = raw.find(":")
		if i <= 0 or raw.substr(i + 1).strip_edges() == "":
			return null
		line.speaker = raw.substr(0, i).strip_edges()
		line.text = raw.substr(i + 1).strip_edges()
		return line
	if raw is Dictionary:
		line.speaker = raw.get("speaker", "") if raw.get("speaker") != null else ""
		line.text = raw.get("text", "")
		line.pause = float(raw.get("pause", 0.0))
		line.cue = raw.get("cue", "") if raw.get("cue") != null else ""
		if (line.speaker == "") != (line.text == ""):
			return null
		return line
	return null
