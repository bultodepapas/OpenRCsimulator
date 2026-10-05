# RC airplane simulator: exploratory research notebook

Research date: **2026-10-05**. This is a growing collection of evidence, possibilities, and questions, not a stack selection or a requirements document. The only established principles remain those in [AGENTS.md](AGENTS.md). [DECISIONS.md](DECISIONS.md) records decisions when we actually make them.

## Contents

- [Reading the evidence](#reading-the-evidence)
- [Existing simulators, communities, and experience design](#existing-simulators-communities-and-experience-design)
- [Flight physics: several useful levels of approximation](#flight-physics-several-useful-levels-of-approximation)
- [RC-scale aerodynamics and model authoring](#rc-scale-aerodynamics-and-model-authoring)
- [Electric propulsion: distinguish the components and their evidence](#electric-propulsion-distinguish-the-components-and-their-evidence)
- [Wind, thermals, and inexpensive validation](#wind-thermals-and-inexpensive-validation)
- [Engines, platforms, and controls: several viable paths](#engines-platforms-and-controls-several-viable-paths)
- [RC input is an end-to-end pipeline](#rc-input-is-an-end-to-end-pipeline)
- [Simulation timing, reproducibility, and useful observations](#simulation-timing-reproducibility-and-useful-observations)
- [Assets, environments, and sensory feedback](#assets-environments-and-sensory-feedback)
- [Adjacent robotics and autopilot ecosystems](#adjacent-robotics-and-autopilot-ecosystems)
- [AI-assisted development as an experiment we can observe](#ai-assisted-development-as-an-experiment-we-can-observe)
- [Continuing the research](#continuing-the-research)

## Reading the evidence

- **Documented / source inspected:** an original manual, specification, repository, or implementation supports the stated capability. This does not mean we have built it or tested it on our hardware.
- **Measured / research evidence:** an original experiment or dataset reports results within stated conditions. Generalization beyond those conditions remains a question.
- **Author or vendor claim:** a project's author describes performance, realism, or intended behavior that we have not independently validated.
- **Community report:** a firsthand user experience or issue, useful for identifying experiments but not proof of universal behavior.
- **Inference / experiment:** our interpretation or an idea to investigate, not an established project commitment.

No simulator, engine export, transmitter, or flight model was run in this research pass. Sources were read online; some raw source files and documentation were fetched directly when browser extraction failed. Unless an entry states another version, links to `main`, `master`, `stable`, and `latest` refer to the pages inspected on the research date and can change. License observations describe the inspected source; they do not establish compatibility of an eventual combined application.

## Existing simulators, communities, and experience design

### CRRCSim: a concentrated archive of RC-specific problems

**Evidence: official project metadata and historical release notes inspected.** The project identifies Linux, Mac, and Windows ports and GPLv2 licensing. Its published 0.9.13 release was created on 2016-04-10; that date alone does not establish the state of every fork or downstream package. [Project page](https://sourceforge.net/projects/crrcsim/) · [Release files and cumulative notes](https://sourceforge.net/projects/crrcsim/files/crrcsim/crrcsim-0.9.13/).

Useful details in those notes include configurable thermals, a turbulence model attributed to MIL-HDBK-1797, flap and spoiler effects, improved propellers, launch presets, F3F slope racing, F3A practice, slow motion, and delayed camera tracking. Older entries describe a propulsion chain with battery voltage/current/capacity, shaft and gearbox inertia, efficiency, and folding propellers. This is a good place to find how RC concerns accumulated over time, beyond generic lift/drag examples. [Release notes](https://sourceforge.net/projects/crrcsim/files/crrcsim/crrcsim-0.9.13/).

**How it could help:** inspect small subsystems, configuration examples, and past bug fixes when exploring wind, launches, control mixing, and propulsion. Historical implementation choices can suggest experiments without obliging us to inherit its application structure. **Open questions:** current compiler compatibility, numerical behavior, aircraft calibration, and exact reusable-file licenses still need source-level review and execution.

### PicaSim: study the current source and the older website separately

**Evidence: current repository, license, and author website inspected.** The current repository documents build infrastructure for Windows, Linux, macOS, Android, and iOS, plus distinct framework, aircraft application, terrain, platform abstraction, and bundled Bullet physics directories. These are concrete architecture/build references; builds were not executed. [Repository and build instructions](https://github.com/Rowlhouse/PicaSim).

The older author website emphasizes gliders, powered aircraft, custom planes, and scenery, while also saying development is on hold. It should not be treated as the sole authority for the newer repository. The current `LICENSE.txt` is **PolyForm Noncommercial 1.0.0**, copyright 2026, with permitted-purpose restrictions. Record it as source-available with restrictions; public source visibility does not establish unrestricted reuse in our open-source project. [Older website](https://www.rowlhouse.co.uk/PicaSim/) · [Current license](https://github.com/Rowlhouse/PicaSim/blob/main/LICENSE.txt).

**How it could help:** compare how one RC application organizes platforms and custom content, and study its soaring experience. **Open questions:** what changed between original releases and the present repository, which assets have independent terms, and which documented targets actually build from a pinned revision.

### Slope Soaring Simulator: component aerodynamics and wind as the environment

**Evidence: original author's overview, download page, and manual inspected.** SSS describes C++/OpenGL/GLUT, GPL licensing, and separate aerodynamic, physical, and graphical representations. Its component approach models independent aerofoils described in text files, while graphical aircraft can use component geometry or 3DS models. Terrain and wind can be loaded or generated. [Author overview](https://www.rowlhouse.co.uk/sss/).

An unusual lead is its terrain workflow: grayscale images become heightfields, while windfields may come from the meteorological model Metphomod or be generated by SSS. The author explicitly warns that a coarse wind grid spreads lift regions too much. The manual also documents a dynamic-soaring setup. The overview and download page give different version numbers, so avoid declaring a definitive latest release from either alone. [Download and terrain notes](https://www.rowlhouse.co.uk/sss/download.html) · [Manual](https://www.rowlhouse.co.uk/sss/documentation.html).

**How it could help:** explore soaring with a small terrain and spatially varying wind rather than a large scenery catalog. **Open questions:** aerodynamic interactions between components, wind interpolation, portability today, and how much of the historical source is educational versus directly reusable.

### FlightGear and JSBSim: distinguish a complete simulator from its flight model

**Evidence: official project documentation inspected.** FlightGear documents a complete desktop simulator with aircraft, global scenery, networking, external interfaces, and Windows/macOS/Linux support under the GPL. JSBSim separately documents a C++ flight-dynamics framework whose aircraft are defined with XML, configurable systems and aerodynamic coefficients, real-time or batch execution, and configurable outputs. Its documentation identifies LGPL licensing. [FlightGear features](https://www.flightgear.org/about/features/) · [JSBSim introduction](https://jsbsim-team.github.io/jsbsim/).

The JSBSim project's FAQ gives an explicit example running two executables: FlightGear receives external state over UDP with its own FDM disabled, while JSBSim sends the simulated state. This is evidence of a documented separation between visualization and dynamics. [Integration example](https://github.com/JSBSim-Team/jsbsim/wiki/Frequently-Asked-Questions).

**How it could help:** a future experiment could compare an embedded FDM, a separate simulation process, or FlightGear as a temporary visualizer. A small headless experiment may answer physics questions before a full UI exists. **Limitations:** an FDM library does not itself provide an RC pilot camera, transmitter onboarding, or a calibrated small-aircraft model. We have not tested integration latency or reviewed distribution obligations for a chosen integration.

### RCForge: browser simulation with unusually explicit uncertainty

**Evidence: repository README, MIT license, and model-evidence pages inspected.** RCForge describes editable JSON aircraft/components, center-of-gravity changes, keyboard/gamepad/RC input, browser-local editing, replay/CSV experiments, and a physics core shared with command-line tools. It differentiates self-hosted operation from sign-in restrictions on its hosted service. The README explicitly calls presets uncalibrated against real flight data. The inspected README referred to 0.8.0 development while the validation page referred to simulation 0.8.1; use a pinned revision when investigating behavior. [Repository](https://github.com/adithya-s-k/RCForge) · [MIT license](https://github.com/adithya-s-k/RCForge/blob/main/LICENSE).

**How it could help:** explore aircraft definitions as inspectable data, preserve sources and estimates beside parameters, and make experiments reproducible. Its distinction between a numerical implementation check and agreement with real flight is especially relevant to an AI-heavy project. It also separates using coding agents during development from requiring AI services during play. [Validation notes](https://github.com/adithya-s-k/RCForge/blob/main/docs/validation.md) · [Benchmark notes](https://github.com/adithya-s-k/RCForge/blob/main/docs/benchmarks.md).

**Limitations:** the listed capabilities remain author-documented here; tests and comparisons were not reproduced. Aircraft design references and bundled assets retain separate rights. Plan images are described as references requiring interpretation, not automatic aerodynamic models.

### yotamgi/rcsim: a lightweight native/web route worth inspecting

**Evidence: README and CMake configuration inspected.** This repository describes RC airplanes and helicopters, modular aircraft, mixers, flight controllers, servo filtering, and desktop/web operation. Its build file concretely fetches raylib 5.5 and raylib-cpp v5.5.0 and contains an Emscripten branch using WebGL2, WASM, preloaded resources, and memory growth. Linux linkage appears explicitly in the native branch. [Repository](https://github.com/yotamgi/rcsim) · [Build configuration](https://github.com/yotamgi/rcsim/blob/main/CMakeLists.txt).

**How it could help:** compare a compact code-first application with a full editor-based engine; inspect how controls and aircraft configuration are organized before assuming sophisticated tooling is necessary.

**Limitations:** a README claim of cross-platform support is broader than the Linux and Emscripten instructions inspected. We did not establish Windows or macOS build success, inspect all aerodynamic implementations, or verify a license grant. The inspected root listing did not expose a license file; resolve reuse terms before borrowing code. The advertised helicopter effects do not prove fixed-wing fidelity.

### DaScient/RC-Flight-Sim: a useful example of why feature tables need qualification

**Evidence: README and build instructions inspected.** The project advertises Godot 4, JSBSim, several camera modes, transmitter calibration, multiple platforms, and an optional LLM instructor. However, its quick-start extension build uses `JSBSIM_ENABLED=OFF`, and its documentation explicitly says that this produces a kinematic fallback. Android build instructions also show the flag disabled. [Repository](https://github.com/DaScient/RC-Flight-Sim) · [Build instructions](https://github.com/DaScient/RC-Flight-Sim/blob/main/docs/build_instructions.md).

**How it could help:** inspect the intended boundary between input/cameras and a replaceable dynamics backend. It also suggests an incremental demonstration: a visible airplane and functioning input can precede a mature FDM.

**Limitations:** do not repeat “full JSBSim physics on every listed platform” as verified. A build/export matrix, a fallback implementation, and a calibrated aircraft are different evidence. The source and CI need deeper inspection before treating this as a working integration reference. Its in-game AI feature is a separate product experiment, not a necessary consequence of AI-assisted development.

### Propwash: an adjacent prototype with honest model omissions

**Evidence: repository documentation inspected; multirotor scope.** This browser FPV prototype documents gamepad and keyboard/mouse controls, configurable JSON5 definitions, first/third-person views, and returning to the position from a second earlier. It explicitly lists missing battery sag, ground effect, propwash, motor saturation, and airflow-dependent thrust. Attitude response is approximated rather than a complete motor/controller model. Its asset attribution table distinguishes code dependencies from differently licensed scenery, including a noncommercial asset. [Repository](https://github.com/mqnc/propwash).

**How it could help:** learn from the interaction loop, quick recovery after mistakes, accessible configuration, and clear disclosure of simplifications. This fits gradual growth: a useful prototype can describe its limits precisely.

**Limitations:** multirotor response is not a fixed-wing model. “Uses a physics engine” would not imply the omitted aerodynamics exist. Model, sound, and map rights should be tracked individually rather than inferred from a repository-wide badge.

### Commercial feature references: RealFlight and aerofly RC

**Evidence: official manuals and vendor feature documentation, not independent performance measurements.** RealFlight Evolution's help guide documents flight rewind, recording/playback with transmitter display, training videos, trajectory trails, a sky grid, aircraft editing, and photo-based fields. These are concrete UX references; claims that its physics or winds are the most realistic remain marketing claims. [RealFlight help guide, especially printed pages 5–6](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2069310/manuals/RealFlight_Help_Guide.pdf?t=1719957185).

Aerofly RC 10 documents a five-second skip-back action, F3A visual guides, dynamic-soaring flight paths, night flying, controller calibration, custom game-controller profiles, and RC Modes 1–4. Its homepage links Windows/Mac/Linux distribution and describes ground/follow VR viewpoints, but no platform or headset was tested. [Feature page](https://www.aeroflyrc.com/features/) · [Homepage](https://www.aeroflyrc.com/).

**How it could help:** form optional experiments around repeatable practice, readable input feedback, fast reset, and preserving a good flying view. These products are comparison references, not a feature checklist for our initial release. **Open questions:** which conveniences matter most to first-time users, and which require a larger simulation state or authoring system than the first prototype needs.

### SeligSIM: detailed teaching and camera references

**Evidence: official 2026 manual inspected.** The manual identifies SeligSIM 2026a and dates its update to September 21, 2026; it also explains its relationship to earlier FS One versions. Free download availability is not evidence that its implementation is open-source. [Manual homepage](https://www.seligsim.com/manual/).

Its training documentation describes narrated aircraft demonstrations with synchronized stick inputs, pause/slow playback, hover assistance, and thermal practice with sailplanes, launch methods, an optional thermal map, and acoustic variometer. **Possible use:** investigate learning aids that reveal the relationship between sticks, aircraft motion, and air movement. **Limit:** these documented teaching tools do not establish measured transfer to real flight. [Flight-training chapter](https://www.seligsim.com/manual/flight_training.html).

Its camera chapter distinguishes perfect tracking, tracking with lag, distance-based autozoom, shifted framing, and a Keep Ground In View mode that changes field of view with aircraft elevation. **Possible use:** treat the pilot camera as an experiment in aircraft visibility versus horizon/runway context; compare fixed framing, mild lag, and adaptive zoom on the same flight. **Limit:** many options are not automatically better for a beginner; readability and orientation should be observed on different display sizes. [Camera chapter](https://www.seligsim.com/manual/cameras.html).

### Scenery can be a panorama plus geometry, or a fully navigable world

**Evidence: two implementation/documentation approaches inspected.** SeligSIM's custom-field guide separates panorama imagery from field metadata, ground elevation, and optional collision geometry. The worked example specifies eye height and NED coordinates in feet; collision files consist of triangular facets with outward normals. A panorama therefore does not eliminate the need to align physical space, contacts, and visible obstacles. [Custom panorama guide](https://www.seligsim.com/manual/documentation.html).

PicaSim's parallax design note explains the limitation of a depthless cubemap in stereo VR, then describes depth-based offsets, expanded image-tile borders, and shader correction across cube-face boundaries. This is a documented implementation approach, not a quality assessment from a headset test. [Parallax panorama design](https://github.com/Rowlhouse/PicaSim/blob/main/ParallaxPanorama.md).

**How it could help:** a simple stationary pilot scene may be explored without committing to huge terrain generation. More freedom of movement, FPV, or stereo viewing introduces different scenery needs. **Open questions:** can a deliberately plain field provide better initial orientation cues; how accurately must photographic obstacles match collision geometry; and what content workflow is easiest for contributors?

### Firsthand community reports: useful questions, not capability certification

- **Input detection is not correct mapping.** In the Propwash author's Reddit thread, one user reports that a DJI FPV RC Controller 3 appears in Windows 10/Chrome but initially has incorrect mapping. The author notes a gamepad-centered hover behavior that could feel wrong with a transmitter throttle. **Possible use:** gather device, OS, browser, raw axes, direction, and expected stick behavior separately. **Limit:** this is one reported combination, not a universal support claim. [Original developer/user discussion](https://www.reddit.com/r/fpv/comments/1rr6yi2/im_making_an_open_source_fpv_drone_simulator_for/).
- **People want practice structure.** A beginner asks for measurable simulator exercises; replies describe patterns, figure-eights, touch-and-goes, wind variations, and dead-stick approaches. Several distinguish ground-view orientation practice from chase-camera enjoyment. **Possible use:** prototype a small optional exercise and observe whether it makes sessions more purposeful. **Limit:** advice and preferences from forum participants are not controlled training-effectiveness evidence or fixed requirements. [Original r/RCPlanes thread](https://www.reddit.com/r/RCPlanes/comments/1wr7gia/realflight_simulator_exercises_for_absolute/).
- **Community authorship is part of the simulator ecosystem.** PicaSim's forum index exposes custom-aircraft/scenery areas, modeling tutorials, suggestions, and device-specific bug reporting. **Possible use:** investigate where people struggle to create an aircraft or report a controller issue before designing contribution formats. **Limit:** the index proves those discussion areas exist; it does not verify every downloadable model or its license. [PicaSim forum](https://www.tapatalk.com/groups/picasim/).
- **Learning to use the transmitter is an explicit beginner need.** Flite Test's own beginner page presents simulation as practice using a transmitter with an RC model. **Possible use:** consider an early control-surface/stick visualization as an experiment even before sophisticated scenery. **Limit:** it is instructional/vendor guidance, not an independent efficacy study. [Flite Test beginner guide](https://beginner.flitetest.com/learn-to-fly/).

### Leads and gaps for the next research pass

These are possible investigations, not a planned roadmap:

1. Run a few existing simulators with one known controller, recording setup time, axis mapping, reset behavior, distant-aircraft visibility, and ground-view orientation. Separate those usability observations from judgments about aerodynamic fidelity.
2. Trace CRRCSim's propulsion and thermal implementations, and compare their equations/data with primary aerodynamics and propeller measurements. Historical release prose is only the starting point.
3. Inspect a small aircraft definition in SSS, PicaSim, RCForge, and JSBSim. Record exactly which values are measured, estimated, fitted, or derived; a visual mesh alone does not answer those questions.
4. Study a tiny contributor workflow: define one wing and tail, show calculated mass/CG and control surfaces, fly, then inspect a flight trace. The experiment could be implemented in several technologies.
5. Investigate community catalogs without automatically importing them. Record author, source, permission, geometry, physics provenance, and dependencies separately for each asset considered.
6. Search further into control-line simulation, discus launch, towline dynamics, dynamic soaring, intentional low-poly graphics, and instrument-free orientation practice. They offer distinct design questions beyond adding more powered aircraft.
7. Access limitations from this pass: the [PicaSim “Add planes” thread](https://www.tapatalk.com/groups/picasim/add-planes-in-picasim-t304.html) returned an anti-bot page; the [Oxford model-flying club's PicaSim article](https://oxfordmfc.bmfa.club/wp-content/uploads/2021/05/Picasim-Article.pdf) failed to open; the old PicaSim customization link also failed. They remain leads, not evidence used for technical conclusions. Older RealFlight product/update URLs redirected to a general vendor page, so the linked official PDF was used for feature details instead.

Search routes included combinations of `CRRCSim source electric propulsion`, `PicaSim source custom scenery`, `Slope Soaring Simulator wind field`, `open source RC flight simulator browser github`, `RC simulator camera autozoom`, and developer/RC community discussions. Search popularity and repository star counts were not used as quality proxies.

## Flight physics: several useful levels of approximation

### A small airplane does not require solving the airflow everywhere

**Finding — documented equations; implementation possibilities.** A force-based model can begin with dynamic pressure and coefficient curves:

```text
qbar = 0.5 * rho * V_air^2
Lift = qbar * S * CL
Drag = qbar * S * CD
Pitching moment = qbar * S * c_ref * Cm
```

Use air-relative speed `V_air` in m/s, density `rho` in kg/m³, area `S` in m², and reference chord `c_ref` in m; forces are N and moments N·m. Coefficients are dimensionless, but their reference area, length, coordinate axes, and moment origin matter. A coefficient is a compact representation of aerodynamic behavior, not a universal constant. NASA explains the lift relationship; JSBSim demonstrates force and moment contributions expressed through functions and tables. [NASA lift equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/lift-equation/), [JSBSim force construction](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/forces-and-moments/).

**How it could help:** the following menu separates questions that are easy to conflate. We could compare small implementations without committing to one progression:

| Approach | What it could teach us | What it would leave unresolved |
| --- | --- | --- |
| Directly controlled position/orientation | Whether the airplane, camera, field, and controls are understandable | Physical flight behavior |
| One rigid body with simple lift, drag, thrust, and control moments | Basic launch, turns, glide, and landing interaction | Reliable stall, stability derivatives, detailed propulsion |
| Whole-aircraft coefficient tables/functions | How measured or estimated aircraft data changes handling | Data coverage outside the measured envelope |
| Several aerodynamic surfaces or strips | Effects of wing/tail placement and local airflow | Induced flow, separation, and interference still need models |
| A dedicated flight dynamics library | Whether mature dynamics/instrumentation reduces project work | Integration, aircraft authoring, and data quality |

The table is research synthesis, not a claim that increasing geometric detail automatically improves accuracy. A finely subdivided wing with unsuitable coefficients can still produce unsuitable forces.

### JSBSim is a physics component, with aircraft data remaining a separate problem

**Finding — documented capability.** JSBSim supplies nonlinear six-degree-of-freedom dynamics in C++, configurable aerodynamics, controls, propulsion, and landing gear through XML, plus headless execution and Python bindings. Its repository identifies the core library as LGPL 2.1 and distinguishes licenses of some integration examples. The bundled named aircraft are described as approximations for education/entertainment. [Project repository and licensing notes](https://github.com/JSBSim-Team/jsbsim).

Its coefficient-building interface supports wind or body force axes, additive contributions, lookup tables, and control-dependent terms. The manual includes a lift table with a stall hysteresis variable; this documents an authoring mechanism, not an automatically correct stall model for every aircraft. [Aerodynamic functions and table example](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/forces-and-moments/).

**How it could help:** a headless RC-sized aircraft experiment could investigate trim, control response, and parameter tuning before committing to any rendering engine. Its costs include learning aircraft definitions and checking units/axes at the integration boundary. Existing full-size aircraft definitions would not establish RC-scale fidelity.

**Important scoped limitation:** current `FGElectric` documentation states that throttle scales configured shaft power linearly, with no battery energy consumption or internal friction. The inspected implementation computes that power and returns zero fuel consumption. This is a finding about this built-in class, not a claim that JSBSim cannot host an additional electrical system. [Class documentation in source](https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGElectric.h), [implementation](https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/propulsion/FGElectric.cpp).

### A game/robotics rigid body can receive simple aerodynamic forces

**Finding — documented capability.** Gazebo's `LiftDrag` system exposes surface area, air density, force application position, surface axes, lift/drag slopes before and after a stall angle, and optional control-surface input. This provides a concrete example of attaching a small aerodynamic model to an ordinary physical body. It does not establish RC handling accuracy. [Gazebo Sim 8 LiftDrag API](https://gazebosim.org/api/sim/8/classgz_1_1sim_1_1systems_1_1LiftDrag.html).

**How it could help:** the same idea could be explored in a lightweight custom implementation or another engine: apply forces at wing/tail locations and let the rigid-body solver integrate motion. Research questions include whether pitch/roll damping emerges adequately, whether collisions remain stable, and what happens at zero airspeed or extreme attitudes. The historical Gazebo tutorial explicitly illustrates its two-line lift-curve approximation, which is useful educational material but not a recommendation to adopt the retired Gazebo Classic stack. [Historical aerodynamics tutorial](https://classic.gazebosim.org/tutorials?tut=aerodynamics).

## RC-scale aerodynamics and model authoring

### Reynolds number matters when borrowing aircraft data

**Finding — established relationship and measured-data lead.** Reynolds number is `Re = rho * V * c / mu = V * c / nu`, where `c` is characteristic chord, `mu` dynamic viscosity, and `nu` kinematic viscosity. Matching shape alone does not reproduce the balance between inertial and viscous effects. [NASA similarity parameters](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/similarity-parameters/).

For an illustrative `c = 0.20 m`, `V = 10 m/s`, and assumed `nu = 1.5e-5 m²/s`, `Re ≈ 133,000`; these are example inputs, not a project aircraft specification. UIUC's original low-speed test-program description targeted roughly 40,000–500,000. [UIUC test-program manifesto](https://m-selig.ae.illinois.edu/pd/manifest.html).

**How it could help:** select or generate coefficient data at relevant Reynolds numbers rather than scaling a full-size airplane's visual mesh and mass. Changing speed, chord, or atmospheric conditions may change the coefficients as well as the `V²` multiplier. This also suggests recording the airfoil test conditions alongside any future aircraft parameters.

### UIUC provides experimental airfoil polars, with explicit terms for those datasets

**Finding — measured data; inspected dataset-specific terms.** UIUC provides downloadable low-speed airfoil performance data across several published volumes, including corrected replacements for older reductions. Its performance-data page labels these data “GPL'd Data” and specifies attribution, retention of redistribution freedoms, and inclusion of the license, copyright notice, and manifesto in data distributions. These statements concern the airfoil performance data on that page; they do **not** establish identical terms for airfoil coordinate files or propeller measurements. [UIUC performance datasets and terms](https://m-selig.ae.illinois.edu/pd.html).

**How it could help:** experimental polars can anchor a simple lift/drag curve or check a generated polar without requiring project-owned measurement hardware. Preserve airfoil identity, Reynolds number, test configuration, source volume, and corrections. Before bundling data, inspect the exact files and applicable notices rather than treating public availability as a generic permissive license.

### XFOIL is useful before runtime, within its documented envelope

**Finding — documented methods and limitations.** XFOIL analyzes isolated subsonic airfoils with viscous/inviscid interaction, transition modeling, separation bubbles, limited trailing-edge separation, and polar generation. Its primer warns that accuracy degrades near/past stall and that strong separation bubbles need adequate panel resolution. These are author-documented limitations. [Drela/Youngren XFOIL primer](https://web.mit.edu/drela/Public/web/xfoil/xfoil_doc.txt).

**How it could help:** generate candidate coefficient tables offline, vary Reynolds number and transition assumptions, and compare with UIUC measurements. A runtime table avoids requiring a convergent iterative airfoil solve each frame. An airfoil section polar is not a complete finite-wing model, and extrapolating it to inverted, tumbling, or deep-stall flight needs an explicit separate approximation. Nonconvergence should remain visible in exported research data instead of silently becoming a credible-looking curve.

### AVL, XFLR5, and flow5 are aircraft-authoring leads

**Finding — documented capability and current project status.** AVL supports whole-configuration forces/moments, control and rotational derivatives, trim, and eigenmode analysis. Its author describes the appropriate regime as predominantly thin lifting surfaces at small angles of attack/sideslip with quasi-steady flow. These assumptions limit using it as a source for aggressive low-speed aerobatics. [AVL user primer](https://web.mit.edu/drela/Public/web/avl/avl_doc.txt).

The official XFLR5 page describes XFOIL plus lifting-line, vortex-lattice, and panel methods for low-Reynolds-number model-aircraft work. It now says XFLR5 closed on **June 30, 2026**, with no further updates, and that its successor flow5 became open source on **January 1, 2026**. The page identifies XFLR5 as GPL; this visit did not establish flow5's exact current license. [Official XFLR5 page](https://www.flow5.tech/xflr5/xflr5.html).

**How it could help:** generate an initial stability model or compare design changes before building an aircraft editor. Follow the current flow5 project rather than assuming older XFLR5 advice describes current maintenance. The project's separate limitations presentation is a useful checklist for interpreting potential-flow results. [XFLR5 limitations](https://flow5.tech/xflr5/docs/Part%20IV:%20Limitations.pdf).

### NeuralFoil offers an AI-related lead with a specific kind of evidence

**Finding — documented tool; author-reported benchmarks.** NeuralFoil exposes vectorized airfoil analysis through Python/NumPy, multiple model sizes, `CL`, `CD`, `CM`, and an `analysis_confidence` output. Its headline comparisons largely measure agreement with XFOIL. The repository describes extra post-stall and control-deflection handling through AeroSandbox. The inspected license is MIT. [Repository, outputs, and benchmark discussion](https://github.com/peterdsharpe/NeuralFoil), [license](https://github.com/peterdsharpe/NeuralFoil/blob/master/LICENSE.txt).

**How it could help:** rapidly explore many airfoils or generate candidate tables, using confidence to flag suspicious regions for review. Agreement with XFOIL is not independent validation against flight or wind-tunnel measurements; a confidence score is not a guarantee of correct stalled-wing behavior. The paper and training details are promising follow-up reading before treating this as a physics dependency. [Authors' paper](https://arxiv.org/abs/2503.16323).

## Electric propulsion: distinguish the components and their evidence

### UIUC propeller measurements provide a practical starting dataset

**Finding — measured data.** UIUC's propeller database covers small-UAV/model-aircraft propellers, with static and wind-tunnel measurements organized into volumes. The main page links independent UIUC/Ohio State comparison plots and explains the measurement arrangements; this is stronger evidence than an unexplained thrust calculator. [Database and experimental comparison](https://m-selig.ae.illinois.edu/props/propDB.html).

Volume 4 covers 17 two-blade APC Thin Electric propellers from 12–21 inches. It records tests over advance ratio at particular RPMs and static RPM sweeps. Its notes explicitly use **true measured diameter**, which can differ from nominal diameter, and derive power from measured torque and rotational speed. [Volume 4 data and conventions](https://m-selig.ae.illinois.edu/props/volume-4/propDB-volume-4.html).

**How it could help:** interpolate thrust and shaft power for a specific propeller instead of inventing a universal throttle-to-thrust constant. Preserve RPM dependence as well as advance ratio. The database main page and inspected volume pages did not establish a clear standard redistribution license for propeller data; the airfoil-data terms above should not be copied across by assumption.

Useful standard relations, with `n` in **revolutions/second**, diameter `D` in m, axial inflow speed `V` in m/s, and air density `rho` in kg/m³:

```text
J = V / (n * D)             advance ratio
T = CT * rho * n^2 * D^4    thrust, N
P = CP * rho * n^3 * D^5    shaft power, W
Q = P / (2*pi*n)           shaft torque, N*m
eta_prop = J * CT / CP     propulsive efficiency in forward operation
```

UIUC publishes its coefficient definitions with the database. **Implementation inference:** handle `n → 0` explicitly; do not divide by zero to obtain advance ratio or torque. Static thrust at `V = 0` can be substantial while `T*V/P` is zero, so this particular efficiency measure is not a hovering/static-thrust score. [UIUC definitions](https://m-selig.ae.illinois.edu/props/propDB.html).

### APC offers a larger complementary source, but its performance files are computed

**Finding — manufacturer-documented predictions.** APC says its performance files come from proprietary analysis using actual propeller geometry and a vortex-based method. File headers include a software version and simulation date; APC separately points readers to UIUC for wind-tunnel experiments. [APC performance-data explanation](https://www.apcprop.com/technical-information/performance-data/).

**How it could help:** explore many propellers, inspect consistent speed/RPM trends, and compare a propeller present in both collections. Agreement would be a useful check, not evidence that all computed entries are measurements. APC also provides downloadable technical and geometry resources that could support blade-element research. Downloadability alone does not establish redistribution terms; record file versions and inspect terms before bundling. [APC downloads](https://www.apcprop.com/technical-information/file-downloads/).

### QPROP/QMIL connect propeller aerodynamics to motor behavior

**Finding — documented analytical tool.** MIT's QPROP evaluates propeller–motor and windmill–generator combinations; QMIL designs propellers/windmills. The project distributes Fortran source under GPL, with tabular outputs and batch sweeps suited to external plotting. [Author's project and release conditions](https://web.mit.edu/drela/Public/web/qprop/).

Its theory combines blade elements with induced-flow/vortex treatment, including radial variation and a coupled nonlinear solve. A blade-element model needs geometry and section aerodynamics; subdividing a propeller is not a substitute for those inputs. [QPROP aerodynamic formulation](https://web.mit.edu/drela/Public/web/qprop/qprop_theory.pdf).

**How it could help:** generate offline motor/propeller performance maps, compare against experimental data, or study an alternative to direct lookup tables. The guide documents sweeps over speed, RPM, and voltage, and a simple motor input using resistance, no-load current, and `Kv`. It permits folding wiring/battery/ESC resistance into the effective series resistance, while explaining that the resulting efficiency then includes those losses. That simplification does not resolve switching behavior. [QPROP user guide](https://web.mit.edu/drela/Public/web/qprop/qprop_doc.txt).

### A compact motor model can already teach useful things

**Finding — published equivalent-circuit model.** Drela's first-order model relates back EMF, resistance, current, torque, and shaft power. Rewritten in a common SI convention:

```text
V_motor = Ke * omega + I * R
Q_motor = Kt * (I - I0)
P_shaft = Q_motor * omega
```

Here `omega` is rad/s, `I` and `I0` are A, `R` is ohms, `Ke` is V·s/rad, and `Kt` is N·m/A. For compatible ideal SI conventions, `Kt = Ke`; if `Kv` is quoted in rpm/V, `Ke = 60 / (2*pi*Kv)`. Drela uses reciprocal torque/speed constants, so notation must be converted deliberately. [First-order motor theory](https://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf).

**How it could help:** model why RPM changes with load and voltage, why current rises under greater propeller load, and where heat losses appear. This is an averaged equivalent model, not a full three-phase brushless controller simulation. The follow-on model introduces speed-dependent losses, resistance variation, and torque lag, offering optional extensions rather than a reason to start complex. [Second-order motor theory](https://web.mit.edu/drela/Public/web/qprop/motor2_theory.pdf).

### The ESC is more than a throttle multiplier

**Finding — manufacturer-documented behavior.** A concrete airplane ESC, Hobbywing Skywalker V2, documents brake options, throttle calibration, startup modes, soft/hard low-voltage cutoff, and signal-loss behavior. These settings change what zero throttle or a depleted battery means. They are product-specific capabilities, not guarantees for all ESCs. [Manufacturer manual, revision 2025-08-14](https://www.hobbywing.com/en/uploads/file/20250930/64b726be7a56c9f415385f77683cdc46.pdf).

**How it could help:** later experiments could compare a free-spinning versus braked propeller, response delay, or reduced-power behavior. A first simulator could deliberately approximate these without recreating firmware. Open BLHeli documentation/source is an additional lead for understanding sensorless control and motor damping; its helicopter/multirotor origins should remain visible when borrowing assumptions for fixed-wing use. [BLHeli SiLabs project documentation](https://github.com/bitdump/BLHeli/blob/master/SiLabs/README.md).

### Battery detail can also grow in small steps

**Finding — documented reference implementation; proposed simplification.** PyBaMM's Thevenin implementation combines an open-circuit-voltage source, series resistance, configurable RC elements, and thermal modeling. This is a useful reference for model structure, not proof that its default parameters represent an RC LiPo pack. [PyBaMM Thevenin source](https://raw.githubusercontent.com/pybamm-team/PyBaMM/main/src/pybamm/models/full_battery_models/equivalent_circuit/thevenin.py).

**How it could help:** an exploratory lightweight model could first use `V_terminal = OCV(SOC) - I_battery * R_pack` and `dSOC/dt = -I_battery / (3600 * capacity_Ah)` with discharge current positive. This proposed approximation exposes voltage sag and finite duration without electrochemical simulation. It needs actual pack parameters to represent a real battery. ESC input current and motor phase/equivalent current should not be assumed identical; electrical power balance matters when coupling them. Temperature, aging, transient recovery, and cell imbalance remain separate research questions.

## Wind, thermals, and inexpensive validation

### Wind is an airflow field, while turbulence and thermals represent different phenomena

**Finding — documented models.** JSBSim's wind component includes steady wind, gusts, turbulence, and up/downburst facilities. Its documentation describes Dryden-spectrum variants with altitude-dependent parameters from MIL-F-8785C. That establishes implementation availability, not accuracy for turbulence behind a particular RC field's trees. [JSBSim wind model](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGWinds.html).

NASA's Allen updraft model provides a separate thermal-soaring lead: it derives statistical updraft size, vertical structure, spacing, and height from measurements at Desert Rock, Nevada, and includes code with a verification case. Its desert-region derivation is a limit on generalization. [NASA report and original PDF](https://ntrs.nasa.gov/citations/20060004052).

**How it could help:** start an experiment with a constant air-velocity vector, then separately investigate gusts, spatial thermals, or terrain effects if those become interesting. A glider or motor-off soaring experiment could add meaningful variety without adding a more complicated propulsion system. Reproducible weather inputs would make handling comparisons easier.

### Verification and real-world validation are different, and both can start cheaply

**Finding — published verification and limited experimental comparison.** NASA's 6-DoF check-case project compares trajectories across independently implemented simulators. It is evidence for checking equations of motion and environment integration, not blanket validation of an aircraft's aerodynamic coefficients. [NASA verification report](https://ntrs.nasa.gov/citations/20150001263).

XFLR5's author also publishes a small model-aircraft comparison using trimmed speed, phugoid period, and Dutch-roll period. For that case, measured/AVL/XFLR5 phugoid periods were 11/10/10.9 seconds. This is a useful example of observable quantities and explicit scope, not universal agreement across aircraft. [Flight-mode measurements and predictions](https://flow5.tech/xflr5/docs/XFLR5_Mode_Measurements.pdf).

**How it could help — proposed experiments:** compare thrust maps with held-out UIUC runs; reproduce a published thermal check case; inspect level-flight force balance and motor-off glide; compare one aircraft's response after changing only CG or a control input. Existing public data can support these experiments before buying hardware. Optional future telemetry or careful video measurements could add evidence, while pilot impressions would answer handling questions without replacing quantitative validation. MIT's motor-measurement note is another follow-up, explicitly for **brushed DC motors**, so it should not be applied unchanged to a brushless system. [Motor-constant measurement note](https://web.mit.edu/drela/Public/web/qprop/motor_measure.pdf).

### Open leads to retain

- Which minimal model produces enjoyable RC handling, and which inaccuracies would users actually notice first?
- What real RC airframe has usable mass, inertia, geometry, propulsion data, and flight-response measurements with clear reuse terms?
- How much is gained by propwash on the tail, torque reaction, asymmetric propeller inflow, and ground effect before attempting spins or hovering aerobatics?
- Which post-stall datasets cover low-Reynolds-number RC wings, inverted flight, and hysteresis well enough to evaluate competing approximations?
- Can runtime lookup tables preserve a clear provenance chain back to measurements versus generated predictions, including the region where interpolation becomes extrapolation?
- What are the exact current flow5 license/build conditions, and the separate redistribution conditions for each prospective airfoil-coordinate and propeller dataset?
- Can propulsion-map experiments expose units or energy-balance mistakes without choosing a rendering engine, programming language, or final aircraft format?

## Engines, platforms, and controls: several viable paths

### Godot: an integrated editor with important differences between export targets

**Documented findings.** Godot's engine is available under the [MIT License](https://godotengine.org/license/). Its official physics introduction describes scene objects with different responsibilities, including simulated rigid bodies and manually controlled character bodies. This provides a useful place to investigate whether aerodynamic forces should be applied to an engine-managed body or whether an independent flight solver should publish poses to the scene. Neither option is selected here. [Godot physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html).

Web export has concrete constraints: the inspected stable manual requires WebAssembly and WebGL 2; only the Compatibility renderer is supported, and Godot 4 C# projects cannot currently export to the web. Single-threaded export is the default. Threads and web-compiled GDExtensions require cross-origin isolation. The default web audio sample mode lacks procedural audio and some effects; stream playback changes the latency tradeoff. [Godot web export manual](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

**How this could help.** An editor can make the first little airplane, ground plane, camera, and later aircraft authoring tangible quickly. The open engine also leaves implementation details inspectable. Browser demonstrations remain a possibility, but choosing C#, a rendering feature, or a native physics extension can affect that possibility independently of choosing Godot.

**Next experiment / limits.** Build the same deliberately small scene as desktop and web exports before assuming parity. Include an airplane silhouette at distance, one loaded asset, controls, and a simple sound; record download size, launch time, and frame pacing. This is an optional comparison experiment, not a requirement to target both platforms initially.

### Three.js: a browser graphics layer with room to assemble our own simulator

**Documented findings.** Three.js uses the [MIT License](https://github.com/mrdoob/three.js/blob/dev/LICENSE). The current renderer guide describes two paths: maintained `WebGLRenderer` for WebGL 2 applications, and an experimental `WebGPURenderer` that can automatically fall back to WebGL 2. That fallback is significant, but does not promise identical feature availability or performance. The new renderer uses node materials/TSL; older custom `ShaderMaterial` and `EffectComposer` integrations do not simply transfer unchanged. [Three.js renderer guide](https://threejs.org/manual/pages/webgpurenderer).

**How this could help.** A browser prototype could combine a minimal scene with familiar HTML controls, plots, and tuning panels. We could explore flight behavior without first adopting an editor's scene and gameplay conventions. This is an architectural possibility, not evidence that a complete simulator comes with the renderer.

**Next experiment / limits.** Use a simple airplane mesh and an explicit update loop, then compare WebGL 2 with WebGPU on actual available machines. Keep the first materials basic enough to make the comparison informative. Separately measure input behavior: renderer fallback cannot repair a browser's inability to expose a particular radio.

### Babylon.js and Babylon Native: browser tooling plus a distinct native route

**Documented findings.** Babylon.js lists WebGL 1/2 and WebGPU, a scene graph, glTF import, cameras, audio, GUI, collisions, and inspector tools. Its core repository carries [Apache License 2.0](https://github.com/BabylonJS/Babylon.js/blob/master/license.md). Its physics feature list includes Havok integration; that is evidence of an integration, not proof that the physics package and every dependency have the core engine's licensing terms. [Babylon.js specifications](https://www.babylonjs.com/specifications/).

Babylon Native aims to reuse Babylon.js JavaScript beyond the browser on Windows, macOS, iOS, Android, and Linux. The inspected repository still describes a **source-only public preview**, incomplete feature coverage, and an API contract that may change. It carries an MIT license, separate from Babylon.js's core license. [Babylon Native repository and status](https://github.com/BabylonJS/BabylonNative).

**How this could help.** Babylon offers a middle ground between assembling a renderer-centric application and adopting a desktop game editor. Native reuse is a promising migration experiment, especially if browser development proves productive.

**Next experiment / limits.** Compare the effort of making a camera, aircraft loader, and tuning interface against Three.js. If native matters later, port that exact small sample and test its input/audio/assets. Do not count the native platform list as proof of drop-in application portability.

### Bevy: Rust, composable systems, and an evolving API

**Documented findings.** Bevy describes a modular, data-oriented engine built in Rust around an Entity Component System. Its repository explicitly warns of missing features, sparse documentation, and frequent breaking API changes, with migration guides rather than a promise of painless upgrades. Most code is dual-licensed under the **MIT License or Apache License, Version 2.0**, with exceptions and separate asset terms noted. [Bevy repository](https://github.com/bevyengine/bevy).

The project lists Windows, macOS, Linux, web, iOS, and Android and describes 3D rendering, glTF loading, UI, and asset hot reload. Those are project capability statements, not our tested compatibility matrix. [Bevy feature overview](https://bevy.org/). Its examples README describes separate WebGL 2 and experimental WebGPU builds: enabling `webgpu` overrides `webgl2`, and that build does not run on browsers lacking WebGPU. This differs materially from Three.js's documented automatic fallback. [Bevy platform examples](https://github.com/bevyengine/bevy/blob/main/examples/README.md).

**How this could help.** Flight forces, environment queries, inputs, and presentation could be explored as distinct systems in a code-oriented project. Rust may be attractive if the team values explicit types and native computation.

**Next experiment / limits.** Measure a contributor's clean build and edit-to-running cycle, and try one small version migration. Generated code should be checked against the pinned engine version: similar-looking examples from another release may not compile. No assumption is made that Rust or ECS is necessary for this project.

### raylib and SDL: a small native program remains a serious research path

**Documented findings.** raylib's C API includes 3D models, cameras, math, audio, and a large example collection. Its repository lists Windows, Linux, macOS, Raspberry Pi, Android, and HTML5 and explicitly favors simplicity, including a single-window default. It describes its license as **zlib/libpng**, with embedded dependencies carrying their own terms. [raylib repository](https://github.com/raysan5/raylib), [license text](https://raw.githubusercontent.com/raysan5/raylib/master/LICENSE).

Its API exposes gamepad availability, axis count, axis values, buttons, and SDL-style mapping strings. That is useful functionality to inspect, but the word “gamepad” does not establish that every nonstandard transmitter reaches those functions correctly. [raylib cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html).

SDL itself supplies low-level access to input, audio, and graphics facilities across platforms and is distributed under the **zlib license**. It is a building block rather than an aircraft simulator. [SDL3 overview](https://wiki.libsdl.org/SDL3/FrontPage), [SDL license](https://raw.githubusercontent.com/libsdl-org/SDL/main/LICENSE.txt).

**How this could help.** A small C/C++ program can literally start with an airplane, a camera, and a loop. It offers a useful contrast to large engines when judging how much infrastructure we actually need.

**Next experiment / limits.** Try a tiny native scene and its web build. Record what we had to supply ourselves: asset reload, UI, packaging, input configuration, and debugging. A short initial program does not establish that the complete development lifecycle stays simpler.

### Unity and Unreal: useful comparators with different openness and input costs

**Documented findings.** Unity 6.0 documentation lists desktop, mobile, and web deployment requirements; its web target includes specific browser/WebAssembly/WebGL requirements. These are version-specific platform requirements. [Unity 6.0 requirements](https://docs.unity3d.com/6000.0/Documentation/Manual/system-requirements.html). Unity Input System 1.14.2 says joystick support is limited to generic HID interpretation and that descriptor-based control identification may be inaccurate; it suggests user remapping and custom layouts. [Unity joystick support](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.14/manual/Joystick.html).

Unity's editor/runtime are governed by proprietary software terms, including tier eligibility and distribution conditions. An open-source game repository would not turn Unity itself into an open-source dependency. [Unity software terms](https://unity.com/legal/editor-terms-of-service/software).

Unreal's RawInput plugin addresses devices poorly handled by XInput, with configurable device axes/buttons. Its plugin index identifies it specifically as **Windows RawInput**. Treat it as a Windows integration lead, not cross-platform transmitter support. [RawInput documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/rawinput-plugin-in-unreal-engine), [plugin index](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/PluginIndex/RawInput). Unreal source access remains under Epic's EULA, which restricts engine-code distribution and combinations with certain licenses, explicitly including GPL. Source access is not equivalent to a permissive open-source engine license. [Unreal EULA](https://www.unrealengine.com/eula/unreal).

**How this could help.** Both remain useful research comparators for authoring workflows, visualization, and the amount of custom simulator code needed. Their engine terms and contributor setup deserve their own evaluation alongside technical capabilities.

**Next experiment / limits.** If either becomes promising, inspect the specific version, selected plugins, and compatible licensing combinations before reusing simulator code. No platform, vendor, or engine is ruled in or out by this survey alone.

## RC input is an end-to-end pipeline

### A radio's channel output is not necessarily a raw stick position

**Documented findings.** EdgeTX Classic USB joystick mode sends configured output channels. Its manual maps channels 1–8 to axes and 9–32 to buttons; Advanced mode can choose joystick, gamepad, or multiaxis identity and assign axis/button/simulation usages. The manual also describes an optional circular cutout for paired axes. [EdgeTX USB joystick](https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick).

The versioned v2.11 developer guide documents a classic report with **8 analog axes, 24 digital buttons, and 11-bit analog resolution**, with configurable radio-side deadbands, mixing, and nonlinear scaling. It provides concrete evdev, Linux joystick, DirectInput, Raw Input, and Windows.Gaming.Input mappings. Notably, its Windows Multimedia table marks CH5 and CH8 unavailable. [EdgeTX developer mappings](https://manual.edgetx.org/v2.11/edgetx-how-to/joystick-mapping-information-for-game-developers).

**How this could help.** An input monitor could distinguish device discovery from usable channel delivery. A simulator-side “aileron” command may already include radio expo, rates, trim, or mixing. Applying those again could change the intended response. This is a design implication from the documented processing path.

**Next experiment / limits.** Compare a clean simulator model on the radio with an existing aircraft model; log each delivered axis while moving one control at a time. Record firmware version and USB mode with results. These guides describe versions/configurations, not every transmitter ever running EdgeTX.

### Legacy OpenTX documentation is useful, but version details matter

**Documented findings.** OpenTX's 2.2 manual describes Taranis/Horus USB joystick emulation with 8 analog axes and 24 buttons. Its technical section describes an **8-bit** analog representation, clipping channel outputs outside ±100%, and warns that Linux `jscal` can introduce an unwanted center deadband. The same page contains an old CRRCsim/Linux setup example. [OpenTX 2.2 joystick manual](https://doc.open-tx.org/manual-for-opentx-2-2/advanced-features/radio_joystick).

**How this could help.** Older radios may offer a convenient entry point, and the deadband warning explains why fine control can feel wrong even when a device is detected.

**Next experiment / limits.** Do not generalize that old 8-bit description to current EdgeTX or every OpenTX build. Measure actual steps, endpoints, jitter, and clipping on borrowed hardware. The historical CRRCsim installation commands are background evidence, not current setup instructions.

### SDL's joystick and gamepad APIs answer different questions

**Documented findings.** SDL3's joystick API exposes arbitrary axes, buttons, and hats. The gamepad API adds standardized physical meanings through mapping strings. SDL explicitly says the lower-level interface is useful when an application supplies its own configuration UI. [SDL gamepad overview](https://wiki.libsdl.org/SDL3/CategoryGamepad).

SDL joystick instance IDs change after unplug/replug; GUIDs describe device classes and are platform-dependent. SDL also supports virtual joysticks, including recording/playback uses. [SDL joystick overview](https://wiki.libsdl.org/SDL3/CategoryJoystick).

**How this could help.** General gamepads could use familiar mappings while unusual RC radios retain a channel-oriented route. A virtual-device or recorded-channel test could reproduce a reported input sequence without requiring every contributor to own that transmitter.

**Next experiment / limits.** Compare raw joystick and mapped gamepad readings on the same device, including channels beyond the four main controls. Reconnect it and attach a second similar device. Avoid treating device index zero or a GUID as a permanent identifier for one physical radio.

### Engine controller support is not a substitute for RC calibration

**Documented findings.** Godot 4.6 documentation states that desktop controller support moved to SDL3 in 4.5, while Android, iOS, and web still use a different implementation. Specialized peripherals receive less testing. It also documents a default action deadzone of 0.5 and a circular deadzone for `Input.get_vector()`. [Godot 4.6 controller guide](https://docs.godotengine.org/en/4.6/tutorials/inputs/controllers_gamepads_joysticks.html).

QGroundControl is an adjacent project with a concrete calibration workflow: choose the active device, move sticks through guided steps, then inspect an axis/button monitor. Its advanced options distinguish throttle semantics and configurable deadbands. The guide explicitly warns that incorrect mappings can prevent calibration. [QGroundControl joystick setup](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/setup_view/joystick.html).

**How this could help.** We could borrow the interaction idea without adopting the autopilot software. An RC pilot may need independent full aileron and elevator simultaneously; a gamepad-style circular magnitude limit could unintentionally couple them. This is a hypothesis worth testing, not a claim that a particular engine forces that policy.

**Next experiment / limits.** A small calibration prototype could compare endpoint/center capture, channel assignment, inversion, deadband, and separate throttle treatment. Show both received values and final aircraft commands so invisible processing becomes visible.

### Browser Gamepad API: convenient access with discovery and mapping caveats

**Documented findings.** The W3C specification exposes arrays of axes normalized to `[-1, 1]`, button values in `[0, 1]`, a mapping identifier, connection status, and timestamps. An empty mapping string does not mean the standard gamepad layout. Device exposure is gated on an observed gamepad gesture; the specification distinguishes self-centering axes from controls lacking a neutral default. [Gamepad specification](https://www.w3.org/TR/gamepad/).

**How this could help.** A tiny web diagnostic can explore browser viability before building a flight scene. Record every axis and button rather than guessing which four correspond to flight controls. A noncentering throttle may be a poor sole “wake up the controller” instruction; that is an inference from the gesture rules.

**Next experiment / limits.** Test current Firefox, Chromium-based browsers, and Safari on hardware actually available. Check initial detection, missing channels, reconnect, background tabs, and whether a centered-stick movement or momentary button makes the device visible. API specification compliance is not a radio compatibility certificate.

### WebHID: an optional escape hatch with narrower practical reach

**Documented findings.** Chrome's first-party WebHID article describes user-selected access to individual HID devices, report descriptors, input reports, and filtering by vendor/product/usage. It exists partly for unusual controllers whose behavior is poorly handled by generic browser paths. The article documents protected usages and possible Linux `hidraw` permission setup. Its browser-support display shows that this is not a universally available browser feature. [Chrome WebHID documentation](https://developer.chrome.com/docs/capabilities/hid).

**How this could help.** A device-specific adapter might recover useful radio reports when Gamepad mapping loses information. Raw descriptors could also improve diagnostics.

**Next experiment / limits.** Try capability detection and one known radio before considering a larger adapter system. Compare Gamepad and HID readings. Permission prompts, browser support, operating-system access, and report parsing create real implementation work; WebHID is a possibility, not a universal compatibility solution.

### Firmware configuration and middleware can change the same hardware's behavior

**Documented findings.** EdgeTX's Advanced-mode guide recommends reconnecting after descriptor changes; it describes different axis-order interpretations, Linux collisions between certain axis/simulation usages, and Android half-axis treatment. Advanced mode is unavailable on some monochrome radios with less than 1 MB flash. [EdgeTX Advanced configuration](https://manual.edgetx.org/edgetx-how-to/configure-advanced-joystick-with-edgetx).

**Firsthand report, not independently reproduced.** A Steam Deck user running Seligsim through Proton reported that `evtest` showed eight updating axes while SteamOS/Seligsim delivered only five usable axes. Their post includes the device identity, event names, and ranges, and discusses suspected controller translation. It does not establish a universal Steam Deck failure or a verified root cause. [Steam Deck/Seligsim report](https://www.reddit.com/r/SteamDeck/comments/1rytlgk/using_edgetx_rc_transmitter_with_seligsim_axis/).

**How this could help.** The report illustrates why “detected,” “all channels delivered,” and “correct aircraft response” are separate milestones. Useful community bug reports can contain diagnostic evidence that a simple compatibility list misses.

**Next experiment / limits.** Compare native execution, Proton/Wine where relevant, and Steam input enabled/disabled while holding the radio model constant. Capture observations at the OS, framework, and simulator levels before assigning the fault to a renderer or firmware.

### Follow-up questions for platform and input research

- **The pilot's view:** compare a fixed ground camera, tracking camera, chase view, and cockpit view using the same little airplane. Which teaches RC orientation and makes a distant airplane readable? This is a research question, not a commitment to all camera modes.
- **Latency rather than only frame rate:** measure stick motion to visible response with a repeatable input signal or camera recording. Separate radio sampling, OS delivery, input polling, simulation stepping, and presentation. No latency measurements were collected in this research.
- **Compatibility matrix:** record exact device, firmware, radio model/mixes, USB mode, OS, input API, engine/browser version, and usable channel count. Include an ordinary gamepad and at least one RC transmitter when hardware becomes available. A matrix can grow only as evidence arrives.
- **Community follow-up:** EdgeTX's documentation and discussions, engine issue trackers, QGroundControl's controller work, and Linux gaming/Steam Deck reports are valuable places to follow reproducible cases. Search by USB VID/PID and HID axis names as well as product name; that can uncover the same technical issue under different branding.
- **Unresolved:** no prototype was compiled, no device connected, no mobile USB adapter tested, no package-size/performance ranking measured, and no game-engine licensing combination approved. Those gaps are opportunities for focused experiments if and when they help the next small step.

## Simulation timing, reproducibility, and useful observations

### Fixed simulation steps and rendering can evolve separately

**Documented technique.** Glenn Fiedler's original *Fix Your Timestep!* article explains why passing an arbitrary rendering frame interval directly into a physics integrator can change behavior. An accumulator lets simulation advance in equal steps while rendering interpolates between completed states. It also identifies a failure mode: trying to recover from a slow frame with too much simulation work creates an ever-growing backlog. [Original article](https://gafferongames.com/post/fix_your_timestep/)

**How this could help.** A tiny airplane demo could expose simulation time separately from wall-clock/render time. Later we could replay exactly timed control inputs, change rendering quality, or run physics without drawing. An experiment could replay a short maneuver at several rendering rates and compare state histories, then vary the physics step to measure convergence. No particular simulation frequency or integrator is selected here.

**Limit.** Fixed steps do not by themselves guarantee identical results across operating systems, processors, compilers, or engine releases. Fiedler's separate engineering article describes those floating-point reproducibility difficulties. Treat bit-identical cross-platform replay as an additional question; tolerance-based comparisons may be sufficient for many experiments. [Floating Point Determinism](https://gafferongames.com/post/floating_point_determinism/)

### A replay can be a research instrument

**Inference from the timing sources above.** A saved initial state plus timestamped controls, aircraft parameters, wind settings, and random seed could turn a pilot's observation into something another contributor can investigate. A useful first trace might contain position, orientation, airspeed, angular rates, input commands, and applied forces. Full telemetry infrastructure is unnecessary to test the idea: a small CSV or JSON file would suffice.

**How this could help.** Separate three questions that screenshots alone cannot answer: did the input arrive correctly, did the physics respond correctly, and did the camera make that response understandable? A replay that reproduces a bug is valuable even if it is only reproducible in one build. This is an optional debugging direction, not a requirement for the first visible airplane.

## Assets, environments, and sensory feedback

### glTF is a candidate interchange format, not an aircraft physics format

**Documented.** The glTF 2.0 specification defines a scene/node hierarchy, meshes, materials, animation, and transforms. Its coordinate conventions include a right-handed system, +Y up, distances in meters, and angles in radians; quaternion components are XYZW. [glTF specification, coordinate system and units](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#coordinate-system-and-units)

**How this could help.** A small reusable aircraft asset could contain named nodes for wings, elevator, rudder, ailerons, and propeller. The visual could then move between experiments in different renderers. The aircraft's aerodynamic coefficients, mass distribution, center of gravity, and control limits would still need their own representation or explicitly defined metadata. That separation is a possibility for preserving work while changing technologies.

**Experiment / limits.** Export one simple aircraft and check scale, handedness, orientation, material appearance, and hinge pivots in two candidate viewers. A successful mesh import does not establish aerodynamic dimensions or equivalent material rendering. Engine-specific extensions could reduce interchangeability.

### Khronos sample assets can help diagnose rendering before aircraft art

**Documented.** Khronos maintains sample assets grouped by purpose, including core-only assets and rendering tests. Models have individual license and credit information; the repository instructs readers to inspect each model's README. GLB packages resources into one binary container, while ordinary glTF can use separate mesh and texture files. [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)

**How this could help.** If the airplane looks wrong after an engine change, a known sample model can help distinguish an importer/material problem from an aircraft-authoring problem. Core-only examples offer a small common denominator for comparisons. These are diagnostic resources, not a proposed aircraft collection.

### Blender can support a repeatable asset experiment

**Documented example.** Khronos supplies a Blender conversion example using Python and background execution. It is explicitly a template for task automation rather than a complete explanation of every conversion option. [Blender glTF converter example](https://github.com/KhronosGroup/glTF-Tutorials/blob/main/BlenderGltfConverter/README.md)

**How this could help.** A script could generate a plain airplane from primitive shapes, name control surfaces, and export it repeatedly as we explore engines. This would also give AI coding tools a text-based way to propose geometric changes. **Unverified:** the example has not been run against a chosen Blender release; APIs and export options need checking at that point. Some Blender manual pages were inaccessible through the research browser, so this finding rests on the inspected Khronos example, not a tested asset pipeline.

### A simple field and a photographic environment answer different questions

**Documented resource.** Poly Haven identifies its HDRIs, textures, and 3D models as CC0 assets, with reuse and redistribution permitted under its stated asset terms. This statement concerns the assets, not every part of the website or its services. [Poly Haven asset license](https://polyhaven.com/license)

**How this could help / inference.** A grass texture or sky environment could add orientation cues cheaply after the first scene works. A deliberately plain runway and horizon may make early camera, scale, and landing experiments easier to interpret. A panoramic image can provide appearance but does not automatically supply terrain geometry, collision surfaces, or local airflow. Compare these visual approaches before investing in scenery complexity.

### Motor sound could provide feedback before visual realism

**Documented building block.** The Web Audio specification includes oscillators with controllable frequency and custom periodic waveforms, plus gain and spatial-audio building blocks. These are browser audio mechanisms, not a ready-made electric-aircraft sound model. [Web Audio 1.0 specification](https://www.w3.org/TR/webaudio-1.0/#OscillatorNode)

**How this could help / experiment.** Try a simple RPM-linked tone or loop alongside a silent version and observe whether pilots can judge throttle changes more easily. Pitch, loudness, and distance attenuation could be adjusted independently of the propulsion calculation. A tone following throttle alone is an interface cue; it does not prove that simulated motor RPM or propeller acoustics are accurate. Equivalent native-engine approaches remain open.

## Adjacent robotics and autopilot ecosystems

### ArduPilot offers an optional connection to software-in-the-loop research

**Documented.** ArduPilot SITL runs autopilot code on a computer without flight-controller hardware. Simulated sensor data comes from built-in or external vehicle dynamics. Its JSON interface uses UDP and has Python, MATLAB/Simulink, and C++ examples for connecting a physics backend. [SITL overview](https://ardupilot.org/dev/docs/sitl-simulator-software-in-the-loop.html), [JSON interface](https://ardupilot.org/dev/docs/sitl-with-JSON.html)

**How this could help.** If later interests include stabilization, assisted flight, or comparing manual and autopilot control, this provides an existing integration surface to investigate. It also illustrates how control software and vehicle dynamics can communicate without sharing a renderer.

**Limits.** This is not a ready-made RC training interface, and connecting an autopilot would add timing, coordinate, sensor, and configuration work. A successful connection would establish protocol interoperability, not that our aircraft behaves like a real one. It is a possible later branch of research, not part of the first demo.

### Gazebo and PX4 expose both aerodynamic building blocks and their uncertainties

**Documented.** Gazebo's `LiftDrag` system computes aerodynamic forces. PX4 documents an automation tool that calls MIT AVL from wing inputs and produces parameters for its Advanced Lift Drag plugin/model format. The same PX4 page explicitly warns that its parameter assignments have not been verified by an expert. That warning is part of the evidence, even though the page is official. [Gazebo Sim 9 LiftDrag API](https://gazebosim.org/api/sim/9/classgz_1_1sim_1_1systems_1_1LiftDrag.html), [PX4 AVL automation](https://docs.px4.io/main/en/sim_gazebo_gz/tools_avl_automation)

**How this could help.** Study a concrete pipeline from aircraft geometry to simulator coefficient tables. It could inform an aircraft-authoring experiment even if Gazebo is never our renderer. Generated coefficients would still need sign, unit, convention, and flight-regime checks.

**Community report.** A January 2026 PX4 forum post asks how the `rc_cessna` and `advanced_plane` examples relate to physical geometry and whether a known input/output pair exists for the automation tool. The inspected thread contains questions, not a verified resolution. It suggests that transparent model provenance and worked examples may be useful to contributors. [Original fixed-wing modeling discussion](https://discuss.px4.io/t/questions-about-creating-custom-fixed-wing-gazebo-models/48260)

### A documented integration may have a weaker support status than its components

**Documented caveat.** PX4's JSBSim integration page labels the integration community-maintained and says it may not work with current PX4 versions; its setup instructions mention testing on Ubuntu 18.04. This caveat concerns that bridge, not JSBSim's overall status. [PX4 JSBSim integration](https://docs.px4.io/main/en/sim_jsbsim/index)

**How this could help.** When evaluating an engine plus dynamics library plus input adapter, record each connection separately. A mature component does not establish that a particular combination builds today. An optional future experiment would pin versions and demonstrate one command/control/state round trip before investing in deeper integration.

### AirSim is useful historical architecture, with an explicit maintenance boundary

**Documented.** Microsoft Research says the original AirSim research project is archived and will receive no further updates, while its code remains available. The project illustrates game-engine rendering combined with sensors, vehicle control, and synthetic-data collection. [Microsoft Research project page](https://www.microsoft.com/en-us/research/project/aerial-informatics-robotics-platform/), [original AirSim repository](https://github.com/microsoft/AirSim)

**How this could help.** Read it for architectural ideas about observations and external control if those become relevant. Its existence does not establish a suitable fixed-wing RC model, a current build on our platforms, or maintenance of a specific fork. Successor projects and forks would require their own source and license review.

## AI-assisted development as an experiment we can observe

### Productivity evidence is contextual and changes over time

**Measured evidence.** METR's July 2025 randomized study involved 16 experienced open-source developers and 246 tasks in repositories they knew well. Allowing the AI tools used in that setting increased completion time by 19%. The authors explicitly caution against generalizing the result to all developers or future tools. [Original study report](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)

**Later evidence and uncertainty.** In February 2026, METR reported that its follow-up had substantial selection and measurement problems, including developers avoiding tasks without AI and difficulty measuring concurrent agent work. The researchers considered greater acceleration plausible but described the new data as weak evidence for its magnitude. Reporting the 2025 slowdown as a timeless result, or the follow-up as a clean proof of a particular speedup, would both misrepresent these sources. [Follow-up and experiment redesign](https://metr.org/blog/2026-02-24-uplift-update/)

**How this could help / experiment.** For our small prototypes, record time to a working visible result, review and repair effort, and whether another contributor can reproduce it. AI may help most with some tasks and least with others; engine familiarity, documentation quality, and tool feedback are testable factors. This research does not select a model, provider, or development workflow.

### Software benchmarks do not establish visual or flight-model correctness

**Research evidence.** The 2024 SWE-bench Multimodal paper expanded evaluation to 617 tasks across 17 JavaScript libraries with visual material, and reported difficulties transferring performance from the original text-heavy benchmark. Its numerical model rankings are historical; its relevant contribution here is the difference between task domains. [Authors' paper](https://arxiv.org/abs/2410.03859)

**How this could help / inference.** Evaluate an AI-built airplane through several observations: does it appear, do controls move the intended surfaces, do numerical trajectories behave sensibly, and can a pilot follow its orientation? Passing generated tests alone cannot answer all four. An aircraft can look plausible while using a wrong force direction or unit conversion.

### Command-line access and visible feedback give agents something concrete to check

**Documented capabilities.** Godot documents command-line project startup, script parsing, headless execution, asset import, export, and movie/image capture. Some commands depend on editor builds or export templates; unknown arguments can be silently ignored. Playwright documents screenshot comparison for browser applications and warns that rendering differences across browsers and platforms affect baselines. [Godot command-line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots)

**How this could help.** These are examples of feedback paths to compare across technologies: a reproducible launch command, actual compiler/parser output, a saved image of the airplane, and a short control trace. Headless execution can help inspect numerical behavior; a rendered run is still needed to assess the view. Screenshot comparisons can reveal a missing aircraft or broken interface, but are not an aerodynamic validation method. We have not implemented either workflow.

### Existing projects distinguish generated work from demonstrated work

**Documented practice.** GitHub's Copilot agent documentation acknowledges inaccurate output and incomplete reviews and calls for reviewing and testing generated changes. PX4's own AI contribution policy welcomes assistance while requiring human accountability, disclosure, and truthful statements about tests actually performed. These are the respective projects' practices, not rules adopted for this repository. [GitHub agent application card](https://docs.github.com/en/copilot/responsible-use/agents), [PX4 AI contribution policy](https://docs.px4.io/main/en/contribute/ai_assistants.html)

**How this could help / inference.** Keep research citations, implemented behavior, and executed checks distinguishable. A focused task such as “show the aircraft and produce a screenshot” has observable feedback; “make the physics realistic” needs a specific maneuver, measurement, or comparison before progress can be assessed. Small reviewable changes fit the project's gradual-growth principle. The PX4 page was read by direct HTTP fetch after browser extraction failed.

## Continuing the research

### Small experiments suggested by these findings

These are independent options, not a ranked plan. Any one can be narrowed, changed, or discarded as we learn. They do not all need to precede the first working airplane.

| Question | Small experiment | Useful evidence to retain |
| --- | --- | --- |
| Which development path makes a little airplane easy to change? | Make equivalent plain scenes in two contrasting approaches, such as a browser library and an editor-based engine. | Setup effort, edit/run cycle, screenshot, exact versions, and what felt difficult. |
| Can people understand the aircraft's attitude from the ground? | Replay one flight with a few camera and aircraft-color treatments. | Visibility at distance, lost-orientation moments, display size, pilot comments. |
| What does a connected transmitter actually deliver? | Show raw channels and mapped flight commands in a small diagnostic. | Device/firmware/OS/API combination, endpoints, axis ordering, reconnect behavior. |
| How little physics is already useful? | Compare a simple force model with a coefficient-driven model on the same glide or turn. | Assumptions, force balance, state traces, numerical stability, handling observations. |
| How well does a propulsion approximation fit data? | Compare one propeller's measured UIUC points with a lookup or QPROP/APC prediction. | RPM, airspeed, diameter conventions, residuals, and extrapolated regions. |
| Can an aircraft asset survive a technology change? | Load the same small glTF aircraft in two renderers. | Scale, orientation, materials, control-surface pivots, and conversion steps. |
| Where does AI assistance help this project? | Give a bounded implementation task an observable result and record the work needed to accept it. | Working artifact, executed checks, review/repair effort, and reproducibility. |

### Search trails and communities to revisit

This pass combined general searches with exact API names, source-file names, and queries about failure modes. Useful routes included `open source RC flight simulator browser github`, `CRRCSim source electric propulsion`, `Slope Soaring Simulator wind field`, `RC simulator camera autozoom`, `FGElectric`, `UIUC propeller static advance ratio`, `QPROP motor resistance`, `joystick mapping game developers`, `Gamepad WebHID transmitter`, `fixed wing gazebo model`, and studies of AI-assisted open-source development. Following manuals into code, datasets, and issue discussions produced more useful distinctions than feature lists alone.

The linked PicaSim, RCPlanes, FPV, EdgeTX, PX4, and Steam Deck discussions suggest different sources of experience: model authors, beginner pilots, transmitter developers, simulation researchers, and users navigating compatibility layers. Future searches could include aircraft plans with measured mass/CG, post-stall low-Reynolds-number datasets, control-line and tow-launch simulation, accessibility of ground-view controls, and end-to-end input latency. These are open leads; no community outreach was performed.

### Selected repository snapshots

The following default-branch revisions were recorded through GitHub's API on 2026-10-05. Selected license/build/validation files were also checked at their pinned revisions. These snapshots make the notable documentation differences easier to revisit; they are not build endorsements.

| Repository | Recorded revision | Why preserve it |
| --- | --- | --- |
| PicaSim | [5b2c5871b82a](https://github.com/Rowlhouse/PicaSim/tree/5b2c5871b82aecae4ae6293b862f31600a6a949c) | Current noncommercial license versus older website descriptions. |
| RCForge | [560365528303](https://github.com/adithya-s-k/RCForge/tree/560365528303906b1db96b312e90ffcebbe2da08) | README application version and validation simulation version differ; model limits are explicit. |
| DaScient/RC-Flight-Sim | [86ef3de91269](https://github.com/DaScient/RC-Flight-Sim/tree/86ef3de912697ec4d75c17b5bb6951bb52a652a2) | Quick-start build selects the kinematic fallback. |
| yotamgi/rcsim | [65cbf6a8be93](https://github.com/yotamgi/rcsim/tree/65cbf6a8be93c263e30f63290b84a55b21b69cee) | Concrete raylib/Emscripten build configuration for later inspection. |

### Keeping the notebook useful

As research continues, add findings beside their topic with the date, original source and version where relevant, evidence type, useful details, possible project benefit, and remaining uncertainty. If a claim changes, retain enough context to explain the correction. Experimental results can be added with the exact setup and observations when experiments actually occur; a list of possible tests is not a test result.

**Research log — 2026-10-05:** initial broad survey completed across existing simulators, aerodynamics, electric propulsion, engines, input, portability, assets, communities, validation, and AI-assisted development. No stack, platform, dependency, aircraft specification, or additional project requirement was selected.
