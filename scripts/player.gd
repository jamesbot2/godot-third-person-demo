extends CharacterBody3D
## Third-person character controller.
## WASD / arrows: move (relative to camera) · Shift: sprint · Space: jump
## Mouse: orbit camera · Wheel: zoom · Esc: release mouse · Click: recapture · R: respawn

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 6.5
@export var acceleration: float = 14.0
@export var air_acceleration: float = 4.0
@export var rotation_speed: float = 12.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = deg_to_rad(-70.0)
@export var max_pitch: float = deg_to_rad(30.0)
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0
@export var push_force: float = 3.0
@export var fall_limit: float = -25.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn_position: Vector3

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var model: Node3D = $Model


func _ready() -> void:
	_spawn_position = global_position
	# The pivot follows the player position but not its rotation.
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position + Vector3(0, 1.5, 0)
	spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = clampf(spring_arm.spring_length - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = clampf(spring_arm.spring_length + 0.5, min_zoom, max_zoom)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
	elif event.is_action_pressed("reset_player"):
		_respawn()


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Movement relative to the camera yaw
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var direction := cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var target := direction * speed
	velocity.x = lerpf(velocity.x, target.x, clampf(accel * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target.z, clampf(accel * delta, 0.0, 1.0))

	# Smoothly rotate the visual model toward the move direction (model faces -Z)
	if direction.length_squared() > 0.001:
		var target_yaw := atan2(-direction.x, -direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf(rotation_speed * delta, 0.0, 1.0))

	move_and_slide()

	# Push rigid bodies we bump into
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is RigidBody3D:
			body.apply_central_impulse(-col.get_normal() * push_force * delta * 10.0)

	if global_position.y < fall_limit:
		_respawn()


func _process(delta: float) -> void:
	# Camera follows smoothly
	var follow_target := global_position + Vector3(0, 1.5, 0)
	camera_pivot.global_position = camera_pivot.global_position.lerp(follow_target, clampf(15.0 * delta, 0.0, 1.0))


func _respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
