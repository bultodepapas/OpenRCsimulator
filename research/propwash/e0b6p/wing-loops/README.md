# E0b6p — Wing-loop invariant experiment

2026-10-09 · **Status: verified experiment; combined candidate not adopted.**

`candidate.py` hoists per-call aileron, incidence-presence and coefficient reads in `Aero.wing_lift_coefficient`, and computes each induced-map row offset once in that helper and `_local_loads`. Floating-point expressions, strip count and summation order stay fixed. No value is cached across calls or RK stages.

The experiment stages independent baseline/candidate scripts in a disposable app. The source application is not edited by the runner. `verify.gd` compares original float64 bytes over 1,024 manufactured requests: four fleet aircraft, induced-map present/absent, incidence present/absent, and 64 varying states/control settings. Wing lift, local loads and blended loads include instantaneous and held downwash. This is a numerical equivalence sweep, not physical validation.

The paired flight probe reuses the established stage-sharing fixtures: 1,216 direct-load requests and 30 flights with initial state plus 240 boundaries each. Timing alternates baseline/candidate order with warmups excluded; direct and flight samples are batch averages. The prepared option uses independently prepared model snapshots in both paths, while preserving the GDScript legacy route. The GDScript option checks the production backend. Run all timing jobs sequentially.

Do not assume an improvement from source-level operation counts. Retain raw paired timings, original trajectory hashes, candidate patch, input hashes and engine logs; compare whole ticks before accepting the candidate. The application suite and existing goldens remain the production regression gate.

## Run

From the repository root, use a fresh output directory for every run. The prepared option requires the existing hashed build; build it with `research/propwash/e0b6p/prepared-model/build.py --jobs 2` if absent.

```sh
python3 research/propwash/e0b6p/wing-loops/run.py \
  --godot "$(app/get-godot.sh)" --backend prepared --output /tmp/wing-prepared --keep-work
python3 research/propwash/e0b6p/wing-loops/run.py \
  --godot "$(app/get-godot.sh)" --backend gd --output /tmp/wing-gd --keep-work
```

`--project /path/to/app` selects a source snapshot. If the current Aero implementation has changed, recover the measured baseline and provide it explicitly; the override replaces only the disposable copy:

```sh
git show 77312ec:app/physics/aero.gd > /tmp/wing-baseline.gd
python3 research/propwash/e0b6p/wing-loops/run.py \
  --godot "$(app/get-godot.sh)" --baseline-aero /tmp/wing-baseline.gd \
  --backend prepared --output /tmp/wing-reproduction --keep-work
```

For full reproduction, use the source revision and application hashes recorded in the evidence, not an arbitrary later app with different physics. `--build` selects another prepared manifest. `--keep-work` retains the staged app at the path written in `evidence.json`; otherwise the temporary project is removed. All raw engine reports, the candidate patch and mutation reports remain in the output directory.

Two real candidate mutations run after timing and must fail the complete numerical sweep without an engine error. The candidate is restored before generated-script hashes are rechecked. Report validators also reject changed workload and coverage; prepared mode checks per-case routes and disallows measured stateless setup calls.

[Measured results and decision](../../../../docs/research/propwash/E0b6p/wing-loops/README.md).
