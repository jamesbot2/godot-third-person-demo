class_name RollAuthoring
extends RefCounted
## Authored variant of the CC0 "Roll" clip (UAL1 Standard) for a GROUND
## forward roll. The source clip is a jumping dive roll: the legs stay
## extended and trail ~1 m above the floor while the body pitches over the
## hands, which reads as a flat "superman" dive once the visual root is
## grounded. Here the leg chain (thigh/calf/foot/ball local rotations) is
## slerped toward the clip's own deep-crouch frame through the dive and the
## shoulder roll, so the knees stay tucked to the chest; the clip's upper body
## (hand plant, chin tuck, shoulder roll) and its stand-up are kept.
## Result is a new in-memory Animation "roll_tuck"; nothing is written to disk.
## CharacterAnimator._cap_roll_pelvis then rounds the back (spine/neck curl,
## arms counter-rotated) and pitches the pelvis key-by-key so the pelvis
## stays low over the shoulders (needs the skeleton, so it runs there).

const LEG_BONES := ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
## clip time of the reference deep crouch (feet down, knees folded)
const REF_T := 0.93
## tuck weight ramps in over the take-off and out before the feet come down
const IN_T := Vector2(0.0, 0.16)
const OUT_T := Vector2(0.78, 0.9)


static func tuck_w(t: float) -> float:
	return smoothstep(IN_T.x, IN_T.y, t) * (1.0 - smoothstep(OUT_T.x, OUT_T.y, t))


static func build(src: Animation) -> Animation:
	var a: Animation = src.duplicate(true)
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(a.track_get_path(i)).get_slice(":", 1)
		if bone not in LEG_BONES:
			continue
		var ref: Quaternion = src.rotation_track_interpolate(i, REF_T)
		for k in a.track_get_key_count(i):
			var t := a.track_get_key_time(i, k)
			var w := tuck_w(t)
			if w <= 0.0:
				continue
			var q: Quaternion = a.track_get_key_value(i, k)
			a.track_set_key_value(i, k, q.slerp(ref, w))
	return a
