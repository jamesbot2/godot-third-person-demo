class_name BackwardGait
extends RefCounted
## Authored BACKWARD gait derived from a CC0 forward locomotion clip (UAL1
## Standard). Backpedal used to play the forward clip in reverse. Measured
## backward-gait hip/knee kinematics are close to a time-reversed forward
## gait, so this keeps that base and fixes the parts that read wrong:
##  * jog/sprint: the end of stance (front foot) stays on the forefoot with a
##    bent knee (backward RUNNING does not land/leave on the heel); walk keeps
##    the reversed heel-last lift-off (backward WALKING does leave heel-last).
##  * swing: the reversed knee drive in front is damped - the thigh is pulled
##    toward the source's passing frame (kd weight, sine bump over the front
##    part of the swing), so the knee no longer rises high in front of the
##    hips. The rear part of the swing and the toe landing are the source's
##    own frames played in reverse (matched ground speed at contact).
## build() bakes a new clip at 60 keys/s that is played FORWARD while the
## body moves backward (bwd(u) = src(L - u) + leg edits); arms/torso are the
## source's own. Landmarks measured on the source clips (tools/_bwd_probe.gd):
## lo = toe-off (normalized forward clip), mid = swing frame where the knee
## passes under the hip, push = stance frame used for the bent push-off knee,
## pw/kw = push-off foot/knee weights, kd = knee-drive damping weight.
## Honest limit: knee lead ahead of the hips drops 0.36 -> ~0.30 m in the
## backpedal test, a modest change; the leg still sweeps back quickly in the
## middle of a jog swing (inherited from the source's fast forward recovery).
const LEG := {"thigh": 0, "calf": 1, "foot": 2, "ball": 3}
const PARAMS := {
	"walk": {"lo": 0.59, "mid": 0.68, "push": 0.12, "pw": 0.0, "kw": 0.0, "kd": 0.6},
	"jog": {"lo": 0.20, "mid": 0.57, "push": 0.05, "pw": 0.6, "kw": 0.3, "kd": 0.75},
	"sprint": {"lo": 0.20, "mid": 0.54, "push": 0.05, "pw": 0.6, "kw": 0.3, "kd": 0.75},
}
const FPS := 60.0
## right leg phase relative to the left (normalized cycle)
const R_OFF := 0.5


static func build(src: Animation, clip: String = "jog") -> Animation:
	var p: Dictionary = PARAMS.get(clip, PARAMS["jog"])
	var lo: float = p["lo"]
	var L := src.length
	var out := Animation.new()
	out.length = L
	out.loop_mode = src.loop_mode
	var n := int(ceil(L * FPS))
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		var path := src.track_get_path(i)
		var bone := str(path).get_slice(":", 1)
		var j := out.add_track(ty)
		out.track_set_path(j, path)
		out.track_set_interpolation_type(j, src.track_get_interpolation_type(i))
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_SCALE_3D:
			for k in src.track_get_key_count(i):   # (none expected) copy as-is
				out.track_insert_key(j, src.track_get_key_time(i, k), src.track_get_key_value(i, k))
			continue
		var part := bone.get_slice("_", 0)
		var side := bone.get_slice("_", 1)
		var is_leg := ty == Animation.TYPE_ROTATION_3D and LEG.has(part) and (side == "l" or side == "r") and bone.get_slice_count("_") == 2
		var off := R_OFF if side == "r" else 0.0
		for k in n + 1:
			var u := L * float(k) / n
			var ts := fposmod(L - u, L) if k < n else 0.0
			if k == n:
				ts = 0.0
			var v: Variant
			if not is_leg:
				v = _sample(src, i, ty, ts)
			else:
				var tau := fposmod(ts / L - off, 1.0)
				if k == n:
					tau = fposmod(-off, 1.0)
				v = _leg(src, i, part, tau, off, p)
			match ty:
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(j, u, v)
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(j, u, v)
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(j, u, v)
	return out


static func _sample(src: Animation, i: int, ty: int, t: float) -> Variant:
	match ty:
		Animation.TYPE_ROTATION_3D:
			return src.rotation_track_interpolate(i, t)
		Animation.TYPE_POSITION_3D:
			return src.position_track_interpolate(i, t)
	return src.scale_track_interpolate(i, t)


static func _rot(src: Animation, i: int, tau: float, off: float) -> Quaternion:
	return src.rotation_track_interpolate(i, fposmod(tau + off, 1.0) * src.length)


## push-off pose of one leg bone (stance end, foot in front)
static func _push(src: Animation, i: int, part: String, off: float, p: Dictionary) -> Quaternion:
	var q0 := _rot(src, i, 0.0, off)
	match part:
		"calf":
			return q0.slerp(_rot(src, i, p["push"], off), p["kw"])
		"foot", "ball":
			return q0.slerp(_rot(src, i, p["lo"] + 0.03, off), p["pw"])
	return q0


static func _leg(src: Animation, i: int, part: String, tau: float, off: float, p: Dictionary) -> Quaternion:
	var lo: float = p["lo"]
	if tau <= lo:
		# stance (reversed: lands behind at tau=lo, pushes off in front at 0)
		return _stance_mod(src, i, part, tau, off, p)
	# swing: the source swing in reverse (the time reverse of a forward swing
	# is close to measured backward-gait hip/knee kinematics: the foot is
	# lifted by hip flexion in front, swept back, and set down toe-first
	# behind), with the reversed knee drive damped: the thigh is pulled toward
	# the source passing frame through the front half of the swing
	var q := _rot(src, i, tau, off)
	var q_push := _push(src, i, part, off, p)
	# keep the push-off pose continuous into the swing
	var wl := 1.0 - smoothstep(1.0 - (1.0 - lo) * 0.2, 1.0, tau)
	q = q_push.slerp(q, wl) if tau > 1.0 - (1.0 - lo) * 0.2 else q
	if part != "thigh":
		return q
	var mid: float = p["mid"]
	if tau <= mid:
		return q
	var x := (1.0 - tau) / (1.0 - mid)
	return q.slerp(_rot(src, i, mid, off), p["kd"] * sin(PI * x))


static func _stance_mod(src: Animation, i: int, part: String, tau: float, off: float, p: Dictionary) -> Quaternion:
	var q := _rot(src, i, tau, off)
	var wp := 1.0 - smoothstep(0.0, p["lo"] * 0.45, tau)
	if wp <= 0.0 or part == "thigh":
		return q
	var tgt := _rot(src, i, p["push"] if part == "calf" else p["lo"] + 0.03, off)
	return q.slerp(tgt, wp * (p["kw"] if part == "calf" else p["pw"]))


## plain time-reversed copy (A/B reference): rev(u) = src(L - u)
static func reversed(src: Animation) -> Animation:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	var L := src.length
	var n := int(ceil(L * FPS))
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		var j := out.add_track(ty)
		out.track_set_path(j, src.track_get_path(i))
		for k in n + 1:
			var u := L * float(k) / n
			var v: Variant = _sample(src, i, ty, fposmod(L - u, L) if k < n else 0.0)
			match ty:
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(j, u, v)
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(j, u, v)
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(j, u, v)
	return out
