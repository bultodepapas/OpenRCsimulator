# R11 Linux integration verification: candidate -07

This report records verification against the immutable Linux candidate at `/home/bulto/openrc-r11-b09-r05b-20261015-07`, derived from commit `7c47c7ba02f7d2c874ec92a381ea73ef967069d6`. Its frozen `app/test.sh` SHA-256 is `dae260326426be613b065b0ae00f040842c310fab217979b537a274b3b36b7d6`; its pinned Godot 4.7.2 Linux binary SHA-256 is `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`. The candidate’s source/overlay manifests and materialization receipt are preserved beside this report.

## Canonical and supplemental tests

The canonical `app/test.sh` gate is red. The first attempt's import process ended with a shell-reported `Aborted`/SIGABRT at `test.sh` line 19; its cause is unknown. A later run in `canonical-app-test-02.log` completed import and earlier suites, then stopped at `test_atmosphere_column_session.gd`, which reported 96 checks with 3 failures because the clean candidate had no repository `tmp/` parent for preference-file tests. Creating only an empty ignored `tmp/` directory reproduced 96/0 with the frozen test. The separately updated live fixture, run against frozen candidate resources, passed 97/0. The original failure and later fixture qualifications are in `canonical-app-test-01.log`, `canonical-app-test-02.log`, `atmosphere-column-session-output-dir-01.log`, and `atmosphere-column-session-updated-live-test-01.log`.

The sequential diagnostic remainder of the `test_*.gd` loop covered 441 suites: 435 passed and 6 failed. The failures were three P-51 behavior expectations: stall recovery reached 83 m against an 80 m limit; liftoff was 25.2 m/s (1.61 Vs) against a 1.5 Vs upper bound; and the loop reached 343° against a 360° minimum. The others were rudder decay (15.13°/s against a 15°/s maximum), scenery cold-build time (932.651 ms against 800 ms while another P-51 process was active), and the retained yaw-damping comparison (7.75% against 7% at α=11°). The scenery result is not a performance qualification. Raw results are in `diagnostic-remainder-01/`.

The rest of the frozen `app/test.sh` tail ran sequentially as 72 diagnostic steps: 63 passed, 9 failed. This is a diagnostic continuation, not a green canonical run. Its nine failures were the frozen 17-test trace-acceptance suite (10 failures and 2 errors), the stale D8b synthetic-polar `--check`, one pull-up candidate CLI test, two shaft CLI checker errors counted at the suite step, and five frozen trace-checker invocations rejecting the newer `aero_model` metadata. The direct trace runs for Stik, Extra, P-51, Avanti, and Timber all completed with expected aircraft IDs. The updated checker passed all five traces; the frozen checker failed each with `missing or unsupported aero_model`. Avanti physics data, weather, turbulence, atmosphere, atmosphere-column, calendar/time-of-day, frame-time, 30/60/144 fps invariance, E0b5/E0b6p, E5a, and E5b checks passed. Full command/output records are in `diagnostic-tail-01/`.

The supplemental checker run kept the candidate app and pinned Godot unchanged while routing checker imports and `CHECKER` to the separately identified updated checker (`bcaa40377bda39fc8e8e7a2be6753fc41441bf2901b0ca60d8c5feb11c203d81`). It passed 16/17 frozen `TraceAcceptance` tests; the sole remaining failure was a no-op mutation fixture for `wheel_profile_status="applied"`. The two selected shaft CLI tests passed 2/2 with the updated checker, and the live repaired continuous-turbine metadata test passed 1/1 against the frozen app. Results and source identities are in `updated-checker-supplement-01/`.

The tail outcome audit confirms all seven explicit negative controls exited with ordinary refusal codes (1 or 31); none returned GNU timeout codes 124/137 or a signal status. Successful direct Godot commands had no `ERROR:`, `SCRIPT ERROR:`, or `SHADER ERROR:` markers. Error output appeared only in explicit refusal and invalid-output controls. See `diagnostic-tail-01/outcome-audit.json`.

The D8b failure was then isolated on a disposable copy. The frozen candidates contained pre-D11g rate-derivative values and provenance: across the three candidates, the prior-to-regenerated differences are the `CLq`, `Cmq`, and `Cnr` values and their three source strings. The current generator's write mode and subsequent `--check` both passed on the copy. A separate regenerated-candidate comparison found a decimal-token difference in `Cldr.value` versus the catalog JSON, but Godot parses both to the same float and reports their non-polar dictionaries equal; that token difference is not the cause of the stale-fixture rejection. The original frozen `test_pullup_cli.py`, app, reference Stik JSON, Godot binary and test-module bytes were retained; overriding only its `CANDIDATE` to the regenerated intermediate file passed 3/3 tests in 37.690 s. The generator outputs were later promoted to the live tree only after checking their three inputs and CRLF-only dependencies; see `../../d8b-candidate-diagnostic/live-regeneration-promotion-01.json`. These checks qualify the regenerated research fixture/test path only; the frozen -07 fixture and full canonical result remain unchanged and red. Evidence: `../../d8b-candidate-diagnostic/execution/01-generate.log`, `02-check.log`, `04-regeneration-verification.json`, `05-godot-cldr-parse-probe.log`, and `06-frozen-override-unittest.log`.

## Post-run source integrity

The final source walk reconciled every path, mode and SHA-256 in the -07 post-overlay manifest (14,922 entries; tree SHA-256 `b9108ec7cfa993a396a218fd809f9d58bee6e9e54d299424a6a42599f6f77e5c`). There were no missing or changed manifested files. The 85 new paths are separately retained and classified: 39 Python bytecode files, 43 ignored flight-recorder test-scratch files, one Godot-generated UID sidecar, and two files for the retained package-editor sidecar runner. Candidate HEAD, 66-entry Git status and clean staged diff match the materialization receipt. Godot import cache and exported `dist/` are excluded from this source identity and handled as generated output. The raw path/hash reconciliation and classification are `post-run-source-01.json` and `../materialized-20261015-08/postrun-classification-01.json`.

## Local package diagnostics

The earlier `app/export.sh` attempt on -07 is preserved in `export-01.log`. Linux export completed, but the Windows preset failed because this candidate did not contain `app/native/ground_vehicle/openrc_ground_vehicle.dll`. The script stopped there; this is not an all-platform export result.

The resulting Linux executable (`dist/linux/openrc-simulator.x86_64`, SHA-256 `7af0a2d18862a21380d9381f416471ca797d69c2effd4b9eed15485ece9384a1`) ran the compiled `--trace` route and emitted a 721-row, 720-tick Stik trace. The updated checker passed it. Godot printed a four-ObjectDB-leak warning at exit; the trace completed successfully. See `linux-exported-main-smoke-01.log` and `.csv`.

The external package probe also completed 34 checks with no simulation fault for both the Stik and Avanti: 240 accepted control ticks per aircraft, initial sample plus each tick in the ORFL, checkpoint capture, and exact recorded-input checkpoint-continuation state equality. This establishes continuation-state equality for that test; it does not claim exact ORFL replay. The clean sidecar run is `linux-editor-main-pack-native-smoke-01.log` with ORFLs and `probe.json` under `package-smoke/linux-editor-main-pack-native-01/`. It used the pinned editor physically copied next to the exported Linux `.so` and the original exported executable as `--main-pack`. The separate native ClassDB probe passed: `OpenRCGroundVehicleNative` was registered, reported backend `native`, ABI float64/IEEE754, and matched the packaged Linux build receipt and sidecar SHA-256 `08c8c08e74bd9c9465d1c0f732b082fc23829dcf243287eac51f25ed4e98f3a3`. The probe source hash is `a5b4148fd1ec3e5758e23ae0c8987b456f026c3e82233fdeb87ba12639095abc`; output is `linux-ground-vehicle-classdb-03.log`.

Two earlier editor-plus-main-pack invocations, including one with `--path` set to the exported directory, completed the same 34 checks but emitted GDExtension loader errors because the `.so` was not beside the editor executable. The successful sidecar arrangement matches Godot 4.7.2’s Unix dynamic-library fallback beside the running executable in [`OS_Unix::open_dynamic_library`](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/unix/os_unix.cpp#L982-L989). This explains the harness layout and does not explain the separate release-template `--script` timeout.

The exported-binary `--script` probe did not produce output within its preserved 180-second cap; a smaller release-binary SceneTree marker also timed out at 30 seconds. Help and version probes worked, and the compiled binary’s ordinary `--trace` route worked. The script/marker timeout cause remains unresolved; it is not evidence of failed flight simulation. Logs include `linux-package-smoke-01.log`, `package-marker-01.log`, `package-help-01.log`, `package-version-01.log`, and `linux-package-timeout-host-context-01.txt`. The host snapshot was captured after timeout, so it cannot establish earlier resource conditions.

## Reproduction

From WSL, the frozen tail and its outcome audit were run with:

```bash
python3 -u /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01/run-diagnostic-tail-01.py
python3 /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01/audit-tail-results-01.py
```

These are the original commands, with fixed candidate/evidence paths; the runners refuse to overwrite existing result directories. Reproduction therefore requires a fresh, explicitly identified candidate/output directory and updated manifest/hash record, rather than rerunning in place.

The updated-checker supplemental command was:

```bash
python3 -u /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01/run-updated-checker-supplement-01.py
```

The -07 canonical gate and initial export remain red; the separately successful diagnostics do not change those outcomes or establish physical validation.
