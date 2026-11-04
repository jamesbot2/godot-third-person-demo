class_name BodyPoseModifier
extends SkeletonModifier3D
## Procedural layer applied AFTER the AnimationTree pose (pure presentation):
##   * bank: whole-body roll about the ground contact point (root bone pivot)
##   * lean: forward/back pitch distributed over the spine (accel / braking)
##   * orientation warp: pelvis (and so the legs) yawed toward the velocity
##     direction, spine + neck counter-rotated so the chest/head keep facing
##   * pelvis_drop: lowers the pelvis on slopes/stairs so the downhill foot
##     does not float
## Skeleton space here is the glTF character space: +Y up, character faces +Z,
## character's right is -X.

var bank := 0.0          # rad, + = lean to the character's right
var pitch := 0.0         # rad, + = lean forward
var warp := 0.0          # rad, + = legs turned to the character's left (CCW from above)
var pelvis_drop := 0.0   # m
var head_pitch := 0.0    # rad, small head stabilisation

var _b := {}


func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone(n)
	return _b[n]


func _rot_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	# Rotate `bone` about its own origin by skeleton-space rotation q.
	var g := sk.get_bone_global_pose(bone)
	var ng := Transform3D(Basis(q) * g.basis, g.origin)
	var p := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	var local := pg.affine_inverse() * ng
	sk.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var up := Vector3.UP
	var fwd := Vector3(0, 0, 1)
	var left := Vector3(1, 0, 0)   # rotating +angle about +X tips +Y toward +Z (forward)
	var pelvis := _bone("pelvis")
	if absf(pelvis_drop) > 0.0005:
		sk.set_bone_pose_position(pelvis, sk.get_bone_pose_position(pelvis) + _root_space_down(sk) * pelvis_drop)
	# Bank + a little of the pitch at the root (pivot = ground point between the feet).
	var root := _bone("root")
	var q_root := Quaternion(fwd, bank) * Quaternion(left, pitch * 0.25)
	if not q_root.is_equal_approx(Quaternion.IDENTITY):
		_rot_global(sk, root, q_root)
	if absf(warp) > 0.0005:
		_rot_global(sk, pelvis, Quaternion(up, warp))
	var spine := ["spine_01", "spine_02", "spine_03", "neck_01"]
	var warp_share := [0.3, 0.3, 0.25, 0.15]
	var pitch_share := [0.3, 0.3, 0.15, 0.0]
	for i in spine.size():
		var b := _bone(spine[i])
		var q := Quaternion(up, -warp * warp_share[i]) * Quaternion(left, pitch * pitch_share[i])
		if i == 3:
			q = q * Quaternion(left, head_pitch - pitch * 0.4)
		if not q.is_equal_approx(Quaternion.IDENTITY):
			_rot_global(sk, b, q)


func _root_space_down(sk: Skeleton3D) -> Vector3:
	# pelvis position is expressed in the root bone's space (Z-up in the source rig)
	var rg := sk.get_bone_global_pose(_bone("root"))
	return rg.basis.inverse() * Vector3.DOWN
