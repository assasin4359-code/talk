class_name BTGSaveSystem
extends RefCounted
## Corruption-resistant saves: two slots (A/B) written alternately, each with a
## sequence number and a sha256 checksum. A crash mid-write can only damage the
## slot being written; the other one still loads.
##   {"format": "BTGSave", "version": 1, "seq": 7, "checksum": "...", "payload": {StoryState}}

const FORMAT := "BTGSave"
const VERSION := 1

## version -> Callable(payload: Dictionary) -> Dictionary, upgrading to version + 1
static var migrations := {}


static func slot_paths(base: String) -> PackedStringArray:
	return PackedStringArray([base + "_a.json", base + "_b.json"])


## JSON numbers come back as floats; turn whole numbers back into ints so the
## checksum is computed over the same canonical text that was written.
static func _normalize(v: Variant) -> Variant:
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		return v.map(func(x): return _normalize(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _normalize(v[k])
		return out
	return v


static func _checksum(version: int, seq: int, payload: Dictionary) -> String:
	var canonical := JSON.stringify(_normalize({"payload": payload, "seq": seq, "version": version}), "", true)
	return canonical.sha256_text()


## Reads one slot. Returns {state, seq, problem}; state is null when unusable.
static func read_slot(path: String) -> Dictionary:
	var result := {"state": null, "seq": -1, "problem": ""}
	if not FileAccess.file_exists(path):
		result["problem"] = "%s: missing" % path.get_file()
		return result
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		result["problem"] = "%s: unreadable" % path.get_file()
		return result
	var env: Dictionary = json.data
	if env.get("format") != FORMAT or not env.get("payload") is Dictionary:
		result["problem"] = "%s: not a %s file" % [path.get_file(), FORMAT]
		return result
	var version := int(env.get("version", -1))
	var seq := int(env.get("seq", -1))
	var payload: Dictionary = env["payload"]
	if env.get("checksum") != _checksum(version, seq, payload):
		result["problem"] = "%s: checksum mismatch" % path.get_file()
		return result
	if version > VERSION or version < 0:
		result["problem"] = "%s: unsupported version %d" % [path.get_file(), version]
		return result
	while version < VERSION:
		if not migrations.has(version):
			result["problem"] = "%s: no migration from version %d" % [path.get_file(), version]
			return result
		payload = migrations[version].call(payload)
		version += 1
	var state := BTGStoryState.from_dict(_normalize(payload))
	if state == null:
		result["problem"] = "%s: bad payload" % path.get_file()
		return result
	result["state"] = state
	result["seq"] = seq
	return result


## Loads the newest valid slot. Returns {state, source, problems}.
static func load_newest(base: String) -> Dictionary:
	var best := {"state": null, "source": "", "seq": -1}
	var problems := PackedStringArray()
	for path in slot_paths(base):
		var r := read_slot(path)
		if r["state"] == null:
			problems.append(r["problem"])
		elif r["seq"] > best["seq"]:
			best = {"state": r["state"], "source": path, "seq": r["seq"]}
	return {"state": best["state"], "source": best["source"], "problems": problems}


## Overwrites the older (or broken) slot, never the newest good one.
static func write(base: String, state: BTGStoryState) -> Error:
	DirAccess.make_dir_recursive_absolute(base.get_base_dir())
	var paths := slot_paths(base)
	var a := read_slot(paths[0])
	var b := read_slot(paths[1])
	var newest_seq := maxi(a["seq"] if a["state"] != null else -1, b["seq"] if b["state"] != null else -1)
	var target := paths[1] if a["state"] != null and a["seq"] == newest_seq else paths[0]
	var seq := newest_seq + 1
	var payload := state.to_dict()
	var env := {
		"format": FORMAT,
		"version": VERSION,
		"seq": seq,
		"checksum": _checksum(VERSION, seq, payload),
		"payload": payload,
	}
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(env, "  ", true))
	f.flush()
	f.close()
	return OK
