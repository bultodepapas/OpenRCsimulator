# E3b2 — Runway start in static equilibrium

2026-10-07 · **Status: implemented and verified.** Main-line ROADMAP M2 E3b2; uses E3b1 anchors and D1-R3 support.

## What it does

`GroundStart.threshold(field)` returns the start spot: on the runway centre line, 3 m inside an end (estimated, so the tail sits on the runway), facing along the runway. It is east-bound from the west end by default. The default field gives (15, −47) m, heading east. There is no wind model yet, so the direction is a parameter.

`GroundStart.solve(...)` (pure, Newton on a central-difference Jacobian, partial-pivot elimination) runs in two stages:

1. **Engine off.** At the requested spot and heading, height, roll and pitch are solved so the vertical force and both horizontal moments vanish. All forces are vertical there. The anchors then go to the wheels' ground points: the airplane was placed and its wheels stuck.
2. **Idling.** With those anchors fixed, all six pose values are solved so every body acceleration vanishes at zero velocity. The airplane leans onto its anchors as if the engine had come up to idle slowly. The solve refuses if idle thrust would exceed the wheels' hold.

`FlightSession.reset_on_runway(north, east, heading)` performs a normal reset, then applies: closed throttle, the steady idle rpm, servos at their trimmed positions, the solved state and the stuck anchors. Gear without stiction data (Extra: no gear; P-51: gear without `breakaway_factor`) is refused, and the aircraft keeps its normal flying start. No UI or CLI entry point is added in this step.

## Proof

[`test_runway_start.gd`](../../../../app/tests/test_runway_start.gd): **19 checks, 0 failed.**

- **Roadmap criteria:**
  - After 1 s at idle, |v| is at most **3.7e-14 m/s**, and the attitude difference from the solve is 0°.
  - Over **10 s**, |v| and |ω| stay below 1e-13, the airplane moves 0 m and the anchors are unchanged.
- **ΣN versus m·g:** the roadmap's "ΣN = m·g ± 0.1%" assumed horizontal thrust. Physically the idle thrust moves load to the nose wheel, so the Stik rests **1.60° nose-down**, and the tilted thrust pushes the wheels down by T·sin θ = 0.073 N. ΣN is therefore 1.0026·m·g (within 0.3%). The test checks the exact vertical balance, **ΣN = m·g + T·sin θ to 1e-9 N**.
- **Independent physics:**
  - The anchors cancel the idle thrust (2.60 N) horizontally to 1e-9 N.
  - Each wheel leans 2.40–2.47 mm past its anchor, against T/Σk = 2.446 mm.
  - The nose load from the solve (10.0919 N) matches a world-frame side-view moment balance (10.0922 N; geometry and equilibrium only, with the anchors' pull shared by stiffness).
  - The solve converges below 1e-11 in 6 Newton iterations.
- **Other cases:** the threshold for both ends; a field without a runway is refused; the west-bound start solves; the Extra and P-51 are refused and keep their flying starts.
- **Mutation checks** on scratch copies, all caught: skipping the idle stage (7 checks fail; it rolls at 0.039 m/s), starting with sliding wheels (5 fail), and solving without thrust (7 fail).
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (93 sections, 389 s); goldens unchanged. [Summary](suite-summary.log).

## Limits

The 3 m line-up and the start direction are estimates and parameters. This is verification of the numerical model's own equilibrium, not field validation. A real Stik's resting pitch at idle (here 1.60° nose-down, driven by the estimated gear stiffness) and its breakaway are field observations for VAL. E3b3 (takeoff roll against a hand integral) starts from this state.
