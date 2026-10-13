# AV-18…20: continuous turbine RPM implementation

2026-10-13 · **Delivered software slice:** explicit continuous RPM, stage thrust/gyro, endpoint telemetry, strict state/trace/checkpoint guards. The [active plan](../../../plans/turbine-realism.md) owns future ECU, fuel and physical-validation work. [AV-18](../AV-18/README.md) owns the manufacturer/source review. This report does not claim measured P100 response or finite fuel.

## Result and scope

The experimental Ventage Jet's source generator now selects `propulsion.engine.spool_integrator: rk4`. One continuous float64 RPM evolves alongside the body; each RK stage uses its own RPM for the existing governor/rate schedules, thrust and rotor gyro. `AUX_RPM` mirrors the accepted endpoint for existing render/audio/trace consumers. The sampled helper and absence/`sampled` remain the historical route.

No numeric engine or airframe coefficient was retuned. Steady thrust/fuel/ram tables, prescribed wet mass, rotor-inertia/sense assumptions and the unresolved transient mounting torque retain their earlier evidence scope. Stage coupling is a numerical correction; it does not fit the engine to new measurements.

Delivered interfaces:

| Definition/state | Consumer and boundary |
| --- | --- |
| Optional categorical `engine.spool_integrator` | Contract enum/engine shape → strict loader → `Turbine.is_continuous` → session callback selection; source generator explicitly selects the catalog route |
| Continuous RPM slot 0 | Pure joint evaluation supplies body loads, continuous derivative and gyro; optional auxiliary mirror is a projection, not a second evolving state |
| Governor/rate-table slope | Launch preflight requires `dt * max(1/tau, absolute table slopes) <= 0.25`; unsupported dynamic-wheel turbine combinations are refused |
| `FlightSession.turbine_state()` | Read-only accepted RPM/demand, airspeed, gross/net force and current fuel-map estimate; mass policy remains `prescribed_fuel` |
| Flight checkpoint v8 | Engine law, complete continuous/sampled/discrete state and weather identity; collision wrapper v7 carries inner format v8 |
| Trace model `turbine-rpm-governor-rk4-v1` | Existing CSV RPM column is the endpoint; load columns refer to k1 RPM/body. Writers/readers reject malformed/mixed sampling metadata |

An explicit unpowered glide initializes zero RPM. This slice deliberately refuses a hot `engine_running=false` transition rather than inventing a fuel-cut/thermal law or silently forcing RPM to zero. AV-05b supplies that future lifecycle. The checkpoint tests now use an explicit cold-glide start for the nondefault turbine mode; hot-transition refusal has its own regression.

## Evidence and independent rejection controls

Native engine: pinned Godot 4.7.2-stable, `ed1daf0bf`. Paired Linux baseline source is `5f3b73740d9cbf5983b23bf19c20f8224cd64b9f`; the candidate is an isolated Linux checkout with the reviewed turbine overlay and concurrent crash-contact dependency. The [summary](summary.json) fingerprints the actual core/data files used for comparison. Windows Godot was used for draft parse and focused checks; Linux LF checkouts were used for paired verification and suite qualification. No tests read/write player preferences in the paired probe.

| Check | Result |
| --- | --- |
| `test_turbine.gd` | 27 checks pass; historical helper/loader/thrust/gyro equations preserved |
| `test_turbine_continuous.gd` | 46 checks pass: selector/branch refusals, stiffness, stage sampling, pure observations, analytic response/impulse/position, replay/rollback, hold/reset and trace guards |
| `test_avanti_handling.gd` | 47 checks pass; broad model consistency, finite complete maneuvers and lifecycle retain their experimental scope |
| `test_checkpoint.gd` | 92 checks pass; cold turbine mode and powered reset/reload, full continuation and invalid-mode refusal |
| Atmosphere flight integration | 142 checks pass; reference snapshots ignore physically inactive stored atmosphere fields, custom-air trim and replay remain consistent |
| Python trace acceptance | 16 tests pass in the frozen Linux candidate; mixed sampling, invalid/missing state and wrong law are rejected |
| Focused shared regressions | [11 scripts pass](focused-checks.json), including checkpoint integrity, continuous-state rollback, session guards, coupled propeller shaft and electric fixed-bus/battery behavior |
| AV-18 reducer | 11 tests pass: up/down/rated crossings, sample support, dwell and uncertainty; no physical run is implied |
| AV-10b reference | 5 tests pass: open-system momentum, constant-thrust solution, annulus drainage and fixed-datum/current-CG transforms; production fuel remains pending |
| Schema/parameter register/aircraft generator | `--check` passes on the authoring platform; categorical selection is the intentional aircraft-data change |

The synthetic governor fixture has `tau=0.4 s`, initial 90,000 RPM and target 91,000 RPM. Its RPM errors at 120/240/480 Hz are approximately **3.2781e-7 / 2.0329e-8 / 1.2515e-9 RPM**, consistent with fourth-order refinement on this smooth branch. A synthetic linear-RPM force independently checks the integrated impulse and position; endpoint-held body force cannot pass it. These very small errors describe numerical arithmetic, not hardware accuracy.

The paired probe flies five aircraft for 720 ticks with the same commands, recording six complete-state digests per aircraft. **All four inactive aircraft are bit-identical** in body, previous body, continuous/sampled/discrete state, inputs, loads, clock and mass/inertia. The turbine changes intentionally. The summary reports its position, velocity, attitude chord and angular-rate deltas separately, with units.

Two real-code mutations run only in disposable script copies:

1. Replace stage RPM with sampled `AUX_RPM` inside the actual turbine evaluator. Stage thrust/gyro and smooth governor/impulse/refinement assertions fail.
2. Keep the old RPM in the endpoint mirror. Mirror, lifecycle and trace assertions fail.

Each mutation has a passing unmodified control, a nonzero exit and a completed assertion count; script/runtime errors are rejected as proof. No production source is deliberately mutated.

## Response numbers and interpretation

The [response summary](response-summary.json) is a **synthetic fixed-body stand** at 240 Hz, zero airspeed and reference density. It reuses the actual engine law while a stand reaction cancels aircraft loads. Initial/target thrusts are the installed model's 1.84644/92 N. The command edge is at 1 s; values below are elapsed after the edge. The public reducer distinguishes normalized endpoint progress from percent rated thrust and retains a 4.167 ms sampling bracket with 50 ms crossing dwell.

| Transition | Integrator | t10 | t50 | t90 | t95 |
| --- | --- | ---: | ---: | ---: | ---: |
| Idle → full | Historical sampled | 1.418433 s | 2.590468 s | 3.324394 s | 3.601655 s |
| Idle → full | Continuous RK4 | 1.417253 s | 2.588312 s | 3.322110 s | 3.599367 s |
| Full → idle | Historical sampled | 0.057422 s | 0.361944 s | 1.141673 s | 1.428877 s |
| Full → idle | Continuous RK4 | 0.057493 s | 0.362397 s | 1.143104 s | 1.430667 s |

Sub-millisecond displayed digits are interpolation output, not acquired resolution. The existing several-second spool behavior is preserved; the numerical difference is a few milliseconds. No claim is made that these schedules reproduce a particular physical P100 ECU preset. AV-21 needs matched independent engine observations before retuning.

## Integration findings

- A legacy atmosphere test assumed every atmospheric checkpoint was v3. Continuous turbine state needs v8; the test now checks the active law while preserving the physical atmosphere assertions.
- Reference-mode checkpoint equality initially exposed ignored stored atmosphere values in the new v8 weather payload. Calm/reference snapshots now serialize the canonical reference configuration, so inactive UI values do not alter physical replay identity.
- The existing generic checkpoint fixture forced a hot binary stop. That behavior is unsupported for this slice; a cold glide provides a valid nondefault discrete state, while a separate test verifies that an unsupported hot stop rolls back rather than erasing RPM.
- Native JSON header reparse differs by one float64 ULP at the trimmed RPM. The first-row trace comparison allows **1e-9 RPM**, while native continuous/aux checkpoint equality remains exact. This is a diagnostic serialization allowance, not a simulation tolerance.
- A read-only review found that calm turbine traces could accept malformed servo metadata. Header entries and all native rows now require finite values; gaps are refused and physical metadata freezes at the first accepted sample.
- Parallel audio/crash work introduced one session merge conflict. Both independent identity additions were retained. Verification uses frozen source copies, and the crash-contact dependency was carried with its session caller.

## Reproduce

Standard setup and the Linux/WSL LF workflow are in [TOOLS](../../../TOOLS.md). Existing `app/test.sh` discovers the new GDScript test automatically.

```bash
python3 research/aircraft-standardization/build_schema.py --check
python3 research/aircraft-standardization/parameter_register.py --check
python3 research/avanti-s/av06/derive_physics.py --check
python3 -B -m unittest discover -s research/avanti-s/av18 -p 'test_*.py'
python3 -B -m unittest discover -s research/avanti-s/av10 -p 'test_*.py'
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_turbine_continuous.gd
```

Paired verification requires imported, frozen baseline/candidate repositories and a fresh output directory:

```bash
python3 research/avanti-s/av20/verify.py \
  --baseline /absolute/baseline --candidate /absolute/candidate \
  --godot "$(app/get-godot.sh)" --out /absolute/fresh-evidence
```

This produces raw native response captures, complete-state hashes, reduced response metrics, passing-control and mutation logs, and a source-fingerprinted summary. Generated raw captures stay outside `app/`. The observational timing in the probe is not an idle-target Gate P result; the 500 µs budget remains open.

## Full-suite qualification and next gates

The frozen pre-change full suite reproduced an unrelated `test_landscape_gravel.gd` failure (47 remaining cells). Later candidate qualification exposed the atmosphere/checkpoint expectations addressed above, which now pass. The final frozen `app/test.sh` run passes import, schema/tool/float64 guards, every-script parsing and the tests through the crash integration case, then **stops at `test_crash_integration.gd`: 95 checks, 2 failed**. Both failures are the Stik/Extra assertions that crash detection preserves the complete simulation checkpoint.

The same two assertion failures reproduce in a disposable copy of that candidate with `turbine_is_continuous()` forced false. This is a control for independence from the new turbine route, not a passing mutation test or a claim that the whole project suite is green. [Suite qualification](suite-status.json) records the exact failures. No unrelated crash test was weakened. Later full-suite tests are not implied to have run; the separate focused regression set covers the relevant turbine/session/shaft/electric/atmosphere paths.

Next required work remains AV-21 matched response/steady identification, AV-22/05b source-backed thermal/start/cut/cooling state, and AV-10a/b/c finite fuel with consistent mass/CG/inertia. The [variable-mass reference](../../../../research/avanti-s/av10/README.md) shows why a fixed-centroid fuel box and a single pickup cannot be combined blindly: mass and angular-momentum flux must match the declared distribution. No fuel mass is consumed in this delivered runtime slice.
