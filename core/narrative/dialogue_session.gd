class_name BTGDialogueSession
extends RefCounted
## Steps through one beat chain. Call advance() until an "end" event; call
## choose() after a "choices" event. Events are dictionaries:
##   {type: "line", speaker, text, cue}   {type: "pause", seconds}
##   {type: "choices", options}           {type: "end", faint}
## Order of operations: docs/03_Narrative_Data_Spec.md (실행 순서).

var engine: BTGNarrativeEngine
var beat: BTGNarrativeDB.Beat
var done := false

var _queue: Array = []
var _open_choices: Array = []
var _awaiting_choice := false
var _effects_done := false
var _ending := false  # a choice without "next" closes the conversation


func _init(p_engine: BTGNarrativeEngine, p_beat: BTGNarrativeDB.Beat) -> void:
	engine = p_engine
	_start(p_beat)


func _start(b: BTGNarrativeDB.Beat) -> void:
	beat = b
	engine.state.mark_seen(b.id)
	_queue.clear()
	for line in b.lines:
		if line.pause > 0.0:
			_queue.append({"type": "pause", "seconds": line.pause})
		if line.speaker != "" or line.cue != "":
			_queue.append({"type": "line", "speaker": line.speaker, "text": line.text, "cue": line.cue})
	_effects_done = false


func _chain(beat_id: String) -> bool:
	if beat_id == "" or not engine.db.beats.has(beat_id):
		return false
	var nxt: BTGNarrativeDB.Beat = engine.db.beats[beat_id]
	if not engine.check(nxt.when):
		return false  # chained beat not valid right now: the conversation just ends
	_start(nxt)
	return true


func _end() -> Dictionary:
	done = true
	return {"type": "end", "faint": engine.pending_faint}


func advance() -> Dictionary:
	if done:
		return {"type": "end", "faint": engine.pending_faint}
	if _awaiting_choice:
		push_error("advance() called while waiting for choose()")
		return {"type": "choices", "options": _open_choices.map(func(c): return c.text)}
	while true:
		if not _queue.is_empty():
			var ev: Dictionary = _queue.pop_front()
			if ev["type"] == "line" and ev["cue"] != "":
				engine.emit_cue(ev["cue"])
				if ev["text"] == "":
					continue  # cue-only line
			return ev
		if _ending:
			return _end()
		if not _effects_done:
			_effects_done = true
			engine.apply_effects(beat.effects)
		_open_choices = beat.choices.filter(func(c): return engine.check(c.when))
		if not _open_choices.is_empty():
			_awaiting_choice = true
			return {"type": "choices", "options": _open_choices.map(func(c): return c.text)}
		if _chain(beat.next):
			continue
		return _end()
	return _end()  # unreachable; keeps the parser happy


func choose(index: int) -> void:
	if not _awaiting_choice or index < 0 or index >= _open_choices.size():
		push_error("choose(%d) with no such open choice" % index)
		return
	var choice: BTGNarrativeDB.Choice = _open_choices[index]
	_awaiting_choice = false
	_open_choices = []
	engine.apply_effects(choice.effects)
	if not _chain(choice.next):
		_ending = true
