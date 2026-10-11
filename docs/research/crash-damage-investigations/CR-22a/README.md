# CR-22a — Integrated crash presentation

2026-10-11 · **Status: implemented; native qualification and 193 isolated GDScript regressions passed.** A single clean repository-wide run is not claimed; snapshot caveats are recorded below. Includes CR-03a and CR-19a visual evidence. Physical damage and Gate CR remain open.

## Behavior and boundary

Interactive flight reads the existing immutable CR-01 impact snapshot, estimates severity, hides the source airplane and animates a disposable copy. The original float64 flight checkpoint remains frozen. No wreck transform, particle, sound, debris contact or damage estimate writes into flight dynamics. Trace, scripted and capture routes keep their previous behavior; `-- --crash-effects=off` restores the previous timed-restart presentation.

The [estimator](../CR-08a/severity.md) combines total mass, normal/tangential contact speed, impact angle, surface transfer and component exposure. Hull components are geometric region estimates. Gear overtravel uses a marked CG-speed proxy because deforming gear-point velocity is unavailable. Crossing position is available for the picture; speed remains detected-tick kinematics.

The [wreck](../CR-09a/README.md) reuses each aircraft's real meshes and preserves its source hierarchy/hinges. C0–C2 remain one body; C3/C4 detach recognizable sections. Accepted C3 core contacts accumulate a separate exposure index and can release one remaining propeller, gear, canopy or engine group per contact at provisional 4/12/25/50 J index thresholds. Deferred releases transfer estimated mass from the core, inherit current point velocity and add no scatter energy. CCD bodies bounce, emit secondary-contact cues and sleep. The aftermath stays until explicit restart. The pilot camera remains at its station; C switches to a fixed inspection view. There is no synthetic camera shake.

Dust, sparks, splinters, gouges/scorches and smoke use a bounded pool. Fire requires a hot running turbine, positive declared kerosene inventory and an estimated ruptured tank. The rupture heuristic is C4, or a C3 central (engine/fuselage) impact with at least 600 estimated J; this is **not** a tank-strength measurement. A wing hit alone does not rupture a tank. Fire lasts at most 50 seconds, estimated as declared fuel / 0.035 kg/s. Its light and audio fade over the final three seconds; flame/smoke emission stops at fuel-budget expiry and existing particles drain over their lifetimes. Those rate/duration values are presentation estimates. The Avanti inventory supplies 1.28 kg; flight consumption is not simulated. Smoke and flames drift with the existing wind. One unshadowed light flickers while burning.

[Crash audio](../CR-02a/README.md) layers spatial impacts, cracking, tearing, short scrape tails, engine/turbine rundown, debris hits and fire on its own limited bus. Primary cues fire once. Secondary contacts are rate-limited; voice stealing is bounded. User/menu pause freezes the wreck/effects and pauses/mutes crash audio; the terminal crash hold allows the aftermath to continue.

## Budget and reproduction

Qualification uses pinned Godot 4.7.2, Windows WASAPI and OpenGL Compatibility, at 1280×720. Native scenarios cap rendering at 60 FPS and measure wall intervals including cap/vsync wait. These are host measurements, not broad hardware acceptance. Limits established before final qualification:

| Item | Limit |
| --- | ---: |
| Native full-scene frame p95 | 33.3 ms |
| Director/effects script update p95 | 1.5 ms |
| Impact setup | 10 ms |
| First impact frame wall interval | 50 ms |
| Wreck bodies / lightweight splinters | 24 / 160 |
| Particles / ground marks / lights | 700 / 16 / 1 unshadowed |
| Crash audio voices | 8 |
| Combined Master peak | −1 dBFS, linear tolerance 0.00001 for float32 filter roundoff |

The implementation allocates 556 particles and 24 body/contact-shadow slots before flight. Active section counts depend on the model. Splinters settle and stop updating after 12 seconds. Marks recycle secondary slots while preserving the primary scorch. No pool grows with successive crashes.

From the repository root:

```powershell
python research/crash-damage/cr-22a/qualify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out .tools/crash-qualification
python research/crash-damage/cr-02a/generate_assets.py --verify
```

`qualify.py` runs severity/effects/wreck/audio/production integration/legacy-pose checks, then real rendered and audible Ugly Stik/Avanti descending crashes, a low-speed runway scrape and a banked wing contact. It fails on engine errors, budget violations, missing screenshots, missing/clipped/dropped audio, state mutation or reset failure, and records source hashes. The two descending starts fly through the production 240 Hz solver; scrape/wing contacts are manufactured detector intervals and are labeled accordingly. Neither is a measured physical drop test.

`trace_parity.py --godot <engine> --baseline <pre-change-app> --out <folder>` compares three-second healthy traces for all four aircraft. It excludes only volatile `created_utc`; all remaining metadata, columns and numerical rows must match. The pre-change snapshot is captured before editing; do not recreate it from the candidate.

## Evidence

[Qualification manifest](evidence/qualification.json) records **passed=true**, stable source hashes and no engine errors for the following runs:

| Check | Result |
| --- | --- |
| Severity / effects / wreck focused checks | 44 / 56 / 135 passed |
| Crash audio, Dummy setup/lifecycle | 12 passed; real playback intentionally disabled |
| Four-aircraft production integration | 76 Dummy + 84 native checks passed |
| Later shared-tree integration | 84 native checks passed again after other tracks changed Main/session ([log](evidence/integration-current.log)); [source hashes collected after that run](evidence/integration-current-source-after-run.json) |
| Original CR-01 pose/timer fixture | 84 passed with effects disabled |
| Pause/Continue/Restart/End and runway menus | Both production UI tests passed; five Home/flight cycles retained the same node count |
| Healthy flight | All four 3-second traces identical except creation UTC; [hashes](evidence/trace-parity.json), [raw traces/logs](evidence/healthy-traces.zip) |
| Native crash-bus focused capture | 18 checks, −1.25 dBFS peak; [CR-02a](../CR-02a/README.md) |
| Exported resource availability | Clean disposable Git clone imported and exported; all 18 crash resources/notices loaded from the PCK ([check](evidence/clean-pack-check.log)) |

Native measurements on an **NVIDIA GeForce RTX 3090**, Godot **4.7.2**, Compatibility, 1280×720, 60 FPS cap, 579 sampled frame intervals per case:

| Scenario | Outcome / bodies | Frame p95 | First impact frame | Setup | Director update p95 |
| --- | --- | ---: | ---: | ---: | ---: |
| [Ugly Stik flown nose-in](evidence/ugly-flown.json), 22.94 m/s | C3 / 8 | 17.002 ms | 25.222 ms | 1.269 ms | 0.092 ms |
| [Avanti flown nose-in](evidence/jet-flown.json), 40.85 m/s | C4 / 6, fire | 16.884 ms | 34.555 ms | 0.950 ms | 0.109 ms |
| [Runway scrape](evidence/scrape.json), 2.86 m/s | C1 / 1, no breakup | 16.876 ms | 23.924 ms | 1.066 ms | 0.053 ms |
| [Banked wing contact](evidence/wingtip.json), 21.84 m/s | C3 / 8 | 16.919 ms | 35.649 ms | 1.097 ms | 0.102 ms |

Every active body was sleeping at the approximately eight-second observation. The C3 runs recorded later contact-driven releases; C1 retained the whole aircraft. Combined Master captures peaked at approximately **−1.000 dBFS**, within the stated float32 tolerance, with **zero dropped frames** and audible sample energy in all four captures. Native playback resources exited cleanly. The Dummy production fixture can still report pre-existing flight-audio ObjectDB warnings, but no crash-resource errors.

Selected untouched engine captures: [Ugly breakup](evidence/ugly-flown-090.png), [Ugly aftermath](evidence/ugly-flown-480.png), [jet impact](evidence/jet-flown-090.png), [jet fire/aftermath](evidence/jet-flown-480.png). Native mix recordings: [Ugly](evidence/ugly-flown-master.wav), [jet](evidence/jet-flown-master.wav). These were measured, not human listening-approved.

The host had concurrent development activity. The first impact is first use **within each process**, with the existing driver shader cache; a cleared driver cache and lower-end hardware are not qualified. PNG readback occurs after the first crash and can affect later upper frame-time tails. Source/render/audio checks establish bounded software behavior, not owner listening acceptance or structural realism.

The broader regression used the [pre-change runner](evidence/existing-contract-runner.sh), placed inside an isolated candidate's `app/` on the local Linux filesystem, with separate user settings. Every one of its **193 `test_*.gd` files** passed on its final attempt, including all new crash tests. Float64 guards, all-script parsing, golden sensitivity, four model contracts, trace/CLI/weather/time/shaft checks and all four trimmed flights passed. Real-app, wash-transport and swirl hashes were identical at **30/60/144 FPS**. Logs retain the successive phases: [initial](evidence/crash-existing-contract-suite.log), [keyboard-test continuation](evidence/crash-existing-contract-rest.log), [Git-identity continuation](evidence/crash-existing-contract-end.log), [frame-rate continuation](evidence/crash-existing-contract-final.log). [App source hashes](evidence/regression-app-source-sha256.json) and [two later source corrections](evidence/regression-continuation-sha256.json) identify the candidate; text copied into Linux had CRLF normalized to LF.

This was **not one clean full-suite pass**. The keyboard test initially expected automatic crash restart and was corrected for the new explicit-R contract. The disposable Git fixture initially lacked a commit, causing a build-identity assertion; creating a commit in that fixture fixed it without changing production code. Companion generators copied during concurrent development did not match the frozen Avanti/Extra generated files, so their freshness gates stopped the broad run. Both checks pass in the newer shared tree: [Avanti](evidence/crash-avanti-generation-current.log), [Extra](evidence/crash-extra-generation-current.log). No aircraft data was regenerated or replaced by this task to silence those failures.

The remaining E5a programs passed directly against the frozen app: [21 contact checks](evidence/crash-e5a-checks.log) and [63 session/throttle checks](evidence/crash-e5a-session.log). E5b's full verifier passed **125 checks** with stable input hashes ([report](evidence/e5b-verification.json), [log](evidence/e5b-full.log)). [Archived continuation runners](evidence/regression-runners.zip) show exactly which earlier sections were retained rather than repeated.

The initial pre-change run timed out in `test_input_report_cli.gd` on the Windows-mounted WSL filesystem ([log](evidence/crash-baseline-suite.log)); the local-Linux candidate passed it. A concurrent AS-01/02 preflight initially rejected `--check` ([log](evidence/working-tree-suite.log)); its owner subsequently fixed it and the [recheck passed](evidence/schema-preflight-recheck.log). The current shared tree continues to change, so the results qualify their recorded sources rather than every other track's later edits. The final provenance-label-only director correction is covered by native qualification.

## Assets and compatibility

- [Kenney Smoke Particles](https://kenney.nl/assets/smoke-particles): two unchanged PNGs (`whitePuff00`, `explosion00`), **CC0 1.0**. The downloaded archive's included license was checked. Archive and file SHA-256, URLs and license copy are in [sources.json](../../../../app/assets/crash/sources.json) and [LICENSE-Kenney.txt](../../../../app/assets/crash/LICENSE-Kenney.txt). [Fetcher](../../../../research/crash-damage/cr-22a/fetch_assets.py) pins the archive hash before extraction. Actual CPUParticles3D/StandardMaterial3D rendering verifies Compatibility support on the pinned engine.
- Twelve original offline synthesized mono 22,050 Hz PCM WAVs, **MIT**: [manifest](../../../../app/assets/audio/crash/sources.json), [license](../../../../app/assets/audio/crash/LICENSE.txt), [reproducible generator](../../../../research/crash-damage/cr-02a/generate_assets.py). No downloaded audio is shipped. [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) was researched as a CC0 alternative.
- All three export presets explicitly include the crash manifests and license notices. `clean_pack.py --godot <engine>` verifies a fresh disposable clone, empty import cache and real PCK resource loads; this is a resource-pack check, not a signed installer or platform-executable acceptance.
- Engine references: [CPUParticles3D](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html), [RigidBody3D](https://docs.godotengine.org/en/4.7/classes/class_rigidbody3d.html), [AudioStreamPlayer3D](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer3d.html), [AudioEffectHardLimiter](https://docs.godotengine.org/en/4.7/classes/class_audioeffecthardlimiter.html). Pinned-engine tests, rather than current tutorials alone, establish compatibility.

## Limits

- C0–C2 are severity/presentation classes, **not flyable damage**. Existing hull/gear-limit contacts still end the flight. Ordinary safe wheel contacts keep existing physics and do not trigger crash effects.
- Material/joint strengths, local participating mass, tank rupture, fragment mass shares and restitution are uncalibrated estimates. No damaged lift, mass, inertia, prop-strike model or in-flight fatigue is introduced.
- Progressive wreck separation is downstream presentation. It is not replayable structural state and does not complete H8/G4b or the physical CR-B/CR-C contracts.
- Ground damage is a flat textured mark, not terrain excavation. No terrain slopes, tree collisions, fence collisions or landscape deformation are added. Avanti has no separate turbine-casing group in its model.
- Fire is an estimated fuel-fed presentation; no dynamic tank/ECU/fuel-burn or LiPo thermal model exists. Fire remains at the estimated spill point, rather than following every fragment.
- Audio is authored synthesis, not an acoustic measurement. Scraping is a short contact layer, not a contact-force-driven loop; speed-of-sound propagation and human listening acceptance remain open.
- No crash replay, full localization, durability UI or physical realism acceptance is claimed. The retained ordinary-flight data warnings are unrelated to crash effects.

## Review and reusable findings

Three Luna/max agents owned severity, wreck and audio under [non-overlapping assignments](../CR-09a/coordination.md). The lead reviewed source and contracts, normalized secondary joules into bounded mix intensity, corrected mesh visibility/CG inheritance/scatter energy, exercised the combined scene and retained source-flight parity. Other developers' dirty files were preserved; no cross-track commit or revert was made.

Godot Dummy playback retained WAV playback resources despite stopping/freeing voices; isolated native WASAPI exited cleanly. Crash audio now skips actual playback on Dummy, while native tests retain playback/mix assertions. A guard around `stream_paused` is required when a voice has no playback. Particle `restart()` is necessary when reusing the pool to avoid showing old particles at the next crash. The source shadow must be hidden every frame after Main refreshes it. Vertical speed must not lengthen a horizontal ground mark. PNG encoding before a descending collision contaminated one first-impact timing interval; the qualification captures now begin after that collision. These observed lifecycle and measurement failures are separate from physics correctness.
