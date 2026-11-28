# EDF scientific literature review: power, thrust, dynamics and consumption

**Revision:** EDF-00-R3, 2026-11-21. **Reviewed plan:**
`e4b42d064874dd56432b2b83744ad2e4ee0fb881`.
**Scope:** research and implementation-plan changes; no runtime implementation
or newly acquired physical measurements.

This round examines **14 distinct scientific studies of electrically driven
ducted fans**. Their methods and relevant results were reviewed in full-text
papers, including two author-uploaded manuscripts. The original NASA repository
record identifies P01; its author-uploaded full text supplies the readable copy.
Three specialist assignments covered electrical performance, installed-flow
experiments and a fresh Good Enemy challenge. The lead reconciled the findings
and owns these documentation changes.

The result is a more precise measurement and validation contract, not fourteen
sets of coefficients for the Vantage Jet. The chosen 128 mm DS-98 installation
still lacks a matched, independently validated thrust/shaft-load/installed-wrench
dataset. The 152 mm and 195 mm experiments retain separate hardware, geometry,
mass, electrical and evidence identities.

## 1. Decisions that change the implementation plan

1. **Name the power port.** Battery-terminal, ESC-input, motor-shaft and
   aerodynamic shaft-load power are different quantities. Record measured,
   efficiency-inferred, reaction-torque-derived and CFD-derived power separately.
2. **Report consumption as energy over a stated mission.** Static thrust per
   electrical watt is useful on a stand, but is not a dimensionless efficiency
   or an endurance measurement. Mission energy, charge, cutoff and reserve need
   their own accepted-state accounting.
3. **Validate thrust and power independently across the envelope.** Matching a
   static thrust curve does not qualify current, wind-on behavior, moments,
   response time or heating. Preserve each output's measured support.
4. **Treat an installed propulsor as a coupled load problem.** Record the force
   boundary and held-constant variable for comparisons. Do not add a measured
   whole-aircraft axial force to an independently computed aircraft drag force.
5. **Keep geometry and source conventions auditable.** Rotor diameter, casing,
   hub, annulus, tip-gap basis, surface finish, stators and power measurement
   location belong in the map identity. Corrections and unresolved discrepancies
   affect whether numerical reuse is admissible.
6. **Identify dynamics before adding dynamic states.** A fitted spool constant
   is conditional on the hardware, step, operating point and measurement chain.
   Begin with the existing coupled inertia/motor/fan model; add a separately
   identified controller or inflow state only when discriminating data require it.
7. **Keep runtime small and native.** Use prepared, bounded C++ laws and native
   accepted-step metrics. CFD, paper digitization and parameter estimation are
   offline evidence tools. This review adds no runtime CFD, scripting dependency,
   second solver or relaxed qualification gate.

The authoritative equations and metric definitions are in
[the physics contract](physics-and-sources.md#performance-and-consumption-metrics).
Sequencing belongs to [the implementation plan](../../plans/edf-propulsion.md);
T37–T40 and strengthened V01–V06 are in
[the validation matrix](validation-matrix.md).

## 2. Study register and counting rules

Each P entry is one distinct investigation. P05's correction is part of P05,
not another experiment. P13's 2025 conference presentation and 2026 journal
manuscript describe the same wing experiment and count once. P01 and P13 are
distinct isolated-fan and wing campaigns with related hardware and researchers;
they are not fourteen statistically independent hardware replications.
Supplementary X entries do not contribute to the fourteen-study count.

| ID | Scientific paper | Primary text inspected / identifier |
| --- | --- | --- |
| P01 | R. Weinstein and B. M. Simmons (2024), *Experimental Characterization of an Electric Ducted Fan for the SUSAN 25% Scale Research Vehicle* | [NASA record](https://ntrs.nasa.gov/citations/20230017299); [author-uploaded paper](https://www.researchgate.net/publication/377800337_Experimental_Characterization_of_an_Electric_Ducted_Fan_for_the_SUSAN_25_Scale_Research_Vehicle). DOI: 10.2514/6.2024-1524. |
| P02 | O. Odukoya and B. W. Jo (2026), *Experimental Investigation and Performance Evaluation of an Electric Ducted Fan (EDF) for Distributed Propulsion Systems* | [Author-uploaded AIAA paper](https://www.researchgate.net/publication/406026587_Experimental_Investigation_and_Performance_Evaluation_of_an_Electric_Ducted_Fan_EDF_for_Distributed_Propulsion_Systems). DOI: 10.2514/6.2026-4746. |
| P03 | D. Urban et al. (2023), *Effect of Electric Ducted Fans Structural Arrangement on Their Performance Characteristics* | [Publisher full text](https://www.mdpi.com/2076-3417/13/5/2787). DOI: 10.3390/app13052787. |
| P04 | S. Zhang et al. (2026), *Evaluation and Selection of Multiple k-ω Turbulence Models for Micro Electric Ducted Fans Through Experimental Validation* | [Publisher full text](https://www.mdpi.com/2226-4310/13/7/625). DOI: 10.3390/aerospace13070625. |
| P05 | H.-Q. Chu et al. (2025), *Static Aero-Propulsion Experiment of an Electric Ducted Fan*, with the authors' 2026 correction | [Article](https://www.mdpi.com/2226-4310/12/6/509) and [correction](https://www.mdpi.com/2226-4310/13/5/458). DOIs: 10.3390/aerospace12060509; 10.3390/aerospace13050458. |
| P06 | T. Ebus, M. Dietz and A. Hupfer (2021), *Experimental and numerical studies on small contra-rotating electrical ducted fan engines* | [Publisher full text](https://link.springer.com/article/10.1007/s13272-021-00517-7). DOI: 10.1007/s13272-021-00517-7. |
| P07 | D. Castroviejo, M. Van Der Stichelen and P. Hendrick (2022), *Distributed electric propulsion with blended wing-body for fixed-wing UAVs* | [EUCASS paper](https://www.eucass.eu/doi/EUCASS2022-4724.pdf). DOI: 10.13009/EUCASS2022-4724. |
| P08 | L. Cho, S. Lee and J. Cho (2013), *Numerical and Experimental Analyses of the Ducted Fan for the Small VTOL UAV Propulsion* | [J-STAGE paper](https://www.jstage.jst.go.jp/article/tjsass/56/6/56_T-12-8/_pdf). DOI: 10.2322/tjsass.56.328. |
| P09 | M. Ryu, L. Cho and J. Cho (2016), *Aerodynamic Analysis of the Ducted Fan for a VTOL UAV in Crosswinds* | [J-STAGE paper](https://www.jstage.jst.go.jp/article/tjsass/59/2/59_T-14-79/_pdf). DOI: 10.2322/tjsass.59.47. |
| P10 | P. Martin and C. Tung (2004), *Performance and Flowfield Measurements on a 10-inch Ducted Rotor VTOL UAV* | [NASA-hosted paper](https://rotorcraft.arc.nasa.gov/Publications/files/Martin_2004.pdf). DOI: 10.4050/VFS-F60-000007. |
| P11 | A. Akturk and C. Camci (2011), *Tip Clearance Investigation of a Ducted Fan Used in VTOL UAVs, Part 1: Baseline Experiments and Computational Validation* | [Author-hosted paper](https://cengizcamci.github.io/papers/GT2011_46356_DUCTED_FAN_1.pdf). DOI: 10.1115/GT2011-46356. |
| P12 | P. D. Bravo-Mosquera, H. D. Cerón-Muñoz and F. M. Catalano (2023), *Potential Propulsive and Aerodynamic Benefits of a New Aircraft Concept: A Low-Speed Experimental Study* | [Publisher full text](https://www.mdpi.com/2226-4310/10/7/651). DOI: 10.3390/aerospace10070651. |
| P13 | R. Weinstein, V. A. Spada and B. M. Simmons (2026), *Experimental Study of Aeropropulsive Interactions for Electric Ducted Fans on a Wing* | [NASA accepted manuscript](https://ntrs.nasa.gov/api/citations/20250007333/downloads/Weinstein_Spada_Simmons_ADEPT_2026_JoA_accepted.pdf). DOI: 10.2514/1.C038401. |
| P14 | F. Casagrande Hirono et al. (2024), *Aerodynamic and aeroacoustic design of electric ducted fans* | [Cambridge accepted paper](https://api.repository.cam.ac.uk/server/api/core/bitstreams/18df53c2-16e0-4c41-9002-05969b55b4e2/content). DOI: 10.1016/j.ast.2024.109411. |

### P01 — A useful model-identification protocol, with separate validation

The Jetfan 130 Pro campaign varies voltage, RPM, freestream conditions and
incidence. It identifies static drive, dynamic drive, thrust and electrical
power models and evaluates observations excluded from fitting. Sections IV–VI
are the relevant methods/results. Its acquisition streams have different rates:
power-supply V/I at 2 Hz, ESC telemetry at 50 Hz and analog balance channels at
2500 Hz. These are not interchangeable transient measurements.

**Adopt:** independent conditions, output-specific models and synchronized
measurement provenance. **Limit:** its hardware and electrical power model do
not identify our fan's shaft load; a whole-assembly balance does not become a
shaft dynamometer. Retain the campaign's actual domain and channel bandwidth.

### P02 — Static fits and a limited transient sample

The Jetfan 120 Pro/HET motor experiment records thrust, RPM and ESC electrical
telemetry. Tables 2–3 report static fits and a spin-up mean of 95.0 ms with
86.9 ms standard deviation over eleven fitted steps; no usable spin-down events
are reported. The described static fit is not independent held-out validation.
The measured electrical-power exponent alone cannot establish shaft efficiency
without the assumed shaft-power law and loss evidence.

**Adopt:** collect both step directions and preserve variation, command history,
sensor delay and operating point. **Reject:** a universal 95 ms EDF response,
its use as an aircraft control limit, or importing the fitted RPM exponents as
the DS-98 law. A high fit R² is not an independent accuracy result.

### P03 — Outlet geometry changes static electrical demand

The 50/64 mm prototype study measures thrust, RPM and electrical power. At about
1.96 N, the 50/0.8, 50/1 and 50/1.1 variants respectively need 198, 135 and
123 W (§3, Figure 5). The outlet parameter uses an **annular area ratio**,
not simply an outlet/fan diameter ratio. Printed finish and tolerances matter;
the 64 mm sequence is not strictly monotonic. The two-rotor arrangements rotate
in the same direction.

**Adopt:** compare controlled geometry at equal thrust and preserve manufacturing
context. **Limit:** these are static electrical watts, not flight energy, shaft
efficiency or a universal optimum nozzle ratio. Reaction torque on the stand
needs a verified mechanical boundary before shaft interpretation.

### P04 — Three static points do not establish an operating map

The 120 mm study compares turbulence models with three stabilized static
commands, each repeated three times. Tables 2–4 report approximately 8.39, 39.38
and 88.56 N with 0.500, 2.269 and 7.329 kW electrical input. Section 5.4
distinguishes measured DC power from CFD rotor torque times angular speed;
their ratio is not an independently measured motor/ESC efficiency.

**Adopt:** keep DC and predicted shaft quantities separate and retain the small
experimental sample count. **Limit:** low thrust error at these points does not
qualify transients, current prediction, crossflow or a flight envelope. Published
tables contain small power-rounding differences; preserve the chosen table and
precision. Raw proprietary geometry/data are not a reusable complete map.

### P05 — Large electric fans exist, and corrections matter

The experiment uses a 386 mm rotor in a 390 mm assembly with a BLDC drive and
two LiFePO4 pack configurations. It reports thrust, voltage sag, current and RPM
over repeated static tests (§4). The 2026 correction changes rotational-speed
units to rad/s and recomputes coefficient figures; the corrected article and
correction must travel together. Manual electrical readings do not identify
fast current or spool dynamics.

**Adopt:** large-fan electrical loading and voltage sag belong in the acquisition
plan. **Limit:** no diameter-only extrapolation to 128/152/195 mm, no transfer of
its recommended operating limit, and no aircraft endurance inferred from its
static battery tests. Preserve the source's figure-of-merit definition rather
than equating it to a fraction of battery energy converted into thrust.

### P06 — Contra-rotation requires separate electrical and rotor boundaries

The 132 mm contra-rotating rig has independently controlled front and rear
motors. Sections 2.3 and 3 describe total balance loads, mass flow/pressure,
RPM and separate ESC-input voltage/current measurements. Static observations
are ten-second averages sampled at 10 Hz. The authors explicitly distinguish
electrical input from shaft power.

**Adopt:** retain per-drive power measurement and total-versus-component load
ownership. **Limit:** a total torque balance cannot determine both rotor loads;
the steady averaging does not identify transient states. This motivates clean
interfaces, not a two-rotor requirement for the first single-rotor Vantage Jet.
Contra-rotation is different from P03's same-direction two-rotor arrangement.

### P07 — Check arithmetic and the flow measurement, not only the conclusion

The 50/64 mm bench investigation compares ducted and unducted electric fans.
Section 3 contrasts direct force with pitot-derived estimates; a single local
velocity is insufficient to represent the whole exit. Its reported 355→620 g
thrust comparison is called a 43% increase, but the increase relative to 355 is
74.65%; about 42.74% is the deficit relative to 620. Parasitic duct drag was not
measured for an installed forward-flight comparison.

**Adopt:** preserve direct-force evidence and the comparator denominator.
**Limit:** do not import the stated percentage, its static power savings or a
uniform-exit-flow assumption into the A200. Instrumentation listing alone does
not supply a validated matched shaft-power dataset.

### P08 — Inferred shaft power needs its efficiency assumption

The electrically driven 248 mm rotor/250 mm duct has three rotor blades and
five stators. Section 5 compares static tests with computation. Equation 9
calculates shaft power from motor input voltage, current and manufacturer
calibration efficiency; this is **inferred power**, not independent inline
shaft-torque measurement. Intake geometry affects comparison with the numerical
model.

**Adopt:** store the efficiency source, its applicable conditions and uncertainty
when using inferred shaft power. **Limit:** it cannot independently validate
both our motor efficiency and fan torque. A static duct comparison supplies no
wind-on installed-wrench envelope. Its hardware is distinct from P09.

### P09 — Crossflow affects more than axial thrust

The BLDC-driven 198 mm rotor/200 mm duct study uses a six-component balance.
Equation 13 infers shaft power through an electrical-input/efficiency relation.
Experimental incidence points cover −30°…+30° at 3, 6 and 9 m/s; the wider
incidence investigation includes CFD predictions beyond that measured domain
(§§3–4, Figures 10–11).

**Adopt:** acquire side force and moments with incidence/sideslip, and label
experimental and predicted support separately. **Limit:** do not turn the CFD
angle sweep into measured coverage or transfer VTOL crosswind coefficients to
the A200. Negative inflow, reversed rotor spin, windmilling and electrical
regeneration remain different physical/electrical states.

### P10 — A duct's axial contribution can change sign

Preston Martin and Chee Tung test a 254 mm electric ducted rotor with an
electrical drive/gearbox, comparing rotor, duct and complete configurations in
hover and wind-on conditions. Their power includes electrical-system losses.
At low RPM, Figure 6 and its discussion identify net duct download relative
to the isolated rotor. Their figure of merit deliberately chooses an ideal
reference for comparison; an alternative ducted reference is discussed.

**Adopt:** allow signed duct contributions and preserve the reference-area and
power definitions. **Limit:** neither a positive duct multiplier nor a universal
figure-of-merit bound follows. Configuration-difference loads are not simultaneous
component sensors and need their own interaction/tare uncertainty.

### P11 — Tip gap needs a denominator and a measurement boundary

The 22-inch/559 mm, eight-blade fan uses a 20 hp BLDC motor. Its hover experiment
measures force, support reaction torque, RPM and pressure. Clearance is expressed
relative to **blade height**, not rotor diameter. The results compare several
clearances and the unducted rotor; power derived from reaction torque requires
the mounted-assembly boundary to be retained.

**Adopt:** record clearance value, denominator and manufactured geometry; preserve
how torque becomes power. **Limit:** no universal clearance multiplier, no
assumption that support torque is an isolated rotor-shaft measurement, and no
forward-flight validation from hover tests. This is useful large-EDF evidence,
not a calibration substitute for the smaller jet installation.

### P12 — Aircraft power savings are not isolated-fan efficiency

The box-wing experiment compares podded and partially buried electric-fan
installations. It measures the complete model and electrical input; Figure 12's
reported saving is at **zero net axial force**, where positive propulsion and
aircraft resistance balance. Mechanical flow power was not measured. The article
also gives a 70 mm outer duct dimension and a 73 mm fan diameter in adjacent
method sections without resolving their compatibility.

**Adopt:** compare installed aircraft at an equal stated operating condition and
keep total-model loads separate from fan thrust. **Limit:** no generic BLI gain,
shaft-efficiency claim or geometry reconstruction. The unresolved dimensions
block quantitative geometry reuse until clarified.

### P13 — Wing and fan loads cannot always be superposed

The NASA wing campaign evaluates one-, three- and five-fan arrangements with
Jetfan 130 Pro units and multiple placements. The balance measures total
aeropropulsive loads; it does not separately resolve thrust and aircraft drag.
Sections II–IV describe configuration-dependent interactions and power-system
constraints. Longer motor wiring also changes the drive relative to the earlier
isolated-fan experiment.

**Adopt:** preserve installation, wiring, actual RPM and electrical conditions;
use an explicitly owned installation residual or a complete installed law.
**Limit:** equal throttle commands do not establish equal RPM or input power.
Do not add the measured total load to standalone fan and airframe loads. Related
P01 hardware and the earlier conference version are disclosed dependencies.

### P14 — Aerodynamics, electrical matching and sound are related objectives

The study designs and tests three electrically driven rotor/stator sets, using
wind-on thrust and acoustic evidence. Its Figure 14 efficiency is a **CFD
polytropic stage efficiency**, not measured battery-to-propulsive efficiency.
The prose's 120 mm tip diameter conflicts with Table 1's listed tip radius;
the table's radius/area values also require clarification before numerical reuse.

**Adopt:** assess propulsion and sound at matched operating conditions and keep
flow-design metrics distinct from electrical metrics. **Limit:** do not copy an
unresolved geometry or promise an identified acoustic spectrum from blade-pass
frequency. Native audio remains an accepted-state observer; CFD and acoustic
analysis stay offline.

## 3. Supplementary evidence and exclusions

| ID | Source and access | Useful scope / exclusion |
| --- | --- | --- |
| X01 | A. I. Abrego, I.-C. Chang and R. W. Bulaga (2002), *Performance Study and CFD Predictions of a Ducted Fan System*: [NASA paper](https://ntrs.nasa.gov/api/citations/20020052417/downloads/20020052417.pdf). Full text, also examined in the earlier research round. | A 38-inch electrically driven installation broadens the large-fan context, including forces/moments in wind-on flow. Related presentations and a later NASA report are not counted as new experiments. No DS-215 coefficient transfer. |
| X02 | S. H. Shin et al. (2022), *Experimental Study on Aerodynamic Performance and Wake Characteristics of the Small Ducted Fan for VTOL UAV*: [journal abstract](https://journal2.ksas.or.kr/publication/View.asp?idx=25441&sf=J2021049). DOI: 10.5139/JKSAS.2022.50.1.1. | The 104 mm electric-fan abstract motivates wake/side-force measurements. Full methods and power boundary were not available in this review; excluded from the fourteen full-text studies. |
| X03 | S. Yilmaz, D. Erdem and M. S. Kavsaoglu (2015), *Performance of a Ducted Propeller Designed for UAV Applications at Zero Angle of Attack Flight: An Experimental Study*: [institutional abstract](https://research.itu.edu.tr/en/publications/performance-of-a-ducted-propeller-designed-for-uav-applications-a/). DOI: 10.1016/j.ast.2015.06.005. | Component-force/torque lead; drive type and full methods were not verified. Not counted as a confirmed EDF study or used for numerical calibration. |

Reddit and supplier claims remain leads in
[the earlier twenty-investigation round](native-research-2026-11-21.md).
They do not count toward this scientific-paper requirement. Search hits without
an inspectable primary paper were not promoted merely to increase the count.

## 4. Source audit and numerical-adoption policy

| Audit issue | Disposition in the plan |
| --- | --- |
| Corrected speed/coefficient convention, P05 | Preserve original publication, correction status and exact acquired version. Convert dimensional quantities before recomputing coefficients. A correction is not a second experiment. |
| Ambiguous efficiency or power denominator, P01–P14 | Store the metric formula, power port, force boundary, area and frame. Never normalize different metrics by their display name. |
| Source-defined figure of merit, notably P02/P05 versus P01/P10 | For coefficients based on `ρ n² D⁴` and `ρ n³ D⁵`, an open circular-disk comparison uses `sqrt(2/π) * CT^(3/2) / CP`. A `1/sqrt(2)` multiplier implies a different reference area. Preserve source-defined values; do not silently relabel or clamp ducted metrics. |
| Arithmetic/comparator discrepancy, P07 | Recompute from reported dimensional values, disclose the baseline and keep the discrepancy attached to any extracted comparison. |
| Geometry inconsistency, P12/P14 | Mark unresolved; do not repair the paper by guessing. Qualitative lessons remain usable while geometry-dependent coefficient adoption is blocked. |
| Fit quality presented as broad validation, P02/P04 | Keep fit, independent validation, CFD prediction and measured domain as distinct evidence roles. No extrapolated measured envelope or universal controller constant. |
| Related hardware or publication versions, P01/P05/P13/X01 | Retain an experiment-family identifier and dependency notes; do not inflate sample size or apparent independent replication. |

These are evidence-quality findings, not newly reproduced simulator bugs.
The existing repository findings and bounded repair ownership remain in
[the repository audit](repository-audit.md).

Before a paper can contribute numerical calibration, EDF-02b must acquire the
actual reusable data/file with its content hash and rights, document any
digitization and corrected-version chain, resolve relevant measurement boundaries,
and identify independent validation observations. A web citation is not a raw
data package. This review links papers; it does not redistribute their figures,
fabricate raw data or claim that a PDF was hashed when only rendered text was read.

## 5. Concrete integration into implementation steps

| Owner / step | Required addition | Decisive evidence |
| --- | --- | --- |
| EDF-01 / EDF-02 | Freeze power/force/metric provenance, correction status, geometry conventions and experiment-family identity. | T37 catches coefficient-unit/port mismatches and unresolved geometry before numerical adoption. |
| EDF-03 | Keep signed installed wrench and aerodynamic shaft load jointly consistent; identify either a complete installed law or an owned residual. | T39 exposes full-aircraft force double counting and equal-command comparisons with unequal RPM/power. |
| EDF-04 | Preserve source, wiring, auxiliary-load and shaft-loss ownership; identify up/down dynamics independently. | Existing energy/ESC gates plus T40/V02 distinguish delay, response and measurement filtering. |
| EDF-08 | Add native stand metrics and accepted-flight energy/charge/limiting summaries with explicit unavailable states. | T38 and actual Godot review; zero-speed and zero-input ratios cannot produce misleading efficiency. |
| EDF-09 | Acquire static, wind-on, installed and transient evidence separately, with declared sensor bandwidth and independent runs. | V01–V05 retain output-specific errors and uncertainty; absent data remain inconclusive. |
| EDF-10 | Compare controlled missions at each sibling's own mass/trim and reserve/termination policy; EDF reports terminal Wh/Ah, turbine reports its supported fuel measures. | T24/T38 plus V06 for physical claims; nominal Wh/peak-W is not endurance, and pack-only energy is not a common turbine/EDF efficiency metric. |
| EDF-11 | Refit/re-identify each fan installation; keep equal-thrust, equal-RPM and equal-input-power comparisons separate. | Existing factorial campaign plus per-size source/geometry/power-port receipts and domain reporting. |

### Minimum physical acquisition sequence

1. **Document the hardware:** actual rotor/hub/duct geometry, manufacturing and
   clearance basis, motor/ESC/firmware/wiring, pack and instrumentation. Resolve
   relevant ambiguities before claiming that a measurement describes the model.
2. **Run steady isolated tests:** synchronized terminal/ESC V/I, thrust and RPM
   across command and voltage/SOC, with repeats, tare, environment and thermal
   stabilization recorded. Acquire independent shaft information if torque or
   electromechanical efficiency is to be physically identified.
3. **Run wind-on and installed tests:** use the actual inlet/nozzle; record
   axial and transverse flow, complete wrench, and measured RPM/power. Select
   fixed-RPM or fixed-electrical-power comparisons in advance. Include powered,
   source-off and relevant restart conditions within the admissible envelope.
4. **Run dynamic tests:** independent upward/downward steps with declared size,
   history and SOC/temperature, sensor timing, latency, filtering and repeatability.
   Separate transport/telemetry delay from rotor/drive response before adding lags.
5. **Run matched mission validation:** use an independently acquired flight or
   load history with the actual pack, mass/CG, atmosphere and cooling. Score
   thrust-related outcomes, terminal energy, voltage/cutoff and modeled
   temperatures separately; reserve a final untouched validation campaign.

This order supplies discriminating information without requiring a CFD solver
in the simulator. Acquisition can proceed in parallel with the synthetic native
stand. Missing hardware data block the corresponding realism claim, not the
explicitly estimated software experiment.

## 6. What this round does and does not establish

The paper count, critical review and plan changes are completed research work.
The proposed native functions, metric accumulators, datasets and T/V gates remain
implementation work. No new endurance, thrust, acoustic, thermal, native-speed
or physical-fit result is claimed for the Vantage Jet.

Actual documentation checks and review disposition are recorded in
[the research index](README.md#verification-and-delivery). Existing calculation
artifacts remain reproducible planning calculations; neither arithmetic nor a
literature citation qualifies a physical aircraft.
