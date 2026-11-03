extends SceneTree
## Measures, per locomotion clip on the UBC character: cycle length, the
## ground speed implied by the planted foot (median backward speed of the
## lower foot while it is near its minimum height) and min/max foot heights.
## Used to set the playback-rate constants in character_animator.gd.

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_measure()
	return false


func _measure() -> void:
	var ch: Node3D = (load("res://assets/characters/ubc_male/ubc_male.scn") as PackedScene).instantiate()
	root.add_child(ch)
	var ap := AnimationPlayer.new()
	ch.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", load("res://assets/animations/ual_clips.res"))
	var sk: Skeleton3D = ch.find_child("Skeleton3D", true, false)
	var fl := sk.find_bone("ball_l")
	var fr := sk.find_bone("ball_r")
	var args := OS.get_cmdline_user_args()
	var clips := ["idle", "walk", "jog", "sprint", "crouch_idle", "crouch_walk", "slide_loop"] if args.is_empty() else Array(args)
	for c in clips:
		var a := ap.get_animation(c)
		ap.play(c)
		var n := int(a.length * 120.0)
		var pts_l: Array[Vector3] = []
		var pts_r: Array[Vector3] = []
		for i in n + 1:
			ap.seek(a.length * float(i) / n, true)
			ap.advance(0.0)
			sk.force_update_all_bone_transforms()
			pts_l.append((sk.global_transform * sk.get_bone_global_pose(fl)).origin)
			pts_r.append((sk.global_transform * sk.get_bone_global_pose(fr)).origin)
		var speeds: Array[float] = []
		var vx: Array[float] = []
		var miny := 9.0
		var maxy := -9.0
		for i in n:
			for pts in [pts_l, pts_r]:
				miny = minf(miny, pts[i].y)
				maxy = maxf(maxy, pts[i].y)
		for i in n:
			var lo: Array[Vector3] = pts_l if pts_l[i].y < pts_r[i].y else pts_r
			if lo[i].y < miny + 0.03:
				var v := (lo[i + 1] - lo[i]) * 120.0 / a.length * float(n) / 120.0
				speeds.append(-v.z)  # model forward is +Z; planted foot moves -Z
				vx.append(-v.x)
		speeds.sort()
		var med := speeds[speeds.size() / 2] if speeds.size() > 0 else 0.0
		vx.sort()
		var medx := vx[vx.size() / 2] if vx.size() > 0 else 0.0
		var r0 := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis"))).origin
		print("%-12s len=%.3f plant_speed=%.3f m/s lat=%.3f (n=%d) foot_y min=%.3f max=%.3f" % [c, a.length, med, medx, speeds.size(), miny, maxy])
	quit()
