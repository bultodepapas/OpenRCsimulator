# Stall, Post-Stall Aileron Reversal, and 3D Aerobatics Findings

2026-10-18 · Branch: `improve-stall-behaviour` · **Status: diagnosis and design reference.**

This document records the root-cause findings for the current stall behavior, post-stall aileron reversal, and high-alpha / 3D aerobatic handling limitations in `app/physics/`.

## 1. Post-Stall Aileron Reversal (`app/physics/aero.gd`)

### Mechanism in Current Code
In [`Aero._wing_flow()`](../../../app/physics/aero.gd#L285-L315) and [`Aero._local_loads()`](../../../app/physics/aero.gd#L418-L458), each wing strip ($i \in \{0..5\}$) incorporates aileron deflection by adding an equivalent angle shift directly to the geometric angle of attack:

```gdscript
var control: float = d.aileron_right if ys[i] > 0.0 else d.aileron_left
var angle := wrapf(M.atan2_(f2, f0) + float(model.surfaces.wing_aileron_effectiveness)*control, -PI, PI)
```

In [`Aero._local_loads()`](../../../app/physics/aero.gd#L424-L458), this single `effective` angle (`angles[i]`) drives **both**:
1. The attached lift `base = cl0 + cla * effective` (or the coupled Weissinger map `e_map * angles`), and
2. The stall separation weight `weight = _smoothstep((stall_angle - a1) / a_span)`.

The resulting strip lift is:
$$C_L(\alpha_{\text{eff}}) = (1 - w(\alpha_{\text{eff}}))\,C_{L,\text{attached}}(\alpha_{\text{eff}}) + w(\alpha_{\text{eff}})\,\frac{1}{2} C_{D90} \sin(2\alpha_{\text{eff}})$$

### Why It Reverses Post-Stall
In the stall transition region $\alpha \in [\alpha_1, \alpha_2]$ (for the Ugly Stik, $\approx 12.13^\circ \to 18.13^\circ$; for the Extra 300S, $\approx 11.9^\circ \to 17.9^\circ$), the total slope $\frac{\partial C_L}{\partial \alpha_{\text{eff}}}$ is **strongly negative** because $C_{L,\text{attached}} \approx 1.1\text{–}1.3$ while the flat-plate branch $\frac{1}{2} C_{D90} \sin(2\alpha)$ is only $\approx 0.30\text{–}0.35$ at $15^\circ\text{–}18^\circ$:

- When the pilot commands **right roll** (`c.roll > 0`):
  - The left aileron deflects trailing-edge **down** (`d.aileron_left > 0`), increasing $\alpha_{\text{eff},L}$.
  - The right aileron deflects trailing-edge **up** (`d.aileron_right < 0`), decreasing $\alpha_{\text{eff},R}$.
- Because $\frac{\partial C_L}{\partial \alpha_{\text{eff}}} < 0$ across the stall ramp:
  - Increasing $\alpha_{\text{eff},L}$ pushes the left wing deeper into separation (`weight` $\to 1$), **collapsing its lift** and spiking its pressure drag.
  - Decreasing $\alpha_{\text{eff},R}$ pulls the right wing back toward attached flow (`weight` $\to 0$), **restoring its lift** toward $C_{L,\max}$.
- Consequently, a right-roll stick input produces **upward lift on the right wing and downward lift loss on the left wing**, rolling the aircraft **left** (reversed roll response) while also generating strong adverse yaw from the drag spike on the left wing.
- Furthermore, once fully stalled (`weight == 1.0`), the flat-plate term $\frac{1}{2} C_{D90} \sin(2(\alpha + \tau_a \delta_a))$ loses almost all control authority near $\alpha \approx 45^\circ$ and reverses again for $\alpha > 45^\circ$.

### Comparison with the Existing Flap Law (`AV-09-F` / `P51-11a`)
Notice that [`Aero._local_loads()`](../../../app/physics/aero.gd#L309-L315) already solved a closely related problem for trailing-edge flaps:
- `flaps.stall_shift_fraction` (lines 311, 426): A deflected trailing-edge surface shifts stall onset by only a fraction of its zero-lift camber shift $\Delta\alpha_0$, rather than moving the stall angle 1:1 with the camber shift.
- `flap_lift_delta` (line 466): Even in separated flow (`weight > 0`), camber deflection changes the pressure/normal force on the forward-facing chord plane (`strip_slope * shift * weight * max(cos(alpha), 0)`).
- Applying a consistent physical camber/flap decomposition to ailerons (separating the zero-lift camber lift increment and post-stall normal/camber authority from the stall-angle shift) prevents artificial stall-ramp sign reversal while preserving realistic roll damping and high-alpha control.

---

## 2. Abrupt Stall Initiation & Post-Peak Lift Drop

As quantified in [`D8b-R2`](../flight-robustness/D8b-R2/research-experiments.md):
1. **Steep Transition to Low Flat-Plate Lift:**
   - Over a $6^\circ$ `stall_blend_width`, strip lift blends from $C_L \approx 1.1$ directly to $\frac{1}{2} C_{D90} \sin(2\alpha) \approx 0.30\text{–}0.35$.
   - Real airfoils at $Re \sim 2\times 10^5\text{–}5\times 10^5$ (and finite wings of $AR \approx 5\text{–}6$) retain a much higher post-stall lift plateau ($C_L \approx 0.7\text{–}0.9$ from $16^\circ\text{–}30^\circ$, as modeled in Viterna-Corrigan via the $A_2 \cos^2\alpha / \sin\alpha$ term) rather than dropping immediately to $\frac{1}{2} C_{D90} \sin(2\alpha)$.
   - The $C_L$ cliff causes $\frac{\partial M_x}{\partial p}$ to spike to $+11.1\text{ N}\cdot\text{m/(rad/s)}$, turning any small perturbation into a violent snap roll.
2. **Simultaneous Full-Span Separation:**
   - Without spanwise stall progression (`wing_station_incidence` or root-to-tip stall margin on rectangular/sport wings), all six strips cross `a1` simultaneously during a pitch pull.
3. **Quasi-Steady Separation (No Dynamic Stall Lag):**
   - Instantaneous `weight(alpha)` has no circulation/separation time constant ($\tau \sim k \cdot c / V$), so rapid pitch inputs immediately trigger full separation without dynamic overshoot or progressive buffet/mush.

---

## 3. Propwash and 3D Aerobatic Authority (Hover, Stall Turns, Harriers, Snap Rolls)

1. **Missing Tail & Wing Slipstream on Aerobatic / Sport Aircraft:**
   - Currently, `propulsion.propeller.slipstream` is only configured on `p51d_mustang_120.json` and the experimental `stik_glow_*` files. Neither `jensen_ugly_stik_60.json` nor `gp_extra_300s_60.json` has active slipstream in production.
   - At low airspeed or $V \to 0$ (hover, torque roll, stall-turn pivot), dynamic pressure $q = \frac{1}{2}\rho V^2 \to 0$, so elevator and rudder have **zero authority** without slipstream.
2. **Missing Propeller Slipstream on Inboard Wing & Aileron Strips:**
   - Even when `slipstream.gd` is active, it only washes `pieces` on the `horizontal` and `vertical` tail surfaces.
   - In a hover, harrier, or slow 3D pull, the inboard wing strips (and inboard portions of full-span / strip ailerons) sit directly inside the contracted propeller jet ($r_s \approx 0.707 R \text{ to } R$).
   - Because [`Aero._wing_flow()`](../../../app/physics/aero.gd#L268-L315) and [`Aero._local_loads()`](../../../app/physics/aero.gd#L418-L560) evaluate wing strips using only free-stream `air.v_air + omega x r`, the wing strips see zero axial airflow at $V = 0$, giving **zero aileron roll authority in a hover** and no blown-wing lift in harriers.
3. **Missing Fuselage Crossflow Side Force in `_local_loads` (`FT-01` Finding #1):**
   - Above $|\beta| = 25^\circ$, `local_flow_weight` reaches $1.0$ and fuselage side force (`CYb`) drops out because `_local_loads` only sums wing $x\text{-}z$ strips and tail surfaces, causing excessive sink in knife-edge and weak pendulum/pivot damping in stall turns.
