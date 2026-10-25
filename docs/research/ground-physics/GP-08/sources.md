# GP-08 — advanced ground/flight audit and source ledger

Date: **2026-10-25**. Status: **planning research only; GP-08 implementation/qualification remains pending**. Authoritative proposal: [advanced ground-flight physics masterplan](../../../advanced-ground-flight-physics-masterplan.md). Existing GP results remain in the [ground evidence index](../README.md).

## Scope and execution truth

The mission requested an audit and implementation plan, not code changes. The primary deliverable has all fourteen requested sections; this ledger preserves dated evidence and source limitations. No runtime physics, aircraft data, assets or tests were implemented by this mission. No flight, drop, audio listening, physical hardware measurement or performance campaign was executed. The Godot specialist did execute the pinned local binary's `--version`, obtaining `4.8.beta1.official.4d10419ca`. Source inspection, primary-source browsing, document path/structure checks and specialist reviews are the evidence produced here. Existing test files and historical reports are cited as reusable assets, not newly passing tests.

The `openrc-tools` skill and tool index were used. Codebase-memory graph discovery preceded source fallback. The graph was materially stale: its FlightSession snapshot was approximately 1,000 lines while the live file was approximately 4,900. Current source and symbols took precedence over stored graph ranges; unsuccessful graph lookup did not establish absence.

Six requested specialist roles were actually executed using **`gpt-6.1-sol`, high reasoning**, with fresh task context and explicit read-only boundaries. No unavailable-model fallback was needed. Work ran in bounded batches within the available concurrency, with architecture/integration and final reviews sequenced after initial findings.

| Specialist | Evidence handoff and influence on final recommendation |
| --- | --- |
| Aircraft Ground Dynamics Physicist | Current wheel/contact law, arbitrary-rate energy-proof limitation, coupled relative-spin equations, friction/static/rolling distinctions, numerical bounds and primary mechanics sources. |
| Aerodynamics & RC Aircraft Specialist | Actual fleet capabilities/generators, local-flow/GE/wash bookkeeping, gear drag/trim, RC-scale limits and manufacturer/FAA research. |
| Godot Physics Architect | Actual beta1 binary/pin/default backend, custom float64 ownership, generic callback limitations, supported query APIs and native alternative assessment. |
| Landing Gear & Damage Engineer | Current continued hull/prop responses versus terminal overtravel, per-component work/strength, moving mechanisms, detachment, intentional gear-up accidents and heavy/asymmetric landing review. |
| Game Audio & Feedback Designer | Actual ground-audio polling/material aliases, pools/assets/tools, accepted packet design, pinned engine playback semantics, licensing and native-output gates. |
| Simulation QA & Integration Architect | Existing tests/logs/Workshop/lifecycle, quantitative gates, concurrent UI-FS conflict, minimal generation-latched M7 compatibility, rollback and bounce evidence requirements. |

The main agent selected the final architecture and resolved disagreements in masterplan §14: retain continuous custom integration first; separate semantic incidents from M7's generation latch; reuse existing audio allocation; treat bounce as mechanics and unknown strength as unknown. Final damage/QA review corrected moment-frame wording, power-off balloon energy, topology limits and crash-count scope. Specialist scratch handoffs remain ignored working material; the tracked plan and this ledger contain the durable conclusions.

## Repository identity and concurrent-work boundary

Initial baseline HEAD: `4336ba6897e46adef2fe88aa24f55e639d5ad140`. Other work changed the shared tree and HEAD during the audit, including observed commits `82376c1155c5557ea3397e10b81a6d4cd7b904a9`, `dd80491b7a1c32f1483f5b47dd9a49a1218464c3`, and final source-identity sampling at `498767e39859dff33ea8f38dc6caf2a6456455aa`. This mission did not stage or create those commits. Consequently this is a symbol/source audit, not an isolated reproducible runtime qualification receipt. Re-freeze at implementation GP-08.

Statistics was a plan at the initial baseline and became an active implementation during the audit. Later `app/statistics/detector.gd::observe/_handle_terminal` used terminal observations to emit crash, latch and close flight; this confirms the nonterminal-accident integration requirement, but does not establish the evolving feature's accepted status. Mechanical audio, Workshop, lighting, UI and other concurrent changes likewise remain outside this audit's implementation ownership. Re-read those source files before GP-14/19/20.

Working-file Git blob identities sampled for decisive seams:

| File | Blob |
| --- | --- |
| `app/sim/vehicle_model.gd` | `69e3b497bc2a9e1ee12615ad520a32cecc0bb73c` |
| `app/sim/simulation.gd` | `36611de464fba91bc53e752570e5d98b9a7a0501` |
| `app/sim/flight_session.gd` | `d88b7c2b22eab51391320e262c47879f9b8841ed` |
| `app/physics/ground_wheels.gd` | `ef16c932191054f24092bb0a19a386a6bb538f9a` |
| `app/physics/ground_contact.gd` | `cce7c7e02dc51319975858bdd25af49d2b53e688` |
| `app/physics/fixed_datum_body.gd` | `174799bb22df43a5a9ae571776a707916a639a0f` |
| `app/sim/aircraft_contact_events.gd` | `45ea5b75b6601c4b9e18deeca2aa5340b16ed1e5` |
| `app/audio/ground_audio_model.gd` | `97121a3b01fecd6897f9a03b600ff17996edcbff` |
| `app/statistics/detector.gd` | `222896a40ebcf56c74c4a8bcd29e2a86b961e414` |
| `app/statistics/rules.gd` | `da12c9dde829b782ed1312d0491f868cb1f8732f` |

Source paths/functions and implementation classifications are in masterplan §2; they are not duplicated here as another operating guide. Native backend resolution is **configuration plus pinned-source inference**, not live server introspection: no backend override was found, `DEFAULT` resolves to GodotPhysics3D in this binary's source. Authoritative aircraft integration is the repository's custom float64 kernel regardless of that native default.

## Primary mechanics and landing references

Access/review date for this source set: 2026-10-25. Sources were reviewed by the specialists and selected checks repeated by the main agent. Access scope below matters: an archival record or abstract is not a full-paper reading. No quoted manufacturer's or certification coefficient is silently adopted as an RC tire/gear parameter.

| ID / primary source | Supported use | Access and transfer limit |
| --- | --- | --- |
| M1 — [JSBSim FGLGear reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGLGear.html) | Per-contact bogey/structure configuration, spring/damping and separate friction/steering/brake properties. | Documentation/source review. Main-agent direct open later returned 404, but indexed official documentation was retrievable via search. Useful precedent, not RC calibration or guaranteed URL permanence. |
| M2 — [JSBSim FGAccelerations source](https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/FGAccelerations.cpp), `CalculateFrictionForces` | Mobility and bounded iterative contact reactions as an alternative/reference. | Mutable master source; pin exact commit/content before implementation reuse. LGPL code license must be reviewed if copying code. This plan reuses repository math and does not import it. |
| M3 — [Flugge & Coale, NACA TN-3217, 1954](https://ntrs.nasa.gov/citations/19930084093), *The influence of wheel spin-up on landing-gear impact* | Primary historical lead for wheel inertia/tangential impact coupling. | NTRS archival metadata verified; PDF fetch failed during specialist research. No fresh full-paper derivation or numerical parameter extraction claimed. |
| M4 — [FAA AC 23-19A, 2007](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_23-19A.pdf), landing-gear discussion around printed p.50 | Spin-up/springback and separate longitudinal/vertical load cases; testing methodology. | Historical full-scale guidance. Neither current RC regulation nor a universal safe sink/drop height. |
| M5 — [Stewart & Trinkle, implicit time stepping with Coulomb friction](https://www.cse.lehigh.edu/~trink/Papers/STicra00.pdf) | Coupled impulse/contact alternative and treatment of nonsmooth mechanics. | Research paper; not a drop-in pure RK4 stage law, nor evidence of GDScript performance. |
| M6 — [Project Chrono 9.0 tire models](https://api.projectchrono.org/9.0.0/wheeled_tire.html) | Tire-model domains, combined/transient slip and limits of handling models on deformable soil. | Versioned official documentation; automotive parameter sets are not RC foam/rubber measurements. |
| M7 — [FAA AC 25.723-1](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/22663) | Landing-gear dynamic-test methodology and distinction between analysis and test evidence. | Official advisory record, full-scale transport context. No certification claim or RC strength limit derived. |
| M8 — [NASA CR-3113 landing gear study, 1979](https://ntrs.nasa.gov/citations/19790015777) | Historical dynamic gear-model/testing research. | Archival study of a 2,722 kg aircraft; method reference only, not scale-transfer authority. |
| M9 — USDA *Wood Handbook*, [2021 chapter 5](https://research.fs.usda.gov/treesearch/62244) and [chapter 10](https://research.fs.usda.gov/treesearch/62250) | Material variability and assembly/joint dependence; reason for component-specific evidence. | Government reference records. Bulk wood properties do not establish a balsa/plywood/glue airframe joint's ultimate load. |

The masterplan's coupled equations, virtual-work requirements, force ownership and controlled fixtures are engineering derivations from mechanics and current repository conventions. Proposed tolerances and stage-solver selection are design decisions, explicitly distinguished from measured hardware data. The +0.8 W example is a calculation under an inadequate additive energy oracle, **not a measured increase in the correct total energy of a running aircraft**.

## Aerodynamics and RC configuration references

| ID / primary source | Supported use | Access and transfer limit |
| --- | --- | --- |
| A1 — FAA *Airplane Flying Handbook*, [chapter 6](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/07_afh_ch6.pdf) | Tricycle takeoff, rotation, departure and ground-effect context. | Official handbook. Qualitative mechanism/technique context; full-scale speeds and advice are not universal RC control laws. |
| A2 — FAA *Airplane Flying Handbook*, [chapter 14](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/15_afh_ch14.pdf) | Tailwheel configuration, directional stability, tailwheel control and wheel/three-point landings. | Official handbook; pilot procedure does not replace force/moment equations or installed control geometry. |
| A3 — Phillips & Hunsaker, 2013, [author repository record](https://digitalcommons.usu.edu/mae_facpub/81/), [DOI](https://doi.org/10.2514/1.C032152) | Ground-effect dependence on wing geometry/height and limits of simple correction factors. | Author abstract/record reviewed, not a newly acquired full validation dataset. |
| A4 — [E-flite Turbo Timber manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dwf0e3a412/Manuals/EFL105275-Manual-EN.pdf) | Actual RC configuration and operating/gear context. | Manufacturer manual. Reference aircraft features are not proof that the current Turbo Lumber simulator implements them. |
| A5 — [CARF Corsair manual](https://carf-models.com/files/product/34/ed/06/corsair_manual.pdf), p.44 | RC taildragger/nose-over caution and configuration context. | Manual reviewed; product-page route returned 404. The simulator/manual discrepancy is an open test, not a pitch override justification. |
| A6 — UIUC [SoarTech 8 low-Reynolds-number airfoil record](https://m-selig.ae.illinois.edu/ads/soartech8_abs.html), [publication index](https://m-selig.ae.illinois.edu/publications.html) | RC-relevant Reynolds-number regime and the importance of matched aerodynamic evidence. | Primary university records; one direct data page timed out. No new airfoil fit/data ingestion by this mission. |
| A7 — Selig 2010, [small-UAV propeller/slipstream author record](https://experts.illinois.edu/en/publications/modeling-propeller-aerodynamics-and-slipstream-effects-on-small-u-3/), [DOI](https://doi.org/10.2514/6.2010-7938) | Slipstream modeling scope and installation dependence. | Bibliographic/abstract record reviewed, not full-paper acquisition. Existing repository wake/wash implementation remains authoritative. |
| A8 — [E-flite 700-class retract manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dwb64302f4/Manuals/EFLG700-manual-MULTI.pdf) | Example of real retract power/obstruction/door constraints requiring hardware-specific models. | Manufacturer example only; no claim that all stock aircraft install this unit. |
| A9 — FAA *Airplane Flying Handbook*, [chapter 9](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/10_afh_ch9.pdf), pp.9-32–34 | Landing/balloon/bounce discussion, especially pitch/AOA change after main-wheel contact. | Official chapter located and relevant passage read by the main agent. Its emphasis on aerodynamic bounce does not eliminate elastic rebound in an RC gear-drop fixture; quantify both with separate energy channels. |

A previously cited NACA WR-L-95 route was inaccessible (403) during specialist research and is not used as newly verified evidence. Existing repository aircraft source manifests remain the primary provenance for current coefficients. No new universal gear CdA, friction, damping, strength or GE constant is claimed.

## Exact Godot version and API evidence

Pinned official source commit: **`4d10419cacd6d3009976e8f9fd3abd970fd58018`**, matching the project's Godot 4.8-beta1 pin and observed CLI identity. Context7 helped discovery but returned a 4.7/master documentation corpus; decisive beta1 claims were corroborated against pinned source/XML. GitHub HTML occasionally returned a cache miss; raw source was available for main-agent rechecks.

| ID / pinned primary source | Supports |
| --- | --- |
| G1 — [ProjectSettings XML](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/ProjectSettings.xml), [GodotPhysics3D registration](https://raw.githubusercontent.com/godotengine/godot/4d10419cacd6d3009976e8f9fd3abd970fd58018/modules/godot_physics_3d/register_types.cpp), [server manager](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/servers/physics_3d/physics_server_3d_manager.cpp) | Missing setting resolves via DEFAULT to registered GodotPhysics3D; a new-project Jolt selection is different from this existing project's unset setting. |
| G2 — [RigidBody3D XML](https://raw.githubusercontent.com/godotengine/godot/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/RigidBody3D.xml), [PhysicsDirectBodyState3D XML](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/PhysicsDirectBodyState3D.xml) | Force integration/contact APIs; custom integrator does not disable collision response. Native collision is therefore not an additive upgrade to custom flight. |
| G3 — [VehicleBody3D XML](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/VehicleBody3D.xml) | Native vehicle limitations and reason to reject it for this aircraft roadmap. |
| G4 — [PhysicsDirectSpaceState3D XML](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/PhysicsDirectSpaceState3D.xml), [shape query parameters](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/PhysicsShapeQueryParameters3D.xml) | Query/mask/exclusion APIs, motion casts and initial-overlap limits; optional geometry adapter only. |
| G5 — [RayCast3D](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/RayCast3D.xml), [ShapeCast3D](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/ShapeCast3D.xml), [World3D](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/World3D.xml) | Cached query/update behavior and direct-space access context. Native query precision/order is not a cross-platform exact-replay guarantee. |
| G6 — [AudioStreamPlayer3D XML](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/AudioStreamPlayer3D.xml), [internal player source](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/scene/audio/audio_stream_player_internal.cpp), [3D player source](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/scene/3d/audio_stream_player_3d.cpp) | Queued play scheduling, stop/pending-play/pause ownership, spatial playback and bounded pool lifecycle. Source observations, not newly run native audio probes. |

## Audio assets and reuse

Existing import pipeline: `tools/audio/import_landing_gear.py`, `numpy==2.4.6`, `miniaudio==1.71`, `app/assets/audio/landing_gear/manifest.json` and uncompressed WAV import settings. Original-provider pages were reviewed by the audio specialist; no new recordings were downloaded or generated by this mission.

| Original source | Existing/proposed role and limitation |
| --- | --- |
| [FOSSarts skateboard, CC0](https://freesound.org/people/FOSSarts/sounds/740125/) | Existing hard rolling proxy; not an RC wheel calibration recording. |
| [FOSSarts grass footstep, CC0](https://freesound.org/people/FOSSarts/sounds/740144/) | Existing vegetation texture proxy; no real tire-load transfer inferred. |
| [alexftw123 car wheel on gravel, CC0](https://freesound.org/people/alexftw123/sounds/152657/) | Existing gravel texture; car scale/perspective remains a limitation. |
| [Grotelue sailplane touchdown, CC0](https://freesound.org/people/Grotelue/sounds/204737/) | Existing touchdown proxy; onboard/full-scale recording is not externally heard RC audio. |
| [Kenney Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds) | Free original-provider CC0 bank, 130 files; candidate for audition only, not yet selected/downloaded/validated for a specific component. |
| [Creative Commons CC0](https://creativecommons.org/publicdomain/zero/1.0/) | License reference. Retain source/license/retrieval/hash/edit recipe per asset; other licenses need their own redistribution/attribution review. |

Existing HQ MP3 previews have lossy-source limits even when converted to WAV. Appropriate freely downloadable assets should be evaluated before creating substitutes. Audio quality, material authenticity, native mixer deadlines and listening acceptance remain future gates.

## Verification of this documentation

The final document check covers fourteen top-level sections, all sixteen proposed GP-08…23 step IDs, local Markdown file targets, fenced-block balance and whitespace. It does not resolve every external URL, execute physics scenarios, establish performance, or certify measured bounce/strength behavior. The working tree contains unrelated changes; only the masterplan, this source ledger and small GP index links belong to this mission's authored deliverables.
