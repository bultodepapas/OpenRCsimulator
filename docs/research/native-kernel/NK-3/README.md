# NK-3 — native stage evaluator, electric Ugly Stik (2026-10-27)

Step NK-3 of the [native-kernel scoping](../../native-kernel-scoping-2026-10-27.md#phases-r-research-i-implementation),
option (b): one `VehicleModel.stage` boundary on a prepared model. The owner approved NK-3 on 2026-10-27 and
delegated D1–D8 to the lead (port now; no SF-08 amendment; Linux bit-exact fingerprints, Windows later; backend
identity pinned in checkpoints; macOS reference-only; native refuses unknown laws; Stik first; reference always
available). Research only: nothing is installed into `app/`. Milestone 2 (the complete stage through the
kernel) builds on milestone 1 (the components), kept below as dated evidence.
Code and commands: [research/native-kernel](../../../../research/native-kernel/README.md).

## Milestone 2: the complete stage through the kernel

### Verdict

- The native joint stage replaces `FlightSession._wheel_evaluate` as `sim.model.stage` on a live session (one
  boundary, SF-08) and reproduces the reference byte for byte through the real kernel tick: 49,553 ticks in five
  cases. Trim, runway idle and manoeuvre run for 14,400 ticks each; the take-off tape and the lake glide each end in
  the same crash on the same tick. State, aux, continuous, inputs, loads and modes match on every tick, and so do
  the [session_probe](../../../../research/performance/session_probe.gd) fingerprints.
- The stage parts and the stage dictionary: 128,565 comparisons on 12,000 random tick contexts and states
  (918 malformed), all identical. Fault paths, a mid-run checkpoint/restore and the D6 fallback (P-51) also match.
- Per tick, at session_probe's boundary (median of three alternating pairs, two full runs): runway idle
  2.1–3.3 → 0.66–1.1 ms, trim 0.94–1.1 → 0.42–0.46 ms, manoeuvre 0.93–1.05 → 0.42–0.43 ms; per-pair speedups
  2.0–3.8×, 2.1–2.6× and 2.2–2.9×. The native stage then costs 24–36 µs per tick; 96–97% of the tick is still
  GDScript (pre-step, collision, input, kernel glue and observers).

### Findings

1. **Exact through the kernel.** With the milestone-1 rules, the propeller, hull, ground evaluation and assembly
   needed no special handling. The native stage was called four times and given its context once per tick in every
   run, and it was never uninstalled.
2. **Dictionary key type.** GDScript's `{loads = ...}` literal has `StringName` keys. A `String`-keyed native result
   is numerically equal and accepted by the kernel, but its bytes differ (all 11,421 stage dictionaries in the first
   stage-oracle run). The port now builds the reference's keys.
3. **The pre-step shields the stage from most overflow.** NaN or overflowing velocity and rates are rejected by
   the kernel's input checks or by the pre-step's downwash-lag update before any stage runs. Only a buried CG
   (1e306 m) reaches the stage, which then returns `{}` in both backends.
4. **Restore semantics (observation, not native).** After `checkpoint_json` → `restore_checkpoint_json` →
   `resume()` the session is paused with "checkpoint restored (recorded inputs)". The restored pass differs from the
   uninterrupted pass in both backends from the first tick (pitch command 0.0584 vs 0.0751). The two backends match
   each other exactly across the restore. The cause was not investigated.
5. **What stays GDScript.** See the attribution table. Once the stage is native, pre-step (anchors, servos,
   downwash lag), post-step collision, session input and the kernel's RK glue with `RigidBody.derivative` and
   observers make up nearly the whole tick. The research context hand-off (wrapped `pre_tick` calling the session's
   `_deflections`) moves the reference stage's first `_deflections` call into the pre-step. Pre-step time stayed
   within noise of the reference.

### Method

- **Adapter** ([stage_adapter.gd](../../../../research/native-kernel/stage_adapter.gd)): `config_for(session)` passes
  the committed model, gear, surface table, lake, prepared hull, layout, density and ground-effect reach, plus 14
  capability flags. `install` swaps `sim.model.stage` for the native method and wraps `pre_tick` to call
  `set_tick_context(aux, inputs, _deflections(aux), sim.time())`. No `app/` file changes.
- **Stage oracle** ([stage_oracle.gd](../../../../research/native-kernel/stage_oracle.gd), seed 20261027): 41% ground
  states as in milestone 1, 25% hull-heavy (any attitude, CG 0.1 m below to 0.6 m above the ground, including the
  lake bank), 34% airborne. Each state gets a random tick context: rpm 0, 0.5 (below `STOPPED_RPM`) or up to 1.1×
  maximum; servos; anchors at the contact points (stuck or sliding); downwash lag; random wind and density for the
  propeller component. 8% are malformed: special values, NaN, ±INF or negative stage times, wrong-sized wheel
  arrays. Each state compares the propeller, hull, `_ground_evaluation`, `_ground_up` and `_wheel_evaluate`
  against the live session. Coverage: hull loads in 3,266 states, 32,608 hull points over the lake's covered
  region, a turning propeller in 10,819, wheel loads in 5,749, and 271 stage results with non-finite loads.
- **Trajectories** ([trajectory.gd](../../../../research/native-kernel/trajectory.gd)): detached sessions built as
  session_probe builds them (Stik, default field, full scenery collision world, `near_runway` lake, soft hull).
  Each tick runs the session's `_physics_process`, then the simulation's.
  - Input tapes: session_probe's trim, runway and manoeuvre tapes, plus two research tapes, not pilot-qualified:
    take-off (throttle ramp over 1 s, rudder blip, pull at 5 s) and a lake glide from (110, 125, −10).
  - Comparison: the reference run, then the native run, in one process, compared tick by tick.
  - Fault paths: one injection at tick 1200 of the runway case, then `Simulation.step` (the kernel transaction).
  - Checkpoint/restore: manoeuvre case, checkpoint at tick 1200, run to 2400, restore, resume, run to 2400 again;
    each pass is compared between backends.
- **Timing:** session_probe's per-tick boundary (session `_physics_process` + simulation `_physics_process`), 600
  warm-up and 4,800 measured ticks per run. Three pairs per case, alternating which backend runs first; the
  medians of the pair medians and of the pair p95s are reported.
- **Attribution:** in both backends alike, GDScript wrappers time `pre_tick`, `stage` and the post-step collision
  callback; three alternating repeats, medians. The native stage's own time comes from the extension's counters.

### Results

Full data: [results-stage-linux-2026-10-27.json](results-stage-linux-2026-10-27.json) (stage oracle, trajectory run
with timing and attribution, an earlier timing repeat, the negative control).

| Stage part (12,000 states) | Compared | Identical |
| --- | ---: | ---: |
| Propeller loads (stage inflow, then `Propulsion.loads`) | 12,000 | 12,000 |
| `HullContact.loads` | 12,000 | 12,000 |
| `_ground_evaluation` ok flag / loads / wheel rates | 12,000 / 11,421 / 11,421 | all |
| `_ground_up` | 12,000 | 12,000 |
| Stage shape; loads, derivative, rotor momentum, dictionary bytes (579 `{}` in both) | 12,000; 11,421 each | all |
| D6 refusals (14 capability flags, tilted and electric propellers, live-mass hull, wash pieces) | 18 | 18 refused |

| Case | Ticks | End (both backends) | Fingerprint (both) |
| --- | ---: | --- | --- |
| Trim | 14,400 | flying | `32f76875fb843374…` |
| Runway idle | 14,400 | rolling | `85637b42b1c0e117…` |
| Manoeuvre | 14,400 | flying | `8676b495cda9ce9a…` |
| Take-off tape | 2,507 | crash, hull point 25 at 37.4 m/s | `d011d6a12f2593b0…` |
| Lake glide | 3,846 | crash, hull contact at 8.4 m/s | `64e0d6d0da8f2404…` |

| Injection at tick 1200 (runway), then `Simulation.step` | Both backends reject with | Bytes after |
| --- | --- | --- |
| NaN body velocity | current state is nonfinite, malformed, or has a degenerate quaternion | equal |
| NaN wheel speed | input or auxiliary state is nonfinite or malformed | equal |
| Velocity 1e180 / rates ±1e200 | pre-step produced nonfinite or malformed auxiliary state | equal |
| CG buried at 1e306 m | joint stage evaluation is nonfinite or malformed (stage returns `{}`) | equal |

Checkpoint/restore: both 1,200-tick passes equal between backends. D6 fallback: the P-51 (`p51d-mustang-120`) is
refused ("unsupported session capability: retractable"), keeps its `evaluate` stage, and its 960-tick
fingerprint equals a session where nothing was attempted. Negative control (`--mutant`: three more reassociated
sums in the hull, propeller and terrain, plus the milestone-1 sites): differing propeller loads 4,465, hull 590,
ground loads 3,063, wheel rates 2,079, ground-effect height 6,014, stage loads 4,943; verdict fail.

| Per-tick µs, session_probe boundary | Reference median | Native median | Reference p95 | Native p95 |
| --- | ---: | ---: | ---: | ---: |
| Runway idle (run A / run B) | 2,141 / 3,251 | 659 / 1,112 | 3,452 / 6,333 | 1,345 / 2,361 |
| Trim | 936 / 1,109 | 422 / 455 | 1,410 / 2,081 | 659 / 938 |
| Manoeuvre | 926 / 1,047 | 422 / 427 | 1,505 / 1,906 | 625 / 693 |

Host load (1/5/15-minute load average): run A (17:55 UTC) 9.99 / 5.91 / 5.44 at start and 5.07 / 7.43 / 6.84 at
the end. Run B (18:08 UTC) 4.81 / 5.93 / 6.36 at start, 3.4–4.4 (1 min) during the cases, 4.48 at the end.
Debug editor binary on 12 shared logical CPUs, with other sessions running Godot. Run B's runway pairs were
slower in both backends.

| Attribution, µs per tick (run B, median of 3 repeats) | Runway reference | Runway native | Trim reference | Trim native |
| --- | ---: | ---: | ---: | ---: |
| Session input (`FlightSession._physics_process`) | 221 | 176 | 167 | 135 |
| Pre-step (`pre_tick`) | 322 | 295 | 189 | 193 |
| Stage, four calls (inside the extension) | 1,782 | 36 (30) | 700 | 24 (18) |
| Post-step collision | 174 | 134 | 141 | 124 |
| Kernel remainder (RK4 glue, `RigidBody.derivative`, validation, observers) | 279 | 192 | 246 | 202 |
| Tick | 2,777 | 832 | 1,443 | 678 |

### Limits

- Linux x86_64, one shared host, debug VM, no release template or target host; Windows is not built (design note in
  the [code README](../../../../research/native-kernel/README.md#windows-design-note-not-built)); macOS is
  reference-only.
- The native stage covers only this route: the electric Stik, fixed gear, legacy propeller, soft hull, calm settled
  weather. Every other aircraft or option falls back. The fallback is shown at session level for the P-51 only;
  other cases are shown by flag-level refusals. No fleet fingerprint run.
- Deterministic test tapes, not pilot flights; one oracle seed. The research context hand-off is scaffolding, not
  the integration design.

### Remaining work to app integration

| Item | Work |
| --- | --- |
| Packaging and receipt | Install into an ignored `app/native/kernel/` with descriptor, per-platform receipt (binary, source, lock and mirrored-source hashes) and godot-cpp licence, as the truck does; the loader checks the receipt and binary hash before `GDExtensionManager.load_extension`; ABI and backend version |
| Selection | Session backend setting, reference by default until qualified; `prepare_stage` at every revision boundary (aircraft commit and Workshop edits, `set_field`, `set_lake_context`, `set_collision_world`, hull re-prepare, `setup_weather`, soft-hull toggle, mass change, reset, restore) |
| Tick context | Replace the research `pre_tick` wrapper by a session hook in `_kernel_pre_step`, or port `_deflections` and read aux natively; the stage stays the only native boundary (SF-08) |
| Identity pinning (D4) | Backend identity and binary SHA in the checkpoint configuration hash and `trace_meta`; a checkpoint or `.orfl` from another backend restores only as a candidate |
| Fallback (D6, D8) | Reference installed first; a refusal, load failure, receipt, ABI or law-identity mismatch keeps it and records the reason; optional debug shadow mode comparing both every N ticks |
| Tests and CI | `app/tests` for loader, receipt, refusal and checkpoint identity; a Linux CI job building the library and running the stage oracle and a short trajectory run; a rule that edits to the mirrored GDScript (receipt list) keep the oracles passing |
| Gates still open | Fleet fingerprints (every other aircraft refused, unchanged), p50/p95 with the release template on the target host, the Windows build |

About 1–1.5 weeks for packaging, selection, identity pinning and tests (low confidence); target-host timing and
Windows depend on hardware access.

## Toolchain and identity

| Item | Value |
| --- | --- |
| Host | Ubuntu 24.04, Intel i5-10500 (12 logical CPUs, shared VM), glibc 2.39 |
| Godot | 4.8.beta1.official.4d10419ca editor `28485fbd…5e82` (debug VM; no release template) |
| godot-cpp | 10.0.0-stable `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, API 4.7, profile {OS, RefCounted} |
| SCons | 4.10.1 wheel `bd9d1c52…7e126` (shared `research/native-slipstream/build.py`) |
| Compiler | g++ 13.3.0, `template_release` + `-fno-fast-math -ffp-contract=off -fexceptions -std=c++17` |
| Library (milestone 2) | `libopenrc_native_kernel.so` `a9b36f67792e850b069a115ac93d6f4e07e50e1c67115f4ba5abac0fa13300af`; sources `e47eae36…8cf5`, builder `ea96e1ea…8c3b`; mutant `697f9644…9199` |
| Library (milestone 1) | `58bffae91422c8e433a2858b0da4f3d46f23036b0950b4da66e37f08fc8fd50f`; sources `155a4068…6263`; mutant `90823587…ff52` |
| Imports | `atan2`, `cos`, `sin`, `sincos`, `sqrt` @GLIBC_2.2.5, `pow` @GLIBC_2.29; lock `850f6cf3…fa34` |
| Reference | `430c5feb6` plus the live tree: `app/sim/flight_session.gd` `d3cc9169…46b8` carries another session's uncommitted out-of-trim edit; the JSON records every mirrored source's hash |

## Milestone 1: components

### Verdict

- The terrain + lake sampler, GP-02 wheel evaluation and compressions, `Air.compute`, `GroundEffect.factors` and
  `Aero.loads` (with `_global_loads`, `_local_loads`, `local_flow_weight` and the wing wake source) return the
  reference's bytes: 488,259 comparisons, 0 differences, including 2,440 malformed (NaN, ±INF, ±0, subnormal,
  ±DBL_MAX) input sets (1,662 wheel, 778 aero). Every stage output has ≥ 12,000 states on the production Stik context
  (wheel outputs 15,900, aero outputs 18,000 with variants).
- A deliberately mutated build (reassociated sums, one commuted sum) fails the same oracle in every mutated
  component, so the oracle detects one-operation order changes, including NaN-priority-only ones.
- Through the GDExtension binding a component call is 40–67× cheaper than the GDScript call on the debug VM
  (wheels at runway rest 121 → 2.9 µs; aero 105–185 → 1.7–2.9 µs; medians of three runs).

### Findings

1. **Plain C++ doubles are not enough for malformed inputs.** With the GDScript arithmetic copied operation by
   operation, every finite result matched, but 53 of 305,459 comparisons (smoke run, malformed states only)
   differed in the sign of a NaN: aero loads 7, `_global_loads` 22, `_local_loads` 7, wheel loads 16, wake
   source 1. Mechanism: x86 SSE2 returns the first operand's NaN when both are NaN; the pinned engine's GDScript
   evaluator is left-first on every path (typed, Variant, packed, compound; probed), while GCC commutes `+` and
   `*`. Example (oracle input, rim speed +INF on one wheel): the slip force is +INF, the friction-circle scale
   `limit / INF` is 0, so `tire · scale` is the default NaN `0xfff8…` and so are the wheel forces; the rim
   derivative `(−tire − brake/r) / m` keeps the negated `0x7ff8…`, and so does `spin = (I/r) · rate`. In
   `loads[3] += r[1]·fz − r[2]·fy + spin·(…)` the reference keeps the left `0xfff8…`; GCC's `addsd` kept
   `spin`'s. Fix: all port scalars are `nk::R`, whose `+ − × ÷` are single SSE2
   instructions with the left operand first (inline asm). After the fix: 0 differences. Kernel cost rose roughly
   10–30% (loosely measured under load).
2. **Engine C++ helpers have their own operand order.** `lerpf` is engine C++, not the evaluator; its NaN priority
   is `weight · (to − from) + from` (17 math-probe NaN cases until mirrored). Finite results are unaffected.
3. **Engine helper semantics hold:** `absf` keeps a NaN's sign (not `fabs`), `maxf`/`minf`/`clampf` are the
   `a > b ? a : b` forms, `wrapf` matches godot-cpp's copy; 290,206 probe values identical, 32 float literal
   spellings parse to the same bits in GDScript and GCC. GDScript's `-0.0` literal is +0.0 (NK-1); the oracle's
   self-test caught its own use of it.
4. **D6 refusal works at prepare time.** Flaps, tailless elevons, a tabulated wing polar, an empty envelope, an
   unknown `surfaces` key and an unknown contact key are all refused with a reason; key allowlists cover every
   dictionary the ported laws read, so a new optional term added in GDScript disables native instead of being
   silently ignored.
5. **Gain is in the components that dominate the runway tick.** Reference cost per call on this VM: aero
   105–185 µs, wheels 121 µs, terrain 13 µs. A Stik runway stage calls aero, wheels and the ground-effect
   terrain once, four stages per tick: roughly 1.0 ms of reference work against about 0.02 ms native. This is an
   inference from component calls, not a tick measurement.

### Method

- **Reference.** `oracle.gd` runs with `--path app`; it preloads `app/physics/*.gd` and builds a real runway
  session (default field, `near_runway` lake, runway start, soft hull contacts) for the model, gear, surface table,
  lake and rest state. The extension loads at run time (`GDExtensionManager.load_extension`).
- **Comparison.** `var_to_bytes` of each output; a difference is classed as finite ulp, ±0, NaN bits, class or
  shape and recorded with exact bit patterns. A self-test must first flag a one-ulp, a zero-sign and a NaN-sign
  change. Law identities (`Aero.LOADS_LAW`, `Wheels.ROLLING_LAW`) must equal the native's.
- **Wheel states** (seed 20261027): around the rest pose over runway, rotor pad, grass and the lake bank; yaw
  anywhere, ±0.25 rad tilt or any attitude; ground clearance −0.06…+0.09 m about rest; creeping, rolling or wild
  velocities and rates; anchors at the contact points ±2 cm, stuck/sliding/garbage flags; rim speeds within ±3 cm/s
  of the contact speed (stuck path) or ±30 m/s; 10% malformed (special values in state, rims or anchors) and 6%
  wrong-sized anchor/rim arrays. Contexts: Stik (12,000), brake/steer/default-key gear variant, flat table without
  lake, invalid table, invalid lake, no gear.
- **Aero states:** 45% attached cruise (α −0.1…0.13, β ±0.08, 6–35 m/s), the rest any direction, near-zero and
  zero airspeed, rates to ±30 rad/s, wind, density 0.9–1.3, deflections, downwash lag NaN or set, ground height
  from the dry terrain under the CG or NaN; 8% malformed. Model variants: twist + `wing_cm_ac` + body side force,
  no ground effect, uncoupled strips, legacy horizontal tail.
- **Timing.** Alternating reference/native rounds (15 rounds of 1,000–5,000 calls), median µs per call; the
  native kernel alone is a 100,000–200,000-call loop inside the extension. Three full runs; the table gives the
  median and range. Editor (debug VM) binary, `nice 19`, load average 8–13 from other sessions on 12 cores.

### Results

Full data: [results-linux-2026-10-27.json](results-linux-2026-10-27.json) (library `58bffae9…`; first run with build
receipt, two timing repeats, the negative control). All three runs gave identical comparison counts. Re-run with
the milestone-2 library `a9b36f67…` at `430c5feb6`: 488,266 of 488,266 identical (seven more literals).

| Component | Compared | Identical |
| --- | ---: | ---: |
| Wheel loads / rim derivatives / compressions | 15,900 each | 15,900 each |
| Terrain with lake / without lake | 12,000 each | 12,000 each |
| `Aero.loads`, `Air.compute`, `GroundEffect.factors`, `local_flow_weight`, `_global_loads`, `_local_loads`, wake source | 18,000 each | 18,000 each |
| Surface-table validity (edited tables) | 315 | 315 |
| Math-shim probe / float literals / timing inputs | 290,206 / 32 / 6 | all |

Coverage on the Stik context: 7,316 of 12,000 wheel states loaded (17,124 loaded wheels, 3,244 stuck, 4,822 over
the lake's covered region, all four surface rows); the variant gear adds 1,521 braking wheels. Aero: 4,720 states
in the oracle domain (blend 0), 646 blended, 6,578 local strips, 56 NaN blend; ground effect active in 4,368,
downwash lag in 7,917; 536 malformed; 187 states where the reference itself is non-finite.

Negative control (`--mutant`, same seed and counts): differing outputs in aero loads 220 and `_global_loads` 279
(finite ulp), terrain 7,055 / 5,540, wheel loads 6,023 (27 of them NaN-bit only), rim derivatives 4,354,
compressions 9,100; the unmutated components stay identical.

| Component call (Stik) | Reference µs | Native via binding µs | Native kernel µs | Binding speedup |
| --- | ---: | ---: | ---: | ---: |
| Wheels, runway rest (3 wheels, lake context) | 121 (90–148) | 2.85 (1.76–3.00) | 0.63 (0.60–1.18) | 43–51× |
| Aero, runway rest (ground effect, blend 0) | 116 (91–173) | 1.73 (1.50–2.75) | 1.12 (0.93–1.32) | 61–67× |
| Aero, take-off 12 m/s (ground effect) | 185 (109–190) | 2.94 (2.28–3.85) | 1.95 (1.56–2.86) | 48–65× |
| Aero, cruise 15 m/s (blend 0) | 105 (58–111) | 2.59 (1.41–2.70) | 1.33 (0.83–1.53) | 41× |
| Aero, post-stall (local strips) | 107 (71–147) | 2.57 (1.76–3.05) | 1.29 (1.07–1.49) | 40–48× |
| Terrain sample, runway with lake | 13 (7–13) | 0.76 (0.46–0.76) | — | 15–17× |

Reference cost includes `Air.compute` (native computes it inside). Binding cost includes argument marshalling and
the returned packed array or dictionary.

### Limits

- Component calls only (milestone 2 adds the stage and trajectories). Debug-VM timings on a loaded shared VM are
  indicative (ranges above).
- Seeded random states, not exhaustive. Flaps, tailless elevons, the wing polar, slipstream and spatial
  (station-delta) air are refused, not ported.

## Reproduce

```bash
python3 research/native-kernel/build.py --jobs 4                           # library, descriptor, receipt
python3 research/native-kernel/run.py                                      # milestone-1 components
python3 research/native-kernel/run.py --script stage_oracle.gd             # stage parts, D6 refusals
python3 research/native-kernel/run.py --script trajectory.gd --timeout 3500 \
  --option ticks=14400 --option pairs=3 --option warmup=600 --option samples=4800 --option repeats=3
python3 research/native-kernel/build.py --jobs 4 --mutant                  # negative control
python3 research/native-kernel/run.py --mutant --script stage_oracle.gd    # expect verdict=fail
```
