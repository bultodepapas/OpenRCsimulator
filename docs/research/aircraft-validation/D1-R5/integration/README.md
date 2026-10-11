# D1-R5 — Runtime integration

2026-10-09 · **Status: integrated and verified; physical lift/damping validation remains open.** Owning step: [ROADMAP D1-R5](../../../../../ROADMAP.md). Earlier [prototype evidence](../README.md) is retained.

## Change

At `d61d268`, the application loader still matched the recorded pre-repair hash, and the previously documented 115-check test source was absent. The saved [patch](../change.patch) is now applied to [aircraft_data.gd](../../../../../app/physics/aircraft_data.gd). Its resulting SHA-256 remains `95f8886a4a6d309ad5f749acc7ef98e4cf21b62615703c606dc94c8f68571348`.

The loader refuses a nonpositive/nonfinite wing-lift target, a nonfinite final map, an unsatisfied slope residual, or nonfinite lift offsets before publishing a model. The residual tolerance remains `1e-10 × max(1, |target|)` /rad. It is a numerical acceptance limit, not an aerodynamic uncertainty band. Valid solve arithmetic is unchanged; no per-tick code, aircraft input, force law, UI or golden fixture changes.

The newly reconstructed [app regression](../../../../../app/tests/test_induced_integrity.gd) runs automatically in `app/test.sh`. The verification tool also requires four completed 24-pair comparisons and four explicit refusals per map fault. Its negative control must actually load the deliberately wrong all-ones map; an unrelated refusal cannot count as the intended defect escaping.

## Proof

- [Focused run](focused.log): **168 checks pass**. Covers four valid models, both supported section-slope bounds on every model, lift/twist offsets, invalid targets and offsets, initial refusal, preservation of aircraft/start/trim, simulation checkpoint and pause state after a refused reload, and subsequent flight continuation. Boundary targets are constructed from the fixed geometry; the independent Weissinger oracle remains in `test_strip_induced.gd`.
- [Baseline reproduction](reproduction.log), in a disposable clone of `d61d268` with the same new regression: **168 checks, 86 failures**, no engine errors. Of these, 42 expose unsafe acceptance/publication or the missing calibration diagnostic; 44 require the new boolean solve contract that the old void-returning helper lacked. [Source identity](reproduction-source.json) binds this run to the retained baseline and current test.
- [Loader comparison and faults](verification.json): **96 complete fleet load results remain byte identical**, including diagnostics and input identity; **12/12 NaN, infinity and zero-map faults refuse empty models**. [Residual negative control](missing_residual.log) loads four incorrect finite maps when only residual acceptance is removed. Faults stay in private loader copies.
- [Unchanged baseline suite](baseline-app.log) and [integrated suite](app.log): `app/test.sh` exits 0 before and after integration, with 125 → 126 GDScript test programs. Goldens, four trimmed-aircraft traces, keyboard/radio/UI tests, contact checks and 30/60/144 FPS equality pass. All six reported wash/swirl FPS fingerprints match the baseline. [Manifest](manifest.json) records source/evidence hashes and completed results.
- [Focused debugger](focused-diagnostics.json): zero engine/parse errors and zero warnings in the new test. Its 16 dependency warnings match the [baseline debugger](reproduction-diagnostics.json). Static lint retains the same 12 existing warnings and zero errors; this is not a warning-free project.
- [Resource validation](validation.json): zero errors, configuration warnings or physics-layer findings; all scanned resources load. The sweep includes local, ignored capture copies and reports 430 warnings. [Three-scene smoke](scenes.json) with input fuzzing passes with zero errors/findings and 285 warnings. These broad diagnostic counts are not clean-clone or target-GPU acceptance.

Read-only Luna Max review found no blocking defect. Generic matrix-inverse hardening remains outside this repair; the existing independent strip tests still verify the map mathematics.

## Reproduce

From the repository root, with Python 3 and the pinned Godot:

```sh
app/test.sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_induced_integrity.gd
patch --reverse --output /tmp/d1-r5-baseline.gd app/physics/aircraft_data.gd \
  < docs/research/aircraft-validation/D1-R5/change.patch
python3 research/aircraft-data/d1-r5/verify.py \
  --baseline /tmp/d1-r5-baseline.gd --output /tmp/d1-r5-integration-proof
```

The output directory must be new. No external data, package or engine upgrade is required. These checks establish loader integrity and software preservation on Linux; physical lift, damping, pilot handling and the open flight gates remain unvalidated.
