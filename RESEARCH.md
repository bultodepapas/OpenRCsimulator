# RC airplane simulator: exploratory research notebook

Research date: **2026-10-05**. This is a growing collection of evidence, possibilities, and questions, not a stack selection or a requirements document. The only established principles remain those in [AGENTS.md](AGENTS.md). [DECISIONS.md](DECISIONS.md) records decisions when we actually make them.

Latest focused follow-up: [propeller comparison, mass properties, and low-speed evidence](#testing-the-evidence-behind-the-first-aircraft). This pass includes an executed numerical comparison; physical aircraft measurements and the [earlier prototype and pilot experiments](#focused-follow-up-on-the-three-priority-research-gaps) remain open.

**Current aircraft direction — 2026-10-05:** the project owner selected an **Ultra Stick / Ugly Stick-style .60 nitro airplane** as the first model. The exact variant, geometry, engine/propeller combination, mass properties, and aerodynamic parameters remain open. Begin with a simple representation and refine it through research. This supersedes earlier statements that no first-aircraft direction had been selected; those dated entries remain research history. See [DECISIONS.md](DECISIONS.md).

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
- [Ten additional investigations](#ten-additional-investigations)
- [Ten investigations into development and 3D tools](#ten-investigations-into-development-and-3d-tools)
- [Ten investigations into codebase libraries and runtime tools](#ten-investigations-into-codebase-libraries-and-runtime-tools)
- [Ten open-source projects to study for code inspiration](#ten-open-source-projects-to-study-for-code-inspiration)
- [Ten investigations to guide early prototype experiments](#ten-investigations-to-guide-early-prototype-experiments)
- [Focused follow-up on the three priority research gaps](#focused-follow-up-on-the-three-priority-research-gaps)
- [Closing the .60 nitro Stick research gaps](#closing-the-60-nitro-stick-research-gaps)
- [Testing the evidence behind the first aircraft](#testing-the-evidence-behind-the-first-aircraft)
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

## Ten additional investigations

Second research pass: **2026-10-05**. These ten topics examine questions beyond the first survey's main coverage. Some deepen earlier leads; others explore different flying experiences, contribution workflows, or ways to evaluate the simulator. They are research choices, not new requirements or an implementation sequence. All experiments below are proposals; none was run.

- [1. Landing gear, grass, and the first few seconds on the ground](#1-landing-gear-grass-and-the-first-few-seconds-on-the-ground)
- [2. Launch methods as initial conditions, then as physical interactions](#2-launch-methods-as-initial-conditions-then-as-physical-interactions)
- [3. Servo dynamics and linkage geometry between the stick and the surface](#3-servo-dynamics-and-linkage-geometry-between-the-stick-and-the-surface)
- [4. Floatplanes: the boundary between floating, planing, and flying](#4-floatplanes-the-boundary-between-floating-planing-and-flying)
- [5. Does simulator practice transfer to real RC flying?](#5-does-simulator-practice-transfer-to-real-rc-flying)
- [6. Accessible flying: alternative actions and readable aircraft orientation](#6-accessible-flying-alternative-actions-and-readable-aircraft-orientation)
- [7. Shared control, buddy-box practice, and remote coaching](#7-shared-control-buddy-box-practice-and-remote-coaching)
- [8. Community aircraft packages and format evolution](#8-community-aircraft-packages-and-format-evolution)
- [9. Offline use, portable downloads, and predictable updates](#9-offline-use-portable-downloads-and-predictable-updates)
- [10. Learning flight-model parameters from recorded data](#10-learning-flight-model-parameters-from-recorded-data)

### 1. Landing gear, grass, and the first few seconds on the ground

**Question:** how little ground physics produces a believable takeoff run and landing, and where does that approximation fail?

**Documented capability:** JSBSim's landing-gear interface separates rolling, static, and dynamic friction; configurable spring and damping coefficients; rebound damping; steering; and structural versus wheel contact points. Its explanatory model derives contact velocity from both aircraft translation and rotation, applies forces at the gear locations, and obtains the resulting moments from the force lever arms. The spring/damper normal force is constrained so the ground cannot attract the aircraft. These are useful building blocks for distinguishing a landing bounce from a generic collision. The prose includes simplifying assumptions, so it should be read alongside a pinned implementation before reproducing the algorithm. [JSBSim FGLGear documentation and embedded source](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGLGear.html).

**Alternative documented approach:** Jolt's versioned vehicle API lists ray, sphere-cast, and cylinder-shape wheel collision testers. This gives a concrete comparison to investigate: a wheel does not necessarily need its own fully simulated spinning rigid body to find contact with terrain. The API establishes available query methods, not which one gives satisfactory RC gear behavior. [Jolt 3.0.1 vehicle collision tester reference](https://jrouwe.github.io/JoltPhysicsDocs/3.0.1/_vehicle_collision_tester_8h.html).

**How it could help — inference:** ground handling offers a contained experiment with visible outcomes before elaborate aerodynamics. A spring contact model might represent flexible wire gear, while a simple game-engine contact model might be enough for an early trainer. Grass could initially be explored as tunable rolling resistance plus modest terrain roughness. That would be an explicitly approximate surface model: this research found no measured RC tire/grass coefficients suitable for treating a single “grass friction” number as truth. Wheel diameter, surface softness, and grass height remain calibration questions.

**Optional experiment:** drop the same simple aircraft from several small heights, then coast it along a flat surface with propulsion disabled. Record settling time, peak pitch, stopping distance, and contact forces. Repeat with a smaller timestep and compare ray versus shape contact queries over a small bump. Unexplained increases in bounce energy or strong timestep dependence would identify numerical problems before tuning by feel. A tricycle/taildragger comparison could then test whether changing gear locations alone produces plausible differences. None of these models or tests has been run for this project.

### 2. Launch methods as initial conditions, then as physical interactions

**Question:** can hand launches, bungees, and aerotows be explored without first building a complete launcher simulation?

**Documented operational distinction:** ArduPilot's automatic-takeoff guide treats hand, catapult, and bungee launches separately. Its hand-launch logic includes acceleration, ground-speed, and delay conditions for motor activation; catapult guidance discusses stronger acceleration and motor clearance timing. Bungee launch involves stored elastic energy and tension before release. These are autopilot procedures, not a validated physical launch model, but they reveal meaningful phases a simulator could represent: held, accelerating, released, and powered climb. [ArduPilot automatic takeoff](https://ardupilot.org/plane/docs/automatic-takeoff.html).

**Source-inspected simulator lead:** FlightGear YASim's `Hitch` interface exposes tow length, an elasticity parameter, break force, mass per unit length, and winch speed, power, force, and length limits. The implementation binds these to simulator properties. This confirms concrete implementation interfaces; it does not establish accuracy for an RC bungee or a working setup for every launch type. [Hitch interface](https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Hitch.hpp), [implementation and property bindings](https://raw.githubusercontent.com/FlightGear/flightgear/next/src/FDM/YASim/Hitch.cpp). The YASim wiki itself was inaccessible, so source inspection supplied this evidence. FlightGear's separate towing page, last edited in August 2020 and potentially stale, distinguishes aerotow and winch implementations from auto-tow/bungee work it describes as unavailable. Treat that as historical documentation, not a current feature verdict. [FlightGear towing documentation](https://wiki.flightgear.org/Towing).

**How it could help — inference:** a very small launch experiment could start immediately after release, defining position, orientation, translational velocity, angular velocity, and throttle timing. This would let us vary a weak throw, unintended bank, or excessive pitch without simulating a person. Crucially, throw velocity relative to the ground and airspeed in wind would be separate quantities. The experiment could answer whether the initial aircraft model remains controllable at low speed.

A later tether experiment could apply a tension-only spring force at a configurable hook point. Hook location matters because an off-centre pull creates a pitching moment; tension should disappear when the line becomes slack. Aerotow would add a moving attachment point and coupled aircraft dynamics. These are candidate approximations, not claims that a linear spring reproduces rubber, rope sag, launcher rails, or towplane wakes.

**Optional experiment:** compare identical post-release states produced by an instant initial-velocity launch and a short scripted acceleration phase. If the trajectories differ, inspect the release state and accumulated angular motion before adding launcher detail. No launch model was implemented or validated in this pass.

### 3. Servo dynamics and linkage geometry between the stick and the surface

**Question:** how much of an RC aircraft's handling comes from the actuator rather than the wing model?

**Manufacturer specifications, not independent measurements:** Hitec's HS-55 datasheet reports no-load travel times of 0.17 seconds per 60 degrees at 4.8 V and 0.14 seconds at 6.0 V, with an 8-microsecond deadband and pulse-based position control. These imply nominal no-load average shaft rates of roughly 353 and 429 degrees/second. They do not establish speed under aerodynamic load or total transmitter-to-surface latency. There is also a useful provenance warning: the older PDF lists 1.3 kg·cm torque at 6 V, while the current manufacturer chart lists 1.5 kgf·cm for HS-55. Preserve the specific source and version rather than quietly combining them into a supposedly definitive servo. [HS-55 specification PDF](https://hitecrcd.co.jp/material/spec_sheet/servo/31055.pdf) · [Hitec servo specification chart](https://hitecrcd.com/servo-specification-chart/?setCurrencyId=1).

**Documented simulation building block:** JSBSim's actuator component supports an ideal pass-through or additional lag, rate limiting, deadband, mechanical hysteresis, bias, and hard stops. It documents the order of these effects and permits distinct increasing/decreasing rate limits. This is a concrete reference for experiments more modest than simulating a servo's motor and internal controller. Its generic actuator interface is not itself a measured RC-servo model. [JSBSim FGActuator documentation](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGActuator.html).

**How it could help — inference:** keep requested control-surface deflection distinct from actual deflection when experimenting. A rate limiter alone could reveal whether rapid stick reversals feel materially different from instantaneous movement. Linkage geometry is another independent variable: servo-shaft rotation does not directly equal elevator angle, and horn lengths alter the motion/force relationship. A first approximation could use a fixed angular ratio; a later one could solve the actual pushrod geometry. Neither no-load speed nor stall torque should be treated as a complete load-dependent model.

**Optional experiment:** plot requested and actual surface angles for a step input and repeated reversals, comparing ideal motion, a rate cap, and small hysteresis. Keep controller sampling and display interpolation fixed so their delays are not mistakenly attributed to the servo. A later bench experiment with video and a known supply voltage could test unloaded motion first; loaded motion and backlash would require additional measurements. Such a separation could make slow response explainable without prematurely adding a detailed electronics subsystem. No servo measurements or runtime tests were performed here.

### 4. Floatplanes: the boundary between floating, planing, and flying

**Question:** could water operation become a useful future branch, and what would a simple model omit?

**Documented capability:** Gazebo's buoyancy documentation calculates displaced volume from collision geometry, illustrating that buoyancy geometry can be separate from the thin outer collision shell. Its hydrodynamics tutorial separately describes a six-degree-of-freedom marine model with added mass, Coriolis terms, linear and quadratic damping, and water-relative velocity. The tutorial's buoyant-cylinder example uses distinct buoyancy, hydrodynamics, and trajectory plugins. This separation is helpful conceptually: being able to float does not establish credible acceleration across a water surface. The inspected pages are versioned documentation, not proof that these plugins reproduce RC floatplane takeoffs. [Gazebo Sim 8 buoyancy theory](https://gazebosim.org/api/sim/8/theory_buoyancy.html) · [Gazebo Sim 9 hydrodynamics theory](https://gazebosim.org/api/sim/9/theory_hydrodynamics.html).

**Original experimental evidence, limited to the reported setup:** a 1942 NACA investigation examined porpoising of a V-shaped planing surface fitted with tail surfaces. NASA's report abstract describes variations in load, speed, inertia, pivot position, elevator setting, and tail area. It reports a critical trim insensitive to elevator setting or tail area in that experiment, while pivot location and radius of gyration affected the boundary. This makes a valuable caution against treating repeated pitch oscillation as something that can always be fixed by increasing elevator authority. Only the original archive abstract and metadata were inspected here; its full data tables were not extracted or fitted. [NACA-WR-L-479, NASA archive record](https://ntrs.nasa.gov/citations/19930092992).

**How it could help — inference:** floatplanes expose an interesting interface between environmental forces and ordinary aircraft dynamics. An exploratory hierarchy might begin with static buoyancy and roll stability, then directional water drag, then speed/trim-dependent planing lift, leaving spray and detailed free-surface flow for separate research. A graphical water shader would not validate any of those forces. Conversely, a simple flat water surface could be enough to investigate them numerically.

**Optional experiment:** float a rigid body with two simple pontoons; vary mass distribution and measure equilibrium attitude and return after a small roll disturbance. Only then compare an accelerating run with and without a provisional planing term. Parameters from full-scale flying-boat research would need scale-aware interpretation before RC use. Water entry impacts, wetted-area changes, wave encounters, and porpoising remain substantial open questions. This branch is an optional research possibility, with no implementation or scheduling commitment and no runtime validation yet.

### 5. Does simulator practice transfer to real RC flying?

**Evidence: adjacent experimental aviation research, a research-methods paper, and firsthand RC club instruction; RC-specific transfer remains unverified in this pass.** This question is different from whether a simulator offers attractive training features. We can measure improvement inside a game without establishing improvement at a flying field. Targeted searches for RC simulator training-transfer studies did not locate a controlled RC airplane trial strong enough to support an effectiveness claim; this is a search limitation, not proof that no such study exists.

An 18-month study by Macchiarella, Arban, and Doherty examined an experimental private-pilot curriculum comprising 60% flight-training-device time and 40% airplane time. Students practiced tasks to a standard in the device before actual flight; the authors report significant effective transfer for most tasks examined. **Useful insight:** define the particular task and criterion being learned, rather than treating total simulator hours as the outcome. **Boundary:** the inspected university record provides the abstract, not enough methodological detail for an effect-size claim. Full-size cockpit flying, this curriculum, and these participants cannot establish transfer for ground-view RC flying. [Authors' institutional publication record](https://commons.erau.edu/publication/149/).

A NASA-hosted control-loader experiment provides an especially useful distinction: *quasi-transfer* moves participants between simulators; *transfer* tests them in the real vehicle. Its roll-disturbance task compared controller dynamics, and the paper says data collection was incomplete at submission. **Project relevance:** successfully transferring between our aircraft models or between two simulators would be an interesting result, but calling that real-flight validation would overstate the evidence. [Cardullo and colleagues, control-loader study](https://ntrs.nasa.gov/api/citations/20120006673/downloads/20120006673.pdf).

George Krueger's Coachella Valley RC Club manual supplies concrete practitioner hypotheses: practice from repeatable maneuver-entry positions, start without wind, and later practice deliberate geometry against ground references. It assumes some actual field experience. **Evidence boundary:** this is an instructor's practical curriculum for an older RealFlight version, not a controlled comparison or a universal safety authority. Its value is an example of structured practice that can be investigated. [Original club training manual](https://cvrcclub.com/wp-content/uploads/2021/07/RC_Model_Airplane_Training_Manual.pdf).

**Possible small experiment:** compare equal-duration free flight and a single structured orientation exercise, then test both groups on an unfamiliar simulated approach without hints and again after a delay. Record wrong-direction corrections, completion, and prior experience. That would investigate learning and retention inside the simulator. A later, separately designed instructor-supervised field study would be needed before making RC flight-transfer claims. Neither photorealism nor favorable pilot anecdotes can substitute for that distinction.

### 6. Accessible flying: alternative actions and readable aircraft orientation

**Evidence: official input-device specifications and game accessibility guidance; proposed RC adaptations have not been tested.** A four-channel transmitter is one useful interface, but its two-handed operation is also a research question. Remapping alone cannot solve the need to hold several continuous inputs while operating menus or restarting after a crash.

Microsoft's input guidance distinguishes speed, complexity, and duration of actions. It discusses digital alternatives to analog interaction, remappable actions, adjustable gameplay speed, and toggles for sustained actions. **RC application, as an inference:** a one-handed experiment could combine a stick for elevator/aileron, incremental throttle buttons that retain their setting, optional rudder coordination, and an easily reached pause/reset action. Separately configurable input curves and simulation speed answer different needs: curves change response to movement; slower time changes the time available to react. These are possible configurations, not a universal accessible control scheme or evidence of equivalent training. Menus and calibration need to be operable with the same available inputs, otherwise a flyable airplane can remain inaccessible. [Xbox Accessibility Guideline 107](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107).

The Xbox Adaptive Controller's official v1.6 device specification is useful beyond a product recommendation: external USB HID joystick inputs become thumbstick positions, firmware changes affect supported buttons and second-stick detection, and some simultaneous connections take precedence over others. For example, a USB joystick can override an analog joystick connected to the corresponding 3.5 mm stick port. **Project relevance:** document and inspect the actual resulting axes/actions instead of assuming every connected assistive device contributes independently. **Limit:** those electrical and firmware rules describe this controller; they do not establish our compatibility across operating systems or with every custom switch. [Microsoft input-device specification, sections 10 and related mappings](https://assets.xboxservices.com/assets/b8/05/b8055a56-827c-48f8-b8ec-2c7aa66ef069.pdf?n=xbox-adaptive-controller-input-device-specification_1.6_Finalpdf.pdf).

Visual access also touches flight behavior. Microsoft's cue guidance recommends conveying information through more than color and warns that color-vision simulation filters do not replace testing with affected players. **RC-specific possibility:** compare asymmetric wing patterns, distinct top/bottom markings, and optional orientation symbols against red/green-only coloring; evaluate them at actual on-screen aircraft sizes. A warning could combine text or shape with sound, without relying exclusively on controller vibration. [Xbox Accessibility Guideline 103](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/103).

**Possible small experiment:** invite players with relevant access needs to configure and complete one short flight using their preferred setup. Observe setup barriers, missed orientation cues, fatigue, and accidental resets. Treat high-contrast liveries and assistance as options worth evaluating; keep any claims about real-RC skill transfer separate from successful access to the simulator.

### 7. Shared control, buddy-box practice, and remote coaching

**Evidence: transmitter documentation, engine networking documentation, and a web standard; an RC coaching implementation is a possibility.** Multiplayer can mean different things: two pilots controlling separate aircraft, an instructor watching a student's flight, or two people sharing one aircraft. The last case deserves its own control model before investigating online infrastructure.

EdgeTX's v2.11 trainer configuration documents per-axis handling for aileron, elevator, throttle, and rudder: instructor-only input, adding instructor/student values, or replacing instructor input with student input. It also exposes source-channel mapping, student input weighting, and center calibration; the master radio is bound to the model receiver. **Project relevance:** real trainer operation supplies a richer reference than simply summing two gamepads. A simulator could explore giving a learner aileron/elevator while an instructor retains throttle, with a clear indication of who currently controls each action. **Limit:** these are documented radio semantics, not a complete specification for software handover or remote failure behavior. [EdgeTX trainer documentation](https://manual.edgetx.org/v2.11/color-radios/radio-settings/trainer).

Godot's networking documentation illustrates a general transport distinction without selecting an engine: reliable delivery suits events that must arrive, whereas frequently superseded state can use unreliable or unreliable-ordered delivery. Separate channels prevent reliable chat traffic from holding up unrelated reliable gameplay messages. It also documents browser transport differences. **Potential application:** ownership requests and aircraft snapshots need different treatment; an old stick sample should not become a fresh command merely because it arrived late. **Boundary:** RPC authority and delivery modes do not automatically produce correct flight synchronization, predictable handover latency, or deterministic physics. [Official high-level multiplayer documentation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).

For a browser route, the W3C WebRTC standard defines ordered or unordered data channels and partial reliability controlled by maximum retransmissions or packet lifetime; those two limits cannot be configured simultaneously. **Useful detail:** transport policy can reflect whether a message is still meaningful after delay. It does not remove the need for session setup, connectivity handling, or application-level ownership rules. [WebRTC data-channel specification](https://www.w3.org/TR/webrtc/#rtcdatachannel).

**Possible progression:** first test two local input devices sharing one aircraft, making handover and per-axis ownership visible. Next, an observer could receive snapshots and see both pilots' inputs while one machine owns the simulation. Only then try remote takeover with deliberately delayed, reordered, and dropped messages. Measure handover time and inspect disconnect behavior. This host-owned design is an experiment that avoids requiring identical simulation on every peer; it is not a commitment to a networking architecture. Replay review or screen-sharing may already answer some coaching needs before interactive multiplayer exists.

### 8. Community aircraft packages and format evolution

**Question.** How could someone share an aircraft that remains understandable and usable as the simulator changes?

**Documented examples.** FlightGear separates its simulator from aircraft hangars. Its launcher can read both the official hangar and third-party `catalog.xml` URLs; a catalog-generation tool turns source content into distributable listings. This provides an example of decentralized aircraft distribution rather than requiring one central marketplace. [FlightGear hangar catalog](https://wiki.flightgear.org/Hangar_catalog)

JSON Schema offers a smaller building block: properties, required fields, and policies for unknown properties. The official guide explains that `additionalProperties` can interact unexpectedly with composed schemas, while `unevaluatedProperties` can account for properties evaluated in subschemas. A separate `$schema` declaration identifies the JSON Schema dialect; it is not an aircraft's format version or the simulator's physics version. [Object validation](https://json-schema.org/understanding-json-schema/reference/object), [dialect declaration](https://json-schema.org/understanding-json-schema/reference/schema)

**How this could help / design possibilities.** A first sharing experiment could be a folder containing a visual asset, aircraft data, a preview, and a short manifest identifying the author and parameter sources. Later questions include stable aircraft IDs, distinguishing a repaint from a physics change, units, asset credits, and what an older reader does with a newer format. These are questions to explore, not a proposed mandatory schema. A catalog could come much later, if exchanging folders becomes inconvenient.

**Important distinction.** A structurally valid file can still contain physically unsuitable coefficients. Inference: useful checks would have separate roles—schema checks for shape, model checks for units/ranges/relationships, and flight experiments for behavior. A physics update may change an aircraft's response even when its file still loads, so data compatibility and repeatable handling are different questions.

**Small experiment.** Share one minimal aircraft folder between two clean prototype installations, then introduce one optional field and one intentionally unsupported format version. Observe the explanation given to the user and whether the original file survives unchanged. No package system or validator was implemented here. FlightGear's more detailed catalog-metadata page returned HTTP 403 and remains a follow-up, rather than evidence for specific manifest fields.

### 9. Offline use, portable downloads, and predictable updates

**Question.** Could someone practice at a field or club without reliable internet, and keep a useful version while experiments continue?

**Documented browser route.** Google's PWA guide distinguishes Cache Storage for fetched application resources from IndexedDB for structured local data. Storage limits and eviction vary; a request for persistent storage can help where supported, but users can still clear their data. Its update guide describes replacing all cached assets, updating changed assets, and choosing when new versions take effect. An installed icon alone does not demonstrate an offline-ready simulator. [Offline data](https://web.dev/learn/pwa/offline-data), [update strategies](https://web.dev/learn/pwa/update)

**Documented native alternatives.** AppImage describes a Linux application distributed as one executable file, while still depending on an intentionally selected system baseline and graphics-driver environment. Its guidance to build against older supported systems illustrates why packaging is distinct from simply compiling. It is a Linux option, not one binary for every OS. Separately, itch.io's butler documents platform channels, explicit build labels, and differential uploads/updates. Direct downloads do not receive the itch app's automatic updates. [AppImage concepts](https://docs.appimage.org/introduction/concepts.html), [butler distribution guide](https://itch.io/docs/butler/pushing.html)

**How this could help / inference.** The first prototype could test a complete offline experience with one airplane and one plain field. Downloadable aircraft later raise a separate question: what is actually available offline? Saving calibration and custom aircraft in an exportable form could preserve a user's work independently of app updates. Side-by-side experimental builds could make comparisons easier, without deciding now on a store, installer, or update service.

**Small experiment.** After one successful online launch, disconnect, restart the application, load the same aircraft, and recover its control profile. Then try an update with intentionally changed aircraft data. Record startup, missing-resource behavior, persistence, update size, and whether the previous version can still be used. No installer, service worker, upload, or deployment was created during this research. Browser behavior and native packaging need actual platform tests before any support promise.

### 10. Learning flight-model parameters from recorded data

**Question.** Could an aircraft evolve from plausible estimates toward measured behavior without rebuilding its model by hand each time?

**Research evidence.** Benjamin Simmons's 2023 dissertation specifically studies small, fixed-wing, remotely piloted electric propeller aircraft, including aerodynamic/propulsive model identification from flight data. It also explores methods that do not begin with known mass properties. This is evidence of researched methods for relevant aircraft classes, not proof that arbitrary hobby telemetry contains enough information to identify a complete airplane. The NASA abstract was inspected; reproducing the dissertation's methods remains further work. [Original dissertation record and download](https://ntrs.nasa.gov/citations/20230004001)

**Documented tooling.** NASA's SIDPAC catalog describes MATLAB routines covering experiment design, data conditioning, parameter estimation, accuracy assessment, and validation. Its current listing offers software by request as a U.S. and Foreign Release; the listing does not establish a permissive open-source grant. It is a methodological reference, not a selected dependency. [Current SIDPAC software listing](https://software.nasa.gov/software/LAR-16100-1)

ArduPilot Plane documents frequency-sweep input excitation for collecting model-identification data, and its operation guide describes synchronized reference, gyro, and acceleration logging. The Plane feature page says this support is not automatically included in the stable firmware build. These details distinguish an intentional identification dataset from a casually recorded flight. [Plane system identification](https://ardupilot.org/plane/docs/common-systemid-mode.html), [logging and operation](https://ardupilot.org/plane/docs/common-systemid-mode-operation.html)

**How this could help / inference.** Start by trying to identify one response, such as roll damping or an actuator time constant, rather than every aerodynamic coefficient. Time alignment, sensor filtering, wind, and the difference between commanded and actual surface motion could otherwise be mistaken for aircraft dynamics. Keep fitting data separate from a held-out maneuver used to assess prediction.

**Small experiment.** Generate synthetic input/output traces from a deliberately simple known model, add controlled noise and delay, then see whether an estimator recovers its parameters and predicts a different maneuver. This would test the identification procedure only; it would not validate a real airplane. Later, existing consented flight logs could reveal whether sufficient excitation and measurements are available before considering any new physical data collection.

## Ten investigations into development and 3D tools

Third research pass, **2026-10-05**: ten new investigations focused on coding workflows, AI tooling, game development, Blender, and 3D assets. These extend the earlier survey with specific authoring and diagnostic tools. Capabilities below are documented upstream; none of these tools was installed or exercised for this pass. Suggested experiments remain possibilities, with no stack or workflow selected.

- [1. Parameterized airplane modeling with Blender Geometry Nodes](#1-parameterized-airplane-modeling-with-blender-geometry-nodes)
- [2. Hard-surface aircraft rigging: editable parts, hinge pivots and export behavior](#2-hard-surface-aircraft-rigging-editable-parts-hinge-pivots-and-export-behavior)
- [3. AI-generated 3D assets: TRELLIS, Hunyuan3D and the cleanup boundary](#3-ai-generated-3d-assets-trellis-hunyuan3d-and-the-cleanup-boundary)
- [4. RenderDoc: investigating an invisible or incorrectly rendered airplane](#4-renderdoc-investigating-an-invisible-or-incorrectly-rendered-airplane)
- [5. Tracy: measuring simulation stutter across CPU, GPU, and allocations](#5-tracy-measuring-simulation-stutter-across-cpu-gpu-and-allocations)
- [6. Asset optimization tooling: glTF Transform, meshoptimizer, and KTX2](#6-asset-optimization-tooling-gltf-transform-meshoptimizer-and-ktx2)
- [7. Repository-aware coding tools: Aider and Continue](#7-repository-aware-coding-tools-aider-and-continue)
- [8. AI access to Blender and game editors through MCP](#8-ai-access-to-blender-and-game-editors-through-mcp)
- [9. Repeatable development environments and build commands](#9-repeatable-development-environments-and-build-commands)
- [10. Versioning editable 3D sources and generated assets](#10-versioning-editable-3d-sources-and-generated-assets)

### 1. Parameterized airplane modeling with Blender Geometry Nodes

**Question:** Could a small editable generator produce several recognizable airplane shapes while preserving the freedom to replace the asset workflow?

**Documented capabilities.** Blender 4.5's Geometry Nodes modifier uses a reusable node group whose exposed inputs can differ between objects sharing that group. Inputs may also be fields evaluated across geometry. This supplies the building blocks for a proposed wing generator with span, chord, taper and dihedral controls; Blender does not supply a verified RC-aircraft generator in the material inspected. The documented mechanism is general procedural geometry, not an aerodynamic design system. [Geometry Nodes modifier, Blender 4.5](https://docs.blender.org/manual/en/4.5/modeling/modifiers/generate/geometry_nodes.html).

Instances provide another useful distinction: a repeated wheel or rib need not duplicate its underlying geometry. Realize Instances converts instances into actual geometry for individual processing, but Blender warns that realizing many complex instances can substantially worsen performance. For an export workflow, realization is therefore a deliberate conversion step to investigate, not something to add indiscriminately. [Realize Instances, Blender 4.5](https://docs.blender.org/manual/en/4.5/modeling/geometry_nodes/instances/realize_instances.html).

A separate operation, **Visual Geometry to Objects**, extracts evaluated geometry into objects and collections while preserving shared geometry and instancing hierarchy. It leaves the original object intact. However, the documentation explicitly says instance attributes are not preserved. That matters if hypothetical identifiers such as `left_aileron` or material labels are carried as attributes: their survival would need checking rather than assumption. [Apply operations, Blender 4.5](https://docs.blender.org/manual/en/4.5/scene_layout/object/editing/apply.html).

**Project relevance and limits.** A modest generator could make distinct trainer, glider and sport-plane silhouettes from one understandable source. Parameters could also make AI-authored modifications easier to inspect than arbitrary vertex edits. These are potential benefits, not measured results. A visual wing's dimensions do not establish its airfoil polar, mass distribution or flight behavior; generated geometry should not quietly become authoritative physics data. Increasing generator complexity could also cost more than hand-modeling a few simple aircraft.

**Small experiment.** Expose only span, chord and tail length; create three variants; extract editable objects; inspect dimensions and separation of control surfaces after export/reimport. Compare editing effort with three manually modeled blockouts. Retain the generator only if it makes this tiny exercise simpler. No generator or export has been executed during this research.

### 2. Hard-surface aircraft rigging: editable parts, hinge pivots and export behavior

**Question:** What is the smallest modeling convention that allows an airplane to move its control surfaces without making every asset a complex character rig?

**Documented capabilities.** Blender supports ordinary object parenting and parenting objects to armature bones. Its manual describes object parenting as the general mechanism; bone parenting attaches objects to a selected bone. This gives two candidate representations: a hierarchy of separate rigid objects, or an armature coordinating those objects. The parenting reference inspected is Blender 3.6, so UI details should be rechecked against the eventual authoring version. [Parenting objects, Blender 3.6](https://docs.blender.org/manual/en/3.6/scene_layout/object/editing/parent.html).

Object origins affect rotation and scaling, and can be moved independently of geometry, including to the 3D cursor. Consequently, placing a separate elevator's origin on its hinge is a plausible implementation technique. Blender's origin-to-center-of-mass option assumes uniform mesh density; that convenience is not a measured RC aircraft center of gravity. [Object origin, Blender 4.5](https://docs.blender.org/UATEST/manual/en/4.5/scene_layout/object/origin.html).

Non-destructive modifiers preserve the editable base geometry until applied. Their stack order affects the result, so an editable symmetric fuselage and its baked export should be treated as related artifacts rather than interchangeable sources. [Modifier introduction, Blender 4.5](https://docs.blender.org/manual/en/4.5/modeling/modifiers/introduction.html).

Blender's glTF documentation supports object transforms, pose-bone animation and shape-key values. It does not imply that arbitrary Blender behavior transfers: other animated properties can be ignored, and animation organization/export mode matters. This makes a simple object-rotation test valuable before adopting an elaborate rig. [glTF animation documentation, Blender 4.5](https://docs.blender.org/manual/es/4.5/addons/import_export/scene_gltf2.html).

**Project relevance and limits.** A proposed first aircraft could contain a fuselage, two ailerons, elevator, rudder and propeller as named parts, with live simulator commands driving rotations. An armature remains worth exploring for coordinated mechanisms or deformation, but is not a prerequisite established by these sources. Neither representation establishes the physical effect of deflection; that remains a separate simulation question.

**Small experiment.** Model one wing and aileron using an object hinge, then reproduce it with a bone. Export/reimport neutral and deflected poses; inspect rotation axis, part names and attachment. Compare contributor effort and runtime control before standardizing either convention. Also measure whether a low-detail model remains readable from the pilot's viewing distance.

### 3. AI-generated 3D assets: TRELLIS, Hunyuan3D and the cleanup boundary

**Question:** Can generative 3D tools reduce asset work once cleanup, editability and redistribution are counted?

**Documented capabilities and limits.** Microsoft's original **TRELLIS** repository provides text/image-conditioned generation, mesh output and a textured GLB example with simplification and texture-size controls. Its authors recommend image conditioning; they report weaker creativity/detail for text models and caution that their tuning-free multiview implementation may not work best for every input. The documented environment is Linux with an NVIDIA GPU of at least 16 GB; Windows setup is not fully tested. Those are upstream requirements, not a local benchmark or a claim about later TRELLIS versions. [TRELLIS repository](https://github.com/microsoft/TRELLIS).

**Hunyuan3D-2** supplies separate shape-generation and texture-generation pipelines, including multiview variants. This separation suggests an experiment using generated appearance with manually controlled geometry, rather than assuming generation must replace the whole modeling process. No aircraft-quality claim was verified. [Hunyuan3D-2 repository](https://github.com/Tencent-Hunyuan/Hunyuan3D-2).

**Licensing evidence.** TRELLIS says its models and most code use MIT, while identifying differently licensed submodules. A top-level license therefore does not settle every dependency. Hunyuan3D-2's inspected Community License covers model code and weights, excludes the EU, UK and South Korea from its territory, and explicitly restricts use/distribution of outputs outside that territory. Although Tencent says it claims no rights in outputs, this is not an unrestricted-output promise. Exact revisions and generated-asset redistribution terms need checking before adopting a workflow. The linked Hugging Face `LICENSE.txt` returned 404 in this pass; it was not independently verified. [TRELLIS licensing section](https://github.com/microsoft/TRELLIS#%EF%B8%8F-license), [Hunyuan3D-2 license](https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE).

**Project relevance and uncertainty.** Decorative airfield objects are a plausible first target. Aircraft need separate hinges, trustworthy dimensions and deliberate collision shapes; those properties were not verified in generated output. Blender offers remeshing and manual retopology, but explicitly warns that automatic remeshing does not generally produce suitable deformation topology. [Blender 4.5 remeshing](https://docs.blender.org/manual/en/4.5/modeling/meshes/retopology.html).

**Small experiment.** Where the chosen model's terms permit, compare one generated windsock stand and one hand-built version: count cleanup minutes, triangles, material complexity and silhouette errors. For a subsequent airplane trial, test symmetry, thin trailing edges, scale and independently editable ailerons. Compare total effort, not attractive preview renders. No model was installed or run.

*Source-access note for these three topics: several direct Blender page opens returned 402/403. The cited findings were checked against the official manual content returned by indexed search, including substantial page text, rather than treating failed fetches as evidence. Runtime/export behavior remains untested.*

### 4. RenderDoc: investigating an invisible or incorrectly rendered airplane

**Question.** When an airplane disappears, looks inside out, or has the wrong material, what evidence can developers inspect beyond a screenshot?

**Documented capabilities.** RenderDoc captures graphics frames for inspection and is MIT-licensed. Its official support table lists Vulkan, OpenGL ES, and desktop core OpenGL on applicable Windows/Linux/Android targets, plus D3D11/12 on Windows. It explicitly excludes old OpenGL compatibility APIs and D3D9/10. Metal is unsupported; macOS is absent from the supported platforms. Consequently, a cross-platform simulator cannot assume this single debugger covers every eventual renderer. Nintendo Switch support is separately distributed through Nintendo's SDK, not part of an unrestricted desktop workflow. [RenderDoc repository and API/platform matrix](https://github.com/baldurk/renderdoc/blob/v1.x/README.md).

The mesh viewer exposes vertex data in tables and a 3D preview at different stages of the graphics pipeline. This makes it possible to inspect geometry entering and leaving vertex processing, rather than only the final image. The pipeline-state viewer exposes the active shaders, resource bindings, and graphics state, with links into detailed resource inspection. [Mesh-viewer documentation](https://github.com/baldurk/renderdoc/blob/v1.x/docs/window/mesh_viewer.rst), [pipeline-state documentation](https://github.com/baldurk/renderdoc/blob/v1.x/docs/window/pipeline_state.rst).

RenderDoc also offers an optional application API for controlled capture triggering. Its documentation recommends detecting the injected library at runtime; the ordinary application can continue without it. This leaves room for an eventual “capture the next aircraft-rendering failure” developer action without making the debugger a normal runtime dependency. [In-application API](https://github.com/baldurk/renderdoc/blob/v1.x/docs/in_application_api.rst).

**Possible project value.** A future investigation could ask, in order: was the aircraft draw submitted; were the expected vertices supplied; did the transform place them within the camera volume; were the intended material resources bound; and did depth or culling state suppress the result? These are proposed diagnostic questions, not claims that RenderDoc automatically identifies the cause. They could also give AI-generated rendering fixes concrete evidence to explain.

**Small experiment, unperformed.** On one supported prototype, deliberately reverse face winding or corrupt a transform, save a frame, and try to identify the change from capture evidence. Record the engine, graphics API, GPU, driver, and debugger version. Successful capture on that configuration would not establish support on every target. Frame inspection answers rendering-correctness questions; timing a long flight requires a separate profiling approach.

### 5. Tracy: measuring simulation stutter across CPU, GPU, and allocations

**Question.** Could a profiler explain why controls feel uneven even when average frame rate appears acceptable?

**Documented capabilities.** Tracy's repository describes CPU instrumentation, GPU profiling, allocations, locks, context switches, and frame-associated screenshots. Direct language integrations and third-party bindings are distinguished: finding a Rust or C# binding is not evidence that it has identical maintenance or functionality to the C/C++ integration. The advertised GPU backends include OpenGL, Vulkan, Direct3D, Metal, and WebGPU. [Tracy repository](https://github.com/wolfpld/tracy).

The manual documents scoped CPU zones, frame markers, allocation/free events, and application plots. GPU profiling uses backend-specific instrumentation and event collection. Its WebGPU path names **Dawn and wgpu-native**, with pass-level timing; this should not be read as a promise of ordinary browser JavaScript integration. D3D11 command lists are explicitly unsupported. [Tracy user manual source](https://github.com/wolfpld/tracy/blob/master/manual/tracy.tex).

**Integration limits.** Profiling is enabled with `TRACY_ENABLE`; manually defining it as `0` still defines the macro and does not disable it. Optimized builds better represent normal execution than debug builds. Instrumentation, call stacks, and event collection have costs; detailed wait-stack collection can be expensive on weaker hardware. Platform and graphics-backend support must be checked for the exact feature being investigated. [Build and instrumentation guidance](https://github.com/wolfpld/tracy/blob/master/manual/tracy.tex).

**Possible project value.** A useful initial trace could name just four CPU activities: input polling, physics stepping, rendering preparation, and asset loading. A plot of physics substeps per displayed frame could reveal whether stutter coincides with simulation catch-up. Allocation events could expose repeated temporary objects during flight. GPU zones could help distinguish rendering cost from a CPU-side pause. Those interpretations would remain hypotheses until the timeline and a controlled change support them; tracing alone does not prove causality or input-to-display latency.

**Small experiment, unperformed.** Run a repeatable camera-and-aircraft movement sequence, introduce one deliberate loading pause, then compare traces before and after removing it. Examine long frames and their frequency, not only averages. Compare an instrumented build with a matching uninstrumented build to estimate measurement disturbance. Keep the capture short and the zone set small before adding detail. Pin the client and viewer versions used for any saved result. RenderDoc would help explain a wrong image; Tracy would help explain when and where execution time accumulated. Neither tool verifies aerodynamic realism.

### 6. Asset optimization tooling: glTF Transform, meshoptimizer, and KTX2

**Question.** How could an editable Blender airplane become a lighter runtime asset without losing the ability to revise it or change engines?

**Documented capabilities.** glTF Transform provides inspection, validation, mesh joining, vertex quantization, geometry/animation compression, simplification, and texture operations. Its documentation warns that the broad `optimize` command's defaults are not ideal for every scene, making inspection and selected transforms worth investigating before adopting a blanket preset. [glTF Transform CLI](https://gltf-transform.dev/cli).

meshoptimizer distinguishes reordering/compression from triangle simplification. Its simplifier has an error limit and may stop before the requested triangle target because of topology or attribute seams. It supports building levels of detail, but producing a smaller mesh does not itself supply an engine's runtime LOD selection or transition behavior. Thin wings, control-surface gaps, and silhouettes therefore deserve inspection at flight viewing distances. [meshoptimizer algorithms and simplification guidance](https://github.com/zeux/meshoptimizer).

Khronos's `KHR_texture_basisu` extension carries Basis Universal textures in KTX2, with runtime transcoding into a block-compressed format supported by the target platform. It supports ETC1S and UASTC and can carry mip levels. A fallback PNG/JPEG may be supplied; without one the extension must be marked required. Thus smaller delivery files and reduced GPU texture memory are related but distinct benefits, contingent on actual loader/transcoder support. [Ratified texture-extension specification](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_texture_basisu/README.md).

**Practical dependency.** The currently inspected glTF Transform KTX encoding implementation invokes KTX-Software and checks its installed version. This is an additional offline tool dependency, not something implied merely by installing an engine or accepting `.glb` files. [KTX encoding implementation](https://github.com/donmccurdy/glTF-Transform/blob/main/packages/cli/src/transforms/toktx.ts).

**Possible project value.** Keep an original `.blend`, original textures, and an uncompressed export; generate optimized derivatives with recorded tool versions and settings. This would make compression reversible and let future renderer experiments choose compatible outputs. Mesh compression requires the corresponding decoder in the target loading path. Automatic joining or hierarchy changes deserve special attention if ailerons, elevator, and propeller need separate transforms.

**Small experiment, unperformed.** Compare original, simplified, and texture-compressed variants of one aircraft. Measure download size, load time, runtime memory, and frame timing separately. Inspect markings, normal maps, control surfaces, and distant silhouette. Retain a plain export as the compatibility baseline; no compression format or asset budget is selected here.

### 7. Repository-aware coding tools: Aider and Continue

**Question.** Which concrete mechanisms help an AI tool work on an unfamiliar simulator repository and check its changes?

**Documented capabilities.** Aider builds a repository map containing selected symbols and signatures, ranks relevant material using a dependency graph, and fits that map into a token budget. This is a context-selection mechanism; it does not mean every file is read in full or every architectural relationship is understood. It could help an agent locate the relationship between input handling, aircraft state, and rendering as the project grows. [Aider repository map](https://aider.chat/docs/repomap.html).

Aider can invoke configured lint and test commands, receive their diagnostics, and attempt repairs. Automatic testing after changes is configurable; it should not be assumed to run merely because a command exists. A command returning a failure status supplies a stronger signal than prose saying the code looks correct. These hooks could eventually run a build, a small numerical check, or an asset validator, depending on the prototype. Built-in language linting does not establish support for every future engine scripting language. [Aider linting and testing](https://aider.chat/docs/usage/lint-test.html).

Continue's agent documentation describes file reading, searching, editing, and terminal execution from the workspace root. Its Ollama provider documentation gives model configuration and distinguishes tool-use and image-input capabilities; it also records context-related memory failures and configuration adjustments. This supplies a local-model research path, but says nothing about whether a particular model can reliably repair our simulator. Capability flags and a successful connection are not quality benchmarks. [Continue agent operation](https://docs.continue.dev/ide-extensions/agent/how-it-works), [Ollama configuration](https://docs.continue.dev/customize/model-providers/top-level/ollama).

**Possible project value and limits.** Comparing the surrounding workflow separately from the model could reveal whether better file selection and diagnostics matter more than changing providers. Our inference is that compact, runnable experiments would make both human review and AI feedback more concrete. Passing code checks would still leave visual readability, controller feel, and aerodynamic plausibility unresolved.

**Small experiment, unperformed.** Give two candidate workflows the same tiny project and one known defect, such as an inverted elevator visual. Record files inspected, commands actually run, unintended edits, total time, and whether the rendered correction matches the intended motion. Keep the starting revision and acceptance check identical. Do not rank tools from their feature lists alone.

### 8. AI access to Blender and game editors through MCP

**Question.** Could an agent inspect and modify a live 3D scene while receiving evidence about what happened?

**Upstream-documented capabilities.** The community project formerly linked as `ahujasid/blender-mcp` now redirects to **mcp-for-blender**. It explicitly disclaims affiliation with the Blender Foundation. Its architecture combines a Blender add-on that receives socket commands with a Python MCP server connecting those commands to an AI client. The README describes object/material editing, Blender Python execution, and multiple visual inspection modes, including camera and wireframe views. These are upstream capability descriptions, not functionality tested here. The repository also describes optional external asset/generation integrations; their existence does not establish redistribution rights for resulting assets. [MCP for Blender repository](https://github.com/ahujasid/mcp-for-blender).

**Godot MCP**, maintained by Coding-Solo, documents editor launching, project execution, debug output, and scene operations such as creating scenes, adding nodes, changing properties, and saving. Its 3D operations include MeshLibrary export. Some UID operations explicitly target Godot 4.4 or later. This is a particular community server's interface, not a universal promise about Godot or all MCP servers. Debug output alone does not demonstrate that an airplane is visibly correct. [Godot MCP repository](https://github.com/Coding-Solo/godot-mcp).

**Possible project value.** A promising loop is: inspect the scene, modify one named component, run or render, then compare the result. For example, an agent could investigate whether an aileron's hinge is misplaced by checking both object transforms and a deflected view. This could complement ordinary script generation when scene state is difficult to infer from files alone.

**Limits.** The Blender bridge can execute arbitrary Python inside Blender, so it is an execution interface with the process's available access. Trying it in a disposable scene and retaining a saved baseline would make changes recoverable. Versioning the bridge, editor, and client together would help interpret failures. A successful tool response is only evidence that a command completed; visual correctness and exported behavior still need independent inspection. These are proposed experiment boundaries, not new repository rules.

**Small experiment, unperformed.** Ask a candidate bridge to create one wing and hinged aileron, inspect the neutral and deflected states, save, reopen, and export. Compare the result and effort with a short explicit Blender Python script. Keep the simpler workflow if the live bridge adds little value.

### 9. Repeatable development environments and build commands

**Question.** How could contributors and AI tools reproduce a small experiment without prematurely standardizing the whole technology stack?

**Documented capabilities.** The Development Container specification describes development metadata around container environments. Its reference supports an image or Dockerfile, workspace mounts, environment variables, optional Features, and lifecycle commands. A significant detail is that `initializeCommand` runs on the host, while later container setup commands run inside the container. Tool-specific customizations also exist, so a configuration file is not proof that every editor implements every behavior identically. [Development Containers](https://containers.dev/), [official metadata reference](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainerjson-reference.md).

For a potential C/C++ experiment, CMake presets can describe configuration, build, test, package, and workflow operations. `CMakePresets.json` is intended for shared settings; `CMakeUserPresets.json` is intended for personal settings. Presets can capture generator choices, build directories, cache variables, environments, and toolchain references. Available fields depend on the supported preset schema and CMake version. A preset refers to a build environment; it does not by itself install or freeze every compiler and dependency. [CMake presets manual](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html).

**Possible project value.** A small documented command sequence could give a human contributor and an AI agent the same way to build and check an experiment. A container might help reproduce numerical or asset-processing work even if the interactive simulator runs natively. If another language or engine proves easier, its native project and dependency mechanisms remain equally open alternatives. Introducing CMake or a container now would provide no evidence that either is the right choice.

**Limits and inference.** Reproducing user-space tools would not reproduce every GPU driver, display system, USB transmitter, or host scheduling behavior. A successful headless run inside one container cannot certify interactive compatibility across operating systems. Image tags and unpinned downloads may also change; recording actual tool versions would make experimental results easier to revisit.

**Small experiment, unperformed.** Once one tiny prototype exists, ask a fresh environment to build it and generate a short repeatable numerical trace using only documented commands. Separately launch the native graphical build and exercise a real controller. Compare setup time and failure diagnosis with and without a container before accepting its maintenance cost.

### 10. Versioning editable 3D sources and generated assets

**Question.** How can contributors recover an older aircraft and understand how its exported assets were produced?

**Documented capabilities.** Git LFS stores small pointers in Git while placing large content in separate storage; file patterns are tracked through repository attributes. This addresses storage and transfer of large binaries, not semantic merging of a Blender scene. Its locking command records a lock on the server, and push verification has configuration and server-support considerations. Locking should not be described as a universal guarantee that competing edits are impossible. [Git LFS](https://git-lfs.com/), [lock command documentation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-lock.adoc).

DVC offers another research direction: its pipeline stages wrap commands with declared file dependencies and outputs in `dvc.yaml`. Dependencies between stages form a directed acyclic graph, and data may be cached separately from the small metadata tracked in Git. Although its examples often concern machine learning, the documented command/dependency/output mechanism suggests an asset-generation experiment. [DVC pipeline definition](https://doc.dvc.org/user-guide/pipelines/defining-pipelines).

**Possible project value.** A proposed chain could start with an editable `.blend` and original textures, run an export script, then generate optimized GLB/KTX2 derivatives. Recording the source revision, tool versions, and processing settings could explain which editable scene produced a particular in-game airplane. LFS would primarily address storing large revisions; a pipeline tool would address how outputs depend on inputs. They solve different problems and need not be adopted together.

**Limits.** This tooling would not make binary scene conflicts easy to merge, establish asset ownership, or guarantee bit-for-bit regeneration when exporter versions or nondeterministic operations change. Remote storage availability, quotas, and collaborator access would need evaluation against an actual hosting arrangement. For the first tiny aircraft, ordinary Git plus a small export script might be easier than maintaining either system. This topic concerns contributor source history, distinct from the earlier research on distributing aircraft packages to players.

**Small experiment, unperformed.** Save two visibly different revisions of one source aircraft and their exports. From a clean checkout, recover the older editable version and regenerate its derivative. Record storage downloaded, manual steps, missing tools, and any output differences. Separately try concurrent edits to the same source file to learn whether object-level separation, communication, or locking helps the actual modeling workflow.

## Ten investigations into codebase libraries and runtime tools

Fourth research pass, **2026-10-05**: ten new investigations into code organization, reusable libraries, diagnostics, and runtime services. These are candidate building blocks, not a proposed dependency list. Several examples concern C/C++ because their libraries expose useful implementation details; no language, engine, or architecture is selected. All capabilities are documented upstream, and all project experiments below remain unperformed.

- [1. Entity-component libraries: EnTT and Flecs alongside plain aircraft state](#1-entity-component-libraries-entt-and-flecs-alongside-plain-aircraft-state)
- [2. Numerical building blocks: GLM and physical quantity types](#2-numerical-building-blocks-glm-and-physical-quantity-types)
- [3. Runtime scripting: Lua and sol2 for behaviors that exceed configuration](#3-runtime-scripting-lua-and-sol2-for-behaviors-that-exceed-configuration)
- [4. Dear ImGui and ImPlot: inspecting the airplane's internal state](#4-dear-imgui-and-implot-inspecting-the-airplanes-internal-state)
- [5. Clang sanitizers: finding memory, arithmetic, and concurrency defects](#5-clang-sanitizers-finding-memory-arithmetic-and-concurrency-defects)
- [6. libFuzzer and Hypothesis: exploring inputs beyond hand-written examples](#6-libfuzzer-and-hypothesis-exploring-inputs-beyond-hand-written-examples)
- [7. Virtual file access with PhysicsFS](#7-virtual-file-access-with-physicsfs)
- [8. Library dependency resolution with vcpkg and Conan](#8-library-dependency-resolution-with-vcpkg-and-conan)
- [9. Audio implementation with miniaudio](#9-audio-implementation-with-miniaudio)
- [10. Background jobs and task scheduling with enkiTS](#10-background-jobs-and-task-scheduling-with-enkits)

### 1. Entity-component libraries: EnTT and Flecs alongside plain aircraft state

**Question.** At what point would separating entities, components, and systems make the simulator easier to change than an ordinary aircraft-state structure and explicit update functions?

**Documented/source inspected.** EnTT is a header-only C++ library whose registry stores components and exposes views over entities with selected component types. Its example combines position and velocity components without requiring a base-class hierarchy. The ECS header can be included separately from the broader library, which also offers events, resource handling, and reflection. The inspected `main` README requires C++20; older discussions describing different compiler requirements should not substitute for checking a chosen release. The source is MIT-licensed. [EnTT repository and integration documentation](https://github.com/skypjack/entt)

Flecs documents prefabs with default component values, entity names and parent scopes, and stable entity handles that still need validity checks after deletion. Its design guide distinguishes cached queries, which cost more to create but are cheaper to iterate, from uncached queries suited to occasional searches. It explicitly warns against repeatedly creating and destroying cached queries. The guide recommends small components but acknowledges that many components become harder to discover; these are the author's design recommendations, not universal requirements. [Flecs design guide](https://www.flecs.dev/flecs/DesignWithFlecs.html)

**How this could help; inference.** Components might eventually let a powered airplane, glider, and scenery windsock share only the state they need. However, one aircraft does not establish a need for an ECS. Splitting its tightly coupled flight state across many components could make the equations harder to follow. An ordinary `AircraftState` plus a function receiving controls, wind, and a timestep remains a useful comparison. An ECS also does not decide the physically correct ordering of force calculation and integration, or establish deterministic execution.

**Small experiment, not performed.** Implement the same toy update with plain structures and one library. Compare how easily a contributor can trace one control input to a force and resulting pose, add a glider, reset the scene, and detect stale references. Measure actual work only if entity counts become relevant; repository performance claims alone do not predict this workload.

### 2. Numerical building blocks: GLM and physical quantity types

**Question.** Which library responsibilities belong to geometric mathematics, and which belong to preventing unit and coordinate mistakes?

**Documented/source inspected.** GLM provides C++ graphics-oriented vectors, matrices, and quaternion facilities. Its manual documents configuration switches affecting coordinate conventions: `GLM_FORCE_LEFT_HANDED` changes the handedness used by relevant functions, while `GLM_FORCE_DEPTH_ZERO_TO_ONE` changes the projection depth range from the default negative-one-to-one convention. These settings concern the math API; they are not a complete definition of an aircraft's body axes or the simulator's world frame. [GLM source](https://github.com/g-truc/glm), [GLM configuration manual](https://github.com/g-truc/glm/blob/master/manual.md)

mp-units documents compile-time dimensional analysis, unit conversion, and quantity-kind checking for C++ physical quantities. Its introductory example defines a custom length unit and converts the resulting quantity into feet and metres. The project describes C++20 as sufficient for its functionality and links a separate compiler-support chapter; it is MIT-licensed. Its proposed standardization is an ongoing project direction, not evidence that these facilities already belong to the C++ standard library. [mp-units documentation](https://mpusz.github.io/mp-units/latest/)

**How this could help; inference.** A geometry library could handle attitude and camera transformations; a quantity library could help distinguish mass, force, time, and length when importing aircraft parameters. Those are separate protections. Correct dimensions do not catch a force pointing along the wrong body axis, an incorrect aerodynamic coefficient, or the use of a world-frame velocity where an air-relative velocity was intended. Explicit frame names and conversions would remain useful even with quantity types.

The interesting boundary is where typed simulation quantities become the plain numbers expected by a renderer, engine, file format, or foreign-function interface. No seamless GLM/mp-units combination was tested here. Adapters, compiler diagnostics, compile times, and compatibility with a future engine deserve observation before assuming the combination is convenient.

**Small experiment, not performed.** Express one force calculation with ordinary scalars and with quantity types. Deliberately substitute a mass for a force, then transform a known body-axis vector into world coordinates. Check which mistakes compilation catches and which require an expected-value check. Keep this independent of a language or engine decision.

### 3. Runtime scripting: Lua and sol2 for behaviors that exceed configuration

**Question.** When would changing behavior without recompiling be useful enough to justify embedding a scripting runtime?

**Documented/source inspected.** Lua 5.4 defines a host C API, protected calls, garbage collection, and standard libraries that include filesystem and operating-system operations. The host can open libraries individually rather than using `luaL_openlibs` to open all of them. Its instruction-count hook runs after a configured number of Lua instructions, but the manual explicitly limits this event to Lua execution: it is not a general timeout for a native function called from a script. These are documented embedding mechanisms, not a ready-made isolation policy. [Lua 5.4 reference manual](https://www.lua.org/manual/5.4/manual.html)

sol2 supplies a C++ binding layer with examples for exposing functions, tables, and user-defined types. Its safety documentation recommends protected function calls when errors must be inspected, describes object-lifetime issues across Lua and C++, and documents explicit safety configuration macros. The inspected documentation labels itself sol 3.2.3 despite the repository/library name “sol2”; examples and build configuration should be matched to the release actually evaluated. Type checks and protected calls do not impose a script time budget or make arbitrary host bindings harmless. [sol tutorial](https://sol2.readthedocs.io/en/latest/tutorial/all-the-things.html), [sol safety and configuration](https://sol2.readthedocs.io/en/latest/safety.html)

**How this could help; inference.** Scriptable lesson triggers, launch sequences, or changing wind scenarios might accelerate research. Aircraft mass and a table of propeller coefficients can remain ordinary validated data: an interpreter adds little when only values vary. A narrow behavioral API could expose simulation time and specific actions without exposing every internal object. Live replacement would still require a policy for existing script state, errors, references, and repeatability; adding Lua does not automatically provide usable hot reload.

**Small experiment, not performed.** Express a timed training prompt first as data and then as a script. Change it during a session and deliberately return the wrong value or raise an error. Observe whether the previous behavior remains usable, whether diagnostics identify the script location, and whether resetting reproduces the same scenario. Only then investigate callbacks inside the flight-physics loop, where allocation and execution-time variation have different consequences.

### 4. Dear ImGui and ImPlot: inspecting the airplane's internal state

**Documented capabilities.** Dear ImGui is an MIT-licensed C++ library for developer interfaces. Its core emits vertex buffers and drawing commands; platform and renderer backends connect input and graphics APIs. The project supplies backends including SDL, GLFW, OpenGL, Vulkan, Metal, and WebGPU. A simulator could therefore experiment with inspection panels without first building a complete editor. Integration still depends on the chosen host application and backend; bindings to other languages are separate integrations. The README explicitly prioritizes development tools and states that full internationalization and accessibility features are unsupported. This makes its suitability for a developer console a different question from its suitability for the eventual pilot-facing interface. [Dear ImGui repository and integration overview](https://github.com/ocornut/imgui)

ImPlot extends ImGui with interactive line, scatter, histogram, heatmap, and other plots, including zooming, panning, multiple axes, and custom data access. Its own documentation favors interactive application data over publication-quality export. Dense plots also expose concrete integration limits: default 16-bit drawing indices may require renderer vertex-offset support or 32-bit indices. Claims about handling large datasets are project guidance, not measurements on our simulator. [ImPlot features, integration, and limitations](https://github.com/epezent/implot)

**How this could help — inference.** A panel showing raw transmitter input, calibrated command, actual surface angle, airspeed, and individual force terms could make an unexpected turn understandable. A plot could reveal whether oscillation starts in the input path, an actuator approximation, or the flight equations. Human developers and AI-assisted debugging would share the same visible evidence. We could initially expose read-only values and add parameter controls only when a particular experiment needs them.

**Small experiment, not performed.** In a future compatible prototype, add one panel and a short rolling trace for an elevator step. Record simulation timestamps separately from display frames, label units, and compare the trace with the saved numerical output. Check input focus so typing in a diagnostic field does not also command the airplane. Compare frame time with the panel hidden and visible before treating the integration as lightweight.

### 5. Clang sanitizers: finding memory, arithmetic, and concurrency defects

**Documented capabilities.** AddressSanitizer instruments native code to detect errors including out-of-bounds access, use-after-free, and invalid frees. It requires compiler instrumentation and its runtime; Clang documents a typical slowdown around 2×, with additional memory costs. This is an upstream estimate, not a project benchmark. Debug information and symbolization help turn a runtime failure into a useful source-level report. [Clang AddressSanitizer documentation](https://clang.llvm.org/docs/AddressSanitizer.html)

UndefinedBehaviorSanitizer checks selected language-level faults such as signed integer overflow, misaligned access, and integer division by zero. Its default `undefined` group does **not** include every available check: floating-point division by zero and unsigned overflow are notable exclusions. Consequently, enabling UBSan does not establish that numerical simulation state remains finite or physically meaningful. [Clang UBSan checks and configuration](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)

ThreadSanitizer detects data races. Its documentation reports typical slowdowns of 5–15× and memory overhead of 5–10×, and lists specific supported operating systems and architectures. Those constraints make it a separate investigation if threaded input, loading, or simulation appears; they are not a reason to introduce concurrency now. [Clang ThreadSanitizer documentation](https://clang.llvm.org/docs/ThreadSanitizer.html)

**How this could help — inference.** If we explore C or C++, these tools could distinguish a damaged object or stale pointer from an aerodynamic bug. Aircraft replacement, resetting a flight, and controller disconnects are plausible places to exercise resource lifetimes. A race detector could later inspect handoffs between input and simulation. A clean run only tells us about the instrumented execution exercised: it does not prove correctness, replace checks on units and finite values, or validate lift and drag.

**Small experiment, not performed.** Run a short scripted load/reset/unload sequence in an instrumented native prototype, retaining the compiler version, command, input sequence, and symbolized diagnostics. Start with ASan/UBSan; consider a distinct TSan run only if there are threads to investigate. Compare ordinary and instrumented builds without interpreting sanitizer timing as normal flight performance. No sanitizer toolchain or implementation language is selected here.

### 6. libFuzzer and Hypothesis: exploring inputs beyond hand-written examples

**Documented capabilities.** LLVM's libFuzzer repeatedly calls a native target function with byte arrays, uses instrumented coverage to guide mutations, and retains interesting inputs in a corpus. Targets should tolerate malformed input, run quickly, and be as deterministic as possible. It can combine with sanitizers. A maintenance detail matters: its original authors have moved active development to Centipede; the documentation promises important bug fixes but asks users not to expect major new features. This is a useful established option to compare, rather than evidence that it is the only future fuzzing route. [LLVM libFuzzer documentation](https://llvm.org/docs/LibFuzzer.html)

Hypothesis supplies a different entry point for Python experiments: describe input strategies and properties with `@given`, then let the library generate cases. Strategies can generate dependent values, and tests work with pytest or unittest. This could suit an early Python numerical model or tooling layer without assuming the final simulator uses Python. [Hypothesis introduction](https://hypothesis.readthedocs.io/en/latest/), [quickstart and strategies](https://hypothesis.readthedocs.io/en/latest/quickstart.html)

**How this could help — inference.** Byte-oriented fuzzing could explore a future aircraft configuration reader with truncated files, unusual numbers, or malformed nesting. Property tests could explore calibration and rotation helpers with generated valid inputs. Candidate properties include preserving a vector's length under a normalized rotation within a tolerance, and keeping calibrated outputs within their documented limits. Preconditions matter: a zero-length quaternion needs an explicit policy, and arbitrary nonfinite numbers do not represent ordinary flight states.

The main research question is the quality of the property being checked. A parser that never crashes may still accept impossible mass, and a consistently incorrect formula can satisfy weak assertions. Physical reference cases and example-based regressions would remain useful alongside generated cases. Neither tool demonstrates realistic RC flight by itself.

**Small experiment, not performed.** Choose one small parser or calibration helper when it exists, define valid and invalid inputs, and introduce a deliberate defect in a disposable copy. Observe whether the generated cases expose it, then retain a readable regression example. Track which branches and numeric boundaries were actually exercised before expanding to whole-flight scenarios.

### 7. Virtual file access with PhysicsFS

**Question.** Could the same aircraft-loading code read a development folder and an archive without knowing how the content is stored?

**Documented capabilities.** PhysicsFS provides a virtual search path made from directories and archives, including ZIP files. Multiple sources appear as one hierarchy, with search order deciding which matching file is opened. Writes through its API are restricted to a designated write directory; `.` and `..` path elements are forbidden, and symbolic-link handling is configurable. These are library-level I/O rules, not restrictions on every other API in the process. Despite its name, PhysicsFS is a file-access library, not a physics engine. [PhysicsFS project overview](https://icculus.org/physfs/).

The API includes `PHYSFS_getRealDir`, which identifies the search-path directory or archive supplying a file. When several sources contain the same virtual path, it reports the first match, consistent with opening that path. This could help explain why a local aircraft texture overrides a bundled one. [PhysicsFS API reference](https://icculus.org/physfs/docs/html/physfs_8h.html).

**Possible project value.** A prototype could load `aircraft/trainer/model.glb` from loose files during editing and from an archive during distribution. An optional developer panel could display the resolved source, avoiding confusing override behavior. This investigates the implementation beneath asset loading; it does not choose the community package format discussed earlier.

**Limits and inference.** Rendering or audio libraries expecting native filenames might need custom read callbacks or memory-buffer loading to participate. A virtual path is not necessarily an operating-system path. Archive access does not validate the contents of an aircraft model or establish compatible units and coefficients. An engine's existing resource system may already solve the problem more simply. The overview mixes historical release information with platform listings; no current platform matrix was tested here.

**Small experiment, unperformed.** Load the same tiny asset from a directory and ZIP, then mount two different versions of its texture. Check precedence, reported provenance, missing-file diagnostics, and where settings are written. Compare integration effort with direct filesystem access before adding a virtual layer.

### 8. Library dependency resolution with vcpkg and Conan

**Question.** If a native prototype uses several libraries, how could contributors reproduce their versions and understand platform-specific build settings?

**Documented capabilities.** vcpkg's manifest mode records project dependencies and enables versioning and registries. Its versioning reference distinguishes baseline versions, minimum constraints, and explicit overrides. An override forces a particular version for a package already in the dependency graph. The reference also warns that a manifest without configured registries or a built-in baseline uses classic resolution and ignores versioning information. Merely having a manifest therefore does not establish the intended version behavior. [Manifest mode](https://learn.microsoft.com/en-us/vcpkg/concepts/manifest-mode), [versioning reference](https://learn.microsoft.com/en-us/vcpkg/users/versioning).

Conan profiles capture settings, options, tool requirements, and environment configuration. The documented automatic profile detector explicitly describes its output as a guess and advises maintaining one's own profiles for stability. Conan lockfiles capture dependency versions and recipe revisions; its tutorial shows that a lock created for one configuration can omit a dependency needed by another architecture. A strict lock then fails until the additional configuration is handled. [Conan profiles](https://docs.conan.io/2/reference/config_files/profiles.html), [Conan lockfiles](https://docs.conan.io/2/tutorial/versioning/lockfiles.html).

**Possible project value.** These tools could make a specific C/C++ library experiment easier to reproduce and upgrade deliberately. They address dependency resolution, complementing the earlier research on build commands and development containers. They do not select C++ for this project; an eventual language or engine may provide its own simpler dependency mechanism.

**Limits and inference.** Resolved source versions do not by themselves demonstrate identical binaries, ABI compatibility, working graphics drivers, or successful cross-compilation. Package recipes and upstream libraries are separate maintenance surfaces. A tiny vendored library may initially cost less effort than a package manager.

**Small experiment, unperformed.** Build one minimal program using a math and an audio library from two clean environments. Record resolved versions, compiler settings, download/build time, and any patches. Try one controlled dependency upgrade and restore the previous setup before judging either manager.

### 9. Audio implementation with miniaudio

**Question.** What code-level facilities would support a moving airplane's sound without requiring a full audio middleware stack?

**Documented capabilities.** miniaudio supplies low-level device callbacks and a higher-level engine. Its manual documents pitch control, spatialization, distance attenuation, and Doppler settings. Device initialization and shutdown belong outside the audio callback: starting or stopping the device from that callback can deadlock. Objects also have lifetime constraints: their addresses must remain stable, and copying the structures is not a supported ownership strategy. The manual explicitly does not guarantee ABI compatibility between releases, including bug fixes. [miniaudio programming manual](https://miniaud.io/docs/manual/index.html).

The upstream repository provides source and examples for the C library. This makes a small standalone sound experiment possible before integrating with a renderer; the repository's portability claims remain upstream claims until a selected backend runs on our hardware. [miniaudio repository](https://github.com/mackron/miniaudio).

**Possible project value.** A first implementation might feed aircraft position and velocity into spatialization while controlling a looping sound's pitch and volume from an approximate motor state. Audio code could consume a compact snapshot of simulation state rather than directly traversing mutable aircraft objects. That is a design possibility to test, not a chosen interface. An engine's built-in sound system remains an alternative with potentially less integration work.

**Limits and inference.** Pitch-shifting one recording does not establish a realistic propeller sound model, and throttle alone need not equal RPM. Real-time callback constraints make file loading, unpredictable work, and unsynchronized simulation reads poor candidates for the audio path. The exact threading and buffering arrangement would depend on the chosen API and prototype. Audio-device latency would require measurement separately from physics timing.

**Small experiment, unperformed.** Move one looping source past a stationary listener, varying RPM independently from speed. Listen for discontinuities during parameter changes and pause/resume; record backend, buffer settings, and CPU cost. Compare built-in engine audio with standalone miniaudio only if both paths remain plausible.

### 10. Background jobs and task scheduling with enkiTS

**Question.** When would moving work off the main thread help a small simulator, and what machinery would that introduce?

**Documented capabilities.** enkiTS is a task scheduler with C and C++ interfaces and a C++11 implementation requirement. Its examples cover partitioned task sets, dependencies, priorities, and tasks pinned to particular threads. A main-thread pinned task still needs that thread to service it; adding it to a queue does not independently execute main-thread work. The README distinguishes frequently tested Windows/Linux configurations from less frequently tested macOS and ARM Android, while describing iOS support as an expectation. These are upstream support statements, not local results. [enkiTS repository and examples](https://github.com/dougbinks/enkiTS).

**Possible project value.** Independent jobs such as decoding an image or preparing a terrain chunk could be candidates before parallelizing flight dynamics. A completed job might hand an immutable result to the main thread, which then creates the engine resource using its permitted thread. Whether a particular renderer allows this must be checked in that renderer's documentation; the scheduler supplies no such guarantee.

**Limits and inference.** A dependency graph expresses ordering only where dependencies are actually declared. It does not eliminate data races, manage arbitrary object lifetimes, or guarantee deterministic simulation. Small jobs can cost more to schedule and synchronize than to execute directly. For one airplane and a simple field, a serial update may remain the clearest and fastest adequate approach. If an engine already has worker jobs, a second scheduler could add competing threads and debugging work.

**Small experiment, unperformed.** Measure a noticeable asset-preparation pause in a serial prototype, then move only that preparation into one job. Keep GPU resource creation on the appropriate thread. Compare frame stalls and total loading time, test closing the scene while the job is unfinished, and verify that the flight-state trace remains unchanged. Retain concurrency only if its measured benefit justifies the added lifetime and synchronization logic.

## Ten open-source projects to study for code inspiration

Fifth research pass, **2026-10-05**: ten additional projects selected for specific, readable implementation ideas. This pass follows source files and functions as well as project documentation. Source inspection confirms the described code exists; it does not establish runtime behavior, performance, or suitability for RC flight. No project was built or run. Lessons and experiments are possibilities, not dependencies or architecture decisions. Branch links can change; commit-pinned links preserve the inspected revisions where recorded.

- [1. SuperTuxKart: recorded ghosts and a camera with its own state](#1-supertuxkart-recorded-ghosts-and-a-camera-with-its-own-state)
- [2. Neverball: a compact input-to-simulation-to-presentation reading exercise](#2-neverball-a-compact-input-to-simulation-to-presentation-reading-exercise)
- [3. Pioneer: explicit coordinate frames and terrain relative to the camera](#3-pioneer-explicit-coordinate-frames-and-terrain-relative-to-the-camera)
- [4. Rigs of Rods: tracing an editable vehicle definition into physics and graphics](#4-rigs-of-rods-tracing-an-editable-vehicle-definition-into-physics-and-graphics)
- [5. VDrift: inspectable input processing and vehicle force state](#5-vdrift-inspectable-input-processing-and-vehicle-force-state)
- [6. OpenRocket: editable component trees and transparent mass properties](#6-openrocket-editable-component-trees-and-transparent-mass-properties)
- [7. Godot TPS demo: traceable input, camera, and settings code](#7-godot-tps-demo-traceable-input-camera-and-settings-code)
- [8. Endless Sky: readable vehicle definitions and helpful loading diagnostics](#8-endless-sky-readable-vehicle-definitions-and-helpful-loading-diagnostics)
- [9. OpenTTD: saved-state evolution and rebuilding derived state](#9-openttd-saved-state-evolution-and-rebuilding-derived-state)
- [10. TinyRenderer: a small codebase for understanding the first visible airplane](#10-tinyrenderer-a-small-codebase-for-understanding-the-first-visible-airplane)

### 1. SuperTuxKart: recorded ghosts and a camera with its own state

**Source-inspected finding.** SuperTuxKart provides a concrete replay-reading trail: start with [`ReplayRecorder::update()`](https://github.com/supertuxkart/stk-code/blob/master/src/replay/replay_recorder.cpp), which stores timestamps, positions, visual rotations, and additional kart state; follow [`ReplayPlay`](https://github.com/supertuxkart/stk-code/blob/master/src/replay/replay_play.cpp) into ghost creation and reset; then inspect [`GhostKart::update()`](https://github.com/supertuxkart/stk-code/blob/master/src/karts/ghost_kart.cpp). The ghost interpolates positions between recorded samples and uses quaternion spherical interpolation for rotation. Playback handles the final sample explicitly. This is implemented state playback, not evidence that rerunning old control inputs reproduces identical physics.

A separate reading trail is [`CameraNormal::moveCamera()` and `update()`](https://github.com/supertuxkart/stk-code/blob/master/src/graphics/camera/camera_normal.cpp). The camera has configurable position/rotation smoothing, mode-dependent settings, and its own transition state. These functions show why resetting a vehicle and resetting its view deserve separate attention.

**How this could help.** A translucent recorded airplane could illustrate a landing approach or make two tuning runs visually comparable. Recording poses would keep that visualization useful while the flight model changes. For diagnosing physics, the trace could additionally retain controls, wind, parameter versions, and simulation state; the kart implementation does not establish which aircraft quantities are sufficient.

**Limits and reuse.** Chase-camera behavior designed for a road vehicle will not automatically suit an observer standing on an RC field. The inspected replay source headers specify GPL-3.0-or-later; assets and other dependencies need their own inspection before reuse. Reading its separation of responsibilities does not require adopting its renderer or race framework.

**Small experiment, not performed.** Record a short synthetic airplane circuit as time/position/orientation samples, play it at several rendering rates, and reset halfway through. Observe ghost continuity and camera settling separately before adding any replay UI.

### 2. Neverball: a compact input-to-simulation-to-presentation reading exercise

**Source-inspected finding.** Neverball is a useful non-flight example because its core interaction is small enough to trace. In [`ball/game_server.c`](https://github.com/Neverball/neverball/blob/master/ball/game_server.c), a single input structure stores tilt, response, view rotation, and camera selection. Public setters lead into that structure; `game_step()` advances gameplay, while `game_update_view()` handles the view. This is a concrete place to inspect how a mouse or stick becomes game intent without making every caller manipulate world state.

The other side is [`ball/game_client.c`](https://github.com/Neverball/neverball/blob/master/ball/game_client.c). `game_client_sync()` consumes queued commands, optionally writes them to a demo file, and applies them through `game_run_cmd()`. Rendering uses interpolation data through `game_client_blend()` and `game_client_draw()`. The names “server” and “client” describe a useful implementation boundary here; the inspected path by itself does not establish online multiplayer support.

**How this could help.** We could trace a future RC stick sample through normalized command, aircraft update, and visible pose just as explicitly. Camera selection and camera motion could be observable inputs of their own. This makes a small program easier for humans and coding agents to inspect: a symptom such as “moving the view changes the aircraft” has a short set of functions to examine.

**Limits and reuse.** Neverball's floor-tilting mechanics, response smoothing, and camera-relative behavior are gameplay choices, not RC control laws. Its global state is also something to evaluate rather than automatically copy. The project's [licensing file](https://github.com/Neverball/neverball/blob/master/LICENSE.md) states GPL-2.0-or-later generally and lists component exceptions, including GPLv3 easings and separately licensed libraries/fonts.

**Small experiment, not performed.** Sketch an equally short control-to-pose trace in any candidate prototype. Feed identical airplane commands while changing the camera, then compare aircraft state. Add a command queue only if recording or separating updates makes it useful.

### 3. Pioneer: explicit coordinate frames and terrain relative to the camera

**Source-inspected finding.** Pioneer's [`src/Frame.h`](https://github.com/pioneerspacesim/pioneer/blob/master/src/Frame.h) makes reference frames explicit: parent/child relationships, position, orientation, velocity, rotating-frame state, and transforms relative to another frame. It separately exposes interpolated transforms for drawing between physics ticks. [`Body::SwitchToFrame()`](https://github.com/pioneerspacesim/pioneer/blob/master/src/Body.cpp) converts velocity, position, and orientation during a frame change rather than merely changing a parent identifier. These are useful code entry points for examining what a coordinate conversion actually must preserve.

A complementary graphics example is [`GeoPatch::RenderImmediate()`](https://github.com/pioneerspacesim/pioneer/blob/master/src/GeoPatch.cpp): it subtracts camera position from the patch centroid in `vector3d`, builds a double-precision transform, then converts the result to `matrix4x4f` for rendering. [`vector3.h`](https://github.com/pioneerspacesim/pioneer/blob/master/src/vector3.h) confirms that `vector3d` stores doubles. The source demonstrates a particular precision boundary; it does not prove all distant-scene artifacts are eliminated.

**How this could help.** Even a small field has aircraft-local, world, and camera coordinates. Naming those relationships explicitly can prevent force-direction and visual-orientation mistakes. If scenery eventually expands, Pioneer's camera-relative rendering is a concrete alternative to blindly using enormous single-precision world coordinates.

**Limits and collaboration.** Hierarchical astronomical frames and planetary terrain would be substantial extra machinery for one RC field. The [project README](https://github.com/pioneerspacesim/pioneer) identifies GPLv3 and explicitly rejects materially AI-generated contributions. That is an upstream contribution policy to respect if approaching its maintainers, not a rule for this repository; its stated legal reasoning is not independently evaluated here.

**Small experiment, not performed.** Draw the same small aircraft/field arrangement near the origin and at a large translated coordinate, comparing ordinary and camera-relative transforms. Keep a simple local origin unless the experiment reveals an actual precision problem.

### 4. Rigs of Rods: tracing an editable vehicle definition into physics and graphics

**Evidence: source and official developer documentation inspected; no simulator run.** Rigs of Rods is especially interesting as a worked example of user-authored vehicle data. Its aircraft guide describes wing segments bounded by eight structural nodes, with airfoil data and control-surface behavior. This makes it possible to follow a concrete aircraft part from a text definition into a simulated object. [Aircraft and aerodynamics guide](https://docs.rigsofrods.org/vehicle-creation/aircraft-and-aerodynamics/)

**Code worth reading.** In `source/main/resources/rig_def_fileformat/RigDef_Parser.cpp`, `ProcessCurrentLine()` dispatches the wings section to `ParseWing()`. That function reads node references, texture coordinates, surface type, hinge-related chord position, deflection limits, airfoil name and an optional efficacy coefficient into a `Wing` record. `GetArgWingSurface()` recognizes ailerons, elevators, rudders, elevons and other combinations. This is a useful example of expressing physical and visual relationships explicitly in content data. [Parser implementation](https://github.com/RigsOfRods/rigs-of-rods/blob/master/source/main/resources/rig_def_fileformat/RigDef_Parser.cpp)

The developer overview also points to `GfxScene::BufferSimulationData()` and actor simulation buffers. It describes separating simulation updates from visual mesh updates, while explicitly acknowledging legacy coupling and incomplete separation. That honesty makes the architecture useful to study as an evolving codebase. [Codebase overview](https://developer.rigsofrods.org/d4/d38/_codebase_overview_page.html)

**Potential use and limits.** We could borrow the idea of tracing each visible control surface back to its physical definition and exposing that relationship in a debug view. The node-and-beam model itself is substantially more elaborate than our first airplane needs; this research does not establish its accuracy for small RC aircraft. The inspected parser carries a GPL-3.0 notice; that is relevant if considering code reuse, independently of learning from its organization.

**Small experiment, not performed:** sketch a single wing record and trace which values a simple physics model and a hinge animation would each consume. Start with a rigid airplane; investigate structural deformation only if a later question warrants it.

### 5. VDrift: inspectable input processing and vehicle force state

**Evidence: source inspected; no driving session or controller test.** VDrift offers code inspiration outside aviation: a driving simulator must translate imperfect physical controls into continuous commands and make complicated vehicle forces understandable. Its README identifies it as an open-source driving simulation under GPL v3. [Project repository](https://github.com/VDrift/vdrift)

**Code worth reading.** `src/carcontrolmap.cpp` keeps configuration loading and saving alongside an explicit processing path. `HandleAxis()` applies inversion, deadzone, gain and exponent shaping; `HandleButton()` distinguishes edge-triggered actions from values ramped over time. `ProcessInput()` receives joystick, keyboard and mouse inputs before applying driving-specific steering processing. These are concrete examples of where to inspect a transformation when a controller feels wrong. They are not evidence that a particular RC transmitter works. [Input implementation](https://github.com/VDrift/vdrift/blob/master/src/carcontrolmap.cpp)

`src/physics/cartirebase.h` defines `CarTireState` with friction, camber, slip, slip angle and force/moment fields. `cartire1.h` documents a force-model interface in terms of normal load and wheel/surface velocities. The interesting design is the inspectable intermediate state: a physics result can retain explanatory quantities instead of returning only one opaque force vector. [Tire state](https://github.com/VDrift/vdrift/blob/master/src/physics/cartirebase.h), [tire interface](https://github.com/VDrift/vdrift/blob/master/src/physics/cartire1.h)

**Potential use and limits.** An equivalent airplane debug record might preserve local airspeed, angle of attack, coefficient lookup results and resulting forces for each surface. VDrift's car-specific steering and tire coefficients do not establish suitable RC behavior. Some mapped actions use separate positive channels clamped to 0–1, so signed elevator/aileron commands would need deliberate treatment. The inspected tire interface carries a GPL-3.0-or-later notice.

**Small experiment, not performed:** draw the raw-axis-to-elevator transformation and a surface-force diagnostic record. Check where transmitter expo could combine with simulator expo, and whether a surprising force can be explained from the recorded values.

### 6. OpenRocket: editable component trees and transparent mass properties

**Evidence: source and project documentation inspected; no model built or simulated.** OpenRocket is a model-rocket design and simulation application. Its useful connection to RC airplanes is the relationship between an editable assembly, measured component properties and computed mass behavior. The project also provides 3D visualization and simulation plots, according to its own documentation. [Project repository](https://github.com/openrocket/openrocket)

**Code worth reading.** `core/src/main/java/info/openrocket/core/rocketcomponent/RocketComponent.java` implements a component tree, including child insertion checks and change events. Its mass and center-of-gravity override setters distinguish a specified override value from whether that override is active. Changes can emit mass-specific events, separating their meaning from purely visual edits. This is a concrete reference for representing measured values alongside geometric estimates. [Component implementation](https://github.com/openrocket/openrocket/blob/unstable/core/src/main/java/info/openrocket/core/rocketcomponent/RocketComponent.java)

`core/.../masscalc/MassCalculator.java` exposes separate structural, launch, burnout and motor mass calculations. The main calculation path assembles components and computes moments of inertia. One particularly useful caution appears in the same file: the `getCMAnalysis()` documentation warns that its component-map approach mishandles instancing. Repeated parts need identities that distinguish individual instances from shared component definitions. [Mass calculator](https://github.com/openrocket/openrocket/blob/unstable/core/src/main/java/info/openrocket/core/masscalc/MassCalculator.java)

**Potential use and limits.** Moving an RC battery or adding ballast could update total mass and center of gravity through a small assembly model. This could begin as a few named masses rather than a full aircraft editor. Rocket-specific aerodynamics and propellant behavior do not validate airplane physics, and the inspected `unstable` branch can change. OpenRocket's license is GPL-3.0-or-later with an additional permission concerning packaged non-compilable data files. [License](https://github.com/openrocket/openrocket/blob/unstable/LICENSE.TXT)

**Small experiment, not performed:** describe a fuselage, battery and two identical wing-mounted masses; move only one mass. Hand-check total mass and center of gravity, and confirm that the two instances remain distinguishable.

### 7. Godot TPS demo: traceable input, camera, and settings code

**Question.** What can a complete playable demonstration teach us about connecting input, camera behavior, and user settings without inventing an editor framework?

**Source inspected.** In the Godot third-person shooter demo, `player/player_input.gd` collects movement actions separately from camera actions. Gamepad camera movement is scaled by frame time, while mouse motion uses relative event displacement. `rotate_camera` applies yaw, orthonormalizes the camera base, and clamps pitch. Local multiplayer authority determines whether a player's camera and input processing are active. These are concrete implementation choices in a shooter, not established RC input conventions. [Input and camera implementation](https://github.com/godotengine/tps-demo/blob/a82f15448e9b015440d3bbdf5e10801b260c4e9f/player/player_input.gd).

`menu/settings.gd` loads a user configuration file, fills missing entries from a defaults dictionary, and applies graphics settings separately. It also contains a documented limitation around re-enabling shadows in the menu: useful examples can include imperfect behavior worth investigating. [Settings implementation](https://github.com/godotengine/tps-demo/blob/a82f15448e9b015440d3bbdf5e10801b260c4e9f/menu/settings.gd).

**Possible project lesson.** A small RC prototype could make its input-to-camera path similarly easy to trace while keeping airplane control channels separate. A settings defaults table could let experimental options appear gradually without requiring users to discard old settings. These ideas can transfer even if we never choose Godot.

**Limits.** Chase-camera aiming differs substantially from a stationary RC pilot following a distant aircraft. Mouse displacement and transmitter stick deflection also have different semantics. The repository identifies engine-version branches and warns about a large first import. Its license file separates MIT-style code terms from CC-BY 3.0 assets/music and records additional material provenance; it is not a single uniform asset license. [Demo README](https://github.com/godotengine/tps-demo), [license record](https://github.com/godotengine/tps-demo/blob/a82f15448e9b015440d3bbdf5e10801b260c4e9f/LICENSE.md).

**Small experiment, unperformed.** In a disposable tiny scene, trace keyboard, gamepad, and mouse events to camera changes. Replace the avatar with an airplane blockout, fix the camera at a pilot position, and compare the amount of code that remains useful.

### 8. Endless Sky: readable vehicle definitions and helpful loading diagnostics

**Question.** How does an established content-rich game turn editable vehicle descriptions into runtime objects?

**Source inspected.** Endless Sky's ship-authoring guide describes its text-based ship definitions and editing workflow. In `source/Ship.cpp`, `Ship::Load` reads attributes and variant relationships; `FinishLoading` fills unspecified values from base models. The code also emits diagnostics for unsupported or unrecognized attributes. This provides an actual implementation to study alongside the contributor-facing guide, rather than inferring the loader from screenshots or modding claims. [Ship-authoring guide](https://github.com/endless-sky/endless-sky/wiki/CreatingShips), [ship loading and finalization](https://github.com/endless-sky/endless-sky/blob/aa2f75faa74da55bd6689822cc0592cdba10bd70/source/Ship.cpp).

`DataNode::PrintTrace` walks parent nodes to explain context. `DataNode::Value(int)` reports missing or nonnumeric tokens but returns zero after failure. That fallback is important to notice: convenient recovery in one game's data pipeline would need careful reconsideration for aircraft mass or dimensions. [DataNode diagnostics and conversion](https://github.com/endless-sky/endless-sky/blob/aa2f75faa74da55bd6689822cc0592cdba10bd70/source/DataNode.cpp).

**Possible project lesson.** Follow one definition from a human-readable document through parsing, reference resolution, and final runtime construction. A trainer variant could eventually inherit visual settings while explicitly changing its propulsion data. Good errors could identify both the parameter and the containing aircraft/component, helping contributors and AI-generated edits alike.

**Limits.** Space-game movement and balance values are not aerodynamic references. Inheritance can obscure the effective value and its origin; readable source files alone do not make a complex override system understandable. We need not adopt this custom text syntax. The repository copyright inventory identifies GPL-3+ as the general license and lists separate asset terms and exceptions. [Copyright inventory](https://github.com/endless-sky/endless-sky/blob/aa2f75faa74da55bd6689822cc0592cdba10bd70/copyright).

**Small experiment, unperformed.** Trace one base ship and variant on paper, then sketch a minimal aircraft loader with explicit errors for missing mass. Compare flat data with inheritance using only two aircraft before deciding whether shared defaults actually simplify authoring.

### 9. OpenTTD: saved-state evolution and rebuilding derived state

**Question.** What can a long-lived simulation game's loading code teach us about changing a model without confusing persisted state and runtime caches?

**Source inspected.** OpenTTD's `src/saveload/afterload.cpp` has an explicit `AfterLoadGame` phase containing version-dependent conversions. A separate `InitializeWindowsAndCaches` function resets windows and refreshes derived data. Its comment explains that this separation followed bugs caused by initializing those systems before conversions were complete. There are also deliberate early rebuilds for structures needed during conversion, illustrating that the dependency order matters more than an absolute rule to rebuild everything last. [Post-load conversion and initialization source](https://github.com/OpenTTD/OpenTTD/blob/5fcaa0982deb5fa1fb2afea1312bd79cea255a96/src/saveload/afterload.cpp).

The official source reference exposes the broader save/load machinery and its callers, giving a navigation path from this concrete example into serialization and error handling. These are mature game systems to read selectively; their size is not a target for our first prototype. [Official save/load source reference](https://docs.openttd.org/source/d0/d47/saveload_8cpp).

**Possible project lesson.** If saved flights eventually become useful, an aircraft pose, a user setting, and a renderer's cached transform might deserve different treatment. A load operation could first restore and interpret persistent values, then construct the runtime resources needed to display and continue the flight. The same question can help clarify a reset operation even before file saving exists.

**Limits.** Loading an old file does not guarantee that a changed flight model will continue the same trajectory. Compatibility for data, simulation behavior, and replay are distinct questions. We have no reason to commit to long-term saved-flight compatibility now. OpenTTD publishes GPL version 2 license text with stated exceptions for some third-party modules; consult the actual files if code reuse becomes a concrete proposal. [License file](https://github.com/OpenTTD/OpenTTD/blob/5fcaa0982deb5fa1fb2afea1312bd79cea255a96/COPYING.md).

**Small experiment, unperformed.** Define two toy versions of a saved aircraft state, add one field with an explicit default, and rebuild a visual transform after loading. Compare the result with a fresh initialization and document which quantities are saved versus recomputed.

### 10. TinyRenderer: a small codebase for understanding the first visible airplane

**Question.** Can a compact educational renderer make graphics failures easier to reason about without committing us to building our own rendering engine?

**Documented scope.** TinyRenderer is a software-rendering course. Its README explicitly describes producing an image from a triangulated model and textures, with no graphical interface. The author's objective is to explain graphics-pipeline ideas, not to supply a GPU application framework. [TinyRenderer course and repository](https://github.com/ssloy/tinyrenderer).

**Source inspected.** `main.cpp` loads models, constructs a shader, processes face vertices, calls the rasterizer, and saves a framebuffer image. `our_gl.cpp` contains camera/view/projection setup and rasterization in a short file: perspective division, screen-space bounds, barycentric coordinates, depth testing, and fragment shading are visible together. It also discards triangles using an area/direction test. These are concrete reading entry points for tracing why a mesh is invisible or incorrectly oriented. [Main rendering path](https://github.com/ssloy/tinyrenderer/blob/97eb7a480e762285899a93c5d21e70a79e60782e/main.cpp), [transform and rasterization code](https://github.com/ssloy/tinyrenderer/blob/97eb7a480e762285899a93c5d21e70a79e60782e/our_gl.cpp).

**Possible project lesson.** A handful of triangles forming an airplane could be a useful teaching asset for contributors: trace a wing vertex from model space to its pixel and explain the camera convention. This could make later AI-generated graphics changes easier to review regardless of which renderer we ultimately use.

**Limits.** A static software-rendered image does not satisfy the interactive simulator goal by itself. This implementation's simplified projection and clipping behavior should not become a reference for every production graphics API. Its compactness is educational, not evidence of adequate real-time performance. The source carries permissive zlib-style terms; bundled sample-model provenance would need separate attention before reuse. [Source license](https://github.com/ssloy/tinyrenderer/blob/97eb7a480e762285899a93c5d21e70a79e60782e/LICENSE.txt).

**Small experiment, unperformed.** Use an original low-detail airplane mesh, render a few known poses, then deliberately reverse triangle winding or change a transform. Explain the resulting image from the inspected code. Keep this as a learning exercise if an existing engine already serves the interactive prototype better.

## Ten investigations to guide early prototype experiments

Sixth research pass, **2026-10-05**: ten questions chosen to connect the growing knowledge base to small, informative prototype experiments. The emphasis is on understandable starting conditions, behavior at model boundaries, player-visible response, and evidence we can compare. Some questions deepen earlier broad topics; each investigates a specific unresolved mechanism. None of the experiments was performed, and no feature, tool, accuracy target, or implementation approach is required by this section.

- [1. Trimmed starting states and resets that reveal the aircraft model](#1-trimmed-starting-states-and-resets-that-reveal-the-aircraft-model)
- [2. What happens when flight leaves the available airfoil polar?](#2-what-happens-when-flight-leaves-the-available-airfoil-polar)
- [3. Ground effect as an aerodynamic question separate from wheel contact](#3-ground-effect-as-an-aerodynamic-question-separate-from-wheel-contact)
- [4. Stick-to-photon latency: measure the whole response path](#4-stick-to-photon-latency-measure-the-whole-response-path)
- [5. Lost focus and disconnected controls: what should the flight do?](#5-lost-focus-and-disconnected-controls-what-should-the-flight-do)
- [6. Distant-aircraft rendering: preserve a tiny moving silhouette](#6-distant-aircraft-rendering-preserve-a-tiny-moving-silhouette)
- [7. Numerical convergence: separating integration error from flight-model error](#7-numerical-convergence-separating-integration-error-from-flight-model-error)
- [8. Self-describing experiment traces with MCAP](#8-self-describing-experiment-traces-with-mcap)
- [9. Repeatable visual evidence for human and AI code review](#9-repeatable-visual-evidence-for-human-and-ai-code-review)
- [10. Sensitivity analysis to decide what is worth researching next](#10-sensitivity-analysis-to-decide-what-is-worth-researching-next)

### 1. Trimmed starting states and resets that reveal the aircraft model

**Evidence — documented solver and implementation inspected.** JSBSim's `FGTrim` searches for attitude and control settings that satisfy a requested steady flight condition. It iteratively reduces selected acceleration residuals; its longitudinal implementation adjusts angle of attack, throttle, and pitch trim. The API exposes tolerances, iteration limits, reports, and failure status. Its documentation explicitly warns that the requested speed, configuration, mass, or center of gravity can make a trim impossible. A configurable fallback changes flight-path angle when available thrust cannot satisfy the original request. [JSBSim FGTrim documentation and source](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGTrim.html).

**How this could help — inference.** A reset in midair could begin at a reproducible operating point instead of an arbitrary combination of speed, attitude, and throttle. That would make initial control experiments easier to interpret: immediate acceleration might otherwise come from the spawn condition rather than a change in the model. This idea does not require adopting JSBSim; a small longitudinal force-and-moment balance could answer the initial question.

There are useful distinctions to preserve. Numerical equilibrium does not demonstrate that the airplane returns to it after a disturbance, nor validate the aerodynamic coefficients. Initialization also differs from continuously applying an autopilot. If the user starts moving the controls, the ordinary flight equations should determine what follows. A solver's fallback glide should be reported as a different starting condition, not presented as successful level flight. Radio trim and a simulator's initialization offset also need an explicit relationship before both are applied.

**Small experiment — not performed.** For one candidate airplane, compare a hand-chosen spawn with three solved starting speeds. Record residual accelerations, control limits, and ten seconds of motion with controls held fixed. Change the center of gravity and repeat. Include an intentionally impossible condition and check that failure remains visible.

### 2. What happens when flight leaves the available airfoil polar?

**Evidence — documentation and source inspected.** AirfoilPreppy provides a concrete offline example of extending limited airfoil data to ±180 degrees with the Viterna method. Its documentation separately describes rotational corrections intended for wind-turbine analysis. These are distinct operations, not a general guarantee of stalled-aircraft accuracy. [AirfoilPreppy documentation](https://github.com/NLRWindSystems/AirfoilPreppy/blob/master/docs/documentation.rst).

The `Polar.extrapolate` implementation accepts maximum drag, a minimum drag floor, and the number of additional samples. Its optional `AR` argument is defined as rotor radius divided by chord at 75% radius; supplying it estimates maximum drag. That definition must not be silently replaced with the familiar fixed-wing aspect ratio. The source also contains separate angle intervals and an asymmetry adjustment, useful reminders that a complete-looking curve can contain explicit modeling assumptions. [Extrapolation implementation](https://github.com/NLRWindSystems/AirfoilPreppy/blob/master/airfoilprep/airfoilprep.py).

**How this could help — inference.** Earlier research established that XFOIL and measured polars have limited envelopes. This investigation addresses the runtime boundary: an RC airplane can encounter angles outside that envelope during launch mistakes, inverted flight, or recovery. We could keep measured, computed, and extrapolated intervals distinguishable in the data and diagnostics. Simply holding the last coefficient constant is also an assumption; drawing a smooth extension does not make it measured evidence.

**Limits.** An angle-indexed static extension alone cannot encode history-dependent stall, spin dynamics, changing local flow across a finite wing, or propwash effects. Wind-turbine corrections are not automatically suitable for a fixed RC wing. Pitching moment needs its own scrutiny rather than being inferred from plausible lift and drag.

**Small experiment — not performed.** Extend one documented polar using two explicit assumptions, sweep the entire angle range, and plot coefficients and boundary continuity. Feed the alternatives into the same scripted recovery and mark every timestep outside the original data envelope. Compare sensitivity without declaring either result validated.

### 3. Ground effect as an aerodynamic question separate from wheel contact

**Evidence — instructional reference and measured research.** The FAA describes the nearby surface changing wing upwash, downwash, and vortices. Its explanation distinguishes increased lift at fixed angle of attack from reduced induced drag at fixed lift coefficient. It relates the magnitude to wing height relative to span. These are useful qualitative checks; the handbook's example percentages are not a calibrated lookup table for every RC airplane. [FAA Pilot's Handbook, ground-effect discussion in Chapter 5](https://www.faa.gov/sites/faa.gov/files/uas/recreational_fliers/where_can_i_fly/airspace_101/pilot_handbook.pdf).

NASA's 1961 wind-tunnel investigation tested thick, highly cambered rectangular wings with aspect ratios 1, 2, 4, and 6. It found increasing lift-curve slope and decreasing induced drag near the ground, along with configuration-dependent stability observations. This is experimental evidence for those wings, not evidence that their coefficients transfer directly to a lightweight trainer at another Reynolds number. [NASA TN D-926 and report download](https://ntrs.nasa.gov/citations/19980231058).

**How this could help — inference.** Landing float and changes during liftoff could be investigated independently of tire friction, suspension, and collision response. A candidate model could vary an aerodynamic correction with wing height while leaving the ground-contact model separate. Using the aircraft origin or wheel clearance as the aerodynamic height without considering wing placement would confound a high-wing/low-wing comparison. A universal upward spring above the runway would conceal which aerodynamic effect it approximates.

**Limits.** Any first correction would need a declared scope, such as approximately level wings over a flat surface. Banks, slopes, rough terrain, wingtip proximity, tail interaction, and separated flow raise further questions. No source here establishes an RC-specific implementation.

**Small experiment — not performed.** Evaluate fixed-angle and fixed-lift cases separately across several height/span ratios, checking convergence toward the free-air model. Then compare identical landing approaches with the correction enabled and disabled while logging aerodynamic and contact forces separately.

### 4. Stick-to-photon latency: measure the whole response path

**Documented finding.** NVIDIA's LDAT uses a luminance sensor to measure input-to-visible-response latency. Its page describes vendor-independent GPU compatibility, but lists Windows 10 and a particular driver under requirements; that is not evidence that its software runs on every platform. More accessible for source inspection, **OSLTT** publishes desktop software, device firmware, and circuit diagrams. Its README describes Windows installation and Visual Studio builds. These are external measurement approaches, unlike timings that end when the application submits a frame. Neither source establishes direct support for an RC transmitter's analog-stick signal. [LDAT documentation](https://developer.nvidia.com/nvidia-latency-display-analysis-tool), [OSLTT repository](https://github.com/OSRTT/OSLTT).

**Why investigate this separately from profiling?** Our inference is that a responsive-looking frame counter can hide delay across transmitter sampling, USB delivery, application polling, physics scheduling, rendering queues, display scanout, and pixel response. A diagnostic square that changes when the application receives input measures a different endpoint from an elevator moving, and both differ from the aircraft beginning to rotate under aerodynamic forces. Those distinctions could prevent us from “fixing” a realistic aircraft response by changing unrelated rendering code.

**Possible measurement design.** Begin with a high-frame-rate video containing both a visibly marked physical stick and the display. Define a repeatable stick-position threshold and visible-response threshold, then record many trials. A later electrical trigger plus light sensor could narrow measurement uncertainty. Record camera frame interval, display refresh setting, input device, rendering settings, sample count, and latency distribution; a camera recording provides a bounded estimate, not arbitrary millisecond precision. Software event timestamps could help locate delay without replacing the external measurement.

**Small experiment, not performed.** Compare an input-indicator patch, direct control-surface animation, and aircraft roll response in the same minimal scene. Change only one timing setting between runs. This could identify where further investigation is useful without imposing a latency target or purchasing specialized hardware.

### 5. Lost focus and disconnected controls: what should the flight do?

**Documented finding.** SDL distinguishes keyboard-focus loss, window hiding/minimizing, joystick removal, and gamepad removal as separate events. Its background-joystick hint disables joystick/gamecontroller input events while the application is in the background by default, with an option to enable them. An application therefore needs to understand event delivery independently from whether its simulation continues. [SDL event types](https://wiki.libsdl.org/SDL3/SDL_EventType), [background-input hint](https://wiki.libsdl.org/SDL3/SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS).

The browser introduces another distinction: focus loss does not necessarily mean that a page is hidden. MDN documents `visibilitychange`, widespread suspension of `requestAnimationFrame()` in hidden tabs, and background timer throttling. These are browser scheduling behaviors; they do not define the correct flight state when the player returns. [Page Visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API).

**Possible project value.** This is a small interaction question with consequences for early prototypes. If a transmitter disappears while the elevator is held back, retaining the last input, centering the surfaces, cutting throttle, pausing the flight, and resetting the airplane produce very different experiences. Centered elevator and zero throttle also have different meanings: “neutralize all axes” is ambiguous for a throttle channel. No single behavior is established here, and a future shared session might need a different policy from solo practice.

**Open implementation questions.** Could input availability and flight state be represented separately, so reconnecting does not silently resume flight? Would a visible paused state plus an explicit resume action be understandable? Should resuming require low throttle, or merely display the current channel positions? These are alternatives to compare, not new requirements. Any elapsed-time accumulator also needs examination after a long suspension, so returning to a tab does not accidentally simulate the whole absence in one burst.

**Small experiment, not performed.** Hold a nonzero command, switch windows, hide the tab if applicable, unplug, reconnect with throttle high, and resume. Log each transition and resulting control values. Repeat with keyboard input and record which behavior feels predictable.

### 6. Distant-aircraft rendering: preserve a tiny moving silhouette

**Documented finding.** Godot's antialiasing guide makes a useful distinction: MSAA addresses geometric edges but does not solve specular aliasing; TAA combines information across frames and can blur or leave trails behind moving objects. Supersampling addresses several aliasing sources at a much higher rendering cost. These are documented properties of the described techniques and implementation, not measured results for our aircraft. Renderer availability also varies: in the inspected Godot 4.5 documentation, TAA requires Forward+, while MSAA is available across renderers. [Godot 4.5 antialiasing guide](https://docs.godotengine.org/en/4.5/tutorials/3d/3d_antialiasing.html).

**A concrete scale question.** Perspective projection relates field of view, depth, and screen size; Microsoft's projection documentation provides the matrix construction. For a centered, broadside span `b`, camera depth `d`, horizontal field of view `f`, and image width `W`, our geometric derivation is `pixels = W × b / (2 × d × tan(f/2))`. A 1.2 m span at 100 m occupies about 20 pixels in a 1920-pixel image with a 60-degree horizontal field of view; at 300 m, about 6.7 pixels. This assumes the span is parallel to the image plane and ignores perspective variation across it. Banking can make the relevant silhouette thinner still. [Perspective projection matrix](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bb281728%28v%3Dvs.85%29).

**Possible project value.** A beautiful close-up model may be difficult to follow in normal RC ground-view flight. At these sizes, marking detail, specular highlights, thin wing geometry, and temporal history deserve separate evaluation. A still screenshot cannot reveal flicker or trails. Enlarging the aircraft visually would change apparent scale, so that would be a separate experiment rather than an invisible rendering correction.

**Small experiment, not performed.** Render one scripted fly-by at several distances, bank angles, backgrounds, and native resolutions. Compare no antialiasing, MSAA, and an available temporal method with identical geometry and camera motion. Inspect moving silhouette continuity and orientation recognition alongside frame time; do not select a winner from close-up image quality alone.

### 7. Numerical convergence: separating integration error from flight-model error

**Question.** If an airplane oscillates or gains energy unexpectedly, is the cause in the equations, their implementation, or the timestep?

**Documented capabilities.** SciPy's `solve_ivp` exposes several ordinary-differential-equation solvers, including explicit Runge–Kutta methods and implicit methods intended for stiff problems. Its error control combines absolute and relative tolerances; absolute tolerances can differ between state components. Output times requested through `t_eval` are separate from the solver's internal steps. Event detection searches for sign changes over a step and can miss multiple crossings inside that step. These details matter when using an offline solver as a comparison tool rather than assuming its output is exact. [SciPy integration reference](https://docs.scipy.org/doc/scipy/reference/generated/scipy.integrate.solve_ivp.html).

**Possible project value.** A small offline version of a flight equation could provide a comparison for a future fixed-step implementation. This investigates numerical accuracy, extending the earlier discussion of separating rendering and physics rates. A constant-force translation or a deliberately simple oscillator has an analytical solution; it could reveal basic integration errors before aerodynamic coefficients complicate the diagnosis.

**Limits and inference.** Agreement between two solvers establishes neither realistic aerodynamics nor correct parameter values. Both can integrate the same mistaken equations. Tight local error tolerance also does not guarantee a chosen global trajectory error. Discontinuous control changes and collisions need explicit treatment; simply tightening tolerances is not a substitute for handling their timing. Comparing angle representations also requires care around wrapping and quaternion sign equivalence.

**Small experiment, unperformed.** Run one smooth, short scenario at step sizes `h`, `h/2`, and `h/4`, sampling results at common times. Compare position, velocity, and orientation against an analytical case first, then against a tightly controlled offline calculation. Record runtime and the error trend. If refinement stops helping, investigate equations, discontinuities, and floating-point effects before increasing the simulation rate again. No integrator, timestep, or Python runtime dependency is selected by this research.

### 8. Self-describing experiment traces with MCAP

**Question.** What should an exported flight trace preserve so that another contributor can understand an experiment without the original developer present?

**Documented capabilities.** MCAP organizes messages into channels with optional schemas describing their payloads. The format specifies separate publication and recording timestamps, an optional sequence counter, channel metadata, attachments, and optional chunk compression/indexing. Messages written outside chunks cannot use the chunk message indexes. These are storage facilities; they do not supply an aircraft telemetry schema or automatically synchronize clocks. [MCAP concepts](https://mcap.dev/guides/concepts), [format specification](https://mcap.dev/spec).

**Possible project value.** A trace could combine control commands, aircraft state, per-surface force diagnostics, and configuration metadata without forcing all signals into the same sampling rate. An attached parameter snapshot could help explain why two runs differ. A file with named channels and explicit units could also give AI-assisted investigations more reliable evidence than a screenshot of a plot.

**Limits and inference.** Simulation time, input-event time, and wall-clock recording time need an explicit mapping. A timestamp field alone cannot tell us whether a command was applied before or after a physics step. A useful candidate message might therefore carry a simulation step index as well as time. The format does not guarantee lossless capture, deterministic replay, or complete state restoration. Recording every value may introduce overhead and large files; a plain CSV remains a useful baseline for the first few signals.

**Small experiment, unperformed.** Export the same short elevator step as CSV and as a few MCAP channels. Include parameter/version identifiers and document timestamp meanings. Ask a second script to locate the applied command, the resulting force, and the first changed pose. Deliberately omit a sample and check whether the gap is visible. Compare the effort and diagnostic benefit before adopting a richer format. This is about portable experimental evidence, distinct from a player-facing replay feature or saved flight.

### 9. Repeatable visual evidence for human and AI code review

**Question.** How could a change demonstrate that the airplane still appears correctly and its control surfaces still move as intended?

**Documented capabilities.** Playwright supports screenshot comparisons against stored baselines. Its documentation warns that browser rendering varies with the OS, hardware, settings, and headless mode, among other factors. It recommends matching the environment used for baseline generation. Its comparison workflow waits for consecutive screenshots to match; an actively moving flight scene therefore needs a deliberately controlled capture state. [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots).

For an engine-based example, Godot's Movie Maker mode produces non-real-time frame output, including PNG sequences. The documentation explicitly distinguishes this from recording actual gameplay in real time. It could produce inspectable frames at known points in a scripted sequence, but smooth exported footage would not establish smooth interactive performance. [Godot movie capture documentation](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html).

**Possible project value.** A small visual scenario could show the aircraft from a fixed camera, command elevator and aileron deflections, and capture neutral and deflected states. A numerical record of actual surface angles would complement the images. That would let reviewers assess what an AI-generated code change actually rendered, while still using ordinary source review to understand why.

**Limits and inference.** Pixel equality is sensitive to rendering variation; generous image thresholds can also hide a missing thin wing or reversed surface. A baseline may itself be wrong. A few stable views plus explicit scene-state checks could be more informative than an enormous screenshot suite. Neither browser automation nor offline movie capture exercises a physical RC transmitter by itself.

**Small experiment, unperformed.** Capture three known poses in one candidate prototype, introduce a reversed aileron or missing material, and check whether the evidence makes the error obvious. Record renderer, resolution, camera, capture step, and tool versions. Choose browser or engine-native capture only after a prototype exists; do not add both merely for coverage.

### 10. Sensitivity analysis to decide what is worth researching next

**Question.** Which uncertain aircraft parameters materially affect the behavior we want to improve?

**Documented capabilities.** SALib separates input sampling from model execution and analysis: it generates parameter sets, the user runs a model, then SALib analyzes the outputs. Its documented methods include Sobol, Morris, and FAST. The guide distinguishes first-order effects from interactions and total-order contributions. Its example also shows how evaluating second-order interactions increases the required number of model runs. This could support offline investigation without embedding Python into the interactive simulator. [SALib workflow and sensitivity indices](https://salib.readthedocs.io/en/latest/user_guide/basics.html).

**Possible project value.** For a simple trainer, uncertain mass, drag parameters, thrust scaling, or control effectiveness could be varied while observing a defined outcome such as glide distance or pitch response. The result could help decide whether another hour is better spent measuring a mass, refining propulsion data, or improving control-surface geometry. This asks how uncertainty affects predictions; it does not estimate the best parameters from recorded flights, the subject of an earlier investigation.

**Limits and inference.** A ranking depends on the chosen scenario, output, parameter ranges, and sampling assumptions. It is not a universal importance ranking for airplanes. Inputs that are physically coupled need a sampling scheme that respects that relationship; arbitrary combinations could describe impossible aircraft. Failed or unstable simulations need explicit reporting instead of being silently removed. Sensitivity within a simplified model cannot reveal effects that the model omits entirely.

**Small experiment, unperformed.** Begin with only three uncertain parameters and one short deterministic maneuver. Justify each range from a measurement or label it as exploratory. Plot outputs from a small preliminary sweep, then use a suitable sensitivity method only if the extra runs answer a real question. Repeat for a different maneuver to see whether the ranking changes. Preserve the model revision, parameter ranges, sampling method, and failures with the result; no parameter-accuracy budget is fixed here.

## Focused follow-up on the three priority research gaps

Seventh research pass, **2026-10-05**: follow-up to the notebook review, concentrating on a reference aircraft, a common prototype comparison, and direct pilot evidence. This pass deepens selected sources instead of adding another ten topics. The provisional specimen and comparison pair are research choices that can change, not project requirements.

| Gap | New evidence or concrete preparation | What remains unresolved |
| --- | --- | --- |
| One coherent aircraft | Pinned Ultra Stick 25e entrypoint and parameter manifest; documented discrepancies against a paper and generator; four XML files fetched and parsed. | Full dependency resolution, simulator execution, trim, measured flight correspondence, and raw-log availability. |
| Fair technology comparison | Shared presentation/input/reset task for Three.js and Godot, source-level input caveat, recording criteria, and outcome-dependent next steps. | No implementation, build timings, performance measurements, or winner. |
| Actual pilot experience | Six original public reports with contrasting needs, plus a short proposed observation protocol. | No project-specific interviews, observed sessions, or training-transfer evidence. |

The first runtime comparison can use scripted motion and an original blockout, so missing calibrated aerodynamics need not block a visible airplane. Aircraft-data reconciliation can proceed separately. Pilot observations could begin with an existing simulator when participants are available; no outreach was performed. These are independent ways to reduce uncertainty, not a mandatory sequence.

- [A reference aircraft: separate a reproducible digital specimen from measured reality](#a-reference-aircraft-separate-a-reproducible-digital-specimen-from-measured-reality)
- [A common task for comparing development approaches](#a-common-task-for-comparing-development-approaches)
- [Pilot evidence: six concrete reports and a way to observe the next questions](#pilot-evidence-six-concrete-reports-and-a-way-to-observe-the-next-questions)

### A reference aircraft: separate a reproducible digital specimen from measured reality

**Direction update:** the first simulator aircraft is now aimed at the Ultra Stick / Ugly Stick-style .60 nitro family. The electric Ultra Stick 25e below remains a useful research comparison, not the selected physical configuration. Next aircraft-specific research should identify candidate .60 nitro plans/manuals and their geometry, mass/CG, engine, propeller, and control throws. Nitro propulsion and sound need their own evidence; neither the electric power model nor its aircraft parameters should be silently carried over.

**Finding:** Ultra Stick 25e is a promising *research specimen*, because both experimental literature and inspectable aircraft definitions exist. They are not interchangeable versions of one authoritative aircraft. This investigation inspected source files and a research paper; it did not run the simulator or reproduce flight measurements. “University of Minnesota” (UMN) is the relevant Ultra Stick research group here, distinct from the University of Illinois (UIUC) airfoil and propeller databases.

#### Three candidate routes

| Candidate | Evidence actually found | Why investigate it | Main limitation |
|---|---|---|---|
| UMN Ultra Stick 25e / UASLab OpenFlightSim | A published identification study plus public JSBSim configuration, geometry, motor, propeller and actuator files. | Small conventional RC airframe; lets us compare a data manifest against real implementation dependencies. | Multiple configurations differ; the digital model is not demonstrated to reproduce the paper's identified aircraft. |
| NASA FASER | NASA reports static, forced-oscillation and rotary-balance tests on the same research aircraft used for flight tests. Rotary tests cover angle of attack 0–50°, sideslip −5–10°, and nondimensional spin rates −0.5–0.5. | Stronger lead for studying high-angle-of-attack and rotational behavior later. | The [2016 report record](https://ntrs.nasa.gov/citations/20160010112) says control-effect characterization remains incomplete; this pass did not recover a complete machine-readable database with matching flight configuration. |
| BYU textbook Aerosonde model | One [parameter file](https://github.com/byu-magicc/mavsim_public/blob/10363e0eaeb16a61a7463505f8e122a9eb7e2b4e/mavsim_python/parameters/aerosonde_parameters.py) collects mass, inertia, geometry, stability/control coefficients and motor/propeller constants. | A compact independent calculation fixture for equations, units and control signs. | Its configured mass is 11 kg and span 2.8956 m; treat it as a textbook numerical specimen, not evidence about a small hobby trainer's handling. A parameter file alone does not establish measurement provenance. |

The first row is supported by the [UMN aircraft overview](https://uav.umn.edu/resources/aircraft), the [identification paper](https://dept.aem.umn.edu/~mettler/Courses/AEM%205333%20%28spring%202013%29/AEM5333%20CourseDropbox/Week%207%20Identification/Ultrastick%20Identification/2012_AIAA_JA_SYSID.pdf), and the pinned files below. This comparison favors a traceable next investigation, not a final aircraft choice.

#### Provisional digital specimen and parameter manifest

Use **OpenFlightSim commit `b020511223946b8642c73a35eacd17c4d5c09ddf`, UltraStick25e** as the specimen identifier. The [top-level definition](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/UltraStick25e.xml) actually loads `MassOpenFlight.xml`, `MetricsOpenFlight.xml` and `AeroOpenFlight.xml`, alongside effectors, propulsion, gear, controls and sensors. Selecting a plausible neighboring XML file would silently select different data. As a limited reproducibility check, this pass fetched and parsed the pinned entrypoint, mass, metrics, and effectors XML with Python's standard XML parser, confirming these include names and the values below. This was not complete dependency resolution or a successful JSBSim load/run.

| Quantity | Loaded definition or availability | Evidence status and unresolved question |
|---|---|---|
| Configured empty mass | 1.959 kg (`emptywt`) | Implemented value in [MassOpenFlight.xml](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/MassOpenFlight.xml); physical configuration behind it needs reconciliation. |
| CG | `(0.222, 0, 0.046)` m | Coordinates present in the same file. Preserve its structural reference convention; do not interpret this automatically as distance aft of wing leading edge. |
| Inertia | `Ixx=0.07151`, `Iyy=0.08636`, `Izz=0.15364`, `Ixz=−0.014` kg·m²; other cross terms zero | Implemented, not newly measured. Confirm simulator product-of-inertia convention before porting. |
| Wing references | Area 0.3097 m², span 1.27 m, chord 0.25 m | [MetricsOpenFlight.xml](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/MetricsOpenFlight.xml). Aerodynamic reference point `(0.2175,0,0.046)` m is separate from CG. |
| Aerodynamic coefficients | For example, `CL0=0.1068`, `CLα=4.58` per radian, `CD0=0.0434`; rate and surface contributions are explicit | [AeroOpenFlight.xml](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/AeroOpenFlight.xml). The inspected lift sum is a derivative model; having coefficients does not establish a validated stall envelope. |
| Motor | E-Flite Power25 model, 600 W | [Power25.xml](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/engine/Power25.xml) specifies power, not a measured battery/ESC/motor efficiency map. |
| Propeller | APC 12×6e, two blades, tabulated thrust and power coefficients | [Propeller file](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/engine/APC%2012x6e.xml) attributes derivation to APC's website; exact original dataset/version remains unresolved. |
| Controls | Separate ailerons, flaps, rudder and elevator; limits ±0.523599 rad; servo delay 0.020 s | [Effectors.xml](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/Effectors.xml). Model settings, not an identified transmitter-to-surface calibration. |
| Starting flight state | Cruise initializer supplies 17 m/s | [initCruise.xml](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/initCruise.xml) is an initialization request, not evidence of equilibrium or a reproduced trim solution. |

#### The mismatch is useful evidence

The identification paper's Table 1 reports 1.959 kg, but inertias `0.089, 0.144, 0.162` kg·m² and `Ixz=0.014`, with inertia obtained from swing tests. Its surfaces reach ±25°. Its baseline borrows aerodynamic information from the Ultra Stick Mini and 120, explicitly not exact geometric scales; flight identification then updates selected derivatives. Slow phugoid and spiral behavior is less well established. These distinctions are reasons to keep the paper configuration separate, not average its constants into the digital model. See sections III, VI and VII of the [paper](https://dept.aem.umn.edu/~mettler/Courses/AEM%205333%20%28spring%202013%29/AEM5333%20CourseDropbox/Week%207%20Identification/Ultrastick%20Identification/2012_AIAA_JA_SYSID.pdf).

There is also an internal reproducibility issue: the [Python aircraft generator](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Utilities/UltraStick25e.py) assigns `Ixz=0`, while the loaded XML uses `−0.014`. It marks mass-property sourcing unfinished and calls servo delay a guess. Regenerating files is therefore a separate operation whose output must be compared with the checked-in specimen. This is source inspection, not proof of a runtime failure.

**Reuse:** The repository carries an [MIT license](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/LICENSE.md). That establishes stated software terms; inspect provenance of third-party propeller tables and visual assets before redistributing a bundle. Availability of a paper also does not establish a reusable raw flight-log dataset; none was verified here.

**Small next experiment:** extract a machine-readable manifest and resolve every loaded include from the pinned specimen. Preserve values, units, coordinate conventions and status as “implemented,” “measured in paper,” “estimated,” or “unknown.” Then attempt one trimmed condition and separate elevator/aileron pulses, logging forces and rates. First judge whether another clean checkout can reproduce the same result; only afterwards compare a separately constructed paper configuration against published responses. Success would justify this specimen as a useful engineering fixture. Unresolved configuration lineage or failed reproduction would justify switching fixtures without changing the simulator's direction.

### A common task for comparing development approaches

**Research finding.** Two contrasting routes are sufficiently documented to justify a small comparison: Three.js with JavaScript and a local web build, and Godot with GDScript and its Compatibility renderer. They are experimental representatives of a browser-library workflow and an integrated-engine workflow, not finalists or a stack decision. A third implementation would add work before the first pair reveals which differences matter.

**What the source inspection establishes.** Three.js's installation guide describes HTML/JavaScript files, npm/Vite development, a production `dist` directory, and separately imported addons such as `GLTFLoader`. Its game tutorial explicitly supplies application structure beyond rendering. Godot's SceneTree supplies a running scene's lifecycle, processing, and input callbacks; its command-line interface exposes import, script checking, and export operations. This establishes different starting responsibilities, not a productivity winner. [Three.js setup](https://threejs.org/manual/pages/installation.html), [game tutorial](https://threejs.org/manual/pages/game.html), [Godot scene lifecycle](https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html), [Godot command-line operations](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).

For a browser-to-browser comparison, Godot's documented web path uses WebGL 2 through Compatibility, offers a single-threaded export, and excludes Godot 4 C# projects. Three.js can be tested with its WebGL renderer on the same browser. Testing Godot natively first is useful for setup observations, but comparing that native run with a browser run would conflate application framework and deployment platform. [Godot web-export constraints](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

**Concrete input-source caution.** Godot's official joypad diagnostic, inspected at revision `3e08537616661a5883831628decab4c526260289`, displays numeric axis values and connection events. Its loop is bounded by `min(JOY_AXIS_MAX, 10)`, and its controller illustration uses a `0.2` deadzone for highlighting. This is a useful starting diagnostic, but not proof that every radio channel is exposed. The illustration's deadzone should not be mistaken for modification of the separately displayed raw numeric value. [Diagnostic source](https://github.com/godotengine/godot-demo-projects/blob/3e08537616661a5883831628decab4c526260289/misc/joypads/joypads.gd). The earlier notebook's Gamepad/SDL distinctions remain relevant.

**Proposed shared task, not executed.** Give both implementations the same small input specification:

| Part | Controlled comparison |
| --- | --- |
| Scene | One original airplane blockout, flat field, horizon, fixed lighting, and ground camera. Use identical dimensions and hinge locations. |
| Motion | Play the same timestamped pose sequence first. This tests presentation without introducing two independently tuned flight models. |
| Interaction | Move named aileron/elevator parts from keyboard input; expose the received and mapped values. Add the same physical controller only when available. |
| Reset | Restore aircraft pose, camera state, and displayed controls to the same recorded initial condition. |
| Delivery | Run locally, then open browser builds on the same machine/browser at the same viewport and drawing-buffer resolution. |
| Change request | After the baseline works, change a hinge location, add axis inversion, and adjust the camera while retaining the original pose sequence. |

Matching display resolution alone is insufficient: Three.js's responsive-rendering guide distinguishes CSS canvas dimensions from the actual drawing buffer and explains the extra pixel cost on high-density displays. Record both so a sharper, more expensive output is not misread as an engine performance difference. [Canvas resolution and display density](https://threejs.org/manual/pages/responsive.html).

**Evidence to collect.** Separately record clean setup time, first visible result, edit-to-running time, failed builds/imports, manual editor operations, and review/repair time. Retain exact tool versions, launch instructions, screenshots at known sample times, console diagnostics, payload bytes, and frame-time observations on the same hardware. Separate cold from cached loading. Generated code quantity is not a productivity score. For AI-assisted work, retain task instructions and distinguish agent execution from human intervention; keep tool/model settings comparable and record prior familiarity. One small trial cannot establish a general ranking.

**What would change our direction.** If the engine route makes the second change substantially easier, investigate its authoring advantage further. If browser-library assembly remains short and diagnostic access is clearer, deepen that route. Missing input channels would trigger a specific input-path investigation before any conclusion about rendering. If setup dominates the allotted experiment, preserve the failure and stop expanding the sample; it is evidence of friction, not proof of permanent incompatibility. If outcomes are close, choose whichever helps the next experiment temporarily, or defer the choice. No measured outcome currently exists, and neither implementation was created in this research pass.

### Pilot evidence: six concrete reports and a way to observe the next questions

**Research question:** what prevents people from reaching an enjoyable, understandable first flight, and which problems should our earliest playable experiment expose? This pass adds firsthand reports rather than another feature catalogue. **Evidence: original public posts and replies, read on 2026-10-05.** These are self-selected accounts, not representative survey results, verified pilot credentials, or controlled evidence of learning transfer. No participant was contacted or observed for this project.

#### Reports with context and limits

| Original report | What the author actually reports | Useful question for our project; evidence limit |
| --- | --- | --- |
| [FMS beginner asking how much practice is enough, March 2024](https://www.reddit.com/r/RCPlanes/comments/1boha89/how_long_should_i_practice_in_sim_before_flying_a/) | A person using FMS and a FlySky FS-I6X, without an RC airplane yet, says distant aircraft become too small to distinguish. Another participant objects that simulator zoom can create a misleading perspective. | Can users identify bank direction while retaining field context? These conflicting observations suggest testing visibility and distance judgment separately. They do not establish a universally correct zoom policy or FMS aerodynamic accuracy. |
| [NX6 calibration difficulty, October 2022](https://forums.realflight.com/index.php?threads/how-to-use-windows-to-calibrate-nx6.56876/) | A prospective pilot with extensive IT experience describes hours of setup, unexplained throttle, jumping channels, and confusion over Windows axis labels. The author later reports that using a USB hub resolved the erratic behavior on their Dell XPS13/Windows 11 setup. | Would raw-input visibility distinguish connection trouble from incorrect mapping before someone blames flying ability? The reported remedy is one hardware/software case, not proof that USB-C generally fails or that a hub is our solution. |
| [DXS reset interruption, September 2024](https://forums.realflight.com/index.php?threads/dxs-controller-with-dongle-reset.60736/) | The author asks how to reset from the transmitter because every crash requires returning to the keyboard. Replies discuss trading an existing channel assignment for reset. | Does reaching for another device interrupt short practice sessions, and can users discover a workable reset? This establishes one person's friction; the replies' controller-compatibility details were not independently hardware-tested here. |
| [Experienced user's simulator practice, March 2021](https://www.reddit.com/r/RCPlanes/comments/lyfw1o/is_realflight_actually_helpful/) | A commenter identifying as a university research pilot describes modifying a simulator aircraft to approximate relevant characteristics, then practicing circuits, landings, and failures. Others describe returning to flying after long breaks. | A useful session may involve recreating a maneuver or regaining confidence, rather than completing beginner lessons. These are self-reports; model similarity, improvement, and field outcomes were not measured. |
| [Assistance and discouragement, May 2026](https://www.reddit.com/r/RCPlanes/comments/1tborp2/learning_to_fly/) | A learner reports successful simulator landings in an intermediate mode but difficulty and discouragement in expert mode and instructor-led field sessions. Replies disagree: several favor immediate manual practice; another self-described instructor reports teaching through mode switching to build confidence. | Observe whether users understand which assistance is active and what they personally want to practice. The thread does not isolate input calibration, aircraft setup, teaching style, or assistance as the cause. It cannot settle which curriculum works best. |
| [Different visual needs and preferred viewpoints, January 2026](https://www.reddit.com/r/RCPlanes/comments/1qkz4nr/new_to_rc_flying/) | In a discussion about introducing a child to RC, an adult participant reports limited vision in one eye, frequent orientation loss, and a personal preference for FPV. Another pilot describes relying on memory of the aircraft's previous attitude. | Include different visual needs and preferred flying experiences when observing the prototype. These accounts do not establish medical suitability or make FPV an equivalent substitute for ground-view practice. |

The calibration and reset threads were inspected directly from the original forum HTML because the web reader normalized their query-string URLs into the forum index. The linked thread URLs preserve the original paths; summaries above refer to the posts, not the index.

#### What the disagreements change

**Inference:** “realism” is too broad an interview question. A user might mean recognizable orientation, familiar control response, credible stalls, difficult landings, or the emotional consequences of crashing. Ask for a particular moment and the behavior they expected. Keep aircraft setup and active assistance visible in the notes before interpreting a handling complaint as a physics defect.

Reset also has two possible roles. It enables inexpensive repetition, but an immediate restart may hide what caused failure. In the March 2021 discussion, a participant recommends continuing recovery attempts instead of treating every problem as a disposable crash; in the May 2026 discussion, easy reset is used to argue for trying harder control modes. These are competing practice preferences, not evidence for imposing penalties or removing reset. A short optional replay or a repeatable starting position could be investigated if users actually ask to understand a mistake. [Practice discussion](https://www.reddit.com/r/RCPlanes/comments/lyfw1o/is_realflight_actually_helpful/) · [Assistance discussion](https://www.reddit.com/r/RCPlanes/comments/1tborp2/learning_to_fly/).

#### Proposed observation, not an experiment already performed

Start with four to six willing adult participants spanning beginners, returning pilots, and experienced flyers; seek varied display/controller setups and relevant access needs. This is a practical exploratory sample, not a statistically powered effectiveness study. Use an existing simulator first, or the smallest prototype once available. Allow roughly 25 minutes per person:

1. **Context, 3 minutes:** ask what they want to do, what they already fly or play, their controller mode, and an example of frustrating or enjoyable practice.
2. **Getting airborne, 7 minutes:** ask them to configure controls and begin flight without coaching initially. Record first usable-input time, first-flight time, requests for help, and mismatched axes. Separate installation/download delay from calibration work. Cap the attempt and offer help rather than consume the whole session.
3. **Orientation and repetition, 10 minutes:** attempt an outbound turn, an inbound turn, and a return toward a chosen field reference. Ask them to repeat a difficult segment. Record when the aircraft becomes unreadable, wrong-direction corrections, reset discovery, and time between attempts. If comparing two views, alternate presentation order and hold aircraft, wind, and assistance constant.
4. **Reflection, 5 minutes:** ask which moment they wanted to repeat, which behavior surprised them, and what one change would let them enjoy or understand another flight. Record confidence separately from task completion.

**What would change:** repeated setup failure would prioritize a tiny input inspector and guided mapping trial; readable aircraft with poor field-relative judgment would prioritize camera/context experiments; long reset interruptions would prioritize restart interaction; assistance confusion would prioritize clearer state feedback. Conversely, successful setup and orientation would justify investigating flight behavior next. Preserve individual counterexamples and configuration details rather than average incompatible experiences into one satisfaction score. A short session can reveal usability problems and preferences; it cannot demonstrate long-term learning, real-flight transfer, or aerodynamic fidelity.

## Closing the .60 nitro Stick research gaps

**Follow-up — 2026-10-05.** The chosen aircraft family makes several earlier gaps more concrete: we need consistent airframe parameters, propulsion evidence appropriate to glow engines, source-level checks of reusable models, and configuration-specific handling references. This pass investigates those gaps while keeping execution and measurement tasks visibly open.

### A documented .60 nitro airframe: separate the variants before combining parameters

**Evidence status:** original manufacturer manuals inspected on distributor/retailer mirrors on 2026-10-05; key specification and control tables were also rendered from the downloaded PDFs and visually checked. These are manufacturer setup recommendations, not measured flight-dynamics datasets. The user's first-aircraft direction remains an Ultra Stick / Ugly Stick-style .60 nitro airplane; this comparison does not select a particular commercial variant.

Two useful candidates illustrate why the family name is insufficient. Hangar 9's [Ultra Stick .60 manual](https://www.astramodel.cz/manualy/hangar9/hangar9_ultra_stick_60.pdf) describes conventional and quad-flap wings. Great Planes' [Big Stik .40/.60 ARF manual](https://rcflight.se/pdf/pdf.aspx?a07=1259) is the 2001 GPMZ1250 V1.0 document for GPMA1220/1221. The entries below use its **.60** column. Pages are one-based PDF pages and match the printed numbers where present.

| Parameter | Ultra Stick .60 | Big Stik .60 ARF |
| --- | --- | --- |
| Span; length | 66 in; 55 in (p. 1) | 66.5 in; 59 in (p. 1) |
| Wing area | 913 in² conventional; 927 in² quad (p. 1) | 1,000 in² (p. 1) |
| Listed weight | Approximately 6–7 lb (p. 1) | 6.5 lb (p. 1) |
| Two-stroke displacement range | .61–.78 in³ (p. 1) | .60–.91 in³ (p. 1) |
| CG aft of wing leading edge | 4⅛ in (p. 43) | Start 4 in; range 3¾–4½ in; empty tank (pp. 17–18) |
| Aileron travel, low/high | ±¾ / ±1¼ in (p. 43) | ±¾ / ±1 in (p. 17) |
| Elevator travel, low/high | ±1 / ±1½ in (p. 43) | ±⅝ / ±⅞ in (p. 17) |
| Rudder travel, low/high | ±2½ / ±4 in (p. 43) | ±1¼ / ±1½ in (p. 17) |
| Gear | Tailwheel (pp. 24–26) | Steerable nosewheel (pp. 12–13) |
| Fuel evidence | Tank listed as 10.8 oz (p. 6) | Tank assembly/installation, pp. 10–11; capacity unresolved |

**A source defect worth preserving:** the Ultra cover actually prints 5,934.5 and 6,025.5 **sq dm** beside its imperial areas; this is visible in the PDF, not merely an extraction error. Independently converting the imperial values gives 0.58903108 and 0.59806332 m². Treat these as calculated values, not silently corrected manufacturer measurements. Ultra's CG paragraph does not state tank fill condition. Big Stik defines throw measurement at each surface's widest part; its four-stroke recommendations also differ between cover and p. 3. These unresolved details belong in provenance notes.

**What this gives the project.** A coherent provisional envelope is now possible without borrowing mass, geometry or trim from the electric 25e. Similar spans do not justify mixing either aircraft's elevator travel with the other's area and CG. The different landing-gear layouts would also produce different ground behavior. A .60 class designation is an engine-size family: 0.60 cubic inch converts to approximately 9.83 cm³. It is neither a 60-inch wingspan specification nor a 60 cm³ gasoline-engine specification.

**A proposed parameter manifest, not a required file format:** each future entry could carry `variant`, `configuration`, `quantity`, `original_value`, `original_unit`, `si_value`, `source_page`, `evidence_kind`, and `uncertainty_note`. Preserve the original value beside the conversion. Store the listed mass as a range or nominal specification until one configured airframe has actually been weighed; an engine, muffler, propeller and fuel state must accompany any measured mass.

The manual audit still leaves several physics inputs open:

- **Inertia and mass distribution:** no measured inertia tensor was established. An initial component-mass estimate should label its assumptions; matching total mass and longitudinal CG alone does not determine roll or pitch inertia.
- **Section geometry:** no validated airfoil coordinates or full root/tip/hinge geometry were established. A rectangular-looking photograph is insufficient to select an airfoil polar or establish control effectiveness.
- **Control angles:** these are linear travels. Conversion to an angle needs the actual hinge-to-measurement distance and measurement convention; assigning the number in inches directly to degrees would be wrong.
- **Fuel contribution:** volume is not mass. Resolve the tank unit convention, usable fill, fuel density and tank position before estimating fuel-dependent CG; do not interpret the listed 10.8 oz as fuel mass.
- **Aerodynamics:** a manufacturer's handling description does not supply lift/drag curves, damping derivatives, stall boundaries or measured response traces.

**Useful next experiment.** Assemble a small manifest for one candidate's conventional wing; independently calculate the units and visually compare a simple untextured mesh against span, length and gear layout. Mark every guessed quantity. The outcome should be an explicit list of dimensions requiring a plan or physical measurement, not a claim that the aircraft is flight-validated. If uncertainty in a parameter changes the simulated response substantially, investigate that parameter before adding model detail.

**Source reuse and reproducibility.** This pass links the manuals; it does not establish permission to redistribute their illustrations, logos or scans as open-source assets. An original simplified mesh and authored parameter notes can carry their own provenance. Download fingerprints identify the exact bytes inspected: Ultra PDF SHA-256 `90b411fd750fe26fdf5b64fef43b9735c23aa665519a5db8a09972e2f02d5bc7`; Big Stik PDF SHA-256 `bd56627bd34cf0e948e70442b5600212eb4eb7ffe6b37c7bb94735ccc467d5d0`. No flight model, real-aircraft measurement or handling test was performed in this audit.

### Nitro propulsion: a documented engine and propeller without invented performance curves

**Question.** What can we actually parameterize for the chosen .60 nitro Stick family, and what would still be an assumption? This investigation uses **O.S. MAX-65AX, code 16520, with E-4050 silencer** as a reference candidate. It does not select that engine or establish compatibility with a particular airframe variant.

**Manufacturer specifications, not project measurements.** O.S. lists 10.63 cm³ displacement, 24.0 mm bore, 23.5 mm stroke, 1.75 PS / 1.73 hp at 16,000 rpm, and a 2,000–17,000 rpm practical range. The engine weighs 497 g; the Japanese product page separately lists the E-4050 silencer at 128 g and E-4010A at 156 g. Thus the researched engine-plus-E-4050 combination totals **625 g**, before mount, propeller, spinner, tank or fuel. The different silencer combination totals 653 g. Both values are arithmetic from catalog masses, not weighed installations. [O.S. English specification](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/16520.htm), [O.S. variant and silencer details](https://www.os-engines.co.jp/line_up/engine/air/aircraft/catalog/Responsive/65la_16520_16521/index.html).

The older **MAX-61FX, code 17750**, is a separate reference: its official catalog lists 9.95 cm³, 1.9 PS at 16,000 rpm, 550 g, a 60C carburetor and E-4010 silencer. Its page identifies it as no longer sold. We should not silently combine 61FX power, 65AX weight and another engine's propeller response under the label “.60 nitro.” [O.S. archived MAX-61FX catalog](https://www.os-engines.co.jp/line_up/engine/air/aircraft/catalog/17750.htm).

**What the manual contributes.** The exact [65AX/E-4050 manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/2stglow/65AX_E4050_EG.pdf) describes a two-stroke glow engine, Type 61D carburetor, separate high-speed and low-speed mixture controls, and muffler-pressurized fuel supply. It suggests a roughly 350 cm³ tank and describes approximately 10–12 minutes of flight as dependent on fuel, propeller and throttle use. Its fuel description specifies methanol, lubricant and nitromethane; “nitro” therefore does not mean pure nitromethane. Suggested sport propeller sizes include 12×6, 13×6–7 and 14×6. These are documented starting ranges, not measured thrust or endurance for our airplane.

**Interpretation for the simulator.** One maximum-power rating cannot establish a torque curve, idle thrust, throttle linearity, acceleration time or fuel flow. An early model could have explicit stopped/running states, a provisional throttle-to-target-rpm curve and a replaceable response-time parameter. That is an approximation to disclose and test. Later, measured engine torque and propeller load could determine shaft acceleration through `I_shaft × dω/dt = Q_engine − Q_prop − Q_loss`. Carburetor command belongs on the input side of that model; electric motor `Kv`, battery voltage and ESC behavior are inappropriate substitutes. Neither the catalog nor manual inspected here supplies the necessary torque surface or shaft inertia.

**An exact propeller lead—and an evidence mismatch.** APC identifies **LP12060** as its 12×6 Sport propeller. Its published mass is 1.62 oz; mass alone does not identify rotational inertia. [APC product specification](https://www.apcprop.com/product/12x6/). APC supplies [PER3_12x6.dat](https://www.apcprop.com/files/PER3_12x6.dat), whose inspected header identifies software `v2022-0915` and simulation date `09/22/2022`. The file gives thrust, torque, power and nondimensional coefficients versus rpm and forward speed. APC explicitly says these files are calculated using its geometry and proprietary vortex-based analysis. They are **manufacturer predictions**, distinct from wind-tunnel measurements. [APC methods and data index](https://www.apcprop.com/technical-information/performance-data/).

UIUC provides a measured **APC Sport 11×6** reference: [static data](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_static_rd0488.txt) and an approximately [6,000 rpm advancing-flow run](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_rd0495_6000.txt). These can test coefficient ingestion, interpolation and comparison with APC predictions for that same 11×6. They do not validate the 12×6 candidate at its eventual loaded engine rpm. No matching measured 12×6 Sport dataset was identified in the inspected [UIUC Volume 1](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html) and [Volume 2](https://m-selig.ae.illinois.edu/props/volume-2/propDB-volume-2.html) listings. This is a search result, not proof that such measurements do not exist. Electric and Sport families must retain separate identities even when nominal diameter and pitch match.

**Mass, sound and useful missing evidence.** Our proposed installation record should track engine and muffler positions, empty tank mass, fuel quantity, fuel density and fuel centroid separately. Fuel burn changes mass and potentially CG; a forward tank would move the CG aft as it empties, conditional on actual component positions. The manual's endurance estimate is insufficient to set either fuel density or a throttle-dependent consumption curve. Sound can initially follow simulated rpm, but recordings should ultimately identify engine, propeller, muffler, rpm and microphone position. None of the inspected sources provides calibrated sound, throttle-step recordings or a transient response measurement.

**Small next experiment, not yet executed.** Build an offline plot of predicted 12×6 load versus rpm at several forward speeds, with the catalog engine rating shown as a single point rather than a fabricated curve. Separately compare the measured and predicted 11×6 at overlapping conditions. Record data versions, units and out-of-range queries. The result would reveal how much the flight prototype can infer from existing data and which engine observations would reduce uncertainty most: loaded steady rpm, throttle-step timing, idle behavior and installation mass/CG. Keep all provisional coefficients replaceable while the first visible airplane takes shape.

### Code audit: a glow-aircraft label does not establish a nitro engine model

**Evidence: source inspected, not executed.** This audit follows the historical Paparazzi CRRCSim fork at revision `2d1131ec7d99f1172e4f051a303966046f62dbda`. It does not establish the behavior of every CRRCSim release or fork.

Its generic Sport aircraft is described as a glow-powered aerobatic trainer, but the actual XML defines a battery, shaft, propeller and automatically parameterized engine. The shaft parser instantiates `Engine_DCM` for the engine element; the battery code integrates remaining capacity from current. This is a concrete example of a combustion-aircraft preset using an electric-style propulsion approximation. It may produce useful handling, but its label is not evidence of a measured glow-engine response. The generic Sport is also not an identified Stick airframe. [Sport configuration](https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/models/sport.xml), [shaft construction and integration](https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/src/mod_fdm/power/shaft.cpp), [battery implementation](https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/src/mod_fdm/power/battery.cpp).

The implementation nevertheless offers useful things to study. Engine and propeller contribute opposing shaft moments before angular speed is integrated using shaft inertia. The flight-model adapter passes body-relative airflow into the power subsystem after conversion to SI, then converts returned forces and moments into pounds-force and pound-feet. Aerodynamic, propulsion and landing-gear contributions remain identifiable before summation. These boundaries could inspire a small diagnostic that displays each contribution separately. [Shaft code](https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/src/mod_fdm/power/shaft.cpp), [flight-model adapter](https://github.com/paparazzi/crrcsim-pprz/blob/2d1131ec7d99f1172e4f051a303966046f62dbda/src/mod_fdm/fdm_larcsim/fdm_larcsim.cpp).

**Integration detail to investigate before reuse:** inside the adapter's update loop, `ls_step(dt)` precedes the controller callback and the aerodynamic, propulsion and ground calculations; `ls_accel(...)` follows those calculations. Understanding the integrator's stored history and initialization is necessary before changing this order. A plausible-looking rearrangement is not automatically equivalent. A useful future experiment would trace one control step, log units and force signs, and repeat at smaller timesteps. No such execution was performed here.

A second capability trap appears in JSBSim's `FGPiston` documentation: it exposes a `cycles` parameter for two- or four-stroke engines, while explicitly documenting support only for four-stroke engines. It also describes spark/magneto-related behavior. Merely setting `cycles=2` therefore does not demonstrate a calibrated two-stroke glow model. This does not rule out JSBSim as a framework; a custom approximation or further implementation audit remains possible. [Official FGPiston reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGPiston.html).

**Project benefit:** follow an aircraft preset through its loader, actual equations, units and state update before treating it as a reference. We can learn from subsystem separation while keeping our first nitro approximation explicit and replaceable.

### Handling evidence: preserve the tested installation and the limits of pilot impressions

**Evidence: historical firsthand review, accessed through an archive transcription.** Outerzone reproduces an RCM February 1988 review of a Great Planes Big Stik 60 kit, using a Super Tigre G60 engine. The archive lists 67.5-inch span and 930-square-inch area: this is a different specimen from the 2001 ARF manual above. The reviewer reports little trimming needed, straightforward aerobatics and some down-elevator for inverted flight. The account also describes a lightly loaded nosewheel and bouncing during taxi, with a landing-gear change improving the behavior. These are qualitative observations of one installation, not measured coefficients or universal Stick behavior. [Archived review transcription and original-scan link](https://outerzone.co.uk/plan_details.asp?ID=11467).

**How this helps:** aircraft setup belongs beside every handling report. Record exact variant, engine/propeller, fuel state, CG, throws, rates/expo, field surface and wind when available; leave absent information unknown. This historical review suggests cases worth observing later: trimmed upright flight, inverted flight, power-off approach and taxi on a specified surface. The proposed cases are our interpretation, not experiments completed in this research pass.

A simulator that receives a favorable subjective review still needs separate numerical and physical checks. Conversely, a manual's geometry cannot tell us whether a ground-view airplane is readable or enjoyable to fly. The earlier pilot-observation proposal remains useful for camera, controls and practice behavior; it cannot replace aircraft-specific measurements. No pilots were contacted and no original scan was visually verified for this handling entry.

### Remaining weak points and the smallest useful evidence to seek

| Gap after this pass | What we now have | Small next investigation or experiment |
| --- | --- | --- |
| Exact first-aircraft variant | Two separately documented .60-family candidates | Compare a simple blockout against one manual; identify missing dimensions without mixing variants. |
| Mass properties and control geometry | Published weight, CG and linear throws | Build an assumption-marked component inventory; seek hinge distances and configuration-specific mass measurements. |
| Nitro performance | Exact engine catalog and manual, plus a candidate propeller prediction | Seek loaded-rpm and transient observations for the same installation; keep a provisional response model explicit. |
| Propeller confidence | Predicted 12×6 Sport data and measured 11×6 Sport data | Compare measured and predicted data for the matching 11×6; leave the 12×6 validation gap visible. |
| Reusable simulation code | Traced loader, propulsion types, unit boundary and update order | Run a minimal force/sign/timestep diagnostic if this code becomes a serious candidate. |
| Handling and player experience | Historical qualitative report and earlier observation protocol | Collect configuration-specific observations and independently try camera/input usability. |
| Development path | Earlier comparable-prototype proposal | Execute one small visible-airplane experiment; more source reading cannot establish edit/run effort or controller compatibility. |

These investigations can accompany the first simple airplane. Missing inertia measurements or a complete nitro torque map need not prevent a clearly labeled approximation from appearing on screen. No exact commercial variant, engine, library, platform or implementation architecture is selected by this pass.

## Testing the evidence behind the first aircraft

**Follow-up — 2026-10-05.** The weakest evidence is now less about finding more tools and more about establishing which inputs and behaviors we can trust. This pass performs one small data comparison and investigates methods for reducing uncertainty in mass properties and low-speed aerodynamics. These are research options; they do not select a stack or make complete aircraft calibration a prerequisite for a simple working airplane.

### Executed comparison: APC Sport 11×6 static prediction versus measurement

**Evidence: calculation executed on 2026-10-05 using published data.** The previous pass proposed comparing matching propeller datasets. This pass performed a bounded version: static thrust and power coefficients for APC Sport 11×6, with no engine model and no flight simulation. This propeller is a comparison specimen, not a selection for our .60 nitro airplane.

The measured input is UIUC's `apcsp_11x6_static_rd0488.txt`, containing 16 samples from 1,752 to 6,259 rpm. UIUC identifies Volume 1 as wind-tunnel measurements of unmodified retail propellers and advises using its corrected online data rather than older thesis tables. [Measured samples](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_static_rd0488.txt), [dataset provenance and correction notes](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html).

The comparison uses APC's static rows (`V=0`, `J=0`) at 1,000-rpm intervals from 1,000 through 7,000 rpm. Its file header identifies `v2022-0915`, dated 2022-09-22. These are calculated coefficients. We linearly interpolated each coefficient in rpm at the UIUC sample positions, without extrapolation. Relative difference is `100 × (prediction / measurement − 1)`. [APC prediction file](https://www.apcprop.com/files/PER3_11x6.dat), [manufacturer's calculation-method description](https://www.apcprop.com/technical-information/performance-data/).

Selected results below; the script prints all 16 comparisons. Display precision does not imply equivalent measurement precision.

| RPM | Measured Ct | Predicted Ct | Difference | Measured Cp | Predicted Cp | Difference |
| --- | --- | --- | --- | --- | --- | --- |
| 1,752 | 0.0917 | 0.10495 | +14.45% | 0.0514 | 0.04918 | −4.31% |
| 3,857 | 0.1056 | 0.10566 | +0.05% | 0.0491 | 0.04264 | −13.15% |
| 5,954 | 0.1130 | 0.10638 | −5.86% | 0.0471 | 0.04054 | −13.93% |
| 6,259 | 0.1129 | 0.10650 | −5.67% | 0.0468 | 0.04037 | −13.74% |

Across the 16 samples, mean absolute relative difference is **5.01% for Ct** and **11.64% for Cp**. The signed Ct mean is only +1.04%, hiding the change from overprediction to underprediction. Cp is below the measurements throughout this comparison. These summaries weight each sample equally; they are not weighted by likely flight conditions and are not confidence intervals.

**What this changes for our research.** A close thrust match at one speed would not establish a close shaft-load match: the 3,857-rpm row illustrates this directly. We should inspect thrust and power/torque separately before coupling a propeller model to a provisional engine response. A single correction multiplier also deserves scrutiny because Ct discrepancy changes sign across this small interval. These are interpretations of the comparison, not evidence that either dataset is universally wrong.

**Limits:** matching a product family and nominal size does not establish identical historical specimens or geometry revisions. We did not resolve experimental uncertainty, production variation, prediction-method error or interpolation error into separate contributions. These static results do not cover advancing flow, the intended larger propeller, typical full-throttle engine loading, or installation/airframe interference. No engine horsepower curve was inferred and no coefficients were tuned to force agreement.

**Reproduce:** run `python3 research/compare_static_propeller.py` from the repository root. The [small research script](research/compare_static_propeller.py) uses Python's standard library and embeds the factual coefficient extracts with their source URLs and version notes; it does not introduce a simulator language or dependency choice. UIUC's downloaded file was checked against the embedded rows, and interpolation was checked at an exact knot, an interior point and out-of-range inputs. APC's direct file download returned HTTP 403 in this environment, so its seven static rows were transcribed from the browser's source extraction and checked against those rows. The script records the UIUC raw-file hash; no APC raw-file hash is claimed.

### Mass-property evidence for the .60 Stick family

Research follow-up — 2026-10-05. The first-aircraft direction is an Ultra Stick / Ugly Stick-style .60 nitro model, with exact kit, ARF, wing and installed component configuration still open. As the existing manual comparison establishes, published weight and CG are setup/specification evidence; neither candidate manual supplies a measured full inertia tensor or component mass map. Keep variants separate and do not treat their values as measurements of the future simulator aircraft.

#### What can be established cheaply

For one physical build, record configuration, installed parts and fuel state; weigh the complete airframe and locate its CG in defined axes. Keep an inventory of major groups—airframe, powerplant hardware, tank contents, radio gear, battery, landing gear and ballast—with each mass and centroid where accessible. Catalog mass can seed a row, but measured installed mass should supersede it.

A report on NASA's PRANDTL-D aircraft gives a direct example: three zeroed scales under known support points supplied reaction weights; summing reaction times position and dividing by total weight yielded CG in the measured directions. This checks a component inventory and can reveal omitted or misplaced mass. The tested vehicle was a 12.3 ft subscale flying wing, so its setup and values do not transfer to a Stick. The report selected which inertia terms to measure based on their effect on the flight-analysis result. Here, estimate all properties first, then prioritize measurements for values the simple model is sensitive to. [Callan, “Test and Analysis of the Mass Properties for the PRANDTL-D Aircraft”](https://dione.carthage.edu/ojs/index.php/wsc/article/download/50/50).

#### Estimating the distribution before measurement

NASA's OpenVSP guide illustrates a useful estimate: assign volume or surface density to modeled components, enter discrete hardware as point masses, and report per-component mass, CG and inertia plus totals. Slicing resolution and overlapping geometry affect results; the guide recommends comparison with handbook methods or similar aircraft. A simplified CAD model can produce a first estimate but cannot resolve unknown material or hardware distribution. A centroid point mass omits a wing's own spanwise and chordwise inertia unless intrinsic inertia is supplied; segmented masses or surface density better represent that spread. These remain estimates until checked against a build. [NASA OpenVSP: Mass Analysis](https://www.nasa.gov/reference/openvsp-mass-analysis/).

#### Measuring inertia and accounting for uncertainty

Jardin and Mueller's original AIAA study applies a bifilar (two-wire) pendulum to aircraft: suspend the test article from two parallel filars so it oscillates about the chosen axis, measure the wire geometry and angular motion over time, and infer inertia from a dynamic model. The authors modeled viscous and aerodynamic damping and fit the measured motion rather than relying only on an ideal undamped-period formula. They first checked their apparatus against a uniform aluminum bar whose inertia followed from its dimensions; the pendulum result was within 0.5% of that geometric value. With large foam damping paddles, apparent measured inertia was about 12% higher, illustrating that air entrained by broad surfaces can matter. Their UAV application measured yaw-axis inertia; it is not a ready-made full tensor for this Stick. [Jardin & Mueller, AIAA 2007-6822](https://doi.org/10.2514/6.2007-6822) · [author-hosted conference PDF](https://www.researchgate.net/profile/Matthew-Jardin-2/publication/317290050_UAVMoIWithBifilarPendulum/links/59305b2d0f7e9beee761e2f6/62007-6822.pdf).

Preserve an uncertainty range, not just one inertia number. Record configuration, CG/axis alignment, filar length and separation, fixture tare, oscillation data, repeat runs and reduction assumptions. The paper shows error depends on pendulum dimensions and timing, and that broad surfaces can disturb the result. Validate a future bench fixture with an object of calculable inertia, repeat the aircraft measurement, and report repeatability separately from model uncertainty. Yaw measurement does not establish pitch or roll; reconfigure for those axes or label them estimated.

#### Geometry still missing

The manual audit found linear control throws but no hinge-to-measurement distance or full section/hinge geometry. Do not convert inches directly to degrees. Resolving those dimensions remains separate from the rigid-body mass-property estimate; revisit surface-level inertia only if moving-surface dynamics become part of the model.

**Recommended evidence path (proposal):** build a source-tagged mass/geometry manifest for one named .60 configuration; use manual dimensions and published CG/weight only as provisional bounds; enter physically weighed installed groups and positions when available; create a density/point-mass CAD estimate; then measure selected principal-axis inertias with a repeatable pendulum and compare. No Stick-specific inertia or component masses were discovered in this pass, and no physical measurements were made. All proposed values should remain replaceable and carry their source, configuration, method and uncertainty.

### Low-speed, stall, control, and propwash evidence for the first .60 Stick

**Follow-up to `RESEARCH.md`; research only, 2026-10-05.** The notebook already explains Reynolds number, the UIUC low-speed archive, XFOIL's weak post-stall accuracy, and that no Stick stall boundary or control derivatives are documented. These sources add measured low-Re examples for control-surface response, finite-wing stall transients, and propeller-on-wing effects. None tests an Ultra Stick or Ugly Stick. They are generic evidence and should not be described as calibration for either airplane.

A dimensional check puts the missing data in context. The Hangar 9 Ultra Stick .60 manual gives the conventional wing as 66 in span and 913 in² area. Treating area divided by span as an approximate mean chord gives 0.351 m. With an explicitly assumed air kinematic viscosity of 1.5×10⁻⁵ m²/s, illustrative speeds of 5, 10, 15, 20, and 25 m/s correspond to chord Reynolds numbers of about 117k, 234k, 351k, 468k, and 585k. These are a search bracket, not measured Stick speeds or a stall-speed claim; local chord, exact variant, air conditions, and flight-speed envelope remain unresolved. ([manufacturer manual](https://www.astramodel.cz/manualy/hangar9/hangar9_ultra_stick_60.pdf))

**Control effectiveness changes with separation.** Anyoji et al. tested flapped NACA 0012, NACA 0006, and a 3%-thick flat plate in a low-speed tunnel across Re 20k–80k. The force models had 100 mm chord, used a flap from 70% chord to the trailing edge, and swept flap deflection from 0° to 20° and angle of attack from −4.5° to 22.5°. At Re 20k, NACA 0012 showed nonlinear lift and flap response; from 0° to 3° flap it produced little lift change below about 5° angle of attack. The thinner sections had less nonlinear response in those cases. Their pressure observations link this behavior to upper/lower-surface separation and laminar separation bubbles. The authors caution that flow unsteadiness may contaminate their high-angle measurements, so the control-effectiveness discussion focuses mainly on 0° and 6° angle of attack. This makes a constant “control angle × fixed effectiveness” rule suspect near separation. The study does not provide an Ultra Stick elevator or aileron derivative: it is a two-dimensional section with a large plain flap, and its Reynolds numbers sit mostly below the dimensional screen above. [Open paper and methods](https://www.jstage.jst.go.jp/article/jfst/9/5/9_2014jfst0072/_pdf/-char/en)

**Stall can retain history and respond to pitch rate.** Toppings and Yarusevych tested an NACA 0018 section and an AR 2.5 finite wing with 0.20 m chord at Re 80k–100k, using direct forces and particle-image velocimetry. For the wing, quasi-static increasing-angle stall was about 12° and decreasing-angle reattachment about 11.3°; the authors report substantial lift hysteresis. During pitch-up transients, the lift loss depends on pitch rate and can occur after the static stall boundary. This is a useful measured example for why one angle threshold can make stall recovery artificially reversible or instantaneous. Its Re is lower than much of the illustrative Stick range, its airfoil and aspect ratio are not the Stick, and the authors make supporting data available on reasonable request rather than as a public dataset. [Open JFM paper](https://www.cambridge.org/core/journals/journal-of-fluid-mechanics/article/transient-dynamics-of-stall-and-reattachment-at-low-reynolds-number/F97A76B0038B843B58BDC6625B67A8F2)

**Tractor propwash changes local wing flow, but the result is configuration-dependent.** Ananda, Deters, and Selig's open 2018 experiment used a rectangular FX 63-137 wing of AR 4 and 89 mm chord, with small 3–5 in propellers, in tractor and pusher arrangements. Although the paper discusses low-Re applications around 50k–300k, this wing experiment reports Re 60k–90k. For its tractor setup, oil-flow visualization showed transition in the slipstream region and separation-bubble changes outside it; the paper reports lift-to-drag improvements up to 70% under tested conditions. It says effects depend on advance ratio, blade count, prop diameter relative to span, and local dynamic pressure/angle of attack. The pusher case behaved differently. This is strong evidence against treating propwash as a universal constant tail multiplier, but it measures a wing, not tail control authority, and its tiny-prop/wing ratios and airfoil do not match a .60 Stick installation. [Accessible author-deposited paper](https://portfolio.erau.edu/ws/portalfiles/portal/39868925/Experiments%20of%20Propeller-Induced%20Flow%20Effects%20on%20a%20Low-Reynolds-N.pdf) · [DOI](https://doi.org/10.2514/1.J056667)

**Data lead, without choosing a section.** UIUC's Low-Speed Airfoil Tests publish tabulated data as plain ASCII. Their catalog includes a symmetric NACA 64A010 section with separate measured lift and drag runs spanning the Re 20k–300k band; this can serve as a data-ingestion or symmetric-section comparison case, not as evidence that the Stick uses that airfoil. The UIUC archive's broader volumes cover 30k–500k, but an airfoil polar remains section data and does not include finite-wing stall progression, Stick geometry, propwash, or hinge mechanics. The existing notebook records UIUC's specific reuse conditions for these airfoil performance datasets. [Dataset index and NACA 64A010 run table](https://m-selig.ae.illinois.edu/uiuc_lsat.html) · [Volume 1 catalog](https://m-selig.ae.illinois.edu/uiuc_lsat/AirfoilsVolume1.pdf)

If later experiments justify more detail, candidates include Reynolds-indexed lift/drag, nonlinear surface effectiveness, and a gradual or history-aware stall state; propwash could be explored as a separately switchable local-flow increment. A first simple airplane does not require all of these mechanisms. These are modeling hypotheses, not validation claims. The next useful aircraft-specific evidence would be measured wing section/planform and local chord, control hinge geometry, actual speed/prop rpm traces, and powered versus unpowered control response on one identified Stick configuration. Until then, preserve the evidence ranges above and label the .60 airframe's coefficients provisional.

### What is stronger now, and what still needs execution

| Weak point | Progress in this pass | Remaining limitation |
| --- | --- | --- |
| Propeller prediction confidence | Executed a reproducible static comparison at 16 measured speeds | Advancing flow, 12×6 Sport measurements and the actual engine installation remain unvalidated. |
| Aircraft inertia | Found concrete component-estimation and measurement methods, including apparatus-error examples | No measured .60 Stick inertia tensor or component inventory was found. |
| Low-speed control and stall | Located experiments with explicit geometry, Reynolds ranges and history-dependent behavior | Their coefficients cannot be transferred directly to the chosen aircraft family. |
| Propwash | Found a measured wing-interaction study and its configuration limits | Tail authority and installed propeller effects on our aircraft remain unknown. |
| Technology and pilot experience | Existing comparison and observation protocols still apply | No renderer/export comparison, transmitter hardware check or participant session was performed. |

The most useful next software experiment remains a small visible airplane with inspectable controls and forces. A provisional physical model can accompany it, with assumptions labeled. More literature alone will not resolve edit/run friction, device compatibility, readability from the ground, or pilot preferences; those questions need executed prototypes and observations. This is a suggested direction for further investigation, not a new stack decision or implementation requirement.

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

**Research log — 2026-10-05, second pass:** added ten investigations covering ground handling, launches, servos, floatplanes, training transfer, accessibility, shared control, aircraft packages, offline distribution, and parameter identification. Added original-source findings and possible experiments while preserving the distinction between documented behavior and untested project ideas.

**Research log — 2026-10-05, third pass:** added ten investigations into Geometry Nodes, aircraft rigging, generative 3D, RenderDoc, Tracy, asset optimization, repository-aware coding tools, editor MCP bridges, reproducible development environments, and asset source versioning. Preserved upstream capability claims, access limitations, and unperformed experiments separately. No tools were installed and no additional project decisions were made.

**Research log — 2026-10-05, fourth pass:** added ten investigations into entity-component libraries, math and quantity types, Lua embedding, developer inspection panels, sanitizers, generated-input testing, virtual file access, library dependency resolution, audio implementation, and task scheduling. Recorded original sources, capability boundaries, and possible experiments without selecting a language, architecture, or dependency. No libraries were installed or runtime tests performed.

**Research log — 2026-10-05, fifth pass:** investigated SuperTuxKart, Neverball, Pioneer, Rigs of Rods, VDrift, OpenRocket, the Godot TPS demo, Endless Sky, OpenTTD, and TinyRenderer. Added concrete source-reading paths, implementation observations, limitations, and small possible experiments. No upstream code or assets were imported, and no architecture or technology was selected.

**Research log — 2026-10-05, sixth pass:** investigated trimmed initialization, airfoil extrapolation, ground effect, end-to-end latency, interrupted input, distant-aircraft rendering, numerical convergence, structured experiment traces, repeatable visual evidence, and parameter sensitivity. Added original-source findings and small proposed experiments, keeping numerical correctness, physical validity, and player experience distinct. No experiments were run or new project decisions made.

**Research log — 2026-10-05, seventh pass:** deepened three priority gaps. Compared Ultra Stick 25e, FASER, and Aerosonde reference routes; pinned the Ultra Stick configuration and checked four XML files; documented mismatched source parameters; specified a fair two-approach prototype comparison; and inspected six original pilot reports with an observation protocol. No simulator builds, flight validation, participant observations, or outreach were performed. All project technology and aircraft choices remain open.

**Research log — 2026-10-05, eighth pass:** compared original Ultra Stick .60 and Big Stik .60 ARF manuals, checked unit and variant mismatches, investigated exact O.S. engine and APC/UIUC propeller references, traced a historical CRRCSim propulsion implementation, checked JSBSim piston-model limits, and examined a configuration-specific historical handling report. Manufacturer specifications, predictions, measured propeller data, source inspection and pilot impressions remain distinct. No simulator builds, propulsion plots, flight tests or participant sessions were performed. The first-aircraft family remains chosen; its exact variant and all technology choices remain open.

**Research log — 2026-10-05, ninth pass:** executed a 16-point static comparison of APC Sport 11×6 predicted and measured coefficients, preserved a standalone reproduction script, investigated mass/inertia estimation and measurement uncertainty, and examined low-Re control, stall hysteresis and propwash experiments. Checked the measured-data transcription and interpolation behavior. No simulator, physical aircraft test, renderer comparison or pilot session was run; no exact variant or technology was selected.
