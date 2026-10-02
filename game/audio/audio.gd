class_name BTGAudio
extends RefCounted
## Audio routing in one place. Bus tree (default_bus_layout.tres):
##   Master
##   ├─ World ─ Ambient, Footsteps, SFX     everything the world makes
##   ├─ Voice ─ NPCVoice, Narrator          the narrator must survive total silence
##   ├─ UI
##   └─ Music
## Total silence later = mute World/Music/NPCVoice/UI, keep Narrator.

const AMBIENT := &"Ambient"
const FOOTSTEPS := &"Footsteps"
const SFX := &"SFX"
const NPC_VOICE := &"NPCVoice"
const NARRATOR := &"Narrator"


## False when there is no real audio output (headless tests, captures). Callers still
## run their logic and emit their signals; they just skip play(). (A playback started
## on the Dummy driver is never cleaned up if its node is freed mid-sound.)
static func can_play() -> bool:
	return AudioServer.get_driver_name() != "Dummy"
