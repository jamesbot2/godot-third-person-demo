# Godot 第三人称操控 Demo

一个用 **Godot 4（GDScript）** 编写的最小可玩第三人称角色控制器示例。场景全部由基础几何体（Box / Cylinder / Capsule）搭建，不依赖任何外部美术资源，打开即可运行。

## 功能

- `CharacterBody3D` 胶囊体角色：重力、跳跃、加速/减速平滑、空中控制
- 移动方向相对于相机朝向（WASD / 方向键），Shift 冲刺
- 角色模型平滑转向移动方向
- `SpringArm3D` 第三人称轨道相机：鼠标视角（俯仰角限制）、滚轮缩放、撞墙自动拉近
- 关卡：地面、围墙、箱子、斜坡 + 平台、台阶、柱子、浮空跳台
- 可推动的 `RigidBody3D` 黄色箱子
- `DirectionalLight3D` 实时阴影 + `WorldEnvironment` 程序化天空（SSAO / Glow / 雾）
- 屏幕左上角操作提示，左下角显示 FPS / 速度 / 鼠标状态
- 掉出地图或按 R 自动回到出生点

## 操作

| 按键 | 作用 |
| --- | --- |
| W A S D / 方向键 | 移动（相对相机方向） |
| Shift | 冲刺 |
| Space | 跳跃 |
| 鼠标移动 | 旋转视角 |
| 鼠标滚轮 | 拉近 / 拉远相机 |
| Esc | 释放鼠标 |
| 鼠标左键 | 重新锁定鼠标 |
| R | 回到出生点 |

输入映射定义在 `project.godot` 的 `[input]` 段，可在 *项目设置 → 输入映射* 中修改。

## 运行

1. 下载 [Godot 4.x](https://godotengine.org/download)（已在 **4.7.2-stable** 上验证，4.3+ 均可）。
2. 打开 Godot，选择 *导入*，选中本目录下的 `project.godot`。
3. 按 **F5** 运行（主场景为 `res://scenes/main.tscn`）。

命令行方式：

```bash
# 直接运行游戏
godot --path .
# 打开编辑器
godot -e --path .
# 无头模式导入 + 冒烟测试
godot --headless --path . --import
godot --headless --path . --quit-after 300
```

## 目录结构

```
project.godot        项目配置（主场景、输入映射）
icon.svg             项目图标
scenes/main.tscn     主场景：环境、灯光、关卡、可推箱子、玩家、HUD
scenes/player.tscn   玩家：CharacterBody3D + 胶囊模型 + SpringArm3D 相机
scripts/player.gd    角色控制与相机逻辑
scripts/hud.gd       HUD 状态显示
```

## 可调参数

在编辑器中选中 `Player` 节点，可以在检查器中直接调整：`walk_speed`、`sprint_speed`、`jump_velocity`、`acceleration`、`rotation_speed`、`mouse_sensitivity`、俯仰角限制、缩放范围、推箱子力度等。
