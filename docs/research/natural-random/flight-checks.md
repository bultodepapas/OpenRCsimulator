# Natural Random flight qualification (NR-03)

Date: 2026-10-13. Scope: deterministic generated aircraft/weather selection, production-session setup, fixed-step numerical flight, and replay. This is software evidence, not physical validation or release acceptance.

## Executed matrix

Engine: Godot `4.7.2.stable.official.ed1daf0bf`, headless with the Dummy audio driver.

Command:

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --headless --path app --audio-driver Dummy --script res://tests/test_natural_random_flight.gd
```

Result: exit code 0; `NR-03 numerical flight qualification: 576 checks, 0 failed`.

The check searched seeds below 65,536 and found all 20 aircraft/recipe cells. Each row configured and reset a production `FlightSession`, then checked a finite trace at the 240 Hz solver rate. Nineteen rows advanced 240 ticks (1 second). The P-51D windy row advanced 1,200 ticks (5 seconds), reset to the same accepted launch, and reproduced the fixed-input solver trace byte for byte.

| Aircraft | calm_air | gentle_breeze | lively_afternoon | windy_day |
| --- | ---: | ---: | ---: | ---: |
| jensen-das-ugly-stik-60 | 35 | 3 | 71 | 54 |
| gp-extra-300s-60 | 16 | 10 | 1 | 0 |
| p51d-mustang-120 | 9 | 6 | 13 | 5 |
| sebart-avanti-s-a200-p100rx | 80 | 11 | 26 | 55 |
| turbo-lumber-evolution | 7 | 4 | 20 | 105 |

The diagnostic snapshot reproduced the same matrix result; its [full output](flight-matrix.log) is retained with this report.

## Full-gust-period check

The opt-in command is:

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --headless --path app --audio-driver Dummy --script res://tests/test_natural_random_flight.gd -- --gust-period
```

An earlier current-working-tree attempt did not reach integration: `app/sim/flight_session.gd` referenced failure modules that had not yet been created by the concurrent integration. That failed attempt is not passing evidence.

The isolated diagnostic application built from commit `7562dba6` with the Natural Random app overlays and matching authoring sources from its aircraft model manifests passed this check. The snapshot was imported before running the test; [`snapshot.py`](../../../research/natural-random/snapshot.py) recreates it. The result is scoped to that snapshot and is not current-working-tree acceptance.

Command:

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --headless --path .tools/natural-random/snapshot/app --audio-driver Dummy --log-file C:/DEVELOPMENT/OpenRCsimulator/.tools/natural-random/snapshot-checks/gust-period-engine.log --script res://tests/test_natural_random_flight.gd -- --gust-period
```

Result: exit code 0; `NR-03 numerical flight qualification: 60 checks, 0 failed`. The P-51D Mustang windy-day case used seed 5 and advanced 7,428 fixed ticks (30.950 simulated seconds), covering the gust delay plus one complete gust period. The trace remained finite, and the check confirmed integration through the full period. [Full output](gust-period.log).

After the concurrent integrations became parseable, the same full-period check completed against the current `app/`: **60 checks, zero failures**, 7,428 ticks / 30.950 simulated seconds, no engine/script error or warning markers. [Current-tree output](current-gust.log). The GUI-subsystem executable returned control to PowerShell before completion; this result was accepted only after its process exited and the engine log contained the final summary.

## Limits

These checks establish software-level determinism, session acceptance, finite state/load/wind values, fixed-step progress, and exact replay for the tested inputs. They do not establish physical fidelity, pilot workload or readability, hardware input acceptance, realistic gust response, long-duration robustness, or platform release readiness. No wall-clock performance claim is made.
