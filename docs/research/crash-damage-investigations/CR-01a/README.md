# CR-01a — Tick-boundary crash diagnostics

2026-10-07 · **Status: implemented and verified; CR-01 crossing reconstruction remains open.** Bounded first increment of [CR-01](../../../CRASH-DAMAGE-PLAN.md). Owns `app/physics/impact_snapshot.gd`, the crash-only session hook, focused tests and [reproduction tools](../../../../research/crash-damage/cr-01a/).

## Contract

The existing detector still decides whether flight stops: hull contact first, then gear compression strictly beyond travel. After that decision, a typed snapshot records the observed simulation tick and an owned copy of its rigid-body state. No force, integrator, aircraft input, trigger threshold or ordinary-flight callback is changed.

Hull snapshots select the first penetrating point **in data order**, using exactly the current detector's arithmetic and `down >= 0` boundary. The index identifies a point only within the loaded model; it is not a stable component ID or a claim about which point struck first in time. The readout numbers hull points from one; the stored index starts at zero.

For a hull point at body offset `r`, its world position is `position + R r`; its world velocity is `R(v_body + omega_body × r)`. `down_speed_mps` is signed along NED down; the flat-ground normal is `[0,0,-1]`. The snapshot's point speed differs from the existing `crash.speed`, which remains CG speed. Nonfinite derived kinematics leave `has_kinematics=false`, empty arrays and unused zero scalars rather than exposing infinity.

Gear snapshots retain the first over-travel leg's existing name, undeformed body coordinate, compression and travel limit. The undeformed point's rigid-body velocity is not the actual compliant wheel's velocity, so gear contact kinematics remain explicitly unavailable. The cause reads “landing gear travel limit” rather than asserting structural collapse.

Snapshots are transient read-only observations. Consumers must not mutate them: a deep Dictionary copy retains references to contained RefCounted objects. State/geometry arrays are duplicated at capture. Menu holds retain the observation; reset, successful reload or checkpoint restore clears it with the existing `crash` record. Simulation checkpoints and CSV metadata are unchanged; replay is still downstream of live-session crash countdown behavior.

## Scope left open

CR-01 is **not complete**. Earliest sub-tick contact, interpolated crossing pose, physical component labels, rendered crossing-pose acceptance and localized UI wording remain separate work. Tick-end snapshots may already penetrate the field. This step does not infer structural strength, damage severity, contact impulse, pilot error or actual failure of a gear leg.

## Verification

The candidate is built and tested in an isolated clone of `a6c1e4d4a0c90c4f6160566ffc60075450341d62`, with isolated runtime settings. Shared landing, aircraft-schema, stall-search and visual work is excluded from the evidence baseline.

- [Full isolated `app/test.sh`](app-tests.log) passes all 133 sections, including goldens, UI, fleet model contracts, trace failures and 30/60/144 FPS hashes. [Exact source hashes](verification.json); [lint](lint-counts.json): zero errors, unchanged 12 pre-existing warnings.
- [42 focused checks](focused-tests.log) pass and exercise analytical translated/rotated point velocities, `omega × r`, signed motion, boundary inequalities, contact ordering, explicit unavailable fields, overflow refusal, data ownership, readout wiring and lifecycle behavior.
- Three deliberate defects are rejected on disposable copies: omit point rotational velocity, change hull `>=` to `>`, change gear `>` to `>=`. The unmodified control passes. [Mutation evidence](mutations.log).
- [All four three-second numeric CSV records](comparison.json) are byte-identical to baseline (721 samples each). Five timing batches cover trimmed/stalled actual-session ticks and crash-only snapshot construction; the latter medians are 35.1 µs Stik, 34.8 µs Extra, 38.1 µs P-51 and 39.2 µs Avanti.

Run from the repository root:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_crash_snapshot.gd
app/test.sh
python3 research/crash-damage/cr-01a/compare.py --godot "$(app/get-godot.sh)" \
  --baseline /path/to/baseline-clone --candidate /path/to/candidate-clone \
  --output /tmp/cr01a-comparison.json
```

The comparison imports both supplied projects and uses isolated user-data directories. Timings are batch-average observations on a concurrently loaded development host, not individual-tick percentiles or target-hardware acceptance. Snapshot construction occurs only after a detected crash; the ordinary-flight branch executes the same operations as before.

The geometry/kinematics definition follows the existing [rigid-body layout](../../../../app/physics/rigid_body.gd), [ground-contact model](../../../../app/physics/ground_contact.gd) and [crash architecture investigation](../05-architecture-impact-model.md). Fixtures and tools are original repository code. Independent Luna Max review checked detector equivalence, frames and lifecycle coverage. The final focused rerun strengthens the active-crash manual-reset precondition; production files are identical to the full-suite run. The same 42 checks pass after integration into the shared app.

Ready-to-paste commit message:

```text
CR-01a: record typed tick-boundary crash diagnostics

Proof: 42 focused checks and full isolated app/test.sh pass; three
contact-math mutations fail; all four 3 s numeric traces unchanged.
Snapshot cost 35–39 us on the shared host, only on crash. No force or
aircraft-data changes; crossing pose/component labels remain CR-01.
```
