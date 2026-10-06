# 01 — Damage models in simulators and games

**Status:** research, 2026-10-06. **Serves:** CRASH-DAMAGE-PLAN (CR- steps).

How RC simulators, flight simulators and part-based games decide that something broke, what breaks, how it feeds back into flight, and what the pilot sees next. Builds on [04 §6](../roadmap-investigations/04-ground-handling-collisions.md) (per-point crash thresholds, CRRCSim `max_force`, PicaSim Δv/Δω), which is not repeated here.

**Method:** web search, official manuals (PDF text extracted with `pdftotext`), and source code read in shallow clones (PicaSim, CRRCSim, FlightGear YASim, FlightGear `crash-and-stress.nas`, the community A-4E DCS flight model). Licences are noted per source; the PolyForm-Noncommercial and All-Rights-Reserved sources are used for ideas and numbers only.

## Summary

1. **RC simulators mostly use a crash → reset loop.** Partial damage you can keep flying with is rare. RealFlight is the exception: "contact can result in damage ranging from minor handling problems to spectacular crashes" (Help Guide 2024). Its parts come off along a parent–child hierarchy, so a wing takes its gear with it.
2. **Reset delay is a user setting everywhere:** Phoenix offers immediately / 1 / **3 s (default)** / 10 s / never / "at idle throttle". RealFlight game modes offer none / ≈1 / ≈3 / ≈6 s. PicaSim relaunches after **3 s** on the ground. aerofly RC 10 has "Time for restart after a crash". Our fixed 1.5 s hold is within that range but not configurable.
3. **Categorical crash flags are cheap and readable.** PicaSim sets AIRFRAME (the control surfaces stop responding), PROPELLER (the prop stops at ω = 0, slipstream off) and UNDERCARRIAGE (wheels lose steering, brake 5) independently. The body keeps tumbling under physics until the relaunch.
4. **Thresholds scale with model size.** PicaSim scales its Δv limits by √(size) and its Δω limits by 1/√(size) (Froude scaling, source code). This is directly useful across our 2.9 kg to 21.5 kg fleet.
5. **Force thresholds per contact point are the norm in RC sims.** Examples: CRRCSim `max_force` (Allegro glider 5 lbf = 22 N per wing hardpoint, ≈ 2.4–3.4 × weight), Heli-X `MaximalContactVelocity` (default **5 m/s**), and the FS/MSFS per-contact "impact damage threshold" (commonly 1574.8 ft/min = **8.0 m/s**, search result only).
6. **Damage feeds into flight through per-surface aerodynamics.** In DCS, wing skin damage reduces lift and spar damage lowers the breaking load. The A-4E community flight model scales each wing strip's lift by an integrity factor (0–1) and its drag by **0.7 × integrity**. We already have wing strips (D9b), so this maps directly.
7. **In-flight overstress needs persistence and warning cues.** The A-4E breaks a wing only after the load has stayed above the limit for **0.2 s**. FlightGear's `crash-and-stress.nas` plays creak and crack cues from **50 / 75 / 90 %** of the wing-load limit and breaks at **100 %**. Its negative limit defaults to **−0.4 ×** the positive one.
8. **Debris is visual only and pre-split.** War Thunder authors 3 breakable wing sections per side plus break emitters, RealFlight uses `~CS_` named detachable components, and Phoenix has a "Crash Debris" on/off switch. Runtime mesh fracture is avoided even by its own Godot author ("pre-computed destruction … **far** more efficient").
9. **Soft-body damage is out of budget.** BeamNG runs node-beam physics at **2000 Hz** (0.5 ms). Its "deterministic mode" only fixes the step rate and "does not (yet) lead to deterministic simulation for every scenario". Our whole budget (~500 µs/tick at 240 Hz) is already spent.
10. **Durability is a single multiplier or a mode.** Examples: RealFlight physics levels ("crashes are more forgiving" on Beginner) plus per-component strength % (default 110 per forum, unverified), Liftoff "God mode", Phoenix's unbreakable torque trainer, and Kerbal Krash System's scale factor on crash tolerance.
11. **Randomness is common in damage outcomes and must be avoided here.** FlightGear's crash-and-stress fails each failure mode with probability v_kt²/40000 using `rand()`, and IL-2 hit outcomes are probabilistic. Our golden replays need damage to be a deterministic function of state.
12. **Pilots ask for weaker, not stronger, airframes.** On the RealFlight forum: "the sim planes are too strong … If I can get away with it in the sim, I will likely try high-G moves at the field". Users lowered wing strength from 110 to 50–60 % and gear to ≤ 22 % (forum, unverified). MSFS users complain about the opposite failure: low-speed touches that end in a black screen, and tree hits that register only on the centreline.

## RC simulators

| Sim | What is modelled | Thresholds / numbers | After a crash; feedback into flight | Licence | Source |
| --- | --- | --- | --- | --- | --- |
| RealFlight (7.5 → Evolution) | "Full Coverage" collision points over the whole airframe; detachable components (`~CS_` names, parent–child hierarchy); "Structural Integrity" failure (parts break off in flight); flight recorder (AFR); Instant Rewind | Per-component strength %, default 110 (forum, unverified); collision mesh < 1500 polygons (third-party guide) | Partial damage is flyable ("minor handling problems"); "Automatic Reset Delay (sec)" applies "after a crash during which a piece of the aircraft has broken off"; game modes: None / Short ≈ 1 s / Medium ≈ 3 s / Long ≈ 6 s; physics levels Beginner ("crashes are more forgiving") / Intermediate / Realistic | Proprietary | RF 7.5 manual, RF Help Guide 2024, ArduPilot blog, RF forum |
| Phoenix R/C 3–5 | Crash or "damage" events; visual crash debris (toggle); failures menu | Reset: immediately / 1 s / 3 s (default) / 10 s / no auto-restart / at idle throttle | Notification bar ("crashed model", click to reset); logbook counts crashes per model; torque trainer "will not break on impact" | Proprietary | Phoenix 3.0 manual |
| aerofly RC 10 | Crash detection (details not documented) | "Time for restart after a crash" | Reset to the saved start position; damage not documented | Proprietary | RC10 manual |
| Heli-X 10 | Contact-velocity crash; crash objects in photo scenes; rotor crash discs | `MaximalContactVelocity` default 5 m/s; `CrashSensitivityFactor` per object, default 1; rotor `CrashSizePercentage` 0–100 | A broken tail rotor stays flyable (`MultiplicatorAirResistanceTailRotorBroken`); "Crash and Retry" puts the heli back "some seconds before the crash"; replay on crash; crash simulation can be disabled | Proprietary | Heli-X 10.1 guide |
| PicaSim | Flags AIRFRAME / PROPELLER / UNDERCARRIAGE (detail in 04) | Default Δv (5, 5, 10) m/s per update, Δω 500 °/s, scaled √size and 1/√size; `mRelaunchTime` 3 s | AIRFRAME: wings stop reading the controller, jet throttle 0; PROPELLER: ω = 0, wash 0, sound fades; UNDERCARRIAGE: wheels uncontrolled, brake 5; HUD lists the flags; relaunch when on the ground > 3 s | PolyForm NC: ideas only | Source, fetched |
| CRRCSim | Crash = any hardpoint normal force > `max_force` | Default 9999 lbf (off); Allegro wing hardpoints 5 lbf | `STATE_CRASHED` stops the simulation and the sound; key `r` restarts; no damage | GPL-2.0 | Source, fetched |
| VelociDrone | Prop damage (race mode) | 25 % steps, more than 25 % per crash if severe | Slower quad; vibration at 100 %; recharge gate repairs; reset to the last gate | Proprietary | Desktop manual |
| Liftoff | Prop damage in collisions | — | "God mode" disables it; R reset, T rewind | Proprietary | Support page |
| neXt, ClearView | Not found | — | — | Proprietary | Search only |

## Flight simulators

| Sim | What is modelled | Thresholds / numbers | Feedback into flight | Licence | Source |
| --- | --- | --- | --- | --- | --- |
| FlightGear YASim | Crash if the lowest gear contact is > 1 m below ground ("integration slop") | 1 m | Sets `/sim/crashed`, then the FDM stops updating | GPL-2.0 | `Model.cpp`, `YASim.cxx` |
| FlightGear JSBSim | `FGLGear` crash check after 2 consecutive weight-on-wheels steps | Compression > 500 ft, force > 1e8, moment > 5e9, sink > 44 ft/s (13.4 m/s) | Logs only; the freeze is commented out | LGPL-2.1 | JSBSim discussion #819 |
| FlightGear `crash-and-stress.nas` | Impact failures; wing-load overstress; repair | Per failure mode p = v_kt²/40000 (`rand()`); explode if p > 0.766 (≈ 175 kt) and fuel > 2500 lb; cues at 50/75/90 %, break at 100 % of maxG × weight; lower limit −0.4 × upper; repair takes 10 s | Failures through FailureMgr; wings detach | GPL-2.0+ | Source (OpRedFlag copy) |
| MSFS (FSX lineage) | Per contact point "impact damage threshold"; scrape-point class 2; propeller class 17; gear airspeed damage | Threshold in ft/min, common value 1574.8 (= 8.0 m/s, search result only) | Options: Crash Damage, Aircraft Stress Damage, Engine Stress Damage (secondary source); crash ends the flight | Proprietary | MSFS SDK docs |
| DCS (WWII DM, G.91R) | Spars, longerons, stringers, skin, systems | None published | Skin damage reduces lift; spar damage lowers strength and the wing snaps under load; G.91R: per-surface forces so "local damage" changes handling; progressive structural integrity | Proprietary | ED reports 2020-11-06, 2026-09-04 |
| DCS A-4E community flight model | `ed_fm_on_damage(element, integrity 0..1)` | Lift factor = integrity, drag factor 0.7 × integrity per wing element; overstress after 0.2 s above the limit | Asymmetric lift and drag from strip damage | All Rights Reserved: ideas only | Source, fetched |
| IL-2 Great Battles | Structure from blueprints; hit probability depends on angle | None | Damaged wing loses lift; broken spar breaks at lower G | Proprietary | Search results, dev blog |
| War Thunder | Low-poly damage-model mesh; `wing_l_dm`, `wing1_l_dm`, `wing2_l_dm` (+ right, `tail_dm`, `spar*_dm`); `emtr_break_wing_*` emitters | Damage-model mesh 3–5 k triangles (fighters) | Parts that detach: wings, tail, gear, flaps, control surfaces (forum) | Proprietary | CDK wiki |

## Part-based and soft-body games

| Game | Model | Numbers | Cost / determinism | Source |
| --- | --- | --- | --- | --- |
| Kerbal Space Program | `crashTolerance` (m/s impact speed per part); `breakingForce`/`breakingTorque` on the joint to the parent (Unity `Joint.breakForce` semantics) | Wing Connector A 15 m/s; Poodle engine 7 m/s; example cfg 6 / 50 / 50 | Rigid parts joined by joints; parts explode | Wiki and forum (search results only) |
| Kerbal Krash System (KSP mod) | A band below the scaled tolerance deforms parts instead of exploding them; damaged parts lose efficiency; repair | Scale factors configurable (values not found) | — | Forum (search only) |
| BeamNG.drive | Node-beam soft body; beam deforms above `beamDeform` and breaks above `beamStrength` (N); `breakGroup` breaks a set together; `deformGroup` triggers visuals | Defaults: spring 4.3e6 N/m, damp 580 N·s/m, deform 2.2e5 N, strength FLT_MAX; 2000 Hz | Deterministic mode fixes the step only | Official docs, fetched |
| Rigs of Rods | Same node-beam family | `set_beam_defaults` 9e6, 12000, 4e5, 1e6 N (break) | Open source (GPL; version not checked) | Docs, fetched |
| Teardown | Every voxel simulated; structural integrity solver | — | Custom engine, multithreaded | Search only |
| Besiege, Stormworks, Juno | Not found in primary sources | — | — | — |
| Burnout 3 | "Impact Time" slow-motion crash camera with "aftertouch" steering of the wreck | — | UX reference only | Search only |

## Open-source Godot examples

| Repo | What | Licence | Use for us |
| --- | --- | --- | --- |
| [Jummit/godot-destruction-plugin](https://github.com/Jummit/godot-destruction-plugin) | Swaps an intact mesh for a pre-fractured scene (Blender Cell Fracture, "~5–20" rigid bodies) on `destroy()` | MIT code, CC0 assets | Pattern for visual debris |
| [the-dunk/Godot-Destruction](https://github.com/the-dunk/Godot-Destruction) | Runtime plane slicing of convex meshes; Voronoi in progress | MIT | Avoid (convex only; author recommends pre-computed) |
| [Terabase-Studios/Godot-Voxel-Destruction](https://github.com/Terabase-Studios/Godot-Voxel-Destruction) | Voxel destruction with debris | MIT | Not relevant to airframes |

GitHub searches for Godot vehicle or aircraft damage that feeds back into physics found nothing (2026-10-06).

## What makes crash outcomes differ

| Input | Who uses it | Our mapping |
| --- | --- | --- |
| Normal impact speed at the touching point | Heli-X, MSFS, KSP, doc 04 | `v_n` per hull point, per component threshold |
| Contact force | CRRCSim, PicaSim gear, BeamNG beams | Gear legs (E1 travel/force); not for rigid hull points (force depends on contact stiffness) |
| Body Δv / Δω per tick | PicaSim | Backstop only: tick-rate dependent (PicaSim's per-update limits change with dt) |
| Which part touches | All part-based models | Component id on every hull point |
| Sustained load | A-4E (0.2 s), FlightGear wing load | In-flight overstress: strip root bending or n·W against the limit |
| Energy | JSBSim proposal (cap stored energy ≤ KE) | Severity grading: ½ m v_n² against a per-part absorbable energy (estimated) |
| Hierarchy / cascade | RealFlight, War Thunder, BeamNG `breakGroup` | Parent–child table: wing → its gear and aileron; fuselage → all |
| Prop rpm at contact | PicaSim, MSFS propeller contact class | Prop strike stops the engine, not a crash |

## UX patterns and pilot reactions

- **Reset flow:** an auto-reset delay is universal (summary 2). Phoenix's "at idle throttle" reset suits a radio-first app: the pilot lowers the stick, and the airplane resets.
- **Crash report:** PicaSim lists the crash flags, Phoenix shows a notification plus a logbook count, and CRRCSim prints the hardpoint and force. We already print speed and sink, and doc 04 proposes naming the component as well.
- **Rewind and replay:** RealFlight Instant Rewind ("hold the Reset button … let go … to re-start"), Liftoff rewind (T), and Heli-X Crash-and-Retry and replay-on-crash. A deterministic simulation makes rewind a state snapshot plus a re-run.
- **Flying on with damage:** RealFlight, Heli-X (broken tail rotor), VelociDrone (damaged props: slower, vibration) and DCS all allow it. Phoenix, aerofly, CRRCSim and PicaSim reset instead.
- **Pilot reactions:** RC pilots want realistic fragility because the sim trains habits ("sim planes are too strong", RealFlight forum). Flight-sim users dislike all-or-nothing crashes on minor contact (MSFS forum). Both argue for graded outcomes with a durability setting that defaults to realistic.

## Patterns we should adopt / avoid for this repo

**Adopt**

1. **Damage is simulation state, not presentation.** Use a small float64 array (one integrity value per component, 0–1) plus a "detached" bitmask, held in the simulation state or aux. Change it only at tick boundaries, with the same event detection as today's crash (first penetration between `sim.previous` and `sim.state`). Record changes as trace event rows. Golden flights then stay bit-exact, and a flight without damage events is unchanged.
2. **Aero feedback through the existing wing strips (D9b):** multiply each strip's lift by its integrity. For drag, use the A-4E split (0.7 × integrity, ideas only) or keep the full drag until the strip detaches. When a part detaches, remove its strips, its mass and inertia, and update the CG. This is a one-off mass-properties update at the event, not a per-tick cost.
3. **Categorical outcomes first (PicaSim):** prop strike (engine off), gear collapse (that leg's contact becomes a hull point), control loss (a surface stuck at its last deflection), airframe (end of flight). Each one is cheap and changes how the crash plays out.
4. **Per-component thresholds with Froude scaling:** borrow PicaSim's √size rule to carry thresholds across the four aircraft, then override them per aircraft in `openrc-aircraft v1` with `{value, unit, kind, source}`.
5. **Persistence for in-flight overstress** (load above the limit for ≥ 0.2 s, borrowed from the A-4E), with creak and crack audio cues at 75 / 90 % of the limit (FlightGear). This gives the pilot a warning, and the cues are presentation only.
6. **Parent–child cascade table** in the aircraft data (RealFlight, War Thunder).
7. **Visual-only debris:** pre-split meshes from the model team (War Thunder / RealFlight `~CS_` approach), spawned as Godot `RigidBody3D` with the part's position and velocity at the break tick. Nothing is read back into the simulation, and debris is excluded from golden checks. Respect the model team's node names (`airplane`, `propeller`, `*_hinge`).
8. **One durability multiplier on all thresholds**, stored in settings and written to the trace header (doc 04), plus a "no damage" training mode (Liftoff God mode, Phoenix torque trainer).
9. **Configurable reset:** delay options (1.5 s default kept; add 3 s and "manual"), plus Phoenix's "at idle throttle" reset. Add rewind later from state snapshots in the recorder.

**Avoid**

1. Soft-body node-beam damage: BeamNG needs 2000 Hz and our budget is spent.
2. Godot physics or joints inside the simulation (32-bit and frame-synced; AGENTS rules).
3. `rand()` in damage decisions (FlightGear). If variety is wanted, hash (tick, component id) deterministically.
4. Runtime mesh slicing (convex only, costly).
5. A global Δv/Δω rule as the primary criterion: it depends on dt and ignores which part touched.
6. All-or-nothing crashes on gentle touches (MSFS complaints). The wingtip-scrape anchor in doc 04 covers this.

## Numbers worth borrowing

| Quantity | Value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| Max contact speed without crash (heli default) | 5 | m/s | borrowed | Heli-X `MaximalContactVelocity` |
| Contact impact damage threshold (full-size, common) | 1574.8 ft/min = 8.0 | m/s | borrowed (search only) | FS `contact_points` field 4 |
| Hardpoint crash force, 0.66–0.96 kg glider | 5 lbf = 22.2 (≈ 2.4–3.4 × weight) | N | borrowed | CRRCSim `allegro.xml` |
| Crash Δv (x, y, z) / Δω, per update, default | 5, 5, 10 / 500 | m/s / °/s | borrowed | PicaSim `GameSettings.cpp` |
| Size scaling of Δv / Δω limits | × √s / × 1/√s | — | borrowed | PicaSim `AeroplanePhysics.cpp` |
| Relaunch delay after crash | 3 | s | borrowed | PicaSim; Phoenix default |
| Reset delay presets | 0, ≈1, ≈3, ≈6 | s | borrowed | RealFlight 7.5 manual |
| Overstress persistence before a wing breaks | 0.2 | s | borrowed (ideas only) | A-4E `FlightModel.cpp` |
| Damaged strip drag factor | 0.7 × integrity | — | borrowed (ideas only) | A-4E `FlightModel.cpp` |
| Overstress cue levels / break | 50, 75, 90 / 100 | % of limit | borrowed | FlightGear `crash-and-stress.nas` |
| Negative wing-load limit if unspecified | −0.4 × positive | — | borrowed (estimate in source) | FlightGear `crash-and-stress.nas` |
| Prop damage step | 25 | % | borrowed | VelociDrone manual |
| KSP part impact tolerance (structural wing / engine) | 15 / 7 | m/s | borrowed (search only) | KSP wiki and forum |
| BeamNG physics rate | 2000 | Hz | borrowed | BeamNG architecture doc |
| RealFlight component strength default / user "realistic" | 110 / 50–60 (wing), ≤ 22 (gear) | % | unverified (forum) | RealFlight forum |

## Sources

1. RealFlight Help Guide (Evolution / Trainer Edition, 2024), Horizon Hobby. https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1314820/manuals/RealFlight_Help_Guide.pdf (fetched)
2. RealFlight 7.5 manual. https://xcopter.com/xcopter/support/simulator/RealFlight_7.5_Manual.pdf (fetched)
3. "Creating a RealFlight model with Blender", ArduPilot Discourse. https://discuss.ardupilot.org/t/creating-a-realflight-model-with-blender/116967 (fetched)
4. "Ripping the Wings Off", RealFlight forum. https://forums.realflight.com/index.php?threads/ripping-the-wings-off.22923/ (fetched)
5. Phoenix R/C 3.0 user manual. https://www.astramodel.cz/manualy/runtime/RTM3000-Manual_EN.pdf (fetched)
6. aerofly RC 10 manual. https://www.ikarus.net/en/rc10-manual/ (fetched)
7. HELI-X User's Guide 10.1. https://www.skyraccoon.com/assets/pdf/HELI-X-V10_3387.pdf (fetched)
8. PicaSim source (PolyForm Noncommercial 1.0.0): `AeroplanePhysics.cpp`, `Wing.cpp`, `PropellerEngine.cpp`, `JetEngine.cpp`, `ChallengeFreeFly.cpp`, `GameSettings.cpp`. https://github.com/Rowlhouse/PicaSim (fetched)
9. CRRCSim source (GPL-2.0): `src/SimStateHandler.cpp`, `src/mod_fdm/gear01/gear.cpp`, `models/allegro.xml`. https://github.com/mrtbrnz/crrcsim (fetched)
10. VelociDrone desktop manual. https://velocidrone.co.uk/desktop_manual (fetched)
11. Liftoff support. https://www.liftoff-game.com/support (fetched)
12. Oscar Liang, FPV simulator round-up. https://oscarliang.com/fpv-simulator/ (fetched)
13. FlightGear YASim `Model.cpp`, `YASim.cxx` (GPL-2.0). https://gitlab.com/flightgear/flightgear/-/tree/next/src/FDM/YASim (fetched)
14. JSBSim discussion #819, "Crash Detection". https://github.com/JSBSim-Team/jsbsim/discussions/819 (fetched)
15. `crash-and-stress.nas` v0.19 (GPL-2.0+), Slavutinsky, Christensen. https://github.com/NikolaiVChr/OpRedFlag/blob/master/libraries/crash-and-stress.nas (fetched)
16. MSFS SDK, `[CONTACT_POINTS]`. https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model/contact_points.htm (fetched)
17. FS contact points with 1574.8 ft/min, community forum. https://forum.flyawaysimulation.com/forum/topic/5779/contact-points-explained-and-some-fixes/ (search result only)
18. MSFS 2024 damage options, FlyAway Simulation. https://flyawaysimulation.com/ask/answers/enable-damage-failures-msfs-2024/ (fetched; secondary)
19. MSFS forum, "Unrealistic! Accident tolerance and damage". https://forums.flightsimulator.com/t/unrealistic-accident-tolerance-and-damage-to-aircraft/334052 (fetched)
20. DCS Damage Model Development Report, 2020-11-06. https://www.digitalcombatsimulator.com/en/news/2020-11-06/ (fetched)
21. DCS G.91R Development Report, 2026-09-04. https://www.digitalcombatsimulator.com/en/news/2026-09-04/ (fetched)
22. Community A-4E-C EFM (All Rights Reserved): `ExternalFM/FM/FlightModel.cpp`, `Scooter.cpp`. https://github.com/Community-A-4E/community-a4e-c (fetched)
23. IL-2 damage model overview, Stormbirds. https://stormbirds.blog/2020/04/18/a-look-at-il-2s-new-damage-model-system/ (search result only)
24. War Thunder CDK, "3D models for aircraft". https://wiki.warthunder.com/cdk/232-3d-models-for-aircraft (fetched)
25. War Thunder forum, "Aircraft Damage Model Overhaul". https://forum.warthunder.com/t/aircraft-damage-model-overhaul/14252 (search result only)
26. KSP wiki, Wing Connector Type A. https://wiki.kerbalspaceprogram.com/wiki/Wing_Connector (search result only; wiki blocks fetch)
27. KSP forum, part file explanation and crash tolerance threads. https://forum.kerbalspaceprogram.com/topic/25217-part-file-explanation (search result only)
28. Kerbal Krash System. https://forum.kerbalspaceprogram.com/topic/129410-1100-kerbal-krash-system-051-2020-08-05 (search result only)
29. Unity `Joint.breakForce`. https://docs.unity3d.com/550/Documentation/ScriptReference/Joint-breakForce.html (search result only)
30. BeamNG beams. https://documentation.beamng.com/modding/vehicle/sections/beams/ (fetched)
31. BeamNG architecture. https://documentation.beamng.com/beamng_tech/architecture/ (fetched)
32. BeamNG deterministic mode. https://documentation.beamng.com/beamng_tech/deterministic_mode (fetched)
33. Rigs of Rods truck file format. https://docs.rigsofrods.org/vehicle-creation/fileformat-truck/ (fetched)
34. Teardown (Wikipedia; 80.lv). https://en.wikipedia.org/wiki/Teardown_(video_game) (search result only)
35. Burnout 3: Takedown (Wikipedia). https://en.wikipedia.org/wiki/Burnout_3:_Takedown (search result only)
36. Godot repos: Jummit/godot-destruction-plugin, the-dunk/Godot-Destruction, Terabase-Studios/Godot-Voxel-Destruction (READMEs fetched via `gh`)

## Limits of this research

- **RealFlight internals are not public.** Its component strength %, the default of 110 and the "realistic" values come from one forum thread. Whether partial damage changes aerodynamics or only geometry is unverified.
- **No damage details were found** for aerofly RC 10, neXt, ClearView, Besiege, Stormworks or Juno. "Not found" does not mean "not present".
- **KSP numbers are search snippets;** the wiki blocked fetching. KSP's exact collision-speed definition (relative or normal velocity) is unverified.
- **The MSFS 1574.8 ft/min value comes from community configuration examples,** not from Asobo's documentation. The SDK page's own example value (2.5) does not match its stated unit.
- **The A-4E code is All Rights Reserved and PicaSim is PolyForm Noncommercial:** we take ideas and numbers only, never code.
- **No number here was measured on our aircraft.** Every threshold copied into `app/data/aircraft/` must keep `kind: borrowed` or `estimated` until a test or the owner's judgement validates it. The per-tick cost of the proposed checks is estimated as small (comparisons per hull point) but has not been benchmarked.
