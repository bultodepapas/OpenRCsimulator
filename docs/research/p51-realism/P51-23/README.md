# P51-23: CI freshness checks and fresh-clone Linux verification

2026-10-15 · Revision 1 · **Status: implemented and run; the full suite is not green, and every failure is attributed below.** Prefix: P51-23. [Plan](../../../P51-PLAN.md)

## Change

- **`app/test.sh` now checks the P-51 generators.** It runs `research/p51/p51-20/ground_effect_vlm.py --check` and `research/p51/p51-05/derive_physics.py --check`, as it already did for the Avanti and Timber generators. Until now, nothing in CI caught P-51 data that had gone stale relative to its generator.
- **The VLM `--check` compares numerically.** Keys, strings and structure must match exactly; numbers may differ by 1e-9 relative. The table is written at full precision, and platform `libm` (`sin`, `cos`, `atan2`) may differ by an ulp, so a byte comparison could fail on Linux without any physical change. A negative control rejects a 1e-6 change and accepts 1e-12.
- **The generated JSON needs no extra rule.** `.gitattributes` already forces CRLF for `app/data/aircraft/*.json`, and the report comparison reads text with universal newlines.

## Linux run

A fresh LF clone (`git -c core.autocrlf=false clone --no-hardlinks`) of `ed1720a8`, which includes P51-19…21, with only the two files above overlaid ([identity](linux-suite/identity.txt)). `research/p51/p51-15/run_suite.py` ran `app/test.sh` under WSL2 Ubuntu (Linux 6.18) with the pinned Godot 4.7.2 Linux binary and isolated user-data directories. It continues past failures and records each component ([results](linux-suite/results.json)).

**477 recorded steps, 464 pass.** The uninterrupted attempt stops at `test_atmosphere_column_session` ([first failure](linux-suite/000-first-failure.txt)); continuation covers the rest. This is not a green `app/test.sh`.

| Step | Result | Attribution |
| --- | --- | --- |
| New P-51 freshness group ([log](linux-suite/449.log)) | pass | This change, cross-platform. |
| P-51 model contract, clearances, finish ([448](linux-suite/448.log), [450](linux-suite/450.log), [451](linux-suite/451.log)) | pass | — |
| `test_runway_start`, `test_prop_strike` | pass | P51-21 qualification holds on Linux. |
| `test_p51_envelope` 83 m stall recovery, `test_p51_ground` lift-off at 25.2 m/s, `test_p51_handling` loop 343° ([252](linux-suite/252.log), [253](linux-suite/253.log), [254](linux-suite/254.log)) | fail | The known open items, with values identical to native Windows. Stall recovery is P51-19; lift-off and loop are P51-22. |
| `test_atmosphere_column_session`: three column-preference checks | fail | VAL-AUD R09 preferences; no P-51 path. |
| `test_golden`, H7 golden signatures ([144](linux-suite/144.log), [444](linux-suite/444.log)) | fail | Ugly Stik goldens replay with small deviations. The physics-audit track holds updated goldens uncommitted in the shared tree. |
| C7-R1 trace acceptance, G2a/G2b shaft CLI, headless catalog trace ([455](linux-suite/455.log), [463](linux-suite/463.log), [464](linux-suite/464.log)) | fail | `check_trimmed_flight.py` still accepts only `local-surfaces-v1` while the session now writes the R02 law name `section-plane-source-weighted-wake-velocity-v2`. The integration gap is in R02 and affects every aircraft's trace. |
| D8b-R2 ([456](linux-suite/456.log)) | fail | Stale synthetic polar candidate `research/flight-robustness/d8b-r2/candidates/steep.json` (Stik-derived). |
| `test_replay_policy` ([301](linux-suite/301.log)) | fail | "legacy v1 remains readable"; replay format, no P-51 path. |
| `test_rudder_authority` ([309](linux-suite/309.log)) | fail | Its session uses the default aircraft (Ugly Stik): yaw rate 15.1°/s against the 15°/s screen. |
| `test_landing_maneuver` ([213](linux-suite/213.log)) | timeout | Stik landing; every printed check passes until the 90 s per-script limit during its 480 Hz cases under WSL. |

The overlay touches only `app/test.sh` and the VLM checker, so none of the non-P-51 results can depend on it.

## Limits

This is one Linux run and one native Windows run on one host. It is not a release gate or a target-hardware performance measurement. The non-P-51 failures belong to their owners and were neither changed nor tolerated here.
