# Weather, soaring instruments, and tow wake: investigations GI-13–GI-18

**Status:** source investigations and identified arithmetic completed, 15 November 2026; implementation and qualification experiments remain proposed. The reviewed production baseline is [`ad21070798bfb9658785576a9c0b8bfc9a71fc7f`](https://github.com/bultodepapas/OpenRCsimulator/commit/ad21070798bfb9658785576a9c0b8bfc9a71fc7f); the glider-plan documents were inspected in the working snapshot supplied for this research.

The [master](../../plans/glider-soaring.md), [physics](../../plans/glider-soaring/02-physics-and-tow.md), [aircraft and weather](../../plans/glider-soaring/03-aircraft-and-weather.md), [acceptance matrix](../../plans/glider-soaring/04-acceptance-and-delivery.md), current M5 reference and consolidated audit remain the canonical homes. These cards add discriminating questions and proposed owner-scoped changes. Source reading and the explicitly identified arithmetic below were performed; **no simulator, physical flight, instrument, platform or performance tests were run**. Illustrative values are not aircraft calibration or release limits. Preserve existing M5 law identities unless an independently qualified, versioned extension is adopted.

## GI-13 — What does the finite thermal actually conserve?

**Question.** Can the existing cell support a truthful near-ground lesson while remaining distinct from a buoyant, density-consistent thermal?

**Primary sources inspected.** Hourdin et al., *Unified Parameterization of Convective Boundary Layer Transport and Clouds With the Thermal Plume Model* (2019) [W01]; Matsui et al., *A thermal-driven graupel generation process to explain dry-season convective vigor over the Amazon* (2024) [W02]. Both discuss modeled convective transport; the latter tracks cloudy thermals in a particular tropical simulation.

**Finding and inference.** The existing cell is a prescribed finite circulation with a birth, drift, height envelope and zero-extension boundaries, not a rising buoyant parcel or a surface-heating solution. The existing source's midpoint example gives about 0.044 m/s upward at 10 m for `P=1.8 m/s`, `H=200 m`; this arithmetic is local air velocity, not an aircraft's climb. The plume study includes entrainment/detrainment and mass flux, whereas a prescribed volume-divergence-free velocity only satisfies `div(rho W)=W·grad(rho)` for a stationary, spatially varying density. Thus its zero divergence does not automatically establish local mass-flux closure in a standard column. In the uniform literal-reference atmosphere, constant density removes this particular distinction. Neither paper supplies an RC-field cell strength, size or lifetime.

**Proposed edit and verification.** In [weather §5](../../plans/glider-soaring/03-aircraft-and-weather.md#5-weather-recipes-and-admission), tie hand-launch lessons to measured sink and remaining altitude. Under SG-06 and M5-W-AUD-12/M5-ATM-AUD-01, compare one-sided velocity/derivative limits at floor/top and `r=4R,5R`. Use the actual composite provider or a labelled analytic extension at the floor: the standalone thermal query rejects negative height. Isolate the thermal field and compare surface flux `integral(rho W·n dA)` with independently integrated `integral(W·grad(rho) dV)` over valid-domain core/sink boxes, refining the grid; the expected column flux need not be zero. Include constant-density and zero-cell controls and normalize by nonzero one-way throughput. Preserve field identity; do not change its law merely to make a lesson winnable.

**Priority / uncertainty:** P1 for honest lessons and admission; real near-ground plume, density and aircraft sink measurements are missing.

## GI-14 — Are turbulence encounters coherent across the whole pair?

**Question.** Can two aircraft and their individual lifting stations encounter one evolving field without falsely identical or independent gust histories?

**Primary sources inspected.** OpenFAST's *FAST.Farm Modeling Guidance*, v5.0.0 documentation [W03], and Robertson et al., *Sensitivity analysis of the effect of wind characteristics and turbine properties on wind turbine loads* (2019) [W04]. These discuss full-field turbine inflow, component spectra and point-to-point coherence; their scales and wind regimes are not RC validation.

**Finding and inference.** Both actors need the same world-field law, configuration and epoch, including RNG identity/state only when that provider uses randomness; an explicit agenda can define a deterministic field without a seed. Each point/time query must retain the appropriate correlation and phase across wings, tails and both aircraft. Separately advanced OU processes can be identical or unrelated depending on sampling; neither substitutes for a shared spatial field, and current v5 excludes legacy OU amplitudes. For a **frozen sinusoidal illustration**, points 1 m apart along a 2 m wavelength differ by 180°; motion along the wave at 10 m/s relative to advection encounters 5 cycles/s. Intrinsic evolution changes the general result. Matching pointwise RMS alone cannot establish spatial loads or phase.

**Proposed edit and verification.** Add a cross-reference under SG-06/07 and M5-W-AUD-14/15 in [acceptance A13–A15](../../plans/glider-soaring/04-acceptance-and-delivery.md#3-aircraft-and-environment-test-matrix). First use a single analytic field with known phases, and sample left/right wing, tail, and two aircraft in both query orders at identical stage times. Then use multiple seeds and report vector mean, RMS, cross-component covariance, complex cross-spectra/coherence and uncertainty at declared separations and heights. State whether coherence is magnitude or magnitude-squared. Compare actual load/roll response and convergence, without adding independent synthetic angular gusts or double-counting advection. A periodic or gridded TurbSim example is an **independent statistical benchmark**, not an automatic replacement provider or proof of RC-scale coherence.

**Priority / uncertainty:** P1 for shared-world correctness; field measurements at aircraft-scale separations and product-grade performance remain open.

## GI-15 — Which thermal circle actually gains energy?

**Question.** How should a centering lesson balance radius, bank-induced sink, drift and finite lifetime without prescribing a universal bank angle?

**Primary sources inspected.** Allen and Lin, NASA/TM-2007-214611/REV1, *Guidance and Control of an Autonomous Soaring UAV* (2007) [W05], and An, Lin and Zhang, *An Autonomous Soaring for Small Drones Using the Extended Kalman Filter Thermal Updraft Center Prediction Method Based on Ordinary Least Squares* (2023) [W06]. The NASA article reports flight tests on a 4.27 m powered motorglider; the 2023 study tests a different powered UAV and estimator.

**Finding and calculation.** The studies separate lift detection, estimated center, bank/sink and flight guidance. Their settings are not EG4 limits. A synthetic comparison follows the current thermal law: at peak age and `h=H/2`, set `P=1.8 m/s`, `R=20 m`, with no horizontal drift. Assume a centered horizontal circular path at 10 m/s and use the ideal level-turn approximation; vertical updraft makes total air-relative speed different, so this is not an exact trimmed flight. The resulting radii are 17.66 m at 30° and 10.20 m at 45°. At those radii the field gives about 0.18 and 1.03 m/s upward air velocity. The tighter circle samples more lift while increasing load factor and potentially sink. These are arithmetic illustrations, **not** glider climb rates, a recommended bank or a flown test.

**Proposed edit and verification.** Add a bank/speed/center-offset/drift scenario card to [weather §5](../../plans/glider-soaring/03-aircraft-and-weather.md#5-weather-recipes-and-admission) and SG-03/06/15. Run paired left/right turns at the same initial state and sampled field, holding autopilot/assistance constant; record air-relative radius, ground-track drift, actual bank, TAS, load factor, polar-predicted bank sink, actual altitude and energy, time to center, altitude margin and finite-cell expiry. Include weak-cell and too-small-cell negative controls. Test recovery and field return rather than optimize altitude alone; hide center/field truth from an unassisted controller and score any displayed aid separately.

**Priority / uncertainty:** P1 for lesson credibility; the selected glider's banked polar, stall margins, actuator lag and achievable radius are unmeasured.

## GI-16 — Can TE/netto cues distinguish lift from a delayed sensor?

**Question.** How should an instrument represent airspeed/height energy, banked sink and signal timing without revealing the simulator's hidden wind as a sensor reading?

**Primary sources inspected.** FAA, *Glider Flying Handbook*, FAA-H-8083-13B, 2024, chapter 4 [W07]; ArduPilot, *Soaring*, Plane 4.1 documentation [W08]. The first describes compensated and netto instruments; the second uses an aircraft-specific sink polar for its autopilot. Neither specifies the user's chosen RC sensor or proves an OpenRC implementation.

**Finding and calculation.** For constant mass and a common datum, `h_TE=h+V_TAS²/(2g)` separates ideal altitude/airspeed exchange from actual energy change. A netto estimate also needs a sink polar and bank/load/configuration correction; temporal wind, shear, tow or propulsion work can bias interpretation. Barometric altitude, airspeed sensing, mounting, noise and filtering have distinct delays. Indicated/equivalent airspeed must not silently replace TAS. For an ideal first-order filter with `tau=1 s`, a step reaches 50% after `ln(2) s`: at 10 m/s relative motion, that indication occurs 6.93 m later along the path after crossing the edge. This is a step-response calculation, not a universal lag, downwind displacement, thermal-center offset or real measurement; low-frequency group delay approaches `tau` instead.

**Proposed edit and verification.** Under SG-06/13/15, amend [physics §4](../../plans/glider-soaring/02-physics-and-tow.md#4-airmass-energy-and-instruments) and acceptance A15 to define three independently labelled outputs: physical truth diagnostic, sensor-derived instrument and optional assisted cue. Record sampling times, filter coefficients/state, warmup, saturation and selected units; filter before any reduction in sample rate and log both unrounded input and published cue. Compare calm pull-up, steady sink, uniform lift, banked lift, advected sharp edge and shear, including invalid airspeed/dropout, reset and restore. Require sign, declared delay and no hidden true-wind input in the sensor mode; account for filter lag when evaluating centering.

**Priority / uncertainty:** P1 for honest training; actual instrument hardware, filtering and glider polar are unknown.

## GI-17 — What is an honest first tow-wake exclusion?

**Question.** How can an initial no-wake model avoid teaching an unsupported close propwash encounter while retaining a useful experimental tow?

**Primary sources inspected.** Deters, Ananda and Selig, *Slipstream Measurements of Small-Scale Propellers at Low Reynolds Numbers*, AIAA 2015-2265 [W09]; FAA, *Aeronautical Information Manual*, §7-4, wake turbulence [W10], current web edition reviewed 15 November 2026. The first measures 4.2, 5 and 9 inch propellers to three diameters; FAA discusses full-scale vortices.

**Finding and scope.** The small-prop measurements show that static and advancing flow differ, and that propeller geometry and wing installation affect the slipstream. Three diameters is the **furthest measured location**, not a distance at which wake vanishes. Wingtip vortices are a distinct wake mechanism that can move with ambient flow; full-scale separation advice is not an RC threshold. The initial paired solver has neither a validated tug-to-glider wake nor line interaction with it. It must not claim ambient-only air is undisturbed or present a safe separation recommendation.

**Proposed edit and verification.** Keep first ambient-only airborne SG-09/10/11 towing explicitly experimental with respect to wake. A candidate downstream `0–3D` axial slab may be explored as a geometry sensitivity experiment, **not adopted as an admission or clearance rule**: an infinite lateral slab rejects unrelated sideways positions yet misses centerline exposure beyond `3D`, and omits advected historic wake and wing vortices. Independent review rejected calling it conservative for total wake exposure. No distance in this research establishes a wake-free region or a real-world safety recommendation.

Compare static thrust, advancing flight and crossed paths against velocity profiles for the exact propeller/wing, within and beyond the source's measurement range. Record thrust/advance ratio, geometry, yaw/crosswind, wake age and uncertainty; test shared stage-time sampling and interval crossings for any implemented model. A coupled wake needs its own law/identity and independent near-/far-field evidence. Aircraft collision remains a separate gate; an ambient-only successful tow cannot validate wake handling.

**Priority / uncertainty:** P1 for accurate capability claims; P2 for a wake-model study. Selected installation wake measurements are absent.

## GI-18 — How do atmosphere and weather identity affect the same flight?

**Question.** Can density, viscosity, airspeed and scenario epoch change independently without silently invalidating a polar or replay?

**Primary sources inspected.** Ames Research Staff, NACA Report 1135, *Equations, Tables, and Charts for Compressible Flow*, Appendix A (1953), including Sutherland's viscosity relation [W11]; U.S. Standard Atmosphere, 1976, NOAA/NASA/USAF [W12]. These are standard-atmosphere and fluid-property references, not weather observations for the selected field or a measured RC polar.

**Finding and calculation.** At identical dry-air pressure, warming from 10°C to 25°C gives `rho_25/rho_10≈0.9497`. With the report's Sutherland constant converted from 198.6°R to 110.33 K, `mu_25/mu_10≈1.0408`, so at the same TAS and chord `Re_25/Re_10≈0.9124`. Holding effective `CLmax`, mass and area fixed, the simple stall-speed estimate rises by a factor of about 1.026; a real low-Re polar may itself change, so this is **not** a predicted EG4 stall shift. OpenRC's literal standard-reference atmosphere intentionally returns exactly 1.225 kg/m³; its separately evaluated uniform or standard-column law follows different calculations. Density altitude is a derived reference comparison, not simply geometric height.

**Proposed edit and verification.** For SG-01/03/06 and M5 atmosphere owners, append a condition/identity matrix to [acceptance A04/A09/A14](../../plans/glider-soaring/04-acceptance-and-delivery.md#3-aircraft-and-environment-test-matrix): pin atmosphere law and values, physical datum, aerodynamic/polar law and hash, actual mass/CG, controls, weather version, seed, resolved event agenda, world epoch/offset, bounds and sensor filter initialization. Recompute these values when inputs change; do not label a fixed-Re polar as dynamically Reynolds-aware. Verify standard literal versus formula-derived reference, humid/dry cases within admitted models, air-to-ground velocity conversion, pressure/temperature unit refusal, changed-identity rejection and same-identity complete replay. For a 3,600 s world horizon with a 300 s initial epoch offset, the remaining valid simulation time is 3,300 s; check each aircraft/station before it crosses any field boundary.

**Priority / uncertainty:** P1 for provenance and replay, P2 for Reynolds-dependent polar expansion; atmospheric weather, polar variation and measurement uncertainty need separate evidence.

## Primary-source register

All external materials were accessed or reviewed on **15 November 2026**; no long passages or data files are copied. Mutable online manuals should be version-pinned if later used to implement or redistribute a law.

- [W01] Hourdin et al., thermal-plume transport and clouds, 2019.
- [W02] Matsui et al., modeled Amazon convection and thermal tracking, 2024.
- [W03] OpenFAST FAST.Farm, modeling guidance, v5.0.0 observed at review.
- [W04] Robertson et al., inflow coherence and turbine-load sensitivity, 2019.
- [W05] Allen and Lin, NASA/TM-2007-214611/REV1, autonomous soaring, 2007.
- [W06] An, Lin and Zhang, thermal-center estimation and UAV flight, 2023.
- [W07] FAA-H-8083-13B, *Glider Flying Handbook*, 2024, chapter 4.
- [W08] ArduPilot Plane, *Soaring*, version 4.1 documentation.
- [W09] Deters, Ananda and Selig, AIAA 2015-2265, small-propeller slipstream, 2015.
- [W10] FAA *Aeronautical Information Manual*, §7-4, current online edition.
- [W11] Ames Research Staff, NACA Report 1135, 1953, Appendix A.
- [W12] NOAA/NASA/USAF, *U.S. Standard Atmosphere, 1976*, NASA-TM-X-74335.

[W01]: https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2019MS001666
[W02]: https://acp.copernicus.org/articles/24/10793/2024/
[W03]: https://openfast.readthedocs.io/en/main/source/user/fast.farm/ModelGuidance.html
[W04]: https://wes.copernicus.org/articles/4/479/2019/index.html
[W05]: https://ntrs.nasa.gov/citations/20070022339
[W06]: https://www.mdpi.com/2504-446X/7/10/603
[W07]: https://www.faa.gov/sites/faa.gov/files/Glider-Flying-Handbook.pdf
[W08]: https://ardupilot.org/plane/docs/soaring-4_1.html
[W09]: https://m-selig.ae.illinois.edu/pubs/DetersAnandaSelig-2015-AIAA-2015-2265-LRN-PropSlipstream.pdf
[W10]: https://www.faa.gov/air_traffic/publications/aim_html/chap7_section_4.html
[W11]: https://www.nasa.gov/wp-content/uploads/2023/03/equations-tables-charts-compressibleflow-report-1135.pdf
[W12]: https://ntrs.nasa.gov/citations/19770009539
