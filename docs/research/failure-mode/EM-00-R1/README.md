# EM-00-R1 — Real RC airplane failure library and incidence evidence

**Research date:** 2026-10-27. **Step:** EM-00-R1, revision of the [EM-00 source review](../EM-00/README.md) for the emergency-training track. **Scope:** real fixed-wing RC failures (common, uncommon, catastrophic) that a random-failure and emergency-training system could model: mechanism, in-flight symptoms, simulation consequence, pilot response, recoverability and any incidence evidence. No runtime change, flight test or physical validation was performed. The [failure-mode plan](../../../plans/failure-mode.md) owns design and acceptance.

**Method.** Manufacturer manuals, association rules, investigation reports, magazine articles and academic reliability work were opened and read; search-engine snippets were used only to find documents. PDFs were text-extracted with `pdftotext` (poppler) and page-located per page. YouTube facts come from the uploader-supplied title, date and description embedded in each watch page, not from video playback. The 40 published AAIB record-only UAS lists (January 2020 to June–July 2026) were pulled through the GOV.UK content API and every model-aircraft row was classified by hand ([§4.2](#42-aaib-record-only-model-aircraft-rows-2020-to-2026)). Sources, hashes and the row classification are in [sources.json](sources.json). Local copies live in the ignored `references/failure-mode/` or in the existing reference folders named in the manifest.

**Evidence levels (Ev).** **M** official document: manufacturer manual, association rulebook, investigation report. **R** report: magazine or event article, academic study, documented first-hand account with provenance. **F** forum or single uploaded video, uncorroborated. **E** engineering estimate, with no direct source found.

**Limits.** No source gives hobby fixed-wing failure rates per flight or per hour. Every frequency in this note is either a stated breakdown of a different population or a labelled training-policy estimate. Videos and forum threads support possibility, not probability. Manufacturer thresholds belong to the named product. Pages are PDF pages unless marked “printed”.

## 1. Main findings

1. **Airborne power, not RF, is the leading hardware cause in manufacturer and practitioner sources.** Spektrum states that inadequate receiver power systems “have become the number one cause of in-flight failures” (R27). A hobby-shop author ranks battery, switch and receiver failure, in that order, after pilot error (R20). A University of Minnesota reliability study of an Ultra Stick 120 UAV ranks the failsafe switch, receiver, avionics battery, BEC and tail servos as its highest-priority catastrophic components (R21). Pilots report many of these events as “lost signal”; the BMFA notes the temptation to blame interference (R72).
2. **The failsafe default is a setup trap.** FrSky receivers hold the last position if failsafe is never set, and a rebind disables it (R28). The BMFA says nearly all 2.4 GHz equipment defaults to hold and that the result can be a flyaway or high-throttle impact (R25). Spektrum warns that a wrongly set failsafe can advance to mid or full throttle (R26). ExpressLRS PWM receivers default to 1500 µs except output 3 (R29), so a throttle on another output fails to mid-throttle.
3. **Receiver reconnect after brownout is a per-receiver datum**, from about 0.04 s (Spektrum DSMX, R27) through under 1 s (Futaba R608FS measured, R31; OrangeRx R617XL, R30) to several seconds (early DSM2, D6-SRV-00). During reconnection, analog servos may coast to their extremes (R30).
4. **Electric power faults are mostly reductions, not stops.** Spektrum Avian ESCs limit output to 60 % at low voltage and above 110 °C, and cut the motor 0.25 s after throttle-signal loss (R35). BLHeli_S steps power to 75/50/25/0 % as temperature rises past its threshold (R38). Hobbywing reduces output above about 110 °C (R36). Castle offers hard, soft, RPM-decrease or pulsing cutoff (R37). A desync stops or stutters the motor after a quick throttle increase at low RPM (R38).
5. **A disconnected surface floats; it does not hold its position.** The University of Minnesota research platform analysis lists bias, oscillation, floating, stuck and hard-over as servo fault modes. It names hard-over and floating as “two of the more common control surface impairments” (R22). Stripped gears can either free the surface or lock it (R22). Clevis, horn and hinge failures also free it (R45–R47).
6. **Prop and installation failures cascade.** A blade that parted on a giant-scale P-40 produced vibration that “rendered the servos powerless” (R51). Prop imbalance loosens screws and foams fuel, so the engine runs lean or quits (R45). Glow engines quit at idle with a worn plug and on throttle-up after a rich idle (R42).
7. **Structural loss is reported mostly as unrecovered.** In the AAIB sample, 4 of 65 model-aircraft rows are wing or tail separations, all ending in a crash or a lost model (R19). Five successful one-wing landings were found in videos or reports; two were by competition freestyle pilots at invitational events. Every account that describes the technique used knife-edge flight, and both that describe the trigger were snap rolls ([§5](#5-wing-loss-and-one-wing-recovery-case-file)). No denominator exists.
8. **The only official hobby occurrence sample is dominated by link/unresponsive events and loss of sight.** Of 65 AAIB model-aircraft rows, 21 are link-lost or unresponsive, 16 are loss of sight or weather, and 5 each are pilot handling and single-channel loss (R19). The sample favours flyaways and third-party risk; deadstick landings almost never appear.
9. **Military and civil UAS breakdowns do not transfer directly but point the same way.** OSD: power/propulsion 37 %, flight control 26 %, human/ground 17 %, communications 11 %, miscellaneous 9 % for Predator, Pioneer and Hunter Class A mishaps (R17). Civil RPAS: equipment problems 64 % of cases with a known cause (R18).
10. **EM-00 R07 needs a correction.** The Xicoy manual's diagnosis page does state the 0.5 s idle plus 1.5 s shutdown failsafe sequence (R50, PDF p.40), although its failsafe page does not ([§6](#6-contradictions-dead-ends-and-open-questions)).

## 2. Source register (continues EM-00 R01–R16)

Each entry: claim used → applicability and limit. D6-SRV-00 identifiers refer to the [servo-load source manifest](../../servos/D6-SRV-00/sources.json). R03–R05, R07, R09 and R12 are reused from EM-00.

### Incidence and reliability

| Ref | Source | Claim used | Applicability / limit |
| --- | --- | --- | --- |
| R17 | [OSD UAV Roadmap 2002–2027](https://www.nasa.gov/centers/dryden/pdf/111759main_DoD_UAV_Roadmap_2003.pdf), Dec 2002, §5.2, printed pp.48–51, Fig. 5.2-2 (extracted from OSD's 2003 UAV Reliability Study) | Mishap causes: power/propulsion 37 %, flight control 26 %, communications 11 %, human/ground 17 %, miscellaneous 9 %. Basis: nearly 100,000 h over a combined 36 years of operation since 1986; Class A mishap rates | Military UAVs with autopilots and ground stations; Class A only. Ratios, not hobby rates. |
| R18 | [Wild, Gavin, Murray, Silva, Baxter, JATM 9(2):157–168, 2017](https://jatm.com.br/jatm/article/view/701), doi 10.5028/jatm.v9i2.701, printed pp.161–165 | 152 civil RPAS occurrences 2006–2015: system/component failure 63 %, loss of control in flight 14 %; equipment problems 41 % (64 % excluding 35 % unknown), human factors 15 % (23 %). Just under a third of equipment problems involved lost link. Example case: engine-mount failure | Convenience sample; type (fixed/rotary) often unrecorded; not hobby-specific. |
| R19 | [AAIB record-only UAS investigation lists](https://www.gov.uk/government/publications/aaib-record-only-uas-investigations-reviewed-april-may-2026), 40 lists Jan 2020–Jul 2026; GOV.UK content API | 65 model-aircraft rows hand-classified ([§4.2](#42-aaib-record-only-model-aircraft-rows-2020-to-2026)) | UK reported occurrences; pilot-supplied, “accuracy cannot be assured”. Biased to flyaways and third-party risk. |
| R20 | Apostolico, *Model Aviation* (MA) [Nov 2009, pp.46–51](https://library.modelaviation.com/article/crashing-not-option-200911) and [Aug 2010, pp.38–44](https://library.modelaviation.com/article/defensive-rc-flying-201008) | After pilot error: battery, switch and receiver failure, in that order; setup error is the chief cause; unset failsafe leaves full throttle; under-glued giant-scale hinges caused a crash | Hobby-shop experience, giant scale; ordinal and uncounted. |
| R21 | [Reimann et al., *UAV for Reliability*, UMN AEM 4331, 19 Dec 2013](https://dept.aem.umn.edu/~SeilerControl/Papers/2013/ReimannEtAl_13TR_Part1UAVforReliability.pdf) | Ultra Stick 120 FMEA/FTA: predicted 2.17 catastrophic failures per 100 h (handbook rates × 50 for servos, × 25 for other hobby parts). Highest-priority catastrophic (1A) components: failsafe switch, receiver, avionics battery, BEC, rudder and elevator servos. A surface stuck outside its trim range is catastrophic. | Predicted rather than observed; student design report. |
| R22 | [Freeman, PhD thesis, U. Minnesota, Nov 2014](https://dept.aem.umn.edu/~SeilerControl/Thesis/2014/Freeman_14PhD_ReliabilityAssessmentForLowCostUAVs.pdf), printed pp.23–24 and 73 | Servo fault modes: bias (common; gear slippage, bent linkage), oscillation/deadband, floating (free about hinge under aerodynamic moments, channel authority lost), stuck/hard-over (broken linkage or gears). Hard-over and floating are “two of the more common” | Ultra Stick 120 “Ibis” research UAV with hobby-grade servos; qualitative. |
| R23 | [Venkataraman, Seiler, Lukátsi, Vanek, 2017, author copy](https://dept.aem.umn.edu/~SeilerControl/Papers/2017/VenkataramanEtAl_17JA_ReliabilityAssesmentOfActuatorArch.pdf) | Hobby servos have failure times “on the order of thousands of hours”; a Futaba hobby servo (citing Murtha 2009) marks the low end of a 500–8000 h MTBF range | MTBF is cited, not measured here. |
| R24 | Orr, [“Receiver voltage”, MA Aug 2014](https://www.modelaviation.com/receiver-voltage) | One battery, switch harness and connector are single points; failures are typically mechanical connections; his tested receivers dropped out around 2.5–2.7 V; servo load causes dips; do not exceed BEC rating | Author bench tests; receivers of that time. |

### Radio, receiver, transmitter and airborne power

| Ref | Source | Claim used | Applicability / limit |
| --- | --- | --- | --- |
| R25 | [BMFA Handbook, Annex B §3.12 Failsafes](https://handbook.bmfa.org/annex-b/3-radio-control-and-you), accessed 2026-10-27 | Powered models: failsafe must cut engine to at least idle. Nearly all 2.4 GHz equipment defaults to hold, so a lost signal means “throttle and control lock-on”. Rebinding may restore defaults. Test before each session. Electric: cut motor. Gliders: spoilers or crow. Turbines: idle failsafe and manual fuel shutoff | UK association rule; revision date not shown. |
| R26 | [Spektrum DX6e manual](https://cdn.shopify.com/s/files/1/0036/2115/8947/files/dx6e.pdf), Feb 2019, PDF pp.2, 12, 22–23, 27 | SmartSafe, Hold Last, Preset failsafe; a wrong failsafe “might advance to mid or full throttle”; rebind after setup; battery alarm; inactivity alarm; throttle-cut switch; ice and wind can cause loss of control | Spektrum product family. |
| R27 | Spektrum AR6335 manual (D6-SRV-00 `SPEKTRUM-AR6335`), PDF pp.3, 5, 8 | Power systems are the number-one cause of in-flight failures; ≥4.8 V under full servo load; reconnect about 0.04 s after brownout; ModelMatch refuses the wrong model memory; not for full carbon fuselages; a 10-minute flight typically has < 50 frame losses and no holds | One DSMX receiver. |
| R28 | [FrSky X8R manual](https://www.flyingtech.co.uk/wp-content/uploads/2021/03/X8R.pdf) (distributor copy, PDF dated 2015) | If failsafe is not set, it holds the last position, so the model may fly away; re-binding disables failsafe | ACCST X8R. |
| R29 | [ExpressLRS PWM receivers](https://www.expresslrs.org/hardware/pwm-receivers/) and [Model Match](https://www.expresslrs.org/software/model-config-match/), accessed 2026-10-27 (PWM page shows an unlabelled 9 Sep 2024 date) | Failsafe after link quality 0 or 1 s without a valid packet. Defaults are 1500 µs on all outputs except output 3 at 988 µs. No pulses at power-up before a transmitter connects. A Model Match mismatch blocks output | ELRS PWM firmware; the default throttle output is configuration-dependent. |
| R30 | [OrangeRx R617XL manual](https://www.flyingtech.co.uk/wp-content/uploads/2019/01/R617XL-.pdf), Nov 2018 (DSM2/DSMX-compatible, not Spektrum) | Signal loss < 1 s holds the last command, then moves to bound positions. Reconnect after brownout takes up to 1 s, during which “analog servos may coast to their extremes”. Counts holds; carbon and metal block signal | Third-party receiver. |
| R31 | [RC Model Reviews, FASST-compatible TFR8 review, part 2](https://mail.rcmodelreviews.com/fasst_compatible_review02.shtml), updated 11 Aug 2010 | TFR8 and Futaba R608FS recovered from power loss in “well under 1 second” | One reviewer's bench; numeric brownout voltages only in images. |
| R32 | Futaba R7008SB manual (D6-SRV-00 `FUTABA-R7008SB`) | Diversity antennas at 90°; in carbon fuselages, leave 30 mm of each antenna tip exposed outside | FASSTest receiver. |
| R33 | [E-flite Opterra 2 m manual EFL11150](https://horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/EFL11150-Manual-EN.pdf), Jun 2017, PDF pp.11–13 | AS3X becomes active after the first throttle advance. An incorrect control-direction test result can cause a crash: “DO NOT fly”. Oscillation is over-control; reduce gain | AS3X installation. |
| R34 | [E-flite Apprentice STS 1.5 m manual EFL3700](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/EFL3700-Manual-EN.pdf), 2019, PDF pp.2, 12, 14, 17, 22, 29 | LVC slows the model and pulses the motor. Failsafe is low throttle. Never fly with low transmitter batteries. Troubleshooting covers aft CG, damaged prop and binding faults. A malfunctioning GPS assist should be deactivated | SAFE trainer. |
| R35 | [Spektrum Avian Smart ESC manual](https://cdn.shopify.com/s/files/1/0424/5104/2453/files/Avian-Manual-EN_995b579c-48f3-4c81-bc8d-97138c2af403.pdf), Aug 2019 (hash-identical to the local copy), PDF pp.15–18 | > 110 °C: power limited to 60 %. LVC: output limited to 60 %. Throttle-signal loss over 0.25 s: immediate cut. Overload and over-current: cut. A damaged motor causes early LVC. Stutter above 60 % means thermal protection | Avian family only. |
| R36 | Hobbywing SkyWalker [V1 manual mirror](https://www.manualsdir.com/manuals/737937/hobbywing-skywalker-20a-skywalker-40a-skywalker-40a-ubec.html) and [V2 leaflet](https://cdn.shopify.com/s/files/1/0109/9702/files/SKYWALKER_V2_mini_Leaflet_EN.pdf) (2025) | Soft cutoff reduces output gradually; hard cutoff stops. Above about 110 °C, output is reduced. Throttle-signal loss: reduce at 1 s, cut after 2 s more. Start failure: cut after 2 s. Linear-BEC models list a maximum servo count that falls as cell count rises | Only that trend is used; the mirror's V1 table is garbled, so no per-model numbers are adopted. |
| R37 | [Castle Phoenix Edge quick start, P/N 095-0223-00, rev 03/2013](https://www.astramodel.cz/manualy/castle_creations/castle-edge_qsg.pdf) | LVC 3.0–3.4 V/cell (default 3.2). Cutoff types: hard, soft (default), RPM decrease, pulsing. Error codes include radio glitch, motor anomaly, over-temperature and excessive load | Edge family; mirror copy. |
| R38 | [BLHeli_S manual SiLabs rev 16.x](https://raw.githubusercontent.com/bitdump/BLHeli/master/BLHeli_S%20SiLabs/BLHeli_S%20manual%20SiLabs%20Rev16.x.pdf), Nov 2017 | Demagnetisation causes “motor stop or stutter upon quick throttle increase, particularly when running at a low rpm”. Thermal limits are 75/50/25/0 % at the threshold and +5/+10/+15 °C (threshold 80–140 °C). Stall protection waits for zero throttle. Disabling low-RPM protection raises sync-loss risk | BLHeli_S firmware. |
| R39 | Shaw, [MA Jun 2001, pp.81–82](https://library.modelaviation.com/article/safety-comes-first-224) | Receiver-pack negative lead worn through by vibration; no control; “dove into the ground at full throttle” | Single account. |
| R40 | Shaw, [MA Apr 1999, pp.83–87](https://library.modelaviation.com/article/safety-comes-first-201) | Servos oscillating around trim traced to old, dirty or corroded aileron extension plugs; a delta crashed after elevator failure | Two members' accounts. |
| R41 | Richardson, [“Flight Control Servo Balancing”, MA (undated web)](https://www.modelaviation.com/article/Flight-Control-Servo-Balancing) | Paired servos fighting cause buzz and up to 180 mA static per servo; one disconnected servo feels sluggish | Undated web article. |

### Engines, propellers, installation and kits

| Ref | Source | Claim used | Applicability / limit |
| --- | --- | --- | --- |
| R42 | [O.S. MAX-50SX/40–91FX manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf), PDF pp.3, 7, 8, 12 | A backfire can loosen the prop nut. Spinner slots can weaken blade roots. A disconnected throttle linkage can foul the prop. Tank top 5–10 mm above the needle valve. A worn plug makes the engine cut out at idle. Nylon props can throw a blade. A rich idle drops RPM or stops the engine on throttle-up; a lean one cuts out | Two-stroke glow family. |
| R43 | [Desert Aircraft DA-120 manual, 8 Jan 2018](https://www.desertaircraft.com.au/shop/files/attachments/17517/DA120_MANUAL_1-8-2018.pdf), printed pp.2–7 (table page references are printed) | Lean running fades RPM on long verticals and overheats. A hot carburettor is erratic. Overheated electronics fail intermittently. A loose plug cap or damaged shield causes RF noise. Ignition pack ≥5.0 V; wires break near connectors. Loose prop bolts shear. Air leaks lean the mixture. “This motor can stop at any time” | One gasoline engine. |
| R44 | [DLE-120 manual (Hobbico), 2014](http://manuals.hobbico.com/dle/dleg0120-manual.pdf), PDF pp.3–4, 6 | Lean running overheats. Vibration can break the shaft. Ignition installation can cause radio interference. Opto kill switch | One gasoline engine. |
| R45 | [Great Planes PT-20/40 Mk II manual v1.2, 2004](http://manuals.hobbico.com/gpm/gpma0116-0118-manual-v1_2.pdf), PDF pp.53–57 | Prop imbalance loosens screws and foams fuel so the engine runs lean or quits. Range-check failures: switch, battery, cell, antenna. Wheel-collar and steering flats. Rubber-band rule. Low rate for take-off. Flutter caution and causes list | Glow trainer kit. |
| R46 | [Top Flite giant P-51D manual](http://manuals.hobbico.com/top/topa0400-manual.pdf), Jan 2001, PDF pp.56–57 (IMAA code excerpts) | Mandatory manual kill switch. One servo per aileron and stabiliser half. Heavy-duty servos and hinges. Clevis lock nuts and keepers. Redundant batteries. Anti-glitch devices on long leads | Giant scale; code of that era. |
| R47 | Hangar 9 Ultra Stick 120 manual, 2003 (local copy under `references/ultra-stick-120/`; download URL not recorded), PDF pp.7, 9, 30, 37–41 | Tug-test CA hinges; clevis and wire keepers; threadlock against loosening | Kit manual. |
| R48 | Hangar 9 AT-6 manual HAN1925 (FUEL-00 `HAN1925`), PDF p.36 | The clunk must drop freely to the top of the tank when it is inverted | Kit manual. |
| R49 | Russell, [MA Feb 2009, pp.139–140](https://library.modelaviation.com/article/radio-control-pylon-racing-200902) | Saito 1.80 engines starved in turns once the tank fell below a level; a pump fixed it | Pylon racing. |
| R50 | Xicoy TurboJet manual v1.5/2024 (EM-00 R07, same hash), PDF pp.31, 35, 39–40 | “Never fly with the failsafe set to hold.” Shutdown codes LowRPM (bubbles, lack of fuel, batteries), HighTemp, Battery, Pump overload, RCPwFail. FailSafe: idle 0.5 s after signal loss, shutdown after a further 1.5 s | Xicoy ECU, not the simulator's JetCat. |
| R51 | de Vries, [MA Oct 1988, pp.48–49, 154](https://library.modelaviation.com/article/radio-control-giant-scale-77) | P-40 blade parted (glue joint); vibration rendered the servos powerless; 15° nose-down; lost. P-47 cowl came adrift into the prop | Giant scale. |
| R52 | Perry, [MA Jun 2026](https://www.modelaviation.com/article/new-people-and-technology) | Collet adapters loosened while running; vibration is the common thread for liberated props | Electric. |

### Structure, gear, mass and operation

| Ref | Source | Claim used | Applicability / limit |
| --- | --- | --- | --- |
| R53 | de Vries, [MA May 1998, pp.83–84](https://library.modelaviation.com/article/radio-control-giants-70) | Wing folded in the middle during a sharp pull-out; poorly bonded centre-section braces; vibration and fuel-soaked joints | Narrative, no named model. |
| R54 | Preston, [MA Jul 1985](https://library.modelaviation.com/article/safety-comes-first-66) | 1982 Virginia fatality: a previously repaired right stabiliser broke off in flight; power was lost | Police report as quoted. |
| R55 | [CHIRP DUASxxx3, BMFA report, 24 Aug 2022](https://chirp.co.uk/report/duasxxxx-3/) | Hatch popped open as an air brake: end-over-end tumble at about 150 ft; battery ejected | One pilot's analysis. |
| R56 | [AAIB Bulletin 10/2022, MA Scale F4 Phantom, AAIB-27831](https://assets.publishing.service.gov.uk/media/6321af5ae90e072ce3c633b6/MA_Scale_F4_Phantom__UAS_registration_n-a__10-22.pdf) | 6.4 kg turbine maiden flight: sluggish ailerons, growing up-trim, sudden veer and spin; cause undetermined. The club flies about 6,500 flights a year | Correspondence investigation. |
| R57 | [AAIB Bulletin 2/2022, Edge 540 G-EDGY](https://assets.publishing.service.gov.uk/media/6204f069d3bf7f3147a624b3/Edge_540_G-EDGY_02-22.pdf) | Full-scale: aileron hinge fatigue; right aileron detached during a roll. The aircraft felt heavy in roll; approach at 100 kt, not 80 kt; landed 2 min 20 s after failure | Out-of-domain analogue only. |
| R58 | Buckland, MA May 2016 (D6-SRV-00 `MA-BUCKLAND-2016-FLUTTER`) | Machine-gun flutter noise; slop is the main cause; servo, horn, wiper damage or disintegration | Sailplanes. |
| R59 | de Vries, [MA May 1989, pp.46–47, 157](https://library.modelaviation.com/article/radio-control-giant-scale-83) | A rudder hard-over was landed by slowing down and using full aileron. A single locked aileron: hold the other opposite, add a touch of rudder, slow down. One elevator half: use power for pitch. Author saw “only one true servo hard-over” | Giant scale. |
| R60 | [ArduPilot forum, Pandolfi, 7 Nov 2021](https://discuss.ardupilot.org/t/auto-takeoff-error/77717) | Untied battery slid aft during climb-out; pitch-up; tied down on next flight and climbed normally | Forum (F). |
| R61 | [Robart 176 Pressure Guard, rev 11-14](https://cdn.shopify.com/s/files/1/0339/0713/files/176_Pressure_Guard_Instructions_Rev_11-14.pdf?5242) | Pneumatic gear failure or forced gear-up landing from leaks, unfilled reservoir or too many cycles; auto-extend below threshold or on lost signal | Robart accessory. |
| R62 | [E-flite EFLG200 electric retracts](https://www.astramodel.cz/manualy/E/EFLG200-Manual.pdf), 2010 | Receiver-powered; sequence 0.75–1.25 s. Threadlock wheel collars and axles against vibration. Check for wheel-well obstructions | One retract family. |
| R63 | Hiller, [MA Jan 2023](https://www.modelaviation.com/Landing-Gear) | Jet pneumatic gear: cylinder leaks and air-line degradation; brakes fiddly to set up | Experienced jet modeller. |
| R64 | Snyder, [MA Aug 2012, p.37](https://www.modelaviation.com/howtolandinggear) | Wire gear bends on rough landings; wheels may not retract completely | Scale builder. |
| R65 | Aberle, [MA Jun 2004](https://library.modelaviation.com/article/technical-review-200406) | Selecting the wrong model memory “could result in a crash” | Product review. |
| R66–R71 | Wing-loss case sources | See [§5](#5-wing-loss-and-one-wing-recovery-case-file) | — |
| R72 | [BMFA Handbook, Annex B §5 Interference](https://handbook.bmfa.org/?p=4545) (© 2021) | Outside interference is rare. Rule out airborne power, hardware, ground and pilot causes first | 35 MHz era text. |

## 3. Failure library

Page references in the tables follow each register entry's convention: PDF pages unless the entry says printed. **Type:** H hardware, **S** setup or maintenance error, **P** pilot or operational error, X external. S and P are not random hardware failures; present them as preflight or setup lessons unless the plan decides otherwise. **Onset:** Sud sudden, Prog progressive, Int intermittent, Pre preflight/latent, Cond triggered by a condition. **Rec.** (recoverability in a skilled pilot's hands, qualitative): U usually, S sometimes, R rarely, A abort before flight if checked.

Existing and EM-30 mechanisms map as follows: `roll/pitch/yaw_jam` → `servo.stuck`; `roll/pitch/yaw_bias` → `servo.bias_slip` or `tx.trim_bumped`; `roll/pitch/yaw_slow` → `servo.slow_weak`; `*_travel_limit` → `servo.blowback`; `throttle_limit` → `battery.lvc_soft`/`esc.thermal_derate`; `throttle_stuck(_low)` → `engine.throttle_linkage_loose`; `glow_fuel_cut` → the engine stop entries; `electric_drive_loss` → `battery.lvc_hard`/`esc.overcurrent_cut`; `radio_loss` → `radio.link_lost_sustained`.

### 3.1 Glow, gasoline and turbine engines

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `engine.lean_overheat` | H/S | Lean needle or poor cooling; heat builds in long full-power climbs | Prog | RPM fades on verticals; cuts on throttle-up | Heat state derates combustion torque, then zero; prop windmills | Lower power, level off; deadstick if it quits | U | M | R42 p.12; R43 pp.2, 5 |
| `engine.rich_idle_stop` | S | Over-rich idle or prolonged idle loads the engine | Cond: throttle-up after idle | Smoke; RPM drops or engine stops on go-around | Torque collapses on a throttle step after idle dwell | Advance slowly; commit to landing | U | M | R42 p.12 |
| `engine.glowplug_idle_cut` | H | Worn or contaminated filament cools at low RPM | Cond: low throttle | Runs at power, dies on approach | Combustion stops below a plug-heat threshold; no air restart | Keep some power on approach | U | M | R42 p.7 |
| `engine.fuel_foam` | H | Vibration from prop or mount foams fuel | Prog | Surging, lean sag, stop | Lean factor driven by vibration level | Land; balance prop | U | M | R45 p.54 |
| `engine.attitude_starve` | S | Clunk stuck or line too stiff; tank too low or far | Cond: inverted, high g, low tank | Stutters in turns or inverted, quits late in the tank | Pickup availability f(attitude, g, fuel level) | Roll upright, unload; deadstick | U | M+R | R48; R42 p.7; R49 |
| `engine.fuel_air_leak` | H | Split or loose fuel line, carburettor or seal leak | Int→Prog | Erratic RPM, lean, stop | Random lean excursions, then stop | Land | U | M | R43 pp.2, 7 |
| `engine.hot_carb` | H/S | Carburettor or fuel heated by exhaust | Prog | Erratic running, hard restart | Intermittent torque dropouts | Reduce power, land | U | M | R43 p.2 |
| `engine.ignition_power` | H/S | Gas ignition pack low or lead broken by vibration | Sud/Prog | Misfire then stop; radio unaffected if separate | Combustion zero; servos unchanged | Deadstick | U | M | R43 pp.3, 5 |
| `engine.ignition_rfi` | H/S | Loose plug cap or damaged shield radiates noise | Int, RPM-linked | Servo glitches only with engine running | Link quality degraded as a function of RPM | Reduce RPM, land | S | M | R43 p.3; R44 p.3 |
| `engine.throttle_linkage_loose` | H | Throttle pushrod or clevis detaches | Sud | Throttle ignores stick; may stay high | Carburettor stays at last value or drifts with spring/vibration | Independent kill if fitted; else fly off energy | S | M+E | R42 p.3; R43 p.2 |
| `engine.one_out_twin` | H | One engine or motor of a twin stops | Sud | Yaw and roll toward dead side; climb lost | Asymmetric thrust plus windmill drag | Rudder; reduce good engine near ground | S | R | R19 (Catalina 2023); R59 |
| `turbine.flameout` | H | Bubble or fuel interruption, batteries → LowRPM shutdown | Sud | EGT and RPM decay | Thrust spools to zero; relight only with ECU autorestart and its conditions | Glide; commit to landing | S | M | R50 pp.35, 39–40; R07 |
| `turbine.ecu_shutdown` | H | Over-temperature, battery out of limits, pump overload | Sud | Engine stops | As flameout | As flameout | S | M | R50 pp.39–40 |
| `turbine.failsafe_shutdown` | H (consequence) | Link loss: idle after 0.5 s, shutdown after 1.5 s more | Cond | Thrust lost even if the link returns late | Timed ECU states | Glide | S | M | R50 p.40 |

### 3.2 Electric drive and energy

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `battery.lvc_soft` | H/S | Loaded pack voltage reaches ESC threshold | Prog, late | Motor pulses; power limited | Latched cap: 60 % (Avian), gradual (Hobbywing), soft/RPM-decrease/pulsing (Castle) | Land now | U | M | R34 p.14; R35 p.16; R36; R37; R05 |
| `battery.lvc_hard` | H/S | Hard cutoff selected | Sud, late | Motor stops; controls stay | Drive torque zero; BEC alive | Deadstick | U | M | R36; R37 |
| `battery.weak_pack` | H | Aged, high-resistance or damaged pack; damaged motor draws excess current | Prog | Weak climb, early LVC | Maximum power f(loaded voltage) | Land early | U | M | R35 p.17; R24 |
| `esc.thermal_derate` | H/S | ESC above about 110 °C or its programmed threshold | Prog: long climbs, poor cooling | Stutter above 60 % throttle; power drops | Cap 60 % (Avian) or steps 75/50/25/0 % (BLHeli_S); recovers as it cools | Reduce throttle, land | U | M | R35 p.15; R36; R38 |
| `esc.desync` | H/S | Commutation lost on fast throttle increase at low RPM; wrong timing | Cond: throttle punch | Stutter or stop after a punch | Torque collapses; restart after throttle zero | Throttle to zero, re-advance smoothly | U | M | R38; R37 |
| `esc.overcurrent_cut` | H | Overload or peak current (damaged motor, binding, wrong prop) | Sud | Motor stops | Drive zero until re-armed | Deadstick | U | M | R35 pp.16, 18 |
| `esc.signal_loss_timer` | H (consequence) | No throttle signal: Avian cut at 0.25 s; Hobbywing reduce at 1 s, cut after 2 s more; EFLA1040 2 s | Cond | Motor stops during an outage | ESC-specific timers; resume rules | — | — | M | R35 p.16; R36; R05 |
| `esc.failure_with_bec` | H | ESC fails; where its BEC powers the receiver, control is lost too | Sud | Motor stops and model is unresponsive | Receiver and servos unpowered | None | R | R+E | R19 (Tiger Trainer 2026; BEC role inferred) |
| `power.main_connector_open` | H | Main battery connector unseats or is faulty | Sud | Total loss; uncontrolled glide | All electrics off | None | R | R | R19 (MiG-29 2025, Soar 40 2023) |
| `motor.mechanical` | H | Bearing, bent shaft, rubbing, loose magnet | Prog | Noise, vibration, heat, power loss | Extra drag torque; vibration; may stop | Reduce power, land | U | M+F | R35 p.18; magnets forum only |

### 3.3 Propeller and powerplant installation

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `prop.blade_loss` | H | Blade separates (glue joint, crack, overspeed) | Sud | Violent vibration; thrust lost; servos may stop | Thrust ~0; large once-per-revolution force; servo authority degraded or lost | Throttle off at once; glide | S | R+M | R51; R42 p.8 |
| `prop.departure` | H/S | Nut or collet loosens (backfire, vibration, brake with heavy prop) | Sud | Over-speed sound, no thrust | Thrust zero; small forward mass loss | Deadstick | U | M+R | R42 p.3; R52 |
| `prop.damage_imbalance` | H | Cracked or nicked prop or spinner | Prog | Vibration; secondary loosening and foaming | Vibration state feeds other faults | Land; replace | U | M | R42 p.3; R34 p.22; R45 |
| `prop.spinner_loss` | H/S | Spinner or backplate loosens; slots weaken blade roots | Sud | Vibration; possible blade failure | Drag and imbalance | Land | U | M+E | R42 p.3; R43 p.5 |
| `mount.failure` | H | Vibration or fatigue cracks mount or firewall | Prog→Sud | Vibration; thrust-line change; engine may leave | Thrust vector rotates; losing the engine moves CG far aft | Throttle back, land early; if the engine leaves, likely uncontrollable | S (R if engine leaves) | R+E | R18 (case 34a); R45 p.54; R43 p.6 |
| `cowl.detach` | H | Cowl comes adrift into the prop | Sud | Prop strike, vibration, drag | Drag plus prop damage | Throttle off, land | S | R | R51 |
| `exhaust.muffler_loose` | H | Muffler bolts back out | Prog | Louder; power change; may fall off | Small power and mass change | Land | U | E | — |

### 3.4 Control surfaces and actuators

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `servo.stuck` | H | Mechanical seizure or a broken gear locks the output | Sud | One axis frozen | Surface held at capture position | Use remaining controls; manageable if inside trim range | S | R | R21; R22 pp.23–24 |
| `servo.hardover` | H | Electronics or feedback pot drives to the end stop | Sud | Strong uncommanded roll, pitch or yaw | Surface at travel limit | Full opposite on remaining surfaces; slow down | S (R on elevator) | R | R59; R22; R21 |
| `servo.gear_stripped_float` | H | Gear teeth strip; output disengaged | Sud | Axis dead; surface flops or buzzes | Free surface: hinge moment, friction and damping set a time-varying equilibrium (often near trail; E) | Remaining controls; slow down | S | R+F | R22 p.24; R21 |
| `servo.bias_slip` | H/S | Gear slippage, bent linkage, rigging | Sud/Prog | Needs constant stick or trim | Offset on actual deflection | Retrim | U | R | R22 p.23 |
| `servo.jitter` | H | Dirty or corroded plug, worn feedback pot, vibration | Int | Surface oscillates about trim after stick release | Bounded oscillation added to the actuator; extra current | Land; avoid high speed | U | R+M | R40; R04 |
| `servo.slow_weak` | H | Low supply voltage, worn motor, overload | Prog | Sluggish; less deflection at speed | Rate and stall torque reduced (D6-SRV voltage law) | Small early inputs | U | M | D6-SRV-00; R24 |
| `servo.blowback` | S | Undersized servo: hinge moment exceeds stall torque at speed | Cond: high speed | Authority fades with speed | Deflection limited at torque equilibrium | Slow down | U | M+E | D6-SRV-00; R46 p.56 |
| `servo.overload_cutout` | H | Stalled servo overheats; overload protection switches output off | Prog | Axis goes soft | Output off → floating surface | Slow down, land | S | M | R03; R41 |
| `linkage.clevis_open` | S | Clevis without keeper springs open | Sud | Axis dead; surface flops | Free surface | As stripped gear | S | M+E | R46 p.57; R47 pp.37–41 |
| `linkage.horn_or_arm_loss` | S/H | Horn pulls out, horn or servo-arm screw backs out | Sud/Prog | Partial or total loss of a surface | Free surface or reduced throw | As stripped gear | S | E | R47 pp.30, 38–41 (installation) |
| `linkage.slop_wear` | H | Worn holes, gear backlash, pushrod flex in tight bends | Prog | Poor centring; flutter risk | Backlash/deadband in actuator-to-surface path | Fix on ground | U | M+R | R45 p.57; R58 |
| `surface.flutter` | H/S | Slop at high speed → aeroelastic oscillation | Sud: dive, high speed | Low or machine-gun buzz; horns, servos, surface or wing destroyed | Not physically modelled (D6-SRV OD7). Training proxy only: buzz, then actuator or surface damage | Cut throttle and slow down immediately | S | M+R | R45 p.57; R58 |
| `surface.single_aileron` | H | One aileron stuck, floating or missing (two-servo wing) | Sud | Roll tendency; heavy in roll | Independent per-side surface state | Hold the other aileron opposite, touch of rudder, slow; faster approach | U/S | R | R59; R57 |
| `surface.split_elevator_half` | H | One elevator half stuck or floating | Sud | Pitch change with roll coupling | Per-half surface state | Working half plus power for pitch | S | R | R59 |
| `surface.dual_servo_conflict` | H/S | Two servos on one surface fight, or one disconnects | Prog/Sud | Buzz and current; sluggish | Extra current; reduced rate | Land | U | R | R41 |
| `flap.asymmetric` | H | One flap servo or linkage fails at deployment | Cond: flap selection | Roll on flap selection | Per-side flap deflection | Retract flaps; land flapless | U | M (full-scale)+E | R09 |
| `hinge.failure` | S/H | Poorly glued CA or nylon hinges pull out | Sud | Flutter, then surface leaves | Hinge freed → separation | Slow down, land | S | M+R | R47 pp.7, 9; R20; R57 |

### 3.5 Radio link, receiver and transmitter

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `radio.link_lost_sustained` | H/X | Range, masking, receiver or transmitter fault | Sud | No response | Receiver profile: hold, preset, no pulses, SmartSafe; ESC and ECU timers | None beyond waiting for reacquisition | R | M+R | R25–R30; R19 |
| `radio.dropout_brief` | H/X | Frame loss shorter than the failsafe timeout | Int | Twitch or freeze up to about 1 s, then control | Commands held for Δt (R617XL < 1 s; ELRS 1 s) | Keep flying, gain height, land | U | M | R30; R29 |
| `radio.failsafe_not_set` | **S** | Never set, or reset by rebind; default holds | Pre (latent) | On loss: throttle holds high, surfaces frozen → flyaway or high-energy impact | Last throttle and surface commands held | None in flight; failsafe test before flight | R (A) | M | R25; R28; R26 p.12; R20 |
| `radio.failsafe_preset_wrong` | **S** | Bad preset (surfaces, gear) or ELRS default 1500 µs on a non-output-3 throttle | Pre (latent) | On loss: turn, climb, gear moves, half throttle | Preset outputs | Ground test | R (A) | M+E | R25; R29 |
| `radio.antenna_masking` | **S**/H | Antenna in carbon or near metal, parallel or damaged antennas | Int: attitude, range | Glitches or holds in certain attitudes or at distance | Link quality f(range, attitude) | Fly closer; land | U | M | R27 pp.3, 5; R32; R30 |
| `radio.interference_external` | X | External RF | Int | Glitches | Link degradation | Land | U | M | R72 |
| `rx.brownout_reboot` | H | Supply below about 3.5 V (servo load, weak pack, BEC) | Sud | Glitch up to seconds of no control | Outputs undriven during reboot; analog servos may run away; reconnect 0.04 s to ≤1 s to several seconds by receiver | Reduce load; land | S | M+R | R27 p.8; R30; R31; D6-SRV-00 |
| `rx.hardware_dead` | H | Receiver failure | Sud | Unresponsive; motor cut by ESC | No outputs: servos limp or float; ESC timers | None | R | R | R20; R21 |
| `tx.battery_low` | **S** | Transmitter battery depleted | Prog | Alarm, then link loss | Link loss after the alarm interval | Land on alarm | U | M | R26 p.22; R34 p.2 |
| `tx.gimbal_fault` | H | Worn pot or oxidised gimbal connector | Int | One axis jumps or drifts | Command jumps on one axis | Land with remaining axes | S | F | Not registered (forum only) |

### 3.6 Airborne power and wiring

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `power.switch_open` | H | Switch harness opens (vibration, small switch) | Sud/Int | Total loss of control | Receiver and servos unpowered; a glow throttle servo stays where it was (inference consistent with R39) | None | R | R+M | R20; R24; R21; R46 p.57 |
| `power.rx_pack_depleted` | **S**/H | NiMH false peak, forgotten charge, failed cell | Prog | Slow servos, then brownout | Voltage decay → slow servos → reboot → loss | Land at first slowness | S | M+R | R27 p.8; R20 |
| `power.lead_chafe` | H | Lead worn through by vibration | Int→Sud | Glitches, then total loss | Intermittent supply | None | R | R | R39 |
| `bec.linear_overload` | **S** | Linear BEC beyond its servo and cell rating overheats | Prog: busy flying | Glitches, then receiver loss | BEC thermal state → shutdown → brownout | Fewer inputs; land | S | M+E | R36; R24 |
| `power.servo_load_sag` | H/S | Many or high-current servos sag a marginal supply | Cond: hard manoeuvres | Brief glitches or brownout | Load-dependent voltage feeding `rx.brownout_reboot` | Gentler inputs | S | M | R04; R27 p.8; R24 |

### 3.7 Stabiliser and automation

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gyro.reversed` | **S** | AS3X/SAFE direction or orientation wrong | Pre / take-off | Gyro reinforces disturbances; divergent | Stabiliser sign flipped | Direction test; abort | A | M | R33 p.13 |
| `gyro.gain_oscillation` | **S** | Gain too high for the speed | Cond: high speed | Rocking on one axis | Gain × dynamic pressure exceeds stability margin | Slow down; reduce gain or switch off | U | M | R33 p.12 |
| `gyro.mode_malfunction` | H | GPS or self-level mode misbehaves | Sud | Unexpected attitude commands | Automation adds inputs | Switch assist off | U | M | R34 p.29 |
| `gyro.not_armed` | S | AS3X active only after the first throttle advance | Pre | No damping at launch without throttle | Assist absent until armed | Advance throttle first | A | M | R33 p.12 |

### 3.8 Setup and pilot operation

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `setup.reversed_control` | **S** | Servo reverse or channel map wrong after setup or repair | Pre | One axis acts opposite | Sign flip on one axis | Control-direction check; abort take-off | A | M | R34 p.12; R45 p.54 |
| `setup.wrong_model_memory` | **S** | Wrong model memory selected | Pre | Wrong reverse, rates, trims, or no connection | Wrong command shaping, or connection refused | Check before flight | A | M+R | R27 p.8; R29; R65 |
| `setup.cg_aft` | **S** | CG behind limit (battery position, repairs) | Pre | Pitch-sensitive, hard to control | Existing mass/CG | Land; fix | S | M | R34 p.22 |
| `setup.no_independent_kill` | **S** | No independent kill or fuel shutoff on gas/turbine | Pre | Stuck-high throttle cannot be stopped | Kill path unavailable | — | — | M | R46 p.56; R25 |
| `tx.trim_bumped` | **P** | Trim switch knocked in flight or transport | Sud | Slow drift in roll or pitch | Command offset | Retrim | U | E | — |
| `tx.rates_low` | **P/S** | Low rate left on | Pre/Sud | Sluggish; flare or recovery short | Command scale reduced | Switch to high rate | U | M+E | R45 p.56; R26 p.27 |
| `tx.throttle_cut_bumped` | **P** | Throttle-cut switch flipped in flight | Sud | Engine or motor stops | Throttle to cut value | Electric: reset; glow: deadstick | U | M+E | R26 p.27 |

### 3.9 Landing gear and ground handling

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gear.retract_fail_up` | H | Leak, low pressure, too many cycles; electric unit stalled | Cond: gear-down | Gear stays up | Retracted contact set; lower drag | Belly-land on grass; stop engine before touchdown | U | M | R61; R62; R63 |
| `gear.retract_one_leg` | H | One leg incomplete (binding, geometry, leak) | Cond | Asymmetric gear | One leg down: asymmetric drag and contact → ground loop | Retract all if possible; else hold the wing up on the good side | S | M+R+E | R61; R64 |
| `gear.retract_stuck_down` | H | Retract will not raise | Cond | Extra drag | Higher drag | Continue; land normally | U | E | R61 |
| `gear.wheel_departure` | **S**/H | Wheel-collar set screw loosens | Prog | Wheel leaves, maybe unseen | Axle stub: high friction one side → swerve or nose-over | Land on grass; hold the wheel-less side up with aileron | S | M+E | R62; R45 p.53 |
| `gear.steering_loss` | **S**/H | Steering arm slips on the nose-gear wire | Prog | No ground steering | Steering command ineffective | Rudder only | U | M | R45 p.54 |
| `gear.brake_fault` | H/S | Leak, mis-setting, one-sided brake | Cond | Weak or asymmetric braking | Brake torque reduced or asymmetric | Long runway; rudder | U | R | R63 |
| `gear.collapse` | H | Bent wire or torn mount after a hard landing | Cond: touchdown | Gear folds; prop strike | Contact geometry change | — | U (damage) | M+R | R45 p.54; R64 |

### 3.10 Structure, hatches and mass

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `wing.panel_separation` | H | Wing tube, joiner, spar or bolt failure, often in a snap or at high g | Sud | Violent roll; panel leaves | Remove panel mass, area and control; lateral CG and inertia change | Knife-edge on fuselage side force and thrust if available ([§5](#5-wing-loss-and-one-wing-recovery-case-file)) | R | R | R19; §5 |
| `wing.fold_center` | H/P | Centre section folds in a high-g pull-out | Sud | Both panels fold | Lift collapse | None | R | R | R53; R19 (2021) |
| `wing.partial_section` | H | Outer section or tip lost (impact, flutter) | Sud | Roll tendency; aileron may go | Partial area and aileron removal; lateral CG | Opposite aileron/rudder; faster approach | S | E | R12; R57 |
| `wing.hold_down_release` | **S** | Too few or oily rubber bands, failed bolts | Cond: high g | Wing lifts or pops off | Attachment compliance → separation | — | R | M | R45 p.56 |
| `tail.horizontal_separation` | H/S | Stabiliser breaks off (old repair, fatigue) | Sud | Pitch lost; spin | Remove stabiliser and elevator half | None reliable | R | R | R54; R19 (Laser 2025) |
| `tail.fin_separation` | H | Fin and rudder lost | Sud | Directional divergence | Remove fin | Aileron and elevator only | S | E | R12 |
| `surface.separation` | H | Control surface leaves (hinge failure, flutter) | Sud | As a single-surface loss | Remove surface | As `surface.single_aileron` | S | R+E | R57 |
| `canopy.loss` | H/S | Canopy or hatch latch or magnets fail | Sud | Drag; pitch or yaw disturbance | Drag and small mass change | Land | U | R+E | R55 |
| `hatch.battery_ejection` | **S** | Unsecured hatch opens as an air brake; battery ejected | Sud | Tumbling; electric power lost | Drag pulse, mass loss, CG shift, power loss | None | R | R | R55 |
| `cg.battery_shift_aft` | **S** | Untied battery slides aft under climb acceleration | Cond: climb-out | Pitch-up; possible stall | CG moves aft; pitch moment | Down elevator, reduce power | S | F | R60 |
| `cg.battery_shift_forward` | **S** | Battery slides forward in a dive or landing | Cond | Nose-heavy; short flare | CG moves forward | Faster approach, power-on flare | U | E | R60 (note) |
| `structure.fatigue` | H | Joints weakened by vibration or fuel soak | Prog | Creaks, flexing | Reduced strength → later separation | Ground inspection | — | R | R53 |

### 3.11 External

| ID | Type | Mechanism | Onset | Symptoms | Simulation consequence | Pilot response | Rec. | Ev | Refs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ext.midair` | X | Collision with another model | Sud | Surface or structural damage; battery disconnect | Damage set: surface loss or power loss | Varies | S | R | R19 (Soar 40 2023) |
| `ext.bird` | X | Raptor harassment or strike | Sud | Usually none; damage possible | Damage set | Maintain speed, turn away | — | F/E | No documented downing found |
| `ext.vlos_loss` | **P**/X | Sun, cloud, mist, distance, contrast | Cond | Orientation or sight lost | Scenario, not a failure | Several reporting pilots cut the throttle | — | R | R19 |
| `ext.gust_upset_low` | X | Gust in the circuit | Cond | Wing drop or stall | Existing wind model | Speed margin | — | R | R19 |

Total: 97 entries in 11 groups. Mechanisms marked E or F should not be presented to players as documented hardware behaviour until better evidence exists.

## 4. Incidence and relative-frequency evidence

### 4.1 What exists

| Evidence | Population | Finding | Transfer to hobby fixed-wing |
| --- | --- | --- | --- |
| R17 OSD | 3 military UAV fleets, ~100,000 h, Class A mishaps | Power/propulsion 37 %, flight control 26 %, human/ground 17 %, comms 11 %, misc 9 % | Weak: autopilots, data links and maintenance regimes differ; supports propulsion and actuators as large shares. |
| R18 Wild 2017 | 152 civil RPAS reports, 2006–2015 | Equipment problems 64 % of known causes; about a third of those involved lost link | Weak: civil operations, aircraft type often unrecorded, small convenience sample. |
| R19 AAIB | 65 UK model-aircraft occurrences, 2020–2026 | See §4.2 | Closest population; reporting bias toward flyaways and third-party risk. |
| R21 Reimann | Predicted Ultra Stick 120 | 2.17 catastrophic per 100 h; airborne power and tail servos dominate | Model prediction; ranks components, not observed rates. |
| R20, R27, R24 | Practitioner, manufacturer | Power path (battery, switch, connector, BEC) is the leading hardware cause | Ordinal; no counts. |

No hobby association (AMA, BMFA, MAAA, MAAC, NZMAA) was found publishing cause statistics. The MAAA requires members to report accidents and incidents, but no aggregate was found.

### 4.2 AAIB record-only model-aircraft rows, 2020 to 2026

Rows whose aircraft type names a model aircraft (MA) were read and classified once by this review; the row list is in [sources.json](sources.json). Classification follows the text as reported; “link lost” is the pilot's description and may include brownouts.

| Class | Rows | Share of 65 | Share of 37 hardware-attributable (A–E) |
| --- | --- | --- | --- |
| A link lost or unresponsive, cause not determined | 21 | 32 % | 57 % |
| B airborne electrical failure stated (connector, ESC, battery) | 3 | 5 % | 8 % |
| C propulsion stop or power loss, control retained | 4 | 6 % | 11 % |
| D single control channel lost or intermittent | 5 | 8 % | 14 % |
| E structural separation (wing or tail) | 4 | 6 % | 11 % |
| F pilot handling (stall, wrong input, orientation) | 5 | 8 % | — |
| G lost sight, cloud, mist, sun, wind drift | 16 | 25 % | — |
| H mid-air collision | 1 | 2 % | — |
| I other (autogyro, VTOL, unexplained “lost control”) | 6 | 9 % | — |

### 4.3 Recommended training-policy default weights (estimate)

These are **training-policy estimates**, not measured RC failure rates. They replace uniform selection only if the owner adopts them. Within a category, use uniform selection over the mechanisms the aircraft can support. Redistribute an empty category proportionally.

| Pool | Category | Weight | Basis |
| --- | --- | --- | --- |
| Ordinary | Propulsion and energy (engine stops, LVC, thermal derate, desync, reduced power, stuck throttle) | 40 % | OSD 37 % power/propulsion; a manufacturer warns that the engine can stop at any time (R43); deadstick is the common manageable emergency, but such landings rarely reach AAIB. |
| Ordinary | Control surfaces and actuators (stuck near trim, floating, bias, slow, jitter, one-side) | 30 % | OSD 26 % flight control; AAIB D is 14 % of hardware rows; R22 common modes. |
| Ordinary | Brief link or power (dropout under 1 s, fast brownout reboot) | 10 % | Spektrum and practitioners rank power first; only brief forms are manageable. |
| Ordinary | Landing gear and ground (retract, wheel, steering, brake) | 10 % | Training value; only where the aircraft has the part. No incidence data. |
| Ordinary | Minor airframe (canopy, partial surface damage, small CG shift) | 10 % | Training value; R55, R60. |
| Catastrophic | Sustained link loss or total airborne power loss, including failsafe-hold throttle | 50 % | AAIB A+B = 65 % of hardware rows; R18 lost link; R20, R21. |
| Catastrophic | Structural separation (wing panel, tail, centre fold, surface) | 25 % | AAIB E = 11 % of hardware rows; raised for the requested wing-loss practice. |
| Catastrophic | Catastrophic propulsion (blade loss, mount failure) | 15 % | R51, R18; no counts. |
| Catastrophic | Collision (mid-air, bird) | 10 % | AAIB 1/65; training value. |

Setup and pilot errors (S/P rows) belong in a separate preflight or scenario lesson, not in the random hardware pool. Loss of sight and weather (25 % of AAIB rows) belong to the weather and scenario system.

## 5. Wing-loss and one-wing recovery case file

No denominator exists: these are the successful cases found, and unsuccessful ones are under-filmed. AAIB records four separations, none recovered (R19).

| Ref | Date | Aircraft, span, power | Portion lost | Reported technique | Outcome | Source quality |
| --- | --- | --- | --- | --- | --- | --- |
| R66 | Video uploaded 30 Sep 2008 | Yak-54 model (owner Keith Ellis); span and power not stated | Left wing, during a full-throttle snap roll at mid-field | Held the correction; found a new stick position for stable knife-edge; lined up on the runway | Landed right side up on the runway | R: [pilot's own video](https://www.youtube.com/watch?v=hOBB_-gZFNo) description; [AVweb, 27 Oct 2008](https://avweb.com/multimedia/votw/video-of-the-week-one-winged-rc-landing/); pilot's RCGroups text seen only as a [forum repost](https://romanian-spotters.forumgratuit.ro/t876-aterizari) (original thread blocked). |
| R67 | Uploaded 27 Dec 2008 | “3D plane”, irks.org field; pilot “Van” | “Wings breaks off”; one wing remained | Not stated | Landed with one wing | F: [uploader description only](https://www.youtube.com/watch?v=pu-VCN32Vh4). |
| R15 + R69 | 7–11 Oct 2009, Tucson Aerobatic Shootout freestyle | Not identified in the reviewed sources | Left wing, in a low, fast snap at the end of the routine | Circled in knife-edge and landed | “Perfect landing” | R: R15 filmer's account plus [video description](https://www.youtube.com/watch?v=Gh52tyilpr4) (uploaded 19 Oct 2009). |
| R16 | 14–16 Jun 2013, XFC freestyle | Not identified | “Wing broke off” | Not described | “Perfect one-wing landing” | R: AMA event report. |
| R68 | Uploaded 23 Sep 2013 | Model at Markham Park; pilot “Jacob P” | A wing came off in flight | Knife-edge | Landed (description says “with further damage”, probably meaning without) | F: [uploader description](https://www.youtube.com/watch?v=ibwuaOdA_ng). |
| R71 | 1 May 1983 | Full-scale F-15D (IAF), out of domain | Right wing, about 2 ft from root, after mid-air with an A-4 | Afterburner and high speed for control | Landed at about 260 kt (other sources: about 300 kt); arresting hook torn off | R (secondary journalism: [Task & Purpose/Sandboxx, 23 Sep 2020](https://taskandpurpose.com/history/1983-negev-mid-air-collision)); speeds conflict; comparison only. |

**Pattern.** The recovered RC cases that name a type are aerobatic or 3D models; two pilots were flying competition freestyle (R15/R69, R16). Every account that describes the technique (R66, R15/R69, R68) used knife-edge flight. Fuselage side force and thrust carrying the weight, with rudder setting the flight path, is the physical interpretation (E), not a reported measurement. Both accounts that describe the trigger (R66, R15/R69) were snap rolls, consistent with structural overload in that manoeuvre. Nothing establishes that a trainer, warbird or jet cannot do it, or that an aerobatic model usually can. [EM-31](../EM-31/README.md) owns the feasibility analysis for the fleet.

**Excluded.** A widely shared full-scale “one-wing landing” video is a hoax ([AVweb, 29 Nov 2008](https://www.avweb.com/news/revisiting-the-one-wing-landing-video-just-for-pilots)) and must not be used as a case.

## 6. Contradictions, dead ends and open questions

### Contradictions

| Topic | Conflict | Treatment |
| --- | --- | --- |
| Xicoy failsafe timing | EM-00 R07 says the 0.5 s idle + 1.5 s shutdown sequence was not supported. The failsafe page (PDF p.31) does not give it, but the diagnosis page (PDF p.40) does. | Correct EM-00 R07 in integration; still Xicoy-only, not JetCat. |
| 2.4 GHz failsafe default | BMFA: all 2.4 GHz defaults to hold (R25). Spektrum SmartSafe sends throttle to its bound position (R26). ELRS PWM: 1500 µs except output 3 (R29). | Default is brand- and binding-specific; the receiver profile must state it. |
| Reconnect time | 0.04 s (AR6335), up to 1 s (AR6110, R617XL, R608FS), several seconds (early DSM2) | Per-receiver profile data. |
| What “link lost” means | AAIB rows are dominated by “signal lost” (R19). Spektrum ranks power systems first (R27); the BMFA calls interference rare (R72). | Treat link loss and brownout as separately caused events with similar symptoms. |
| Most common servo failure mode | Reimann assumed hard-over (R21); Freeman names hard-over and floating (R22); de Vries saw only one true hard-over (R59). | No counts; weight stuck, floating and bias similarly. |
| F-15 landing speed | 260 kt vs about 300 kt in secondary sources | Out of domain; not used numerically. |

### Dead ends (do not repeat)

- **Forums:** RCGroups returns HTTP 402 (TollBit) to automated fetches. RCUniverse and modelflying.co.uk return 403. FlyingGiants returns a 202 challenge page.
- **Publishers and archives:** MDPI (Wild 2016 *Aerospace*), the ECU repository and Wright State CORE Scholar return 403. FAA, ROSAP and DTIC copies of Williams (2004, DOT/FAA/AM-04/24) also return 403. The NATO STO paper MP-HFM-124-05 returns 404. The original OSD 2003 *UAV Reliability Study* was not found online; R17 is OSD's own extract.
- **Timeouts and withdrawn pages:** the ATSB RPAS safety analysis AR-2017-016a timed out twice. Flying Magazine (`?p=29866`) returns 410. The APC RPM-limit page and the HobbyKing prop blog return 403. `conservancy.umn.edu` returns 403; `dept.aem.umn.edu` works.
- **Not found:** the Spektrum “hold = 45 frame losses ≈ 1 s” definition appears only in forum reposts, not in an official manual reviewed. No measured Jeti/FrSky reboot times. No model-engine carburettor icing evidence. No documented raptor downing of an RC airplane. No hobby association cause statistics.

### Open questions

1. Floating-surface equilibrium and damping for each control surface: hinge moment, friction and backlash data or a defensible surrogate (EM-00 open item; D6-SRV owns servo physics).
2. Receiver and ESC profiles for the fleet's assumed radio installation: failsafe default, hold timeout, reboot time, ESC signal-loss timer, BEC type.
3. Whether brief dropouts and brownouts should be ordinary practice. Recovery depends on profile timing that the fleet does not yet declare.
4. Prop blade-loss vibration effects on servos and mounts need a vibration model before the event can be more than thrust loss.
5. Hobby incidence: a club-level logbook (flights, deadsticks, crashes by cause) would be the first real denominator. The F4 Phantom club's 6,500 flights a year (R56) shows that such clubs exist.
