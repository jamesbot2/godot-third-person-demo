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

## 可恢复状态（2026-11-03）

- 分支 `dev/movement-system`，PR #1（**不要合并**）。测试 94/94 @30/60/120 Hz，core 与 extras 两种模式（`tests/results/`）。
- 跑测试：`runall.sh <tag> [ENV=val]`（运行机 `/workspace/eval/`，不在仓库中）；或
  `godot --headless --fixed-fps <hz> --path . -s res://tests/run_tests.gd -- --hz=<hz>`；`UAL_EXTRAS=0` 强制 core。
- 调试翻越/攀爬：`TRACE_TRAVERSE=1` 打印 PLAN/TR 行；`/workspace/eval/jumps.py <log> 0.07` 统计单帧跳变。
- Round 3 进度：优先级 1（脚部 IK）、2（翻越/攀爬接触）完成；许可证拆分完成；优先级 3 的起停/侧移/后退/斜向完成（Cycle 9）。
  剩余：原地 90°/180° 转身（plant-and-turn）、优先级 4 翻滚入口。
  优先级 3（起停/转身/侧移）：core 模式没有专门片段（Standard 包里没有 strafe/turn），只能程序化；
  extras 片段已烘焙但未接入（存疑，接入也只在本机生效）。上一次未提交的 extras 方向混合尝试在 git stash `wip-aimed-directional-backup`
  与运行机 `/workspace/backup_r3/wip_aimed_directional.patch`。优先级 4 翻滚入口未开始。
- 未验收（需 M2 真机）：所有动态观感。

## 下一步优先级

0. （Round 2）脚部锁定 IK 以消除残留滑步（13–31% 身体速度）；找/做 CC0 的起步/停步/转身/侧移/翻越/攀上台沿专门片段替代程序化补偿；查明攀爬手部接触时长随物理频率变化的原因；真机 M2 验收。
1. 推箱子 120 Hz 距离差异（~30%）。
2. 空中接近矮墙时的“跳跃→翻越”衔接（跳跃缓冲进入检测距离时自动转翻越）。
3. 真实 GPU 上的人工手感验收与参数微调（当前只在 llvmpipe 上渲染过）。
4. ~~动画：灰盒程序化姿态 → 骨骼动画/IK~~（Round 2 已完成骨骼动画与手部 IK；脚部 IK 未做）。
5. 移动平台、斜坡上滑铲加速的上限调优。
