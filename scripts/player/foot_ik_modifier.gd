class_name FootIKModifier
extends SkeletonModifier3D
## Foot locking + foot placement, applied after BodyPoseModifier on the
## final animated pose (pure presentation, never moves the body).
##
## Per foot:
##   * stance detection from the ANIMATED contact height (ball / ankle above
##     the animation ground, with hysteresis);
##   * lock: when a foot plants, its ball point is pinned in WORLD space for
##     the rest of the stance (kills residual stride/blend slip). The pin is
##     released when the animation lifts the foot, the leg would over-stretch
##     (max_lock_offset) or the body has yawed too far (turn in place); the
##     accumulated offset then decays back to the animated foot during swing
##     (with a small lift if it has to catch up while still low);
##   * placement: down raycasts under ankle and ball give the real ground, the
##     foot keeps its animated clearance above it, the sole is clamped above it
##     (no toe / heel penetration) and the planted foot is tilted to the
##     ground normal;
## Pelvis: lowered by the amount the lower foot needs (stairs / slopes) and
## any reach deficit, so the downhill leg is not over-stretched.
## Legs: analytic two-bone IK (thigh / calf), knee kept in the animated knee
## plane, foot keeps its animated world orientation (+ tilt / toe clamp).
##
## Skeleton space = glTF character space (+Y up, faces +Z).

const ANKLE_REST := 0.0865      # foot_l rest height above the animation ground
const BALL_REST := 0.0152       # ball_l rest height
const ANKLE_MIN := 0.093        # ankle joint -> sole (heel) clearance
const BALL_MIN := 0.024         # ball joint -> sole clearance
const PLANT_H := 0.03           # animated contact height to plant
const RELEASE_H := 0.06         # ... to release (default)
## release height actually used (the animator lowers it for reverse playback)
var release_h := RELEASE_H
const SIDES: Array[String] = ["l", "r"]

## 0..1 overall weight (animator fades it with the ground state)
var space_provider: Node = null   # CharacterAnimator (render_xf)
var weight := 0.0
## allow locking (0 disables only the pin, placement still runs)
var lock_enabled := true
var max_lock_offset := 0.24
var max_lock_yaw := 0.6
## standing turn (turn in place): a pinned foot whose body has yawed this far
## steps around (settle step with lift arc) instead of breaking; the feet step
## one at a time unless the twist reaches max_lock_yaw_stand
var turn_step_yaw := 0.45
var max_lock_yaw_stand := 1.2
## a pinned foot left this far below the body (stairs: the clip stride spans
## two treads) is released and steps up instead of crouching the pelvis
var max_lock_drop := 0.34
var max_pelvis_drop := 0.26
var dt := 1.0 / 60.0
var collision_mask := 1
var exclude: Array[RID] = []
var ray_up := 0.55
var ray_down := 0.75

# per-foot state
var planted: Array[bool] = [false, false]
var cooldown: Array[bool] = [false, false]
var lock_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # world, ball point
var lock_yaw: Array[float] = [0.0, 0.0]
var offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]     # world xz display offset of the foot
var ground_s: Array[float] = [0.0, 0.0]                     # smoothed support height (skeleton space)
var plant_w: Array[float] = [0.0, 0.0]
var pelvis_off := 0.0
var _init_ground := false
## swing detection: world-space speed of the UNLOCKED animated ball. In stance
## the clip ball is (nearly) still in the world; in swing it travels at ~2x
## body speed. A planted foot is released normally (no break, no pop) once
## the clip clearly says "swing" even if the ball is still low (toe-off, and
## reverse playback where the low part of the swing comes first).
var swing_speed := 1.1
var _prev_bw: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _clip_v: Array[float] = [0.0, 0.0]
var _prev_root := Vector3.ZERO
var _root_v := 0.0
## only near-break stances are released this way; normal stances end on height
var swing_min_offset := 0.18
var swing_hold: Array[bool] = [false, false]
## scale of the swing-release lift arc (the animator lowers it while
## backpedalling: the clip already lifts the foot behind the body, and an extra
## arc at toe-off, with the foot still in FRONT, threw the knee forward)
var swing_arc_scale := 1.0
## procedural step arc: a foot that is released while still on the ground
## (swing release, settle step, lock break) is lifted in proportion to the
## distance it still has to travel, so it never skates flat across the floor
var _lift: Array[float] = [0.0, 0.0]
## settle step (standing still): set when a pinned foot is re-placed onto the
## idle pose; cleared once it has arrived
var settle: Array[bool] = [false, false]
var debug := {}

var _b := {}


func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone(n)
	return _b[n]


func _gp(sk: Skeleton3D, b: int) -> Transform3D:
	return sk.get_bone_global_pose(b)


func _set_global_basis(sk: Skeleton3D, bone: int, basis: Basis) -> void:
	var p := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	var local := pg.basis.orthonormalized().inverse() * basis.orthonormalized()
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


func _rot_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var g := sk.get_bone_global_pose(bone)
	_set_global_basis(sk, bone, Basis(q) * g.basis.orthonormalized())


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	return space.intersect_ray(q)


## Forget pins / offsets (teleports, respawn).
func reset() -> void:
	for i in 2:
		planted[i] = false
		cooldown[i] = false
		offset[i] = Vector3.ZERO
		plant_w[i] = 0.0
		swing_hold[i] = false
		settle[i] = false
		_clip_v[i] = 0.0
	pelvis_off = 0.0
	_init_ground = false


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if weight <= 0.001:
		for i in 2:
			planted[i] = false
			cooldown[i] = false
			offset[i] = Vector3.ZERO
			plant_w[i] = 0.0
			swing_hold[i] = false
			settle[i] = false
			_clip_v[i] = 0.0
		pelvis_off = 0.0
		_init_ground = false
		debug = {"planted": [false, false], "pelvis": 0.0}
		return
	# solve in the frame the skeleton is DRAWN in (physics interpolation on;
	# see CharacterAnimator.render_xf)
	var xf: Transform3D = space_provider.render_xf(sk) if space_provider else sk.global_transform
	var inv := xf.affine_inverse()
	var space := sk.get_world_3d().direct_space_state
	var sk_yaw := atan2(xf.basis.z.x, xf.basis.z.z)
	var k_ground := 1.0 - exp(-22.0 * dt)
	var k_rise := 1.0 - exp(-60.0 * dt)
	var decay := exp(-11.0 * dt)
	if _init_ground:
		var rv := Vector2(xf.origin.x - _prev_root.x, xf.origin.z - _prev_root.z).length() / maxf(dt, 1e-4)
		_root_v = lerpf(_root_v, rv if rv < 25.0 else _root_v, 1.0 - exp(-20.0 * dt))
	_prev_root = xf.origin
	var swing_thr := maxf(swing_speed, 0.5 + 0.6 * _root_v)
	var tgt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var gnd_n: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var gball: Array[float] = [0.0, 0.0]
	var gank: Array[float] = [0.0, 0.0]
	var anim_ank: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var dg: Array[float] = [0.0, 0.0]
	var fbasis: Array[Basis] = [Basis(), Basis()]
	for i in 2:
		var s: String = SIDES[i]
		var A := _gp(sk, _bone("foot_" + s)).origin
		var B := _gp(sk, _bone("ball_" + s)).origin
		anim_ank[i] = A
		var hc := minf(B.y - BALL_REST, A.y - ANKLE_REST)
		var Bw := xf * B
		var cv := 0.0
		if _init_ground:
			cv = Vector2(Bw.x - _prev_bw[i].x, Bw.z - _prev_bw[i].z).length() / maxf(dt, 1e-4)
			if cv > 25.0:
				cv = 0.0
		_prev_bw[i] = Bw
		_clip_v[i] = lerpf(_clip_v[i], cv, 1.0 - exp(-30.0 * dt))
		if swing_hold[i] and not settle[i] and (hc > release_h or _clip_v[i] < swing_thr * 0.5 or _root_v < 0.35):
			swing_hold[i] = false
		if settle[i] and Vector2(offset[i].x, offset[i].z).length() < 0.01:
			settle[i] = false
			swing_hold[i] = false
		# ---- stance / lock state machine (world space)
		if cooldown[i] and (hc > release_h or Vector2(offset[i].x, offset[i].z).length() < 0.03):
			cooldown[i] = false
		if planted[i]:
			var o: Vector3 = lock_pos[i] - Bw
			o.y = 0.0
			var yaw_d := absf(wrapf(sk_yaw - lock_yaw[i], -PI, PI))
			if hc > release_h or not lock_enabled or weight < 0.5:
				planted[i] = false
			elif _root_v >= 0.35 and absf(ground_s[i]) < 0.05 and o.length() > swing_min_offset and (_clip_v[i] > swing_thr or hc > PLANT_H):
				planted[i] = false
				swing_hold[i] = true
			elif _root_v < 0.35 and (o.length() > 0.2 or (o.length() > 0.05 and _clip_v[i] < 0.3) \
					or (yaw_d > turn_step_yaw and not swing_hold[1 - i]) or yaw_d > max_lock_yaw_stand):
				# standing still: keep the foot pinned while the clip blends
				# into idle, then re-place it with a small procedural step
				# (lifted arc) instead of skating it across the floor
				planted[i] = false
				swing_hold[i] = true
				settle[i] = true
			elif o.length() > max_lock_offset or (yaw_d > max_lock_yaw and _root_v >= 0.35) or ground_s[i] < -max_lock_drop:
				planted[i] = false
				cooldown[i] = true
				if OS.has_environment("FOOTIK_DEBUG"):
					print("FOOTIK break ", s, " off=%.3f yaw=%.2f drop=%.2f cv=%.2f thr=%.2f rv=%.2f hc=%.3f" % [o.length(), yaw_d, ground_s[i], _clip_v[i], swing_thr, _root_v, hc])
			else:
				offset[i] = o
		elif lock_enabled and weight >= 0.5 and not cooldown[i] and not swing_hold[i] and hc < PLANT_H:
			planted[i] = true
			lock_pos[i] = Bw + offset[i]
			lock_yaw[i] = sk_yaw
		if not planted[i]:
			offset[i] *= decay
		plant_w[i] = lerpf(plant_w[i], 1.0 if planted[i] else 0.0, 1.0 - exp(-18.0 * dt))
		# ---- ground under the displayed foot
		var ow: Vector3 = offset[i]
		var aw := xf * A + ow
		var bw := Bw + ow
		var root_w := xf.origin
		var hit_a := _ray(space, Vector3(aw.x, root_w.y + ray_up, aw.z), Vector3(aw.x, root_w.y - ray_down, aw.z))
		var hit_b := _ray(space, Vector3(bw.x, root_w.y + ray_up, bw.z), Vector3(bw.x, root_w.y - ray_down, bw.z))
		var ga := (inv * (hit_a["position"] as Vector3)).y if hit_a else 0.0
		var gb := (inv * (hit_b["position"] as Vector3)).y if hit_b else 0.0
		var nrm := Vector3.UP
		if hit_b:
			nrm = (inv.basis * (hit_b["normal"] as Vector3)).normalized()
		elif hit_a:
			nrm = (inv.basis * (hit_a["normal"] as Vector3)).normalized()
		var support := maxf(ga, gb)
		if not _init_ground:
			ground_s[i] = support
		else:
			# rise fast (a step edge under the foot must never be entered),
			# fall at the normal rate
			# (a PLANTED foot follows both ways at the fast rate: with the slow fall
			# a pinned ball on a stair tread hovered up to 8 cm while the
			# visual root rose onto the next step)
			ground_s[i] = lerpf(ground_s[i], support, k_rise if (support > ground_s[i] or planted[i]) else k_ground)
		gank[i] = ga
		gball[i] = gb
		gnd_n[i] = nrm
		# ---- final foot orientation: animated, tilted to the ground when
		# planted, then pitched up just enough to keep the ball above the sole
		var fb := _gp(sk, _bone("foot_" + s)).basis.orthonormalized()
		var tilt := plant_w[i] * 0.85
		if nrm.angle_to(Vector3.UP) < deg_to_rad(35.0) and tilt > 0.001:
			fb = Basis(Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP, nrm), tilt)) * fb
		var v := fb * (_gp(sk, _bone("foot_" + s)).basis.orthonormalized().inverse() * (B - A))
		# ---- target ankle (skeleton space)
		var lo := inv.basis * ow
		var lift := 0.0
		var lift_t := 0.0
		if swing_hold[i]:
			lift_t = minf(0.07, Vector2(ow.x, ow.z).length() * 0.6 + 0.03 * _clip_v[i]) * swing_arc_scale
		elif cooldown[i]:
			lift_t = minf(0.05, Vector2(ow.x, ow.z).length() * 0.4)
		_lift[i] = lerpf(_lift[i], lift_t, 1.0 - exp(-30.0 * dt))
		lift = _lift[i]
		var t := A + Vector3(lo.x, 0.0, lo.z)
		# break lift rides on the animated ankle (as before); the step arc of a
		# swing/settle release is added on top of the ground clamp so the
		# foot really leaves the floor
		var arc := lift if swing_hold[i] else 0.0
		t.y = A.y + ground_s[i] + (lift - arc)
		t.y = maxf(t.y, ga + ANKLE_MIN) + arc
		var req := gb + BALL_MIN
		if t.y + v.y < req and v.length() > 0.01:
			var e0 := asin(clampf(v.y / v.length(), -1.0, 1.0))
			var e1 := asin(clampf((req - t.y) / v.length(), -1.0, 1.0))
			var ax := v.cross(Vector3.UP)
			if ax.length() > 1e-4:
				var q := Quaternion(ax.normalized(), e1 - e0)
				fb = Basis(q) * fb
				v = q * v
		if planted[i]:
			# the pinned point is the ball: derive the ankle from it
			var lb := inv * lock_pos[i]
			t.x = lb.x - v.x
			t.z = lb.z - v.z
			# the derived ankle may sit over different ground (step edge)
			var tw := xf * t
			var h2 := _ray(space, Vector3(tw.x, root_w.y + ray_up, tw.z), Vector3(tw.x, root_w.y - ray_down, tw.z))
			if h2:
				t.y = maxf(t.y, (inv * (h2["position"] as Vector3)).y + ANKLE_MIN)
		tgt[i] = t
		fbasis[i] = fb
		dg[i] = t.y - A.y
	_init_ground = true
	# ---- pelvis: lower foot + reach deficit
	var need := maxf(0.0, -minf(dg[0], dg[1]))
	var pelvis := _bone("pelvis")
	for i in 2:
		var s: String = SIDES[i]
		var T := _gp(sk, _bone("thigh_" + s)).origin
		var K := _gp(sk, _bone("calf_" + s)).origin
		var L := T.distance_to(K) + K.distance_to(anim_ank[i])
		var d := T - tgt[i]
		var reach := d.length() - L * 0.985
		if reach > 0.0:
			need = maxf(need, reach / maxf(0.6, d.y / maxf(d.length(), 0.001)))
	need = minf(need, max_pelvis_drop)
	var rate := 14.0 if need > pelvis_off else 7.0
	pelvis_off = lerpf(pelvis_off, need, 1.0 - exp(-rate * dt))
	var w := clampf(weight, 0.0, 1.0)
	if pelvis_off * w > 0.0005:
		var pg := _gp(sk, pelvis)
		var par := sk.get_bone_parent(pelvis)
		var ppg := _gp(sk, par) if par >= 0 else Transform3D.IDENTITY
		var new_o := pg.origin + Vector3.DOWN * pelvis_off * w
		sk.set_bone_pose_position(pelvis, ppg.affine_inverse() * new_o)
	# ---- legs
	var pl: Array[bool] = [false, false]
	var err: Array[float] = [0.0, 0.0]
	var reach_err: Array[float] = [0.0, 0.0]
	for i in 2:
		var s: String = SIDES[i]
		var th := _bone("thigh_" + s)
		var ca := _bone("calf_" + s)
		var ft := _bone("foot_" + s)
		var ba := _bone("ball_" + s)
		var foot_basis := _gp(sk, ft).basis.orthonormalized()
		var A := _gp(sk, ft).origin
		var target: Vector3 = A.lerp(tgt[i], w)
		_solve_leg(sk, th, ca, ft, target)
		var fq := foot_basis.get_rotation_quaternion().slerp(fbasis[i].get_rotation_quaternion(), w)
		_set_global_basis(sk, ft, Basis(fq))
		_knee_out(sk, th, ca, ft, i, w)
		if w > 0.05:
			_post_clamp(sk, space, xf, inv, ft, ba, w)
		pl[i] = planted[i]
		var bf := xf * _gp(sk, ba).origin
		var af := xf * _gp(sk, ft).origin
		err[i] = Vector2(bf.x - lock_pos[i].x, bf.z - lock_pos[i].z).length() if planted[i] else -1.0
		reach_err[i] = af.distance_to(xf * target)
	debug = {"planted": pl, "pelvis": pelvis_off * w, "offset_l": offset[0], "offset_r": offset[1],
		"ground_l": ground_s[0], "ground_r": ground_s[1], "err": err, "reach_err": reach_err}


## after the solve the reachable ankle may differ from the target (leg fully
## stretched, the ankle swings toward the hip): re-check the final ankle and
## ball against the ground under them and correct the remaining penetration
func _post_clamp(sk: Skeleton3D, space: PhysicsDirectSpaceState3D, xf: Transform3D, inv: Transform3D, ft: int, ba: int, w: float) -> void:
	var th := sk.get_bone_parent(sk.get_bone_parent(ft))
	var ca := sk.get_bone_parent(ft)
	var A := _gp(sk, ft).origin
	var aw := xf * A
	var ha := _ray(space, Vector3(aw.x, xf.origin.y + ray_up, aw.z), Vector3(aw.x, xf.origin.y - ray_down, aw.z))
	if ha:
		var ga := (inv * (ha["position"] as Vector3)).y
		var dy := (ga + ANKLE_MIN - A.y) * w
		if dy > 0.002:
			var fb := _gp(sk, ft).basis
			_solve_leg(sk, th, ca, ft, A + Vector3(0.0, dy, 0.0))
			_set_global_basis(sk, ft, fb)
			A = _gp(sk, ft).origin
	var B := _gp(sk, ba).origin
	var bw := xf * B
	var hb := _ray(space, Vector3(bw.x, xf.origin.y + ray_up, bw.z), Vector3(bw.x, xf.origin.y - ray_down, bw.z))
	if hb:
		var req := (inv * (hb["position"] as Vector3)).y + BALL_MIN
		var v := B - A
		if B.y < req and v.length() > 0.01:
			var e0 := asin(clampf(v.y / v.length(), -1.0, 1.0))
			var e1 := asin(clampf((req - A.y) / v.length(), -1.0, 1.0))
			var ax := v.cross(Vector3.UP)
			if ax.length() > 1e-4:
				var q := Quaternion(ax.normalized(), (e1 - e0) * w)
				_set_global_basis(sk, ft, Basis(q) * _gp(sk, ft).basis.orthonormalized())


## Knee tracking: the jog clip (plus the hip warp) lets the knee drift up to
## ~3 cm inside the hip->ankle line (knock-kneed, worst right after a sharp
## turn). Swing the leg about the hip->ankle axis so the knee sits at least
## knee_out_min outside that line; the ankle lies on the axis so it does not
## move, and the foot keeps its world orientation.
var knee_out_min := 0.012


func _knee_out(sk: Skeleton3D, th: int, ca: int, ft: int, i: int, w: float) -> void:
	var T := _gp(sk, th).origin
	var K := _gp(sk, ca).origin
	var A := _gp(sk, ft).origin
	var hip := _gp(sk, _bone("thigh_r")).origin - _gp(sk, _bone("thigh_l")).origin
	hip.y = 0.0
	if hip.length() < 0.01 or A.distance_to(T) < 0.1:
		return
	var u := (A - T).normalized()
	var outp := hip.normalized() * (1.0 if i == 1 else -1.0)
	outp = outp - u * outp.dot(u)
	if outp.length() < 0.1:
		return
	outp = outp.normalized()
	var kp := K - T
	kp -= u * kp.dot(u)
	var r := kp.length()
	if r < 0.02:
		return   # leg (nearly) straight: no knee plane to swing
	var want := minf(knee_out_min, r * 0.5)
	var o := kp.dot(outp)
	if o >= want:
		return
	var ang := (asin(clampf(want / r, -1.0, 1.0)) - asin(clampf(o / r, -1.0, 1.0))) * w
	var q := Quaternion(u, ang)
	if (q * kp).dot(outp) < (Quaternion(u, -ang) * kp).dot(outp):
		q = Quaternion(u, -ang)
	var fb := _gp(sk, ft).basis.orthonormalized()
	_rot_global(sk, th, q)
	_set_global_basis(sk, ft, fb)


func _solve_leg(sk: Skeleton3D, th: int, ca: int, ft: int, target: Vector3) -> void:
	var T := _gp(sk, th).origin
	var K := _gp(sk, ca).origin
	var A := _gp(sk, ft).origin
	if A.distance_to(target) < 0.0005:
		return
	var a := T.distance_to(K)
	var b := K.distance_to(A)
	var to := target - T
	var c := clampf(to.length(), absf(a - b) + 0.002, a + b - 0.002)
	var dir := to.normalized()
	# bend direction: keep the animated knee plane, fall back to forward (+Z)
	var kp := K - T
	var bend := kp - dir * kp.dot(dir)
	var hint := Vector3(0, 0, 1) - dir * dir.z
	bend = bend + hint.normalized() * 0.01
	if bend.length() < 1e-5:
		return
	bend = bend.normalized()
	var cos_a := clampf((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
	var kn := T + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	var f0 := (K - T).normalized()
	var f1 := (kn - T).normalized()
	if f0.dot(f1) < 0.99999:
		_rot_global(sk, th, Quaternion(f0, f1))
	var K1 := _gp(sk, ca).origin
	var A1 := _gp(sk, ft).origin
	var p := T + dir * c
	var g0 := (A1 - K1).normalized()
	var g1 := (p - K1).normalized()
	if g0.dot(g1) < 0.99999:
		_rot_global(sk, ca, Quaternion(g0, g1))
