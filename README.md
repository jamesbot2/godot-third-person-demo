# Godot 4 第三人称拟真运动系统（Graybox Demo）

Godot **4.7.2** / GDScript / Jolt Physics。目标是“物理可信 + 响应快 + 动作流畅”的第三人称移动手感
（参考对象为 ARC Raiders 这类写实撤离射击游戏的**可观察**移动表现；本项目不包含、也不声称了解其任何专有代码、资源或内部实现）。
场景是程序化灰盒几何体；角色是 **Quaternius Universal Base Characters（CC0）** 的蒙皮人形 + **Universal Animation Library 1/2（CC0）** 骨骼动画（来源与构建见 [THIRD_PARTY.md](THIRD_PARTY.md)）。

> 开发分支：`dev/movement-system`（`main` 保持为最初的稳定 demo）。
> 文档：[MOVEMENT_SPEC.md](MOVEMENT_SPEC.md)（参数与公式） · [TEST_REPORT.md](TEST_REPORT.md)（真实测试输出） ·
> [ITERATION_LOG.md](ITERATION_LOG.md)（迭代记录） · [THIRD_PARTY.md](THIRD_PARTY.md)（参考来源与许可证）

## 功能

- **地面运动**：走/慢跑/冲刺三档速度，分离的加速、刹车、转向抓地参数；侧移/后退减速；冲刺需要“蓄速”，松开后逐步回落；上坡减速。
- **跳跃/空中**：按高度定义跳跃（0.9 m），上升/下落不同重力，可变跳高（短按 0.39 m），Coyote time 0.12 s，跳跃缓冲 0.15 s，有限空中控制，不能连跳加速（no bhop）。
- **地形**：StepSolver（`body_test_motion` 扫掠）上台阶 ≤0.40 m，0.50 m 拦截；下台阶/下楼梯贴地不腾空；坡度 ≤45°（+3° 接触容差）可走，50° 拒绝；陡坡不滑移；高速撞墙不穿透。
- **动作**：蹲（切换/按住）、滑铲、翻滚、翻越（≤1.15 m 薄墙）、攀爬（≤1.6 m，含空中抓边）、落地分级（轻/中/重 + 翻滚卸力）。每个动作有明确的触发、取消、冷却。
- **相机**：独立 top-level 相机架，球形碰撞拉近（不进墙）、平滑回弹、滚轮缩放、肩部偏移、冲刺/滑铲 FOV、落地下沉弹簧、蹲伏高度过渡、极近时隐藏模型。
- **骨骼角色动画（Round 2）**：`CharacterAnimator` = Skeleton3D(65 骨) + AnimationPlayer + AnimationTree 状态机（ground/air/slide/roll/vault/mantle）。
  地面为相位同步的 idle→walk→jog→sprint 混合，播放速率 = 速度/实测步幅（防滑步）；蹲/蹲走混合；起跳/滞空/落地按落地严重度加权；
  滑铲与翻滚用真实动画片段并**按控制器进度 seek**（不是整体机械旋转）；翻越/攀爬按控制器轨迹进度 seek，并用 `TwoBoneIK3D` 把双手按到墙顶/台沿。
  `BodyPoseModifier` 做加减速前倾、转弯侧倾、移动方向扭转、坡面骨盆下沉。物理控制器始终是唯一位移来源（动画的根运动被丢弃）。
  旧的灰盒人形 `graybox_body.gd` 仍保留在仓库中但不再是正式角色。
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

当前结果（见 `tests/results/`）：30/60/120 Hz 均 99/99（core 模式，仓库默认；原 86 项 + Round 3 新增 6 项瞄准方向移动 + 2 项起停 + 2 项原地转身 + Round 4 新增 3 项：翻越/攀爬单帧跳变、180° 急转腿部间距、后退步态）。本机 extras 模式（不随仓库发布）为 97/99：extras 自带的后退片段和翻越/攀爬片段没有通过 Round 4 新增的两项检查（`headless_*hz_local_extras.txt`）。

动画模式：仓库只含 CC0 Standard 片段（core 模式，翻越/攀爬为程序化拼接）。真实翻越/攀爬/转身片段来自第三方 Drawcall Market 转发的
Quaternius 付费级内容，许可证**存疑**，不提交；可在本机运行 `tools/fetch_drawcall.sh` + `tools/retarget_drawcall.gd --build`
生成 git 忽略的 `assets/animations/local/ual_extra.res`（extras 模式）。`UAL_EXTRAS=0` 强制 core 模式。详见 THIRD_PARTY.md。

```bash
# 可视化展示（必须非 headless，需要 X 显示；录制 avi，再用 ffmpeg 转 mp4）
DISPLAY=:17 godot --path . --rendering-driver opengl3 --fixed-fps 30 \
  --resolution 1280x720 --write-movie /tmp/showcase.avi -s res://tools/showcase.gd -- --shots=/tmp/shots
# 只跑部分段落：-- --shots=/tmp/shots --only=roll,vault,mantle
ffmpeg -i /tmp/showcase.avi -c:v libx264 -pix_fmt yuv420p showcase.mp4
# 重新构建角色/动画资源（需先下载原始包，见 THIRD_PARTY.md）
tools/fetch_quaternius.sh universal-base-characters /workspace/assets_raw/ubc
tools/fetch_quaternius.sh universal-animation-library /workspace/assets_raw/ual1
tools/fetch_quaternius.sh universal-animation-library-2 /workspace/assets_raw/ual2
godot --headless -s res://tools/build_character_assets.gd -- --src=/workspace/assets_raw/
```

## 目录

```
scenes/main.tscn                 主场景（环境/灯光/测试场/箱子/玩家/HUD）
scenes/player.tscn               玩家（CharacterBody3D + 灰盒模型 + 相机架）
scripts/player/player_controller.gd   运动状态机与全部运动学
scripts/player/step_solver.gd         上台阶扫掠求解
scripts/player/character_animator.gd  骨骼角色：AnimationTree 状态机、步幅匹配、seek 动作、手部 IK、姿态修改器
scripts/player/graybox_body.gd        旧灰盒人形（不再使用）
assets/characters/ubc_male/           UBC 男性角色（CC0，构建产物）
assets/animations/ual_clips.res       UAL1/2 Standard 动画片段（CC0，构建产物，根运动已去除）
assets/animations/local/              （git 忽略）本机可选 extras 片段库
assets/licenses/                      原始许可证文本
tools/build_character_assets.gd       资源构建（glTF→.scn/.res，重定向、去根运动、纹理）
tools/fetch_quaternius.sh             从 itch.io 免登录下载 $0 包
scripts/camera/camera_rig.gd          第三人称相机架
scripts/level/course_layout.gd        测试场尺寸常量（测试与关卡共用）
scripts/level/graybox_course.gd       测试场生成
scripts/hud.gd                        HUD
tests/run_tests.gd                    自动化测试（99 项）
tools/showcase.gd                     可视化自动驾驶展示 + 截图
```
