# UI-06c evidence

**Status: exported Linux smoke passed on 2026-10-08.** The [aggregate report](export-smoke.json) and [command log](export-smoke.log) record the run. The tested binary SHA-256 is `b13ba90d592ff10fec12ff02fc100ccdcb15191e223f36001cae2f4d7295a05f`; its trace build identity is `v0.1.0-rc6-3-g1504ed8-dirty`. The report records the workspace Git identity plus hashes for runtime source files, project settings, aircraft data, field data and traces.

The manual GUI route ran the exported binary with no user arguments under Xvfb. Native XTest key events selected runway on Home, activated Fly, started Recorder with **T**, held **W**, stopped and saved with **T**, then exercised **R** and Pause → Restart. The saved Stik trace reports 349 rows over 1.45 simulated seconds, maximum throttle command 0.625, east displacement 0.841 m and final horizontal speed 2.412 m/s. It records `selected_start_choice=runway`, `launch_choice=runway`, `launch_kind=runway_threshold`, `launch_field_id=default`, `launch_engine_running=true` and an empty `launch_error`. Recorder tick and auxiliary snapshots match the first CSV row. Restart recordings start at idle and retain the runway selection.

The source and exported Stik and Extra CLI traces each contain 481 rows and match exactly at CSV precision (maximum numeric difference 0). With `start_choice=runway` saved, both source and exported traces report selected and actual starts as airborne. The exported `--quick-flight` route and scripted capture passed, and all CLI routes preserved the exact runway settings bytes. The manual Home route also saved `start_choice=runway` inside temporary `XDG_DATA_HOME`. Temporary XDG data and cache directories are removed after the run.

## Artifacts

- [manual-launch.json](manual-launch.json) — exported GUI route, metadata, launch snapshot, Recorder snapshot and measured simulated duration.
- [export-smoke.json](export-smoke.json) — executable/source hashes, source/export CLI parity, settings isolation and scripted capture manifest.
- [runway-manual.csv](runway-manual.csv), [runway-r-restart.csv](runway-r-restart.csv), [runway-pause-restart.csv](runway-pause-restart.csv) — actual Recorder output from the packaged interactive route.
- [Home airborne](home-airborne.png), [Home runway selection](home-runway.png), [runway flight](flight-runway.png), [W taxi](flight-taxi.png), [pause/restart](flight-pause-restart.png), and [scripted capture](scripted-capture.png) with [capture manifest](scripted-capture.json).
- [exported GUI log](exported-gui.log) and [full command log](export-smoke.log).
- [Full app test log](../app-test.log.gz), [verification manifest](../verification.json), [export log](../export.log) and [export package checksums](../SHA256SUMS).

This evidence verifies software routing on one Linux host. It does not rate handling, establish physical-radio behavior or establish takeoff, circuit or landing quality; those remain separate owner-flight evidence in the [manual flight card](../FLIGHT-CARD.md).
