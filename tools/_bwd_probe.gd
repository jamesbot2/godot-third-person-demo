extends SceneTree
## dev probe: leg kinematics of a locomotion clip per frame (forward time).
## usage: godot --headless --path . -s res://tools/_bwd_probe.gd -- <walk|jog|sprint> [bwd]
var _done := false
func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var ch: Node3D = (load("res://assets/characters/ubc_male/ubc_male.scn") as PackedScene).instantiate()
	root.add_child(ch)
	var ap := AnimationPlayer.new()
	ch.add_child(ap)
	ap.root_node = NodePath("..")
	var lib: AnimationLibrary = load("res://assets/animations/ual_clips.res")
	var args := OS.get_cmdline_user_args()
	var c: String = args[0] if args.size() > 0 else "jog"
	if args.size() > 1 and args[1] == "bwd":
		var l2 := AnimationLibrary.new()
		for n in lib.get_animation_list():
			l2.add_animation(n, lib.get_animation(n))
		l2.add_animation("x", BackwardGait.build(lib.get_animation(c), c))
		lib = l2
		c = "x"
	ap.add_animation_library("", lib)
	var sk: Skeleton3D = ch.find_child("Skeleton3D", true, false)
	var a := ap.get_animation(c)
	ap.play(c)
	var n := 40 if args.size() > 1 else 28
	var vstr: float = {"walk": 1.29, "jog": 3.42, "sprint": 5.0}.get(args[0], 1.0) / a.length
	var pb := {}
	for i in n:
		ap.seek(a.length * float(i) / n, true)
		ap.advance(0.0)
		sk.force_update_all_bone_transforms()
		var line := "t=%.2f" % (float(i) / n)
		for s in (["l", "r"] if args.size() > 2 else ["l"]):
			var T := sk.get_bone_global_pose(sk.find_bone("thigh_" + s)).origin
			var K := sk.get_bone_global_pose(sk.find_bone("calf_" + s)).origin
			var A := sk.get_bone_global_pose(sk.find_bone("foot_" + s)).origin
			var B := sk.get_bone_global_pose(sk.find_bone("ball_" + s)).origin
			var knee := 180.0 - rad_to_deg((T - K).angle_to(A - K))
			var hip := rad_to_deg(atan2((K - T).z, -(K - T).y))
			var fp := rad_to_deg(atan2(B.y - A.y, (B - A).z))
			var wz := B.z - vstr * a.length * float(i) / n
			line += " wv=%+.2f" % ((wz - pb.get(s, wz)) / (a.length / n))
			pb[s] = wz
			line += " | %s ank_y=%.3f ank_z=%+.3f ball_y=%.3f hip=%+4.0f knee=%3.0f footpitch=%+4.0f" % [s, A.y, A.z, B.y, hip, knee, fp]
		var p := sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
		var sp := sk.get_bone_global_pose(sk.find_bone("spine_03")).origin
		line += " | pel_y=%.3f lean=%+.0f" % [p.y, rad_to_deg(atan2((sp - p).z, (sp - p).y))]
		print(line)
	return false
