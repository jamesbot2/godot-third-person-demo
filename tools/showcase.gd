extends SceneTree
## Scripted visual showcase (autopilot) for visual acceptance, round 2
## (skeletal character). Must run NON-headless (needs a renderer), e.g.:
##   DISPLAY=:17 godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##       --write-movie /workspace/acceptance/round2/showcase.avi \
##       -s res://tools/showcase.gd -- --shots=/workspace/acceptance/round2
## Optional: --only=<segment>[,<segment>] to render a subset while iterating.
## Drives the real input actions (Input.action_press with analog strength),
## so the controller runs exactly as with a keyboard/gamepad. Screenshots are
## real framebuffer captures (Viewport texture -> PNG). Besides the gameplay
## camera, an "inspection" camera can follow the player from a fixed world
## offset (side / front / back / close-up) so poses can be reviewed.

const L := preload("res://scripts/level/course_layout.gd")
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint",
	"crouch", "crouch_toggle", "roll", "walk_toggle", "aim"]
const SEGMENTS := ["locomotion", "turn_strafe", "jump_land", "stairs", "ramp", "crouch_slide", "roll", "vault", "mantle"]
var main: Node
var pc: PlayerController
var rig: CameraRig
var anim: Node
var shots_dir := "/workspace/acceptance/round2"
var only: PackedStringArray = []
var move_world := Vector3.ZERO   # desired world-space move direction (re-mapped every frame)
var orbit_rate := 0.0            # camera yaw rad/s
var shot_n := 0
var _last_state := ""
var log_lines: PackedStringArray = []
var icam: Camera3D               # inspection camera
var icam_off := Vector3.ZERO     # world-space offset from the player
var icam_look_h := 1.0
var icam_on := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	pc = main.get_node("Player")
	rig = pc.get_node("CameraRig")
	anim = pc.get_node("Model")
	icam = Camera3D.new()
	icam.fov = 50.0
	main.add_child(icam)
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


func _update_icam() -> void:
	if not icam_on:
		return
	var p := pc.global_position
	var target := p + Vector3(0, icam_look_h, 0)
	icam.global_position = target + icam_off
	icam.look_at(target, Vector3.UP)


## Inspection camera: `off` is the world offset from the player's chest.
## Pass Vector3.ZERO to go back to the gameplay camera.
func cam(off: Vector3, look_h := 1.0, fov := 50.0) -> void:
	icam_off = off
	icam_look_h = look_h
	icam.fov = fov
	icam_on = off != Vector3.ZERO
	if icam_on:
		_update_icam()
		icam.make_current()
	else:
		rig.get_camera().make_current()
	# camera_rig hides "Model" when its own camera is too close; the
	# inspection camera always wants to see the character.
	anim.visible = true


func frames(sec: float) -> void:
	for i in maxi(1, int(round(sec * 30.0))):
		if orbit_rate != 0.0:
			rig.add_look(orbit_rate / 30.0, 0.0)
		_apply_move()
		await process_frame
		_update_icam()
		if icam_on:
			anim.visible = true
		var st := pc.get_state_name()
		if st != _last_state:
			var line := "STATE|%s->%s|pos=%s|anim=%s" % [_last_state, st, pc.global_position, anim.anim_state]
			print(line)
			log_lines.append(line)
			_last_state = st


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	shot_n += 1
	var img := root.get_texture().get_image()
	var path := "%s/%02d_%s.png" % [shots_dir, shot_n, name]
	img.save_png(path)
	var d: Dictionary = anim.get_anim_debug()
	var line := "SHOT|%s|state=%s anim=%s pos=%s hspeed=%.2f vy=%.2f gait=%.2f rate=%.2f warp=%.0f bank=%.1f pitch=%.1f land_w=%.2f" % [
		path, pc.get_state_name(), d["anim_state"], pc.global_position, pc.get_horizontal_speed(), pc.velocity.y,
		d["gait"], d["cycle_rate"], d["warp_deg"], d["bank_deg"], d["pitch_deg"], d["land_weight"]]
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


func tap(action: String) -> void:
	Input.action_press(action)
	await frames(1.0 / 30.0)
	Input.action_release(action)


func seg(title: String) -> bool:
	if only.size() > 0 and not only.has(title):
		return false
	print("SEGMENT|%s|t=%.2f" % [title, Time.get_ticks_msec() / 1000.0])
	return true


## Advance until the controller's action progress (roll or traverse, 0..1)
## reaches `u`, so shots land on the same phase at any timing.
func wait_progress(u: float, timeout := 2.0) -> void:
	var n := int(timeout * 30.0)
	for i in n:
		var p := 1.0
		if pc.get_state_name() == "ROLL":
			p = pc.roll_time / maxf(pc.roll_duration, 0.01)
		elif pc.state == PlayerController.State.TRAVERSE:
			p = anim.get_traverse_progress()
		if p >= u:
			return
		await frames(1.0 / 30.0)


func wait_state(sname: String, timeout: float) -> bool:
	for i in int(timeout * 30.0):
		if pc.get_state_name() == sname:
			return true
		await frames(1.0 / 30.0)
	return false


const SIDE := Vector3(3.4, 0.0, 0.0)      # camera on the player's right (+X) for -Z travel
const SIDE_CLOSE := Vector3(2.6, 0.0, 0.6)
const FRONT := Vector3(0.0, 0.0, -3.4)
const BACK := Vector3(0.0, 0.3, 3.6)


func _run() -> void:
	var fwd := Vector3(0, 0, -1)
	# 1. idle (front/side/back), walk / jog / sprint / stop, side camera
	if seg("locomotion"):
		await place(Vector3(0, 0.02, 10), 0.0, 0.0)
		cam(FRONT); await frames(0.6); await shot("idle_front")
		cam(SIDE); await frames(0.3); await shot("idle_side")
		cam(BACK); await frames(0.3); await shot("idle_back")
		cam(SIDE_CLOSE, 1.1, 40.0); await frames(0.3); await shot("idle_close")
		cam(SIDE)
		await tap("walk_toggle")
		move_world = fwd
		await frames(1.0); await shot("walk_side_a")
		await frames(0.33); await shot("walk_side_b")
		await tap("walk_toggle")
		await frames(1.0); await shot("jog_side_a")
		await frames(0.2); await shot("jog_side_b")
		Input.action_press("sprint")
		await frames(1.4); await shot("sprint_side_a")
		await frames(0.15); await shot("sprint_side_b")
		Input.action_release("sprint")
		move_world = Vector3.ZERO
		await frames(0.12); await shot("stop_brake")
		await frames(0.8); await shot("stop_settled")
		cam(Vector3.ZERO)
		release_all(); await frames(0.3)

	# 2. turns (90 deg, 180 deg) and aimed strafe / backpedal
	if seg("turn_strafe"):
		await place(Vector3(0, 0.02, 14), 0.0, 0.0)
		cam(Vector3(2.5, 2.6, 3.5), 0.8, 55.0)
		move_world = fwd
		await frames(1.0)
		move_world = Vector3(1, 0, 0)
		await frames(0.2); await shot("turn90_bank")
		await frames(0.8)
		move_world = Vector3(-1, 0, 0)
		await frames(0.15); await shot("turn180_mid")
		await frames(0.9)
		release_all(); await frames(0.5)
		# strafe: hold aim, facing follows the camera (camera looks -Z)
		await place(Vector3(0, 0.02, 14), 0.0, 0.0)
		cam(FRONT + Vector3(0, 0.3, 0))
		Input.action_press("aim")
		move_world = Vector3(1, 0, 0)
		await frames(0.9); await shot("strafe_right_front")
		move_world = Vector3(-1, 0, 0)
		await frames(1.2); await shot("strafe_left_front")
		cam(SIDE)
		move_world = Vector3(0, 0, 1)
		await frames(1.0); await shot("backpedal_side")
		move_world = Vector3(1, 0, -1)
		await frames(0.8); await shot("strafe_diag_side")
		cam(Vector3.ZERO)
		release_all(); await frames(0.4)

	# 3. standing jump, running jump, 2 m drop (hard landing)
	if seg("jump_land"):
		await place(Vector3(4, 0.02, 10), 0.0, 0.0)
		cam(SIDE)
		await frames(0.3)
		Input.action_press("jump")
		await frames(2.0 / 30.0); await shot("jump_takeoff")
		await frames(0.3); await shot("jump_apex")
		Input.action_release("jump")
		for i in 30:
			if pc.get_state_name() == "GROUND":
				break
			await frames(1.0 / 30.0)
		await frames(2.0 / 30.0); await shot("jump_land_soft")
		await frames(0.6)
		move_world = fwd
		await frames(0.8)
		Input.action_press("jump")
		await frames(0.4); await shot("runjump_air")
		Input.action_release("jump")
		await frames(0.8)
		release_all(); await frames(0.3)
		# drop from the 2 m tower landing toward +X
		var mid_z := L.TOWER_Z0 - L.TOWER_TREAD * L.TOWER_MID_STEPS - L.TOWER_LANDING * 0.5
		await place(Vector3(L.TOWER_X, 2.02, mid_z), -PI / 2.0, 0.0)
		cam(Vector3(0, 0.2, 4.2), 0.9)
		move_world = Vector3(1, 0, 0)
		await wait_state("AIR", 2.0)
		await frames(0.2); await shot("drop_fall")
		for i in 40:
			if pc.get_state_name() == "GROUND":
				break
			await frames(1.0 / 30.0)
		move_world = Vector3.ZERO
		await frames(2.0 / 30.0); await shot("drop_land_hard")
		await frames(0.25); await shot("drop_recover")
		await frames(0.6)
		cam(Vector3.ZERO)
		release_all(); await frames(0.3)

	# 4. stairs (0.18 m risers) up and down
	if seg("stairs"):
		await place(Vector3(L.STAIR_X, 0.02, L.STAIR_Z0 + 2.0), 0.0, 0.0)
		cam(SIDE + Vector3(0, 0.3, 0))
		move_world = fwd
		await frames(1.1); await shot("stairs_up_side")
		await frames(0.25); await shot("stairs_up_side_b")
		await frames(1.6); await shot("stairs_down_side")
		cam(Vector3.ZERO)
		release_all(); await frames(0.4)

	# 5. 30 degree ramp up
	if seg("ramp"):
		await place(Vector3(L.ramp_x(2), 0.02, L.RAMP_Z0 + 2.0), 0.0, 0.0)
		cam(SIDE + Vector3(0, 0.3, 0))
		move_world = fwd
		await frames(1.25); await shot("ramp30_up_side")
		await frames(0.6)
		cam(Vector3.ZERO)
		release_all(); await frames(0.3)

	# 6. crouch walk, then sprint -> slide
	if seg("crouch_slide"):
		await place(Vector3(-4, 0.02, 12), 0.0, 0.0)
		cam(SIDE)
		await tap("crouch_toggle")
		await frames(0.5); await shot("crouch_idle_side")
		move_world = fwd
		await frames(1.0); await shot("crouch_walk_side")
		await tap("crouch_toggle")
		Input.action_press("sprint")
		await frames(1.3)
		await tap("crouch_toggle")
		await frames(0.1); await shot("slide_entry")
		await frames(0.35); await shot("slide_mid")
		await wait_state("GROUND", 1.5)
		await frames(0.1); await shot("slide_exit")
		await frames(0.6)
		cam(Vector3.ZERO)
		release_all(); await frames(0.5)

	# 7. roll from a jog
	if seg("roll"):
		await place(Vector3(-8, 0.02, 12), 0.0, 0.0)
		cam(SIDE)
		move_world = fwd
		await frames(0.8)
		await tap("roll")
		await wait_state("ROLL", 0.5)
		await wait_progress(0.12); await shot("roll_a")
		await wait_progress(0.4); await shot("roll_b")
		await wait_progress(0.62); await shot("roll_c")
		await wait_progress(0.88); await shot("roll_d")
		await frames(0.6)
		cam(Vector3.ZERO)
		release_all(); await frames(0.4)

	# 8. vault the 0.9 m wall
	if seg("vault"):
		await place(Vector3(L.VAULT_X, 0.02, L.VAULT_Z + 5.0), 0.0, 0.0)
		cam(SIDE_CLOSE, 0.9, 42.0)
		move_world = fwd
		for i in 90:
			if pc.global_position.z <= L.VAULT_Z + 1.0:
				break
			await frames(1.0 / 30.0)
		Input.action_press("jump")
		await wait_state("VAULT", 1.0)
		await wait_progress(0.3); await shot("vault_reach")
		await wait_progress(0.52); await shot("vault_plant")
		Input.action_release("jump")
		await wait_progress(0.76); await shot("vault_clear")
		await frames(0.25); await shot("vault_land")
		await frames(0.8)
		cam(Vector3.ZERO)
		release_all(); await frames(0.3)

	# 9. mantle the 1.5 m box
	if seg("mantle"):
		await place(Vector3(L.MANTLE_X, 0.02, L.MANTLE_Z + 2.0), 0.0, 0.0)
		cam(SIDE_CLOSE + Vector3(0, 0.2, 0), 1.2, 44.0)
		move_world = fwd
		await frames(0.4)
		Input.action_press("jump")
		await wait_state("MANTLE", 1.0)
		await wait_progress(0.2); await shot("mantle_hang")
		await wait_progress(0.45); await shot("mantle_pull")
		await wait_progress(0.7); await shot("mantle_step")
		release_all()
		await frames(0.3); await shot("mantle_top")
		await frames(0.4)
		cam(Vector3.ZERO)
		release_all(); await frames(0.3)

	var f := FileAccess.open(shots_dir + "/shots.log", FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()
	print("SHOWCASE|done|shots=%d" % shot_n)
	quit(0)
