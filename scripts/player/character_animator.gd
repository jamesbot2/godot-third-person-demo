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
const CLIP_LIB := preload("res://assets/animations/ual_clips.res")
const BodyPoseModifierScript := preload("res://scripts/player/body_pose_modifier.gd")

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
@export var backward_enter_deg := 115.0
@export var backward_exit_deg := 95.0

# Roll clip window used for the controller's roll (s, clip time).
const ROLL_T0 := 0.36
const ROLL_T1 := 1.25
const SLIDE_T0 := 0.30
const SLIDE_T1 := 0.83
const CLIMB_T0 := 0.10
const CLIMB_T1 := 0.667

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

var character: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var pose_mod: SkeletonModifier3D   # body_pose_modifier.gd
var _pc: PlayerController
var _pb: AnimationNodeStateMachinePlayback
var _yaw := 0.0
var _prev_yaw := 0.0
var _vis_y := 0.0
var _vel_s := Vector3.ZERO
var _acc_s := Vector3.ZERO
var _backward := false
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
	_setup_arm_ik()
	# Modifier results (lean/warp/IK) only exist while the skeleton is being
	# finalised; snapshot the FINAL pose so tests/debug measure what is drawn.
	skeleton.skeleton_updated.connect(_snapshot_final_pose)
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	anim_player.root_node = anim_player.get_path_to(character)
	anim_player.add_animation_library("", CLIP_LIB)
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


func _snapshot_final_pose() -> void:
	var n := skeleton.get_bone_count()
	_final_pose.resize(n)
	for i in n:
		_final_pose[i] = skeleton.get_bone_global_pose(i)


## World-space position of a bone in the final (post-modifier) pose that is
## rendered. Falls back to the animation pose before the first update.
func get_final_bone_world(bone_name: String) -> Vector3:
	var i := skeleton.find_bone(bone_name)
	var pose := _final_pose[i] if i >= 0 and i < _final_pose.size() else skeleton.get_bone_global_pose(i)
	return (skeleton.global_transform * pose).origin


func _setup_arm_ik() -> void:
	var ik := TwoBoneIK3D.new()
	ik.name = "ArmIK"
	skeleton.add_child(ik)   # after BodyPoseModifier: runs on the final pose
	ik.set_setting_count(2)
	for i in 2:
		var sd := "l" if i == 0 else "r"
		var t := Marker3D.new(); t.name = "HandTarget_" + sd; t.top_level = true
		var pl := Marker3D.new(); pl.name = "ElbowPole_" + sd; pl.top_level = true
		add_child(t); add_child(pl)
		_ik_t.append(t); _ik_p.append(pl)
		ik.set_root_bone_name(i, "upperarm_" + sd)
		ik.set_middle_bone_name(i, "lowerarm_" + sd)
		ik.set_end_bone_name(i, "hand_" + sd)
		ik.set_target_node(i, ik.get_path_to(t))
		ik.set_pole_node(i, ik.get_path_to(pl))
	ik.influence = 0.0
	ik.active = false
	arm_ik = ik


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
	var move := _blend2(g, "move", "idle", gaitn, Vector2(900, 100))
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
	rl.connect_node("output", 0, _seeked(rl, "r", "roll", Vector2.ZERO))
	sm.add_node("roll", rl, Vector2(600, 400))
	var mt := AnimationNodeBlendTree.new()
	mt.connect_node("output", 0, _seeked(mt, "c", "climb", Vector2.ZERO))
	sm.add_node("mantle", mt, Vector2(900, 200))
	var vt := AnimationNodeBlendTree.new()
	var vc := _seeked(vt, "c", "climb", Vector2.ZERO)
	var vtuck := _seeked(vt, "tuck", "ninja_air", Vector2(0, 200))
	vt.connect_node("output", 0, _blend2(vt, "tuck_mix", vc, vtuck, Vector2(700, 100)))
	sm.add_node("vault", vt, Vector2(900, 400))
	var xfade := {"ground": 0.18, "jump": 0.08, "air": 0.2, "slide": 0.12, "slide_exit": 0.1,
		"roll": 0.14, "mantle": 0.1, "vault": 0.1}
	for a in xfade:
		for b in xfade:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = xfade[b]
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


## Reads the controller and drives the tree. Separate from _process so tests
## can call it deterministically.
func update_presentation(dt: float) -> void:
	_state_t += dt
	var st := _pc.get_state_name()
	var v3 := _pc.velocity
	var hv := Vector3(v3.x, 0, v3.z)
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
	_drive_ground(dt)
	_drive_actions(dt)
	_drive_traverse_contact(dt, st)
	_drive_procedural(dt, st)
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
			elif anim_state == "vault" and _state_t < 0.05:
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
	var lim := deg_to_rad(warp_limit_deg)
	target_warp = clampf(target_warp, -lim, lim) * clampf((v - 0.3) / 0.5, 0.0, 1.0)
	warp_angle = lerp_angle(warp_angle, target_warp, 1.0 - exp(-12.0 * dt))

	# gait solve: stride needed for a human cadence at this speed
	var stride_need := v * 2.0 / _cadence(v)
	run_style = smoothstep(4.6, 6.6, v)
	gait = _solve_gait(stride_need, run_style)
	var s_blend := _stride_at(gait, run_style)
	cycle_rate = v / s_blend * (-1.0 if _backward else 1.0)
	_move_s = lerpf(_move_s, smoothstep(0.08, 0.7, v), 1.0 - exp(-12.0 * dt))
	var crouch_t := 1.0 if (_pc.is_crouched and p_state == "GROUND") else 0.0
	_crouch_s = lerpf(_crouch_s, crouch_t, 1.0 - exp(-10.0 * dt))
	_p("ground/walk_ts/scale", LEN_WALK * cycle_rate)
	_p("ground/jog_ts/scale", LEN_JOG * cycle_rate)
	_p("ground/sprint_ts/scale", LEN_SPRINT * cycle_rate)
	_p("ground/run/blend_amount", run_style)
	_p("ground/gait/blend_amount", gait)
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
		"mantle":
			var u := get_traverse_progress()
			_p("mantle/c_seek/seek_request", lerpf(CLIMB_T0, CLIMB_T1, u))
			_p("mantle/c_ts/scale", 0.0)
		"vault":
			var u := get_traverse_progress()
			_p("vault/c_seek/seek_request", lerpf(CLIMB_T0, 0.42, minf(u / 0.45, 1.0)))
			_p("vault/c_ts/scale", 0.0)
			_p("vault/tuck_seek/seek_request", 0.4)
			_p("vault/tuck_ts/scale", 0.0)
			_p("vault/tuck_mix/blend_amount", smoothstep(0.2, 0.45, u))


## Vault / mantle presentation: keep the visual body low until the hands are
## planted on the obstacle edge, then let it catch up with the capsule (pure
## visual offset, the controller path is untouched), and pull the hands onto
## the real edge with two-bone arm IK while they can reach it.
func _drive_traverse_contact(dt: float, st: String) -> void:
	var trav := st == "VAULT" or st == "MANTLE"
	if trav and (_prev_ctrl_state != st or _tr_h == 0.0):
		var pts: Array = _pc._tr_points
		_tr_fwd = _pc._tr_dir
		_tr_start_y = (pts[0] as Vector3).y
		_tr_h = (pts[1] as Vector3).y - _tr_start_y
		_tr_top = (pts[1] as Vector3).y - 0.06
		_tr_face = (pts[1] as Vector3) + _tr_fwd * _pc.body_radius
	if not trav:
		_tr_h = 0.0
		_tr_off = lerpf(_tr_off, 0.0, 1.0 - exp(-16.0 * dt))
		_tr_fwd_off = lerpf(_tr_fwd_off, 0.0, 1.0 - exp(-16.0 * dt))
		_tr_lean = lerpf(_tr_lean, 0.0, 1.0 - exp(-10.0 * dt))
		hand_ik_weight = lerpf(hand_ik_weight, 0.0, 1.0 - exp(-20.0 * dt))
		_tr_off_prev = _tr_off
		_tr_fwd_off_prev = _tr_fwd_off
	else:
		var u := get_traverse_progress()
		var y := _pc.global_position.y
		var plant_in := 0.0
		var plant_out := 1.0
		var inset := 0.07
		if st == "MANTLE":
			# hang/reach -> pull: visual root rises later than the capsule
			var w := _tr_start_y + _tr_h * smoothstep(0.2, 0.95, u)
			_tr_off = minf(0.0, w - y)
			_tr_lean = deg_to_rad(28.0) * smoothstep(0.1, 0.4, u) * (1.0 - smoothstep(0.75, 1.0, u))
			# the capsule keeps its radius off the wall; the chest should not
			_tr_fwd_off = 0.2 * smoothstep(0.35, 0.6, u) * (1.0 - smoothstep(0.8, 1.0, u))
			plant_in = smoothstep(0.02, 0.14, u)
			plant_out = 1.0 - smoothstep(0.62, 0.82, u)
		else:
			# speed vault: hips skim ~0.35 m over the top while hands push off it
			var bump := smoothstep(0.15, 0.4, u) * (1.0 - smoothstep(0.7, 0.95, u))
			var dip := maxf(0.0, y - (_tr_top + 0.3 - 0.91))
			_tr_off = -dip * bump
			_tr_lean = deg_to_rad(38.0) * bump
			_tr_fwd_off = 0.0
			plant_in = smoothstep(0.12, 0.3, u)
			plant_out = 1.0 - smoothstep(0.6, 0.78, u)
			inset = 0.12
		hand_ik_weight = plant_in * plant_out
		var right := _tr_fwd.cross(Vector3.UP).normalized()
		_tr_off_prev = _tr_off
		_tr_fwd_off_prev = _tr_fwd_off
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			var tp := Vector3(_tr_face.x, _tr_top + 0.045, _tr_face.z) + _tr_fwd * inset + right * side * 0.2
			_ik_t[i].global_position = tp
			# elbows: behind and outside the hand, slightly down (push-up)
			_ik_p[i].global_position = tp - _tr_fwd * 0.6 + right * side * 0.45 - Vector3.UP * 0.1
			_ik_t[i].global_basis = Basis.looking_at(-_tr_fwd, Vector3.UP)
	arm_ik.influence = clampf(hand_ik_weight, 0.0, 1.0)
	arm_ik.active = hand_ik_weight > 0.001
	var lf := global_basis.inverse() * (_tr_fwd * _tr_fwd_off)
	character.position = Vector3(lf.x, _vis_y + _tr_off, lf.z)


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
	var drop_t := clampf(tan(deg_to_rad(p_slope_deg)) * 0.12, 0.0, 0.08) if on_ground else 0.0
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
	}
