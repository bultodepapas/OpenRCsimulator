# Phoenix RC flight model, decoded, and its translation to OpenRC

Dated research, 2026-11-20. Sources: the Phoenix 6.0.i update scripts in the owner's ISO corpus (`resources/objects/aircraft/physics.sim`, `functions.sim`, `fixedWing/airplane.sim`), read with [decompile_luac.py](../../../research/aircraft-creator/phoenix/decompile_luac.py) (the chunks keep local names and line numbers); strings of the owner's `Simulator.exe` 5.5.k; the Phoenix Builder user guide; an OpenRC kernel code map; and a web survey of real models. Nothing from the stock scripts is committed: this note restates the formulas in our own words. Units below are SI unless noted; Phoenix works internally in centimetres and its scripts convert.

## 1. How Phoenix flies a fixed-wing model

**Wings and tails** are split into 20 sections per airfoil (`physics.num_airfoil_sections`). Each section's force comes from the airfoil's tabulated 2D polar (`resources/airfoils/*.sim`, −90…90° at 0.5°, linear interpolation):

- lift `CL(α_local)·½ρV_l²·A`, where the local velocity includes the **propeller wash** and α_local is measured from the section normal; no finite-span reduction of the lift slope;
- drag `(CD_section + CL²/(π·AR·0.85))·½ρV²·A` on the free-stream velocity only (no wash), with Phoenix's span efficiency 0.85 (`physics.airfoil_efficiency`).

The engine (`pxModel_computeWing`) reads `Fine_tuning.Lift`, `Dihedral` and `Wash` next to this computation; their exact use is engine-internal. Stall is the polar's own, plus a scripted **stall severity** term: when either wing tip's angle passes the airfoil's stall angles (`pxModel_airfoilStallAngles` × `Fine_tuning.Stall.speed`), the excess /50 × severity (capped by `Stall.limit`/2000) drives a wing drop on the deeper side.

**Fuselage** drag is `0.75 × ½ρV² × Fuselage_drag_area.frontal` along the body axis; the lateral and vertical areas fly as two flat plates on the "Funfly" polar (lateral counted, vertical not). On the ground the script adds a speed-proportional rolling drag (weight × 20, fading with throttle) and yaw damping.

**Propellers** (one script step per unit):

- RPM is *commanded*, not computed from a motor: `RPM = Idle + throttle^Throttle_Curve × (Max − Idle)`, slewed at `Response.load` / `Response.unload` full ranges per second; throttle below 15 % is shaped cubically. There is no battery or motor model.
- Static thrust `T = Pitch·D³·RPM²/20000` N (Pitch and D in metres) × blade factor (2 → 1, 3 → 1.3, 4 → 1.54, 5 → 1.85, 6 → 2.06) × `Fine_tuning.Thrust`/100. That is a thrust coefficient Ct ≈ 0.147·P/D per two blades.
- Thrust falls linearly with the axial speed to zero at 1.6 × the pitch speed (`RPM/60 × Pitch`).
- The thrust line is rotated by `Down_thrust` and `Right_thrust`.
- Reaction torque is `2.1 × thrust × Torque% × Fine_tuning.Torque%`, **faded out between 5 and 10 m/s** forward speed; on the ground a separate yaw "ground torque" (`Ground_Torque_Effect`) acts at low throttle.
- **Prop wash** speed = pitch speed above idle × a thrust-to-weight factor × the same speed fade × `Fine_tuning.Wash`, reduced by forward speed, applied to every airfoil (`Wash` per airfoil) and reaching the tail through a short delay line.
- Angular damping is added in proportion to the wash and the weight (`pxModel_setAngularDamping`), plus a flat-spin yaw term.

**Turbines and ducted fans** (`type = "turbine"`): RPM slews over `Spool_Time`; thrust = `Idle_Thrust + RPM fraction × (Max_Thrust − Idle_Thrust)` in newtons × `Fine_tuning.Thrust`, × (1 − 0.01 × axial speed in m/s): a straight 1 % per m/s loss, i.e. the momentum law with an efflux speed of 100 m/s. No wash, no torque.

**Controls**: each channel is `applyExpo` (|x|^(1 + 2·Expo/100), signed), the low rate when switched, a dead band, then a servo that moves 1/`Servo_Speed` of the half travel per millisecond (`Servo_Speed` 25 → 50 ms for a full throw). `Fine_tuning.Elevator/Aileron/Rudder` scale the **deflection**, as do the `*_Rate` setup values; rudder couples into roll and pitch through `Rudder_Roll_Coupling` and `Rudder_Elevator_Coupling`.

**Global fudges**: gravity grows slightly with the nose's vertical attitude (`980 + 100·|look.y|` cm/s²) and a self-righting roll torque acts at low throttle with sideslip.

## 2. OpenRC's kernel, as the translation target

From the [kernel map](../../AIRCRAFT_CONTRACT.md): a hybrid aero model. Global small-angle coefficients blend into three local strips per wing side plus tail elements beyond the attached limits, with Viterna flat-plate post-stall, a lagged downwash state, optional tabulated `wing_polar`, optional `ground_effect`, wing twist, flaps and `controls.rates`.

Propulsion: `electric_prop` (motor/ESC/battery law with Ct/Cp tables, reaction torque always on, gyroscopic rotor), `glow_prop` (the only kind with the opt-in tail slipstream), and `turbine` (momentum thrust with ram drag at the intake, spool limits, no torque, no wash; energy `prescribed_fuel`). One propulsion unit per aircraft. **Electric records cannot carry any propeller wash**, so Phoenix's wash-driven low-speed authority and damping have no record-level equivalent; the contract also says not to fly an EDF on tractor-propeller coefficients.

## 3. Real-world anchors

From manufacturers and reviews (survey 2026-11-20; sources in the survey transcript, summarised):

| Model | Span | Flying weight | Power | Notes |
| --- | --- | --- | --- | --- |
| Apprentice S 15e | 1.50 m | 1.39 kg | 15-size 840 kV, 11×8 | 33 dm² |
| EasyStar | 1.37 m | 0.68–0.70 kg | Speed 400, 6×4 | 24 dm² |
| Radian | 2.0 m | 1.07 kg | glider, folding prop | 35.5 dm² |
| Habu 2 | 0.92 m | 1.47 kg | 69 mm fan, 4S | about 36 m/s top speed, 3–7 min |
| F-4 Phantom 80 mm | 0.91 m | 2.9–3.0 kg | 80 mm fan, 6S | about 36 m/s |
| T-28 1.1 m | 1.12 m | 1.08 kg | 3S/4S | mild stall |
| Mentor | 1.63 m | 2.0 kg | 3528-1000, 11×5.5 | 45 dm² |
| FunCub | 1.40 m | 1.13 kg | 3S | |

RC ducted fans: 70 mm 12-blade units give about 16–18 N static on 4S (1.3–1.8 g/W); efflux speed ≈ √(T/(ρ·A_exit)) ≈ 65 m/s for a 70 mm fan (50–80 m/s across 50–90 mm fans). Momentum theory: T(V) = ρ·A·Ve·(Ve − V), linear to zero at the efflux speed for a constant efflux, slower decay at constant power. No measured stall speeds, climb rates or roll rates of these models were found; roll comparisons should use the helix angle p·b/(2V).

## 4. What follows for the translation

- **Phoenix's own steady performance can be computed** from the decoded formulas (static thrust, thrust at speed, drag build-up, stall from the polar peak, and the level-flight band at half throttle from the commanded-RPM law): [phoenix_reference.py](../../../research/aircraft-creator/phoenix/phoenix_reference.py) gives a reference per model, independent of OpenRC, to compare flight cards against.
- **Thrust**: Phoenix's static law (Ct ≈ 0.147·P/D) sits 20–30 % below measured propeller data (UIUC APC Sport 11×6), and its linear decay to 1.6 × the pitch speed is generous at speed. The converter keeps the measured table's shape: the advance ratio stretches with the pitch ratio, the coefficient with its square root, times Phoenix's blade factor and thrust tuning; the power coefficient rises where needed to keep the static figure of merit at most 0.8 (small propellers reach about 0.75); Kv is calibrated so the runtime's full-throttle static RPM is Phoenix's Max_RPM.
- **Drag**: Phoenix's fuselage coefficient is 0.75 on the frontal area; the converter used 0.3, which made imported models too fast (Habu 2 card 53 m/s against about 36 m/s real).
- **EDFs and turbines** belong in OpenRC's `turbine` kind (momentum thrust, ram drag, spool limit, no torque), with the Phoenix `Max_Thrust`, `Idle_Thrust` and `Spool_Time`. The converter keeps Phoenix's 100 m/s efflux for both, for parity with Phoenix; a real 70 mm fan's efflux is nearer 65 m/s.
- **Wash** cannot be reproduced on electric records; the static-thrust cap and the absent wash damping stay explicit limitations. The cap is 3 × weight, the upper end of real extreme 3D electrics; Phoenix specifies up to about 5 × on a few models.
- **Controls**: Phoenix tuning scales throws; expo and low rate map to `controls.rates`; Phoenix servos are much faster than the 0.14 s estimate.
- **Centre of gravity**: Phoenix's wing `Position` is the root leading edge (Builder guide), and model positions are percent of `Size` relative to the CG. Across the 114 stock models the CG sits at a median 33 % of the root chord (quartiles 26–39 %), the real-model range, so Phoenix applies its lift near the quarter chord and its CG translates literally.

## 5. Translation results (2026-11-20)

Corpus: 114 stock fixed-wing and glider models, real propose, apply, compile and start sequence ([creator_corpus.gd](../../../research/aircraft-creator/phoenix/creator_corpus.gd)); level speeds from the kernel's own trim on the exported records.

| Measure | Result |
| --- | --- |
| Compiled / airborne starts / hand launches | 110 / 92 (75 before the start reference below) / 17 |
| Level speed at full throttle, ours / Phoenix reference | jets median 1.02 (8 models); propellers median 1.10, quartiles 1.04–1.14 (98) |
| Level speed at half throttle | at the top of Phoenix's half-throttle band for most models (Piper Cub 14.6 vs 14.7 m/s, Tutor 40 16.3 vs 16.5, Habu 2 27.0 vs 26.6, F-4 24.9 vs 24.9, A-10 turbine 39.5 vs 38.9) |
| Static margin | median 13 % of the mean chord, quartiles 9–21 %; the package domain bounds it to 8–30 % |

The product starts airborne flights trimmed at half throttle, searching upward from the record's start speed. Phoenix's own law levels many models at half throttle only between 1.05 and 1.6 × the stall speed, so the converter's start reference is the whole aircraft trimmed level at 7° of body angle (tail load about the CG, elevator within 80 % of its travel), never slower than about 1.2 × the stall speed. Of the 18 models still without an airborne start, 11 cannot fly level at half throttle in Phoenix's own law either (B-17, P-47, Rare Bear, SE5a, UM Spitfire, 4-Site Micro, Grasshopper, Stearman, Storch, IL-2, I-15, Hype); the others need slightly more than half throttle at the slowest attached trim (3D models whose real thrust exceeds the cap, and the GTX turbine, whose half-throttle speed lies beyond the search's 2.5 × start bound).
