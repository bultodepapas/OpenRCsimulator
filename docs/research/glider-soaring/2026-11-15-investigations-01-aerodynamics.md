# Glider investigations GI-01–GI-06: aircraft and aerodynamics

**Status:** source investigations and analytic reasoning completed 15 November 2026. All proposed measurements, implementation and acceptance tests remain **unperformed**.  
**Identity:** runtime baseline `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; plan branch supplied as `49dce1db4fce7e907c38367cdfdbe1fc0338876a`. These cards propose additions to the [master plan](../../plans/glider-soaring.md), [physics plan](../../plans/glider-soaring/02-physics-and-tow.md), [aircraft/weather dossier](../../plans/glider-soaring/03-aircraft-and-weather.md) and [acceptance plan](../../plans/glider-soaring/04-acceptance-and-delivery.md); they do not change their current status. Priority P1 denotes first trainer credibility, P2 an extension or targeted uncertainty reduction, and P3 later vehicle-class work.

## Inspected primary sources

| ID | Primary source and edition | Use and scope |
| --- | --- | --- |
| S1 | [Ramšak, *Radio Controlled Sailplane Flight: Experimental and Numerical Analysis*, 2012](https://www.sv-jme.eu/wp-content/uploads/ns_articles/files/ojs/457/submission/copyedit/457-1090-1-CE.pdf), DOI 10.5545/sv-jme.2009.153 | One 0.320 kg RC sailplane; photogrammetry, glide uncertainty and computation comparison. |
| S2 | [Weishäupl, McLay and Sóbester, *Experimental evaluation of the drag curves of small fixed wing UAVs*, online 2023](https://www.cambridge.org/core/journals/aeronautical-journal/article/experimental-evaluation-of-the-drag-curves-of-small-fixed-wing-uavs/453B48240E5861B1360B9D33288C5C88) | Actual unpowered glide and deceleration experiments, with wind-tunnel comparison, on their instrumented UAV. |
| S3 | [McGhee, Jones and Jouty, *Performance characteristics from wind-tunnel tests of a low-Reynolds-number airfoil*, AIAA 88-0607, 1988](https://ntrs.nasa.gov/citations/19880035228) | Eppler 387 section results, including separation and reattachment; NTRS abstract inspected. |
| S4 | [Mangalam et al., *Transition and separation control on a low-Reynolds number airfoil*, 1986](https://ntrs.nasa.gov/citations/19880023959) | Effects of controlled transition on a specific LRN(1)-1007 model; NTRS abstract inspected. |
| S5 | [Wolowicz and Yancey, *Experimental determination of airplane mass and inertial characteristics*, NASA TR R-433, October 1974](https://ntrs.nasa.gov/citations/19750001990) | Measurement methods and suspension-related error sources, not RC build data. |
| S6 | [Ouhabi and Narsipur, *Off-board aerodynamic measurements of small-UAVs in glide flight using motion tracking*, online 2025](https://www.cambridge.org/core/journals/aeronautical-journal/article/offboard-aerodynamic-measurements-of-smalluavs-in-glide-flight-using-motion-tracking/4F2CB54FF6A9C3DF9870305D0EA92044) | Indoor optical tracking, body-frame reconstruction and uncertainty for the studied small vehicles. |
| S7 | [Weick and Noyes, *Wind-tunnel research comparing lateral control devices … II*, NACA TR-422, 1933](https://ntrs.nasa.gov/citations/19930091496) | Aileron types and differential in tested historical wing models; NTRS abstract inspected. |
| S8 | [MULTIPLEX *EasyGlider 4* manual, kit #21 4332, 2017 v1.0](https://www.multiplex-rc.de/userdata/filegallery/original/4934_214332-bedienungsanleitung-easyglider-4--de-en-fr-it-es.pdf) | Installed control options, geometry conventions and proposed settings; does not give the selected pure build's complete mass/polar. |
| S9 | [Drela, *SuperGee I* design and construction notes, 2003](https://charlesriverrc.org/articles/on-line-plans/mark-drela-designs/supergee/) | A DLG designer's description of launch loading, boom deflection and control-linkage arrangement. |
| S10 | [Antiporda et al., *IAM3D Discus Launch Glider*, NMSU student project poster, 2025](https://engrcdp.nmsu.edu/assets/img/posters-2025/9%20NMSU%20IAM3D%20Glider.pdf) | Authors report one unsuccessful prototype test and unresolved possible causes; not a calibrated launch dataset. |
| S11 | [Bennett, *Application of a flight test and data analysis technique to flutter of a drone aircraft*, NASA TM-83136, May 1981](https://ntrs.nasa.gov/citations/19810016531) | Drone research-wing modal identification in flight, not a generic RC flutter limit. |
| S12 | [Voracek, *Ground Vibration and Flight Flutter Tests of the Single-seat F-16XL Aircraft with a Modified Wing*, NASA TM-104264, June 1993](https://ntrs.nasa.gov/citations/19940006761) | Aircraft-specific distinction between ground modal survey and flight aeroelastic behavior. |

Repository inspection used the pinned [wing-polar implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/wing_polar.gd), [control mapping](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/control_surfaces.gd), [mass inventory](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/mass_inventory.gd), and [air-start/hand-release path](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/sim/flight_session.gd#L3846-L3964). Public access to a paper, plan, photograph, airfoil, software or asset does not itself authorize redistribution; audit the exact file and license before intake.

## GI-01 — Identify a whole-aircraft polar without fitting the atmosphere

**Priority:** P1. **Question:** How can SG-03 recover sink versus airspeed for the exact unpowered build, while detecting wind, transient and sensor biases?

**Evidence and finding:** In S1, the author used video on a lightweight RC glider and found that the low-speed data were scattered; two apparent high-glide-ratio points violated the steady-flight assumption, and air movement was a material uncertainty. S2 compared unpowered glides and deceleration with a wind-tunnel reference on an instrumented 5 kg-class UAV; maneuver choice depended on conditions. Neither study measures the selected EasyGlider.

**Inference and applicability:** Ground trajectory alone cannot uniquely separate ambient vertical air motion from aircraft sink. In a simple steady example, true air-relative sink of 0.5 m/s in a 0.3 m/s updraft produces only 0.2 m/s ground descent; fitting 0.2 as the aircraft sink creates a 60% low bias. This is an arithmetic illustration, not a glider specification. Opposite-direction runs may expose horizontal wind effects but do not by themselves remove a changing or spatially varying updraft.

**Proposed plan change — SG-02/03/16, A05:** Pin the complete aircraft, mass/CG, surface/trim state, sensor installation, density and calibration. Use a calm indoor motion-capture volume where practical, or synchronize calibrated airspeed/altitude/attitude and position with independent wind observations at relevant location and height. Reweigh the instrumented aircraft; quantify wind-sensor representativeness and timing. Predeclare steady-window and wind-quality thresholds from sensor error, use repeated runs at several speeds and headings, and reject or explicitly model acceleration, turns and thermal contamination. Keep raw records and filters; fit trimmed whole-aircraft sink and confidence intervals, not merely wing-section `CL/CD`.

**Discriminating acceptance experiment:** Partition flights by run/day into fit and held-out sets. Compare predicted held-out sink, glide angle and trim across speed with uncertainty intervals; inject the illustrative updraft into a synthetic measurement reducer and require it to expose the bias, not score the apparent polar as ground truth. **Remaining uncertainty:** feasible air-relative wind sensing and adequate steady-flight duration at RC scale.

## GI-02 — Select a low-Reynolds polar domain before interpolating

**Priority:** P1. **Question:** When is a fixed-reference polar credible, and what evidence would justify Reynolds-dependent interpolation or transition modeling?

**Evidence and finding:** S3's Eppler 387 section showed separation-bubble-dominated behavior below about 200,000 Reynolds number and two flow regimes at the same angle for one tested condition. S4 reports different results when transition was deliberately triggered on another small model. These are observations for those airfoils, finishes and tunnels, not universal thresholds or proof that roughening always improves performance.

**Inference and applicability:** `Re = rho V c / mu` varies with local chord and local airspeed. A smooth curve across widely separated Reynolds values can erase a transition discontinuity or hysteresis. The pinned `tabulated-wing-v1` implementation takes a **finite-wing strip-reference** incidence table, uses shape-preserving interpolation in angle and numerical endpoint continuations, and has no Reynolds axis. A measured two-dimensional airfoil table is not automatically its input format; the current angle interpolation is not Reynolds interpolation or proof of transition fidelity.

**Proposed plan change — SG-02/03/16:** Inventory each source's geometry, section versus finite-wing meaning, Reynolds range, transition trip/roughness, angle sweep direction, units and uncertainty. Estimate the selected aircraft's actual section-Re range across the intended maneuvers without inventing a viscosity consumer. First qualify one bounded reference model against measured whole-aircraft flights; label out-of-domain results unavailable or experimental. If that domain is too narrow, specify a versioned Reynolds/angle/configuration lookup with separate observed branches, controlled interpolation and an explicit out-of-range refusal or labeled continuation. Preserve provenance and avoid silently importing incompatible 2D `CD` into the existing finite-wing induced-drag closure.

**Discriminating acceptance experiment:** Predeclare candidate models, metrics and comparison rules; use separate development/selection data to compare fixed-reference and any evidenced alternative across low-, mid- and high-speed glides with matching finish. Freeze the selected model before evaluating a final independent flight holdout. If inspection of that final holdout motivates another model or selection, reclassify the inspected data as development and reserve a fresh final holdout; avoiding coefficient refits alone does not preserve independence. Test interpolation at nodes, boundaries and across documented regime changes. This experiment-design correction follows the [plan audit](2026-11-15-plan-audit.md); no experiment was executed. **Remaining uncertainty:** actual EG4 airfoil, finish, local transition and existing available coefficients.

## GI-03 — Separate balance, inertia and stability identification

**Priority:** P1. **Question:** Which measurements distinguish a wrong mass distribution from incorrect static stability or damping?

**Evidence and finding:** S5 explains that inertia identification depends on the suspension and that sway and rocking can contaminate the sought mode. S6 reconstructed a tracked vehicle's body pose and derivatives from calibrated camera markers, reporting experimental uncertainty. Both demonstrate measurement methods; neither identifies the selected aircraft's inertia or stability derivatives.

**Inference and applicability:** A correct total mass and visually plausible CG do not determine all six inertia-tensor terms. The pinned mass inventory computes tensor contributions with a parallel-axis model; agreement with that computation does not independently validate its component geometry. Pitch oscillation amplitude can arise from inertia, aerodynamic restoring/damping, actuator response, trim or wind, so one free-response trace cannot uniquely identify every parameter.

**Proposed plan change — SG-02/03/16, A03/A08:** Measure ready-to-fly mass and multi-axis CG with electronics, release, ballast and any test instrumentation. Compare computed tensor with a calibrated, small-amplitude pendulum or other suitable independent rig; record suspension geometry, fixture inertia, repeatability, axis transformations, products and uncertainty. Then hold an evidenced build and trim, apply bounded measured elevator/rudder/aileron perturbations at several admissible airspeeds, record actual surfaces and motion, and identify coupled dynamic modes with confidence intervals. Vary CG deliberately within an established range while remeasuring all resulting mass properties. Derive static pitching slope only from a method with sufficient moment/control calibration; an elevator-trim curve alone is not a direct moment measurement.

**Discriminating acceptance experiment:** Compare the pinned inventory estimate to independently measured inertia, then fit a limited dynamic model on some perturbations and predict withheld pulse responses and the CG-shift direction, duration and damping. Reject nonidentifiable derivative combinations rather than optimizing each independently. **Remaining uncertainty:** practical fixture accuracy and whether available disturbances excite distinct modes without leaving the validated envelope.

## GI-04 — Calibrate real surface mixes and adverse yaw

**Priority:** P1 for EG4 spoilerons; P2 for crow. **Question:** Can the simulator reproduce each installed surface's roll, yaw, drag and trim effects without conflating independent surfaces?

**Evidence and finding:** S8 specifies differential aileron travel and describes a landing mix raising both ailerons with elevator compensation. S7's tested wings showed that differential motion had a greater adverse-yaw effect than the particular aileron-type differences considered. This is a historical wind-tunnel comparison, not a correction coefficient for the EG4. Crow on a later four-surface wing is a separate installation.

**Inference and applicability:** Symmetric raised ailerons alter lift distribution, drag and pitch while leaving less residual travel for roll; a yaw response also depends on aircraft inertia, sideslip, roll rate and local airflow. At the pinned baseline `surface_deflections_deg` maps conventional roll into opposite ailerons; `independent_deflections_deg` is explicitly a conversion/fixture seam, not evidence of a complete separate-actuator player path. A generic drag multiplier or a rendered hinge alone cannot capture the mix.

**Proposed plan change — SG-02/03/13/16, A07:** Measure left and right achieved angles, asymmetric travel, neutral, servo speed and saturation against named roll/brake commands, including the manufacturer's elevator compensation as a starting setting. Add a versioned symmetric spoileron command, actual actuator state, mixing priority, saturation and matching spanwise lift/drag/moment and hinge bindings. Add crow only for a real flap-equipped configuration with independent evidence; do not label the EG4 a separate blade-spoiler aircraft.

**Discriminating acceptance experiment:** On the bench sweep brake and left/right roll simultaneously, checking command-to-achieved angles and continuity at saturation. In calm, matched-speed trials compare spoilerons retracted/deployed and left/right roll pulses: record altitude, speed, pitch, bank and yaw/sideslip or an independently reconstructed estimate. Compare held-out changes with a no-mix control; crosswind ground-track angle alone is not sideslip. **Remaining uncertainty:** surface load, airfoil effects and sensing accuracy across the EG4 envelope.

## GI-05 — Measure release state and keep DLG energy separate

**Priority:** P1 for ordinary hand release; P3 for DLG. **Question:** Which measured state enters the solver at hand separation, and what extra information does a discus launch need?

**Evidence and finding:** S1 describes a specific discus-launched RC sailplane and uses external image-based motion measurement; its speed observations are not a universal release envelope. S9 explains how one SuperGee design's boom and linkage deform under launch loads. The S10 student prototype failed immediately after release and the authors leave several plausible causes unresolved; it does not identify any one cause or prove a release-speed value.

**Inference and applicability:** A DLG's pre-release rotation produces both center-of-mass translation and body angular motion. At separation, the rigid body's kinetic energy is `0.5*m*|v_CM|² + 0.5*omegaᵀ*I_CM*omega`; position and velocity must use a consistent inertial frame. Counting the pre-release swing energy again as an extra impulse would double-count energy. Subsequent energy exchange and losses do not guarantee all angular energy becomes altitude; wing/tail flex is a separate issue.

**Proposed plan change — SG-05/16:** Measure synchronized, calibrated multi-view video or sufficiently light onboard motion sensing across separation: CG position, 3D ground velocity, attitude, body angular rates, release height, controls, wind and build identity. Transform any tracked marker velocity to the CG using its rigid-body lever arm and measured angular rate. Preserve correlated release samples by pilot, aircraft, technique and conditions; do not combine independently sampled marginal maxima. Extend DLG only after a separate peg, structural, release-attitude and rate dataset exists. Do not apply a hidden force after release or present a conventional EG4 overhand toss as a DLG throw.

**Discriminating acceptance experiment:** Reconstruct held-out release states, replay the actual first seconds with no hand force, and compare 3D trajectory, rates, speed and height with synchronized observations and uncertainty. Perturb assumed marker offset to demonstrate its effect. **Remaining uncertainty:** marker occlusion, flexible deformation and sensor weight during high-rate release.

## GI-06 — Bound rigid-wing use with structural evidence

**Priority:** P1 for explicit limits; P2 for measurements; P3 for flexible-wing simulation. **Question:** When is a rigid-body model a defensible approximation, and what evidence separates its limitations from flutter clearance?

**Evidence and finding:** S9 identifies launch-related boom deflection on a specific DLG. S11 identifies in-flight frequencies and damping on a research drone wing; S12 combines ground vibration and flight flutter tests on a different full-size aircraft. They establish mechanisms and methods, not the stiffness, flutter onset or safe operating speed of the EasyGlider.

**Inference and applicability:** Wing bending/twist, hinge free play and flexible tail linkages can change loads and control response before any instability. A visually stiff wing, a numerically stable 240 Hz step, and a successful ordinary glide do not prove a real wing flutter-free. Conversely, absence of a detailed flexible model does not prevent an explicitly bounded rigid first implementation if measured differences are below the intended accuracy.

**Proposed plan change — SG-02/03/05/16:** Record build condition, wing retention, control free play and measured deflection under documented non-destructive loads; where feasible identify low-amplitude ground modes, fixture effects and uncertainty. Declare the supported mass, launch type, airspeed, load/control state and weather evidence. Compare time-aligned measured attitudes and wing deformation with the rigid model; defer DLG, high-speed dives, structural damage, flutter prediction and automatic strength claims beyond the established domain. Do not make exceeding an unknown flutter or strength threshold a fabricated event.

**Discriminating acceptance experiment:** Use predeclared, measurement-based tolerances and matched nominal flights: measure deformation and dynamic response with synchronized wing markers/strain sensing where feasible, then compare retained rigid-body response with held-out traces and residual spectra. If coherent flexible-mode response exceeds the declared tolerance, narrow the supported scenario or research a validated flexible model. Ground testing alone cannot clear flight flutter; retain expert-led assessment and a separate safety envelope. **Remaining uncertainty:** excitation, sensor resolution, damage variation and unmeasured margins.

[S1]: https://www.sv-jme.eu/wp-content/uploads/ns_articles/files/ojs/457/submission/copyedit/457-1090-1-CE.pdf
[S2]: https://www.cambridge.org/core/journals/aeronautical-journal/article/experimental-evaluation-of-the-drag-curves-of-small-fixed-wing-uavs/453B48240E5861B1360B9D33288C5C88
[S3]: https://ntrs.nasa.gov/citations/19880035228
[S4]: https://ntrs.nasa.gov/citations/19880023959
[S5]: https://ntrs.nasa.gov/citations/19750001990
[S6]: https://www.cambridge.org/core/journals/aeronautical-journal/article/offboard-aerodynamic-measurements-of-smalluavs-in-glide-flight-using-motion-tracking/4F2CB54FF6A9C3DF9870305D0EA92044
[S7]: https://ntrs.nasa.gov/citations/19930091496
[S8]: https://www.multiplex-rc.de/userdata/filegallery/original/4934_214332-bedienungsanleitung-easyglider-4--de-en-fr-it-es.pdf
[S9]: https://charlesriverrc.org/articles/on-line-plans/mark-drela-designs/supergee/
[S10]: https://engrcdp.nmsu.edu/assets/img/posters-2025/9%20NMSU%20IAM3D%20Glider.pdf
[S11]: https://ntrs.nasa.gov/citations/19810016531
[S12]: https://ntrs.nasa.gov/citations/19940006761
