# D8b-R2b flight matrix

Research telemetry for the Ugly Stik pull-up comparison. These runs check simulator response and trace completeness; they do not establish physical validation.

The 240 Hz matrix has 17 cases: positive progressive and abrupt pulls from 15, 25, and 30 m/s; negative progressive and abrupt pulls from 25 m/s; positive 25 m/s progressive and abrupt pulls at idle, trim, and full throttle; paired `p = ±0.0001 rad/s` starts for both pull styles; and a 15 m/s full-power acceleration to 25 m/s followed by a progressive pull without retrimming.

Each case runs through `FlightSession._physics_process`, its production command slew limiter, trim/clamp path, and `Simulation.step`. The research harness supplies scheduled raw targets through `FlightSession.read_raw`; this does not measure OS keyboard or radio latency. Every full trace has the initial row and one row per physics tick. Rows contain raw, shaped, trimmed, and servo inputs; airspeed, alpha, beta, rates, load factors, full state; aerodynamic, propeller, and total forces/moments; rotor momentum and gyro acceleration deltas; and per-strip wing telemetry. State and load timestamps refer to the same committed tick boundary; loads are recomputed at that boundary, not copied from an RK4 intermediate stage. The strip rows describe the local wing before blending and exclude tail, propulsion, and gyro loads.

`run_matrix.py` stores retained traces as lossless gzip CSV files and records generated-trace hashes, byte counts, sample completeness, and finite checks in `trace_inventory.json`. By default it retains all full traces. `--trace-case CASE_ID` may be repeated or comma-separated to retain only selected full traces; other cases still run and keep their peak metrics, final state, completeness, and generated trace hash. This keeps routine three-model comparisons compact while preserving the complete per-tick runner for later use.

Example candidate run:

```powershell
python research/flight-robustness/d8b-r2/run_matrix.py `
  --label steep `
  --aircraft-file research/flight-robustness/d8b-r2/candidates/steep.json `
  --output docs/research/flight-robustness/D8b-R2/implementation/matrix/steep `
  --compare docs/research/flight-robustness/D8b-R2/implementation/matrix/baseline-final `
  --trace-case v25_abrupt_positive_trim `
  --trace-case v15_trim_accelerate_25_preserve_trim
```

The comparison reports per-case peak-metric deltas. `physics_dependency_hash_sha256` fingerprints the app simulation, input, physics, aircraft, data, specification, and project files; the full source-tree and measurement-tool hashes remain recorded separately. Optional `--common-time-case CASE_ID` adds row-aligned numeric and wing-strip deltas when both `--compare` runs retain that case. It reports matched-time differences and does not estimate RK4 order.

## Captured comparison

The baseline and three candidate matrices each completed all 17 cases with finite telemetry. For `v25_abrupt_positive_trim`, the three candidates have identical peak summaries: maximum body alpha 13.6412° and maximum normal load 5.9086. The largest local effective wing-strip alpha is 10.6025° (largest local geometric alpha is 13.7751°). The candidate tables share their knots through 14° and first differ at the 25° lift value, which changes the PCHIP segment between 14° and 25°; this trace stays below that segment. The identical result therefore samples the shared curve and is not three independent confirmations of the post-peak alternatives. The candidate tables identify themselves as synthetic sensitivity fixtures, not Jensen measurements or calibrated flight data.

The intermediate candidate was also run for this case at 480 and 960 Hz. Each trace had 1,201 timestamps in common with its 240 Hz run, and all three rates passed the finite checks. On the common 240 Hz grid, maximum airspeed differences from the 240 Hz trace were 0.0109 m/s at 480 Hz and 0.0163 m/s at 960 Hz; maximum alpha differences were 0.000840 rad and 0.001263 rad. These are observed run-to-run differences, not convergence-order estimates.

The matrices keep their exact source fingerprints from execution time. `post_capture_provenance.json` records the later app-tree fingerprint after the CLI route and FlightSession telemetry metadata/test changes, along with the physics-code and legacy-equation fingerprints. The legacy equation hash matches across baseline, candidate runs, and the post-capture tree; the full physics-code hash matches the candidate runs after their capture.
