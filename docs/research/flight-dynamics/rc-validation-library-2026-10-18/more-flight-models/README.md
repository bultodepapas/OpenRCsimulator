# Further aircraft studies and flight recordings

Acquisition date: **2026-10-19 UTC**. This collection extends the [RC validation library](../README.md) to further aircraft configurations and flight datasets. It supports the existing VAL-/DATA- research, without changing runtime models or closing physical-validation gates. The [source manifest](sources.json) owns acquisition URLs, identity, file hashes/sizes, aircraft configuration, inspection depth and access limits.

This pass adds **20 topic records**, referring to **19 distinct newly acquired local originals**. One record has no local original. New originals comprise 14 PDFs, three CSVs, one MAT and one ZIP. A paper, archive, README and individual logs from the same experiment are companion artifacts, not independent flight campaigns. New originals are private local copies under ignored `references/rc-validation-library-2026-10-18/more-flight-models/`.

## Read an artifact before using it

| Evidence | Comparison it can support | Boundary |
| --- | --- | --- |
| Aircraft flight time histories | State/control timing, response, trim or model prediction | Match the exact airframe, configuration, clock, preprocessing, units and coordinate conventions |
| Measured motor speeds with motion | Rotor-speed-to-motion dynamics and aerodynamic-model inputs | Measured speed is not necessarily the motor command or direct force/torque |
| Published surface-sensor signals | Sensor and local-flow-change behavior during a reported flight segment | These are not full-body states or lift/drag coefficients |
| Flight-based identified model in a paper/thesis | Reported derivatives, modal response, fitting/validation conditions | Published curves are not a retained raw flight log |
| Aeroelastic or morphing test | Structural/shape coupling for that vehicle and setup | Distinguish physical flight, physical tunnel and numerical calculations |
| Dataset metadata or blocked lead | A route to a named source | The underlying measurements have not been locally acquired |

Keep Skysurfer X8 trainer studies separate from the previously held Skywalker X8 flying-wing studies. Distinct aircraft, configurations and similarly named models cannot be merged into a generic RC coefficient set. Multirotor and transitioning vehicles retain their own validation gates; their records do not validate a fixed-wing airplane model. Larger research aircraft and undisclosed industry prototypes are explicit methodological analogues.

## New RC fixed-wing flight studies

Scope: primary studies and real flight data for named RC fixed-wing models not already represented in the baseline catalog. Keep measured sensors, estimated states, commands, and actual surface positions distinct. A plot-only source is useful but labeled as such.

Originals for this section are under `references/rc-validation-library-2026-10-18/more-flight-models/planes/`.

### Mini Talon — Steffensen doctoral thesis (2025; includes a 2024 article)

- **Source:** [Full doctoral thesis, TUM repository](https://mediatum.ub.tum.de/1752143). The acquired PDF is the 2025 thesis *Fixed-Wing Flight Control Law Design using Incremental Control*, not a standalone article. Appendix A.3 reproduces the 2024 article *Practical System Identification and Incremental Control Design for a Subscale Fixed-Wing Aircraft* ([DOI 10.3390/act13040130](https://doi.org/10.3390/act13040130)).
- **Local original:** `references/rc-validation-library-2026-10-18/more-flight-models/planes/steffensen-ginnell-holzapfel-2024-mini-talon-system-identification.pdf`; 17,252,582 bytes; SHA-256 `8dbc8a882f860d6acc1ad2808ca246ba30cfa30aacc32f85b13c0c30dca4d882`. The PDF signature, metadata and extracted text were checked; the embedded article is 33 pages.
- **Evidence:** Embedded article reports flight identification/control study on the modified 1.3 m X-UAV Mini Talon “Albadrone.” IMU rates/accelerations, GPS, pitot airspeed, Hall-sensor surface/servo position and injected commands are separately described; internal signals were logged at 100 Hz. Surface positions are measured, not inferred from RC commands.
- **Use and limits:** Real sine-sweep response and closed-loop controller evidence; no raw flight files are openly bundled (authors say dataset is available on request). Aircraft is modified and the reported mass is a 1–2 kg range; not a stock-airframe nonlinear coefficient set.

### Sky Surfer 2000 — Rodzewicz (2024)

- **Source:** [DOI 10.24425/ame.2024.151335](https://doi.org/10.24425/ame.2024.151335), open-access publisher PDF.
- **Local original:** `references/rc-validation-library-2026-10-18/more-flight-models/planes/rodzewicz-2024-sky-surfer-2000-load-spectra.pdf`; 4,177,944 bytes; SHA-256 `056967be4c0a07837d4ce113d4e47a97b36a595adf07f886b5bd05d6bf7e2945`. PDF header, metadata and full extracted text were checked.
- **Evidence:** Two actual flights on a 2.0 m / 2.2 kg Sky Surfer 2000: manual maneuvering and mostly-autonomous photogrammetry. Added accelerometer and wing-deflection/extensometer channels were acquired at 500 Hz, compared with the autopilot IMU and downsampled series at 50 Hz and 5 Hz. These are measured signals; derived load factor is an analysis product.
- **Use and limits:** Strong measured load/sampling evidence, but not a full flight-dynamics ID study. The article gives plots and derived summaries only; raw logs are not bundled and no flight-control command or surface-position dataset is described. Article license is CC BY 4.0.

### Skysurfer X8 longitudinal dynamics — Juffermans (2021)

- **Source:** TU Delft [repository thesis PDF](https://repository.tudelft.nl/file/File_38c79fe2-0c75-4f7f-a133-7b89aab18ea3).
- **Local original:** `references/rc-validation-library-2026-10-18/more-flight-models/planes/juffermans-2021-skysurfer-x8-longitudinal-handling.pdf`; 11,945,112 bytes; SHA-256 `4c40e8bb9712a03351726ddfb57d6c6e5f88a5c38797d546b929046401cd480e`. PDF header/metadata and full extracted text checked.
- **Evidence:** Actual elevator/throttle sweep and doublet tests; a modified 1.41 m Skysurfer X8 with twin wing motors, Pixhawk 4/PX4, IMU, GPS and pitot. Logged inputs are servo PWM commands; available outputs include estimator speed, local acceleration, attitude/rates, height and pitot airspeed. The campaign targets 18 m/s at 30 m, with 0.4–5 Hz sweeps.
- **Use and limits:** Identified longitudinal response and handling metrics, compared with XFLR5. It is a twin-engine modified airframe; PWM commands do not establish measured surface angles. Underlying PX4 ULogs are described but not published. The thesis itself notes difficulty trimming and a weakly represented forward-speed response.


### Skysurfer X8 lateral-directional dynamics — Kuijpers (2021)

- **Source:** [TU Delft repository record](https://repository.tudelft.nl/record/Thing_424b380c-eb78-4d29-a394-e6396f864b48); full master thesis, separate from the related Juffermans longitudinal thesis.
- **Local original:** `references/rc-validation-library-2026-10-18/more-flight-models/planes/kuijpers-skysurfer-x8-lateral-directional-handling.pdf`; 4,548,096 bytes; SHA-256 `67d3d0a12e8465ab50de45eedb4cc5dd3cad58c9ebf427260b35ad53dade78f5`. PDF header, metadata and full extracted text were checked.
- **Evidence:** Aileron and rudder sweeps plus a separate validation sequence on a modified 1.41 m twin-motor X8 with Pixhawk 4/custom PX4, GNSS, pitot, and four servos. Sensor records and servo commands are distinct; sideslip, wind and state-space results are estimates. Reports an unstable spiral-mode doubling time of 5.18 s and a 0.93 Hz Dutch roll.
- **Use and limits:** The thesis notes control/servo channels were logged at 5 Hz while controller and servo updates were 50 Hz, limiting higher-frequency fidelity. Only plotted/analyzed results are public; raw logs are not attached. Repository metadata does not state reuse rights. Group this source with the Juffermans longitudinal thesis as related evidence from the TU Delft Skysurfer X8 test program.

## Experimental small-aircraft validation sources

Scope: new primary studies and downloadable records for morphing or flexible wings, tailsitters or quadplanes, high-angle-of-attack/perching/agile small fixed-wing aircraft, and openly described aircraft-design flight campaigns. Existing catalog items are excluded unless this pass establishes a materially new data object. Downloaded originals are retained only when their identity, integrity, and model or sensor semantics can be recorded in the adjacent JSON manifest.

### Verified sources

#### X-56A flexible-aircraft flight identification (NASA, 2020)

Grauer and Boucher summarize the X-56A Phase 1 campaign: 39 flights and about 1,000 maneuvers (2017–2019), with parameter estimation from measured responses. Instrumentation includes accelerometers, strain sensors, air-data boom, high-bandwidth gyros and measured control-surface positions. The multisine commands were added after the active control law/mixer; the analysis used measured actuator deflections. This is unusually rich physical aeroelastic evidence, but the 28-ft, 200–480-lb X-56A is not hobby scale and the paper does not publish raw logs. Its flexible wings are not actively morphing.

Source: [NASA NTRS record](https://ntrs.nasa.gov/citations/20200002775), [paper PDF](https://ntrs.nasa.gov/api/citations/20200002775/downloads/20200002775.pdf). PDF signature and searchable text were verified; local SHA-256 is in the JSON manifest.

#### PigeonBot II rudderless morphing (Dryad, 2024)

Dryad links the raw 81-trial wind-tunnel dataset for PigeonBot II to Chang, Chin and Lentink’s [Science Robotics study](https://doi.org/10.1126/scirobotics.ado4535). The data description identifies autopilot attitude, servo outputs, airspeed, IMU and PID traces over morphing, angle-of-attack and turbulence conditions. This is useful physical data for actuator coupling and stability trends, with a strict boundary: the described Dryad data are tunnel-supported “virtual flight” measurements rather than a free-flight 6-DOF log.

Source: [Dryad dataset record](https://datadryad.org/dataset/doi:10.5061/dryad.zkh1893h5). It is CC0-1.0; the raw MAT file is 248,583,985 bytes. The official API reports its checksum, but its API download returned 401 and Dryad’s file-stream returned 403 in this pass. No alternate route was used, so the listed checksum is not locally verified and there is no local MAT copy.

#### Cyclone tailsitter flight and airspeed data (TU Delft, 2026)

The 4TU record for Ntouros, Kelley and Smeur’s study links to the authors’ [TU Delft GitHub repository](https://github.com/tudelft/propeller_airspeed_sensor). The retained ZIP is pinned to commit `6db5cc19327f0d6c31a4e51783a442704007dbc3`; all archive CRCs passed. Its numeric MATLAB inputs were inspected safely. The training and held-out test files contain 55,000 and 43,500 samples, respectively, with corrected Pitot airspeed, right-ESC RPM/voltage/current, body rates, Euler attitude, GPS N/E/D velocity, and time. Both declare `fs=500` and have uniform 2 ms timestamp spacing: describe 500 Hz as the stored grid, since the paper does not establish it as an independent hardware sampling clock. The aircraft is the 1 kg, 0.90 m span Cyclone tailsitter with two tractor propellers; the paper describes manual turns and speed/altitude variation and corrects measured airspeed for the right propeller’s 0.24 m lateral offset using roll rate.

Keep the data classes distinct: `training.mat` and `test.mat` are processed flight arrays, not raw autopilot logs; `wt.mat` is a physical propeller/ESC wind-tunnel record; `BEM.mat` is simulation. The flight arrays omit explicit pilot/surface command channels, and the paper’s main model regime is forward flight (`J > 0.20`). The paper reports 5% nRMSE on unseen flight data but is an airspeed-model validation, not a general aerodynamic model. Sources: [4TU dataset record](https://data.4tu.nl/datasets/8bcecbac-5478-4595-b629-4378feac6dcb), [final journal paper](https://doi.org/10.1016/j.ast.2025.110999), [TU Delft repository PDF](https://repository.tudelft.nl/record/uuid:7e2450c2-f066-460b-9bdf-fa8ce5680924). The data license in the repository is CC-BY-4.0; the related paper is also CC BY.

#### High-angle-of-attack glider perching (Cory & Tedrake, 2008)

Cory and Tedrake report 240 indoor glider trajectories used for unsteady model identification and physical perching tests. Their 77 g, unpowered, 98 mm-chord glider was tracked by a 16-camera Vicon MX system at about 119 Hz; reported marker accuracy is sub-millimeter. Elevator policy evaluation used a 50 Hz ground station receiving motion-capture state, so this is strong measured post-stall/perching evidence but not an onboard-sensing or onboard-control flight log. The paper describes its trajectory processing and selected results; no reusable raw trial file was found.

Source: [AIAA paper DOI](https://doi.org/10.2514/6.2008-7256), [public author-hosted PDF](https://faculty.washington.edu/minster/bio_inspired_robotics_2018/papers/Cory_tedrake_fixed_wing_perching_procaiaa2008.pdf). The retained 12-page PDF’s signature and searchable text were verified. The public copy does not state an open-content reuse license.

## Further multirotor flight datasets

Three newly acquired numeric datasets describe custom and commercial multirotors, with motion, rotor-speed and other flight channels. Their records distinguish measurements, filtered estimates, commands and simulation-derived parameters. These are separate vehicle configurations with their own validation limits.

All retained originals belong under `references/rc-validation-library-2026-10-18/more-flight-models/rotors/`.

### Verified sources

#### NeuroBEM quadrotor test segment (2021)

Leonard Bauersfeld, Elia Kaufmann, Philipp Foehn, Sihao Sun, and Davide Scaramuzza, [“NeuroBEM: Hybrid Aerodynamic Quadrotor Model,” RSS 2021](https://doi.org/10.15607/RSS.2021.XVII.042), [official project and dataset page](https://rpg.ifi.uzh.ch/NeuroBEM.html), [dataset README](https://rpg.ifi.uzh.ch/neuro_bem/Readme.html). The research group reports a 96-flight, 75-minute dataset at 400 Hz; the selected file is an identified held-out test segment (`2021-02-18-13-44-23_seg_2`). The corresponding flight-list entry describes a 3-D circle with 4 m vertical displacement at 2 m/s.

The downloaded CSV has 16,797 numeric rows plus a header and passes the source ZIP member CRC32 (`bedaa715`); it is retained at `references/rc-validation-library-2026-10-18/more-flight-models/rotors/neurobem-2021-02-18-seg-2.csv` (13,061,515 bytes; SHA-256 `07ec70532b8865101e3cf52a93f4ee46166d84c9ae69241b0df7e7cdb83c95a9`). Columns contain time, filtered body rates and angular accelerations, Vicon pose, filtered/derived acceleration and velocity, position, four individual motor speeds and their derivatives, and battery voltage. Motor speeds are measured signals; position and pose are Vicon measurements; several state derivatives are filtered estimates. No direct thrust sensor or target motor command is in this processed CSV. The official README gives aircraft mass 0.772 kg and diagonal inertia [0.0025, 0.0021, 0.0043] kg m². It is a custom quadrotor testbed, not a conventional RC heli or fixed-wing EDF/turbine, and the values do not transfer directly to other vehicles. The dataset page does not state a license; do not assume redistribution rights.


#### Crazyflie 2.1 Brushless nano-drone benchmark (2026)

Riccardo Busetto, Elia Cereda, Marco Forgione, Gabriele Maroni, Dario Piga, and Daniele Palossi, [“Nonlinear System Identification for a Nano-drone Benchmark,” *Control Engineering Practice* 172 (2026), 106871](https://doi.org/10.1016/j.conengprac.2026.106871), [ETH Research Collection record](https://www.research-collection.ethz.ch/items/5ef14ad7-431f-4c34-b34e-990ec04c3c60), [authors’ data and code repository](https://github.com/idsia-robotics/nanodrone-sysid-benchmark). The openly described real-flight benchmark has 15 trajectories from a Crazyflie 2.1 Brushless, including separate train and held-out test trajectories. The retained file is one held-out Melon test run.

The CSV has 6,500 samples at 100 Hz and 21 columns. Per the paper’s data table, time comes from the STM32 timer; four motor angular velocities are sensorless ESC back-EMF zero-crossing measurements; position/orientation use OptiTrack with laser altitude, velocity uses optical flow, angular velocity is from the gyroscope, and body specific acceleration is from the accelerometer. The 45 g aircraft includes Flow-deck v2 and AI-deck; the diagonal inertia is taken from the Crazyflow simulator, not an independent mass-properties test. The paper aligns channels, retimes/resamples to 100 Hz, and zero-phase filters continuous values. Thus this is useful for actuator-speed-to-motion response, not raw PWM or pilot-input identification. The selected CSV matches its Git LFS SHA-256 pointer and size (2,543,109 bytes; SHA-256 `41137fbe34e8f3ecec17e9c00c99145898677906c1ee662ecf8491afeb4c678e`). The source repository has no data-specific license; the ETH record marks the article CC BY 4.0, which is not evidence of a CSV license.

#### DronePropA QDrone 2 healthy cross run (2024 dataset; 2025 article)

Mohamed AA Ismail, Mohssen E Elshaar, Ayman Abdallah, and Quan Quan, [“DronePropA: Motion trajectories dataset for defective drones,” *Data in Brief* 60 (2025), 111589](https://doi.org/10.1016/j.dib.2025.111589), with the [Mendeley Data dataset record](https://data.mendeley.com/datasets/ftdyxrr3c5/1) (published 17 December 2024; dataset DOI `10.17632/ftdyxrr3c5.1`). The record describes 130 indoor flights on commercial multirotors, including healthy and artificially damaged propellers, multiple paths and speed levels. This acquisition is the healthy, high-speed cross path, drone 1, run 1 (`F0_SV0_SP1_t1_D1_R1.mat`); the dataset description defines the cross path as back-and-forth diagonals of a 1 m square and the high speed as 2.00 m/s translational and 3.14 rad/s yawing speed.

The MATLAB v5 file is retained at `references/rc-validation-library-2026-10-18/more-flight-models/rotors/dronepropa-qdrone2-healthy-cross-fast-run1.mat` (39,716,650 bytes; SHA-256 `7ecd6aaaa617ef3db8adcc2dd6a230e4689525e479932a7461da5e1b5367b6c3`, matching the official API metadata). It contains 87,837 samples in each of `QDrone_data` (56 channels), `commander_data` (37), and `stabilizer_data` (21). The paper identifies 1 kHz logging, a Quanser QDrone 2 platform with 1.5 kg maximum takeoff weight, two onboard IIM-42652 IMUs, onboard DAQ and motor/ESC monitor I/O, and OptiTrack motion capture. Its signal table distinguishes reference trajectory and controller fields (`commander_data`, including reference thrust in newtons) from onboard IMU, battery, altitude and per-motor command/ESC voltage-percent fields (`QDrone_data`); the position and yaw fields include OptiTrack values. The arrays include commands and sensor-based motion, not direct thrust/torque or measured RPM. It is a commercial indoor multirotor under closed-loop trajectory control, so it provides useful real flight/control-response data but does not scale directly to an RC heli or EDF/turbine airplane. The Mendeley dataset record licenses the data CC BY 4.0.

## Instrumented research aircraft and companion modeling studies

### RC Cessna 182: measured flight signals with published numeric source data

[Xu et al. (2023)](https://doi.org/10.1038/s41467-023-38486-6) instrumented an RC Cessna 182 with DATSS triboelectric/piezoelectric wing-surface sensors after tunnel testing. The paper describes its wing length as **1420 mm**; preserve that wording rather than treating it as a fully specified geometric model. Figure 5b shows wireless flight signals from two sensor units. Tunnel measurements, free-flight observations and CFD appear together in the article and must be classified separately. Electrical signal amplitudes differed between the field and tunnel tests.

The complete paper, supplementary PDF and original **21.4 MB source-data CSV** were acquired. These are three artifacts from one study. The CSV is a wide collection of figure arrays, not a synchronized flight-state table: its first row identifies separate figure groups, with 100,880 following rows and 153 column positions. Some groups include sensor experiments, wind-tunnel cases or CFD residuals.

The **Figure 5b block**, zero-based columns 30–34, contains **32,001 finite rows**: a published time grid and four sensor signals, spanning approximately 0–16 s with 0.0005 s spacing. This is useful numeric evidence for surface-sensor changes during a published flight segment. The grid is not an independently verified acquisition clock, and the block is not a complete sortie, a lift/drag coefficient table or a position/attitude/control tape. The signal ordering and units need the corresponding figure and methods before analysis.

The CSV is not valid UTF-8 throughout. Original bytes were preserved; ASCII figure headers and numeric arrays were inspected through a one-to-one Latin1 decoding without asserting the original label encoding. All 153-column row widths and the selected block's numeric finiteness and time increments were checked. No source values were rewritten or inferred from a rendered plot.

### NASA RAVEN-SWFT: configuration, then measured hover identification

The [2024 RAVEN-SWFT overview](https://ntrs.nasa.gov/citations/20240004190) describes a subscale tiltrotor research model and its wind-tunnel/modeling/control program. At that date, successful free-flight hover/transition/forward-flight demonstrations were described as next steps. It is a configuration and program-stage reference, not evidence that those planned flights had already happened.

The [full SciTech 2026 hover-identification paper](https://ntrs.nasa.gov/citations/20250011078) and its [official presentation](https://ntrs.nasa.gov/citations/20260000047) describe subsequent physical hover testing with multisine excitation and model-prediction checks. The paper is filed under a 2025 accession ID but belongs to the January 2026 conference. The model has six variable-pitch proprotors, four tilting nacelles and 24 control effectors; it is 28.6% scale of a conceptual 1000-lb-class vehicle. Table 1 reports mass 1.185 slug and span 5.71 ft, with imperial inertias and reference geometry. The 2024 projected 37-lb vehicle and later approximately 38-lb test setup are dated configurations.

The study records IMU/INS, air data, controller signals and additional acquisition channels, then derives aerodynamic/propulsive forces and moments for identification. Sensor readings, estimated state, commands and derived loads are distinct. The reported hover-model agreement does not establish forward-flight/transition behavior across the full envelope. No raw numeric flight archive was attached to the inspected NTRS records; available flight videos were not downloaded as substitutes for logs. The paper and slides are companion descriptions of the same program, not independent campaigns.

### AIBOT 500: methodology with a deliberately undisclosed configuration

The [2025 NASA/industry paper](https://ntrs.nasa.gov/citations/20250003661) concerns **AIBOT 500**, a separate vectored-thrust eVTOL prototype. It discusses multisine experiment design, hover-flight identification and wake-related modeling considerations. The paper explicitly withholds the vehicle configuration. It is useful methodological evidence, but supplies neither a fully specified RC comparison airframe nor acquired raw logs. Its curves must not be assigned to RAVEN-SWFT. Unlike the other NASA records here, its NTRS rights metadata warns that copyright material may be included.

Originals are under `references/rc-validation-library-2026-10-18/more-flight-models/primary/`. PDF signatures and text parsing, source hashes/sizes, CSV schema and the selected sensor block were verified. No identification code, CFD solver or downloaded research script was executed. Searches included `RC Cessna 182 stall sensing source data`, `RAVEN SWFT hover identification`, `subscale tiltrotor flight test`, and `AIBOT flight test identification`.

### NeuroBEM companion model paper

The complete [NeuroBEM methods paper](https://doi.org/10.15607/RSS.2021.XVII.042) was acquired from the authors’ [UZH project page](https://rpg.ifi.uzh.ch/NeuroBEM.html). It accompanies the flight segment described in the multirotor section: blade-element/momentum physics and learned residuals are evaluated with processed motion-capture flight observations. Predicted thrust and torque are not direct force-sensor channels. This is a companion paper from the same study, not a further flight campaign; no published fitting or software was executed.

## Acquisition and verification

Searches combined aircraft names with `flight test`, `system identification`, `flight data`, `maneuver`, `motor speed`, `MAT`, `CSV` and `dataset`, then followed publisher/institutional pages to original files or author-linked repositories. The pass is source acquisition and selected inspection, not an exhaustive systematic review or a reproduction of published models.

The [existing catalogue verifier](../../../../../research/reference-library/catalog.py) checks original hashes/sizes, PDF headers/parsing and ZIP CRCs. Source-specific notes state any additional array/table/record checks, retained subsets, preprocessing and version identities. Downloaded research code and serialized executable objects were not executed. Public access does not establish redistribution rights; licenses are recorded per source. Originals remain unchanged.

For later simulation comparisons, use the [flight logging workflow](../../../../FLIGHT-LOGGING.md) and match configuration, inputs and measurement processing before interpreting agreement. Software replay and plausible behavior do not establish agreement with the external aircraft.
