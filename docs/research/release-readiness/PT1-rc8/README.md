# PT1 — rc8 release verification

2026-10-12 (America/Bogota) · Status: rc8 published; tagged CI, all downloaded checksums and Linux standalone smoke passed. Native GUI, physical-radio, target-GPU and pilot acceptance remain open.

## Candidate scope

The release integrates current main-line work since rc7, including aircraft v2, wheel/terrain integration, landscape/population and soundscape, persistent crash presentation, updated Home defaults, update notices and the Turbo Lumber Evolution PREVIEW. [Release notes](../../../releases/v0.1.0-rc8.md) define the download's scope and limits.

Preflight found existing Linux blockers. The schema controls removed the Stik's gear while retaining its catalog ID, which attaches a real wheel profile at the file boundary. The three controls now use a synthetic profile-free ID. The full pinned-Linux contract test passes **1,873 cases / four tests**, retaining strict runtime validation.

The extreme-atmosphere reset control attempted a 15 m/s Stik trim at 4,000 m, 45 °C, 870 hPa QNH and 100% RH (density 0.5400099459 kg/m³). Pinned Linux Godot reproduces the previously documented nonconvergence, residual 0.16638981173064932. Nearby atmosphere configurations at 15 m/s and the same extreme configuration at 16 m/s converge. This release uses 16 m/s for the reset/recovery control, verifies that speed is retained and checks checkpoint availability before reading its fields. Runtime trim equations, acceptance tolerances and golden flights are unchanged. The exact 15 m/s convergence limitation remains open; [original Linux/Windows evidence](../../landscape-upgrade/LU-06/atmosphere-baseline.md) records its scope.

Focused pinned-Linux checks pass: atmosphere flight **142/142**, trim **14/14** (including 5 m/s refusal), trim density **35/35**, trim integrity **700/700**.

The v2 agreement runner also retained a scratch-directory default absent in fresh CI checkouts. Its default now resolves the checked-out `app/`; the CI command passes **62 cases**.

A clean Linux suite also reached the landing test's 60-second runner deadline without an assertion failure. Its unchanged four-flight workload passes **28/28** in **81.91 s** (prior [CR-01b measurement](../../crash-damage-investigations/CR-01b/README.md): **75.51 s**). Only this test receives a bounded 180-second runner deadline; every test and assertion remains enabled, and other Godot invocations retain 60 seconds.

Local offline-tool regressions and all eleven CI geometry/physics/Timber generator commands pass. Full app/capture/export qualification is required before publication; no test skips or golden-flight replacements are authorized by this release.

## Visual fixture correction

The L10 cue checker originally hid each cue and its new `FieldProjectedShadows` receiver together, then incorrectly required every changed pixel to fall inside the cue mesh bounds. The windsock's close/pilot-turn/overview captures had **6,676 / 847 / 148** changed pixels outside those bounds and one extra shadow draw. Using the existing `--field-shadows=off` flag isolates the mesh ablation without changing runtime rendering or pixel/triangle/clipping gates. All four cue modes pass complete first/repeat/scenery-on checks in the production capture environment; independent pairs match exactly. The projected-shadow regression still passes **63/63**. [Harness contract](../../../../tools/ground/README.md).

Two local mutation-project imports aborted after editor-layout completion: [disabled-surface log](local-disabled-import-abort.log), [stripe log](local-stripes-import-abort.log). Three fresh and one warm disabled-surface replay, plus ten unfiltered replays, passed; no reproducible source fix was found. Failed output was retained, then the surface and stripe-reference checks passed on fresh outputs. This is a local engine/tooling reliability observation, not evidence of a flight failure or a closed headless-reliability gate. Tagged CI must run the complete unmodified sequence with the corrected cue fixture.

## Completed local qualification

Frozen candidate: `9e25b71`. Runtime application content is unchanged from the candidate whose complete `app/test.sh` step passed in [CI 38303404608](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38303404608); that run subsequently reproduced the old L10 fixture failure. Only the cue checker and its documentation differ. Local qualification covered all **225 GDScript test scripts**, the original shell-tail checks, offline tools and generators. The landing script ran complete under its measured deadline; no scripts were omitted.

The complete capture inventory passed in the isolated Linux checkout after the recorded import retries and corrected L10 fixture: **46 base images**, **66 VQ cases**, **64 treeline cases**, all landscape/cue reviews and the runway scenario. [Capture manifest](preflight-capture-manifest.json) retains their hashes. The scenario holds a common state across cameras, remains stationary at idle, and reaches 42.3 m altitude at 12 s; these are scripted software checks, not takeoff validation.

An independent clean Linux checkout at `9e25b71`, with an isolated local rc8 tag, exported all three packages and passed Linux flight, resource-pack, identity, platform-version and macOS architecture/signature checks. [Export log](preflight-export.log) · [Preflight checksums](preflight-SHA256SUMS). These hashes identify local preflight builds; published CI packages have their own checksums.

The exported Linux binary refuses a Turbo Lumber real-flight request with exit 1 and the explicit preview-only message. Its scripted visual route runs and writes a complete frame-time report; it also logs the expected absence of flight data. Native Windows/macOS GUI, hardware radios, target-GPU and pilot acceptance remain open.

## Tagged publication

Tag `v0.1.0-rc8` identifies `9e25b71d2a36dbeb1eb44d4b65d3da9e622b4375`. [Tagged CI 38317830534](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38317830534) passed all four jobs, including the full headless app suite, complete capture sequence, three-platform exports and publication. The prerelease was published at **2026-10-12 19:05:50 America/Bogota** (**2026-10-13 00:05:50 UTC**) with exactly three ZIPs and `SHA256SUMS`. [Release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8).

The release is frozen at the selected candidate. Subsequent ground-effect and propeller-blur work in the shared checkout is outside this release and remains with its owners.

## Downloaded release verification

All four expected assets were downloaded with `gh release download`. The three ZIPs match the published [SHA256SUMS](SHA256SUMS); every local file, including the checksum file, also matches its GitHub asset digest. The prerelease flag and the remote tag's exact candidate commit were independently checked.

The extracted Linux executable ran headless with Dummy audio for three seconds from an initially empty working directory, with isolated user data. It exited **0** and left the working directory empty. The frozen candidate's `check_trimmed_flight.py --duration=3` passed: **720 ticks**, exactly **3.000000000 s**, finite samples, altitude **30.000 → 30.000 m** and airspeed **15.0000 m/s**. The trace identifies build `v0.1.0-rc8`; it emits no commit field. [Engine log](linux-engine.log) retains the existing estimated-inertia warning and contains no engine errors. This qualifies the downloaded Linux pack's headless execution, not native GUI, radio or physical handling.

Main's download links now point to the verified rc8 release. The frozen tag and published packages are unchanged by this evidence/documentation promotion.
