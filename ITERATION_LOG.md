# ITERATION_LOG

流程：OBSERVE → RESEARCH → DESIGN → IMPLEMENT → VALIDATE → EVALUATE → REPRIORITIZE。每轮结束时 30/60/120 Hz 全量测试；让手感变差的改动回退。

## Cycle 0 — 观察（基线：main 上的初版 demo, bfc284d）

- 胶囊体 + SpringArm 相机 + 简单 lerp 加速；无台阶求解、无动作系统、无测试。
- **初始发现 Top-3**
  1. HUD 每帧重新排版 CJK 文本，在软件渲染下每帧约 55 ms —— 性能问题掩盖了所有手感评估（改为 10 Hz 刷新 + 字体缓存）。
  2. 运动缺少可解释的物理参数（加速/刹车/转向混在一个 lerp 里，帧率相关）；台阶只能靠胶囊滑上去，楼梯会弹跳。
  3. 相机臂最短距离钳制会把相机推进墙里；没有任何自动化回归手段。

## Cycle 1 — 控制器重写（df24308）

- 研究：Godot CharacterBody3D 文档、Jeh3no 状态机控制器、PantheraDigital GodotCharacterStep、Andicraft stairs-character、SUCC（见 THIRD_PARTY.md；只参考思路，独立实现）。
- 实现：状态机（GROUND/AIR/SLIDE/ROLL/TRAVERSE）、分离加速/刹车/抓地参数、中点积分、按高度定义的跳跃、coyote/buffer、StepSolver、坡度处理、滑铲/翻滚/翻越/攀爬、落地分级、top-level 相机架、程序化灰盒人形、测试场、73 项 headless 测试。
- 发现并修复：
  - 测试在攀爬后没松开输入导致走下平台 → 测试 bug，增加 `wait_traverse` 并释放输入。
  - 翻越检测距离过短（冲刺时来不及触发）→ 检测距离随速度增加。
  - 相机最短距离钳制导致相机在墙内 → 去掉钳制，改为低于 0.35 m 时隐藏模型；600 次采样 0 次在几何体内。
- 结果：60 Hz 73/73；但 30/120 Hz 存在失败（进入 Cycle 2）。

## Cycle 2 — 帧率无关性（f2e99e5 及之后）

- 120 Hz：上台阶/下楼梯时边缘接触造成 AIR 闪烁、下楼梯自由落体、相机每 tick 跳 0.10 m → 新增 `_ground_probe()` 向下扫掠吸附 + 边缘站立判定；相机峰值降为 0.040 m/tick，ungrounded_ticks=0。
- 推箱子在 60/120 Hz 完全推不动（碰撞后速度已被清零，冲量为 0）→ 使用意图速度 + 前方 test_move 接触探测，力上限 450 N。
- 30 Hz 模糊测试：翻越期间 vy 6.56 m/s 的“弹射” → 翻越/攀爬路径改为 smoothstep 抬升 + 缓入，时长随高度与接近距离增加；最大 vy ≈ 4.5 m/s。
- 120 Hz 40° 坡脚卡住：坡脚边缘接触法线 ≈ 45.6° 超过 45° 限制 → `slope_contact_tolerance_deg = 3°`；50° 坡依然拒绝。
- 30 Hz 跳跃缓冲测试的判定窗口过窄 → 测试 bug，修复判定。
- 结果：**30 Hz 73/73，60 Hz 73/73，120 Hz 73/73**。

## Cycle 3 — 可视化验收

- `tools/showcase.gd`：通过真实输入动作驱动的自动驾驶脚本，覆盖走/跑/冲刺/刹车、楼梯上下、0.35 m 台阶通过 / 0.50 m 拦截、30° 坡 / 50° 拒绝、跳跃与落地、滑铲、翻滚、翻越、攀爬、相机碰撞环绕、推箱子，并记录状态切换。
- 非 headless 渲染（Xvfb + llvmpipe）录制 39 s mp4 + 23 张截图。
- 观察：在 0.9 m 墙前约 2.4 m 就按跳，会是一次普通跳跃（0.9 m 跳高刚好越过 0.9 m 墙），而不是翻越动作；在约 1 m 处按跳则稳定触发 VAULT。记录为已知行为。
- 自建的 Xvfb :7 在运行约 35–50 s 后被外部结束（原因不明），最终在已有的 DISPLAY=:6 上完成录制。

## Cycle 4 — Round 2：骨骼角色替换（57f8c36, 910cc83, f1b327c）

- 资源：Mixamo 需 Adobe 登录（https://www.mixamo.com/）且不允许再分发 → 阻塞，未用。改用 Quaternius UBC + UAL1/UAL2（CC0），`tools/fetch_quaternius.sh` 免登录 $0 下载，`tools/build_character_assets.gd` 构建（去根运动、盆骨按腿长缩放）。
- `CharacterAnimator`：AnimationTree 状态机，相位同步、按实测步幅匹配速率的地面混合；seek 式一次性动作（滑铲/翻滚/翻越/攀爬按控制器进度）；`BodyPoseModifier` 做前倾/侧倾/扭转/骨盆下沉。
- 新增 t_anim 测试，82/82 @30/60/120 Hz（当时在修改器前的姿态上测量，见 Cycle 5）。

## Cycle 5 — 翻越/攀爬接触、翻滚、测量修正（2ba6b41 及之后）

- 发现：Godot 4.7 的 `SkeletonModifier3D` 结果只在骨骼更新内部有效，别处 `get_bone_global_pose` 是修改器前的姿态 → 在 `skeleton_updated` 快照，测试改用 `get_final_bone_world()`。
- `TwoBoneIK3D`（ArmIK）把双手按到墙顶/台沿，肘部极向量在后外下方；视觉根下压/前移 + 前倾，让身体与障碍物接触而不是“飘在旁边”。
- 攀爬视觉根高度曲线调到 smoothstep(0.2,0.95)：更早(0.12,0.92) 30 Hz 手部接触不足；更晚(0.25,1.0) 脚穿入台面 9–12 cm。曾尝试“按肩部可达距离额外下压”，导致脚穿入 38–46 cm，已回退。
- 翻滚跳过片段开头的水平飞扑（ROLL_T0 0.12→0.36，xfade 0.14）。
- 纹理修复：`keep_compressed_buffer = true`。
- 新增 anim_vault_contact / anim_mantle_contact → 84/84 @30/60/120 Hz。
- 可视化：showcase 按动作进度截图（wait_progress），攀爬相机抬高；`/workspace/acceptance/round2/` 产出 mp4/截图/特写/联系表（软件渲染）。

## Cycle 6 — Round 3：脚部锁定 / 落脚 IK

- 新 `FootIKModifier`（SkeletonModifier3D，顺序 BodyPose → FootIK → ArmIK）。着地判定用动画接触高度（<0.03 锁定，>0.06 释放）；
  世界坐标钉住球骨；踝骨目标由钉住的球骨反推（这是让滑移真正归零的关键：之前只钉踝骨，脚掌姿态修正又把球骨推走，残留 0.2–0.5 m/s）。
- 踝/球骨各一条向下射线（root+0.55 → root−0.75），支撑高度平滑（上升 60/s、下降 22/s）；<35° 时按地面法线倾斜脚掌；
  解算后再做一次“最终踝/球骨对地”检查（腿伸直时踝骨会偏向髋部，脚尖撞台阶立面 → 抬踝/抬脚尖）。
- 骨盆下沉 = max(最低脚下沉, 够不到的距离)，上限 0.26 m。楼梯：锁定脚比身体低 > 0.34 m 时释放（片段一步跨两级）。
- 权重只在 GROUND/ground 动画为 1（淡入 10/s、淡出 30/s，避免攀爬时脚穿入台面），瞬移时 reset()。
- 测试 86/86 @30/60/120 Hz。`FOOTIK_OFF=1` 环境变量可关闭脚部 IK 做 A/B。

## Cycle 7 — Round 3：翻越/攀爬（真实 CC0 片段 + 接触驱动）

- 资源：Drawcall Market 免费再分发的 Quaternius UAL2 Source 级 CC0 单片段（safety vault、climb up 2m、转身/侧移/后退），
  `tools/fetch_drawcall.sh` curl 获取，`tools/retarget_drawcall.gd` 用 Jog_Fwd 双形式标定的常量骨局部偏移重定向。注意其付费层来源（THIRD_PARTY）。
- `ClipSampler` 离线采样片段接触点；视觉根按“片段手落在台面 / 片段鞋底落在台面”放置，片段时间由轨迹进度驱动。
- **根因**：攀爬手部接触随物理频率变化 = `get_global_transform_interpolated()` 返回 FTI 第 1 遍缓存，不含本帧 `_process` 改的视觉偏移，
  `TwoBoneIK3D` 与脚部 IK 的空间晚一帧（详见 MOVEMENT_SPEC §9.y）。修复：`render_xf()` + 骨架下隐藏的 IK 目标喂入节点。
  攀爬手接触时长 0.20/0.18/0.32 s → 0.43/0.43/0.43 s。
- 脚：鞋底深度常量、地面/顶面/前立面钳制、`_find_back_face` 后沿射线；翻越鞋底穿入 0.067 → 0。
- 手：伸手路径先升后入（不扫过台沿角，0.09 → 0）；超出臂长时手权重淡出（不再满权重悬空 4–7 cm）。
- 测试收紧（见 TEST_REPORT），86/86 @30/60/120 Hz。

## Cycle 8 — Round 3：许可证核查与 core/extras 拆分

- 核查 Drawcall 片段：zip README 显示一部分是 UAL1 **Pro**、一部分是 UAL2 **Source**（旧文档全记成 UAL2，错误）；都是付费级，
  由身份不明的第三方免费转发；Quaternius 2026-08-28 起的新许可证 QAL v1.0 禁止再分发资源本身。结论“存疑” → 不提交（THIRD_PARTY.md）。
- `ual_clips.res` 恢复为 Standard-only（= c9e8228）；extras 片段改为本机可选、git 忽略的 `assets/animations/local/ual_extra.res`。
- core 模式翻越/攀爬重写为“预先规划的视觉根偏移表 + IK 目标内混合”，消除 0.6 m/帧的跳变（剩余最大约 0.16 m/帧 @120 Hz）。
- 测试运行器自检：完整运行必须恰好 86 条结果。日志打印 `INFO|anim_library=…`。
- core 与 extras 两种模式均 86/86 @30/60/120 Hz。
- **未处理**：已推送的 `9e0060c` 中的 `ual_clips.res` 含存疑片段的烘焙数据；改写历史需仓库所有者确认。

## Cycle 9 — Round 3：瞄准方向移动 + 起停（第 2 里程碑）

- 新测试 8 项（6 项瞄准方向 + 2 项起停），总数 94。core 方向移动：骨盆扭转（瞄准上限 92°）+ 后退倒放（115°/95° 迟滞）。
- FootIK：swing release（动画脚摆动时正常释放 + 抬脚弧线）、站定 settle 小步、锁定脚支撑高度双向快速跟随、翻越/攀爬进入时把越过立面的锁推回。
- 起停断开 2–5 次 → 0；侧移/后退/斜后 pops 1–3 → 0；楼梯 120 Hz p90 0.073 → 0.047；extras 攀爬鞋底穿入 0.030 → 0。
- 试过但撤回：起步 1/_move_s 循环加速（断开更多）；swing_min_offset 0.06/0.14（冲刺滑移中位数 0.36–0.89）。

## Cycle 10 — Round 3：原地转身、翻滚入口、第 3 轮可视化验收（3c1fb94, 2337812, dfbb5bd）

- 原地转身：站定时偏航超限走 settle 小步而非断锁；新测试 2 项 → 96 项。基线 180° 在 30/120 Hz 各断 1 次，现 0。
- 翻滚入口：从片段 0.12 s 进入 + 0.10 s 淡化 + 最低接触点下压表；俯冲腾空 0.27–0.31 → ~0.13 m，身体系头速 52 → ≤19 m/s。
  试过：T0 0.36/0.06 淡化（33.6 m/s）、0.20/0.10（17.1）、0.05/0.08（15.8，但入口更突兀）。
- ClipSampler 骨骼名断言（发现 `"head"` 静默读错骨骼）。
- 第 3 轮可视化（core）：showcase 加原地转身段 + 28 张特写（SubViewport，不打断视频）。结论见 TEST_REPORT 末节。

## Cycle 11 — Round 4（f7afe1e, b3a0da9, cd60173, 645732e, 565ca5c, 1c774dd）

- 所有者决定：用 squash 合并 PR #1 来去掉 9e0060c 中存疑的数据，不改写历史（THIRD_PARTY + PR 正文都有说明）。
- 翻滚：`roll_tuck` 在入口阶段收腿，头-脚跨度 1.48 → 1.13 m。骨盆最高点没有处理（仍是 0.7–0.9 m）。
- 翻越/攀爬单帧跳变：只修正真正穿进方块的脚底，修正量经临界阻尼弹簧平滑，淡化改为缓入缓出。速度跳变 13–25 → 5–10 m/s。新增 `anim_traverse_pops`。
- 180° 急转：`_knee_out`，膝间距 0.19 → 0.24 m，内扣 0.027 → −0.012。新增 `anim_turn180_legs`。（“腿交叉”经查是相机视角造成的，不是真的交叉。）
- 后退：`BackwardGait`（由 CC0 片段生成），新增 `anim_backpedal_gait`。
  试过把整段摆动替换成关节空间曲线（蹬地 → 收腿 → 落地）：膝盖靠前时屈膝会让脚贴着地面向后扫（钟摆最低点），IK 关闭时脚尖拖地、单帧落地跳 0.2 m。
  改为“倒放源片段 + 衰减抬膝”后，实测与后退步态的生物力学（大致是前进的时间反演）一致。
- 侧移交叉步：没有做。
- 展示脚本：楼梯下行特写按位置触发，每张特写渲染前都隐藏标签（标签在 setup 之后才建，原来的隐藏没生效），默认输出 round4。

## Cycle 12 — Round 5（ca1a8a9, ef53970, 517da83, 53da67b, 8105eff, e6dbbe2）

- 翻滚：倒立阶段弯背 + 骨盆前倾，按“骨盆离最低接触 ≤ 0.45 m”求解（`ROLL_NOCAP=1` / `ROLL_CAP=` 做 A/B）；入口淡入后骨盆 0.69 → 0.57 m（目标 0.55 未完全达到）。
- 推箱子：帧率无关的速度伺服 + 箱子摩擦 0.5，30/60/120 Hz 推动 3.13/3.12/3.12 m（原 3.45/3.40/2.31）。新增 `crate_push_rate_independent`。
- 翻越“越过”特写重新取景；展示默认输出 round5。
- 攀爬起身：放开的手经 IK 下垂，手腕相对肩 −0.19…−0.23 → −0.31…−0.32 m。新增 `anim_mantle_standup_arms`。
- 侧移交叉步：`StrafeGait` + BlendSpace2D（8 点）。先试了“前进片段 + 侧移片段”两点混合：斜向步幅不匹配，片段滑步 46–61%，于是补了 4 个斜向片段并按方向插值步幅。
  余弦摆动在起止处有速度台阶，引起 FootIK 硬跳脱，改为 Hermite 摆动；120 Hz 斜后方仍有 1 次跳脱（脚离地 2.6 cm < PLANT_H 3 cm），改为 sin^0.6 快速抬脚后消除。
  初版（支撑 0.5、宽度 0.8、步幅 1.7）最宽时两腿分得过开，改为 0.42 / 0.6 / 1.6。
- core 101/101 @30/60/120；extras 98/101。

## Cycle 13 — Round 6（0f3d41e, 6fd70de, a1a0fbd, 8ef32b1, 96c1e44, ecd2327）

- 翻滚：逐帧分析（`ROLL_DEBUG=1`）定位峰值在撑手阶段（下落曲线平均后下沉不足，手离地 2–4 cm），不是倒立前的过渡帧。补回包络后入口淡入后骨盆 0.57 → 0.52 m，门限收紧到 ≤ 0.55。`ROLL_DROP_PLAIN=1` 做 A/B。
- 瞄准前进/后退：在源头重新摆姿（同 `StrafeGait`），片段滑步 1.02/0.81 m/s → ≈ 0。后退初版膝前伸 0.376 m（门限 0.33），改为单独支撑占比 0.38、抬脚 0.08、步幅 ×0.7 后 0.324–0.326。`AIM_FB_RAW=1` 做 A/B。
- 侧移：步幅 1.3、内收 0.4，最宽站距 1.14 → 0.90 m；降低 SIDE_TAN 无效且引入抬脚速度台阶，放弃。髋部反向转动 ±7°（先试的方向让髋跟着胸转、扭转反而变小，改了符号；后退底片段的肩摆相位相反，所以 z<0 时再翻一次符号）。胸部朝向用锁骨线测量（上臂线会被手臂摆动污染）。
- 斜后方：后退底 + 单独支撑/抬脚/偏晚抬脚 + 步幅 1.5，最宽 1.52 → 1.16 m。节奏改进无硬指标（`step_asym` 之前已 ≈ 0）。
- 推箱子特写：发现推动时角色站着滑行（碰撞把 `velocity` 截到 ~0.18 m/s @60 Hz）。动画在推动时改用真实位移速度，新增 `crate_push_anim_walks`。特写用高机位避开相邻箱子。
- README 增加 M2 试玩清单。
- 测试中途踩坑：用 Python `str.replace` 插入测试代码时命中了另一个测试里相同的代码块，产生重复插入 → 解析错误；改为 `count()==1` 断言后再替换。
- core 102/102 @30/60/120；extras 99/102。

## 可恢复状态（2026-11-03，Cycle 13 之后）

- 分支 `dev/movement-system`，PR #1（**不要合并、不要强推；将来只能 squash 合并**）。测试 core 102/102 @30/60/120 Hz；本机 extras 99/102。
- 跑测试：`runall.sh <tag> [ENV=val]`（运行机 `/workspace/eval/`）；或
  `godot --headless --fixed-fps <hz> --path . -s res://tests/run_tests.gd -- --hz=<hz> [--only=t_anim]`；`UAL_EXTRAS=0` 强制 core；`FOOTIK_DEBUG=1` 打印锁脚跳脱。
- 调试开关：`TRACE_TRAVERSE=1`、`ROLL_DEBUG=1`、`ROLLPROBE=1`、`ROLL_UNTUCKED=1`、`ROLL_NOCAP=1`/`ROLL_CAP=<m>`、`ROLL_DROP_PLAIN=1`、`BWD_RAW=1`、`AIM_WARP=1`、`AIM_FB_RAW=1`（瞄准前后改回旧混合）、`PUSH_DEBUG=1`。
  新增 class_name 脚本后先跑一次 `godot --headless --editor --quit --path .` 刷新类缓存。
- 可视化：`tools/showcase.gd`（默认输出 `/workspace/acceptance/round6`）；第 6 轮产物在 `/workspace/acceptance/round6/`。
- 剩余问题：推箱子没有推姿势（手不扶箱子）；后退膝前伸 0.325 m 离门限 0.33 只差 0.5 cm、步频偏高；斜后方“节奏”只有观感判断；
  侧移手臂仍是前进片段；后退 → 瞄准前进切换有一帧略蹲；30 Hz 翻越单帧跳变（门限内）；extras 模式 3 项失败。
- 未验收（需 M2 真机，按 README 试玩清单）：所有动态观感。

## 下一步优先级

0. （Round 2）脚部锁定 IK 以消除残留滑步（13–31% 身体速度）；找/做 CC0 的起步/停步/转身/侧移/翻越/攀上台沿专门片段替代程序化补偿；查明攀爬手部接触时长随物理频率变化的原因；真机 M2 验收。
1. ~~推箱子 120 Hz 距离差异（~30%）~~（Round 5 已解决）。
2. 空中接近矮墙时的“跳跃→翻越”衔接（跳跃缓冲进入检测距离时自动转翻越）。
3. 真实 GPU 上的人工手感验收与参数微调（当前只在 llvmpipe 上渲染过）。
4. ~~动画：灰盒程序化姿态 → 骨骼动画/IK~~（Round 2 已完成骨骼动画与手部 IK；脚部 IK 未做）。
5. 移动平台、斜坡上滑铲加速的上限调优。
