class_name BTGVoiceProfile
extends BTGSoundSet
## Fake voice for one character (handoff §9): sound set + pitch range + volume range +
## speech rate. `samples` are vowel blips in the order a, e, i, o, u — the fake voice
## picks one from each Hangul syllable's vowel, so lines get a speech-like contour.
## Referenced from GameData/targets.json "voice" (e.g. VP_Guard -> VP_Guard.tres).

@export var chars_per_second := 28.0  ## typewriter speed for this speaker
@export var blip_every := 1  ## 2 = blip on every other syllable (slow, terse speakers)
