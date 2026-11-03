extends SceneTree
## Headless automated movement tests.
## Usage: godot --headless --fixed-fps <HZ> -s res://tests/run_tests.gd -- --hz=<HZ> [--only=name]
## Time is measured in physics ticks (t = ticks / hz), never wall-clock.
## Output: one "RESULT|PASS/FAIL|name|detail" line per check + "METRIC|name|value" lines.

const L := preload("res://scripts/level/course_layout.gd")
var hz := 60
var only := ""
var main: Node
var pc: PlayerController
var rig: CameraRig
var passes := 0
var fails := 0
var metrics := {}
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint",
	"crouch", "crouch_toggle", "roll", "walk_toggle", "aim"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hz="):
			hz = int(a.substr(5))
		elif a.begins_with("--only="):
			only = a.substr(7)
	Engine.physics_ticks_per_second = hz
	Engine.max_physics_steps_per_frame = 8
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	pc = main.get_node("Player")
	rig = pc.get_node("CameraRig")
	_run.call_deferred()


# ------------------------------------------------------------- helpers ---
func tick(n := 1) -> void:
	for i in n:
		await physics_frame


func secs(t: float) -> int:
	return maxi(1, int(round(t * hz)))


func press(a: String) -> void:
	Input.action_press(a)


func release(a: String) -> void:
	Input.action_release(a)


func release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func place(pos: Vector3, yaw := 0.0) -> void:
	release_all()
	await tick(1)
	pc.teleport(pos, yaw)
	rig.yaw = yaw
	await tick(secs(0.4))   # settle onto floor


## Hold the current inputs until the player's z <= z_target (or timeout).
## Returns stats {ok, t, max_y, max_vy, air}.
func walk_until_z(z_target: float, timeout: float) -> Dictionary:
	var st := {"ok": false, "t": -1.0, "max_y": -INF, "max_vy": 0.0, "air": 0}
	for n in secs(timeout):
		await tick()
		st["max_y"] = maxf(st["max_y"], pc.global_position.y)
		st["max_vy"] = maxf(st["max_vy"], pc.velocity.y)
		if pc.state == PlayerController.State.AIR:
			st["air"] += 1
		if pc.global_position.z <= z_target:
			st["ok"] = true
			st["t"] = float(n + 1) / hz
			break
	return st


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("RESULT|%s|%s|%s" % ["PASS" if ok else "FAIL", name, detail])


func metric(name: String, v: float) -> void:
	metrics[name] = v
	print("METRIC|%s|%.4f" % [name, v])


func want(name: String) -> bool:
	return only == "" or name.begins_with(only)


# --------------------------------------------------------------- runner ---
func _run() -> void:
	await tick(5)
	print("INFO|physics_hz=%d engine=%s" % [hz, Engine.get_version_info()["string"]])
	var tests := ["t_accel", "t_reverse", "t_turn", "t_steps", "t_step_down", "t_stairs", "t_ramps",
		"t_slope_rest", "t_jump", "t_coyote", "t_buffer", "t_air_control", "t_corridors", "t_wall",
		"t_tunnel", "t_slide", "t_roll", "t_vault", "t_mantle", "t_tall_wall", "t_landing",
		"t_crates", "t_camera", "t_fuzz", "t_anim"]
	for t in tests:
		if want(t):
			await call(t)
	release_all()
	print("SUMMARY|hz=%d|pass=%d|fail=%d" % [hz, passes, fails])
	quit(0 if fails == 0 else 1)


# ---------------------------------------------------------------- tests ---
func t_accel() -> void:
	await place(Vector3(0, 0.02, 4))
	press("move_forward")
	var n := 0
	var t90 := -1.0
	while n < secs(2.0):
		await tick()
		n += 1
		if t90 < 0.0 and pc.get_horizontal_speed() >= pc.jog_speed * 0.9:
			t90 = float(n) / hz
	metric("jog_t90_s", t90)
	check("accel_jog_t90", t90 > 0.1 and t90 < 0.3, "t90=%.3fs (expect ~0.17)" % t90)
	var z0 := pc.global_position.z
	release("move_forward")
	n = 0
	while pc.get_horizontal_speed() > 0.01 and n < secs(2.0):
		await tick()
		n += 1
	var d_stop := absf(pc.global_position.z - z0)
	var expect := pc.jog_speed * pc.jog_speed / (2.0 * pc.brake_decel)
	metric("jog_stop_dist_m", d_stop)
	metric("jog_stop_time_s", float(n) / hz)
	check("brake_dist_jog", absf(d_stop - expect) < 0.04, "d=%.3f expect=%.3f" % [d_stop, expect])
	# sprint build-up and stop
	await place(Vector3(0, 0.02, 20))
	press("move_forward"); press("sprint")
	n = 0
	var t_sprint := -1.0
	while n < secs(3.0):
		await tick()
		n += 1
		if t_sprint < 0.0 and pc.get_horizontal_speed() >= pc.sprint_speed * 0.95:
			t_sprint = float(n) / hz
	metric("sprint_t95_s", t_sprint)
	check("sprint_buildup", t_sprint > 0.35 and t_sprint < 0.8, "t95=%.3fs" % t_sprint)
	z0 = pc.global_position.z
	release_all()
	n = 0
	while pc.get_horizontal_speed() > 0.01 and n < secs(2.0):
		await tick()
		n += 1
	d_stop = absf(pc.global_position.z - z0)
	metric("sprint_stop_dist_m", d_stop)
	check("brake_dist_sprint", d_stop > 0.6 and d_stop < 1.2, "d=%.3f" % d_stop)
	# sprint release -> jog (overspeed decel, not instant)
	await place(Vector3(4, 0.02, 20))
	press("move_forward"); press("sprint")
	await tick(secs(1.5))
	release("sprint")
	await tick(secs(0.1))
	var v01 := pc.get_horizontal_speed()
	await tick(secs(0.4))
	metric("sprint_exit_speed_0.1s", v01)
	check("sprint_exit_gradual", v01 > pc.jog_speed + 0.4 and absf(pc.get_horizontal_speed() - pc.jog_speed) < 0.2, "v@0.1s=%.2f v@0.5s=%.2f" % [v01, pc.get_horizontal_speed()])
	release_all()


func t_reverse() -> void:
	await place(Vector3(0, 0.02, 4))
	press("move_forward")
	await tick(secs(1.0))
	release("move_forward"); press("move_back")
	var n := 0
	var t_rev := -1.0
	while n < secs(1.5):
		await tick()
		n += 1
		if pc.velocity.z > pc.jog_speed * 0.9:
			t_rev = float(n) / hz
			break
	metric("reverse_t90_s", t_rev)
	check("reverse_180", t_rev > 0.2 and t_rev < 0.5, "t=%.3fs" % t_rev)
	release_all()


func t_turn() -> void:
	# 90 deg cut at jog: lateral momentum carries (curved path) but settles quickly.
	await place(Vector3(0, 0.02, 4))
	press("move_forward")
	await tick(secs(1.0))
	var p0 := pc.global_position
	release("move_forward"); press("move_right")
	var n := 0
	var t_turn := -1.0
	var max_speed := 0.0
	while n < secs(1.0):
		await tick()
		n += 1
		max_speed = maxf(max_speed, pc.get_horizontal_speed())
		if t_turn < 0.0 and pc.velocity.x > pc.jog_speed * 0.9 and absf(pc.velocity.z) < 0.3:
			t_turn = float(n) / hz
	var overshoot := absf(pc.global_position.z - p0.z)
	metric("turn90_t_s", t_turn)
	metric("turn90_overshoot_m", overshoot)
	check("turn_90", t_turn > 0.08 and t_turn < 0.35 and max_speed <= pc.jog_speed + 0.01, "t=%.3fs overshoot=%.2fm vmax=%.2f" % [t_turn, overshoot, max_speed])
	# facing never snaps: max yaw change per tick bounded
	release_all()
	await place(Vector3(0, 0.02, 4))
	press("move_forward")
	await tick(secs(0.5))
	release("move_forward"); press("move_back")
	var max_dyaw := 0.0
	var y_prev := pc.facing_yaw
	for i in secs(0.6):
		await tick()
		max_dyaw = maxf(max_dyaw, absf(wrapf(pc.facing_yaw - y_prev, -PI, PI)))
		y_prev = pc.facing_yaw
	var max_rate := rad_to_deg(max_dyaw) * hz
	check("no_instant_turn", max_rate <= pc.turn_rate_slow + 1.0, "max turn rate %.0f deg/s" % max_rate)
	release_all()


func t_steps() -> void:
	# Walk into each block and stop once the body centre is 1 m onto the tread.
	var zt := L.STEP_Z_NEAR - 1.0
	for i in L.STEP_HEIGHTS.size():
		var h: float = L.STEP_HEIGHTS[i]
		await place(Vector3(L.step_lane_x(i), 0.02, -3.5))
		press("move_forward")
		var st := await walk_until_z(zt, 3.0)
		release_all()
		await tick(secs(0.2))
		var y := pc.global_position.y
		var detail := "h=%.2f reached=%s y_on_top=%.3f max_y=%.3f max_vy=%.2f air_ticks=%d t=%.2fs" % [h, st["ok"], y, st["max_y"], st["max_vy"], st["air"], st["t"]]
		if h <= pc.max_step_height + 0.001:
			check("step_up_%.2f" % h, st["ok"] and absf(y - h) < 0.03 and st["max_y"] < h + 0.06 and st["max_vy"] < 1.5 and st["air"] <= 2, detail)
		else:
			check("step_block_%.2f" % h, (not st["ok"]) and y < 0.05 and st["max_y"] < 0.1, detail)


func t_step_down() -> void:
	# Walk off the far edge of each climbable step block: must stay grounded (snap), no float.
	for i in 4:
		var h: float = L.STEP_HEIGHTS[i]
		await place(Vector3(L.step_lane_x(i), h + 0.02, L.STEP_Z_FAR + 1.0))
		press("move_forward"); press("sprint")
		var air := 0
		var min_vy := 0.0
		for n in secs(1.0):
			await tick()
			if not pc.is_on_floor():
				air += 1
			min_vy = minf(min_vy, pc.velocity.y)
		release_all()
		check("step_down_%.2f" % h, pc.global_position.y < 0.05 and air <= 2 and pc.state == PlayerController.State.GROUND,
			"y=%.3f air_ticks=%d" % [pc.global_position.y, air])


func t_stairs() -> void:
	# Normal stairs (0.18 riser) up, across the landing and down - no jump input.
	await place(Vector3(L.STAIR_X, 0.02, L.STAIR_Z0 + 1.5))
	press("move_forward")
	var max_y := 0.0
	var air := 0
	var t_top := -1.0
	var cam_y := []
	var max_vy := 0.0
	for n in secs(4.0):
		await tick()
		max_y = maxf(max_y, pc.global_position.y)
		max_vy = maxf(max_vy, pc.velocity.y)
		if pc.state == PlayerController.State.AIR:
			air += 1
		if t_top < 0.0 and pc.global_position.y > 1.78:
			t_top = float(n) / hz
		rig.update_rig(1.0 / hz)
		cam_y.append(rig.get_camera().global_position.y)
	metric("stairs_up_time_s", t_top)
	check("stairs_up_no_jump", t_top > 0.0 and max_y < 1.86 and max_vy < 1.5, "t_top=%.2fs max_y=%.3f air_ticks=%d jumps=0" % [t_top, max_y, air])
	# camera vertical smoothness on stairs: largest per-tick change
	var max_dcam := 0.0
	for k in range(1, cam_y.size()):
		max_dcam = maxf(max_dcam, absf(cam_y[k] - cam_y[k - 1]))
	metric("stairs_cam_max_dy_per_tick", max_dcam)
	check("stairs_camera_smooth", max_dcam < 0.06 * 60.0 / hz + 0.01, "max cam dy/tick=%.4f" % max_dcam)
	# continue down
	var air_down := 0
	for n in secs(4.0):
		await tick()
		if not pc.is_on_floor():
			air_down += 1
	release_all()
	check("stairs_down_grounded", pc.global_position.y < 0.05 and air_down <= 3, "y=%.3f ungrounded_ticks=%d" % [pc.global_position.y, air_down])
	# steep stairs 0.25 riser
	await place(Vector3(L.STEEP_X, 0.02, L.STAIR_Z0 + 1.5))
	press("move_forward")
	var st := await walk_until_z(L.STAIR_Z0 - L.STEEP_TREAD * L.STEEP_STEPS - 1.0, 5.0)
	release_all()
	await tick(secs(0.2))
	check("steep_stairs_0.25", st["ok"] and absf(pc.global_position.y - 2.0) < 0.03 and st["max_vy"] < 2.0,
		"reached=%s y=%.3f t=%.2fs max_vy=%.2f air_ticks=%d" % [st["ok"], pc.global_position.y, st["t"], st["max_vy"], st["air"]])


func t_ramps() -> void:
	for i in L.RAMP_ANGLES.size():
		var a: float = L.RAMP_ANGLES[i]
		await place(Vector3(L.ramp_x(i), 0.02, L.RAMP_Z0 + 1.5))
		press("move_forward")
		var st := await walk_until_z(L.RAMP_Z0 - L.ramp_run(i) - 1.0, 5.0)
		var y := pc.global_position.y
		var d := "angle=%d reached=%s y=%.3f t=%.2fs max_vy=%.2f air_ticks=%d" % [int(a), st["ok"], y, st["t"], st["max_vy"], st["air"]]
		if a <= pc.max_slope_deg:
			# no launch over the crest: never airborne, vertical speed bounded by slope geometry
			check("ramp_up_%d" % int(a), st["ok"] and absf(y - L.RAMP_RISE) < 0.05 and st["air"] <= 2, d)
			# top-of-ramp crest: walk back down - no launch at the crest/bottom
			release_all()
			press("move_back")
			var air2 := 0
			for n in secs(3.0):
				await tick()
				if not pc.is_on_floor():
					air2 += 1
			release_all()
			check("ramp_down_%d" % int(a), pc.global_position.y < 0.05 and air2 <= 3, "y=%.3f ungrounded_ticks=%d" % [pc.global_position.y, air2])
		else:
			check("ramp_reject_%d" % int(a), y < 0.6, d)
		release_all()


func t_slope_rest() -> void:
	# Stand still on the 40 deg ramp: no sliding drift.
	var i := 3
	var run := L.ramp_run(i)
	var z := L.RAMP_Z0 - run * 0.5
	await place(Vector3(L.ramp_x(i), L.RAMP_RISE * 0.5 + 0.3, z))
	await tick(secs(0.5))
	var p0 := pc.global_position
	await tick(secs(2.0))
	var drift := pc.global_position.distance_to(p0)
	metric("slope40_drift_m", drift)
	check("slope_40_no_drift", drift < 0.03 and pc.is_on_floor(), "drift=%.4f" % drift)


func t_jump() -> void:
	await place(Vector3(-4, 0.02, 4))
	var y0 := pc.global_position.y
	press("jump")
	var apex := y0
	var t_air := 0
	await tick()
	while t_air < secs(2.0):
		await tick()
		t_air += 1
		apex = maxf(apex, pc.global_position.y)
		if pc.state == PlayerController.State.GROUND:
			break
	release("jump")
	metric("jump_apex_m", apex - y0)
	metric("jump_airtime_s", float(t_air) / hz)
	check("jump_full_height", absf((apex - y0) - pc.jump_height) < 0.03, "apex=%.3f expect=%.2f airtime=%.3fs" % [apex - y0, pc.jump_height, float(t_air) / hz])
	# tap jump (1 tick)
	await place(Vector3(-4, 0.02, 4))
	y0 = pc.global_position.y
	press("jump")
	await tick()
	release("jump")
	apex = y0
	for n in secs(1.2):
		await tick()
		apex = maxf(apex, pc.global_position.y)
	metric("jump_tap_apex_m", apex - y0)
	check("jump_variable_tap", apex - y0 > 0.3 and apex - y0 < 0.55, "tap apex=%.3f" % (apex - y0))
	# no double jump / no bunny-hop speed gain
	await place(Vector3(-4, 0.02, 4))
	press("move_forward"); press("sprint")
	await tick(secs(1.5))
	var vmax := 0.0
	for k in 6:
		press("jump")
		for n in secs(0.9):
			await tick()
			vmax = maxf(vmax, pc.get_horizontal_speed())
		release("jump")
		await tick(2)
	release_all()
	check("no_bhop_gain", vmax <= pc.sprint_speed + 0.05, "max h-speed over 6 chained jumps=%.3f" % vmax)


func t_coyote() -> void:
	for spec in [[0.07, true], [0.2, false]]:
		var delay: float = spec[0]
		# walk off the east side of the 2 m tower mid landing (fall ~0.47 s, so a
		# buffered press cannot fire on touchdown and mask a late coyote jump)
		var mz := L.TOWER_Z0 - L.TOWER_TREAD * L.TOWER_MID_STEPS - L.TOWER_LANDING * 0.5
		await place(Vector3(L.TOWER_X, 2.02, mz), -PI / 2.0)
		press("move_forward")
		var n := 0
		while pc.state != PlayerController.State.AIR and n < secs(2.0):
			await tick()
			n += 1
		await tick(secs(delay))
		press("jump")
		await tick(2)
		var jumped := pc.velocity.y > 2.0
		release_all()
		check("coyote_%.2fs" % delay, jumped == spec[1], "delay=%.2f jumped=%s vy=%.2f" % [delay, jumped, pc.velocity.y])
		await tick(secs(0.8))


func t_buffer() -> void:
	# Press jump ~0.1 s before touching down; the jump fires on landing.
	await place(Vector3(-4, 0.02, 4))
	press("jump")
	await tick(2)
	release("jump")
	var n := 0
	# y < 0.15 on the way down = ~0.13 s before touchdown (inside the 0.15 s buffer)
	while not (pc.velocity.y < 0.0 and pc.global_position.y < 0.15) and n < secs(2.0):
		await tick()
		n += 1
	press("jump")
	await tick()
	release("jump")
	var landed_at := -1
	var rejumped := false
	for k in secs(0.5):
		await tick()
		# we were falling when jump was pressed: any upward speed now means the
		# buffered press fired on (or right after) touchdown
		if pc.velocity.y > 3.0:
			rejumped = true
			landed_at = k
			break
	check("jump_buffer", rejumped, "rejumped=%s" % rejumped)
	await tick(secs(1.0))


func t_air_control() -> void:
	# Standing jump: air steering can only produce limited drift (no mid-air flight).
	await place(Vector3(-8, 0.02, 4))
	press("jump")
	await tick()
	press("move_right")
	var x0 := pc.global_position.x
	var n := 0
	await tick()
	while pc.state == PlayerController.State.AIR and n < secs(2.0):
		await tick()
		n += 1
	var drift := pc.global_position.x - x0
	release_all()
	metric("air_drift_from_rest_m", drift)
	check("air_control_limited", drift > 0.1 and drift < 0.6, "lateral drift=%.3fm in %.2fs" % [drift, float(n) / hz])
	# Running jump with reverse input: momentum retained (cannot stop in air).
	await place(Vector3(-8, 0.02, 4))
	press("move_forward")
	await tick(secs(1.0))
	press("jump")
	await tick()
	release("move_forward"); press("move_back")
	var v_start := -pc.velocity.z
	n = 0
	while pc.state == PlayerController.State.AIR and n < secs(2.0):
		await tick()
		n += 1
		if pc.state == PlayerController.State.AIR:
			v_start = v_start
	var v_land := -pc.velocity.z
	release_all()
	check("air_momentum", v_land > pc.jog_speed * 0.5, "fwd speed at take-off=%.2f, before landing=%.2f" % [pc.jog_speed, v_land])


func t_corridors() -> void:
	for spec in [[L.CORRIDOR_X, "1.0"], [L.NARROW_X, "0.85"]]:
		await place(Vector3(spec[0], 0.02, L.CORRIDOR_Z0 + 1.5))
		press("move_forward"); press("sprint")
		await tick(secs(2.8))
		var z := pc.global_position.z
		release_all()
		check("corridor_%s" % spec[1], z < L.CORRIDOR_Z0 - L.CORRIDOR_LEN + 0.6 and absf(pc.global_position.x - spec[0]) < 0.2 and pc.global_position.y < 0.1,
			"z=%.2f x_err=%.3f y=%.3f" % [z, pc.global_position.x - spec[0], pc.global_position.y])
	# diagonal into corridor corner: no jitter/sticking (keeps sliding along wall)
	await place(Vector3(L.CORRIDOR_X, 0.02, L.CORRIDOR_Z0 - 2.0), deg_to_rad(20.0))
	press("move_forward")
	var max_y := 0.0
	var max_xerr := 0.0
	var zs := pc.global_position.z
	for n in secs(1.0):   # stays inside the corridor (ends at z=-12)
		await tick()
		max_y = maxf(max_y, pc.global_position.y)
		max_xerr = maxf(max_xerr, absf(pc.global_position.x - L.CORRIDOR_X))
	release_all()
	var prog := zs - pc.global_position.z
	var lim := L.CORRIDOR_WIDTH * 0.5 - pc.body_radius + 0.02
	check("corridor_wall_slide", max_y < 0.06 and max_xerr <= lim and prog > 2.0,
		"max_y=%.3f max|x-c|=%.3f (limit %.3f) progress=%.2fm" % [max_y, max_xerr, lim, prog])


func t_wall() -> void:
	# Sprint head-on and at 30 deg into the 2.3 m wall at 120% speed: no climb, no tunnel.
	for ang in [0.0, 30.0]:
		await place(Vector3(L.TALL_X, 0.02, L.MANTLE_Z + 3.0), deg_to_rad(ang))
		press("move_forward"); press("sprint")
		var max_y := 0.0
		var min_z := 99.0   # closest approach while in front of the 3 m wide wall
		for n in secs(2.0):
			await tick()
			max_y = maxf(max_y, pc.global_position.y)
			if absf(pc.global_position.x - L.TALL_X) < 1.5 - pc.body_radius:
				min_z = minf(min_z, pc.global_position.z)
		release_all()
		check("wall_no_climb_%d" % int(ang), max_y < 0.06 and min_z > L.MANTLE_Z + pc.body_radius - 0.02,
			"max_y=%.3f min_z_in_front=%.3f (face z=%.2f + r=%.2f)" % [max_y, min_z, L.MANTLE_Z, pc.body_radius])
	# Fast projectile-like velocity into the wall (tunnelling check at low tick rate)
	await place(Vector3(L.TALL_X, 0.02, L.MANTLE_Z + 3.0))
	pc.velocity = Vector3(0, 0, -30)
	await tick(secs(0.5))
	check("wall_no_tunnel_30mps", pc.global_position.z > L.MANTLE_Z, "z=%.3f" % pc.global_position.z)


func t_tunnel() -> void:
	# Standing: blocked by the 1.35 m roof. Crouched: passes. Can't stand up inside.
	await place(Vector3(L.TUNNEL_X, 0.02, L.TUNNEL_Z0 + 2.0))
	press("move_forward")
	await tick(secs(1.5))
	var z_stand := pc.global_position.z
	check("tunnel_blocks_standing", z_stand > L.TUNNEL_Z0, "z=%.2f" % z_stand)
	press("crouch")
	await tick(secs(1.5))
	release("crouch")    # try to stand inside the tunnel
	await tick(secs(0.3))
	var inside_ok := pc.is_crouched and pc.current_height <= pc.crouch_height + 0.01
	check("tunnel_no_stand_inside", inside_ok and pc.global_position.z < L.TUNNEL_Z0, "z=%.2f crouched=%s h=%.2f" % [pc.global_position.z, pc.is_crouched, pc.current_height])
	await tick(secs(4.0))
	var through := pc.global_position.z < L.TUNNEL_Z0 - L.TUNNEL_LEN
	release_all()
	await tick(secs(0.3))
	check("tunnel_crouch_through_and_stand", through and not pc.is_crouched, "z=%.2f crouched=%s" % [pc.global_position.z, pc.is_crouched])


func t_slide() -> void:
	await place(Vector3(4, 0.02, 20))
	press("move_forward"); press("sprint")
	await tick(secs(1.5))
	var v0 := pc.get_horizontal_speed()
	var z0 := pc.global_position.z
	press("crouch_toggle")
	await tick()
	release("crouch_toggle")
	await tick()
	var started := pc.state == PlayerController.State.SLIDE
	var v_peak := pc.get_horizontal_speed()
	var n := 0
	while pc.state == PlayerController.State.SLIDE and n < secs(3.0):
		await tick()
		n += 1
	var dist := absf(pc.global_position.z - z0)
	metric("slide_time_s", float(n) / hz)
	metric("slide_dist_m", dist)
	check("slide_start", started and v_peak > v0 and v_peak <= pc.slide_max_entry + 0.01, "v_sprint=%.2f v_entry=%.2f" % [v0, v_peak])
	check("slide_ends", n > secs(0.6) and n < secs(1.7), "time=%.2fs dist=%.2fm state=%s" % [float(n) / hz, dist, pc.get_state_name()])
	# immediate re-slide is blocked by cooldown / speed
	press("crouch_toggle"); await tick(); release("crouch_toggle"); await tick()
	check("slide_cooldown", pc.state != PlayerController.State.SLIDE, "state=%s" % pc.get_state_name())
	release_all()
	await tick(secs(0.5))
	# slide jump cancel
	await place(Vector3(8, 0.02, 20))
	press("move_forward"); press("sprint")
	await tick(secs(1.5))
	press("crouch_toggle"); await tick(); release("crouch_toggle")
	await tick(secs(0.3))
	press("jump"); await tick(2); release("jump")
	check("slide_jump_cancel", pc.state == PlayerController.State.AIR and pc.velocity.y > 2.0 and pc.current_height > 1.79, "state=%s vy=%.2f h=%.2f" % [pc.get_state_name(), pc.velocity.y, pc.current_height])
	release_all()
	await tick(secs(1.0))
	# slide under the tunnel: ends crouched inside, never stands into the roof
	await place(Vector3(L.TUNNEL_X, 0.02, L.TUNNEL_Z0 + 9.0))
	press("move_forward"); press("sprint")
	await tick(secs(1.15))
	press("crouch_toggle"); await tick(); release("crouch_toggle")
	release("sprint")
	var ceiling_ok := true
	for k in secs(2.0):
		await tick()
		if pc.global_position.z < L.TUNNEL_Z0 - 0.2 and pc.global_position.z > L.TUNNEL_Z0 - L.TUNNEL_LEN + 0.2 and pc.current_height > L.TUNNEL_HEIGHT:
			ceiling_ok = false
	release_all()
	check("slide_into_tunnel_safe", ceiling_ok and pc.global_position.y < 0.05, "z=%.2f h=%.2f y=%.3f" % [pc.global_position.z, pc.current_height, pc.global_position.y])


func t_roll() -> void:
	await place(Vector3(-4, 0.02, 20))
	press("move_forward")
	await tick(secs(1.0))
	press("roll"); await tick(); release("roll")
	await tick()
	var started := pc.state == PlayerController.State.ROLL
	var z0 := pc.global_position.z
	var n := 0
	while pc.state == PlayerController.State.ROLL and n < secs(2.0):
		await tick()
		n += 1
	var dur := float(n + 1) / hz
	metric("roll_dist_m", absf(pc.global_position.z - z0))
	check("roll", started and absf(dur - pc.roll_duration) < 0.05, "dur=%.3fs dist=%.2fm end=%s" % [dur, absf(pc.global_position.z - z0), pc.get_state_name()])
	press("roll"); await tick(); release("roll"); await tick()
	check("roll_cooldown", pc.state != PlayerController.State.ROLL, "state=%s" % pc.get_state_name())
	await tick(secs(0.6))
	# roll from standstill uses facing
	press("roll"); await tick(); release("roll"); await tick(3)
	check("roll_from_idle", pc.state == PlayerController.State.ROLL, "state=%s" % pc.get_state_name())
	release_all()
	await tick(secs(1.0))


## Hold inputs until a traverse of `kind` has started and finished (or timeout).
## Returns {saw, done, max_y, blocked}.
func wait_traverse(kind: String, timeout: float) -> Dictionary:
	var r := {"saw": false, "done": false, "max_y": -INF}
	for n in secs(timeout):
		await tick()
		r["max_y"] = maxf(r["max_y"], pc.global_position.y)
		if pc.get_state_name() == kind:
			r["saw"] = true
		elif r["saw"]:
			r["done"] = true
			break
	return r


func t_vault() -> void:
	# Jog at the 0.9 m wall and press jump ~1 m before it.
	await place(Vector3(L.VAULT_X, 0.02, L.VAULT_Z + 3.0))
	press("move_forward")
	await walk_until_z(L.VAULT_Z + 1.0, 2.0)
	press("jump")
	var r := await wait_traverse("VAULT", 1.5)
	release("jump")
	await tick(secs(0.6))
	release_all()
	await tick(secs(0.3))
	var beyond := pc.global_position.z < L.VAULT_Z - L.VAULT_T - 0.3
	check("vault_0.9", r["saw"] and r["done"] and beyond and pc.global_position.y < 0.05 and r["max_y"] < L.VAULT_H + 0.3 and pc.state == PlayerController.State.GROUND,
		"saw=%s z=%.2f y=%.3f max_y=%.2f state=%s" % [r["saw"], pc.global_position.z, pc.global_position.y, r["max_y"], pc.get_state_name()])
	# Sprinting vault, jump pressed ~1.5 m out (speed-scaled detection reach)
	await place(Vector3(L.VAULT_X + 0.8, 0.02, L.VAULT_Z + 8.0))
	press("move_forward"); press("sprint")
	await walk_until_z(L.VAULT_Z + 1.5, 3.0)
	var vs := pc.get_horizontal_speed()
	press("jump")
	var r2 := await wait_traverse("VAULT", 1.5)
	release_all()
	await tick(secs(0.8))
	check("vault_sprint", r2["saw"] and pc.global_position.z < L.VAULT_Z - 1.0 and pc.global_position.y < 0.05 and r2["max_y"] < L.VAULT_H + 0.3,
		"v_in=%.2f saw=%s z=%.2f max_y=%.2f" % [vs, r2["saw"], pc.global_position.z, r2["max_y"]])
	# Standing jump with no move input at the wall: no traverse (needs intent)
	await place(Vector3(L.VAULT_X, 0.02, L.VAULT_Z + 0.4))
	press("jump"); await tick(); release("jump")
	await tick(secs(1.0))
	check("vault_needs_input", pc.state == PlayerController.State.GROUND and pc.global_position.z > L.VAULT_Z, "z=%.2f state=%s" % [pc.global_position.z, pc.get_state_name()])


func t_mantle() -> void:
	await place(Vector3(L.MANTLE_X, 0.02, L.MANTLE_Z + 1.0))
	press("move_forward")
	await tick(secs(0.4))
	press("jump")
	var r := await wait_traverse("MANTLE", 2.0)
	release_all()
	await tick(secs(0.4))
	check("mantle_1.5", r["saw"] and r["done"] and absf(pc.global_position.y - L.MANTLE_H) < 0.03 and pc.state == PlayerController.State.GROUND and r["max_y"] < L.MANTLE_H + 0.15,
		"saw=%s y=%.3f max_y=%.3f state=%s" % [r["saw"], pc.global_position.y, r["max_y"], pc.get_state_name()])
	# Running jump into the 1.5 m box, holding jump -> ledge catch, ends on top
	await place(Vector3(L.MANTLE_X + 1.0, 0.02, L.MANTLE_Z + 4.0))
	press("move_forward")
	await tick(secs(0.6))
	press("jump"); await tick(); release("jump")
	await tick(secs(0.2))
	press("jump")
	var r2 := await wait_traverse("MANTLE", 1.5)
	release_all()
	await tick(secs(0.4))
	check("mantle_air_catch", r2["saw"] and absf(pc.global_position.y - L.MANTLE_H) < 0.03 and pc.state == PlayerController.State.GROUND,
		"saw=%s y=%.3f state=%s" % [r2["saw"], pc.global_position.y, pc.get_state_name()])


func t_tall_wall() -> void:
	await place(Vector3(L.TALL_X, 0.02, L.MANTLE_Z + 1.0))
	press("move_forward")
	await tick(secs(0.4))
	press("jump")
	var traversed := false
	for n in secs(1.5):
		await tick()
		if pc.state == PlayerController.State.TRAVERSE:
			traversed = true
	release_all()
	await tick(secs(0.5))
	check("tall_wall_rejected", not traversed and pc.global_position.y < 0.05, "traversed=%s y=%.3f" % [traversed, pc.global_position.y])


func t_landing() -> void:
	var tz := L.TOWER_Z0 - L.TOWER_TREAD * L.TOWER_TOP_STEPS - L.TOWER_LANDING * 1.5
	var mz := L.TOWER_Z0 - L.TOWER_TREAD * L.TOWER_MID_STEPS - L.TOWER_LANDING * 0.5
	for spec in [[2.0, mz, 1], [4.0, tz, 2]]:
		await place(Vector3(L.TOWER_X, spec[0] + 0.02, spec[1]), -PI / 2.0)
		var sev := [-1]
		var imp := [0.0]
		var cb := func(i: float, s: int) -> void:
			sev[0] = s
			imp[0] = i
		pc.landed.connect(cb)
		press("move_forward")
		await tick(secs(2.0))
		pc.landed.disconnect(cb)
		release_all()
		check("landing_%dm" % int(spec[0]), sev[0] == spec[2], "impact=%.2f m/s severity=%d expect=%d" % [imp[0], sev[0], spec[2]])
	# landing roll from 4 m: buffered roll converts hard landing
	await place(Vector3(L.TOWER_X, 4.02, tz), -PI / 2.0)
	press("move_forward")
	var n := 0
	while pc.state != PlayerController.State.AIR and n < secs(2.0):
		await tick(); n += 1
	await tick(secs(0.53))   # 4 m fall = 0.67 s: press ~0.15 s before touchdown
	press("roll"); await tick(); release("roll")
	var rolled := false
	for k in secs(0.6):
		await tick()
		if pc.state == PlayerController.State.ROLL:
			rolled = true
	release_all()
	check("landing_roll", rolled and pc.landing_recovery <= 0.0, "rolled=%s recovery=%.2f" % [rolled, pc.landing_recovery])


func t_crates() -> void:
	var light: RigidBody3D = main.get_node("Props/Crate2")
	var heavy: RigidBody3D = main.get_node("Props/Crate5")
	var lp0 := light.global_position
	await place(lp0 + Vector3(0, 0.02 - lp0.y, 2.0))
	press("move_forward")
	var max_y := 0.0
	var max_vy := 0.0
	for n in secs(2.0):
		await tick()
		max_y = maxf(max_y, pc.global_position.y)
		max_vy = maxf(max_vy, pc.velocity.y)
	release_all()
	var moved := light.global_position.distance_to(lp0)
	check("crate_push_light", moved > 0.5 and max_y < 0.3 and max_vy < 1.5, "crate moved=%.2fm player max_y=%.3f max_vy=%.2f" % [moved, max_y, max_vy])
	var hp0 := heavy.global_position
	await place(hp0 + Vector3(0, 0.02 - hp0.y, 2.0))
	press("move_forward")
	for n in secs(2.0):
		await tick()
	release_all()
	var hmoved := heavy.global_position.distance_to(hp0)
	check("crate_heavy_resists", hmoved < moved * 0.6 and pc.global_position.y < 0.1, "heavy moved=%.2fm" % hmoved)


func t_camera() -> void:
	# Camera must never end up inside world geometry, near walls / pillars / overhang.
	var space := pc.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = 1
	var bad := 0
	var samples := 0
	var co := L.CAM_ORIGIN
	var routes := [[co + Vector3(0, 0.02, 4), 0.0], [co + Vector3(6.95, 0.02, -2), 0.0], [Vector3(L.CORRIDOR_X, 0.02, L.CORRIDOR_Z0 + 1), 0.0], [Vector3(L.TALL_X, 0.02, L.MANTLE_Z + 0.6), PI]]
	for r in routes:
		await place(r[0], r[1])
		press("move_forward")
		for n in secs(2.5):
			await tick()
			rig.add_look(deg_to_rad(90.0) / hz, 0.0)
			rig.update_rig(1.0 / hz)
			q.position = rig.get_camera().global_position
			samples += 1
			if not space.intersect_point(q, 1).is_empty():
				bad += 1
				if bad <= 5:
					print("INFO|cam_inside route=%s cam=%s player=%s" % [routes.find(r), q.position, pc.global_position])
		release_all()
	check("camera_never_inside_geometry", bad == 0, "inside=%d / %d samples" % [bad, samples])
	# Camera / view jitter while standing still: zero.
	await place(Vector3(0, 0.02, 4))
	await tick(secs(0.5))
	var p0 := rig.get_camera().global_position
	var maxd := 0.0
	for n in secs(1.0):
		await tick()
		rig.update_rig(1.0 / hz)
		maxd = maxf(maxd, rig.get_camera().global_position.distance_to(p0))
	check("camera_idle_stable", maxd < 0.002, "max drift=%.5f" % maxd)


func t_fuzz() -> void:
	# Random input mash for 60 s across the course: no NaN, no launch, no fall-through,
	# no stuck state.
	seed(1234)
	var spots := [Vector3(0, 0.02, 4), Vector3(L.STAIR_X, 0.02, -2.5), Vector3(L.ramp_x(2), 0.02, -2.5),
		Vector3(L.TUNNEL_X, 0.02, -4), Vector3(L.VAULT_X, 0.02, -4), Vector3(L.TOWER_X, 0.02, -3), L.CAM_ORIGIN + Vector3(0, 0.02, 2), L.CRATE_ORIGIN + Vector3(0, 0.02, 2)]
	var max_vy := 0.0
	var min_y := 99.0
	var nan := false
	var state_ticks := {}
	var max_state_run := 0
	var run := 0
	var last_state := -1
	var issues := []
	for sp in spots:
		await place(sp, randf_range(-PI, PI))
		for n in secs(7.5):
			if n % secs(0.25) == 0:
				release_all()
				for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch"]:
					if randf() < 0.3:
						press(a)
				for a in ["jump", "roll", "crouch_toggle"]:
					if randf() < 0.15:
						press(a)
				rig.yaw += randf_range(-0.6, 0.6)
			await tick()
			var p := pc.global_position
			if is_nan(p.x) or is_nan(p.y) or is_nan(pc.velocity.y):
				nan = true
			if pc.velocity.y > 5.0 and issues.size() < 8:
				issues.append("vy=%.2f st=%s pos=%s spot=%d n=%d" % [pc.velocity.y, pc.get_state_name(), p, spots.find(sp), n])
			max_vy = maxf(max_vy, pc.velocity.y)
			min_y = minf(min_y, p.y)
			if pc.state == last_state and pc.state != PlayerController.State.GROUND and pc.state != PlayerController.State.AIR:
				run += 1
			else:
				run = 0
			last_state = pc.state
			max_state_run = maxi(max_state_run, run)
	release_all()
	var max_run_s := float(max_state_run) / hz
	check("fuzz_no_nan", not nan)
	check("fuzz_no_launch", max_vy < 6.0, "max vy=%.2f %s" % [max_vy, issues])
	check("fuzz_no_fall_through", min_y > -0.05, "min y=%.3f" % min_y)
	check("fuzz_no_stuck_action_state", max_run_s < 4.5, "longest SLIDE/ROLL/TRAVERSE run=%.2fs" % max_run_s)


# ------------------------------------------------------------ animation ---
## Skeletal presentation layer: tree active, no T-pose, state mapping,
## speed-matched playback (planted-foot slip), feet on the floor.
var _anim: Node
var _sk: Skeleton3D


func _bone_world(n: String) -> Vector3:
	# final rendered pose (after lean/warp/IK modifiers), see CharacterAnimator
	return _anim.get_final_bone_world(n)


func _not_tpose() -> bool:
	# A/T-pose = arms straight out: hands ~1.4 m apart at shoulder height.
	var hl := _bone_world("hand_l")
	var hr := _bone_world("hand_r")
	var sh := _bone_world("upperarm_l")
	return hl.distance_to(hr) < 1.25 and minf(hl.y, hr.y) < sh.y - 0.15


func _wait_anim(st: String, timeout: float) -> bool:
	for n in secs(timeout):
		await tick()
		if _anim.anim_state == st:
			return true
	return false


## Samples the final rendered pose while the controller is in TRAVERSE.
## Obstacle: top at `top_y`, front face at z `z_face`, back face at `z_back`
## (the course approaches along -Z). Returns the closest hand-to-top-edge
## distance, how many ticks a hand was within 8 cm, and the deepest a foot
## (ankle or ball bone) got inside the obstacle volume.
func _traverse_contact(top_y: float, z_face: float, z_back: float) -> Dictionary:
	var best := INF
	var close := 0
	var pen := 0.0
	for n in secs(2.0):
		if pc.state != PlayerController.State.TRAVERSE:
			break
		var near := false
		for h in ["hand_l", "hand_r"]:
			var p := _bone_world(h)
			var q := Vector3(p.x, top_y, clampf(p.z, z_back, z_face))
			var d := p.distance_to(q)
			best = minf(best, d)
			near = near or d < 0.08
		if near:
			close += 1
		for f in ["foot_l", "foot_r", "ball_l", "ball_r"]:
			var p := _bone_world(f)
			if p.z < z_face and p.z > z_back and p.y < top_y:
				pen = maxf(pen, minf(top_y - p.y, minf(z_face - p.z, p.z - z_back)))
		await tick()
	return {"hand": best, "hand_frames": close, "pen": pen}


func t_anim() -> void:
	_anim = pc.get_node("Model")
	_sk = _anim.skeleton if _anim else null
	var tree: AnimationTree = _anim.anim_tree if _anim else null
	check("anim_setup", _sk != null and _sk.get_bone_count() == 65 and tree != null and tree.active and _anim.anim_player.has_animation("jog"),
		"bones=%d active=%s" % [_sk.get_bone_count() if _sk else -1, tree.active if tree else false])
	# idle
	await place(Vector3(0, 0.02, 4))
	await tick(secs(0.6))
	var d: Dictionary = _anim.get_anim_debug()
	var foot_y := minf(_bone_world("ball_l").y, _bone_world("ball_r").y) - pc.global_position.y
	metric("anim_idle_foot_y", foot_y)
	check("anim_idle", d["anim_state"] == "ground" and d["sm_node"] == "ground" and _not_tpose() and absf(foot_y) < 0.04,
		"state=%s node=%s foot_y=%.3f tpose=%s" % [d["anim_state"], d["sm_node"], foot_y, not _not_tpose()])
	# steady locomotion: planted-foot slip in world space
	for spec in [["walk", 1.8], ["jog", 4.2], ["sprint", 6.8]]:
		await place(Vector3(4, 0.02, 20))
		press("move_forward")
		if spec[0] == "walk":
			press("walk_toggle"); await tick(); release("walk_toggle")
		if spec[0] == "sprint":
			press("sprint")
		await tick(secs(1.4))
		var prev := {}
		var slips: Array[float] = []
		var fwd_slip := 0.0
		var tpose_ok := true
		var min_fy := INF
		for n in secs(1.2):
			await tick()
			var floor_y := pc.global_position.y
			var lo := ""
			var lo_y := INF
			for b in ["ball_l", "ball_r"]:
				var p := _bone_world(b)
				if p.y < lo_y:
					lo_y = p.y
					lo = b
			for b in ["ball_l", "ball_r"]:
				var p := _bone_world(b)
				if prev.has(b) and b == lo and p.y - floor_y < 0.035:
					slips.append(Vector2(p.x - prev[b].x, p.z - prev[b].z).length() * hz)
					fwd_slip += -(p.z - prev[b].z) * hz
				prev[b] = p
			min_fy = minf(min_fy, lo_y - floor_y)
			if not _not_tpose():
				tpose_ok = false
		slips.sort()
		var med := slips[slips.size() / 2] if slips.size() > 0 else -1.0
		d = _anim.get_anim_debug()
		metric("anim_%s_slip_med" % spec[0], med)
		metric("anim_%s_min_foot_y" % spec[0], min_fy)
		metric("anim_%s_slip_drift" % spec[0], fwd_slip / maxf(slips.size(), 1))
		var fwd_mean := fwd_slip / maxf(slips.size(), 1)
		# Guard: planted foot speed stays a small fraction of body speed and
		# has no systematic drift (playback rate matches ground speed).
		check("anim_%s" % spec[0], d["anim_state"] == "ground" and tpose_ok and slips.size() > 10 and med < 0.25 * spec[1] + 0.2 and absf(fwd_mean) < 0.35 and min_fy > -0.05 and min_fy < 0.05,
			"v=%.2f gait=%.2f style=%.2f rate=%.2f slip_med=%.2fm/s drift=%.2fm/s n=%d min_foot_y=%.3f" % [pc.get_horizontal_speed(), d["gait"], d["run_style"], d["cycle_rate"], med, fwd_mean, slips.size(), min_fy])
		release_all()
		if spec[0] == "walk":
			press("walk_toggle"); await tick(); release("walk_toggle")
	# jump -> air -> land
	await place(Vector3(0, 0.02, 4))
	press("jump"); await tick(); release("jump")
	await tick(2)
	var saw_jump: bool = _anim.anim_state == "jump"
	var saw_air := await _wait_anim("air", 1.0)
	var saw_ground := await _wait_anim("ground", 2.0)
	await tick(2)
	var lw: float = _anim.land_weight
	check("anim_jump_air_land", saw_jump and saw_air and saw_ground and lw > 0.05, "jump=%s air=%s ground=%s land_w=%.2f" % [saw_jump, saw_air, saw_ground, lw])
	# slide
	await place(Vector3(4, 0.02, 20))
	press("move_forward"); press("sprint")
	await tick(secs(1.5))
	press("crouch_toggle"); await tick(); release("crouch_toggle")
	var saw_slide := await _wait_anim("slide", 0.3)
	await tick(secs(0.4))
	var pelvis_low := _bone_world("pelvis").y - pc.global_position.y
	release_all()
	await tick(secs(1.5))
	check("anim_slide", saw_slide and pelvis_low < 0.5, "slide=%s pelvis_h=%.2f" % [saw_slide, pelvis_low])
	# roll: pose comes from the clip, the Model node itself never rotates off-axis
	await place(Vector3(-4, 0.02, 20))
	press("move_forward")
	await tick(secs(0.8))
	press("roll"); await tick(); release("roll")
	var saw_roll := await _wait_anim("roll", 0.2)
	var max_tilt := 0.0
	var min_head := INF
	for n in secs(0.6):
		await tick()
		max_tilt = maxf(max_tilt, absf(_anim.rotation.x) + absf(_anim.rotation.z))
		min_head = minf(min_head, _bone_world("Head").y - pc.global_position.y)
	release_all()
	check("anim_roll", saw_roll and max_tilt < 0.001 and min_head < 0.9, "roll=%s model_tilt=%.3f min_head_h=%.2f" % [saw_roll, max_tilt, min_head])
	# vault + mantle map to their own states
	await place(Vector3(L.VAULT_X, 0.02, L.VAULT_Z + 3.0))
	press("move_forward")
	await walk_until_z(L.VAULT_Z + 1.0, 2.0)
	press("jump")
	var saw_vault := await _wait_anim("vault", 1.0)
	# contact: hands come down onto the wall top, feet never inside the wall
	var v := await _traverse_contact(L.VAULT_H, L.VAULT_Z, L.VAULT_Z - L.VAULT_T)
	release_all()
	await tick(secs(1.0))
	check("anim_vault_contact", v["hand"] < 0.12 and v["pen"] < 0.04,
		"closest hand-to-wall-top=%.3f m  max foot penetration=%.3f m" % [v["hand"], v["pen"]])
	await place(Vector3(L.MANTLE_X, 0.02, L.MANTLE_Z + 1.0))
	press("move_forward")
	await tick(secs(0.4))
	press("jump")
	var saw_mantle := await _wait_anim("mantle", 1.0)
	var m := await _traverse_contact(L.MANTLE_H, L.MANTLE_Z, L.MANTLE_Z - 3.0)
	release_all()
	await tick(secs(0.8))
	check("anim_mantle_contact", m["hand"] < 0.08 and m["hand_frames"] >= secs(0.15) and m["pen"] < 0.04,
		"closest hand-to-ledge=%.3f m  frames within 8 cm=%d  max foot penetration=%.3f m" % [m["hand"], m["hand_frames"], m["pen"]])
	check("anim_traverse_states", saw_vault and saw_mantle and _anim.anim_state == "ground", "vault=%s mantle=%s end=%s" % [saw_vault, saw_mantle, _anim.anim_state])

