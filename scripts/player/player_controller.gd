class_name PlayerController
extends CharacterBody3D
## Third-person character movement controller (graybox, Godot 4.7 / Jolt).
##
## Design goals: physically plausible (mass, inertia, human-scale speeds, no
## instant turns / air steering), but responsive (input buffers, coyote time,
## no long animation locks). See MOVEMENT_SPEC.md for every parameter's meaning.
##
## Architecture: one small explicit state machine (State enum) with one tick
## function per state, plus posture flags (crouch / sprint / aim) that are NOT
## states. Integration uses the midpoint rule so jump height, braking distance
## and slide distance are frame-rate independent (validated at 30/60/120 Hz).

signal landed(impact_speed: float, severity: int)
signal state_changed(old_state: int, new_state: int)
signal stepped(height: float)
signal jumped(kind: String)

enum State { GROUND, AIR, SLIDE, ROLL, TRAVERSE }
enum Traverse { NONE, VAULT, MANTLE }
const STATE_NAMES := ["GROUND", "AIR", "SLIDE", "ROLL", "TRAVERSE"]

@export var camera_rig_path: NodePath
@export var input_enabled := true

@export_group("Body")
## Mass used for pushing physics props (kg).
@export var mass := 80.0
@export var body_radius := 0.35
@export var stand_height := 1.80
@export var crouch_height := 1.15
## Roll / slide collision height (m).
@export var low_height := 1.0

@export_group("Ground speeds (m/s)")
@export var walk_speed := 1.8
@export var jog_speed := 4.2
@export var sprint_speed := 6.8
@export var crouch_speed := 2.0
@export var aim_speed := 3.0
## Aim/strafe direction multipliers (fraction of aim_speed).
@export var strafe_factor := 0.9
@export var backpedal_factor := 0.72
## Max speed multiplier when walking straight up the steepest walkable slope.
@export var uphill_speed_factor := 0.75

@export_group("Ground dynamics (m/s^2)")
## Propulsion from 0 up to jog speed.
@export var ground_accel := 22.0
## Propulsion above jog speed (sprint build-up feels heavier).
@export var sprint_accel := 9.0
## Braking when there is no input (tread friction).
@export var brake_decel := 26.0
## Lateral grip / reverse braking: how fast velocity NOT aligned with input is removed.
@export var turn_grip := 34.0
## Decel when above the current target speed (e.g. releasing sprint, after a slide).
@export var overspeed_decel := 12.0

@export_group("Turning (deg/s)")
@export var turn_rate_slow := 900.0
@export var turn_rate_fast := 420.0
@export var turn_rate_air := 160.0

@export_group("Jump & air")
## Apex height of a full (held) jump above take-off (m).
@export var jump_height := 0.9
## Gravity while rising with jump held (m/s^2). Defines take-off speed: v0 = sqrt(2 g h).
@export var gravity_rise := 12.5
## Gravity while falling (m/s^2). Higher than rise for a less floaty arc.
@export var gravity_fall := 18.0
## Gravity multiplier when jump is released early while rising (variable jump height).
@export var jump_cut_multiplier := 2.6
@export var terminal_speed := 35.0
## Horizontal air acceleration (m/s^2) - small: steering, not flying.
@export var air_accel := 3.0
## Max horizontal speed air control can build from rest (m/s).
@export var air_min_control_speed := 1.0
## Max deceleration against current momentum while airborne (m/s^2).
@export var air_brake := 1.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15

@export_group("Landing")
## Impact speeds (m/s) separating soft / medium / hard landings.
@export var land_medium_speed := 6.5
@export var land_hard_speed := 10.5
@export var land_medium_keep := 0.8
@export var land_medium_recovery := 0.15
@export var land_hard_keep := 0.35
@export var land_hard_recovery := 0.45
## Hard landings block jumping for this long (s).
@export var land_hard_jump_block := 0.2

@export_group("Terrain")
@export var max_step_height := 0.40
## Free tread depth required above a step (m).
@export var step_min_depth := 0.12
@export_range(0.0, 89.0) var max_slope_deg := 45.0
## Extra tolerance on the physics floor test. Contacts on a slope's toe edge
## report a blended normal a few degrees steeper than the face (measured
## 44-46 deg on a 40 deg ramp at 120 Hz), which stalled the player at the foot
## of walkable ramps. Uphill speed scaling still uses max_slope_deg.
@export_range(0.0, 10.0) var slope_contact_tolerance_deg := 3.0

@export_group("Slide")
@export var slide_min_speed := 5.0
@export var slide_boost := 1.0
@export var slide_max_entry := 8.0
@export var slide_max_speed := 11.0
## Kinetic friction while sliding (m/s^2) ~ mu 0.5.
@export var slide_friction := 5.0
@export var slide_gravity_scale := 0.85
@export var slide_steer_rate := 60.0
@export var slide_exit_speed := 2.6
@export var slide_max_time := 1.6
@export var slide_cooldown_time := 0.45
@export var slide_boost_cooldown := 1.2

@export_group("Roll")
@export var roll_duration := 0.6
@export var roll_speed_start := 6.8
@export var roll_speed_end := 3.0
@export var roll_speed_max := 8.0
@export var roll_push_accel := 60.0
@export var roll_steer_rate := 90.0
@export var roll_jump_cancel := 0.7
@export var roll_cooldown_time := 0.5

@export_group("Vault / mantle")
@export var traverse_reach := 0.7
@export var vault_max_height := 1.15
@export var vault_max_thickness := 0.6
@export var mantle_max_height := 1.6
## Max ledge height above the feet that can be caught while airborne (m).
@export var air_mantle_reach := 1.25
@export var vault_exit_speed := 3.5
@export var mantle_exit_speed := 2.0

@export_group("Push")
## Max horizontal force the character can exert on props (N). ~450 N = firm shove.
@export var push_force_max := 450.0

# ---------------------------------------------------------------- runtime ---
var state: int = State.GROUND
var traverse_kind: int = Traverse.NONE
var facing_yaw := 0.0
var wish_dir := Vector3.ZERO
var wish_strength := 0.0
var move_input := Vector2.ZERO
var is_crouched := false
var crouch_toggled := false
var walk_toggled := false
var is_sprinting := false
var is_aiming := false
var time_since_grounded := 0.0
var jumped_this_air := false
var jump_rising := false
var jump_buffer := 0.0
var crouch_buffer := 0.0
var roll_buffer := 0.0
var landing_recovery := 0.0
var landing_speed_scale := 1.0
var landing_jump_block := 0.0
var last_impact := 0.0
var last_land_severity := 0
var slide_cooldown := 0.0
var slide_boost_timer := 0.0
var slide_time := 0.0
var roll_cooldown := 0.0
var roll_time := 0.0
var roll_dir := Vector3.FORWARD
var roll_start_speed := 0.0
var step_count := 0
var sim_time := 0.0
var current_height := 1.8
var accel_world := Vector3.ZERO

var _rig: Node
var _collider: CollisionShape3D
var _shape: CylinderShape3D
var _spawn: Transform3D
var _prev_pressed := {}
var _tr_points: Array[Vector3] = []
var _tr_time := 0.0
var _tr_duration := 0.0
var _tr_dir := Vector3.FORWARD
var _tr_exit_speed := 0.0
var _tr_blocked := 0
var _prev_hv := Vector3.ZERO
var _jump_impulse := false

const EDGE_ACTIONS := ["jump", "crouch", "crouch_toggle", "roll", "walk_toggle"]


func _ready() -> void:
	_rig = get_node_or_null(camera_rig_path)
	_collider = $CollisionShape3D
	_shape = (_collider.shape as CylinderShape3D).duplicate()
	_collider.shape = _shape
	_shape.radius = body_radius
	_set_collider_height(stand_height)
	floor_max_angle = deg_to_rad(max_slope_deg + slope_contact_tolerance_deg)
	floor_snap_length = max_step_height + 0.05
	floor_constant_speed = true
	floor_stop_on_slope = true
	floor_block_on_wall = true
	max_slides = 6
	_spawn = global_transform
	facing_yaw = rotation.y
	rotation = Vector3.ZERO


# ------------------------------------------------------------------ input ---
func _unhandled_input(event: InputEvent) -> void:
	# Event-based capture so sub-tick taps are never lost at low physics rates.
	if not input_enabled:
		return
	if event.is_action_pressed("jump"):
		jump_buffer = jump_buffer_time
	elif event.is_action_pressed("roll"):
		roll_buffer = jump_buffer_time
	elif event.is_action_pressed("reset_player"):
		respawn()


func _edge(action: String) -> bool:
	var now := input_enabled and Input.is_action_pressed(action)
	var was: bool = _prev_pressed.get(action, false)
	_prev_pressed[action] = now
	return now and not was


func _gather_input(dt: float) -> Dictionary:
	var raw := Vector2.ZERO
	if input_enabled:
		raw = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_input = raw
	var yaw := get_camera_yaw()
	var w := Basis(Vector3.UP, yaw) * Vector3(raw.x, 0.0, raw.y)
	wish_strength = clampf(w.length(), 0.0, 1.0)
	wish_dir = w.normalized() if wish_strength > 0.05 else Vector3.ZERO
	var e := {}
	for a in EDGE_ACTIONS:
		e[a] = _edge(a)
	if e["jump"]:
		jump_buffer = jump_buffer_time
	if e["roll"]:
		roll_buffer = jump_buffer_time
	if e["crouch"] or e["crouch_toggle"]:
		crouch_buffer = jump_buffer_time
	if e["walk_toggle"]:
		walk_toggled = not walk_toggled
	is_aiming = input_enabled and Input.is_action_pressed("aim")
	jump_buffer = maxf(jump_buffer - dt, 0.0)
	roll_buffer = maxf(roll_buffer - dt, 0.0)
	crouch_buffer = maxf(crouch_buffer - dt, 0.0)
	return e


func get_camera_yaw() -> float:
	if _rig and _rig.has_method("get_yaw"):
		return _rig.get_yaw()
	return 0.0


# ------------------------------------------------------------ main update ---
func _physics_process(dt: float) -> void:
	sim_time += dt
	var e := _gather_input(dt)
	slide_cooldown = maxf(slide_cooldown - dt, 0.0)
	slide_boost_timer = maxf(slide_boost_timer - dt, 0.0)
	roll_cooldown = maxf(roll_cooldown - dt, 0.0)
	landing_jump_block = maxf(landing_jump_block - dt, 0.0)
	if landing_recovery > 0.0:
		landing_recovery = maxf(landing_recovery - dt, 0.0)
		if landing_recovery == 0.0:
			landing_speed_scale = 1.0

	var v_old := velocity
	var v_new := velocity
	match state:
		State.GROUND:
			v_new = _tick_ground(dt, e)
		State.AIR:
			v_new = _tick_air(dt, e)
		State.SLIDE:
			v_new = _tick_slide(dt, e)
		State.ROLL:
			v_new = _tick_roll(dt, e)
		State.TRAVERSE:
			_tick_traverse(dt)
			_update_facing(dt)
			_prev_hv = Vector3(velocity.x, 0, velocity.z)
			return
	if state == State.TRAVERSE:   # a traverse started this tick
		_update_facing(dt)
		return
	# A jump/state switch may have replaced the velocity: integrate from v_old -> v_new.
	_integrate_and_move(dt, v_old, v_new)
	_update_facing(dt)
	var hv := Vector3(velocity.x, 0, velocity.z)
	accel_world = (hv - _prev_hv) / dt
	_prev_hv = hv
	if global_position.y < -30.0:
		respawn()


func _integrate_and_move(dt: float, v_old: Vector3, v_new: Vector3) -> void:
	# Midpoint (trapezoidal) integration: displacement uses the average of the
	# old and new velocity -> exact for piecewise-constant acceleration, so jump
	# apex and braking distances do not depend on the physics tick rate.
	var v_mid := (v_old + v_new) * 0.5
	if _jump_impulse:
		# Impulse applied at the start of the tick, then gravity for the rest of it.
		_jump_impulse = false
		v_mid.y = v_new.y - gravity_rise * dt * 0.5
		v_new.y -= gravity_rise * dt
	var pre_vy := v_new.y
	var grounded_move := state in [State.GROUND, State.SLIDE, State.ROLL] and is_on_floor()
	if grounded_move:
		var hm := Vector3(v_mid.x, 0, v_mid.z) * dt
		if hm.length() > 0.0005:
			var st := StepSolver.probe_step_up(self, hm, max_step_height, step_min_depth, floor_max_angle)
			if not st.is_empty():
				global_position.y += float(st["height"]) + 0.002
				step_count += 1
				stepped.emit(float(st["height"]))
				v_mid.y = 0.0
				v_new.y = 0.0
	velocity = v_mid
	move_and_slide()
	var v_final := v_new + (velocity - v_mid)   # keep collision clipping
	velocity = v_final
	# Push toward the speed the player is *trying* to move at (input), since the
	# post-collision velocity is clipped to ~0 against the prop.
	var intended := Vector3(v_mid.x, 0, v_mid.z)
	if state == State.GROUND and wish_dir != Vector3.ZERO:
		intended = wish_dir * _target_speed() * wish_strength
	_push_props(intended, dt)
	if is_on_floor():
		time_since_grounded = 0.0
		if state == State.AIR:
			_on_land(-pre_vy)
	else:
		var held := state == State.GROUND and velocity.y <= 0.0 and _ground_probe()
		if held:
			velocity.y = 0.0
		else:
			time_since_grounded += dt
		if state == State.GROUND and not held:
			_set_state(State.AIR)   # walked off a ledge (coyote time starts)
		elif state in [State.SLIDE, State.ROLL] and time_since_grounded > coyote_time:
			if state == State.SLIDE:
				slide_cooldown = slide_cooldown_time
			_restore_stance_after_low()
			_set_state(State.AIR)


## Fallback ground check when move_and_slide lost the floor while GROUND.
## A flat-bottom cylinder that overhangs a tread/ledge edge by millimetres gets
## an *edge* contact normal (not floor). This happens on step-up/step-down at
## high tick rates. Rules (no unconditional snapping):
##   - sweep down by max_step_height + 0.05;
##   - walkable hit  -> snap down onto it (stair step-down), stay GROUND;
##   - edge hit with ~zero travel at foot level -> resting on the edge, stay GROUND;
##   - nothing / steep surface further down -> AIR (real ledge, coyote applies).
func _ground_probe() -> bool:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = Vector3.DOWN * (max_step_height + 0.05)
	params.margin = safe_margin
	params.recovery_as_collision = true
	var res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(get_rid(), params, res):
		return false
	var n := res.get_collision_normal()
	var travel := res.get_travel()
	if n.angle_to(Vector3.UP) <= floor_max_angle + 0.01:
		global_position += travel
		return true
	var foot_dy := res.get_collision_point().y - global_position.y
	# Contact point at the soles and only a few cm of give: we are standing
	# on the edge. Keep the current height (do not sink into the edge).
	return travel.length() < 0.035 and foot_dy > -0.035 and foot_dy < 0.02


# ---------------------------------------------------------------- GROUND ---
func _tick_ground(dt: float, e: Dictionary) -> Vector3:
	var hv := Vector3(velocity.x, 0, velocity.z)
	if jump_buffer > 0.0 and _try_traverse(false):
		return velocity
	if jump_buffer > 0.0 and _can_jump():
		return _do_jump(hv)
	if roll_buffer > 0.0 and roll_cooldown <= 0.0 and landing_jump_block <= 0.0:
		return _start_roll(hv)
	if crouch_buffer > 0.0 and _slide_allowed(hv):
		return _start_slide(hv)
	_update_stance(e)
	_update_sprint(hv)
	var target := wish_dir * _target_speed()
	hv = _accelerate_ground(hv, target, dt)
	var vy := velocity.y - gravity_fall * dt
	return Vector3(hv.x, vy, hv.z)


func _accelerate_ground(v: Vector3, target: Vector3, dt: float) -> Vector3:
	var t_speed := target.length()
	if t_speed < 0.001:
		return v.move_toward(Vector3.ZERO, brake_decel * dt)
	var d := target / t_speed
	var v_par := v.dot(d)
	var v_perp := v - d * v_par
	# Lateral grip removes sideways momentum (gives curved, weighty turns).
	v_perp = v_perp.move_toward(Vector3.ZERO, turn_grip * dt)
	var budget := dt
	if v_par < 0.0:
		# Moving against the input: brake first with grip, then accelerate.
		var t_stop := -v_par / turn_grip
		if t_stop >= budget:
			v_par += turn_grip * budget
			budget = 0.0
		else:
			v_par = 0.0
			budget -= t_stop
	if budget > 0.0:
		if v_par > t_speed:
			v_par = move_toward(v_par, t_speed, overspeed_decel * budget)
		else:
			var knee := minf(jog_speed, t_speed)
			if v_par < knee:
				var t_knee := (knee - v_par) / ground_accel
				if t_knee >= budget:
					v_par += ground_accel * budget
					budget = 0.0
				else:
					v_par = knee
					budget -= t_knee
			if budget > 0.0 and v_par < t_speed:
				v_par = move_toward(v_par, t_speed, sprint_accel * budget)
	return d * v_par + v_perp


func _target_speed() -> float:
	if wish_dir == Vector3.ZERO:
		return 0.0
	var s := jog_speed
	if is_crouched:
		s = crouch_speed
	elif is_sprinting:
		s = sprint_speed
	elif walk_toggled:
		s = walk_speed
	if is_aiming:
		var fwd := _yaw_forward(get_camera_yaw())
		var c := wish_dir.dot(fwd)
		var dir_scale := strafe_factor
		if c >= 0.0:
			dir_scale = lerpf(strafe_factor, 1.0, c)
		else:
			dir_scale = lerpf(strafe_factor, backpedal_factor, -c)
		s = minf(s, aim_speed) * dir_scale
	s *= wish_strength
	# Uphill slows you down (effort), downhill does not speed you up on foot.
	if is_on_floor():
		var n := get_floor_normal()
		var slope := n.angle_to(Vector3.UP)
		if slope > 0.02:
			var downhill := Vector3(n.x, 0, n.z).normalized()
			var uphill_amount := clampf(-wish_dir.dot(downhill), 0.0, 1.0)
			var steep := clampf(slope / deg_to_rad(max_slope_deg), 0.0, 1.0)
			s *= lerpf(1.0, uphill_speed_factor, steep * uphill_amount)
	if landing_recovery > 0.0:
		s *= landing_speed_scale
	return s


func _update_sprint(hv: Vector3) -> void:
	var want := input_enabled and Input.is_action_pressed("sprint") and wish_dir != Vector3.ZERO
	if want and is_crouched:
		if _can_stand():
			crouch_toggled = false
			_set_crouched(false)
		else:
			want = false
	if want and is_aiming:
		want = false
	if want and landing_recovery > 0.0 and last_land_severity >= 2:
		want = false
	# Sprinting requires running roughly where the body faces (no sideways sprint).
	if want and hv.length() > 1.0 and hv.normalized().dot(wish_dir) < 0.0:
		want = false
	is_sprinting = want


func _update_stance(e: Dictionary) -> void:
	if e.get("crouch_toggle", false):
		crouch_toggled = not crouch_toggled
	var want := crouch_toggled or (input_enabled and Input.is_action_pressed("crouch"))
	if want and not is_crouched:
		_set_crouched(true)
	elif want and current_height < crouch_height - 0.01 and _fits_height(crouch_height):
		_set_crouched(true)
	elif not want and is_crouched and _can_stand():
		_set_crouched(false)
	elif not want and current_height < crouch_height - 0.01 and _fits_height(crouch_height):
		_set_crouched(true)
	crouch_buffer = 0.0


# ------------------------------------------------------------------- AIR ---
func _tick_air(dt: float, _e: Dictionary) -> Vector3:
	var hv := Vector3(velocity.x, 0, velocity.z)
	if jump_buffer > 0.0 and _can_jump():
		return _do_jump(hv)    # coyote jump
	if jump_buffer > 0.0 and velocity.y < 2.0 and _try_traverse(true):
		return velocity
	var g := gravity_fall
	if velocity.y > 0.0:
		g = gravity_rise
		if jump_rising and not (input_enabled and Input.is_action_pressed("jump")):
			g = gravity_rise * jump_cut_multiplier
	if velocity.y <= 0.0:
		jump_rising = false
	var vy := maxf(velocity.y - g * dt, -terminal_speed)
	if wish_dir != Vector3.ZERO:
		# Air steering: re-directs momentum but cannot create speed beyond the
		# take-off speed (or a small floor for standing jumps), and the part of
		# the change that opposes current momentum is capped at air_brake
		# (you cannot "stop" in mid-air - nothing to push against).
		var cap := maxf(hv.length(), air_min_control_speed)
		var dv := (wish_dir * cap * wish_strength - hv).limit_length(air_accel * dt)
		var sp := hv.length()
		if sp > 0.05:
			var dir := hv / sp
			var along := dv.dot(dir)
			if along < -air_brake * dt:
				dv -= dir * (along + air_brake * dt)
		var nv := hv + dv
		if nv.length() > cap:
			nv = nv.normalized() * cap
		hv = nv
	return Vector3(hv.x, vy, hv.z)


func _can_jump() -> bool:
	if landing_jump_block > 0.0:
		return false
	var grounded := state in [State.GROUND, State.SLIDE] or (state == State.ROLL and roll_time / roll_duration >= roll_jump_cancel)
	var coyote := state == State.AIR and not jumped_this_air and time_since_grounded <= coyote_time
	if not (grounded or coyote):
		return false
	if current_height < stand_height - 0.01 and not _can_stand():
		return false
	return true


func _do_jump(hv: Vector3) -> Vector3:
	var kind := "jump"
	if state == State.AIR:
		kind = "coyote"
	elif state == State.SLIDE:
		kind = "slide_jump"
		slide_cooldown = slide_cooldown_time
		hv *= 0.92
	elif state == State.ROLL:
		kind = "roll_jump"
		roll_cooldown = roll_cooldown_time
	if current_height < stand_height - 0.01:
		crouch_toggled = false
		_set_crouched(false)
	jump_buffer = 0.0
	jumped_this_air = true
	jump_rising = true
	_set_state(State.AIR)
	jumped.emit(kind)
	_jump_impulse = true
	return Vector3(hv.x, sqrt(2.0 * gravity_rise * jump_height), hv.z)


func _on_land(impact: float) -> void:
	last_impact = impact
	jumped_this_air = false
	jump_rising = false
	var sev := 0
	if impact >= land_hard_speed:
		sev = 2
	elif impact >= land_medium_speed:
		sev = 1
	var hv := Vector3(velocity.x, 0, velocity.z)
	last_land_severity = sev
	if sev >= 1 and roll_buffer > 0.0 and roll_cooldown <= 0.0:
		# Landing roll converts the impact into forward motion: no penalty.
		_set_state(State.GROUND)
		landed.emit(impact, 0)
		var rv := _start_roll(hv)
		velocity = Vector3(rv.x, 0, rv.z)
		return
	if sev == 1:
		hv *= land_medium_keep
		landing_recovery = land_medium_recovery
		landing_speed_scale = 0.65
	elif sev == 2:
		hv *= land_hard_keep
		landing_recovery = land_hard_recovery
		landing_speed_scale = 0.35
		landing_jump_block = land_hard_jump_block
		is_sprinting = false
	velocity = Vector3(hv.x, minf(velocity.y, 0.0), hv.z)
	_set_state(State.GROUND)
	landed.emit(impact, sev)
	if sev < 2 and crouch_buffer > 0.0 and _slide_allowed(hv):
		velocity = _start_slide(hv)


# ----------------------------------------------------------------- SLIDE ---
func _slide_allowed(hv: Vector3) -> bool:
	return slide_cooldown <= 0.0 and hv.length() >= slide_min_speed and is_on_floor() \
		and not (landing_recovery > 0.0 and last_land_severity >= 2)


func _start_slide(hv: Vector3) -> Vector3:
	crouch_buffer = 0.0
	var speed := hv.length()
	if slide_boost_timer <= 0.0:
		speed = minf(speed + slide_boost, maxf(slide_max_entry, speed))
	slide_boost_timer = slide_boost_cooldown
	slide_time = 0.0
	is_sprinting = false
	_set_collider_height(low_height)
	_set_state(State.SLIDE)
	var d := hv.normalized()
	return Vector3(d.x * speed, velocity.y, d.z * speed)


func _tick_slide(dt: float, e: Dictionary) -> Vector3:
	slide_time += dt
	var hv := Vector3(velocity.x, 0, velocity.z)
	if jump_buffer > 0.0 and _can_jump():
		return _do_jump(hv)
	var cancel: bool = e.get("crouch", false) or e.get("crouch_toggle", false)
	var downhill_acc := Vector3.ZERO
	if is_on_floor():
		var n := get_floor_normal()
		var along := Vector3.DOWN - n * n.dot(Vector3.DOWN)   # |along| = sin(slope)
		downhill_acc = Vector3(along.x, 0, along.z) * 9.81 * slide_gravity_scale
	hv += downhill_acc * dt
	hv = hv.move_toward(Vector3.ZERO, slide_friction * dt)
	if wish_dir != Vector3.ZERO and hv.length() > 0.1:
		var cur_yaw := atan2(-hv.x, -hv.z)
		var tgt_yaw := atan2(-wish_dir.x, -wish_dir.z)
		var ny := rotate_toward(cur_yaw, tgt_yaw, deg_to_rad(slide_steer_rate) * dt)
		hv = _yaw_forward(ny) * hv.length()
	if hv.length() > slide_max_speed:
		hv = hv.normalized() * slide_max_speed
	var accelerating := downhill_acc.length() > slide_friction * 0.9
	var too_long := slide_time >= slide_max_time and not accelerating
	if cancel or hv.length() < slide_exit_speed or too_long:
		_end_slide(cancel)
	return Vector3(hv.x, velocity.y - gravity_fall * dt, hv.z)


func _end_slide(force_crouch: bool) -> void:
	slide_cooldown = slide_cooldown_time
	if force_crouch:
		crouch_toggled = true
	_restore_stance_after_low()
	_set_state(State.GROUND)


# ------------------------------------------------------------------ ROLL ---
func _start_roll(hv: Vector3) -> Vector3:
	roll_buffer = 0.0
	jump_buffer = 0.0
	roll_dir = wish_dir if wish_dir != Vector3.ZERO else _yaw_forward(facing_yaw)
	roll_time = 0.0
	roll_start_speed = clampf(maxf(roll_speed_start, hv.length() * 0.85), 0.0, roll_speed_max)
	is_sprinting = false
	landing_recovery = 0.0
	landing_speed_scale = 1.0
	_set_collider_height(low_height)
	_set_state(State.ROLL)
	return Vector3(hv.x, velocity.y, hv.z)


func _tick_roll(dt: float, _e: Dictionary) -> Vector3:
	roll_time += dt
	var hv := Vector3(velocity.x, 0, velocity.z)
	if jump_buffer > 0.0 and _can_jump():
		return _do_jump(hv)
	var u := clampf(roll_time / roll_duration, 0.0, 1.0)
	if wish_dir != Vector3.ZERO:
		var ry := rotate_toward(atan2(-roll_dir.x, -roll_dir.z), atan2(-wish_dir.x, -wish_dir.z), deg_to_rad(roll_steer_rate) * dt)
		roll_dir = _yaw_forward(ry)
	var speed := lerpf(roll_start_speed, roll_speed_end, smoothstep(0.0, 1.0, u))
	hv = hv.move_toward(roll_dir * speed, roll_push_accel * dt)
	if u >= 1.0:
		roll_cooldown = roll_cooldown_time
		_restore_stance_after_low()
		_set_state(State.GROUND)
	return Vector3(hv.x, velocity.y - gravity_fall * dt, hv.z)


# ------------------------------------------------------- VAULT / MANTLE ---
func _try_traverse(in_air: bool) -> bool:
	var hv := Vector3(velocity.x, 0, velocity.z)
	var f := wish_dir
	if f == Vector3.ZERO:
		return false
	var rid := get_rid()
	var params := PhysicsTestMotionParameters3D.new()
	params.margin = safe_margin
	var res := PhysicsTestMotionResult3D.new()
	var xf := global_transform
	params.from = xf
	# Detection reach grows with speed: a running player commits earlier.
	params.motion = f * (traverse_reach + minf(hv.length() * 0.1, 0.6))
	if not PhysicsServer3D.body_test_motion(rid, params, res):
		return false
	var n := res.get_collision_normal()
	if absf(n.y) > 0.3 or res.get_collider() is RigidBody3D:
		return false
	var wall_dir := Vector3(-n.x, 0, -n.z).normalized()
	if wall_dir.dot(f) < 0.5:
		return false
	var wall_dist := res.get_travel().length()
	var feet := xf.origin
	var space := get_world_3d().direct_space_state
	var probe_xz := feet + wall_dir * (wall_dist + body_radius + 0.25)
	var top_limit := air_mantle_reach if in_air else mantle_max_height
	var q := PhysicsRayQueryParameters3D.create(probe_xz + Vector3.UP * (top_limit + 0.35), probe_xz + Vector3.UP * (max_step_height * 0.5))
	q.exclude = [rid]
	q.collision_mask = collision_mask
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.8:
		return false
	var top_y: float = (hit["position"] as Vector3).y
	var h := top_y - feet.y
	if h <= max_step_height + 0.03 or h > top_limit:
		return false
	# Lift path must be clear (head-room above us).
	params.from = xf
	params.motion = Vector3.UP * (h + 0.06)
	if PhysicsServer3D.body_test_motion(rid, params, res) and res.get_travel().y < h + 0.04:
		return false
	var raised := xf.translated(Vector3.UP * (h + 0.06))
	# Phase-1 end point: at the wall face, on top of the obstacle height.
	var approach := maxf(wall_dist - 0.02, 0.0)
	var p1 := raised.origin + wall_dir * approach
	# Vault: thin obstacle with open space and lower ground beyond.
	if not in_air and h <= vault_max_height and hv.length() >= 1.5:
		var beyond := feet + wall_dir * (wall_dist + vault_max_thickness + body_radius * 2.0 + 0.1)
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(beyond.x, top_y + 0.3, beyond.z), Vector3(beyond.x, top_y - 0.35, beyond.z))
		q2.exclude = [rid]
		q2.collision_mask = collision_mask
		var below := space.intersect_ray(q2)
		if below.is_empty():
			var over := Vector3(beyond.x, top_y + 0.06, beyond.z) - raised.origin
			params.from = raised
			params.motion = over
			if not PhysicsServer3D.body_test_motion(rid, params, res):
				_start_traverse(Traverse.VAULT, [p1, raised.origin + over], wall_dir,
					maxf(hv.length() * 0.9, vault_exit_speed), 0.40 + 0.12 * h + approach / maxf(hv.length(), 2.0))
				return true
	# Mantle: stand on top.
	var target := Vector3(feet.x, top_y + 0.06, feet.z) + wall_dir * (wall_dist + body_radius + 0.15)
	params.from = raised
	params.motion = target - raised.origin
	if PhysicsServer3D.body_test_motion(rid, params, res):
		return false
	_start_traverse(Traverse.MANTLE, [p1, target], wall_dir, mantle_exit_speed, 0.35 + 0.25 * h + approach / maxf(hv.length(), 2.0))
	return true


func _start_traverse(kind: int, pts: Array, dir: Vector3, exit_speed: float, duration: float) -> void:
	traverse_kind = kind
	_tr_points = [global_position, pts[0], pts[1]]
	_tr_time = 0.0
	_tr_duration = duration
	_tr_dir = dir
	_tr_exit_speed = exit_speed
	_tr_blocked = 0
	jump_buffer = 0.0
	is_sprinting = false
	_set_state(State.TRAVERSE)


func _tick_traverse(dt: float) -> void:
	_tr_time += dt
	var u := clampf(_tr_time / _tr_duration, 0.0, 1.0)
	var rise_frac := 0.55   # phase 1: rise while closing on the wall face
	var p: Vector3
	if u < rise_frac:
		var a := u / rise_frac
		# Height: smoothstep (starts and ends with zero vertical speed, peak
		# 1.5*h/t_rise, no instant upward pop). Approach: ease-in a^2, which
		# stays below the smoothstep, so the feet are above the top edge
		# (relatively) before the body reaches the wall face.
		var y := lerpf(_tr_points[0].y, _tr_points[1].y, a * a * (3.0 - 2.0 * a))
		var xz := _tr_points[0].lerp(_tr_points[1], a * a)
		p = Vector3(xz.x, y, xz.z)
	else:
		var b := (u - rise_frac) / (1.0 - rise_frac)
		p = _tr_points[1].lerp(_tr_points[2], b * b * (3.0 - 2.0 * b))
	var before := global_position
	var col := move_and_collide(p - global_position)
	if col:
		var rem := col.get_remainder()
		move_and_collide(rem.slide(col.get_normal()))
		if rem.length() > 0.02:
			_tr_blocked += 1
	velocity = (global_position - before) / dt
	if _tr_blocked > 4:
		_finish_traverse(true)
	elif u >= 1.0:
		_finish_traverse(false)


func _finish_traverse(aborted: bool) -> void:
	var kind := traverse_kind
	traverse_kind = Traverse.NONE
	time_since_grounded = 0.0
	jumped_this_air = true   # no coyote jump out of a traverse
	if aborted:
		velocity = Vector3(0, 0, 0)
		_set_state(State.AIR)
		return
	if kind == Traverse.VAULT:
		velocity = _tr_dir * _tr_exit_speed
		_set_state(State.AIR)
	else:
		velocity = _tr_dir * _tr_exit_speed
		apply_floor_snap()
		_set_state(State.GROUND if is_on_floor() else State.AIR)
		jumped_this_air = false


# ---------------------------------------------------------------- facing ---
func _update_facing(dt: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	var target_dir := Vector3.ZERO
	var rate := lerpf(turn_rate_slow, turn_rate_fast, clampf(hv.length() / sprint_speed, 0.0, 1.0))
	match state:
		State.SLIDE:
			target_dir = hv
		State.ROLL:
			target_dir = roll_dir
			rate = 1080.0
		State.TRAVERSE:
			target_dir = _tr_dir
			rate = 720.0
		State.AIR:
			target_dir = wish_dir if wish_dir != Vector3.ZERO else Vector3.ZERO
			rate = turn_rate_air
		_:
			target_dir = wish_dir
	if is_aiming and state in [State.GROUND, State.AIR]:
		facing_yaw = rotate_toward(facing_yaw, get_camera_yaw(), deg_to_rad(turn_rate_slow) * dt)
		return
	if target_dir.length() > 0.05:
		var ty := atan2(-target_dir.x, -target_dir.z)
		facing_yaw = wrapf(rotate_toward(facing_yaw, ty, deg_to_rad(rate) * dt), -PI, PI)


# --------------------------------------------------------------- helpers ---
static func _yaw_forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func get_facing_forward() -> Vector3:
	return _yaw_forward(facing_yaw)


func _set_state(s: int) -> void:
	if s == state:
		return
	var old := state
	state = s
	state_changed.emit(old, s)


func _set_collider_height(h: float) -> void:
	current_height = h
	_shape.height = h
	_collider.position = Vector3(0, h * 0.5, 0)


func _set_crouched(c: bool) -> void:
	is_crouched = c
	_set_collider_height(crouch_height if c else stand_height)


func _fits_height(h: float) -> bool:
	## True if the collider could grow from its current height to h here.
	var dh := h - current_height
	if dh <= 0.001:
		return true
	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = Vector3.UP * dh
	params.margin = safe_margin
	var res := PhysicsTestMotionResult3D.new()
	return not PhysicsServer3D.body_test_motion(get_rid(), params, res)


func _can_stand() -> bool:
	return _fits_height(stand_height)


func _restore_stance_after_low() -> void:
	var want_crouch := crouch_toggled or (input_enabled and Input.is_action_pressed("crouch"))
	if not want_crouch and _fits_height(stand_height):
		_set_crouched(false)
	elif _fits_height(crouch_height):
		_set_crouched(true)
	else:
		is_crouched = true   # stay at low height until there is room


func _push_props(intended_hv: Vector3, dt: float) -> void:
	# Force-limited push: a person can exert ~push_force_max on an object.
	# The force drives the prop toward our *intended* speed (the clipped
	# velocity after the collision would be ~0 and stop pushing). Light crates
	# follow at walking pace, heavy ones (static friction > max force) resist.
	var contacts: Array[KinematicCollision3D] = []
	for i in get_slide_collision_count():
		contacts.append(get_slide_collision(i))
	# Resting against a prop the per-tick motion can be below the safe margin
	# and move_and_slide reports no contact (rate dependent) -> probe ahead.
	var ih := intended_hv.length()
	if ih > 0.1:
		var probe := KinematicCollision3D.new()
		if test_move(global_transform, intended_hv / ih * 0.04, probe, 0.001, true, 1):
			contacts.append(probe)
	var done := {}
	for c in contacts:
		var rb := c.get_collider() as RigidBody3D
		if rb == null or done.has(rb):
			continue
		done[rb] = true
		var push_dir := -c.get_normal()
		push_dir.y = 0.0
		if push_dir.length() < 0.1:
			continue
		push_dir = push_dir.normalized()
		var v_rel := intended_hv.dot(push_dir) - rb.linear_velocity.dot(push_dir)
		if v_rel <= 0.0:
			continue
		var force := minf(v_rel * rb.mass / dt * 0.5, push_force_max)
		var at := c.get_position() - rb.global_position
		at.y = 0.0   # push at centre height: slide rather than tip
		rb.apply_impulse(push_dir * force * dt, at)


func respawn() -> void:
	global_transform = Transform3D(Basis.IDENTITY, _spawn.origin)
	velocity = Vector3.ZERO
	_prev_hv = Vector3.ZERO
	_set_crouched(false)
	crouch_toggled = false
	_set_state(State.GROUND)


func teleport(pos: Vector3, yaw: float) -> void:
	## Test/debug helper: place the character and reset transient state.
	global_position = pos
	velocity = Vector3.ZERO
	_prev_hv = Vector3.ZERO
	facing_yaw = yaw
	jump_buffer = 0.0
	roll_buffer = 0.0
	crouch_buffer = 0.0
	landing_recovery = 0.0
	landing_speed_scale = 1.0
	landing_jump_block = 0.0
	slide_cooldown = 0.0
	roll_cooldown = 0.0
	slide_boost_timer = 0.0
	crouch_toggled = false
	walk_toggled = false
	_set_crouched(false)
	_set_state(State.AIR)
	jumped_this_air = true
	if _rig and _rig.has_method("snap_to_target"):
		_rig.snap_to_target(yaw)


func get_state_name() -> String:
	if state == State.TRAVERSE:
		return "VAULT" if traverse_kind == Traverse.VAULT else "MANTLE"
	return STATE_NAMES[state]


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_debug_info() -> Dictionary:
	return {
		"state": get_state_name(),
		"speed": get_horizontal_speed(),
		"vy": velocity.y,
		"on_floor": is_on_floor(),
		"floor_deg": rad_to_deg(get_floor_angle()) if is_on_floor() else -1.0,
		"crouched": is_crouched,
		"sprint": is_sprinting,
		"aim": is_aiming,
		"walk": walk_toggled,
		"steps": step_count,
		"impact": last_impact,
		"height": current_height,
	}
