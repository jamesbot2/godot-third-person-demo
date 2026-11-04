class_name StepSolver
extends RefCounted
## Stair step-up probe for CharacterBody3D, using PhysicsServer3D.body_test_motion.
##
## Approach (forward -> up -> forward -> down sweep), informed by:
##   * PantheraDigital/GodotCharacterStep (MIT)  https://github.com/PantheraDigital/GodotCharacterStep
##   * Andicraft/stairs-character (MIT)          https://github.com/Andicraft/stairs-character
## This is an independent re-implementation with stricter validation:
##   - only triggers when the forward sweep hits a NON-walkable surface (a riser),
##   - requires head-room for the full lift,
##   - requires a minimum ledge depth at the raised height (no stepping onto thin lips),
##   - requires the landing surface to be walkable (<= floor_max_angle),
##   - requires the gained height to be in (min_step, max_step],
##   - never steps onto RigidBody3D (those are pushed instead).
## It returns the vertical lift and the landing normal; the caller only *raises*
## the body (never teleports it forward), then move_and_slide() performs the real
## horizontal motion. Nothing is lifted unconditionally.

const MIN_STEP := 0.02


static func probe_step_up(body: CharacterBody3D, horizontal_motion: Vector3, max_step: float,
		probe_depth: float, max_floor_angle: float) -> Dictionary:
	var result := {}
	var h_len := horizontal_motion.length()
	if h_len < 0.0001:
		return result
	var dir := horizontal_motion / h_len
	var rid := body.get_rid()
	var params := PhysicsTestMotionParameters3D.new()
	params.margin = body.safe_margin
	params.recovery_as_collision = false
	var res := PhysicsTestMotionResult3D.new()
	var xf := body.global_transform

	# 1. forward sweep at current height: must hit a riser (non-walkable)
	var fwd := dir * maxf(h_len, 0.02)
	params.from = xf
	params.motion = fwd
	if not PhysicsServer3D.body_test_motion(rid, params, res):
		return result
	var n := res.get_collision_normal()
	if n.angle_to(Vector3.UP) <= max_floor_angle + 0.01:
		return result   # a walkable slope: move_and_slide handles it
	var collider := res.get_collider()
	if collider is RigidBody3D:
		return result
	var contact_y := res.get_collision_point().y - xf.origin.y
	if contact_y > max_step + 0.02:
		return result   # contact is higher than a step: it's a wall

	# 2. lift: check head-room
	params.from = xf
	params.motion = Vector3.UP * max_step
	PhysicsServer3D.body_test_motion(rid, params, res)
	var lift := res.get_travel().y
	if lift < MIN_STEP:
		return result
	var raised := xf.translated(Vector3.UP * lift)

	# 3. forward at raised height: must have at least probe_depth of free space
	params.from = raised
	params.motion = dir * probe_depth
	var ahead := raised.translated(dir * probe_depth)
	if PhysicsServer3D.body_test_motion(rid, params, res):
		if res.get_travel().length() < probe_depth * 0.5:
			return result   # still blocked above the step height -> wall
		ahead = raised.translated(res.get_travel())

	# 4. down: find the step tread
	params.from = ahead
	params.motion = Vector3.DOWN * (lift + 0.05)
	if not PhysicsServer3D.body_test_motion(rid, params, res):
		return result   # nothing to stand on (a gap)
	var floor_n := res.get_collision_normal()
	if floor_n.angle_to(Vector3.UP) > max_floor_angle:
		return result
	if res.get_collider() is RigidBody3D:
		return result
	var gained := lift + res.get_travel().y   # travel.y is negative
	if gained < MIN_STEP or gained > max_step + 0.001:
		return result
	result["height"] = gained
	result["normal"] = floor_n
	return result
