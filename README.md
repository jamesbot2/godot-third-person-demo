# Godot 4 第三人称拟真运动系统（Graybox Demo）

Godot **4.7.2** / GDScript / Jolt Physics。目标是“物理可信 + 响应快 + 动作流畅”的第三人称移动手感
（参考对象为 ARC Raiders 这类写实撤离射击游戏的**可观察**移动表现；本项目不包含、也不声称了解其任何专有代码、资源或内部实现）。
场景和角色全部是程序化灰盒几何体，无外部美术资源。

> 开发分支：`dev/movement-system`（`main` 保持为最初的稳定 demo）。
> 文档：[MOVEMENT_SPEC.md](MOVEMENT_SPEC.md)（参数与公式） · [TEST_REPORT.md](TEST_REPORT.md)（真实测试输出） ·
> [ITERATION_LOG.md](ITERATION_LOG.md)（迭代记录） · [THIRD_PARTY.md](THIRD_PARTY.md)（参考来源与许可证）

## 功能

- **地面运动**：走/慢跑/冲刺三档速度，分离的加速、刹车、转向抓地参数；侧移/后退减速；冲刺需要“蓄速”，松开后逐步回落；上坡减速。
- **跳跃/空中**：按高度定义跳跃（0.9 m），上升/下落不同重力，可变跳高（短按 0.39 m），Coyote time 0.12 s，跳跃缓冲 0.15 s，有限空中控制，不能连跳加速（no bhop）。
- **地形**：StepSolver（`body_test_motion` 扫掠）上台阶 ≤0.40 m，0.50 m 拦截；下台阶/下楼梯贴地不腾空；坡度 ≤45°（+3° 接触容差）可走，50° 拒绝；陡坡不滑移；高速撞墙不穿透。
- **动作**：蹲（切换/按住）、滑铲、翻滚、翻越（≤1.15 m 薄墙）、攀爬（≤1.6 m，含空中抓边）、落地分级（轻/中/重 + 翻滚卸力）。每个动作有明确的触发、取消、冷却。
- **相机**：独立 top-level 相机架，球形碰撞拉近（不进墙）、平滑回弹、滚轮缩放、肩部偏移、冲刺/滑铲 FOV、落地下沉弹簧、蹲伏高度过渡、极近时隐藏模型。
- **灰盒人形**：程序化姿态（走跑摆臂、蹲、滑铲、翻滚、翻越、攀爬、落地）。
- **测试场**：台阶 0.15/0.25/0.35/0.40/0.50 m、0.18/0.30 楼梯、0.25 陡楼梯、10–50° 坡道、塔楼、窄走廊、低矮隧道、翻越墙/攀爬台/过高墙、轻/重可推箱子、相机碰撞区（柱子/顶棚/墙）。

## 操作

| 按键 | 作用 |
| --- | --- |
| W A S D / 方向键 | 移动（相对相机） |
| Shift | 冲刺 |
| Space | 跳跃（长按跳更高）；贴近矮墙按 = 翻越 / 攀爬 |
| C | 蹲（切换）；冲刺中按 C = 滑铲 |
| Ctrl | 蹲（按住） |
| V | 翻滚 |
| 鼠标右键 | 瞄准（平移、减速） |
| CapsLock / Z | 走路切换 |
| 鼠标 / 滚轮 | 视角 / 缩放 |
| F1 | 调试信息 |
| R | 重置位置 |
| Esc | 释放鼠标 |

## 运行

```bash
godot --path .            # 运行
godot -e --path .         # 编辑器
```

## 测试

```bash
# 无头自动化测试（时间以物理 tick 计，不依赖墙钟），30/60/120 Hz 各跑一遍
for hz in 30 60 120; do
  godot --headless --fixed-fps $hz -s res://tests/run_tests.gd -- --hz=$hz
done
# 输出：RESULT|PASS/FAIL|名称|细节 、METRIC|名称|值 、SUMMARY|hz|pass|fail
```

当前结果（见 `tests/results/`）：30 Hz 73/73、60 Hz 73/73、120 Hz 73/73。

```bash
# 可视化展示（必须非 headless，需要 X 显示；录制 avi，再用 ffmpeg 转 mp4）
DISPLAY=:7 godot --path . --rendering-driver opengl3 --fixed-fps 30 \
  --write-movie /tmp/showcase.avi -s res://tools/showcase.gd -- --shots=/tmp/shots
ffmpeg -i /tmp/showcase.avi -c:v libx264 -pix_fmt yuv420p showcase.mp4
```

## 目录

```
scenes/main.tscn                 主场景（环境/灯光/测试场/箱子/玩家/HUD）
scenes/player.tscn               玩家（CharacterBody3D + 灰盒模型 + 相机架）
scripts/player/player_controller.gd   运动状态机与全部运动学
scripts/player/step_solver.gd         上台阶扫掠求解
scripts/player/graybox_body.gd        程序化灰盒人形姿态
scripts/camera/camera_rig.gd          第三人称相机架
scripts/level/course_layout.gd        测试场尺寸常量（测试与关卡共用）
scripts/level/graybox_course.gd       测试场生成
scripts/hud.gd                        HUD
tests/run_tests.gd                    自动化测试（73 项）
tools/showcase.gd                     可视化自动驾驶展示 + 截图
```
