# Sources and parameter provenance

Access date for external sources: **2026-11-15**. Publication/revision dates below are distinct from access dates. This is a reference ledger, not a dataset redistribution or a hardware qualification report.

## Evidence rules

OpenRC v2 accepts `manual`, `measured`, `borrowed`, `estimated` and `derived`. A manufacturer value is `manual` for that exact installation; using it on AERIS is normally `borrowed` or `estimated`. A calculation remains `derived` from its named assumptions. Simulated manufacturer prop data are predictions, not `measured`. Prior user-design dimensions are design inputs; without metrology, do not label them measured. Preserve uncertainty and applicability in the source/report.

## Airframe, engine, propeller and controls

| ID | Primary source | What it supports | Limits |
| --- | --- | --- | --- |
| S01 | [Extreme Flight 104 Extra NG V3 product](https://extremeflightrc.com/products/ef-104-extra-ng-v3-red-white-scale-ng-scheme) | RC-specific design and provenance of the linked specification sheet | V3 wing-position changes make version identity important; not a full-scale Extra aerodynamic database |
| S02 | [EF 104 Extra NG specification sheet](https://extremeflightrc.com/cdn/shop/files/DATASHEET_104_Extra_NG_3cb0eca5-c117-4b60-9b65-5979bd3358b4.pdf?v=7463632038284693398), one page, revision unspecified | Dimensions, CG datum, throws/expo, incidence/thrust angles and suggested equipment | Linked from V3, but the sheet itself lacks a clear version; mass fuel state is not established |
| S03 | [Pilot-RC Extra NG V2 103](https://pilot-rc.com/extra-ng-103-2-63m/) | Independent 100–120 cc class comparator | Listed inch/metric dimensions are rounded inconsistently; CG is model-specific |
| S04 | [Desert Aircraft DA-120](https://www.desertaircraft.com/products/da-120) | 121 cc, 2.25 kg, 1,300–6,900 RPM, recommended prop sizes and claimed 11.7 hp | No complete torque/RPM/throttle map; exhaust and installation matter |
| S05 | [DA120 owner's manual](https://www.desertaircraft.com.au/shop/files/attachments/17517/DA120_MANUAL_1-8-2018.pdf), document marked 7/17 | Two-stroke operation, pumped carburetor, clunk/vent installation, idle/transition and setup dependencies | Historical hardware revision; not a present ignition-voltage specification or target endurance measurement |
| S06 | [Mejzlik 28×10 2B GAS EVO LF, PN 228108](https://www.mejzlik.eu/files/28x10-2b-gas-evo-lf-datasheet.pdf), rev. 3.0, 2025-12-18 | Prop dimensions/mass, estimated inertia, RPM limit and Ct/Cp versus advance ratio | Performance explicitly simulated at 5,000 RPM; no reverse-inflow or large-crossflow map |
| S07 | [Mejzlik propeller data index](https://www.mejzlik.eu/propeller-data) | Available prop-specific datasets | Individual files mix measurement and simulation; classify each one |
| S08 | [UIUC Propeller Database](https://m-selig.ae.illinois.edu/props/propDB.html) | Experimental methods and identified model/UAV prop measurements | Check diameter, blade type, Reynolds number and flow regime; no arbitrary small-electric-prop transfer |
| S09 | [APC performance data](https://www.apcprop.com/technical-information/performance-data/) | Public computational propeller performance methodology | Predicted data; neither matching AERIS measurements nor a reason to change its prop |
| S10 | [Team Savox SB-2290SG](https://www.teamsavox.com/product/sb-2290sg/) | Published voltage-dependent speed/torque; 0.13 s/60° at 7.4 V and 0.11 at 8.4 V | Servo-shaft catalog motion, not loaded AERIS surface response; torque table notation is inconsistent with kg·cm prose |
| S11 | [EdgeTX v2.11 inputs](https://manual.edgetx.org/v2.11/bw-radios/model-select/inputs-mixes-and-outputs/inputs), [mixes](https://manual.edgetx.org/v2.11/color-radios/model-settings/inputs-mixes-and-outputs/mixes) | Inputs, weights/curves, mixer and channel semantics | Firmware-specific documentation; not USB latency data or a universal expo-percentage conversion |
| S12 | [Walbro US6394424B2 diaphragm carburetor disclosure](https://patents.google.com/patent/US6394424B2/en) | Orientation-independent diaphragm-metering principle | Not evidence of unlimited inverted/negative-g fuel supply in a specific tank |

## Flight dynamics and validation methods

| ID | Primary source | Application / boundary |
| --- | --- | --- |
| S13 | Selig, [Real-Time Flight Simulation of Highly Maneuverable Unmanned Aerial Vehicles](https://m-selig.ae.illinois.edu/pubs/Selig-2014-JofAC-FlightSim-FINAL.pdf), *Journal of Aircraft* 51(6), 2014, DOI 10.2514/1.C032370 | Directly relevant component/strip method for RC aerobatics. Quasi-steady; explicitly excludes dynamic stall. Example aircraft and tuned coefficients do not validate AERIS. |
| S14 | Selig, [Modeling Propeller Aerodynamics and Slipstream Effects on Small UAVs in Realtime](https://m-selig.ae.illinois.edu/pubs/Selig-2010-AIAA-2010-7638-PropAeroSim.pdf), AIAA 2010-7938, 2010 | Nonaxial prop loads, slipstream/swirl and transient modeling. Filename contains 7638; retain the publication identity printed in the paper. No target installation calibration. |
| S15 | JSBSim [frames of reference](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/) and [actuator source documentation](https://jsbsim-team.github.io/jsbsim/FGActuator_8h_source.html) | Cross-check frame distinctions and separate lag/rate-limit/deadband concepts. OpenRC's contract remains authoritative; no solver replacement proposed. |
| S16 | Murphy, Klein and Frink, [Unsteady Aerodynamic Modeling in Roll for the NASA Generic Transport Model](https://ntrs.nasa.gov/citations/20120014566), 2012 | Methodological reason to identify unsteady roll effects from dynamic data. Transport coefficients are not RC coefficients. |
| S17 | Simmons, [Advances in Aero-Propulsive Modeling for Fixed-Wing and eVTOL Aircraft Using Experimental Data](https://ntrs.nasa.gov/citations/20230004001), 2023 | Experimental aero-propulsive identification and independent validation; not target parameters. |
| S18 | Grauer and Boucher, [Aircraft System Identification from Multisine Inputs and Frequency Responses](https://ntrs.nasa.gov/citations/20200002776), 2020 | Input design, parameter fitting and uncertainty; linear methods have a bounded attached-flow use here. |

## Reference values and transfer limits

| Quantity | AERIS design input | EF linked 104 NG sheet | Pilot-RC 103 NG V2 |
| --- | --- | --- | --- |
| Span | 2.64 m | 104 in = 2.6416 m | Listed 2.630 m |
| Length | 2.60 m | 101.5 in = 2.5781 m | Listed 2.580 m, with spinner |
| Wing area | 1.2408 m² | 1900 in² = 1.225804 m² | 1.189 m² |
| Aircraft mass | Unknown | 27–29 lb = 12.247–13.154 kg | Listed 12.6 kg |
| CG aft of root LE | Unknown | 187–212 mm | 225 mm |

The mass descriptions do not establish a common fuel state. Do not add an engine again to an all-up mass, borrow a donor's millimetre CG, or substitute `S/b` for MAC in a stability calculation. AERIS's exact planform, battery placement, engine/exhaust, fuel and control installation remain its own definition.

## Missing evidence

No matching AERIS measurements were found for inertia, CG, torque map, installed static/dynamic thrust, fuel flow, loaded control response, wing/tail polars, propwash velocity, spin recovery or pilot-rated handling. The plan can use documented surrogates, but those unknowns remain open. Manufacturer specifications and papers do not close the measurement or pilot gates.

## Reuse of existing project research

Use the [RC validation collection](../flight-dynamics/rc-validation-library-2026-10-18/README.md), [Extra realism evidence](../extra-300-realism/README.md), [fuel standard](../../FUEL-SYSTEM.md), [servo plan](../../plans/servo-dynamics.md) and [historical 3D proposal disposition](../flight-mechanics-stall-hover-knife-edge-2026-10-18.md#integration-disposition-2026-10-26). Their existence does not mean every proposed mechanism is in the pinned runtime. The source audit records the distinction.
