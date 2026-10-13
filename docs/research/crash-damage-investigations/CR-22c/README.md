# CR-22c — Cost of the crash-realism paths

2026-10-13 · **Status:** partial. Script (CPU) cost is measured on the shared Linux VM. Rendered frame cost needs the owner's Windows host (this VM has no GPU). **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.6.

## Script cost (headless, Godot 4.7.2, shared 12-core VM, load ≈ 2.5)

[bench_script_cost.gd](../../../../research/crash-damage/cr-22c/bench_script_cost.gd) times 40 batches of 250 calls; values are µs per call (median / p95). Before is the E3d1 module as first committed; after adds an altitude early-out to `terminal()` and moves allocation after the in-contact test (scalar depth first).

| Path | When | Before | After |
| --- | --- | --- | --- |
| `HullContact.loads` | every RK stage (×4 per tick), high above the ground | 0.80 / 1.00 | 0.41 / 0.51 |
| `HullContact.loads` | within hull reach, no contact | 3.61 / 6.35 | 3.62 / 4.74 |
| `HullContact.loads` | touching | 4.98 / 8.41 | 4.94 / 9.14 |
| `terminal` + `contacts` | every tick, high above the ground | 5.61 / 6.63 | 2.73 / 3.00 |
| `terminal` + `contacts` | within reach, no contact | 10.38 / 15.42 | 8.72 / 14.52 |
| `terminal` + `contacts` | touching | 56.84 / 85.61 | 49.06 / 77.29 |
| `CrashCause.classify` | once per crash, full 5 s history | — | 135.47 / 211.45 |
| `Effects.update` | per frame, C4 with 144 chips, venting | — | 1.50 / 10.86 |

At 240 Hz the airborne contact work is about 4 × 0.4 + 2.7 ≈ 4.3 µs per tick, about 0.1 % of one core. Resting or sliding on the ground costs about 4 × 5 + 49 ≈ 69 µs per tick (≈ 1.7 % of one core) while it lasts. The cause history adds one telemetry sample every 0.05 s of sim time. The VM is shared, so differences under about 2× in the small figures are within noise. The early-out is kept because it removes allocation for airborne points, not because of a measured speed-up.

## Particle and pool budget

The effects allocate 700 particles: 556 crash, 24 soft-touch puff and 120 LiPo venting. That is exactly the CR-22a 700-particle limit, and `test_crash_energy.gd` checks it. Pools do not grow: 24 wreck bodies, 160 chips, 16 marks, one light.

## Open

- Native frame p95 per class and distance, and first-impact hitch with shader pre-warm, on the owner's Windows host: rerun `research/crash-damage/cr-22a/qualify.py` with the new scenarios.
- Distance LOD for particle and chip counts. `CPUParticles3D.amount_ratio` support on the pinned 4.7.2 still needs a probe; until then counts are reduced by class only.
