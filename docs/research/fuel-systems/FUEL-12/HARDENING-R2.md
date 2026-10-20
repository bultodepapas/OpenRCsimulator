# FUEL-12-R2 fuel hardening

Checked 2026-10-19 with native Godot 4.7.2 on Windows. This round repairs defects in the completed finite glow/gasoline/turbine implementation. The [engineering standard](../../../FUEL-SYSTEM.md) remains authoritative; the [qualification plan](../../../plans/fuel-mass-balance.md) retains physical and release gates.

## Repairs

| Reproduced defect | Accepted behavior and regression |
| --- | --- |
| The multi-surface event step treated small positive values as zero. A positive endpoint caused an unbracketed-root fault; a tiny positive start could cross below zero without an exhaustion event. Multiplying subnormal endpoints could also invent a crossing. | Crossing detection uses strict signs; residual tolerance applies after bracketing. Generic tests cover falling, rising, either-direction and subnormal cases. With `5e-11 kg` usable fuel, all five aircraft locate exhaustion, retain residue and repeat the boundary exactly. The three glow cases previously failed. |
| A stopped glow checkpoint could remove the main tank's unusable residue. | Accepted states reject missing residue in every source mode. A separate line permits only a narrow float64 subtraction allowance. Native and JSON restoration reject the malformed snapshots without changing the destination; all three current glow aircraft are covered. RK trial continuation remains separate from accepted-state validation. |
| A legacy checkpoint with unknown launch-fill provenance acquired a false preference when restored, saved and restored again. | Unknown provenance remains unknown; each receiving session retains its own selected launch fill while restoring the exact physical state. Native/JSON chains, reset behavior and malformed unknown metadata are covered for glow, gasoline and turbine. |
| Malformed samples/adapters could coerce boolean quantities, produce engine type errors, bind unknown store IDs or emit nonfinite derived volume. | Sample headers, store fields, reserve flags, prepared inventory shape/IDs and flow coefficients receive explicit checks. Derived and aggregate arithmetic must stay finite. Reordered valid resources remain bound by their prepared IDs. Existing negative-tick refusal is preserved. |
| The HUD test exited while AudioServer still retained its warning playback, producing resource-leak errors despite passing its assertions. | The fixture observes a playback weak reference after overlay removal, waits at most 500 ms and asserts release. The same failure reproduced on the immutable baseline; production audio is unchanged. The corrected test passes without engine errors. |

The glow derivative now reuses the coupling already computed by the same-stage feed-pressure solve. The public observer result is unchanged. A [16-sample stage comparison](../../../../research/fuel-systems/FUEL-12/hardening-20261019-r2/probes/stage-compare.log) covers complete point dictionaries, loads, derivatives, rotor momentum and datum acceleration: both sides produce 165136 identical bytes, SHA-256 `b20417ec…16378`. Query order remains immaterial. No law/layout version or calibration data changed.

## Verification

The [final native result](../../../../research/fuel-systems/FUEL-12/hardening-20261019-r2/checks/native-results.json) covers **49 scripts, zero outstanding failures**. It retains the initial HUD teardown failure and points to its corrected verbose rerun. Checks reject nonzero exits and engine/script/shader errors; warnings from experimental data remain visible. Selected coverage includes 54 generic event checks, 46 real fuel-boundary checks, 38 sample checks, 34 liquid-adapter checks, 67 launch-fill checks, 48 liquid-session checks, 110 glow stage/feed checks, 140 glow-session checks, 2005 stage-reuse comparisons, 3247 flight-log checks, 372 trace-metadata checks, contacts, checkpoint integrity, Workshop, crashes and the four-flight landing/refinement test. This is a focused suite, not the entire repository suite.

The [compile result](../../../../research/fuel-systems/FUEL-12/hardening-20261019-r2/checks/compile.json) loaded **1054 GDScript resources with zero failures**. The subsequently corrected HUD fixture was parsed and run separately. Physics/sim/failure sources and the 49 tested scripts have [recorded hashes](../../../../research/fuel-systems/FUEL-12/hardening-20261019-r2/checks/source-manifest.json). The candidate snapshot includes sibling `assets/` and `tools/` dependencies.

Baseline exact replay was verified before changes. The [same-law comparison](../../../../research/fuel-systems/FUEL-12/hardening-20261019-r2/flights/verification.json) then reused all ten retained full/10% tapes: MAX-61FX, FS-64V, Extra, P-51 and Ventage. Each complete 600-tick candidate agrees byte-for-byte with all **601 recorded numeric physics/air/mass samples**, then exact-replays its own new recording. All ten new ORFLs, CSVs and production export reports are retained together; exports confirm complete logs and 601 rows each.

`solver_changed=true`: baseline `db4aba33…105a8`, candidate `e3eb9fa0…f9c6b`. This establishes preservation on those normal tapes. The new boundary regressions deliberately change defective behavior outside their sampled domain; neither replay agreement nor synthetic conservation establishes physical realism.

## Cost

An earlier, less-contended paired MAX-61FX probe with one warm-up and five 600-tick repeats measured **2.755 → 2.747 ms/tick at full fill** and **2.762 → 2.769 ms/tick at 10%**. Those differences do not establish a meaningful whole-tick speedup. A more contended initial run is retained separately and is not used to claim a gain.

The [final-source three-family sweep](../../../../research/fuel-systems/FUEL-12/hardening-20261019-r2/performance/summary.json) uses the same warm-up/repeat protocol. Medians are milliseconds per tick:

| Aircraft/family | Full baseline | Full candidate | 10% baseline | 10% candidate |
| --- | ---: | ---: | ---: | ---: |
| MAX-61FX glow | 3.812 | 2.954 | 3.793 | 3.815 |
| P-51 gasoline | 2.126 | 1.909 | 1.894 | 2.393 |
| Ventage turbine | 1.191 | 1.255 | 1.193 | 1.581 |

A separate scenery-build audit ran on the shared host during that sweep. The mixed changes cannot establish an isolated causal speedup or release headroom. Liquid adapters also repeat the new inventory validation during RK stages; profile that cost on an isolated host before closing the performance gate. Simulation timing excludes import, trim/setup, restoration and recording; it measures batch averages, not individual-tick tails. Target hardware/GPU qualification remains open.

## Reproduce

Use the engine and checks in [TOOLS](../../../TOOLS.md). Run each named native script with `--headless --path app --audio-driver Dummy --script res://tests/<name>.gd`. The durable experiment drivers are:

```text
research/fuel-systems/verify_hardening.gd -- --source-dir=<absolute baseline ORFL directory> --out=<new absolute directory>
research/fuel-systems/compare_stage_bytes.gd
research/fuel-systems/benchmark_completion.gd -- --aircraft=res://data/aircraft/<name>.json --out=<new absolute JSON path>
```

Pass research scripts as absolute `--script` paths and run them separately against the source snapshots being compared. Exact replay requires matching recorded source/data bytes. Preserve the baseline; candidate experiments use the recorded initial state and input tape with explicit source changes. The existing Word standard still describes the same contracts, so this round adds dated evidence without generating a duplicate standard.
