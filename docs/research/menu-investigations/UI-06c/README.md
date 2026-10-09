# UI-06c — exported runway-launch smoke

2026-10-08 · Step prefix: **UI-06c** · **Status: exported Linux smoke passed.** This report owns the packaged manual-launch smoke and its pilot flight card. It verifies software delivery only; owner flight, landing behavior and PT2 remain open.

The later [UI-06c-R1 refresh](../UI-06c-R1/README.md) rebuilds and verifies packages containing the checkpoint-origin repair. The measurements below remain historical evidence for the original UI-06c binary.

## Reproduce the exported check

After `app/export.sh` produces the Linux package, run from the repository root:

```sh
python3 docs/research/menu-investigations/UI-06c/run_export_smoke.py \
  --binary dist/linux/openrc-simulator.x86_64 \
  --out docs/research/menu-investigations/UI-06c/evidence
```

The runner opens the actual exported binary under Xvfb (or an existing display) with no user arguments. Its Python driver injects native X11 keyboard events through XTest: it selects **Start: runway** on Home, flies the manual route with W, records and saves through the app's `Recorder`, then checks R and Pause → Restart. The flight trace's metadata and recording-start snapshot are checked against its first CSV row. The route does not call `reset_on_runway` or use autopilot. The release binary does not support Godot's `--script` option; the manual route therefore uses the real exported UI.

The runner also compares source and exported CLI trace rows for the default Stik and `--aircraft=gp-extra-300s-60`, checks `--quick-flight` and an optional scripted capture, and verifies direct trace routes launch airborne while `settings.cfg` still says runway. It sets only `XDG_DATA_HOME` and `XDG_CACHE_HOME` to temporary roots, checks that `settings.cfg` is written under the isolated data root, and removes those roots at exit. Trace comparison uses the CSV's nine-decimal output precision.

The run passed on 2026-10-08. It selected and launched the default Stik at the runway threshold with the engine running and no startup error. The manual Recorder trace contains 349 rows over 1.45 simulated seconds; W reached 0.625 throttle command, with 0.841 m east displacement and 2.412 m/s horizontal speed at the final row. The R and Pause → Restart traces also report the selected and actual runway start, and their recording-start snapshots match their first rows. Stik and Extra source/export CLI traces each have 481 rows and match byte-for-byte at CSV precision; while a runway choice is saved, both CLI traces select and launch airborne. `--quick-flight` and scripted capture passed, and all CLI routes preserved the runway settings bytes.

The runner report records the executable, project, aircraft, field and runtime-source hashes, the dirty exported build identity, trace metadata, route results and preference isolation. The evidence index is in the [evidence folder](evidence/README.md). These are software checks; they do not rate handling or prove a successful takeoff, circuit or landing.

## Owner flight

Use the [manual flight card](FLIGHT-CARD.md) with the exact build being flown. Preserve failed attempts and the trace/camera evidence. Use the existing [E3c2b review kit](../../ground-contact/E3c2b/index.html) for the experimental circuit reference and the [G1b1 range audit](../../propulsion/G1b1/README.md) for the recorded propeller queries. The offline audit reconstructs queries from previous-state velocity and current auxiliary RPM; it does not count internal RK-stage queries or establish physical propeller support.

## Limits

The automated W hold proves that keyboard throttle reaches a runway-started session and moves the airplane in the package on the executing Linux host. It does not establish controllability, trim, readable attitude or height, target-machine performance, radio behavior, takeoff or wheel-landing quality. The runway launch and full circuit remain experimental until the owner's separate evidence is recorded.
