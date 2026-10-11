# Same-process aircraft metadata benchmark AS04-paired-p51-24-20261011-r1

Status: PASS.

- App: `C:\DEVELOPMENT\OpenRCsimulator\.tools\as-integration\app`; engine `C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe` SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Driver SHA-256: `0b48b199c2f7633e561a765de5e16753ff99e618b77d5e4a27675fc79f924cce`; wrapper SHA-256 `ab0d201a729184e9819e70c4c91c9787fba15b06ff42fe09b7eb6c929d38a07b`.
- Method: one Godot process per phase; v2 session with expected-ID guard vs an on-disk `AircraftData.legacy_v1_input` clone; 120 warmup ticks and 24 paired 120-tick batches in ABBA repeated order; reset/input setup outside the per-step timer.
- Selection: `p51d-mustang-120`.
- Timing ratios are descriptive and have no pass/fail threshold. Exact non-metadata model values, initial state, warmup state, and each paired final simulation byte boundary are checked.
- Windows and WSL Godot process inventories immediately before and after each phase are retained in `runs.json`; they document residual host activity but do not measure total CPU load.
- Evidence: `C:\DEVELOPMENT\OpenRCsimulator\docs\research\aircraft-standardization\AS-04\evidence\AS04-paired-p51-24-20261011-r1` (raw self-check/benchmark JSON, logs, source manifests, and summary).

Paired v2 / legacy per-tick timing ratios are descriptive. Values show the median across 24 paired batches and the full observed min–max range; 1.000 is equal measured time. No timing threshold is applied.

| Aircraft | p50 ratio (range) | p95 ratio (range) |
| --- | ---: | ---: |
| `p51d-mustang-120` | 0.986 (0.754–1.134) | 0.972 (0.690–1.369) |
