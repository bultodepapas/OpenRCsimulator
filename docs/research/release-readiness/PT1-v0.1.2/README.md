# PT1 — v0.1.2 release verification

2026-10-16. Release preparation; no v0.1.2 package is published yet.

## Native Windows source smoke

At `6ce6eec9`, official Godot `4.7.2.stable.official.ed1daf0bf` produced five headless three-second trimmed traces on Windows with isolated application-data directories. All five have 720 flown ticks, finite samples and level altitude under the existing validator. The controller pause-recovery test passed 24/24 without engine errors or object/resource leaks. [Results and artifact hashes](windows-source/verification.json), [controller log](windows-source/windows-controller-pause.log), [clean import log](windows-source/windows-import-rerun.log).

The first cached import after switching source revisions reported `get_multiple_md5` errors; the subsequent import was clean before these checks ran. This is source-editor evidence, not final downloaded-package, renderer, controller-hardware, performance or physical-flight acceptance. The P-51 trimmed trace does not resolve [P51-22](../../p51-realism/P51-22/README.md).

Recheck a retained trace with `python app/tests/check_trimmed_flight.py docs/research/release-readiness/PT1-v0.1.2/windows-source/trace-default.csv --duration 3` (substitute the other four names). Produce traces using the corresponding five commands in `app/test.sh` with the pinned Windows console executable; run `res://tests/test_controller_pause_recovery.gd` with `--headless --audio-driver Dummy`.
