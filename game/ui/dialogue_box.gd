class_name BTGDialogueBox
extends CanvasLayer
## Plays a BTGDialogueSession: typewriter text, silent pauses, choices.
## Presentation only — what is said and in what order comes from the session.
##
## `autoplay` (tests, captures): when non-null, lines advance by themselves and
## choices are answered from the queue by prefix; stops advancing once
## `autoplay_hold_at` lines have been shown (so a capture can photograph that line).

signal finished(faint_reason: String)
signal character_revealed(speaker: String, character: String)  ## hook for the fake voice
signal _advance
signal _picked(index: int)

const CHARS_PER_SEC := 28.0
const PUNCT_PAUSE := {".": 0.18, "?": 0.22, "!": 0.2, "…": 0.12, ",": 0.08}

var autoplay = null  # null | Array of choice-text prefixes
var autoplay_hold_at := -1
var instant := false  # no typewriter, no pauses (tests)
var transcript: Array = []  # [speaker, text]
var active := false

var _panel: PanelContainer
var _name: Label
var _text: Label
var _more: Label
var _choices: VBoxContainer
var _typing := false
var _waiting := false
var _choosing := false


func _ready() -> void:
	layer = 10
	_build()
	_panel.visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -230
	_panel.offset_left = 120
	_panel.offset_right = -120
	_panel.offset_bottom = -36
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.86)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	style.border_color = Color(0.85, 0.72, 0.5, 0.35)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 19)
	_name.add_theme_color_override("font_color", Color(0.95, 0.78, 0.48))
	v.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 25)
	_text.custom_minimum_size = Vector2(0, 70)
	v.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	v.add_child(_choices)
	_more = Label.new()
	_more.text = "▼"
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more.add_theme_color_override("font_color", Color(0.95, 0.78, 0.48, 0.8))
	v.add_child(_more)


func run(session: BTGDialogueSession) -> String:
	active = true
	_panel.visible = true
	_clear_choices()
	_text.text = ""
	_name.text = ""
	_more.visible = false
	var faint := ""
	while true:
		var ev := session.advance()
		match ev["type"]:
			"pause":
				_more.visible = false
				if not instant:
					await get_tree().create_timer(ev["seconds"]).timeout
			"line":
				await _show_line(ev["speaker"], ev["text"])
			"choices":
				session.choose(await _show_choices(ev["options"]))
			"end":
				faint = ev["faint"]
				break
	_panel.visible = false
	active = false
	finished.emit(faint)
	return faint


func _speaker_name(id: String) -> String:
	return "나" if id == "player" else Narrative.target_name(id)


func _show_line(speaker: String, text: String) -> void:
	transcript.append([speaker, text])
	_name.text = _speaker_name(speaker)
	_text.text = text
	_more.visible = false
	if instant:
		_text.visible_characters = -1
	else:
		_text.visible_characters = 0
		_typing = true
		var i := 0
		while i < text.length() and _typing:
			i += 1
			_text.visible_characters = i
			var ch := text[i - 1]
			if ch != " ":
				character_revealed.emit(speaker, ch)
			await get_tree().create_timer(1.0 / CHARS_PER_SEC + PUNCT_PAUSE.get(ch, 0.0)).timeout
		_typing = false
		_text.visible_characters = -1
	_more.visible = true
	if autoplay != null:
		if autoplay_hold_at >= 0 and transcript.size() >= autoplay_hold_at:
			await get_tree().create_timer(3600.0).timeout  # hold for a capture
		return
	_waiting = true
	await _advance
	_waiting = false


func _show_choices(options: Array) -> int:
	_more.visible = false
	if autoplay != null:
		var want: String = autoplay.pop_front() if not autoplay.is_empty() else ""
		for i in options.size():
			if want != "" and options[i].begins_with(want):
				return i
		push_error("autoplay: no choice starting with '%s' in %s" % [want, options])
		return options.size() - 1
	_clear_choices()
	for i in options.size():
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func(): _picked.emit(i))
		_choices.add_child(b)
	(_choices.get_child(0) as Button).grab_focus()
	_choosing = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var index: int = await _picked
	_choosing = false
	_clear_choices()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return index


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if _choosing:
		for i in range(1, 10):
			if event.is_action_pressed("choice_%d" % i) and i <= _choices.get_child_count():
				get_viewport().set_input_as_handled()
				_picked.emit(i - 1)
				return
		# E/Space/Enter pick the focused option; mouse clicks go to the button under the cursor
		if event.is_action_pressed("interact") and not event is InputEventMouseButton:
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button and focused.get_parent() == _choices:
				get_viewport().set_input_as_handled()
				_picked.emit(focused.get_index())
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if _typing:
			_typing = false  # finish the line instantly
		elif _waiting:
			_advance.emit()
