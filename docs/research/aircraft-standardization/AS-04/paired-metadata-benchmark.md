# AS-04: Same-process aircraft metadata benchmark

2026-10-11 · Prefix: AS-

**Status: Measured. Physics and lifecycle equivalence passed; timing evidence is descriptive and inconclusive for a 5% performance target.**

The benchmark compared each current v2 `FlightSession` against a second session loaded from an on-disk `AircraftData.legacy_v1_input` conversion of the same v2 JSON. Both sessions used the same Godot process, code, platform, manual input schedule and physics values. The v2 session used the selected-aircraft identity guard; the explicit legacy clone used the historical v1 loader route. Only root metadata (`capabilities`, `convention_id`, and `data_sha256`) was excluded from model equality checks.

For each of the four catalog aircraft and four electric fixtures, the driver verified exact non-metadata model equality, the v2 identity guard, exact initial and 120-tick warmup simulation bytes, six 120-tick paired batches, exact simulation bytes after each pair, and reset to the original state. It alternated the per-pair order as `v2, legacy`, then `legacy, v2`, repeated three times. Reset and manual-input preparation were outside the per-`Simulation.step()` timers. Every batch retains all 120 tick samples, p50 and p95 values, its order and its final byte boundary. The Python wrapper also checked all eight case results, sample counts, engine return codes, error output and source-manifest stability.

All eight cases passed those model/state checks. The self-check and benchmark engine processes exited 0 with no engine errors. The app source manifest was identical before and after both phases: `643aa1a0b8d934dff6bbd9f339c62c4529482b0122123a731c60c66ec8a4970e`.

The following values are the median across six paired ratios of v2 / legacy per-tick timing; parentheses show the full observed min–max range. Ratios near 1.0 mean equal measured time. These observations have no pass/fail timing threshold.

| Aircraft | p50 ratio (range) | p95 ratio (range) |
| --- | ---: | ---: |
| Ugly Stik | 1.000 (0.975–1.011) | 1.016 (0.755–1.179) |
| Extra 300S | 0.994 (0.712–1.025) | 0.855 (0.691–1.066) |
| P-51D Mustang | 1.202 (0.822–1.420) | 1.260 (0.766–1.656) |
| Avanti S | 0.999 (0.987–1.423) | 1.006 (0.859–1.301) |
| Electric 4S | 1.005 (0.867–1.150) | 1.077 (0.896–1.455) |
| Electric 6S | 1.002 (0.731–1.126) | 0.923 (0.634–1.266) |
| Electric 4S battery | 0.995 (0.944–1.008) | 0.977 (0.884–1.136) |
| Electric 6S battery | 0.998 (0.957–1.013) | 0.984 (0.717–1.134) |

The P-51 p50 ratio is 1.20, but its six-pair range is 0.82–1.42, and its p95 range is 0.77–1.66. The other aircraft have p50 medians close to 1.0, with wider p95 or occasional batch spreads. The captured host context shows that the full WSL Godot suite continued during the benchmark, and native Windows Godot processes also remained open. ABBA ordering reduces process-order bias but cannot remove this concurrent host variability. The P-51 result is therefore a signal to repeat under quieter conditions, not evidence that v2 adds a 20% tick cost or that the 5% target has been met. The P-51-only follow-up below provides that longer repeat, with its own remaining spread reported explicitly.

## P-51-only 24-pair repeat

After the full suite stopped at its first failure and other owned engine runs finished, the driver ran `--only p51d-mustang-120 --pairs 24`. It repeated the self-check, then measured 24 paired 120-tick batches in the same ABBA order. All 24 final simulation byte comparisons passed; normalized models, identity guards, warmup and reset boundaries matched. Both engine processes exited 0 without errors, and the integration app manifest stayed at `643aa1a0b8d934dff6bbd9f339c62c4529482b0122123a731c60c66ec8a4970e`.

The P-51 p50 ratio median was 0.986, range 0.754–1.134; the p95 ratio median was 0.972, range 0.690–1.369. This does not reproduce the initial +20% median as a stable slowdown. The 24-pair spread still exceeds 5% by a wide margin, so this run also cannot claim the ≤5% target is met. The WSL process inventory was empty immediately before and after these phases, while two native Windows Godot processes remained open; inventories do not capture total CPU load.

A source search found no per-tick reads of `capabilities` or `convention_id`: they are checked by the contract loader and otherwise carried as metadata or used in tests. `data_sha256` is read by `FlightSession.trace_meta()` for trace-header metadata. The benchmark gives no evidence for changing tick code, so no optimization was made.

Evidence: [all-aircraft six-pair README and ratio table](evidence/AS04-paired-metadata-20261011-r1/README.md), [P-51 24-pair README and ratio table](evidence/AS04-paired-p51-24-20261011-r1/README.md), [all-aircraft summary](evidence/AS04-paired-metadata-20261011-r1/summary.json), [P-51 raw reports, process inventories and manifests](evidence/AS04-paired-p51-24-20261011-r1/runs.json), [benchmark log](evidence/AS04-paired-p51-24-20261011-r1/benchmark.log), [self-check log](evidence/AS04-paired-p51-24-20261011-r1/self_check.log). Drivers: [GDScript probe](../../../../research/aircraft-standardization/paired_metadata_bench.gd), [Python runner](../../../../research/aircraft-standardization/paired_metadata_bench.py).
