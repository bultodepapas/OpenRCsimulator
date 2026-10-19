# Ugly Stik studies, flight tests and source data

Focused research expansion, **2026-10-19 UTC**. This guide brings together new research, original pilot reports and experimental data for the Ugly Stik family. The [source manifest](sources.json) records acquisition, aircraft identity, inspection depth, limitations and original file hashes. Return to the [library catalogue](../README.md) for CSV, BibTeX and verification results. Originals remain local-only under ignored root `references/`.

This pass adds **34 catalogue records**, including **26 newly downloaded originals: 16 PDFs and ten complete MAT/HDF5 flight logs**. One previously held Flight 9 report is reused, giving 27 distinct local files referenced by this topic. Seven records have no local original. Companion reports, format guides and overlapping publications are not independent experiments; one retained thesis has unconfirmed aircraft identity.

The [further Stik and comparable-aircraft expansion](../stik-analogues/README.md) adds a twelve-page Ugly Stik instrumentation article with measured flight plots, further Giant Big Stik theses, gust/flow-sensing experiments and additional trainer/Ultra Stick campaign leads. Its manifest records which original files were actually acquired.

## Keep the aircraft identities separate

The simulator's Jensen Das Ugly Stik 60 has its authoritative geometry sources in the [aircraft reference index](../../../aircraft-reference-index.md) and [original reference guide](../../../ugly-stik-resources.md). The Grid Leaks prototype, Jensen kit, later commercial Ugly Stick models, Great Planes Big Stik/Giant Big Stik and Hangar 9 Ultra Stick are different configurations. A common name or appearance does not establish matching airfoil, CG, inertia, control geometry or propulsion.

Use direct Ugly Stik observations to frame aircraft-specific questions. Big Stik measurements are related-airframe evidence. Ultra Stick/FASER measurements and university logs are explicit analogues. Numerical model files and simulator output are separate from real flight recordings.

## Previously held evidence worth reading closely

| Source | What it actually establishes |
| --- | --- |
| [Urbano Molano, 2011](https://jci.uniautonoma.edu.co/2011/2011-5.pdf), retained in [conventional sources](../conventional/sources.json) | A reverse-engineered UglyStik and computational cruise/design analysis. The closing page describes an initial checkout flight, a landing propeller strike and a reported nose-heavy condition corrected by rearranging component weights. It also explicitly says dynamic behavior data were simulated and proposes future control-input/flight-data acquisition. These qualitative flight observations are not an identified dynamic model. The printed claim that weights were adjusted without affecting CG is not a reproducible mass-property measurement. |
| [Cereceda thesis](https://memorial.scholaris.ca/items/f97eed21-9c23-4839-ad10-59634eb03bac) and [2019 Giant Big Stik article](https://www.mdpi.com/2504-446X/3/2/48) | JSBSim model development and a limited comparison with recorded aircraft motion. The [existing review](../conventional/README.md#closest-stik-evidence) records manually adjusted gain/offset/delay, omitted rudder/takeoff/landing and constant-throttle assumptions. These limitations matter more than a single correlation score. |
| [Ultra Stick/FASER scientific registry](../../rc-aero-data-sources.md#ultra-stick-family) | Flight-identified matrices/inertias, tunnel polars, forced oscillation and spin evidence on explicitly different research aircraft. Keep these as comparative evidence with their original reference geometry and normalization. |

These previously catalogued sources are linked here rather than presented as newly discovered studies.

## New Giant Big Stik flight studies

[Murrant's 2018 thesis](https://hdl.handle.net/20.500.14783/9370) documents an electric Giant Big Stik with Pixhawk and independently logged inertial sensing. The September 2017 manual flight applied oscillatory aileron, elevator and rudder inputs for model identification; subsequent flights tested attitude control and path following. The identified model is intended for approximately 25 m/s conventional flight, not stall/spin behavior. The thesis provides model parameters and plotted traces, but no separate raw-log bundle. Its stated 14 kg maximum takeoff mass includes payload capacity; actual test-flight mass is not established. Its electric configuration differs from the piston-powered Cereceda model already held.

[Stevenson's 2015 thesis](https://hdl.handle.net/20.500.14783/10645) documents actual landing trials in 2010 and 2013 using different electric GiantStik airframes. The 2013 experiment compared unaided RC, fixed-view FPV and head-tracked VR using touchdown location and runway-centerline deviation. This is small-sample pilot/landing-performance evidence, with weather and incomplete approaches documented. The [2015 Procedia paper](https://doi.org/10.1016/j.promfg.2015.07.144) is an overlapping report of the same 2013 campaign; its publisher PDF was not obtained, while the complete thesis is retained.

The [Cereceda JSBSim manual, 2019](https://hdl.handle.net/20.500.14783/9498) adds a downloadable Giant Big Stik configuration case study, XML listings and a 100 Hz CSV output setup. Its traces and manual FlightGear flights are simulated. The [earlier JSBSim/AeroSim comparison](https://doi.org/10.1109/SMC.2016.7844857) likewise concerns numerical validation; the official institutional record dates publication to February 2017 for the 2016 conference. Both belong to the existing Cereceda model-development lineage, not additional measured-flight campaigns.

## Downloaded university flight records: explicit analogues

The [University of Minnesota flight-data collection](https://hdl.handle.net/11299/163580) supplies complete archived data files, not cropped examples. **Baldr is an instrumented Ultra Stick 120; Thor is an Ultra Stick 25e. Neither is the Jensen Ugly Stik.** The files include sensor measurements, derived/filtered states and controller channels; archived originals are not necessarily unprocessed sensor streams.

| Record | Retained data and experiment |
| --- | --- |
| [Baldr 9, 2015-03-11](https://hdl.handle.net/11299/198154) | MAT file and reused report for a split-elevator H-infinity controller trial stopped after two unstable runs. Each test run begins with five seconds under a baseline controller; this is not the beginning of the whole archive. Absolute maneuver windows have not been mapped. |
| [Baldr 12, 2016-11-02](https://hdl.handle.net/11299/198141) | MAT file and report: trim, turns, straight-ahead and accelerated power-off stalls. The report does not establish a developed-spin campaign for this sortie. |
| [Baldr 13, 2016-11-02](https://hdl.handle.net/11299/198142) | MAT file and report: baseline configuration, three straight-ahead stalls followed by four developed-spin test points and active recovery. |
| [Baldr 14, report dated 2017-09-29](https://hdl.handle.net/11299/198143) | Complete MAT file and report: configuration N, nominal loading, three stalls and thirteen spin points. |
| [Baldr 15, report dated 2017-09-29](https://hdl.handle.net/11299/198144) | Complete MAT file and report: configuration A, aft CG, two stalls and eight spin points. |
| [Baldr 16, report dated 2017-10-05](https://hdl.handle.net/11299/198145) | Complete MAT file and report: configuration B, increased roll inertia, three stalls and seven spin points. |
| [Baldr 17, 2017-10-05](https://hdl.handle.net/11299/198146) | MAT file and report: configuration C, increased roll inertia plus aft CG, three stalls and seven spin points. The report defines mass-loading changes rather than exact measured CG/inertia. |
| [Thor 97](https://hdl.handle.net/11299/174374), [Thor 98](https://hdl.handle.net/11299/174375), [Thor 104](https://hdl.handle.net/11299/174228) | Three HDF5 files with 84 synchronized channels at 50 Hz. Archive names identify confidence-metric flights and an air-data-circle flight; no separate procedure reports were attached. |

Flights 14–17 provide the reported N/A/B/C loading matrix. Added wing masses and a removable 333 g block change loading; actual mass properties are not established by the labels. Separate flights and weather prevent treating this as a fully matched comparison. For Flights 14–16, reports and MAT files are paired by their official archive items, but MAT flight timestamps and channel arrays were not decoded; their reported flight dates must not be confused with file-creation dates.

Both attached format guides are retained. The [G1 dictionary](https://hdl.handle.net/11299/198154) lists IAS in m/s and angles in radians, but labels `psi` as roll and `phi` as yaw. The [G2 guide](https://hdl.handle.net/11299/198141) lists airspeed in knots, EKF angles in degrees, IMU rates in rad/s and acceleration in m/s². G2 actuator channels can be normalized values or angles in radians depending on configuration; they are not guaranteed independent surface-position measurements. G1/G2 are not interchangeable, and a related dictionary does not establish an exact version match for every file.

The retained Baldr 12/13/17 MAT structures have 100 Hz time vectors and label EKF attitude and actuator/surface channels in degrees, IMU rates in rad/s, acceleration in m/s² and EKF velocity in m/s. These per-file labels differ from some generic CSV-format alternatives. A logged angle is still not established as a measured surface position. The older Flight 9 MAT archive is approximately 16.7 Hz; Thor files are 50 Hz.

Confirm the selected file's axes, units, sampling and controller mode before reconstruction. Whole-file timestamp spans include logging outside the maneuver and are not established airborne durations. Sensor full-scale/saturation specifications were not established. Exact flight-window alignment, stall/spin segmentation and coefficient estimation have not been performed in this collection.

## Original flight reviews and pilot observations

| Primary source | Useful observation and boundary |
| --- | --- |
| [Crossley, Model Aviation, September 2024](https://tcrconline.com/documents/RC%20Information/Ugly_Stik.pdf) | First-person Jensen history covering decades of flights and engine/radio testing, plus a later modified build. Reports handling and failures, without measured CG, speed or control-response traces. Original article PDF retained. |
| [RCM Big Stik 60 review, February 1988](https://outerzone.co.uk/plan_details.asp?ID=11467) | Reports 67.5 in span, 930 in² area and 7 lb 12 oz ready-to-fly mass, plus qualitative aerobatics, inverted flight and recovery. Its numeric CG and throws are not printed. Original two-page review retained; Great Planes aircraft, not Jensen. |
| [Jensen owner reports, 2005–2006](https://www.rcuniverse.com/forum/golden-age-vintage-antique-rc/2769063-phil-krafts-original-ugly-stick-print.html?pp=40) | Original pilots discuss nose-heavy trim and moving CG aft to obtain spins. The quoted 4¾ in plan mark is an owner's statement, not independently verified plan data; no final aft position or test procedure is given. Link-only. |
| [Giant Big Stik owner/reviewer reports](https://www.rcuniverse.com/forum/arf-rtf-75/3164223-great-planes-giant-big-stik-3.html) | Installation, balance, propeller and flap-induced pitch observations across separate models. No calibrated RPM, exact duration or flight telemetry. Link-only. |
| [Seagull Classic Ugly Stik 71 in reports](https://www.rcuniverse.com/forum/arf-rtf/11637537-seagull-classic-ugly-stik-71-a-print.html) | Owners report electric/gasoline installations, all-up weights, endurance estimates and stall handling. These are different aircraft and uncalibrated observations; they are not a measured polar or Jensen data. Link-only. |
| [Doug Smith, RCM variant, 2017](https://outerzone.co.uk/plan_details.asp?ID=6801); [Dries Neyrinck, Grid Leaks variant, 2016](https://outerzone.co.uk/plan_details.asp?ID=5175) | Original electric-build/flight notes with battery, motor, propeller and all-up weight. Distinct plan variants; no calibrated flight-response recordings. Both link-only. |
| [Myers, Ampeer, December 2016](https://www.theampeer.org/ampeer/ampdec16/ampdec16.htm) | Foam-board derivative with a Clark-Y wing: build measurements and an incidence change following excessive powered climb. Different wing/fuselage from Jensen; no logged dynamics. Original newsletter retained. |

## Historical Ugly Stick recovery experiment

[Aderhold, Gordon and Scott, NASA CR-137894 (1976)](https://ntrs.nasa.gov/citations/19770003105), printed page 113 and figures 15–16, describes a commercial **58 in, 10 lb Ugly Stick modified with a deployable rotor**. More than 60 flights investigated rotor loading, sections and blade pitch; the report describes deployment, spin-up, autogyro maneuvering and landings without ground roll, recorded on film.

This is direct evidence that a modified Ugly Stick was flown in a research program. It is not a stock Jensen aerodynamic dataset, and neither a telemetry archive nor the mentioned film was obtained. The complete original report is retained without alteration. Its legacy NTRS ingestion prefix puts the PDF header at byte 436; normal PDF parsing succeeds, and the catalogue verifier preserves and checks the original bytes.

## Unconfirmed related lead

[Urbano Molano's 2005 Cauca thesis](https://repositorio.unicauca.edu.co/handle/123456789/6903) is retained because its institutional abstract describes instrumentation and flight-model testing by the author of the later UglyStik article. The aircraft identity is unconfirmed. Inspection was limited to the repository abstract and cover; the PDF reports restricted printing/copying permissions, which were not removed. This record is not counted as established Ugly Stik flight evidence.

## Reading a source for simulator comparison

Record the exact variant and configuration before extracting numbers. For a pull-up, stall or spin comparison, the useful context includes actual all-up mass and CG, measured throws or surface angles, airspeed, throttle/propeller state, wing incidence/dihedral, wind and controller augmentation. A pilot's statement about a gentle stall is a handling observation; it does not determine a post-stall lift curve or yaw/roll damping.

Separate manufacturer setup recommendations, measured quantities, inferred estimates, first-person recollections and numerical predictions. Treat flight duration and peak GPS groundspeed as installation/environment observations unless the source supplies the conditions needed to interpret them. Files named `.csv` can contain synthetic JSBSim output; a model's logging configuration is not itself a flight log.

No verified raw telemetry archive for the exact Jensen 60 was located in this pass. The complete downloaded flight logs are Ultra Stick analogues; the additional Giant Big Stik studies expose measured results through thesis plots/tables rather than separate telemetry files.

Representative searches combined `Ugly Stik`, `Ugly Stick`, `Das Ugly Stik`, `Big Stik`, `Giant Big Stik`, `Ultra Stick`, `Baldr` and `Thor` with `flight test`, `system identification`, `stall`, `spin`, `CG`, `flight data`, `JSBSim`, `aeromodelo` and `comprobación en vuelo`. Primary universities, NASA, original publications and original pilot posts were preferred. Access failures and inspection limits remain explicit in the manifest.
