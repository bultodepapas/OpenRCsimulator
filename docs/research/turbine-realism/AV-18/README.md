# AV-18: fuel-powered RC turbojet source review

2026-10-13 · Read-only research and current-source inspection. No propulsion changes or new physical measurements. Implementation requirements and remaining work live in the [turbine realism plan](../../../plans/turbine-realism.md). Earlier [AV-05 research](../../avanti-s-av05-turbine-dynamics.md) and [AV-14 audit](../../avanti-realism/AV-14/propulsion-audit.md) retain their dated scope.

## Scope and method

The production reference is the **2017 JetCat P100-RX, non-BL**, installed in the experimental SebArt A200 / Ventage Jet. Other engines provide comparison evidence, never interchangeable calibration. Manufacturer publications take precedence for specifications and ECU features; original experiments inform identification; NASA supplies general physical relations. Missing measurements remain missing.

Official PDFs were downloaded without alteration, checked for page coverage and encryption, and extracted with `pypdf==6.1.3` under CPython 3.12.12. All eight PDFs in the fingerprint table have native text, no encryption and no empty extracted pages. Decision-critical pages were rendered with `PyMuPDF==1.26.5`: JetCat 2017 PDF p.15, RX 2011 p.36, RX/RXi 2015 pp.14/51, Many p.7, Xicoy p.37 and P250 p.5. The catalog contains spreads: PDF p.15 is printed pp.28–29. Page references below are printed pages unless explicitly marked PDF. Downloaded copyrighted PDFs and temporary renders are local review material, not redistributed assets.

The graph index had stale line ranges: its `_pre_step` snippet landed in unrelated reload code. Current files were inspected directly before accepting the findings. Several other tracks were editing/committing concurrently; the file fingerprints below identify the inspected bytes independently of HEAD.

## Manufacturer register

### R1 — JetCat P100-RX, selected historical configuration

[JetCat 2017 catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf), printed p.28, P100-RX column: idle/max **44,000/154,000 rpm**, **2/100 N**, **80/390 ml/min**, **0.064/0.312 kg/min**; air flow **0.23 kg/s**, pressure ratio **2.9**, exhaust speed **1,565 km/h**, EGT **490–720 °C**, mass **1,080 g including valves**. Conditions: **15 °C, 1013 mbar, STP ±3%**. Catalog values are nominal specifications, not a full test map or statistical confidence interval. Pump/ECU/battery mass must be inventoried separately according to the actual assembly.

### R2 — JetCat RX/RXi ECU behavior

[RX/RXi operating manual](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_RXi_120218.pdf), cover **March 2015**, 71 pages. Response settings: pp.13–14/51; upper-range setting acts above about **70,000 rpm**. The narrative and Limits table are not fully consistent about response defaults; record the actual chosen configuration. `ThrStick Curve` p.51 gives factory **3.0**, versus RPM-proportional **1.0**, without specifying the project's exact cube-root equation. P.48 gives **2–5 s for low-idle to normal idle**, not idle to full power. Fuel/oil and installation: pp.11–12; state sequence and stop/cooling: pp.31–38. These describe a dated RX/RXi family ECU, not every V12 feature or a measured P100 step response.

### R3 — JetCat RX manual, earlier revision

[RX-only operating manual](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf), cover **August 2011**, 72 pages. P.35: `AutoOff` targets `StabilRPM`, then shuts off after approximately **6 s**. P.36: `SlowDown` has pump off and kerosene valve closed; OFF requires RPM **<800**, exhaust temperature **<95 °C**, and the switch in OFF. This URL does **not** support the later `IdleThrResponse`/`FullThrResponse` citations assigned to it in earlier repository research. Preserve the publication date rather than inferring it from the URL suffix.

### R4 — JetCat P100-RX-BL, current comparison

[Official product specifications](https://www.jetcat.de/en/productdetails/produkte/jetcat/produkte/RC%20ENGINES/Engines/p100_rx-bl): idle/max **2/100 N**, **44,000/154,000 rpm**, **80/390 ml/min**, EGT **480–720 °C**, **5% oil**. It describes a brushless fuel pump and ECU V12 ambient pressure/temperature sensing. Similar endpoints do not establish identical response, thermal limits or controller behavior to the selected non-BL installation. The 480 °C lower EGT figure differs from R1's 490 °C; retain both identities.

### R5 — Xicoy X52, current small-engine comparison

[Official X52 specifications](https://www.xicoyturbines.com/page29.html): adjustable maximum **25–52 N**, idle **1.8 N**, RPM **60,000–225,000**, fuel **160 g/min at 52 N**, also listed as **205 ml/min**. Fuel is **kerosene only with 4% oil**, excluding biodiesel. Ambient sensors are included; recommended battery is **2S LiPo / 2200 mAh**. No idle fuel-flow point or numerical throttle-response time is supplied. Mass/volume flow conversion requires this fuel's density, not the P100's catalog ratio.

### R6 — Xicoy family ECU, v1.5/2024

[TurboJet user manual](https://www.xicoyturbines.com/assets/files/XicoyTurbojetManual_EN.pdf), 40 pages: p.10 historical model table **does not contain X52**. Family ambient ramps: pp.18/27; fuel: p.12; shutdown/cooldown and restart: pp.34–35; curves: p.37. The curve table supplies separate FULL EXPO, HALF EXPO and LINEAR schedules; its prose contains a contradictory linearity statement. Auto-restart is disabled by default, requires several qualifying signals, and aborts if stable combustion is not detected within **10 s**; quoted restored-power time is **10–15 s**, not guaranteed. Cooling is to **<100 °C**. The approximately **15 s up / 10 s down** first-run procedure on p.33 is an operator calibration exercise, not measured spool response. X52-specific applicability requires firmware confirmation.

### R7 — JetCat P250-PRO-S-V2, response-definition comparison

[Basic technical information V1-4](https://www.jetcat.de/jetcat/anleitungen/P250-PRO-BasicTechn-Information-V1-4.pdf), cover **02/2023**, p.5: at **15 °C, 101.325 kPa, zero airspeed**, maximum/idle **250/12 N**. Acceleration is **5 s, 5%→95% thrust**; deceleration **5 s, 95%→5% thrust**. Startup OFF→idle is **13–20 s, 15 s typical**. This proves that transition endpoints and startup must be distinguished; it also prevents assuming every turbine necessarily decelerates faster than it accelerates. None of these durations is a P100 calibration.

### R8 — KingTech K-210G5, comparison with incomplete conditions

[Official K-210G5 specification list](https://www.kingtechturbines.com/product/kingtech-k-210g5/132?cp=true&q=false&sbp=false): maximum **121,000 rpm**, thrust **21 kg at maximum RPM**, maximum EGT **750 °C**, consumption **590 g/min**, and **10–15 s start time**. Fuels listed: diesel, Jet A1, kerosene; lubrication **5%**. The thrust unit is interpreted as kgf: **205.94 N**, using standard gravity. The page does not define startup endpoints, consumption operating point, ambient test conditions or idle values. It is unsuitable for deriving a response curve. The direct site is rendered dynamically; indexed official-page text was used. K-102G4+ was also investigated, but is not used as numerical evidence here because source readback was incomplete.

## Experiments and general physics

### R9 — P100-RX multi-sine ground identification

Many et al., [DGLR paper 550281](https://www.dglr.de/publikationen/2022/550281.pdf), DLRK 2021; publisher release 2022. Pp.6–7: tests cover approximately **46–85% throttle** with a different idle command convention; thrust corner about **0.4 Hz**, versus an initial step estimate near **1 Hz**. Smaller excitation amplitudes permitted higher frequency. ECU readout frequency differs from actual value updates, and clocks drifted. Pp.9–11 discuss fit residuals and parameter uncertainty. A more complex thermodynamic model did not automatically provide reliable parameters. These results support operating-point-dependent identification, not a universal 0.4 s RPM pole.

### R10 — Nonlinear identified models

L'Erario et al., [Modeling, Identification and Control of Model Jet Engines for Jet Powered Robotics](https://arxiv.org/abs/1909.13296), version 5, 2020, §§IV–V/Table IV: P100-RX and P220-RXi experiments and nonlinear second-order thrust identification. Momin et al., [Nonlinear Model Identification and Observer Design for Thrust Estimation](https://arxiv.org/abs/2205.08330), 2022, §II/Table III: **P160-RXi-B/P220-RXi**, useful for comparing throttle/thrust shapes, not matched P100 parameters. Both motivate fitting multiple transitions and preserving held-out data. Their coefficients are experimental-system-specific, not plug-in aircraft laws.

### R11 — P100 instrumentation and independent runs

Wright et al., [Small jet engine reservoir computing digital twin](https://arxiv.org/abs/2312.09978), 2023 preprint, §§III.B–D: P100-RX thrust sampled at **1000 Hz**, ECU at **10 Hz**, additional temperatures at **25 Hz**. Calibration and command instrumentation are described. The study evaluates separate runs as well as within-run splits. Its achieved prediction errors do not establish the simulator's accuracy, and plotted traces alone do not identify the exact command latency or the historical Avanti ECU setting.

### R12 — General engine equations and controller limitations

[NASA Glenn thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) supplies inlet/outlet momentum and nozzle pressure thrust. [NASA corrected airflow](https://www.grc.nasa.gov/WWW/K-12/airplane/wcora.html) distinguishes total pressure and total temperature. [NACA TN 2091](https://ntrs.nasa.gov/citations/19930082903), 1950, treats spool dynamics. [NASA/TM-2013-217821](https://ntrs.nasa.gov/citations/20130013439), 2013, explains engine-control constraints. These establish general mechanisms; they do not supply P100 maps, surge margins, casing torque or installation losses.

### R13 — Fuel supplier properties

[ExxonMobil Jet A-1 properties](https://www.exxonmobil.com/en/aviation/products-and-services/products/exxonmobil-jet-a-1), product-property table: density **775–840 kg/m³ at 15 °C**, minimum net heat of combustion **42.8 MJ/kg**. This range is not the actual density of an RC oil/fuel blend. R1's paired consumption units imply **0.800 kg/L** for its tabulated conversion; that is not a universal measured blend density. Use measured mixture density/temperature when converting a physical run.

## Current implementation findings

Inspection reference HEAD: `455b68367ba5036b2c07e3e00d8d9600cea914a8`. Findings are about the following bytes, not a guarantee that concurrent HEAD remains unchanged.

| File | SHA-256 |
| --- | --- |
| `app/physics/turbine.gd` | `6f7cb1a5dcd4c757c6b8663fde7b1f921db51c45161facb39664c41dae5f9662` |
| `app/sim/flight_session.gd` | `deb781c8980a1d8d601dbb7b2249f8f80207212c4901bda94c3e981bdbe0820b` |
| `app/sim/simulation.gd` | `edaf012561e96714ca4ddb05b07fdbbb9eb9f3faed930ce4fafe265d3e5f7c6c` |
| `research/avanti-s/av06/inputs.json` | `3894641aa5cbaA0d4d6f588f77922876f1b73b680ceb0213995c9e66ee901369` |
| `app/data/aircraft/sebart_avanti_s_a200.json` | `d5a3eed4cec571cc145bc09f84af9bc2b83d74fe08cfc43e5325585a0f2c86d4` |

1. `Turbine.spool_step` advances RPM before body RK4; its schedule-limited branch holds the current rate over the tick. Body loads and rotor momentum use sampled RPM. Continuous callbacks already exist for other propulsion/ground state.
2. `engine_running == false` bypasses spool advancement and publishes zero RPM. There is no gameplay turbine ECU start/stop sequence. Throttle zero while running commands idle.
3. `fuel_flow` has no current runtime flight-state consumer. Fuel is a fixed **1.28 kg** inventory item; `prescribed_fuel` explicitly promises fixed wet mass. Current inventory sums to **11.705089 kg**; subtracting that fuel gives **10.425089 kg** of this virtual dry build, not a measured airframe. The **3.2 L** capacity is dealer-derived; tank position/envelope are estimates. The inventory mentions a hopper, but does not define a separate simulated fuel volume.
4. Static intermediate thrust, intermediate fuel flow, ram corrections, 0.92 installation factor, rotor inertia/sense and spool schedules retain fitted/derived/estimated assumptions. The 0.4 s governor source now correctly qualifies its small-signal interpretation.
5. Thrust/airflow use density scaling; no dynamic EGT, hot core, pump, supply battery, start fuel, tank empty event or inlet-distortion model exists. The below-idle hot-thrust table must not become an OFF-state law without new evidence.
6. Source/current-contract checks were performed; no simulation tests were run for this documentation-only research. Existing passing tests establish their recorded software scope, not fresh physical validation.

## Download fingerprints

These hashes support re-fetch comparison; they do not claim permanent preservation of publisher URLs. Future implementation evidence must retain lawful source identity and page extracts under the project's existing provenance policy.

| Publication | PDF pages | SHA-256 |
| --- | ---: | --- |
| JetCat catalog 2017 | 39 | `1f085e7067a090602525388fab9a04fd25b365985252670699689bd49f9b26b5` |
| JetCat RX August 2011 | 72 | `abbe031b5f6034ed92fa7cce98823b87d738bddfab407a5b4e9b64eb2a3757e9` |
| JetCat RX/RXi March 2015 | 71 | `4d1760a571975535bc79964fc6730f99de61e33a317b24495d94549d39231992` |
| JetCat P250 V1-4, 02/2023 | 11 | `bca3946c2f7518cbec3fd1b971ded8d440570388427d841f6f23a23af7398640` |
| Xicoy v1.5/2024 | 40 | `d34afb0d2820ae3e0bb74b7b8df19304b0c93f7e8e79d7e4c4e87ce52cc7cbe6` |
| Many / DGLR 550281 | 15 | `6f1e519f62fe1b9e2b79f8255dbf70da31bc95a584751a377abf846d1c5b4191` |
| L'Erario / arXiv 1909.13296 | 8 | `6b20ed2f3f5229e605cb8e9f4b818d7d0b4128a700cd2f87a6b454299927ec8e` |
| Wright / arXiv 2312.09978 | 10 | `c948d44d51b92bfb0448f9349f4dbb59ea8944217e42a57df01071f9a5cae678` |

## Unresolved evidence

No matched installed-A200/P100-RX data set was obtained for thrust versus airspeed, large steps with identified response presets, fuel-cut rundown, below-idle flow, tank metrology, hot starts, mounting torque or rotor direction. No public dataset found in this review closes those gaps. Do not replace missing evidence with another engine's timing, a forum anecdote, an unqualified video or a model's own predicted trace.
