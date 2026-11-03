extends SceneTree
## Retarget CC0 Quaternius clips redistributed by Drawcall Market (normalized
## VRM-style humanoid node hierarchy, no skin) onto the UAL/UBC 65-bone UE
## skeleton. Offline build step; outputs are committed.
##
##   godot --headless --path . -s res://tools/retarget_drawcall.gd -- --src=/workspace/assets_raw [--calibrate]
##
## Method: the normalized clips were produced from the same Quaternius
## source rigs by a rotation-only re-basing, so for every bone there is a
## constant bone-local offset O_b with  G_ue(t) = W * G_src(t) * O_b.
## O_b is measured (and its constancy checked) on a clip that exists in both
## forms (UAL1 "Jog_Fwd" native vs Drawcall "jog-fwd-loop"); it is then
## applied to clips that only exist in the normalized form.

const MAP := {
	"hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "upperChest": "spine_03",
	"neck": "neck_01", "head": "Head",
	"leftShoulder": "clavicle_l", "leftUpperArm": "upperarm_l", "leftLowerArm": "lowerarm_l", "leftHand": "hand_l",
	"rightShoulder": "clavicle_r", "rightUpperArm": "upperarm_r", "rightLowerArm": "lowerarm_r", "rightHand": "hand_r",
	"leftUpperLeg": "thigh_l", "leftLowerLeg": "calf_l", "leftFoot": "foot_l", "leftToes": "ball_l",
	"rightUpperLeg": "thigh_r", "rightLowerLeg": "calf_r", "rightFoot": "foot_r", "rightToes": "ball_r",
	"leftThumbMetacarpal": "thumb_01_l", "leftThumbProximal": "thumb_02_l", "leftThumbDistal": "thumb_03_l",
	"rightThumbMetacarpal": "thumb_01_r", "rightThumbProximal": "thumb_02_r", "rightThumbDistal": "thumb_03_r",
	"leftIndexProximal": "index_01_l", "leftIndexIntermediate": "index_02_l", "leftIndexDistal": "index_03_l",
	"leftMiddleProximal": "middle_01_l", "leftMiddleIntermediate": "middle_02_l", "leftMiddleDistal": "middle_03_l",
	"leftRingProximal": "ring_01_l", "leftRingIntermediate": "ring_02_l", "leftRingDistal": "ring_03_l",
	"leftLittleProximal": "pinky_01_l", "leftLittleIntermediate": "pinky_02_l", "leftLittleDistal": "pinky_03_l",
	"rightIndexProximal": "index_01_r", "rightIndexIntermediate": "index_02_r", "rightIndexDistal": "index_03_r",
	"rightMiddleProximal": "middle_01_r", "rightMiddleIntermediate": "middle_02_r", "rightMiddleDistal": "middle_03_r",
	"rightRingProximal": "ring_01_r", "rightRingIntermediate": "ring_02_r", "rightRingDistal": "ring_03_r",
	"rightLittleProximal": "pinky_01_r", "rightLittleIntermediate": "pinky_02_r", "rightLittleDistal": "pinky_03_r",
}
# our name : [drawcall slug, loop]
const CLIPS := {
	"_check_jog": ["jog-fwd-loop", true],   # validation only, not saved
	"vault_safety": ["safety-vault-root-motion", false],
	"climb_ledge": ["climb-ledge", false],
	"climb_up_2m": ["climb-up-2m-root-motion", false],
	"jog_left": ["jog-left-loop", true],
	"jog_right": ["jog-right-loop", true],
	"jog_bwd": ["jog-bwd-loop", true],
	"walk_left": ["walk-l-loop", true],
	"walk_right": ["walk-right-loop", true],
	"walk_bwd": ["walk-bwd-loop", true],
	"turn90_l": ["turn90-l", false],
	"turn90_r": ["turn90-right", false],
	"turn180_l": ["turn180-left-root-motion-alternate-2", false],
	"turn180_r": ["turn180-r-rm", false],
}
const FPS := 60.0
const UBC_REL := "ubc/Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
const UAL1_REL := "ual1/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
const DC := "drawcall/"

var src := "/workspace/assets_raw/"
var offs_cache := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6).trim_suffix("/") + "/"
	_calibrate()
	if OS.get_cmdline_user_args().has("--build"):
		_build()
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--traj="):
			_traj(a.substr(7))
	quit()


func _traj(slug: String) -> void:
	var rig := _load(_dc_file(slug))
	var dap: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	var da := dap.get_animation(dap.get_animation_list()[0])
	var rr := dap.get_node(dap.root_node)
	print(slug, " len ", da.length)
	for f in 21:
		var t := da.length * f / 20.0
		var g := _src_globals(rr, da, t)
		print("t=%.2f hips=%s lhand=%s rhand=%s lfoot=%s rfoot=%s ltoe=%s" % [t, g["hips"].origin, g["leftHand"].origin, g["rightHand"].origin, g["leftFoot"].origin, g["rightFoot"].origin, g["leftToes"].origin])


func _probe() -> void:
	var ue := _load(src + "ual2/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb")
	var sk: Skeleton3D = ue.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = ue.find_children("*", "AnimationPlayer", true, false)[0]
	var na: Animation = ap.get_animation("ClimbUp_1m")
	var rig := _load(_dc_file("climb-up-1m-root-motion"))
	var dap: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	var da := dap.get_animation(dap.get_animation_list()[0])
	var rr := dap.get_node(dap.root_node)
	print("climb native len ", na.length, " rm len ", da.length)
	for f in 11:
		var t := na.length * f / 10.0
		var gs := _src_globals(rr, da, t)
		var gu := _ue_globals(sk, na, t)
		var e := 0.0
		for k in ["leftUpperArm", "leftLowerArm", "rightUpperLeg", "leftFoot", "head", "spine"]:
			var q: Quaternion = gs[k].basis.get_rotation_quaternion() * offs_cache[k]
			e = maxf(e, rad_to_deg(q.angle_to(gu[MAP[k]].basis.get_rotation_quaternion())))
		print("t=%.2f hips_rm=%s pelvis_native=%s lfoot_rm=%s lfoot_nat=%s rot_err_max=%.2f" % [t, gs["hips"].origin, gu["pelvis"].origin, gs["leftFoot"].origin, gu["foot_l"].origin, e])


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	assert(doc.append_from_file(path, st) == OK, path)
	var n := doc.generate_scene(st)
	return n


func _dc_file(slug: String) -> String:
	var d := src + DC + slug + "/public/humanoid-animation/"
	return d + DirAccess.get_files_at(d)[0]


## world transforms of the normalized node rig at time t
func _src_globals(rig: Node, a: Animation, t: float) -> Dictionary:
	var ap_root := rig
	for i in a.get_track_count():
		var np := a.track_get_path(i)
		var n := ap_root.get_node_or_null(NodePath(String(np).get_slice(":", 0))) as Node3D
		if n == null:
			continue
		match a.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				n.quaternion = a.rotation_track_interpolate(i, t)
			Animation.TYPE_POSITION_3D:
				n.position = a.position_track_interpolate(i, t)
	var out := {}
	for k in MAP:
		var n := rig.find_child(k, true, false) as Node3D
		if n:
			out[k] = _node_global(n)
	return out


## skeleton-space globals of the UE rig for a native clip at time t
func _ue_globals(sk: Skeleton3D, a: Animation, t: float) -> Dictionary:
	for b in sk.get_bone_count():
		sk.set_bone_pose(b, sk.get_bone_rest(b))
	for i in a.get_track_count():
		var bn := String(a.track_get_path(i)).get_slice(":", 1)
		var b := sk.find_bone(bn)
		if b < 0:
			continue
		match a.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(b, a.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(b, a.position_track_interpolate(i, t))
	var out := {}
	for k in MAP:
		out[MAP[k]] = _bone_global(sk, sk.find_bone(MAP[k]))
	return out


func _node_global(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _bone_global(sk: Skeleton3D, b: int) -> Transform3D:
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t


func _calibrate() -> void:
	var ue := _load(src + UAL1_REL)
	var sk: Skeleton3D = ue.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = ue.find_children("*", "AnimationPlayer", true, false)[0]
	var na: Animation = null
	for n in ap.get_animation_list():
		if n.begins_with("Jog_Fwd"):
			na = ap.get_animation(n)
	var rig := _load(_dc_file("jog-fwd-loop"))
	var dap: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	var da := dap.get_animation(dap.get_animation_list()[0])
	var rig_root := dap.get_node(dap.root_node)
	print("native len ", na.length, " dc len ", da.length, " dc root ", rig_root.name)
	var offs := {}
	for f in 8:
		var t := na.length * f / 8.0
		var gs := _src_globals(rig_root, da, t * da.length / na.length)
		var gu := _ue_globals(sk, na, t)
		for k in MAP:
			if not gs.has(k):
				continue
			var o: Quaternion = (gs[k].basis.get_rotation_quaternion().inverse() * gu[MAP[k]].basis.get_rotation_quaternion())
			if not offs.has(k):
				offs[k] = []
			offs[k].append(o)
		if f == 0:
			print("hips src ", gs["hips"].origin, "  pelvis ue ", gu["pelvis"].origin)
			print("lfoot src ", gs["leftFoot"].origin, "  foot_l ue ", gu["foot_l"].origin)
	for k in offs:
		offs_cache[k] = offs[k][0]
	for k in ["hips", "spine", "leftUpperArm", "leftLowerArm", "leftUpperLeg", "leftFoot", "head", "rightHand"]:
		var arr: Array = offs[k]
		var mx := 0.0
		for q in arr:
			mx = maxf(mx, rad_to_deg((q as Quaternion).angle_to(arr[0])))
		print("%s offset spread %.2f deg" % [k, mx])


## Bake every CLIPS entry into res://assets/animations/ual_clips.res (added to
## the library written by build_character_assets.gd; run that first).
## Output is in the same convention as the rest of the library: local bone
## rotations on the UAL/UE rest + pelvis position scaled by k. These clips have
## no root bone (Drawcall's normalized export drops it), i.e. they are
## in-place: no root motion exists to strip.
func _build() -> void:
	var ue := _load(src + UAL1_REL)
	var sk: Skeleton3D = ue.find_children("*", "Skeleton3D", true, false)[0]
	var ubc := _load(src + UBC_REL)
	var csk: Skeleton3D = ubc.find_children("*", "Skeleton3D", true, false)[0]
	var k := csk.get_bone_rest(csk.find_bone("pelvis")).origin.z / sk.get_bone_rest(sk.find_bone("pelvis")).origin.z
	var lib: AnimationLibrary = load("res://assets/animations/ual_clips.res")
	var root_g := sk.get_bone_rest(sk.find_bone("root"))
	var inv_map := {}
	for kk in MAP:
		inv_map[MAP[kk]] = kk
	for our in CLIPS:
		var spec: Array = CLIPS[our]
		var rig := _load(_dc_file(spec[0]))
		var dap: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
		var da := dap.get_animation(dap.get_animation_list()[0])
		var rr := dap.get_node(dap.root_node)
		var out := Animation.new()
		out.length = da.length
		out.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		var tr := {}
		for b in sk.get_bone_count():
			var bn := sk.get_bone_name(b)
			if bn == "root":
				continue
			var t := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t, "Armature/Skeleton3D:" + bn)
			out.track_set_interpolation_loop_wrap(t, spec[1])
			tr[bn] = t
			if not inv_map.has(bn):
				out.track_insert_key(t, 0.0, sk.get_bone_rest(b).basis.get_rotation_quaternion())
		var pt := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pt, "Armature/Skeleton3D:pelvis")
		out.track_set_interpolation_loop_wrap(pt, spec[1])
		var n := int(round(da.length * FPS))
		for f in n + 1:
			var time := minf(f / FPS, da.length)
			var gs := _src_globals(rr, da, time)
			var gq := {}
			for kk in MAP:
				gq[MAP[kk]] = gs[kk].basis.get_rotation_quaternion() * offs_cache[kk]
			for bn in gq:
				var b := sk.find_bone(bn)
				var par := sk.get_bone_parent(b)
				var pq: Quaternion = root_g.basis.get_rotation_quaternion() if sk.get_bone_name(par) == "root" else gq[sk.get_bone_name(par)]
				out.track_insert_key(tr[bn], time, (pq.inverse() * gq[bn]).normalized())
			out.track_insert_key(pt, time, (root_g.affine_inverse() * gs["hips"].origin) * k)
		if our == "_check_jog":
			_compare(out, lib.get_animation("jog"))
			continue
		if lib.has_animation(our):
			lib.remove_animation(our)
		lib.add_animation(our, out)
		print("baked ", our, " <- ", spec[0], " len=", snappedf(da.length, 0.01), " keys/track=", n + 1)
	var err := ResourceSaver.save(lib, "res://assets/animations/ual_clips.res", ResourceSaver.FLAG_COMPRESS)
	print("saved library: ", err, " k=", k)


func _compare(a: Animation, b: Animation) -> void:
	var worst := 0.0
	var wb := ""
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var j := b.find_track(a.track_get_path(i), Animation.TYPE_ROTATION_3D)
		if j < 0:
			continue
		for f in 10:
			var t := a.length * f / 10.0
			var d := rad_to_deg(a.rotation_track_interpolate(i, t).angle_to(b.rotation_track_interpolate(j, t)))
			if d > worst:
				worst = d
				wb = String(a.track_get_path(i))
	var pa := a.find_track("Armature/Skeleton3D:pelvis", Animation.TYPE_POSITION_3D)
	var pb := b.find_track("Armature/Skeleton3D:pelvis", Animation.TYPE_POSITION_3D)
	var pe := 0.0
	for f in 10:
		var t := a.length * f / 10.0
		pe = maxf(pe, a.position_track_interpolate(pa, t).distance_to(b.position_track_interpolate(pb, t)))
	print("VALIDATION retargeted jog-fwd-loop vs native Jog_Fwd: max local rot err %.3f deg (%s), pelvis pos err %.4f m" % [worst, wb, pe])
