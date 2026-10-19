# Further Stik studies and comparable RC aircraft

Research expansion: **2026-10-19 UTC**. This pass searches beyond the previously held [focused Stik collection](../ugly-stik/README.md) and [other airplanes](../other-airplanes/README.md), including alternative spellings, named trainer platforms, reference lists and university campaign descriptions. The [manifest](sources.json) pins original URLs, inspection depth, aircraft identity, file sizes and SHA-256 hashes. The parent [library](../README.md) supplies the combined CSV/BibTeX catalogue and verification inventory.

## Use these sources first

The extended Urbano Molano article adds **actual plots from a reconstructed Ugly Stik**, beyond the short design article previously held. The additional Giant Big Stik theses document actual flights, but their sensor/avoidance/acoustics results answer different questions from aerodynamic system identification. The new Ultra Stick and trainer studies broaden the experiments available for comparison; they do not specify the Jensen Ugly Stik 60 used by the simulator.

For a simulation comparison, prefer a source with known aircraft configuration, input history, sensor channels and a described maneuver. Treat controller outputs, estimated states and measured states separately. Digitizing a printed plot requires its own uncertainty; it does not recover the original log. Source counts below count documents/data artifacts, not independent physical campaigns.

## Further direct Giant Big Stik evidence

- **Murrant, 2012 — attitude estimation in a real GBS flight.** [Institutional original](https://www.collectionscanada.gc.ca/obj/thesescanada/vol2/002/MR88040.PDF), Section 4.2, Figures 4.21–4.22, Table 4.10. Manual/autopilot flight at Argentia provides an independent early instrumentation study. The author reports inter-estimator RMS differences of yaw 11.7°, pitch 6.52° and roll 8.82°. These compare an AHRS reconstruction to MicroPilot, with no independent true attitude. The magnetometer input was synthesized; the ten processing runs describe random-noise realizations, not ten separate flights. Use this to interpret sensor residuals before assigning them to aerodynamics. No raw telemetry bundle obtained.
- **Fang, 2018 — actual GBS encounter trials.** [Institutional thesis](https://hdl.handle.net/20.500.14783/9343), Chapter 7. Table 7.1 identifies a DLE-30/APM 2.6 installation, 2.045 m span and 0.9793 m² area. The listed 7 kg empty mass and 10 kg MTOW do not specify actual sortie mass. Figures 7.7 and 7.11 describe flight synchronization and trajectories from recorded autopilot logs; Section 7.4.3 reports over a dozen avoidance maneuvers before explaining the separate HIL campaign. No underlying log bundle was obtained. Useful for maneuver/latency context, with the controller included in the observed response.
- **Cereceda, Rolland and O’Young, 2017 — implementation companion.** [Five-page NECEC paper](https://hdl.handle.net/20.500.14783/9501) supplies parameter tables, configuration and event/output examples. Maximum-aileron plots are simulation output. This shares the model lineage of the already-held 2019 paper/manual and 2020 thesis; it adds implementation context, not an independent physical experiment.
- **Harvey, 2018 — acoustic flight measurements with a GBS target.** [Institutional thesis](https://hdl.handle.net/20.500.14783/9347), Chapter 6, TS#2. A gasoline GBS flies near an instrumented Delta X-8; GPS-derived relative motion supports the acoustic analysis. Tables 6-5/6-6 give source/propeller context. The author explicitly states actual engine speed was unknown and derives the approximate 135 Hz source frequency from spectra. No raw audio/GPS bundle was obtained. Separate actual detection samples from extrapolated maximum ranges. This is useful for propulsion/noise and instrumentation context, with no aerodynamic derivatives identified.

Public legacy Memorial PDF URLs now return repository HTML in ordinary retrieval; the current public Scholaris records supplied their linked ORIGINAL bitstreams. Library and Archives Canada supplied the earlier AHRS original. The existing 2019 MDPI GBS article was searched again, but ordinary publisher/static and institutional attachment retrieval remained blocked; no new local original is claimed for it.

### Extended Ugly Stik instrumentation article

[Urbano Molano, Ingenium 12(24), 2011, pp.82–93](https://dialnet.unirioja.es/servlet/articulo?codigo=5038448) is a twelve-page original, distinct from the four-page design article already held. It shares the reconstructed 1.56 m-span, 0.59 m² aircraft and adds acquisition electronics and measured flight plots (Figures 28–33). Four boards cover RC PWM inputs, data storage, gyros and air data/acceleration; LabVIEW processes RS-232 records. Results describe a turn at 15–20 s and altitude/speed changes at 20–45 s. This supplies experimental plots, not a raw dataset or identified aerodynamic model; regression is explicitly future work.

Printed page91 was visually inspected because hidden PDF text is duplicated. It labels acceleration in g, altitude in m and airspeed in m/s. The very low displayed speeds must not become a stall-speed target without checking instrument calibration and test conditions. The stated roughly 100 m operating height is distinct from the plotted altitude near the 1737 m field elevation. No verified raw files, sampling rate or sensor error budget were acquired.


## Gust and flow-sensing research

This pass checked the 281-record baseline, `rc-aero-data-sources.json`, and the existing validation-library source registries before adding records. The five entries in `lineage.json` have no matching source URL or SHA-256 in those holdings. One new full-text paper was retained locally. Four sources remain metadata-only: three institutional PDF links returned an Azure WAF JavaScript challenge, and the conference-paper record exposed no manuscript link.

### Strongest new evidence

Xie et al.’s ICRA 2026 paper tests an E-flite Slow Ultra Stick with a two-axis wind-tunnel rig, six-axis force transducer, two five-hole probes, seven wing-pressure taps, independently actuated flaperons/elevator/rudder, and a movable upstream gust generator. It reports force-estimation and control-tracking comparisons at 7, 9, 10, and 14 m/s, with the clearest generalization result at the held-out 14 m/s condition. The PDF is stored at `references/rc-validation-library-2026-10-18/stik-analogues/lineage/xie-et-al-2026-narwhal-icra-slow-ultra-stick.pdf`; see the [arXiv record](https://arxiv.org/abs/2510.07160), [version 2 PDF](https://arxiv.org/pdf/2510.07160v2), and [authors’ ICRA page](https://fxxie2.github.io/narwhal_website/). arXiv records v1 submitted 2025-10-08 and v2 revised 2026-03-27 03:58:02 UTC. The authors’ page and Crossref proceedings metadata confirm this is an ICRA 2026 conference paper (DOI [10.1109/ICRA57385.2026.11697429](https://doi.org/10.1109/ICRA57385.2026.11697429)), not only an arXiv preprint.

The main simulator value is methodological and comparative: the paper demonstrates how flow probes and local pressure taps affect a force model under gusts, and reports controlled-surface tracking. It does not provide a free-flight aerodynamic database. Its headline six-axis RMSE combines forces in newtons and moments in newton-metres, and the paper exposes no raw synchronized measurements, so those aggregate errors are not coefficient-validation targets.

### Additional primary leads

Tjhai’s 2013 UMN master’s thesis is a direct Mini Ultra-Stick lineage lead. Its indexed abstract describes stochastic electric-propeller thrust validated against wind-tunnel measurements and stochastic aerodynamic-coefficient uncertainty; indexed thesis text identifies the Mini Ultra-Stick as the aircraft for validating the flight-dynamics method. DSpace API metadata resolves the supplied bitstream UUID through its `ORIGINAL` bundle to [thesis handle 11299/162402](https://hdl.handle.net/11299/162402), title “Developing stochastic model of thrust and flight dynamics for small UAVs” (item UUID `fe2b1789-ef4d-4f66-896c-7bff26470549`). Handle [11299/163580](https://hdl.handle.net/11299/163580) is a different UMN flight-data collection already held in the repository. The official thesis download link returned a WAF JavaScript challenge, so the record has no local copy and no coefficient values are claimed. Its companion [UMN record for “Stochastic Thrust Model for Small UAVs”](https://experts.umn.edu/en/publications/stochastic-thrust-model-for-small-uavs) confirms a separate 2013 conference publication with Monte Carlo/perturbation uncertainty analysis and wind-tunnel validation. Treat those two publications as overlapping evidence, not two independent tests.

The Bristol sensing group’s [2017 paper](https://doi.org/10.2514/6.2017-1487) reports wind-tunnel, indoor, and outdoor flights with pressure- and strain-sensing UAVs, including gust exposure and roll/pitch control. Its [institutional record](https://research-information.bris.ac.uk/en/publications/bio-inspired-distributed-strain-and-airflow-sensing-for-small-unm/) does not identify the aircraft or expose flight logs. The group’s [2019 paper](https://doi.org/10.2514/1.C035416) adds a chordwise pressure-array study with tunnel characterization, pressure-based angle-of-attack control, and flight-trial validation; see the [Bristol record](https://research-information.bris.ac.uk/en/publications/distributed-pressure-sensingbased-flight-control-for-small-fixed-/). Both official AAM PDF links returned the same kind of WAF challenge. Their campaign overlap is unknown, so do not count them as independent flight sets without reading the papers.

### Acquisition limits

The arXiv PDF was downloaded through its ordinary public endpoint, parsed, and hashed. The University of Minnesota and University of Bristol direct institutional PDF links returned an Azure WAF JavaScript challenge with HTTP 403. No challenge solving or alternate-route retrieval was attempted. The UMN thesis identity was verified using ordinary DSpace metadata endpoints only; no thesis content was downloaded. The metadata-only records preserve these leads for later retrieval through normal institutional access. The author pages checked for the Slow Ultra Stick paper exposed the paper and video but no raw-data or code download link.


## Trainer and sport-airframe evidence

These records target conventional RC trainer analogues of Ugly Stik. It excludes simulation-only records as validation evidence and distinguishes flight measurements, model calculations, and unshared logs.

### Strong new originals

- **Rizwan (2011), Kadet Senior system identification.** [University of Waterloo repository PDF](https://dspacemainprd01.lib.uwaterloo.ca/server/api/core/bitstreams/a3238ce2-af59-4fa8-8ed9-40a9a96a82f4/content), saved as `references/rc-validation-library-2026-10-18/stik-analogues/trainers/rizwan-2011-kadet-senior-flight-system-id-thesis.pdf`. The thesis records actual flight outputs and RC commands from a custom sensor suite: pitot speed, alpha/beta vanes, 3-axis gyros/accelerometers/magnetometers, throttle/elevator/aileron/rudder PWM references, synchronized onboard logging at about 75 Hz. It reports Output Error Method model fits, then an improved 23-parameter fit after filtering noisy MEMS rates. Raw log files are not attached. RC PWM references are not measured surface positions; the author flags wind, sensor drift, vane/control calibration and parameter initialization as limitations. Later aggressive tracking is simulated; only linear control was flight-tested, and the airframe was not considered structurally sound for aggressive maneuvers.

- **Jimenez, Silva & Hernandez (2017), Kadet Senior TECS/EKF flight evaluation.** [EUCASS paper PDF](https://www.eucass.eu/doi/EUCASS2017-411.pdf), saved as `references/rc-validation-library-2026-10-18/stik-analogues/trainers/jimenez-silva-hernandez-2017-kadet-tecs-flight-tests.pdf`. The actual flight campaign used a roughly 4.95 kg, 2.045 m span Kadet Senior with electric propulsion. Pixhawk reports actuator commands at 30 Hz and IMU data at 25 Hz; recorded/reported quantities include airspeed, altitude, groundspeed, wind, attitude/rates, throttle and elevator servo. TECS errors are reported against flight response. This is control/estimator validation, not a comprehensive aerodynamic coefficient validation: the inertias are calculated using XFLR5, some stability-rate terms are flight-estimated, and the raw logs are absent.

- **Matamala Carvajal (2025), Kadet-40/X-Plane response comparison.** [University of Concepción repository item](https://repositorio.udec.cl/items/fb892da0-4b9b-4f08-9c5b-2215133bef65), direct [bitstream](https://repositorio.udec.cl/bitstreams/ef10f0a3-72a0-4169-bb81-2ae599143555/download), saved as `references/rc-validation-library-2026-10-18/stik-analogues/trainers/matamala-carvajal-2025-kadet-40-flight-validation-thesis.pdf`. The modified 5.09 kg electric Kadet-40 used Pixhawk 6C, a BMI055 IMU, MS5611 barometer, MS4525DO pressure sensors and potentiometer AOA/SSA vanes. Mission Planner logs support analyses of airspeed, attitude, angular rate, barometric altitude and RC outputs. The thesis reports pitot-versus-tunnel and AOA-vane calibration errors, and compares selected elevator 3-2-1-1 and aileron/rudder doublet responses with X-Plane. Campaign 1 had overlapping inputs and just 5.5 s between tests; campaign 2 selected responses after a better procedure. This is not aerodynamic-derivative identification; the electric aircraft is compared with a combustion-motor simulation, curves differ materially, rates are not specified, and raw logs are not attached.

### Useful metadata-only leads

- **Jimenez et al. (2020), same-title Energies article.** [MDPI article](https://www.mdpi.com/1996-1073/13/1/14), DOI [10.3390/en13010014](https://doi.org/10.3390/en13010014). It is a related journal publication on the same Kadet Senior K1/K2 platform and should not be counted as a separate airframe or known independent flight-data campaign. MDPI metadata and indexed article text were reviewed. The ordinary PDF/article endpoints returned 403/429, and the Warsaw University repository file route produced a Cloudflare verification page; no bypass was attempted and no HTML challenge response was retained. Institutional metadata lists CC BY 4.0. Raw flight logs are not known to be released.

- **Sarmento et al. (2019), Telemaster Senior synthetic alpha/beta.** [Official ABCM proceedings record](https://abcm.org.br/proceedings/view/COB2019/1578), DOI [10.26678/ABCM.COBEM2019.COB2019-1578](https://doi.org/10.26678/ABCM.COBEM2019.COB2019-1578). The MicroPilot LRC2 INS/GPS, magnetometer, pitot and attitude data support wind-triangle alpha/beta estimates from actual Telemaster flights in calm and turbulent weather. Measured vane references were taken on a separate Vector-P aircraft with an ICASIM smart boom, so this is not direct Telemaster angle validation. The official PDF control produced a malformed link with no file identifier; no local PDF or raw log was acquired.

### Deduplication and access notes

The five source records and their exact URLs/DOIs were checked against the 281-record `baseline.json` and `docs/research/flight-dynamics/rc-aero-data-sources.json`; no exact source/DOI match was found. SHA-256 values for the three saved PDFs also match no baseline record. The 2017 EUCASS and 2020 Energies papers are related versions on the same Kadet campaign and are explicitly linked as such rather than presented as independent evidence.

Only verified PDFs are present in the assigned trainer reference directory. The MDPI 403 response and the earlier Warsaw repository challenge page were not retained as originals. No raw log archive was found among these sources; figures and selected time histories are not a substitute for downloadable synchronized logs.


## New UMN Thor flight-log records

Research snapshot: 2026-10-19 UTC. This fragment adds three selected Thor flight identities from two report-backed campaigns; it does not mirror the full UMN archive. Thor is the UMN Ultra Stick 25e, a conventional sport-aircraft analogue, not the Jensen Ugly Stik 60.

### Selected campaigns

#### 2012-03-30 — manual upset and post-stall, Flight 34

The [UMN item for Thor Flight 34](https://hdl.handle.net/11299/174314) includes a two-page report for Flights 34 and 35 plus Flight 34 HDF5 and MATLAB v5 data. The report states both sorties were flown manually and gives Flight 34 windows from 219 to 710 s. Its test points include roll upsets, rudder impulses and sustained rudder, and sustained post-stall attempts (the Flight 34 LOC3 entries list 20% and 16% throttle). It notes several roll/yaw departures and failed departures, giving useful control and maneuver context.

The same report identifies material data limits: the Euler-angle data need post-processing; the AoA polarity is wrong; AoA estimation fails as sensed pressure becomes too low; manual pilot feedthrough was considered noisy and laggy. The report covers Flight 35 too, but this acquisition retains no Flight 35 binary.

#### 2012-05-21 — system identification and controller validation, Flights 44–46

The [UMN item for Thor Flight 44](https://hdl.handle.net/11299/174325) includes a two-page report covering Flights 44, 45 and 46. Flight 44 used 1 s, 4° doublets on roll, yaw and pitch after manual trim. Its data were intended to complement earlier manually injected doublets. The report notes a mismatch in predicted versus observed Dutch-roll behavior and manual elevator input at the end of each elevator doublet. Flight 45 repeated the sequence with improved pilot timing. Flight 46 tested a baseline controller in closed loop using roll and pitch tracking doublets. Raw Flight 44 and 46 HDF5/MAT files are retained; Flight 45 is described in the report but its raw files are not included.

#### File inspection and channel limits

All HDF5 files expose flat root datasets with no unit attributes. MATLAB v5 files expose flat per-channel variables and also contain no per-variable units. Exact observed HDF5/MAT variable names are:

- Flight 34: GPS_TOW, Pd, Pd_aoa, Pd_aos, Ps, adStatus, alt, aoa, aos, ax, ax_bias, ay, ay_bias, az, az_bias, cpuLoad, da_l, da_l_in, da_r, da_r_in, de, de_in, df_l, df_l_in, df_r, df_r_in, dg_in, dr, dr_in, dthr, dthr_in, etime_actuators, etime_control, etime_daq, etime_datalog, etime_guidance, etime_nav, etime_sensfault, etime_surffault, etime_sysid, etime_telemetry, gpsStatus, h, hx, hy, hz, ias, imuStatus, lat, lon, mode, motor_RPM, motor_current, motor_powerout, motor_throttle, motor_time, motor_voltage, navValid, navalt, navlat, navlon, navvd, navve, navvn, p, p_bias, phi, pitch_ref, psi, q, q_bias, r, r_bias, roll_ref, run_num, satVisible, the, time, vd, ve, vn.
- Flight 44: GPS_TOW, Pd, Pd_aoa, Pd_aos, Ps, adStatus, alt, aoa, aos, ax, ax_bias, ay, ay_bias, az, az_bias, cpuLoad, da_l, da_l_in, da_r, da_r_in, de, de_in, df_l, df_r, dr, dr_in, dthr, dthr_in, etime_actuators, etime_control, etime_daq, etime_datalog, etime_guidance, etime_nav, etime_sensfault, etime_surffault, etime_sysid, etime_telemetry, gpsStatus, h, hx, hy, hz, ias, imuStatus, lat, lon, mode, navValid, navalt, navlat, navlon, navvd, navve, navvn, p, p_bias, phi, pitch_ref, psi, q, q_bias, r, r_bias, roll_ref, run_num, satVisible, the, time, vd, ve, vn.
- Flight 46: GPS_TOW, Pd, Pd_aoa, Pd_aos, Ps, adStatus, alt, aoa, aoa_cmd, aos, aos_cmd, ax, ax_bias, ay, ay_bias, az, az_bias, cpuLoad, da_l, da_l_in, da_r, da_r_in, de, de_in, df_l, df_r, dr, dr_in, dthr, dthr_in, gamma_cmd, gndtrk_cmd, gpsStatus, h, h_cmd, hx, hy, hz, ias, ias_cmd, imuStatus, lat, lon, mode, navValid, navalt, navlat, navlon, navvd, navve, navvn, p, p_bias, p_cmd, phi, phi_cmd, psi, psi_cmd, q, q_bias, q_cmd, r, r_bias, r_cmd, run_num, satVisible, theta, theta_cmd, time, vd, ve, vn.

These names identify logged variables, not guaranteed units or physical sensor interpretations. Exact signs, units, calibration, sensor ranges, saturation limits and whether output variables equal physical surface positions are not established by these files. Flight 34 additionally has motor throttle, output power, voltage, current, RPM and a separate motor_time vector. Flight 46 includes controller command fields such as phi_cmd/theta_cmd and p_cmd/q_cmd/r_cmd.

The report's excitation angles are in degrees; this does not establish the unit or scaling of stored control channels. The HDF5/MAT files should be treated as logged and estimated channels, not independently calibrated measurements. The time spans below include the complete archive and do not establish airborne duration.

| Flight | File | Main time vector | Structural inspection |
| --- | --- | --- | --- |
| 34 | HDF5 and MATLAB v5 | 44,777 samples; 0.021–895.581 s; median step 0.020004 s; one 0.040 s interval | 81 HDF5 datasets; separate motor stream has 6,103 samples at 0.2 s, with motor_time ending at 1220.4 s |
| 44 | HDF5 and MATLAB v5 | 34,052 samples; 0.021–681.041 s; median step 0.0200005 s | 72 root datasets |
| 46 | HDF5 and MATLAB v5 | 25,998 samples; 0.021–519.961 s; median step 0.0200005 s | 72 root datasets |

#### Representative maneuver windows from the report

| Flight 34 time (s) | Recorded test description |
| --- | --- |
| 219–230 | Right-bank upset followed by inappropriate pull-up recovery; roll/yaw departure |
| 315–335 | Left-bank upset; no departure |
| 435–450 | Right-rudder impulse; roll/yaw departure |
| 465–482 | Sustained right rudder, reported −6°; no departure |
| 605–640 | Sustained post-stall attempt, 20% throttle; roll oscillations, no departure |
| 680–710 | Sustained post-stall attempt, 16% throttle; roll oscillations, no departure |

These windows refer to the report/flight time, not a newly exported or replay-aligned simulator input tape. Flight 46's reported reference excitation is a four-second, 20° roll-tracking doublet followed by a four-second, 5° pitch-tracking doublet. Those are controller references, distinct from Flight 44's surface-excitation commands.

### Acquisition and checksums

Each local file is under ignored root references/ and remains a research copy. The table gives local byte count, locally calculated MD5 and SHA-256. The local MD5 was also checked against the University Digital Conservancy bitstream metadata. Public retrieval does not grant redistribution permission; no item-specific open license was found.

| Source | Local file | Bytes | MD5 | SHA-256 |
| --- | --- | ---: | --- | --- |
| [Flight 34 report](https://conservancy.umn.edu/server/api/core/bitstreams/0f36ce35-2ce2-42ff-a029-6c75d28264af/content) | thor-flight-34-2012-03-30-report.pdf | 148,900 | 424a44e4b9c94f8a1132f5a5c21f62de | 41e90514a030cc6af9b23913b4eb7c291da09a48100e4a3de76cef03ac058a65 |
| Flight 34 HDF5 | [thor-flight-34-2012-03-30.h5](https://conservancy.umn.edu/server/api/core/bitstreams/c9c4785f-8edc-41f9-b1cb-3a4a5bfaf4d7/content) | 27,191,176 | 42a5c040bc173a1eeb6ea1bcb22ef1d0 | 2b0de6b1b470915f440cbb0d0d70e68acb59303bf2e63283f1555f1aaea67288 |
| Flight 34 MATLAB v5 | [thor-flight-34-2012-03-30.mat](https://conservancy.umn.edu/server/api/core/bitstreams/89be86c9-4a02-45ba-9876-55d99801e9d6/content) | 5,161,645 | 0c8311119a9837ace3ad2eea40737432 | 645533a806f86979ef59ebbb81b9631b989341b39fdc26501f9663c0d62b059d |
| [Flights 44–46 report](https://conservancy.umn.edu/server/api/core/bitstreams/7e7c3712-5bf7-49f0-bcfb-a14abc37b6eb/content) | thor-flight-44-2012-05-21-report.pdf | 125,770 | 92385663f42f05984198e0d23713695a | 150ec6079b9a32cd3195d2bf3db5921b41da3700457dd81f312a72eb8122f142 |
| Flight 44 HDF5 | [thor-flight-44-2012-05-21.h5](https://conservancy.umn.edu/server/api/core/bitstreams/58749c12-70c0-486a-b870-0a3585db69c5/content) | 19,642,224 | c5505f503b3873bd4daf6253ff4c7b80 | 61bab08a0434a9f536eb03c12fd960a4d09f030496a6c290af394b420ccf435c |
| Flight 44 MATLAB v5 | [thor-flight-44-2012-05-21.mat](https://conservancy.umn.edu/server/api/core/bitstreams/b409e3ab-9b9c-4bdf-b959-33de9502c2a8/content) | 2,190,764 | f65d78171056c161088357d35a3b3d53 | 353a95042045f21be3bf5ad9d16c0ac2990cf231cfee8ee0e6690abf4e490d19 |
| Flight 46 HDF5 | [thor-flight-46-2012-05-21.h5](https://conservancy.umn.edu/server/api/core/bitstreams/9f46c8fd-b1cf-4275-b9d7-a7ce5597e34f/content) | 15,002,040 | f37d91a145bcd3106a69c947b0524daf | e890d02ae38f40e1dac34d4177eb4684bc58392aac7caa242c022699ffa4d678 |
| Flight 46 MATLAB v5 | [thor-flight-46-2012-05-21.mat](https://conservancy.umn.edu/server/api/core/bitstreams/ff5bf440-f3ee-491c-82e5-ea78c00e426a/content) | 1,681,854 | 99dd16874debb8f75f05afd3c25629f4 | 7ca6bf0dd5d3f7d00bdb73d80488c96f860f64531b103bdf6fa32ca26a373ce1 |

All eight files were retrieved from ordinary public bitstream content URLs. Initial transient HTTP 504 responses succeeded on ordinary retries. PDFs were parsed as text, MATLAB v5 exports inspected with scipy.io.loadmat, and HDF5 files inspected read-only with h5py. No embedded code or pickles were executed.


## Discovery and verification scope

Query families included `Ugly Stik/Stick`, `Giant Big Stik`, `Mini/Slow/Ultra Stick`, `Thor`, `Kadet K1/K2/40/Senior`, `Telemaster Senior`, combined with `instrumentation`, `flight tests`, `chirp`, `doublet`, `loss of control`, `stochastic thrust`, `gust`, and Spanish `dinámica de vuelo` / `adquisición de datos`. Author publications, citations, university repository metadata and flight-report descriptions supplied additional leads. Existing holdings were checked before acquisition.

Third-party originals are local-only in ignored `references/rc-validation-library-2026-10-18/stik-analogues/`. Manifests retain licenses/access limits; public availability is not assumed to permit redistribution. Downloads were not executed. PDF parsing, original hashes/sizes and any ZIP CRC checks are included in the parent inventory. Dataset structure inspection is described in the log notes. No source coefficients were imported into simulator code, and this collection does not establish physical validation.
