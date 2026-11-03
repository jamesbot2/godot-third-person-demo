extends SceneTree
## Gameplay-camera-only recording: ONE continuous shot from the player's own
## CameraRig (scripts/camera/camera_rig.gd), exactly what a player sees.
## No inspection cameras, no close-ups, no teleports, no title cards; the
## in-game HUD stays (its F1 debug panel is switched off with a real F1 key
## press, like a player would).
## All control goes through the normal input path (Input.parse_input_event):
##   * keyboard InputEventKey (W/A/S/D, Shift, Space, C, V, Z, F1) and the
##     right mouse button (aim), matched by the project's InputMap;
##   * mouse look as InputEventMouseMotion (integer pixel deltas), handled by
##     CameraRig._unhandled_input with its own sensitivity. The autopilot
##     "player" steers by turning the mouse toward the next waypoint while
##     holding W, so the camera orbits/follows exactly as for a human.
## Run NON-headless (needs a renderer):
##   UAL_EXTRAS=0 DISPLAY=:23 godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##       --resolution 1280x720 --write-movie /tmp/gameplay.avi \
##       -s res://tools/gameplay_cam_record.gd -- --log=/workspace/acceptance/round8/gameplay_thirdperson.log
##   ffmpeg -i /tmp/gameplay.avi -an -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -movflags +faststart gameplay_thirdperson.mp4

const L := preload("res://scripts/level/course_layout.gd")
const FPS := 30.0
const KEYS := {
	"w": KEY_W, "a": KEY_A, "s": KEY_S, "d": KEY_D, "shift": KEY_SHIFT,
	"space": KEY_SPACE, "c": KEY_C, "v": KEY_V, "z": KEY_Z, "f1": KEY_F1,
}
var main: Node
var pc: PlayerController
var rig: CameraRig
var frame := 0
var log_path := "/workspace/acceptance/round8/gameplay_thirdperson.log"
var log_lines: PackedStringArray = []
var _held := {}
var _last_state := ""
var _px_carry := Vector2.ZERO
# steering: while set, the "player" turns the mouse toward this point
var steer_on := false
var steer_pt := Vector3.ZERO
var steer_off := 0.0             # desired camera yaw relative to the move direction
var max_turn := deg_to_rad(150.0) # rad/s mouse turn cap (a brisk human flick)
var turn_gain := 5.0             # 1/s proportional mouse response
var look_rate := Vector2.ZERO    # free-look mouse rate (rad/s yaw, pitch) when not steering
var pitch_goal := deg_to_rad(-12.0)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--log="):
			log_path = a.substr(6)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	pc = main.get_node("Player")
	rig = pc.get_node("CameraRig")
	_run.call_deferred()


func note(s: String) -> void:
	var line := "t=%6.2f f=%4d | %s | pos=(%.2f, %.2f, %.2f) state=%s speed=%.2f" % [
		frame / FPS, frame, s, pc.global_position.x, pc.global_position.y, pc.global_position.z,
		pc.get_state_name(), pc.get_horizontal_speed()]
	print("GCAM|" + line)
	log_lines.append(line)


# ------------------------------------------------------------ raw input ---
func key(k: String, down: bool) -> void:
	if bool(_held.get(k, false)) == down:
		return
	_held[k] = down
	var ev := InputEventKey.new()
	ev.physical_keycode = KEYS[k]
	ev.keycode = KEYS[k]
	ev.pressed = down
	Input.parse_input_event(ev)


func rmb(down: bool) -> void:
	if bool(_held.get("rmb", false)) == down:
		return
	_held["rmb"] = down
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT if down else 0
	ev.pressed = down
	Input.parse_input_event(ev)


## mouse look by an angle (rad); converted to whole pixels with the rig's
## own sensitivity, the remainder is carried to the next frame.
func mouse_look(d_yaw: float, d_pitch: float) -> void:
	var px := Vector2(-d_yaw, -d_pitch) / rig.mouse_sensitivity + _px_carry
	var ipx := Vector2(roundf(px.x), roundf(px.y))
	_px_carry = px - ipx
	if ipx == Vector2.ZERO:
		return
	var ev := InputEventMouseMotion.new()
	ev.relative = ipx
	ev.screen_relative = ipx
	ev.velocity = ipx * FPS
	ev.screen_velocity = ipx * FPS
	Input.parse_input_event(ev)


func tap(k: String) -> void:
	key(k, true)
	await step()
	await step()
	key(k, false)


func release_keys() -> void:
	for k in ["w", "a", "s", "d", "shift", "space", "c", "v"]:
		key(k, false)
	rmb(false)


# ------------------------------------------------------------ frame loop ---
func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func step() -> void:
	var dt := 1.0 / FPS
	var dy := 0.0
	var dp := 0.0
	if steer_on:
		var d := _flat(steer_pt - pc.global_position)
		if d.length() > 0.05:
			var want := atan2(-d.x, -d.z) + steer_off
			var diff := wrapf(want - rig.get_yaw(), -PI, PI)
			dy = clampf(diff * turn_gain, -max_turn, max_turn) * dt
	else:
		dy = look_rate.x * dt
	dp = clampf((pitch_goal - rig.pitch) * 3.0, -1.0, 1.0) * dt + look_rate.y * dt
	mouse_look(dy, dp)
	await process_frame
	frame += 1
	var st := pc.get_state_name()
	if st != _last_state:
		note("STATE %s -> %s" % [_last_state, st])
		_last_state = st


func wait(sec: float) -> void:
	for i in maxi(1, int(round(sec * FPS))):
		await step()


## hold W (plus whatever is held) and steer at `pt` until within `r` metres
func go_to(pt: Vector3, r := 0.8, timeout := 8.0) -> void:
	steer_on = true
	steer_pt = pt
	key("w", true)
	for i in int(timeout * FPS):
		if _flat(pt - pc.global_position).length() <= r:
			return
		await step()
	note("WARN go_to timeout %s" % pt)


func wait_until(cond: Callable, timeout: float) -> bool:
	for i in int(timeout * FPS):
		if cond.call():
			return true
		await step()
	return false


func _run() -> void:
	await process_frame
	tap("f1")   # hide the HUD's F1 debug panel (normal key press)
	note("BEGIN mouse_mode=%d (2=captured)" % Input.mouse_mode)
	var t0 := Time.get_ticks_msec()

	# 1. idle, glance around with the mouse
	await wait(0.8)
	note("look around")
	look_rate = Vector2(deg_to_rad(-45.0), 0.0); await wait(0.9)
	look_rate = Vector2(deg_to_rad(45.0), 0.0); await wait(1.8)
	look_rate = Vector2(deg_to_rad(-45.0), 0.0); await wait(0.9)
	look_rate = Vector2.ZERO

	# 2. walk (Z toggles walk), then jog, then sprint with camera turns
	note("walk")
	await tap("z")
	steer_on = true; steer_pt = Vector3(-4.0, 0, -4.0)   # veer left of the zone-A sign (camera would clip it)
	key("w", true)
	await wait(2.6)
	note("jog")
	await tap("z")
	await go_to(Vector3(4.5, 0, -6.0), 1.0)
	note("sprint")
	key("shift", true)
	await go_to(Vector3(4.5, 0, -14.0), 1.5)
	await go_to(Vector3(-3.0, 0, -15.0), 1.5)
	await go_to(Vector3(-4.0, 0, -6.0), 1.5)
	key("shift", false)
	note("jog (sprint released)")
	await go_to(Vector3(-4.0, 0, -2.0), 1.0)
	key("w", false)
	steer_on = false
	await wait(0.8)

	# 3. aim: strafe right / left, backpedal, aimed forward (camera keeps a slow turn)
	note("aim + strafe right")
	rmb(true)
	await wait(0.4)
	key("d", true)
	look_rate = Vector2(deg_to_rad(12.0), 0.0)
	await wait(1.6)
	key("d", false)
	note("aim + strafe left")
	key("a", true)
	look_rate = Vector2(deg_to_rad(-12.0), 0.0)
	await wait(1.8)
	key("a", false)
	note("aim + backpedal")
	key("s", true)
	look_rate = Vector2.ZERO
	await wait(1.6)
	key("s", false)
	note("aim + forward")
	key("w", true)
	await wait(0.9)
	key("w", false)
	rmb(false)
	await wait(0.4)

	# 4. standing jump, then running jump
	note("standing jump")
	key("space", true); await wait(0.25); key("space", false)
	await wait_until(func(): return pc.get_state_name() == "GROUND" and frame > 0, 2.0)
	await wait(0.4)
	note("run toward the tower")
	await go_to(Vector3(-8.0, 0, 0.5), 1.2)
	note("running jump")
	key("space", true); await wait(0.25); key("space", false)
	await go_to(Vector3(-14.0, 0, 0.6), 0.9)

	# 5. climb the tower stairs to the 2 m landing, run off the side (drop)
	note("climb stairs")
	await go_to(Vector3(-14.0, 0, -8.3), 0.6)
	note("run off the 2 m landing")
	await go_to(Vector3(-18.0, 0, -8.3), 1.5)
	await wait_until(func(): return pc.get_state_name() == "GROUND" and pc.global_position.y < 0.3, 2.0)

	# 6. to the vault wall
	note("sprint to the vault wall")
	key("shift", true)
	await go_to(Vector3(-22.0, 0, -2.0), 1.5)
	await go_to(Vector3(-40.0, 0, -1.0), 2.0)
	key("shift", false)
	await go_to(Vector3(-42.0, 0, L.VAULT_Z + 1.25), 0.4)
	steer_pt = Vector3(-42.0, 0, -12.0)
	await wait_until(func(): return pc.global_position.z <= L.VAULT_Z + 1.0, 1.0)
	note("vault (space)")
	key("space", true)
	await wait_until(func(): return pc.get_state_name() == "VAULT", 1.0)
	key("space", false)
	await wait_until(func(): return pc.get_state_name() == "GROUND", 2.0)
	note("vault done")

	# 7. mantle the 1.5 m box: swing round to its south face, climb, cross
	#    the top and drop off the north edge
	await go_to(Vector3(-43.0, 0, -12.5), 1.0)
	await go_to(Vector3(-47.0, 0, -13.5), 1.0)
	steer_pt = Vector3(-47.0, 0, 0.0)
	await wait_until(func(): return pc.global_position.z >= L.MANTLE_Z - 3.0 - 0.9, 3.0)
	note("mantle (space)")
	key("space", true)
	var ok := await wait_until(func(): return pc.get_state_name() == "MANTLE", 1.0)
	key("space", false)
	if not ok:
		note("WARN no mantle")
	await wait_until(func(): return pc.get_state_name() == "GROUND", 3.0)
	note("on top of the box")
	await go_to(Vector3(-47.0, 0, -6.6), 0.4)
	note("drop off the north edge")
	await go_to(Vector3(-46.0, 0, -3.5), 1.0)

	# 8. sprint to the crates through the gap between the tunnel and the
	#    narrow corridor: slide, then roll on the way
	note("sprint to the crates")
	key("shift", true)
	await go_to(Vector3(-37.0, 0, -2.0), 1.5)
	await go_to(Vector3(-30.7, 0, -3.0), 1.2)
	await go_to(Vector3(-30.7, 0, -7.0), 1.0)
	steer_pt = Vector3(-30.7, 0, -20.0)
	await wait_until(func(): return pc.global_position.z <= -8.6, 1.5)
	note("slide (C while sprinting)")
	await tap("c")
	await wait_until(func(): return pc.get_state_name() != "SLIDE", 2.5)
	await go_to(Vector3(-29.0, 0, -15.0), 1.5)
	await go_to(Vector3(-16.0, 0, -19.5), 1.5)
	note("roll (V)")
	await tap("v")
	await wait_until(func(): return pc.get_state_name() == "GROUND", 1.5)
	# approach a little left of the crate lane so the camera does not pass
	# straight through the zone-H sign hanging above it
	await go_to(Vector3(-3.0, 0, -26.0), 1.2)
	key("shift", false)
	note("jog to Crate2")
	await go_to(Vector3(-1.2, 0, -31.5), 0.6)

	# 9. push Crate2
	note("push crate")
	steer_pt = Vector3(0.0, 0, -35.0)
	await wait_until(func(): return pc.global_position.z <= -34.6, 2.0)
	steer_pt = Vector3(0.0, 0, -60.0)
	await wait(3.6)
	key("w", false)
	steer_on = false
	note("stop, look back")
	await wait(0.5)
	look_rate = Vector2(deg_to_rad(40.0), 0.0); await wait(1.5)
	look_rate = Vector2(deg_to_rad(-40.0), 0.0); await wait(1.5)
	look_rate = Vector2.ZERO
	await wait(0.7)
	release_keys()
	var crate: Node3D = main.get_node("Props/Crate2")
	note("END crate2=(%.2f, %.2f, %.2f) wall_ms=%d" % [crate.global_position.x, crate.global_position.y, crate.global_position.z, Time.get_ticks_msec() - t0])
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()
	quit(0)
