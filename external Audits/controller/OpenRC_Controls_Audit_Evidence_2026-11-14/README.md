# OpenRC controls audit — evidence and reproduction

This bundle accompanies **OpenRC_Controls_Input_Audit_2026-11-14.md**.

## Identity

- Repository: https://github.com/bultodepapas/OpenRCsimulator
- Audited commit: f41d0fd2eb5483c609bcd858bcf22776eb311e14
- Godot: 4.8.beta2.official.cafc17a19 (Linux x86-64 in the recorded runs)
- Linux executable SHA-512: 428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
- Production checkout remained unchanged.
- Original logs retain original command paths. Use the portable launcher below; those host paths are not required.

## What a passing probe means

The diagnostic probes intentionally demonstrate adverse current behavior. A passing diagnostic says the fixture observed the reported problem or printed its discriminating result. It does **not** mean the product behavior is correct. Convert these into product regressions asserting the desired fixed contract.

The 14 existing repository test scripts are different: their final original runs reported 845 successful checks. The profile and calibration probe assertion totals must not be added to that baseline total.

The bundle does not contain a physical-controller qualification, a complete rendered flight, the full app test suite, or an exported Windows/macOS result.

## Requirements

Use Python 3 and an audited repository checkout containing tools/godot/run_checked.py and its normal supporting modules. Obtain the pinned engine using that checkout's documented engine workflow, and verify its hash/version. The executable and full repository/asset set are not included here.

The fixtures include the actual production scripts needed by the probes. They use minimal project configurations. Generated Godot caches are intentionally excluded; import each fixture before its first run. The launcher does this automatically.

Linux was used for the recorded and delivery-validation runs. XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME are isolated by the launcher. Do not point the probes at a real simulator user-data directory.

## Run the main diagnostic groups

From the extracted archive directory, set absolute paths appropriate to your machine:

~~~sh
export GODOT_BIN=/absolute/path/to/Godot_v4.8-beta2_linux.x86_64
export CHECKED_RUNNER=/absolute/path/to/OpenRCsimulator/tools/godot/run_checked.py
python3 run_probes.py
~~~

The default runs calibration, setup/profile capture, routing and hot-path operation counts. It requires the exact recorded engine version, imports each disposable project, and invokes the original checked runner with required completion text. It writes fresh results under new_runs; it does not replace the original evidence.

Run one group:

~~~sh
python3 run_probes.py --group calibration
python3 run_probes.py --group profiles
python3 run_probes.py --group routing
python3 run_probes.py --group hotpath
~~~

Run the existing baseline tests:

~~~sh
python3 run_probes.py --group baseline
~~~

Add the controlled two-writer persistence observation:

~~~sh
python3 run_probes.py --group profiles --race
~~~

The race scheduler waits until both real saves have read/merged the old store, publishes A, then publishes B, and verifies that only B remains. See evidence/profiles/PORTABLE_REPRO.md. The profile-specific portable script accepts the same engine/runner environment variables and can be run independently after import.

Run the isolated timing comparison only when competing engine/performance work is stopped:

~~~sh
python3 run_probes.py --group hotpath --measure
~~~

The timing comparison uses inert application objects and verbatim AppRoot method bodies. Production routing has lightweight counting instrumentation. The cache prototype lacks production invalidation. Neither numbers nor ratio certify full-application frame time, physical event rate, input latency or a production-ready optimization.

## Important fixture boundaries

- Calibration: actual calibration/profile/reader and UI classes; synthetic raw samples and a stub connection.
- Profile/setup: actual setup/service/store; synthetic registry devices and isolated profile files.
- Capture: direct InputEvent injection into the actual Controls screen.
- Concurrent writers: the real store subclass pauses only at transaction entry after load/merge; original write implementation is then called.
- Quad: actual adapter, flight controller and controlled plant; synthetic electric-quad fixture and synthetic inputs.
- Airship pause: actual adapter and session resume method; the session is marked prepared, and an unused collision-world dependency is stubbed. There is no actual world/render/flight simulation in that probe.
- Hot path: 13 verbatim AppRoot methods, inert surrounding app objects, real actions/profiles/service; no SDL, USB, renderer or full scene.
- Minimal project.godot files, generated UID sidecars and some SVG import metadata differ from the source project. These are explicitly catalogued in evidence/VERIFICATION.md.
- The bundled routing/setup_probe.py and original profile/run_concurrent.py are historical construction/launch records containing original host paths. Use the included ready-to-import fixture and portable launchers; do not run those historical helpers unchanged on another machine.

## Original evidence selection

evidence/selected_runs.json identifies **29 curated successful original checked runs**, including the 14 baseline scripts, final diagnostic runs, projection parse and two import checks. Every included log matches its original recorded SHA-256 and byte length.

The independent verification summary covers the larger original working set of 44 runs (35 successful and nine earlier failed fixture attempts). The nine failures were missing-resource/translation/marker/prototype issues, not product bugs, and are omitted from this curated archive. Superseded successful attempts are also omitted. References to historical runs in original author notes are retained for provenance; use the final paths in the consolidated report and selected_runs.json.

The original verification report is not a cryptographic attestation of an immutable execution environment. It verifies consistency of the retained files and their reported checksums.

## Locate findings

- CTRL-01, CTRL-04 and CTRL-05: evidence/routing/
- CTRL-02, CTRL-03, CTRL-06, CTRL-07, CTRL-14: evidence/profiles/
- CTRL-08 through CTRL-13: evidence/calibration/
- CTRL-15: evidence/parent/project/audit_hotpath.gd and the two hotpath runs
- Exact source permalinks, severity, reproduction, fixes, regression criteria and limits: the full report

The author notes may use earlier grouping/priority wording. The consolidated report is authoritative for the delivered assessment.

## Delivery verification

Before packaging, the four disposable projects were imported from their delivered locations and the default portable launcher plus the race protocol was executed. All **15 checked processes** completed successfully: four imports, eight diagnostic scripts, two race writers and one final store reader. The expected two AUX overlap warnings were retained. This validates package paths/resources and reproduction instructions on the recorded Linux environment; it adds no physical qualification and does not change the 845-check baseline total. See delivery_verification/summary.json and its checked logs.

## Integrity

SHA256SUMS.txt lists every delivered file except itself. After extraction on Linux:

~~~sh
sha256sum -c SHA256SUMS.txt
~~~

The extracted directory should be used as a disposable evidence workspace; importing/running it will create cache and result files not covered by the original manifest.

Bundled OpenRC code remains under its included MIT license. Resource-specific license/provenance files are retained with the included resources. No full engine, repository, proprietary reference scans or production user profile data are bundled.
