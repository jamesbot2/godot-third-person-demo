# TEST_REPORT

所有数据来自真实运行输出（`tests/results/headless_{30,60,120}hz.txt`），未做任何手工编辑。

- 引擎：Godot v4.7.2.stable.official（Jolt Physics），Linux x86_64
- 命令：`godot --headless --fixed-fps HZ -s res://tests/run_tests.gd -- --hz=HZ`
- 时间以物理 tick 计（`t = ticks / hz`），与墙钟无关

## 汇总

```
SUMMARY|hz=30|pass=73|fail=0
SUMMARY|hz=60|pass=73|fail=0
SUMMARY|hz=120|pass=73|fail=0
```

## 关键指标（三种物理频率）

| 指标 | 30 Hz | 60 Hz | 120 Hz |
|---|---|---|---|
| jog_t90_s | 0.2000 | 0.1833 | 0.1750 |
| jog_stop_dist_m | 0.3411 | 0.3400 | 0.3394 |
| jog_stop_time_s | 0.1667 | 0.1667 | 0.1667 |
| sprint_t95_s | 0.4667 | 0.4500 | 0.4500 |
| sprint_stop_dist_m | 0.8911 | 0.8900 | 0.8894 |
| sprint_exit_speed_0.1s | 5.6000 | 5.6000 | 5.6000 |
| reverse_t90_s | 0.3000 | 0.3000 | 0.3000 |
| turn90_t_s | 0.2000 | 0.1833 | 0.1750 |
| turn90_overshoot_m | 0.2633 | 0.2606 | 0.2596 |
| stairs_up_time_s | 1.2000 | 1.0333 | 1.0250 |
| stairs_cam_max_dy_per_tick | 0.0989 | 0.0680 | 0.0396 |
| slope40_drift_m | 0.0000 | 0.0000 | 0.0000 |
| jump_apex_m | 0.8990 | 0.8999 | 0.9007 |
| jump_airtime_s | 0.7000 | 0.6833 | 0.6917 |
| jump_tap_apex_m | 0.4392 | 0.3931 | 0.3710 |
| air_drift_from_rest_m | 0.5333 | 0.5167 | 0.5250 |
| slide_time_s | 1.0333 | 1.0333 | 1.0333 |
| slide_dist_m | 5.7189 | 5.5554 | 5.4732 |
| roll_dist_m | 2.7045 | 2.8040 | 2.8472 |

## 全部用例（60 Hz 细节；30/120 Hz 结果列出 PASS/FAIL）

| 用例 | 30 | 60 | 120 | 60 Hz 细节 |
|---|---|---|---|---|
| accel_jog_t90 | PASS | PASS | PASS | t90=0.183s (expect ~0.17) |
| brake_dist_jog | PASS | PASS | PASS | d=0.340 expect=0.339 |
| sprint_buildup | PASS | PASS | PASS | t95=0.450s |
| brake_dist_sprint | PASS | PASS | PASS | d=0.890 |
| sprint_exit_gradual | PASS | PASS | PASS | v@0.1s=5.60 v@0.5s=4.20 |
| reverse_180 | PASS | PASS | PASS | t=0.300s |
| turn_90 | PASS | PASS | PASS | t=0.183s overshoot=0.26m vmax=4.20 |
| no_instant_turn | PASS | PASS | PASS | max turn rate 885 deg/s |
| step_up_0.15 | PASS | PASS | PASS | h=0.15 reached=true y_on_top=0.151 max_y=0.151 max_vy=0.00 air_ticks=0 t=0.93s |
| step_up_0.25 | PASS | PASS | PASS | h=0.25 reached=true y_on_top=0.251 max_y=0.251 max_vy=0.00 air_ticks=0 t=0.93s |
| step_up_0.35 | PASS | PASS | PASS | h=0.35 reached=true y_on_top=0.351 max_y=0.351 max_vy=0.00 air_ticks=0 t=0.93s |
| step_up_0.40 | PASS | PASS | PASS | h=0.40 reached=true y_on_top=0.401 max_y=0.401 max_vy=0.00 air_ticks=0 t=0.93s |
| step_block_0.50 | PASS | PASS | PASS | h=0.50 reached=false y_on_top=0.001 max_y=0.001 max_vy=0.00 air_ticks=0 t=-1.00s |
| step_down_0.15 | PASS | PASS | PASS | y=0.001 air_ticks=0 |
| step_down_0.25 | PASS | PASS | PASS | y=0.001 air_ticks=0 |
| step_down_0.35 | PASS | PASS | PASS | y=0.001 air_ticks=0 |
| step_down_0.40 | PASS | PASS | PASS | y=0.001 air_ticks=0 |
| stairs_up_no_jump | PASS | PASS | PASS | t_top=1.03s max_y=1.801 air_ticks=0 jumps=0 |
| stairs_camera_smooth | PASS | PASS | PASS | max cam dy/tick=0.0680 |
| stairs_down_grounded | PASS | PASS | PASS | y=0.001 ungrounded_ticks=0 |
| steep_stairs_0.25 | PASS | PASS | PASS | reached=true y=2.001 t=1.18s max_vy=0.00 air_ticks=0 |
| ramp_up_10 | PASS | PASS | PASS | angle=10 reached=true y=1.501 t=2.88s max_vy=0.00 air_ticks=0 |
| ramp_down_10 | PASS | PASS | PASS | y=0.001 ungrounded_ticks=0 |
| ramp_up_20 | PASS | PASS | PASS | angle=20 reached=true y=1.501 t=1.88s max_vy=0.00 air_ticks=0 |
| ramp_down_20 | PASS | PASS | PASS | y=0.001 ungrounded_ticks=0 |
| ramp_up_30 | PASS | PASS | PASS | angle=30 reached=true y=1.501 t=1.57s max_vy=0.00 air_ticks=0 |
| ramp_down_30 | PASS | PASS | PASS | y=0.001 ungrounded_ticks=0 |
| ramp_up_40 | PASS | PASS | PASS | angle=40 reached=true y=1.501 t=1.42s max_vy=0.00 air_ticks=0 |
| ramp_down_40 | PASS | PASS | PASS | y=0.001 ungrounded_ticks=0 |
| ramp_reject_50 | PASS | PASS | PASS | angle=50 reached=false y=0.000 t=-1.00s max_vy=0.00 air_ticks=0 |
| slope_40_no_drift | PASS | PASS | PASS | drift=0.0000 |
| jump_full_height | PASS | PASS | PASS | apex=0.900 expect=0.90 airtime=0.683s |
| jump_variable_tap | PASS | PASS | PASS | tap apex=0.393 |
| no_bhop_gain | PASS | PASS | PASS | max h-speed over 6 chained jumps=6.800 |
| coyote_0.07s | PASS | PASS | PASS | delay=0.07 jumped=true vy=4.33 |
| coyote_0.20s | PASS | PASS | PASS | delay=0.20 jumped=false vy=-4.65 |
| jump_buffer | PASS | PASS | PASS | rejumped=true |
| air_control_limited | PASS | PASS | PASS | lateral drift=0.517m in 0.67s |
| air_momentum | PASS | PASS | PASS | fwd speed at take-off=4.20, before landing=3.52 |
| corridor_1.0 | PASS | PASS | PASS | z=-12.65 x_err=0.000 y=0.000 |
| corridor_0.85 | PASS | PASS | PASS | z=-20.27 x_err=0.000 y=0.001 |
| corridor_wall_slide | PASS | PASS | PASS | max_y=0.001 max |
| wall_no_climb_0 | PASS | PASS | PASS | max_y=0.001 min_z_in_front=-5.649 (face z=-6.00 + r=0.35) |
| wall_no_climb_30 | PASS | PASS | PASS | max_y=0.001 min_z_in_front=-4.940 (face z=-6.00 + r=0.35) |
| wall_no_tunnel_30mps | PASS | PASS | PASS | z=-5.647 |
| tunnel_blocks_standing | PASS | PASS | PASS | z=-5.65 |
| tunnel_no_stand_inside | PASS | PASS | PASS | z=-9.17 crouched=true h=1.15 |
| tunnel_crouch_through_and_stand | PASS | PASS | PASS | z=-22.68 crouched=false |
| slide_start | PASS | PASS | PASS | v_sprint=6.80 v_entry=7.72 |
| slide_ends | PASS | PASS | PASS | time=1.03s dist=5.56m state=GROUND |
| slide_cooldown | PASS | PASS | PASS | state=GROUND |
| slide_jump_cancel | PASS | PASS | PASS | state=AIR vy=4.33 h=1.80 |
| slide_into_tunnel_safe | PASS | PASS | PASS | z=-11.01 h=1.15 y=0.001 |
| roll | PASS | PASS | PASS | dur=0.600s dist=2.80m end=GROUND |
| roll_cooldown | PASS | PASS | PASS | state=GROUND |
| roll_from_idle | PASS | PASS | PASS | state=ROLL |
| vault_0.9 | PASS | PASS | PASS | saw=true z=-9.77 y=0.001 max_y=0.96 state=GROUND |
| vault_sprint | PASS | PASS | PASS | v_in=6.80 saw=true z=-9.81 max_y=0.96 |
| vault_needs_input | PASS | PASS | PASS | z=-5.60 state=GROUND |
| mantle_1.5 | PASS | PASS | PASS | saw=true y=1.501 max_y=1.560 state=GROUND |
| mantle_air_catch | PASS | PASS | PASS | saw=true y=1.501 state=GROUND |
| tall_wall_rejected | PASS | PASS | PASS | traversed=false y=0.001 |
| landing_2m | PASS | PASS | PASS | impact=8.55 m/s severity=1 expect=1 |
| landing_4m | PASS | PASS | PASS | impact=12.15 m/s severity=2 expect=2 |
| landing_roll | PASS | PASS | PASS | rolled=true recovery=0.00 |
| crate_push_light | PASS | PASS | PASS | crate moved=3.40m player max_y=0.001 max_vy=0.00 |
| crate_heavy_resists | PASS | PASS | PASS | heavy moved=0.00m |
| camera_never_inside_geometry | PASS | PASS | PASS | inside=0 / 600 samples |
| camera_idle_stable | PASS | PASS | PASS | max drift=0.00001 |
| fuzz_no_nan | PASS | PASS | PASS |  |
| fuzz_no_launch | PASS | PASS | PASS | max vy=4.54 [] |
| fuzz_no_fall_through | PASS | PASS | PASS | min y=0.000 |
| fuzz_no_stuck_action_state | PASS | PASS | PASS | longest SLIDE/ROLL/TRAVERSE run=0.58s |

## 已知的跨频率差异（如实记录）

- 轻箱 2 s 推动距离：30 Hz 3.45 m、60 Hz 3.40 m、120 Hz 2.40 m（约 30% 差异），均满足“可推动”判定。原因未确认（推测与每 tick 接触冲量和 Jolt 摩擦求解有关），列为已知问题。
- 楼梯相机每 tick 最大竖直位移随频率变化（每 tick 的量本身就与 dt 成正比）。

## VISUAL ACCEPTANCE（可视化验收）

- **headless 测试本身不构成视觉验收**：上面 73 项都是 headless 运行，VISUAL ACCEPTANCE: NOT VERIFIED（仅凭 headless）。
- 另外做了一次**真实非 headless 渲染**：`tools/showcase.gd` 自动驾驶，在 Xvfb 显示（DISPLAY=:6）上用 `--rendering-driver opengl3 --fixed-fps 30 --write-movie` 录制。
  渲染器为 **Mesa llvmpipe（软件光栅化，LLVM 19.1.7）**，所以 HUD 显示的墙钟 FPS 只有 17–24；Movie Maker 模式下游戏时间固定 30 fps，录像不受影响。
- 产物：23 张 PNG 截图 + `showcase.mp4`（1280×720，30 fps，39.3 s）+ `shots.log`（每张截图对应的状态/位置/速度/相机距离/FOV 与状态切换日志）。
  产物不提交到仓库，存放于运行机的 `/workspace/acceptance/`。
- 截图由开发者逐张查看过画面是否与日志状态一致；**最终手感验收需要仓库所有者本人确认**。

