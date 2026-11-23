# V2-SCRIPT-07 / V2-IMPL-04 — Director's revision and source audit

**Date:** 22 November 2026. **Branch:** `docs/trailer-v2-preproduction-2026-11-21`.
**Input branch head:** `fd2eb1f31b4df31571aed35d8a31df7006c97ce6`.
**Game-source baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e`; no `app/` changes between that baseline and the input head, or in this revision. The R7 numeric plan pins 40 game-source files by SHA-256.
**Scope:** current script, source capabilities, proposed staging/cameras, titles, capture-tool contracts and documentation. This is not a playback audit of a newly completed trailer. No R7 game footage, imported source collection, soundtrack or target-host measurement was produced.

## Outcome

The current package is **R7, A SKY WITHIN REACH**: [script](cinematic-script-r7.md), [numeric plan](shot-plan-r7.json), [storyboard](storyboard-r7.md), [title plan](title-plan-r7.json) and [direction/continuity sheet](direction-and-continuity.md). The index names one active set. R2–R6 retain their historical instructions and evidence under their original paths; their times are not current production instructions.

The edit remains **150 seconds / 9,000 frames / 62 stable R4-prefixed IDs**. Every cut retains its previous duration, cast and source class. Allocation remains **112 s G + 15 s U + 18 s P + 5 s E**. The internal coverage still includes all 13 reviewed Home roster/configuration entries. The revision changes how the ideas connect, rather than adding an unbudgeted feature montage.

## 1. Editorial changes and reasons

| Decision | R7 result | Why it improves the intended film |
| --- | --- | --- |
| Give the opening aircraft enough screen presence. | Parallel eyes for Vantage and Electric Stick; retain their actual native-speed passes. | The old fixed-eye jet geometry put the nominal endpoints about 60 m away. The new nominal range is about 10.9 m, with an upright horizon and full silhouette as acceptance targets. |
| Put rotor inspection and flight together before the Corsair details. | HX-700 39–43 s, separate X-Cell 43–47 s, Corsair 47–59 s. | The viewer first understands a mechanism, then sees a clearly different playable helicopter; grounded fixed-wing details form their own coherent passage. |
| Make experimentation lead into the beauty section. | Lab 73–80 s, scale 80–89 s; AI/panorama/weather/Extra 89–105 s. | Tuning and scale no longer interrupt the later transition from warm flight into the signature images. |
| Preserve the requested hero passage. | Corsair orbit 105–115 s; lake 115–121 s; Bisonte shore 121–126 s. | All13 stock skins and the full six-second lake remain. The truck inherits a visual water/shore motif in a separately prepared sunset session. |
| Give the final flight a clear identity. | Creator/imports 126–141 s; labelled Turbo Lumber 141–145 s; invitation 145–150 s. | The night image now resolves the film. Its identity label prevents it being mistaken for the preceding imported trial. |
| Match the final import preview and trial orientation. | Proposed trial camera changes from rear-left to rear-right FRU(−7,+4,+2). | Both accepted images should show a nose-right model; no mirroring of markings, controls or scenery. |
| Make the tiny model readable without a false scale comparison. | Closer proposed 10% camera, plus retained field reference and size disclosure. | Giant and tiny flight shots may use different framing. Only the labelled same-depth comparator implies direct apparent-size comparison. |
| Keep reading subordinate to action. | Three main headlines; functional type increases from 38 to 52 px at 1080p; no added lake title. | Longer qualifications get more readable type, while the signature image remains unobstructed. Real-background and phone acceptance remain open. |

The [edit map](diagrams/r7-edit-map.svg) is generated from chapter frames. Its bar lengths are exact planned durations; its color swatches are creative references, not measurements of the game's output. Every shot now specifies projected direction, axis reasoning, the actual next cut and its transition type.

## 2. Source findings that changed the plan

### Lighting exists, but the routes matter

The field-world source provides dawn, sunrise, morning, noon, afternoon, golden hour, sunset, blue hour, moon-view night and dark-night/moonrise variants. Morning and afternoon are direct presets even though the Home cycle does not expose them. Legacy Day is the fixed 45° sun, not a named `PRESETS.day` value. The [direction sheet](direction-and-continuity.md#3-the-lighting-script-and-the-source-api) maps the actual arguments and source defaults.

A source review found that an inherited `OPENRC_TIME` clock takes priority over a named preset. Every R7 field-world argument set now begins with an explicit empty `--time=`. Fixed Day also uses `--time_of_day=` and a fresh direct session with empty `session_preset`. Date/location environment variables must be cleared for the source reference or deliberately recorded. A focused test uses the real resolver to reproduce the precedence and check the corrected invocation.

`--time_scale=0` freezes the sky clock; the world still adapts exposure. The calibrated Phoenix panorama carries its own photographic light. Creator UI is an explicit break before the separate daylight imported trial. The final night take needs a readable body as well as lights; blue hour is a declared alternate, not an unrecorded substitution.

### The lake camera needed a different aim

The source mean-water plane is D+0.45, while the nominal Corsair CG is D−2.55. A CG-centered view can exclude the lower reflection. The new target uses the actual presented CG's north/east projected onto the pinned water plane, with eye N145/D−1/E=CG east−8 and vertical FOV 34°. Actual CG and aim are separate evidence fields.

The source shoreline leaves only about 74.18 m / 3.225 s of the proposed six-second corridor over water at nominal 23 m/s. The script therefore describes approach, crossing and exit. A moving-aircraft mirror requires the active High planar path and non-headless Forward+; the default cubemap excludes it. No geometry calculation or camera test qualifies a reflection, trajectory or clearance.

An inherited low-sun risk remains: the glare consumer can run before the later trailer camera, unlike the planar-reflection consumer. Real golden/sunset footage must be checked for inconsistent glare/afterimages. No game runtime repair is claimed in R7.

### Do not advertise an adapter the harness cannot execute

The independent reviewer caught two proposed routes that needed correction. First, a real 10% Workshop trial has a `workshop-<hash>` runtime model ID; the current camera guard correctly requires its stock model ID. R4-36/37 are now explicitly marked as Workshop trials, the camera exporter refuses them, and R4-37's close geometry remains a proposal awaiting a separately qualified composition route. The stock identity guard was not weakened.

Second, the MONSTER CAR 2 jump harness rejects time/sky arguments, defaults to classic sky and has a 46° orbit. The planned R4-02 morning/clear/42° composition now names that harness as a reference only and requires manual or adapted capture. The five-second Bisonte shore, stopped HX-700 schedule, X-Cell ground preparation, configured failure practice and source-identified imports likewise retain their real route requirements. Generic world arguments are not universal harness options.

The existing Lumber camera was corrected in the plan to its actual visual-model-root geometry: FRU forward 5.4→4.5, right 2.2→1.8, up 0.1; look 0.4 above the root, FOV 33°. Its source-clock phase must be aligned to the retained edit window. `night_radian` uses an admitted lighting/customization route and is not a factory paint scheme.

## 3. Bounded implementation

`shot_plan.py` now validates R7 chapters, next-cut links, selected source presets, protected time arguments, the orbit/lake environment match and the final-preview/trial identity and direction. It binds a water-plane aim to the pinned lake source and refuses Workshop-trial camera exports. Generated cards, cut tables, maps and the three executable recipes stay tied to the same plan. Legacy R5/R6 remain explicitly selectable and valid.

`planned_camera.gd` retains `fixed_world` and `parallel_east`, adds `presented_cg_water_plane`, and makes FOV vertical through `KEEP_HEIGHT`. It records actual CG, independent aim, requested/actual eye, quaternion, projection, FOV and plan identity. Live checks reject altered poses, cameras and invalid projection/offsets.

Independent review also identified that an unchanged CG could allow an old camera record to look current. Successful applications now record the actual engine process frame and live simulation tick; the post-draw capture guard checks those against the session/director record. A real SceneTree fixture advances engine frames, a stub session tick and a director callback with stationary CG, disables/re-enables the adapter, and checks rejection/recovery. The exact rendered post-draw path remains an explicit qualification limit below.

`title_plan.py` and `assemble.py` bind R7's 23 cues to the reordered timeline and reject mixed current/legacy plans. R6's original windows and 36–40 px label contract remain separate. R7 requires 48–56 px functional type and includes the new 141–145 s Lumber identity. The lake interval 6900–7260 contains no title. The final trial still requires its actual estimated/donor basis for publication; passing layout validation is not publication acceptance.

## 4. Applied skills and primary inspiration

The director, continuity, edit-review, camera-cinematography, color-script, shot-list and cut-list skills were read and applied. Useful procedures were: identify the story before choosing lenses, assign one purpose per camera, record start/middle/end composition, carry source identity through cuts, and keep a planned timeline separate from recorded source in/out. Two original OpenRC skills and their mirrored copies now find the active revision through the index and no longer advertise an unexposed fixed-wing closeup player mode. Vendored upstream skills and licenses are unchanged.

| Primary reference, reviewed 22 November 2026 | Principle used | Concrete R7 application |
| --- | --- | --- |
| [Steamworks — Trailers](https://partner.steamgames.com/doc/store/trailer?l=english) | Show representative play promptly and consider viewers who watch without audio. | Visible action in the opening, genuine useful HUD, identifiable vehicle/goal/outcome. This is relevant marketing guidance, not a claim that Steam publication is planned. |
| [Derek Lieu — How to Think About Pacing in a Trailer](https://www.derek-lieu.com/blog/2020/11/16/how-to-think-about-pacing-in-a-trailer) | Sections communicate successive ideas; pacing includes time to breathe. His Spiritfarer analysis is an editorial example. | Purposeful chapters, a resolved recovery/practice sequence, protected orbit/lake breathing room and a distinct import burst. No copying of that film's footage or timing. |
| [Derek Lieu — Pull the Audience in With Match Cuts](https://www.derek-lieu.com/blog/2018/5/13/pulling-the-audience-in-with-match-cuts) | Action and visual continuity can pull attention into the next shot. | Match orientation/shape for orbit→lake and last preview→trial, plus a shoreline motif into the truck. Do not disguise unrelated takes as the same recorded action. |
| [ASC / Jay Holben — Analyzing a Script](https://theasc.com/post/shot-craft/analyzing-a-script/) | Emotional/story beats motivate camera, lighting and coverage choices; an overhead plan serves a different purpose from a storyboard. | A purpose for each chapter/camera, explicit lighting sessions, a measured edit map and separate geographic blocking map. |
| [Adobe — Continuity Editing](https://www.adobe.com/creativecloud/video/hub/ideas/what-is-continuity-editing-in-film.html) | Maintain spatial comprehension and deliberate transitions. | Per-shot axis notes, honest context resets and proposed sound bridges. Real-motion acceptance is still required. |

These are creative applications, not measured claims that this edit will convert more players. The prior GitHub/Reddit research and selected skill provenance remain in the [research ledger](research-ai-video-skills-2026-11-21.md). No new framework or video-generation dependency was needed for this revision.

## 5. Actual verification and limits

The compact [software-check record](review/r7/software-checks.json) identifies checked inputs, commands, results and retained log hashes. Tests used Linux x86-64 and the pinned **Godot 4.8 beta 2** (`4.8.beta2.official.cafc17a19`) executable; SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.

| Check actually performed | Result | Scope |
| --- | --- | --- |
| Six Python suites: shot-plan, camera recipe, cinema type, legacy title plan, cinema assembly and R7 direction | **60 tests passed.** | Includes exact cut preservation, source hashes, invalid time/plane rejection, mixed-revision rejection, Workshop export refusal, generated artifacts and a real synthetic two-cut caption encode. No simulator footage. |
| Focused real SceneTree/Camera3D fixture, real adapter and exported lake recipe | **230 checks, 0 failures; 0 engine errors/warnings.** | Minimal project, stub flight owner/director, real engine processing. Tests CG/aim separation, camera-only mutation, rejected stale records at stationary CG and actual recipe-byte hash. No aircraft or rendered scene. |
| Actual `Conditions.resolve()` with its real ephemeris/lunar sources | **18 checks, 0 failures; 0 engine errors/warnings.** | Clock precedence, explicit blank override, frozen scale, preset solar elevations and fresh-session Day behavior. No exposure or sky pixels. |
| `capture_flight.gd --check-only` with prepared real production dependencies | **Passed; 0 engine errors/warnings.** | The 842 app scripts in that prepared fixture matched the checkout; the two changed capture sources were refreshed. This is compile/load coverage, not startup or flight. |
| Direct parse in the sparse working project | **Failed due to missing imported texture/audio resources.** | Not hidden as a pass. The prepared dependency fixture above resolves that particular parse check without stubbing Main. No engine capture is claimed. |
| Optional bounded `--check-post-draw` fixture in headless mode | **Not qualified:** the route emitted no `frame_post_draw`; 232 checks with 1 failure. | The probe completed rather than hanging. No display/Xvfb was available. Run it on an actual rendering route and then check real capture before accepting post-draw evidence. The headless 230-check pass does not close this gate. |
| R7 typography study | **1920×1080, 60 fps, 1,365 frames, 22.750 s; full FFmpeg decode passed.** | Synthetic neutral background with permanent “NO GAME FOOTAGE” marking. All three main-title animations, representative labels, Lumber and full end card are sampled. Trial binding remains unresolved. |
| Visual inspection | Edit map and typography contact inspected; actual encoded HX-700, Phoenix and end-card frames inspected at 480×270. | No clipped map labels or text overlap observed in these samples. Neutral-background readability does not establish full-motion legibility over gameplay or review every final cue. |

The typography provenance records Pillow 13.0.0, FreeType 2.14.3, raqm 0.11.0, FFmpeg/ffprobe 7.1.5 and exact font/license hashes. The [22.75-second study](review/r7/typography-study.mp4), [contact](review/r7/typography-contact.jpg) and [summary](review/r7/study-summary.json) are retained as a small review set. Historical R6 and text-window studies remain unchanged.

## 6. Independent review and closure

Three helpers supplied editorial/source-camera/inspiration work with separate write scopes. The lead selected the final order, integrated the plans and tools, read the accepted diffs, ran all software/media checks and reviewed the generated visuals. A separate source-only Good Enemy reviewed the integrated code/plan without authoring it. Its three route/environment findings were corrected as described above; its earlier stale-record finding produced the freshness checks. No helper claimed to have run an engine or reviewed newly filmed gameplay.

The following remain production work: real inverted/banked opener; complete truck landing under the chosen settings; actual rotor and grounded controls; recovery and failure-practice outcomes; Workshop camera composition; exact imported source and last-trial identity; settled exposure and low-sun glare; genuine lake reflection and clearance; readable night body; source audio/music and rights; title/HUD clearance on real frames; Windows/RTX3090 renderer/performance; final website/download flow; full-film export and viewing. The `300+` claim and optional text-window transition remain outside the active master.

The [verification gates](verification-gates.md) and [direction sheet](direction-and-continuity.md) carry those requirements into capture. This revision completes the reorganization and source-grounded production specification; it does not relabel pending footage as a finished trailer.
