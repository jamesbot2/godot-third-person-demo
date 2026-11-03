# THIRD_PARTY — 参考来源与许可证

本项目代码全部为独立编写。下方“代码/思路参考”中的项目仅作为**思路参考**（阅读其方法与公开说明），未复制代码或资源。所有参考项目均为 MIT 许可证（2026-11-02 通过 GitHub API 核对）。

## 代码/思路参考

| 来源 | 许可证 | 参考内容 |
|---|---|---|
| Godot 官方文档：CharacterBody3D、PhysicsServer3D.body_test_motion、Physics interpolation、Movie Maker — https://docs.godotengine.org/en/stable/ | CC BY 3.0（文档） | API 语义、`floor_max_angle`、`body_test_motion`、物理插值、`--write-movie` |
| Jeh3no/Godot-Advanced-State-Machine-First-Person-Controller — https://github.com/Jeh3no/Godot-Advanced-State-Machine-First-Person-Controller | MIT | 状态机划分方式（行走/冲刺/蹲/滑铲/跳跃）、coyote/buffer 的组织 |
| Jeh3no/Godot-Simple-State-Machine-First-Person-Controller — https://github.com/Jeh3no/Godot-Simple-State-Machine-First-Person-Controller | MIT | 同上（简化版） |
| PantheraDigital/GodotCharacterStep — https://github.com/PantheraDigital/GodotCharacterStep | MIT | 用 `body_test_motion` 做上抬-前移-下落的台阶检测思路 |
| Andicraft/stairs-character — https://github.com/Andicraft/stairs-character | MIT | 扁平圆柱碰撞体 + 下楼梯吸附的思路 |
| bearlikelion/SUCC (SurfsUp Character Controller) — https://github.com/bearlikelion/SUCC | MIT | 台阶/坡度处理与相机平滑的组织方式 |

关于 ARC Raiders：只参考其公开可观察的移动表现（重量感、冲刺蓄速、翻越/攀爬的节奏），本项目不包含其任何代码、资源，也不声称了解其内部实现。

## 美术资源（Round 2，已提交到仓库）

| 资源 | 来源 URL | 许可证 | 仓库中的形式 |
|---|---|---|---|
| Universal Base Characters [Standard]（Quaternius）— 使用 `Superhero_Male_FullBody.gltf`（Godot - UE 版，65 骨 UE 命名骨架）| https://quaternius.itch.io/universal-base-characters （作者站 https://quaternius.com）| CC0 1.0（原文：`assets/licenses/Quaternius_UBC_License.txt`）| 构建产物 `assets/characters/ubc_male/ubc_male.scn` |
| Universal Animation Library [Standard]（Quaternius）— `UAL1_Standard.glb` | https://quaternius.itch.io/universal-animation-library | CC0 1.0（`assets/licenses/Quaternius_UAL1_License.txt`）| `assets/animations/ual_clips.res` 中的片段 |
| Universal Animation Library 2 [Standard]（Quaternius）— `UAL2_Standard.glb` | https://quaternius.itch.io/universal-animation-library-2 | CC0 1.0（`assets/licenses/Quaternius_UAL2_License.txt`）| 同上 |

- 获取：三个包在 itch.io 上是“自愿付费，可 $0 下载”，`tools/fetch_quaternius.sh` 用 itch 的公开下载流程（csrf token → download_url）免登录下载，未付费。原始 zip/glb **未提交**（体积原因；许可证本身允许再分发）。
- 构建：`tools/build_character_assets.gd` 读取原始 glTF/GLB，烘焙网格+骨架为 `.scn`，把使用的 19 个片段（Idle、Walk、Jog_Fwd、Sprint、Crouch_Idle、Crouch_Fwd、Jump_Start、Jump、Jump_Land、Roll、Push、A_TPose、Slide_Start、Slide、Slide_Exit、ClimbUp_1m、NinjaJump_Start/Idle/Land）写入 `.res`；只保留骨骼旋转和按身高比例缩放的盆骨位置，**丢弃根运动**；纹理用 `PortableCompressedTexture2D` 并设置 `keep_compressed_buffer = true`（否则保存为 .scn 后纹理丢失）。
- 片段的使用方式见 MOVEMENT_SPEC §9。

### 候选比较（如实）

| 候选 | 结论 |
|---|---|
| Mixamo（Adobe）| **阻塞**：https://www.mixamo.com/ 需要 Adobe 账号登录，无法用 curl 获取；且其条款不允许把独立的角色/动画文件再分发到公开仓库。未使用、未提交任何 Mixamo 文件。 |
| Quaternius UBC + UAL1/UAL2 | **采用**：CC0、写实比例的人形、标准 UE 骨架（角色和动画是同名同层级的 65 骨骨架；UBC 腿更长（盆骨静止高 0.949 vs 0.917 m），构建时只保留旋转并按腿长比例缩放盆骨轨道）、动画覆盖 idle/走/跑/冲刺/蹲/跳/落地/翻滚/滑铲/攀爬。 |
| 旧的程序化灰盒人形（本仓库）| 被替换：方块肢体、程序化姿态，不满足“真人感”要求。 |

已知资源缺口（CC0 Standard 包中没有，靠程序化补偿，见 MOVEMENT_SPEC §9）：专门的起步/停步/原地转身/侧移片段、真正的翻越（vault）片段、真正的攀上台沿（mantle）片段。翻越/攀爬是用 `ClimbUp_1m`（爬坡循环）+ `NinjaJump_Idle` 收腿姿态 + 手部 IK + 视觉根偏移拼出来的。

## Round 3：Drawcall Market 片段的许可证核查（2026-11-03，结论：**存疑 → 不提交**）

Round 3 前期（提交 `9e0060c`）把 Drawcall Market（https://market.drawcall.ai）上的 14 个 Quaternius 单片段
重定向后烘焙进了 `assets/animations/ual_clips.res`，并把它们记为“UAL2 Source，CC0”。本轮重新核查后的结论：

| 核查项 | 发现（来源） |
|---|---|
| 片段归属 | zip 内 README 自述：safety-vault-root-motion、climb-up-2m-root-motion、turn180-*、walk-l/right/bwd-loop 为 “Universal Animation Library **2 Source**”；climb-ledge、jog-fwd/left/right/bwd-loop、turn90-l/right 为 “Universal Animation Library **Pro**”（UAL1）。旧文档把它们全记成 “UAL2 Source”，**记错了**。 |
| 在作者处的级别 | 都不在免费的 Standard 包里，属于付费级（itch.io 上 UAL1 `[Source].zip` 需付 $14.99 以上；UAL2 同理）。 |
| 作者声明的许可证 | itch.io 包页面写 “Free to use … (CC0 License)”，Asset license 栏为 CC0 1.0（https://quaternius.itch.io/universal-animation-library 、…/universal-animation-library-2，2026-11-03 查看）。 |
| 作者的新许可证 | Quaternius Asset License (QAL) v1.0（https://quaternius.com/license.html ，最后更新 2026-08-28）**禁止把资源本身（含修改后）作为资源再分发**，并称“无论从哪个站点/平台获得”均适用；第 7 条称只适用于此后发布的资源、不溯及既往。UAL1 v3.0（2026-06-16）、UAL2 v2.2（2026-09-28）都在更新。 |
| 再分发者 | Drawcall Market 是与作者无明确关系的第三方，免登录免费提供付费级单片段并标注 CC0；无法核实其获得的是哪个版本、在哪个许可证下发布。 |

**结论：存疑（doubtful）。** 作者的包页面写 CC0，按 CC0 这些片段本可再分发；但它们是付费级内容，经身份不明的第三方
免费转发，版本与 QAL 生效日期的先后关系无法核实，旧文档对来源的记录也有误。按任务规则“存疑就不提交原始文件，只保留获取脚本”：

- `assets/animations/ual_clips.res` 已恢复为只含 CC0 **Standard** 片段的版本（与 `c9e8228` 相同）。
- 本机可选：`tools/fetch_drawcall.sh` 下载 → `tools/retarget_drawcall.gd --build` 写入 **git 忽略** 的
  `assets/animations/local/ual_extra.res`。存在该文件时动画器自动启用 “extras” 模式（真实翻越/攀上台沿片段），否则用
  “core” 模式（只用 Standard 片段，程序化翻越/攀爬）。`UAL_EXTRAS=0` 强制 core 模式。两种模式都跑满 86 个测试。
- 删除了 `assets/licenses/Quaternius_UAL2_Source_via_Drawcall.txt`（它把片段错误地描述为全部 UAL2、并断言可再分发）。
- **历史问题与处理决定（仓库所有者，2026-11-03）**：已推送的提交 `9e0060c` 中的 `ual_clips.res` 仍包含这些片段的烘焙数据。
  **不改写历史**；PR #1 **必须以 squash merge 方式合并**——squash 后进入 `main` 的只有分支最终状态（不含这些烘焙数据），
  `9e0060c` 不会出现在 `main` 的历史里。**不要用普通 merge 或 rebase merge 合并 PR #1。**
- 如需正式使用这些片段：直接向 Quaternius 购买 Source/Pro 包，并按购买时附带的许可证决定能否把烘焙结果放进公开仓库。

Round 4 新增的派生片段（`roll_tuck`、`walk_bwd`/`jog_bwd`/`sprint_bwd`，见 `scripts/player/roll_authoring.gd`、
`scripts/player/backward_gait.gd`）只在运行时、在内存中由已提交的 CC0 Standard 片段计算出来，没有引入新的第三方数据，也不读取 extras。

Round 5 新增的瞄准移动片段（`aim_fwd`/`aim_bwd` 与 6 个侧移/斜向交叉步片段，见 `scripts/player/strafe_gait.gd`）同样是派生数据：
运行时在内存中由已提交的 CC0 Standard 走/慢跑片段（及其派生的后退片段）计算（相位对齐混合 + 双骨 IK 重定向），不入库、不引入新的第三方数据。

Round 6：`aim_fwd`/`aim_bwd` 改为与侧移相同的方式由 CC0 前进/后退片段重新摆姿（支撑脚沿移动反方向扫过、双骨 IK），
斜后方片段改用后退片段为底；侧移/斜向片段增加髋部反向转动。仍然只在运行时内存中计算，不入库、不引入新的第三方数据。
推箱子特写只改了展示脚本与动画速度来源，没有新资源。**提醒：PR #1 仍然只能 squash merge（见上文 `9e0060c` 说明）。**

Standard 包（UBC、UAL1 Standard、UAL2 Standard）的结论不变：CC0，直接从作者的 itch.io 页面以 $0 获得。
