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
		if _pop_on:
			_pop_sample()


## Round 4 "pop" probe: per rendered frame, world positions of the main body
## points; the largest second difference |x[n+1]-2x[n]+x[n-1]| is a sudden
## position/velocity step. A true teleport of D metres gives ~D at any rate;
## smooth motion gives ~a/hz^2. Reported as the velocity jump (2nd diff * hz).
const POP_BONES := ["pelvis", "Head", "hand_l", "hand_r", "foot_l", "foot_r", "calf_l", "calf_r"]
var _pop_on := false
var _pop_hist: Array = []
var _pop_max := 0.0
var _pop_bone := ""


func _pop_begin() -> void:
	_pop_on = true
	_pop_hist = []
	_pop_max = 0.0
	_pop_bone = ""


func _pop_sample() -> void:
	var cur := {}
	for b in POP_BONES:
		cur[b] = _bone_world(b)
	_pop_hist.append(cur)
	if _pop_hist.size() > 3:
		_pop_hist.pop_front()
	if _pop_hist.size() == 3:
		for b in POP_BONES:
			var d2: Vector3 = _pop_hist[2][b] - 2.0 * _pop_hist[1][b] + _pop_hist[0][b]
			if d2.length() > _pop_max:
				_pop_max = d2.length()
				_pop_bone = b


func _pop_end() -> Dictionary:
	_pop_on = false
	return {"d2": _pop_max, "vjump": _pop_max * hz, "bone": _pop_bone}


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


const EXPECTED_TOTAL := 105


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
	# guard: a script parse error silently skips whole test groups (they then
	# report nothing) -- a full run must report exactly EXPECTED_TOTAL results
	if only == "" and passes + fails != EXPECTED_TOTAL:
		print("RESULT|FAIL|runner_total|expected %d results, got %d (script error?)" % [EXPECTED_TOTAL, passes + fails])
		fails += 1
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


func _rollprobe(st: Dictionary, tag: String) -> void:
	if _anim == null:
		_anim = pc.get_node("Model")
	var xf := pc.global_transform
	var parts := []
	for b in ["pelvis", "Head", "ball_l", "ball_r", "hand_l", "hand_r"]:
		var w := _bone_world(b)
		var l := xf.affine_inverse() * w
		var d: float = (l - (st[b] as Vector3)).length() if st.has(b) else 0.0
		st[b] = l
		parts.append("%s=%.3f" % [b, d])
	var sole := minf(_bone_world("ball_l").y, _bone_world("ball_r").y) - 0.024 - pc.global_position.y
	print("RP %s st=%s rt=%.3f sole=%.3f %s" % [tag, pc.get_state_name(), pc.roll_time, sole, " ".join(parts)])


func t_roll() -> void:
	await place(Vector3(-4, 0.02, 20))
	press("move_forward")
	await tick(secs(1.0))
	var _rp := {}
	if OS.has_environment("ROLLPROBE"):
		for n0 in secs(0.15):
			await tick()
			_rollprobe(_rp, "pre")
	press("roll"); await tick(); release("roll")
	if OS.has_environment("ROLLPROBE"):
		_rollprobe(_rp, "R")
		for n0 in secs(0.7):
			await tick()
			_rollprobe(_rp, "R")
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
	var max_tilt := 0.0
	var am: Node = pc.get_node("Model")
	var push_n := 0
	var push_anim := 0.0
	var push_vel := 0.0
	var push_disp := 0.0
	for n in secs(2.0):
		var pp := pc.global_position
		await tick()
		if pc.is_pushing and n > secs(1.2):
			push_n += 1
			push_anim += float(am.p_speed)
			push_vel += Vector2(pc.velocity.x, pc.velocity.z).length()
			push_disp += Vector2(pc.global_position.x - pp.x, pc.global_position.z - pp.z).length() * Engine.physics_ticks_per_second
		max_y = maxf(max_y, pc.global_position.y)
		max_vy = maxf(max_vy, pc.velocity.y)
		max_tilt = maxf(max_tilt, rad_to_deg(light.global_basis.y.angle_to(Vector3.UP)))
	release_all()
	var moved := light.global_position.distance_to(lp0)
	check("crate_push_light", moved > 0.5 and max_y < 0.3 and max_vy < 1.5, "crate moved=%.2fm player max_y=%.3f max_vy=%.2f" % [moved, max_y, max_vy])
	# Round 5: the push must slide the crate (not tumble it) by the same
	# distance at every tick rate. Walk 2 m at 4.2 m/s then push at
	# push_speed_max (2 m/s) for the rest of 2 s -> ~3.1 m; was
	# 3.45/3.40/2.31 m at 30/60/120 Hz with the crate tumbling at 30/60.
	check("crate_push_rate_independent", absf(moved - 3.12) < 0.15 and max_tilt < 5.0, "crate moved=%.2fm (want 3.12+-0.15) max tilt=%.1f deg" % [moved, max_tilt])
	# Round 6: while pushing, move_and_slide clips velocity to ~0 though the
	# body moves with the crate; the animator must use the real displacement
	# (was: idle pose sliding along at ~2 m/s).
	var pn := maxf(push_n, 1)
	metric("crate_push_anim_speed", push_anim / pn)
	metric("crate_push_body_speed", push_disp / pn)
	metric("crate_push_clipped_vel", push_vel / pn)
	check("crate_push_anim_walks", push_n > 5 and absf(push_anim / pn - push_disp / pn) < 0.35 and push_anim / pn > 1.2, "pushing ticks=%d anim speed=%.2f body speed=%.2f (clipped velocity %.2f)" % [push_n, push_anim / pn, push_disp / pn, push_vel / pn])
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
	var hpen := 0.0
	var planted_err := 0.0
	var raise := -INF
	for n in secs(2.0):
		if pc.state != PlayerController.State.TRAVERSE:
			break
		# round 5: released hands during the stand-up (u >= 0.75) -- height
		# of the wrist above its shoulder (>0 = arm swinging up by the head)
		if _anim.get_traverse_progress() >= 0.75:
			raise = maxf(raise, _arm_raise(true))
		var near := false
		for h in ["hand_l", "hand_r"]:
			var p := _bone_world(h)
			var q := Vector3(p.x, top_y, clampf(p.z, z_back, z_face))
			var d := p.distance_to(q)
			best = minf(best, d)
			near = near or d < 0.08
			# wrist joint inside the obstacle (palm is ~3 cm under the wrist)
			if p.z < z_face and p.z > z_back and p.y < top_y + 0.03:
				hpen = maxf(hpen, minf(top_y + 0.03 - p.y, minf(z_face - p.z, p.z - z_back)))
			if _anim.hand_contact[0 if h == "hand_l" else 1]:
				planted_err = maxf(planted_err, absf(p.y - top_y - 0.03))
		if near:
			close += 1
		for f in ClipSampler.SOLE:
			# SOLE point (joint minus sole depth), not the joint: a joint 2 cm
			# above the top can still have the shoe 0.5-7 cm inside it
			var p := _bone_world(f) - Vector3(0, ClipSampler.SOLE[f], 0)
			if p.z < z_face and p.z > z_back and p.y < top_y:
				pen = maxf(pen, minf(top_y - p.y, minf(z_face - p.z, p.z - z_back)))
		if OS.has_environment("TRACE_TRAVERSE"):
			var pl := "POP %.3f" % _anim.get_traverse_progress()
			var cg: Vector3 = pc.global_position; var mg: Vector3 = _anim.global_position
			pl += " cap %.4f %.4f %.4f model %.4f %.4f %.4f" % [cg.x, cg.y, cg.z, mg.x, mg.y, mg.z]
			for b in ["pelvis", "Head", "hand_l", "hand_r", "foot_l", "foot_r", "calf_l", "calf_r", "spine_03"]:
				var bw := _bone_world(b)
				pl += " %s %.4f %.4f %.4f" % [b, bw.x, bw.y, bw.z]
			print(pl)
			var hl := _bone_world("hand_l"); var hr := _bone_world("hand_r")
			var fl := _bone_world("foot_l"); var fr := _bone_world("foot_r")
			var bl := _bone_world("ball_l"); var br := _bone_world("ball_r")
			print("TR u=%.2f ct=%.3f hl=(%.2f %.3f %.2f) hr=(%.2f %.3f %.2f) fl=(%.2f %.2f) fr=(%.2f %.2f) bl=(%.2f %.2f) br=(%.2f %.2f) cap=(%.2f %.2f) w=%.2f/%.2f" % [
				_anim.get_traverse_progress(), _anim._tr_clip_t, hl.x, hl.y - top_y, hl.z, hr.x, hr.y - top_y, hr.z,
				fl.y - top_y, fl.z, fr.y - top_y, fr.z, bl.y - top_y, bl.z, br.y - top_y, br.z, pc.global_position.y, pc.global_position.z, _anim.hand_w[0], _anim.hand_w[1]])
		await tick()
	return {"hand": best, "hand_frames": close, "pen": pen, "hpen": hpen, "planted_err": planted_err, "raise": raise}


## Highest wrist-above-own-shoulder of the hands not planted (m).
func _arm_raise(skip_planted: bool) -> float:
	var r := -INF
	for i in 2:
		if skip_planted and _anim.hand_contact[i]:
			continue
		var sd := "l" if i == 0 else "r"
		r = maxf(r, _bone_world("hand_" + sd).y - _bone_world("upperarm_" + sd).y)
	if OS.has_environment("ARM_DEBUG"):
		print("ARM u=%.2f st=%s raise=%.3f hl=%.3f hr=%.3f" % [_anim.get_traverse_progress(), pc.get_state_name(), r, _bone_world("hand_l").y - _bone_world("upperarm_l").y, _bone_world("hand_r").y - _bone_world("upperarm_r").y])
	return r


## Per tick while GROUND: sole clearance of the LOWER foot over the real
## ground under it (down raycasts at ball and ankle). gap<0 = penetration.
func _terrain_feet(n: int) -> Dictionary:
	var space := pc.get_world_3d().direct_space_state
	var gaps: Array = []
	var pen := 0.0
	var max_y := 0.0
	for k in n:
		await tick()
		max_y = maxf(max_y, pc.global_position.y)
		if pc.state != PlayerController.State.GROUND:
			continue
		var lo := INF
		for sd in ["l", "r"]:
			var foot_gap := INF
			for spec in [["ball_", 0.024], ["foot_", 0.093]]:
				var p := _bone_world(spec[0] + sd)
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 1.0, pc.collision_mask, [pc.get_rid()])
				var h := space.intersect_ray(q)
				if h:
					var gp: float = p.y - (h["position"] as Vector3).y - spec[1]
					foot_gap = minf(foot_gap, gp)
					pen = maxf(pen, -gp)
			lo = minf(lo, foot_gap)
		if lo < INF:
			gaps.append(lo)
	return {"gaps": gaps, "pen": pen, "max_y": max_y}


func t_anim() -> void:
	_anim = pc.get_node("Model")
	if OS.has_environment("FOOTIK_OFF"):
		_anim.foot_ik_enabled = false
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
		var p90 := slips[int(slips.size() * 0.9)] if slips.size() > 0 else -1.0
		metric("anim_%s_slip_p90" % spec[0], p90)
		d = _anim.get_anim_debug()
		metric("anim_%s_slip_med" % spec[0], med)
		metric("anim_%s_min_foot_y" % spec[0], min_fy)
		metric("anim_%s_slip_drift" % spec[0], fwd_slip / maxf(slips.size(), 1))
		var fwd_mean := fwd_slip / maxf(slips.size(), 1)
		# Guard: planted foot speed stays a small fraction of body speed and
		# has no systematic drift (playback rate matches ground speed).
		# Round 3 (foot locking): planted-foot median slip < 10 % of body speed,
		# no systematic drift, and the sole never below the floor
		# (ball joint sits 0.024 m above the sole: min_foot_y >= 0.024 - 0.01).
		check("anim_%s" % spec[0], d["anim_state"] == "ground" and tpose_ok and slips.size() > 10 and med < 0.1 * spec[1] and absf(fwd_mean) < 0.15 * spec[1] and min_fy > 0.014 and min_fy < 0.06,
			"v=%.2f gait=%.2f style=%.2f rate=%.2f slip_med=%.3fm/s (%.1f%% of v) p90=%.2fm/s drift=%.2fm/s n=%d min_foot_y=%.3f" % [pc.get_horizontal_speed(), d["gait"], d["run_style"], d["cycle_rate"], med, 100.0 * med / spec[1], p90, fwd_mean, slips.size(), min_fy])
		release_all()
		if spec[0] == "walk":
			press("walk_toggle"); await tick(); release("walk_toggle")
	# start / stop transitions: idle -> walk/jog -> idle. Foot locks must not
	# break (a break = the pinned foot visibly slides back to the clip pose)
	# and planted feet must not skate while the body accelerates/brakes.
	for spec in [["walk", true], ["jog", false]]:
		await place(Vector3(4, 0.02, 20))
		await tick(secs(0.6))
		var fk = _anim.foot_ik
		var breaks := [0, 0]
		var slips: Array[float] = []
		var prev := {}
		for phase in 2:
			if phase == 0:
				press("move_forward")
				if spec[1]:
					press("walk_toggle"); await tick(); release("walk_toggle")
			else:
				release("move_forward")
			for n in secs(1.2):
				var was_cd: Array = fk.cooldown.duplicate()
				await tick()
				for k in 2:
					if fk.cooldown[k] and not was_cd[k]:
						breaks[phase] += 1
				var floor_y := pc.global_position.y
				var lo := ""
				var lo_y := INF
				for b in ["ball_l", "ball_r"]:
					var bp := _bone_world(b)
					if bp.y < lo_y:
						lo_y = bp.y
						lo = b
				for b in ["ball_l", "ball_r"]:
					var bp := _bone_world(b)
					if prev.has(b) and b == lo and bp.y - floor_y < 0.035:
						slips.append(Vector2(bp.x - prev[b].x, bp.z - prev[b].z).length() * hz)
					prev[b] = bp
		release_all()
		if spec[1]:
			press("walk_toggle"); await tick(); release("walk_toggle")
		slips.sort()
		var med := slips[slips.size() / 2] if slips.size() > 0 else -1.0
		var p90 := slips[int(slips.size() * 0.9)] if slips.size() > 0 else -1.0
		metric("anim_startstop_%s_breaks" % spec[0], breaks[0] + breaks[1])
		metric("anim_startstop_%s_slip_p90" % spec[0], p90)
		check("anim_startstop_%s" % spec[0], breaks[0] + breaks[1] == 0 and med < 0.05 and p90 < 0.5,
			"lock breaks start=%d stop=%d  planted slip med=%.3f p90=%.2f m/s n=%d" % [breaks[0], breaks[1], med, p90, slips.size()])
	# turn in place (aimed, standing): the camera swings 90 / 180 deg and the
	# body follows at the aim turn rate. The feet must step around (settle
	# steps), never visibly snap back (lock break), and planted balls must
	# not skate; afterwards both feet are back near the idle pose (< 6 cm:
	# offsets under the 5 cm settle threshold are kept on purpose, no micro-steps).
	for spec in [["90", 90.0], ["180", 180.0]]:
		await place(Vector3(4, 0.02, 20))
		press("aim")
		await tick(secs(0.6))
		var fk = _anim.foot_ik
		var breaks := 0
		var prev := {}
		var slips: Array[float] = []
		var steps := 0
		rig.yaw = wrapf(rig.yaw + deg_to_rad(spec[1]) * (1.0 if spec[1] < 179.0 else 0.999), -PI, PI)
		var t_done := -1.0
		for n in secs(2.0):
			var was_cd: Array = fk.cooldown.duplicate()
			var was_sh: Array = fk.swing_hold.duplicate()
			await tick()
			for k in 2:
				if fk.cooldown[k] and not was_cd[k]:
					breaks += 1
				if fk.swing_hold[k] and not was_sh[k]:
					steps += 1
			if t_done < 0.0 and absf(wrapf(pc.facing_yaw - pc.get_camera_yaw(), -PI, PI)) < deg_to_rad(2.0):
				t_done = float(n + 1) / hz
			var floor_y := pc.global_position.y
			for b in ["ball_l", "ball_r"]:
				var bp := _bone_world(b)
				var k := 0 if b == "ball_l" else 1
				if prev.has(b) and fk.planted[k] and bp.y - floor_y < 0.035:
					slips.append(Vector2(bp.x - prev[b].x, bp.z - prev[b].z).length() * hz)
				prev[b] = bp
		var off_end := maxf(Vector2(fk.offset[0].x, fk.offset[0].z).length(), Vector2(fk.offset[1].x, fk.offset[1].z).length())
		release_all()
		slips.sort()
		var med: float = slips[slips.size() / 2] if slips.size() > 0 else 0.0
		var p90: float = slips[int(slips.size() * 0.9)] if slips.size() > 0 else 0.0
		metric("anim_turn%s_breaks" % spec[0], breaks)
		metric("anim_turn%s_steps" % spec[0], steps)
		metric("anim_turn%s_time_s" % spec[0], t_done)
		check("anim_turn_inplace_%s" % spec[0], breaks == 0 and t_done > 0.0 and med < 0.05 and p90 < 0.3 and off_end < 0.06,
			"t=%.2fs lock breaks=%d settle/swing steps=%d planted slip med=%.3f p90=%.2f m/s n=%d end offset=%.3f m" % [t_done, breaks, steps, med, p90, slips.size(), off_end])
	# feet on uneven ground: stairs up/down and a 20 deg ramp up/down
	for spec in [["stairs", Vector3(L.STAIR_X, 0.02, L.STAIR_Z0 + 1.5), 6.5], ["ramp20", Vector3(L.ramp_x(1), 0.02, L.RAMP_Z0 + 1.5), 5.0]]:
		await place(spec[1])
		press("move_forward")
		press("walk_toggle"); await tick(); release("walk_toggle")
		var g := await _terrain_feet(secs(spec[2] * 0.5))
		release_all()
		press("move_back")
		var g2 := await _terrain_feet(secs(spec[2] * 0.5))
		release_all()
		await tick()
		press("walk_toggle"); await tick(); release("walk_toggle")
		release_all()
		var pen := maxf(g["pen"], g2["pen"])
		var gaps: Array = g["gaps"] + g2["gaps"]
		gaps.sort()
		var fmed: float = gaps[gaps.size() / 2] if gaps.size() > 0 else 1.0
		var fp90: float = gaps[int(gaps.size() * 0.9)] if gaps.size() > 0 else 1.0
		metric("anim_%s_foot_pen" % spec[0], pen)
		metric("anim_%s_foot_gap_med" % spec[0], fmed)
		metric("anim_%s_foot_gap_p90" % spec[0], fp90)
		# p90 0.07: on stairs the clip stride (~0.65 m/step) spans two 0.30 m treads, so
		# a released trailing foot briefly hangs ~5-6 cm while it catches up (measured, documented)
		check("anim_feet_%s" % spec[0], gaps.size() > secs(1.0) and pen < 0.02 and fmed < 0.02 and fp90 < 0.07,
			"lowest-foot sole gap over ground: median=%.3f m p90=%.3f m  max penetration=%.3f m  n=%d max_y=%.2f" % [fmed, fp90, pen, gaps.size(), maxf(g["max_y"], g2["max_y"])])
	# aimed strafe / backpedal / diagonal: the body faces the camera and the
	# legs carry it in the movement direction. Shipping: BlendSpace2D over the
	# authored aim set (StrafeGait: CC0 fwd/bwd + cross-step side/diagonal
	# clips), legs face the camera (warp 0). AIM_WARP=1: the old
	# orientation-warp strafe (forward cycle yawed toward the movement).
	# Two passes:
	#  1. foot IK off -> "clip slip" (how well the clip itself matches the
	#     ground motion); gated < 10 % of speed for the authored side /
	#     diagonal clips (the CC0 fwd/bwd clips are reported only)
	#  2. foot IK on (shipping config): planted-ball slip < 10 % of speed, no
	#     drift, no lock breaks (visible pops), face error < 10 deg; aim set:
	#     warp < 5 deg and (strafe) the feet really cross (order along the
	#     movement swaps both ways by > 8 cm); AIM_WARP=1: legs pointing
	#     within 25 deg of the movement (or its reverse)
	var arm_fwd := {}   # aim_fwd hand swing ranges (reference for the strafe arms)
	for spec in [["aim_fwd", ["move_forward"]], ["strafe_left", ["move_left"]], ["strafe_right", ["move_right"]],
			["backpedal", ["move_back"]], ["diag_fl", ["move_forward", "move_left"]], ["diag_br", ["move_back", "move_right"]]]:
		var res := {}
		for pass_ik in [false, true]:
			await place(Vector3(4, 0.02, 20))
			_anim.foot_ik_enabled = pass_ik
			press("aim")
			await tick(secs(0.3))
			for a in spec[1]:
				press(a)
			await tick(secs(1.2))
			var fk = _anim.foot_ik
			var prev := {}
			var slips: Array[float] = []
			var drift := 0.0
			var pops := 0
			var max_face := 0.0
			var max_leg := 0.0
			var tp_ok := true
			var vs := 0.0
			var knee_lead := 0.0   # swing knee ahead of the hips along the legs' heading
			var max_warp := 0.0
			var cross_lo := INF   # (ball_l - ball_r) along the movement
			var cross_hi := -INF
			var n_s := secs(1.2)
			# hips vs chest yaw (counter-rotation) and step rhythm
			# (alternating touchdown times)
			var tw_lo := INF
			var tw_hi := -INF
			var hy_lo := INF
			var hy_hi := -INF
			var cy_lo := INF
			var cy_hi := -INF
			var lo_prev := ""
			var sw_t: Array[float] = []
			var up := {}
			var pel_min := INF
			var arm_r: Array[float] = [INF, -INF, INF, -INF, INF, -INF, INF, -INF]
			for n in n_s:
				var was_cd: Array = fk.cooldown.duplicate()
				await tick()
				pel_min = minf(pel_min, _bone_world("pelvis").y - pc.global_position.y)
				# hands vs the chest (shoulder-line frame): fore-aft / sideways swing
				var cl := _bone_world("clavicle_l")
				var cr := _bone_world("clavicle_r")
				var lft := (cl - cr) * Vector3(1, 0, 1)
				lft = lft.normalized()
				var fwd_c := lft.cross(Vector3.UP)
				var cm := (cl + cr) * 0.5
				for hi in 2:
					var hp := _bone_world(["hand_l", "hand_r"][hi]) - cm
					var fa := hp.dot(fwd_c)
					var la := hp.dot(lft)
					arm_r[hi * 4] = minf(arm_r[hi * 4], fa)
					arm_r[hi * 4 + 1] = maxf(arm_r[hi * 4 + 1], fa)
					arm_r[hi * 4 + 2] = minf(arm_r[hi * 4 + 2], la)
					arm_r[hi * 4 + 3] = maxf(arm_r[hi * 4 + 3], la)
				var hv := pc.velocity * Vector3(1, 0, 1)
				var mdir := hv.normalized()
				var floor_y := pc.global_position.y
				var lo := ""
				var lo_y := INF
				for b in ["ball_l", "ball_r"]:
					var bp := _bone_world(b)
					if bp.y < lo_y:
						lo_y = bp.y
						lo = b
				# touchdowns: a ball dropping below 3.5 cm after a swing (> 6 cm)
				for b in ["ball_l", "ball_r"]:
					var hh := _bone_world(b).y - floor_y
					if hh > 0.06:
						up[b] = true
					elif hh < 0.035 and up.get(b, false):
						up[b] = false
						if lo_prev != b:
							sw_t.append(float(n) / hz)
							lo_prev = b
				var pel_x := _bone_world("thigh_l") - _bone_world("thigh_r")
				var ch_x := _bone_world("clavicle_l") - _bone_world("clavicle_r")
				# yaw of the hip line / shoulder line vs the facing (body) yaw
				var fy_ := pc.facing_yaw
				var hy := rad_to_deg(wrapf(atan2(-pel_x.z, pel_x.x) + fy_ - PI, -PI, PI))
				var cy := rad_to_deg(wrapf(atan2(-ch_x.z, ch_x.x) + fy_ - PI, -PI, PI))
				var tw := cy - hy
				tw_lo = minf(tw_lo, tw)
				tw_hi = maxf(tw_hi, tw)
				hy_lo = minf(hy_lo, hy)
				hy_hi = maxf(hy_hi, hy)
				cy_lo = minf(cy_lo, cy)
				cy_hi = maxf(cy_hi, cy)
				for b in ["ball_l", "ball_r"]:
					var bp := _bone_world(b)
					if prev.has(b) and b == lo and bp.y - floor_y < 0.035:
						var dv: Vector3 = (bp - prev[b]) * hz
						slips.append(Vector2(dv.x, dv.z).length())
						drift += dv.dot(mdir)
					prev[b] = bp
				for k in 2:
					if fk.cooldown[k] and not was_cd[k]:
						pops += 1
				max_face = maxf(max_face, absf(rad_to_deg(wrapf(pc.facing_yaw - pc.get_camera_yaw(), -PI, PI))))
				# leg heading = facing + warp; compare with movement (mod 180 for reverse playback)
				if hv.length() > 0.5:
					var mv_yaw := atan2(-hv.x, -hv.z)
					var leg_yaw: float = pc.facing_yaw + _anim.warp_angle
					var e := absf(wrapf(mv_yaw - leg_yaw, -PI, PI))
					e = minf(e, PI - e)
					max_leg = maxf(max_leg, rad_to_deg(e))
					max_warp = maxf(max_warp, absf(rad_to_deg(_anim.warp_angle)))
					var dl := (_bone_world("ball_l") - _bone_world("ball_r")).dot(mdir)
					cross_lo = minf(cross_lo, dl)
					cross_hi = maxf(cross_hi, dl)
					var lf := Vector3(-sin(leg_yaw), 0, -cos(leg_yaw))
					var pel := _bone_world("pelvis")
					for sd in ["l", "r"]:
						if _bone_world("ball_" + sd).y - floor_y > 0.08:
							knee_lead = maxf(knee_lead, (_bone_world("calf_" + sd) - pel).dot(lf))
				vs += hv.length() / n_s
				if not _not_tpose():
					tp_ok = false
			release_all()
			await tick()
			slips.sort()
			var key := "ik_" if pass_ik else "fk_"
			res[key + "med"] = slips[slips.size() / 2] if slips.size() > 0 else -1.0
			res[key + "p90"] = slips[int(slips.size() * 0.9)] if slips.size() > 0 else -1.0
			res[key + "drift"] = drift / maxf(slips.size(), 1)
			res[key + "n"] = slips.size()
			if pass_ik:
				res["v"] = vs
				res["pops"] = pops
				res["face"] = max_face
				res["leg"] = max_leg
				res["tp"] = tp_ok
				res["knee_lead"] = knee_lead
				res["warp"] = max_warp
				res["cross"] = minf(-cross_lo, cross_hi)
				res["wide"] = maxf(-cross_lo, cross_hi)
				res["pel_min"] = pel_min
				res["arm_fa"] = 0.5 * ((arm_r[1] - arm_r[0]) + (arm_r[5] - arm_r[4]))
				res["arm_lat"] = 0.5 * ((arm_r[3] - arm_r[2]) + (arm_r[7] - arm_r[6]))
				res["twist"] = tw_hi - tw_lo
				res["hip_yaw"] = hy_hi - hy_lo
				res["chest_yaw"] = cy_hi - cy_lo
				# step rhythm: |L->R - R->L| touchdown intervals / their mean
				var ev := 0.0
				var od := 0.0
				var ne := 0
				var no := 0
				for i in range(1, sw_t.size()):
					if i % 2 == 0:
						ev += sw_t[i] - sw_t[i - 1]
						ne += 1
					else:
						od += sw_t[i] - sw_t[i - 1]
						no += 1
				res["asym"] = absf(ev / maxi(ne, 1) - od / maxi(no, 1)) / maxf(0.5 * (ev / maxi(ne, 1) + od / maxi(no, 1)), 1e-3) if ne > 0 and no > 0 else -1.0
				# cadence (steps per minute) from the mean touchdown interval
				res["cadence"] = 60.0 * (sw_t.size() - 1) / maxf(sw_t[-1] - sw_t[0], 1e-3) if sw_t.size() > 2 else -1.0
		_anim.foot_ik_enabled = true
		metric("anim_%s_clip_slip_med" % spec[0], res["fk_med"])
		metric("anim_%s_slip_med" % spec[0], res["ik_med"])
		metric("anim_%s_lock_pops" % spec[0], res["pops"])
		metric("anim_%s_leg_err_deg" % spec[0], res["leg"])
		metric("anim_%s_swing_knee_lead_m" % spec[0], res["knee_lead"])
		if res.has("cadence"):
			metric("anim_%s_cadence_spm" % spec[0], res["cadence"])
		if spec[0] == "backpedal":
			# authored backward gait (BackwardGait): damped reversed knee drive.
			# The plain reversed forward clip measures 0.36 m here (BWD_RAW=1);
			# the authored clip 0.29-0.31 m; the round 6 re-posed aim_bwd
			# (shorter steps, late low lift) 0.32-0.33 m. Round 7: most of that
			# was FootIK's swing-release arc lifting the toe-off foot while it
			# was still in FRONT of the hips (IK-off clip: ~0.14 m); the arc is
			# scaled down while backpedalling -> ~0.25 m. Gate 0.30 m.
			check("anim_backpedal_gait", res["knee_lead"] < 0.30, "max swing knee lead ahead of hips=%.2f m (raw reversed forward clip 0.36)" % res["knee_lead"])
		var aim_set: bool = _anim.has_aim_set
		var authored: bool = aim_set and spec[0] in ["aim_fwd", "strafe_left", "strafe_right", "backpedal", "diag_fl", "diag_br"]
		var is_strafe: bool = spec[0] in ["strafe_left", "strafe_right"]
		metric("anim_%s_warp_deg" % spec[0], res["warp"])
		if is_strafe:
			metric("anim_%s_cross_m" % spec[0], res["cross"])
		metric("anim_%s_stance_max_m" % spec[0], res["wide"])
		metric("anim_%s_pelvis_min_m" % spec[0], res.get("pel_min", -1.0))
		metric("anim_%s_hand_fore_aft_range_m" % spec[0], res.get("arm_fa", -1.0))
		metric("anim_%s_hand_side_range_m" % spec[0], res.get("arm_lat", -1.0))
		if spec[0] == "aim_fwd":
			arm_fwd = {"fa": res["arm_fa"], "lat": res["arm_lat"]}
		elif spec[0] in ["strafe_left", "strafe_right"] and _anim.has_aim_set and not arm_fwd.is_empty():
			# round 7: strafe-specific arms -- less fore-aft (walk) swing, more
			# sideways swing than the aimed forward gait's arms
			check("anim_%s_arms" % spec[0], res["arm_fa"] < 0.6 * arm_fwd["fa"] and res["arm_lat"] > 1.5 * arm_fwd["lat"],
				"hand swing fore-aft %.3f m (aim_fwd %.3f), sideways %.3f m (aim_fwd %.3f)" % [res["arm_fa"], arm_fwd["fa"], res["arm_lat"], arm_fwd["lat"]])
		metric("anim_%s_hip_chest_twist_deg" % spec[0], res["twist"])
		metric("anim_%s_hip_yaw_range_deg" % spec[0], res["hip_yaw"])
		metric("anim_%s_chest_yaw_range_deg" % spec[0], res["chest_yaw"])
		metric("anim_%s_step_asym" % spec[0], res["asym"])
		var leg_ok: bool = (res["warp"] < 5.0 and ((res["cross"] > 0.08 and res["wide"] < 1.0) or not is_strafe)) if aim_set else res["leg"] < 25.0
		var clip_ok: bool = res["fk_med"] < 0.1 * res["v"] if authored else true
		check("anim_%s" % spec[0], res["tp"] and res["ik_n"] > secs(0.3) and res["ik_med"] < 0.1 * res["v"] and absf(res["ik_drift"]) < 0.15 * res["v"] and res["pops"] == 0 and res["face"] < 10.0 and leg_ok and clip_ok,
			"%s v=%.2f IK on: slip med=%.3f m/s (%.0f%% of v) p90=%.2f drift=%.2f pops=%d face_err=%.1fdeg leg_err=%.0fdeg warp=%.1fdeg cross=%.2fm widest=%.2fm n=%d | IK off: clip slip med=%.2f (%.0f%%%s) drift=%.2f" % ["aim-set" if aim_set else "warp", res["v"], res["ik_med"], 100.0 * res["ik_med"] / maxf(res["v"], 0.01), res["ik_p90"], res["ik_drift"], res["pops"], res["face"], res["leg"], res["warp"], res["cross"], res["wide"], res["ik_n"], res["fk_med"], 100.0 * res["fk_med"] / maxf(res["v"], 0.01), ", gated" if authored else "", res["fk_drift"]])
	# aimed backpedal -> aimed forward switch (round 7): the round 6 showcase
	# showed a crouched frame at the reversal (the blend position snapped
	# to the opposite clip in one frame). Reference: the plain (un-aimed)
	# forward gait's lowest pelvis at its steady speed.
	await place(Vector3(4, 0.02, 20))
	_anim.foot_ik_enabled = true
	press("move_forward")
	await tick(secs(1.2))
	var ph_ref := INF
	var v_ref := pc.get_horizontal_speed()
	for n in secs(0.6):
		await tick()
		ph_ref = minf(ph_ref, _bone_world("pelvis").y - pc.global_position.y)
	release_all()
	await place(Vector3(4, 0.02, 20))
	press("aim")
	await tick(secs(0.3))
	press("move_back")
	await tick(secs(1.2))
	var ph_prev := _bone_world("pelvis").y - pc.global_position.y
	release("move_back"); press("move_forward")
	var ph_min := INF
	var t_min := 0.0
	var ph_jump := 0.0
	for n in secs(1.2):
		await tick()
		var ph := _bone_world("pelvis").y - pc.global_position.y
		if OS.has_environment("SWITCH_DEBUG"):
			print("SW n=%d ph=%.3f v=%.2f bp=%s" % [n, ph, pc.get_horizontal_speed(), str(_anim._aim_bp)])
		ph_jump = maxf(ph_jump, absf(ph - ph_prev) * hz / 60.0)   # per 1/60 s
		ph_prev = ph
		if ph < ph_min:
			ph_min = ph
			t_min = float(n) / hz
	var v_aim := pc.get_horizontal_speed()
	release_all()
	metric("anim_aim_switch_pelvis_min_m", ph_min)
	metric("anim_aim_switch_pelvis_step_m", ph_jump)
	metric("anim_fwd_ref_pelvis_min_m", ph_ref)
	check("anim_aim_switch_no_crouch", ph_jump < 0.05 and ph_min > ph_ref - 0.05,
		"backpedal->aim forward: max pelvis step %.3f m/frame(60Hz); pelvis min %.3f m at +%.2fs (v=%.1f) vs plain forward gait min %.3f m (v=%.1f)" % [ph_jump, ph_min, t_min, v_aim, ph_ref, v_ref])
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
	# "flying" = the lowest body contact point (soles, hands, head/shoulder/
	# pelvis surfaces) is off the floor: in a ground roll something touches
	# the floor all the time. Measured over the roll's first half (the dive).
	var max_float := 0.0
	var max_pelvis := 0.0
	# after the 0.10 s entry crossfade: pelvis peak and any RISE of the
	# pelvis after it has started down (a rise = the roll reads as a jump)
	var pel_post := 0.0
	var pel_min_so_far := INF
	var pel_rise := 0.0
	var rad := {"hand_l": 0.03, "hand_r": 0.03, "Head": 0.11, "upperarm_l": 0.07, "upperarm_r": 0.07, "spine_02": 0.12, "pelvis": 0.11,
		"ball_l": 0.024, "ball_r": 0.024, "foot_l": 0.093, "foot_r": 0.093}
	var head_prev := Vector3.INF
	var head_v_max := 0.0
	# "flat dive" = the body stretched out (head far from the feet) while the
	# trunk is pitched over (head not above the pelvis). A tucked roll keeps
	# the knees at the chest, so head-to-feet span stays short.
	var dive_span := 0.0
	for n in secs(0.6):
		await tick()
		max_tilt = maxf(max_tilt, absf(_anim.rotation.x) + absf(_anim.rotation.z))
		var fy := pc.global_position.y
		# head speed relative to the body (capsule frame): the entry crossfade
		# from the upright jog into the inverted roll pose must not flip
		var hl := pc.global_transform.affine_inverse() * _bone_world("Head")
		if pc.state == PlayerController.State.ROLL and head_prev != Vector3.INF:
			head_v_max = maxf(head_v_max, (hl - head_prev).length() * hz)
		head_prev = hl
		min_head = minf(min_head, _bone_world("Head").y - fy)
		if pc.state == PlayerController.State.ROLL and pc.roll_time < pc.roll_duration * 0.5:
			var low := INF
			var low_b := ""
			for b in rad:
				var hb: float = _bone_world(b).y - fy - rad[b]
				if hb < low:
					low = hb
					low_b = b
			max_float = maxf(max_float, low)
			if OS.has_environment("ROLL_DEBUG"):
				print("RF low=%s u=%.2f st=%.3f float=%.3f pelvis=%.2f head=%.2f drop=%.3f anim=%s clip_head=%.2f clip_pel=%.2f" % [low_b, pc.roll_time / pc.roll_duration, _anim._state_t, low, _bone_world("pelvis").y - fy, _bone_world("Head").y - fy, _anim._roll_drop_s, _anim.anim_state, _anim._cs_roll.at("Head", lerpf(_anim.ROLL_T0, _anim.ROLL_T1, pc.roll_time / pc.roll_duration)).y, _anim._cs_roll.at("pelvis", lerpf(_anim.ROLL_T0, _anim.ROLL_T1, pc.roll_time / pc.roll_duration)).y])
			var ph := _bone_world("pelvis").y - fy
			max_pelvis = maxf(max_pelvis, ph)
			if _anim._state_t >= 0.10:
				pel_post = maxf(pel_post, ph)
			pel_min_so_far = minf(pel_min_so_far, ph)
			pel_rise = maxf(pel_rise, ph - pel_min_so_far)
		if pc.state == PlayerController.State.ROLL and pc.roll_time < pc.roll_duration * 0.6:
			var hw := _bone_world("Head")
			if hw.y - _bone_world("pelvis").y < 0.3:
				var fm := (_bone_world("foot_l") + _bone_world("foot_r")) * 0.5
				dive_span = maxf(dive_span, hw.distance_to(fm))
	release_all()
	metric("anim_roll_float_max_m", max_float)
	metric("anim_roll_pelvis_max_m", max_pelvis)
	metric("anim_roll_pelvis_post_entry_max_m", pel_post)
	metric("anim_roll_pelvis_rise_m", pel_rise)
	metric("anim_roll_min_head_m", min_head)
	metric("anim_roll_head_v_max", head_v_max)
	metric("anim_roll_dive_span_m", dive_span)
	check("anim_roll", saw_roll and max_tilt < 0.001 and min_head < 0.9 and min_head > 0.0 and max_float < 0.2 and head_v_max < 25.0 and dive_span < 1.25 and pel_post <= 0.55 and pel_rise < 0.05,
		"roll=%s model_tilt=%.3f min_head_h=%.2f dive: lowest contact off floor max=%.3f m pelvis max=%.2f m (after entry crossfade %.2f m, rise %.3f m)  head speed in body frame max=%.1f m/s  pitched head-feet span max=%.2f m" % [saw_roll, max_tilt, min_head, max_float, max_pelvis, pel_post, pel_rise, head_v_max, dive_span])
	# round 4: 180 deg sharp turn at jog speed -- legs must not cross
	# (feet / knees measured along the hip axis thigh_l->thigh_r; <0 = crossed)
	await place(Vector3(0, 0.02, 14))
	press("move_forward")
	await tick(secs(1.2))
	release("move_forward"); press("move_back")
	var tmin_foot := INF
	var tmin_knee := INF
	var tmax_fyaw := 0.0
	var tmax_valgus := -INF
	for n in secs(1.0):
		await tick()
		var hl := _bone_world("thigh_l"); var hr := _bone_world("thigh_r")
		var ax := (hr - hl); ax.y = 0.0
		if ax.length() < 0.01:
			continue
		ax = ax.normalized()
		var fsep := (_bone_world("foot_r") - _bone_world("foot_l")).dot(ax)
		var ksep := (_bone_world("calf_r") - _bone_world("calf_l")).dot(ax)
		var bfw := Vector3.UP.cross(ax)
		var fyaw := 0.0
		for sd in ["l", "r"]:
			var fv := _bone_world("ball_" + sd) - _bone_world("foot_" + sd); fv.y = 0.0
			if fv.length() > 0.1:   # flat-ish foot only (a pointed swing foot has no yaw)
				fyaw = maxf(fyaw, rad_to_deg(bfw.angle_to(fv.normalized())))
		tmax_fyaw = maxf(tmax_fyaw, fyaw)
		# knee valgus: knee inside the hip->ankle line (m, >0 = knock-kneed)
		var kin := -INF
		for sd in [["l", -1.0], ["r", 1.0]]:
			var T := _bone_world("thigh_" + sd[0]); var K := _bone_world("calf_" + sd[0]); var A := _bone_world("foot_" + sd[0])
			var u := (A - T).normalized()
			var outp: Vector3 = ax * float(sd[1]); outp = (outp - u * outp.dot(u)).normalized()
			var kp := K - T; kp -= u * kp.dot(u)
			kin = maxf(kin, -kp.dot(outp))
		tmax_valgus = maxf(tmax_valgus, kin)
		tmin_foot = minf(tmin_foot, fsep)
		tmin_knee = minf(tmin_knee, ksep)
		if OS.has_environment("TRACE_TURN"):
			var dd: Dictionary = _anim.get_anim_debug()
			print("TURN %d kin=%.3f fyaw=%.0f fsep=%.3f ksep=%.3f warp=%.0f yaw=%.0f v=%.2f back=%s" % [n, kin, fyaw, fsep, ksep, dd["warp_deg"], rad_to_deg(pc.facing_yaw), Vector2(pc.velocity.x, pc.velocity.z).length(), _anim._backward])
	release_all()
	await tick(secs(0.5))
	metric("anim_turn180_min_foot_sep_m", tmin_foot)
	metric("anim_turn180_min_knee_sep_m", tmin_knee)
	metric("anim_turn180_max_foot_yaw_deg", tmax_fyaw)
	metric("anim_turn180_max_knee_valgus_m", tmax_valgus)
	check("anim_turn180_legs", tmin_foot > 0.1 and tmin_knee > 0.1 and tmax_valgus < 0.005,
		"min foot sep=%.3f knee sep=%.3f valgus=%.3f" % [tmin_foot, tmin_knee, tmax_valgus])
	print("INFO|turn180 legs: min foot sep=%.3f min knee sep=%.3f max foot yaw=%.0f max knee valgus=%.3f" % [tmin_foot, tmin_knee, tmax_fyaw, tmax_valgus])
	# vault + mantle map to their own states
	await place(Vector3(L.VAULT_X, 0.02, L.VAULT_Z + 3.0))
	press("move_forward")
	await walk_until_z(L.VAULT_Z + 1.0, 2.0)
	_pop_begin()
	press("jump")
	var saw_vault := await _wait_anim("vault", 1.0)
	# contact: hands come down onto the wall top, feet never inside the wall
	var v := await _traverse_contact(L.VAULT_H, L.VAULT_Z, L.VAULT_Z - L.VAULT_T)
	await tick(secs(0.25))
	var vpop := _pop_end()
	release_all()
	await tick(secs(1.0))
	# round 3: tightened from hand<0.12 / pen<0.04 (joint) to palm-level contact
	check("anim_vault_contact", v["hand"] < 0.04 and v["planted_err"] < 0.01 and v["hpen"] < 0.02 and v["pen"] < 0.02,
		"closest hand-to-wall-top=%.3f m  planted wrist err=%.3f m  hand penetration=%.3f m  max sole penetration=%.3f m" % [v["hand"], v["planted_err"], v["hpen"], v["pen"]])
	await place(Vector3(L.MANTLE_X, 0.02, L.MANTLE_Z + 1.0))
	press("move_forward")
	await tick(secs(0.4))
	_pop_begin()
	press("jump")
	var saw_mantle := await _wait_anim("mantle", 1.0)
	var m := await _traverse_contact(L.MANTLE_H, L.MANTLE_Z, L.MANTLE_Z - 3.0)
	var m_raise: float = m["raise"]
	for n in secs(0.25):
		await tick()
		m_raise = maxf(m_raise, _arm_raise(false))
	var mpop := _pop_end()
	release_all()
	await tick(secs(0.8))
	check("anim_mantle_contact", m["hand"] < 0.04 and m["hand_frames"] >= secs(0.3) and m["planted_err"] < 0.01 and m["hpen"] < 0.02 and m["pen"] < 0.025,
		"closest hand-to-ledge=%.3f m  frames within 8 cm=%d (%.2f s)  planted wrist err=%.3f m  hand penetration=%.3f m  max sole penetration=%.3f m" % [m["hand"], m["hand_frames"], m["hand_frames"] / float(Engine.physics_ticks_per_second), m["planted_err"], m["hpen"], m["pen"]])
	# round 5: mantle stand-up -- released arms must not swing up beside the
	# head (pre-fix the climb clip's next reach lifted a free wrist to -0.19..-0.23 m below its
	# shoulder while the body stood up on the top)
	metric("anim_mantle_standup_arm_raise_m", m_raise)
	check("anim_mantle_standup_arms", m_raise < -0.25,
		"stand-up (u>=0.75 .. 0.25 s after): highest free wrist relative to its shoulder=%.3f m (want < -0.25)" % m_raise)
	# round 4: no single-frame pops from jump press to 0.25 s after landing
	# (pre-fix: ~1.3 m mantle-entry teleport; 0.25-0.4 m/frame at 60 Hz)
	metric("anim_vault_pop_m", vpop["d2"])
	metric("anim_mantle_pop_m", mpop["d2"])
	check("anim_traverse_pops", vpop["vjump"] < 12.0 and mpop["vjump"] < 12.0,
		"largest per-frame 2nd difference of body points: vault %.3f m (%s, %.1f m/s velocity jump)  mantle %.3f m (%s, %.1f m/s)" % [vpop["d2"], vpop["bone"], vpop["vjump"], mpop["d2"], mpop["bone"], mpop["vjump"]])
	check("anim_traverse_states", saw_vault and saw_mantle and _anim.anim_state == "ground", "vault=%s mantle=%s end=%s" % [saw_vault, saw_mantle, _anim.anim_state])

