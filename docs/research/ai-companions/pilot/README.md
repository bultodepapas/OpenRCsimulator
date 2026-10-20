# Ugly Stik Companion Pilot Qualification

## Result

**Not qualified for the 40 m circuit-radius gate.** All six calm/gentle-practice flights completed 28,800 physics ticks (120 simulated seconds) for each requested fleet size, with no pilot refusals, crashes, or simulation faults. The measured maximum absolute radial error was 64.09–78.62 m, exceeding the 40 m gate in every scenario. The seeded three-aircraft calm repeat was bit-identical across all sampled state and command values; both repeated flights completed.

The controller stayed within the other measured limits: local terrain clearance was 33.93–75.01 m, true airspeed was 14.55–15.50 m/s, player separation was at least 122.48 m, fleet center separation was at least 23.62 m, and normalized input magnitude peaked at 0.662. Maximum observed bank was 26.34°; the controller's 25° bank-demand clamp is not a measured hard cap on aircraft bank.

| Weather | Companions | Ticks per aircraft | AGL min–max (m) | TAS min–max (m/s) | Max radial error (m) | Player separation min (m) | Fleet separation min (m) | Max bank (°) | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Calm | 1 | 28,800 | 33.940–35.008 | 14.943–15.034 | 72.464 | 123.504 | n/a | 26.187 | Fail: radius |
| Calm | 2 | 28,800 | 33.940–55.011 | 14.943–15.034 | 72.464 | 123.504 | 25.045 | 26.187 | Fail: radius |
| Calm | 3 | 28,800 | 33.940–75.006 | 14.943–15.034 | 72.464 | 123.504 | 23.881 | 26.187 | Fail: radius |
| Gentle practice | 1 | 28,800 | 33.934–35.009 | 14.564–15.342 | 64.094 | 122.475 | n/a | 26.342 | Fail: radius |
| Gentle practice | 2 | 28,800 | 33.934–55.010 | 14.564–15.464 | 78.617 | 122.475 | 25.038 | 26.342 | Fail: radius |
| Gentle practice | 3 | 28,800 | 33.934–75.007 | 14.547–15.497 | 78.322 | 122.475 | 23.615 | 26.342 | Fail: radius |

The exact scenario values and one-second aircraft samples are in [scenario_metrics.csv](scenario_metrics.csv) and [flight_samples_1hz.csv](flight_samples_1hz.csv). The radial-error peak is a real trajectory excursion in the sampled states, not a missing pair-distance sample; the metrics now evaluate clearance, TAS, player separation, and all fleet pairs on every accepted tick.

## Method

The checked Godot 4.7.2 run exercised the current `FlightSession` external-driver path with the Jensen Das Ugly Stik 60 and accepted Club field. The pilot was sampled at 60 Hz, and its trim-relative roll/pitch/yaw commands plus absolute throttle were held for four 240 Hz physics ticks. The six scenario runs used seed `20261020`; the two additional calm three-aircraft repeats used the same seed.

```powershell
python tools/godot/run_checked.py --out-dir .tools/companions-pilot-qualification --label external-driver-qualification-matrix-v2 --timeout 1800 --require-text "companion pilot qualification:" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/ai-companions/pilot_probe.gd
```

The measured gates were: terrain clearance at least 20 m and no more than 20 m above the highest assigned altitude band; TAS 10–25 m/s; absolute radial error at most 40 m; player distance at least 30 m; aircraft-center separation at least 15 m; normalized input magnitude at most 1. These are qualification limits used by this probe, not independent evidence of physical realism.

The gentle-practice preset is an estimated practice condition: 1.5 m/s east wind, 0.6 m/s horizontal gust, 0.15 m/s vertical gust, and N/E/D turbulence RMS 0.15/0.15/0.08 m/s with weather seed `20261011`. It is not a measurement of site weather.

Focused controller tests passed 24 checks, including bounded head-on avoidance, reciprocal zero-CPA head-on turn selection toward opposite world sides, mirrored nonzero-CPA crossings, faster traffic closing from behind, self-traffic filtering, deterministic commands, and safe refusal of malformed/unsupported observations. Config tests passed 22 checks, including rejection of missing CLI flag values.

## Evidence identity

- Checked-runner result: **complete**, engine process exit code 1 because eight radial-error checks failed (six matrix scenarios and two repeat flights); zero engine errors/warnings. The runner itself did not time out.
- Log: `.tools/companions-pilot-qualification/external-driver-qualification-matrix-v2-qrcr4fnl/engine.log`
- Runner report: `.tools/companions-pilot-qualification/external-driver-qualification-matrix-v2-qrcr4fnl/report.json`
- Capture ID: `c5262db7-ab2d-49df-97d4-d0f7efcc666d`
- Log SHA-256: `9f7164d4a094a4e1f5ad17552f362769ae60c5b166ce8d08840200ebed70008f`
- Runner-report SHA-256: `f91ce7046fe7f5a766a62df617a1c5cdf6847ccd609c70d77de4dcd53f45c69f`
- Pilot source SHA-256: `6450514705530245d9fe607b6f712380c0e281cc7d7d2d4833a7f32654e5eade`
- Config source SHA-256: `2455c71f7b42b3b3e7f1b1cb6378b0534645b2ddd9281d3338e5d346a563601b`
- Pilot tests SHA-256: `4ffe103f9d53925f57bf1c5dd5ce4d6315dfff047c17e3cbd0a38181f0ae9f4e`
- Config tests SHA-256: `ab4136b671a2ae07af1653785fe89b902797e88d6b5118572ed471328f0e273d`
- Probe source SHA-256: `49bfefb2bc5ffb47f2726c6d4fca30cf8d66b8c274059be11551e47481dc24dd`

This evidence does not establish 60 fps performance, physical validation, or performance with moving/encounter traffic during long flights. The long-flight matrix used a stationary player at the accepted field pilot position and the companion fleet only.
