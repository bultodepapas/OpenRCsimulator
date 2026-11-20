# Flight Simulator → RC follow-up: physics, calibration, and mod lessons

**Product-direction update:** the later [automatic wizard contract](../../../../plans/flight-simulator-import-wizard.md) owns current delivery acceptance: in-app conversion, questions only for unresolved data and editable results. Earlier preparation/manual-step recommendations in this dated evidence are optional development/recovery proposals; underlying format and physics findings remain unchanged.

Part of the [24-investigation follow-up](README.md). The [feature plan](../../../../plans/flight-simulator-aircraft-import.md) owns acceptance and implementation; [tools and fixtures](tooling-and-fixtures.md) turns these findings into a proposed evaluation backlog.

Research date and access date for **all sources below: 2026-11-16**. Source pages without a publication date are identified by their documented version or by the branch/page state observed on that date; they are not immutable revisions. This is published research, not implementation or a flight qualification. Community posts are first-person reports or development leads, not independent physical validation. No tools, aircraft, SDK components, or binaries were installed or run.

## R13: Low Reynolds tools and airfoil data

**Question.** How can low-Reynolds tools inform an RC polar without promising a full aircraft model?

**Sources**

1. [XFOIL source `xfoil.f`](https://github.com/RobotLocomotion/xfoil/blob/master/src/xfoil.f), observed branch `master`, code identifies version 6.97 and GPL-2.0-or-later; [XFOIL user primer and caveats](https://web.mit.edu/drela/Public/web/xfoil/xfoil_doc.txt), author documentation, 6.9 primer last updated 2001-11-30.
2. [XFLR5 v6.10 XFoil class](https://github.com/subprotocol/xflr5/blob/master/xflr5-6.10/src/xdirect/analysis/XFoil.h), observed branch `master`, GPL-2.0-or-later notice; [v6.10 guidelines](https://github.com/subprotocol/xflr5/blob/master/xflr5-6.10/doc/latex/guidelines_en.tex), 2013-era guidelines.
3. NASA, [OpenVSP VSPAERO Basics](https://www.nasa.gov/reference/openvsp-vspaero-basics/), documentation notes OpenVSP 3.45/VSPAERO 7 change; [OpenVSP license](https://github.com/OpenVSP/OpenVSP/blob/main/LICENSE), observed `main`, NASA Open Source Agreement 1.3.
4. UIUC, [Wind Tunnel Data](https://m-selig.ae.illinois.edu/pd.html), observed page updated through 2026; [UIUC Airfoil Data Site](https://m-selig.ae.illinois.edu/ads.html), undated coordinate catalog.
5. OpenVSP, [Issue #362: VSPAERO config from old versions may result in control surfaces not found](https://github.com/OpenVSP/OpenVSP/issues/362), 2026-03-21, 3.42.3 → 3.48.2 user report.

**Observed.** XFOIL estimates two-dimensional airfoil behavior; its caveats explicitly identify low Reynolds number, massive separation, unsteady flow and insufficient resolution of separation bubbles as possible viscous-solver failure cases. XFLR5 combines translated XFOIL and finite-wing analysis for model aircraft; its guidelines question applying two-dimensional transition results to finite wings. OpenVSP is parametric geometry plus VSPAERO analysis; NASA says its reference area, span and chord normalize computed loads, and its older guide predates substantial solver-7 changes. A user reported lost control-surface references on opening an older project in a newer VSPAERO version. A catalog of *coordinates* is not a wind-tunnel polar. UIUC's airfoil performance data carry a specific GPL-related notice, attribution, inclusion of license/copyright/manifest and commercial-product conditions; check the specific dataset, not just the site name. OpenVSP NOSA and GPL-covered source obligations require separate component review.

**Inference and limits.** An externally generated sectional polar is a candidate input/measurement comparison, not directly a complete 3-D aircraft law. Transition settings, surface roughness, airfoil identity, actual low-Re range, solver version, grid/panel settings and non-converged points matter. A VLM/panel solution can inform geometry trends but cannot alone establish viscous separation, post-stall behavior, propwash or RC control response. The GPL code notices cited are version-specific; do not assume they govern every separately distributed tool, data file or output.

**Proposed addition and acceptance.** Later, add an optional user-supplied evidence record: section/coordinate hash and span station; Reynolds, Mach, transition/roughness, angle and deflection; solver/version, convergence and source data license; coefficient axes/reference; measured versus modeled. Reject missing/failed/nonfinite points and out-of-range extrapolation. A synthetic fixture holds dimensional pitch moment, dynamic pressure, reference area, moment reference point and axes/sign fixed while changing only the reference chord: doubling that chord must halve `Cm`; changing VSPAERO version or geometry hash must make the evidence distinct. A known held-out UIUC polar case may validate the *comparison workflow* within preset tolerances, not the aircraft or AC-12.

## R14: Propeller datasets and operating limits

**Question.** What propeller and electric installation evidence can replace full-scale horsepower?

**Sources**

1. UIUC, [Propeller Database Volume 1](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html), version 3, 2015-02-03; off-the-shelf wind-tunnel and static data.
2. APC, [Performance Data](https://www.apcprop.com/technical-information/performance-data/) and [Engineering](https://www.apcprop.com/technical-information/engineering/), undated live pages; 2022 model update noted.
3. APC, [RPM Limits](https://www.apcprop.com/technical-information/rpm-limits/), undated live manufacturer guidance, and [FAQ](https://www.apcprop.com/faq/), product nomenclature.
4. Rob McDonald, [PropDBTools](https://github.com/ramcdona/PropDBTools), 2021, observed `main`; BSD-2-Clause software license.
5. UIUC, [Propeller Data Site](https://m-selig.ae.illinois.edu/props/propDB.html), observed 2026 site with volumes and separate experiment references.

**Observed.** UIUC Volume 1 supplies measured thrust/torque coefficients over advance ratio at individual RPM, plus static RPM sweeps; its online reduction corrects earlier thesis data. APC explicitly calls its performance files outputs of a proprietary, changing vortex-based calculation, not wind-tunnel results, and recommends test anchoring. Header software version/date therefore matters. The names identify different propeller families: for a 10-inch APC Slow Flyer the suggested limit is `65,000/10 = 6,500 RPM`, while the listed Thin Electric limit is `150,000/10 = 15,000 RPM`; this is family-specific, not a universal diameter rule. PropDBTools warns that some metadata are encoded in multiple filenames and special cases break uniform parsing. Its code license does not license UIUC propeller data; those exact data reuse terms remain unresolved. APC's published data access is not automatically a redistribution grant either.

**Inference and limits.** `10×4.7` is nominal diameter and geometric pitch in inches, not measured advance per revolution or peak aircraft speed. At 6,500 RPM the ideal pitch-speed arithmetic is about 12.93 m/s, with actual operating point affected by slip, torque, current, voltage, inflow and propeller efficiency. For `J=V/(nD)`, doubling RPM at fixed V halves J; thrust need not quadruple because `CT` can change. The familiar 4× thrust/8× shaft-power comparison holds only with the same `CT`/`CP` at the same J, same D and density (thus V also doubles). Avoid `J` division at zero RPM and do not infer advancing performance from static thrust.

**Proposed addition and acceptance.** Record exact propeller family/blades/diameter/pitch, RPM limit, datum provenance, torque versus electrical power, motor/ESC/battery limits, rotation and installation offset. Use only the selected supported estimated electric power package/law, marked experimental, within a Creator domain that passes AC-12 or an independently preregistered substitute. Package support is not flight qualification; there is no implicit table importer or guarantee of a measured product. A synthetic coefficient fixture must verify static `J=0`, constant-J speed doubling with fixed `CT`, `CP`, diameter and density (4× thrust, 8× shaft power), fixed-V changed-J lookup, RPM unit conversion and an explicit stopped-shaft path. Reject unsupported/extrapolated tables and mismatched model/revision. Compare voltage/current/RPM and thrust against independent bench data before any calibrated claim; manufacturer predictions stay labeled modeled.

## R15: Controls and response calibration

**Question.** Which control adjustments describe hardware, pilot preference, or simulator tuning?

**Sources**

1. Microsoft, [2024 `flight_model.cfg`](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/flight_model.cfg/), retail documentation as observed, especially limits, elasticity, tuning and assistance fields.
2. Microsoft, [2020 Geometry](https://docs.flightsimulator.com/html/mergedProjects/How_To_Make_An_Aircraft/Contents/Files/Flight_Model/Geometry.htm), undated tutorial revision; authority and dynamic-pressure elasticity discussion.
3. Flight Simulator forum, [Control sensitivity way too sensitive](https://forums.flightsimulator.com/t/control-sensitivity-way-to-sensitive-same-for-trim-wheel/185961), 2020-08-22 thread.
4. Flight Simulator forum, [How to configure controllers](https://forums.flightsimulator.com/t/how-to-use-the-interface-to-configure-your-controllers/183095), 2020 community guide.
5. MSFS DevSupport, [Flight model aero parameters in 2020 versus 2024](https://devsupport.flightsimulator.com/t/flight-model-aero-parameters-working-in-msfs-2020-but-not-in-msfs-2024/13042), A380X developer reports 2025-02-05 and 2025-08-13.

**Observed.** Microsoft's geometry tutorial separates measured maximum surface deflection from `elevator_effectiveness` and `elevator_maxangle_scalar`; elasticity can further vary authority with dynamic pressure. Source controls may have force-based options and assistance. In the 2020 forum, one reported workaround reduced effectiveness from 1 to 0.2; it changes modeled authority, not simply the shape of a user's stick curve. A controller guide describes its then-current sensitivity curve as preserving endpoints while reshaping intermediate input. In the A380X report, a developer said elevator effectiveness 1.25 resolved a light/forward-CG rotation problem in MSFS 2020, but 1.7 was required in 2024. That is a simulator/version-specific tuning report for an excluded multi-engine airliner, not evidence for RC elevator parameters or a general correction factor.

**Inference and limits.** Keep separate: calibrated transmitter command/dead zone/expo; mixer and channel reversals; supported actuator limits and timing under load; physical surface travel/hinge geometry; visible animation; aerodynamic derivative; and optional assistance. A controller curve cannot establish aerodynamic authority; matching visible endpoints cannot establish servo speed, aerodynamic moment, load response or mixer internals. A source gauge, elasticity table, control computer, user assistance or external transmitter may change the effective relationship. If a mapping requires unsupported mixing, state that rather than quietly approximating it. No empirical hardware timing can be inferred from a source deflection scalar.

**Proposed addition and acceptance.** Add separate provenance and UI rows for pilot profile, physical configuration and source-only tuning, with a per-axis response trace from raw command through supported mix, actuator and visual output to aerodynamic deflection. Test centered and positive/negative endpoints, asymmetric travel, reversal, monotonicity and sign; verify changing expo changes intermediate response while preserving physical endpoint under an endpoint-preserving profile. Verify changing aerodynamic effectiveness affects predicted moments but does not alter commanded/measured hinge travel; independently test a timed servo step only where the target law represents it. Freeze assistance and profile identity in any comparison. Treat a source-reported mod as a fixture for preserving values and modes, not a parameter recommendation.

## R16: Mass balance and contact semantics

**Question.** How should mass, moving CG, and contacts survive user modifications?

**Sources**

1. Microsoft, [2020 Contact Points](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model/contact_points.htm), live section revision observed; includes zero-based field definitions and spring/damping notes.
2. Microsoft, [2024 `flight_model.cfg`](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/flight_model.cfg/), retail page observed, including weight/inertia and advanced-contact fields.
3. Flight Simulator forum, [DA40NG flight-model mod](https://forums.flightsimulator.com/t/flight-model-mod-for-the-da40ng/263331), author and user discussion, 2020-09-09–11.
4. Flight Simulator forum, [YSim SubSonex JSX-2 contact modification](https://forums.flightsimulator.com/t/new-release-ysim-subsonex-jsx-2/424389/62), 2021-07-25, post 62.
5. Flight Simulator forum, [Ground physics and new contact parameters](https://forums.flightsimulator.com/t/please-fix-the-ground-physics-friction-inertia-etc/455009/192), 2024-02-15, post 192.

**Observed.** In the DA40NG mod thread, a user saw an out-of-limits CG display despite the author's stated W&B changes; the author attributed this to displayed MAC positioning, and a later exchange distinguishes DA40-TDI and DA40NG variants. This is an unresolved report, not proof either displayed or live CG was correct. In the SubSonex thread, the user changed three contact rows' compression/damping and reported adoption in version 1.1. Microsoft says default wheel spring/damping are derived using maximum gross weight and CG, and documents contact-order dependence when `point_order_independent_suspension_solver=0`; retain the source version, flag and default rather than generalize that behavior to all solvers. The zero-based `point.N` field 9 is a *ratio* when `set_max_compression=0`, but an absolute distance in feet when 1. Advanced gear flex is compliance, with units distinct from a dimensionless damping ratio; a later community post warned flight-model mods can overwrite new contact effects.

**Inference and limits.** A known total mass or displayed `%MAC` cannot identify individual inventory masses, inertias, live CG, or correctness of gear dynamics. A source empty-aircraft aggregate already includes some equipment: add an RC motor and battery only after explicitly defining the removed/replaced hardware. Source fuel stations are not automatically target consumables. Finite charge depletion in a normal closed electric battery does not by itself mean the battery's mass or location changes; represent live shifts only for supported moving/consumable mass or deliberate ballast. Initial airborne/hand-launch scope must not imply runway-contact qualification.

**Proposed addition and acceptance.** Report source empty and loaded roles, station positions and simulator/version alongside separate RC component inventory, independently calculated tensor and live CG; show assumed versus measured hardware. Add paired parser fixtures with identical `point.N[9]` and opposite `set_max_compression`, expecting unitless ratio versus feet; verify order/type preserved and no source spring constant silently copied. In a synthetic inventory, move a 0.20 kg ballast 0.50 m aft on a 2.0 kg aircraft: CG moves 0.05 m aft; replacing it with an equal-mass fixed battery whose state of charge decreases leaves CG unchanged. Recompute full inertia about live CG and check total mass and reference-point consistency. Ground-support checks and numerical contact tolerances remain a separate later GP gate.

## R17: Telemetry and independent validation

**Question.** Which open telemetry and reference tools are useful without assuming SDK authorization?

**Sources**

1. Microsoft, [2020 SDK EULA](https://docs.flightsimulator.com/html/Introduction/SDK_EULA.htm) and [2024 retail SDK EULA](https://docs.flightsimulator.com/msfs2024/retail/introduction/sdk-eula/), live terms observed 2026-11-16.
2. jbencina, [FSTelemetry](https://github.com/jbencina/fstelemetry), observed `master`, MIT license; 2020 SimConnect logging project.
3. nguyenquyhy, [Flight Recorder](https://github.com/nguyenquyhy/Flight-Recorder), observed `main`, GPL-3.0; recording/replay project.
4. JSBSim Team, [JSBSim](https://github.com/JSBSim-Team/jsbsim), observed `master`, repository identifies LGPL-2.1, standalone flight-dynamics software; [FGOutput](https://github.com/JSBSim-Team/jsbsim/blob/master/src/models/FGOutput.h), output documentation in source.
5. Microsoft, [SimConnect SDK](https://docs.flightsimulator.com/html/Programming_Tools/SimConnect/SimConnect_SDK.htm), 2020 live documentation describing an add-on communication API.

**Observed.** FSTelemetry records configurable variables to CSV, by default polling at one-second intervals; that sampling is inadequate to characterize many fast RC control steps without a separately justified acquisition setup. Flight Recorder exports recorded frame variables but warns that replay freezes the sim, does not reliably auto-start the engine, and has odd ground turns; replay is not an independent physics run. JSBSim can run standalone with configurable dynamics, controls and CSV output, and says requested output rate can depend on integration `dt`; its example aircraft are publicly sourced approximations, not ground truth. Its LGPL code license and an example aircraft's data rights must be checked separately.

Both published SDK agreements restrict use of the SDK/components for development of a competing flight simulator and for competitive benchmarking/analysis, among other purposes. The precise scope of any particular application, third-party library, game runtime component and actual license is a legal question; an MIT or GPL wrapper does **not** authorize restricted SDK use. No claim is made that this project or telemetry collection qualifies for an exception. The current plan already selects no SDK samples, compiler, or benchmarking dependency; keep it that way absent explicit rights review and authorization.

**Inference and limits.** A simulator's trace identifies behavior of a named software/aircraft/version/settings combination; it is not evidence of a real RC aircraft. A useful first campaign instead uses properly authorized independent bench thrust/current/RPM, mass balance, servo travel and RC flight measurements. JSBSim may serve as a separately licensed *comparison of equations/implementation* with independently constructed inputs; matching two simulations or copying their coefficients does not independently validate the physics. Replays with frozen dynamics and uncontrolled assists are especially weak as calibration evidence.

**Proposed addition and acceptance.** Define a tool-neutral, local measurement envelope: origin/rights, exact run and aircraft hash, units and coordinate frame, sample time source/rate/jitter/dropouts, environment, initial CG, controls, motor and assist state, plus calibration/uncertainty. First acceptance uses generated known-answer traces and independent measurement fixtures only: reject missing units, nonmonotonic timestamps and unsupported frames; align sample intervals explicitly and preserve original samples. If a future rights-reviewed source-simulator trace is ever admitted, isolate it from the default test and release gates and label it source behavior; its presence cannot close AC-12 or grant calibration.

## R18: Conditional flight model fields

**Question.** What do CFD, normalization, and update-sensitive mods actually mean for transfer?

**Sources**

1. Microsoft, [2024 `flight_model.cfg`](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/flight_model.cfg/), retail page observed, `normalizationmethod`, CFD and `pitch_moment_delta_elevator` definitions.
2. Microsoft, [2020 Flight Model Tab](https://docs.flightsimulator.com/html/Developer_Mode/Aircraft_Editor/Tabs/The_Flight_Model_Tab.htm), live documentation on clean lift target and surface construction.
3. MSFS DevSupport, [C160 2020 aircraft behaves differently in 2024](https://devsupport.flightsimulator.com/t/msfs2020-aircraft-flight-model-behavior-very-different-in-fs2024/10631), report 2024-10-30, developer explanation 2024-11-12, fixed in SU2 beta 1.4.7.0 per 2025-03-26 reply.
4. MSFS DevSupport, [Legacy lines removed from modern flight model](https://devsupport.flightsimulator.com/t/unexpected-behavior-when-flight-model-cfg-legacy-lines-are-deleted-or-commented-out/18329), SU6 1.8.14.0 report 2026-08-14 and discussion.
5. Flight Simulator forum, [C208B Improvement Mod announcement](https://forums.flightsimulator.com/t/c208b-grand-caravan-ex-mods-general/322172/1265), 2026-02-16, SU4 with SU5 version planned.

**Observed.** The 2024 SDK documents `normalizationmethod=-1` as raw surface coefficients, `0` as normalized with assumed 2020 orientations, and `1` as normalized using 2024 physics-object orientations/properties. `CFD_EnableSimulation` is a separate flag; voxel and reinjection settings have conditional effects. The 2020 documentation describes a clean-aircraft lift target used during surface construction and normalization, not a complete arbitrary-flight polar. A particularly important exception to blanket legacy classification: the 2024 SDK says `pitch_moment_delta_elevator` normally does not supply the modern aerodynamic derivative magnitude, but its sign affects elevator input and the autopilot may use its value; zero or a very wrong value is unsuitable. The SU6 thread reports additional unexpected behavior on removing legacy lines, but does not establish a general rule.

For C160, the developer attributed 2020-to-2024 takeoff problems to equal low/high normalization angles and a wrong clamp in the 2024 path, later reported fixed; a temporary 1°/18° pair was aircraft-specific. The C208B mod author listed simultaneous CFD, flight-model, autopilot and propeller retuning and separate update targeting. These are compatibility and regression leads, not physical RC proof. Both example aircraft fall outside the first single-electric-tractor flight domain.

**Inference and limits.** Preserve feature mode, defaults, source simulator and observed revision along with each field. A CFG file version, a present coefficient, or the word CFD alone cannot reconstruct the source solver, its transient flow, a complete force law or an RC derivative. A field can have distinct sign, magnitude, control and autopilot roles; unknown or disputed behavior must remain unknown rather than be flattened to `inactive`.

**Proposed addition and acceptance.** Add role-specific source dispositions and a conditional-semantics registry with simulator family/build, normalization and CFD flags, defaults, assistance and subsystem. A synthetic modern-mode case should preserve a legacy field's active sign and documented possible autopilot use while declining to copy its magnitude as an OpenRC derivative; unknown subsystem use remains unknown. For equal normalization bounds, preserve inputs and emit a version-specific diagnostic; do not invent a physical correction or silently apply the C160 workaround. Test unchanged source bytes under different declared host builds remain distinct observations. Keep normalizations, CFD voxel values and tuning scalars reference-only until a separately qualified mapping exists.
