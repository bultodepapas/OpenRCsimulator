# M5-W01a — calm parity and wind cost snapshot

**Status (2026-10-09):** Measurement evidence only. Calm trajectories are exactly preserved; wind gates and pilot acceptance remain open.

The frozen source was commit `6973e42159eaf21574c17f44f64e536b2e0304eb`. A detached overlay added only the stable wind, session, ground-start, and trace files. Its SHA-256 manifest identifies snapshot `810075d0893bd231803341bd886856061b5098c467499fd287243a18fd6b77b8`; the four aircraft data files and `bench_wind.gd` match the baseline byte for byte.

The same harness measured five warmed 240-tick batches for trim, stall, and ground fixtures on all four catalog aircraft. It captured full state, auxiliary, continuous, mode, input, and load snapshots at ticks 0, 240, and 480. The core calm overlay matches every baseline value and hash exactly. Steady wind samples `(0, 3, 0) m/s` NED. The gust run used the benchmark-only `gust_delay_s=0` override; its 4 s pulse reaches `(0, 6, -1.5) m/s` NED at 2 s. All weather runs completed 480 ticks without numerical faults.

The largest observed core median is the P-51 stall fixture under gusts: 530.08 µs/tick, versus 491.51 in core calm and 504.59 in steady wind. The deltas across all aircraft and fixtures have mixed signs, and a long UI test shared the host during measurement. The result does not isolate a wind cost or establish the target-machine budget. No independent aerodynamic or pilot validation was performed.

The frozen-clone `app/test.sh` completed with exit code 0, including the all-script parse and four golden-flight replays.

Detailed method, all fixture medians, sample distributions, and interpretation: [wind benchmark report](../../../../research/wind/M5-W01a/README.md).

- [Baseline measurements](../../../../research/wind/M5-W01a/baseline.json)
- [Core calm measurements](../../../../research/wind/M5-W01a/core-calm.json)
- [Core steady measurements](../../../../research/wind/M5-W01a/core-steady.json)
- [Core gust measurements](../../../../research/wind/M5-W01a/core-gusty.json)
- [Source SHA manifest](../../../../research/wind/M5-W01a/core-source-manifest.json)
- [Comparison output and checker](../../../../research/wind/M5-W01a/core-comparison.txt) · [compare_core.py](../../../../research/wind/M5-W01a/compare_core.py)
- [Benchmark runner](../../../../app/tests/bench_wind.gd)
- [Frozen full-suite log](../../../../research/wind/M5-W01a/app-test.log)
