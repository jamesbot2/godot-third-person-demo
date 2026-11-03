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
const RELEASE_H := 0.06         # ... to release
const SIDES: Array[String] = ["l", "r"]

## 0..1 overall weight (animator fades it with the ground state)
var weight := 0.0
## allow locking (0 disables only the pin, placement still runs)
var lock_enabled := true
var max_lock_offset := 0.24
var max_lock_yaw := 0.6
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
		pelvis_off = 0.0
		_init_ground = false
		debug = {"planted": [false, false], "pelvis": 0.0}
		return
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	var space := sk.get_world_3d().direct_space_state
	var sk_yaw := atan2(xf.basis.z.x, xf.basis.z.z)
	var k_ground := 1.0 - exp(-22.0 * dt)
	var k_rise := 1.0 - exp(-60.0 * dt)
	var decay := exp(-11.0 * dt)
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
		# ---- stance / lock state machine (world space)
		if cooldown[i] and (hc > RELEASE_H or Vector2(offset[i].x, offset[i].z).length() < 0.03):
			cooldown[i] = false
		if planted[i]:
			var o: Vector3 = lock_pos[i] - Bw
			o.y = 0.0
			var yaw_d := absf(wrapf(sk_yaw - lock_yaw[i], -PI, PI))
			if hc > RELEASE_H or not lock_enabled or weight < 0.5:
				planted[i] = false
			elif o.length() > max_lock_offset or yaw_d > max_lock_yaw or ground_s[i] < -max_lock_drop:
				planted[i] = false
				cooldown[i] = true
			else:
				offset[i] = o
		elif lock_enabled and weight >= 0.5 and not cooldown[i] and hc < PLANT_H:
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
			ground_s[i] = lerpf(ground_s[i], support, k_rise if support > ground_s[i] else k_ground)
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
		if cooldown[i]:
			lift = minf(0.05, Vector2(ow.x, ow.z).length() * 0.4)
		var t := A + Vector3(lo.x, 0.0, lo.z)
		t.y = A.y + ground_s[i] + lift
		t.y = maxf(t.y, ga + ANKLE_MIN)
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
