class_name CameraRig
extends Node3D
## Over-the-shoulder third-person camera rig.
## Runs in _process on the *interpolated* character transform (physics
## interpolation is enabled project-wide; this node opts out of it), so the view
## is smooth at any render rate regardless of the physics tick.

@export var target_path: NodePath

@export_group("Look")
@export var mouse_sensitivity := 0.0022   ## rad per pixel (raw, no smoothing)
@export var invert_y := false
@export var pitch_min_deg := -75.0
@export var pitch_max_deg := 55.0
@export var gamepad_look_speed := 3.0     ## rad/s at full stick

@export_group("Framing")
@export var distance := 3.6
@export var zoom_min := 1.8
@export var zoom_max := 6.0
@export var zoom_step := 0.4
@export var zoom_smooth := 10.0
@export var shoulder_offset := 0.55       ## m to the right of the character
@export var height_stand := 1.55
@export var height_crouch := 1.15
@export var height_low := 0.9
@export var height_smooth := 8.0

@export_group("Follow")
## Vertical follow rate (1/s) while grounded / airborne. Horizontal follow is rigid.
@export var follow_v_ground := 14.0
@export var follow_v_air := 4.0
@export var max_v_lag := 0.6

@export_group("Collision")
@export var collision_radius := 0.22
@export_flags_3d_physics var collision_mask := 1
@export var pull_out_rate := 5.0           ## ease-out after an obstruction clears (1/s)
## Below this boom length the character model is hidden (camera is inside it).
@export var min_distance := 0.35

@export_group("FOV")
@export var fov_base := 72.0
@export var fov_sprint_add := 6.0
@export var fov_slide_add := 4.0
@export var fov_rate := 4.0

@export_group("Landing dip")
@export var dip_impulse_per_mps := 0.3
@export var dip_impulse_max := 3.0
@export var dip_stiffness := 120.0

var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var _target: Node3D
var _cam: Camera3D
var _zoom := 3.6
var _zoom_target := 3.6
var _cur_dist := 3.6
var _height := 1.55
var _fy := 0.0
var _dip := 0.0
var _dip_v := 0.0
var _initialized := false
var _sphere := SphereShape3D.new()
var last_obstructed := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam = $Camera3D
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node_or_null(target_path)
	_zoom = distance
	_zoom_target = distance
	_cur_dist = distance
	_sphere.radius = collision_radius
	if _target and _target.has_signal("landed"):
		_target.landed.connect(_on_landed)
	if not DisplayServer.get_name() == "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_yaw() -> float:
	return yaw


func get_camera() -> Camera3D:
	return _cam


func snap_to_target(new_yaw: float) -> void:
	yaw = new_yaw
	_initialized = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		var dy: float = event.relative.y * mouse_sensitivity
		pitch -= -dy if invert_y else dy
		pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - zoom_step, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + zoom_step, zoom_min, zoom_max)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func add_look(d_yaw: float, d_pitch: float) -> void:
	## For scripted showcase / tests.
	yaw += d_yaw
	pitch = clampf(pitch + d_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func _on_landed(impact: float, _sev: int) -> void:
	_dip_v -= minf(impact * dip_impulse_per_mps, dip_impulse_max)


func _process(dt: float) -> void:
	update_rig(dt)


func update_rig(dt: float) -> void:
	if _target == null:
		return
	# Gamepad / keyboard look (optional actions).
	var look := Vector2.ZERO
	if InputMap.has_action("look_left"):
		look = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= look.x * gamepad_look_speed * dt
	pitch = clampf(pitch - look.y * gamepad_look_speed * dt * (-1.0 if invert_y else 1.0), deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

	var tp := _target.get_global_transform_interpolated().origin
	var want_h := height_stand
	var on_floor := true
	if _target is PlayerController:
		var pc := _target as PlayerController
		on_floor = pc.is_on_floor() or pc.state != PlayerController.State.AIR
		if pc.current_height < pc.stand_height - 0.01:
			want_h = height_crouch if pc.current_height >= pc.crouch_height - 0.01 else height_low
		var fov_t := fov_base
		if pc.state == PlayerController.State.SLIDE:
			fov_t += fov_slide_add
		elif pc.is_sprinting and pc.get_horizontal_speed() > pc.jog_speed + 0.5:
			fov_t += fov_sprint_add
		_cam.fov = lerpf(_cam.fov, fov_t, 1.0 - exp(-fov_rate * dt))
	if not _initialized:
		_fy = tp.y
		_height = want_h
		_cam.fov = fov_base
		_initialized = true
	_height = lerpf(_height, want_h, 1.0 - exp(-height_smooth * dt))
	var rate := follow_v_ground if on_floor else follow_v_air
	_fy = lerpf(_fy, tp.y, 1.0 - exp(-rate * dt))
	_fy = clampf(_fy, tp.y - max_v_lag, tp.y + max_v_lag)
	# Landing dip: critically damped spring.
	var damping := 2.0 * sqrt(dip_stiffness)
	_dip_v += (-dip_stiffness * _dip - damping * _dip_v) * dt
	_dip += _dip_v * dt
	_dip = clampf(_dip, -0.2, 0.2)

	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-zoom_smooth * dt))
	var pivot := Vector3(tp.x, _fy + _height + _dip, tp.z)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pivot)

	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _target is CollisionObject3D:
		exclude.append((_target as CollisionObject3D).get_rid())
	# Shoulder offset clamped by walls on the right.
	var right := basis.x
	var sh := shoulder_offset
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.collision_mask = collision_mask
	q.exclude = exclude
	q.transform = Transform3D(Basis.IDENTITY, pivot)
	q.motion = right * shoulder_offset
	var r := space.cast_motion(q)
	if r.size() == 2 and r[0] < 1.0:
		sh = shoulder_offset * r[0]
	var shoulder_pt := pivot + right * sh
	# Boom collision.
	var back := basis.z
	q.transform = Transform3D(Basis.IDENTITY, shoulder_pt)
	q.motion = back * _zoom
	r = space.cast_motion(q)
	var allowed := _zoom
	if r.size() == 2 and r[0] < 1.0:
		# Never clamp outward past the hit: a minimum distance here would push
		# the lens back into the wall. Very close = over-the-shoulder/head view.
		allowed = _zoom * r[0]
	last_obstructed = allowed < _zoom - 0.01
	if allowed < _cur_dist:
		_cur_dist = allowed                       # snap in: never show through walls
	else:
		_cur_dist = lerpf(_cur_dist, allowed, 1.0 - exp(-pull_out_rate * dt))
	_cam.global_transform = Transform3D(basis, shoulder_pt + back * _cur_dist)
	var model := _target.get_node_or_null("Model") as Node3D
	if model:
		model.visible = _cur_dist >= min_distance
