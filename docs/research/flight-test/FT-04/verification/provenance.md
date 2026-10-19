# FT-04 provenance

Every FT-04 result was flown against one frozen copy of `app/` (`cp -r app`), taken at 2026-10-19 02:05 UTC. Other tracks committed several times while the card was written. Each run used its own frozen copy of `research/flight-test/`.

## Snapshot of `app/`

| Item | Value |
| --- | --- |
| Commit | `97136354`. Under `app/` it had no modified tracked files; untracked were `app/physics/battery/` and two `.uid` files (later committed by their track) |
| Tree hash | `46ad103b1ec3768cab872d8d81a6a22d65e81a188b33d4f8c16fc9a67235937b` (SHA-256 of the sorted per-file SHA-256 list, `.godot/` excluded) |
| Engine | Godot 4.7.2 official (`4.7.2.stable.official.ed1daf0bf`), Linux headless, 240 Hz, calm standard air |

## Cards

| Card | Source | Files |
| --- | --- | --- |
| `ft-card-v3` | `research/flight-test/` at `d055b780` | `flight_test.gd` `08d19f25…`, `pilot.gd` `9ffd5fc5…` |
| `ft-card-v4` | identical to `research/flight-test/` at `76d1c15e` (byte-compared) | `card_aerobatics.gd` `5100ad59…`, `card_field.gd` `e5daa515…`, `card_power.gd` `ad593eca…`, `card_stalls.gd` `6602a1eb…`, `flight_test.gd` `f368b7ea…`, `pilot.gd` `5636813f…`, `run.py` `eb8ea61b…`, `compare.py` `63e9ce0a…`, `summarize.py` `965db771…` |

## Runs

| Run | Card | Aircraft, jobs | Result |
| --- | --- | --- | --- |
| v3 on the snapshot | v3 | all 8, 3 jobs, with other work on the VM | Exit 1. The FS-64V hit the old 1800 s default timeout about 1 s after it wrote its complete 21-test profile, so the comparison uses that profile. `run.py` now defaults to 3600 s |
| **v4 final** (this folder) | v4 | all 8, 4 jobs, timeout 14400 s | Exit 0, no script errors, 51 min wall time; 557–1092 s per aircraft, glow Stiks 2005–2263 s |
| v4 repeat | v4 | Stik and Ventage Jet, 2 jobs, alongside the final run | Exit 0; [identical](determinism.md) |

Earlier v4 runs used card versions before the last three pilot repairs, so they are not evidence. The repairs were:
- `stall_turning` failed when a glow Stik never broke;
- the snap recovery's opposite rudder, keyed to the sign of the roll rate, held the Ventage Jet in a Dutch-roll limit cycle;
- 45 s stall flights were too short for a glow engine at idle.

The CSV traces are not kept; `run.py` regenerates them. In `run.json`, the `run.log` files and these reports, the session scratch path is replaced by `<scratch>/`. `run.json` shows an empty commit because each runner ran from its frozen copy outside the repository; the commits above replace it.
