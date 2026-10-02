class_name BTGSoundSet
extends Resource
## A family of interchangeable sounds (e.g. "footsteps on stone"): one is picked at
## random each time, with a little pitch/volume jitter so repeats don't sound canned.
## Placeholders and real recordings plug in the same way: swap `samples`.

@export var samples: Array[AudioStream] = []
@export var pitch_min := 0.95
@export var pitch_max := 1.05
@export var volume_db_min := -2.0
@export var volume_db_max := 0.0
@export var bus: StringName = &"SFX"


func pick(rng: RandomNumberGenerator, index := -1) -> AudioStream:
	if samples.is_empty():
		return null
	return samples[index % samples.size()] if index >= 0 else samples[rng.randi() % samples.size()]


## Plays one sound on `player` (a 2D or 3D AudioStreamPlayer); returns the stream used.
func play_on(player: Node, rng: RandomNumberGenerator, index := -1) -> AudioStream:
	var stream := pick(rng, index)
	if stream == null or not BTGAudio.can_play():
		return stream
	player.stream = stream
	player.bus = bus
	player.pitch_scale = rng.randf_range(pitch_min, pitch_max)
	player.volume_db = rng.randf_range(volume_db_min, volume_db_max)
	player.play()
	return stream
