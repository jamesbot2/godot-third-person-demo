class_name ClipSampler
extends RefCounted
## Samples bone positions of a clip on the REAL character skeleton (rest
## bone lengths of the UBC body) without touching the live skeleton, so the
## traverse presentation can place the visual root from clip contacts
## (planted hand / planted feet) instead of guessing.
##
## Positions are returned in the CharacterAnimator's local frame (x = right,
## y = up, -z = forward), with the visual root (animator origin) at 0.

const RATE := 60.0

var t_len := 0.0
var pts := {}   # bone name -> PackedVector3Array (one per 1/RATE s)


static func sample(skel: Skeleton3D, to_anim: Transform3D, anim: Animation, bones: PackedStringArray) -> ClipSampler:
	var s := ClipSampler.new()
	s.t_len = anim.length
	var n := skel.get_bone_count()
	var rot_tr := {}
	var pos_tr := {}
	for i in anim.get_track_count():
		var bn := String(anim.track_get_path(i)).get_slice(":", 1)
		var b := skel.find_bone(bn)
		if b < 0:
			continue
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			rot_tr[b] = i
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			pos_tr[b] = i
	for bn in bones:
		s.pts[bn] = PackedVector3Array()
	var frames := int(ceil(anim.length * RATE)) + 1
	var g: Array[Transform3D] = []
	g.resize(n)
	for f in frames:
		var t := minf(f / RATE, anim.length)
		for b in n:   # parents precede children in this skeleton
			var r := skel.get_bone_rest(b)
			var q := r.basis.get_rotation_quaternion()
			var o := r.origin
			if rot_tr.has(b):
				q = anim.rotation_track_interpolate(rot_tr[b], t)
			if pos_tr.has(b):
				o = anim.position_track_interpolate(pos_tr[b], t)
			var l := Transform3D(Basis(q), o)
			var p := skel.get_bone_parent(b)
			g[b] = l if p < 0 else g[p] * l
		for bn in bones:
			s.pts[bn].append(to_anim * g[skel.find_bone(bn)].origin)
	return s


func at(bone: String, t: float) -> Vector3:
	var a: PackedVector3Array = pts[bone]
	var x := clampf(t, 0.0, t_len) * RATE
	var i := mini(int(x), a.size() - 2)
	return a[i].lerp(a[i + 1], clampf(x - i, 0.0, 1.0))


## lowest point among the given bones (y) at time t
func min_y(bones: PackedStringArray, t: float) -> float:
	var m := INF
	for b in bones:
		m = minf(m, at(b, t).y)
	return m


## Sole depth below each foot joint on the UBC body (ball / ankle), used to
## turn joint heights into contact heights.
const SOLE := {"ball_l": 0.024, "ball_r": 0.024, "foot_l": 0.093, "foot_r": 0.093}


## lowest SOLE point (joint height minus its sole depth) at time t
func sole_min(t: float) -> float:
	var m := INF
	for b in SOLE:
		m = minf(m, at(b, t).y - SOLE[b])
	return m
