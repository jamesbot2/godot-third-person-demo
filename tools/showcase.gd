extends SceneTree
## Scripted visual showcase (autopilot) for visual acceptance.
## Must run NON-headless (needs a renderer), e.g.:
##   DISPLAY=:7 godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##       --write-movie /workspace/acceptance/showcase.avi -s res://tools/showcase.gd -- --shots=/workspace/acceptance
## Drives the real input actions (Input.action_press with analog strength),
## so the controller runs exactly as with a keyboard/gamepad. Screenshots are
## real framebuffer captures (Viewport texture -> PNG).

const L := preload("res://scripts/level/course_layout.gd")
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint",
	"crouch", "crouch_toggle", "roll", "walk_toggle", "aim"]
var main: Node
var pc: PlayerController
var rig: CameraRig
var shots_dir := "/workspace/acceptance"
var move_world := Vector3.ZERO   # desired world-space move direction (re-mapped every frame)
var orbit_rate := 0.0            # camera yaw rad/s
var shot_n := 0
var _last_state := ""
var log_lines: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	pc = main.get_node("Player")
	rig = pc.get_node("CameraRig")
	_run.call_deferred()


func _apply_move() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
	if move_world == Vector3.ZERO:
		return
	# camera-relative input that produces the requested world direction
	var local := Basis(Vector3.UP, -rig.get_yaw()) * move_world.normalized()
	var m := maxf(absf(local.x), absf(local.z))
	local /= m   # push the stick to the rim (deadzone remap keeps direction)
	if local.x > 0.01: Input.action_press("move_right", local.x)
	if local.x < -0.01: Input.action_press("move_left", -local.x)
	if local.z > 0.01: Input.action_press("move_back", local.z)
	if local.z < -0.01: Input.action_press("move_forward", -local.z)


func frames(sec: float) -> void:
	for i in maxi(1, int(round(sec * 30.0))):
		if orbit_rate != 0.0:
			rig.add_look(orbit_rate / 30.0, 0.0)
		_apply_move()
		await process_frame
		var st := pc.get_state_name()
		if st != _last_state:
			var line := "STATE|%s->%s|pos=%s" % [_last_state, st, pc.global_position]
			print(line)
			log_lines.append(line)
			_last_state = st


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	shot_n += 1
	var img := root.get_texture().get_image()
	var path := "%s/%02d_%s.png" % [shots_dir, shot_n, name]
	img.save_png(path)
	var line := "SHOT|%s|state=%s pos=%s hspeed=%.2f vy=%.2f cam_dist=%.2f fov=%.1f" % [path, pc.get_state_name(),
		pc.global_position, pc.get_horizontal_speed(), pc.velocity.y, rig._cur_dist, rig.get_camera().fov]
	print(line)
	log_lines.append(line)


func release_all() -> void:
	move_world = Vector3.ZERO
	orbit_rate = 0.0
	for a in ACTIONS:
		Input.action_release(a)


func place(pos: Vector3, yaw: float, cam_yaw_offset := 0.0) -> void:
	release_all()
	await process_frame
	pc.teleport(pos, yaw)
	rig.yaw = yaw + cam_yaw_offset
	await frames(0.5)


func seg(title: String) -> void:
	print("SEGMENT|%s|t=%.2f" % [title, Time.get_ticks_msec() / 1000.0])


func wait_state(sname: String, timeout: float) -> bool:
	for i in int(timeout * 30.0):
		if pc.get_state_name() == sname:
			return true
		await frames(1.0 / 30.0)
	return false


func _run() -> void:
	var fwd := Vector3(0, 0, -1)
	# 1. walk -> jog -> sprint -> stop on the flat track (3/4 rear camera)
	seg("walk_jog_sprint_stop")
	await place(Vector3(0, 0.02, 6), 0.0, 0.5)
	Input.action_press("walk_toggle"); await process_frame; Input.action_release("walk_toggle")
	move_world = fwd
	await frames(1.2); await shot("walk")
	Input.action_press("walk_toggle"); await process_frame; Input.action_release("walk_toggle")
	await frames(1.0); await shot("jog")
	Input.action_press("sprint")
	await frames(1.4); await shot("sprint_fov")
	Input.action_release("sprint")
	move_world = Vector3.ZERO
	await frames(0.15); await shot("braking")
	await frames(0.8)

	# 2. stairs 0.18 m risers up, no jump (side-ish camera)
	seg("stairs_up_no_jump")
	await place(Vector3(L.STAIR_X, 0.02, L.STAIR_Z0 + 2.0), 0.0, 0.9)
	move_world = fwd
	await frames(1.1); await shot("stairs_mid")
	await frames(1.2); await shot("stairs_top")
	await frames(1.6); await shot("stairs_down")
	release_all(); await frames(0.4)

	# 3. single steps 0.35 ok / 0.50 blocked
	seg("steps_035_ok_050_blocked")
	await place(Vector3(L.step_lane_x(2), 0.02, -3.5), 0.0, 1.0)
	move_world = fwd
	await frames(0.55); await shot("step_035_up")
	await frames(0.6)
	release_all()
	await place(Vector3(L.step_lane_x(4), 0.02, -3.5), 0.0, 1.0)
	move_world = fwd
	await frames(1.0); await shot("step_050_blocked")
	release_all(); await frames(0.3)

	# 4. ramps: 30 deg up, 50 deg rejected
	seg("ramp_30_up_50_rejected")
	await place(Vector3(L.ramp_x(2), 0.02, L.RAMP_Z0 + 2.0), 0.0, 1.1)
	move_world = fwd
	await frames(1.2); await shot("ramp_30")
	await frames(1.0)
	release_all()
	await place(Vector3(L.ramp_x(4), 0.02, L.RAMP_Z0 + 2.0), 0.0, 1.1)
	move_world = fwd
	await frames(1.3); await shot("ramp_50_rejected")
	release_all(); await frames(0.3)

	# 5. running jump + landing
	seg("jump_and_land")
	await place(Vector3(4, 0.02, 6), 0.0, 1.4)
	move_world = fwd
	await frames(0.8)
	Input.action_press("jump")
	await frames(0.3); await shot("jump_apex")
	Input.action_release("jump")
	await frames(0.6); await shot("landing")
	release_all(); await frames(0.5)

	# 6. sprint -> slide
	seg("slide")
	await place(Vector3(-4, 0.02, 6), 0.0, 1.3)
	move_world = fwd
	Input.action_press("sprint")
	await frames(1.2)
	Input.action_press("crouch")
	await frames(0.35); await shot("slide")
	await frames(0.9)
	release_all(); await frames(0.6)

	# 7. roll
	seg("roll")
	await place(Vector3(-8, 0.02, 6), 0.0, 1.3)
	move_world = fwd
	await frames(0.8)
	Input.action_press("roll"); await process_frame; Input.action_release("roll")
	await frames(0.25); await shot("roll")
	await frames(0.8)
	release_all(); await frames(0.4)

	# 8. vault 0.9 m wall
	seg("vault")
	await place(Vector3(L.VAULT_X, 0.02, L.VAULT_Z + 4.0), 0.0, 1.2)
	move_world = fwd
	for i in 60:
		if pc.global_position.z <= L.VAULT_Z + 1.0:
			break
		await frames(1.0 / 30.0)
	Input.action_press("jump")
	await wait_state("VAULT", 1.0)
	await frames(0.12); await shot("vault")
	Input.action_release("jump")
	await frames(0.9); await shot("vault_after")
	release_all(); await frames(0.3)

	# 9. mantle 1.5 m box
	seg("mantle")
	await place(Vector3(L.MANTLE_X, 0.02, L.MANTLE_Z + 1.2), 0.0, 1.2)
	move_world = fwd
	await frames(0.3)
	Input.action_press("jump")
	await wait_state("MANTLE", 1.0)
	await frames(0.25); await shot("mantle")
	release_all()
	await frames(0.7); await shot("mantle_top")
	await frames(0.3)

	# 10. camera collision: orbit near pillars / wall
	seg("camera_collision_orbit")
	await place(L.CAM_ORIGIN + Vector3(0, 0.02, 3.0), 0.0)
	move_world = fwd
	orbit_rate = 1.6
	await frames(1.0); await shot("camera_orbit_a")
	await frames(1.0); await shot("camera_orbit_b")
	move_world = Vector3.ZERO
	await frames(1.5); await shot("camera_orbit_c")
	release_all(); await frames(0.3)

	# 11. crate push
	seg("crate_push")
	var crate: Node3D = main.get_node("Props/Crate2")
	await place(crate.global_position * Vector3(1, 0, 1) + Vector3(0, 0.02, 2.0), 0.0, 0.8)
	move_world = fwd
	await frames(1.5); await shot("crate_push")
	release_all(); await frames(0.5)

	var f := FileAccess.open(shots_dir + "/shots.log", FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()
	print("SHOWCASE|done|shots=%d" % shot_n)
	quit(0)
