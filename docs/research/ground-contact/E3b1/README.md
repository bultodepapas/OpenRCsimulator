# E3b1 — Per-wheel stiction anchors

2026-10-07 · **Status: implemented and verified (numerical model). Breakaway factor estimated; field measurement open.** Main-line ROADMAP M2 E3b1; prerequisites H8 (state) and D1-R3 (support polygon) are done.

## Problem

The E2 tyre law has no memory. Its rolling resistance is regularised (∝ v below 1 cm/s), so a steady push below rolling resistance does not hold. The Stik idling on the mown runway crept about 1 cm/s ([E3a](../../ground-surfaces-e3a.md)): 102 mm in 10 s in this report's reference run. E3b (runway start, takeoff roll) needs a parked airplane that stays put.

## Model

This is the knowledge base's recommendation ([04 §2](../../roadmap-investigations/04-ground-handling-collisions.md)): an elasto-plastic "stuck point" per wheel (YASim pattern; Gonthier et al. 2004 bristle model), with modes changed once per tick.

- **State:** aux carries `[north, east, stuck]` per contact after the four sampled values, but only when the gear declares `breakaway_factor`. Gear without it, including the P-51's generated data, keeps the four-entry layout and the E2 law bit for bit. Trace columns and `aux_layout` metadata are unchanged; checkpoints and rollback carry the anchors (H8); restore rejects a stuck flag other than 0 or 1.
- **Inside RK4** (`Ground.loads`, pure; anchors frozen): a stuck wheel's tyre force is a spring-damper toward its anchor, split along the wheel heading. It is clamped at `breakaway·C_rr·N` along the wheel and `μ·N` across it (surface-scaled), then the friction circle applies. A sliding wheel uses E2 unchanged.
- **Once per tick** (`Ground.anchor_step` in `FlightSession._pre_step`, from the committed state):
  - sliding → stuck below `STICK_SPEED` 0.02 m/s (estimated; above the E2 creep), with the anchor at the wheel, so no energy is stored;
  - stuck → sliding when the **elastic** force `k·d` exceeds a hold, or the wheel leaves the ground.
- **Springs** (numerical, derived by the loader):
  - `Σk = m·ω²` with ω = 19.2 rad/s, a fixed frequency (ω·dt 0.08 at 240 Hz; the loader refuses ω·dt ≥ 0.1). The model is therefore the same at every tick rate.
  - Each wheel's share is its **static load share**: the barycentric weight of the CG projection on the D1-R3 resting facet. Stik: mains 0.366 each, nose 0.268. Holds ∝ N, so all wheels reach their hold at the same deflection (3.3 mm on the runway).
  - Damping ζ 0.7 on each wheel's mass share. The anchor yaw mode is at ω·dt 0.043.
- **Data:** Stik `landing_gear.breakaway_factor` = 1.25 (estimated; knowledge base bracket 1.0–1.5). Hold on the mown runway: 3.5 N, against 2.6 N idle thrust. On dry pavement: 1.4 N, so the Stik rolls at idle there, as before.

### Design decisions found by testing

1. **Release on the elastic force, not spring + damper.** With the damper included, the numerical damping force of a thrust-step transient broke a wheel free at 73% of its static load: one main released at 1.7 mm against a 3.3 mm hold. A sustained load breaks a tyre free; a transient damper force is clamped at the hold instead. This is the bristle/YASim rule.
2. **Springs by static load share, not equal.** With equal springs the lightly loaded nose saturated first and the release cascaded (breakaway at 2.76 N).
3. **No pre-loaded re-stick.** Re-sticking with a pre-loaded anchor would make the force continuous, but it creates energy: about 1.3 mJ per event, more than the airplane's kinetic energy at the re-stick speed, so friction could push the airplane backwards. The anchor starts unloaded.
4. **Breakaway is below the "all wheels at once" sum.** Thrust acting about 0.26 m above the ground moves load from the mains to the nose (0.73 N per newton of thrust), and the propeller torque unloads the right main, so the mains saturate first. The independent quasi-static prediction is 3.11 N, against 3.54 N if every wheel reached its static limit together. Load-proportional stiffness (YASim's ∝ N) would reach the sum, but it adds a ½k̇d² energy term; fixed springs keep energy exact.

## Proof

[`test_ground_stiction.gd`](../../../../app/tests/test_ground_stiction.gd): **25 checks, 0 failed.**

- **Loader:** springs match an independent side-view load split, and Σk = m·ω² exactly; a factor above 2 is refused; without the factor there are no anchor fields.
- **Unit checks against hand values:** at rest the stuck and E2 loads are identical; 1 mm of displacement pulls back Σk·1 mm to 1e-9 N; past the hold inside a stage the force is clamped at Σ breakaway·C_rr·N (3.5366 N) to 1e-9; 98% of the hold distance keeps every anchor and 102% releases them; wheels lifted 5 cm (within reach) release; a sliding wheel above `STICK_SPEED` stays sliding.
- **Parked:** 60 s at idle on the mown runway drifts **0.04 mm** after a 2 s settle, with every wheel still stuck (requirement < 2 mm). Reference: the E2 law alone creeps 102 mm in 10 s.
- **Breakaway:** throttle steps from engine start hold at 2.92 N and roll at 3.09 N, bracketing the quasi-static prediction of 3.11 N within 5%.
- **Energy:** an unclamped ring-down after a 1.5 cm/s nudge never gains energy (KE + PE + gear springs + anchor springs; the largest per-tick change is −4.8e-8 J).
- **Refinement:** 240 vs 480 Hz agree to 1.5e-12 m after 1 s.
- **Checkpoint:** a mid-hold checkpoint replays 200 ticks byte-identically, state plus anchors; a stuck flag of 0.5 is refused.
- **Airborne:** 960 trimmed-flight ticks are byte-identical in state and loads with and without stiction.
- **Takeoff:** at full throttle every anchor releases in 0.05 s, and the roll reaches 24.4 m/s in 3 s.
- **Mutation checks** on scratch copies, all caught: release on total force (early breakaway), never stick (5 checks fail; 550 mm drift), equal spring shares (2 fail), keeping anchors on airborne wheels, and an unclamped stuck force.
- **Other suites:** existing ground suites (E1 22, E2 26, E3a 28), H8 checkpoints (90), session guards (32), H9 replay policy (46), C7-R2 trace metadata (128) and contact policy (72) pass unchanged. H9's golden replay maps the aux layout (rpm, servos, anchors) and requires matching sizes; the policy gains an `anchor` component (1e-6 m; the flag is exact).
- **Integration fixes found by the full suite:**
  - The H7 checker instruments `Ground.loads` by unique source text. `anchor_step`'s copy of the compression branch now carries its own comment.
  - H7 also injects `const Ground` into `golden_flights.gd`, so the golden replay names its import `GroundContact`.
  - The trace header's `recording_start_aux` keeps its C7-R2 contract (the four `aux_layout` columns); the anchors are exact only in H8 checkpoints. The header's `ground` text names "stiction anchors (E3b1)" when they are active.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (92 sections, 379 s); goldens unchanged; every H4/H12–H15 oracle stays exact; H7 one-ulp sensitivity passes. [Summary](suite-summary.log).
- **Cost:** the fleet bench's 16 fingerprints are unchanged, because the bench fixtures use a four-entry aux and so run E2. Parked at idle on the runway, a stuck tick costs **399 µs/tick** (median of 8 × 480 ticks; E2 alone 343) on the shared target, within the 500 µs budget. `anchor_step` and the per-call aux slices are the next bit-exact cleanup candidates if a later measurement needs them.

## Limits

This is verification of a numerical model, not validation. `breakaway_factor`, `STICK_SPEED`, the spring frequency and the damping are estimated or numerical. The thrust at which a real Stik leaves its parking spot on the owner's grass, measured with a luggage scale (static pull, then steady rolling pull), would calibrate the factor; that is VAL work. Starting the engine instantly from rest is a 0 → 2.6 N thrust step, 84% of the quasi-static breakaway. The gear's pitch rocking (E1, ζ 0.4) briefly unloads the mains below their hold, a wheel releases and re-sticks, and the airplane slips **13.7 mm** before holding for good (measured probe). E3b2 starts from a solved equilibrium, and a real engine spools up over a fraction of a second; neither has this step. Lateral relaxation ("rolling" stuck point, tyre lag) is the knowledge base's L2 and is not modelled.
