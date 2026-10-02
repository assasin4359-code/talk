class_name BTGFakeVoice
extends Node
## Animal-Crossing-style fake voice (handoff §9). Hooked to the dialogue box's
## character_revealed signal: every revealed syllable plays a short vowel blip in the
## speaker's voice profile. Hangul syllables pick the blip from their vowel (ㅏ/ㅐ/ㅣ/ㅗ/ㅜ
## families), so lines rise and fall like speech instead of beeping on one note.
## Speakers without a profile (the player) stay silent.

signal blipped(speaker: String, vowel: int)

const VOICE_DIR := "res://assets/audio/voices/%s.tres"
const DEFAULT_CPS := 28.0
const A := 0
const E := 1
const I := 2
const O := 3
const U := 4
## Hangul medial vowel (jungseong index 0..20) -> blip sample index.
const VOWEL_OF_JUNG := [
	A, E, A, E, O, E, O, E,  # ㅏ ㅐ ㅑ ㅒ ㅓ ㅔ ㅕ ㅖ
	O, A, E, E, O, U, O, E,  # ㅗ ㅘ ㅙ ㅚ ㅛ ㅜ ㅝ ㅞ
	I, U, U, I, I,  # ㅟ ㅠ ㅡ ㅢ ㅣ
]

var _profiles := {}  # voice id -> BTGVoiceProfile (or null if missing)
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer
var _syllables := 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.max_polyphony = 4  # blips overlap a little at fast speech rates
	add_child(_player)


func profile_for(speaker: String) -> BTGVoiceProfile:
	var voice: String = Narrative.db.targets.get(speaker, {}).get("voice", "")
	if voice == "":
		return null
	if not _profiles.has(voice):
		var path := VOICE_DIR % voice
		_profiles[voice] = load(path) if ResourceLoader.exists(path) else null
	return _profiles[voice]


## Typewriter speed for a speaker (the dialogue box asks this per line).
func chars_per_second(speaker: String) -> float:
	var p := profile_for(speaker)
	return p.chars_per_second if p != null else DEFAULT_CPS


func on_character(speaker: String, character: String) -> void:
	var p := profile_for(speaker)
	if p == null:
		return
	var vowel := vowel_of(character)
	if vowel < 0:
		return
	_syllables += 1
	if _syllables % maxi(p.blip_every, 1) != 0:
		return
	blipped.emit(speaker, vowel)
	p.play_on(_player, _rng, vowel)


## Blip index for one character: Hangul -> its vowel family, Latin letters/digits ->
## something stable, everything else (spaces, punctuation, "……") -> -1 (no sound).
static func vowel_of(character: String) -> int:
	if character.is_empty():
		return -1
	var c := character.unicode_at(0)
	if c >= 0xAC00 and c <= 0xD7A3:
		return VOWEL_OF_JUNG[((c - 0xAC00) / 28) % 21]
	if (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A):
		return c % 5
	return -1
