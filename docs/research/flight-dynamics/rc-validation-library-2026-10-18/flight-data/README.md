# Measured fixed-wing flight data and studies

Research snapshot: **2026-10-18 (Bogotá)**, with retrieval checks through **2026-10-19 UTC**. The manifest contains 23 entries covering 21 distinct primary sources; the NTNU ReadMe and paired CSV entries all belong to one dataset, not independent studies. See [`sources.json`](sources.json) for source citations, direct download links, file hashes, access status, channel notes, and inspection depth. Originals are in the repository's ignored `references/` tree where a `local_path` is present.

## Best starting points

The strongest locally inspectable time-series material is the [UAVDB 26%-scale Cub archive](https://uavdb.org/cub.php): 53 flight CSVs plus its channel/unit notes, including stalls and six named spin cases. Its records mix measured, filtered, and derived channels; the file called “high rate” has repeated timestamps, so establish each file's time base before resampling or computing derivatives. This is real flight data, but its airframe is not the Jensen Ugly Stik 60.

The paired [NTNU Skywalker X8 clean/iced lateral 1-2-1 records](https://doi.org/10.18710/NNHVBP) are small processed flight samples with 126 columns each. Their timestamps represent a jittered EKF timeline with a mean rate near 20 Hz, not uniform 50 ms samples. The channels include state estimates, control inputs, air data, and author-derived aerodynamic quantities. Use the measured/estimated fields with their metadata; do not treat powertrain-specific derived coefficients as model-independent observations. The deposit's web metadata says CC0 1.0 while its bundled README says CC BY 4.0, so the applicable terms are unresolved.

For plotted physical responses without local raw rows, start with the [UMN Ultra Stick 120/NASA handling-qualities report](https://ntrs.nasa.gov/citations/20200002019) and the [FASER publications](../../rc-aero-data-sources.md). The NASA report documents flight excitations and plots at cruise and low-speed/flap conditions. FASER's 2006 source describes its aircraft and sensors; its 2012 forced-oscillation results are wind-tunnel measurements; the 2016 spin paper combines rotary-balance tunnel tests with one actual flight spin, whose roll gyro saturated. These evidence types must stay separate. The existing UMN Ultra Stick papers add system-identification methods and related-airframe response scales, not raw logs.

[ALFA](https://www.cs.cmu.edu/~mmousaei/alfa-dataset/) is a valuable public source for real Carbon-Z T-28 flights with nominal and induced engine/control faults, plus raw ROS, DataFlash, and companion-computer logs. [IDF-DS](https://zenodo.org/records/16992976) broadens coverage to 240 fixed-wing missions across different firmware and sensor architectures. Both deposits are multi-gigabyte and were not mirrored here. The [Avistar Elite record](https://uavdb.org/avistar-data.php) is a close trainer lead, but its current official data page still says “Coming Soon!!”. [Southampton's FliTePlat record](https://eprints.soton.ac.uk/489303/) lists measured flight logs, though binary requests were blocked during this pass. See the manifest before relying on a rate, sensor, or availability claim.

## What counts as a comparison

Treat every record according to what was actually inspected: downloaded rows, processed samples, paper figures, article text, or repository metadata. An actual flight log is not necessarily raw sensor output; a paper's flight plot is not a downloadable log; tunnel data are not free-flight behavior; and a controller's autonomous trajectory does not identify open-loop airframe dynamics by itself. The FASER tunnel studies and published aircraft-model comparisons are useful supporting evidence, but are not flight-log substitutes.

For a useful simulator comparison, first document the test aircraft and build: geometry and reference areas, mass and inertia, CG, control surfaces and travels, linkage/servo response, propeller/motor/battery, firmware, and environmental conditions. Then identify each channel's units, sensor location, coordinate convention, sign, filter or estimator, sample clock and rate. Keep commanded controls distinct from measured surface deflections, and measured sensors distinct from estimator outputs. Convert axes and units explicitly, align time bases, and preserve gaps, jitter, saturation, and flight-mode changes rather than smoothing them away.

Compare like-for-like conditions: trim and speed; control doublets, chirps or multi-sines; attitude/rate/acceleration response; measured airspeed and angle-of-attack trends; and stall or spin entry only where the record truly contains those maneuvers. Report uncertainty from calibration, filtering, timing, plot digitization, wind, and configuration mismatch. A different RC airframe can bound plausibility or test sensitivity; it cannot by itself establish validation for the simulator's aircraft. Keep experimental evidence separate from deterministic replay and software checks.

## Access and search record

No access controls were bypassed. The 80 MB local cap was respected; large collections and inaccessible files are linked rather than copied. Specific remaining gaps include the current Avistar logs, complete NTNU deposit, ALFA and IDF-DS archives, FliTePlat pickle files, unparsed TU Delft measurements, and full CZ150 spin-paper time histories. The FliTePlat binary was not deserialized. Dataset and article licenses are recorded separately where they differ or conflict; public access is not treated as redistribution permission.

Representative primary-source queries used:

- `site:uavdb.org Ultra Stick flight data dataset Avistar data download`
- `fixed wing aircraft flight dataset telemetry actual flight data repository Pixhawk CSV airspeed experimental dataset`
- `site:zenodo.org fixed-wing flight test dataset IMU GNSS airspeed aircraft flight logs dataset`
- `RC aircraft high angle of attack spin flight data dataset Carbon Z Cessna 150 spin modeling Gresham`
- `site:dataverse.no Skywalker UAV system identification icing flight test CSV`
- `site:eprints.soton.ac.uk FliTePlat flight test dataset pkl`
- `Ultra Stick flight data system identification NASA UMN`
- `Carbon-Z Cessna 150 spin modeling flight test data AIAA 2022`

The collection is source triage, not a systematic review or a claim that any vehicle has passed physical validation. No coefficients or measured logs were imported into production.
