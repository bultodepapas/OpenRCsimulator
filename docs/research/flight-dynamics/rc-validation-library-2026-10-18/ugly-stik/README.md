# Ugly Stik studies, flight tests and source data

Focused research expansion, **2026-10-19 UTC**. This guide brings together new research, original pilot reports and experimental data for the Ugly Stik family. The [source manifest](sources.json) records acquisition, aircraft identity, inspection depth, limitations and original file hashes. Return to the [library catalogue](../README.md) for CSV, BibTeX and verification results. Originals remain local-only under ignored root `references/`.

The initial acquisition added **34 catalogue records**, including **26 newly downloaded originals: 16 PDFs and ten complete MAT/HDF5 flight logs**. One previously held Flight 9 report is reused, giving 27 distinct local files referenced by this topic. Seven records have no local original. Companion reports, format guides and overlapping publications are not independent experiments; one retained thesis has unconfirmed aircraft identity.

With the subsequent acquisitions below, this focused topic now contains **78 source records and 61 distinct local originals**. The [latest acquisition](#further-flight-identification-construction-and-operation-sources) adds 22 records and 18 originals: 13 PDFs, one prepared MAT sample, one source/data ZIP and three HTML snapshots. Records and files are not independent-study counts.

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

## Further documentation, tests and equipment evidence

Further acquisition pass, **2026-10-19**. These sources add free original documents, model setup data, actuator/propeller studies and first-person observations. Published specifications, bench measurements, flight recordings, simulations and informal flight reports retain different evidential status. The source manifest identifies the inspection depth and access result for every record. Documents from the same research lineage are not counted as independent experiments.

### Further university originals and flight documentation

| Original acquired | Useful evidence | Boundary |
| --- | --- | --- |
| [García Gascón, UPV thesis, 2021](https://riunet.upv.es/handle/10251/170908), Section 5.2.7, printed p.91 / PDF p.92 | Pilot/author description and photographs of AeroDesign UPV’s Ugly Stick build and successful June 2021 first flight; the original PDF embeds the [author’s flight-video link](https://www.youtube.com/watch?v=RjvQ5Rq0NAk) | The thesis primarily concerns a separate solar UAV. The Ugly Stick subsection has no calibrated flight data or mass/CG table; video was located, not downloaded or measured. Adjacent Lunak/solar-aircraft dimensions do not describe this Ugly Stick. |
| [Harvey and O’Young, Drones 2018](https://doi.org/10.3390/drones2010004), 18 pp. | Published GBS/Delta X-8 acoustic experiment with GPS tracks, spectra and an instrumentation-accuracy table; adds the complete journal original to the previously held thesis | Same research lineage as Harvey’s thesis, not another independent flight campaign. No raw WAV/autopilot bundle. Table 1’s GBS length differs from other held descriptions; verify configuration and dimensions before comparison. |
| [Fang, O’Young and Rolland, Drones 2018](https://doi.org/10.3390/drones2020013), 17 pp., Section 5 / Figure 17 | Actual GBS round-trip flight tracks toward Fox Island, described as about 7 km each way at approximately 400 m MSL, with control/communications context | Overlaps Fang’s thesis. Separate physical flights from Monte Carlo/HIL results elsewhere in the paper. No raw telemetry bundle or aerodynamic derivatives were obtained. Historical operating requirements are not current instructions. |

The two published journal originals were retrieved from ordinary public Semantic Scholar-hosted copies of the articles; both PDFs print **CC BY 4.0** on their last page. Publisher DOIs remain their bibliographic source. UPV supplied its thesis through its public repository; its metadata reserves all rights. Public retrieval does not authorize redistribution of the thesis.

### Actuator experiments and Ultra Stick model comparisons

This scoped set adds three locally verified primary sources and one metadata-only lead. The three downloaded PDFs have valid PDF signatures, searchable text, checked title/authorship, matching recorded byte counts and SHA-256 hashes, and no matching URL or hash in the 304-record baseline or legacy catalog. Copies are retained only in the ignored reference library; copyright remains with the authors or publisher.

#### Verified PDFs

- **Carlson et al. (2013), “Analysis of Modeling Techniques for Low-Cost Actuators.”** The paper compares three actuator model structures using data from a specially instrumented modified Futaba S3305 and reports a first-order bandwidth of 4.78 Hz plus asymmetric rate estimates. This is useful component-level servo evidence, but it is a bench characterization without aircraft installation, hinge loading, or flight validation. [UMN Seiler Controls Lab PDF](https://dept.aem.umn.edu/~SeilerControl/Papers/2013/CarlsonEtAl_13AFM_AnalysisOfModelingTechniquesForLowCostActuators.pdf)

- **Lakshminarayan (2016), “Model-based Fault Detection for Low-cost UAV Actuators.”** The thesis models and bench-tests HITEC servos, including the HS-225BB used on FASER, and replays recorded FASER aileron commands through a bench servo to evaluate fault detection. The test is an actuator bench experiment driven by flight inputs, not a flight with an intentionally failed servo or an aerodynamic hinge-load test. [UMN Seiler Controls Lab PDF](https://dept.aem.umn.edu/~SeilerControl/Thesis/2016/Lakshminarayan_16MS_ModelBasedFaultDetection.pdf)

- **Polgar (2013), “Confidence metrics analysis of a fixed-wing UAV.”** This thesis compares linear and nonlinear simulation responses with Ultra Stick 25e/Thor measurements and describes six confidence-metric flight-test configurations from UMore Park on 5 November 2013. The author says the perturbation calculations used in the tests were wrong and overly conservative, while the validation process itself was correct. Its flight measurements overlap the Thor flight-log lineage already catalogued, so this adds analysis and a caveat rather than a new raw dataset. [UMN Seiler Controls Lab PDF](https://dept.aem.umn.edu/~SeilerControl/Thesis/2013/Polgar_13MS_ConfidenceMetricsAnalysisOfAUAV.pdf)

#### Metadata-only lead

- **Heide (2019), “Evaluating the Accuracy of Conventional Drag Prediction and Validation Methods for Small Electric UAVs.”** The author's page describes glide tests on three University of Minnesota UAVs, wind-tunnel measurements of windmilling-propeller drag, and a corrected component drag build-up method. The linked University of Minnesota Conservancy PDF endpoint returned HTTP 403, so this is retained only as a lead and has no local copy, hash, or full-text verification. The same author page lists a separate 2018 predecessor that explicitly reports Ultra Stick 25e glide testing; it is not added here. [Author's publication page](https://leonidheide.github.io/publications/2019-07-28-drag-prediction-validation-small-electric-uavs/), [linked University of Minnesota record](https://conservancy.umn.edu/items/32d7f602-1912-406c-a60b-1c672c80a6d0)

The source URLs and local paths are recorded in [source manifest](sources.json). Existing Dorobantu 2012/2013, FASER and Thor/Baldr logs, Tjhai 2013 metadata, and other already-held sources were not duplicated.

### Ugly Stik family manuals: further acquisition

Eight distinct original manuals were acquired from manufacturer hosts or legitimate dealer mirrors and parsed. SHA-256 and byte counts are in [source manifest](sources.json); all eight hashes are new against the baseline and existing Ugly Stik research registries reviewed for this pass. The PDFs are stored under the ignored `references/rc-validation-library-2026-10-18/ugly-stik/further-manuals/` directory.

These numbers are manufacturer setup recommendations, except where a manual explicitly says its guidance comes from the manufacturer's flight tests. None of these documents supplies independent, machine-readable flight-test data. No manual gives a target wing or tail incidence angle; Great Planes mentions using an incidence meter to check wing twist, without specifying an incidence target.

| Model and source | Geometry and mass | Manufacturer setup values | Configuration notes |
|---|---|---|---|
| Durafly Das Ugly Stik 1100 EPO [manual](https://www.air-rc.com/assets/pdf/Ugly-Stick_275.pdf) | 1100 mm span, 950 mm length, 1050 g flying mass (printed p. 1) | CG ~65 mm aft of wing LE; elevator low/high ±10/20 mm, aileron ±10/18 mm, rudder ±12/18 mm (pp. 8–9) | 3S 2200 mAh battery is to be pushed fully forward for the stated balance point (p. 9). PNF foam model, unlike the larger built-up kits. |
| Great Planes Big Stik .40/.60 ARF [manual](https://rcflight.se/pdf/pdf.aspx?a07=1259) | .40: 58.5 in span, 770 sq in, 5.25 lb, 51.5 in length; .60: 66.5 in, 1000 sq in, 6.5 lb, 59 in (p. 1) | Starting CG: .40 3¾ in with 3¼–4 in range; .60 4 in with 3¾–4½ in range. .40 high/low throws: elevator ¾/⅝ in, rudder 1⅜/1 in, aileron ⅞/⅝ in. .60: elevator ⅞/⅝ in, rudder 1½/1¼ in, ailerons 1/¾ in (p. 17) | Manual says the CG is measured aft from the wing LE, ready-to-fly and with an empty tank. The .40 rudder's printed 1⅜ in / 41 mm pair conflicts; its inch figure is 35 mm. The manual gives no target incidence. |
| Hangar 9 Ultra Stick 60 ARF [manual](https://www.astramodel.cz/manualy/hangar9/hangar9_ultra_stick_60.pdf) | 66 in span, 55 in length, 913 sq in (two-aileron) or 927 sq in (quad flap), approx. 6–7 lb (p. 1) | CG 4⅛ in aft of LE. Low/high: elevator 1/1½ in, aileron ¾/1¼ in, rudder 2½/4 in; flaps 1½ in down (p. 43) | Built for conventional two-aileron or quad-flap wings. Mix discussion on pp. 44–45 covers crow, elevator-to-flap, and aileron-to-flap; crow guidance suggests about ¼ in down elevator compensation. |
| Hangar 9 Ultra Stick Lite (HAN2325) [manual](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/han2325-manual.pdf) | Printed 76 in span, 55 in length, 1210/1230 sq in wing area, 9–11 lb (p. 1) | CG 4⅛ in aft of LE. Low/high: elevator 1/1½ in, aileron ¾/1¼ in, rudder 2½/4 in; flaps 1½ in down (p. 43) | Specification conversions are internally inconsistent (e.g., 76 in is paired with 1676 mm; 9–11 lb with 2.7–3.15 kg). Treat its printed metric fields as errors, not corroboration. Mixing discussion is on pp. 44–46. |
| Hangar 9 Ultra Stick 30cc (HAN2365) [manual](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/HAN2365-Manual-MULTI.pdf) | 81 in span, 1360 sq in, 73 in length, 12–14 lb; 30 cc two-stroke or 36 cc four-stroke gasoline (p. 2) | CG 4½ in (115 mm) aft of LE. High/low: aileron up 2 11/16/1 3/16 in, down 2 5/32/1 in; elevator 2 5/32/1 1/16 in each way; rudder 2¾/1⅜ in; flaps mid 1 in and landing 2 5/32 in (p. 27) | P. 27 calls these general recommendations measured from Hangar 9's own flight tests. |
| Hangar 9 Ultra Stick PNP 60 (HAN4775) [product page](https://www.horizonhobby.com/product/ultra-stick-pnp-60/HAN4775.html), [manual](https://www.horizonhobby.de/on/demandware.static/-/Sites-horizon-master/default/dw40f8d3e0/Manuals/HAN4775-Manual-MULTI.pdf) | 60 in span, 810 sq in, 58 in length, 7–9 lb (p. 47) | CG 4 in (102 mm) aft of LE; flight-tested flyable range 3¾–4¼ in (95–108 mm) (p. 9). Throws and mixing are tabulated on p. 10; examples include 30 mm takeoff flap, 45–60 mm landing flap and crow mix. | Mixing text on p. 10 says “Ultra Stick 10cc” despite HAN4775/PNP 60 identity. Treat this as a likely copy-edit error and verify the mix schedule before use. |
| Seagull Classic Ugly Stick ARF (SEA255) [manufacturer page/manual](https://sigmfg.com/products/seagull-models-classic-ugly-stick) | 70.9 in span, 1033.2 sq in, 7.7 lb, 57.8 in length (p. 1) | CG 100 mm aft of wing LE at root; ailerons/elevator 12–15 mm each way; rudder 20–30 mm each way (pp. 22–23) | Manual allows later experimentation ±10 mm from the starting CG. Four channels/five servos; no flap-mix schedule. |
| Seagull Classic Ugly Stick Master Scale Kit Edition (SEA 255K) [manual](https://www.minicars.se/internt/artiklar/SEA01255/SEA255KIT_manual.pdf) | Same stated 70.9 in span, 1033.2 sq in, 7.7 lb and 57.8 in length (p. 1) | CG 100 mm aft of wing LE at root, with ±10 mm later adjustment; ailerons/elevator 12–15 mm each way; rudder 20–30 mm each way (pp. 58–59) | Separate kit construction manual; shares the ARF geometry/setup values, but is a distinct source and assembly configuration. |

The Great Planes Giant Big Stik ARF manual was identified as GPMZ0197 / GPMA1224, but no copy was retained: the Great Hobbies direct PDF returned HTTP 405, ModelFlight returned HTTP 429, and the legacy Hobbico host timed out. I stopped at those ordinary retrieval failures rather than trying to evade them. Candidate links: [Great Hobbies PDF](https://www.greathobbies.com/manuals/g/gpm/gpma1224.pdf), [ModelFlight PDF](https://www.modelflight.com.au/media/wysiwyg/Documents/Great_Planes/gpma1224-manual.pdf), [Tower product/support page](https://www.towerhobbies.com/product/giant-big-stik-gp-arf-1.2-1.6-80.5/GPMA1224.html).

No manufacturer manual specifically for the original Jensen Ugly Stik was found in the reviewed registries or this bounded collection pass. The two Seagull documents are the Classic Ugly Stick descendant/configurations, not evidence for the original Jensen plan's construction values.

### Additional UglyStik and Stik field evidence

This pass adds seven sources absent from the existing catalogue. Numeric performance details below remain author- or publication-reported; none of these sources provides calibrated flight telemetry or a controlled comparison. The two retained originals are ignored local references only.

#### Original magazine scans

1. [RCM Product Review: Bud Nosen Big Stik](https://outerzone.co.uk/plan_details.asp?ID=7114), scan pages 1–4. The page 1 panel lists a 101-inch span, 1,940 in² wing, 368 oz (23 lb) ready-to-fly weight and 27.3 oz/ft² wing loading. Its prototype used a Super Hustler 2.6 cu in engine and an E.W.H. one-quart tank; the specifications separately recommend a 32-ounce tank. The installation text names a 20x8 propeller. The reviewer leveled the model and checked incidence at zero with a Robart meter, then reports about 100 ft of ground roll and qualitative aerobatics. No reviewer/date, numeric CG, tach reading, thrust or calibrated airspeed is given. Original scan (project-root-relative): `references/rc-validation-library-2026-10-18/ugly-stik/further-field/Big_Stik_101in_oz7114_review.pdf`.

2. [Big Big Big Stik design and first-flight article](https://outerzone.co.uk/plan_details.asp?ID=7114), *R/C Model Builder*, October 1979, printed pp. 16–23 and continuation pp. 68–74. The first-flight account (pp. 72–74) reports a 2.6 cu in Quadra, 18x6 prop, 16:1 gasoline-to-chainsaw-oil mix, 19 lb dry weight and CG about 1/2 in behind the main spar. It gives control throws and describes a snap roll, spin recovery and idle glide; speed is estimated in the 60 mph range, and the author says the model may stall after about a 50 ft idle glide unless the nose is lowered. These are observations from one build, not an instrumented flight log; speed is an unaided estimate and the CG datum is not the leading edge. The scan jumps from pp. 16–23 to pp. 68–76; p. 76 is adjacent unrelated content. Original scan (project-root-relative): `references/rc-validation-library-2026-10-18/ugly-stik/further-field/Big_Stik_101in_oz7114_article.pdf`.

#### Ultra Stick 30cc and Giant Big Stik reports

3. [Andrew Griffith's Model Aviation review](https://www.modelaviation.com/hangar9-ultra-stick), May 2017 issue reprint, unpaginated web copy. The review lists Evolution 33cc power, 18x8 Xoar wood prop on wheels and 18x8 Falcon carbon prop on floats, 13 lb 8 oz ready-to-fly weight and 20-minute duration. The float installation adds slightly less than 4 lb, with no CG shift or ballast reported. Stall, slow-flight and water-landing notes are qualitative; no numeric CG, RPM, thrust or airspeed is given.

4. [Tom Hintz's Hangar 9 Ultra Stick 30cc review](https://www.flyingrc.net/h9ultrastick.html), posted 22 August 2018. He balances to the listed 4.5 in behind-leading-edge CG, first adding 2-1/8 oz of firewall lead and later removing it after changing the spinner/prop washer. He rebends the main gear from 7 to 8 in clearance and uses 4 in wheels; flight notes describe a routine maiden and predictable rudder response. The page does not identify the engine/prop used, report aircraft weight, or provide instrumented speed/stall/power data.

5. [RC-Network owner thread: Hangar 9 Ultra Stick 30cc](https://www.rc-network.de/threads/hangar-9-ultra-stick-30cc.718822/), posts #5, #14, #15 and #35, March–June 2019. Jürgen reports an OS GT33 setup, roughly three hours of flying by his early summary and six hours before a later engine-stop incident. His landing observations include 50–60° flaps, up-aileron crow and steep low-energy approaches. The incident account describes an engine stop while inverted at low altitude, followed by a no-flap descent and stall. Andreas reports 7,507 g for an electric 30cc Stik with two 5S/5,000 mAh packs and 7,314 g for a separate Saito radial setup with 500 g fuel. The owners do not report a shared weighing protocol, common installations or telemetry; the German posts are owner statements.

6. [RC-Network owner propulsion reports](https://www.rc-network.de/threads/hangar-9-ultra-stick-30-cc-passender-4-takt-motor-empfehlung.719332/), posts #2 and #11, September–October 2018. For a Hangar 9 Ultra Stick 30cc, Peng reports an OS GT33 with Biela 17x10x3 and static thrust approximately equal to model weight; an 18x10x2 Graupner Super Sonic is said to make more power with more noise. Horst separately reports a Great Planes Giant Big Stik at 2.05 m and 6.1 kg with Saito FA-200R3 and Graupner G-Sonic 16x8 at just over 9,000 rpm. These are separate aircraft/configurations, and neither report states a calibrated test method, uncertainty or tachometer details.

7. [Giant Big Stik XL tow report](https://forum.scalesoaring.com/forum/tugs-and-stuff/tow-planes/25329-towing-with-the-giant-big-stik-xl), April 2018 opening posts. A club reports using a DLE61-powered Great Planes Giant Big Stik XL to tow gliders up to 5 m and 20 lb. A follow-up describes roughly 30 greased landings on a smooth grass strip. These are practical owner observations, not a maximum tow rating; no speed, climb, tow force, thrust or rough-landing test is provided.

#### Retained files and verification

The original RCM scans are at `references/rc-validation-library-2026-10-18/ugly-stik/further-field/`. Both were checked as PDFs and reviewed page by page. [source manifest](sources.json) records page scope, setup, reported quantities, hashes, byte counts and limits for every source. Forum/web sources remain linked at their public origin; no downloaded media or attachments were retained.

Representative additional searches combined `Ugly/Big/Ultra Stik/Stick`, model numbers and manufacturer names with `manual`, `glide`, `windmilling`, `actuator identification`, `servo fault`, `static thrust`, `RPM`, `tow`, `Erfahrungen`, `dinámica` and `AeroDesign`. Originals live under ignored root `references/`; public availability is not assumed to grant redistribution rights. The parent catalogue verifies originals and records acquisition gaps. No aircraft data or simulator behavior was changed by collecting these sources.

## Further flight-identification, construction and operation sources

Acquisition pass **2026-10-19**. The strongest new comparison artifact is an instrumented Ultra Stick IBIS study with a short prepared flight-data segment and pinned author code. Additional sources document other Ultra Stick flight experiments, historic Stik construction, float operation and propulsion reports. These are different aircraft configurations and evidence types, not interchangeable Jensen coefficients. The [source manifest](sources.json) preserves provenance and access limits.

### Instrumented IBIS thrust/drag study, example data and original code

[Jaeger, Thome, Gebre-Egziabher and Hemati (2026)](https://doi.org/10.2514/6.2026-4164) identify installed thrust and drag from flight using sensed energy maneuverability. The complete 24-page paper is retained. IBIS is a heavily instrumented, electrically converted **Ultra Stick**, with APC 16×8E, E-Flite Power 110 and 12S/10,000 mAh propulsion; Table 2 reports 20.17 lb weight, 6.33 ft span and 7.91 ft² wing area. It is a different configuration from Jensen, Thor and Baldr. Sections III–IV describe sensor calibration, uncertainty propagation and model comparisons; control deflections are measured with potentiometers, rather than inferred solely from servo commands. The fitted models are not a complete nonlinear aerodynamic database or an unrestricted-envelope validation.

The [author repository](https://github.com/Jaeger-Sam/EnergyManeuverability_ThrustDragID) was retained as a complete ZIP pinned to commit `85afd93ded139e724c8fbd98244904b58bbfbfdf`, alongside its sample MAT. These three catalogue records belong to **one study**. The archive contains the same MAT and a copy of the paper; it does not add an independent flight campaign. All six archive-file Git blob hashes match the pinned tree, and ZIP CRC passed. The institutional and archived PDFs have different bytes; their extracted-word differences are limited to the 24 download-watermark dates, June 4 versus June 11.

The MATLAB v5 sample has 2,258-row arrays and `dt = 0.01 s`: a **nominal 22.57-second segment**, not a complete sortie. No explicit timestamp vector, flight/date identity, GPS or throttle-command history is included. Signal arrays inspected are finite; `param_fix` contains intentional NaN placeholders, not failed sensor samples.

| Sample field | Contents and interpretation |
| --- | --- |
| `u`, `alpha`, `beta` | Forward air-relative speed input, angle of attack and sideslip. The function documentation calls `u` airspeed, while its code calculates total speed as `u/(cos(alpha)*cos(beta))`; retain that convention. Angles are radians. |
| `a_xyz` | 2,258×3 body-frame acceleration array; this sample uses ft/s². It is prepared input, not independently inspected raw IMU output. |
| `delta_vec` | 2,258×4 deflections, ordered elevator, aileron, rudder, flap; radians. |
| `n` | Propeller revolutions per second; not RPM or rad/s. |
| `W`, `Sw`, `d`, `rho`, `g` | This sample uses 20.17 lb weight, 7.9167 ft² area, 1.3333 ft propeller diameter, density in slug/ft³ and `g = 32.174 ft/s²`. Do not mix its imperial constants with SI arrays. |
| `param`, `param_fix`, `sig_sensor` | Regression selection/fixed-parameter inputs and sensor standard deviations; not additional measured flight channels. |

The MATLAB identification/filter source was inspected statically and **not executed**; no fit or figure was reproduced. Its convex-optimization path requires Mosek. The repository retains an MIT software/documentation license; the paper separately prints authors/AIAA copyright. The sample has no separate data-specific license statement. The manifest preserves each original hash, path, download URL and the repository commit.

### Further Ultra Stick flight experiments

Five primary studies were retained after comparing title, DOI and SHA-256 against the 326-record expansion baseline and existing research manifests. The Dorobantu 2013 source title also appears in an older investigation note as fetched; this pass verified the public PDF, while no retained PDF or DOI/SHA record appeared in the baseline or legacy source manifests. Local copies are under the ignored Ugly Stik reference directory.

These papers provide configuration-specific flight evidence. None provides aerodynamic coefficients that can be transferred directly to the Jensen Ugly Stik.

#### Included sources

##### Dorobantu, Seiler and Balas (2013), [uncertain-model validation](https://doi.org/10.2514/6.2013-4984) (local original: `references/rc-validation-library-2026-10-18/ugly-stik/further-faser-r4/dorobantu-2013-uncertain-model-validation.pdf`)

Aircraft/configuration: UMN modified Ultra Stick 25e, 1.5 kg, 1.27 m span and 17 m/s cruise.

Measured versus derived: Repeated closed-loop roll-step flight responses were measured and compared with 1,000 Monte Carlo runs of an uncertain simulation model. The uncertainty envelope bounded the reported roll response but not yaw; the authors attribute the yaw mismatch to stronger turbulence in flight than the model represented. The 5-degree disturbance used in the uncertainty model was synthetic.

Limits: This is simulation-model validation, not a new aerodynamic coefficient-identification campaign. Results are tied to the 25e and its controller; plots are published, but no raw time-series log is attached.

##### Sun, Regan and Gebre-Egziabher (2019), [model-free synthetic air data](https://doi.org/10.2514/1.C035290) (local original: `references/rc-validation-library-2026-10-18/ugly-stik/further-faser-r4/sun-2019-model-free-airdata-us120.pdf`)

Aircraft/configuration: UMN Ultra Stick 120 with IMU, GPS, pitot-static system and an in-situ-calibrated five-hole probe. The flight data are from 21 June 2018.

Measured versus derived: Sensor records and probe airspeed/angle measurements are reference observations. The model-free filter derives airspeed, angle of attack, sideslip, wind and uncertainty from GPS/IMU/pitot measurements. Maneuvers included wind circles, a push-over/pull-up near 2g and rudder-induced steady sideslip.

Limits: One instrumented flight; the five-hole probe is calibrated, not error-free truth. The estimator assumes wind varies slowly relative to aircraft dynamics. The article supplies plots rather than a raw flight log.

##### Weiser, Ossmann and Heller (2018), [robust controller and anti-windup flight validation](https://doi.org/10.2514/6.2018-2982) ([DLR record](https://elib.dlr.de/120888/), local original: `references/rc-validation-library-2026-10-18/ugly-stik/further-faser-r4/weiser-2018-ultrastick120-antwindup.pdf`)

Aircraft/configuration: DLR UltraStick 120, 8.13 kg with a 1.92 m span and 0.769 m² wing. The paper describes the DLR aircraft and does not identify it as NASA FASER.

Measured versus derived: Flight responses were collected with predefined commands and pilot-augmented attitude control. Pitch used an H-infinity controller, roll used velocity-scheduled LPV control, and reduced elevator saturation limits deliberately triggered anti-windup tests. Controller behavior and nonlinear-model comparisons are derived results.

Limits: Control-system validation, not new aerodynamic identification. Lookup-table aerodynamics came from prior wind-tunnel work; raw flight logs are not attached. Do not combine its 8.13 kg DLR setup with another Ultra Stick 120 configuration.

##### Bauer, Hiba and Zsedrovits (2019), [Budapest real-flight collision decision study](https://doi.org/10.1155/2019/7191839) (local original: `references/rc-validation-library-2026-10-18/ugly-stik/further-faser-r4/bauer-2019-budapest-ultrastick25e-collision.pdf`)

Aircraft/configuration: Budapest trials used a 1.27 m, 1.5–2 kg E-flite Ultra Stick 25e as the intruder and a separate 3.5 m, 10–12 kg twin-engine Sindy as the camera-equipped own aircraft. Both carried IMU, GPS, pitot and pressure sensors.

Measured versus derived: Parallel, nearly level encounters used 15 m or 30 m horizontal separation, with nominal 20 m/s and 17 m/s air-relative speeds. Camera observations and aircraft sensor data were measured; closest-point and time-to-closest-point estimates were computed by the monocular algorithm. Avoidance was disabled for an initial offline-evaluation set and activated for later horizontal maneuvers.

Limits: Sense-and-avoid evidence, not aerodynamic data. The Ultra Stick is the intruder; tests do not map its stall, gust or control envelope. Results are tied to the parallel-encounter geometry.

##### Venkataraman and Seiler (2016), [single-surface Baldr flight tests](https://doi.org/10.2514/6.2016-0634) (local original: `references/rc-validation-library-2026-10-18/ugly-stik/further-faser-r4/venkataraman-2016-baldr-one-surface.pdf`)

Aircraft/configuration: UMN Baldr, an approximately 8 kg Ultra Stick 120 derivative with eight independently actuated surfaces, including custom split elevators and rudders. The flight computer selected one left or right elevator as the only active aerodynamic surface.

Measured versus derived: Roll, pitch and elevator histories were measured over straight-and-level and banked-turn tests on three days between January and May 2015. The paper compares LQG and H-infinity control and reports stable flight with degraded tracking; best-case command tracking was within about 5 degrees.

Limits: A custom over-actuated configuration and fault-tolerant-control demonstration, not standard Ultra Stick aerodynamics. Wind and turbulence varied across days, so the tests do not define a controlled gust response or stall boundary. The paper contains selected plots, not an attached raw log.

#### Screening notes

The 2018 IFAC elevon fault-detection article reports software-in-the-loop results, and the 2018 FASER Learn-to-Fly paper is simulation-based. Neither was counted as physical flight evidence. The NASA FASER static, forced-oscillation and rotary-balance papers are already represented in the baseline.

### Further Ugly Stik construction and rigging sources

Research pass: 2026-10-19 UTC. Local-only originals are in `references/rc-validation-library-2026-10-18/ugly-stik/further-build-r4/`. The parallel [source manifest](sources.json) records source identity, acquisition, hashes and limits. Every downloaded PDF has a valid PDF signature and page count; SHA-256 was checked against the 326-source baseline with no matches. These copies remain in the ignored references tree.

#### Direct Jensen branch: RCM Plan 939 (1985)

The [Outerzone record for RCM Plan 939](https://outerzone.co.uk/plan_details.asp?ID=6801) identifies the article and plan as the Jensen-kitted version. It describes a plastic engine mount and contemporary radio as updates. The two-sheet plan adds engineering detail beyond the held Jensen insert set: 1.5 inches of tip rise per wing panel, spar splice/doubler and center-section sketches, central aileron servo with bellcranks, and recommended travel of 3/8 inch elevator, 1 inch rudder, and 5/16 inch up / 1/4 inch down aileron at the control surface. Local copy: `references/rc-validation-library-2026-10-18/ugly-stik/further-build-r4/rcm-939-das-ugly-stik-plan-1985.pdf`. The 13-page illustrated article is useful as a construction sequence and equipment-installation reference; local copy: `references/rc-validation-library-2026-10-18/ugly-stik/further-build-r4/rcm-939-das-ugly-stik-build-article-1985.pdf`.

The archive lists this RCM drawing as 62 inches span while the Jensen plan is catalogued as 60 inches. Preserve that scale discrepancy rather than silently rescaling the scan. The RCM article is a later re-presentation of the Jensen branch; it does not supersede the Grid Leaks prototype or the held Jensen plan/inserts. Outerzone notes that its plans are free for personal use and requires source credit/linking for publication.

#### Direct descendants: Liddle Stik and Mini Stik

The [1968 Liddle Stik record](https://outerzone.co.uk/plan_details.asp?ID=4952) includes Larry Leonard and Bud Anders' original magazine text and plan. It calls the model a 75-percent reduction of the Kraft design and says the structure was modified and elevator area increased. Its plan specifies 0–1 1/4 inches dihedral per panel and illustrates spruce spars, full-length vertical-grain webbing, sheeting and the bellcrank system; local copy: `references/rc-validation-library-2026-10-18/ugly-stik/further-build-r4/das-liddle-stik-rcm-346-plan-1968.pdf`. The article says over 1/8 inch of aileron movement gave excessive angular acceleration, and the remedy was longer aileron horns. It reports a 3 1/2-pound dry prototype, with examples flown both with and without dihedral or ailerons. This is the author's reported response to linkage gain on this variant; no controlled scaling comparison is reported. Do not transplant these values to the 60/62-inch aircraft.

The [1973 Mini Stik record](https://outerzone.co.uk/plan_details.asp?ID=6144) describes a 36-inch, 270-square-inch, 2.5-pound `.15–.19` descendant. Its plan and article document compact equipment placement, steerable nose gear and elevator-operated wheel brakes. The article reports moving the battery aft and nose gear forward to manage CG and tank space, then changing the nose-wheel linkage after repeated Nylink pin failures. It also describes the fuel-tank pressure pickup and more than 100 qualitative flights. This is period installation evidence for a much smaller variant, not a modern radio/fuel-system specification. Local copies: `references/rc-validation-library-2026-10-18/ugly-stik/further-build-r4/das-mini-stik-36in-rcm-541-plan-1973.pdf` and `references/rc-validation-library-2026-10-18/ugly-stik/further-build-r4/das-mini-stik-36in-rcm-541-article-1973.pdf`.

A later [Liddle Stik owner comment](https://outerzone.co.uk/plan_details.asp?ID=4952) says some examples powered by .40 engines folded their wings; the author's response was to use a sheeted D-tube wing. The comment does not identify a common build, structural inspection, speed or failure sequence, so it is a useful lead rather than a validated strength limit.

#### Flutter and failure reports

The [RCM Plan 939 build thread](https://www.rcuniverse.com/forum/scratch-building-aircraft-design-3d-cad-174/4678179-rcm-das-ugly-stick.html) contains one owner's high-speed flutter/crash report. After impact, the builder found damage to both plastic bellcranks, a loose clevis, split/separated ailerons, torn hinges and failed double-sided servo tape. The owner explicitly could not determine the initiating failure because the crash destroyed the evidence; servo retention and linkage slop remain hypotheses. This is the clearest failure sequence found for the RCM branch, but it is not a controlled investigation.

On the [Outerzone plan page](https://outerzone.co.uk/plan_details.asp?ID=6801), separate builders blame flutter on ailerons extending to the wingtip or on a powerful engine, and describe clipping/fixing the aileron tip or extending the fixed wing tip. These are anecdotal diagnoses and proposed changes with no matched tests. Keep them separate from the original plan's linkage/structure and from any simulation validation claim.

#### Float adaptation

An archived [1987–88 water-flying discussion](https://decnotes.datacellar.net/showtopic.php?conf=1614&topic=1073744599&userno=117588) includes an Ugly Stik owner reporting 33-inch Gee-Bee floats and spray passing behind the propeller arc. The thread also describes a rigid mount using stock landing gear, 10-24 threaded rod and aluminum-tube spreaders, and warns that a flexible installation can keep the floats from cleanly reaching the step. The detail is operational advice from individual users, not a dimensioned conversion drawing. Other takeoff failures in the same thread concern an Eaglet 50 or other models, so their buoyancy, spray and water-ingress observations are not Stik measurements.

#### Evidence limits

The magazine plans/articles are image scans; the plan sheets were inspected visually, but the articles were not fully OCR-transcribed. Outerzone supplies archival identity, scans and quoted article text; it is not a current manufacturer. The Liddle/Mini sources are direct family descendants with substantially different scale, loading and equipment. The flutter and float material consists of first-person online reports without instrumentation, matching airframes or controlled conditions. Use it to frame structural and setup questions, not to claim measured flutter boundaries, float takeoff performance or physical validation.

### Further Ugly / Big / Ultra Stik field reports

This bounded pass adds five first-party or first-person reports with quantified Stik-family operating details. URLs and local SHA-256/byte metadata are in [source manifest](sources.json). Exact source URLs were checked against the 326-record baseline and the existing Ugly Stik registry; none matched. None of the retained file hashes matched those registries.

| Source | Aircraft and configuration | Reported measurements or flight observations | Evidence limits |
|---|---|---|---|
| [David Hipperson, Yarra Valley Aeromodellers newsletter, Jan. 2013](https://yarravalleyaeromodellers.com.au/wp-content/uploads/2013/07/0113-YVA-Newsletter.pdf), printed p. 5 | Hobby City Stick 1500. Initial Hobby City motor/3S 3200 mAh; later Scorpion 3026-710 V2, Master Airscrew Electric 12x8, Castle Creations 50 A ESC, 4S 4170 mAh. | The author reports 630+ W and “all-up weight without the pack” of 2050 g. The first flight was flown by Greg Lepp in very windy conditions; Hipperson later reports easy, powerful flights on the 4S installation. | First-person club-newsletter report. Wattmeter and scale methods are not given. The 2050 g excludes the flight pack and must not be treated as ready-to-fly mass. No RPM, current, airspeed, or flight duration is supplied. |
| [Jay Smith and Ed Smetak, Model Aviation, Jan. 2022](https://www.modelaviation.com/content/electric-powered-ultra-stick-has-much-offer) | Hangar 9 Ultra Stick PNP, 60 in. At-a-glance table lists an E-flite BL50 525 Kv motor; it calls the ESC Avian 60 A and lists 6S 4000/5000 mAh batteries. The table says 13x8 prop; the flight section says 14x8E APC and calls the motor “52BL.” | Test weight is reported as 7.46 lb with 6S 5000 mAh; duration 5–8 min depending on pack. The authors describe actual maiden/subsequent flights and publish flap and mix settings. | Magazine field review. The article mentions ESC telemetry but publishes no RPM/current log, airspeed, or measuring protocol for weight/time. Motor and propeller nomenclature differ between the setup table and flight text. |
| [RCU owner report, Hangar 9 Ultra Stick 60 float flight, post #24](https://www.rcuniverse.com/forum/arf-rtf-75/6376651-hangar-9-ultra-stick-60-a.html) | Mostly stock Ultra Stick 60, Super Tigre 60, 12x6 prop, about 37 in. Nitro Planes 60-size floats; about 2 oz tail ballast. | The pilot says the floats added about 1 lb, the model got onto the step in 30–40 ft and lifted off in under 100 ft, with steep climbs and normal water landings afterward. | These are owner estimates; no distance, weight, tach, or airspeed measurement method is stated. Search indexing exposed the relevant post dated 18 Aug. 2010, but the source endpoint returned HTTP 403 on direct retrieval, so no local copy was retained. |
| [Thomas, RC-Network OS GT33 thread, post #137, 11 Nov. 2024](https://www.rc-network.de/threads/os-gt33.548084/page-7) | Hangar 9 Ultra Stick 30cc with OS GT33, SparkSwitch Pro RPM/temperature sensor, Zimmermann stainless muffler, Biela Sport 19x10, 1:50 premium gasoline/oil mix. | The owner reports maximum in-flight RPM of about 7800. | German-language, sensor-derived first-person report, with no raw log, sensor calibration, sampling rate, flight conditions, or aircraft mass. Do not generalize this installation-specific maximum. |
| [Kai, RC-Network RCGF 40 Boxer V2 thread, post #2, 24 Mar. 2021](https://www.rc-network.de/threads/erfahrung-mit-rcgf-40-boxer-v2.11843123/) | Hangar 9 Ultra Stick 30cc with RCGF 40 V2 Stinger, two PEFA single-cylinder mufflers, Biela 18x10 three-blade propeller. | The owner reports an initial ground run without tuning at 6450 rpm and thrust reported as “8.9 kg” (the author’s notation). | German-language owner-reported static run, not a calibrated test stand report; no instrument identity, fuel, ambient conditions, or repeatability are stated; the “kg” thrust notation is not aircraft mass or a documented force calibration. |

The material is complementary: the newsletter provides an older electric conversion and rough power/mass values; the magazine review documents a modern electric 60-inch variant; the forum posts add one water takeoff observation and two gas-propulsion measurements for the Hangar 9 30cc airframe. Across all five sources, the numeric values are author- or owner-reported. None is a calibrated open flight log or independent measurement campaign. There is no calibrated flight speed in this set. The RCU takeoff distances are the only field-distance numbers and their measurement method is unstated.

Four originals were saved unchanged in the ignored `references/rc-validation-library-2026-10-18/ugly-stik/further-field-r4/` directory: the YVA newsletter PDF, the Model Aviation page HTML, and two RC-Network page HTML responses. The RCU post was not saved because ordinary direct retrieval returned 403; no login or access workaround was used. Each retained file's signature/text was checked, and SHA-256/byte counts are recorded in [source manifest](sources.json).

This pass used `energy maneuverability`, `thrust drag identification`, `IBIS`, `anti-windup`, `synthetic air data`, `sense and avoid`, `RCM 939/346/541`, `float`, `flutter`, `RPM` and model-specific propulsion terms. Local HTML files are unchanged page snapshots, not flight logs; archive/code files were not executed. Originals remain in ignored root `references/`. Public availability does not establish redistribution rights or physical validation. No simulation coefficients were changed.
