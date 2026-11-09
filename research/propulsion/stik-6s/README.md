# Electric Stik installation candidate

EL1e-STIK-03a, 2026-11-08. The generated aircraft is an experimental numerical candidate. This report does not establish physical fit, pilot handling, measured battery behavior or hardware safety. The source is [installation.json](installation.json); generate with `python -I research/propulsion/stik-6s/build_aircraft.py`, and check with `--check`. `--draft-dir` writes both candidates outside `app/` for admission checks. The battery owner is `research/battery/bat-05/build_batteries.py`; the unpriced economics entry is maintained by `build_costing_entry.py` and checked with `--check`.

## Selection and provenance

The selected propeller is [APC LP12080E 12x8E Thin Electric](https://www.apcprop.com/product/12x8e/), replacing the plan's initial 13x8E and 13x6.5E candidates. The 12x8E manufacturer's sample point on the [Scorpion SII-4020-540 chart](https://www.scorpionsystem.com/files/i2,653_data_chart.htm) is 22.2 V, 49.92 A, 10,334 rpm and 3.265 kgf. Against this inventory's 2.600082 kg it corresponds to 426 W/kg and 1.256 thrust/weight. These are sample-point screening calculations, not measurements of the modeled airframe.

The model uses selected `J, Ct, Cp` rows at 10,000 rpm from [APC's 12x8E data](https://www.apcprop.com/files/PER3_12x8E.dat), version v2022-0915, dated 2022-09-22. APC describes the tables as computational predictions, not wind-tunnel measurements. The selected rows and source URL are retained in `installation.json`. Direct raw-file retrieval returned HTTP 403 here; the table was read through a web reader, so no raw upstream-file hash is asserted. In-flight `Ct/Cp` are independent of the electrical fit, but are not independent physical validation of this installation. A single 10,000 rpm map neglects RPM/Reynolds dependence.

The named 6S 4000 mAh Gens ace GEA406S60X9GT pack has the manufacturer's approximate 606 g mass and 162 × 45 × 37 mm box. Its fitted cell curve, resistance scale, lead resistance, heat transfer and weak-cell assumptions remain estimates; they do not characterize the Gens ace product. The Scorpion Tribunus III 06-80A hardware reference is 70 g without connectors; separate estimated wiring and connectors are in the inventory. Its firmware and BEC setting are unknown. The simulator's generic estimated 3.2 V/cell soft cutoff, timing and throttle-reset behavior are not claims about that ESC.

## Electrical regression and checks

Catalog motor values are 540 rpm/V, 0.020 ohm and 1.22 A at 10 V; the same chart lists a sample no-load Kv of 555 rpm/V, 0.021 ohm and 1.79 A at 20 V. The chart does not specify the phase-to-DC resistance convention or its voltage measurement point. Directly treating 0.021 ohm as the simulator's equivalent would predict 11,751 rpm and 48.9 A at nominal voltage with the APC map; the measured sample gives 10,334 rpm and 49.92 A. Do not call that a matched model.

Instead, the candidate conditionally fits `V = rpm/Kv + I*R` to the chart's 12x8E points at 18.5 V/35.85 A/8,938 rpm and 22.2 V/49.92 A/10,334 rpm. This yields **593.114 rpm/V and 0.0956875 ohm**, used as estimated motor-equivalent values, with 1.79 A held constant. This fit assumes the chart's input voltage is the ideal motor command. Unidentified wiring and ESC voltage drops may bias it; they are not separately identified, and the fitted resistance is not a measured winding resistance. The runtime schema calls for a motor-winding equivalent and excludes separately modeled wiring/ESC losses, so this is a conditional surrogate, not an identified motor. On held-out chart points, the electrical relation predicts 9,680 versus 9,953 rpm for 13x8E and 9,877 versus 10,065 rpm for 13x6.5E; these are cross-propeller electrical checks, not independent validation of propeller thrust or a hardware characterization.

Combining that fit with the independent APC 12x8E prediction at sea-level density gives the following steady, full-duty static points. The 22.2 V prediction is 10,678 rpm, 43.86 A, 973.7 W and 36.83 N: relative to the chart point, rpm is 3.3% high, current 12.1% low and thrust 15.0% high. Those discrepancies remain open.

| Ideal bus voltage | Static rpm | Motor current | Electrical input | Static thrust |
| --- | ---: | ---: | ---: | ---: |
| 15.0 V | 7,589 | 23.04 A | 346 W | 18.61 N |
| 16.5 V | 8,257 | 26.95 A | 445 W | 22.03 N |
| 18.5 V | 9,127 | 32.53 A | 602 W | 26.91 N |
| 20.0 V | 9,764 | 36.97 A | 739 W | 30.80 N |
| 22.2 V | 10,678 | 43.86 A | 974 W | 36.83 N |
| 24.0 V | 11,408 | 49.81 A | 1,195 W | 42.04 N |
| 25.2 V | 11,886 | 53.92 A | 1,359 W | 45.64 N |

These are equilibrium values, not transient current limits. At 25.2 V static the conditional model is below Scorpion's 68 A recommended screening level (80% of 85 A), its 1,850 W rating, the ESC's 80 A label, and [APC's suggested Thin Electric limit](https://www.apcprop.com/technical-information/rpm-limits/) of 150,000 / 12 = 12,500 rpm. Sampled axial speeds 0, 5, …, 30 m/s at 25.2 V remain below 12,500 rpm in this model. A 40 m/s numerical point is about 12,511 rpm, beyond that suggestion: there is no unlimited-speed envelope and the simulator has no overspeed protection. This speed screen is not proof of safe hardware operation or a defined taxi/takeoff/landing envelope.

The 16.5 V row corresponds to six times the borrowed cell-template 2.75 V data floor; 15 V is a mathematical continuation only. Neither row implies that the estimated pack remains connected at that voltage: its generic LVC and exhaustion events are dynamic and depend on load and history.

A separate point-based extrapolation using each chart's 22.2 V speed/current, sample Kv 555 and a quadratic static torque approximation estimates at 25.2 V: 13x8E 75.6 A/1,905 W; 13x6.5E 71.4 A/1,800 W; 12x8E 61.7 A/1,555 W. The first two exceed the 68 A screening target. This extrapolation is not a measured full-charge test; the conditional model predicts different 13-inch results. That disagreement, resistance convention, thermal state and propeller/ESC tolerances require measured follow-up.

The finite pack model at rest, 288.15 K, zero rpm and full duty produced 194.85 A motor current, 24.93 V open circuit and 18.65 V terminal voltage. This is an idealized severe startup transient from estimated electrical parameters, beyond both hardware current labels; neither the motor nor the ideal ESC law has a current limiter, thermal protection or startup ramp. Do not interpret the steady screening table as protection or verified startup behavior. The software soft cutoff responds to modeled low pack voltage and is not motor-current or overspeed protection.

## Inventory and geometry

The unchanged donor's 247.7 g virtual balance fixture, glow engine/muffler, fuel/tank, engine mount and receiver battery are excluded. The unused throttle servo is removed from the three equal estimated fuselage servos, retaining elevator and rudder servos. The motor, propeller, mount, adapter, ESC, wiring, pack and restraint are inventoried; the selected pack's 0.606 kg matches its BAT record exactly. Nothing is added solely to reach the 3.0–3.4 kg planning aim.

The resulting estimated mass is **2.600082 kg**; CG is `[0.1209, 0, 0.0046845] m` in the LE frame. Aligned-box inventory inertia is approximately `[0.112806, 0.179426, 0.277193] kg·m²` on its diagonal, with the full tensor derived by the runtime. Propeller plus estimated rotor polar inertia is `0.000242794 kg·m²`. The modeled pack and tray are centered 0.16448 m aft of the leading edge to obtain the donor plan's longitudinal CG; real bay volume, access, restraint, wiring and cooling are unverified. Four glow-cylinder hull probes are replaced by estimated motor-box extrema; the closed hull category still uses its generic `engine` label for this powerplant region. The spinning disc uses the 0.3048 m diameter and the unchanged fixed donor hub. At level rigid geometry, wheel-bottom height versus the 0.1524 m prop radius gives roughly 0.098 m minimum clearance before suspension, pitch and terrain. The declared 0.12 m maximum gear compression alone can remove that margin, so the normal operational clearance envelope is not yet qualified.

## Software evidence and identity

The checked Godot test admitted both v2 resources and passed 32 checks, including corruption/mass mismatch rejection, ideal/pack physical consistency, sampled steady full-charge RPM, pack sag, generic LVC response and recovery, ideal/pack coupled session setup and a one-second exact checkpoint replay. A low-SOC flight test with an estimated 8% initial charge reached the generic soft cutoff at tick 3,817 (15.90 s), then reset after throttle release; this is software behavior, not a Tribunus firmware measurement.

The electric aircraft shares the exact donor wheel-profile key through a closed default-registry alias; its aircraft ID remains distinct. The global wheel registry stays byte-identical, so existing basic Workshop dependency pins remain valid. A missing aliased donor is refused, and explicit profile selections/custom fixture paths retain their semantics. The loaded pack's retained gear requests two contact pieces at the runway, while its finite-source event policy owns the whole outer tick. The session adapter composes the existing battery step over those pieces and samples the ESC supervisor once at the outer endpoint; it does not change the generic kernel's policy guard. The new ground test confirms 80.47 mm static prop clearance and 67.55 mm minimum clearance in its two-second full-duty roll, plus reset, controlled strike, depleted-start refusal, policy-ownership guard and exact ground replay. These are bounded numerical cases, not full landing or hardware qualification. A separate composition test checks event chronology, late-clock rounding, failure atomicity and one-piece byte equivalence. The app tests are `test_stik_electric_6s*.gd` and `test_electric_contact_step.gd`.

BAT `--check`, installation `--check`, and costing-entry `--check` pass; BAT local reference datasets were absent, so its optional upstream file-hash comparison was skipped. The [integration evidence](../../../docs/research/propulsion/ugly-stik-implementation-2026-11-08.md) records catalog/model/Workshop admission, both-mode maneuver cards, exported resources and scoped native checks separately. These checks do not establish release or physical admission.

| Input/output | SHA-256 |
| --- | --- |
| Basic donor | `5635e7f7b2a44bdfc7db5ad2646c74654af42944133bc39a91a0908bac887b66` |
| Installation source | `c6ead24fc3832df793e6ca2fad050bf4efd8f64d655d49de6ef0f49e8de9b4b1` |
| BAT pack | `bda884c9bd3d82a0535bef32517cf82773c5aba9ee38178012659f9086e981d1` |
| Ideal aircraft | `830137e2daaf43295c404ad0af6676ac44a8fb0102c2d2b81c2c0b4a395337e6` |
| Pack aircraft | `fbbfd74512b8e3141adc530296687721c5ca7e3d94a38c384fbaf10f03c2c73e` |
