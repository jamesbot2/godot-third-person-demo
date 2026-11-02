# THIRD_PARTY — 参考来源与许可证

本项目代码全部为独立编写。以下项目仅作为**思路参考**（阅读其方法与公开说明），未复制代码或资源。所有参考项目均为 MIT 许可证（2026-11-02 通过 GitHub API 核对）。

| 来源 | 许可证 | 参考内容 |
|---|---|---|
| Godot 官方文档：CharacterBody3D、PhysicsServer3D.body_test_motion、Physics interpolation、Movie Maker — https://docs.godotengine.org/en/stable/ | CC BY 3.0（文档） | API 语义、`floor_max_angle`、`body_test_motion`、物理插值、`--write-movie` |
| Jeh3no/Godot-Advanced-State-Machine-First-Person-Controller — https://github.com/Jeh3no/Godot-Advanced-State-Machine-First-Person-Controller | MIT | 状态机划分方式（行走/冲刺/蹲/滑铲/跳跃）、coyote/buffer 的组织 |
| Jeh3no/Godot-Simple-State-Machine-First-Person-Controller — https://github.com/Jeh3no/Godot-Simple-State-Machine-First-Person-Controller | MIT | 同上（简化版） |
| PantheraDigital/GodotCharacterStep — https://github.com/PantheraDigital/GodotCharacterStep | MIT | 用 `body_test_motion` 做上抬-前移-下落的台阶检测思路 |
| Andicraft/stairs-character — https://github.com/Andicraft/stairs-character | MIT | 扁平圆柱碰撞体 + 下楼梯吸附的思路 |
| bearlikelion/SUCC (SurfsUp Character Controller) — https://github.com/bearlikelion/SUCC | MIT | 台阶/坡度处理与相机平滑的组织方式 |

关于 ARC Raiders：只参考其公开可观察的移动表现（重量感、冲刺蓄速、翻越/攀爬的节奏），本项目不包含其任何代码、资源，也不声称了解其内部实现。
