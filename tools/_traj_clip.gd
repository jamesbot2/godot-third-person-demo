extends SceneTree
## Print the contact trajectory of a clip on the UBC body (animator frame:
## x right, y up, z = BACK (forward is -z); visual root at 0).
##   godot --headless --path . -s res://tools/_traj_clip.gd -- <clip> [lib.res]
var _d := false
func _process(_x):
	if _d:
		return true
	_d = true
	var args := OS.get_cmdline_user_args()
	var lib: AnimationLibrary = load(args[1] if args.size() > 1 else "res://assets/animations/ual_clips.res")
	var ch: Node3D = (load("res://assets/characters/ubc_male/ubc_male.scn") as PackedScene).instantiate()
	ch.rotation.y = PI
	root.add_child(ch)
	var sk: Skeleton3D = ch.find_child("Skeleton3D", true, false)
	var m := Transform3D.IDENTITY
	var n: Node = sk
	while n != root:
		m = (n as Node3D).transform * m
		n = n.get_parent()
	var bones: PackedStringArray = ["hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r", "pelvis", "upperarm_l"]
	var cs := ClipSampler.sample(sk, m, lib.get_animation(args[0]), bones)
	print(args[0], " len ", cs.t_len)
	var f := 0.0
	while f <= cs.t_len + 0.001:
		print("t=%.3f pel=(%.2f,%.2f) hl=(%.2f,%.2f,%.2f) hr=(%.2f,%.2f,%.2f) sole=%.3f fl=(%.2f,%.2f) fr=(%.2f,%.2f)" % [f,
			cs.at("pelvis", f).y, cs.at("pelvis", f).z,
			cs.at("hand_l", f).x, cs.at("hand_l", f).y, cs.at("hand_l", f).z,
			cs.at("hand_r", f).x, cs.at("hand_r", f).y, cs.at("hand_r", f).z,
			cs.sole_min(f), cs.at("ball_l", f).y, cs.at("ball_l", f).z, cs.at("ball_r", f).y, cs.at("ball_r", f).z])
		f += 1.0 / 30.0
	quit()
	return false
