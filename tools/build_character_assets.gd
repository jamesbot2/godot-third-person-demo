extends SceneTree
## Offline asset build step (run once; outputs are committed).
##
##   godot --headless --path . -s res://tools/build_character_assets.gd -- --src=/path/to/assets_raw
##
## Inputs (all CC0, Quaternius, see THIRD_PARTY.md):
##   <src>/ubc/.../Godot - UE/Superhero_Male_FullBody.gltf  (+ .bin, textures)
##   <src>/ual1/.../Unreal-Godot/UAL1_Standard.glb           (in-place clips)
##   <src>/ual2/.../Unreal-Godot/UAL2_Standard.glb
## Outputs:
##   res://assets/characters/ubc_male/ubc_male.scn   skinned mesh + Skeleton3D (65 bones)
##   res://assets/animations/ual_clips.res           AnimationLibrary of the clips we use
##
## The raw files are loaded with GLTFDocument at build time so the game itself
## needs no import step for them. Clip retarget: UAL and UBC share the same
## 65-bone hierarchy and bone names, but the UBC "Superhero" rest pose has
## longer legs (pelvis rest height 0.949 m vs 0.917 m). We therefore keep only
## bone ROTATION tracks (local, applied on the character's own bone lengths),
## drop every position track except the pelvis, and scale the pelvis track by
## the leg-length ratio so the feet stay on the ground. Scale tracks are all 1
## and are dropped.

const UBC_REL := "ubc/Universal Base Characters[Standard]/Base Characters/Godot - UE/"
const UAL1_REL := "ual1/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
const UAL2_REL := "ual2/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb"

# our name : [source file key, source clip name, loop]
const CLIPS := {
	"idle": ["ual1", "Idle", true],
	"walk": ["ual1", "Walk", true],
	"jog": ["ual1", "Jog_Fwd", true],
	"sprint": ["ual1", "Sprint", true],
	"crouch_idle": ["ual1", "Crouch_Idle", true],
	"crouch_walk": ["ual1", "Crouch_Fwd", true],
	"jump_start": ["ual1", "Jump_Start", false],
	"jump_air": ["ual1", "Jump", true],
	"jump_land": ["ual1", "Jump_Land", false],
	"roll": ["ual1", "Roll", false],
	"push": ["ual1", "Push", true],
	"tpose": ["ual1", "A_TPose", false],
	"slide_start": ["ual2", "Slide_Start", false],
	"slide_loop": ["ual2", "Slide", true],
	"slide_exit": ["ual2", "Slide_Exit", false],
	"climb": ["ual2", "ClimbUp_1m", false],
	"ninja_start": ["ual2", "NinjaJump_Start", false],
	"ninja_air": ["ual2", "NinjaJump_Idle", true],
	"ninja_land": ["ual2", "NinjaJump_Land", false],
}

var src := "/workspace/assets_raw/"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
			if not src.ends_with("/"):
				src += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/characters/ubc_male"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/animations"))
	var char_root := _load_gltf(src + UBC_REL + "Superhero_Male_FullBody.gltf")
	var skel: Skeleton3D = char_root.find_child("Skeleton3D", true, false)
	_build_character(char_root)
	_build_library(skel)
	quit()


func _load_gltf(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	assert(err == OK, "cannot load " + path)
	return doc.generate_scene(st)


func _tex(img: Image, size: int, normal: bool) -> Texture2D:
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps(normal)
	var t := PortableCompressedTexture2D.new()
	t.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, normal, 0.92)
	return t


func _build_character(root: Node) -> void:
	var dir := src + UBC_REL
	# Two-tone "clay" albedo derived from the base texture's luminance:
	# skin -> light neutral grey, the dark shorts -> charcoal. Reads as a
	# neutral mannequin instead of a painted nude superhero.
	var base := Image.load_from_file(dir + "T_Superhero_Male_Dark.png")
	base.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	for y in base.get_height():
		for x in base.get_width():
			var c := base.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			var t := smoothstep(0.10, 0.22, l)   # shorts are < 0.1
			var shade := lerpf(0.85, 1.05, clampf((l - 0.2) / 0.5, 0.0, 1.0))
			var skin := Color(0.66, 0.64, 0.61) * shade
			var cloth := Color(0.13, 0.14, 0.16)
			base.set_pixel(x, y, cloth.lerp(skin, t))
	var body_mat := StandardMaterial3D.new()
	body_mat.resource_name = "M_Body_Clay"
	body_mat.albedo_texture = _tex(base, 1024, false)
	body_mat.normal_enabled = true
	body_mat.normal_texture = _tex(Image.load_from_file(dir + "T_Superhero_Male_Normal.png"), 1024, true)
	body_mat.roughness = 0.78
	var eye_mat := StandardMaterial3D.new()
	eye_mat.resource_name = "M_Eyes"
	eye_mat.albedo_color = Color(0.12, 0.1, 0.09)
	eye_mat.roughness = 0.3
	var brow_mat := StandardMaterial3D.new()
	brow_mat.resource_name = "M_Brows"
	brow_mat.albedo_color = Color(0.1, 0.09, 0.08)
	brow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var hair := Image.load_from_file(dir + "T_Hair_1_BaseColor.png")
	brow_mat.albedo_texture = _tex(hair, 256, false)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var old := m.mesh.surface_get_material(s)
			var n := old.resource_name if old else ""
			var mat: Material = body_mat
			if n.contains("Eye"):
				mat = eye_mat
			elif n.contains("Hair"):
				mat = brow_mat
			m.mesh.surface_set_material(s, mat)
			print("mesh ", m.name, " surf ", s, " ", n, " -> ", mat.resource_name)
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		ap.free()
	root.name = "UBCMale"
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, "res://assets/characters/ubc_male/ubc_male.scn", ResourceSaver.FLAG_COMPRESS)
	print("saved character: ", err)


func _build_library(char_skel: Skeleton3D) -> void:
	var srcs := {"ual1": _load_gltf(src + UAL1_REL), "ual2": _load_gltf(src + UAL2_REL)}
	var src_skel: Skeleton3D = (srcs["ual1"] as Node).find_child("Skeleton3D", true, false)
	var pi_c := char_skel.find_bone("pelvis")
	var pi_s := src_skel.find_bone("pelvis")
	var k := char_skel.get_bone_rest(pi_c).origin.z / src_skel.get_bone_rest(pi_s).origin.z
	print("pelvis height ratio k=", k)
	var lib := AnimationLibrary.new()
	for our in CLIPS:
		var spec: Array = CLIPS[our]
		var ap: AnimationPlayer = (srcs[spec[0]] as Node).find_child("AnimationPlayer", true, false)
		var srcname: String = spec[1]
		var a: Animation = null
		for n in ap.get_animation_list():
			if n == srcname or n == srcname + "_Loop" or n.trim_suffix("_Loop") == srcname:
				a = ap.get_animation(n)
		assert(a != null, "missing clip " + srcname)
		var out := Animation.new()
		out.length = a.length
		out.loop_mode = Animation.LOOP_LINEAR if spec[2] else Animation.LOOP_NONE
		for t in a.get_track_count():
			var path := String(a.track_get_path(t))
			var bone := path.get_slice(":", 1)
			var ty := a.track_get_type(t)
			if bone == "root" or ty == Animation.TYPE_SCALE_3D:
				continue
			if ty == Animation.TYPE_POSITION_3D and bone != "pelvis":
				continue
			if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
				continue
			var nt := out.add_track(ty)
			out.track_set_path(nt, "Armature/Skeleton3D:" + bone)
			out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
			out.track_set_interpolation_loop_wrap(nt, spec[2])
			for kk in a.track_get_key_count(t):
				var v: Variant = a.track_get_key_value(t, kk)
				if ty == Animation.TYPE_POSITION_3D:
					v = (v as Vector3) * k
				out.track_insert_key(nt, a.track_get_key_time(t, kk), v)
		# Bones the source clip leaves untouched sit at the SOURCE rest pose,
		# which differs from the UBC rest by up to 17 deg (neck/clavicles);
		# key them explicitly so they don't snap to the UBC rest in blends.
		for b in src_skel.get_bone_count():
			var bn := src_skel.get_bone_name(b)
			if bn == "root":
				continue
			var bp := NodePath("Armature/Skeleton3D:" + bn)
			if out.find_track(bp, Animation.TYPE_ROTATION_3D) == -1:
				var nt2 := out.add_track(Animation.TYPE_ROTATION_3D)
				out.track_set_path(nt2, bp)
				out.track_insert_key(nt2, 0.0, src_skel.get_bone_rest(b).basis.get_rotation_quaternion())
			if bn == "pelvis" and out.find_track(bp, Animation.TYPE_POSITION_3D) == -1:
				var nt3 := out.add_track(Animation.TYPE_POSITION_3D)
				out.track_set_path(nt3, bp)
				out.track_insert_key(nt3, 0.0, src_skel.get_bone_rest(b).origin * k)
		lib.add_animation(our, out)
		print("clip ", our, " <- ", srcname, " len=", snappedf(a.length, 0.01), " tracks=", out.get_track_count())
	var err := ResourceSaver.save(lib, "res://assets/animations/ual_clips.res", ResourceSaver.FLAG_COMPRESS)
	print("saved library: ", err)
	for n in srcs.values():
		(n as Node).free()
