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

## Follow-up sources: measured mechanisms, handling and reusable data

The [2026-11-15 follow-up](evidence-update-2026-11-15.md) records the interpretation and development consequences. Some flight papers already appear in the retained RC collection; this pass adds a closer audit of their instruments, reconstructed quantities and transfer limits. Public availability of a paper is not permission to redistribute its files.

| ID | Primary source / locator | Supported use and limit |
| --- | --- | --- |
| S19 | Ragheb, Dantsker and Selig, [Stall/Spin Flight Testing with a Subscale Aerobatic Aircraft](https://aerosyslab.com/papers/conferences/RaghebSelig-2013-AIAA-2013-2806-StallSpin.pdf), AIAA 2013-2806, §§II–IV | Electric Extra 260 spin/configuration evidence; pitot incidence and wind-sensitive reconstruction limits. Not AERIS spin or recovery data. |
| S20 | Dantsker and Selig, [High Angle of Attack Flight of a Subscale Aerobatic Aircraft](https://aerosyslab.com/papers/conferences/DantskerSelig-2015-AIAA-2015-2568-HighAngleFlight.pdf), AIAA 2015-2568, §§II–IV | 2.6 m electric Sukhoi, synchronous motion/RPM/actual surfaces; illustrated descending harrier is unpowered. Inferred coefficients are not directly measured component loads. |
| S21 | Johnson and Lind, [Characterizing Wing Rock with Variations in Size and Configuration of Vertical Tail](https://web.mae.ufl.edu/ricklind/rick_pubs/j_air10.pdf), *Journal of Aircraft* 47(2), 2010, DOI 10.2514/1.45719 | Paired upright/inverted tests on a small aerobat; locally narrowband wing rock and configuration effects. Neither a universal cause nor transferable frequency. |
| S22 | HFE, [DA120 EFI data sheet](https://hfe.aero/wp-content/uploads/2025/11/DA120-Data-Sheet.pdf), HFEDCN0810 Rev A, 2025 file, pp. 1–4 | EFI/stock-muffler steady dyno and BSFC comparison only. Pin version; operating-range/peak-power inconsistency and predicted prop rows remain explicit. |
| S23 | Steffensen, Ginnell and Holzapfel, [Practical System Identification and Incremental Control Design for a Subscale Fixed-Wing Aircraft](https://www.mdpi.com/2076-0825/13/4/130), *Actuators* 13(4), 2024, §3 | Measured ground/flight surface response and actuator identification. Different servos/aircraft; no AERIS constants. |
| S24 | Zarev and Green, [Experimental investigation of the effect of yaw angle on the inflow of a two-bladed propeller](https://eprints.gla.ac.uk/211776/), 2020; [Glasgow dataset, DOI 10.5525/gla.researchdata.969](https://researchdata.gla.ac.uk/969/) | Oblique **upstream** inflow benchmark, J=0.36–1.54 and yaw 0–20°. Data/README CC BY 4.0; accepted manuscript CC BY-NC-ND. README inspected, archive not inspected. |
| S25 | Cooper and Harper, [The Use of Pilot Rating in the Evaluation of Aircraft Handling Qualities](https://ntrs.nasa.gov/api/citations/19690013177/downloads/19690013177.pdf), NASA TN D-5153, 1969, discussion and Appendix B | Task, performance, compensation and interface distinctions; methodology, not RC certification or automatic rating thresholds. |
| S26 | Crane, [The effects of time delay in man-machine control systems](https://ntrs.nasa.gov/citations/19850009674), 1984 | Delay effects depend on system/task; no transferable consumer-radio or AERIS latency limit. |
| S27 | NIST TN 1297, [Appendix A: Law of Propagation of Uncertainty](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty), 1994 edition | First-order sensitivity/covariance and measurement-process uncertainty. Does not convert missing uncertainty into zero or define this campaign's errors. |
| S28 | MIT Unified Engineering, [Performance of Propellers](https://web.mit.edu/16.unified/www/SPRING/thermodynamics/notes/node86.html), §§11.7.3–11.7.4 | Ideal actuator-disk assumptions and coefficient definitions used in reference arithmetic; not installed wake or real shaft-loss measurements. |
| S29 | Bock, [Airscrew Gyroscopic Moments](https://ntrs.nasa.gov/citations/20050019386), NACA TM-1099, 1946 | Mean versus instantaneous two-blade gyroscopic moments; no installed DA120 inertia or vibration calibration. |
| S30 | ExpressLRS, [Switch Configs: Channel Update Rate versus Packet Rate](https://www.expresslrs.org/software/switch-config/#channel-update-rate-versus-packet-rate), accessed 2026-11-15 | RF mode/channel scheduling distinction; does not characterize a USB joystick route or physical-to-photon latency. |
| S31 | Dias, Violato and Martins, [Dynamic Model of a Two-Stroke Glow Engine from Experimental Data](https://www.abcm.org.br/anais/cobem/2011/PDF/096102.pdf), COBEM 2011, §§2–7 | Separate throttle-servo identification; remaining prop-loaded O.S. .61/13×4 dynamics are not a gasoline DA120 map or lag constant. |
| S32 | Fouda, [Experimental Investigations of Airplane Stability and Control Characteristics in Stall](https://escholarship.org/uc/item/1k88f97s), UC Irvine PhD, 2022, Table 2.1 and §§4.2–4.4 | Unpowered low-Re planform/control comparisons; supports a signed large-deflection map, not universal stall reversal or AERIS coefficients. |
| S33 | Leng et al., [Slipstream Deformation of a Propeller-Wing Combination Applied for Convertible UAVs in Hover Condition](https://www.imavs.org/papers/2019/13.pdf), IMAV 2019-13, §§2–4 | Downstream wake deformation and flap interaction on a small static rig. Not installed AERIS flow or transient transport. |
| S34 | Su et al., [Visualization of vortical flows around a rapidly pitching wing and propeller](https://journals.sagepub.com/doi/full/10.1177/1756829316685189), 2017 | Flow visualization of a small wing with contra-rotating props; incidence/separation interaction. Geometry/Reynolds regime prevent direct coefficient transfer. |
| S35 | Ratz et al., [On the aerodynamics of an accelerating and decelerating propeller in hover at low Reynolds numbers](https://arxiv.org/abs/2611.07862), preprint v1, submitted 2026-11-05, §4.2 | Provisional transient-load/flow lead on a small electric prop. Abstract and detailed text disagree on a pitch label; no magnitude, sign or time constant adopted for AERIS. |
| S36 | Ratz et al., [associated experimental dataset](https://zenodo.org/records/23083730), DOI 10.5281/zenodo.23083730, v1.0.0, 2026-10-05; README §§2–4, 6 | CC BY 4.0. Small thrust/RPM HDF5 and README acquired with published checksums verified; processed ensemble histories, not individual trials. [Six-row derived benchmark and source identities](../../../research/aeris-120/README.md#external-transient-benchmark). Large PIV files not acquired. |

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

No matching AERIS measurements were found for inertia, CG, torque map, installed static/dynamic thrust, fuel flow, loaded control response, wing/tail polars, propwash velocity, spin recovery or pilot-rated handling. Related EFI maps and other-aircraft observations above do not close that gap. The plan can use documented surrogates, but those unknowns remain open. Manufacturer specifications and papers do not close the measurement or pilot gates.

## Reuse of existing project research

Use the [RC validation collection](../flight-dynamics/rc-validation-library-2026-10-18/README.md), [Extra realism evidence](../extra-300-realism/README.md), [fuel standard](../../FUEL-SYSTEM.md), [servo plan](../../plans/servo-dynamics.md) and [historical 3D proposal disposition](../flight-mechanics-stall-hover-knife-edge-2026-10-18.md#integration-disposition-2026-10-26). Their existence does not mean every proposed mechanism is in the pinned runtime. The source audit records the distinction.
