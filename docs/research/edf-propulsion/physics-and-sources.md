# EDF physics, installation research and primary sources

**EDF-00 · 2026-11-21 · Research, not an implemented or physically validated aircraft.**
Repository baseline: `57abea025f62b20233ca281d58d2acbee4ab8b8e`.
The [implementation plan](../../plans/edf-propulsion.md) owns sequencing; the
[audit](repository-audit.md) owns current-code findings. Source IDs below identify
public material inspected during this investigation. Numerical examples are
reproduced by [calculations.py](../../../research/edf-propulsion/calculations.py)
and retained in [calculations.json](calculations.json).
The [independent external audit](external-audit-2026-11-21.md) records corrections
to the original research candidate and the limits retained after review.

## 1. The experiment and its aircraft identity

An electric ducted fan is an electrically driven rotor in a duct, usually with
stationary outlet guide vanes. It does not burn fuel, and its motor, controller,
battery, fan and installed duct jointly determine its operating point. A turbine
throttle-to-RPM schedule cannot identify that system.

The existing **Vantage Jet** is the SebArt Avanti S A200 reference,
`sebart-avanti-s-a200-p100rx`, with the 2017 non-BL P100-RX. Its manufacturer lists
2.00 m span and 2.22 m length; the listed 10.5 kg is a **dry turbine RTF** weight,
not an EDF conversion mass [S11]. The manufacturer's Avanti XS is a separate
1.80 m-span aircraft with an EDF option [S12]. Its mass, duct geometry and setup
must not migrate into the A200 simply because both names contain Avanti.

Retain the A200 wing, tail, controls, retracts and airframe identity for the
experiment. Author a new powertrain and inventory, and disclose any local inlet,
rear-fuselage or nozzle changes. Do not enlarge the entire airframe to make a fan
fit and still call the result the unchanged A200. Existing geometry is a physical
surrogate; rendered appearance does not measure its internal clearances.

## 2. Large-fan candidates

The following are **manufacturer isolated static ranges**, not paired endpoints,
installed thrust guarantees, or complete motor/ESC/battery maps [S03–S09].

| Candidate | Casing inside diameter | FSA | Static thrust | Electrical input | Fan + motor mass | Listed pack class |
| --- | --- | --- | --- | --- | --- | --- |
| DS-98 HST / DSM6036-600 | 128 mm | 98 cm² | 82–107 N | 4.7–7.0 kW | 1.25 kg | 12–14S, 9 Ah |
| DS-130 HST / DSM7857-470 | 152 mm | 130 cm² | 135–175 N | 8–12 kW | 1.75 kg | 12–14S, 14 Ah |
| DS-215 HST / DSM10066-290 | 195 mm | 215 cm² | 215–250 N | 9.8–15.6 kW | 3.40 kg | 12–14S, 20 Ah |

**Recommended research order:** identify the 128 mm system first, use the 152 mm
case to study increased power and installation demand, and retain the 195 mm case
as the deliberately oversized experiment. The model numbers are not diameters.
No candidate's casing, intake, outlet, pack or mounting fit is established here.
The 128 mm installation is selected for a useful comparison with the existing
100 N turbine reference, not because its installed performance or fit is known.

The DS-98/DSM6036, DS-130 and DS-215 charts identify their ESC, a VDI 2041 test
intake and ISA correction [S04, S25, S08]. Digitization must retain that setup and estimate chart
reading uncertainty. Do not infer a measured torque map from plotted electrical
power. The DS-215 chart's filename says `295`, while its internal motor label and
product specification say `290`; resolve the exact hardware identity before
calibration. Its older flyer lists 10–14S, whereas the current page lists 12–14S
[S07, S08, S24]. Preserve the disagreement instead of silently combining limits.

Other useful comparisons are the developer's Jetfan 130 Pro and WeMoTec's
100 mm/HET setup [S13, S14]. The latter states test conditions and is a useful
lower-power check of the measurement workflow. Neither supplies an A200 map.

### Energy and current arithmetic

Assume **14S at 3.7 V nominal per cell**, constant stated electrical power and an
illustrative usable fraction of **80% of nominal energy**:

$$
E_{nom}[Wh]=N_s V_{cell,nom} C[Ah],\qquad
I_{nom}=P_e/V_{nom},\qquad
t[min]=60 f E_{nom}/P_e.
$$

| Scenario | Nominal energy | Constant input | Nominal current | Arithmetic duration |
| --- | --- | --- | --- | --- |
| 14S, 9 Ah | 466.2 Wh | 7.0 kW | 135.1 A | 3.20 min |
| 14S, 14 Ah | 725.2 Wh | 12.0 kW | 231.7 A | 2.90 min |
| 14S, 20 Ah | 1,036 Wh | 15.6 kW | 301.2 A | 3.19 min |

These are energy-budget examples, not endurance forecasts. Sag, actual current
history, weakest-cell cutoff, temperature, auxiliary loads and installed thrust
are absent. Nominal voltage is not full-charge or under-load voltage. At a fixed
power requirement a lower terminal voltage requires more current; an actual
unregulated motor need not maintain that power as voltage falls.

One 6S/10 Ah pack page has conflicting masses: **1.357 kg in its description** and
**1.296 kg in its specification table** [S15]. Preserve that disagreement until
the exact hardware is weighed. Two such packs in series are 12S/10 Ah,
**not 12S/20 Ah**; the description-based mass example is 2.714 kg, while the other
listed value gives 2.592 kg. The page distinguishes cell C-rating from pack
capability and specifies only **60 A continuous / 90 A pulse** for the complete
pack. It is therefore a mass illustration, not a compatible supply for the
high-power scenarios above. Do not fabricate a 14S/20 Ah pack's mass from its
capacity alone. MGM's ESC ratings have PWM, electrical-RPM,
temperature and cooling conditions [S16]; a nameplate current is not an
unconditional installed limit.

### Same-airframe mass budget

The pinned A200 inventory totals **11.438578 kg**, including **1.29628 kg** of
fuel. Removing the modeled turbine (1.08 kg), accessories (0.30 kg), thrust tube
(0.35 kg), empty tank (0.30 kg), fuel and virtual ballast (0.062298 kg) leaves
**8.05 kg** in that inventory. Sources: [generated aircraft](../../../app/data/aircraft/sebart_avanti_s_a200.json)
and [owning generator](../../../research/avanti-s/av06/derive_physics.py).

Adding only a 1.25 kg fan/motor and the illustrative two-pack mass gives an
**incomplete 12.014 kg subtotal**, using the description's 1.357 kg per pack.
The conflicting 1.296 kg value would instead give 11.892 kg. Neither identifies
an approved high-current pack. New ducts, ESC, wiring, mounts and balance are
missing. The retained receiver/ECU-battery and avionics entries bundle several
devices; their split is unresolved. This is not a minimum certified build mass
or an EDF all-up estimate. Recompute CG, full inertia, thrust arms, trim, wheel
loads, suspension support and stall envelope from the final authored inventory.
Battery charge depletion does not remove battery mass as fuel depletion does.

## 3. Force and power boundaries

Use SI units internally, revolutions per second for `n`, radians per second for
`Omega`, and explicit thrust and spin axes. Body axes are FRD; the repository's
authored installation offsets use aft/right/up and require conversion. The
existing [aircraft contract](../../AIRCRAFT_CONTRACT.md) owns the datum rules.

For a steady axial stream with a defined upstream ambient capture plane and exit
plane, no fuel addition, and consistently accounted pressure/duct forces:

$$
T_{net}=\dot m(V_e-V_0)+(p_e-p_0)A_e.
$$

This is the control-volume accounting relationship [S02], not a complete model
for unknown mass flow, pressure rise, nozzle loss or incidence. In an installed
force model the external duct/nacelle force, spillage and pressure surfaces need
explicit ownership. A pressure term at an internal inlet plane cannot simply be
omitted while retaining the far-upstream formula.

Choose one of two representations per identified law:

| Representation | What the model owns | What must not be added again |
| --- | --- | --- |
| Measured **installed net wrench** map | Measured installation force and moment at its declared datum; tare and airframe exclusions recorded | Separate ram drag, duct lift, stator moment or installation multiplier already inside the measurement |
| Component pressure/flow model | Fan pressure rise/shaft work, duct losses, nozzle state and a complete force/moment balance | A second empirical net-thrust force for the same stream |

For the first coupled implementation use an identified fan/installation map with
separate rotor load and installation wrench. Keep a component pressure model as
a later, evidence-dependent option. Do not reconstruct a complete pressure-rise
curve from a single static thrust point. A measured open-intake map requires a
new, explicit installation correction or installed measurements; record the
correction as estimated until qualified. Assign airframe drag terms carefully
when replacing the turbine inlet/exhaust treatment.

Local aircraft-relative-to-air velocity at a station is
`v_air_at_O + omega_body cross r_station - (wind_station - wind_O)_body`,
where `r_station` is from the authored fixed datum O and every term uses the same
stage, frame, time and environment. Axial speed is positive along the forward
thrust axis. The wind difference vanishes in uniform wind. Spatial wind is
**already implemented**: [WindFlow](../../../app/physics/wind_aircraft_flow.gd)
prepares `air.propulsion_air_body` with both corrections. Register the EDF intake
station and consume that receipt once; do not add rotation or the gradient again.
Keep the existing receipt identity. EDF-00-R2 requires native sampling and
evaluation for every admitted EDF weather mode, with launch refusal when that
capability is absent; the non-EDF fallback policy is unchanged. Intake and
nozzle force locations can differ,
so a net axial thrust alone does not identify the pitching moment. For crossflow,
use a measured wrench or a labeled bounded approximation; do not quietly borrow
the turbine's full-vector momentum continuation.

Station-center flow is not a blade-element flow field. A fixed-housing fan map
usually neglects body-rate and ambient-vorticity gradients across the finite
disc. At zero relative shaft speed, a fan center on the roll axis can have zero
station velocity while its blades still move through air with the rolling body.
Declare this quasi-steady approximation and its body-rate/low-speed domain; bound
its omitted loads for a physical claim or add identified rate-dependent inputs.
Avoid a singular `|body_rate|/Omega` rejection rule at ordinary starts: use a
declared dimensional or regularized error bound. Motor back EMF uses speed
relative to its stator; adding body spin indiscriminately changes that convention.

## 4. Fan maps and their validity envelope

For `n > 0` and a declared **blade-tip diameter** `D`:

$$
J_a=V_a/(nD),\quad C_T=T/(\rho n^2D^4),\quad
C_Q=Q_{fan}/(\rho n^2D^5),\quad
C_{P,fan}=P_{fan}/(\rho n^3D^5)=2\pi C_Q.
$$

`D` is not automatically the catalog casing diameter. Store rotor diameter,
casing diameter, hub diameter, tip clearance and fan swept area separately.
Here `P_fan=Q_fan*Omega` is relative-shaft aerodynamic load power. At nonzero body
rate it is not, alone, the rotor-fluid torque's full inertial-frame work. Motor shaft power
`Q_motor*Omega` can differ during rotor acceleration and due to mechanical
losses/body coupling. `C_P,electrical` from DC power is **not** either mechanical
power coefficient. If shaft torque is
inferred using motor/ESC losses, record that inference and its uncertainty; do
not tag it measured. A thrust/power fit alone cannot identify motor resistance,
no-load loss, inertia and fan torque independently.

The preferred map includes axial flow, incidence/crossflow, speed and relevant
density/temperature effects. Fix its interpolation, axes, row order, endpoint
policy and valid domain. At a given operating point solve the electrical source
and fan load together; a throttle-to-thrust lookup bypasses this coupling.

**Support is joint and output-specific.** A static voltage sweep is a correlated
locus of observed voltage, current, RPM and thrust, not a measured box containing
every combination of their extrema. It does not identify wind-on loads, shaft
torque, rotor inertia or installed moments. Record acquired points and admissible
interpolation cells/hulls, holes and uncertainty for each output. Separate
published/digitized thrust, inferred shaft load and assumed residual moments;
one measured channel cannot label the entire wrench/load model measured.

For EDF-02a, a fully synthetic map with an explicit finite operating domain is a
valid software fixture. Mark all its outputs and domain estimated; selected
parameter ranges are sensitivity assumptions, not statistical confidence bounds.
EDF-02b/09 physical calibration needs matched independent observations. Withheld
positions on the same published smoothed curve test interpolation, not an
independent experiment. A useful identifiability check fits two plausible
parameter sets to the static observations and compares their independent
transient/wind-on predictions. Unresolved divergence limits the physical claim.
NASA's tested wind-off power model needed wind-on data for that regime [S01,
section VI.G]; its coefficients do not identify this installation.

At similar `J_a`, geometry and flow regime, dimensional scaling suggests
`T ~ rho n²D⁴` and `P_shaft ~ rho n³D⁵`. At constant tip speed, both scale with
`rho D²`; at constant RPM they have different strong diameter dependencies.
These are similarity relations, not permission to scale a 90 mm map into a
195 mm installation. Hub ratio, duct area ratios, tip clearance, blade geometry,
Reynolds number, tip Mach and losses must also be comparable. Check tangential
tip Mach `pi n D/a`; helical relative velocity and actual acoustic speed refine
the screen. Numerical exploration outside measured support must be labeled.

### Direct experimental evidence and limits

NASA's 2024 Jetfan 130 Pro study uses independent identification and validation
data, varying voltage, speed, freestream and incidence. Its stators nearly cancel
measured steady net torque; independent shaft torque was unavailable. It observes
windmilling and negative net thrust in part of its tested domain. Its transient
fit depends on controller ramp settings and step size [S01]. Those observations
justify separate torque channels, wind-on data and controller-specific dynamics.
They do not calibrate the Schübeler candidates or establish universal thresholds.

### Zero speed, windmilling and reverse flow

`J_a` is singular at zero RPM. Define a dimensional low-speed branch for the
selected installation and prove continuity to its rotating map. Distinguish
stopped/freewheel, electrically driven, source-disconnected, and any future
braked mode. A rotor may extract mechanical energy from the air while the
motoring-only ESC sends no energy to the battery. Track that aerodynamic work,
rotor energy and dissipation. Negative net thrust can be drag and must not be
globally clamped to zero.

An admitted experimental flight law needs a **bounded physical operating
envelope**, which may be entirely estimated. Where measured support exists,
distinguish it from estimated continuation through throttle-off, high advance
ratio and ordinary aircraft incidence. All-stage reporting requires pure stage
diagnostics and qualified accepted-path transport that cannot leak rejected
trials. That transport does not currently exist as a general `VehicleModel`
facility: EDF-01 must prototype it or explicitly report endpoint-only quality,
which cannot certify intermediate-stage support (EDF-A11).

Keep a third domain separate: **event-locator trial continuation**. The current
[event step](../../../app/physics/event_step.gd) intentionally probes negative
trial RPM to bracket a stop, and the
[electric battery policy](../../../app/physics/electric_battery_step.gd) similarly
uses negative trial charge near exhaustion. These are not accepted reverse spin
or negative SOC. Reusing that policy requires a finite moving-side extension
through zero that retains the EDF's zero-speed fan load and installation wrench.
Prove that the extension covers every admitted probe, or qualify an owner-controlled
guarded locator with the same battery/contact/LVC composition. Merely refusing a
coarse beyond-boundary probe prevents localization; an arbitrary narrow negative
range without a safe refinement route does not fix it. Trial diagnostics must
remain distinguishable from physical-domain quality and rejected trials publish
nothing. Nonfinite values and unrelated invalid maps still refuse atomically.

Outside the admitted physical envelope, a non-locator evaluation refuses the
tick. The session must enter a visible paused/fault outcome with the last accepted
frame, boundary/reason, recorder status and reset/Home recovery; no repeated
automatic retry, clock advancement or hidden law/backend substitution. A stand
prototype may refuse all unsupported physical states. Accepted reverse rotor
rotation, active braking and regeneration remain separately unsupported unless
their laws, energy paths and events are implemented. If torque at rest exceeds the
declared static-hold capacity toward an unsupported reverse-spin direction,
refuse that trial/tick rather than clamp the rotor with an invented reaction.
Test forward breakaway, static hold and reverse-breakaway refusal with native
parity and rollback. Aerobatic reverse inflow is not evidence of reverse rotor
rotation.

## 5. Shaft torque, stators and the rigid body

The central integration distinction is between **rotor aerodynamic load** and
**the whole installation's external aerodynamic torque**. A stator can recover
swirl while the motor still supplies substantial shaft power. Use different
outputs even when an early surrogate assigns them simple values.

Use a unit **spin axis** `a_s` and nonnegative relative speed `Omega`. It may be
aligned or opposed to the thrust axis; declaring both avoids changing thrust
direction when changing rotation sense. Let `I_L` be locked aircraft inertia
about the live CG, `J_r` the rotor axial inertia, `w` body rate, and
`h=J_r Omega a_s` relative rotor momentum. `M_ext` is the **total external moment
about that same CG**, expressed in body axes, including other vehicle loads when
balancing the complete aircraft. The installation map returns its wrench about
the authored datum O; transfer its moment once with
`M_CG = M_O - r_CG/O cross F` before adding the other external moments:

$$
I_L\dot{\mathbf w}=\mathbf M_{ext}-
\mathbf w\times(I_L\mathbf w+\mathbf h)-J_r\dot\Omega\mathbf a_s,
$$

$$
J_r(\dot\Omega+\mathbf a_s\cdot\dot{\mathbf w})=Q_{motor}-Q_{fan}.
$$

These are the repository's [RotorCoupling](../../../app/physics/rotor_coupling.gd)
equations with the EDF's two torque channels made explicit. The whole
installation's fluid moment can, where identified, be represented as
`(-Q_fan + Q_stator) a_s` plus other aerodynamic moments. Alternatively consume a
measured total moment directly. Do not combine both representations. Do not add
motor reaction, stator recovery, spin-acceleration reaction or gyro a second time
after the corresponding channel has included it.

Acceptance requires an ideal steady fixture with zero net axial angular-momentum
flux at both upstream and downstream boundaries and no other external axial
fluid moments. Nonzero opposing rotor/stator torques then give zero total
external axial torque; a spool transient still exchanges body/rotor momentum.
Test both spin-axis conventions. Reflection symmetry applies only to a fully
mirrored rotor/stator/installation fixture: for reflection matrix P, polar
vectors transform with P and axial vectors with `det(P) P`; inertia transforms
with `P I P^T`. Reversing the motor of unchanged pitched hardware is not that
symmetry and remains outside the first slice. Carrier inertia must remain
physical after rotor reservation. None of these fixtures asserts zero residual
torque for every real EDF.

### Independent mechanical-energy and passivity oracles

For constant `I_L`, `J_r` and fixed axis, the rotational kinetic energy and its
rate derived from the two equations above are

$$
K=\tfrac12\mathbf w^T I_L\mathbf w+
J_r\Omega(\mathbf a_s\cdot\mathbf w)+\tfrac12J_r\Omega^2,
\qquad
\dot K=\mathbf w\cdot\mathbf M_{ext}+\Omega(Q_{motor}-Q_{fan}).
$$

The cross term is required even though the locked inertia already includes the
rotor. For the one-axis synthetic fixture `I_L=2`, `J_r=0.5`, `w=3`, `Omega=4`,
`M_ext=2` and `Q_motor-Q_fan=3` in SI, `K=19 J` and `Kdot=18 W`. Add translation,
gravity and other external work separately for a full-aircraft ledger, with
force/moment and velocities expressed at consistent datums.

For a quasi-steady complete installation in uniform ambient air, with no omitted
interacting surfaces, fluid-energy storage, externally supplied heat, mass
injection or other unaccounted energy flux, a necessary aerodynamic passivity
check is

$$
\mathbf F\cdot\mathbf v_{air,O}+\mathbf M_{ext,O}\cdot\mathbf w
-Q_{fan}\Omega\leq 0.
$$

`M_ext,O` here contains the whole installation's external aerodynamic moment,
not other vehicle loads. Test the paired wrench/load map at interpolation
interiors as well as nodes. At `V=20 m/s`, `F_x=-1 N`, `Omega=100 rad/s` and
`Q_fan=-1 N m`, the expression is **+80 W** despite plausible windmill signs:
the fit creates mechanical energy. Do not apply this instantaneous inequality
unmodified to spatial/unsteady inflow, thermal energy delivered into the stream
or an incomplete boundary; those require their declared flow-energy/storage
terms. In uniform flow, transferring both wrench and velocity consistently
preserves `F dot v_air,O + M_O dot w = F dot v_air,CG + M_CG dot w`, with
`v_air,CG = v_air,O + w cross r_CG/O`. The calculator reproduces these
synthetic counterexamples, not a measured EDF efficiency bound.

## 6. Electrical source, ESC and heat

Reuse the existing motor's DC-equivalent convention, with `Kv` in rpm/V:

$$
K_t=60/(2\pi K_v),\quad E_b=RPM/K_v,\quad
I_m=\max((dV_b-E_b)/R_m,0),\quad
Q_m=K_t(I_m-I_0)
$$

for its admitted rotating motoring branch. The actual starting/friction rule is
owned by [electric_motor.gd](../../../app/physics/electric_motor.gd). Do not
combine a line-to-line datasheet resistance with a differently defined winding
equivalent without conversion evidence. Motor constants need matched temperature
and electrical conventions.

The DC-equivalent constant-loss model is a bounded approximation. Drela's
primary derivation distinguishes resistance, speed-dependent no-load losses and
matched parameter measurements [S26]; catalog Kv alone cannot identify them.

For the ideal averaged ESC, `I_b=d I_m+I_aux`. Existing finite-pack code solves
this with `V_b=E_pol-R_pack I_b` at each stage. With a fixed duty, the active
branch has denominator `R_m+d²R_pack`; evaluating each side on an unsagged bus
does not solve the same system. Keep motor current, battery current, phase-current
ratings, DC power and mechanical power distinct. Future multiple EDFs require
one shared-bus solve, not a cloned pack for every fan.

The algebraic motor and averaged ESC do not resolve winding inductance, PWM
ripple or commutation. Specify the equivalent-current, controller sampling and
measurement-filter bandwidth; compare like-for-like filtered bus-current peaks.
Do not claim instantaneous phase peaks or cycle-level protection from a 240 Hz
averaged model [S27]. A synthetic stalled circuit with `L=100 microH`, `R=0.1 ohm`
and `V=25 V` approaches 250 A with a 1 ms time constant, while the algebraic
model jumps immediately to 250 A. Adding a controller limit does not supply the
missing electrical waveform.

The current ideal ESC has no installed current limit, command ramp, motor/ESC
thermal state, switching loss, brake or regeneration model. Before a large-EDF
flight is described as electrically credible, add or identify a bounded command
ramp and current limit, with an explicit sensed-current convention, sample rate,
saturation, hysteresis and cutoff recovery. A first research configuration may
retain an explicitly ideal controller; it cannot claim manufacturer's start or
transient current behavior. Current limiting changes effective duty and must be
solved with the bus/load, not applied only to displayed amps.

Close the energy ledger over a declared system boundary: DC bus delivery,
controller/motor losses, rotor kinetic-energy change, mechanical work on the
air, battery losses and any identified thermal storage. Inflow can supply energy
in windmilling; do not impose a motoring-only power inequality on every regime.
Avoid charging battery heat with losses already dissipated outside the pack.
Existing `pack_ecm` provides pack temperature and cell polarization; it does not
measure motor or ESC temperature. Thermal models need heat capacities, loss maps
and cooling evidence [S17]. The [thermal admission finding](repository-audit.md#edf-a01-battery-thermal-stiffness-is-absent-from-the-admission-bound)
must be resolved before relying on arbitrary new pack cooling parameters.

For a fixed-parameter RC branch, `C= tau/R` and
`I V_RC = V_RC²/R + d(0.5 C V_RC²)/dt`. Consequently OCV power minus terminal
power is not just heat during a pulse/rest transient. With `I=1 A`, `R0=0.1 ohm`,
`R1=1 ohm`, `tau1=1 s`, `V1=0.5 V`, the drop power is 0.60 W, dissipation
0.35 W and RC storage rate 0.25 W. Preserve this distinction in T07.
The existing SOC/temperature-dependent R and tau make C variable; interpreting
`0.5 C V²` as storage then introduces `0.5 Cdot V²`. Restrict the exact capacitor
oracle to fixed parameters, or explicitly derive/account for that parameter
work. Do not silently extend the empirical ECM into a proven full-chemistry
energy model. Its terminal-energy accumulator is not chemical depletion.

## 7. Inlets, nozzle area and unusually large installations

Fan swept area is the blade annulus:

$$
A_{FSA}=\pi(D_{tip}^2-D_{hub}^2)/4.
$$

Manufacturer guidance discusses outlet areas near FSA and smaller areas for
particular fast installations [S10]. This is a starting design heuristic with
conditions, not a universal optimum. For an unobstructed circular exit,
`D_exit=sqrt(4 r_A A_FSA/pi)`: an 85% **area** ratio is not an 85% diameter ratio.
Account for any hub/fairing occupying the exit itself.

| Candidate FSA | Diameter at 85% area | Diameter at 100% area | Existing 72 mm surrogate outlet area / FSA |
| --- | --- | --- | --- |
| 98 cm² | 103.0 mm | 111.7 mm | 41.5% |
| 130 cm² | 118.6 mm | 128.7 mm | 31.3% |
| 215 cm² | 152.5 mm | 165.5 mm | 18.9% |

The current [physical surrogate](../../../assets/aircraft/avanti-s-a200/geometry.json)
has `installation.outlet_radius_m=0.036`. That is a strong reason to investigate
an EDF-specific outlet, **not a measured obstruction or proof of infeasibility**.
The manufacturer's fan casing inside diameter likewise does not include mounting
clearance. Two side inlets need measured open area, shape and bend losses; their
outer silhouette does not establish capture area.

Changing nozzle area changes fan operating point and load, not just exhaust
velocity at fixed power [S20]. Inlet recovery, distortion, incidence and tip
clearance can affect performance [S18, S21, S22]. Large or VTOL experiments supply
mechanisms and test ideas, not small-RC coefficients [S19, S23].

An open actuator-disk ideal-power formula uses an open-disk control volume and
effective area. It is not a universal efficiency bound when the EDF's blade
annulus is substituted for that area while duct forces remain in total thrust.
Use conservation over the actual installation and consistent experimental
boundaries. Do not reject real ducted-fan data solely because that substitution
produces an apparent ideal-power contradiction.

### Native model selection after the second research round

The [twenty investigations](native-research-2026-11-21.md) add primary physics,
native-engine and tooling sources without treating them as new hardware
calibration. The following decisions constrain EDF-01…06/09/11:

- **Keep the model compact and identifiable.** Prepare geometry-specific maps
  offline; report regression rank/conditioning, tare effects and parameter
  ambiguity. CFD may support a labeled surrogate after its own boundary/grid
  checks, but is not an in-flight solver or automatic measurement substitute.
  Each size needs actual rotor/chord/hub/clearance, Reynolds and helical-Mach
  context; casing dimensions and nominal power do not establish similarity.
- **Check the joint power inequality inside the admitted domain.** Monotone
  scalar interpolation and valid vertices do not prove interior passivity when
  the inputs also vary. The normalized example `Omega=x, Q=x, F=x, V=1` on
  `[0,1]` has residual `F V - Q Omega = x - x²`: zero at both ends, positive
  inside. It is an algebraic counterexample, not an EDF dataset. By contrast,
  at one fixed input, common convex weights on complete output tuples preserve
  an inequality affine in those outputs. Independent force/torque weights do
  not. Apply the earlier scoped complete-installation inequality, including
  its body-rate/flow assumptions; see R2-01/09 and T32.
- **Resolve electrical topology before adding model order.** Use a declared
  averaged one-quadrant drive and initially ideal-isolated source-off assumption.
  Aerodynamic windmilling, winding-current freewheel, braking and regeneration
  are different concepts. R2-05 derives a bounded direct active-limit branch
  for a simple synthetic circuit; feasibility and branch checks remain required.
  It also shows why a 1 ms winding mode cannot be added to one unsplit 240 Hz
  RK4 step. A higher-order model needs coupled numerical admission and storage.
- **Identify each dynamic effect separately.** Shaft inertia and motor/fan
  torque already create spool response. Additional empirical lag or dynamic
  inflow can double-count it unless independent transients identify the added
  effect and its work/storage boundary. The present pack model's ohmic/RC heat
  omits reversible entropy heat and spatial hot spots; pulse/rest voltage
  identification and independent mission-temperature validation answer different
  questions. An average pack temperature is not the hottest-cell temperature.

These are model and implementation decisions, not measured speedups or new
physical promotion. The [native design](native-runtime-design.md) specifies
bounded data/workspace, strict float64 arithmetic and complete transaction
ownership; the [matrix](validation-matrix.md) retains separate software and
physical gates.

## 8. Source register and acquisition limits

All links below were inspected on **2026-11-21**. Dates identify publication or
document context where known; a web crawl date is not a hardware revision. No
manufacturer was contacted and no external files or logos are redistributed.
Product information is evidence for the listed setup, not a purchase recommendation.
NASA abstracts were used only for the bounded mechanisms stated here; S01 was
read as a full paper. Full digitized curves, file hashes, rights checks and
matched installed measurements are explicit EDF-02 work.

| ID | Primary source | What it can support / limit |
| --- | --- | --- |
| S01 | [NASA, Weinstein & Simmons, 2024, EDF characterization](https://ntrs.nasa.gov/citations/20230017299), [full paper](https://ntrs.nasa.gov/api/citations/20230017299/downloads/Weinstein_SciTech2024_Final.pdf?attachment=true) | Closely relevant RC-sized installation; force, DC power, transient and validation method; not Schübeler calibration or measured shaft torque. |
| S02 | [NASA Glenn, thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) | Momentum and exit-pressure accounting; not a fan performance model. |
| S03 | [Schübeler DS-98 HST](https://www.schubeler.com/product/ds-98-dia-hst/) | Exact selected motor option, geometry and static ranges. |
| S04 | [DS-98 / DSM6036-600 performance chart](https://www.schubeler.com/wp-content/uploads/2021/02/DS-98-DIA_HST_DSM6036-600.pdf) | Isolated VDI-intake, ISA-corrected curves; plot reading is not raw data. |
| S05 | [Schübeler DS-130 HST](https://www.schubeler.com/product/ds-130-dia-hst/) | Actual 152 mm case and motor/pack range. |
| S06 | [Schübeler DS-82 HST](https://www.schubeler.com/product/ds-82-dia-hst/) | Smaller 120 mm comparison; motor options cannot be mixed. |
| S07 | [Schübeler DS-215 HST](https://www.schubeler.com/product/ds-215-dia-hst/) | Actual 195 mm case; current page has motor-label ambiguity relative to chart link. |
| S08 | [DS-215 performance chart](https://www.schubeler.com/wp-content/uploads/2021/02/DS-215-DIA_HST_DSM10066-295_MGM40063-3.pdf) | ISA/VDI setup; filename 295 versus chart 290 must be resolved. |
| S09 | [Schübeler HST series flyer, copyright 2016](https://www.schubeler.com/wp-content/uploads/2021/02/HST-Series.pdf) | Historical current ranges and setup comparisons, not a current limit certificate. |
| S10 | [Schübeler ducting guidance, 2016](https://www.schubeler.com/channel-configuration/) | FSA, diffuser and intake design guidance with installation-dependent limits. |
| S11 | [SebArt Europe A200 reference](https://www.sebart-europe.com/product-page/avanti-s-2-3m) | Airframe dimensions and dry turbine RTF description. |
| S12 | [SebArt North America Avanti XS](https://www.sebartusa.com/avanti-xs.html) | Distinguishes the smaller EDF-capable aircraft. |
| S13 | [Jetfan 130 Pro developer page](https://www.cnc-luftsporttechnik.de/shop/impeller-und-motoren/impeller-und-ersatzteile/impeller-jetfan-130-pro/) | Alternative assembly class and bench context; no A200 fit evidence. |
| S14 | [WeMoTec Midi Fan100 / HET 700-68-1000](https://shop.wemotec.com/Midi-Fan100-evo-Impeller-HET-700-68-1000-12s-85A-56N-completely-mounted-fine-balanced-and-harmonically-tuned) | Defined smaller-system manufacturer test conditions. |
| S15 | [Tattu 6S 10 Ah pack](https://gensace.de/products/tattu-10000mah-22-2v-30c-6s1p-lipo-battery-pack-with-xt90-anti-spark-plug) | Conflicting 1,357/1,296 g entries; 60 A continuous / 90 A pulse pack specification despite cell C-rating. Mass example only. |
| S16 | [MGM HBCi 30063 controller](https://mgm-compro.com/controllers-inverters-escs/hbci-30063/) | Conditional DC/phase-current, cooling and electrical-speed ratings; illustrative, not the selected matched controller. |
| S17 | [NASA QUEEN ESC thermal tests, 2025 conference](https://ntrs.nasa.gov/citations/20240015333) | Direct thermal-test methodology and separate cooling modes. |
| S18 | [NASA large-scale ducted-fan tests, 1966](https://ntrs.nasa.gov/citations/19660015325) | Tip-clearance and nacelle mechanisms; scale limits explicit. |
| S19 | [NASA ducted-fan performance study, 2002](https://ntrs.nasa.gov/citations/20020052231) | Geometry/flight-condition experiment; 38-inch system, not an RC map. |
| S20 | [NASA bypass nozzle area experiment](https://ntrs.nasa.gov/citations/20140004860) | Changing exit area changes fan operating point; turbofan-simulator scale. |
| S21 | [NASA powered inlet at high incidence, 1977](https://ntrs.nasa.gov/citations/19770024152) | Recovery/distortion/separation measurement design; not A200 coefficients. |
| S22 | [NASA tandem-fan inlet tests, 1981](https://ntrs.nasa.gov/citations/19810017539) | Pitch/yaw and inlet-geometry effects; configuration-specific. |
| S23 | [NASA pneumatic inlet/diffuser investigation, 2003 report](https://ntrs.nasa.gov/citations/20040001424) | Shroud and static/forward-flight tradeoffs; blowing is outside this EDF scope. |
| S24 | [DS-215 historical technical flyer](https://www.schuebeler-tech.com/wp-content/uploads/2021/02/DS-215-DIA-HST-1.pdf) | Historical 10–14S statement versus current 12–14S; retain both identities. |
| S25 | [DS-130 / DSM7857-470 performance chart](https://www.schubeler.com/wp-content/uploads/2021/02/DS-130-DIA_HST_DSM7857-470_MGM40063-3.pdf) | 2019 static voltage sweep; MGM TMM40063-3, VDI 2041 intake, ISA correction; not installed/wind-on validation. |
| S26 | [Drela, MIT, DC motor model, March 2006](https://web.mit.edu/drela/Public/web/qprop/motor2_theory.pdf) | DC-equivalent conventions, loss variation and parameter identification; not measurements of these BLDC assemblies. |
| S27 | [Texas Instruments, BLDC winding-current and protection note, 2016](https://www.ti.com/document-viewer/lit/html/SSZTBP2/GUID-E16F6FD4-B74F-4AB0-990E-C89D493A2398) | Inductance, commutation and PWM bus/winding-current distinctions; no matched EDF controller calibration. |
| S28 | [NIST TN 1297, combined standard uncertainty](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-5-combined-standard-uncertainty) | Components, covariance and correction of systematic effects. |
| S29 | [NIST TN 1297, expanded uncertainty](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-6-expanded-uncertainty) | Coverage factors and conditions on coverage interpretation; not a mandated OpenRC tolerance. |
| S30 | [NIST TN 1297, reporting uncertainty](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-7-reporting-uncertainty) | Report method, components, factor and basis of probability claims; supports the physical-card protocol. |

Public static curves constrain the first experiment, but do not identify all
required laws. Missing quantities include rotor inertia, equivalent motor losses,
shaft torque under flow, residual moment, installed duct pressure/force, exact
controller behavior, pack impedance and cooling. Record estimates with bounds,
run sensitivity sweeps, and reserve separate held-out measurements for physical
validation. A source count is not a confidence score.
