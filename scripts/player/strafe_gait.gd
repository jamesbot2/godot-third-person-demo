class_name StrafeGait
extends RefCounted
## Authored AIM locomotion set for the BlendSpace2D used while aiming (body
## locked to the camera). The core CC0 library (UAL1 Standard) has no
## strafe clips; before this the aimed strafe yawed the whole leg cycle 90 deg
## (orientation warp) under a counter-twisted spine. Here four phase-aligned
## clips of normalized length LEN are baked at load time on the real
## skeleton:
##  * aim_fwd / aim_bwd: the forward / authored-backward gait blended
##    (walk..jog, slerp at normalized phase - what the sync Blend2 plays) at
##    the gait weight the aim speed needs; rotated so the LEFT foot contact
##    is at phase 0. Round 6: legs re-solved like the strafe set (no
##    stagger, softer swing tangents) so the stance foot sweeps exactly the
##    aim stride (no clip slip at the source; AIM_FB_RAW=1 = old blend).
##  * all lateral clips: the hips counter-rotate (HIP_YAW) against the
##    clip's shoulder swing; spine_01 takes the inverse (chest unchanged).
##  * strafe_l / strafe_r: CROSS-STEP side gait. Upper body, arms and pelvis
##    motion are aim_fwd's own (CC0-derived); the legs are re-solved per key
##    with an analytic two-bone IK so the ankles follow an authored lateral
##    trajectory: the stance foot moves sideways at exactly one stride per
##    cycle (zero clip slip by construction when the cycle rate is
##    v / STRIDE_SIDE), the trailing foot crosses IN FRONT of the leading
##    one (z offsets + swing bulge), feet stay flat (idle sole orientation).
##    The pelvis drops where needed so the crossed legs reach (smoothed).
## Left foot contact is at phase 0 and right at 0.5 in all four clips, so
## the 2D blend never mixes mismatched phases (diagonals = blended
## trajectories).
## Positions here are SKELETON space (glTF: +Y up, faces +Z, right = -X).

const FPS := 60
const LEN := 1.0
## stance fraction of the cycle (jog-like strafe with a short flight)
const DUTY := 0.42
## swing apex lift of the ankle (m)
const LIFT := 0.10
## stance foot forward offsets (m): trailing foot crosses in front
const Z_TRAIL := 0.07
const Z_LEAD := -0.07
## extra forward (+) / backward (-) arc of the swing (m), so the crossing
## leg passes around the stance leg instead of through it
const BULGE_TRAIL := 0.07
const BULGE_LEAD := -0.04
## stance width scale vs the idle stance
const NARROW := 0.4
## swing end tangent scale for the side / diagonal set (1.0 = full stance
## velocity at lift-off / touchdown; less = less sideways overshoot -> a
## narrower widest stance)
const SIDE_TAN := 1.0
## back diagonals (backward base): stance fraction, lift (m), late lift like
## the backpedal so the rhythm matches its neighbours
const BD_DUTY := 0.40
const BD_LIFT := 0.09
const BD_SKEW := 1.6
## hip yaw amplitude (deg) at a pure side step (scaled by |dir.x|), against
## the clip's shoulder swing
const HIP_YAW := 7.0
## max hip->ankle reach as a fraction of the straight leg
const REACH := 0.965
## round 6 re-posed aim_fwd / aim_bwd (see build): stance fraction, swing
## lift (m), stance width scale, stance centre offset along the movement (m;
## 0 measured best for the backpedal swing knee)
const FB_DUTY := 0.42
const FB_DUTY_B := 0.38
const FB_LIFT_F := 0.16
const FB_LIFT_B := 0.08
const FB_NARROW := 0.75
const FB_C_F := 0.0
const FB_C_B := 0.0
## swing end tangents vs the stance velocity (less overshoot than strafe)
const FB_TAN := 0.35
## swing lift timing (peak at s = 0.5^(1/skew)): the forward swing lifts
## early (heel recovery behind the body), the backpedal swing late (the foot
## stays low while it is in front, lifts behind)
const FB_SKEW_F := 0.7
const FB_SKEW_B := 2.5


static func _track_map(skel: Skeleton3D, anim: Animation) -> Dictionary:
	var m := {}
	for i in anim.get_track_count():
		var bn := String(anim.track_get_path(i)).get_slice(":", 1)
		var b := skel.find_bone(bn)
		if b < 0:
			continue
		if not m.has(b):
			m[b] = {}
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			m[b]["r"] = i
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			m[b]["p"] = i
	return m


static func _locals(skel: Skeleton3D, anim: Animation, tm: Dictionary, t: float) -> Array:
	var out := []
	for b in skel.get_bone_count():
		var r := skel.get_bone_rest(b)
		var q := r.basis.get_rotation_quaternion()
		var o := r.origin
		if tm.has(b):
			if tm[b].has("r"):
				q = anim.rotation_track_interpolate(tm[b]["r"], t)
			if tm[b].has("p"):
				o = anim.position_track_interpolate(tm[b]["p"], t)
		out.append(Transform3D(Basis(q), o))
	return out


static func _fk(skel: Skeleton3D, loc: Array) -> Array:
	var g := []
	g.resize(loc.size())
	for b in loc.size():   # parents precede children in this skeleton
		var p := skel.get_bone_parent(b)
		g[b] = loc[b] if p < 0 else (g[p] as Transform3D) * (loc[b] as Transform3D)
	return g


## frames (FPS per LEN) of a slerp blend of two looping clips at normalized
## phase, starting at normalized phase `shift`
static func _blend_frames(skel: Skeleton3D, a: Animation, b: Animation, w: float, shift: float) -> Array:
	var ta := _track_map(skel, a)
	var tb := _track_map(skel, b)
	var fr := []
	for k in FPS:
		var u := fposmod(float(k) / FPS + shift, 1.0)
		var la := _locals(skel, a, ta, u * a.length)
		var lb := _locals(skel, b, tb, u * b.length)
		var o := []
		for i in la.size():
			var x: Transform3D = la[i]
			var y: Transform3D = lb[i]
			o.append(Transform3D(Basis(x.basis.get_rotation_quaternion().slerp(y.basis.get_rotation_quaternion(), w)), x.origin.lerp(y.origin, w)))
		fr.append(o)
	return fr


## blend + rotate so the left foot contact (front-most foot_l for a forward
## gait, rear-most for a backward one) lands on phase 0
static func aligned(skel: Skeleton3D, a: Animation, b: Animation, w: float, forward: bool) -> Array:
	var fr := _blend_frames(skel, a, b, w, 0.0)
	var fl := skel.find_bone("foot_l")
	var best := 0
	var bz := -INF
	for k in fr.size():
		var z: float = (_fk(skel, fr[k])[fl] as Transform3D).origin.z
		z = z if forward else -z
		if z > bz:
			bz = z
			best = k
	var out := []
	for k in fr.size():
		out.append(fr[(k + best) % fr.size()])
	return out


static func to_anim(skel: Skeleton3D, frames: Array, src: Animation) -> Animation:
	var tm := _track_map(skel, src)
	var out := Animation.new()
	out.length = LEN
	out.loop_mode = Animation.LOOP_LINEAR
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		var b := skel.find_bone(String(src.track_get_path(i)).get_slice(":", 1))
		if b < 0:
			continue
		var j := out.add_track(ty)
		out.track_set_path(j, src.track_get_path(i))
		out.track_set_interpolation_type(j, Animation.INTERPOLATION_LINEAR)
		for k in frames.size():
			var l: Transform3D = frames[k][b]
			var t := LEN * float(k) / frames.size()
			if ty == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(j, t, l.basis.get_rotation_quaternion())
			else:
				out.position_track_insert_key(j, t, l.origin)
	return out


## Two-bone leg solve on global poses: returns new [thigh, calf, foot]
## globals with the ankle at `tgt`, knee toward `pole`, foot basis `fb`.
static func _solve_leg(g: Array, ih: int, ik: int, ia: int, tgt: Vector3, pole: Vector3, fb: Basis, loc: Array) -> Array:
	var th: Transform3D = g[ih]
	var ca: Transform3D = g[ik]
	var H := th.origin
	var K := ca.origin
	var A := (g[ia] as Transform3D).origin
	var l1 := (K - H).length()
	var l2 := (A - K).length()
	var d := tgt - H
	var dl := clampf(d.length(), absf(l1 - l2) + 1e-4, (l1 + l2) * 0.9995)
	var dn := d.normalized()
	var pp := (pole - dn * pole.dot(dn)).normalized()
	var ca_ := clampf((l1 * l1 + dl * dl - l2 * l2) / (2.0 * l1 * dl), -1.0, 1.0)
	var K2 := H + dn * (l1 * ca_) + pp * (l1 * sqrt(1.0 - ca_ * ca_))
	var T2 := H + dn * dl
	var q1 := Quaternion((K - H).normalized(), (K2 - H).normalized())
	var th2 := Transform3D(Basis(q1) * th.basis, H)
	var ca2 := th2 * (loc[ik] as Transform3D)
	var A2 := (ca2 * (loc[ia] as Transform3D)).origin
	var q2 := Quaternion((A2 - K2).normalized(), (T2 - K2).normalized())
	ca2 = Transform3D(Basis(q2) * ca2.basis, ca2.origin)
	var ft := Transform3D(fb, (ca2 * (loc[ia] as Transform3D)).origin)
	return [th2, ca2, ft]


## Authored directional clip. `dir` = movement direction in skeleton space
## (ground plane, unit; right = -X). `stride` = distance per cycle along it
## in skeleton units, `unit` = metres per skeleton unit. Each stance foot
## moves along -dir at one stride per cycle; with a lateral component the
## trailing foot crosses in front (cross-step), scaled by |dir.x|.
static func dir_frames(skel: Skeleton3D, base: Array, idle_loc: Array, dvec: Vector3, stride: float, unit: float,
		duty := DUTY, lift := LIFT, narrow := NARROW, c_off := 0.0, tan := 1.0, stagger := true, skew := 1.0) -> Array:
	var b_pel := skel.find_bone("pelvis")
	var b_sp := skel.find_bone("spine_01")
	var ig := _fk(skel, idle_loc)
	var legs := {}
	for sd in ["l", "r"]:
		legs[sd] = {"h": skel.find_bone("thigh_" + sd), "k": skel.find_bone("calf_" + sd),
			"a": skel.find_bone("foot_" + sd), "ball": skel.find_bone("ball_" + sd)}
	var cross := absf(dvec.x)
	var sweep := stride * duty
	var n := base.size()
	# pass 1: ankle targets + needed pelvis drop
	var tg := []
	var drop := PackedFloat32Array()
	drop.resize(n)
	for k in n:
		var u := float(k) / n
		var g := _fk(skel, base[k])
		var t := {}
		var need := 0.0
		for sd in ["l", "r"]:
			var L: Dictionary = legs[sd]
			var ip: Vector3 = (ig[L["a"]] as Transform3D).origin
			var ya := ip.y
			ip.y = 0.0
			var c := (ip.dot(dvec) * narrow if stagger else 0.0) + c_off / unit
			var perp := (ip - dvec * ip.dot(dvec)) * narrow
			var trail := c < 0.0
			var p := fposmod(u - (0.0 if sd == "l" else 0.5), 1.0)
			var lat: float
			var h := 0.0
			var bul := 0.0
			if p < duty:
				lat = c + sweep * 0.5 - sweep * (p / duty)
			else:
				var s := (p - duty) / (1.0 - duty)
				# cubic Hermite with the stance velocity at both ends: no
				# velocity step at lift-off / touchdown (the foot keeps
				# moving back for a moment, then whips across)
				var m := -sweep / duty * (1.0 - duty) * tan
				var s2 := s * s
				var s3 := s2 * s
				lat = (2.0 * s3 - 3.0 * s2 + 1.0) * (c - sweep * 0.5) + (s3 - 2.0 * s2 + s) * m \
					+ (-2.0 * s3 + 3.0 * s2) * (c + sweep * 0.5) + (s3 - s2) * m
				h = lift / unit * pow(sin(PI * pow(s, skew)), 0.6)   # quick lift-off / set-down
				bul = (BULGE_TRAIL if trail else BULGE_LEAD) / unit * sin(PI * s) * cross
			var zoff := (Z_TRAIL if trail else Z_LEAD) / unit * cross + bul
			var tgt := dvec * lat + perp + Vector3(0, ya + h, zoff)
			t[sd] = tgt
			var H: Vector3 = (g[L["h"]] as Transform3D).origin
			var R := REACH * ((g[L["k"]] as Transform3D).origin.distance_to(H) + (g[L["a"]] as Transform3D).origin.distance_to((g[L["k"]] as Transform3D).origin))
			var hz := Vector2(tgt.x - H.x, tgt.z - H.z).length_squared()
			var vert := sqrt(maxf(R * R - hz, 0.0))
			need = maxf(need, (H.y - tgt.y) - vert)
		tg.append(t)
		drop[k] = maxf(need, 0.0)
	# smooth the drop (cyclic max then mean over +-5 keys) so it never jerks
	var mx := PackedFloat32Array()
	mx.resize(n)
	for k in n:
		var m := 0.0
		for o in range(-5, 6):
			m = maxf(m, drop[(k + o + n) % n])
		mx[k] = m
	var out := []
	for k in n:
		var dk := 0.0
		for o in range(-5, 6):
			dk += mx[(k + o + n) % n]
		dk /= 11.0
		var loc: Array = (base[k] as Array).duplicate()
		var gp := _fk(skel, loc)
		var par := skel.get_bone_parent(b_pel)
		var pb: Basis = (gp[par] as Transform3D).basis if par >= 0 else Basis.IDENTITY
		var pl: Transform3D = loc[b_pel]
		# hips counter-rotate under the (camera-locked) chest on lateral
		# steps: yaw opposite to the clip's shoulder swing, spine_01 takes the
		# inverse so the chest / arms / aim stay exactly as authored
		var hy := -HIP_YAW * cross * cos(TAU * float(k) / n) * (-1.0 if dvec.z < -0.01 else 1.0)   # backward base: shoulder swing is phase-flipped
		var hb := pl.basis
		if absf(hy) > 1e-5:
			hb = (pb.inverse() * Basis(Vector3.UP, deg_to_rad(hy)) * pb) * pl.basis
		loc[b_pel] = Transform3D(hb, pl.origin + pb.inverse() * Vector3(0, -dk, 0))
		if absf(hy) > 1e-5 and b_sp >= 0:
			var sp_g: Basis = (gp[b_sp] as Transform3D).basis
			var pel_g: Basis = pb * hb
			loc[b_sp] = Transform3D(pel_g.inverse() * sp_g, (loc[b_sp] as Transform3D).origin)
		var g := _fk(skel, loc)
		for sd in ["l", "r"]:
			var L: Dictionary = legs[sd]
			var side := 1.0 if sd == "l" else -1.0   # +X = character left
			var pole := Vector3(0.25 * side, 0, 1)
			var fb: Basis = (ig[L["a"]] as Transform3D).basis
			var r := _solve_leg(g, L["h"], L["k"], L["a"], tg[k][sd], pole, fb, loc)
			var hp: Transform3D = g[skel.get_bone_parent(L["h"])]
			loc[L["h"]] = Transform3D(hp.basis.inverse() * (r[0] as Transform3D).basis, (loc[L["h"]] as Transform3D).origin)
			loc[L["k"]] = Transform3D((r[0] as Transform3D).basis.inverse() * (r[1] as Transform3D).basis, (loc[L["k"]] as Transform3D).origin)
			loc[L["a"]] = Transform3D((r[1] as Transform3D).basis.inverse() * (r[2] as Transform3D).basis, (loc[L["a"]] as Transform3D).origin)
			loc[L["ball"]] = idle_loc[L["ball"]]
			g = _fk(skel, loc)
		out.append(loc)
	return out


## Blend-space points: name, 2D position (x = right, y = forward), stride
## key ("f" / "b" = the CC0 gait strides, else metres per cycle).
const POINTS := [
	["aim_fwd", Vector2(0, 1)], ["aim_diag_fr", Vector2(0.70710678, 0.70710678)],
	["strafe_r", Vector2(1, 0)], ["aim_diag_br", Vector2(0.70710678, -0.70710678)],
	["aim_bwd", Vector2(0, -1)], ["aim_diag_bl", Vector2(-0.70710678, -0.70710678)],
	["strafe_l", Vector2(-1, 0)], ["aim_diag_fl", Vector2(-0.70710678, 0.70710678)],
]


## Builds the aim set (POINTS) into `lib` (no-op if present). g_f / g_b:
## walk..jog gait weights for the aim forward / backpedal speed;
## side_m / diag_m: authored strides (m per cycle); f_m / b_m: the aim
## forward / backpedal strides (m per cycle) the re-posed aim_fwd / aim_bwd sweep.
static func build(skel: Skeleton3D, lib: AnimationLibrary, g_f: float, g_b: float, side_m: float, diag_m: float, unit: float, f_m: float = 2.0, b_m: float = 2.0, diag_b_m: float = 2.0) -> void:
	if lib.has_animation("strafe_r"):
		return
	var walk := lib.get_animation("walk")
	var fwd := aligned(skel, walk, lib.get_animation("jog"), g_f, true)
	var bwd := aligned(skel, lib.get_animation("walk_bwd"), lib.get_animation("jog_bwd"), g_b, false)
	var idle := lib.get_animation("idle")
	var idle_loc := _locals(skel, idle, _track_map(skel, idle), 0.0)
	if OS.get_environment("AIM_FB_RAW") == "1":
		lib.add_animation("aim_fwd", to_anim(skel, fwd, walk))
		lib.add_animation("aim_bwd", to_anim(skel, bwd, walk))
	else:
		# round 6: re-posed at the source like the strafe set (upper body,
		# arms, pelvis = the CC0 blend; legs re-solved, stance foot sweeps
		# exactly one stride per cycle -> no clip slip by construction)
		lib.add_animation("aim_fwd", to_anim(skel, dir_frames(skel, fwd, idle_loc, Vector3(0, 0, 1), f_m / unit, unit, FB_DUTY, FB_LIFT_F, FB_NARROW, FB_C_F, FB_TAN, false, FB_SKEW_F), walk))
		lib.add_animation("aim_bwd", to_anim(skel, dir_frames(skel, bwd, idle_loc, Vector3(0, 0, -1), b_m / unit, unit, FB_DUTY_B, FB_LIFT_B, FB_NARROW, FB_C_B, FB_TAN, false, FB_SKEW_B), walk))
	for pt in POINTS:
		var nm: String = pt[0]
		if lib.has_animation(nm):
			continue
		var v2: Vector2 = pt[1]
		var dv := Vector3(-v2.x, 0, v2.y)   # skeleton: right = -X, forward = +Z
		var back := v2.y < -0.01
		var st := (side_m if absf(v2.y) < 0.01 else (diag_b_m if back else diag_m)) / unit
		if back:
			lib.add_animation(nm, to_anim(skel, dir_frames(skel, bwd, idle_loc, dv, st, unit, BD_DUTY, BD_LIFT, NARROW, 0.0, SIDE_TAN, true, BD_SKEW), walk))
		else:
			lib.add_animation(nm, to_anim(skel, dir_frames(skel, fwd, idle_loc, dv, st, unit, DUTY, LIFT, NARROW, 0.0, SIDE_TAN), walk))
