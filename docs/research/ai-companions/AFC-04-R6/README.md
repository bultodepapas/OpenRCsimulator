# AFC-04 R6: reachable-bank prediction error

This research probe compares the current reachable-bank nominal forecast with the actual fixed-step `FlightSession` path in one deterministic 20-second crossing-right encounter. It measures prediction error while the exact selected bank target remains active and unchanged. It does not establish a `path_error_m`, path feasibility, static containment, a worst-case bound, or flight qualification.

The production pilot was `3842cbdba80c7bef5041844132a811bfd27c1cb68de759ce06f39bb97ca1f024`, its unchanged circuit base was `1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`, and the companion profile pinned normalized solver source set `2f4f35c04c837e89c5317412991046cd097dd3c9f501e9697702e94a6cff4bfa` (133 sources). The ORFL runtime-derived solver identity is `8213b759c5bd746369c57cb76bfa38f21f004532bcf4d8cc9b3a1fa44fca89dd`; it is a different identity convention. The trace-only candidate is SHA-256 `6f9c6b76504a019b9e21c12209a63e6af8c609c6812983d087b7c88956a7de9e`. File hashes bind the exact working-tree sources; the clone HEAD is provenance context, not a substitute for those hashes. See the [verification receipt](verification.json) for source, field, aircraft, engine, and runner bindings.

Both 20-second runs completed 4,800 physics ticks with 1,200 planner samples and 1,186 avoidance samples. Their state-and-command fingerprints match exactly (`6897a937b4c3aa83e4840c9956d2eabc933941ca87e57c0a0f7167d35fe2392d`). The baseline and traced AI replay CSVs are byte-identical; the coupled-player replay CSVs are also byte-identical. All four ORFL streams replayed exactly with 4,801 rows, `complete=true`, and `solver_changed=false`. The raw ORFLs, flight reports, CSVs, replay reports, logs, reducer attempts, and SHA-256 index are retained on the D: evidence volume under `D:\OpenRCsimulator-AFC-work\evidence\avoidance\AFC-04-R6`.

The trace captured all 1,200 possible planner target-state events and 1,186 forecast origins: 2,386 of the 2,400 bounded combined-event slots. The 8-second forecast data was available for 721 origins; 326 retained the same target through the full 8 seconds. The actual target sequence was:

| Tick | Change | Selected bank target |
| ---: | --- | ---: |
| 0 | Initial activation | −5° |
| 3220 | Release | none |
| 3276 | Activation | +10° |
| 3856 | Target change | +5° |
| 4708 | Target change | 0° |

Residuals are sampled at exact 0.25-second offsets. Horizontal is the north/east norm; vertical is the absolute down-axis residual. The table reports sample count and empirical p95 / maximum in metres:

| Horizon | Samples | 3D p95 / max | Horizontal p95 / max | Vertical p95 / max |
| ---: | ---: | ---: | ---: | ---: |
| 0.25 s | 1130 | 0.0568 / 0.0596 | 0.0568 / 0.0596 | 0.0013 / 0.0065 |
| 1 s | 986 | 0.2395 / 0.4108 | 0.2395 / 0.4106 | 0.0089 / 0.0299 |
| 2 s | 806 | 0.6142 / 1.2467 | 0.6142 / 1.2466 | 0.0085 / 0.0513 |
| 4 s | 566 | 0.6162 / 2.0309 | 0.6161 / 2.0309 | 0.0090 / 0.0114 |
| 6 s | 446 | 1.5512 / 3.4666 | 1.5512 / 3.4666 | 0.0137 / 0.0154 |
| 8 s | 326 | 2.9845 / 5.0468 | 2.9844 / 5.0468 | 0.0173 / 0.0185 |

The observed horizontal maxima exceed the current 3 m engineering allowance at 6 s and 8 s. This contradicts treating 3 m as a hard bound for these matched forecast samples. These are overlapping measurements from one deterministic flight, not independent observations or a general bound. The down-axis residual remains much smaller in this fixture. The initial forecast-origin alignment was within `7.25e-13 m` maximum 3D residual.

The internal selected bank value is an angle target, not the aircraft's achieved bank or the normalized roll command. The reducer recomputed the production roll formula for all 1,186 forecast origins with zero mismatches and matched returned roll commands to 4,800 ORFL control samples with zero mismatches. The full 32-horizon curve, component percentiles, transition data, commands, input hashes, and all raw artifact hashes are recorded in `verification.json`.

The first trace-candidate parse attempt used an incorrect `res://` root and failed to find the research script; the successful parent-path retry and the failed report are both retained. Earlier reducer outputs remain indexed beside the validated final component reducer. The simulator also logged the aircraft-data note `Jyy = 0.3692 kg·m² is 2.02× the scaled UltraStick25e value`; no aircraft or physics parameters were changed for this probe.
