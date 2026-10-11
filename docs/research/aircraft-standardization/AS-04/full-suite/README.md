# AS-04: Complete regression coverage

**Status: Passed after documented fixes and reruns, 2026-10-11.** All 195 GDScript tests and all 27 official integration sections are resolved. Prefix: AS-. [Machine-readable final summary](final-summary.json).

## Snapshot and method

A fresh local Git clone at `d486ec2d5d535cff9744e186f2e6a086b565dc0c` received an exact overlay of 6,542 tracked/nonignored working-tree files, preserving the concurrent state under review. No `.godot` cache was copied. [The source manifest](fresh-clone-manifest.json) records those hashes. The isolated Linux checkout normalized Windows CRLF text to LF; this fixed the [initial canonical grass-data failure](initial-windows-line-endings.log), without changing live source or generated values.

Pinned Linux Godot `4.7.2.stable.official.ed1daf0bf` ran `bash app/test.sh` under WSL Ubuntu. The [official log](app-test.log) records successful imports, source/generator checks, float64/transcendental/shader guards, the parse check of every app GDScript, and 32 completed GDScript tests. The next test rejected all five malformed battery cases correctly, but its assertions expected v1 diagnostic wording. The assertions were corrected to v2 field paths while keeping the authored v2 fixtures; [all 67 native checks passed](../focused-final/test_electric_battery_data.log).

The remaining tests ran from an ext4 mirror of that fresh-copy source to avoid repeated NTFS startup overhead. A [fresh resource import](ext4-import.log) passed. [Six late AS files](continuation-overlay.json) supplied the final contract/schema refusals, battery diagnostic assertions and offline propeller-audit compatibility; application physics and concurrent GP files stayed at the frozen snapshot. The [continuation harness](../../../../../research/aircraft-standardization/continue_regressions.py) ran all 163 remaining GDScript tests, followed by the 27 exact integration sections extracted from the official `app/test.sh`. It leaves tests unchanged, captures each exit/log, treats engine errors as failures even with exit zero, and does not stop at the first failure. Each test has a time limit. User data is isolated from the developer's normal app settings.

This is an official run plus an equivalent continuation, not a claim that one uninterrupted `app/test.sh` invocation exited zero. The source manifest and per-section logs identify exactly what was tested. Live GP attachment and authored model hinges were also checked separately in the [final focused evidence](../focused-final/README.md).

## Failure disposition

| Attempt | Finding | Resolution |
| --- | --- | --- |
| Initial Linux clone preflight | Windows checkout CRLF changed canonical generated grass bytes | Normalize text only in the isolated Linux copy; all generator guards then passed |
| Official test 33: battery data | Five expected diagnostic substrings were stale; all invalid data was rejected | Update five assertions to precise v2 paths; 67/67 passed on Windows and Linux |
| Continuation: replay policy | The ext4 mirror initially omitted `.git`, so its required recorded build commit was empty; trajectory replay passed | Restore the original frozen clone's Git metadata, without changing app source; [50/50 replay checks passed](replay-policy-restored-git.log) |
| Integration tail: D8b-R2 polar candidate freshness | Three checked-in research candidates still carried the v1 Stik donor layout | Regenerate through the existing Godot pipeline; [all 1,023 original numeric leaves preserved](../../AS-02/polar-candidate-parity.json), then [Linux freshness and all three CLI tests passed](polar-rerun.json). Offline v2 schema checks also passed for all three. |
| Integration tails: Avanti generator and E5a Extra ground checks | Windows-generated report paths used backslashes, so Linux expected different report text; aircraft data matched | Use POSIX paths in all three generator report headers. [All eight aircraft byte hashes stayed unchanged](generator-portability.log). Windows and [Linux freshness passed](generator-portability-rerun.json); [E5a rerun](e5a-rerun.log) passed 21 geometry and 63 session checks. |
| Continuation source-manifest gate | Four imported Python modules created `__pycache__` files under app/tests; no source file changed or disappeared | Retain the original false gate and raw manifests, verify the only additions are those four caches, and exclude `__pycache__` in future harness manifests; [final source audit](final-summary.json) confirms all 535 source files are byte-identical |

The original failed attempts remain in the [continuation summary](continuation/summary.json); successful reruns are additive evidence. The three regenerated research candidate files were copied into the ext4 mirror after their failure; their old/new hashes are in the parity report. The six portable generator/report files were copied only after the continuation finished ([overlay hashes](generator-portability-overlay.json)); the three freshness checks and full E5a section then reran successfully. No replay tolerance, golden trajectory or physical coefficient was changed to make a check pass. Existing inertia data-quality and teardown leak warnings are retained; they are not hidden or promoted to physical validation.

## Coverage

The frozen suite contains 195 GDScript tests. The 32 official successes plus 163 continuation cases cover loader integrity, all aircraft handling, combustion/turbine/electric propulsion, shaft/wake/rotor behavior, ground contact/friction/stiction, takeoff/landing, stalls/spins/crashes, input, controls, reset/checkpoints, UI selection and environmental state. The replay-build-identity rerun resolves the sole continuation GDScript failure.

The 27 remaining official integration sections cover model contracts/clearances, trace failure exits, experimental polar and shaft routes, weather/turbulence/atmosphere/time-of-day identity, four catalog trimmed flights, rejected IDs, frame logger failure cases, complete-state independence at 30/60/144 fps, and Extra/P-51 ground refinements. The initial continuation had 186 successes and four failures among its 190 jobs; the replay, polar, Avanti and E5a reruns resolve all four. Combined with the official prefix, this provides 195/195 GDScript and 27/27 integration-section coverage.

This test snapshot predates later GP wheel-dynamics changes. Those separately owned physics changes are not AS migration deltas. Software regressions establish consistency and lifecycle behavior; measured RC airframe, engine, tire and field qualification remains open as listed in the [delivery report](../../AS-05/README.md).
