# RC sailplanes, motorgliders and soaring flight data

Research expansion retrieved **2026-10-19 UTC**, within the existing 2026-10-18 library. The [manifest](sources.json) records primary publication pages, original download URLs, file identities and inspection limits. Originals remain private under ignored root `references/`. Return to the [library guide](../README.md) for the combined catalogue and verification command.

## Aircraft and evidence

| Aircraft | Primary sources | Evidence and useful comparison |
| --- | --- | --- |
| Cloud Swift / modified RnR SB-XC | [Allen and Lin, 2007](https://ntrs.nasa.gov/citations/20070022339); [Allen flight summary, 2006](https://ntrs.nasa.gov/citations/20070022832) | Actual autonomous soaring flights, thermal encounters and energy-control behavior. The flight-summary appendices also cover June 2006 inertia-swing measurements, configurations, propeller tests and PID/excitation maneuvers. Match the specific configuration and date before extracting values. |
| Parkzone Radian Pro | [ArduSoar, 2018](https://arxiv.org/abs/1802.08215); [POMDP thermalling, 2018](https://arxiv.org/abs/1805.09875); [Reddy et al., 2018](https://www.nature.com/articles/s41586-018-0533-0) | Real flights of two-metre RC gliders: thermal estimation, control and atmospheric energy response. These include numerical comparisons as well as field results; successful thermalling does not identify a complete aerodynamic model. |
| Multiplex Solius | [Condomines et al., 2015](https://hal.science/hal-01204624) | Instrumented 2.16 m motorglider, wind/airspeed estimation and motor/propeller tunnel tests. Preliminary flight-estimation work; sensor-angle offsets and ongoing aircraft-identification work are explicit limitations. |
| Cularis-05 and companion LSTS/Portuguese Air Force platforms | [Prodan et al., 2013](https://centralesupelec.hal.science/hal-00876457) | Real trajectory-control trials at OTA airfield in May 2012, alongside software simulations. Piccolo inner loops and ground-based predictive control obscure open-loop airframe dynamics. A platform photograph does not assign every plotted trial to that aircraft. |
| Multiplex Cularis model | [Lichota, 2020](https://www.mdpi.com/2226-4310/7/8/113) | Multi-axis excitation/identification study. Metadata and abstract checked; publisher PDF retrieval was blocked. The abstract describes an aircraft model, so actual flight validation is not asserted. |
| Composite 1.5 m hotliner | [Bronz et al., dynamic soaring part 1](https://hal.science/hal-03098769); [part 2 record](https://enac.hal.science/hal-04087058v1); [author dataset](https://mrtbrnz.github.io/dynamic_soaring/) | Actual dynamic-soaring flights with a Paparazzi autopilot and smart probe. Part 1 gives 1.07 kg and 0.207 m² for its installation. The manufacturer/model name is not established. Part 2 remains a publication record without a retained paper PDF. |
| SB-XC / AutoSOAR | [Depenbusch thesis and related PSU publications](https://www.aero.psu.edu/avia/publications.html); [Bird and Langelaan, 2017](https://doi.org/10.2514/6.2017-4092) | System development and field testing; the design-space paper includes a speed polar fitted to SB-XC flight data. Related theses and papers overlap campaigns. Solar/design-space predictions remain numerical evidence. |
| Vulture / G2 Aviation Vera2V | [Bird thesis, 2019](https://www.aero.psu.edu/avia/pubs/Bird_PhD.pdf) | Actual speed-to-fly and atmospheric-observation experiments on the Vulture; most modeled-aircraft simulations use SB-XC. Chapter 3 identifies the 2.5 m, 2.2 kg flight platform and states that its polar was assumed similar to SB-XC rather than measured independently. No solar-equipped flight platform was available. |
| Escale Fox | [Bird thesis, 2013](https://www.aero.psu.edu/avia/pubs/Bird_MS.pdf); [Closing the Loop in Dynamic Soaring, 2014](https://www.aero.psu.edu/avia/pubs/BirLan14.pdf) | Aircraft modeling, wind estimation and dynamic-soaring control in numerical/hardware-in-the-loop experiments. These are not new flight-measured coefficient datasets. |
| SB-XC simulator model | [Daugherty thesis, 2013](https://www.aero.psu.edu/avia/pubs/Daugherty_MS.pdf) | XFLR5-based modeling and energy-control experiments in Silent Wings hardware-in-the-loop simulation. Section 5.2.2 explains that proposed actual flight tests did not occur. |
| Kinetic 100 and high-speed RC soaring | [Richardson, 2012, author copy](https://www2.whoi.edu/staff/prichardson/wp-content/uploads/sites/75/2018/11/Richardson-2012-RCSD-High-speed-Dynamic-Soaring.pdf) | Practitioner observations and simplified energy analysis in RC Soaring Digest. Useful behavior/context, with a lower evidential weight than calibrated telemetry or force measurements. |
| Flexible scaled Diana 2 UAV | [4TU dataset, version 1](https://doi.org/10.4121/0c3fcef0-5b63-480c-ae40-3ff726c657e9.v1) | Companion README and sensor/actuator calibration ZIP now retained for the existing [flight-data record](../flight-data/README.md). The separate 2.57 GB flight-response archive is not mirrored. |

Allen's [2005 endurance analysis](https://ntrs.nasa.gov/citations/20050041655) adds a three-degree-of-freedom atmospheric-energy model. Its predicted endurance is a simulation result, distinct from the subsequent flight campaigns.

## Retained dynamic-soaring logs

Seven original files from [the authors' repository](https://github.com/mrtbrnz/dynamic_soaring/tree/76222e07399dbcb266da7abb6fe53e896d4086c7) are pinned to commit `76222e07399dbcb266da7abb6fe53e896d4086c7`. They cover selected complete logger streams from **Laurac, 2020-11-20, flight 3**, and **Muret, 2021-04-16, flight 2**, plus a probe example, LIDAR measurements and the original license. This is a selection from the larger repository, not a mirror of every sortie.

| Retained artifact | Content inspected |
| --- | --- |
| Laurac `.data` stream and `.log` definitions | 619,423 text-message lines; first/last logged timestamps 34.4020–1433.5220. The `.log` is XML configuration and message definitions. |
| Muret `.data` stream and `.log` definitions | 615,944 text-message lines; first/last logged timestamps 34.4010–1426.2010. Same asynchronous message format, not a uniformly sampled table. |
| Muret WindCube `.rtd` | LIDAR text measurements; header specifies UTC+2. Clock alignment with onboard logs has not been reconstructed. |
| Laurac smart-probe CSV | 10,000 rows and seven named columns: three differential pressures, time and three accelerations. Header alone does not establish units or pressure-to-airspeed calibration. |
| Repository `LICENSE` | GPL-3.0 notice retained. A separate data-specific license was not located. |

Message types include `IMU_GYRO`, `IMU_ACCEL`, `GPS`, `AIR_DATA`, `ATTITUDE`, `SOARING_TELEMETRY`, `RC`, `COMMANDS` and `ACTUATORS`. Separate raw sensing, filtered estimates, controller targets and servo outputs before fitting dynamics. Repeated timestamps and different message rates require deliberate synchronization. Servo outputs are not independently measured control-surface angles.

Local filenames are descriptive; the XML `data_file` attribute retains its original source basename. Use `repository_path` and `git_commit` in the manifest to pair each definition file with its stream. Do not rewrite the originals to make a parser accept them.

## Diana calibration scope

The retained original README describes nine 2022 flight-response files, 200 Hz calibrated/resampled data, 12 distributed IMUs, 21 strain gauges, aerodynamic angles and control-surface measurements. These describe the **upstream flight archive**, not time histories obtained in this collection. The retained 19-member calibration ZIP covers the five-hole probe, actuator dynamics, elevator-angle sensing, IMU alignment and strain/load/temperature calibration. Its CRC was checked and file names inspected; MATLAB scripts and stored identification objects were not executed. Both retained artifacts match the MD5 values published by 4TU and have SHA-256 identities in the manifest. The dataset record states CC BY 4.0.

## Inspection and search limits

Representative searches included `RC glider flight identification`, `Radian Pro thermalling flight tests`, `Multiplex Solius aircraft identification wind`, `Cularis trajectory flight control`, `SB-XC soaring thesis polar`, `Escale Fox dynamic soaring`, `dynamic soaring flight dataset smartprobe` and `Diana scaled glider aeroelastic measurements`.

PDF signatures and title pages were checked, with selected platform, methods and conclusion sections inspected to classify field versus simulation evidence. This is broad source triage, not a complete reproduction or coefficient transcription. Papers, companion logs and calibration artifacts from one campaign are not independent studies. Before comparing a simulator response, establish geometry, mass/inertia, CG, propulsion, wind, axes, sample clocks, calibration and actual surface deflections.
