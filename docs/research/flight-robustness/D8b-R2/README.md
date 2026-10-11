# D8b-R2 — High-speed Ugly Stik pull-up evidence

2026-10-11 · **Status: completed synthetic diagnosis; production correction and physical validation pending.**

The [owning plan](../../../UGLY-STIK-PULLUP-PLAN.md) contains the findings, sources, limitations and next steps. User input confirmed keyboard use; original throttle, exact entry speed and recording were unavailable.

Revision 2 adds [18 source-based investigations](research-index.md): six Godot, six aerodynamics/airframe, and six computational-simulation/validation studies. [Four additional numerical investigations](research-experiments.md) test stall-width sensitivity, strip refinement, finite-difference robustness and the wing stall-weight contribution. No replacement coefficients or production correction are adopted.

## Reproduce

From the repository root on Windows:

```powershell
python research/flight-robustness/d8b-r2/run.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe
```

The same Python driver accepts another local Godot executable via `--godot`; only the recorded Windows run was executed for this investigation. It runs the external research GDScript against `--path app`; no research script is inserted into `app/` and no production file is modified.

## Artifacts

- [results.json](results.json): 28 complete 4 s session trials and one static derivative sweep. Flight maxima are computed at every physics tick; saved state rows are spaced 0.05 s apart. Rates are rad/s unless the key says degrees. Each saved state uses `RigidBody.STATE_LAYOUT`.
- [manifest.json](manifest.json): baseline commit, engine identity, source hashes, result hash and targeted check counts. Relevant source hashes are compared before/after execution to detect concurrent changes. This is not an isolated checkout or a universal cross-platform determinism claim.
- [run.log](run.log): engine output and per-case maxima; includes the existing estimated-inertia warning.
- [spin](test_spin.gd.log), [damping](test_damping_regimes.gd.log), [gyro](test_gyro.gd.log), [handling](test_handling.gd.log): all 43 checks pass. The full app suite was not run: this delivery changes research/documentation only.
- [probe source](../../../../research/flight-robustness/d8b-r2/probe.gd) and [driver](../../../../research/flight-robustness/d8b-r2/run.py).

`baseline`, `no_gyro`, `glide` and `half_pull` use immediate pilot commands through trim and servos. `keyboard` injects raw Down-arrow-equivalent targets through the session's real keyboard sampling/shaping branch, with no physical OS events. The engine remains at its level-trim throttle; raw keyboard throttle is zero (no W/S adjustment). Starts are at 300 m in calm air.

`no_gyro` changes only the rotor-momentum callback. `glide` uses a separately solved dead-stick trim. `no_inertia_cross` zeros Jxy/Jyz in a powered diagnostic. `glide_symmetric` also clears lateral trims and initializes zero lateral velocity/rates; ±seed cases start with p = ±0.0001 rad/s. These are in-memory counterfactuals, not candidate production settings. Finite-precision residuals can grow in unstable flight, including the nominal symmetric case.

The static sweep uses 25 m/s, neutral surfaces, zero base rates, no propeller loads, instantaneous wing downwash and central differences at p = ±0.00001 rad/s. `approximate_p_growth_per_s` is dMx/dp divided by Jxx, not a full eigenanalysis. The returned envelope preserves the actual map/station parameters used.

Driver integrity checks require finite values, all 28 scenarios, expected final ticks/time, 81 ordered samples per flight, successful engine output, 43 successful existing checks and unchanged source hashes. These checks certify complete synthetic evidence; they do not accept its maneuver realism.

## Revision 2 supplemental reproduction

```powershell
python research/flight-robustness/d8b-r2/run_supplement.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe
```

Run the baseline first if `results.json` is absent. The supplemental driver preserves that baseline, runs the current Godot load/loader code, and independently reduces wing forces in Python. It checks finite results, expected case counts, a reconstructed baseline mesh, native/Python agreement, original derivative agreement and source stability. No full flight or physical keyboard is exercised by the supplement.

- [supplement.json](supplement.json): five widths, four meshes, five differencing steps and native wing-only derivatives.
- [decomposition.json](decomposition.json): wing moment derivative with active versus diagnostically frozen stall weights, with native agreement checks.
- [supplement-manifest.json](supplement-manifest.json) and [engine log](supplement.log): engine/source/output fingerprints and run output.
- [supplement.gd](../../../../research/flight-robustness/d8b-r2/supplement.gd) and [run_supplement.py](../../../../research/flight-robustness/d8b-r2/run_supplement.py): reproducible research source outside `app/`.

The 43 targeted checks above belong to the original diagnosis. The supplement adds static verification/sensitivity experiments; it does not claim another full application test run or physical validation.
