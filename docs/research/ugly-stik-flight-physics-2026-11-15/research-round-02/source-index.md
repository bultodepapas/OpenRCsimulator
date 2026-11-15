# Source index

The five source registers contain **107 uniquely identified records** and **105 distinct URLs**, accessed for this work on 2026-11-15. A record can identify a paper, official API/manual, exact source file, license notice or original developer discussion. This is not a count of independent physical studies of the Stik.

The JSON registers retain the claim supported, applicability limits, version/date and reuse caveat for each record. Read those limits and the corresponding investigation before importing data or code. Moving documentation/branch links are identified as such; the second-round engine records include exact commit and blob identities. Primary maintainer experience is a lead, not a controlled experiment.

## Input, calibration and validation

Full metadata: [sources-inputs.json](sources-inputs.json) (25 records).

| ID | Primary source | Kind | Investigations | Version/date |
| --- | --- | --- | --- | --- |
| IN-S01 | [Godot 4.8 beta 2 release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta2) | official release | R01 | 2026-10-29, engine cafc17a192acf67903910a68aeb3c076c0907a4b |
| IN-S02 | [Godot controllers guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html) | official documentation | R01 | 4.7 documentation, accessed 2026-11-15 |
| IN-S03 | [Godot Input class](https://docs.godotengine.org/en/latest/classes/class_input.html) | official documentation | R01, R03 | latest unstable, accessed 2026-11-15 |
| IN-S04 | [SDL_GetJoystickAxis](https://wiki.libsdl.org/SDL3/SDL_GetJoystickAxis) | official API documentation | R01, R02 | SDL3 API since 3.2.0; living page |
| IN-S05 | [SDL_GetJoystickAxisInitialState](https://wiki.libsdl.org/SDL3/SDL_GetJoystickAxisInitialState) | official API documentation | R01 | SDL3 API since 3.2.0; living page |
| IN-S06 | [SDL_UpdateJoysticks](https://wiki.libsdl.org/SDL3/SDL_UpdateJoysticks) | official API documentation | R01 | SDL3 API since 3.2.0; living page |
| IN-S07 | [Godot issue 111231: unmapped flight joystick axes](https://github.com/godotengine/godot/issues/111231) | original developer issue | R01 | 2025-10-03; discussion through 2026-06-21 |
| IN-S08 | [ArduPilot radio control calibration](https://github.com/ArduPilot/ardupilot_wiki/blob/master/common/source/docs/common-radio-control-calibration.rst) | official documentation source | R02 | master, accessed 2026-11-15 |
| IN-S09 | [QGroundControl Radio Setup](https://docs.qgroundcontrol.com/Stable_V5.0/en/qgc-user-guide/setup_view/radio.html) | official documentation | R02 | Stable V5.0, accessed 2026-11-15 |
| IN-S10 | [SDL_JoyAxisEvent](https://wiki.libsdl.org/SDL3/SDL_JoyAxisEvent) | official API documentation | R02, R03 | SDL3 API since 3.2.0; living page |
| IN-S11 | [SDL_JoystickID](https://wiki.libsdl.org/SDL3/SDL_JoystickID) | official API documentation | R03 | SDL3 API since 3.2.0; living page |
| IN-S12 | [SDL joystick background-events hint](https://wiki.libsdl.org/SDL3/SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS) | official API documentation | R03 | SDL3 API since 3.2.0; living page |
| IN-S13 | [Godot controller guide: focus and identity](https://docs.godotengine.org/en/latest/tutorials/inputs/controllers_gamepads_joysticks.html) | official documentation | R03 | latest unstable, accessed 2026-11-15 |
| IN-S14 | [Godot issue 112802: Windows hot-plug](https://github.com/godotengine/godot/issues/112802) | original developer issue | R03 | 2025-11-15, closed/archived |
| IN-S15 | [Godot: fixing jitter, stutter and input lag](https://docs.godotengine.org/en/latest/tutorials/rendering/jitter_stutter.html) | official documentation | R04 | latest unstable, accessed 2026-11-15 |
| IN-S16 | [NVIDIA Latency and Display Analysis Tool](https://developer.nvidia.com/nvidia-latency-display-analysis-tool) | manufacturer documentation | R04 | undated, accessed 2026-11-15 |
| IN-S17 | [Microsoft GameInput Dynamic Latency Input](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/advanced/input-synchronization?view=gdk-2604) | official documentation | R04 | GDK 2604, updated 2026-03-07 |
| IN-S18 | [JSBSim frames of reference](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/) | official manual | R17 | living manual, accessed 2026-11-15 |
| IN-S19 | [JSBSim equations of motion and ground reaction diagram](https://jsbsim-team.github.io/jsbsim-reference-manual/formulation/equations-of-motion/) | official manual | R17 | 2026-10-24 page date |
| IN-S20 | [FlightGear discussion: GroundReactions documentation](https://forum.flightgear.org/viewtopic.php?f=49&t=21803) | original developer forum | R17 | 2014-01-13 |
| IN-S21 | [A method for landing gear modeling and simulation with experimental validation](https://ntrs.nasa.gov/citations/19960049759) | original research | R17 | NASA-CR-201601, 1996-06-01 |
| IN-S22 | [Experimental and analytical determination of characteristics affecting light aircraft landing-gear dynamics](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19780003109.pdf) | original research | R17 | NASA-TM-X-3561, 1977-11-01 |
| IN-S23 | [Flight Test Validation of Optimal Input Design and Comparison to Conventional Inputs](https://ntrs.nasa.gov/citations/20040105626) | original research | R18 | AIAA 97-3711, 1997 |
| IN-S24 | [Flight Test Maneuvers for Efficient Aerodynamic Modeling](https://ntrs.nasa.gov/citations/20110014634) | original research | R18 | AIAA paper, 2011-08-08 |
| IN-S25 | [Dependence of Dynamic Modeling Accuracy on Sensor Measurements, Mass Properties, and Aircraft Geometry](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/20140003885.pdf) | original research | R18 | NASA/TM-2013-218056, 2013-11-01 |

## Aerodynamics, propulsion and measurement

Full metadata: [sources-physics.json](sources-physics.json) (29 records).

| ID | Primary source | Kind | Investigations | Version/date |
| --- | --- | --- | --- | --- |
| PHY-S01 | [Surface Oil Flow Measurements on Several Airfoils at Low Reynolds Numbers](https://m-selig.ae.illinois.edu/pubs/McGranahanSelig-2003-AIAA-2003-4067-LRN-Airfoils.pdf) | experimental paper | R05 | AIAA 2003-4067, 2003 |
| PHY-S02 | [Wind Tunnel Testing Airfoils at Low Reynolds Numbers](https://m-selig.ae.illinois.edu/pubs/SeligDetersWilliamson-2011-AIAA-2011-875-LRN-AirfoilWindTunnelTesting.pdf) | experimental paper | R05 | AIAA 2011-875 |
| PHY-S03 | [UIUC Wind Tunnel Data use terms](https://m-selig.ae.illinois.edu/pd.html) | official data terms | R05 | Undated page, accessed 2026-11-15 |
| PHY-S04 | [UIUC Propeller Database Volume 4](https://m-selig.ae.illinois.edu/props/volume-4/propDB-volume-4.html) | experimental dataset | R06 | v1, 2022-06-12 |
| PHY-S05 | [Performance Testing of APC Electric Fixed-Blade UAV Propellers](https://m-selig.ae.illinois.edu/pubs/DantskerCaccamoDetersSelig-2022-AIAA-Paper-2022-4020-APCEPropTestsVol4.pdf) | experimental paper | R06 | AIAA 2022-4020 |
| PHY-S06 | [Negative Thrust and Torque Characteristics of an Adjustable-Pitch Metal Propeller](https://ntrs.nasa.gov/citations/19930091538) | experimental report | R06 | NACA TR-464, 1934 |
| PHY-S07 | [Slipstream Measurements of Small-Scale Propellers at Low Reynolds Numbers](https://m-selig.ae.illinois.edu/pubs/DetersAnandaSelig-2015-AIAA-2015-2265-LRN-PropSlipstream.pdf) | experimental paper | R07 | AIAA 2015-2265 |
| PHY-S08 | [Longitudinal stability and control with special reference to slipstream effects](https://ntrs.nasa.gov/search.jsp?R=19930091767) | experimental report | R07 | NACA TR-690, 1940 |
| PHY-S09 | [Modeling, System Measurements and Controller Investigation of a Small Battery-Powered Fixed-Wing UAV](https://www.mdpi.com/2075-1702/9/12/333) | experimental paper | R08 | Machines 9(12), 333, 2021 |
| PHY-S10 | [Hobbywing Platinum 60A V4 ESC](https://www.hobbywing.com/en/products/platinum-60a-v473.html) | manufacturer documentation | R08 | V4 product page, accessed 2026-11-15 |
| PHY-S11 | [Practical Battery Thermal Modeling Techniques](https://ntrs.nasa.gov/citations/20205006303) | research report | R08 | 2020 |
| PHY-S12 | [O.S. MAX-50SX and 40/46/61/91 FX Owner Instruction Manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf) | manufacturer manual | R09 | FX series manual, date not specified |
| PHY-S13 | [O.S. FS-64V product specifications](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html) | manufacturer specification | R09 | FS-64V page, accessed 2026-11-15 |
| PHY-S14 | [O.S. Suggested Propeller Sizes](https://www.os-engines.co.jp/english/line_up/propelle/prop.htm) | manufacturer guidance | R09 | Undated page, accessed 2026-11-15 |
| PHY-S15 | [APC Propellers RPM Limits](https://www.apcprop.com/technical-information/rpm-limits/) | manufacturer guidance | R09 | Undated page, accessed 2026-11-15 |
| PHY-S16 | [An Accurate Method of Measuring the Moments of Inertia of Airplanes](https://ntrs.nasa.gov/citations/19930081105) | experimental report | R10 | NACA TN-351, 1930 |
| PHY-S17 | [Methods for Accurate Measurements of Small Fixed Wing UAV Inertial Properties](https://www.cambridge.org/core/journals/aeronautical-journal/article/abs/methods-for-accurate-measurements-of-small-fixed-wing-uav-inertial-properties/507615BF6196D73BAE1747286D49F3FA) | experimental paper | R10 | Lehmkühler, Wong and Verstraete, 2016, doi:10.1017/aer.2016.105 |
| PHY-S18 | [Lifting Line Free Vortex Wake](https://docs.qblade.org/src/theory/aerodynamics/lifting_line/lifting_line.html) | official technical documentation | R11 | QBlade documentation 2.0.9.7 |
| PHY-S19 | [OpenFAST OLAF Theory](https://github.com/OpenFAST/OpenFAST/blob/main/docs/source/user/aerodyn-olaf/OLAFTheory.rst) | official implementation documentation | R11 | Moving main branch, accessed 2026-11-15 |
| PHY-S20 | [Forced Oscillation Wind Tunnel Testing for FASER Flight Research Aircraft](https://ntrs.nasa.gov/citations/20120014506) | experimental paper | R12 | NASA/NF1676L-14053, 2012 |
| PHY-S21 | [Experimental Investigation of Static Stall Hysteresis and 3-Dimensional Flow Structures for an NREL S826 Wing Section of Finite Span](https://www.mdpi.com/1996-1073/11/6/1418) | experimental paper | R12 | Energies 11(6), 1418, 2018 |
| PHY-S22 | [OpenFAST AeroDyn Modeling Considerations](https://github.com/OpenFAST/OpenFAST/blob/main/docs/source/user/aerodyn/modeling.rst) | official implementation documentation | R12 | Moving main branch, accessed 2026-11-15 |
| PHY-S23 | [QBlade Oye Dynamic Stall Model](https://docs.qblade.org/src/theory/aerodynamics/dynamic_stall/OYE_stall.html) | official technical documentation | R12 | QBlade documentation 2.0.9.7 |
| PHY-S24 | [Rotary Balance Wind Tunnel Testing for the FASER Flight Research Aircraft](https://ntrs.nasa.gov/citations/20160010112) | experimental paper | R12 | NASA 2016 |
| PHY-S25 | [The Experimental Determination of the Moments of Inertia of Airplanes](https://ntrs.nasa.gov/citations/19930091541) | experimental report | R10 | NACA TR-467, 1934 |
| PHY-S26 | [OpenFAST source repository](https://github.com/OpenFAST/openfast) | maintainer repository | R12 | Moving main, accessed 2026-11-15 |
| PHY-S27 | [UIUC Low-Speed Airfoil Tests Airfoils Tested](https://m-selig.ae.illinois.edu/uiuc_lsat_airfoilsTested.html) | official dataset index | R05 | Undated index, accessed 2026-11-15 |
| PHY-S28 | [JSBSim discussion 850: How to get the propeller aerodynamic coefficient?](https://github.com/JSBSim-Team/jsbsim/discussions/850) | developer discussion | R06 | 2023-03-02, cites commit ebb770e |
| PHY-S29 | [VortexLattice.jl](https://github.com/byuflowlab/VortexLattice.jl) | maintainer repository | R11 | Moving master, accessed 2026-11-15 |

## Numerics, reuse and experiments

Full metadata: [sources-review.json](sources-review.json) (28 records).

| ID | Primary source | Kind | Investigations | Version/date |
| --- | --- | --- | --- | --- |
| REV-S01 | [SciPy: scipy.linalg.eig](https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.linalg.eig.html) | official documentation | R13 | SciPy 1.17.0 |
| REV-S02 | [LAPACK DGEES: real nonsymmetric Schur form](https://netlib.org/lapack/explore-html/d5/d38/group__gees_gab48df0b5c60d7961190d868087f485bc.html) | upstream numerical documentation | R13 | LAPACK online reference, accessed snapshot |
| REV-S03 | [Franklin: V/STOL Dynamics, Control, and Flying Qualities](https://ntrs.nasa.gov/api/citations/20010038495/downloads/20010038495.pdf) | NASA technical publication | R13 | NASA/TP-2000-209591, 2000 |
| REV-S04 | [SciPy: scipy.optimize.least_squares](https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.optimize.least_squares.html) | official documentation | R14 | SciPy 1.17.0 |
| REV-S05 | [AUTO-07P continuation and bifurcation software](https://github.com/auto-07p/auto-07p) | upstream project | R14 | Repository branch inspected; exact dependency version not selected |
| REV-S06 | [JSBSim discussion: Update FGTrimAnalysis](https://github.com/JSBSim-Team/jsbsim/discussions/988) | upstream developer discussion | R14 | 2023-11 discussion #988 |
| REV-S07 | [Godot ProjectSettings: maximum physics steps](https://docs.godotengine.org/en/4.5/classes/class_projectsettings.html) | official documentation | R15 | Godot 4.5 documentation |
| REV-S08 | [Godot physics interpolation introduction](https://docs.godotengine.org/en/4.5/tutorials/physics/interpolation/physics_interpolation_introduction.html) | official documentation | R15 | Godot 4.5 documentation |
| REV-S09 | [Erin Catto: Determinism](https://box2d.org/posts/2024/08/determinism/) | original developer article | R15 | 2024-08-27 |
| REV-S10 | [Glenn Fiedler: Fix Your Timestep!](https://www.gafferongames.com/post/fix_your_timestep/) | original developer article | R15 | Undated page; accessed snapshot |
| REV-S11 | [SciPy: scipy.integrate.solve_ivp](https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.integrate.solve_ivp.html) | official documentation | R16 | SciPy 1.17.0 |
| REV-S12 | [JSBSim discussion: Review state propagation procedure](https://github.com/JSBSim-Team/jsbsim/discussions/1391) | upstream developer discussion | R16 | 2026, discussion #1391; cited source excerpt short commit 3003423 |
| REV-S13 | [JSBSim README legal notice](https://github.com/JSBSim-Team/jsbsim/blob/master/README.md) | upstream license notice | R23 | Upstream master inspected; exact distribution not selected |
| REV-S14 | [JSBSim version 1.3.3 release](https://github.com/JSBSim-Team/jsbsim/releases/tag/v1.3.3) | upstream release | R23 | v1.3.3, displayed short commit 66f7faf |
| REV-S15 | [AVL upstream overview](https://web.mit.edu/drela/Public/web/avl/) | upstream project documentation | R23 | Upstream web page, accessed snapshot |
| REV-S16 | [AVL source avl.f license header](https://github.com/RobotLocomotion/avl/blob/master/src/avl.f) | authored source license notice | R23 | Mirror master header copyright 2002, accessed snapshot |
| REV-S17 | [AeroSandbox LICENSE.txt](https://github.com/peterdsharpe/AeroSandbox/blob/master/LICENSE.txt) | upstream license text | R23 | Master license inspected; exact release not selected |
| REV-S18 | [OpenFAST LICENSE](https://github.com/OpenFAST/openfast/blob/main/LICENSE) | upstream license text | R23 | Main branch license inspected; exact release not selected |
| REV-S19 | [SciPy LICENSE.txt](https://github.com/scipy/scipy/blob/main/LICENSE.txt) | upstream license text | R23 | Main branch license inspected; 1.17.0 was used in earlier offline analysis |
| REV-S20 | [SciPy bundled licenses](https://github.com/scipy/scipy/blob/main/LICENSES_bundled.txt) | upstream bundled-license inventory | R23 | Main branch inventory inspected; exact wheel not selected |
| REV-S21 | [Tracy LICENSE](https://github.com/wolfpld/tracy/blob/master/LICENSE) | upstream license text | R23 | Master license inspected; exact release not selected |
| REV-S22 | [Perfetto LICENSE](https://github.com/google/perfetto/blob/main/LICENSE) | upstream license text | R23 | Main license inspected; exact release not selected |
| REV-S23 | [pyperf COPYING](https://github.com/psf/pyperf/blob/main/COPYING) | upstream license text | R23 | Main license inspected; exact release not selected |
| REV-S24 | [AeroSandbox pyproject metadata](https://github.com/peterdsharpe/AeroSandbox/blob/master/pyproject.toml) | upstream package metadata | R23 | Master metadata displayed version 4.2.10 when accessed |
| REV-S25 | [Godot: The Profiler](https://docs.godotengine.org/en/4.5/tutorials/scripting/debug/the_profiler.html) | official documentation | R24 | Godot 4.5 documentation |
| REV-S26 | [pyperf: Tune the system for benchmarks](https://pyperf.readthedocs.io/en/stable/system.html) | upstream documentation | R24 | Stable page displayed pyperf 2.11.0 when accessed |
| REV-S27 | [Google Benchmark: random interleaving](https://github.com/google/benchmark/blob/main/docs/random_interleaving.md) | upstream documentation | R24 | Main branch documentation inspected; exact release not selected |
| REV-S28 | [Google Benchmark issue 1051: random interleaving](https://github.com/google/benchmark/issues/1051) | upstream developer issue | R24 | Opened 2020-10-05 |

## Evidence tools and profiling

Full metadata: [sources-lead.json](sources-lead.json) (10 records).

| ID | Primary source | Kind | Investigations | Version/date |
| --- | --- | --- | --- | --- |
| LEAD-S01 | [Python 3.12 subprocess — TimeoutExpired](https://docs.python.org/3.12/library/subprocess.html#subprocess.TimeoutExpired) | official documentation / primary project source | R19 | Python 3.12 documentation (page reports 3.12.16); execution uses 3.12.14 |
| LEAD-S02 | [Python 3.12 JSON — interoperability and decoder hooks](https://docs.python.org/3.12/library/json.html#standard-compliance-and-interoperability) | official documentation / primary project source | R19, R20 | Python 3.12 documentation |
| LEAD-S03 | [Python 3.12 concurrent.futures — Executor.map](https://docs.python.org/3.12/library/concurrent.futures.html#concurrent.futures.Executor.map) | official documentation / primary project source | R19 | Python 3.12 documentation |
| LEAD-S04 | [pytest exit codes](https://docs.pytest.org/en/stable/reference/exit-codes.html) | official documentation / primary project source | R20 | Rolling stable documentation retrieved 2026-11-15 |
| LEAD-S05 | [JSON Schema array validation](https://json-schema.org/understanding-json-schema/reference/array) | official documentation / primary project source | R20 | Rolling official guide retrieved 2026-11-15 |
| LEAD-S06 | [W3C PROV-DM](https://www.w3.org/TR/2013/REC-prov-dm-20130430/) | official documentation / primary project source | R21 | W3C Recommendation 2013-04-30 |
| LEAD-S07 | [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots) | official documentation / primary project source | R21 | Rolling official documentation retrieved 2026-11-15 |
| LEAD-S08 | [Godot — The Profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html) | official documentation / primary project source | R22 | Rolling stable documentation retrieved 2026-11-15 |
| LEAD-S09 | [Godot — General optimization tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html) | official documentation / primary project source | R22 | Rolling stable documentation retrieved 2026-11-15 |
| LEAD-S10 | [Godot — Using C++ profilers](https://docs.godotengine.org/en/stable/engine_details/development/profiling/index.html) | official documentation / primary project source | R22 | Rolling stable documentation retrieved 2026-11-15 |

## Second round: exact input backend

Full metadata: [sources-inputs-second-round.json](sources-inputs-second-round.json) (15 records).

| ID | Primary source | Kind | Investigations | Version/date |
| --- | --- | --- | --- | --- |
| IN2-S01 | [Godot 4.8-beta2 release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta2) | official release | S2-01 | 2026-10-29 |
| IN2-S02 | [Pinned Godot SDL joypad driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/sdl/joypad_sdl.cpp) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob 44dfc8f5b641e65aecb4afa25536ad311bf590cc |
| IN2-S03 | [Pinned Godot Input implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/input/input.cpp) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob 23332b06a4489eb46e84f4c913796d498d75917f |
| IN2-S04 | [Pinned Godot Input declarations](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/input/input.h) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob 71d50f909b6406aca34fa3a3b43223989b6badd2 |
| IN2-S05 | [Pinned vendored SDL joystick implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/thirdparty/sdl/joystick/SDL_joystick.c) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob cf08c30b8617bb9b09f0981e795036f0704d451f |
| IN2-S06 | [Pinned vendored SDL version header](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/thirdparty/sdl/include/SDL3/SDL_version.h) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob 6b7816e0d4d792bb611aef799e77278aa2b35943 |
| IN2-S07 | [Pinned Godot third-party inventory](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/thirdparty/README.md) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob 4af7f2b91252a9b7aa0b7f934472f56b343be51d |
| IN2-S08 | [Pinned Godot input-event declarations](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/input/input_event.h) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob 7891510933148730992a5c362d45d4f43247d580 |
| IN2-S09 | [Pinned Godot SceneTree focus notification](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/main/scene_tree.cpp) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob b755ff4296fe98deb2f7c59d06ae73a2af31e0da |
| IN2-S10 | [Pinned Godot main loop](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/main/main.cpp) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob e754e37083e57dc1c3944982d0e33addcbd93ab0 |
| IN2-S11 | [SDL_JoystickID](https://wiki.libsdl.org/SDL3/SDL_JoystickID) | official API documentation | S2-01 | SDL3 API since 3.2.0; living page |
| IN2-S12 | [Godot joypad issue tracker: RadioMaster Pocket report](https://github.com/godotengine/godot/issues/105417) | original developer issue discussion | S2-01 | 2026-08-25 comment |
| IN2-S13 | [Godot 4.8 dev 6 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-6/) | official release announcement | S2-01 | 2026-09-15 |
| IN2-S14 | [Pinned Linux main loop](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/platform/linuxbsd/os_linuxbsd.cpp) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob c654d86217f4c052baa96775cbfc9fa55313a7ce |
| IN2-S15 | [Pinned Windows display server](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/platform/windows/display_server_windows.cpp) | official source | S2-01 | commit cafc17a192acf67903910a68aeb3c076c0907a4b; Git blob c3ebe4b00751946732d48402c9c05588fa34824a |
