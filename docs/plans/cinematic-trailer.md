# OpenRC Simulator — cinematic trailer production plan

2026-10-21 · **Owner:** trailer/media · **Prefix:** TRA-00…08 · **Status:** [runtime refresh](../research/cinematic-trailer/refresh-2026-10-21.md) delivers a new 58-second local film from the current simulator. It retains [revision 6's](../research/cinematic-trailer/revision-6-2026-10-17.md) scene order, feature titles, MONSTER CAR 2 jump, twilight Turbo Lumber Evolution, two Extra rolls, formation opening and continuous score. Listening review and the existing Turbo Lumber Evolution asset notice remain open before publication. [Original capture evidence](../research/cinematic-trailer/production-2026-10-17.md).

User brief: a **very cinematic, AAA-style game trailer**, entirely in **English**, showing every current vehicle, aerobatics, crashes, controls and several airplanes performing together in the spirit of an airshow. The original exact-minute request was explicitly relaxed for revision 6; the accepted edit is 58 seconds. **Helicopter, both cars, electrical storms and physical wind are mandatory.** Review the complete player-facing feature inventory and select its strongest visual moments. **Prices mean the estimated accident/repair cost displayed after a crash, not the simulator's purchase price or vehicle shopping prices.** Historical storyboard timing below records the earlier targets.

This plan retains the creative targets and remaining review gates. The [production evidence](../research/cinematic-trailer/production-2026-10-17.md) is authoritative for the delivered film, source identities and deliberate changes from those targets. The [dated investigation](../research/cinematic-trailer/2026-10-17.md) records the earlier source audit at commit `049df2034de017e6fedc649a55194eb5977191cd` and research limits.

## Revision 9 — legibility re-cut (TRA-10, 2026-10-29)

**Owner verdict on v8:** too fast; the titles cannot be read. **Audit of v8 (measured on its timeline):**

- 23 distinct cues and 267 words in 58 s (4.6 words/s), with text on about 90 % of the runtime.
- Each cue had three text tiers. Its 1.2 s entrance used most of a 1.5–2.25 s shot, so cues held still for a median of 0.65 s.
- No cue met a 0.5 s + 3 words/s reading budget.
- Liveries changed every 0.2 s, and UI stills lasted 0.8 s.
- The 26 px kicker reads as about 13 px on a phone. The jargon (QNH, "flight-identified") was unreadable at that pace.
- The 60-second slice of the score is all climax, so the film had no build, breath or payoff.

The owner also reported that the Corsair appeared to change place between livery takes.

**v9 rules:**

- 90 s cut from one continuous interval of Uprising, from source 114.939 s to its natural ending. The cue builds, breathes from 6 to 12 s, hits at 12.03 s, and its final chord at 80.9 s lands on the logo.
- Every cut falls on the measured 0.668 s beat.
- One cue per shot, and only on some shots: headline of 1–4 words, detail of 6 words or fewer, on screen for at least 2.6 s.
- Cue entrance 0.55 s; kicker 34 px; detail 40 px; headline 88–96 px; darker sky scrim.
- Montage beats carry no text.
- UI stills last 2 s with an eased push-in on the value shown.

**Corsair (owner request):**

- One real low pass in calm air: no wind, gusts or turbulence. Light left bank, altitude hold, and the camera orbits 360°.
- Eleven paint schemes swap in flight on the beat, presentation only. The aircraft stays in the same place because it is a single take.
- `luftwaffe` and `japan` remain excluded.

## Revision 8 — feature-complete re-cut (TRA-09, 2026-10-28)

**Owner brief (2026-10-28):** v7 is outdated. Show every current attribute quickly: realistic physics with real technical terms, NVIDIA DLSS and AMD FSR, the different aircraft, colored show smoke, AI companions, night flight, compatible radios, Workshop, mini and giant aircraft. Keep the multi-aircraft opening, but with **different airframes and colored smoke**.

### Review of v7

| Keep | Change |
| --- | --- |
| Real gameplay, real crash report, licensed score, Barlow typography, honest labels | **Opening:** four identical red Stiks with white smoke read as one model duplicated. Use five distinct airframes and an airshow palette. |
| Formation as the hook | **Rhythm:** every shot lasts 3–5 s with the same 3/4 rear chase, so the film reads as a slideshow. Alternate 1.5–2 s roll-call cuts with 3 s holds. |
| Crash → cost payoff | **Copy:** generic slogans (`FEEL EVERY INPUT.`) carry no information. RC pilots respond to engineering: name the modeled effects. |
| | **Coverage:** missing Corsair, X8, AI companions, Workshop smoke colors, RGB night lighting, Workshop size range, DLSS/FSR/Reflex, nine languages. |
| | **Repetition:** the same red Stik carries stik-bank, wind, controls and crash. The storm shot has no aircraft. |
| | **Ending:** the film ends on a repair bill. End on spectacle, then the logo. |

### Storyboard (~66 s, 60 fps)

**G** = gameplay capture, **U** = real application UI, **C** = labeled cinematic choreography, **R** = reused v7 source. Callouts use a small mono data line under the headline; every term must name behavior present in source.

| Time | Shot | Callout (headline / data line) |
| --- | --- | --- |
| 0:00–0:06 | **C** five-airframe formation (Stik, Extra, P-51D, F4U, Vantage Jet), red/white/blue/yellow/green smoke, low camera, fan-out | `OpenRC SIMULATOR` cold open; `CINEMATIC FORMATION SEQUENCE` |
| 0:06–0:09 | **R** Extra two rolls | `FLIGHT PHYSICS.` / `6-DOF RIGID BODY · 240 Hz · 64-BIT SOLVER` |
| 0:09–0:11.5 | **R** Mustang pass | `P-FACTOR · GYROSCOPIC PRECESSION · PROPWASH` |
| 0:11.5–0:14 | **R** wind/gust correction | `MEAN WIND · GUSTS · SEEDED TURBULENCE` |
| 0:14–0:16.5 | **R** jet pass | `SPOOLING TURBINE · DOPPLER · SOUND DELAY` |
| 0:16.5–0:19 | **R** Stik bank (gear) | `PER-WHEEL SUSPENSION · TIRE SLIP · STALLS & SPINS` |
| 0:19–0:21 | **G** F4U Corsair: full-throttle level run-up to top speed, then aileron held through two rolls; the edit cuts between eleven livery takes of the identical deterministic flight every 0.2 s | `13 PAINT SCHEMES.` / `Full throttle · aileron held · same flight, every livery` |
| 0:21–0:23 | **G** X8 flying wing | `X8 FLYING WING` / `FLIGHT-IDENTIFIED AERODYNAMICS` |
| 0:23–0:25 | **R** Turbo Lumber twilight | `TURBO LUMBER EVOLUTION` / `ELECTRIC` |
| 0:25–0:27 | **R** helicopter | `RC HELICOPTER` / `COLLECTIVE · CYCLIC · ROTOR SPOOL` |
| 0:27–0:30 | **R** Bisonte → MONSTER CAR 2 jump | `RC CARS` |
| 0:30–0:35 | **G** Workshop size trials: Tiny Stik then Giant Stik | `MINI 15 cm → GIANT 7.6 m` / `WORKSHOP SIZE 10–500 %` |
| 0:35–0:38 | **U** Workshop paint/lighting/smoke pages | `AIRCRAFT WORKSHOP` / `PAINT · LIGHTS · SMOKE · SIZE · POWER` |
| 0:38–0:41 | **G** AI companions, normal flight | `AI WINGMEN` / `UP TO 3 · TRAFFIC AVOIDANCE · EXPERIMENTAL` |
| 0:41–0:44 | **G** night RGB lighting + colored smoke | `NIGHT FLIGHT` / `PROGRAMMABLE RGB LIGHTS · COLOR SMOKE` |
| 0:44–0:46 | **R** storm | `ELECTRICAL STORMS` |
| 0:46–0:48.5 | **R** controls overlay | `YOUR RADIO.` / `EdgeTX · OpenTX (USB) · GAMEPAD · KEYBOARD` |
| 0:48.5–0:51 | **U** Settings → upscaler list | `NVIDIA DLSS · DLAA · REFLEX / AMD FSR` / `EXPERIMENTAL` |
| 0:51–0:55 | **R** crash approach, impact, report | `EVERY MISTAKE HAS A COST.` |
| 0:55–1:03 | **C** formation reprise (fan-out) | — |
| 1:03–1:06 | end card | `EVERY INPUT MATTERS.` / `9 LANGUAGES · OPEN SOURCE · EARLY ALPHA` / URL |

The owner added on 2026-10-28: show the Corsair's liveries switching rapidly during a spectacular roll, at full speed, with the aileron held. Liveries are chosen before flight; the switch is editorial and the card says so. `luftwaffe` and `japan` are left out of the public edit. Settings lists DLSS/FSR as unavailable in the standard Compatibility build, so the trailer shows a labeled card, not that screen.

Claims stay inside source scope: aircraft remain experimental and not flight-validated; Workshop size is virtual similarity scaling; companions are an experimental 1–3 roster; DLSS/DLAA/Reflex and FSR are unqualified trials; radios are EdgeTX/OpenTX USB joystick mode, without a brand compatibility list. The score is re-rendered to the new length from the same licensed Uprising source.

Research expansion: **16 internet investigations**, a parallel **five-track music shortlist**, and comparisons of code-video skills and generative-video tools are recorded in the [research ledger](../research/cinematic-trailer/2026-10-17.md#expanded-investigation-16-research-topics). Production selected Scott Buckley's **Uprising**, native Godot capture and a small Python/FFmpeg edit pipeline. Listening review remains open; captures, effects and the full minute have been rendered.

## 1. Creative direction

**Working title: EVERY INPUT MATTERS.**

The minute moves through four acts: **machines (0–31 s), changing conditions and control (31–42 s), consequence (42–50 s), spectacle and title (50–60 s)**. Make the viewer feel the weight of a landing, the precision of a roll, the acceleration of a turbine and the hesitation before a costly mistake. AAA is the standard for direction, pacing, composition and sound; the vehicles, landscape and gameplay remain recognizably OpenRC. Rebuild the edit around these beats instead of speeding up the longer version.

- **Main film:** exactly 60 seconds including titles and end card, 16:9, English titles and English game UI. Target a 3840×2160/60 master if the capture pilot passes; deliver 1920×1080/60. Do not upscale existing web clips and call them native 4K.
- **Story:** “Your hands. Your machine. Your mistake. Your next attempt.” This is the internal narrative, not four mandatory title cards.
- **Image:** warm low sun and intimate mechanical details give way to dark storm clouds, a single readable lightning event and a final sunlit formation. Keep clear ground reference and restrained color grading. Use the current production models and materials; aircraft stay identifiable throughout turns.
- **Sound:** actual propeller, turbine, rotor and nitro voices carry the edit. One licensed instrumental cue builds in acts; a brief near-silence at the crash makes the repair estimate land. No narration in the first cut; the film must work without sound.
- **Typography:** small vehicle identifiers and at most three large editorial title beats: `TAKE CONTROL.`, `EVERY MISTAKE HAS A COST.`, and the end-card `EVERY INPUT MATTERS.` The actual report and cinematic label remain legible. No scrolling feature list or prolonged menu tour.
- **Composition:** foreground grass, runway markings and shadows establish RC scale. Alternate an intimate mechanical detail, a readable full maneuver and a wider environmental shot. Preserve an uninterrupted action beat before cutting to its result.

**Signature moments:** turbine sound pulls the viewer into an immediate low pass; wing banks and circular mechanical forms motivate cuts between vehicles; a grounded helicopter hover gives way to the weight of a truck landing; lightning briefly reveals the storm silhouette; the crash interrupts the music and exposes its actual cost; the restart releases into a wide formation and coordinated fan-out. Favor these six memorable moments over additional title cards or more cuts. Use one or two well-matched transitions where the existing shot boundaries permit them, rather than inserting a new mechanical montage.

The main cut should contain at least 45 seconds of captured, actually simulated driving/flying and its UI. Reserve **7 seconds** for the clearly identified formation cinematic and **3 seconds** for the closing card. Mechanical inserts are brief; protect the 3–5 second hero actions, readable cost report and continuous formation shot.

## 2. Complete vehicle coverage

Current scope is **eight distinct vehicle visuals**: five airplane families, one playable helicopter and two trucks. There are **eleven selectable configurations** when the three additional Stik engine installations are counted. Variants must not be advertised as additional airframe designs.

| Vehicle / catalog ID | Required hero action | Capture limit and alternative |
| --- | --- | --- |
| Jensen Das Ugly Stik 60 — `jensen-das-ugly-stik-60` | Takeoff, smooth bank and smoke pass; reference aircraft for the formation | Physical handling qualification remains open. Use its configured smoke installation; test the selected route before promising a smoke maneuver. |
| Great Planes Extra 300S .60 — `gp-extra-300s-60` | One complete axial roll, framed to show entry and exit | Rehearse on the frozen build. A loop is an alternate only if it fits the slot at actual speed with a readable entry and exit. |
| P-51D Mustang 1/4 — `p51d-mustang-120` | Low banked pass; retracting gear or landing approach | Use current accepted source behavior; preserve experimental status. Do not infer the current source's gates from an older downloadable package. |
| Vantage Jet — `sebart-avanti-s-a200-p100rx` | Fast opening pass, turbine buildup, climbing bank | No configured jet smoke emitter. Its existing studio camera arc is a reference for new full-resolution inserts. |
| Turbo Lumber Evolution — `turbo-lumber-evolution` | Electric takeoff or low grass-field circuit, then a gentle landing | Fixed wheels, flaps up and assists off. Do not imply SAFE/AS3X or battery depletion. |
| RC Helicopter Research Trainer — `xcell-60-research` | Five-second hero sequence: brief rotor detail into hover/yaw and forward transition | This is the playable X-Cell/HX-700 visual surrogate. Currently one playable helicopter route exists; the advanced articulated HX-700 laboratory candidate is not an additional flyable helicopter. No invented inverted/tic-toc performance. |
| Bisonte MT8 — `mt8-bisonte` | Suspension compression, corner exit and a genuine ramp jump/landing | Use the playable RC circuit. Accept only a continuous actual takeoff/landing; substitute a grounded suspension/traction sequence if the jump does not work. |
| MONSTER CAR 2 — `monster-car-2` | Nitro acceleration, steering and braking on the circuit | Use its own sound and controls. Do not imply truck-to-aircraft collision or simultaneous shared gameplay. |
| Stik engine variants — `stik-glow-61fx-2t`, `stik-glow-55ax-2t`, `stik-glow-fs64v-4t` | Audit all three; use the actual selected installation in the Stik/engine sound shots | Same visual family. The one-minute cut covers every distinct vehicle, without three extra engine title cards. Preserve exact configuration identities in the take sheet. |

The source of aircraft identity is the [catalog](../../app/app_state/aircraft_catalog.gd); truck operation is owned by the [RC vehicle guide](../../research/rc-monster-truck/README.md). The [eight-vehicle media workflow](../media/README.md) supplies existing composition references and reusable model access.

## 3. Main storyboard — exactly 1:00

This table preserves the original edit targets. The [accepted timeline](../research/cinematic-trailer/production-2026-10-17.md#accepted-timeline) records the actual shots: a Stik bank rather than takeoff, grounded truck driving, a Mustang pass without a gear-transition claim, and the shorter title `MISTAKES COST.`. The letter identifies the intended source: **G** = actual gameplay, **S** = model/studio presentation, **C** = staged formation cinematic. The delivered film contains exactly **3,600 frames** at 60 fps.

| Time | Shot and action | Camera / edit / sound | English copy and purpose |
| --- | --- | --- | --- |
| 00:00–00:04 | **G, Vantage Jet:** fast low pass into a climbing bank | Turbine heard before frame entry; close pass opens to readable RC field scale. No logo pre-roll. | Small `OpenRC Simulator` and vehicle identifier. |
| 00:04–00:08 | **G, Stik:** wheels release from the runway, bank and smoke begins | Low runway angle; wheel movement and drifting smoke reveal ground handling and wind. | Small vehicle identifier. |
| 00:08–00:12 | **G, Extra:** one complete axial roll | Hold a clear horizon and the entire aircraft. Cut after recovery; no artificial speed-up. | Small vehicle identifier. |
| 00:12–00:15 | **G, Mustang:** banked pass with gear transition | Match the previous screen direction; golden-hour rim on the fuselage. | `P-51D Mustang 1/4` |
| 00:15–00:18 | **G, Turbo Lumber Evolution:** low electric circuit over grass | Quiet electric voice against the prior gasoline engine; grass foreground and visible aircraft shadow. | `Turbo Lumber Evolution` |
| 00:18–00:23 | **G, helicopter:** rotor detail, hover/yaw into forward flight | Match the outgoing propeller's circular form where framing allows; open quickly to a sustained full-model shot with ground reference. Preserve a distinct five-second helicopter beat. | `RC Helicopter Research Trainer` |
| 00:23–00:27 | **G, Bisonte:** ramp jump and suspension loading on landing | One low three-quarter view spans takeoff and landing; foreground and suspension communicate weight. Test a tiny rotational camera impulse at contact. If no clean jump fits, use the supported corner/suspension alternative. | `Bisonte MT8` |
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

**One-minute choreography:** diamond entry/climbing bank → fan-out. A six-ship delta or formation roll can replace the first action only if it remains readable within four uninterrupted seconds; these are alternatives, not additional beats. The [RAF display description](https://www.raf.mod.uk/display-teams/red-arrows/displays/) supports the creative progression from precise formation to dynamic release. The Blue Angels manual remains provisional: indexed text was found, but its diagrams were not retrieved. Verify any detailed maneuver reference before boards, using RC proportions and a fictional team identity. No unsupported wake interaction, midair collision or shared-player session is advertised.

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
| Glow 2T/4T, gasoline, electric and turbine propulsion; finite-fuel glow controls | Distinct sound/response across vehicles; variants audited, no extra catalog montage | [Glow engines](../GLOW-ENGINES.md), [propulsion](../PROPULSION-CORE-PLAN.md); do not imply Turbo Lumber Evolution battery depletion. |
| Playable helicopter: spool, hover, cyclic/collective/yaw and trainer controls | Mandatory 18–23 s hero | [Helicopter](../HELICOPTER.md); advanced HX-700 laboratory work is not another playable helicopter. |
| Two trucks: electric/nitro, suspension, steering, braking, terrain, circuit ramps/rollers/slalom | Mandatory separate 23–27 and 27–31 s heroes | [RC activity](../../research/rc-monster-truck/README.md); truck experiments and qualification remain separate. |
| Truck water/mud, damage/recovery, tuning laboratory and recording | Audited; mud/grime may appear within a car shot; no extra showcase slot | [RC activity](../../research/rc-monster-truck/README.md); do not transfer its water behavior or repair economics to aircraft. |
| Per-wheel aircraft ground handling, suspension, steering, tire grip and rough grass | Stik takeoff and impact | [Ground model](../research/ground-physics/GP-05/README.md); no calibrated landing-distance claim. |
| Flaps/retracts on equipped aircraft; Stik pump/exhaust smoke | Mustang equipment shot; Stik smoke | [Equipment/controls](../FIRST-LAUNCH.md); no jet smoke or active Turbo Lumber Evolution flaps. |
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
- Download suitable licensed music and limited accent SFX instead of building an audio generator, editor, recorder or new aircraft assets. Existing game audio remains the vehicle sound source. The [five-track shortlist](../research/cinematic-trailer/2026-10-17.md#music-shortlist-and-edit-plan) prioritizes Vanguard and Uprising for audition; asset acquisition and final release checks are pending.

### Programmed effects and camera treatment

All entries are **planned**, not delivered. Use existing engine/compositor features first. Small adapters belong under `tools/trailer/`; they read presentation data and never change vehicle physics. The [research ledger R06–R14](../research/cinematic-trailer/2026-10-17.md#expanded-investigation-16-research-topics) provides the technical sources.

| Priority / treatment | How to produce it | Slot and visual acceptance |
| --- | --- | --- |
| Core — engine-led reveal | Start the existing turbine audio before the aircraft enters frame; keyframe a restrained camera pan | 00–04 s: first vehicle and RC scale are clear before the slot ends. |
| Core — motion/form match cuts | Match screen direction, bank angle or circular propeller/rotor/wheel shapes using source selection and frame-aligned cuts | Existing 12 s, 18 s or 23 s boundaries: choose at most two that actually match. No added slot or rapid insert chain. |
| Core — low camera and controlled tracking | Reuse current viewpoints; where necessary use `Path3D`/`PathFollow3D` in the external filming scene and aim at detached recorded poses | Takeoff, helicopter and truck shots: entire vehicle remains readable; foreground reinforces scale. Check camera clearance and avoid wall/ground clipping. |
| Core — storm silhouette and light continuity | Rehearse the actual storm event; expose for both aircraft silhouette and cloud/bolt detail, then use restrained editorial grading | 31–38 s: a single readable event, separate real wind response, real delayed thunder. Preserve the storm's implemented limits. |
| Core — impact, silence and report | Automate music gain around the real contact; retain wreck sound; hold the original report with an optional gentle crop that retains every qualification | 42–50 s: no impact-obscuring flash, no animated invented money counter; the actual report is static and readable for 45–48 s. |
| Core — simultaneous formation director | Place recorded visual actors on one shot clock, with authored offsets and distinct exit paths; keep smoke history and camera bounds explicit | 50–57 s: four-second uninterrupted wide formation, then fan-out; staged label remains readable. |
| Optional — contact impulse | Apply a seeded, decaying rotational camera offset for roughly 0.2–0.4 s; tune visually in the pilot | Truck landing or main impact, not both by default. Ground contact and vehicle silhouette remain readable. This is camera motion, not simulated wind. |
| Optional — glow/highlight streak | Use supported Godot glow or Blender's existing Glare node with a conservative threshold; compare before/after frames | Sunlit pass or storm highlight. No washed-out fuselage, enlarged lightning show or bloom over text. |
| Optional — jet heat shimmer | Reuse a screen-reading shader technique in a masked background region of a staged insert | Only if the pilot preserves silhouette and transparency correctly; omit if it requires renderer migration. No added gameplay heat feature. |
| Core — timed English graphics and music envelopes | Keyframe existing Blender tools, or use one reviewed video framework; encode/measure with FFmpeg | 3,600-frame timeline, title limits, three-second end card and preserved report hold. Account for transition overlap. |

The project's Godot 4.7 Compatibility renderer supports useful glow and adjustments; its built-in depth-of-field blur, volumetric fog and CompositorEffects are unavailable. Obtain depth from lighting and composition. An optional Blender studio treatment must retain its presentation identity. Do not migrate the renderer or add a new weather system for filming.

### Optional video skills

The [tool comparison](../research/cinematic-trailer/2026-10-17.md#skills-and-production-tool-decision) identifies **HyperFrames** as the first new skill candidate for code-driven editing/titles, with **Remotion** as a React alternative subject to its license eligibility. Both assemble supplied footage. Baseline production can proceed with Blender and FFmpeg; use at most one additional framework if a short pilot demonstrates a benefit. Preserve this storyboard when evaluating templates, and pin exact versions before adoption.

Runway was found as an available, unconnected plugin. Generative video is optional for previs or abstract graphics, with service-specific credits and watermark constraints. Actual vehicle, control, weather and damage demonstrations must come from the simulator. No skill installation, service connection, generated clip or new tool dependency is part of this planning delivery.

### Two capture lanes

**Live gameplay:** rehearse, capture in OBS with recoverable MKV and separate game/music tracks where available, then remux for editing. Film actual controls, crashes and accident reports in the interactive route. Record at 60 fps only if the gameplay and capture sustain it; inspect timing and audio. Reducing output quality is preferable to hiding simulation slowdown.

**Repeatable presentation:** use Godot's built-in `--write-movie` / `--fixed-fps` support for staged/model shots, with PNG frames plus WAV when lossless intermediates are warranted. This engine capability is available; this project's trailer director and visual replay adapter are **pending**. At 60 fps, target four existing 240 Hz simulation ticks per normal-speed frame, and verify the application's actual clock behavior. Use normal shutdown so audio headers finish correctly. Validate a 10-second shot before committing to long exports. [Godot movie documentation](https://docs.godotengine.org/en/4.7/tutorials/animation/creating_movies.html).

The [flight logger](../FLIGHT-LOGGING.md) provides F10 recording, F11 markers, export and numerical exact replay. It is **not a visual replay player**. Use it as evidence for fixed-wing takes; helicopter and truck recordings retain their own formats and acceptance rules. In particular, the standard scripted/capture routes do not automatically reproduce the interactive crash-effects policy: capture the crash live first.

### Production sequence

1. Freeze the source build, asset/config identities, English locale, vehicle selection, environment and controls profile. Preserve player preferences by using an isolated filming profile. Keep physics/data and golden flights unchanged.
2. Produce a short technical pilot covering actual gust response, an electrical-storm event, one impact with its report, and a four-actor formation test. Check image quality, clock, lightning/thunder timing, sound and valuation before filling the shot list.
3. Audition Vanguard and Uprising against an exactly **60-second animatic** from existing references and temporary timing cards; test Five Armies if neither fits. Lock the helicopter's five seconds, both cars' four-second slots, the seven-second storm/wind block, three-second report hold and seven-second formation before polishing transitions. Replace every placeholder before final delivery.
4. Rehearse and capture 3–5 takes of each hero action, with roughly two seconds of edit handles. Record clean and useful-HUD views; retain the actual UI capture for claims.
5. Build the formation sequence and camera paths. Capture smoke warm-up, scene reset and clean starts deterministically; never assume replay includes presentation effects.
6. Assemble picture in Blender VSE, or the single code-video alternative selected in the pilot, then sound, restrained grading, English titles and subtitles for any added speech. Keep source shots and their edits traceable.
7. Review the whole film at speed, muted, on headphones and at phone size; inspect crash/formation sequences frame by frame. Export and decode the complete deliverable before marking it ready.

Slow motion uses actual higher-rate capture or explicit frame retiming; no AI-generated collision/interpolation frames. Use speed ramps only around editorial transitions, not to misrepresent aircraft capability. A trailer cadence is not a runtime performance benchmark.

## 8. Sound and graphic design

The cue should have a spare intro, a driving middle, a usable stop and a final lift. **Audition [Vanguard — Scott Buckley](https://www.scottbuckley.com.au/library/vanguard/) first**, with [Uprising](https://www.scottbuckley.com.au/library/uprising/) as backup. Both creator pages offer full-mix MP3s under CC BY 4.0 with attribution. Five Armies, Aphelion and Simulacra complete the [researched shortlist](../research/cinematic-trailer/2026-10-17.md#music-shortlist-and-edit-plan). These are provisional choices based on descriptions; listening, final source offsets and musical joins remain pending. No fixed BPM is required.

Music arc: **0–4 s anticipation → 4–31 s rising drive with distinct engine voices → 31–42 s storm/control tension → 42–45 s impact drop → 45–48 s spare report bed → 48–50 s restart pickup → 50–57 s formation climax → 57–60 s resolution.** Cut at musical phrases and preserve the picture timing; do not compress a whole track to one minute. The composer identifies Uprising's heroic section at source time 2:07, which is an audition lead, not a committed edit point.

Retain the chosen track's download identity, source page, license and required credit, and note edits. Include attribution in the release description and handoff credits; use a small credit inside the existing end card if the destination has no description. Scott Buckley's [claim guide](https://www.scottbuckley.com.au/library/copyright-claims-release/) explains attribution checks and possible third-party claims. No extra credits tail, paid stems or Content ID exemption is assumed.

Record clean turbine, glow two-stroke, four-stroke, electric motor, helicopter rotor, tires, impact, wind, thunder and field ambience. Save game audio and music separately. Use a quiet environmental bed to connect cuts; reserve large accents for takeoff, the main impact and formation release. Let actual distance-delayed thunder bridge the storm and wind shots; retain enough source handles to capture it. Do not turn every prop aircraft into a full-size fighter jet.

Working mix targets: approximately −14 LUFS integrated and at most −1 dBTP, checked on the delivered file; these are house targets, not a promise of a platform standard. Duck music enough for the different powerplants and the crash/restart beat to register. Keep the aircraft visible instead of covering the impact with flashes or titles.

English editorial titles: `TAKE CONTROL.` · `EVERY MISTAKE HAS A COST.` · `EVERY INPUT MATTERS.` Keep the cost sentence over the approach, never over the report. Small vehicle identifiers, device labels and the cinematic disclosure remain separate functional text. All text must be legible at 1080p and on any vertical derivative.

## 9. Deliverables and file boundaries

| Deliverable | Scope |
| --- | --- |
| Main English trailer | Exactly 60 s / 3,600 frames at 60 fps; 16:9; H.264/AAC stereo MP4; 1080p60 delivery, optional native 4K60 master after the pilot |
| Optional English derivatives, after the main film | 30-second teaser or 15–20-second 1080×1920 vertical cut; no extra shooting requirement. Reframe individually without clipping wings or report qualifications. |
| Editable project | Blender timeline, or the single selected code-video composition, plus used source clips, title assets, separate game/music audio and render settings |
| Poster | A genuine final-video frame; no fictional vehicle or unfilmed screenshot |
| Evidence / credits | Shot manifest, build and input identities, price-report references, asset licenses and source links |

Proposed owned paths: `tools/trailer/` for the small capture/manifest adapters; `docs/research/cinematic-trailer/` for accepted evidence; this plan for remaining steps. Raw takes, frames, proxies and work-in-progress edits go under ignored `tmp/trailer/<run-id>/`. Deliver large final files to a named export folder outside Git, with hashes and a durable handoff location recorded in the evidence. Do not leave the only final copy in temporary storage.

The trailer track does not own `app/sim/`, physics data, aircraft generators, crash/economics logic, or `site/` publication. If filming exposes a defect, report it to its owning track; do not tune physics, bill amounts or crash severity to make a shot look better. Keep new drafts outside `app/` until they parse.

## 10. Steps, dependencies and effort

Estimates are planning ranges for focused production work, excluding unattended rendering and unknown defects; they are not delivery promises. Formation and capture feasibility determine the final schedule.

| ID | Work | Result / remaining gate |
| --- | --- | --- |
| TRA-00 | Source/feature audit, 16 web investigations, five-track shortlist and skills/effects comparison | Completed; [research snapshot](../research/cinematic-trailer/2026-10-17.md). |
| TRA-01 | Capture source, eight visual families / eleven configurations, priced incident, tools/licenses | Source/tree identities and original incident retained. Capture used the working tree, not a frozen checkout. Existing Turbo Lumber Evolution redistribution notice remains unresolved. |
| TRA-02 | Native 1080p60 timing/audio, gusts, storm and four-actor pilot | Captured and checked; four 240 Hz simulation ticks per ordinary rendered flight frame. |
| TRA-03 | English one-minute edit, cameras and music | 17-shot timing locked; Uprising acquired with attribution. Listening review remains open. |
| TRA-04 | Solo aircraft, helicopter, trucks, controls, weather and crash/report | All required subjects captured. Actual inputs/state records retained; no exact-replay or physical qualification claimed. |
| TRA-05 | Four-ship formation | Seven seconds / 420 frames; four visible actors, measured separation and persistent cinematic label. Six-ship alternate omitted. |
| TRA-06 | Edit, sound, titles, grading and report | Complete local H.264/AAC film; source audio, music, timeline and editor retained. |
| TRA-07 | Technical review, poster and editable handoff | Full decode, 3,600 frames, 60.000 s and measured audio passed. Sampled visual review complete. Listening and asset release gate remain open. |
| TRA-08 | Channel adaptation/publication | Not requested; no upload or publication performed. |
| TRA-09 | Revision 8 feature re-cut | Local 58-second film delivered; [evidence](../research/cinematic-trailer/revision-8-2026-10-28.md). Superseded by TRA-10 after the owner's legibility review. |
| TRA-10 | Revision 9 legibility re-cut | Local 90-second film; [evidence](../research/cinematic-trailer/revision-9-2026-10-29.md). Listening and small-screen review remain open. |

The original **27–55 hour** range was a planning estimate, not a measured production duration. The remaining work concerns listening review and release clearance; the movie and editable handoff already exist.

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

The subsequent user instruction authorizes producing the complete trailer. Capture and editing now use the external [trailer tools](../../tools/trailer/README.md). Publication remains outside the requested production scope. The storyboard above records creative targets; the delivery evidence records what was actually filmed and accepted.
