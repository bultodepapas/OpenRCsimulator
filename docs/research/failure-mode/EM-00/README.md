# EM-00 — RC failure and emergency-training research

**Research date:** 2026-10-13. **Scope:** primary-source review, existing repository audit and proposed model/UX implications. No aircraft experiments, new runtime functionality or physical validation were performed. The [failure-mode plan](../../../plans/failure-mode.md) owns the design, phases and acceptance criteria.

## Method and evidence levels

Manufacturer manuals were used to distinguish hardware mechanisms. NASA publications inform damaged-aircraft modeling requirements; full-scale training/investigation documents are used only where their limits are explicit. RC event reports support the possibility of exceptional one-wing recoveries, not a success rate. RealFlight documentation supplies product precedent, not an implementation to copy.

Source availability was checked on the research date. Publication/revision dates below belong to the documents rather than search-engine crawl labels. Page numbers are printed numbers unless marked PDF. Web-indexed excerpts and locally extracted text were checked for context before use. No incidence statistics were inferred from videos, warning labels or the number of search results.

Five official PDFs were downloaded unchanged for local review under ignored `tmp/failure-mode-research/`. PyMuPDF 1.28.2 extracted native text and enumerated every page; no encryption was reported. Representative decision pages were rendered and inspected: FAA 18-11, RealFlight printed p.68, AR410 p.9, Xicoy pp.31/35 and ESC PDF p.4. RealFlight PDF pages 1 and 268 have no extracted text; relied-upon pages 69–74 have text. The other four PDFs have no empty text pages. No OCR-derived measurements or quantitative reading of a video were used.

Futaba's web extraction has corrupted glyphs in parts of its text; its clear S.BUS parameter section supports qualitative behavior only here. Other manuals were read through browser PDF text with the cited section limits. Third-party documents and video frames are not redistributed as repository assets.

## Primary source register

### R01 — RealFlight failure-mode precedent

[RealFlight 9.5 official manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dw6b391a4f/Manuals/RealFlight-9.5-Manual.pdf), printed pp.67–72, PDF pp.69–74. The product provides adjustable occurrence, selectable fault types, notification timing and on-command injection. Its list includes engine failure, radio problems, stuck servos and structural integrity.

**Use:** frequency, eligibility, notices and repeatable practice are understandable simulator concepts. **Limit:** the manual does not define OpenRC's per-flight probability, physical mechanisms, statistical rates or source-code architecture. Older FM/PCM examples must not become a generic modern receiver model.

### R02 — Receiver signal loss versus brownout

[Spektrum DXS and AR410 manual, SPM1010](https://www.spektrumrc.com/on/demandware.static/Sites-spektrum-us-Site/Sites-horizon-master/default/Manuals/SPM1010-Manual-EN.pdf), p.9. SmartSafe uses its bound throttle setting and holds the other channel outputs; an alternative stores preset outputs. The manual states that receiver operation and failsafe are unavailable below 3.5 V until supply recovers.

**Use:** separate missing signal, powered failsafe and loss of supply; model output profiles. **Limit:** this threshold and behavior belong to AR410, not every receiver. A preset output is not automatic aircraft stabilization or a guaranteed landing.

### R03 — Servo hold, overload protection and offset

[Futaba 12K instruction manual](https://futabausa.com/wp-content/uploads/2018/09/12K.pdf), S.BUS servo parameters, pp.71–72. Certain supported servos can switch output off under overload, select hold behavior on input loss and change neutral offset; available functions depend on servo type. A large offset restricts travel on one side.

**Use:** distinguish electronic output behavior, physical jam, offset and available travel. **Limit:** it does not establish a free surface's equilibrium angle after power/output loss, generic time-to-failure or the servo installed in a stock OpenRC aircraft. Do not adopt parameter values from garbled extraction or apply this feature to an unsupported servo.

### R04 — Servo load and supply dependency

[Spektrum DX8 manual](https://www.spektrumrc.com/prodinfo/files/spm8800-manual_en.pdf), p.36, Servo Precautions. Binding/stalling can increase current drain; the manual also discusses vibration/loose linkages and surface buzz/flutter affecting servo feedback components.

**Use:** a future servo-load → supply-sag → receiver-outage cascade has a plausible physical basis. **Limit:** battery/regulator/servo data are needed to predict it. The manual supplies no general event probability or fitted electrical/thermal model. A scripted power outage is not proof of a voltage-driven brownout law.

### R05 — ESC power reduction, cutoff and signal loss

[EFLA1040 completion guide](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/EFLA1040-Completion%20Guide-EN.pdf), PDF pp.2–4. It describes selectable low-voltage power reduction versus hard cutoff, brake/freewheel options, temperature protection and motor cutoff after two seconds of missing throttle signal.

**Use:** separate drive torque, rotor motion, control-bus supply and receiver signal. **Limit:** these timings and thresholds describe this controller; they do not calibrate Timber's unspecified losses or establish that every ESC preserves receiver power. Initial generic power-limit exercises must be labeled as such.

### R06 — Glow-engine response and stop behavior

[O.S. 120AX manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/2stglow/120AX_EG.pdf), starting/idle-adjustment instructions and chart, PDF p.3. The manual distinguishes mixture/idle problems, engine stopping and recovery of full power after a throttle change. It identifies throttle trim as part of carburetor control.

**Use:** combustion loss, poor response and throttle linkage are distinct candidates. **Limit:** this is a particular two-stroke engine, not a universal 2T/4T/gas profile. Prefer the [NITRO manufacturer's source record](../../glow-engines/NITRO-00/README.md) for the actual installed 55AX/FS-64V variants. An electronic trim command cannot independently move a physically jammed carburetor linkage.

### R07 — Turbine failsafe and conditional restart

[Xicoy TurboJet user manual](https://www.xicoyturbines.com/assets/files/XicoyTurbojetManual_EN.pdf), **version 1.5/2024**, pp.31 and 34–35. Its configured failsafe signal commands idle before shutdown if it persists for two seconds. Autorestart is disabled by default and checks radio validity, engine indications, battery and other faults. The manual describes roughly 10–15 seconds to recover pre-shutdown power, conditional on successful restart.

**Use:** explicit ECU states, signal interpretation, conditional relight and delayed power return. **Limit:** this is not the historical JetCat installation. A claim that this cited revision uses a universal 0.5 s + 1.5 s loss-of-signal sequence was not supported by the reviewed failsafe page and is not adopted. Aircraft suitability and flight conditions are not guaranteed by the restart function.

### R08 — Selected JetCat configuration and earlier repository research

The [AV-18 source review](../../turbine-realism/AV-18/README.md) identifies the simulator's **2017 P100-RX, non-BL** and compares ECU revisions. Direct sources include the [2017 JetCat catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf) and [RX/RXi manual, March 2015](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_RXi_120218.pdf).

**Use:** retain AV's canonical source/installation distinctions and planned stop/fuel/restart integration. **Limit:** these PDFs were not independently re-extracted during EM-00; use the dated AV review's page references, hashes and limitations. No Xicoy or modern JetCat feature is imported merely because nominal thrust is similar.

### R09 — Full-scale emergency-control guidance and its RC limit

[FAA Airplane Flying Handbook, FAA-H-8083-3C, Chapter 18](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/19_afh_ch18.pdf), pp.18-2 and 18-10–11; available through the [official handbook page](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/airplane_handbook). It discusses emergency landing judgment, asymmetric flaps and elevator failure. Independent trim mechanisms can help some control failures; a jam is a different condition.

**Use:** make the simulated training mechanism and remaining controls explicit; avoid teaching “trim fixes every elevator failure.” **Limit:** full-scale cables, trim tabs, flaps, landing distances and occupant-protection procedures are not interchangeable with RC digital trim, servo linkages or this fleet. No full-scale performance number is copied into an RC lesson.

### R10 — Existing open-source actuator modeling vocabulary

[JSBSim FGActuator reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGActuator.html), checked 2026-10-13. It documents lag, rate limits, deadband, hysteresis, bias and travel limits, with separate failure modes including stuck, zero and hardover.

**Use:** reuse clear physical distinctions and known numerical concerns. **Limit:** adopting vocabulary does not require integrating another flight solver or establish actuator calibration. OpenRC's healthy dynamics must retain their own compatibility proof. No source code is copied by this planning change; any future code reuse needs license review and an exact source revision.

### R11 — Damaged-body reference frames

[Bacon and Gregory, General Equations of Motion for a Damaged Asymmetric Aircraft](https://ntrs.nasa.gov/citations/20070030307), NASA/AIAA, **20 August 2007**. The publication concerns motion referenced away from a body's changed mass center and compares a damaged transport case with standard simulation equations.

**Use:** a mass/CG change is a state-reference issue as well as an inertia update. **Limit:** EM-00 reviewed the NASA record/abstract; it did not reproduce the paper's numerical cases. The plan's proposed separation invariants require an independent derivation and tests in OpenRC coordinates, not a claim of NASA-validated RC flight.

### R12 — Aerodynamic consequences of area loss

[Gautam H. Shah, Aerodynamic Effects and Modeling of Damage to Transport Aircraft](https://ntrs.nasa.gov/citations/20080034656), **18 August 2008**, AIAA-2008-6203. NASA describes wind-tunnel investigation of partial/total wing, horizontal-tail and vertical-tail area loss and the added modeling issues from asymmetry.

**Use:** loss of area and stability/control coupling need a damaged aerodynamic model. **Limit:** the record/abstract was reviewed, not the underlying datasets. Transport coefficients and recoverability boundaries cannot be transplanted into small aerobatic RC models. Section loss is not equivalent to a servo jam or a scalar reduction in total lift.

### R13 — Flutter and breakup are structural phenomena

[NTSB Safety Alert SA-099, Overspeeding Risks Flutter and In-Flight Breakup](https://www.ntsb.gov/advocacy/safety-alerts/pages/sa-099.aspx), **29 April 2025**. It discusses structural/aerodynamic coupling and accident examples involving overspeed and control-surface mass/balance changes.

**Use:** keep an injected wing-loss exercise separate from predicting when real structure fails. **Limit:** this is full-scale safety/investigation evidence, not RC material properties or a universal breaking speed/G threshold. It cannot validate random surface jitter as a flutter simulation.

### R14 — Deterministic RNG scope in Godot

[Godot 4.7 RandomNumberGenerator](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html) and [seed/state guidance](https://docs.godotengine.org/en/4.7/tutorials/math/random_number_generation.html), checked with both official pages and Context7. Instance seed and state support repeatability; changing seed resets state. The generator implementation is not a cross-version contract. `randf()` includes endpoints, while `randi_range()` supplies inclusive integer bounds.

**Use:** private streams, explicit 0/100 handling, lossless saved state, frozen resolved events and recorded engine/build identity. **Limit:** seeded selection does not prove deterministic rendering, cross-platform trajectories or recovery under different human inputs.

### R15 — Original account of an RC one-wing landing

[Electricdan's account of Todd Bridges at the Tucson Aerobatic Shootout](https://electricdan.wordpress.com/2009/10/22/tucson-aerobatic-shootout-amazing-one-wing-landing/), **22 October 2009**, states that the author filmed the incident and embeds [the associated video](https://www.youtube.com/watch?v=Gh52tyilpr4). The account describes losing the left wing following a low, fast snap and returning in knife-edge flight to land.

**Use:** direct filming provenance supports treating exceptional recovery as possible rather than hardcoding inevitable immediate death. **Limit:** direct video fetching was throttled during final review; the text account and original embedding establish the citation. No playback-derived dimensions, exact detached area, model specification, airspeed, thrust-to-weight ratio or success probability is asserted. An expert demonstration is not an ordinary-aircraft training envelope.

### R16 — Independent RC event report

[Jennifer Orebaugh, XFC 2013, Model Aviation](https://www.modelaviation.com/xfc2013), AMA event coverage of **14–16 June 2013**, with full coverage referenced to the November 2013 issue. The report describes Manuel Santos losing a wing in freestyle and landing the airplane; it later notes use of a backup model.

**Use:** a second contemporaneous RC event supports the requested scenario's relevance. **Limit:** no original video was verified for this case, and the report does not provide a physical model, quantified damage or a denominator of failed attempts. Neither case proves that only a particular aircraft class can recover.

## Download fingerprints

These identify the bytes reviewed, not bundled simulator resources. The download URLs above remain the source links; local scratch files are intentionally not documentation dependencies.

| Document | PDF pages | SHA-256 |
| --- | --- | --- |
| FAA Chapter 18 | 23 | `0fac959a0b0ebd1109cdee797eb83eaaf77a76f2f92660056cbef30e3cde03a5` |
| RealFlight 9.5 manual | 412 | `1fc37ced14d090fb338f3b4c771cfddcc95b07450aa0f0ad3bb55755a4fad99c` |
| Spektrum DXS/AR410 | 17 | `1539274f1b78ff24f8d95aaf9c927baa99ad7254fdd48ae47986f56040f05906` |
| Xicoy 1.5/2024 | 40 | `d34afb0d2820ae3e0bb74b7b8df19304b0c93f7e8e79d7e4c4e87ce52cc7cbe6` |
| EFLA1040 guide | 7 | `4cd77ae71eef8bd9a7e0fa16c3e36ee71f09f78e7de9de71df9e01c0c2bbe852` |

## Repository audit findings

HEAD observed during review was `7265b2e0dc10bfcc7f220544998e21be28159380`, with other tracks' modified/untracked files. This is not a pristine-checkout test result. Discovery used the existing `C-DEVELOPMENT-OpenRCsimulator` graph. Stale snippet spans required current-source verification; no reindex or application mutation was needed.

The shared checkout advanced to `6841da28` during final review. Current-source readback then found initial Natural Random runtime files and launch integration: `ScenarioConfig` has a closed NR-only v1 record; `app_root.start_flight(request)` interprets nonempty requests as NR and requires that screen; `main.bind_scenario()` verifies the matching accepted flight. The plan was updated to require explicit launch-mode/modifier handling instead of treating that parameter as a generic failure request. This observation does not claim those concurrent changes passed their owners' acceptance gates.

| Seam | Observed constraint | Design consequence |
| --- | --- | --- |
| `app/sim/flight_session.gd` | Base aux contains engine RPM plus roll/pitch/yaw servo positions; actual surfaces feed loads. | One-side control faults need independent physical state and a shared topology extension. |
| `app/physics/control_surfaces.gd` | Left/right ailerons derive from one roll value; elevator/rudder have one logical output each. | Do not confuse two rendered hinges with independent servos or split-tail loads. |
| `FlightSession.flown_commands()`, trim/reset | Trim is added to shaped commands; healthy reset initializes servo state at trim. | Off-trim lessons must be applied after start preparation; jam cannot be canceled by a trim command. |
| `app/sim/simulation.gd` | Tick evaluation is validated before acceptance; RK stages share prepared state and failed steps restore last-valid simulation state. | New scheduler/ledger/buffers must join rollback and commit, not mutate irreversibly in `_pre_step()`. |
| Session/native checkpoints and trace | Versioned fingerprints/layouts and fixed trace conventions already exist. | Explicit schema/identity migration and sparse event logging; no unrecognized fields or loss of fault state on restore. |
| `AIRCRAFT_CONTRACT.md` | Conventional controls; capability-specific energy; structural part loss is not an active v2 feature. | Keep the training request outside aircraft source; coordinate actual new physical modules with AS and propulsion owners. |
| `app/render/overlays/warnings_bar.gd` | Telemetry warning list is not a failure event ledger and is subject to HUD visibility. | The notice preference needs its own clear presentation contract, independent of physical state. |
| CR/NR/UI plans | Damaged flight and broader menu/scenario work coexist with implemented foundations. | Reuse their seams, keep owner gates separate and preserve Natural Random's ordinary fault-free policy. |

The detailed integration map is authoritative in the [plan](../../../plans/failure-mode.md#3-current-repository-and-integration-seams). This report intentionally does not duplicate every proposed file or step.

## Questions the evidence does not answer

| Missing evidence | Required follow-up before the corresponding claim |
| --- | --- |
| Relative incidence of RC servo, engine, radio and structure faults | A defined fleet/exposure dataset. Until then all occurrence/category weights are training choices. |
| Exact servo/channel/wiring layout of every shipped configuration | Source inventory/manual/model-binding audit and explicit authored topology. |
| Surface behavior after linkage disconnect or unpowered servo | Hinge moments, friction/backdrivability, servo/gearing and linkage geometry; bench or defensible surrogate law. |
| Maneuver envelope with one/both ailerons or one elevator half disabled | Per-aircraft control-authority/energy analysis and pilot trials, with both sides and relevant weather/starts. |
| Actual stop/relight performance for each engine/ECU | Installation-specific transients and lifecycle evidence from AV/NITRO/EL owners. |
| Endurance of prescribed-fuel/fixed-voltage configurations | Accepted finite-energy model and actual capacity/flow/voltage behavior. |
| Recoverability after panel separation | Damage geometry, full mass/inertia, asymmetric aero/high-angle side force/propwash and named-condition qualification. |
| Strength or flutter thresholds | Structural properties and dynamic evidence. Injected damage can be developed without pretending these are known. |
| Learning benefit | Observed user/pilot practice results; a technically correct effect alone does not establish transfer of skill. |

## Planning conclusions

Begin with standard interfaces and healthy-path parity, then deterministic control/propulsion mechanisms, complete lifecycle state, random selection and player UI. Add receiver faults and energy-dependent lessons through supported subsystem contracts. Structural separation is a distinct physics dependency, not a more dramatic toast.

The ordinary/catastrophic split controls the admitted practice envelope; it cannot guarantee the outcome of a maneuver. One-wing recovery remains an intentionally available possibility to investigate across aircraft, supported by limited anecdotal RC evidence and constrained by a model that must still be qualified.

No new art/audio was needed for this investigation. Existing simulator resources and freely accessible primary manuals supply the planning material. Future external assets or code require suitable redistribution terms; free access to a manual/video does not imply permission to bundle its content.
