# EL1a — electric motor and averaged ESC sources

2026-10-10 · **Status:** primary-source research and independent numerical oracles for the implemented EL1a motor-source kernel; loader, trim, coupled-session, aircraft and physical validation remain later steps. **Scope:** a three-constant motor, one-way averaged ESC, fixed prescribed bus voltage, and the existing coupled shaft state. Read with [ROADMAP M4b](../../../../ROADMAP.md), [propulsion knowledge base 05](../../roadmap-investigations/05-propulsion-engines-motors.md), [coupled shaft plan](../../../PROPULSION-CORE-PLAN.md), [electric integration plan](../../../ELECTRIC-PROPULSION-PLAN.md), and the [Timber B reference and measurement gaps](timber-reference.md).

## First-slice recommendation

The implemented EL1a kernel is a stateless motor/ESC torque and power source, not yet an aircraft or shaft integration. Use it as a stage-local source for the **existing continuous relative shaft-speed state**: prescribe one fixed bus voltage, pass the effective duty after input sampling, and reuse the propeller torque/load path shared with other shaft-driven aircraft. The source law is algebraic and does not need another motor-RPM lag state. This preserves EL1's bounded sequence: loader and normalized model, operating-point/trim support, coupled session and replay, then synthetic aircraft integration. EL1a does not include LiPo state, voltage sag/cutoff, ESC startup schedules, temperature or broad `powerplants[]` generalization.

For a brushed/brushless permanent-magnet **DC-equivalent** motor, define `Kv_rpm` in rpm/V, `R` in Ω, and `I0` in A. Use explicit SI conversion:

```text
Kv = Kv_rpm · 2π/60                [rad s⁻¹ V⁻¹]
kt = 1/Kv = 60/(2π Kv_rpm)         [N m A⁻¹]
ω = rpm · 2π/60                     [rad s⁻¹]
E = ω/Kv = rpm/Kv_rpm               [V, back-EMF]
Vcmd = d · Vbus                     [V, averaged ESC command]
Im = max((Vcmd − E)/R, 0)           [A, one-way motor-port current]
Ibatt = d · Im                      [A, ideal ESC bus current]
Qmotor = kt · (Im − I0)             [N m, source torque while ω > 0]
Pshaft = ω · Qmotor                 [W]
Pbus = Vbus · Ibatt                 [W]
Pcopper = Im² · R                   [W]
Prot = E · I0                       [W, constant-I0 rotational loss]
```

The three-constant relationships come from [Drela's first-order motor note](https://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf), Eqs. 1–12. Drela defines `I0` as the zero-torque current, assumes constant resistance, derives `I=(v−ω/Kv)/R`, and shows `KQ=KV` only when `KV` is in rad/s/V and `KQ` in A/N·m. The familiar nameplate value in rpm/V therefore cannot be used directly as `kt`. QPROP's guide explicitly describes this type-1 approximation as a permanent-magnet brushed **or brushless** DC motor; it is a scalar average model, not a model of phase commutation or a claim about every ESC.

Treat the ESC relation as a derived **ideal averaged-port** assumption. `Vcmd=d·Vbus` and `Ibatt=d·Im` conserve power because `Vbus·Ibatt=Vcmd·Im` when the converter is ideal and the variables are defined at compatible average DC-equivalent ports. `Im` here is not a raw phase-wire RMS current. A brushless ESC can have different phase-current, bus-current, recirculation, and modulation behavior; do not use this relation as a universal commercial ESC law. The model deliberately clamps negative current to zero: it has no electrical regeneration. It also omits controller quiescent draw, switching loss, ESC/motor current limiting and phase timing.

At positive shaft speed, `Qmotor` can be negative when `0 ≤ Im < I0`: it is the retained lumped drag represented by `I0`, even though the electrical current is nonnegative. At exactly zero speed, limiting that loss to the available applied torque is an explicit **Coulomb-loss extension**, not Drela's measured low-speed, breakaway or cogging law; it must never start reverse rotation. Refuse negative-RPM input. Near a stop, constant loss can create negative intermediate RK states, so full-session use still needs event handling or a declared, convergence-tested low-speed regularization; do not hide this with unconditional RK-stage clamping. At zero duty or `enabled=false`, assume an open-circuit/free-coast motor port (`Im=Ibatt=0`) while retaining `−kt·I0` drag during rotation. This is not an ESC brake model. Report commanded `Vcmd` separately from actual terminal voltage: `Vterm=E+Im·R` in this equivalent motor circuit, so when open-circuit (`Im=0`) `Vterm=E` even if `Vcmd=0` or the current clamp is active.

With the above sign convention, the positive-speed power identity is `Pbus=Pshaft+Pcopper+Prot` for the ideal converter. Preserve that accounting in the kernel. Do not subtract the same motor loss again as a generic shaft friction term unless the data distinguish motor loss from bearing/drive-train loss. Keep shaft inertias in the G2 convention: one axial rotor inertia includes the components that spin together, while the aircraft locked inertia must not silently double-count them. [G2a's derivation](../G2a-RK4/sources.md) documents the body/rotor momentum boundary.

## Hand-calculation acceptance fixture

Use a synthetic, explicitly labelled oracle before inserting any aircraft estimates. For `Kv_rpm=600 rpm/V`, `R=0.1 Ω`, `I0=2 A`, `Vbus=12 V`, `d=0.5`, and `rpm=3000`:

| Quantity | Expected |
| --- | ---: |
| `Vcmd`, `E` | 6 V, 5 V |
| `Im`, `Ibatt` | 10 A, 5 A |
| `kt`, `Qmotor` | 0.0159154943 N·m/A, 0.1273239545 N·m |
| `Pbus`, `Pshaft` | 60 W, 40 W |
| `Pcopper`, `Prot` | 10 W, 10 W |

These values satisfy the DC motor law and the ideal ESC power balance exactly before floating-point rounding. Require algebraic outputs and power residual within `1e-10` relative for nonzero reference quantities. Also check the analytic zero-torque speed `rpm0=Kv_rpm·(d·Vbus−I0·R)` (7,080 rpm for the fixture at full duty) and zero-speed current `Im=d·Vbus/R` when the current limit is absent. At `d=0`, verify zero battery current and no regen; at `rpm=0`, verify no negative shaft acceleration. State the current-unlimited stall result as a mathematical limit, not a safe operating value.

For shaft verification, first disable prop load and use constant `d,Vbus`. In the positive-current region the motor/rotor system has the exact first-order solution

```text
Jrot · ωdot = kt · ((d·Vbus − ω/Kv)/R − I0)
ω∞ = Kv · (d·Vbus − I0·R)
τmotor = Jrot · R · Kv²
ω(t) = ω∞ + (ω(0) − ω∞) exp(−t/τmotor)
```

Compare the RK-integrated RPM with this solution and refine the step until the observed smooth-region error ratio approaches 16 under halving. Then exercise the **coupled** aircraft/shaft path with stage-local throttle, air-relative prop inflow and density; table-knot crossings and the existing stopped-prop cutoff can reduce global order, so report their observed order separately. A failed/nonexistent steady balance must make trim refuse the start rather than silently use a bracket endpoint. Measure the full-aircraft cost against the ROADMAP's 0.5 ms per 240 Hz tick target on the owner's slowest machine; do not infer cost from the small scalar kernel alone.

The existing ROADMAP EL1 acceptance remains the scope authority: operating point against hand calculation, plus an electric variant that trims and passes its handling test. Exact synthetic checks verify implementation, not physical accuracy. EL5 still requires independent static testing, with current and thrust within ±10%; that result validates one operating point, not the whole flight model.

## Propeller, battery, and ESC boundaries

The existing common shaft load is

```text
n = rpm/60                             [rev/s]
J = Va/(n·D)                           [dimensionless]
Qprop = Cp(J) · ρ · n² · D⁵/(2π)      [N m, positive when prop absorbs power]
T = Ct(J) · ρ · n² · D⁴              [N]
```

`D` is metres, `Va` is air-relative axial speed in m/s, and the coefficient tables must match the selected propeller and cover the operating range. The [UIUC propeller database](https://m-selig.ae.illinois.edu/props/propDB.html) provides wind-tunnel measurements for model-aircraft/small-UAV propellers and cites its standard coefficient definitions; its [APC electric fixed-blade study](https://m-selig.ae.illinois.edu/pubs/DantskerCaccamoDetersSelig-2022-AIAA-Paper-2022-4020-APCEPropTestsVol4.pdf) records thrust and torque testing. Neither is automatically the Timber's prop map. QPROP is a useful independent offline matching/analysis tool, not a runtime dependency; Mark Drela's [QPROP page](https://web.mit.edu/drela/Public/web/qprop/) states that QPROP is GPL-licensed. QPROP theory treats windmills and signed torque, but a positive-current motor clamp does not by itself model generator loading.

An EL1 ideal battery is simply a fixed, declared `Vbus`; it has no SOC, sag, capacity, temperature or LVC. Do not call a nominal pack voltage a measured loaded voltage. EL2a can add `OCV(SOC)`, pack resistance `Rpack`, and discharge-positive `Ibus`. With the ideal averaged ESC and positive motor current, solve battery sag and motor current together:

```text
Im = max((d·OCV − E)/(Rm + d²·Rpack), 0)  [A]
Ibus = d·Im                                [A, positive for discharge]
Vbus = OCV − Rpack·Ibus                    [V]
SOCdot = −Ibus/(3600·Capacity_Ah)           [s⁻¹, SOC as a fraction]
```

Here `Rm` is the motor's equivalent resistance in Ω. The `d²` term follows from both ESC voltage conversion and bus-current conversion; replacing it with `d` or using motor current directly for SOC is wrong. The equation applies to the declared no-regeneration branch. EL2b can add a pack polarization state, e.g. `Vpdot=Ibus/C1−Vp/(R1·C1)` and replace `OCV` above with `OCV−Vp`, after identifying parameters for the selected pack and conditions. The [fixed-wing Li-Po Thevenin study by Suti, Di Rito, and Mattei](https://doi.org/10.3390/en15239249) identified a pack model from HPPC measurements and reports sub-1% terminal-voltage error above 10% SOC for its tested 6S pack; it is evidence for pack-specific identification, not reusable coefficients for a different RC battery. [Di Nisio et al.'s UAV battery tests](https://doi.org/10.3390/s23156937) similarly validate variable-load discharge prediction only after characterizing their selected pack. Do not copy either paper's fitted values into Timber without matching its pack and conditions.

Keep LVC, startup, brake and telemetry settings outside EL1. The B-revision Timber manual says LVC reduces/removes motor power to preserve flight-control reserve, but it does not publish a complete motor map or all installed ESC settings. The general [Spektrum Avian ESC manual](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/Avian-Manual-EN.pdf) shows that brake, soft/hard cutoff, start-up and freewheel are configurable family behaviors; its exact settings must not be assigned to the Timber's `SPMXAE70E` without a matching manual/configuration. Likewise, the [Hobbywing Skywalker V2 manual](https://www.hobbywing.com/en/uploads/file/20250930/64b726be7a56c9f415385f77683cdc46.pdf) is evidence for that ESC family only, not Timber's Avian ESC. A brake requires an explicit dissipative negative shaft-torque law. Windmilling is an aerodynamic/mechanical condition: a propeller can drive the shaft against the retained motor loss while the one-way motor port remains open and bus current stays zero. It requires valid signed windmill propeller data and the stopped-prop treatment tracked by G1d. Generator loading or battery regeneration additionally requires a bidirectional electrical path; low-voltage cutoff requires battery voltage/SOC and an ESC mode. These are later EL2/EL3/G1d work, not EL1.

## Timber as a configuration example

For the current B-suffix Turbo Timber Evolution, Horizon publishes a configuration of 800 rpm/V, 14 poles, an Avian 70 A Smart Lite 3S–6S ESC, a 4S 14.8 V / 3200 mAh / 30C recommended Li-Po, and a three-blade 11 × 7.3 propeller. The [B-revision manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250B-Manual_EN.pdf) also gives 1.860 kg without battery and 2.190 kg with the specified 4S pack. Treat these as **manufacturer configuration/specification (`manual`)**, not measured operating points. The pole count is useful for matching telemetry conventions; it does not alter the nameplate mechanical rpm/V conversion.

Horizon does not publish the SPM-1012's equivalent `R`, `I0`, or rotor inertia, nor the EFL5962's `Ct/Cp` curve. Any provisional values for those fields are **estimates** with a cited method/range, not motor manual values. An independent bench result becomes **measured** only when it names the exact motor, ESC, propeller, battery, measurement plane, calibration, temperature, voltage/SOC, and raw observations. The [Timber source comparison and measurement card](timber-reference.md) records the hardware revision discrepancy and required bench/flight evidence; do not duplicate legacy specs or silently use an APC two-blade table for this three-blade prop.

Before attaching this motor to an outrunner model, declare the BLDC-to-DC-equivalent parameter convention. Drela's measurement note is written for DC motor terminals. For a three-wire brushless motor, phase-to-phase resistance and phase current are not automatically the model's `R` and `Im`; fit or convert them under one stated winding/ESC convention. Do not mix battery-side ammeter current with the motor-port current in the torque equation. A useful measurement set is synchronized bus V/I, throttle/duty, RPM and thrust/torque over several steady points plus throttle steps, with the exact ESC settings, pack state and temperature. Propeller `Ct/Cp` needs the selected prop's own advancing-flow data to validate nonzero-`J` operation; dimensions and pitch alone do not supply those coefficients.

## Primary sources

- Drela, Mark. [First-Order DC Electric Motor Model](https://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf), MIT Aero & Astro, February 2007. Motor equations, loss-current meaning, parameter measurement and SI/nameplate Kv distinction.
- Drela, Mark. [Measurement of Brushed DC Electric Motor Constants](https://web.mit.edu/drela/Public/web/qprop/motor_measure.pdf). Measurement setup and notes on averaging resistance over rotor position and measuring `I0` near expected RPM. Brushless equivalent-port conversion still requires a declared convention.
- Drela, Mark. [QPROP User Guide](https://web.mit.edu/drela/Public/web/qprop/qprop_doc.txt), Version 1.21, 2007; and [QPROP/QMIL distribution page](https://web.mit.edu/drela/Public/web/qprop/). Describes the type-1 three-constant motor, propeller/motor operating-point tool, windmill capability and GPL release.
- Brandt, Deters, Ananda, Dantsker, and Selig. [UIUC Propeller Database](https://m-selig.ae.illinois.edu/props/propDB.html); Dantsker et al. [Performance Testing of APC Electric Fixed-Blade UAV Propellers](https://m-selig.ae.illinois.edu/pubs/DantskerCaccamoDetersSelig-2022-AIAA-Paper-2022-4020-APCEPropTestsVol4.pdf), AIAA 2022-4020. Wind-tunnel database and measured propeller test method.
- Suti, Di Rito, and Mattei. [Thevenin-based hysteretic models for Li-Po packs in fixed-wing UAVs](https://doi.org/10.3390/en15239249), *Energies*, 2022. Pack-specific HPPC identification and validation evidence for a 6S UAV battery.
- Di Nisio et al. [Battery Testing and Discharge Model Validation for Electric UAVs](https://doi.org/10.3390/s23156937), *Sensors*, 2023. Battery test method and pack-characterized variable-load discharge prediction.
- Horizon Hobby. [Turbo Timber Evolution B-revision manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250B-Manual_EN.pdf), updated 10/23; current BNF listing [EFL105250B](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html). Model configuration, loadout, published masses and LVC guidance.
- Spektrum. [Avian Smart ESC family manual](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/Avian-Manual-EN.pdf); Hobbywing. [Skywalker V2 manual](https://www.hobbywing.com/en/uploads/file/20250930/64b726be7a56c9f415385f77683cdc46.pdf). Examples of configurable ESC behavior; neither substitutes for the exact Timber ESC configuration.
