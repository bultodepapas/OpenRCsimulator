# OpenRC Simulator — cinematic trailer production plan

2026-10-17 · **Owner:** trailer/media · **Prefix:** TRA-00…08 · **Status:** planning only; no trailer footage, capture tool or runtime change delivered.

User brief: an **exactly 60-second, very cinematic, AAA-style game trailer**, entirely in **English**, showing every current vehicle, aerobatics, crashes, controls and several airplanes performing together in the spirit of an airshow. **Helicopter, both cars, electrical storms and physical wind are mandatory.** Review the complete player-facing feature inventory and select its strongest visual moments. **Prices mean the estimated accident/repair cost displayed after a crash, not the simulator's purchase price or vehicle shopping prices.** This revision replaces the longer first-cut proposal.

This is the authoritative production plan. The [dated investigation](../research/cinematic-trailer/2026-10-17.md) records source findings and research limits. Runtime facts below were checked against source commit `049df2034de017e6fedc649a55194eb5977191cd`; refresh the inventory when freezing the filming build.

## 1. Creative direction

**Working title: EVERY INPUT MATTERS.**

The minute moves through four acts: **machines (0–31 s), changing conditions and control (31–42 s), consequence (42–50 s), spectacle and title (50–60 s)**. Make the viewer feel the weight of a landing, the precision of a roll, the acceleration of a turbine and the hesitation before a costly mistake. AAA is the standard for direction, pacing, composition and sound; the vehicles, landscape and gameplay remain recognizably OpenRC. Rebuild the edit around these beats instead of speeding up the longer version.

- **Main film:** exactly 60 seconds including titles and end card, 16:9, English titles and English game UI. Target a 3840×2160/60 master if the capture pilot passes; deliver 1920×1080/60. Do not upscale existing web clips and call them native 4K.
- **Story:** “Your hands. Your machine. Your mistake. Your next attempt.” This is the internal narrative, not four mandatory title cards.
- **Image:** warm low sun and intimate mechanical details give way to dark storm clouds, a single readable lightning event and a final sunlit formation. Keep clear ground reference and restrained color grading. Use the current production models and materials; aircraft stay identifiable throughout turns.
- **Sound:** actual propeller, turbine, rotor and nitro voices carry the edit. One licensed instrumental cue builds in acts; a brief near-silence at the crash makes the repair estimate land. No narration in the first cut; the film must work without sound.
- **Typography:** small vehicle identifiers and at most three large editorial title beats: `TAKE CONTROL.`, `EVERY MISTAKE HAS A COST.`, and the end-card `EVERY INPUT MATTERS.` The actual report and cinematic label remain legible. No scrolling feature list or prolonged menu tour.
- **Composition:** foreground grass, runway markings and shadows establish RC scale. Alternate an intimate mechanical detail, a readable full maneuver and a wider environmental shot. Preserve an uninterrupted action beat before cutting to its result.

The main cut should contain at least 45 seconds of captured, actually simulated driving/flying and its UI. Reserve **7 seconds** for the clearly identified formation cinematic and **3 seconds** for the closing card. Mechanical inserts are brief; protect the 3–5 second hero actions, readable cost report and continuous formation shot.

## 2. Complete vehicle coverage

Current scope is **eight distinct vehicle visuals**: five airplane families, one playable helicopter and two trucks. There are **eleven selectable configurations** when the three additional Stik engine installations are counted. Variants must not be advertised as additional airframe designs.

| Vehicle / catalog ID | Required hero action | Capture limit and alternative |
| --- | --- | --- |
| Jensen Das Ugly Stik 60 — `jensen-das-ugly-stik-60` | Takeoff, smooth bank and smoke pass; reference aircraft for the formation | Physical handling qualification remains open. Use its configured smoke installation; test the selected route before promising a smoke maneuver. |
| Great Planes Extra 300S .60 — `gp-extra-300s-60` | One complete axial roll, framed to show entry and exit | Rehearse on the frozen build. A loop is an alternate only if it fits the slot at actual speed with a readable entry and exit. |
| P-51D Mustang 1/4 — `p51d-mustang-120` | Low banked pass; retracting gear or landing approach | Use current accepted source behavior; preserve experimental status. Do not infer the current source's gates from an older downloadable package. |
| Ventage Jet — `sebart-avanti-s-a200-p100rx` | Fast opening pass, turbine buildup, climbing bank | No configured jet smoke emitter. Its existing studio camera arc is a reference for new full-resolution inserts. |
| Turbo Lumber Evolution — `turbo-lumber-evolution` | Electric takeoff or low grass-field circuit, then a gentle landing | Fixed wheels, flaps up and assists off. Do not imply SAFE/AS3X or battery depletion. |
| RC Helicopter Research Trainer — `xcell-60-research` | Five-second hero sequence: brief rotor detail into hover/yaw and forward transition | This is the playable X-Cell/HX-700 visual surrogate. Currently one playable helicopter route exists; the advanced articulated HX-700 laboratory candidate is not an additional flyable helicopter. No invented inverted/tic-toc performance. |
| Bisonte MT8 — `mt8-bisonte` | Suspension compression, corner exit and a genuine ramp jump/landing | Use the playable RC circuit. Accept only a continuous actual takeoff/landing; substitute a grounded suspension/traction sequence if the jump does not work. |
| MONSTER CAR 2 — `monster-car-2` | Nitro acceleration, steering and braking on the circuit | Use its own sound and controls. Do not imply truck-to-aircraft collision or simultaneous shared gameplay. |
| Stik engine variants — `stik-glow-61fx-2t`, `stik-glow-55ax-2t`, `stik-glow-fs64v-4t` | Audit all three; use the actual selected installation in the Stik/engine sound shots | Same visual family. The one-minute cut covers every distinct vehicle, without three extra engine title cards. Preserve exact configuration identities in the take sheet. |

The source of aircraft identity is the [catalog](../../app/app_state/aircraft_catalog.gd); truck operation is owned by the [RC vehicle guide](../../research/rc-monster-truck/README.md). The [eight-vehicle media workflow](../media/README.md) supplies existing composition references and reusable model access.

## 3. Main storyboard — exactly 1:00

Times are edit targets, not an assertion that these shots have been captured. Prefer one hero action per slot and cuts on movement or sound; avoid rapid fragments that hide the vehicle. The letter identifies the source: **G** = actual gameplay, **S** = model/studio presentation, **C** = staged formation cinematic. At 60 fps the finished film contains exactly **3,600 frames**.

| Time | Shot and action | Camera / edit / sound | English copy and purpose |
| --- | --- | --- | --- |
| 00:00–00:04 | **G, Ventage Jet:** fast low pass into a climbing bank | Turbine heard before frame entry; close pass opens to readable RC field scale. No logo pre-roll. | Small `OpenRC Simulator` and vehicle identifier. |
| 00:04–00:08 | **G, Stik:** wheels release from the runway, bank and smoke begins | Low runway angle; wheel movement and drifting smoke reveal ground handling and wind. | Small vehicle identifier. |
| 00:08–00:12 | **G, Extra:** one complete axial roll | Hold a clear horizon and the entire aircraft. Cut after recovery; no artificial speed-up. | Small vehicle identifier. |
| 00:12–00:15 | **G, Mustang:** banked pass with gear transition | Match the previous screen direction; golden-hour rim on the fuselage. | `P-51D Mustang 1/4` |
| 00:15–00:18 | **G, Turbo Lumber:** low electric circuit over grass | Quiet electric voice against the prior gasoline engine; grass foreground and visible aircraft shadow. | `Turbo Lumber Evolution` |
| 00:18–00:23 | **G, helicopter:** rotor detail, hover/yaw into forward flight | A brief mechanical close-up opens to a sustained full-model shot with ground reference. Preserve a distinct five-second helicopter beat. | `RC Helicopter Research Trainer` |
| 00:23–00:27 | **G, Bisonte:** ramp jump and suspension loading on landing | One low three-quarter view spans takeoff and landing. If no clean jump fits, use the supported corner/suspension alternative. | `Bisonte MT8` |
| 00:27–00:31 | **G, MONSTER CAR 2:** nitro corner exit and acceleration | Tires, steering and chassis movement; distinct nitro sound. A second car gets its own hero, not a background glimpse. | `MONSTER CAR 2` |
| 00:31–00:38 | **G, storms and wind:** 31–34 s electrical-storm tower, branched lightning and distant rain curtains; 34–38 s airplane correcting in configured gusts/turbulence | Night/dusk silhouette and a restrained flash, then a separate readable wind-response shot with windsock/smoke cues. Reuse actual delayed thunder. Aircraft remain visible. | No new large title; actual weather/wind overlay only if it helps. |
| 00:38–00:42 | **G, control:** synchronized stick overlay, moving surfaces and recovery | Keep the aircraft on screen; use the real active input profile. A brief native control guide/glyph row establishes device choices without a menu tour. | `TAKE CONTROL.` with small `USB RADIO · GAMEPAD · KEYBOARD` |
| 00:42–00:50 | **G, consequence:** 42–44 s approach/contact, 44–45 s wreck, 45–48 s actual report, 48–50 s restart | Music drops at impact. Hold the real English cost report for 3 full seconds, then restart on a decisive input/sound. Keep the entire incident consistent. | `EVERY MISTAKE HAS A COST.` over the approach only; the report supplies its own amount and qualifications. |
| 00:50–00:57 | **C, formation finale:** diamond pass/climbing bank, then coordinated fan-out | **50–54 s uninterrupted wide shot with at least four aircraft visible; 54–57 s fan-out.** Six-ship delta is an alternate to the diamond, not an extra sequence. Music releases into the final beat. | Persistent readable `CINEMATIC FORMATION SEQUENCE`. |
| 00:57–01:00 | **S/graphic, end card:** clean logo and one destination | Full 3-second hold, final engine/music tail. No additional pre-roll, credits tail or extra CTA after 01:00. | `OpenRC Simulator` / `EVERY INPUT MATTERS.` / verified project URL; small `EARLY ALPHA`. |

If the current filming build includes unreleased behavior, identify it as a **development build**. The closing URL initially points to the [project website](https://bultodepapas.github.io/OpenRCsimulator/); only use `DOWNLOAD NOW` when the linked package actually contains the advertised scope. Steam guidance informs editing/delivery, not an assumed Steam release.

## 4. Formation centerpiece

**Required creative outcome:** multiple airplanes visibly occupy the same continuous shot while performing together. Intercut solo passes do not satisfy this requirement.

The current review found no production formation director or multiplayer route. Each session installs one model in the shared kernel. Build the filming solution at the presentation boundary, keeping that contract intact.

### Preferred method: in-engine recorded actors

1. Fly and retain one clean baseline maneuver, then additional flights for the split/break. Preserve the original input tape and exact-replay result for each fixed-wing take.
2. Add a small external filming scene under proposed `tools/trailer/`, loading the existing production aircraft builders, field and lighting. It reads detached trajectories and visual channels; it does not modify the simulation kernel.
3. Drive four render actors on one shot clock. Begin with a diamond of Stiks so smoke can use an existing installation. Formation offsets and any duplicated trajectory are **authored visual choreography**, not proof that four aircraft flew with independent interacting physics.
4. Specify paths/offsets in world coordinates and check the entire swept model bounds, smoke paths and camera frustum. Separate the actor paths in depth and altitude for the apparent opposing pass. Verify clearance frame by frame; never rely on screen-space separation alone.
5. Reuse production articulation, propeller and smoke behavior where available. Smoke history, sound, gear and surface channels need explicit filming support; numerical flight replay does not supply a finished visual replay.
6. Finish with four aircraft splitting into individually readable lanes. Test a six-aircraft delta only after the four-aircraft shot passes framing, clearance and render checks. Choose one formation version for the seven-second slot; do not extend the minute.

**One-minute choreography:** diamond entry/climbing bank → fan-out. A six-ship delta or formation roll can replace the first action only if it remains readable within four uninterrupted seconds; these are alternatives, not additional beats. The official airshow manual is a provisional reference found through indexed text; its diagrams could not be retrieved during this investigation. Verify them before detailed choreography boards, using RC proportions and a fictional team identity. No unsupported wake interaction, midair collision or shared-player session is advertised.

**Fallback:** if the in-engine filming scene cannot render a clean simultaneous shot, stage the same current production models in Blender with existing tools and licensed resources. Keep the whole shot labeled `CINEMATIC SEQUENCE`; disclose its production method in the description. Do not quietly replace the requested formation with solo cuts. This fallback changes production method, not the simulator's feature claims.

Avoid adding Blue Angels logos, aircraft or uniforms. The reference is the coordinated spectacle; the film remains an OpenRC RC-airshow identity. Jet formation is an optional alternate without smoke, not a reason to implement a new smoke system.

## 5. Crashes and the displayed price

This is a narrative payoff, not a purchase offer. Select a real incident that produces a visually clear crash and a readable English accident report on the exact filming build.

| Candidate | Purpose | Acceptance |
| --- | --- | --- |
| Stik propeller strike / hard landing | Most controlled path to demonstrate an identified damaged component and its sourced estimate | Actual contact creates the report; the reported scope and missing coverage stay visible. |
| Hard airplane/obstacle impact | Main dramatic crash, wreck and aftermath | Use supported collision geometry and the actual crash presentation. If its valuation is incomplete, show that status; do not manufacture a total-loss number. |
| Truck rollover or heavy landing | Optional quick contrast in the montage | Film the truck's real response; do not attach the aircraft repair report to a truck without implemented truck economics. |

Capture approach, impact, aftermath and report in the same session. Keep the incident identity, aircraft configuration, economy-catalog identity, actual displayed amount, currency, estimate/completeness status and source video timecode together. Select the money shot from that evidence; never hard-code a dramatic amount into the storyboard.

Use the report's exact English wording and currency. A partial subtotal remains a partial subtotal. Any editorial magnification reproduces the same number and its qualifications. Do not crop `estimated`, `inspection required` or missing-price information. A clearly staged montage may cut from a modest priced prop strike to a different dramatic wreck, but it must not suggest that the first bill belongs to the second crash; prefer one incident for the entire payoff.

The [crash guide](../CRASH-DAMAGE-PLAN.md) owns presentation limits; the [economics plan and implementation links](crash-damage-economics.md) own valuation. Current structural/thermal assessment and full fleet costing remain incomplete. A spectacular particle effect does not establish a physically calibrated repair bill.

## 6. Complete feature review and editorial coverage

Review scope: the current-source feature table, player guide, track registry and the feature owners linked below. This is a player-facing inventory review, not a runtime validation campaign. Some older guides count fewer catalog configurations; use the current catalog for counts. Every feature was considered; the minute gives mandatory subjects dedicated beats and carries secondary features through the same images. Auditing a feature does not require a separate title card.

| Feature family / current scope | Treatment in the 60-second film | Source / boundary |
| --- | --- | --- |
| Five fixed-wing families; trim, stalls/spins, servo response and 240 Hz float64 flight model | Takeoff, roll, banking, control and crash shots | [Current features](../../README.md#current-features); show behavior without a physical-validation claim. |
| Glow 2T/4T, gasoline, electric and turbine propulsion; finite-fuel glow controls | Distinct sound/response across vehicles; variants audited, no extra catalog montage | [Glow engines](../GLOW-ENGINES.md), [propulsion](../PROPULSION-CORE-PLAN.md); do not imply Timber battery depletion. |
| Playable helicopter: spool, hover, cyclic/collective/yaw and trainer controls | Mandatory 18–23 s hero | [Helicopter](../HELICOPTER.md); advanced HX-700 laboratory work is not another playable helicopter. |
| Two trucks: electric/nitro, suspension, steering, braking, terrain, circuit ramps/rollers/slalom | Mandatory separate 23–27 and 27–31 s heroes | [RC activity](../../research/rc-monster-truck/README.md); truck experiments and qualification remain separate. |
| Truck water/mud, damage/recovery, tuning laboratory and recording | Audited; mud/grime may appear within a car shot; no extra showcase slot | [RC activity](../../research/rc-monster-truck/README.md); do not transfer its water behavior or repair economics to aircraft. |
| Per-wheel aircraft ground handling, suspension, steering, tire grip and rough grass | Stik takeoff and impact | [Ground model](../research/ground-physics/GP-05/README.md); no calibrated landing-distance claim. |
| Flaps/retracts on equipped aircraft; Stik pump/exhaust smoke | Mustang equipment shot; Stik smoke | [Equipment/controls](../FIRST-LAUNCH.md); no jet smoke or active Timber flaps. |
| Physical mean wind, crosswind, repeating gusts and seeded temporal turbulence | Mandatory 34–38 s correction shot; windsock/smoke elsewhere | [Wind](../WIND-PLAN.md); spatially uniform field, no tornado or obstacle-wake claim. |
| Nine skies and cloud motion; storm tower, distant rain curtains, branched lightning and delayed thunder | Mandatory 31–34 s Electrical Storm shot | [World controls](../FIELD-WORLD-PLAN.md#sky-and-cloud-controls); visual presentation, not rain/bolt damage or spatial storm forces. |
| Elevation, temperature, QNH and humidity affecting atmosphere | Audited; carried by the chosen flight setup, no numeric explainer | [Atmosphere](../ATMOSPHERE-PLAN.md); do not claim that storm appearance changes density. |
| Day/dawn/dusk/night, date/location/time, stars/moon, field lamps, campfire and aircraft-light presentation | Golden-hour vehicle footage into night/dusk storm; visible lamps as scenery | [World](../FIELD-WORLD-PLAN.md), [time](../TIME-OF-DAY-PLAN.md); editorial cuts, not instant physical weather changes. |
| Club field, grass, vegetation, lake, buildings, people/birds and parked vehicles | Environmental layers in hero shots | [Landscape](../LANDSCAPE-PLAN.md); background objects are not additional playable vehicles. |
| Positional engines, propeller/airframe sound, Doppler, wind/foliage/wildlife | Carries the entire film; thunder becomes the tension transition | [Audio](../AUDIO-PLAN.md); use captured voices, not unrelated full-size aircraft audio. |
| Keyboard/gamepad/USB radio, saved calibration, profiles, remapping, AUX, rates/expo and failsafe | Mandatory 38–42 s synchronized controls | [Player guide](../FIRST-LAUNCH.md); active mappings and activity-specific controls are authoritative. |
| Pilot/chase/orbit/close-up, zoom/auto-zoom and shadow aid | Different gameplay perspectives across hero shots | [Camera guide](camera-views.md); filming rails are not advertised player cameras. |
| Sticks/trims, flight data, wind, warnings, control guide, telemetry and diagnostics overlays | Useful sticks/wind overlays only; clean footage elsewhere | [Overlays](flight-overlays.md); never fabricate telemetry for a staged shot. |
| Contacts, debris, wrecks, marks, fire/smoke, limited scenery breakage, persistent aftermath/restart | Mandatory 42–50 s consequence | [Crash](../CRASH-DAMAGE-PLAN.md); damaged-flight mechanics remain unimplemented. |
| Estimated component repair/replacement, incomplete scope and inspection status | Mandatory real incident report, 45–48 s | [Economics](crash-damage-economics.md); preserve partial/provisional status and real amount. |
| Workshop supported size/weight/power/control changes, saved revisions and test flight | Reviewed; optional replacement insert in a derivative, not added to the main minute | [Workshop](../AIRCRAFT-WORKSHOP.md); capability-gated, not arbitrary hardware assembly. |
| Natural Random briefing and repeatable scenario; optional fixed-wing emergency practice | Reviewed; a supported emergency may motivate the existing crash shot, if accurately recorded | [Natural Random](natural-random-flight.md), [failures](failure-mode.md); not every failure or vehicle is supported. |
| English/Spanish menus, saved choices, pause/focus handling, display/text/accessibility settings | English capture; no settings tour | [Player guide](../FIRST-LAUNCH.md); preserve legibility and avoid rapid flash editing. |
| Flight recording/markers, numerical exact replay/CSV, helicopter/truck diagnostics | Production evidence; no player-facing visual-replay promise | [Flight logs](../FLIGHT-LOGGING.md), [tools](../TOOLS.md). |
| Desktop packages and update flow | Verify end-card destination and build availability | [Downloads](../../README.md#download-and-fly); no assumed mobile/web/Steam release. |
| Drone racing, tornado challenge, general multiplayer and advanced helicopter flight | Reviewed as unimplemented/unreleased; exclude from advertised gameplay | [Drone plan](drone-racing.md), [sky plan](sky-clouds-weather.md), [helicopter](../HELICOPTER.md); formation is labeled cinematic. |

**Storm staging:** use the airplane route with `Electrical Storm`; capture its tower, internal light, branched bolt and distant rain curtains. Warm up the storm and retain long sound handles: distant thunder can arrive much later than the three-second picture slot, so select a passage with audible thunder from earlier events rather than forcing an immediate boom onto the visible bolt. The helicopter and Natural Random routes currently keep the classic sky and have no equivalent storm consumer. Do not composite lightning behind the helicopter and present it as its current gameplay. Set physical wind/gusts independently for the following airplane shot. A bolt must not be edited to imply it struck the aircraft, caused the wind impulse or generated the repair bill. Reuse the already bundled free cloud/thunder assets.

Use [FIRST-LAUNCH](../FIRST-LAUNCH.md), [Workshop](../AIRCRAFT-WORKSHOP.md), [helicopter controls](../HELICOPTER.md) and [truck controls](../../research/rc-monster-truck/README.md#drive-and-experiment) as the authoritative mappings. In the control insert, show a modest stick movement, matching surface travel and matching vehicle response; do not animate a decorative unsynchronized stick diagram.

## 7. Capture and editing workflow

### Reuse first

- Reuse the [cinema pipeline](../../site/CINEMA.md), [eight-vehicle studio tooling](../media/README.md), native models, field, licensed fonts and bundled input glyphs. Existing studio clips are 24 fps/1280×800 and the tour is a small GIF: use them for the animatic, then recapture suitable master footage.
- Use free downloadable tools: **OBS Studio** for real-time gameplay, **Godot Movie Maker** for repeatable offline staging, **Blender VSE** for the editable timeline/compositing, and **FFmpeg/ffprobe** for encoding and inspection. Reuse the project's checked FFmpeg distribution before downloading another. Record exact versions and hashes; change no engine pin for filming.
- Download suitable licensed music and limited accent SFX instead of building an audio generator, editor, recorder or new aircraft assets. Existing game audio remains the vehicle sound source. [Research sources](../research/cinematic-trailer/2026-10-17.md#external-references) identify candidate libraries; no track is selected or cleared yet.

### Two capture lanes

**Live gameplay:** rehearse, capture in OBS with recoverable MKV and separate game/music tracks where available, then remux for editing. Film actual controls, crashes and accident reports in the interactive route. Record at 60 fps only if the gameplay and capture sustain it; inspect timing and audio. Reducing output quality is preferable to hiding simulation slowdown.

**Repeatable presentation:** use Godot's built-in `--write-movie` / `--fixed-fps` support for staged/model shots, with PNG frames plus WAV when lossless intermediates are warranted. This engine capability is available; this project's trailer director and visual replay adapter are **pending**. At 60 fps, target four existing 240 Hz simulation ticks per normal-speed frame, and verify the application's actual clock behavior. Use normal shutdown so audio headers finish correctly. Validate a 10-second shot before committing to long exports. [Godot movie documentation](https://docs.godotengine.org/en/4.7/tutorials/animation/creating_movies.html).

The [flight logger](../FLIGHT-LOGGING.md) provides F10 recording, F11 markers, export and numerical exact replay. It is **not a visual replay player**. Use it as evidence for fixed-wing takes; helicopter and truck recordings retain their own formats and acceptance rules. In particular, the standard scripted/capture routes do not automatically reproduce the interactive crash-effects policy: capture the crash live first.

### Production sequence

1. Freeze the source build, asset/config identities, English locale, vehicle selection, environment and controls profile. Preserve player preferences by using an isolated filming profile. Keep physics/data and golden flights unchanged.
2. Produce a short technical pilot covering actual gust response, an electrical-storm event, one impact with its report, and a four-actor formation test. Check image quality, clock, lightning/thunder timing, sound and valuation before filling the shot list.
3. Build an exactly **60-second animatic** from existing references and temporary timing cards. Lock the helicopter's five seconds, both cars' four-second slots, the seven-second storm/wind block, three-second report hold and seven-second formation before polishing transitions. Replace every placeholder before final delivery.
4. Rehearse and capture 3–5 takes of each hero action, with roughly two seconds of edit handles. Record clean and useful-HUD views; retain the actual UI capture for claims.
5. Build the formation sequence and camera paths. Capture smoke warm-up, scene reset and clean starts deterministically; never assume replay includes presentation effects.
6. Assemble picture in Blender VSE, then sound, restrained grading, English titles and subtitles for any added speech. Keep source shots and their edits traceable.
7. Review the whole film at speed, muted, on headphones and at phone size; inspect crash/formation sequences frame by frame. Export and decode the complete deliverable before marking it ready.

Slow motion uses actual higher-rate capture or explicit frame retiming; no AI-generated collision/interpolation frames. Use speed ramps only around editorial transitions, not to misrepresent aircraft capability. A trailer cadence is not a runtime performance benchmark.

## 8. Sound and graphic design

The cue should have a spare intro, a driving middle, a usable stop and a final lift. Audition three freely downloadable tracks around 110–130 BPM; tempo is an editorial preference, not a requirement. Choose a commercial/promotional license that covers the final video, retain attribution and any Content ID certificate, and avoid competing vocals.

Record clean turbine, glow two-stroke, four-stroke, electric motor, helicopter rotor, tires, impact, wind, thunder and field ambience. Save game audio and music separately. Use a quiet environmental bed to connect cuts; reserve large accents for takeoff, the main impact and formation release. Let actual distance-delayed thunder bridge the storm and wind shots; retain enough source handles to capture it. Do not turn every prop aircraft into a full-size fighter jet.

Working mix targets: approximately −14 LUFS integrated and at most −1 dBTP, checked on the delivered file; these are house targets, not a promise of a platform standard. Duck music enough for the different powerplants and the crash/restart beat to register. Keep the aircraft visible instead of covering the impact with flashes or titles.

English editorial titles: `TAKE CONTROL.` · `EVERY MISTAKE HAS A COST.` · `EVERY INPUT MATTERS.` Keep the cost sentence over the approach, never over the report. Small vehicle identifiers, device labels and the cinematic disclosure remain separate functional text. All text must be legible at 1080p and on any vertical derivative.

## 9. Deliverables and file boundaries

| Deliverable | Scope |
| --- | --- |
| Main English trailer | Exactly 60 s / 3,600 frames at 60 fps; 16:9; H.264/AAC stereo MP4; 1080p60 delivery, optional native 4K60 master after the pilot |
| Optional English derivatives, after the main film | 30-second teaser or 15–20-second 1080×1920 vertical cut; no extra shooting requirement. Reframe individually without clipping wings or report qualifications. |
| Editable project | Blender timeline, used source clips, title assets, audio stems and render settings |
| Poster | A genuine final-video frame; no fictional vehicle or unfilmed screenshot |
| Evidence / credits | Shot manifest, build and input identities, price-report references, asset licenses and source links |

Proposed owned paths: `tools/trailer/` for the small capture/manifest adapters; `docs/research/cinematic-trailer/` for accepted evidence; this plan for remaining steps. Raw takes, frames, proxies and work-in-progress edits go under ignored `tmp/trailer/<run-id>/`. Deliver large final files to a named export folder outside Git, with hashes and a durable handoff location recorded in the evidence. Do not leave the only final copy in temporary storage.

The trailer track does not own `app/sim/`, physics data, aircraft generators, crash/economics logic, or `site/` publication. If filming exposes a defect, report it to its owning track; do not tune physics, bill amounts or crash severity to make a shot look better. Keep new drafts outside `app/` until they parse.

## 10. Steps, dependencies and effort

Estimates are planning ranges for focused production work, excluding unattended rendering and unknown defects; they are not delivery promises. Formation and capture feasibility determine the final schedule.

| ID | Work | Proof / status | Effort |
| --- | --- | --- | --- |
| TRA-00 | Inspect source and all player-facing feature families; incorporate 60-second/English/crash-price brief and mandatory helicopter/cars/storm/wind beats | Delivered as documentation only; [research snapshot](../research/cinematic-trailer/2026-10-17.md) | Completed planning |
| TRA-01 | Freeze filming build; audit all 11 configurations and one usable priced incident; inventory tools/licenses | Pending: selected build, shot coverage matrix, incident/report and exact tool versions | 2–4 h |
| TRA-02 | Technical pilot: real-time capture, gusts, storm event, offline timing/audio and four-actor shot | Pending: short pilot, frame/audio inspection, actual weather behavior and supported crash-report path | 4–8 h |
| TRA-03 | Animatic, camera boards, music audition and final capture list | Pending: English 60-second timing cut with every distinct vehicle and all mandatory beats allocated | 2–4 h |
| TRA-04 | Record solo flights, controls, features, trucks and crash/report | Pending: complete take sheet and original media; relevant replay/recorder evidence | 6–12 h |
| TRA-05 | Produce four-ship formation; test six-ship/roll alternatives within the same seven seconds | Pending: simultaneous actors, readable choreography, clearance review, cinematic labels | 4–10 h |
| TRA-06 | Edit, sound design, English titles, grading and cost-report treatment | Pending: full rough cut then polished master | 6–12 h |
| TRA-07 | Complete quality/claim review, encoding, poster and handoff; derivatives optional | Pending: decoded 60-second output, credits/licenses, hashes, complete mandatory coverage | 3–5 h |
| TRA-08 | Adapt and publish to a chosen channel, if subsequently requested | Pending; delivery of the video does not publish it | Separate scope |

Dependency order: TRA-01 → TRA-02 → TRA-03 → TRA-04/05 → TRA-06 → TRA-07. TRA-02 proves the two signature shots before expensive full-fleet filming. Expected active production: **27–55 hours**, revised after the pilot.

## 11. Acceptance gates

- Runtime is exactly 60 seconds including the end card; 3,600 video frames at 60 fps. All eight distinct vehicles are recognizable for at least three seconds each. The playable helicopter retains five seconds; each truck retains four. Engine variants are audited and accurately identified in the takes, without mandatory separate cards. Re-audit if the frozen catalog changes.
- All player-facing text and game UI are English. The first five seconds establish RC gameplay, and the story remains comprehensible muted.
- One solo acrobatic maneuver, preferably the Extra's axial roll, is actually flown and visibly completed at normal speed. Additional formation banking/fan-out provides the group spectacle. A loop is an alternate, not an extra required shot.
- The Electrical Storm shot visibly includes its cloud tower and a lightning event, with actual thunder retained in the sound sequence; a separate shot demonstrates configured physical wind/gusts. Do not substitute generic dark skies for the storm or a camera shake for flight response. No storm feature is falsely attributed to the helicopter route.
- Four or more airplanes share at least one continuous, clearly readable formation shot for three seconds or longer. No intersecting geometry, broken articulation, incorrect smoke installation or unexplained teleporting. Staged footage carries its cinematic label.
- A real crash and its own real English report are shown. The amount, currency, scope and incomplete/provisional status match the recorded incident. No shopping price or unsupported total-loss bill is added.
- The image is crisp, the complete exported video decodes, duration/frame count match the edit, motion pacing is sound, and audio stays synchronized through the end. No rapid strobe montage, unreadable cost flash or fast-forwarded maneuvers. Review full-size, phone-size and muted versions.
- Every feature claim is supported by the selected build; laboratory-only aircraft, multiplayer, full fleet economics, physical validation and unimplemented damage behavior are not implied.
- Models, footage, sound, music, fonts and glyphs have retained provenance and usable licenses. Tool versions, build/config hashes and original media can reproduce or explain every final shot.

## 12. Risks and deliberate alternatives

| Risk | Response |
| --- | --- |
| Formation tooling is the largest new dependency | Prove four actors first; use current models and a presentation-only scene. If needed, use the labeled Blender fallback while retaining simultaneous formation. |
| AAA-style expectation exceeds current rendering | Spend effort on light, camera, composition, controlled pacing and sound. Keep the actual game's visual identity and disclose staged shots. |
| Heavy scenery, smoke or multiple actors slows capture | Measure the pilot; use offline capture for the cinematic and a qualified lower resolution for live gameplay. Do not silently alter flight time or solver step. |
| A one-minute feature montage feels rushed | Combine features inside the same hero shots; keep Workshop, Natural Random, tuning and diagnostics in the reviewed inventory without extra title cards. Protect the dedicated helicopter, cars, weather, report and formation timings. |
| Storm appearance is mistaken for storm physics | Film the actual airplane sky preset, configure wind separately and avoid a bolt-to-crash causal edit. No helicopter storm composite. |
| A dramatic crash has no complete price | Use the actual partial/provisional report, or choose a priced Stik incident for the cost beat. Never substitute an unrelated bill. |
| Replay lacks visual/crash history | Keep original live capture; add only the required external presentation adapter. Numerical replay alone cannot reconstruct the trailer. |
| Six-aircraft roll is unreadable or implausible | Retain the four-ship diamond/climbing bank and fan-out in seven seconds; the delta remains an alternate. |
| New source features are absent from the public download | Label development footage and verify the CTA/package again before delivery. |
| Music rights or Content ID are unresolved | Choose another cleared free track; the edit project keeps music replaceable. |

This request ends at the Markdown plan. Capture-tool implementation, filming, editing and publication are future steps; none are represented as completed here.
