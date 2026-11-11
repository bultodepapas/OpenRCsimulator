# FPV simulator research — product comparison, user evidence and sources

**Snapshot:** 11 November 2026. **Purpose:** auditable evidence for [28 approach investigations](10_FPV_SIMULATOR_APPROACHES.md) and [OpenRC decisions/experiments](11_FPV_PRODUCT_DECISIONS_AND_EXPERIMENTS.md). Technical/product evidence is primary-source documentation or author/developer material. Community evidence is labeled separately. No competitor was installed, flown or benchmarked in this study.

## 1. Method and limits

Searches covered named simulator products, official manuals/releases, racing-league pages, open/developer repositories, research-group papers/docs and task-specific community discussions. Current feature claims were checked against dated release notes where available, particularly Liftoff, EreaDrone, TRYP and DJI. SEO buying guides and product superlatives were discovery leads rather than evidence of physics accuracy.

The community sample deliberately includes racing, freestyle, cinematic, indoor-micro, beginner, radio-setup and modest-hardware concerns. It contains **23 opened and coded source threads**: 14 Reddit, seven Steam Community, one IntoFPV and one Drone Hub. It is purposive, English-heavy, self-selected and search-accessible; it is neither exhaustive nor representative. It does not count unique pilots, votes or all comments. Extra discovery links outside this coded set are not counted as user observations in the handoff.

Each user entry preserves its date/qualification, report and limitation. The OpenRC recommendations are our inferences, not claims that the commenters requested this exact product design. No vendor testimonial is counted as an independent user observation. A later thread date does not identify an installed software version, and self-reported aircraft/pilot experience was not verified.

**Two distinct Liftoff version boundaries:** FPV Drone Racing introduced Physics 6.0 on **10 February 2026** [S02](#s02); Micro Drones introduced it on **1 June 2026** [R07](#r07). Do not use an old subjective handling report as a test of those releases. Likewise, EreaDrone's October notes distinguish V2 default from opt-in V3 beta; a title name alone is insufficient comparison identity. [S29](#s29), [S30](#s30)

Sources in this document were accessed on the snapshot date. A `master`, `main`, `stable`, store, manual or product URL is a moving reference. Freeze exact commits/builds, configs, data/license versions and content hashes before implementation or a benchmark. The OpenRC implementation baseline remains the exact commit in 00/06; these new external links do not imply that every competitor has been source-audited at an immutable commit.

## 2. Consumer-facing comparison: 22 products or standalone editions

Related Liftoff, Freerider and VelociDrone editions are counted as separate delivered examples, not independent vendors. DJI Virtual Flight is retained as a maintenance/compatibility case, and Liftoff XR as an alternative interaction model. This is a coverage inventory, not a ranked recommendation to purchase 22 products.

| # | Product / edition | Main approach | Documented evidence | Boundary / caveat | Sources |
| --- | --- | --- | --- | --- | --- |
| 01 | Liftoff: FPV Drone Racing | Broad practice/build/community platform | Free flight, race/freestyle, builds and authoring. Physics 6.0 changed model and record history. | Vendor accuracy claims remain unmeasured here; version/date matters. | [S01](#s01), [S02](#s02), [S24](#s24) |
| 02 | VelociDrone desktop | Race-practice workflow | Time attack, ghosts, documented classes, controller setup and editing. | Manual is workflow evidence, not an independent physical-accuracy result. | [S03](#s03), [S25](#s25) |
| 03 | Uncrashed | Freestyle/creation and replay | Maps, moving-subject practice, editor/sharing, multiplayer and video export. | Current listing describes Physics 3.0; earlier user reports may concern older builds. | [S04](#s04) |
| 04 | TRYP FPV | Exploration and cinematic scenarios | Large environments, chase scenarios, challenges and racing. | Early Access; multiplayer beta and editor announcements need build-specific confirmation. | [S05](#s05), [S06](#s06) |
| 05 | FPV LOGIC | Configured flight and offline AI races | Freestyle/racing and AI opponents; adjustable aircraft parameters. | Early Access and old roadmap text do not prove completion or abandonment. | [S07](#s07) |
| 06 | AI Drone Simulator | Vehicle personalization/content | Blackbox import, tuning and shared/custom environments. | No disclosed reproducible identification-error benchmark on the cited product page. | [S08](#s08) |
| 07 | The Drone Racing League Simulator | Guided league-racing practice | Interactive lessons, league courses, replay and customization. | One-to-one physics language is a vendor claim; transfer was not tested. | [S09](#s09) |
| 08 | DCL — The Game | Accessible modes plus league racing | Named assist modes, Acro, event courses and multiple input types. | Mode names describe different behavior; no automatic cross-mode result equivalence. | [S10](#s10) |
| 09 | FPV Freerider | Compact practice/demo access | FPV/LOS, Acro/self-level, demo and procedural course generation. | Demo deliberately uses a sluggish setup; it is not the full-product tuning baseline. | [S11](#s11) |
| 10 | FPV Freerider Recharged | Separate practice/editor edition | Camera/rate adjustment, control modes and level editing. | Related edition, not an independent vendor; broad physics claims untested here. | [S12](#s12) |
| 11 | Liftoff: Micro Drones | Indoor micro specialization | Micro-focused flight, tutorial and course authoring/sharing. | Its own Physics 6.0 update occurred on 1 June 2026; separate from FPV Racing. | [S13](#s13), [S14](#s14), [R07](#r07) |
| 12 | Tiny Whoop GO | Micro learning/play progression | Flight school, progression, scavenger objectives and custom tracks. | Official pages describe a trial; do not call the whole product permanently free. | [S15](#s15), [S26](#s26) |
| 13 | FPV.SkyDive | Free base with modular extensions | Base flying plus separately offered school/builder/micro/other modules. | Base availability and DLC scope are different; no adoption/popularity inferred. | [S16](#s16), [S27](#s27), [S28](#s28) |
| 14 | FPV Labs — Drone Simulator | Preset-first, deeper tuning | Ready-to-fly and shared presets with aircraft tuning. | Early Access; advertised physics capabilities are not our validation results. | [S17](#s17) |
| 15 | The Zone | Pilot-tuned baseline and observation | Developer describes a tuned freestyle experience and spectating. | Historical/store text has conflicting inventory/roadmap details; do not quote an exact current map count. | [S18](#s18) |
| 16 | EreaDrone | Events, creation and review | Competition, editor, ghost/replay and freestyle spawn workflow. | October 2026 notes: V3 beta opt-in per drone, V2 default during that beta. | [S19](#s19), [S29](#s29), [S30](#s30) |
| 17 | neXt — CGM RC Flight Simulator | Multi-vehicle RC platform | FPV multicopter racing inside a broader RC product. | Not presented as a dedicated racing-quad fidelity benchmark. | [R01](#r01) |
| 18 | FlowState | Open field-practice project | Developer/source emphasize racing practice, low latency and editable content. | Accessible code-copy provenance and exact build/license need review before reuse. | [A25](#a25), [A26](#a26) |
| 19 | CurryKitten FPV Simulator | Accessible community-supported simulator | Developer hosts documentation, issues and distribution links. | README explicitly says it is not open source; public GitHub hosting does not change that. | [A27](#a27) |
| 20 | VelociDrone Mobile | Portable racing practice | Mobile scenes, tracks, asynchronous opponents and radio connection paths. | A standalone deployment example from the same vendor; test actual OS/input method. | [R05](#r05) |
| 21 | Liftoff: XR Drone | Room-relative XR experience | Meta Quest/VR-controller-oriented flight interaction. | Specialized XR example; not equivalent to the desktop racer. | [R06](#r06) |
| 22 | DJI Virtual Flight | Hardware-ecosystem training, historical maintenance case | Vendor documents supported devices and previously released platforms. | Maintenance ended 21 March 2024; existing installs may remain usable. Newer DJI hardware is not universally supported. | [A32](#a32), [A33](#a33) |

## 3. Experimental, firmware and robotics examples — a separate category

These are examined for their architecture or research method. Their inclusion does not mean they are consumer substitutes with a ready training, radio, track-editor and race-management workflow.

| Example | Useful architectural evidence | OpenRC boundary | Sources |
| --- | --- | --- | --- |
| KwadSim / Betaloop | Godot or Gazebo host with external Betaflight | Historical stack/mapping must be pinned; do not infer current Godot 4.8 compatibility | [A07](#a07), [A08](#a08) |
| Betaflight SITL harness | Explicit RC/sensor/motor exchange and scenario tests | The harness calls its own motion model crude; scenario success is not plant validation | [A09](#a09), [A10](#a10) |
| SimITL / pr0p / libfpv | Firmware plus a separate dynamics implementation and host interface | A returned pose is a different physics authority; do not attach it as if it were only a controller | [A11](#a11), [A12](#a12), [A13](#a13) |
| INAV SITL / INAV X-Plane bridge | Firmware-family-specific sensor/control simulation | SITL and a physical-board HITL route have different timing and state guarantees | [A14](#a14), [A15](#a15) |
| WebFPVSimulator | Browser/WASM firmware-and-plant experiment | Research-stage design; actual radio/browser/export qualification remains open | [A28](#a28) |
| Flightmare | Independent rendering and dynamics | Useful design separation; no measured OpenRC performance or physical fidelity follows | [A16](#a16) |
| RotorS / PX4 ecosystem | Vehicle/sensor examples and supported lockstep patterns | Related ecosystem examples, not interchangeable drop-in configurations | [A19](#a19), [A20](#a20) |
| FlightGoggles | Synthetic perception fed by simulated or measured motion | Vehicle-in-the-loop research differs from a seated pilot wearing goggles | [A17](#a17), [A18](#a18) |
| Original AirSim / Project AirSim | Sensor APIs and a changed maintenance path | Distinguish archived Microsoft original from the independently maintained continuation | [A21](#a21), [A22](#a22), [A23](#a23), [A24](#a24) |
| NeuroBEM / ETH data-driven dynamics | Parameter/data/held-out modeling examples | Dataset aircraft and measurement conditions are not the OpenRC product build | [A04](#a04), [A05](#a05), [A06](#a06) |

### Technical corrections carried into the handoff

1. Actual firmware logic does not validate the aircraft plant. A firmware-only sensor/actuator interface and a library returning its own simulated pose are different integrations.
2. Simulation frequency is not measured end-to-end response. At 240 Hz a base interval is about 4.167 ms; a 1 kHz external controller has a different schedule. Timing, fresh observations and candidate-state commit need explicit contracts.
3. Source availability, free distribution and reusable assets are different properties. CurryKitten's public repository explicitly denies open-source status; FlowState's accessible source copy needs provenance/license review before reuse.
4. Photoreal scenery, synthetic sensor realism, human control feel and physical flight agreement are different validation targets. A robotics framework is not automatically a polished FPV training product.
5. A floating-point implementation or complete local recording does not establish cross-platform bitwise identity. Scope replay claims to the tested source/backend/configuration and the existing contract.
6. NeuroBEM's README reports a 0.772 kg dataset aircraft, while the [frozen OpenRC research fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/7bff78490f9af5c1664f47c8ba865a92b3430920/app/physics/multirotor/plant.gd#L35) uses 0.752 kg. Treat that as a configuration/provenance question before borrowing parameters; do not silently change the fixture or imply the dataset validates the selected F50 assembly. The frame/time/data caveats already live in 03. [A04](#a04)

## 4. Community evidence: the 23 coded threads

No exact product defect, common cause, preference prevalence or skill-transfer effect is inferred solely from these reports. Dates may identify the opening post rather than every selected reply; uncertainty is preserved below. Use these entries to choose experiments in 11, not as firmware/physics tuning recipes.

### U01

**[Liftoff or Uncrashed?](https://www.reddit.com/r/fpv/comments/1jc6fuc/liftoff_or_uncrashed/)** — Reddit discussion / r/fpv. **Date:** 2025-03-15.

**Reported:** In the same discussion, one owner prefers Uncrashed after tuning and likes custom maps and shared presets. Another finds Uncrashed floaty and Liftoff more realistic, while a third says the reverse about Liftoff.

**Limit:** Historical Liftoff: FPV Drone Racing feedback, before Physics 6.0.

### U02

**[Velocidrone, FPV Logic, The Zone - another sim thread](https://www.reddit.com/r/fpv/comments/1r7epng/velocidrone_fpv_logic_the_zone_another_sim_thread/)** — Reddit discussion / r/fpv. **Date:** 2026-02-17.

**Reported:** The poster calls VelociDrone the floatiest of their named sims and likes FPV Logic maps; another participant prefers The Zone for 5-inch and 3.5-inch models configured to match their own aircraft. A different commenter values muscle-memory practice despite imperfect feel.

**Limit:** Post-Physics 6.0 release date, but participants’ exact simulator builds and settings are unspecified.

### U03

**[air65 sims vs reality](https://www.reddit.com/r/TinyWhoop/comments/1mzcurs/air65_sims_vs_reality/)** — Reddit discussion / r/TinyWhoop. **Date:** 2025-08 (thread indexed with 25 August comments; precise submission day unconfirmed).

**Reported:** A poster comparing an Air65 on one real and simulated track likes Liftoff Micro’s overall handling but dislikes its low-throttle response and ground contact; they prefer VelociDrone throttle but say its aircraft skates more. Another commenter has a different throttle-accuracy impression.

**Limit:** August 2025 historical Micro Drones feedback, before that product’s own Physics 6.0 release on 1 June 2026; exact submission day is unconfirmed. This is separate from FPV Drone Racing’s February release.

### U04

**[Best tinywhoop sim?](https://www.reddit.com/r/TinyWhoop/comments/1uy5rdt/best_tinywhoop_sim/)** — Reddit discussion / r/TinyWhoop. **Date:** 2026-07-16.

**Reported:** A beginner seeks a first-whoop match. One commenter says Liftoff Micro was motivating, while another wishes for smaller rooms after feeling overconfident indoors; a different participant likes the scale of VelociDrone micro tracks. The Zone is praised for feel but criticized for limited content by one participant.

**Limit:** User reports; exact versions and physical setups unspecified.

### U05

**[What is the best fpv simulator of 2024](https://www.reddit.com/r/fpv/comments/1g44q0v/what_is_the_best_fpv_simulator_of_2024/)** — Reddit discussion / r/fpv. **Date:** 2024-10-15.

**Reported:** One participant likes FPV Logic for flowing freestyle gaps but misses the custom tracks and opponent-time practice they associate with VelociDrone. Others disagree on which product feels closest; another praises Uncrashed’s visuals and online community but criticizes collision behavior.

**Limit:** Historical Liftoff: FPV Drone Racing feedback, before Physics 6.0; community claims about available features are not a current feature inventory.

### U06

**[Velocidrone vs. Liftoff: Micro Drones](https://intofpv.com/t-velocidrone-vs-liftoff-micro-drones?pid=244628)** — IntoFPV forum discussion. **Date:** 2026-04-26 to 2026-04-27.

**Reported:** A micro racer values the availability of their national championship tracks. A freestyle respondent values modifying community maps and dislikes a forced career gate that removed access to previously enjoyed scenes. Other participants discuss hardware and loading constraints.

**Limit:** Reported user experiences and feature expectations from April 2026, not independent verification of current product behavior.

### U07

**[Tryp FPV is my new favourite, unattainable sim](https://dronehub.co.uk/t/tryp-fpv-is-my-new-favourite-unattainable-sim/6095)** — Drone Hub forum discussion. **Date:** 2025-10-13.

**Reported:** A flyer enjoyed TRYP’s large exploratory spaces on a borrowed gaming laptop but said their own PC was not capable of running it. Another participant appreciated scenery while wanting takeoff/landing practice.

**Limit:** Single-user hardware comparison; not a controlled benchmark.

### U08

**[Sim on low end laptop](https://www.reddit.com/r/fpv/comments/1edeei9/sim_on_low_end_laptop/)** — Reddit discussion / r/fpv. **Date:** 2024-07-27.

**Reported:** A low-end laptop owner asks for accessible software. One commenter says TRYP ran worse than Liftoff and Uncrashed; another reports the opposite kind of disparity, with Liftoff usable and VelociDrone and Uncrashed unsmooth on their older machine.

**Limit:** Hardware is not standardized; opinions do not rank current releases or machines.

### U09

**[All settings reset after today update](https://steamcommunity.com/app/410340/discussions/0/797842031905989292/)** — Steam community discussion / Liftoff. **Date:** 2026-04-23 (year inferred from Steam’s current-year display).

**Reported:** A Linux/TX12 user reports calibration, inversions and switches breaking after an update. A developer suggests recalibration and rebinding after changed controller identification, but the original poster says some issues remained after recalibration; another user reports recovering quickly.

**Limit:** Specific reported update and configuration, not evidence that every controller is affected.

### U10

**[Liftoff Microdrones throttle problem](https://www.reddit.com/r/fpv/comments/1qxt0rk/liftoff_microdrones_throttle_problem/)** — Reddit discussion / r/fpv. **Date:** 2026-02-06.

**Reported:** A Pocket user reports half-range throttle in Micro Drones despite multiple calibrations, while Uncrashed works for them. A Linux user reports a workaround involving remapping a channel, with a tradeoff in arming; the cause is not independently established.

**Limit:** Specific anecdote; the community explanation is a hypothesis, not an established root cause.

### U11

**[First time using a controller. Can’t assign Arm in FPV SkyDive](https://www.reddit.com/r/fpv/comments/sxdeof/first_time_using_a_controller_cant_assign_arm_in/)** — Reddit discussion / r/fpv. **Date:** 2022-02-20.

**Reported:** A first-time radio user can calibrate axes but cannot assign arm or restart and is unfamiliar with mixer/channel setup. A commenter proposes adding channels; later replies show the same advice is not a proven fix for everyone.

**Limit:** Historical thread; no current compatibility conclusion follows.

### U12

**[Restart/ReSet mapping for radios ...add more races per map](https://steamcommunity.com/app/1682970/discussions/0/3821907263112358191/)** — Steam community discussion / Uncrashed. **Date:** 2023-03-26.

**Reported:** A flyer requests a radio-bound reset and likes the ability to enter a race from free flight. A developer replies that reset can already be mapped, suggesting a discoverability gap for this person at that time.

**Limit:** The contemporaneous developer reply is included to avoid claiming reset was absent.

### U13

**[velocidrone leaderboards?](https://www.reddit.com/r/Velocidrone/comments/1igis3n/velocidrone_leaderboards/)** — Reddit discussion / r/Velocidrone. **Date:** 2025-02-03.

**Reported:** A flyer finds leading times hard to interpret. Participants suggest viewing or racing ghosts and differ on how much aircraft choice versus line precision explains the gap.

**Limit:** Individual opinions about competitive performance, not proof of cheating or relative skill.

### U14

**[Trying to learn via DRL on Steam, can you change the beginner tutorial to use FPV?](https://www.reddit.com/r/fpv/comments/1icd2e0/trying_to_learn_via_drl_on_steam_can_you_change/)** — Reddit discussion / r/fpv. **Date:** 2025-01-28 (later replies in February and August 2025).

**Reported:** A beginner says the jump from third-person assisted exercises to first-person less-assisted flight is too abrupt. The same user later appreciates demonstrated inputs in Liftoff, while another finds DRL easier and Liftoff discouraging.

**Limit:** Historical tutorial feedback; features and designs can have changed.

### U15

**[Tutorial](https://steamcommunity.com/app/410340/discussions/0/569290345532228113/)** — Steam community discussion / Liftoff. **Date:** 2026-06-28 (year inferred from Steam’s current-year display).

**Reported:** A beginner dislikes unskippable or hard-to-skip presentation and mid-flight text interruptions. Another says repeating explanatory sections after getting stuck prompted a refund request; the developer agrees a tutorial update is planned.

**Limit:** The developer’s planned update is not evidence it has shipped.

### U16

**[is Liftoff tutorial really for beginners?](https://www.reddit.com/r/fpv/comments/1lfg7pp/is_liftoff_tutorial_really_for_beginners/)** — Reddit discussion / r/fpv. **Date:** 2025-06-19.

**Reported:** A first-hour learner struggles with sensitive controls and figure-eight obstacles. Replies disagree: some suggest progressively teaching basics or changing rates; another considers the tutorial worthwhile with practice. A separate commenter finds DRL’s restricted-mode transitions frustrating.

**Limit:** Historical Liftoff: FPV Drone Racing feedback, before Physics 6.0; training complaints are not a physics benchmark.

### U17

**[What is best FPV drone simulator for beginner in 2023?](https://www.reddit.com/r/fpv/comments/16c2o2j/what_is_best_fpv_drone_simulator_for_beginner_in/)** — Reddit discussion / r/fpv. **Date:** 2023-09-07.

**Reported:** Two participants praise DRL’s ordered skill lessons despite frustration; another uses Liftoff for cinematic and stunt practice while preferring DRL for learning.

**Limit:** Historical opinions; no claim about current lesson quality.

### U18

**[What FOV and screen ratio do you set in simulators?](https://www.reddit.com/r/fpv/comments/10jd38c/what_fov_and_screen_ratio_do_you_set_in_simulators/)** — Reddit discussion / r/fpv. **Date:** 2023-01-23.

**Reported:** One participant preferred different field-of-view settings in Liftoff and DRL and described distortion/aspect differences; another later wanted more visibility in Uncrashed. No universal camera setting follows.

**Limit:** Perception and settings are individual; do not adopt the numerical values as universal defaults.

### U19

**[Which simulator for starting out in 2025?](https://www.reddit.com/r/fpv/comments/1jq3kim/which_simulator_for_starting_out_in_2025/)** — Reddit discussion / r/fpv. **Date:** 2025-04-02 (thread opening; selected comment dates not individually established).

**Reported:** A prospective pilot wants to practice before buying a drone. One respondent recommends a whoop-focused experience for indoor goals; another favors FPV SkyDive’s lessons, while a different respondent strongly dislikes TRYP.

**Limit:** The discussion opening date does not establish the date of every later reply.

### U20

**[Feature Request: Optional & Adjustable Latency](https://steamcommunity.com/app/410340/discussions/0/2270320616975703296/)** — Steam community discussion / Liftoff. **Date:** 2020-04-27.

**Reported:** A flyer requests adjustable input or video delay to reduce the mismatch they perceive between simulator and outdoor flights. A developer describes implementation complications involving frame timing and device sampling.

**Limit:** Historical design discussion, not a measurement of present Liftoff latency.

### U21

**[Multiplayer](https://steamcommunity.com/app/1682970/discussions/0/3195862975786575548/)** — Steam community discussion / Uncrashed. **Date:** 2021-11-26 (comment 2021-11-30).

**Reported:** The poster wants to fly with friends; another says shared flight rooms are a reason they spend time in flight sims. A participant questions the value if friends cannot be seen doing maneuvers.

**Limit:** A 2021 feature request, not a statement of present Uncrashed functionality.

### U22

**[Busted physics in racing mode?](https://steamcommunity.com/app/410340/discussions/0/601911155312688063/)** — Steam community discussion / Liftoff. **Date:** 2025-07-29 (follow-up 2025-08-02).

**Reported:** A pilot reports a different feel and erratic takeoffs across race maps. Another reports large jumps when struggling to run particular maps; a developer suggests performance as an explanation for that user and requests environment and setup details.

**Limit:** Historical Liftoff: FPV Drone Racing feedback before Physics 6.0; the root cause of the original poster’s issue was not established.

### U23

**[Please support Radiomaster Pocket SE button](https://steamcommunity.com/app/1682970/discussions/0/4625853071149315442/)** — Steam community discussion / Uncrashed. **Date:** 2024-11-02.

**Reported:** A Pocket owner wants to bind a momentary button as reset but says it is not recognized; another participant asks whether the switch was added to a radio channel. The discussion does not establish which layer caused the problem.

**Limit:** Historical report; do not infer a current compatibility defect or diagnose the radio remotely.

## 5. Primary product and release sources

Each short evidence note identifies what the source supports. General claims of realism, exact replication, optimal tuning or market leadership remain the author's claims unless separately measured. Store/FAQ descriptions can lag builds; the dated release source takes precedence for the specific change it describes.

### S01

[Liftoff: FPV Drone Racing](https://www.liftoff-game.com/liftoff-fpv-drone-racing) — official vendor.

Free flight, race, freestyle, tutorials, controller setup, track and race building and community content.

### S02

[Milestone 1.7.0 released!](https://www.liftoff-game.com/news/milestone-170-released) — official vendor update, 2026-02-10.

Physics 6.0, propeller and drag changes, power warnings and wind initially limited to single-player free flight.

### S03

[VelociDrone desktop manual](https://www.velocidrone.com/desktop_manual) — official vendor manual.

Controller setup, quick start, views, track editor, race rules and gate guidance, ghosts, leaderboards, wind and track sharing.

### S04

[Uncrashed: FPV Drone Simulator](https://store.steampowered.com/app/1682970/Uncrashed_FPV_Drone_Simulator/) — developer storefront description.

Physics 3.0 claims; freestyle maps, chase, customization, editor/Workshop, multiplayer and replay/video export.

### S05

[TRYP FPV: Drone Racer Simulator](https://store.steampowered.com/app/1881200/TRYP_FPV__The_Drone_Racer_Simulator/) — developer storefront description.

Early Access; flight and aerodynamic claims, exploration, challenges, racing and moving-subject scenarios.

### S06

[TRYP FPV official announcements](https://steamcommunity.com/app/1881200/announcements/) — developer announcements.

Developer characterizes multiplayer as beta, map editor as upcoming, and aerodynamic features as work in progress; later announcements may supersede this snapshot.

### S07

[FPV LOGIC](https://store.steampowered.com/app/2398030/FPV_LOGIC/) — developer storefront description.

Flight customization, multiple views, up to 20 AI drones and joystick support; Early Access notice and stale stated 2024 full-release target.

### S08

[AI Drone Simulator](https://store.steampowered.com/app/1608560/AIDroneSim/) — developer storefront description.

Blackbox import, dynamic environments, user assets, vehicle and map sharing; fidelity claim lacks a published protocol on this page.

### S09

[The Drone Racing League Simulator](https://store.steampowered.com/app/641780/) — developer storefront description.

Interactive tutorial, race replays, league tracks, drone/course building and cross-platform multiplayer; one-to-one physics is a developer claim.

### S10

[DCL - The Game](https://store.steampowered.com/app/964570/DCL/) — developer storefront description.

Arcade, GPS, Angle and Acro modes; keyboard, gamepad and transmitter; racing and competition.

### S11

[FPV Freerider](https://fpv-freerider.itch.io/fpv-freerider) — official developer product page.

Procedural track generation, controller guidance, desktop versions and a deliberately sluggish one-scenery demo; newest displayed changelog dated 2021.

### S12

[FPV Freerider Recharged](https://store.steampowered.com/app/813530/FPV_Freerider_Recharged/) — developer storefront description.

FPV/LOS, self-level/Acro/inverted thrust, modes 1–4, rate and camera tuning, level editor, controller support.

### S13

[Full Release: Liftoff: Micro Drones](https://www.liftoff-game.com/news/full-release-liftoff-micro-drones) — official vendor release notes.

Micro-class product; track builder, gates, triggers, snapping, Workshop, replay review and race-guide options.

### S14

[Liftoff: Micro Drones milestone 0.6.0](https://www.liftoff-game.com/news/milestone-060-released) — official vendor update, 2023-09-16.

Interactive tutorial spanning fundamental and racing skills.

### S15

[Tiny Whoop GO](https://www.tinywhoopgo.com/) — official product website.

30-track progression, non-racing scavenger hunts, interactive flight school, track building and online play; free trial.

### S16

[FPV SkyDive](https://orqafpv.com/products/skydive) — official vendor product page.

Flight School, Track Builder, Micro Drone and Drone Soccer are separate DLC modules.

### S17

[FPV Labs - Drone Simulator](https://store.steampowered.com/app/4038160/FPV_Labs__Drone_Simulator/) — developer storefront description.

2026 Early Access; presets, advanced customization, real-time adjustment and community presets; physics accuracy remains vendor claim.

### S18

[The Zone - FPV Drone Simulator](https://store.steampowered.com/app/3491280/The_Zone_FPV_Drone_Simulator/) — developer storefront description.

Pilot-tuned defaults, freestyle and multiplayer spectating; Early Access. Descriptive text mixes current information with historical and roadmap material.

### S19

[EreaDrone: FPV Drone Simulator](https://store.steampowered.com/app/1301060/EreaDrone_FPV_Drone_Simulator/) — developer storefront description.

Racing, spectating, user track creation, common radio and rates options, FAI event claims and third-party-account requirement; Steam's focus on V2 is incomplete given the October 2026 optional V3 beta, while V2 remained default during the beta.

### S24

[Liftoff simulations](https://www.liftoff-game.com/liftoff-simulations) — official vendor technical description.

Vendor describes individual component modeling and use of CFD/test data. The page is marketing/technical description, not a reproducible external validation dataset; avoid unverified physical details from the page.

### S25

[MultiGP eSport](https://www.multigp.com/esport/) — official racing-league website.

The league identifies VelociDrone as its official simulator and describes online competition.

### S26

[Tiny Whoop home page](https://www.tinywhoop.com/) — official vendor website.

Describes the Tiny Whoop GO free trial as two weeks, not a permanently free full simulator.

### S27

[FPV SkyDive: FPV Drone Simulator](https://store.steampowered.com/app/1278060/FPVSkyDive__FPV_Drone_Simulator/) — developer storefront description.

Orqa describes the base simulator as free-to-play and separately lists paid content modules.

### S28

[FPV.SkyDive calibration FAQ](https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/1278060/manuals/FPV.SkyDive_Calibration_FAQ__4_2022_.pdf?t=1743069505) — official developer calibration manual.

Describes supported controller categories and joystick calibration; device compatibility should still be tested.

### S29

[Physics V3 BETA, Replay & Export, New UI, and more!](https://ereadrone.com/en/news/699901423506162998) — official vendor update, 2026-10-14.

V3 beta opt-in per aircraft with V2 default during beta; changes to motor response, latency options and lap replay/export. Freestyle recording is separately documented in S30.

### S30

[New Map Explorer for Freestyle, new Bando!](https://ereadrone.com/en/news/717919626870134385) — official vendor update, 2026-10-23.

Freestyle map explorer, spawn selection, replay recording and V3 beta still opt-in per drone while V2 remains default.

## 6. Architecture, firmware, engine and research sources

The IDs here use **A** to distinguish them from the product sources. Branch and engine-documentation versions are part of the limitation, not implicit upgrade instructions. The source licenses cited in project material do not authorize copying every bundled model or third-party asset.

### A02

[Betaflight Blackbox logging and usage](https://github.com/betaflight/betaflight.com/blob/master/docs/wiki/guides/current/Black-Box-logging-and-usage.md) — official firmware documentation.

**Supports:** Lists recorded fields, decoding tools and possible dropped frames. **Limit:** Field availability, sample rate and behavior depend on firmware and configuration.

### A03

[Betaflight CLI reference](https://github.com/betaflight/betaflight.com/blob/master/docs/wiki/guides/current/Cli.md) — official firmware documentation.

**Supports:** Blackbox sample rate and field disables are configurable; RPM telemetry requires feature support. **Limit:** Moving reference; pin firmware and documentation versions.

### A04

[NeuroBEM dataset README](https://rpg.ifi.uzh.ch/neuro_bem/Readme.html) — dataset authors.

**Supports:** Describes 400 Hz flight state and individual motor-speed dataset, FLU body frame, voltage, raw Betaflight logs, and 0.772 kg aircraft mass. **Limit:** Dataset and OpenRC fixture mass differ; configuration or provenance must be reconciled.

### A05

[NeuroBEM project and publication](https://rpg.ifi.uzh.ch/NeuroBEM.html) — research project authors.

**Supports:** Describes hybrid physics and learned quadrotor aerodynamics and its specific evaluation. **Limit:** Results concern the study aircraft and envelope, not every FPV build.

### A06

[Data-driven dynamics modeling](https://github.com/ethz-asl/data-driven-dynamics) — research authors source repository.

**Supports:** Parametric modeling pipeline estimates selected vehicle models from ULog or CSV. **Limit:** Availability of code does not identify an unmeasured racing build.

### A07

[KwadSim](https://github.com/timower/KwadSim) — project source repository.

**Supports:** Godot 3.2 FPV project runs Betaflight in an independently restartable server; project identifies GPL-3.0. **Limit:** Historical Godot version and project license require review; no claim of measured physical fidelity.

### A08

[Betaloop](https://github.com/Aeroloop/betaloop) — project source repository.

**Supports:** Betaflight/Gazebo supports FPV and radio and documents differing motor mappings. **Limit:** Setup requires a particular historical Gazebo stack; mapping is implementation-specific.

### A09

[Betaflight SITL/Gazebo container README](https://github.com/betaflight/betaflight/blob/master/.devcontainer/README.md) — official firmware repository.

**Supports:** Documents example UDP RC, sensor and motor feeds and MSP proxy. **Limit:** Branch-specific protocol/port conventions are not universal across all versions.

### A10

[Betaflight SITL test harness](https://github.com/betaflight/betaflight/blob/master/src/test/sitl/sitl_harness.py) — official firmware repository.

**Supports:** Demonstrates scenario-driven SITL with UDP, MSP and an explicitly crude motion model. **Limit:** The harness tests control scenarios, not racing-quad physical fidelity.

### A11

[SimITL](https://github.com/AJ92/SimITL) — project source repository.

**Supports:** Betaflight SITL wrapper outputs simulated orientation and speed; GPL-3.0. **Limit:** Its physics is not a transparent firmware-only plug-in.

### A12

[pr0p](https://pr0p.dev/) — developer project website.

**Supports:** Describes SimITL computing dynamics from motor outputs and communicating with Unity. **Limit:** Project feature and realism statements are not independent validation.

### A13

[libfpv](https://github.com/hammerill/libfpv) — project source repository.

**Supports:** Describes C interface, host-provided collision/rendering, separate 1 kHz simulation thread and SimITL/Betaflight. **Limit:** 1 kHz and use of firmware do not establish measured latency or physical accuracy; review GPL terms and dependencies.

### A14

[INAV Configurator release notes](https://github.com/iNavFlight/inav-configurator/releases) — official firmware organization release notes.

**Supports:** Describes bundled SITL binaries for specified Windows, macOS and Linux architectures. **Limit:** Individual release and target support must be pinned.

### A15

[INAV X-Plane HITL/SITL](https://github.com/RomanLut/INAV-X-Plane-HITL) — project source repository.

**Supports:** Project describes virtual sensors supplied to flight controller and returned control outputs. **Limit:** Independent project and setup/version restrictions; not a claim of official OpenRC compatibility.

### A16

[Flightmare](https://github.com/uzh-rpg/flightmare) — research project source repository.

**Supports:** Separates Unity renderer and dynamics; offers research sensor, Python and ROS interfaces; MIT license. **Limit:** Robotics/autonomy research framework, not a verified consumer FPV racing simulator.

### A17

[FlightGoggles architecture and installation](https://mit-aera.github.io/FlightGoggles-Documentation/Installation_392888321.html) — research project documentation.

**Supports:** Documents renderer/client separation, synthetic sensors, pose input and multicopter/IMU library. **Limit:** Research setup is different from a consumer FPV headset.

### A18

[FlightGoggles research publication](https://dspace.mit.edu/entities/publication/d463c208-38ea-4069-8e9e-68e9695db220) — institutional publication record.

**Supports:** Describes synthetic exteroceptive sensors with a real motion-captured flying vehicle. **Limit:** Vehicle-in-the-loop is not fully simulated dynamics or a normal seated consumer race.

### A19

[RotorS simulator](https://github.com/ethz-asl/rotors_simulator) — research project source repository.

**Supports:** Describes Gazebo multirotor models, sensors, examples and joystick interface. **Limit:** Does not prove drop-in compatibility with current PX4/Gazebo versions.

### A20

[PX4 simulation guide](https://docs.px4.io/main/en/simulation/) — official project documentation.

**Supports:** Describes lockstep and speed control for supported simulators. **Limit:** Moving main-branch documentation; do not assume lockstep for unrelated bridges.

### A21

[Original Microsoft AirSim](https://github.com/microsoft/AirSim) — official original project repository.

**Supports:** Describes Unreal plugin, experimental Unity, sensor API and PX4/ArduPilot simulation integrations. **Limit:** Autonomy research orientation and original-project maintenance status.

### A22

[Microsoft Research AirSim archival statement](https://www.microsoft.com/en-us/research/project/aerial-informatics-robotics-platform/) — original developer institutional statement.

**Supports:** Says original AirSim is archived and no further updates will be made. **Limit:** Different from independently maintained successor project.

### A23

[Microsoft Project AirSim announcement](https://github.com/microsoft/AirSim/blob/main/project_airsim.md) — original developer announcement.

**Supports:** Describes Microsoft/IAMAI Project AirSim release and IAMAI repository. **Limit:** Historic original AirSim archival notice and successor should not be conflated.

### A24

[IAMAI Project AirSim](https://github.com/iamaisim/ProjectAirSim) — current project maintainer repository.

**Supports:** Describes independently maintained MIT-licensed engine-independent core and optional Unreal. **Limit:** Maintainer claims do not prove human FPV racing fitness or accuracy.

### A25

[FlowState Steam listing](https://store.steampowered.com/app/1209750/) — developer product page.

**Supports:** Developer describes open-source racing game and asks for real-aircraft comparisons. **Limit:** Developer claims and early-access goals are not independent validation.

### A26

[FlowState accessible source copy](https://github.com/brucesdad13/FlowState) — public project source copy.

**Supports:** Identifies GPL-3.0 and goals for latency, FPV visuals, field use, and practice. **Limit:** README refers to another original repository; trace provenance and licenses before reuse.

### A27

[CurryKitten Simulator](https://github.com/CurryKitten/CurryKitten-Sim) — developer project repository.

**Supports:** Developer explicitly states it is not an open-source project; repository hosts other materials. **Limit:** Free or publicly hosted resources do not imply source-code licensing.

### A28

[WebFPVSimulator](https://github.com/Mathew-Harvey/WebFPVSimulator) — project source repository.

**Supports:** README describes Betaflight 4.5.1 in WASM, a plant, gamepad radio input and touch controls. **Limit:** Research-stage author claims do not establish hardware compatibility or plant validation for OpenRC.

### A29

[WebHID API](https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API) — browser platform technical documentation.

**Supports:** Documents limited browser availability of WebHID. **Limit:** A Gamepad-compatible transmitter may not require WebHID.

### A30

[HID requestDevice](https://developer.mozilla.org/en-US/docs/Web/API/HID/requestDevice) — browser platform technical documentation.

**Supports:** Documents secure-context, user-activation and permission requirements. **Limit:** Availability differs by browser and platform.

### A31

[Godot 4.5 web export](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html) — official engine documentation.

**Supports:** Describes WASM/WebGL2 and threading isolation requirements. **Limit:** Version 4.5 documentation; verify behavior for OpenRC pinned engine before implementation.

### A32

[DJI Virtual Flight download and discontinuation](https://www.dji.com/downloads/softwares/dji-virtual-flight) — official vendor notice.

**Supports:** Maintenance ended 21 March 2024; already downloaded app can continue. **Limit:** Vendor notice is specifically about DJI Virtual Flight.

### A33

[DJI Virtual Flight supported devices](https://repair.dji.com/help/content?customId=01700008917&lang=en&paperDocType=ARTICLE&re=US&spaceId=17) — official vendor support article.

**Supports:** Names supported/unsupported DJI devices and Windows goggles limitation for DJI Virtual Flight. **Limit:** Does not rule out other third-party simulators or unrelated hardware methods.

### A34

[Godot Android OpenXR deployment](https://docs.godotengine.org/en/stable/tutorials/xr/deploying_to_android.html) — official engine documentation.

**Supports:** Discusses Android headset setup, renderer and OpenXR loader considerations. **Limit:** Not proof a particular device or OpenRC build is compatible.

## 7. Additional primary comparisons and version checks

### R01

[neXt — CGM RC Flight Simulator](https://www.cgm-online.com/rc-flight-simulator/rc-flight-simulator_e.html) — Official product page.

**Supports:** A wider RC simulator includes multicopters, FPV courses, other aircraft classes and transmitter support. **Limit:** Product breadth does not establish a shared-kernel implementation or measured accuracy.

### R02

[Liftoff Physics 5.0 ready for testing — 20 September 2021](https://www.liftoff-game.com/news/physics-50-ready-testing) — Historical developer technical announcement.

**Supports:** Controller and force-processing redesign addressed host-engine update cost, stability and usability. **Limit:** Historical architectural rationale; its screenshots are not a current benchmark or OpenRC performance target.

### R03

[FAI e-Drone Racing World Cup Rules — May 2025](https://www.fai.org/sites/default/files/ciam/wcup_drones/fai_rules_2025_fai_edrone_racing_world_cup.pdf) — Historical rules-owner publication.

**Supports:** Documents event aircraft constraints and explicit start, gate and crash rules for the named 2025 format. **Limit:** Not asserted to be the current 2026 rulebook. OpenRC M3 does not claim compliance with this format.

### R04

[MultiGP Global Qualifier](https://www.multigp.com/globalqualifier/) — Official league page, 2026 content inspected.

**Supports:** A common published track supports an event series across locations. **Limit:** Provides a format/example, not OpenRC certification or proof of real-flight transfer.

### R05

[VelociDrone for Android / iOS](https://www.velocidrone.com/mobile) — Official mobile product page.

**Supports:** Describes mobile practice, stylized scenes, shared tracks/Nemesis and custom transmitter connectivity. **Limit:** Radio-connection restrictions are specific to this product/platform path; no OpenRC mobile compatibility was tested.

### R06

[Liftoff: XR Drone](https://www.liftoff-game.com/our-products/liftoff-xr-drone) — Official product page with 2024 launch/update links.

**Supports:** Describes a Meta Quest-oriented augmented-reality/VR-controller flight experience. **Limit:** Different from a radio-controlled desktop FPV racer or a universal PC-goggles compatibility claim.

### R07

[Liftoff: Micro Drones milestone 1.1.0 — 1 June 2026](https://www.liftoff-game.com/news/milestone-110-released) — Official dated release note.

**Supports:** Introduced Micro Drones Physics 6.0, changed flight-model components and archived older leaderboard scores. **Limit:** Separate release history from Liftoff: FPV Drone Racing; old micro user reports are not current handling measurements.

## 8. Research disposition and remaining evidence

**Completed in this task:** primary-source and community reading; source classification; 28 investigation cards; a 22-product/edition coverage inventory; the 23-thread coded qualitative sample; dated feature/version corrections; product/engineering recommendations; 12 proposed experiments, 13 proposed acceptance cases and P22–P24; independent review for factual and architecture consistency.

**Not completed or claimed:** hands-on competitor comparison, installed-version confirmation on a local test machine, measured input/graphics latency, a representative survey, real-pilot recruitment, physical aircraft measurements, implementation of new OpenRC runtime features, or empirical proof of training transfer. Existing OpenRC and extracted-firmware probes are recorded separately in 06/09 and were not rerun for this desk study.

To adopt the research, update the existing canonical drone plan and link these decisions under the original DR ownership. Keep descriptive market research dated; keep current runtime instructions and actual acceptance results in their existing authoritative homes. The full proposal must be reconciled with any repository changes after the frozen OpenRC commit.
