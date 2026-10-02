class_name BTGFaintFx
extends CanvasLayer
## Screen + sound side of fainting and waking (handoff §11: tinnitus, blurred vision,
## shaking, weak graphic anomaly, collapse, black). The camera motion is the director's.
## Temporary: the tinnitus is a generated sine until real audio exists.

const SHADER := preload("res://game/fx/faint_fx.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial
var _tone: AudioStreamPlayer


func _ready() -> void:
	layer = 20
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)
	_tone = AudioStreamPlayer.new()
	_tone.stream = _make_tone(6200.0)
	_tone.volume_db = -80.0
	add_child(_tone)
	clear()


func _exit_tree() -> void:
	_tone.stop()  # the scene can be freed mid-faint (F9, tests); don't leave the tone playing


func clear() -> void:
	_apply(0.0, 0.0, 0.0)
	_rect.visible = false


func black() -> void:
	_rect.visible = true
	_apply(1.0, 0.0, 1.0)


func _apply(blur: float, glitch: float, darkness: float) -> void:
	_mat.set_shader_parameter("blur", blur)
	_mat.set_shader_parameter("glitch", glitch)
	_mat.set_shader_parameter("darkness", darkness)


func _param_tween(param: String, to: float, seconds: float, delay := 0.0) -> Tween:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_method(func(v): _mat.set_shader_parameter(param, v), _mat.get_shader_parameter(param), to, maxf(seconds, 0.001))
	return t


## Ringing -> blur and tearing -> black. `duration` is the whole collapse.
func play_faint(duration: float) -> void:
	_rect.visible = true
	# No audio output (headless tests, captures): nothing to hear, and a playback started
	# on the Dummy driver is never cleaned up if the scene is freed mid-faint.
	if AudioServer.get_driver_name() != "Dummy":
		_tone.play()
		create_tween().tween_property(_tone, "volume_db", -9.0, duration * 0.8).from(-50.0)
	_param_tween("blur", 1.0, duration * 0.7, duration * 0.15)
	_param_tween("glitch", 0.85, duration * 0.5, duration * 0.3)
	var dark := _param_tween("darkness", 1.0, duration * 0.35, duration * 0.65)
	await BTGTweens.done(dark)
	_tone.stop()
	_mat.set_shader_parameter("glitch", 0.0)


## Black -> blurry -> clear.
func play_wake(duration: float) -> void:
	black()
	var dark := _param_tween("darkness", 0.0, duration * 0.6)
	var blur := _param_tween("blur", 0.0, duration, duration * 0.2)
	await BTGTweens.done(dark)
	await BTGTweens.done(blur)
	clear()


func fade_in(duration: float) -> void:
	_rect.visible = true
	_apply(0.0, 0.0, 1.0)
	await BTGTweens.done(_param_tween("darkness", 0.0, duration))
	clear()


static func _make_tone(freq: float, rate := 22050) -> AudioStreamWAV:
	var n := rate  # one second: a whole number of cycles, so the loop is seamless
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(sin(TAU * freq * i / rate) * 9000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w
