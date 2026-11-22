# Trailer 2.0 — R6 directing and implementation audit

**Date:** 22 November 2026. **Track:** V2-SCRIPT-06 / V2-IMPL-02 / V2-IMPL-03 / V2-REVIEW-06.
**Branch:** `docs/trailer-v2-preproduction-2026-11-21`; parent `f7cf8a13673d8b4243418ab2d9804e40ee6b8f94`.
**Game-source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`; all 32 R5 source pins retained.

## Outcome and scope

R6 makes the direction executable in two focused areas: global-frame cinematic titles and a composed flight-camera adapter. The [current shooting script](cinematic-script-r6.md), [numeric plan](shot-plan-r6.json), [title plan](title-plan-r6.json), [storyboard](storyboard-150s.md) and support documents agree on the same **62 cuts / 9,000 frames / 150 seconds**. The source-class totals remain **112 G + 15 U + 18 P + 5 E**. No simulator, physics, aircraft-data or app-runtime files were changed.

The [18.75-second typography study](review/r6/typography-study.mp4) is a real encoded graphics preview with a permanent **TYPOGRAPHY STUDY · NO GAME FOOTAGE** caption. Its [contact sheet](review/r6/typography-contact.jpg), [input/output summary](review/r6/study-summary.json) and [compact software evidence](review/r6/software-checks.json) are retained. No real gameplay take, imported-model batch, target-host capture, soundtrack or finished 150-second trailer is accepted by this audit.

## Creative changes

| Decision | R6 treatment | Reason |
| --- | --- | --- |
| Main copy | A SKY WITHIN REACH 14.25–17.50 s; FEEL EVERY INPUT 60.25–64.75 s; EXPAND YOUR HANGAR 125–127 s | Three story beats leave more room for aircraft, mechanisms and outcomes. |
| Typography | Vendored Barlow Condensed; warm white #F2EFE7; modest tracking and shadow | A quieter film treatment, consistent with a simulator whose pictures must remain readable. |
| Animation | 18-frame entrance / 12-frame exit; Creator 8/8; at most 8 px settling | The short Creator insert retains a useful settled reading interval. |
| Functional copy | Fully opaque throughout the relevant shot/block | Inspection, presentation, source and trial qualifications do not disappear at cut boundaries. |
| Corsair | Full 10 s / 13 skins, then 6 s lake; final Three Tone retained | Preserves the requested signature sequence and paint continuity. |
| Lake | Parallel north-bank tracking; no added title | Holds the Corsair legibly while the shore/background moves. |
| Imports | 2 s Creator, 18 previews in 10 s, 3 s same-last-model eligible trial | Preserves breadth and a clear distinction between preview and flight. |
| End card | Product name, PLAY FREE, destination; all 300 frames settled | Removes inherited beta/slogan/music/description claims from the new film. |

The large RACE THE GATES, TAKE CONTROL, TUNE YOUR SETUP and MAKE IT YOURS slogans are removed from the active title plan. Actual mode, arming, recovery, alert and telemetry indicators remain footage requirements. The numerical **300+** variant remains inactive. Main title placement is authored, not accepted against actual footage; safe-area validation alone cannot detect a hidden aircraft or obstructed HUD.

The model-attached **7.62 m / 1.52 m / 15 cm** comparison labels remain a separate qualified source/tracked-layout requirement. R6 implements only the static **CINEMATIC SIZE COMPARISON** disclosure. The new cinema mode does not silently reuse the old crystal callouts.

## Camera and blocking corrections

The old R4-40 fixed eye at N145/E125/D−1 would pan approximately **152°** over the nominal N128/E55→193 pass. For the horizontal planning geometry, the peak rate is `23/17 rad/s`, approximately **77.5°/s**. These estimates assume the proposed straight path at constant 23 m/s; they are not measurements from a take.

The new rig keeps N145 and D−1, with east equal to actual displayed CG east minus 8 m. At the nominal 0/3/6-second subject marks the camera eyes are **(145,47,−1), (145,116,−1), (145,185,−1)**, at FOV 42°. The subject stays near frame center and its nose points screen-left; the background supplies the lateral motion. The [generated map](diagrams/r6-lake-blocking.svg) was rasterized and inspected. It shows the true pinned shoreline with proposed marks, not a recorded trajectory.

The subject corridor remains N128/E55→124→193/D−2.55. Its horizontal water chord is **74.1818 m**, approximately **3.2253 s** at nominal 23 m/s, inside the six-second approach/crossing/exit. The camera's low nominal eye is 1.45 m above mean water, but shore/terrain support and the actual path remain unverified. Source anchors are in [the lake data](../../../app/data/fields/lake.json); the [plan tool](../../../tools/trailer/shot_plan.py) calculates the intersection.

R4-01/03 exit language now means passing a world mark while the camera tracks CG. R4-04/05 similarly distinguish world travel and nose orientation from image translation. A camera cannot simultaneously center CG and demand that the same aircraft leave the frame edge. The existing R4-39 orbit retains its **visual-model-root** anchor; the new flight adapter uses **presented CG**.

Three current recipe files are ready for rehearsal setup: [R4-01 Vantage](recipes/r4-01-camera.json), [R4-03 Electric Stick](recipes/r4-03-camera.json) and [R4-40 lake](recipes/r4-40-camera.json). They contain the exact R6 plan digest and camera settings only. They cannot spawn, steer, set skin, establish a flight path or qualify a take.

## Code delivered

| Path | Implemented behavior |
| --- | --- |
| [shot_plan.py](../../../tools/trailer/shot_plan.py) | Defaults to R6; preserves R5 validation; generates readable cards; requires R6 script/card agreement; exports camera-only recipes from one parsed byte snapshot; checks parallel rig marks against its law. |
| [planned_camera.gd](../../../tools/trailer/planned_camera.gd) | Fixed-world and parallel-east eyes, actual displayed CG, bounded recipe/optical validation, sticky failures and camera readback. Runs at priority 20 after the existing director. |
| [capture_flight.gd](../../../tools/trailer/capture_flight.gd) | Adds the camera without replacing pilot ownership; verifies matching loaded aircraft/Club scene; rejects interrupted state and retains per-frame camera evidence. |
| [cinema_titles.py](../../../tools/trailer/cinema_titles.py) | Verified vendored assets, pair-aware letter spacing, measured visible ink, safe-area/collision/glyph checks and global-frame transparent PNG plates. |
| [title_plan.py](../../../tools/trailer/title_plan.py) | Exact R6 cue/coverage checks, trial-basis binding, matching timeline anchors and a reproducible synthetic study. |
| [assemble.py](../../../tools/trailer/assemble.py) | Opt-in cinema mode; exact 62-cut binding; global-time overlays; new end card; explicit new export copy; dependency/content/output-aware cache and per-clip frame-count checks. |

The camera recipe must be a single absolute UTF-8 JSON path, 1–65,536 bytes, with supported schema, finite values and a matching flyable fixed-wing catalog/loaded model. Capture rejects real-time frametimes, lighting-pilot and crash shots, non-Club scenes and external/non-physics sessions. It requires at least two source frames. The selected pilot director must append one current frame/tick record. Pauses, faults, holds, crashes, non-advancing ticks, camera errors and changed/non-current cameras make the take incomplete.

`frame_records[].planned_camera` contains the actual eye, quaternion, FOV and displayed target. Top-level camera evidence retains exact recipe content/hash and script hash. `source_plan_sha256_claimed` is honestly named: capture does not separately read the plan bytes. The exporter binds its recipe to the parsed plan snapshot; take admission must retain and compare that plan.

The cinema assembler checks actual source-frame content instead of trusting a placeholder description of a capture manifest. Cache inputs include master start frame, parsed title/shot plans, font/license/provenance, rasterizer/encoder versions and source media. Cached video and audio must still match their output hashes. The previous receipt is removed before re-encoding, so an interrupted attempt cannot inherit a stale success. Missing sources, image frames or audio are reported as awaiting in preparation mode. Temporary title sequences are removed after encoding.

## Independent review and corrections

A separate reviewer examined the code without authoring it. The review identified and the lead fixed these material issues before delivery:

- Plan parsing and hashing had separate reads; they now share one byte snapshot.
- R6 could omit its script path and bypass card agreement; that path is now required.
- A partially overwritten encode could inherit an old cache fingerprint; receipts now verify both output hashes and are invalidated first.
- Missing image frames/audio aborted preparation; preparation now defers those cuts while final rendering still fails on missing input.
- Repeated preparation left title PNG directories behind; each encode now cleans its temporary sequence.
- Graphics-only output could still select the legacy card; a cinema manifest now gets the R6 card.
- Remaining fixed-camera wording implied screen translation; world marks and nose orientation now state the intended behavior.

The final source review reported no remaining critical or high-severity blocker. Its remaining production findings—model-attached comparator labels, capture plan-hash claims and real-footage readability—are explicitly retained here and in the gates. Source review is not runtime footage acceptance.

## Verification results

The [software evidence](review/r6/software-checks.json) records final source hashes, compact checked-runner results and log digests. Raw logs, imported caches and temporary projects remain outside Git.

| Check | Result | What it establishes |
| --- | --- | --- |
| Shot-plan tests | 15 passed | Existing source/catalog/skin/timing/geometry behavior. |
| Camera export/card tests | 9 passed | Current recipe identities, supported routes, rig-mark agreement, exact snapshot hashes, generated cards and non-overwriting output. |
| Title renderer tests | 10 passed | Fade boundaries, opaque labels, global phase, kerning, safe layout, hashes and output handling. |
| Title-plan tests | 8 passed | Cue coverage, trial basis, duplicate-key/snapshot handling and a short actual FFmpeg study. |
| Cinema assembly tests | 5 passed | Exact cut contract, cache rejection, new end card, missing-input preparation and encoded adjacent-cut label continuity. |
| Combined Python run | **47 passed / 0 failed** | Stable integrated software candidate on this Linux environment, including regenerated Markdown/card agreement. |
| Camera node / composition | **163 checks / 0 failures** | Pinned Godot, real Camera3D/adapter with fake flight owner and separate director; includes three exported recipe-file/hash checks. |
| Isolated production dependency import | Passed | Actual production scripts and exact transitive preload resources imported without app stubs. |
| Final capture-harness parse | Passed; exit 0, no logged errors/warnings | Actual modified harness compiles against that imported graph. No flight was launched. |
| Full typography study | **1,125 frames / 18.75 s / 1920×1080 / 60 fps** | Probe and full decode passed; six input/output hashes matched the retained plans, generators and exports. |

Python runtime components: **Pillow 13.0.0, FreeType 2.14.3, raqm 0.11.0, FFmpeg/ffprobe 7.1.5**. The pinned engine was **Godot 4.8.beta2.official.cafc17a19**, executable SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.

No test pool was configured in this session. Godot used the existing checked local runner with isolated output/user/temp directories. The focused camera project contained exact copies of the real adapter and test script. The harness parse used an isolated, successfully imported sparse copy containing **842 production GDScripts** plus actual transitive preload files and startup metadata. It was not a full exported app package or a target GPU run.

The focused command used `tools/godot/run_checked.py --label r6-planned-camera --timeout 90 --require-text 'failures=0'`, followed by the pinned engine, `--headless --audio-driver Dummy`, the minimal project's `--path` and test `--script`, and three `--exported-recipe=` files. The harness command used the same checked runner with `--label r6-capture-parse-final-bytes --timeout 210`, the isolated app path and `--check-only --script .../capture_flight.gd`. The compact evidence preserves result and source hashes; [the tool guide](../../../tools/trailer/README.md#r6-cinematic-titles-and-camera-recipes) owns normal usage.

The lead visually inspected the final contact sheet and rasterized lake map. The study’s exact fades/cut boundaries also have software/encode checks. Actual gameplay composition, phone/mute legibility and subjective full-motion review remain open.

## Internet tool research applied

Research was checked against primary documentation on 22 November 2026. The selection below is an implementation judgment for this repository, not a universal ranking of video tools.

| Tool/source | Relevant capability | Decision for this pass |
| --- | --- | --- |
| [Pillow ImageDraw](https://pillow.readthedocs.io/en/stable/reference/ImageDraw.html) | Text length/bounds, TrueType layout and kerning-aware measurement. | Keep the existing Python renderer path; implement pair-aware tracking and measured ink rather than approximate letter widths. |
| [FFmpeg filters](https://ffmpeg.org/ffmpeg-filters.html#overlay) | Overlay composition and filter/timeline processing. | Keep FFmpeg for RGBA plates, 60-fps encoding and decode/probe checks; test actual installed behavior. |
| [Google Fonts Barlow license](https://github.com/google/fonts/blob/main/ofl/barlowcondensed/OFL.txt) | The upstream Barlow package carries SIL OFL 1.1. | Reuse the repository's pinned font bytes, provenance and license; no new font download or substitution. |
| [Blender Text Strip manual](https://docs.blender.org/manual/en/latest/video_editing/edit/montage/strips/text.html) | Font, placement, shadow and other title-strip controls described by the official indexed manual. | Keep as an optional manual finishing route. A new Blender scene is unnecessary for this small frame-addressed title increment. Full page retrieval was unavailable; no new Blender workflow was tested. |
| [Remotion API overview](https://www.remotion.dev/docs/api) | Frame/time-based components, composition, sequences and animation APIs. | A possible richer preview editor later; no React/video framework migration or license assumption is needed for the current pipeline. |

The already-selected director, continuity and edit-review skills informed this pass: one camera purpose per shot, protected hero holds, legible silhouette-based import cuts and clear separation of gameplay, UI and presentation. Their [earlier research and provenance](research-ai-video-skills-2026-11-21.md) remain intact. No new skill or upstream licensed material was modified.

## Remaining production work

First qualify a controlled Corsair mechanism take and the real livery orbit. Then rehearse the lake flight with the composed camera, recording actual clearances, source frames and reflection. The generic existing pilot commands do not establish the proposed lake corridor; any pre-tree external fixture needs a separately reviewed session/clock integration.

Imported previews and the same-model final trial still need exact source identities, texture review and admission. Bind ESTIMATED PHYSICS or DONOR PHYSICS from that accepted trial, not from a desired headline. Produce the attached size labels from actual recorded screen positions or an already-qualified labelled source. Then check every overlay against the real image, audition/credit the actual soundtrack and review the finished 150-second film on the requested host and target reading size.

The official destination returned HTTP 200 with title **OpenRC Simulator | Simulador de vuelo RC gratis** on this date; the title manifest records the response digest. This checked page availability/identity only. Browser, download, installation and runtime behavior were not tested and the destination must be rechecked before release.
