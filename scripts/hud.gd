extends CanvasLayer

@export var player_path: NodePath
@onready var info: Label = $Info
var _player: Node


func _ready() -> void:
	_player = get_node_or_null(player_path)


func _process(_delta: float) -> void:
	var speed := 0.0
	if _player and _player.has_method("get_horizontal_speed"):
		speed = _player.get_horizontal_speed()
	var mouse := "已锁定 (Esc 释放)" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "已释放 (左键点击锁定)"
	info.text = "FPS: %d   速度: %.1f m/s   鼠标: %s" % [Engine.get_frames_per_second(), speed, mouse]
