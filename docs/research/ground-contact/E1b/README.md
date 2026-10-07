# E1b — Continuous touchdown

2026-10-07 · **Status: implemented and verified. The gear damping ramps in from zero at touchdown and joins its full value smoothly at half each wheel's static compression; at rest and beyond the onset the E1 law is unchanged bit for bit.** Main-line ROADMAP M2 E1b.

## Problem

E1's contact force `F = max(0, k·δ + c·δ̇)` steps by c·δ̇ the instant a wheel touches: 37 N per main wheel at 2 m/s sink on the Stik (the knowledge base measured 107 N, 3.8 g, for the airplane). A step inside an RK4 tick drops the integrator to first order through touchdown. A one-ulp change of the contact branch then moves a landing trajectory, which makes landing goldens fragile across platforms ([01 §numerics](../../roadmap-investigations/01-numerics-architecture-performance.md)).

## Law

`c(δ) = c · x·(2 − x)` with `x = min(δ / δ_onset, 1)`, so `F = max(0, k·δ + c(δ)·δ̇)` (`Ground.damping`, used by both the loads and the stiction anchor step).

- **Near δ = 0** the damping grows linearly with compression (Hunt–Crossley onset, n = 1), so the force is continuous at touchdown.
- **At δ_onset** it joins c with zero slope (C¹).
- **δ_onset** is `DAMPING_ONSET_FRACTION` (0.5, estimated) of each contact's static compression, its resting load share of m·g over its spring (derived, no new data). Stik: mains 9.2 mm, nose 8.8 mm, against 18.4 / 17.6 mm at rest.
- **At or beyond the onset** the law is E1's. Rest, taxi, the takeoff roll and small oscillations about rest keep the E1 numbers bit for bit, and the loader's ζ check stays meaningful.
- **Passivity:** c(δ) ≥ 0, so the damper only dissipates; the `max(0, …)` clamp still stops it from pulling.

**Rejected designs**, each tried:
- **Pure Hunt–Crossley** (damping ∝ δ without limit) changes every resting and rolling result. The H11 ring-down fixtures fail 31 checks.
- **A linear ramp ending at the static compression** (the first version) puts a slope kink exactly at rest. H11's smooth ring-down about rest then fell from fourth order to ratio 2.5–3.3 (it needs ≈ 16), and its 2 mm fixture never settled. A test that settles the airplane and requires 0.8 × rest compression beyond the onset now pins that design intent.

## Evidence

Level drops, gear only, touching down 2 mm after the start ([`test_touchdown.gd`](../../../../app/tests/test_touchdown.gd)):

| Sink | Law | Peak force | Largest per-tick force step (240 Hz) | 240 vs 480 Hz error at 0.4 s (m + m/s) | Restitution |
| --- | --- | ---: | ---: | ---: | ---: |
| 0.5 m/s | E1 | 50.6 N | 20.1 N | 1.3e-4 | 0.28 |
| 0.5 m/s | **E1b** | 53.3 N | 13.9 N | **5.0e-6** | 0.31 |
| 1 m/s | E1 | 72.8 N | 39.4 N | 3.0e-4 | 0.28 |
| 1 m/s | **E1b** | 76.8 N | 35.0 N | **3.9e-5** | 0.30 |
| 2 m/s | E1 | 128.2 N | 112.6 N | 4.5e-4 | 0.31 |
| 2 m/s | **E1b** | 131.2 N | 94.6 N | **1.8e-4** | 0.32 |

- The refinement error through touchdown falls 2.5–26×. The declared budget (2e-4 at sink ≤ 2 m/s) is met by E1b and missed by E1 at 1 and 2 m/s.
- Peak force rises 2–6%. Restitution is 0.30–0.32, plausible for wire gear on rubber tyres (knowledge base estimate 0.36; not measured).
- No global order is claimed: lift-off and the clamp still switch the law, as the roadmap allows. The smooth intervals (rest, ring-down) keep fourth order (H11).

## Proof

- `test_touchdown.gd`, 12 checks:
  - onsets are 0.5 × static compression;
  - the force 1 nm into contact at 2 m/s is 8.7e-6 N, against 37.2 N for E1;
  - C¹ join at the onset;
  - 2000 states with every wheel beyond its onset are byte-identical to E1;
  - settled by a drop, 0.8 × rest compression is 1.59 × the onset;
  - no energy gain per tick in the three drops;
  - refinement within budget and better than E1 at every sink;
  - restitution 0.25–0.5.
- [`test_contact_policy.gd`](../../../../app/tests/test_contact_policy.gd) (H11, 72 checks): its fixtures now rescale the onset with their static compression; ring-down order, settling and switching-touchdown energy all pass.
- **Unchanged:** test_ground_contact (E1 hand loads, drop, h/h₂), test_ground_friction, test_ground_stiction, test_runway_start, test_takeoff_roll, test_ground_surfaces, test_p51_ground, test_crash, test_handling; all four goldens replay exactly (none touches down).
- **Mutations** on a scratch copy, each caught:
  - E1 law restored (4 checks);
  - unsaturated ramp (8, plus 31 in H11);
  - linear ramp with its kink (1);
  - ramp to the full static compression (1).
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (104 sections) in the shared tree and in a clean worktree with HEAD plus only this change.

## Limits and follow-ups

- Lift-off and the `max(0, …)` clamp still switch the force law; a landing golden (E4) should keep threshold-margin diagnostics.
- The 0.5 fraction, restitution and gear damping are estimates. A drop video of the real Stik (VAL) would measure them.
- The P-51 gear gets the same derived onset; its ground tests are unchanged.
