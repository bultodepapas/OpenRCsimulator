# Flight Mechanics and 3D Aerobatics Implementation: Stall Plateau, Propwash Authority, and Knife-Edge Flight

2026-10-18 · Contributor branch: `improve-stall-behaviour` · **Status: historical proposal; aerodynamic activation deferred, physical validation pending.**

This document preserves the equations, intended behavior and software results reported by the author of [PR #1](https://github.com/bultodepapas/OpenRCsimulator/pull/1) at `5bb547db`. They describe that experimental branch, not accepted current physics. The quoted numerical results below have not been independently established as real-aircraft measurements.

---

## 1. Problem Diagnosis & Requirements

Testing of aerobatic and sport aircraft (`gp_extra_300s_60`, `jensen_ugly_stik_60`, `turbo_lumber_evolution`) identified four key aerodynamic issues:
1. **Abrupt Stall & Wing Drop**: Strip lift collapsed steeply across the $6^\circ$ stall ramp ($C_L \approx 1.15 \to 0.35$), destabilizing roll damping ($\partial M_x / \partial p > 0$) and causing uncommanded wing drops.
2. **Post-Stall Aileron Reversal**: Adding aileron deflection directly to geometric angle of attack shifted the separation boundary, reversing roll response ($\partial M_x / \partial \delta_a < 0$) on stalled strips.
3. **Loss of Control in Hover & High Alpha**: At airspeeds $V \to 0$, wing strips and ailerons received zero slipstream airflow, eliminating roll authority in static hover and reducing high-alpha blown-wing lift.
4. **Lack of Knife-Edge Support & Side Force**: In large sideslip ($\beta > 20^\circ$), `_local_loads` only accounted for the vertical fin and wing drag, neglecting fuselage side area lift ($F_y$) needed to sustain knife-edge flight.

---

## 2. Mathematical Formulations & Architecture Changes

### A. Stall Plateau Modeling (`stall_plateau`)
In standard thin-airfoil separation, a sudden drop to the pure flat-plate model $\frac{1}{2} C_{D90} \sin(2\alpha)$ neglects the suction plateau retained on moderate-thickness cambered sections at model-scale Reynolds numbers ($Re \sim 2\times 10^5\text{–}5\times 10^5$).

In `app/physics/aero.gd` and `app/physics/aircraft_data.gd`:
$$\begin{aligned}
C_{L,\text{sep}} &= \max\left(0.5 \cdot C_{D90} \cdot \sin(2\alpha), \, \text{plateau} \cdot C_{L,\text{stall}} \cdot \cos^2\alpha\right) \quad (\alpha \ge 0) \\
C_{L,\text{sep}} &= \min\left(0.5 \cdot C_{D90} \cdot \sin(2\alpha), \, \text{plateau} \cdot C_{L,\text{stall}} \cdot \cos^2\alpha\right) \quad (\alpha < 0)
\end{aligned}$$
Where $C_{L,\text{stall}} = \alpha_1 \cdot C_{L\alpha} + C_{L0}$ and `plateau` $\in [0.0, 1.0]$.
- **GP Extra 300S .60**: `stall_plateau = 0.75`
- **Jensen Das Ugly Stik .60**: `stall_plateau = 0.70`
- **Turbo Lumber Evolution**: `stall_plateau = 0.75`

This smooths the lift collapse ($C_L \approx 1.15 \to 0.80$ rather than $0.35$), maintaining positive aerodynamic roll damping throughout stall initiation and eliminating unexpected wing drop.

### B. Post-Stall Aileron Authority Without Sign Reversal
In `app/physics/aero.gd` (`_wing_flow` and `_local_loads`):
- `clean_angle` preserves the section geometric angle of attack without control bias, driving the stall separation weight $w(\alpha)$ and flat-plate normal force.
- Aileron deflection contributes to attached lift via `effective = clean_angle + aileron_shift`.
- In separated flow ($w > 0$), aileron trailing-edge deflection contributes a bounded pressure/camber normal increment:
  $$\Delta C_{L,\text{aileron}} = a_0 \cdot \Delta\alpha_{\text{aileron}} \cdot w \cdot \max(\cos\alpha, 0)$$
  This guarantees $\frac{\partial C_L}{\partial \delta_a} > 0$ across all angles of attack $\alpha \in [0^\circ, 80^\circ]$, eliminating post-stall roll reversal while capturing adverse yaw.

### C. Developed Wing Slipstream for 3D Hover Authority
In `app/physics/slipstream.gd`:
- Propeller wake pieces covering inboard wing strips and ailerons now use developed slipstream velocity:
  $$v_{\text{wash}} = w.dv$$
  rather than contracted mass-flux velocity $w.w$.
- At static hover ($V = 0$, $9000\text{ RPM}$), this delivers full dynamic pressure across inboard wing sections, providing verified static roll authority ($\Delta M_x = 0.408\text{ N}\cdot\text{m}$ on Extra 300S, $0.156\text{ N}\cdot\text{m}$ on Ugly Stik, $0.100\text{ N}\cdot\text{m}$ on Timber) alongside elevator and rudder pitch/yaw authority.

### D. Fuselage Lateral Crossflow & Knife-Edge Side Force
In `app/data/schema/openrc-aircraft-v2.schema.json` and `app/physics/aero.gd`:
Added physical fuselage crossflow properties:
- `body_side_area` ($S_{\text{fuse}}$, $\text{m}^2$)
- `body_side_cd` ($C_{D,\text{side}}$, default $1.1$)
- `body_side_position` ($\mathbf{r}_{\text{fuse}}$, le-frame coordinate)

In `Aero._local_loads()`:
$$\begin{aligned}
\mathbf{v}_{\text{fuse}} &= \mathbf{v}_{\text{cg}} + \boldsymbol{\omega} \times \mathbf{r}_{\text{fuse}} \\
v_{\text{plane}} &= \sqrt{u_{\text{fuse}}^2 + v_{\text{fuse}}^2} \\
F_y &= -0.5 \cdot \rho \cdot v_{\text{plane}} \cdot S_{\text{fuse}} \cdot C_{D,\text{side}} \cdot v_{\text{fuse}} \\
F_x &= -0.5 \cdot \rho \cdot v_{\text{plane}} \cdot S_{\text{fuse}} \cdot C_{D,\text{side}} \cdot |v_{\text{fuse}}| \cdot \frac{u_{\text{fuse}}}{v_{\text{plane}}} \\
\mathbf{M}_{\text{fuse}} &= \mathbf{r}_{\text{fuse}} \times \mathbf{F}_{\text{fuse}}
\end{aligned}$$
- In forward planar flight ($v_1 = 0, \boldsymbol{\omega} = 0$), $F_y \equiv 0$ and $F_x \equiv 0$, preserving byte-exact planar parity.
- In $20^\circ$ sideslip at $22\text{ m/s}$, side force reaches $36.6\text{ N}$ on the Extra 300S, $28.3\text{ N}$ on the Ugly Stik, and $26.9\text{ N}$ on the Timber, intended to support sustained knife-edge passes; real-aircraft agreement remains unmeasured.

### E. In-Flight Dual Rates & Workshop Per-Surface Throws
In `app/main.gd`:
- Added hotkey toggle on `F4` and `3` switching between:
  - `normal`: Low/scale sport rates with exponential damping.
  - `full`: Unrestricted 3D aerobatic throws ($100\%$ servo travel).

In `app/ui/workshop.gd`, `app/workshop/compiler.gd`, and `app/workshop/parameters.gd`:
- Added **"Advanced control surface setup"** toggle checkbox in the Aircraft Workshop.
- Exposed independent throw scaling sliders:
  - `control_multiplier_aileron` ($0.5\times \dots 1.5\times$)
  - `control_multiplier_elevator` ($0.5\times \dots 1.5\times$)
  - `control_multiplier_rudder` ($0.5\times \dots 1.5\times$)
- Real-time surface throw report displaying deflection in degrees ($^\circ$) and compile-time validation.

---

## 3. Historical candidate parameter sketches

The following sketches are retained to explain the proposal. They are not a current authoring recipe: some keys and provenance are incomplete. Use each aircraft’s [source pipeline](../tools/physics.md#aircraft-data-and-generators), never hand-edit generated aircraft JSON.

1. **Fuselage Side Lift / Knife-Edge Sustain**:
   In `surfaces`:
   ```json
   "body_side_area": {
     "value": 0.245,     // Area in m2: increase for more lateral lift during knife-edge
     "unit": "m2",
     "kind": "derived"
   },
   "body_side_cd": {
     "value": 1.1,       // Crossflow drag coefficient (1.1 - 1.5)
     "unit": "1",
     "kind": "estimated"
   },
   "body_side_position": {
     "value": [0.05, 0.0, 0.0], // Area centroid [x, y, z] in le frame
     "unit": "m",
     "kind": "derived"
   }
   ```
2. **Rudder Effectiveness & Authority**:
   In `surfaces.vertical`:
   ```json
   "vertical": {
     "area": { "value": 0.051391 },
     "control_effectiveness": { "value": 0.683146 } // Increase for more yaw torque per radian
   }
   ```
3. **Maximum Rudder Deflection**:
   In `controls.rudder`:
   ```json
   "controls": {
     "rudder": {
       "deflection_max": {
         "value": 0.5236 // Max throw in radians (~30 deg). Can be raised to ~45 deg (0.785 rad) for extreme 3D
       }
     }
   }
   ```

---

## 4. Verification & Acceptance Gates

The contributor reported the following selected software checks. This was not a complete regression pass: subsequent review found force/wake inconsistencies and failing reference tests. None of these checks establishes physical validation:
1. **Planar Parity (`test_aero_flow.gd`)**:
   - `H4`: 20,000 byte-exact local flow comparisons passed.
   - `H12`: 20,001 byte-exact local loads comparisons passed in attached planar forward flight.
2. **Post-Stall Aileron Authority**:
   - 51 checks across $\alpha \in [0^\circ, 80^\circ]$ verified positive roll torque on Extra, Ugly Stik, and Timber (0 failures).
3. **Static Hover ($V = 0$) Authority**:
   - 9 checks verified positive 3-axis control moments at static RPM (0 failures).
4. **Knife-Edge Lateral Force**:
   - 3 checks verified $F_y > 10\text{ N}$ at $\beta = 20^\circ, 22\text{ m/s}$ (Extra: $36.65\text{ N}$, Stik: $28.26\text{ N}$, Timber: $26.89\text{ N}$, 0 failures).
5. **Aircraft Dynamics Suites**:
   - `test_extra_handling.gd`: 12/12 checks passed (spin recovery, high-alpha stall, coordinated rolls).
   - `test_timber_handling.gd`: 36/36 checks passed (handling, flaps, electric powertrain).
   - `test_rates.gd`: 28/28 checks passed.
   - `test_workshop_ui.gd` & `test_workshop_integration.gd`: 0 failed across all UI, compiler, and variant integration checks.


## Integration disposition, 2026-10-26

The contribution is integrated with its original commit ancestry. The accepted feature is independent Workshop surface travel, with inherited defaults, integer-safe storage and regressions; its current behavior belongs in the [Workshop guide](../AIRCRAFT-WORKSHOP.md).

The aerodynamic, stock-aircraft tuning, additional F4/3 rate binding and replacement golden-flight changes are not activated. Production physics, aircraft sources, schemas, generated data and goldens retain the `41fb8dae` baseline. This avoids replacing newer main-line contracts or treating a passing synthetic response test as aircraft validation.

Reasons to defer the physics portion:

- The plateau helper/wake and force-producing local/washed strip paths use different lift laws.
- The wake helper drops the ground-effect correction retained by local wing forces.
- The proposed fuselage area/centroid do not participate in Workshop scaling.
- Submitted powered golden recordings disagree with the submitted runtime; rate provenance also mixes proposed settings with manual claims.

A future activation must reconcile those paths, include positive/negative and reversed-flow limits, preserve a baseline flight log, and compare one solver or aircraft change at a time using [flight logging](../FLIGHT-LOGGING.md). Aircraft/pilot qualification stays open. The original code and tests remain available in commit `5bb547db`; no second dormant production solver is added.
