# Twenty-four investigations to strengthen the glider plan

**Completed research:** GI-01…GI-24, 15 November 2026.  
**Runtime source reviewed:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`. **Plan branch before expansion:** `49dce1db4fce7e907c38367cdfdbe1fc0338876a`. Both remote refs were checked before this work and were unchanged.  
**Implementation status:** all SG implementation and physical qualification gates retain their status in the [master plan](../../plans/glider-soaring.md). Research completion does not mark a simulator, bench, flight or training experiment complete.

## Purpose and method

This follow-up investigates **24 separate engineering questions** requested after the first handoff. Each card records a question, primary evidence, a finding, source applicability, a proposed plan change, a discriminating experiment, priority and uncertainty. Sources include original experiments, NASA/NACA reports, manufacturer/designer information, scientific papers and official project documentation. Abstract-only or blocked-full-text access is identified where relevant.

The outcome is a strengthened implementation plan. Findings are incorporated into the [launch/control](../../plans/glider-soaring/01-launch-and-control.md), [physics](../../plans/glider-soaring/02-physics-and-tow.md), [aircraft/weather](../../plans/glider-soaring/03-aircraft-and-weather.md) and [acceptance](../../plans/glider-soaring/04-acceptance-and-delivery.md) guides. Those guides own the requirements; these dated cards retain their reasoning and sources. Existing audit findings stay with their owners; extending an existing validation requirement is not reported as a newly reproduced defect.

## Research volumes

| Volume | Investigation IDs | Scope |
| --- | --- | --- |
| [Aircraft and aerodynamics](2026-11-15-investigations-01-aerodynamics.md) | GI-01…06 | Flight-polar identification, low-Re domain, mass/inertia, surface mixing, release state, structural limits |
| [Towing and numerical methods](2026-11-15-investigations-02-towing.md) | GI-07…12 | Line identification, hook/trim authority, coupled energy, solver/event choice, swept clearance, bounded AI |
| [Weather and instruments](2026-11-15-investigations-03-weather.md) | GI-13…18 | Thermal conservation, spatial coherence, centering, TE/netto latency, wake limitations, atmosphere identity |
| [Controls, evidence and delivery](2026-11-15-investigations-04-delivery.md) | GI-19…24 | Controller transfer, RC visibility/latency, exact replay, validation uncertainty, reuse, learning outcomes |

## Findings and adopted plan changes

The priorities below are planning recommendations: P1 protects the first credible capability, P2 adds evidence or later refinement, and P3 denotes later aircraft classes. Mixed priorities are qualified in the card.

| ID | Investigation result | Concrete requirement added or sharpened | SG steps |
| --- | --- | --- | --- |
| GI-01 | Vertical air motion can contaminate a measured sink polar. | Synchronize air/ground motion and independent wind evidence; predeclare steady windows and reserve entire flights for validation. | 02/03/16 |
| GI-02 | Existing finite-wing incidence tables are not direct 2D or Re-indexed polars. | Record source dimensionality, roughness/transition and Re domain; qualify conversions and interpolation before expanding the envelope. | 02/03/16 |
| GI-03 | CG, inertia and aerodynamic damping can compensate for one another in a fitted response. | Compare mass inventory with independent CG/inertia measurements, then validate identifiable dynamic responses. | 02/03/16 |
| GI-04 | Spoileron mixing changes residual roll authority and multiple aerodynamic components. | Test simultaneous roll/brake saturation, achieved left/right surfaces and pitch/yaw/drag response; crow remains configuration-specific. | 02/03/13/16 |
| GI-05 | Release pose, CG velocity, rates and controls form one correlated initial state. | Transform tracked markers to CG; preserve correlated measurements and avoid an extra post-release energy injection. | 05/16 |
| GI-06 | A stable rigid simulation does not establish a real wing's structural or flutter limit. | Declare the evidenced rigid-airframe domain and compare deformation/modes where needed; leave unknown strength unclaimed. | 02/03/05/16 |
| GI-07 | Real rope response can depend on load history and installed terminations. | Fit and validate loading/unloading loops, rates and conditioning; hold out histories and qualify weak links separately. | 08/09/14/16 |
| GI-08 | Speed overlap alone does not establish a controllable climb. | Establish joint force/moment trim, hook moments, control margins and tug excess power. | 03/08/09/10/11/16 |
| GI-09 | Equal/opposite force exchange can still introduce discrete energy error. | Compare lagged coupling against same-stage evaluation using independent power, energy and event ledgers. | 07/08/15 |
| GI-10 | Stiff compliance and rigid unilateral constraints have different laws and event behavior. | Compare qualified solver candidates using refinement, located events, accuracy and cost; reject unresolved crossings. | 07/08/12/17 |
| GI-11 | Clear endpoints do not rule out a between-tick collision or unknown slack-line path. | Qualify swept aircraft checks; define conditional taut/slack rope bounds, exemptions and conservative failure semantics. | 07/08/12/14/17 |
| GI-12 | AI route goals must be physically reachable by the coupled pair. | Admit climb/turn/speed/control limits, label ideal sensors, and test saturation, release and aborts with held-out cases. | 09/10/11/14/16 |
| GI-13 | A volume-conserving kinematic cell is not automatically density-weighted mass conserving. | Reuse M5's boundary/flux work and label field assumptions; design low-launch lessons around actual available lift. | 06; M5 |
| GI-14 | Shared seeds and equal RMS do not establish spatially coherent encounters. | Compare covariance, complex coherence and stage-time response across wings, tails and both aircraft. | 06/07 |
| GI-15 | A tighter turn samples different lift while changing sink and stall margin. | Compare bank/speed/offset/drift against the actual banked polar, remaining cell life and return requirement. | 03/06/15 |
| GI-16 | Sensor/filter delay can shift a pilot's apparent lift location. | Separate truth, sensor-derived instruments and assisted cues; version sampling/filter state and test delay, dropout and restore. | 06/13/15 |
| GI-17 | A propwash study's downstream measurement extent is not a wake-free distance. | Keep wake-omitted towing explicitly experimental; evaluate candidate geometric guards only as sensitivity experiments until supported by evidence, not as admission or clearance rules. | 09/10/11; M5 |
| GI-18 | Density, viscosity and epoch changes can invalidate a nominally identical flight. | Pin atmosphere/polar/sensor/weather identity together and check actual station bounds and remaining world horizon. | 01/03/06/15 |
| GI-19 | Controller transfer must match the correct command boundary and internal states. | Distinguish requested intent, applied command and achieved position; initialize/track per-loop state transactionally. | 10/11/13 |
| GI-20 | A usable RC view depends on projected size, cues and response timing. | Define camera/FOV/assistance identity and measure the input, physical-response and presentation chain at native 1080p. | 04/10/11/13/17 |
| GI-21 | Exact replay requires full execution/state identity, not a seed alone. | Extend existing replay contracts to both actors, controller/event state and RNG/agenda; distinguish changed-solver candidates. | 07/11/15/17 |
| GI-22 | Accuracy must be assessed for intended use with independent data and uncertainty. | Predeclare metrics, split calibration/validation, report numerical/model/measurement error separately and prioritize sensitive parameters. | 02/03/09/16 |
| GI-23 | Public simulator assets can carry file-specific restrictions and weak physical provenance. | Use a source/hash/terms/applicability intake matrix; no automatic PicaSim mesh or inspected JSBSim SGS-model import. | 02/03/17 |
| GI-24 | Airtime alone can reward poor decisions and hide assistance. | Version lesson outcomes, score accepted events, separate abort/assistance/refusal and use controlled learning evaluations. | 05/06/10…16 |

## Changes that should happen first

1. **Measure a defensible trainer.** Open GI-01…06 and GI-22 with SG-02/03: exact build inventory, wing-area convention, source polar meaning, independent CG/inertia, controls and release measurements. Keep an estimated prototype visibly experimental while data are collected.
2. **Prove a bounded tow model.** Use GI-07…12 with SG-07…09: installed rope histories, joint trim/authority, same-stage energy closure, event refinement and swept clearance. A solver method is selected by evidence and cost, not by an assumed universally adequate timestep.
3. **Qualify the learning environment.** Use GI-13…18 and GI-20 to make thermal exercises achievable and readable with honest instrument signals. Resolve the existing M5 boundary/flux/coherence questions through their owning track.
4. **Complete the human transfer and evidence loop.** Use GI-19/21/24 for both-direction control-state transitions, actual radios, pair replay and useful lessons. Apply GI-23 before asset intake; validate claims using GI-22.

These activities can proceed in parallel within existing ownership boundaries. The four requested journeys and SG-00…17 remain intact. No new mandatory dependency on MATLAB, SciPy, OpenFAST, another simulator or a commercial asset is introduced; referenced tools and experiments provide methods or comparisons.

## Quantitative findings retained as illustrations

| Investigation | Calculation | What it does and does not establish |
| --- | --- | --- |
| GI-01 | 0.5 m/s true sink plus 0.3 m/s updraft appears as 0.2 m/s ground descent: a 60% low sink estimate if misclassified. | Identifiability example; not an EG4 observation. |
| GI-09 | Two unit masses/unit spring under one explicit-Euler step can change total energy from 0.5 to `0.5+h²`. | Discrete energy counterexample; not the production RK4's measured error. |
| GI-14 | A 2 m frozen spatial wave differs by 180° at points separated by 1 m along the wave direction; at 10 m/s relative motion along that direction it is encountered at 5 Hz. | Coherence/sampling example; not a measured turbulence scale or a general time-varying field law. |
| GI-15 | At 10 m/s horizontal path speed using the ideal level-turn approximation, 30°/45° turn radii are 17.66/10.20 m; one synthetic cell yields local lift about 0.18/1.03 m/s at those radii. | Shows the lift-versus-turn tradeoff before aircraft sink; no recommended bank or climb-rate claim. |
| GI-16 | A 1 s first-order filter reaches half a step after 0.693 s, equivalent to 6.93 m at 10 m/s relative motion. | Instrument-lag example; not an actual variometer measurement. |
| GI-18 | At fixed dry-air pressure, 10→25°C gives density ratio 0.9497, viscosity ratio 1.0408 and same-speed/chord Re ratio 0.9124. | Fluid-property illustration; no prediction of the aircraft's changed polar. |
| GI-20 | A broadside 1.8 m span projects to 15.01/7.51 px at 150/300 m on a 1920 px image with 75° horizontal FOV. | Camera geometry example; neither app camera settings nor a visibility threshold. |

## Review and evidence receipt

The additional work used read-only upstream/source inspection, mathematical reasoning and the explicitly recorded arithmetic. Independent review corrected projected-span and thermal-flux wording, distinguished actuator command from achieved position, completed the response-timing chain and strengthened the training-study design. It also rejected an unsupported wake-distance admission rule and clarified the direction and signal assumptions in numerical examples. The final documentation pass checks requirement coverage, source/link structure, arithmetic and the published content identities.

No simulator build/run, physical line or aircraft test, controller/hardware session, rendered capture, performance benchmark, asset import or learner experiment was performed. Each card's proposed experiment remains open work for its named SG/M5 owner. Source methods and results from other aircraft are never reported as an OpenRC validation result.

