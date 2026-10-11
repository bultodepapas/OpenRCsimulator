# PT2 — manual circuit trial preparation

2026-10-08 · **Status: trial prepared; owner flight and physical acceptance pending.**

The next action in [ROADMAP](../../../../ROADMAP.md#execution-order-and-release-gates) is a manual Ugly Stik takeoff–circuit–landing session. The owner confirmed that no pilot evidence is available yet. This preparation uses the delivered [UI-06c-R1 package](../../menu-investigations/UI-06c-R1/README.md) and the existing [flight card](../../menu-investigations/UI-06c/FLIGHT-CARD.md). It changes no simulation or aircraft data.

## Identified trial build

| Item | Identity |
| --- | --- |
| Platform | Linux x86_64; pinned Godot 4.7.2 |
| Export build | `v0.1.0-rc6-4-gce4a80c-dirty` |
| Export executable SHA-256 | `9f245fb183e9ae68ef13d9b587bf2e27a6f1980cb00e559da22efc2a8f18b0d2` |
| Stik input SHA-256 | `fc8e02234c1ed872e7ed5ed9e2cbddbe1c816834f18ad722e3735eaeb27f1e44` |
| Default field SHA-256 | `c575b9df1ac59eb74f45ba71720d58ff90fc3dfa966812c657360e9f332715ea` |

The `dirty` suffix belongs to the original frozen export. Its [617-input source manifest](../../menu-investigations/UI-06c-R1/source-sha256.json) still matches every listed file at preparation commit `28cd5c6`; the build is not renamed to the current commit. All three local ZIPs match the retained [package checksum record](../../menu-investigations/UI-06c-R1/SHA256SUMS). Native Windows/macOS acceptance remains separate.

The local trial folder is `$HOME/OpenRC-trials/PT2-001`. It contains a frozen copy of the Linux executable, aircraft/field inputs, propeller coverage, a prefilled `FLIGHT-CARD.md`, `SHA256SUMS`, and an empty `evidence/` folder. Keep these files together when later exports replace `dist/`. Pilot, controller, display and handling fields remain blank until observed.

## Run the trial

From a terminal:

```sh
cd "$HOME/OpenRC-trials/PT2-001"
sha256sum -c SHA256SUMS
./openrc-simulator.x86_64
```

1. Connect the intended USB radio and record its firmware, USB mode and model/profile in `FLIGHT-CARD.md`. Use the existing [radio setup guide](../../../FIRST-LAUNCH.md#3-fly). Record rates, expo and trim positions.
2. On Home select **Ugly Stik → Start: runway (experimental) → Fly**. In flight, calibrate with **K** if needed; move throttle to low to arm. Use this menu route without user arguments. `--quick-flight`, `--trace` and `--frametimes` select direct flight and do not reproduce this runway trial.
3. Start screen/radio video if available. Press **T** and confirm **REC**. Follow the flight card: idle hold, straight taxi, takeoff, circuit, approach, wheel landing and rollout. Stop at a blocking problem and describe it; a completed circuit is not required for useful feedback.
4. Press **T** to save before ending the flight or quitting. Copy the saved CSV into `evidence/` and record its filename against the attempt. On this Linux setup the default trace folder is `~/.local/share/godot/app_userdata/OpenRC Simulator/traces/`; the HUD/log prints the actual path.
5. **R**, Pause → Restart and crash recovery close an active recording. Check the save message and press **T again** for the next attempt. Keep failed attempts and note which restart route was used. A pause/focus loss freezes the session; it is not a handling observation.
6. Fill the existing axis ratings and readability notes. Identify the largest reproducible blocker with maneuver, input, response and trace/video timestamp. If no real Stik comparison is available, mark handling comparison **not rated**. Preserve the configuration before considering a repair.

The [rendered circuit kit](../E3c2b/index.html) is a reference for presentation only; it is not a prescribed pilot technique or independent flight evidence.

## Supporting diagnostics

Run the controller diagnostic separately, with the physical radio connected, moving every stick through its full range:

```sh
cd "$HOME/OpenRC-trials/PT2-001"
./openrc-simulator.x86_64 -- --input-report=evidence/input-report.json --t=20
```

It opens diagnostics, writes the report and closes. No device is a valid empty report, not controller acceptance. Record firmware and USB mode separately. For another session choose a new filename.

Use **F3** during the runway trial and capture the performance line with the flight video. For a separate target-machine timing sample:

```sh
cd "$HOME/OpenRC-trials/PT2-001"
./openrc-simulator.x86_64 -- --frametimes=evidence/frametimes-airborne.json --t=20
```

This starts an airborne flight and closes after warmup and sampling. Label it **separate airborne performance evidence**; it does not measure the manual runway circuit. Keep the display, camera, auto-zoom and shadow settings recorded for each run. Headless/Xvfb timing is not target-display acceptance.

## Evidence to return

Return the filled `FLIGHT-CARD.md`, the attempt CSVs, any screen/radio video, controller diagnostic, timing report and radio calibration/profile used. On the default Linux setup, calibration is `~/.local/share/godot/app_userdata/OpenRC Simulator/rc_calibration.cfg`; include it only if present and actually used. Retain the frozen input files and checksum list with the evidence.

Afterward, run the existing [G1b1 range audit](../../../../research/propulsion/range-audit/README.md) on each flown trace using this frozen aircraft file and coverage. Supply the attempt's tick count excluding its initial row; verify continuity before interpreting a truncated recording. The audit reconstructs previous-row velocity/current-row RPM and cannot observe internal RK stages. Its source propeller is borrowed; covered ranges are not validated thrust data.

Gate 2/D6d needs the owner's handling/radio observations; Gate L needs human readability and target-machine evidence. PT2 also needs independent pull/coast-down, idle creep and takeoff/landing observations with configuration and uncertainty. Record missing measurements as pending. Choose the next bounded repair from the largest reproduced blocker; bring forward F2 only if trim prevents the session.

## Software readiness proof

The preparation reruns the existing Linux export harness with isolated preferences:

```sh
.tools/visual-venv/bin/python docs/research/menu-investigations/UI-06c/run_export_smoke.py \
  --binary dist/linux/openrc-simulator.x86_64 --out /tmp/openrc-pt2-preflight
```

Use a fresh output folder. The [readiness manifest](preflight/readiness.json), [export report](preflight/export-smoke.json) and [log](preflight/export-smoke.log) retain the results. Home → runway, native throttle input, R/Pause Restart, trace origin, isolated preferences, Stik/Extra source/export numeric equality and scripted capture pass. The taxi trace contains 421 rows over 1.75 simulated seconds, moving 1.818 m east and ending at 4.189 m/s horizontal speed. The [offline range audit](preflight/range-audit.json) accepts all 420 recorded steps against the frozen Stik input. [Home](preflight/home-runway.png) and [taxi](preflight/flight-taxi.png) captures were inspected.

These are automated keyboard/software results, not the owner's flight. UTC timestamps in raw logs fall on 2026-10-09; the preparation date above uses America/Bogota. The original package's full regression proof remains in UI-06c-R1; this documentation-only preparation does not require rebuilding unchanged app inputs.

The logs retain Xvfb/driver VSync warnings and one ObjectDB instance reported at exit by several trace processes. The harness passes; this is not a warning-free run. The existing exit-warning investigation remains separate from this trial preparation, and software-rendered frame times are not used for pilot acceptance.

Ready-to-paste commit message: `PT2: prepare identified manual circuit trial; proof: package hashes, 617 source matches and Linux runway export smoke`
