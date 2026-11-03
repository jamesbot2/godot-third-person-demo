class_name CharacterAnimator
extends Node3D
## Skeletal character presentation for PlayerController (pure presentation:
## it never moves the body; the controller is the only authority on position).
##
##   Model (this)                       yaw-smoothed visual root
##    └ UBCMale (ubc_male.scn, yaw PI)   Quaternius UBC, 65-bone Skeleton3D
##       └ Armature/Skeleton3D
##          └ BodyPoseModifier          procedural lean / bank / warp / pelvis
##    └ AnimationPlayer                 library "": ual_clips.res (CC0 UAL1/2)
##    └ AnimationTree                   StateMachine (see _build_tree)
##
## No root motion is used anywhere: all clips are in-place, displacement
## always comes from the controller. Locomotion playback rate is derived from
## the real ground speed and the MEASURED stride of the blended clips
## (tools/measure_clips.gd), so planted feet do not slide. One-shot actions
## (roll, vault, mantle, slide entry, landing) are SEEKED from the
## controller's own progress (roll_time, traverse progress, slide_time,
## time since landing) so animation and physics cannot drift apart.

@export var controller_path: NodePath = ^".."

const CHAR_SCENE := preload("res://assets/characters/ubc_male/ubc_male.scn")
## Core clip library: Quaternius UAL1/UAL2 STANDARD clips (CC0, committed).
const CLIP_LIB := preload("res://assets/animations/ual_clips.res")
## Optional, LOCAL-ONLY extras (vault_safety, climb_up_2m, ...): paid-tier
## Quaternius clips re-uploaded by a third party, redistribution doubtful, so
## never committed (THIRD_PARTY.md). Built by tools/retarget_drawcall.gd.
## Without it the animator runs in CORE mode (procedural traverse on the
## Standard climb clip). UAL_EXTRAS=0 forces core mode for testing.
const EXTRA_LIB_PATH := "res://assets/animations/local/ual_extra.res"
static var _lib_cache: AnimationLibrary
static var _lib_has_extras := false


## Core library merged with the optional local extras (cached).
static func clip_library() -> AnimationLibrary:
	if _lib_cache:
		return _lib_cache
	var want := OS.get_environment("UAL_EXTRAS") != "0"
	if not want or not ResourceLoader.exists(EXTRA_LIB_PATH):
		_lib_cache = CLIP_LIB
		_lib_has_extras = false
		_add_authored(_lib_cache)
		print("INFO|anim_library=core (CC0 Standard clips only)")
		return _lib_cache
	var lib := AnimationLibrary.new()
	for n in CLIP_LIB.get_animation_list():
		lib.add_animation(n, CLIP_LIB.get_animation(n))
	var ex: AnimationLibrary = load(EXTRA_LIB_PATH)
	for n in ex.get_animation_list():
		if not lib.has_animation(n):
			lib.add_animation(n, ex.get_animation(n))
	_lib_has_extras = lib.has_animation("vault_safety") and lib.has_animation("climb_up_2m")
	_lib_cache = lib
	_add_authored(lib)
	print("INFO|anim_library=", "core+local_extras" if _lib_has_extras else "core")
	return lib
## In-memory authored variants of CC0 clips (see roll_authoring.gd).
static func _add_authored(lib: AnimationLibrary) -> void:
	if not lib.has_animation("roll_tuck"):
		# ROLL_UNTUCKED=1: A/B measurement against the raw source clip
		var raw := OS.get_environment("ROLL_UNTUCKED") == "1"
		lib.add_animation("roll_tuck", lib.get_animation("roll").duplicate() if raw else RollAuthoring.build(lib.get_animation("roll")))
	# backward gait (see backward_gait.gd); BWD_RAW=1: plain time-reversed
	# clips for A/B measurement
	var bwd_raw := OS.get_environment("BWD_RAW") == "1"
	for c in ["walk", "jog", "sprint"]:
		if not lib.has_animation(c + "_bwd"):
			var src := lib.get_animation(c)
			lib.add_animation(c + "_bwd", BackwardGait.reversed(src) if bwd_raw else BackwardGait.build(src, c))


const BodyPoseModifierScript := preload("res://scripts/player/body_pose_modifier.gd")
const FootIKScript := preload("res://scripts/player/foot_ik_modifier.gd")

# --- clip data (measured on the UBC character, see tools/measure_clips.gd) ---
const LEN_WALK := 1.3333
const LEN_JOG := 0.9333
const LEN_SPRINT := 0.6667
const LEN_CWALK := 2.0
## Ground distance covered per gait cycle by the planted foot (m / cycle) of
## the BLENDED walk->run tree at gait weight 0.0, 0.1 .. 1.0, measured by
## tools/calibrate_stride.gd (strides do not blend linearly).
@export var stride_table_jog := PackedFloat32Array([1.29, 1.38, 1.84, 2.22, 2.78, 3.42, 4.13, 4.69, 5.10, 5.47, 5.84])
@export var stride_table_sprint := PackedFloat32Array([1.28, 1.40, 1.68, 2.36, 2.85, 3.24, 3.71, 4.23, 4.75, 5.35, 6.00])
@export var stride_cwalk := 1.42
## Human cadence (steps/s) vs speed (m/s). Cycle = 2 steps. Picks how much of
## the long-stride run clip is mixed with the walk so that cadence stays
## human while playback rate = speed / stride (no foot sliding).
@export var cadence_curve := PackedVector2Array([Vector2(0.0, 1.4), Vector2(1.0, 1.6),
	Vector2(1.8, 1.95), Vector2(3.0, 2.4), Vector2(4.2, 2.6), Vector2(6.8, 2.95), Vector2(9.0, 3.2)])
@export var warp_limit_deg := 70.0
@export var warp_limit_aim_deg := 92.0
## Aimed locomotion: BlendSpace2D over the authored aim set (StrafeGait:
## aim_fwd / aim_bwd / cross-step strafe_l / strafe_r). AIM_WARP=1 restores
## the old orientation-warp strafe for A/B measurement.
## Lateral distance per strafe cycle (m): cycle rate = v / this.
@export var strafe_stride := 1.3
## Distance per cycle of the authored diagonal clips (m).
@export var diag_stride := 2.0
## back diagonals (between strafe_stride and the shortened backpedal)
@export var diag_back_stride := 1.5
## aimed backpedal stride vs the forward-gait table stride at its speed
## (round 6: shorter, quicker backward steps; the re-posed aim_bwd sweeps
## exactly this stride; round 7: 0.7 -> 0.85, cadence 177 -> ~147 steps/min)
@export var backpedal_stride_scale := 0.85
@export var backward_enter_deg := 115.0
@export var backward_exit_deg := 95.0

# Roll clip window used for the controller's roll (s, clip time).
const ROLL_T0 := 0.12
const ROLL_T1 := 1.25
const SLIDE_T0 := 0.30
const SLIDE_T1 := 0.83
# Traverse clips (CC0 Quaternius UAL2 "Source" clips, retargeted by
# tools/retarget_drawcall.gd). Clip times (s) read off the contact analysis
# printed by tools/retarget_drawcall.gd --traj=<slug>.
## safety vault: right hand planted on the top from VAULT_PLANT to VAULT_RELEASE
const VAULT_PLANT := 0.07
const VAULT_RELEASE := 0.48
const VAULT_END := 0.733
## climb up (2 m clip; lower ledges skip its crouch-jump): hands on the ledge
## from MANTLE_GRAB, right released ~MANTLE_REL_R, left ~MANTLE_REL_L; feet
## carry the body on the top from MANTLE_FEET.
const MANTLE_T0 := 0.24
const MANTLE_GRAB := 0.32
const MANTLE_REL_R := 0.84
const MANTLE_REL_L := 0.95
const MANTLE_FEET := 0.91
const MANTLE_END := 1.30
## Released-hand hang during the core mantle stand-up: wrist this fraction of
## the arm length below its shoulder (straight arm = 1.0).
const MANTLE_HANG_DROP := 0.85
## core mode (Standard "climb" = UAL2 ClimbUp_1m loop) window
const CLIMB_T0 := 0.10
const CLIMB_T1 := 0.667
## wrist (hand bone) height above the surface the palm rests on
const PALM_H := 0.03
const HAND_INSET := 0.06
const FEET_BONES: PackedStringArray = ["foot_l", "foot_r", "ball_l", "ball_r"]

# ------------------------------------------------- presentation params ---
## Everything the animation layer reads from physics, recomputed each frame.
var p_speed := 0.0               # horizontal ground speed (m/s)
var p_local_dir := Vector2.ZERO  # move dir in facing frame (x = right, y = forward)
var p_accel := Vector2.ZERO      # smoothed accel in facing frame (m/s^2)
var p_turn_rate := 0.0           # facing yaw rate (rad/s)
var p_grounded := true
var p_vy := 0.0
var p_state := "GROUND"
var p_slope_deg := 0.0
var p_land_severity := 0

# derived / debug
var anim_state := "ground"
var gait := 0.0
var run_style := 0.0
var cycle_rate := 0.0            # gait cycles per second (signed: <0 = backward)
var land_weight := 0.0
var warp_angle := 0.0
var dir_w := Vector3.ZERO        # debug: (lateral, right, back) weight of the directional mix (extras only)

var character: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var pose_mod: SkeletonModifier3D   # body_pose_modifier.gd
var foot_ik: FootIKModifier        # foot locking / placement (after pose_mod)
@export var foot_ik_enabled := true
var _foot_w := 0.0
var _last_pos := Vector3.ZERO
var _pc: PlayerController
var _pb: AnimationNodeStateMachinePlayback
var _yaw := 0.0
var _prev_yaw := 0.0
var _vis_y := 0.0
var _vel_s := Vector3.ZERO
var _acc_s := Vector3.ZERO
var _backward := false
var _bwd_s := 0.0   # smoothed weight of the authored backward gait
var _aim_s := 0.0   # smoothed weight of the aim BlendSpace2D branch
var _aim_phase := 0.0   # shared normalized phase of the aim clips
var _aim_bp := Vector2(0, 1)   # smoothed blend position
var _aim_stride_f := 2.0   # stride/cycle of aim_fwd, aim_bwd (m)
var _aim_stride_b := 2.0
const BWD_ARC := 0.4
var has_aim_set := false
var _land_t := 99.0
var _land_peak := 0.0
var _land_rate := 1.0
var _state_t := 0.0
var _move_s := 0.0
var _crouch_s := 0.0
var _bank_s := 0.0
var _pitch_s := 0.0
var _drop_s := 0.0
var _prev_ctrl_state := "GROUND"
# hand IK (vault / mantle contact) + traverse visual offset
var arm_ik: SkeletonModifier3D      # TwoBoneIK3D (2 settings: left, right arm)
var hand_ik_weight := 0.0
var _ik_t: Array[Marker3D] = []     # targets  [l, r]
var _ik_p: Array[Marker3D] = []     # poles    [l, r]
var _tr_off := 0.0                  # vertical visual offset during traverse (m)
var _tr_fwd_off := 0.0              # forward visual offset (toward the obstacle) (m)
var _tr_off_prev := 0.0
var _tr_fwd_off_prev := 0.0
## upperarm->hand length of the UBC skeleton (0.49 m) minus a little slack
const ARM_REACH := 0.465
var _tr_lean := 0.0
var _tr_start_y := 0.0
var _tr_h := 0.0
var _tr_top := 0.0
var _tr_face := Vector3.ZERO
var _tr_fwd := Vector3.FORWARD
var arm_ik_r: SkeletonModifier3D
var _arm_len := 0.5
var _tr_reach := 1.0                 # mantle reach-in weight (1 = planted)
var _ik_tf_world := [Vector3.ZERO, Vector3.ZERO]
var hand_contact := [false, false]    # hand IK fully on AND target on the plant
var hand_w := [0.0, 0.0]            # per-hand IK weight [l, r]
var _plant_set := [false, false]
var _tr_clip_t := 0.0               # clip time of the active traverse clip
var _vault_tail := false            # vault clip finishing after the controller left TRAVERSE
var _tr_edge_f := 0.0               # obstacle face, along _tr_fwd (m)
var _cs_vault: ClipSampler
var _cs_mantle: ClipSampler
var _cs_climb: ClipSampler    # core mode (Standard clips)
var _cs_tuck: ClipSampler
## roll: visual-root drop per clip time (see _sample_roll); the in-place roll
## clip keeps the dive's flight height (root motion stripped), so without it
## the body somersaults ~0.4 m above the floor at the start of the roll
var _roll_drop := PackedFloat32Array()
var _roll_drop_s := 0.0
var _cs_roll: ClipSampler
## true: contact-driven traverse on the local extras clips; false: core mode
var has_extras := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pc = get_node_or_null(controller_path) as PlayerController
	character = CHAR_SCENE.instantiate()
	character.name = "UBCMale"
	character.rotation.y = PI          # glTF faces +Z, controller forward is -Z
	add_child(character)
	skeleton = character.find_child("Skeleton3D", true, false)
	pose_mod = BodyPoseModifierScript.new()
	pose_mod.name = "BodyPoseModifier"
	skeleton.add_child(pose_mod)
	foot_ik = FootIKScript.new()
	foot_ik.name = "FootIK"
	foot_ik.space_provider = self
	skeleton.add_child(foot_ik)
	if _pc:
		foot_ik.collision_mask = _pc.collision_mask
		foot_ik.exclude = [_pc.get_rid()]
	_setup_arm_ik()
	clip_library()
	has_extras = _lib_has_extras
	_sample_traverse_clips()
	_build_aim_set()
	_arm_len = skeleton.get_bone_rest(skeleton.find_bone("lowerarm_l")).origin.length() \
		+ skeleton.get_bone_rest(skeleton.find_bone("hand_l")).origin.length()
	# Modifier results (lean/warp/IK) only exist while the skeleton is being
	# finalised; snapshot the FINAL pose so tests/debug measure what is drawn.
	skeleton.skeleton_updated.connect(_snapshot_final_pose)
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	anim_player.root_node = anim_player.get_path_to(character)
	anim_player.add_animation_library("", clip_library())
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.root_node = anim_tree.get_path_to(character)
	anim_tree.tree_root = _build_tree()
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_tree.active = true
	_pb = anim_tree.get("parameters/playback")
	_pb.start("ground")
	if _pc:
		_pc.stepped.connect(func(h: float) -> void: _vis_y -= h)
		_pc.landed.connect(_on_landed)
		_pc.jumped.connect(func(_k: String) -> void: _travel("jump"))
		_yaw = _pc.facing_yaw
		_prev_yaw = _yaw
		rotation.y = _yaw
	anim_tree.advance(0.0)


var _final_pose: Array[Transform3D] = []


var _final_xf := Transform3D.IDENTITY


func _snapshot_final_pose() -> void:
	var n := skeleton.get_bone_count()
	_final_pose.resize(n)
	for i in n:
		_final_pose[i] = skeleton.get_bone_global_pose(i)
	# measure in the frame that is actually drawn (see render_xf)
	_final_xf = render_xf(skeleton)



## Transform a node under the controller is DRAWN with this frame.
## Physics interpolation is on: the renderer uses the capsule's interpolated
## transform times the CURRENT local chain (SceneTreeFTI's second pass, after
## _process). Node3D.get_global_transform_interpolated() instead returns the
## value cached by the FIRST pass at frame start, i.e. without the local
## changes made in _process this frame (visual root offset, yaw) -- one frame
## stale. Skeleton modifiers run between the two passes, so they must use this.
func render_xf(n: Node3D) -> Transform3D:
	if _pc == null:
		return n.global_transform
	return _pc.get_global_transform_interpolated() * (_pc.global_transform.affine_inverse() * n.global_transform)


## World-space position of a bone in the final (post-modifier) pose that is
## rendered. Falls back to the animation pose before the first update.
func get_final_bone_world(bone_name: String) -> Vector3:
	var i := skeleton.find_bone(bone_name)
	var pose := _final_pose[i] if i >= 0 and i < _final_pose.size() else skeleton.get_bone_global_pose(i)
	var xf := _final_xf if i < _final_pose.size() else render_xf(skeleton)
	return (xf * pose).origin


func _setup_arm_ik() -> void:
	# one modifier per arm so each hand has its own contact weight
	for i in 2:
		var sd := "l" if i == 0 else "r"
		var ik := TwoBoneIK3D.new()
		ik.name = "ArmIK_" + sd
		skeleton.add_child(ik)   # after BodyPoseModifier: runs on the final pose
		ik.set_setting_count(1)
		var t := Marker3D.new(); t.name = "HandTarget_" + sd; t.top_level = true
		var pl := Marker3D.new(); pl.name = "ElbowPole_" + sd; pl.top_level = true
		add_child(t); add_child(pl)
		_ik_t.append(t); _ik_p.append(pl)
		# TwoBoneIK3D reads target/pole via get_global_transform_interpolated()
		# and resolves them in the skeleton's get_global_transform_interpolated(),
		# both frame-start caches that miss this frame's _process changes. A
		# HIDDEN child of the skeleton is evaluated on demand as
		# skeleton_cache * local, so the IK sees exactly `local` in skeleton
		# space, whatever the cache holds; _feed_arm_ik() sets local from the
		# drawn transform.
		var tf := Node3D.new(); tf.name = "HandTargetFeed_" + sd; tf.visible = false
		var pf := Node3D.new(); pf.name = "ElbowPoleFeed_" + sd; pf.visible = false
		skeleton.add_child(tf); skeleton.add_child(pf)
		_ik_tf.append(tf); _ik_pf.append(pf)
		ik.set_root_bone_name(0, "upperarm_" + sd)
		ik.set_middle_bone_name(0, "lowerarm_" + sd)
		ik.set_end_bone_name(0, "hand_" + sd)
		ik.set_target_node(0, ik.get_path_to(tf))
		ik.set_pole_node(0, ik.get_path_to(pf))
		ik.influence = 0.0
		ik.active = false
		if i == 0:
			arm_ik = ik
		else:
			arm_ik_r = ik


func _build_aim_set() -> void:
	if OS.get_environment("AIM_WARP") == "1" or _pc == null:
		return
	var m := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != self:
		m = (n as Node3D).transform * m
		n = n.get_parent()
	var unit := m.basis.get_scale().y
	var vf := _pc.aim_speed
	var vb := _pc.aim_speed * _pc.backpedal_factor
	var gf := _solve_gait(vf * 2.0 / _cadence(vf), 0.0)
	var gb := _solve_gait(vb * 2.0 / _cadence(vb), 0.0)
	_aim_stride_f = _stride_at(gf, 0.0)
	_aim_stride_b = _stride_at(gb, 0.0) * backpedal_stride_scale
	StrafeGait.build(skeleton, clip_library(), gf, gb, strafe_stride, diag_stride, unit, _aim_stride_f, _aim_stride_b, diag_back_stride)
	has_aim_set = true


func _sample_traverse_clips() -> void:
	# skeleton space -> this node's axes, origin at the visual root (character)
	var m := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != self:
		m = (n as Node3D).transform * m
		n = n.get_parent()
	m.origin -= character.position
	var bones: PackedStringArray = ["hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r", "pelvis", "upperarm_l", "upperarm_r"]
	_sample_roll(m)
	if not has_extras:
		_cs_climb = ClipSampler.sample(skeleton, m, clip_library().get_animation("climb"), bones)
		_cs_tuck = ClipSampler.sample(skeleton, m, clip_library().get_animation("ninja_air"), bones)
		return
	_cs_vault = ClipSampler.sample(skeleton, m, clip_library().get_animation("vault_safety"), bones)
	_cs_mantle = ClipSampler.sample(skeleton, m, clip_library().get_animation("climb_up_2m"), bones)
	_arm_len = skeleton.get_bone_rest(skeleton.find_bone("lowerarm_l")).origin.length() \
		+ skeleton.get_bone_rest(skeleton.find_bone("hand_l")).origin.length()


# ----------------------------------------------------------------- tree ---
func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


func _seeked(bt: AnimationNodeBlendTree, prefix: String, clip: String, pos: Vector2) -> String:
	# clip -> TimeSeek(prefix_seek) -> TimeScale(prefix_ts); returns output node name
	bt.add_node(prefix + "_clip", _anim(clip), pos)
	bt.add_node(prefix + "_seek", AnimationNodeTimeSeek.new(), pos + Vector2(200, 0))
	bt.add_node(prefix + "_ts", AnimationNodeTimeScale.new(), pos + Vector2(400, 0))
	bt.connect_node(prefix + "_seek", 0, prefix + "_clip")
	bt.connect_node(prefix + "_ts", 0, prefix + "_seek")
	return prefix + "_ts"


func _scaled(bt: AnimationNodeBlendTree, prefix: String, clip: String, pos: Vector2) -> String:
	bt.add_node(prefix + "_clip", _anim(clip), pos)
	bt.add_node(prefix + "_ts", AnimationNodeTimeScale.new(), pos + Vector2(200, 0))
	bt.connect_node(prefix + "_ts", 0, prefix + "_clip")
	return prefix + "_ts"


func _blend2(bt: AnimationNodeBlendTree, name: String, a: String, b: String, pos: Vector2, sync := false) -> String:
	var n := AnimationNodeBlend2.new()
	n.sync = sync
	bt.add_node(name, n, pos)
	bt.connect_node(name, 0, a)
	bt.connect_node(name, 1, b)
	return name


## stride per cycle of the aim blend space at blend position `bp` (unit
## vector): the blend between the two neighbouring points (45 deg apart)
func _aim_stride(bp: Vector2) -> float:
	var st := [_aim_stride_f, diag_stride, strafe_stride, diag_back_stride, _aim_stride_b, diag_back_stride, strafe_stride, diag_stride]
	var a := fposmod(atan2(bp.x, bp.y), TAU) / (PI / 4.0)
	var i := int(a) % 8
	return maxf(lerpf(st[i], st[(i + 1) % 8], a - floorf(a)), 0.3)


func _aim_branch(g: AnimationNodeBlendTree, dirn: String) -> String:
	var a2 := AnimationNodeBlendSpace2D.new()
	for pt in StrafeGait.POINTS:
		a2.add_blend_point(_anim(pt[0]), pt[1])
	g.add_node("aim2d", a2, Vector2(600, -600))
	g.add_node("aim_seek", AnimationNodeTimeSeek.new(), Vector2(800, -600))
	g.add_node("aim_ts", AnimationNodeTimeScale.new(), Vector2(1000, -600))
	g.connect_node("aim_seek", 0, "aim2d")
	g.connect_node("aim_ts", 0, "aim_seek")
	return _blend2(g, "aimsel", dirn, "aim_ts", Vector2(900, -100))


func _build_tree() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	# ground: phase-synced locomotion + crouch + landing cushion overlay
	var g := AnimationNodeBlendTree.new()
	g.add_node("idle", _anim("idle"), Vector2(0, 0))
	var w := _scaled(g, "walk", "walk", Vector2(0, 150))
	var j := _scaled(g, "jog", "jog", Vector2(0, 300))
	var s := _scaled(g, "sprint", "sprint", Vector2(0, 450))
	var run := _blend2(g, "run", j, s, Vector2(500, 350), true)
	var gaitn := _blend2(g, "gait", w, run, Vector2(700, 200), true)
	# authored backward gait, played forward while backpedalling; its clip
	# time stays the mirror (L - t) of the forward branch so the dir blend
	# never mixes mismatched phases
	var wb := _scaled(g, "walk_b", "walk_bwd", Vector2(0, -450))
	var jb := _scaled(g, "jog_b", "jog_bwd", Vector2(0, -300))
	var sb := _scaled(g, "sprint_b", "sprint_bwd", Vector2(0, -150))
	var runb := _blend2(g, "run_b", jb, sb, Vector2(500, -250), true)
	var gaitb := _blend2(g, "gait_b", wb, runb, Vector2(700, -300), true)
	var dirn := _blend2(g, "dir", gaitn, gaitb, Vector2(800, 0), true)
	# aimed: BlendSpace2D over the phase-aligned aim set, one shared phase
	# (TimeSeek above the space seeks all four clips together)
	var aimsel := dirn
	if has_aim_set:
		aimsel = _aim_branch(g, dirn)
	var move := _blend2(g, "move", "idle", aimsel, Vector2(900, 100))
	g.add_node("cidle", _anim("crouch_idle"), Vector2(0, 600))
	var cw := _scaled(g, "cwalk", "crouch_walk", Vector2(0, 750))
	var cmove := _blend2(g, "cmove", "cidle", cw, Vector2(500, 650))
	var stance := _blend2(g, "crouch", move, cmove, Vector2(1100, 300))
	var land := _seeked(g, "land", "jump_land", Vector2(0, 900))
	var outn := _blend2(g, "land_mix", stance, land, Vector2(1300, 400))
	g.connect_node("output", 0, outn)
	sm.add_node("ground", g, Vector2(300, 200))
	# jump take-off
	var jt := AnimationNodeBlendTree.new()
	jt.connect_node("output", 0, _seeked(jt, "js", "jump_start", Vector2.ZERO))
	sm.add_node("jump", jt, Vector2(300, 0))
	# air: rise/apex pose -> reaching fall pose by vertical speed
	var air := AnimationNodeBlendTree.new()
	air.add_node("rise", _anim("jump_air"), Vector2.ZERO)
	var fall := _seeked(air, "fall", "jump_land", Vector2(0, 200))
	air.connect_node("output", 0, _blend2(air, "fall_mix", "rise", fall, Vector2(700, 100)))
	sm.add_node("air", air, Vector2(600, 0))
	# slide: entry seeked by slide_time, then loop
	var sl := AnimationNodeBlendTree.new()
	var sst := _seeked(sl, "ss", "slide_start", Vector2.ZERO)
	sl.add_node("loop", _anim("slide_loop"), Vector2(0, 200))
	sl.connect_node("output", 0, _blend2(sl, "slide_mix", sst, "loop", Vector2(700, 100)))
	sm.add_node("slide", sl, Vector2(0, 400))
	var sx := AnimationNodeBlendTree.new()
	sx.connect_node("output", 0, _seeked(sx, "sx", "slide_exit", Vector2.ZERO))
	sm.add_node("slide_exit", sx, Vector2(300, 400))
	# roll / mantle / vault: seeked from controller progress
	var rl := AnimationNodeBlendTree.new()
	rl.connect_node("output", 0, _seeked(rl, "r", "roll_tuck", Vector2.ZERO))
	sm.add_node("roll", rl, Vector2(600, 400))
	var mt := AnimationNodeBlendTree.new()
	mt.connect_node("output", 0, _seeked(mt, "c", "climb_up_2m" if has_extras else "climb", Vector2.ZERO))
	sm.add_node("mantle", mt, Vector2(900, 200))
	var vt := AnimationNodeBlendTree.new()
	if has_extras:
		vt.connect_node("output", 0, _seeked(vt, "c", "vault_safety", Vector2.ZERO))
	else:   # core: climb hand-plant blended into the ninja tuck
		var vc := _seeked(vt, "c", "climb", Vector2.ZERO)
		var vtuck := _seeked(vt, "tuck", "ninja_air", Vector2(0, 200))
		vt.connect_node("output", 0, _blend2(vt, "tuck_mix", vc, vtuck, Vector2(300, 100)))
	sm.add_node("vault", vt, Vector2(900, 400))
	var xfade := {"ground": 0.18, "jump": 0.08, "air": 0.2, "slide": 0.12, "slide_exit": 0.1,
		"roll": 0.10, "mantle": 0.15, "vault": 0.15}
	# ease-in/out crossfade weight: a linear xfade ends with a velocity step
	# (a bone moving between two differently-moving poses snaps to the new
	# pose's velocity in one frame -- ~0.2 m/frame foot "pop" at vault/mantle
	# entry). Zero-slope ends remove that kink.
	var ease := Curve.new()
	ease.add_point(Vector2(0, 0), 0.0, 0.0)
	ease.add_point(Vector2(1, 1), 0.0, 0.0)
	var use_ease := OS.get_environment("XFADE_LINEAR") != "1"
	for a in xfade:
		for b in xfade:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = xfade[b]
				if use_ease:
					t.xfade_curve = ease
				t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				sm.add_transition(a, b, t)
	return sm


func _travel(st: String) -> void:
	if anim_state == st:
		return
	anim_state = st
	_state_t = 0.0
	_pb.travel(st)
	# entry seeks for one-shots that are not progress-driven
	match st:
		"jump":
			_p("jump/js_seek/seek_request", 0.14)
			_p("jump/js_ts/scale", 1.25)
		"slide_exit":
			_p("slide_exit/sx_seek/seek_request", 0.12)
			_p("slide_exit/sx_ts/scale", 1.5)


func _p(path: String, v: Variant) -> void:
	anim_tree.set("parameters/" + path, v)


func _on_landed(impact: float, severity: int) -> void:
	p_land_severity = severity
	_land_t = 0.0
	match severity:
		0:
			_land_peak = clampf((impact - 1.5) / 6.0, 0.12, 0.55)
			_land_rate = 2.2
		1:
			_land_peak = 0.85
			_land_rate = 1.5
		_:
			_land_peak = 1.0
			_land_rate = 1.1


# -------------------------------------------------------------- per frame ---
func _stride_at(g: float, rs: float) -> float:
	var x := clampf(g, 0.0, 1.0) * 10.0
	var i := mini(int(x), 9)
	var f := x - i
	var sj := lerpf(stride_table_jog[i], stride_table_jog[i + 1], f)
	var ss := lerpf(stride_table_sprint[i], stride_table_sprint[i + 1], f)
	return lerpf(sj, ss, rs)


## Inverse of _stride_at (tables are monotonic): gait weight giving `stride`.
func _solve_gait(stride: float, rs: float) -> float:
	if stride <= _stride_at(0.0, rs):
		return 0.0
	for i in 10:
		var a := _stride_at(i / 10.0, rs)
		var b := _stride_at((i + 1) / 10.0, rs)
		if stride <= b:
			return (i + (stride - a) / maxf(b - a, 1e-4)) / 10.0
	return 1.0


func _cadence(v: float) -> float:
	var c := cadence_curve
	if v <= c[0].x:
		return c[0].y
	for i in range(1, c.size()):
		if v <= c[i].x:
			return lerpf(c[i - 1].y, c[i].y, (v - c[i - 1].x) / (c[i].x - c[i - 1].x))
	return c[c.size() - 1].y


func _process(dt: float) -> void:
	if _pc == null or dt <= 0.0:
		return
	update_presentation(dt)
	anim_tree.advance(dt)
	_core_traverse_post()


## Reads the controller and drives the tree. Separate from _process so tests
## can call it deterministically.
func update_presentation(dt: float) -> void:
	_state_t += dt
	var st := _pc.get_state_name()
	if _pc.global_position.distance_to(_last_pos) > 2.0 and foot_ik:
		foot_ik.reset()   # teleport
	_last_pos = _pc.global_position
	var v3 := _pc.velocity
	var hv := Vector3(v3.x, 0, v3.z)
	if _pc.is_pushing:
		hv = _pc.move_velocity   # clipped velocity ~0 while the crate moves
	var k := 1.0 - exp(-14.0 * dt)
	var new_vel := _vel_s.lerp(hv, k)
	_acc_s = _acc_s.lerp((new_vel - _vel_s) / dt, 1.0 - exp(-8.0 * dt))
	_vel_s = new_vel

	# visual yaw (smoothed facing) + turn rate
	_yaw = lerp_angle(_yaw, _pc.facing_yaw, 1.0 - exp(-20.0 * dt))
	p_turn_rate = lerpf(p_turn_rate, wrapf(_yaw - _prev_yaw, -PI, PI) / dt, 1.0 - exp(-10.0 * dt))
	_prev_yaw = _yaw
	rotation = Vector3(0, _yaw, 0)
	_vis_y = lerpf(_vis_y, 0.0, 1.0 - exp(-14.0 * dt))
	character.position.y = _vis_y

	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	p_speed = _vel_s.length()
	p_local_dir = Vector2(_vel_s.dot(right), _vel_s.dot(fwd)) / maxf(p_speed, 0.001) if p_speed > 0.05 else Vector2.ZERO
	p_accel = Vector2(_acc_s.dot(right), _acc_s.dot(fwd))
	p_grounded = _pc.is_on_floor() or st == "GROUND"
	p_vy = v3.y
	p_state = st
	p_slope_deg = rad_to_deg(_pc.get_floor_angle()) if _pc.is_on_floor() else 0.0

	_update_state_machine(st)
	# traverse first: it sets the clip time that _drive_actions seeks to (one
	# frame of lag here = a dt-proportional hand error, i.e. Hz dependence)
	_drive_traverse_contact(dt, st)
	_drive_ground(dt)
	_drive_actions(dt)
	_drive_procedural(dt, st)
	_feed_arm_ik()   # last: after every transform change of this frame
	_prev_ctrl_state = st


func _update_state_machine(st: String) -> void:
	match st:
		"GROUND":
			if _prev_ctrl_state == "SLIDE" and not _pc.is_crouched and anim_state == "slide":
				_travel("slide_exit")
			elif anim_state == "slide_exit" and _state_t < 0.22:
				pass
			else:
				_travel("ground")
		"AIR":
			if anim_state == "jump" and _state_t < 0.32 and p_vy > 0.5:
				pass
			elif anim_state == "vault" and not has_extras and _state_t < 0.05:
				pass
			elif anim_state == "vault" and _vault_tail and _tr_clip_t < VAULT_END - 0.02:
				pass
			else:
				_travel("air")
		"SLIDE":
			_travel("slide")
		"ROLL":
			_travel("roll")
		"VAULT":
			_travel("vault")
		"MANTLE":
			_travel("mantle")


func _drive_ground(dt: float) -> void:
	var v := p_speed
	# backward (reverse playback) with hysteresis; strafe = orientation warp
	var theta := atan2(-p_local_dir.x, p_local_dir.y) if v > 0.3 else 0.0   # + = toward the left
	var ad := rad_to_deg(absf(theta))
	if _backward and ad < backward_exit_deg:
		_backward = false
	elif not _backward and ad > backward_enter_deg:
		_backward = true
	var target_warp := wrapf(theta - PI, -PI, PI) if _backward else theta
	# aimed (body locked to the camera): the core library has no strafe
	# clips, so the legs may yaw the full 90 deg (spine counter-twists)
	var lim := deg_to_rad(warp_limit_aim_deg if _pc.is_aiming else warp_limit_deg)
	target_warp = clampf(target_warp, -lim, lim) * clampf((v - 0.3) / 0.5, 0.0, 1.0)
	var aim_t := 1.0 if (has_aim_set and _pc.is_aiming and not _pc.is_crouched) else 0.0
	_aim_s = lerpf(_aim_s, aim_t, 1.0 - exp(-12.0 * dt))
	target_warp *= 1.0 - aim_t   # aim set: legs face the camera, the clips step sideways
	warp_angle = lerp_angle(warp_angle, target_warp, 1.0 - exp(-12.0 * dt))
	if has_aim_set:
		var ld := p_local_dir
		var bp := ld.normalized() if (ld.length() > 1e-3 and v > 0.3) else _aim_bp
		_aim_bp = _aim_bp.slerp(bp, 1.0 - exp(-14.0 * dt)) if _aim_bp.dot(bp) > -0.99 else bp
		_aim_phase = fposmod(_aim_phase + dt * v / _aim_stride(_aim_bp), 1.0)
		_p("ground/aim2d/blend_position", _aim_bp)
		_p("ground/aim_seek/seek_request", _aim_phase * StrafeGait.LEN)
		_p("ground/aim_ts/scale", 0.0)
		_p("ground/aimsel/blend_amount", _aim_s)

	# gait solve: stride needed for a human cadence at this speed
	var stride_need := v * 2.0 / _cadence(v)
	run_style = smoothstep(4.6, 6.6, v)
	gait = _solve_gait(stride_need, run_style)
	var s_blend := _stride_at(gait, run_style)
	_move_s = lerpf(_move_s, smoothstep(0.08, 0.7, v), 1.0 - exp(-12.0 * dt))
	# (start/stop: a 1/_move_s cycle speed-up was tried and made lock breaks
	# worse; start/stop slip is handled by FootIK's swing release + settle)
	cycle_rate = v / s_blend * (-1.0 if _backward else 1.0)
	var crouch_t := 1.0 if (_pc.is_crouched and p_state == "GROUND") else 0.0
	_crouch_s = lerpf(_crouch_s, crouch_t, 1.0 - exp(-10.0 * dt))
	_p("ground/walk_ts/scale", LEN_WALK * cycle_rate)
	_p("ground/jog_ts/scale", LEN_JOG * cycle_rate)
	_p("ground/sprint_ts/scale", LEN_SPRINT * cycle_rate)
	_p("ground/walk_b_ts/scale", -LEN_WALK * cycle_rate)
	_p("ground/jog_b_ts/scale", -LEN_JOG * cycle_rate)
	_p("ground/sprint_b_ts/scale", -LEN_SPRINT * cycle_rate)
	_p("ground/run/blend_amount", run_style)
	_p("ground/gait/blend_amount", gait)
	_p("ground/run_b/blend_amount", run_style)
	_p("ground/gait_b/blend_amount", gait)
	_bwd_s = lerpf(_bwd_s, 1.0 if _backward else 0.0, 1.0 - exp(-14.0 * dt))
	_p("ground/dir/blend_amount", _bwd_s)
	_p("ground/move/blend_amount", _move_s)
	var c_rate := v / stride_cwalk * (-1.0 if _backward else 1.0)
	_p("ground/cwalk_ts/scale", LEN_CWALK * c_rate)
	_p("ground/cmove/blend_amount", smoothstep(0.08, 0.6, v))
	_p("ground/crouch/blend_amount", _crouch_s)
	# landing cushion (severity-scaled), seeked by time since touchdown
	_land_t += dt
	var land_clip_t := 0.06 + _land_t * _land_rate
	var fade_end := 1.05 if p_land_severity >= 2 else (0.75 if p_land_severity == 1 else 0.5)
	land_weight = _land_peak * (1.0 - smoothstep(fade_end * 0.45, fade_end, land_clip_t)) if land_clip_t < 1.2 else 0.0
	if anim_state != "ground":
		land_weight = 0.0
	_p("ground/land_seek/seek_request", minf(land_clip_t, 1.2))
	_p("ground/land_ts/scale", 0.0)
	_p("ground/land_mix/blend_amount", land_weight)


func _drive_actions(_dt: float) -> void:
	match anim_state:
		"air":
			_p("air/fall_seek/seek_request", 0.0)
			_p("air/fall_ts/scale", 0.0)
			_p("air/fall_mix/blend_amount", smoothstep(-0.5, -5.0, p_vy))
		"slide":
			var st := _pc.slide_time
			_p("slide/ss_seek/seek_request", minf(SLIDE_T0 + st * 1.8, SLIDE_T1))
			_p("slide/ss_ts/scale", 0.0)
			_p("slide/slide_mix/blend_amount", smoothstep(0.24, 0.4, st))
		"roll":
			var u := clampf(_pc.roll_time / maxf(_pc.roll_duration, 0.01), 0.0, 1.0)
			_p("roll/r_seek/seek_request", lerpf(ROLL_T0, ROLL_T1, u))
			_p("roll/r_ts/scale", 0.0)
			# fade the drop in with the 0.10 s state crossfade (the jog pose
			# must not sink) and out again if the roll is cancelled
			var fade := smoothstep(0.0, 0.10, _state_t) if _pc.state == PlayerController.State.ROLL else 0.0
			_roll_drop_s = roll_drop(u) * fade
			character.position.y -= _roll_drop_s
		"mantle":
			_p("mantle/c_seek/seek_request", _tr_clip_t if has_extras else lerpf(CLIMB_T0, CLIMB_T1, get_traverse_progress()))
			_p("mantle/c_ts/scale", 0.0)
		"vault":
			_p("vault/c_ts/scale", 0.0)
			if has_extras:
				_p("vault/c_seek/seek_request", _tr_clip_t)
			else:
				var u := get_traverse_progress()
				_p("vault/c_seek/seek_request", lerpf(CLIMB_T0, 0.42, minf(u / 0.45, 1.0)))
				_p("vault/tuck_seek/seek_request", 0.4)
				_p("vault/tuck_ts/scale", 0.0)
				_p("vault/tuck_mix/blend_amount", smoothstep(0.2, 0.45, u))


## Vault / mantle presentation (pure visual: the controller path is untouched).
## The traverse clips are in-place, so the VISUAL root is placed from the
## clip's own contacts: while a hand is planted the root sits where that
## hand (as posed by the clip on this skeleton) lands on the real obstacle
## top/edge; while the feet carry the body the root sits where the lowest
## foot lands on the top (or the start floor). The clip time is driven by the
## controller's traverse progress, so the result does not depend on the
## physics rate. Two-bone arm IK then pins each planted hand to a fixed world
## point on the top for the remaining (small) error.
var _tail_y0 := 0.0
var _tr_back_f := INF               # obstacle back face, along _tr_fwd (INF = deep ledge)
var _ik_tf: Array[Node3D] = []
var _ik_pf: Array[Node3D] = []


## Far face of the obstacle along _tr_fwd: ray from beyond, back toward the
## front face, just under the top. INF when the top continues (a ledge).
func _find_back_face(cap: Vector3, edge_f: float) -> float:
	var cap_f := cap.dot(_tr_fwd)
	var y := _tr_top - 0.05
	var a := cap + _tr_fwd * (edge_f + 2.5 - cap_f); a.y = y
	var b := cap + _tr_fwd * (edge_f + 0.01 - cap_f); b.y = y
	var q := PhysicsRayQueryParameters3D.create(a, b, _pc.collision_mask, [_pc.get_rid()])
	var hit := _pc.get_world_3d().direct_space_state.intersect_ray(q)
	return INF if hit.is_empty() else (hit["position"] as Vector3).dot(_tr_fwd)


func _drive_traverse_contact(dt: float, st: String) -> void:
	if not has_extras:
		_drive_traverse_core(dt, st)
		return
	var trav := st == "VAULT" or st == "MANTLE"
	# offsets are relative to the RENDERED (interpolated) capsule, so the drawn
	# root lands exactly where the clip contact puts it at any physics rate
	var cap := _pc.get_global_transform_interpolated().origin
	if trav and (_prev_ctrl_state != st or _tr_h == 0.0):
		var pts: Array = _pc._tr_points
		_tr_fwd = _pc._tr_dir
		_tr_start_y = (pts[0] as Vector3).y
		_tr_h = (pts[1] as Vector3).y - _tr_start_y
		_tr_top = (pts[1] as Vector3).y - 0.06
		_tr_face = (pts[1] as Vector3) + _tr_fwd * _pc.body_radius
		_tr_edge_f = _tr_face.dot(_tr_fwd)
		_tr_back_f = _find_back_face(cap, _tr_edge_f)
		_plant_set = [false, false]
		_tr_clip_t = 0.0
		_vault_tail = false
	if trav:
		_keep_locks_off_face()
	var right := _tr_fwd.cross(Vector3.UP).normalized()
	var cap_f := cap.dot(_tr_fwd)
	var tw := [0.0, 0.0]   # target hand weights
	hand_contact = [false, false]
	if trav:
		_tr_reach = 1.0
		var u := get_traverse_progress()
		var cs: ClipSampler
		var t: float
		var root_y: float
		var root_f: float
		var hand := 1   # hand driving the root
		if st == "VAULT":
			cs = _cs_vault
			if u < 0.15:
				t = VAULT_PLANT * u / 0.15
			elif u < 0.75:
				t = lerpf(VAULT_PLANT, VAULT_RELEASE, (u - 0.15) / 0.6)
			else:
				t = lerpf(VAULT_RELEASE, 0.55, (u - 0.75) / 0.25)
			var wc := smoothstep(0.0, VAULT_PLANT, t) * (1.0 - smoothstep(VAULT_RELEASE, 0.6, t))
			root_y = lerpf(_tr_start_y, _tr_top + PALM_H - cs.at("hand_r", t).y, wc)
			root_f = lerpf(cap_f, _tr_edge_f + HAND_INSET + cs.at("hand_r", t).z, wc)
			tw[1] = smoothstep(VAULT_PLANT - 0.04, VAULT_PLANT, t) * (1.0 - smoothstep(VAULT_RELEASE - 0.03, VAULT_RELEASE + 0.04, t))
		else:
			cs = _cs_mantle
			hand = 0
			t = lerpf(MANTLE_T0, MANTLE_END, u)
			var w_h := smoothstep(MANTLE_T0, MANTLE_GRAB, t)
			var w_f := smoothstep(MANTLE_FEET - 0.05, MANTLE_FEET + 0.05, t)
			var r_h := _tr_top + PALM_H - cs.at("hand_l", t).y
			var r_f := _tr_top - cs.sole_min(t)
			root_y = lerpf(lerpf(_tr_start_y, r_h, w_h), r_f, w_f)
			root_f = lerpf(cap_f, _tr_edge_f + HAND_INSET + cs.at("hand_l", t).z, w_h)
			root_f = lerpf(root_f, cap_f, smoothstep(MANTLE_FEET, MANTLE_END, t))
			# reach in over the whole hang-up so the hands come OVER the lip
			# (approach target above/behind the plant, see _tr_reach below)
			# instead of the FK hand sweeping through the face corner
			var reach := smoothstep(MANTLE_T0, MANTLE_GRAB, t)
			var on := smoothstep(0.0, 0.25, reach)   # target starts AT the FK hand: no jump
			tw[0] = on * (1.0 - smoothstep(MANTLE_REL_L - 0.05, MANTLE_REL_L + 0.03, t))
			tw[1] = on * (1.0 - smoothstep(MANTLE_REL_R - 0.05, MANTLE_REL_R + 0.03, t))
			_tr_reach = reach
		# soles never below the start floor ...
		root_y = maxf(root_y, _tr_start_y - cs.sole_min(t))
		# ... nor poking through the front face below the top (clip start
		# poses put a toe ~2-4 cm past the face when the jump fires close)
		var push := 0.0
		for b in ClipSampler.SOLE:
			var bp := cs.at(b, t)
			if root_y + bp.y - ClipSampler.SOLE[b] < _tr_top - 0.01:
				push = maxf(push, root_f - bp.z - (_tr_edge_f - 0.01))
		root_f -= push
		# ... nor inside the obstacle: any foot whose predicted position is over
		# the top (between front face and back face) keeps its sole on/above it
		for b in ClipSampler.SOLE:
			var bp := cs.at(b, t)
			var bf := root_f - bp.z
			if bf > _tr_edge_f - 0.02 and bf < _tr_back_f + 0.02:
				root_y = maxf(root_y, _tr_top + ClipSampler.SOLE[b] - bp.y)
		# hand off to the capsule at the very end (no pop when the state changes)
		var w_end := smoothstep(0.9, 1.0, u) if st == "MANTLE" else 0.0
		_tr_off = lerpf(root_y - cap.y, 0.0, w_end)
		_tr_fwd_off = lerpf(root_f - cap_f, 0.0, w_end)
		_tr_clip_t = t
		for i in 2:
			var hn := "hand_l" if i == 0 else "hand_r"
			if tw[i] > 0.0 and not _plant_set[i]:
				_plant_set[i] = true
				var hx := cs.at(hn, t).x
				_ik_t[i].global_position = Vector3(cap.x, _tr_top + PALM_H, cap.z) + right * hx \
					+ _tr_fwd * (_tr_edge_f + HAND_INSET - cap_f)
			if not _plant_set[i]:
				continue
			var plant: Vector3 = _ik_t[i].global_position
			# out of reach (the visual root was lifted, e.g. to keep the feet
			# out of the obstacle): the hand leaves the surface instead of the
			# IK reporting full weight with a hovering wrist
			var sh := _clip_world(cs, "upperarm_l" if i == 0 else "upperarm_r", t, cap, cap_f, root_y, root_f, right)
			tw[i] *= 1.0 - smoothstep(0.0, 0.03, sh.distance_to(plant) - _arm_len * 0.99)
			# drawn target: from the clip (FK) hand UP over the lip, then in
			# onto the plant, so the reach never sweeps through the face corner
			var fk := _clip_world(cs, hn, t, cap, cap_f, root_y, root_f, right)
			var r := _tr_reach
			var tgt := fk.lerp(plant, smoothstep(0.35, 1.0, r))
			tgt.y = lerpf(fk.y, plant.y + 0.10 * (1.0 - r), smoothstep(0.0, 0.6, r))
			# below the lip the target stays in front of the face; the
			# allowance grows as it rises over the top (soft, no snap)
			var f := (tgt - cap).dot(_tr_fwd) + cap_f
			var f_max := _tr_edge_f - 0.04 + maxf(0.0, tgt.y - (plant.y - PALM_H - 0.01)) * 3.0
			if f > f_max:
				tgt -= _tr_fwd * (f - f_max)
			_ik_tf_world[i] = tgt
			hand_contact[i] = r > 0.999 and tw[i] > 0.99
		_tail_y0 = cap.y
	elif anim_state == "vault" and st == "AIR":
		# finish the vault clip while the capsule drops off the far side: clip
		# time follows the fall, the visual root stays on the floor
		if not _vault_tail:
			_vault_tail = true
			_tail_y0 = cap.y
		var fall := clampf((_tail_y0 - cap.y) / maxf(_tail_y0 - _tr_start_y, 0.1), 0.0, 1.0)
		_tr_clip_t = maxf(_tr_clip_t, lerpf(0.55, VAULT_END, fall))
		_tr_off = minf(0.0, _tr_start_y - cap.y)
		_tr_fwd_off = lerpf(_tr_fwd_off, 0.0, 1.0 - exp(-10.0 * dt))
	else:
		_tr_h = 0.0
		_vault_tail = false
		_tr_off = lerpf(_tr_off, 0.0, 1.0 - exp(-16.0 * dt))
		_tr_fwd_off = lerpf(_tr_fwd_off, 0.0, 1.0 - exp(-16.0 * dt))
	_tr_lean = 0.0
	_tr_off_prev = _tr_off
	_tr_fwd_off_prev = _tr_fwd_off
	var iks := [arm_ik, arm_ik_r]
	for i in 2:
		# fast in (already reached by the clip), fast out
		hand_w[i] = tw[i] if trav else lerpf(hand_w[i], 0.0, 1.0 - exp(-20.0 * dt))
		var side := -1.0 if i == 0 else 1.0
		var tp: Vector3 = _ik_t[i].global_position
		if not (trav and _plant_set[i]):
			_ik_tf_world[i] = tp
		_ik_p[i].global_position = tp - _tr_fwd * 0.6 + right * side * 0.45 - Vector3.UP * 0.1
		_ik_t[i].global_basis = Basis.looking_at(-_tr_fwd, Vector3.UP)
		iks[i].influence = clampf(hand_w[i], 0.0, 1.0)
		iks[i].active = hand_w[i] > 0.001
	hand_ik_weight = maxf(hand_w[0], hand_w[1])
	var lf := global_basis.inverse() * (_tr_fwd * _tr_fwd_off)
	character.position = Vector3(lf.x, _vis_y + _tr_off, lf.z)


## CORE mode (no extras library): the Standard packs have no vault / mantle
## clip, only the ClimbUp_1m climbing loop (+ the ninja-jump tuck). The base
## visual root follows the Round 2 schedule (body low until the hands are on
## the edge, then catching up with the capsule; pure visual, the controller
## path is untouched). After the tree has posed the skeleton this frame,
## _core_traverse_post() reads that pose and corrects the visual root so the
## planted hands are actually within arm reach and no sole is inside the
## obstacle, then pins the hands with the per-arm IK. hand_contact is only
## reported when the plant is really reachable.
var _core_u := 0.0
var _core_plan := [0.0, 0.0]        # scheduled plant weight per hand
var _core_inset := 0.07
var _core_w := [0.0, 0.0]          # effective (reach-gated, rate-limited) plant blend
const CORE_PLAN_N := 96
var _core_lift := PackedFloat32Array()   # planned extra root lift over u
var _post_s := Vector4.ZERO   # post-pass reach residual spring (dy, dy', df, df')


## Capsule position along the traverse at progress u (mirror of
## PlayerController._tick_traverse; collisions aside it is deterministic).
func _core_cap_at(u: float) -> Vector3:
	var pts: Array = _pc._tr_points
	if u < 0.55:
		var a := u / 0.55
		var y: float = lerpf((pts[0] as Vector3).y, (pts[1] as Vector3).y, a * a * (3.0 - 2.0 * a))
		var xz: Vector3 = (pts[0] as Vector3).lerp(pts[1], a * a)
		return Vector3(xz.x, y, xz.z)
	var b := (u - 0.55) / 0.45
	return (pts[1] as Vector3).lerp(pts[2], b * b * (3.0 - 2.0 * b))


## Scheduled (pre-correction) root offset at u.
func _core_sched_off(mantle: bool, u: float, cap_y: float) -> float:
	if mantle:
		return minf(0.0, _tr_start_y + _tr_h * smoothstep(0.12, 0.72, u) - cap_y)
	var bump := smoothstep(0.15, 0.4, u) * (1.0 - smoothstep(0.7, 0.95, u))
	return -maxf(0.0, cap_y - (_tr_top + 0.3 - 0.91)) * bump


## Sole point (animator frame, root at 0) of the core pose at u.
func _core_sole(mantle: bool, b: String, u: float) -> Vector3:
	if mantle:
		return _cs_climb.at(b, lerpf(CLIMB_T0, CLIMB_T1, u))
	var c := _cs_climb.at(b, lerpf(CLIMB_T0, 0.42, minf(u / 0.45, 1.0)))
	return c.lerp(_cs_tuck.at(b, 0.4), smoothstep(0.2, 0.45, u))


## Plant weight schedule (both hands) at u.
func _core_plan_w(mantle: bool, u: float) -> float:
	if mantle:
		return smoothstep(0.02, 0.2, u) * (1.0 - smoothstep(0.5, 0.88, u))
	return smoothstep(0.12, 0.3, u) * (1.0 - smoothstep(0.6, 0.78, u))


## Plan the visual root offset over the whole traverse from the sampled clips
## along the known capsule path: while the hands are planted the shoulders
## stay within arm reach of the plants, the soles are kept over the obstacle
## (that lift is spread ahead in time so the body rises before a foot gets to
## the face), and the result is smoothed so nothing pops. The post pass then
## only fixes small residuals against the pose actually drawn.
func _plan_core_lift(mantle: bool, cap_now: Vector3) -> void:
	_post_s = Vector4.ZERO
	var off := global_position - cap_now
	var off_f := off.dot(_tr_fwd)
	var N := CORE_PLAN_N
	var base := PackedFloat32Array()
	var feet := PackedFloat32Array()
	var floor_need := PackedFloat32Array()
	base.resize(N + 1)
	feet.resize(N + 1)
	floor_need.resize(N + 1)
	var plant_y := _tr_top + PALM_H
	var plant_f := _tr_edge_f + _core_inset_for(mantle)
	for k in N + 1:
		var u := float(k) / N
		var cap := _core_cap_at(u)
		var by := cap.y + off.y + _vis_y
		var root_f := cap.dot(_tr_fwd) + off_f
		var o := _core_sched_off(mantle, u, cap.y)
		var w := _core_plan_w(mantle, u)
		if w > 0.0:
			var lo := -INF
			var hi := INF
			for i in 2:
				var sh := _core_sole(mantle, "upperarm_l" if i == 0 else "upperarm_r", u)
				var dx := sh.x - (-0.2 if i == 0 else 0.2)
				var dfw := (root_f - sh.z) - plant_f
				var r := _arm_len * 0.93
				var hd := minf(Vector2(dx, dfw).length(), r * 0.9)
				var vr := sqrt(r * r - hd * hd)
				lo = maxf(lo, plant_y - vr - sh.y - by)
				hi = minf(hi, plant_y + vr - sh.y - by)
			o = lerpf(o, clampf(o, lo, maxf(lo, hi)), w)
		base[k] = o
		var fneed := -INF
		var flo := -INF
		for b in ClipSampler.SOLE:
			var p := _core_sole(mantle, b, u)
			var f := root_f - p.z
			if f > _tr_edge_f + 0.005 and f < _tr_back_f + 0.06:
				fneed = maxf(fneed, _tr_top + 0.02 - (by + p.y - float(ClipSampler.SOLE[b])))
			# never under the start floor (the post pass clamp, planned here
			# so the hand-over between it and the top-of-obstacle lift is smooth)
			flo = maxf(flo, _tr_start_y - (by + p.y - float(ClipSampler.SOLE[b])))
		feet[k] = fneed
		floor_need[k] = flo
	# smooth the base path (moving average, +-0.06 u)
	var R := int(0.1 * N)
	var sm := PackedFloat32Array()
	sm.resize(N + 1)
	for k in N + 1:
		var acc := 0.0
		var cnt := 0.0
		for j in range(maxi(0, k - R), mini(N, k + R) + 1):
			acc += base[j]
			cnt += 1.0
		sm[k] = acc / cnt
	sm[0] = 0.0 if mantle else base[0]
	# soles: required extra lift, anticipated (0.2 u ahead) and held briefly
	var win := 0.2 * N
	_core_lift.resize(N + 1)
	for k in N + 1:
		var m := 0.0
		for j in range(maxi(0, k - int(win * 0.5)), mini(N, k + int(win)) + 1):
			if feet[j] == -INF:
				continue
			var need := feet[j] - sm[j]
			var d := float(j - k)
			var ramp := smoothstep(win, 0.0, d) if d >= 0.0 else smoothstep(win * 0.5, 0.0, -d)
			m = maxf(m, need * ramp)
		_core_lift[k] = maxf(sm[k] + m, floor_need[k])
	# envelope smoothing: running max then running mean over the same window,
	# so the result stays >= every constraint but has no kinks where the
	# active constraint switches (that switch was a single-frame pop)
	var W := 5
	var dil := PackedFloat32Array()
	dil.resize(N + 1)
	for k in N + 1:
		var mx := -INF
		for j in range(maxi(0, k - W), mini(N, k + W) + 1):
			mx = maxf(mx, _core_lift[j])
		dil[k] = mx
	for k in N + 1:
		var acc := 0.0
		var cnt := 0.0
		for j in range(maxi(0, k - W), mini(N, k + W) + 1):
			acc += dil[j]
			cnt += 1.0
		_core_lift[k] = acc / cnt
	if OS.get_environment("TRACE_TRAVERSE") != "":
		var sn := ""
		for k in range(0, N + 1, 4):
			sn += "%.2f:%.2f/%.2f " % [float(k) / N, base[k], _core_lift[k]]
		print("PLAN ", "M " if mantle else "V ", "h=%.2f " % _tr_h, sn)


func _core_inset_for(mantle: bool) -> float:
	return 0.07 if mantle else 0.12


func _core_lift_at(u: float) -> float:
	if _core_lift.is_empty():
		return 0.0
	var x := clampf(u, 0.0, 1.0) * CORE_PLAN_N
	var i := mini(int(x), CORE_PLAN_N - 1)
	return lerpf(_core_lift[i], _core_lift[i + 1], x - i)


## While the foot IK fades out at traverse entry a ball that is still pinned
## from the run-up can sit a few cm past the obstacle face (the clip toe
## reached into it on the last stride). Slide such locks back onto the floor
## in front of the face; the clip pose itself is kept out by the root push.
func _keep_locks_off_face() -> void:
	if foot_ik == null or foot_ik.weight <= 0.0:
		return
	var lim := _tr_edge_f - 0.02
	for i in 2:
		if not foot_ik.planted[i]:
			continue
		var lp: Vector3 = foot_ik.lock_pos[i]
		var f := lp.dot(_tr_fwd)
		if f > lim and lp.y < _tr_top:
			foot_ik.lock_pos[i] = lp - _tr_fwd * (f - lim)


func _drive_traverse_core(dt: float, st: String) -> void:
	var trav := st == "VAULT" or st == "MANTLE"
	var cap := _pc.get_global_transform_interpolated().origin
	if trav and (_prev_ctrl_state != st or _tr_h == 0.0):
		var pts: Array = _pc._tr_points
		_tr_fwd = _pc._tr_dir
		_tr_start_y = (pts[0] as Vector3).y
		_tr_h = (pts[1] as Vector3).y - _tr_start_y
		_tr_top = (pts[1] as Vector3).y - 0.06
		_tr_face = (pts[1] as Vector3) + _tr_fwd * _pc.body_radius
		_tr_edge_f = _tr_face.dot(_tr_fwd)
		_tr_back_f = _find_back_face(cap, _tr_edge_f)
		_plant_set = [false, false]
		_core_w = [0.0, 0.0]
		_plan_core_lift(st == "MANTLE", cap)
	if trav:
		_keep_locks_off_face()
	hand_contact = [false, false]
	_tr_lean = 0.0   # (a modifier lean is not in the pose the post pass reads)
	if not trav:
		_tr_h = 0.0
		_core_plan = [0.0, 0.0]
		_tr_off = lerpf(_tr_off, 0.0, 1.0 - exp(-16.0 * dt))
		_tr_fwd_off = lerpf(_tr_fwd_off, 0.0, 1.0 - exp(-16.0 * dt))
		for i in 2:
			hand_w[i] = lerpf(hand_w[i], 0.0, 1.0 - exp(-20.0 * dt))
	else:
		var u := get_traverse_progress()
		_core_u = u
		var y := cap.y
		var plant_in := 0.0
		var plant_out := 1.0
		_core_inset = 0.07
		if st == "MANTLE":
			# hang/reach -> pull: visual root rises later than the capsule
			# (the climb loop swings a foot forward from u ~0.5: by then the
			# body must be high enough for that foot to land on the top)
			_tr_off = _core_lift_at(u)
			_tr_fwd_off = 0.0
			plant_in = smoothstep(0.02, 0.2, u)
			plant_out = 1.0 - smoothstep(0.5, 0.88, u)
		else:
			# speed vault: hips skim over the top while the hands push off it
			_tr_off = _core_lift_at(u)
			_tr_fwd_off = 0.0
			plant_in = smoothstep(0.12, 0.3, u)
			plant_out = 1.0 - smoothstep(0.6, 0.78, u)
			_core_inset = 0.12
		var right := _tr_fwd.cross(Vector3.UP).normalized()
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			_core_plan[i] = plant_in * plant_out
			if not _plant_set[i]:
				_plant_set[i] = true
				_ik_t[i].global_position = Vector3(_tr_face.x, _tr_top + PALM_H, _tr_face.z) \
					+ _tr_fwd * _core_inset + right * side * 0.2
	var lf := global_basis.inverse() * (_tr_fwd * _tr_fwd_off)
	character.position = Vector3(lf.x, _vis_y + _tr_off, lf.z)
	_core_ik_out(trav)


## Elbow poles / IK node weights from hand_w (+ targets when not traversing).
func _core_ik_out(trav: bool) -> void:
	var right := _tr_fwd.cross(Vector3.UP).normalized()
	var iks := [arm_ik, arm_ik_r]
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tp: Vector3 = _ik_tf_world[i]
		# elbows: behind and outside the hand, slightly down (push-up)
		_ik_p[i].global_position = tp - _tr_fwd * 0.6 + right * side * 0.45 - Vector3.UP * 0.1
		_ik_t[i].global_basis = Basis.looking_at(-_tr_fwd, Vector3.UP)
		iks[i].influence = clampf(hand_w[i], 0.0, 1.0)
		iks[i].active = hand_w[i] > 0.001
	hand_ik_weight = maxf(hand_w[0], hand_w[1])


## Post pass (after anim_tree.advance): correct the visual root from the pose
## the tree actually produced, then aim the hands.
func _core_traverse_post() -> void:
	if has_extras or _tr_h == 0.0 or _pc.state != PlayerController.State.TRAVERSE:
		return
	var right := _tr_fwd.cross(Vector3.UP).normalized()
	var xf := render_xf(skeleton)
	var P := func(b: String) -> Vector3:
		return xf * skeleton.get_bone_global_pose(skeleton.find_bone(b)).origin
	var L := _arm_len
	var dy := 0.0
	var df := 0.0     # + = toward the obstacle
	# 1) reach: each scheduled hand's shoulder within 0.95 L of its plant
	# (each correction scaled by that hand's plant weight, so it fades in
	# and out with the plant instead of popping)
	var lo := 0.0
	var hi := 0.0
	for i in 2:
		var w: float = _core_plan[i]
		if w <= 0.0:
			continue
		var sh: Vector3 = P.call("upperarm_l" if i == 0 else "upperarm_r")
		var plant: Vector3 = _ik_t[i].global_position
		var hd := Vector2(sh.x - plant.x, sh.z - plant.z).length()
		var r := L * 0.95
		if hd > r * 0.9:
			df = maxf(df, (hd - r * 0.9) * w)
			hd = r * 0.9
		var vr := sqrt(r * r - hd * hd)
		lo = maxf(lo, (plant.y - vr - sh.y) * w)   # shoulder not too far below
		hi = minf(hi, (plant.y + vr - sh.y) * w)   # ... nor too far above
	dy = lo if lo > 0.0 else hi
	# 2) soles: a sole inside the block is lifted over its top or the body
	# is held back from the face, whichever is cheaper; never under the start
	# floor. (Round 4: the old 25 cm anticipation ramp lifted the whole body
	# by up to top-minus-sole (~1.3 m) within a few frames at mantle entry.)
	var lift := 0.0
	var push := 0.0
	for b in ClipSampler.SOLE:
		var p: Vector3 = P.call(b) - Vector3(0, ClipSampler.SOLE[b], 0)
		p += Vector3.UP * dy + _tr_fwd * df
		var f := p.dot(_tr_fwd)
		if f < _tr_back_f + 0.02 and p.y < _tr_top + 0.005:
			# only a sole actually inside the block is corrected, by the
			# cheaper of lifting it over the top or holding the body back
			# from the face (soft choice so the switch cannot pop)
			var pen := (f - (_tr_edge_f - 0.01))
			if pen > 0.0:
				var need_up := _tr_top + 0.005 - p.y
				var w := smoothstep(-0.05, 0.05, need_up - pen)
				lift = maxf(lift, need_up * (1.0 - w))
				push = maxf(push, pen * w)
		lift = maxf(lift, _tr_start_y - 0.005 - p.y)
	df -= push
	# the post corrections are per-frame residuals of the plan; feed them
	# through a critically damped spring so a constraint switching on/off
	# (or the plan/pose mismatch changing slope) cannot pop the body
	dy += lift
	var sdt := 1.0 / float(Engine.physics_ticks_per_second)
	var om := float(OS.get_environment("POST_OM")) if OS.get_environment("POST_OM") != "" else 20.0
	# exact critically damped step (frame-rate independent, stable at 30 Hz)
	var ex := exp(-om * sdt)
	var ey := _post_s.x - dy
	var jy := (_post_s.y + om * ey) * sdt
	_post_s.x = dy + (ey + jy) * ex
	_post_s.y = (_post_s.y - om * jy) * ex
	var ef := _post_s.z - df
	var jf := (_post_s.w + om * ef) * sdt
	_post_s.z = df + (ef + jf) * ex
	_post_s.w = (_post_s.w - om * jf) * ex
	# hard guarantee after the smoothing: whatever penetration the lag left
	# is projected out (and folded into the spring state so it stays smooth
	# from the next frame on). Usually a few mm.
	lift = 0.0
	push = 0.0
	for b in ClipSampler.SOLE:
		var p: Vector3 = P.call(b) - Vector3(0, ClipSampler.SOLE[b], 0)
		p += Vector3.UP * _post_s.x + _tr_fwd * _post_s.z
		var f := p.dot(_tr_fwd)
		if f < _tr_back_f + 0.02 and p.y < _tr_top + 0.005:
			var pen := (f - (_tr_edge_f - 0.01))
			if pen > 0.0:
				var need_up := _tr_top + 0.005 - p.y
				var w := smoothstep(-0.05, 0.05, need_up - pen)
				lift = maxf(lift, need_up * (1.0 - w))
				push = maxf(push, pen * w)
		lift = maxf(lift, _tr_start_y - 0.005 - p.y)
	_post_s.x += lift
	_post_s.z -= push
	dy = _post_s.x
	df = _post_s.z
	lift = 0.0
	if OS.get_environment("TRACE_TRAVERSE") != "":
		var lows := INF
		for b in ClipSampler.SOLE:
			lows = minf(lows, (P.call(b) - Vector3(0, ClipSampler.SOLE[b], 0)).y)
		print("POST u=%.3f base=%.3f reach_dy=%.3f lift=%.3f df=%.3f low_sole=%.3f start_y=%.3f anim_y=%.3f char_y=%.3f vis=%.3f top=%.3f" % [_core_u, _tr_off, dy, lift, df, lows, _tr_start_y, global_position.y, character.position.y, _vis_y, _tr_top])
	dy += lift
	_tr_off += dy
	_tr_fwd_off += df
	var lf := global_basis.inverse() * (_tr_fwd * _tr_fwd_off)
	character.position = Vector3(lf.x, _vis_y + _tr_off, lf.z)
	xf = render_xf(skeleton)
	# 3) hands: target from the FK hand over the lip onto the plant; weight
	# gated by real reach; FK hands kept out of the obstacle
	for i in 2:
		var hn := "hand_l" if i == 0 else "hand_r"
		var fk: Vector3 = xf * skeleton.get_bone_global_pose(skeleton.find_bone(hn)).origin
		var sh: Vector3 = xf * skeleton.get_bone_global_pose(skeleton.find_bone("upperarm_l" if i == 0 else "upperarm_r")).origin
		var plant: Vector3 = _ik_t[i].global_position
		var w: float = _core_plan[i]
		var reach_ok := 1.0 - smoothstep(0.0, 0.03, sh.distance_to(plant) - L * 0.99)
		# plant blend: schedule x soft reach, rate-limited (<= 0.15 s for a
		# full swing) so a change in reach never snaps the hand
		var reach_soft := 1.0 - smoothstep(0.0, 0.15, sh.distance_to(plant) - L * 0.99)
		_core_w[i] = move_toward(_core_w[i], w * reach_soft, get_process_delta_time() * 6.5)
		var we: float = _core_w[i]
		var tgt := fk.lerp(plant, smoothstep(0.0, 1.0, we))
		tgt.y = lerpf(fk.y, plant.y + 0.10 * (1.0 - we), smoothstep(0.0, 0.6, we)) if we < 0.999 else plant.y
		# Round 5: mantle stand-up. Once a hand has let go of the ledge the
		# FK hand is the climb loop's NEXT reach, which swung the free arm up
		# beside the head while the body stood up. Pull released hands down
		# to a relaxed hang beside the thigh instead (the IK is fully on for
		# the whole traverse, so this only moves the target).
		if _pc.get_state_name() == "MANTLE":
			var rr := smoothstep(0.5, 0.8, _core_u) * (1.0 - we)
			if rr > 0.0:
				var hang := sh + Vector3.DOWN * L * MANTLE_HANG_DROP + _tr_fwd * 0.05 \
					+ right * (-1.0 if i == 0 else 1.0) * 0.07
				tgt = tgt.lerp(hang, rr)
		# keep the wrist out of the obstacle box (palm ~3 cm under the wrist)
		var f := tgt.dot(_tr_fwd)
		if f > _tr_edge_f - 0.04 and f < _tr_back_f + 0.04 and tgt.y < _tr_top + PALM_H:
			var over := _tr_top + PALM_H - tgt.y
			var back := f - (_tr_edge_f - 0.04)
			if back < over:
				tgt -= _tr_fwd * back
			else:
				tgt.y = _tr_top + PALM_H
		# the IK is fully on for the whole traverse: the target itself carries
		# the FK -> plant blend (an out-of-reach target leaves the arm extended
		# toward it, never a half-weighted hand inside the obstacle)
		hand_w[i] = 1.0
		_ik_tf_world[i] = tgt
		hand_contact[i] = we > 0.99 and reach_ok > 0.99 and tgt.distance_to(plant) < 0.005
	_core_ik_out(true)
	_feed_arm_ik()


## World position of a sampled clip joint for the current visual root.
func _clip_world(cs: ClipSampler, b: String, t: float, cap: Vector3, cap_f: float, root_y: float, root_f: float, right: Vector3) -> Vector3:
	var bp := cs.at(b, t)
	return Vector3(cap.x, root_y + bp.y, cap.z) + right * bp.x + _tr_fwd * (root_f - bp.z - cap_f)


## Feed the arm IK its targets in skeleton space of the DRAWN skeleton.
func _feed_arm_ik() -> void:
	var inv := render_xf(skeleton).affine_inverse()
	for i in 2:
		_ik_tf[i].transform = inv * Transform3D(_ik_t[i].global_basis, _ik_tf_world[i])
		_ik_pf[i].transform = inv * _ik_p[i].global_transform


## Roll grounding: something is always on the floor in a ground roll (hands,
## then shoulders/back, then feet). For each clip time in the roll window the
## lowest contact point of the clip pose (joint height minus a body radius) is
## measured and the visual root is lowered by that much, smoothed over
## +-0.06 s so the drop never steps. Pure presentation.
const ROLL_RADIUS := {"hand_l": 0.03, "hand_r": 0.03, "Head": 0.11, "upperarm_l": 0.07,
	"upperarm_r": 0.07, "spine_02": 0.12, "pelvis": 0.11}
const ROLL_DROP_N := 64
## half-width (drop samples) of the moving-max envelope before smoothing
const ROLL_DROP_CORR_W := 2


func _sample_roll(m: Transform3D) -> void:
	var bones := PackedStringArray(ROLL_RADIUS.keys())
	for b in ClipSampler.SOLE:
		bones.append(b)
	var clip := clip_library().get_animation("roll_tuck")
	var cs := ClipSampler.sample(skeleton, m, clip, bones)
	if not clip.has_meta("pelvis_capped") and OS.get_environment("ROLL_NOCAP") != "1":
		clip.set_meta("pelvis_capped", _cap_roll_pelvis(clip, cs, m))
		cs = ClipSampler.sample(skeleton, m, clip, bones)
	_cs_roll = cs
	var raw := PackedFloat32Array()
	for i in ROLL_DROP_N + 1:
		var t := lerpf(ROLL_T0, ROLL_T1, float(i) / ROLL_DROP_N)
		var low := cs.sole_min(t)
		for b in ROLL_RADIUS:
			low = minf(low, cs.at(b, t).y - ROLL_RADIUS[b])
		raw.append(low)   # signed: lower a floating pose, lift a pose that sinks in
	_roll_drop.resize(ROLL_DROP_N + 1)
	var w := int(ceil(0.06 / ((ROLL_T1 - ROLL_T0) / ROLL_DROP_N)))
	for i in ROLL_DROP_N + 1:
		var acc := 0.0
		var n := 0
		for j in range(i - w, i + w + 1):
			acc += raw[clampi(j, 0, ROLL_DROP_N)]
			n += 1
		_roll_drop[i] = acc / n
	# round 6: the plain average under-drops where the pose's lowest contact
	# peaks (hand plant: hands 2-4 cm off the floor -> pelvis 0.57 m). Never
	# leave the lowest contact floating: the shortfall (raw - average, >= 0)
	# is enveloped (moving max +-ROLL_DROP_CORR_W) and smoothed, then added
	if OS.get_environment("ROLL_DROP_PLAIN") != "1":
		var corr := PackedFloat32Array()
		corr.resize(ROLL_DROP_N + 1)
		for i in ROLL_DROP_N + 1:
			corr[i] = maxf(raw[i] - _roll_drop[i], 0.0)
		var cw := ROLL_DROP_CORR_W
		var cenv := PackedFloat32Array()
		cenv.resize(ROLL_DROP_N + 1)
		for i in ROLL_DROP_N + 1:
			for j in range(i - cw, i + cw + 1):
				cenv[i] = maxf(cenv[i], corr[clampi(j, 0, ROLL_DROP_N)])
		for i in ROLL_DROP_N + 1:
			var acc := 0.0
			var ws := 0.0
			for j in range(i - cw, i + cw + 1):
				var wj := 1.0 - absf(j - i) / float(cw + 1)
				acc += cenv[clampi(j, 0, ROLL_DROP_N)] * wj
				ws += wj
			_roll_drop[i] += acc / ws
	if OS.has_environment("ROLL_DEBUG"):
		print("ROLL_DROP ", Array(_roll_drop).map(func(x): return snappedf(x, 0.01)))
		var vmax := 0.0
		var tt := 0.0
		while tt < cs.t_len - 0.02:
			var v := (cs.at("Head", tt + 1.0 / 60.0) - cs.at("Head", tt)).length() * 60.0
			if tt >= ROLL_T0 - 0.01 and tt <= ROLL_T1:
				vmax = maxf(vmax, v)
			tt += 1.0 / 60.0
		print("ROLL_CLIP window head_v_max (clip time) %.2f  x playback %.2f" % [vmax, (ROLL_T1 - ROLL_T0) / 0.6])


## Pelvis cap (tucked back): while the trunk is pitched over (head not above
## the pelvis) the source clip keeps the back straight, so the inverted body
## stands on its head with the pelvis ~0.7 m up, which reads as a jump. A
## real forward roll rounds the back and tucks the chin so the hips pass
## over the shoulders low. Here a per-key spine/neck flexion (spine_01..03,
## neck_01, Head: rotation about each bone's lateral axis) is solved so the
## pelvis stays <= the cap above the lowest body contact: the clip is sampled
## at a few uniform curl levels, each key takes the smallest level that meets
## the cap (linear between levels), and that curve is smoothed (+-ROLL_CAP_SM s)
## and rate-limited (ROLL_CAP_RATE deg/s of clip time) so nothing whips.
## Returns the largest curl (deg, summed over the chain).
const ROLL_PELVIS_CAP := 0.45
const ROLL_CURL_BONES := {"spine_01": 0.2, "spine_02": 0.25, "spine_03": 0.25, "neck_01": 0.15, "Head": 0.15,
	"upperarm_l": -ROLL_ARM_COMP, "upperarm_r": -ROLL_ARM_COMP}
## the arms hang from spine_03: counter-rotate them so the curl rounds the
## back without swinging the hands further down (hands-planted entry)
const ROLL_ARM_COMP := 0.7
const ROLL_CURL_LEVELS := [0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0]
const ROLL_CAP_SM := 0.10
const ROLL_CAP_RATE := 400.0


func _roll_pelvis_h(cs: ClipSampler, t: float) -> float:
	var low := cs.sole_min(t)
	for b in ROLL_RADIUS:
		low = minf(low, cs.at(b, t).y - ROLL_RADIUS[b])
	return cs.at("pelvis", t).y - low


func _apply_roll_curl(clip: Animation, orig: Dictionary, axes: Dictionary, curl_at: Callable) -> void:
	for tr in orig:
		var bn := str(clip.track_get_path(tr)).get_slice(":", 1)
		var vals: Array = orig[tr]
		for k in vals.size():
			var c: float = curl_at.call(clip.track_get_key_time(tr, k))
			clip.track_set_key_value(tr, k, ((vals[k] as Quaternion) * Quaternion(axes[bn], deg_to_rad(c * ROLL_CURL_BONES[bn]))).normalized())


func _cap_roll_pelvis(clip: Animation, cs: ClipSampler, m: Transform3D) -> float:
	var cap := float(OS.get_environment("ROLL_CAP")) if OS.has_environment("ROLL_CAP") else ROLL_PELVIS_CAP
	var rate := float(OS.get_environment("ROLL_CAP_RATE")) if OS.has_environment("ROLL_CAP_RATE") else ROLL_CAP_RATE
	var bones := PackedStringArray(ROLL_RADIUS.keys())
	for b in ClipSampler.SOLE:
		bones.append(b)
	# lateral axis of each curl bone in its own local frame (rest pose)
	var lat_sk := m.basis.inverse() * Vector3.RIGHT
	var orig := {}
	var axes := {}
	for bn in ROLL_CURL_BONES:
		var tr := clip.find_track(NodePath("Armature/Skeleton3D:" + bn), Animation.TYPE_ROTATION_3D)
		if tr < 0:
			continue
		var vals := []
		for k in clip.track_get_key_count(tr):
			vals.append(clip.track_get_key_value(tr, k))
		orig[tr] = vals
		axes[bn] = (skeleton.get_bone_global_rest(skeleton.find_bone(bn)).basis.inverse() * lat_sk).normalized()
	if orig.is_empty():
		return 0.0
	# sign of flexion: the one that lowers the pelvis at the worst frame
	var sgn := 1.0
	var probe := {}
	for sv in [1.0, -1.0]:
		_apply_roll_curl(clip, orig, axes, func(_t): return sv * 30.0)
		probe[sv] = ClipSampler.sample(skeleton, m, clip, bones)
	var gain := 0.0
	var tt := ROLL_T0
	while tt <= ROLL_T1:
		gain += _roll_pelvis_h(probe[-1.0], tt) - _roll_pelvis_h(probe[1.0], tt)
		tt += 1.0 / 30.0
	sgn = 1.0 if gain > 0.0 else -1.0
	var lv := []
	for c in ROLL_CURL_LEVELS:
		_apply_roll_curl(clip, orig, axes, func(_t): return sgn * c)
		lv.append(ClipSampler.sample(skeleton, m, clip, bones))
	# per-frame needed curl (60 Hz clip time)
	var n := int(ceil(clip.length * 60.0)) + 1
	var need := PackedFloat32Array()
	need.resize(n)
	for f in n:
		var t := f / 60.0
		if t < ROLL_T0 - 0.05 or t > ROLL_T1 or cs.at("Head", t).y - cs.at("pelvis", t).y >= 0.3:
			continue
		var h_prev := _roll_pelvis_h(lv[0], t)
		if h_prev <= cap:
			continue
		var c_need: float = ROLL_CURL_LEVELS[-1]
		for i in range(1, lv.size()):
			var h := _roll_pelvis_h(lv[i], t)
			if h <= cap:
				var x := clampf((h_prev - cap) / maxf(h_prev - h, 0.001), 0.0, 1.0)
				c_need = lerpf(ROLL_CURL_LEVELS[i - 1], ROLL_CURL_LEVELS[i], x)
				break
			h_prev = h
		need[f] = c_need
	# envelope-preserving smooth: moving max over +-SM, then triangular smooth
	var env := PackedFloat32Array()
	env.resize(n)
	var w := int(ROLL_CAP_SM * 60.0)
	for f in n:
		var mx := 0.0
		for j in range(maxi(f - w, 0), mini(f + w, n - 1) + 1):
			mx = maxf(mx, need[j])
		env[f] = mx
	var curl := PackedFloat32Array()
	curl.resize(n)
	for f in n:
		var acc := 0.0
		var ws := 0.0
		for j in range(maxi(f - w, 0), mini(f + w, n - 1) + 1):
			var wj := 1.0 - absf(j - f) / float(w + 1)
			acc += env[j] * wj
			ws += wj
		curl[f] = acc / ws
	var lim := rate / 60.0
	for f in range(1, n):
		curl[f] = minf(curl[f], curl[f - 1] + lim)
	for f in range(n - 2, -1, -1):
		curl[f] = minf(curl[f], curl[f + 1] + lim)
	var cmax := 0.0
	for x in curl:
		cmax = maxf(cmax, x)
	_apply_roll_curl(clip, orig, axes, func(t: float) -> float:
		var x := clampf(t * 60.0, 0.0, n - 1.0)
		var i := mini(int(x), n - 2)
		return sgn * lerpf(curl[i], curl[i + 1], x - i))
	if OS.has_environment("ROLL_DEBUG"):
		var out := []
		for f in range(0, n, 2):
			out.append(snappedf(curl[f], 1.0))
		print("ROLL_CAP sgn=%d max=%.1f deg curl(30Hz)=%s" % [sgn, cmax, out])
	if OS.get_environment("ROLL_NOPITCH") != "1":
		_cap_roll_pitch(clip, ClipSampler.sample(skeleton, m, clip, bones), m, cap, bones)
	return cmax


## Second stage: whole-body pitch about the pelvis joint (pelvis rotation
## track) for the frames the curl cannot fix (hands planted, hips high):
## per pelvis key the signed pitch within +-ROLL_PITCH_STEP deg that best
## meets the cap, smoothed and rate-limited, iterated ROLL_PITCH_PASSES times.
const ROLL_PITCH_STEP := 40
## pitch only after the entry crossfade (clip time past ROLL_T0)
const ROLL_PITCH_SKIP := 0.12
const ROLL_PITCH_PASSES := 4
const ROLL_PITCH_RATE := 240.0


func _roll_pitch_h(cs: ClipSampler, t: float, r: Quaternion) -> float:
	var pel := cs.at("pelvis", t)
	var low := INF
	for b in ROLL_RADIUS:
		low = minf(low, (pel + r * (cs.at(b, t) - pel)).y - ROLL_RADIUS[b])
	for b in ClipSampler.SOLE:
		low = minf(low, (pel + r * (cs.at(b, t) - pel)).y - ClipSampler.SOLE[b])
	return pel.y - low


func _cap_roll_pitch(clip: Animation, cs: ClipSampler, m: Transform3D, cap: float, bones: PackedStringArray) -> void:
	var tr := clip.find_track(NodePath("Armature/Skeleton3D:pelvis"), Animation.TYPE_ROTATION_3D)
	if tr < 0:
		return
	var pb := skeleton.find_bone("pelvis")
	var par := skeleton.get_bone_parent(pb)
	var qp := (m.basis * (skeleton.get_bone_global_rest(par).basis if par >= 0 else Basis.IDENTITY)).get_rotation_quaternion()
	var rate := float(OS.get_environment("ROLL_PITCH_RATE")) if OS.has_environment("ROLL_PITCH_RATE") else ROLL_PITCH_RATE
	var nk := clip.track_get_key_count(tr)
	var orig: Array[Quaternion] = []
	for k in nk:
		orig.append(clip.track_get_key_value(tr, k))
	var total := PackedFloat32Array()
	total.resize(nk)
	for pass_i in ROLL_PITCH_PASSES:
		var d := PackedFloat32Array()
		d.resize(nk)
		for k in nk:
			var t := clip.track_get_key_time(tr, k)
			if t < ROLL_T0 + ROLL_PITCH_SKIP or t > ROLL_T1 or cs.at("Head", t).y - cs.at("pelvis", t).y >= 0.3:
				continue
			var h0 := _roll_pitch_h(cs, t, Quaternion.IDENTITY)
			if h0 <= cap:
				continue
			var best := h0
			for a in range(-ROLL_PITCH_STEP, ROLL_PITCH_STEP + 1, 2):
				var h := _roll_pitch_h(cs, t, Quaternion(Vector3.RIGHT, deg_to_rad(a)))
				if maxf(h, cap) + absf(a) * 0.0005 < maxf(best, cap) + absf(d[k]) * 0.0005:
					best = h
					d[k] = a
		for k in nk:
			var acc := 0.0
			var wsum := 0.0
			for j in nk:
				var dt := absf(clip.track_get_key_time(tr, j) - clip.track_get_key_time(tr, k))
				if dt < ROLL_CAP_SM:
					var w := 1.0 - dt / ROLL_CAP_SM
					acc += d[j] * w
					wsum += w
			total[k] += acc / wsum
		for k in range(1, nk):
			var lim := rate * (clip.track_get_key_time(tr, k) - clip.track_get_key_time(tr, k - 1))
			total[k] = clampf(total[k], total[k - 1] - lim, total[k - 1] + lim)
		for k in range(nk - 2, -1, -1):
			var lim := rate * (clip.track_get_key_time(tr, k + 1) - clip.track_get_key_time(tr, k))
			total[k] = clampf(total[k], total[k + 1] - lim, total[k + 1] + lim)
		for k in nk:
			clip.track_set_key_value(tr, k, (qp.inverse() * Quaternion(Vector3.RIGHT, deg_to_rad(total[k])) * qp * orig[k]).normalized())
		cs = ClipSampler.sample(skeleton, m, clip, bones)
	if OS.has_environment("ROLL_DEBUG"):
		print("ROLL_PITCH deg=%s" % [Array(total).slice(0, 26).map(func(x): return snappedf(x, 1.0))])


## drop for roll progress u (0..1), faded in over the state crossfade
func roll_drop(u: float) -> float:
	if _roll_drop.is_empty():
		return 0.0
	var x := clampf(u, 0.0, 1.0) * ROLL_DROP_N
	var i := mini(int(x), ROLL_DROP_N - 1)
	return lerpf(_roll_drop[i], _roll_drop[i + 1], x - i)


func get_traverse_progress() -> float:
	if _pc.state != PlayerController.State.TRAVERSE:
		return 1.0
	return clampf(_pc._tr_time / maxf(_pc._tr_duration, 0.01), 0.0, 1.0)


func _drive_procedural(dt: float, st: String) -> void:
	var on_ground := st == "GROUND"
	# Lean = atan(a / g): forward on acceleration, back on braking; bank into
	# turns from the centripetal acceleration v * yaw_rate.
	var a_f := p_accel.y
	var a_lat := p_speed * p_turn_rate   # + = turning left
	var pitch_t := clampf(atan(a_f / 9.81) * 0.55, deg_to_rad(-9.0), deg_to_rad(10.0)) if on_ground else 0.0
	var bank_t := clampf(-atan(a_lat / 9.81) * 0.6, deg_to_rad(-14.0), deg_to_rad(14.0)) if on_ground and not _pc.is_crouched else 0.0
	_pitch_s = lerpf(_pitch_s, pitch_t, 1.0 - exp(-8.0 * dt))
	if st == "VAULT" or st == "MANTLE" or absf(_tr_lean) > 0.001:
		_pitch_s = maxf(_pitch_s, _tr_lean)
	_bank_s = lerpf(_bank_s, bank_t, 1.0 - exp(-8.0 * dt))
	# Slope / stair: drop the pelvis a little so the lower foot reaches.
	# (superseded by FootIK's ground-raycast pelvis correction when it is on)
	var drop_t := clampf(tan(deg_to_rad(p_slope_deg)) * 0.12, 0.0, 0.08) if on_ground and not foot_ik_enabled else 0.0
	var foot_t := 1.0 if foot_ik_enabled and on_ground and anim_state == "ground" else 0.0
	_foot_w = lerpf(_foot_w, foot_t, 1.0 - exp(-(10.0 if foot_t > _foot_w else 30.0) * dt))
	if _foot_w < 0.002 and foot_t == 0.0:
		_foot_w = 0.0
	foot_ik.weight = _foot_w
	# a pinned ball normally leaves via FootIK's swing release (clip ball
	# speed / toe-off height); 0.24 m is only the hard safety break
	foot_ik.max_lock_offset = 0.24
	# backpedal: the clip lifts the foot itself; no extra toe-off arc
	var bwd_w := _aim_s * clampf(-_aim_bp.y * 2.0, 0.0, 1.0)
	foot_ik.swing_arc_scale = lerpf(1.0, BWD_ARC, bwd_w)
	foot_ik.dt = dt
	foot_ik.active = _foot_w > 0.0
	_drop_s = lerpf(_drop_s, drop_t, 1.0 - exp(-10.0 * dt))
	pose_mod.pitch = _pitch_s
	pose_mod.bank = _bank_s
	pose_mod.pelvis_drop = _drop_s
	pose_mod.warp = warp_angle if anim_state == "ground" else lerpf(pose_mod.warp, 0.0, 1.0 - exp(-12.0 * dt))


func get_anim_debug() -> Dictionary:
	return {
		"anim_state": anim_state,
		"sm_node": String(_pb.get_current_node()) if _pb else "",
		"tree_active": anim_tree.active if anim_tree else false,
		"speed": p_speed, "local_dir": p_local_dir, "accel": p_accel, "turn_rate": p_turn_rate,
		"grounded": p_grounded, "vy": p_vy, "state": p_state, "slope_deg": p_slope_deg,
		"land_severity": p_land_severity, "land_weight": land_weight,
		"gait": gait, "run_style": run_style, "cycle_rate": cycle_rate, "warp_deg": rad_to_deg(warp_angle),
		"bank_deg": rad_to_deg(_bank_s), "pitch_deg": rad_to_deg(_pitch_s),
		"foot_ik_w": _foot_w, "foot_ik": foot_ik.debug if foot_ik else {},
	}
