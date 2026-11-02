class_name GrayboxBody
extends Node3D
## Procedural primitive humanoid that visualises the REAL controller state.
## Pure presentation: it never feeds back into movement.
##   * gait phase is driven by distance travelled (no foot sliding drift)
##   * lean from acceleration, bank into turns
##   * placeholder poses for crouch / slide / roll / air / land / vault / mantle
##   * a decaying visual Y offset absorbs step-up pops
##   * chest stripe colour = state (debug readability)

@export var controller_path: NodePath = ^".."

const STATE_COLORS := {
	"GROUND": Color(0.2, 0.75, 0.3), "AIR": Color(0.25, 0.55, 1.0),
	"SLIDE": Color(1.0, 0.6, 0.1), "ROLL": Color(0.9, 0.2, 0.9),
	"VAULT": Color(1.0, 0.95, 0.2), "MANTLE": Color(0.1, 0.9, 0.9),
}

var _pc: PlayerController
var _root: Node3D
var _hips: Node3D
var _spine: Node3D
var _head: Node3D
var _arm := [null, null]
var _elbow := [null, null]
var _leg := [null, null]
var _knee := [null, null]
var _stripe_mat: StandardMaterial3D
var _phase := 0.0
var _vis_y := 0.0
var _land_squash := 0.0
var _lean := Vector2.ZERO
var _yaw := 0.0
var _crouch := 0.0
var _prev_pos := Vector3.ZERO
var _vel_s := Vector3.ZERO
var _acc_s := Vector3.ZERO
var _last_state := ""


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pc = get_node(controller_path) as PlayerController
	_build()
	if _pc:
		_pc.stepped.connect(func(h: float) -> void: _vis_y -= h)
		_pc.landed.connect(func(impact: float, _s: int) -> void: _land_squash = clampf(impact / 14.0, 0.0, 1.0))
		_yaw = _pc.facing_yaw
		_prev_pos = _pc.global_position


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _box(parent: Node3D, size: Vector3, offset: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = offset
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	var skin := _mat(Color(0.85, 0.72, 0.6))
	var cloth := _mat(Color(0.32, 0.36, 0.42))
	var pants := _mat(Color(0.22, 0.24, 0.28))
	_stripe_mat = _mat(Color(0.2, 0.75, 0.3))
	_stripe_mat.emission_enabled = true
	_stripe_mat.emission_energy_multiplier = 0.4
	_root = _pivot(self, Vector3(0, 0.5, 0))          # roll pivot (body centre)
	_hips = _pivot(_root, Vector3(0, 0.45, 0))         # hips at 0.95 m
	_box(_hips, Vector3(0.34, 0.16, 0.2), Vector3.ZERO, pants)
	_spine = _pivot(_hips, Vector3(0, 0.06, 0))
	_box(_spine, Vector3(0.4, 0.52, 0.24), Vector3(0, 0.28, 0), cloth)
	_box(_spine, Vector3(0.41, 0.08, 0.25), Vector3(0, 0.4, 0), _stripe_mat)
	# small backpack so facing direction is readable
	_box(_spine, Vector3(0.3, 0.36, 0.14), Vector3(0, 0.3, 0.18), _mat(Color(0.45, 0.35, 0.25)))
	_head = _pivot(_spine, Vector3(0, 0.6, 0))
	_box(_head, Vector3(0.2, 0.24, 0.22), Vector3(0, 0.12, 0), skin)
	_box(_head, Vector3(0.16, 0.05, 0.04), Vector3(0, 0.15, -0.12), _mat(Color(0.1, 0.1, 0.12)))  # visor = front
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		_arm[s] = _pivot(_spine, Vector3(0.26 * side, 0.5, 0))
		_box(_arm[s], Vector3(0.1, 0.3, 0.1), Vector3(0, -0.15, 0), cloth)
		_elbow[s] = _pivot(_arm[s], Vector3(0, -0.3, 0))
		_box(_elbow[s], Vector3(0.09, 0.28, 0.09), Vector3(0, -0.14, 0), skin)
		_leg[s] = _pivot(_hips, Vector3(0.1 * side, -0.05, 0))
		_box(_leg[s], Vector3(0.14, 0.44, 0.14), Vector3(0, -0.22, 0), pants)
		_knee[s] = _pivot(_leg[s], Vector3(0, -0.44, 0))
		_box(_knee[s], Vector3(0.12, 0.42, 0.12), Vector3(0, -0.21, 0), pants)
		_box(_knee[s], Vector3(0.12, 0.06, 0.22), Vector3(0, -0.42, -0.04), _mat(Color(0.12, 0.12, 0.12)))


func _process(dt: float) -> void:
	if _pc == null or dt <= 0.0:
		return
	var st := _pc.get_state_name()
	var pos := _pc.get_global_transform_interpolated().origin
	var vel := (pos - _prev_pos) / dt
	_prev_pos = pos
	var k := 1.0 - exp(-12.0 * dt)
	var new_vel := _vel_s.lerp(Vector3(vel.x, 0, vel.z), k)
	_acc_s = _acc_s.lerp((new_vel - _vel_s) / dt, 1.0 - exp(-6.0 * dt))
	_vel_s = new_vel
	var speed := _vel_s.length()
	if st != _last_state:
		_last_state = st
		_stripe_mat.albedo_color = STATE_COLORS.get(st, Color.WHITE)

	_yaw = lerp_angle(_yaw, _pc.facing_yaw, 1.0 - exp(-25.0 * dt))
	rotation = Vector3(0, _yaw, 0)
	_vis_y = lerpf(_vis_y, 0.0, 1.0 - exp(-14.0 * dt))
	_land_squash = lerpf(_land_squash, 0.0, 1.0 - exp(-8.0 * dt))

	# Lean (local): forward from forward acceleration, bank from lateral accel.
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var a_f := clampf(_acc_s.dot(fwd) / 20.0, -1.0, 1.0)
	var a_r := clampf(_acc_s.dot(right) / 20.0, -1.0, 1.0)
	var lean_t := Vector2(a_f * 0.18 + clampf(speed / 7.0, 0.0, 1.0) * 0.12, -a_r * 0.15)
	if st != "GROUND":
		lean_t *= 0.4
	_lean = _lean.lerp(lean_t, 1.0 - exp(-10.0 * dt))

	var crouch_t := 0.0
	if _pc.is_crouched or _pc.current_height < _pc.stand_height - 0.01:
		crouch_t = 1.0
	_crouch = lerpf(_crouch, crouch_t, 1.0 - exp(-12.0 * dt))

	# Gait: phase advances with distance (stride grows with speed).
	var stride := 0.9 + 0.22 * speed
	if st == "GROUND" and _pc.is_on_floor():
		_phase = fmod(_phase + speed * dt / stride * PI, TAU)
	var gait := clampf(speed / 4.0, 0.0, 1.6)
	var swing := sin(_phase) * 0.55 * gait

	# Defaults
	_root.position = Vector3(0, 0.5 + _vis_y - _land_squash * 0.18 - _crouch * 0.3, 0)
	_root.rotation = Vector3(-_lean.x, 0, _lean.y)
	_hips.rotation = Vector3.ZERO
	_spine.rotation = Vector3(-_crouch * 0.35 - _land_squash * 0.4, 0, 0)
	_head.rotation = Vector3(_crouch * 0.25, 0, 0)
	var leg_rot := [swing - _crouch * 0.9 - _land_squash * 0.6, -swing - _crouch * 0.9 - _land_squash * 0.6]
	var knee_rot := [maxf(0.0, -swing) * 1.2 * gait + _crouch * 1.6 + _land_squash * 1.0,
		maxf(0.0, swing) * 1.2 * gait + _crouch * 1.6 + _land_squash * 1.0]
	var arm_rot := [-swing * 0.8, swing * 0.8]
	var elbow_rot := [-0.3 - gait * 0.6, -0.3 - gait * 0.6]

	match st:
		"AIR":
			var up := clampf(_pc.velocity.y / 5.0, -1.0, 1.0)
			leg_rot = [-0.5 + up * 0.2, 0.1]
			knee_rot = [1.0, 0.5 - up * 0.3]
			arm_rot = [-0.5 - up * 0.4, -0.5 - up * 0.4]
			elbow_rot = [-0.6, -0.6]
		"SLIDE":
			_root.position.y = 0.32 + _vis_y
			_root.rotation = Vector3(0.9, 0, _lean.y)
			_spine.rotation = Vector3(-0.5, 0, 0)
			leg_rot = [-1.35, -0.9]
			knee_rot = [0.2, 1.4]
			arm_rot = [0.3, -0.9]
			elbow_rot = [-0.2, -0.4]
		"ROLL":
			var u := clampf(_pc.roll_time / _pc.roll_duration, 0.0, 1.0)
			_root.position.y = 0.5 + _vis_y - sin(u * PI) * 0.15
			_root.rotation = Vector3(-u * TAU, 0, 0)
			_spine.rotation = Vector3(-0.9, 0, 0)
			leg_rot = [-1.6, -1.6]
			knee_rot = [2.2, 2.2]
			arm_rot = [-1.2, -1.2]
			elbow_rot = [-1.2, -1.2]
		"VAULT", "MANTLE":
			_spine.rotation = Vector3(-0.6, 0, 0)
			arm_rot = [-2.4, -2.4]
			elbow_rot = [-0.3, -0.3]
			leg_rot = [-0.9, -0.2] if st == "MANTLE" else [-1.2, -1.0]
			knee_rot = [1.4, 0.4] if st == "MANTLE" else [1.2, 1.0]
	for s in 2:
		(_leg[s] as Node3D).rotation = Vector3(leg_rot[s], 0, 0)
		(_knee[s] as Node3D).rotation = Vector3(knee_rot[s], 0, 0)
		(_arm[s] as Node3D).rotation = Vector3(arm_rot[s], 0, 0)
		(_elbow[s] as Node3D).rotation = Vector3(elbow_rot[s], 0, 0)
