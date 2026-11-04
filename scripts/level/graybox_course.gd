@tool
class_name GrayboxCourse
extends Node3D
## Builds the reproducible graybox movement test course from CourseLayout.
## Geometry is generated at runtime (and in the editor, not saved) so the
## layout always matches the automated tests.

const WORLD_LAYER := 1
const PROP_LAYER := 2

var _mats := {}


func _ready() -> void:
	_build()


func _mat(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.5, 0.5, 0.5)
		_mats[key] = m
	return _mats[key]


func _box(name_: String, center: Vector3, size: Vector3, mat: StandardMaterial3D, basis := Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.transform = Transform3D(basis, center)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = Color(1, 1, 0.85)
	add_child(l)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var ground := _mat("ground", Color(0.42, 0.46, 0.42))
	var grey := _mat("grey", Color(0.62, 0.62, 0.66))
	var step := _mat("step", Color(0.85, 0.6, 0.3))
	var bad := _mat("bad", Color(0.8, 0.3, 0.3))
	var ramp := _mat("ramp", Color(0.55, 0.65, 0.8))
	var wall := _mat("wall", Color(0.55, 0.5, 0.6))
	var plat := _mat("plat", Color(0.35, 0.72, 0.75))
	var mark := _mat("mark", Color(0.9, 0.9, 0.9))

	# Ground
	_box("Ground", Vector3(0, -0.5, -20), Vector3(160, 1, 120), ground)
	# Boundary walls
	_box("WallN", Vector3(0, 2, -80.5), Vector3(160, 4, 1), wall)
	_box("WallS", Vector3(0, 2, 40.5), Vector3(160, 4, 1), wall)
	_box("WallE", Vector3(80.5, 2, -20), Vector3(1, 4, 120), wall)
	_box("WallW", Vector3(-80.5, 2, -20), Vector3(1, 4, 120), wall)

	# Zone A: flat track distance markers (visual only, 1 cm tall, no collision)
	for i in range(0, 16):
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(6, 0.01, 0.06)
		mi.mesh = m
		mi.material_override = mark
		mi.position = Vector3(0, 0.005, -i * 2.0)
		add_child(mi)
	_label("A  平地: 起步/急停/急转", Vector3(0, 2.5, 1))

	# Zone B: step blocks
	for i in CourseLayout.STEP_HEIGHTS.size():
		var h: float = CourseLayout.STEP_HEIGHTS[i]
		var x := CourseLayout.step_lane_x(i)
		var depth := CourseLayout.STEP_Z_NEAR - CourseLayout.STEP_Z_FAR
		var zc := (CourseLayout.STEP_Z_NEAR + CourseLayout.STEP_Z_FAR) * 0.5
		_box("Step_%d" % int(h * 100), Vector3(x, h * 0.5, zc), Vector3(2.4, h, depth), bad if h > 0.45 else step)
		_label("%.2fm" % h, Vector3(x, h + 0.8, CourseLayout.STEP_Z_NEAR + 0.5))
	_label("B  单级台阶", Vector3(CourseLayout.step_lane_x(2), 2.6, -4))

	# Zone C: normal stairs up to a landing, then down the other side
	var sx := CourseLayout.STAIR_X
	var z := CourseLayout.STAIR_Z0
	for i in CourseLayout.STAIR_STEPS:
		var top := CourseLayout.STAIR_RISER * (i + 1)
		_box("StairUp_%d" % i, Vector3(sx, top * 0.5, z - CourseLayout.STAIR_TREAD * (i + 0.5)), Vector3(3, top, CourseLayout.STAIR_TREAD), step)
	var land_h := CourseLayout.STAIR_RISER * CourseLayout.STAIR_STEPS
	var land_z0 := z - CourseLayout.STAIR_TREAD * CourseLayout.STAIR_STEPS
	_box("StairLanding", Vector3(sx, land_h * 0.5, land_z0 - CourseLayout.STAIR_LANDING_DEPTH * 0.5), Vector3(3, land_h, CourseLayout.STAIR_LANDING_DEPTH), plat)
	var down_z0 := land_z0 - CourseLayout.STAIR_LANDING_DEPTH
	for i in CourseLayout.STAIR_STEPS:
		var top2 := land_h - CourseLayout.STAIR_RISER * (i + 1)
		if top2 <= 0.001:
			break
		_box("StairDown_%d" % i, Vector3(sx, top2 * 0.5, down_z0 - CourseLayout.STAIR_TREAD * (i + 0.5)), Vector3(3, top2, CourseLayout.STAIR_TREAD), step)
	_label("C  楼梯 0.18/0.30", Vector3(sx, 3.2, -4))
	# Steep stairs
	var ex := CourseLayout.STEEP_X
	for i in CourseLayout.STEEP_STEPS:
		var top3 := CourseLayout.STEEP_RISER * (i + 1)
		_box("SteepStair_%d" % i, Vector3(ex, top3 * 0.5, z - CourseLayout.STEEP_TREAD * (i + 0.5)), Vector3(3, top3, CourseLayout.STEEP_TREAD), step)
	var steep_h := CourseLayout.STEEP_RISER * CourseLayout.STEEP_STEPS
	_box("SteepLanding", Vector3(ex, steep_h * 0.5, z - CourseLayout.STEEP_TREAD * CourseLayout.STEEP_STEPS - 1.5), Vector3(3, steep_h, 3), plat)
	_label("陡楼梯 0.25/0.25", Vector3(ex, 3.4, -4))

	# Zone D: ramps of various angles, each ending on a 1.5 m platform
	for i in CourseLayout.RAMP_ANGLES.size():
		var ang := deg_to_rad(CourseLayout.RAMP_ANGLES[i])
		var run := CourseLayout.ramp_run(i)
		var rx := CourseLayout.ramp_x(i)
		var length := CourseLayout.RAMP_RISE / sin(ang)
		var thick := 0.4
		# Top surface line from (z0, 0) to (z0 - run, rise)
		var mid := Vector3(rx, CourseLayout.RAMP_RISE * 0.5, CourseLayout.RAMP_Z0 - run * 0.5)
		var b := Basis(Vector3.RIGHT, ang)  # tilt so local -Z rises
		var normal := b * Vector3.UP
		_box("Ramp_%d" % int(CourseLayout.RAMP_ANGLES[i]), mid - normal * thick * 0.5, Vector3(CourseLayout.RAMP_WIDTH, thick, length), bad if CourseLayout.RAMP_ANGLES[i] > 46.0 else ramp, b)
		_box("RampTop_%d" % int(CourseLayout.RAMP_ANGLES[i]), Vector3(rx, CourseLayout.RAMP_RISE * 0.5, CourseLayout.RAMP_Z0 - run - 1.5), Vector3(CourseLayout.RAMP_WIDTH, CourseLayout.RAMP_RISE, 3), plat)
		_label("%d°" % int(CourseLayout.RAMP_ANGLES[i]), Vector3(rx, 2.4, CourseLayout.RAMP_Z0 + 0.5))
	_label("D  坡道", Vector3(CourseLayout.ramp_x(2), 3.4, -2))

	# Zone E: drop tower - stairs to 2 m mid landing and 4 m top
	var tx := CourseLayout.TOWER_X
	var tz := CourseLayout.TOWER_Z0
	for i in CourseLayout.TOWER_TOP_STEPS:
		var top4 := CourseLayout.TOWER_RISER * (i + 1)
		var zc4 := tz - CourseLayout.TOWER_TREAD * (i + 0.5)
		if i >= CourseLayout.TOWER_MID_STEPS:
			zc4 -= CourseLayout.TOWER_LANDING
		_box("TowerStep_%d" % i, Vector3(tx, top4 * 0.5, zc4), Vector3(2.5, top4, CourseLayout.TOWER_TREAD), step)
	var mid_h := CourseLayout.TOWER_RISER * CourseLayout.TOWER_MID_STEPS
	var mid_z := tz - CourseLayout.TOWER_TREAD * CourseLayout.TOWER_MID_STEPS - CourseLayout.TOWER_LANDING * 0.5
	_box("TowerMid", Vector3(tx, mid_h * 0.5, mid_z), Vector3(2.5, mid_h, CourseLayout.TOWER_LANDING), plat)
	var top_h := CourseLayout.TOWER_RISER * CourseLayout.TOWER_TOP_STEPS
	var top_z := tz - CourseLayout.TOWER_TREAD * CourseLayout.TOWER_TOP_STEPS - CourseLayout.TOWER_LANDING * 1.5
	_box("TowerTop", Vector3(tx, top_h * 0.5, top_z), Vector3(2.5, top_h, CourseLayout.TOWER_LANDING), plat)
	_label("E  落地测试 2m / 4m", Vector3(tx, 5.2, top_z))

	# Zone F: corridors and a low tunnel
	for spec in [[CourseLayout.CORRIDOR_X, CourseLayout.CORRIDOR_WIDTH, "1.0m"], [CourseLayout.NARROW_X, CourseLayout.NARROW_WIDTH, "0.85m"]]:
		var cx: float = spec[0]
		var w: float = spec[1]
		var zc5 := CourseLayout.CORRIDOR_Z0 - CourseLayout.CORRIDOR_LEN * 0.5
		_box("CorrL_%s" % spec[2], Vector3(cx - w * 0.5 - 0.25, 1.5, zc5), Vector3(0.5, 3, CourseLayout.CORRIDOR_LEN), wall)
		_box("CorrR_%s" % spec[2], Vector3(cx + w * 0.5 + 0.25, 1.5, zc5), Vector3(0.5, 3, CourseLayout.CORRIDOR_LEN), wall)
		_label("走廊 %s" % spec[2], Vector3(cx, 3.6, CourseLayout.CORRIDOR_Z0))
	# L-corner at the end of the 1.0 m corridor
	var cz_end := CourseLayout.CORRIDOR_Z0 - CourseLayout.CORRIDOR_LEN
	_box("CorrCornerBack", Vector3(CourseLayout.CORRIDOR_X - 1.0, 1.5, cz_end - 0.25 - 1.0), Vector3(3.0, 3, 0.5), wall)
	# Low tunnel (crouch / slide only)
	var tzc := CourseLayout.TUNNEL_Z0 - CourseLayout.TUNNEL_LEN * 0.5
	_box("TunnelRoof", Vector3(CourseLayout.TUNNEL_X, CourseLayout.TUNNEL_HEIGHT + 0.25, tzc), Vector3(CourseLayout.TUNNEL_WIDTH + 1.0, 0.5, CourseLayout.TUNNEL_LEN), grey)
	_box("TunnelL", Vector3(CourseLayout.TUNNEL_X - CourseLayout.TUNNEL_WIDTH * 0.5 - 0.25, CourseLayout.TUNNEL_HEIGHT * 0.5, tzc), Vector3(0.5, CourseLayout.TUNNEL_HEIGHT, CourseLayout.TUNNEL_LEN), wall)
	_box("TunnelR", Vector3(CourseLayout.TUNNEL_X + CourseLayout.TUNNEL_WIDTH * 0.5 + 0.25, CourseLayout.TUNNEL_HEIGHT * 0.5, tzc), Vector3(0.5, CourseLayout.TUNNEL_HEIGHT, CourseLayout.TUNNEL_LEN), wall)
	_label("F  低矮通道 1.35m (蹲/滑铲)", Vector3(CourseLayout.TUNNEL_X, 2.6, CourseLayout.TUNNEL_Z0 + 0.5))

	# Zone G: vault / mantle
	_box("VaultWall", Vector3(CourseLayout.VAULT_X, CourseLayout.VAULT_H * 0.5, CourseLayout.VAULT_Z - CourseLayout.VAULT_T * 0.5), Vector3(3, CourseLayout.VAULT_H, CourseLayout.VAULT_T), grey)
	_label("G  翻越 0.9m", Vector3(CourseLayout.VAULT_X, 2.0, CourseLayout.VAULT_Z + 0.5))
	_box("MantleBox", Vector3(CourseLayout.MANTLE_X, CourseLayout.MANTLE_H * 0.5, CourseLayout.MANTLE_Z - 1.5), Vector3(3, CourseLayout.MANTLE_H, 3), plat)
	_label("攀上 1.5m", Vector3(CourseLayout.MANTLE_X, 2.6, CourseLayout.MANTLE_Z + 0.5))
	_box("TallWall", Vector3(CourseLayout.TALL_X, CourseLayout.TALL_H * 0.5, CourseLayout.MANTLE_Z - 0.25), Vector3(3, CourseLayout.TALL_H, 0.5), bad)
	_label("2.3m (不可攀)", Vector3(CourseLayout.TALL_X, 3.0, CourseLayout.MANTLE_Z + 0.5))

	# Zone I: camera torture - overhang, pillar forest, tight alley
	var co := CourseLayout.CAM_ORIGIN
	_box("Overhang", co + Vector3(0, 2.45, 0), Vector3(6, 0.3, 6), grey)
	for p in [Vector3(-2.8, 0, -2.8), Vector3(2.8, 0, -2.8), Vector3(-2.8, 0, 2.8), Vector3(2.8, 0, 2.8)]:
		_box("OverhangLeg", co + p + Vector3(0, 1.15, 0), Vector3(0.3, 2.3, 0.3), wall)
	for i in 12:
		var px := -6.0 + float(i % 4) * 2.2
		var pz := -6.0 - float(i / 4) * 2.2
		_box("Pillar_%d" % i, co + Vector3(px, 1.5, pz), Vector3(0.5, 3.0, 0.5), wall)
	_box("AlleyL", co + Vector3(6.0, 2.0, -9.0), Vector3(0.5, 4.0, 10.0), wall)
	_box("AlleyR", co + Vector3(7.9, 2.0, -9.0), Vector3(0.5, 4.0, 10.0), wall)
	_label("I  镜头: 顶棚/柱林/窄巷", co + Vector3(0, 3.4, 3.5))

	# Zone H label (crates themselves are RigidBody3D nodes in main.tscn)
	_label("H  可推箱子", CourseLayout.CRATE_ORIGIN + Vector3(0, 2.5, 3))
