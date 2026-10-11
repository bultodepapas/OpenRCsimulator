# Same-process aircraft metadata benchmark AS04-paired-metadata-20261011-r1

Status: PASS.

- App: `C:\DEVELOPMENT\OpenRCsimulator\.tools\as-integration\app`; engine `C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe` SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Driver SHA-256: `b15c100e8e993b848a9fd7a9ba71bee42dd651aeb990c0b743f094ee688680d0`; wrapper SHA-256 `6e3ee6400265aec2e66aebba84b8371847106c72165d2663d1aad597e346237a`.
- Method: one Godot process per phase; v2 session with expected-ID guard vs an on-disk `AircraftData.legacy_v1_input` clone; 120 warmup ticks and six paired 120-tick batches in ABBA repeated order; reset/input setup outside the per-step timer.
- Timing ratios are descriptive and have no pass/fail threshold. Exact non-metadata model values, initial state, warmup state, and each paired final simulation byte boundary are checked.
- Windows and WSL Godot process inventories immediately before and after each phase are retained in `runs.json`; they document residual host activity but do not measure total CPU load.
- Evidence: `C:\DEVELOPMENT\OpenRCsimulator\docs\research\aircraft-standardization\AS-04\evidence\AS04-paired-metadata-20261011-r1` (raw self-check/benchmark JSON, logs, source manifests, and summary).

Paired v2 / legacy per-tick timing ratios are descriptive. Values show the median across six paired batches and the full observed min–max range; 1.000 is equal measured time. No timing threshold is applied.

| Aircraft | p50 ratio (range) | p95 ratio (range) |
| --- | ---: | ---: |
| `jensen-das-ugly-stik-60` | 1.000 (0.975–1.011) | 1.016 (0.755–1.179) |
| `gp-extra-300s-60` | 0.994 (0.712–1.025) | 0.855 (0.691–1.066) |
| `p51d-mustang-120` | 1.202 (0.822–1.420) | 1.260 (0.766–1.656) |
| `sebart-avanti-s-a200-p100rx` | 0.999 (0.987–1.423) | 1.006 (0.859–1.301) |
| `synthetic_stik_electric_4s` | 1.005 (0.867–1.150) | 1.077 (0.896–1.455) |
| `synthetic_stik_electric_6s` | 1.002 (0.731–1.126) | 0.923 (0.634–1.266) |
| `synthetic_stik_electric_4s_battery` | 0.995 (0.944–1.008) | 0.977 (0.884–1.136) |
| `synthetic_stik_electric_6s_battery` | 0.998 (0.957–1.013) | 0.984 (0.717–1.134) |
