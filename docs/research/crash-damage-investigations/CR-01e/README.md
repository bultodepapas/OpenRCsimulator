# CR-01e — Crash causes

2026-10-13 · **Status:** implemented; rule thresholds are presentation estimates. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.5, decision D5 (card and log line).

## What the pilot sees

The crash card gains one line, also printed as `CRASH CAUSE: …`. Examples from the real Stik flights in the test:

- `Cause: Tip stall at 8 m: α 11°, 6.8 m/s, bank -1° (throttle closed, steep bank)`
- `Cause: Too late to pull out of a dive path -64° → -15°, 36.0 m/s`

## How

[director.gd](../../../../app/render/crash/director.gd) keeps the last 5 s of flight, one sample every 0.05 s of sim time, from the HUD's 64-bit [telemetry](../../../../app/render/overlays/telemetry.gd). Each sample holds airspeed, ground speed, α, pitch, bank, body roll and yaw rate, height above ground, vertical speed, throttle and engine state. A paused session adds nothing, and a restart starts a fresh history. Nothing is written back to the session.

At the crash, [cause.gd](../../../../app/render/crash/cause.gd) `CrashCause.classify()` applies ordered rules:

1. **Obstacle:** scenery trigger, named by obstacle kind.
2. **Ground handling:** on the ground (< 0.5 m) for the last second. Named a prop strike when the propeller group was struck.
3. **Dead stick:** the engine stopped for the last 2 s.
4. **Spin, tip stall, stall:** a stall is α at or above the aircraft's stall-blend α (`envelope.a1`) minus the HUD's 2° STALL margin, held for ≥ 0.25 s within the last 2.5 s, at ≥ 3 m/s airspeed.
   - **Spin:** |yaw rate| ≥ 90°/s for ≥ 0.5 s.
   - **Tip stall:** |roll rate| ≥ 120°/s, or a bank change ≥ 45° within 1 s of the stall, measured from the attitude just before it.
5. **Dive:** flight path ≤ −45° at ≥ 1.3 × start speed within the last 2 s. It is labelled "too late to pull out" when the final path is shallower.
6. **Gear collapse:** gear overtravel in a landing attitude.
7. **Hard landing:** near level, sinking ≥ 2 m/s.
8. **Steep bank:** |bank| ≥ 60°.
9. **Flew into the ground.**

Contributing factors are a closed throttle, low airspeed (< 0.8 × start speed) and a steep bank (≥ 45°). Radio failsafe pauses the simulation, so it cannot cause a crash and has no rule.

## Evidence

- [test_crash_cause.gd](../../../../app/tests/test_crash_cause.gd): **29 checks**.
  - Every rule from synthetic histories.
  - Guards: a brief α spike, α at very low airspeed, the threshold from data, an engine that just stopped, partial ground windows, no history.
  - Line formatting.
  - Two real Stik flights through the production scene, a slow nose-high mush and a −65° full-throttle dive, plus the card line and the fresh history after restart.
- [Mutations](../../../../research/crash-damage/cr-01e/mutations.log): **9/9 killed** — fixed stall α, no minimum stall time, no spin, bank change from the stall sample, final-path-only dive, gear collapse before flight conditions, dead stick on any stop, no recording, card without the cause.

  Development found two real rule faults, now fixed and tested. The tip-stall bank change was measured from the stalled sample instead of the attitude before it. The dive rule used the final pitch, so a hands-off Stik that had pitched up to −12° by impact after a −65° dive was reported as "gear collapsed".

## Limits

- The rule thresholds are estimates and have not been compared with pilot-labelled crashes; that is the owner review.
- Sampling is per render frame against sim time, so a crash within 0.05 s of a sample uses the latest earlier sample.
- Gusts, out-of-fuel and low battery have no separate rule. An electric pack that sags still shows as a stall or a descent.
- Trace routes do not create the crash director, so causes appear only on interactive flights.
