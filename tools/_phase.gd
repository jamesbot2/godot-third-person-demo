extends SceneTree
## Print the L/R foot-contact phase strip (32 samples) of locomotion clips.
##   godot --headless --path . -s res://tools/_phase.gd -- [lib.res]
## Clips missing from the library (core build has no strafe/turn clips) are skipped.
var _d := false
func _process(_x):
	if _d:
		return true
	_d = true
	var ch: Node3D = (load("res://assets/characters/ubc_male/ubc_male.scn") as PackedScene).instantiate()
	root.add_child(ch)
	var ap := AnimationPlayer.new(); ch.add_child(ap); ap.root_node = NodePath("..")
	var args := OS.get_cmdline_user_args()
	ap.add_animation_library("", load(args[0] if args.size() > 0 else "res://assets/animations/ual_clips.res"))
	var sk: Skeleton3D = ch.find_child("Skeleton3D", true, false)
	var fl := sk.find_bone("ball_l"); var fr := sk.find_bone("ball_r")
	for c in ["walk","walk_left","walk_right","walk_bwd","jog","jog_left","jog_right","jog_bwd","turn90_l","turn90_r","turn180_l","turn180_r"]:
		if not ap.has_animation(c):
			print("%-10s (not in library)" % c)
			continue
		var a := ap.get_animation(c); ap.play(c)
		var line := "%-10s " % c
		var n := 32
		for i in n:
			ap.seek(a.length*i/n, true); ap.advance(0.0); sk.force_update_all_bone_transforms()
			var l := (sk.get_bone_global_pose(fl)).origin; var r := (sk.get_bone_global_pose(fr)).origin
			line += "L" if l.y < r.y - 0.02 else ("R" if r.y < l.y - 0.02 else "=")
		print(line)
	quit()
	return false
