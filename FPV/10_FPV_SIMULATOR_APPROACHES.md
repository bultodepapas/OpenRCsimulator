# FPV simulator research — 28 distinct approaches for OpenRC

**Research date:** 11 November 2026. **Audience:** senior Godot, simulation, controls, gameplay and product developers. **Purpose:** strengthen the existing FPV plan with researched product patterns, user needs, implementation consequences and validation work. This is a comparative desk study, not a hands-on simulator ranking.

**Companion documents:** [11 — decisions, experiments and backlog](11_FPV_PRODUCT_DECISIONS_AND_EXPERIMENTS.md); [12 — product comparison, 23 user discussions and source ledger](12_SIMULATOR_EVIDENCE_LEDGER.md). The previous [34 Betaflight/INAV settings investigations](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) remain part of the same handoff.

## 1. Scope and evidence discipline

An **approach** is a distinct way to serve a pilot or construct the simulator: race practice, indoor specialization, log-based identification, a firmware controller, or a browser entry point. Several products combine several approaches. This report does not present 28 brands as if each had a single exclusive design.

The evidence covers 22 consumer-facing products or standalone editions, including DJI Virtual Flight, whose maintenance ended, and a specialized XR product; related editions are not independent vendors. It also examines experimental projects and robotics simulators separately. The comparison table in 12 names each example and its scope.

Community evidence is a purposive sample of **23 opened and coded discussion threads**: 14 Reddit, seven Steam Community, one IntoFPV and one Drone Hub. The unit counted is a thread, not a unique pilot or review. It is not a representative survey, and no percentages or popularity rankings are inferred. Older reports identify useful failure modes but cannot establish present feature availability or current physical accuracy. Liftoff: FPV Drone Racing introduced Physics 6.0 on 10 February 2026; the separate Micro Drones product followed on 1 June 2026. Their version histories must not be conflated. [S02](12_SIMULATOR_EVIDENCE_LEDGER.md#s02), [R07](12_SIMULATOR_EVIDENCE_LEDGER.md#r07)

Each investigation distinguishes:

- **Documented example:** a vendor, manual, developer repository or paper describes a capability. This is not an independent accuracy measurement.
- **User signal:** a selected experience, including disagreement and its date, where available. Otherwise the proposed user value is explicitly an inference.
- **OpenRC decision:** our recommendation, constrained by the existing architecture and milestones.
- **Verification:** concrete work that would test the recommendation; these are proposed checks, not executed results.

No store review averages, estimated sales, unsupported engine labels, prices or “most realistic” rankings are used to choose the architecture. Official sources support technical/product claims; community sources support statements about experiences. Source IDs below resolve to the ledger in 12.

## 2. Investigation map

**Now** means M0–M2 foundations or usability. **Race** means M3 or the first compatible local-practice iteration after it. **Later** means a separate optional capability; it does not block M2/M3. “Research now, integrate later” means preserving interfaces/data today without committing to the feature.

| ID | Distinct approach | Relevant examples | OpenRC disposition |
| --- | --- | --- | --- |
| SIM-01 | Race practice built around repeatability | VelociDrone | Race |
| SIM-02 | Real event tracks and league rehearsal | DRL, DCL, MultiGP/VelociDrone, EreaDrone | Data/rules now; official formats later |
| SIM-03 | Freestyle playground and flow | Uncrashed, FPV LOGIC | One useful field now |
| SIM-04 | Cinematic exploration and moving-subject chase | TRYP FPV, Uncrashed | Later |
| SIM-05 | Indoor micro-drone specialization | Liftoff: Micro Drones, Tiny Whoop GO | Separate class later |
| SIM-06 | Explicit assistance and staged control learning | DCL, Liftoff Micro | Acro/Angle now; broader aids later |
| SIM-07 | Real-radio transfer and observable setup | Freerider Recharged, FPV.SkyDive | Now |
| SIM-08 | Short-session practice and dependable reset | VelociDrone, EreaDrone | Now |
| SIM-09 | Goal-oriented lessons and skill drills | DRL, Tiny Whoop GO | Small optional drills after usable flight |
| SIM-10 | Ghosts, splits and replay as coaching | VelociDrone, EreaDrone | Complete recorder now; coaching after M3 |
| SIM-11 | Shared flying and spectator learning | Liftoff, Uncrashed, EreaDrone | Later |
| SIM-12 | Creator tools and community course content | Liftoff Micro, AI Drone, Freerider | Strict data now; editor later |
| SIM-13 | Component-based physical builds | Liftoff | One sourced build now |
| SIM-14 | Identify a pilot's vehicle from flight data | AI Drone, NeuroBEM/ETH research | Research now; importer later |
| SIM-15 | Run actual firmware in a simulation loop | KwadSim, Betaloop, Betaflight/INAV SITL | Separate experiment later |
| SIM-16 | Simulator-owned controller designed for the host | Liftoff Flight Controller | Now, independently qualified |
| SIM-17 | Disturbances and degradation as selectable training | Liftoff, VelociDrone | Basic admitted energy now; advanced effects later |
| SIM-18 | Versioned rules and fair comparable results | Liftoff revisions, league formats | Identities now; local class policy at M3 |
| SIM-19 | Frame pacing and scalable graphics as a core feature | FlowState, VelociDrone Mobile | Native 1080p now |
| SIM-20 | Match the FPV sensory interface | Freerider, EreaDrone, FlightGoggles research | Rigid calibrated view now |
| SIM-21 | Low-friction access through free/demo/browser entry | FPV.SkyDive, Freerider, WebFPVSimulator | Simple local entry now; web spike later |
| SIM-22 | Portable mobile practice | VelociDrone Mobile | Later, actual-device qualification |
| SIM-23 | XR and hardware-ecosystem experiences | Liftoff XR, DJI Virtual Flight | Later, separate support matrix |
| SIM-24 | Open development and modifiable simulation | FlowState, KwadSim | Transparent data/research now |
| SIM-25 | Decoupled headless dynamics and rendering | Flightmare, RotorS/PX4 ecosystem | Preserve current boundary |
| SIM-26 | Synthetic sensors and autonomy research | FlightGoggles, AirSim/Project AirSim | Research reference, separate product scope |
| SIM-27 | FPV inside a wider RC simulator | neXt, OpenRC's existing platform | Preserve shared kernel and fleet contracts |
| SIM-28 | Offline controller-driven AI competition | FPV LOGIC | Later; ghosts first |

The following cards provide the evidence and reasoning behind every row.

## 3. Pilot goals and practice workflows

### SIM-01 — Race practice built around repeatability

**Documented example.** VelociDrone describes time attack, personal/leaderboard ghosts and competition classes; MultiGP identifies it as its simulator. [S03](12_SIMULATOR_EVIDENCE_LEDGER.md#s03), [S25](12_SIMULATOR_EVIDENCE_LEDGER.md#s25)

**User signal.** A flyer asks about a large leaderboard gap; respondents suggest viewing/racing ghosts and disagree about aircraft choice versus racing line. This motivates interpretable comparison, without proving actual use or an unfair leaderboard. [U13](12_SIMULATOR_EVIDENCE_LEDGER.md#u13)

**OpenRC decision.** Center local racing on a known aircraft, course and rule identity; show validity, best compatible lap and complete-attempt outcome. Show the next gate and any bounded authoritative diagnostic for a non-counted crossing; if no reason is established, say no required crossing was registered. Start with the existing three-lap rules before adding formats or rankings. Track consistency and failures alongside a best lap, since a single successful attempt can hide poor repeatability.

**Verification.** Implement and pass the proposed RACE-01…15 cases to verify race authority; EXP-06/07 assess interpretation and practice benefit. Keep displayed times derived from accepted simulation events. Scope: M3, with richer feedback under P23.

### SIM-02 — Real event tracks and league rehearsal

**Documented example.** DRL and DCL advertise league-course practice. MultiGP's Global Qualifier publishes standardized track information. EreaDrone documents organized competition. [S09](12_SIMULATOR_EVIDENCE_LEDGER.md#s09), [S10](12_SIMULATOR_EVIDENCE_LEDGER.md#s10), [R04](12_SIMULATOR_EVIDENCE_LEDGER.md#r04), [S19](12_SIMULATOR_EVIDENCE_LEDGER.md#s19)

**User signal.** A micro racer values national-event track availability; a separate participant values editable maps. [U06](12_SIMULATOR_EVIDENCE_LEDGER.md#u06)

**OpenRC decision.** Support dimensioned course definitions, gate directions, obstacle solids, start position and rule provenance before creating an editor. Physical track rehearsal needs correct scale and collision clearance, not merely similar scenery. Do not brand the first three-lap rule set as an official format: the historical May 2025 FAI rules, for example, specify different start and crash behavior. [R03](12_SIMULATOR_EVIDENCE_LEDGER.md#r03)

**Verification.** Reproduce a permitted dimensioned layout numerically, qualify its supported gate geometry, and compare an accepted replay after serialization. EXP-08/P24 cover later authoring. M3 can use an original local course without an external event relationship.

### SIM-03 — Freestyle playground and flow

**Documented example.** Uncrashed emphasizes freestyle spaces; FPV LOGIC offers freestyle-oriented environments. [S04](12_SIMULATOR_EVIDENCE_LEDGER.md#s04), [S07](12_SIMULATOR_EVIDENCE_LEDGER.md#s07)

**User signal.** A selected discussion values flowing gaps and map variety, while also asking for stronger custom-course practice. It describes different needs rather than a universal preference for freestyle. [U05](12_SIMULATOR_EVIDENCE_LEDGER.md#u05)

**OpenRC decision.** The first qualified field should include recognizable landmarks, a clear pad, open recovery space and a small set of readable routes. Reuse permitted assets and qualify their scale/collision proxies. A compact coherent field can support turns, reversals and altitude control without a large-world pipeline. Keep access independent of medal progression and make restarting near the intended practice area understandable.

**Verification.** Ask pilots to find and repeat a route, identify where a contact occurred, and recover without hunting menus. Record collision disputes and frame pacing at 1080p. Implement the baseline field under P12/P13; elaborate abandoned-building interiors are later content.

### SIM-04 — Cinematic exploration and moving-subject chase

**Documented example.** TRYP describes exploration and wingsuit/motorcycle scenarios; Uncrashed describes moving-vehicle chase. [S05](12_SIMULATOR_EVIDENCE_LEDGER.md#s05), [S04](12_SIMULATOR_EVIDENCE_LEDGER.md#s04)

**User signal.** A flyer enjoyed TRYP on a borrowed gaming laptop but said their own PC was not capable of running it; another wanted more takeoff/landing practice. This is a hardware-specific account, not a controlled benchmark on the author's PC. [U07](12_SIMULATOR_EVIDENCE_LEDGER.md#u07)

**OpenRC decision.** Treat following a subject smoothly as a separate task from fastest-lap racing. A future scenario needs an identified moving target, repeatable path/time, visibility and useful framing feedback. The target's animation must not set the drone's motion. Keep subjects decorative unless collisions and scoring are explicitly admitted. Large maps add streaming and visibility work without proving a better controller or plant.

**Verification.** Re-run a target path and pilot tape with identical scenario events, compare framing error and continuity, and measure live performance separately from video export. Defer until the first local practice loop is stable; do not require a cinematic world for M2.

### SIM-05 — Indoor micro-drone specialization

**Documented example.** Liftoff: Micro Drones is a separate indoor product; Tiny Whoop GO offers micro-oriented progression and activities. [S13](12_SIMULATOR_EVIDENCE_LEDGER.md#s13), [S15](12_SIMULATOR_EVIDENCE_LEDGER.md#s15)

**User signal.** An August 2025 Air65/track comparison praises different simulators for throttle and handling while criticizing floor contact; it predates Micro Drones' June 2026 Physics 6.0 revision. A July 2026 discussion distinguishes exciting large spaces from the scale of actual rooms, without identifying exact installed builds. Other commenters disagree. [U03](12_SIMULATOR_EVIDENCE_LEDGER.md#u03), [U04](12_SIMULATOR_EVIDENCE_LEDGER.md#u04), [R07](12_SIMULATOR_EVIDENCE_LEDGER.md#r07)

**OpenRC decision.** Admit a micro as its own assembly, inertia/powertrain/prop/duct/contact configuration and validation envelope. A five-inch mesh scaled down or assigned a smaller mass does not establish micro behavior. Document room dimensions and obstacle clearances. Low-throttle control and light contact deserve dedicated measurements; a racing-quad crash policy may be unsuitable for repeated whoop floor brushes.

**Verification.** EXP-09 measures the chosen micro and room, with independent throttle/contact cases. Preserve the current one-build M2 scope. Add a micro only after its sources, laws and user goal justify a separate class.

### SIM-06 — Explicit assistance and staged control learning

**Documented example.** DCL distinguishes Arcade, GPS, Angle and Acro modes; Liftoff Micro documents an interactive tutorial. [S10](12_SIMULATOR_EVIDENCE_LEDGER.md#s10), [S14](12_SIMULATOR_EVIDENCE_LEDGER.md#s14)

**User signal.** One beginner found the combined assisted third-person to less-assisted FPV transition confusing. A separate thread contains opposing opinions about tutorial difficulty and pacing. This motivates testing several learning paths. [U14](12_SIMULATOR_EVIDENCE_LEDGER.md#u14), [U16](12_SIMULATOR_EVIDENCE_LEDGER.md#u16)

**OpenRC decision.** Keep Acro and the proposed bounded Angle mode explicit. Camera choice and flight assistance are independent concepts: switching to an FPV view does not imply changing the controller. Explain what the mode commands and which axes are stabilized. Do not add GPS/altitude assistance merely because another product labels it as a beginner mode; it needs sensors, controller state and distinct validation. Assisted and unassisted results need an explicit comparison policy.

**Verification.** EXP-05/UX-05 ask users to predict behavior and repeat a task across an intentional mode transition. Numerical mode/controller tests remain in 05 and SET-10/25. Keep a direct route to Acro practice.

### SIM-07 — Real-radio transfer and observable setup

**Documented example.** FPV.SkyDive supplies a calibration guide; Freerider Recharged describes radio/controller use and control-mode choices. [S28](12_SIMULATOR_EVIDENCE_LEDGER.md#s28), [S12](12_SIMULATOR_EVIDENCE_LEDGER.md#s12)

**User signal.** Reports describe missing AUX actions, half-range throttle and profile trouble after an update. They do not prove a common root cause, but show that apparently successful device connection can still leave flying unusable. [U09](12_SIMULATOR_EVIDENCE_LEDGER.md#u09), [U10](12_SIMULATOR_EVIDENCE_LEDGER.md#u10), [U11](12_SIMULATOR_EVIDENCE_LEDGER.md#u11), [U23](12_SIMULATOR_EVIDENCE_LEDGER.md#u23)

**OpenRC decision.** Display raw device input, mapped channel and effective curve separately. Save explicit per-device normalization and mappings; preserve versioned backups and diagnose migrations. Test supported combinations of OS, device mode and switch reporting. Distinguish device readiness from motor arming. Reuse 07/08's typed settings and pre-expo contracts rather than constructing a second configuration system.

**Verification.** EXP-01 and UX-01/02 exercise real device mapping, absent channels, reversal, reconnect and recovery. A known brand name or accepted joystick handle is insufficient support evidence. This is first-release work.

### SIM-08 — Short-session practice and dependable reset

**Documented example.** VelociDrone documents return-to-last-setup; EreaDrone's October 2026 update adds saved freestyle spawn selection. [S03](12_SIMULATOR_EVIDENCE_LEDGER.md#s03), [S30](12_SIMULATOR_EVIDENCE_LEDGER.md#s30)

**User signal.** A user requested a radio reset that a developer said already existed. The useful lesson is discoverability, not an assertion that the product lacked the feature. [U12](12_SIMULATOR_EVIDENCE_LEDGER.md#u12)

**OpenRC decision.** Reduce repeated selection/loading and expose reset clearly, while preserving all transaction guarantees. Last-used preferences lead to a fresh validated disarmed start, not restoration of an armed flight. A settings hold/cancel preserves accepted state; only an accepted explicit reset installs a new start and declared charge. Race reset terminates the old attempt and preserves its result before another countdown. Arbitrary freestyle spawn selection can follow qualified spawn validation later.

**Verification.** Execute EXP-02 to measure recovery components and the proposed TX/REPLAY/INPUT cases to verify correctness. Include camera interpolation history and controller integrals in reset evidence. A quick visual teleport with stale motor/controller state is not a successful restart.

### SIM-09 — Goal-oriented lessons and skill drills

**Documented example.** DRL advertises interactive lessons; Tiny Whoop GO combines flight school with progression and non-race objectives. [S09](12_SIMULATOR_EVIDENCE_LEDGER.md#s09), [S15](12_SIMULATOR_EVIDENCE_LEDGER.md#s15)

**User signal.** Selected pilots praise ordered skill learning, while others dislike repeated explanations and interruptions during flight. [U15](12_SIMULATOR_EVIDENCE_LEDGER.md#u15), [U17](12_SIMULATOR_EVIDENCE_LEDGER.md#u17)

**OpenRC decision.** Build short optional tasks on the working simulator: takeoff, controlled descent/landing, coordinated turn and directed-gate approach. Make explanation replayable and skippable; show objective and feedback without obscuring active flight. Define whether an instruction pauses the simulation before using a modal overlay. Lessons must observe accepted events and keep their progress state explicit. A medal should reward a declared skill, not a hidden assist.

**Verification.** EXP-05 tracks task completion and mode confusion; later retention is a separate measurement. Do not call a small usability study proof of real-world training transfer. Stage under P23 after M2 is usable, independent of career/unlock infrastructure.

### SIM-10 — Ghosts, splits and replay as coaching

**Documented example.** VelociDrone documents ghosts; EreaDrone's October release describes multi-view timeline replay and export. [S03](12_SIMULATOR_EVIDENCE_LEDGER.md#s03), [S29](12_SIMULATOR_EVIDENCE_LEDGER.md#s29)

**User signal.** Ghost discussion shows interest in understanding where time is lost, not just seeing a final number. [U13](12_SIMULATOR_EVIDENCE_LEDGER.md#u13)

**OpenRC decision.** The complete simulation recorder is an M1 foundation. Build a compatible personal ghost and read-only inspection on top after M3; keep pose playback, closed-loop re-simulation and video export distinct. Tie sector times to accepted gate events. Show aircraft/model/course identity and reject or label incompatible references. A ghost is observational and cannot collide with or push the current aircraft. Comparable nearby performance may be more useful for learning than an unexplained record time; that is a testable inference.

**Verification.** PRACTICE-01…03/EXP-07 test compatibility, side effects, interpretation and practice value. Preserve complete recording independently of visual stream decimation and include failed attempts in review history.

### SIM-11 — Shared flying and spectator learning

**Documented example.** Liftoff and Uncrashed advertise online flying; EreaDrone offers racing and spectating. [S01](12_SIMULATOR_EVIDENCE_LEDGER.md#s01), [S04](12_SIMULATOR_EVIDENCE_LEDGER.md#s04), [S19](12_SIMULATOR_EVIDENCE_LEDGER.md#s19)

**User signal.** A historical request values being able to fly with friends and see their maneuvers. It is not a claim that current Uncrashed lacks multiplayer. [U21](12_SIMULATOR_EVIDENCE_LEDGER.md#u21)

**OpenRC decision.** Separate social free flight, synchronized competition and spectator review. Each has different authority and latency requirements. Read-only replay sharing can test whether observation is valuable before building a live service. Later online racing must define event authority, permitted configuration, late packets, disconnects and result persistence; displaying remote poses is insufficient. Spectator controls should not change the pilot's simulation or camera policy.

**Verification.** First validate local replay/identity. A future network campaign needs deliberate jitter/drop/duplication cases and a rule for host or server failure. This is an optional later capability, not a local-racing dependency.

### SIM-12 — Creator tools and community course content

**Documented example.** Liftoff Micro documents track editing/sharing; AI Drone permits user content; Freerider includes procedural track generation. [S13](12_SIMULATOR_EVIDENCE_LEDGER.md#s13), [S08](12_SIMULATOR_EVIDENCE_LEDGER.md#s08), [S11](12_SIMULATOR_EVIDENCE_LEDGER.md#s11)

**User signal.** Editable maps and event tracks serve different participants in the same discussion. [U06](12_SIMULATOR_EVIDENCE_LEDGER.md#u06)

**OpenRC decision.** Make the course a strict versioned data object now. Later provide snapped transforms, dimensions, directed gates, start validation and local export; avoid making scene-node hierarchy the scoring contract. Reuse approved downloadable assets with provenance. Unknown fields, excessive object counts or unsupported gate types need a defined admission response. Procedural variation, if added, must store the seed and resulting admitted definition; it does not replace a hand-qualified reference course.

**Verification.** EXP-08/AUTHOR-01…03 include round-trip identity, geometry agreement and flown results. An editor that saves a plausible scene has not established reachability or race correctness. Keep online discovery/moderation separate from local authoring.

## 4. Simulation and controller cores

### SIM-13 — Component-based physical builds

**Documented example.** Liftoff describes battery/motor/propeller/frame/controller models and added motor-power constraints in Physics 6.0. These are developer descriptions, not a disclosed independent accuracy benchmark. [S24](12_SIMULATOR_EVIDENCE_LEDGER.md#s24), [S02](12_SIMULATOR_EVIDENCE_LEDGER.md#s02)

**Expected value — inference.** Pilots can understand why changing a component changes behavior, provided the modeled quantities and interactions are credible. A catalog resembling real hardware does not establish matching inertia, thrust or transients.

**OpenRC decision.** Start with one complete sourced build and the existing four-load/one-pack proposal. Keep each quantity's units, source and estimate status. Reject incompatible or undefined combinations; preserve the difference between nominal frame class and measured propeller geometry. Expose a stable preset before combinatorial building. Do not create arbitrary tuning gains from raw firmware PID integers.

**Verification.** P04/P08/P11 verify data, power balance and control on the admitted build; M4 measures the selected assembly. The first experimental release may use documented estimates and must say so. More parts do not automatically increase fidelity.

### SIM-14 — Identify a pilot's vehicle from flight data

**Documented example.** AI Drone advertises Blackbox import. NeuroBEM and ETH publish separate data/modeling research. Betaflight logging configuration controls what fields and sampling are available. [S08](12_SIMULATOR_EVIDENCE_LEDGER.md#s08), [A02](12_SIMULATOR_EVIDENCE_LEDGER.md#a02), [A03](12_SIMULATOR_EVIDENCE_LEDGER.md#a03), [A04](12_SIMULATOR_EVIDENCE_LEDGER.md#a04), [A06](12_SIMULATOR_EVIDENCE_LEDGER.md#a06)

**Expected value — inference.** Personalization is attractive when it reduces the gap between a known physical aircraft and its virtual model. A log alone may not identify coupled thrust, drag, mass, motor and timing parameters uniquely.

**OpenRC decision.** Design an offline research path that audits fields, timestamps, units, frames, filtering, motor mapping and independent measurements before fitting. Treat commanded motor output as a command, not RPM or force. Split whole flights/maneuver families before fitting; retain uncertainty and extrapolation limits. Use the frame-conversion contract in 03, not an assumed world heading.

**Verification.** EXP-10 requires held-out residuals and an insufficient-evidence outcome for missing data. This strengthens P16's validation planning but does not create an M2 importer requirement or justify a “digital twin” label.

### SIM-15 — Actual firmware in the simulation loop

**Documented example.** KwadSim and Betaloop use Betaflight processes; Betaflight documents SITL interfaces. INAV has its own SITL/HITL paths. SimITL/pr0p also include a separate dynamics path. [A07](12_SIMULATOR_EVIDENCE_LEDGER.md#a07), [A08](12_SIMULATOR_EVIDENCE_LEDGER.md#a08), [A09](12_SIMULATOR_EVIDENCE_LEDGER.md#a09), [A11](12_SIMULATOR_EVIDENCE_LEDGER.md#a11), [A12](12_SIMULATOR_EVIDENCE_LEDGER.md#a12), [A14](12_SIMULATOR_EVIDENCE_LEDGER.md#a14), [A15](12_SIMULATOR_EVIDENCE_LEDGER.md#a15)

**Expected value — inference.** Executing real controller logic can support firmware experiments. It does not make synthetic sensors, estimated motors or the aircraft plant physically correct.

**OpenRC decision.** Keep firmware comparison outside the first release. Define one plant authority: accepted OpenRC state → timestamped simulated sensors → pinned firmware → timestamped motor commands → OpenRC plant. A pose-returning library with its own dynamics is an alternative simulator, not a transparent controller attachment. Account for exact sample clocks, sensor specific force, motor ordering and external-process state.

**Verification.** Execute EXP-11 to test signs, timing, reset/failure and the supported state-restoration boundary; report any restoration/rollback limitations. Motor-command replay tests the plant under those commands; it cannot demonstrate a changed controller's closed-loop replay. Full checkpoint/rollback is a major unresolved boundary for an external process.

### SIM-16 — A simulator-owned controller designed for the host

**Documented example.** Liftoff's 2021 controller redesign explicitly targeted performance/stability and reduced dependence on high-frequency engine physics. It is historical architectural evidence, not a current performance comparison. [R02](12_SIMULATOR_EVIDENCE_LEDGER.md#r02)

**Expected value — inference.** A bounded, inspectable controller can provide consistent Acro behavior and better failure diagnosis without carrying every embedded peripheral or real-time transport requirement.

**OpenRC decision.** Preserve the proposed simulator-owned rate loop and separately verified Angle outer loop. Keep integrals, filters, sample times and held commands in explicit accepted/candidate state. Treat 240 Hz as the existing qualification hypothesis; if NUM-02 fails, use P19a's generic faster-sampling branch rather than extra hidden updates inside RK4 derivatives. Familiar rates and UI names do not imply complete Betaflight/INAV equivalence.

**Verification.** DR-16a/TX, CTRL and NUM gates verify transaction, response and sample sensitivity. SET-05…17 govern gain/filter semantics. Publish the effective controller identity and supported settings rather than adopting a firmware version badge as a fidelity claim.

### SIM-17 — Selectable disturbances and degradation

**Documented example.** Liftoff's 2026 release adds configurable wind limited there to single-player free flight. Its technical overview discusses signal effects; VelociDrone describes battery/damage options. [S02](12_SIMULATOR_EVIDENCE_LEDGER.md#s02), [S24](12_SIMULATOR_EVIDENCE_LEDGER.md#s24), [S03](12_SIMULATOR_EVIDENCE_LEDGER.md#s03)

**User signal.** A historical request asks for simulated delay to resemble outdoor experience; it does not measure actual simulator or RF/video delay. [U20](12_SIMULATOR_EVIDENCE_LEDGER.md#u20)

**OpenRC decision.** Separate physical wind/pack/actuator effects, simulated sensor/radio degradation, and cosmetic video artifacts. Each must have explicit state, time base, parameters and comparison policy. Implement the proposed basic energy law subject to M2 qualification; defer prop damage, rich wind, RF loss and analog artifacts until independently useful and qualified. Do not conceal poor input/frame pacing behind a “realistic latency” effect. Seeded effects must preserve random-stream state through hold/rollback/replay.

**Verification.** Compare an identical accepted tape with each optional presentation effect; physics must be unchanged. Physical disturbances need explicit scenario identity and measured/model validation. SET-26/27/29/31 and 04's latency rules retain ownership.

### SIM-18 — Versioned competition and comparable results

**Documented example.** Liftoff separated legacy leaderboard times after Physics 6.0. EreaDrone's October notes retain V2 by default while offering V3 beta per drone. Historical FAI rules constrain the aircraft used for an event. [S02](12_SIMULATOR_EVIDENCE_LEDGER.md#s02), [S29](12_SIMULATOR_EVIDENCE_LEDGER.md#s29), [R03](12_SIMULATOR_EVIDENCE_LEDGER.md#r03)

**User signal.** Pilots ask whether aircraft choice explains a gap to others' times. [U13](12_SIMULATOR_EVIDENCE_LEDGER.md#u13)

**OpenRC decision.** Store full run identity separately from a rules-defined competition class. Rates and camera preferences may be permitted within a class; changed thrust, assists, controller implementation or course rules may not be. Preserve all values for audit even when comparison ignores permitted differences. Version physical models and retain earlier results as their own historical class; never silently reinterpret them.

**Verification.** 11 defines the identities and PRACTICE cases. Test model/rule changes, incomplete recordings, paused practice and rejected attempts. Hash equality helps detect identity mismatch; it does not prove authenticity or serve as online anti-cheat.

## 5. Presentation, access and deployment

### SIM-19 — Frame pacing and scalable graphics as core design

**Documented example.** FlowState's source describes low-latency/laptop goals. VelociDrone Mobile uses stylized environments as part of its performance approach. These are goals/descriptions, not our benchmarks. [A26](12_SIMULATOR_EVIDENCE_LEDGER.md#a26), [R05](12_SIMULATOR_EVIDENCE_LEDGER.md#r05)

**User signal.** Low-end-PC reports differ by machine, while another thread links difficult flight to possible performance trouble without establishing the original cause. [U08](12_SIMULATOR_EVIDENCE_LEDGER.md#u08), [U22](12_SIMULATOR_EVIDENCE_LEDGER.md#u22)

**OpenRC decision.** Qualify native 1080p first with named hardware, stable input and scalable render settings. Reduce visual cost without changing physical sample rate, accepted state or collision/scoring geometry. Keep simulation/wall-time ratio visible in performance evidence: fixed-step math can remain correct while real-time pacing degrades. Average FPS is insufficient; inspect tails and actual response. Avoid hidden automatic quality changes during a benchmark.

**Verification.** EXP-03 reuses PERF-01…03, including real input-to-display measurements. Higher resolution follows 1080p; 720p is the fallback priority. No competitor's minimum specifications qualify OpenRC hardware.

### SIM-20 — Match the FPV sensory interface

**Documented example.** Freerider provides camera adjustment, EreaDrone documents lens options, and FlightGoggles treats synthetic camera rendering separately from motion. [S12](12_SIMULATOR_EVIDENCE_LEDGER.md#s12), [S29](12_SIMULATOR_EVIDENCE_LEDGER.md#s29), [A17](12_SIMULATOR_EVIDENCE_LEDGER.md#a17)

**User signal.** One participant reports different FOV/aspect preferences across Liftoff and DRL; another later wants more visibility in Uncrashed. Their settings are individual preferences, not universal calibration values. [U18](12_SIMULATOR_EVIDENCE_LEDGER.md#u18)

**OpenRC decision.** Keep one body-fixed onboard camera with explicit mount offset, tilt, horizontal FOV and content aspect. Full roll, near clipping and one interpolation owner matter before lens distortion. Distinguish physical camera/display matching from subjective “speed feel.” Audio/OSD may help interpretation only when they report quantities the admitted model actually supplies. A headset's look direction must not silently stabilize or steer the drone camera.

**Verification.** VIS-01…08 and EXP-04 isolate projection/latency changes from physical changes. Optional lens/static/video delay should be tested individually and labeled. Rendering a smooth replay is not evidence of live controller responsiveness.

### SIM-21 — Lower the access barrier: free base, demo or browser

**Documented example.** Orqa offers a free base with optional modules; Freerider provides a limited demo; WebFPVSimulator describes a WebAssembly firmware/plant experiment. These are different distribution approaches. [S16](12_SIMULATOR_EVIDENCE_LEDGER.md#s16), [S11](12_SIMULATOR_EVIDENCE_LEDGER.md#s11), [A28](12_SIMULATOR_EVIDENCE_LEDGER.md#a28)

**User signal.** A prospective pilot seeks practice before buying an aircraft, while recommendations vary with indoor versus larger-drone goals. [U19](12_SIMULATOR_EVIDENCE_LEDGER.md#u19)

**OpenRC decision.** Make the local first-flight path understandable and avoid unnecessary services for solo practice. A future browser trial needs an explicit Godot export spike, measured input support and background/focus behavior. Gamepad-exposed radio support, WebHID access and touchscreen control are separate capabilities. A browser deliverable is not established by a successful native build. The referenced Godot 4.5 documentation cannot qualify the pinned 4.8 beta project automatically. [A29](12_SIMULATOR_EVIDENCE_LEDGER.md#a29), [A31](12_SIMULATOR_EVIDENCE_LEDGER.md#a31)

**Verification.** EXP-12 qualifies continuity; later actual-browser tests qualify export, inputs, frame pacing and reference parity. A free trial is not necessarily a permanently free complete product.

### SIM-22 — Portable mobile practice

**Documented example.** VelociDrone Mobile documents Android/iOS versions, downloaded tracks and custom radio connectivity. Its iOS connection requirements are product-specific. [R05](12_SIMULATOR_EVIDENCE_LEDGER.md#r05)

**Expected value — inference.** Portable practice may make short sessions easier, but convenience is not evidence that touch controls transfer the same motor skills as a physical radio.

**OpenRC decision.** Treat mobile as a separate supported platform with a defined device/input matrix. Decide whether the goal is radio practice, touch familiarization or race review. Test app focus, suspend/resume, input reconnection, thermal throttling and actual display timing. Preserve complete session state or terminate cleanly; the OS lifecycle cannot silently skip simulation time. Shared profiles need explicit per-platform input normalization, not assumed identical raw axes.

**Verification.** Reuse UX-01…04/07 and PERF measurements on actual target devices. Qualify wireless transport separately from USB. Do not infer compatibility from another product's radio path. Native desktop 1080p remains first priority.

### SIM-23 — XR and hardware-ecosystem experiences

**Documented example.** Liftoff XR describes a Meta Quest/VR-controller experience. DJI stopped maintaining Virtual Flight in March 2024 and documents exact device limitations. [R06](12_SIMULATOR_EVIDENCE_LEDGER.md#r06), [A32](12_SIMULATOR_EVIDENCE_LEDGER.md#a32), [A33](12_SIMULATOR_EVIDENCE_LEDGER.md#a33)

**Expected value — inference.** Room-relative virtual flight, a headset showing an FPV screen, and dedicated video goggles can offer immersion, but they are different products with different input and comfort requirements.

**OpenRC decision.** Keep separate claims for a USB radio, a PC-video display path and an OpenXR headset. Record exact hardware, runtime, cable/receiver, OS and test result. Do not infer support for newer hardware from a familiar vendor name. The rigid FPV baseline should remain stable; any independent head-tracked spectator view is a separate camera mode. Godot API availability is only an implementation starting point. [A34](12_SIMULATOR_EVIDENCE_LEDGER.md#a34)

**Verification.** Test the complete physical input/display chain, recentering, pause, device loss and sustained performance. Treat historical ecosystem shutdown as a continuity lesson, not a claim that all third-party DJI controller use is unsupported.

## 6. Openness, research and platform fit

### SIM-24 — Open development and modifiable simulation

**Documented example.** FlowState's listing/source present an open project; KwadSim exposes code. CurryKitten's GitHub README explicitly says its simulator is not open source. A public repository is not sufficient evidence of reusable simulator code. [A25](12_SIMULATOR_EVIDENCE_LEDGER.md#a25), [A26](12_SIMULATOR_EVIDENCE_LEDGER.md#a26), [A07](12_SIMULATOR_EVIDENCE_LEDGER.md#a07), [A27](12_SIMULATOR_EVIDENCE_LEDGER.md#a27)

**Expected value — inference.** Inspectable algorithms, data and reproductions can make tuning discussions more useful and support long-term maintenance. Openness alone does not establish correctness or an active maintainer.

**OpenRC decision.** Publish admitted data schema, sources, reference tapes and evidence boundaries through the existing research/documentation workflow. Prefer reusable permitted assets and inspect each dependency's actual code/asset license before integrating it. Keep model changes reviewable and versioned. Do not equate free binaries, shared presets and source access; preserve those distinctions in contributor instructions.

**Verification.** Rebuild an admitted package from identified sources, replay its reference and validate schema migration. Pin external commits before experiments. No external code or assets were integrated during this study.

### SIM-25 — Decoupled headless dynamics and rendering

**Documented example.** Flightmare separates dynamics and rendering. RotorS and PX4 provide different robotics simulation/control examples; PX4 documents lockstep for supported configurations. [A16](12_SIMULATOR_EVIDENCE_LEDGER.md#a16), [A19](12_SIMULATOR_EVIDENCE_LEDGER.md#a19), [A20](12_SIMULATOR_EVIDENCE_LEDGER.md#a20)

**Expected value — inference.** Deterministic commands and inspectable state can be evaluated without a GPU, while graphics can improve independently. A robotics throughput claim is not a measurement of human input latency.

**OpenRC decision.** Preserve the custom float64 `VehicleModel` boundary and use Godot for detached presentation. Drive control from declared simulation time; do not allow render frames to create physics samples. A lockstep external process can help an offline experiment but needs explicit timeout, sequence, hold and restore behavior. Integer/rational clock relationships must be designed if a controller rate differs from the base integration step.

**Verification.** Compare accepted state/events for the same tick/input tape with rendering absent and under different display cadences. Qualify real-time pacing separately. Existing DR-16a/17 and NUM gates own this work; adopting Flightmare or Gazebo is not required.

### SIM-26 — Synthetic sensors and autonomy research

**Documented example.** FlightGoggles supports synthetic visual sensing, including a research vehicle-in-the-loop configuration. Original Microsoft AirSim is archived; Project AirSim has a distinct continuation/maintenance path. [A17](12_SIMULATOR_EVIDENCE_LEDGER.md#a17), [A18](12_SIMULATOR_EVIDENCE_LEDGER.md#a18), [A21](12_SIMULATOR_EVIDENCE_LEDGER.md#a21), [A22](12_SIMULATOR_EVIDENCE_LEDGER.md#a22), [A23](12_SIMULATOR_EVIDENCE_LEDGER.md#a23), [A24](12_SIMULATOR_EVIDENCE_LEDGER.md#a24)

**Expected value — inference.** These approaches are useful for sensor/perception experiments and automated agents. They are not evidence of a complete consumer FPV setup/training/racing product.

**OpenRC decision.** Borrow the separation of motion, sensors and rendering as an architectural lesson. A future sensor stream needs timestamp, pose, intrinsics, exposure/latency policy and uncertainty. Keep it outside M2/M3 unless a concrete user goal requires it. Rendering real captured motion can test visual alignment without validating the simulator's force model. Photoreal assets still need scale and collision qualification for a human racer.

**Verification.** Compare known pose/time to rendered sensor observations, then test physical response independently. Pin the exact research project/version; “AirSim support” is too ambiguous for implementation planning.

### SIM-27 — FPV inside a wider RC simulator

**Documented example.** neXt combines helicopters, fixed-wing and multicopters with FPV racing features. Its product page demonstrates the product category, not OpenRC's internal architecture. [R01](12_SIMULATOR_EVIDENCE_LEDGER.md#r01)

**Expected value — inference.** An existing RC user can reuse controller setup, fields, cameras, recording tools and familiar navigation while changing vehicle class.

**OpenRC decision.** This is the best fit for the current repository. Keep one session-installed `VehicleModel`; extend generic transactions only where required and put quad laws/controller/racing composition in their proper owners. Preserve fixed-wing and other vehicle contracts. Share device calibration but separate motor arming and flight-mode semantics. Route Home/CLI/capabilities explicitly so an unsupported combination never appears flyable.

**Verification.** Use focused affected-session/fleet checks plus required CI at the implementation boundary. Qualify each vehicle class separately; a working aircraft golden does not validate a racer. The source audit and P02/P03/P10/P13 already define the relevant seams.

### SIM-28 — Offline controller-driven AI racing

**Documented example.** FPV LOGIC advertises races against AI drones. This is distinct from replaying another pilot's trajectory. [S07](12_SIMULATOR_EVIDENCE_LEDGER.md#s07)

**Expected value — inference.** Opponents can supply immediate competition without concurrent online players. No preference prevalence or training benefit was measured in this research.

**OpenRC decision.** Start with a personal ghost because it reuses a complete known run and has no control/collision authority. Interactive AI aircraft require additional controllers and vehicle states, an explicit collision policy, race coordination and CPU budgets. Choose whether they obey the same physical limits and rules before claiming comparable races. A visually animated opponent that ignores physics is a different labeled training/gameplay mode.

**Verification.** Measure each additional actor's cost, keep random seeds/state explicit and test that enabling optional opponents cannot silently change human simulation timing or the rules. Validate failure/disconnect equivalents for AI control and replay. Defer until local racing/ghosts demonstrate sufficient practice value.

## 7. What the user evidence supports

The sample supports investigating six recurring concerns: understandable controls, setup/recovery, useful spaces, readable progress, responsive presentation, and configuration-specific feel. It does **not** establish their prevalence in the whole market or a rank order between simulators. The exact reports and opposing views are retained in 12.

| Theme | Positive value seen or requested | Friction or disagreement | OpenRC consequence |
| --- | --- | --- | --- |
| Control confidence | A setup resembling the pilot's intended aircraft/radio | Opposite “floaty” judgments and unreported configurations | Diagnose by maneuver and effective settings; preserve a known default |
| Time spent practicing | Discoverable reset, saved setup, accessible sandbox | Hard-to-find bindings and broken profile recovery | P22 journey/recovery qualification |
| Appropriate space | Flowing freestyle gaps, event tracks, recognizable indoor scale | Large maps can be engaging yet inappropriate for room practice | One purposeful field now; separate class/content validation later |
| Learning and progress | Ordered lessons, ghosts and replay | Repeated explanation, abrupt assistance changes, opaque fast times | Short optional drills and transparent compatible results |
| Responsiveness | A flyable experience on the user's own computer | Strongly conflicting hardware anecdotes | Native 1080p frame/latency evidence, scalable visuals, no guessed rankings |
| Social/creative continuity | Shared flying and editable content | Requests can predate features; update histories change availability | Source-dated research, local import/replay before services |

## 8. Implications for the plan

Adopt the [decisions and experiments in 11](11_FPV_PRODUCT_DECISIONS_AND_EXPERIMENTS.md), preserving the earlier critical path: **transaction → headless control/replay → experimental free flight → local racing → separately measured physical fidelity**. The research adds P22 for first-flight usability qualification and P23/P24 for later local feedback/authoring. It does not move physical measurement, firmware integration or online services into the first-release gate.

The next useful evidence is a working, observable, repeatable OpenRC flight activity on named hardware. A feature checklist and a popular simulator's reputation cannot replace that evidence.
