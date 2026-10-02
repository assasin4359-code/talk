class_name BTGTweens
extends RefCounted
## Awaiting `tween.finished` after the tween already finished hangs forever — and two
## tweens ending in the same frame makes that easy to hit (a soft-lock in the faint/wake
## sequence). Always wait through this instead.


static func done(t: Tween) -> void:
	if t != null and t.is_valid() and t.is_running():
		await t.finished
