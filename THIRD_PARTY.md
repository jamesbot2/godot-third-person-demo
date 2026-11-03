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

## 美术资源（Round 3 新增：翻越/攀爬/转身/侧移片段）

| 资源 | 来源 URL | 许可证 | 仓库中的形式 |
|---|---|---|---|
| Quaternius Universal Animation Library 2 “Source” 级单片段（经 Drawcall Market 再分发）：safety-vault-root-motion、climb-ledge、climb-up-2m-root-motion、jog-fwd-loop（仅用于重定向标定）、jog-left/right/bwd-loop、walk-l/right/bwd-loop、turn90-l、turn90-right、turn180-left-root-motion-alternate-2、turn180-r-rm | 每个片段页 `https://market.drawcall.ai/asset/<slug>`，下载 `https://market.drawcallcontent.com/zips/<slug>@<版本>.zip`（版本见 `tools/fetch_drawcall.sh`）；原作者 https://quaternius.com/packs/universalanimationlibrary2.html | CC0 1.0（片段页与 zip 内 README 均写明 “CC0”；记录见 `assets/licenses/Quaternius_UAL2_Source_via_Drawcall.txt`）| 重定向后写入 `assets/animations/ual_clips.res` |

- **如实说明**：这些片段在 quaternius.com 属于 UAL2 的**付费 “Source” 级**。Drawcall Market 免登录、免费提供单片段下载并标注 CC0；我们没有付费。
  CC0 允许再分发，与原始销售渠道无关；仍署名 Quaternius。若用户对来源有顾虑，可删除这些片段回退到 Round 2 的 Standard 片段（代码需相应回退）。
- 获取：`tools/fetch_drawcall.sh`（curl，无需浏览器/登录），带 sha256 前缀校验。原始 zip/glb 未提交。
- 重定向：`tools/retarget_drawcall.gd`。Drawcall 片段是去掉蒙皮的规范化人形层级（无根骨）；同一 Quaternius 源骨架只做了旋转重定基，
  因此每根骨有常量局部偏移 O_b，用两种形式都有的 Jog_Fwd（UAL1 原生 vs jog-fwd-loop）测出并核对其恒定性，再应用到其它片段。
  片段本身无根骨 → 没有可剥离的根运动；位移只在盆骨轨道，表现层按接触点放视觉根（MOVEMENT_SPEC §9.y），控制器仍是唯一位移权威。
- 已知资源缺口更新：翻越、攀上台沿已使用真实片段；原地转身、侧移/后退片段已烘焙进 `ual_clips.res`（是否接入见 ITERATION_LOG）；起步/停步专用片段仍没有。
