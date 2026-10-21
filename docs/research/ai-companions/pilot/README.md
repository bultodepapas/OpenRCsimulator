# Ugly Stik Companion Pilot Qualification

2026-10-21 follow-up: [AFC-00-R3](../AFC-00-R3/README.md#runtime-promotion-2026-10-21)
promotes the verified clear-trajectory early return (`3842cbdba…1f024`). The
[AFC-02 solver bridge](../AFC-02/solver-merge-2f4f35c0/README.md) supports the
profile's `2f4f35c0…cff4bfa` solver pin for the existing Stik scope. These changes
preserve the circuit base and qualification limits; callback timing remains over
budget with companions enabled.

2026-10-21 migration update: [AFC-04-R4](../AFC-04-R4/README.md) verifies the
production wind-aware bank-candidate wrapper with its 148-check circuit matrix,
six-route moving encounters per weather and six exact crossing replays. Bounded
optional diagnostics and the local-terrain target floor are included. Its measured
trajectory differences from [R3](../AFC-04-R3/README.md) are retained explicitly.
The immutable circuit
base is still SHA `1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`;
the profile binds both sources. This entry point retains historical evidence;
it must not be read as general avoidance, endurance or performance qualification.

The preceding [AFC-04-R2](../AFC-04-R2/README.md) requalified
the narrow separated-circuit scope after bounding descending avoidance targets
above terrain recovery. Its 148-check matrix passed, with both CSVs byte-identical
to the original evidence below; 318 focused integration checks also passed.
That pilot SHA-256 was
`1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`.
Original run identities below remain historical. Its 60-second moving-encounter survey completed without a
crash, but every case still misses player separation; the two repaired crossings
had worse minimum separation. Those failed cases remain retained for comparison.

[AFC-02-R1](../AFC-02/README.md#solver-only-merge-compatibility-afc-02-r1-2026-10-20)
preserves this qualification after the Extra's opt-in solver extension, using
paired Stik replay parity and focused integration checks. The original matrix
below remains its basis and was not rerun for that source-only merge.

The preceding [AFC-04-R1](../AFC-04-R1/README.md) repaired strongest-threat
selection and passed the same matrix with byte-identical CSVs. That source
(`51ccb3cdec3a4c898277c1b30542131c9938841dbde9debc0e45bf24601db1b3`)
is the retained R2 baseline, including its two crossing-induced terrain crashes.

## Result

The pilot passed the six tested calm and gentle-practice matrix scenarios for one, two, and three companions. Every aircraft completed 28,800 physics ticks (120 simulated seconds) without a pilot refusal, crash, or simulation fault. Both additional three-aircraft calm repeats completed and produced bit-identical sampled states and commands for the same seed.

| Weather | Companions | AGL min–max (m) | TAS min–max (m/s) | Max radial error (m) | Min player distance (m) | Min fleet distance (m) | Max bank (°) | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Calm | 1 | 34.44–35.01 | 14.97–15.02 | 1.22 | 123.51 | n/a | 21.9 | Pass |
| Calm | 2 | 34.44–55.01 | 14.97–15.02 | 1.22 | 123.51 | 161.25 | 21.9 | Pass |
| Calm | 3 | 34.44–75.01 | 14.97–15.02 | 1.22 | 123.51 | 140.00 | 21.9 | Pass |
| Gentle practice | 1 | 34.31–35.01 | 14.57–15.43 | 1.64 | 122.31 | n/a | 21.3 | Pass |
| Gentle practice | 2 | 34.31–55.01 | 14.57–15.47 | 2.39 | 122.31 | 160.60 | 25.6 | Pass |
| Gentle practice | 3 | 34.31–75.00 | 14.57–15.50 | 4.05 | 122.31 | 121.74 | 26.0 | Pass |

Across the matrix, local terrain clearance ranged from 34.31 to 75.01 m, TAS from 14.57 to 15.50 m/s, maximum absolute circuit-radius error was 4.05 m against a 40 m limit, player separation stayed above 122.30 m against a 30 m limit, and companion centers stayed above 121.74 m against a 15 m limit. Normalized control magnitude peaked at 0.7854. The greatest measured aircraft bank was 25.97°; the 25° controller demand clamp is not a hard cap on the aircraft's dynamic bank response.

The exact scenario metrics and one-second aircraft samples are in [scenario_metrics.csv](scenario_metrics.csv) and [flight_samples_1hz.csv](flight_samples_1hz.csv). The checked-runner matrix report and full engine log are retained in [checks](checks/).

## Method and scope

The probe used the current `FlightSession` external-driver path with the accepted Jensen Das Ugly Stik 60 and normalized Club field. It sampled the controller at 60 Hz and held each accepted trim-relative roll, pitch, and yaw command plus absolute throttle for four 240 Hz physics ticks. The six weather/count scenarios used seed `20261020`; the two repeated calm three-aircraft runs used the same seed. The probe checked requested absolute spawn heading against tick-zero session yaw within `1e-9` rad for each spawned aircraft.

This pilot matrix loads the Club field surfaces and uses the stationary field pilot position as the player reference. It does not load the complete `CollisionSetup`/lake inventory and contains no moving encounter traffic during the long flights. A separate [three-aircraft production check](../AFC-00-06/production-120s.json) exercises the manager with the full Club collision and lake inventory for 28,800 ticks per aircraft; its checked report is [here](../AFC-00-06/checks/production-120s-report.json). That run is complementary evidence, not a substitute for or replay of this six-scenario matrix.

The matrix gates were local clearance of at least 20 m and no more than 20 m above the highest assigned altitude band; TAS 10–25 m/s; absolute circuit radial error at most 40 m; player distance at least 30 m; aircraft-center separation at least 15 m; and normalized command magnitude at most 1. These gates establish performance only for the tested scope and do not establish physical realism.

The gentle-practice condition is the project's estimated practice preset: 1.5 m/s east wind, 0.6 m/s horizontal gust, 0.15 m/s vertical gust, and N/E/D turbulence RMS 0.15/0.15/0.08 m/s with weather seed `20261011`. It is not measured site weather.

## Reproduce

From the repository root:

```powershell
python tools/godot/run_checked.py --label companions-pilot-matrix --timeout 1800 --require-text "companion pilot qualification:" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/pilot_probe.gd -- --out=../tmp/companions-pilot-matrix
```

The current probe writes both CSVs and a preliminary README into the required new
output directory; missing or existing destinations are refused. Review results
before retaining a new evidence set. These historical run identities remain tied
to the source hashes below. For a three-second heading check without output files,
replace `--out=...` with `--spot-check` and the runner's required text with
`"companion pilot heading spot-check:"`.

The output-routing follow-up passed the same 12 heading checks and refused this
existing evidence directory with the intended exit code 2, before running a matrix.
Its [receipt and raw checks](checks/output-guard/receipt.json) preserve that
expected refusal separately from the passing flight check. The full historical
matrix below was not rerun or overwritten by this tooling change.

## Controller behavior and regression record

Focused pilot tests passed 24 checks, including bounded head-on avoidance, reciprocal zero-CPA head-on avoidance with deterministic opposite world-side turns, mirrored nonzero-CPA crossing corrections, faster traffic closing from behind, self-traffic filtering, deterministic commands, and safe refusal of malformed or unsupported observations. Config tests passed 22 checks, including refusal of `--companions` and `--companions-seed` when their values are missing. The retained logs are [pilot tests](checks/pilot-controller-tests-engine.log) and [config tests](checks/pilot-config-tests-engine.log), with their checked-runner reports beside them.

The earlier `external-driver-qualification-matrix-v2` run is retained only as an integration regression finding, not pilot qualification evidence. `FlightSession` applied the pilot's requested absolute spawn yaw as a rotation offset from the already east-facing trimmed start, adding 90° and sending aircraft along the wrong headings. Its radial excursions therefore cannot be attributed to the pilot. The session seam was corrected to apply absolute yaw while preserving trim pitch and roll; the fix is covered by the session regression test and by the tick-zero heading assertions in this probe. The old [matrix report](checks/external-heading-matrix-v2-invalid-report.json) and [log](checks/external-heading-matrix-v2-invalid-engine.log) preserve the failure; the corrected [heading spot-check report](checks/external-heading-spot-check-v2-report.json) records 12 passing checks over 720 calm ticks.

## Evidence identity

The corrected checked-runner matrix completed successfully with process exit code 0, no checked-runner engine diagnostics, 148 passing checks, and elapsed time 546.031 s. Session setup printed the accepted aircraft's inertia advisory (`Jyy = 0.3692 kg·m²`, 2.02× the scaled UltraStick25e value); it caused no refusal, crash, or simulation fault. This elapsed time is a development-host measurement, not a 60 fps acceptance result.

- Capture ID: `c34bcd46-f775-4762-a80d-32d5e9c62b5d`
- Runner report SHA-256: `3c4103302b5844bea524f3a6f65b46d75e8017137f53081b5a3f65b5c4c23f36`
- Engine log SHA-256: `3de1a94d8842f37c06ec59972a88d3f394380842cbccb9cb0d984d13323f49ab`
- Pilot source SHA-256: `6450514705530245d9fe607b6f712380c0e281cc7d7d2d4833a7f32654e5eade`
- Probe source SHA-256: `3ad69bb7d1be36f038c954cf718851be3ea016d3b3c1cd0e1cf06a226e4fa00f`
- Session seam source SHA-256: `ac26a5eb61a3ee9478242dd68fe7e00f285f1b9a2dbf43f2d96c6075911d5263`
- Config source SHA-256: `2455c71f7b42b3b3e7f1b1cb6378b0534645b2ddd9281d3338e5d346a563601b`
- Pilot test SHA-256: `4ffe103f9d53925f57bf1c5dd5ce4d6315dfff047c17e3cbd0a38181f0ae9f4e`
- Config test SHA-256: `ab4136b671a2ae07af1653785fe89b902797e88d6b5118572ed471328f0e273d`

The adjacent [source receipt](../AFC-00-06/source-receipt.json) records the broader companion integration input hashes. The matrix, heading spot-check, invalid pre-fix run, and focused test runner reports and logs are retained under [checks](checks/).

This qualification does not establish 60 fps performance or physical validation. It also does not cover longer soak duration, moving encounter traffic during long flights, or the complete world collision inventory in the matrix itself. Companion cost measurements and their open performance gate are documented in [AFC-00-06](../AFC-00-06/README.md).
