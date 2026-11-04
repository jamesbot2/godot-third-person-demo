extends SceneTree
## Measures the REAL ground stride (m per gait cycle) of the blended ground
## locomotion tree for a grid of (gait, run_style) weights, by playing the
## tree at a fixed cycle rate and integrating the backward speed of the
## planted (lowest) ball bone in skeleton space. Output is pasted into
## CharacterAnimator.stride_table_* so the gait solver inverts real data
## instead of assuming strides blend linearly.
##   godot --headless --path . -s res://tools/calibrate_stride.gd

const Anim := preload("res://scripts/player/character_animator.gd")
var _a: Node3D
var _frames := 0

func _initialize() -> void:
	_a = Anim.new()
	_a.controller_path = NodePath("")
	root.add_child(_a)

func _measure(g: float, rs: float, rate: float, crouch := false, plant_y := 0.035) -> Vector2:
	var t: AnimationTree = _a.anim_tree
	_a._p("ground/walk_ts/scale", Anim.LEN_WALK * rate)
	_a._p("ground/jog_ts/scale", Anim.LEN_JOG * rate)
	_a._p("ground/sprint_ts/scale", Anim.LEN_SPRINT * rate)
	_a._p("ground/cwalk_ts/scale", Anim.LEN_CWALK * rate)
	_a._p("ground/run/blend_amount", rs)
	_a._p("ground/gait/blend_amount", g)
	_a._p("ground/move/blend_amount", 1.0)
	_a._p("ground/cmove/blend_amount", 1.0)
	_a._p("ground/crouch/blend_amount", 1.0 if crouch else 0.0)
	_a._p("ground/land_mix/blend_amount", 0.0)
	var sk: Skeleton3D = _a.skeleton
	var dt := 1.0 / 240.0
	for i in 240:
		t.advance(dt)
	var prev := {}
	var dist := 0.0
	var tt := 0.0
	var miny := INF
	var bl := sk.find_bone("ball_l")
	var br := sk.find_bone("ball_r")
	for i in int(4.0 / dt):
		t.advance(dt)
		var pl := sk.get_bone_global_pose(bl).origin
		var pr := sk.get_bone_global_pose(br).origin
		var lo := "l" if pl.y < pr.y else "r"
		var p := pl if lo == "l" else pr
		miny = minf(miny, p.y)
		if prev.has(lo) and p.y < plant_y:
			# character faces +Z in skeleton space; planted foot moves -Z
			dist += -(p.z - prev[lo].z)
			tt += dt
		prev.clear()
		prev[lo] = p
	return Vector2(dist / tt / rate if tt > 0 else 0.0, miny)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	for rs in [0.0, 1.0]:
		var row := []
		for i in 11:
			var g := i / 10.0
			var r := _measure(g, rs, 1.0)
			var r2 := _measure(g, rs, 1.0, false, 0.06)
			row.append("%.2f/%.2f" % [r.x, r2.x])
		print("run_style=%.0f strides=[%s]" % [rs, ", ".join(row)])
	var c := _measure(0, 0, 1.0, true)
	print("crouch_walk stride=%.3f min_y=%.3f" % [c.x, c.y])
	return true
