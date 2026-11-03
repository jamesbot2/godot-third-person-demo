# MOVEMENT_SPEC — 运动系统规格

所有数值均为 `@export` 参数，单位为 SI（m、s、m/s、m/s²、kg、N）。下表的“预测”由公式给出，“实测”取自
`tests/results/headless_60hz.txt`（真实输出）。

## 1. 架构

- `PlayerController`（`CharacterBody3D`，扁平圆柱碰撞体 r=0.35 m，站 1.80 / 蹲 1.15 / 滑铲·翻滚 1.00 m）。
- 状态机：`GROUND`、`AIR`、`SLIDE`、`ROLL`、`TRAVERSE(VAULT|MANTLE)`。每个物理 tick 只有一个状态在写速度；转换集中在 `_physics_process`，避免状态互相抢写。
- 积分：中点积分（`v_mid = v + a·dt/2`）+ 起跳冲量在 tick 开始时施加 → 30/60/120 Hz 跳高、刹车距离一致（见 TEST_REPORT）。
- `StepSolver`：`PhysicsServer3D.body_test_motion` 三段扫掠（上抬 → 前移 → 下落）。只有在 (a) 前方确实被挡住、(b) 落点是可走地面、(c) 落点上方有 `step_min_depth` 的踏面、(d) 高度 ≤ `max_step_height` 时才抬升 —— **不会无条件抬升**。
- `_ground_probe()`：离地时向下扫掠 `max_step_height+0.05`，可走地面则吸附（下楼梯不腾空）；若被边缘挡住且脚部高度差在 [-0.035, 0.02] m，视为“站在边缘上”。修复了 120 Hz 下边缘接触导致的 AIR 抖动。
- `CameraRig`：top-level 节点，水平刚性跟随、垂直按地面/空中不同速率跟随，相机臂用球形 `cast_motion` 防进墙。
- 物理层：1 世界、2 道具、3 玩家（玩家 layer 4 / mask 3；箱子 layer 2 / mask 7）。

## 2. 地面运动

| 参数 | 值 | 含义 |
|---|---|---|
| walk / jog / sprint_speed | 1.8 / 4.2 / 6.8 m/s | 走 / 慢跑 / 冲刺目标速度 |
| crouch_speed / aim_speed | 2.0 / 3.0 | 蹲、瞄准 |
| strafe_factor / backpedal_factor | 0.9 / 0.72 | 瞄准时侧移、后退倍率 |
| uphill_speed_factor | 0.75 | 在最陡可走坡正面上坡时的速度倍率（按坡度线性） |
| ground_accel | 22 | 0→jog 推进加速度 |
| sprint_accel | 9 | jog 以上的加速度（冲刺需要“蓄速”） |
| brake_decel | 26 | 无输入刹车 |
| turn_grip | 34 | 去除与输入方向不一致的速度分量（侧向抓地、反向刹车） |
| overspeed_decel | 12 | 超出当前目标速度时减速（松开冲刺、滑铲后） |
| turn_rate_slow / fast / air | 900 / 420 / 160 °/s | 模型朝向转速（低速快、高速慢、空中最慢） |

| 量 | 预测 | 实测 (60 Hz) |
|---|---|---|
| jog 达到 90% 时间 | 0.9·4.2/22 = 0.172 s | 0.183 s |
| jog 刹车距离 | 4.2²/(2·26) = 0.339 m | 0.340 m |
| sprint 刹车距离 | 6.8²/(2·26) = 0.889 m | 0.890 m |
| sprint 达到 95% | — | 0.450 s |
| 180° 反向到 90% | — | 0.300 s |

## 3. 跳跃与空中

| 参数 | 值 | 含义 |
|---|---|---|
| jump_height | 0.9 m | 满跳顶点高度；起跳速度 v0 = √(2·g_rise·h) = 4.74 m/s |
| gravity_rise / gravity_fall | 12.5 / 18 | 上升 / 下落重力，下落更重 → 不“飘” |
| jump_cut_multiplier | 2.6 | 上升中松开跳跃时重力倍率（可变跳高） |
| terminal_speed | 35 | 终端速度 |
| air_accel | 3 | 空中水平加速度（转向而非飞行） |
| air_min_control_speed | 1.0 | 从静止起跳时空中控制最多能建立的水平速度 |
| air_brake | 1.0 | 空中对当前动量的最大反向减速 |
| coyote_time / jump_buffer_time | 0.12 / 0.15 s | 离地宽限 / 提前按跳缓冲 |

预测滞空 = 4.74/12.5 + √(2·0.9/18) = 0.695 s；实测 0.683 s、顶点 0.900 m、短按顶点 0.393 m。连续 6 跳最大水平速度 6.80（= sprint，不累积）。

## 4. 落地

冲击速度 < 6.5 m/s 轻落地；6.5–10.5 中（保留 80% 水平速度，恢复 0.15 s）；≥10.5 重（保留 35%，恢复 0.45 s，0.2 s 内不能跳）。落地瞬间按翻滚可卸力（取消恢复）。实测 2 m 落差 8.55 m/s → 中；4 m 落差 12.15 m/s → 重。

## 5. 地形

| 参数 | 值 | 含义 |
|---|---|---|
| max_step_height | 0.40 m | 自动上台阶上限（0.15/0.25/0.35/0.40 通过，0.50 拦截） |
| step_min_depth | 0.12 m | 台阶顶部最小踏面深度 |
| max_slope_deg | 45° | 可走坡度（上坡减速、站立不滑） |
| slope_contact_tolerance_deg | 3° | 物理地面判定的额外容差：坡脚边缘接触法线是面与地的混合（40° 坡上实测 44–46°），没有容差时 120 Hz 会卡在坡脚。50° 坡仍被拒绝 |

## 6. 动作（触发 / 取消 / 冷却）

| 动作 | 触发 | 取消 | 结束 / 冷却 |
|---|---|---|---|
| 蹲 | C 切换 / Ctrl 按住 | 再按 / 松开；头顶有障碍时不会站起 | — |
| 滑铲 | 冲刺且速度 ≥ 5.0 时按蹲；入场 +1.0 m/s（上限 8.0，1.2 s 内不重复加速） | 跳跃（保留水平速度） | 速度 < 2.6 或 1.6 s；冷却 0.45 s；动摩擦 5 m/s²（μ≈0.5），坡上受 0.85 g 分量 |
| 翻滚 | V（地面，含静止） | 进行到 70% 后可跳跃取消 | 0.6 s，6.8→3.0 m/s；冷却 0.5 s；低矮碰撞体 1.0 m |
| 翻越 | 跳跃 + 前方 ≤ reach 处有 ≤1.15 m 高、≤0.6 m 厚的障碍 | — （运动学路径） | 出口 3.5 m/s；时长 0.40+0.12h+接近距离/速度 |
| 攀爬 | 跳跃 + 前方 ≤1.6 m 台面；空中可抓 ≤1.25 m 的边 | — | 出口 2.0 m/s；时长 0.35+0.25h+接近距离/速度 |

检测距离 `reach = traverse_reach(0.7) + min(水平速度·0.1, 0.6)`。翻越/攀爬路径：前 55% 用 smoothstep 抬升 + a² 缓入贴近墙面，后 45% smoothstep 越过 —— 峰值竖直速度 ≈ 4–5 m/s（旧版为 6.5 m/s 的“弹射”感）。2.3 m 墙拒绝。

## 7. 推箱子

推力取“意图速度”（输入方向 × 目标速度）而不是被碰撞清零后的速度，并在前方 0.04 m 做 `test_move` 探测接触；冲量受 `push_force_max = 450 N` 限制。轻箱可推动，重箱基本不动，玩家不会被箱子顶起。

## 8. 相机

| 参数 | 值 | 含义 |
|---|---|---|
| distance / zoom_min / zoom_max | 3.6 / 1.8 / 6.0 m | 相机臂长与缩放范围 |
| shoulder_offset | 0.55 m | 右肩偏移 |
| height_stand / crouch / low | 1.55 / 1.15 / 0.9 m | 枢轴高度（平滑 8/s） |
| follow_v_ground / air | 14 / 4 1/s | 垂直跟随速率（上楼梯平滑，跳跃不跟抖） |
| max_v_lag | 0.6 m | 垂直滞后上限 |
| collision_radius | 0.22 m | 相机球形碰撞半径 |
| pull_out_rate | 5 1/s | 障碍消失后回弹速率（拉近是瞬时的） |
| min_distance | 0.35 m | 低于此距离隐藏角色模型 |
| fov_base / sprint_add / slide_add | 72 / +6 / +4 ° | FOV |
| dip_* | 0.3 / 3.0 / 120 | 落地下沉弹簧 |

## 9. 角色动画（Round 2，`scripts/player/character_animator.gd`）

原则：**物理控制器是唯一权威**。动画只读取控制器状态来表现，片段的根运动在构建时被丢弃（只保留旋转 + 按比例缩放的骨骼盆骨位置），永远不会出现“根运动和控制器同时位移”。

- 节点：`Player(CharacterBody3D) > Model(CharacterAnimator) > UBCMale > Skeleton3D(65 骨, UE 命名) + 网格`，子节点 `BodyPoseModifier`、`ArmIK(TwoBoneIK3D)`；`AnimationPlayer` + `AnimationTree`（`AnimationNodeStateMachine`）。
- 每帧从控制器暴露的参数：`p_speed`、`p_local_dir`、`p_accel`、`p_turn_rate`、`p_grounded`、`p_vy`、`p_state`、`p_slope_deg`、`p_land_severity`。
- 状态：`ground`（idle/walk/jog/sprint 混合 + 蹲混合）、`air`（jump_start→jump_air / 下落用 ninja_air 收腿）、`slide`、`roll`、`vault`、`mantle`。过渡带 xfade（0.08–0.2 s），不跳帧。
- 步态：`_solve_gait(v)` 在实测步幅表（`tools/calibrate_stride.gd` 测出的每个片段每周期前进距离）上插值，`cycle_rate = v / stride`，所有循环片段相位同步（Blend2 + 统一 TimeScale），切换档位时脚不换相。
- 起步/停步/转身/侧移/后退：**CC0 包里没有专门片段**。用加速度驱动的前倾（atan(a/g)·0.55，−9°…+10°）、刹车后仰、按向心加速度的侧倾（≤14°）、按局部移动方向的下肢扭转（warp）来表现；后退时循环反向播放。
- 跳跃：jump_start（预备）→ jump_air（上升/滞空）→ 下落按 vy（−0.5…−5 m/s）混入 jump_land 第 0 帧（伸腿准备着地）→ jump_land，落地权重 = 落地严重度（软/中/重），重落地追加骨盆下沉与恢复时间。
- 滑铲：Slide_Start → Slide → Slide_Exit，seek 到 `slide_time` 对应位置；蹲起与控制器胶囊高度同步。
- 翻滚：Roll 片段从 `ROLL_T0 = 0.36 s`（跳过片段开头的水平飞扑段）起，按 `roll_time / roll_duration` seek，模型本身不做任何旋转（测试 `anim_roll` 断言 model_tilt = 0）。
- 翻越 / 攀爬（Round 3 起）：见 §9.y。Round 2 的 ClimbUp_1m + ninja_air 拼接方案已被替换。
- 注意（Godot 4.7）：`SkeletonModifier3D`（BodyPoseModifier、TwoBoneIK3D）的结果只在骨骼更新内部有效；在别处调用 `get_bone_global_pose` 拿到的是修改器之前的姿态。`CharacterAnimator` 在 `skeleton_updated` 时快照最终姿态，`get_final_bone_world()` 返回渲染用的最终骨骼位置（测试也用它）。


### 9.x 脚部锁定 / 落脚 IK（Round 3，`scripts/player/foot_ik_modifier.gd`）

| 参数 | 值 | 说明 |
|---|---|---|
| PLANT_H / RELEASE_H | 0.03 / 0.06 m | 动画接触高度 min(球骨−0.0152, 踝骨−0.0865) 的锁定/释放阈值 |
| max_lock_offset | 0.24 m | 钉住点与动画脚距离超过即释放（进入冷却，抬脚 ≤5 cm 追回）|
| max_lock_yaw | 0.6 rad | 锁定后身体偏航超过即释放 |
| max_lock_drop | 0.34 m | 锁定脚比身体低超过即释放（楼梯）|
| max_pelvis_drop | 0.26 m | 骨盆最大下沉 |
| 鞋底高度 | 踝 ≥ 地面+0.093，球骨 ≥ 地面+0.024 | 不入地 |
| 生效 | 仅 GROUND 且动画为 ground | 淡入 10/s，淡出 30/s；物理控制器仍是唯一位移权威，IK 只改骨骼 |


### 9.y 翻越 / 攀爬：真实片段 + 接触驱动视觉根（Round 3，`character_animator.gd::_drive_traverse_contact`）

> **2026-11-03 更新**：这些片段许可证存疑（见 THIRD_PARTY），只在本机 extras 模式可用；仓库默认的 core 模式见 §9.z。

片段（仅 extras 模式）：Quaternius UAL1 Pro / UAL2 Source 级付费内容，经第三方 Drawcall Market 转发，`tools/retarget_drawcall.gd` 重定向到 UE 65 骨：
翻越 = `vault_safety`（safety-vault），攀爬 = `climb_up_2m`（从 MANTLE_T0 = 0.24 s 起播，跳过 2 m 版本的下蹲起跳）。
片段没有根骨，位移只在盆骨轨道里；**控制器仍是唯一位移权威**，下面的一切只移动 `character.position`（视觉偏移）和骨骼。

1. 片段时间 t 由控制器轨迹进度 u 驱动（翻越：u 0–0.15 → 0–VAULT_PLANT 0.07，0.15–0.75 → 至 VAULT_RELEASE 0.48；攀爬：t = lerp(0.24, 1.30, u)）。
2. `ClipSampler` 在 `_ready` 用真实骨架离线采样片段中手/脚/球骨/盆骨/上臂的位置（60 Hz）。
3. 视觉根：
   - 手撑阶段：root_y = 墙顶 + PALM_H(0.03) − 片段手高；root_f = 前沿 + HAND_INSET(0.06) + 片段手前后 → 片段里的手正好落在台面上。
   - 攀爬 t ≥ MANTLE_FEET(0.91)：root_y = 台面 − `sole_min(t)`（片段中最低鞋底），即脚踩在台面上。
   - 钳制：鞋底不低于起点地面；任一只脚预测位于障碍物顶面范围（前沿 → `_find_back_face` 射线测得的后沿）时鞋底不低于顶面；
     顶面以下的脚不超过前立面（`root_f` 后推）。
   - 攀爬 u 0.9–1.0 偏移淡出到 0，交还给胶囊，无跳变。
4. 手：每侧一个 `TwoBoneIK3D`。目标点在第一次有权重时固定（世界坐标）；攀爬时目标从片段（FK）手的位置出发，**先升到台沿上方再向内落到撑点**
   （顶面以下时目标不越过前立面），所以伸手不会穿过台沿角。若肩到撑点距离超过臂长（视觉根被脚部钳制抬高），该手权重按超出量 0–3 cm 淡出，
   即“手离开台面”，而不是 IK 报告满权重但手腕悬空。`hand_contact[i]` = 撑稳（目标在撑点且权重 > 0.99），测试用它判定。
5. 鞋底深度常量 `ClipSampler.SOLE`：球骨 0.024 m，踝骨 0.093 m。

**物理插值下的取值时机（关键发现，Godot 4.7.2 源码核对）**：`SceneTree::process` 在帧开始（`_process` 之前）做 FTI 第 1 遍，
在 `_process` 与空闲回调之后做第 2 遍，渲染使用第 2 遍。`get_global_transform_interpolated()` 对可见节点返回第 1 遍缓存，
**不包含本帧 `_process` 中改过的局部变换**（character.position 偏移、模型偏航），所以晚一帧；骨骼修改器（延迟骨骼更新）在两遍之间运行，
`TwoBoneIK3D` 用 `skeleton.get_global_transform_interpolated()` 把目标变到骨架空间 → 目标错位，误差随视觉偏移的帧间变化而变，**这就是攀爬手部接触随物理频率变化的原因**。
修复：`render_xf(n) = 胶囊插值变换 × (胶囊⁻¹ × n.global_transform)`（胶囊只在物理帧移动，第 1 遍缓存是新的）；脚部 IK 与最终姿态快照用 `render_xf`；
手部 IK 目标经由骨架下的**隐藏**子节点喂入（隐藏节点按需计算 = 最近可见祖先的缓存 × 当前局部），IK 看到的骨架空间目标与我们算的完全一致。


### 9.z 翻越 / 攀爬：core 模式（仅 CC0 Standard 片段，`_drive_traverse_core` / `_plan_core_lift` / `_core_traverse_post`）

- 姿态：攀爬 = `ClimbUp_1m` 循环按 u 播放；翻越 = 前段 `ClimbUp_1m` 与 `NinjaJump_Idle` 收腿姿态按 smoothstep(0.2, 0.45, u) 混合。
- 控制器轨迹对 u 是确定的，`_core_cap_at(u)` 复现它。进入 TRAVERSE 时 `_plan_core_lift` 对 u 采样 96 点，生成视觉根偏移表：
  1. 基础偏移 = 时间表（攀爬：起点高度 + h·smoothstep(0.12,0.72,u)；翻越：越墙时把高出的胶囊压回）；
  2. 撑手窗口内把偏移钳到“肩到撑点距离 ≤ 0.93·臂长”的范围（撑点：左右 ±0.2 m，前沿内 0.07/0.12 m，顶面 + 0.03）；
  3. ±0.1u 滑动平均；
  4. 预测哪只鞋底在台面范围内，要求其 ≥ 顶面 + 0.02，提前 0.2u 抬起、保持 0.1u。
- 后处理（每帧）：剩余够不到量按撑手权重修正；鞋底抬升取各脚最大值（不累加）；手 IK 在整个 TRAVERSE 中权重恒为 1，
  “FK 手 → 撑点”的混合放在 IK 目标里（有效权重 = 时间表 × 软可达性，按 6.5/s 限速），目标钳出障碍体。
  `hand_contact` 只在有效权重 > 0.99、可达、目标在撑点上时为真。
- 攀爬撑手窗口：smoothstep(0.02,0.2,u) × (1 − smoothstep(0.5,0.88,u))；翻越：smoothstep(0.12,0.3) × (1 − smoothstep(0.6,0.78))。
