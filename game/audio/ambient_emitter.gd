extends Node
## Starts its parent AudioStreamPlayer / AudioStreamPlayer3D (a looping ambience) once
## the scene is up — unless there is no audio output (tests), see BTGAudio.can_play().
## Used instead of `autoplay` so headless runs never start real playbacks.


func _ready() -> void:
	if BTGAudio.can_play():
		get_parent().play()
