class_name CourseLayout
extends RefCounted
## Single source of truth for graybox test-course coordinates.
## Used by the level builder (geometry) AND the automated tests (spawn points),
## so tests and level never drift apart. All units are metres; -Z is "forward".

const SPAWN := Vector3(0, 0.02, 6)

# --- Zone A: flat track (start/stop/turn tests) -------------------------
const FLAT_ORIGIN := Vector3(0, 0.02, 0)

# --- Zone B: single step blocks of different heights --------------------
# Each block spans z in [STEP_Z_NEAR, STEP_Z_FAR] (3 m deep) and is 2.4 m wide.
const STEP_HEIGHTS: Array[float] = [0.15, 0.25, 0.35, 0.40, 0.50]
const STEP_X0 := 10.0
const STEP_DX := 3.5
const STEP_Z_NEAR := -6.0
const STEP_Z_FAR := -9.0

static func step_lane_x(i: int) -> float:
	return STEP_X0 + STEP_DX * i

# --- Zone C: staircases ---------------------------------------------------
# Normal stairs: riser 0.18, tread 0.30, 10 steps -> 1.8 m landing.
const STAIR_X := 32.0
const STAIR_Z0 := -4.0
const STAIR_RISER := 0.18
const STAIR_TREAD := 0.30
const STAIR_STEPS := 10
const STAIR_LANDING_DEPTH := 3.0
# Steep stairs: riser 0.25, tread 0.25 (45 deg), 8 steps -> 2.0 m.
const STEEP_X := 37.0
const STEEP_RISER := 0.25
const STEEP_TREAD := 0.25
const STEEP_STEPS := 8

# --- Zone D: ramps ------------------------------------------------------
const RAMP_ANGLES: Array[float] = [10.0, 20.0, 30.0, 40.0, 50.0]
const RAMP_X0 := 44.0
const RAMP_DX := 5.0
const RAMP_Z0 := -4.0       # ramp foot (ground contact line)
const RAMP_RISE := 1.5
const RAMP_WIDTH := 3.0

static func ramp_x(i: int) -> float:
	return RAMP_X0 + RAMP_DX * i

static func ramp_run(i: int) -> float:
	return RAMP_RISE / tan(deg_to_rad(RAMP_ANGLES[i]))

# --- Zone E: drop tower (stairs up to 2 m and 4 m ledges) -----------------
const TOWER_X := -14.0
const TOWER_Z0 := -4.0
const TOWER_RISER := 0.2
const TOWER_TREAD := 0.3
const TOWER_MID_STEPS := 10     # 2.0 m mid landing
const TOWER_TOP_STEPS := 20     # 4.0 m top
const TOWER_LANDING := 3.0

# --- Zone F: corridors + low tunnel --------------------------------------
const CORRIDOR_X := -24.0       # 1.0 m wide corridor centre
const CORRIDOR_WIDTH := 1.0
const NARROW_X := -28.0         # 0.85 m wide corridor centre
const NARROW_WIDTH := 0.85
const CORRIDOR_Z0 := -4.0
const CORRIDOR_LEN := 8.0
const TUNNEL_X := -34.0
const TUNNEL_HEIGHT := 1.35
const TUNNEL_WIDTH := 2.0
const TUNNEL_Z0 := -6.0
const TUNNEL_LEN := 6.0

# --- Zone G: vault / mantle obstacles ------------------------------------
const VAULT_X := -42.0          # 0.9 m tall, 0.3 m thick wall
const VAULT_Z := -6.0
const VAULT_H := 0.9
const VAULT_T := 0.3
const MANTLE_X := -47.0         # 1.5 m tall, 3 m deep box
const MANTLE_Z := -6.0          # near face
const MANTLE_H := 1.5
const TALL_X := -52.0           # 2.3 m wall: must be rejected
const TALL_H := 2.3

# --- Zone H: pushable crates ----------------------------------------------
const CRATE_ORIGIN := Vector3(0, 0, -36)

# --- Zone I: camera torture (overhang + pillar forest + tight alley) ------
const CAM_ORIGIN := Vector3(-14, 0, -30)
