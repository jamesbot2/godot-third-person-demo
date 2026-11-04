extends CanvasLayer
## HUD: compact status line + F1 debug panel showing real controller values.

@export var player_path: NodePath
@onready var info: Label = $Info
var _player: PlayerController
var _debug := true


var _accum := 0.0
var _headless := false
const REFRESH := 0.1   # s; text shaping (CJK) is expensive, refresh at 10 Hz


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_headless = DisplayServer.get_name() == "headless"
	# One explicit CJK-capable system font -> avoids a per-update fallback search.
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Serif CJK SC", "WenQuanYi Micro Hei", "Droid Sans Fallback", "sans-serif"])
	for c in get_children():
		if c is Label:
			(c as Label).add_theme_font_override("font", f)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_debug = not _debug


func _process(delta: float) -> void:
	if _player == null or _headless:
		return
	_accum += delta
	if _accum < REFRESH:
		return
	_accum = 0.0
	var d := _player.get_debug_info()
	var t := "FPS %d | 物理 %d Hz | 状态 %s | 速度 %.2f m/s" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, d["state"], d["speed"]]
	if _debug:
		t += "\nvy %.2f | 着地 %s | 坡度 %.1f° | 高度 %.2f m" % [d["vy"], d["on_floor"], d["floor_deg"], d["height"]]
		t += "\n蹲 %s | 冲刺 %s | 瞄准 %s | 走路 %s" % [d["crouched"], d["sprint"], d["aim"], d["walk"]]
		t += "\n上台阶次数 %d | 上次落地冲击 %.1f m/s" % [d["steps"], d["impact"]]
	if info.text != t:
		info.text = t
