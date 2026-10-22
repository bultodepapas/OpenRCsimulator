# Trim practice: trimming technique, throttle for level flight, the trim curve, inverted flight and hands-off flight, RC and full scale

2026-10-20 · research note for the D6e-R3 follow-up (owner's question: "search for trimming techniques, inverted flight, percentage of throttle, keep horizontal flight, and other things; investigate that in planes and RC, and real planes"). Research only: nothing under `app/` was changed; aircraft JSON was read once for masses. It extends, and does not repeat, [NITRO-06 throttle-power-research.md](../../glow-engines/NITRO-06/throttle-power-research.md) (part-throttle power, Ultra Stick cruise stick, thrust-to-weight) and [rc-aero-data-sources.md](../rc-aero-data-sources.md) (data registry). The simulator-side numbers quoted for comparison come from the draft `docs/research/flight-dynamics/power-climb-2026-10-19/trim-practice-comparison.md` (FT-05 card) and the [D6e-R3 README](README.md).

- Downloads: `references/rc-trim-practice/` (9 PDFs, [trim-practice-sources.md](trim-practice-sources.md) with URL, SHA-256, license; local copies under ignored `references/rc-trim-practice/`).
- Flight-log analysis: [research/flight-dynamics/power-climb/trim-practice/](../../../../research/flight-dynamics/power-climb/trim-practice/) (scripts; run with `python3 -I`, logs parsed with scipy.io/h5py only; the UMN logs are local-only under ignored `references/`).

Evidence labels: **M** measured · **MF** manufacturer (manual, data sheet, product page) · **H** handbook, textbook, regulation or instructor/magazine guidance · **A** anecdotal (forum, review remark) · **D** derived here (arithmetic shown; not evidence on its own) · "excerpt only" = seen only as a search-result snippet (page blocked).

## Key numbers

| Question | Finding | Label |
| --- | --- | --- |
| Throttle at which RC models are trimmed level | Electric trainers ½ (Apprentice STS, Opterra, F-18 EDF manuals); scale, STOL and EDF ¾ (Timber, Turbo Timber Evolution, P-51D 1.5 m, AT-6, F-4); glow trainer PT-40 "level with neutral trim at approximately ¼ to ⅓ throttle"; "trim the model to fly straight at cruise power" | MF, H |
| Behaviour after trimming | full throttle climbs without elevator (Apprentice; PT-40 20–30° climb), half holds height, low throttle descends; PT-40 needs "a little down trim" to stay level at full throttle | MF |
| Downthrust | Sig LT-40 6°, Kadet Mk II 2.5°, Four Star 40 2°, Avistar 1.5°, Top Flite P-51 1.75° (NITRO-06), GP Extra 0.5°; "a couple of degrees" for sport models | MF, H |
| Full scale | "attitude ... first ... then the flight control pressures trimmed out"; C172S cruise 2200–2550 rpm = 50–77 % BHP at 2000 ft, 75 % ≈ full throttle at 8000 ft | H, MF |
| Level-flight stick, RC | ArduPlane default 45 %, iNav ≈ 40 %; ArduPilot logs 20–45 %; electric cruise current 40–50 % of static; Ultra Sticks 0.55–0.83 (known) | defaults, A, M |
| Trim curve (Ultra Stick 120, nominal CG) | up elevator 6.0° at 19 m/s → 3.4° at 25 m/s → 2.3° at 31 m/s; **dδe/dCL 9.8 ± 0.6°** (filter range 7.9–12.1) | D from M |
| Trim curve (Ultra Stick 120, aft CG) | **6.2 ± 0.6°/CL** (5.2–7.2): aft CG flattens the curve by 30–50 % | D from M |
| Trim curve (Ultra Stick 25e) | **6.7 ± 0.9°/CL** (3.8–7.5); −0.26°/(m/s) at 17 m/s | D from M |
| Static margin from the trim curves | 25e 11 % MAC (identified model 13 %); US120 8.6 % nominal, 5.4 % aft | D |
| Dorobantu 2013, 25e | short period 16.33 rad/s, ζ 0.83 (identified); phugoid 0.51 rad/s, ζ 0.38 **not identified** (held at baseline) | M / model |
| Inverted push, RC practice | "a touch" / "very little" (sport and aerobatic), ≈ ⅛ stick at a good CG, "almost full stick" on flat-bottom trainers; Timber with slats "elevator feels heavy" inverted | A, H |
| Inverted push, theory and data | push = 2·CL·dδe/dCL ⇒ 2.5–7° for the measured Ultra Sticks at cruise | D |
| Inverted, full scale | Pitts S-1/S-2 trimmed upright "takes 5 to 8 pounds of forward pressure inverted"; Extra 300L inverted ≤ 4 min | H, MF |
| Hands-off RC | Ultra Stick 120 with elevator fixed: speed swings 6 m/s, pitch 14°, phugoid period 13.6 s at 24 m/s; KHawk flying wing ζ 0.10–0.13, period 8.3–8.7 s | D from M, M |
| Hands-off light aircraft | C172S phugoid 35–40 s, "heavily damped"; spiral dive 10–15 s after a small rudder input; Navion phugoid 29.5 s, ζ 0.08, spiral stable τ 114 s | M, H |
| Commercial RC simulators | runway or saved launch start; models pre-trimmed by their authors (fixed bias); trims are the pilot's; no auto-trim or speed-dependent trim documented | MF |

## 1. Trimming technique

### RC: where and how a new model is trimmed

| Source | Throttle and procedure | Label |
| --- | --- | --- |
| E-flite Apprentice STS 1.5 m manual (EFL3700, 2019, pp. 18–19, 22) | "If your aircraft does not fly straight and level at half throttle with the sticks at neutral, fly into the wind and adjust the trim"; "When properly trimmed, the aircraft's wing design causes a climb at full throttle without the use of elevator"; "Fly at just above half throttle to increase flying time" | MF |
| E-flite Mini Opterra (EFL11450, 2018, p. 12); F-18 80 mm EDF (EFL13950, 2020, p. 12) | trim at ½ throttle (F-18 flaps up) | MF |
| E-flite Timber 1.5 m (EFL5250, 2018, p. 13); Turbo Timber Evolution (EFL105250, 2021, p. 15); P-51D 1.5 m (EFL01250, p. 14); AT-6 (EFL8750, p. 9); F-4 EDF (EFL7950, p. 11) | trim at ¾ throttle, flaps (and gear) up | MF |
| Carbon-Z Cessna 150T (EFL12750, 2021) | 80–100 % on p. 19 and ¾ on p. 20 (the manual contradicts itself) | MF |
| Great Planes PT-40 Mk II glow kit manual (2004, p. 56) | "PT is designed to fly level with neutral elevator trim at approximately 1/4 to 1/3 throttle – this is the best speed for ... if you want the PT to maintain level flight at full throttle, you will need to give it a little down trim"; full-throttle climb about 20–30° | MF |
| D. Pappas, *Model Aviation* Jul/Aug 2006 | trainers "just above half throttle"; "Trim the model to fly straight at cruise power" | H (magazine) |
| *Scale R/C Modeler* trimming chart (Aug 1983, reprinted in the PT-40 manual p. 61) | "Do all maneuvers at full throttle"; with the right thrust line the model holds its path "for at least a dozen plane lengths" after a throttle chop | H (magazine) |
| Fly RC, "Aerobatic Trimming" (2011) | thrust tests at about ¾ throttle; up/down thrust corrections "less than a degree in all" | A |
| Goldsmith aerobatic trimming chart (BMFA copy, PDF 2006; method published in M. Hurley's *MA* column, Feb and Apr 2005) | 13 tests in order: control neutral, aileron throws, CG (vertical-bank test or inverted push), dynamic balance, right thrust, up/down thrust (pull to vertical: pitches to canopy → more downthrust), blowback, differential, throttle→aileron, throttle→rudder, rudder→aileron, rudder→elevator, throttle→elevator (idle downline) | H (club handout) |

No primary source gives a trim *speed*; every source gives a trim *throttle*, and "cruise power" is the doctrine. The throttle is type-specific: ½ for Horizon's electric trainers, ¾ for its scale, STOL and EDF models, ¼–⅓ for a glow trainer.

### RC: expected behaviour once trimmed

| Behaviour | Value | Source | Label |
| --- | --- | --- | --- |
| Full / half / low throttle | climbs / holds height / descends gently | Apprentice S 15e manual p. 16 (manualslib, excerpt only); Apprentice STS p. 18 | MF |
| SAFE stabilised mode (not natural behaviour) | full throttle "pitch up and climb slightly", mid level, low "descend slightly nose-down" | Turbo Timber Evolution p. 14; P-51D 1.5 m p. 15 | MF |
| Full-throttle climb, glow trainer | 20–30° | PT-40 p. 56 | MF |
| Idle check from 50 ft | nose twitches up = too much downthrust; nose drops into a fast glide = more downthrust needed | Pappas, *MA* Aug 2006 | H |
| Glide test | "one or two 'clicks' above a dead idle" | Pappas, *MA* Jul 2006 | H |
| Trimmed for airspeed (instructor) | "With zero elevator deflection, adding throttle causes climb at that airspeed, retarding throttle causes descent at that airspeed" | G. Krueger, Coachella Valley RC Club manual, 2017 | A (instructor) |

No numeric RC climb or sink rates were found beyond the PT-40's 20–30° and the instrumented Ultra Stick 120 in NITRO-06 (+1.8 to +4.8 m/s above cruise stick).

### RC: power-induced pitch (downthrust and mixes)

| Item | Value | Source | Label |
| --- | --- | --- | --- |
| Sig LT-40 trainer | 6° down, 6° right, wing +1.5° | sigmfg.com product page | MF |
| Sig Kadet Mk II / Four Star 40 | 2.5° / 2° down, 0° right | sigmfg.com | MF |
| Hobbico Avistar II 40 | 1.5° down | worthpoint listing, excerpt only | A |
| Sport models | "a couple of degrees" of downthrust | D. Scott, *MA* Aug 2013 | H |
| Right thrust | 2–3°, start at 2.5° | Pappas, *MA* Aug 2006 | H |
| Goldsmith right-thrust rule | rudder trim needed for a straight vertical ÷ 2 = degrees of right thrust | *MA* Feb 2005 | H |
| Throttle→elevator mix | ≈ 2 % down elevator at idle (pattern); 15 % (Big Stik 60); a 0/6/10 % switch | GiantScaleNews 2013; RCU (excerpt only) | A |
| Goldsmith low-throttle mixes | start "at least above half" stick; rudder→elevator 1–2 %, up to 10 % | *MA* Apr 2005 | H |
| Timber manual p. 4 | SAFE removes "the need for flap or throttle to elevator mixing" (i.e. the coupling exists on that model) | MF |

Together with NITRO-06 (0.5–2° on kit manuals), documented downthrust spans 0.5–6°, the large values on high-wing trainers.

### Transmitter trim resolution

| Radio | Step per press | Range | Source | Label |
| --- | --- | --- | --- | --- |
| EdgeTX/OpenTX | coarse 1.6 %, medium 0.8 %, fine 0.4 %, extra fine 0.2 % (exponential: 0.2 % near centre) | ±25 % (extended ±100 %) | https://manual.edgetx.org/color-radios/model-settings/model-setup/trims | MF |
| Spektrum / Futaba | default step 5 / 4; author sets 1 after trimming; 30 % trim rate on a 45° surface ≈ 13.5° of trim | – | J. Glezellis, *MA* Dec 2022, https://www.modelaviation.com/aircraft-trimming | H |

On a ±20° elevator, EdgeTX "medium" is about 0.16° per press and "fine" 0.08°: the simulator's 0.1° per Page Up/Down sits between them (D).

### Full scale

| Item | Value | Source | Label |
| --- | --- | --- | --- |
| Trim procedure | "The airplane attitude should be established first and held with the appropriate flight control pressures, and then the flight control pressures trimmed out" (p. 3-10); "airspeed remains constant in straight-and-level flight if the power setting is also constant" (p. 3-8) | FAA-H-8083-3C *Airplane Flying Handbook*, 2021, ch. 3 | H |
| Climb | "since the power should be fixed at the climb power setting, airspeed is controlled by the use of elevator pressure" (p. 3-19); level-off: throttle "set to the cruise power setting and the airplane re-trimmed" (p. 3-20) | same | H |
| Power–pitch coupling | "The airplane's nose tends to rise as airspeed and power increase" (p. 3-23); added slipstream raises the pitch attitude (p. 3-18) | same | H |
| Doctrine | ch. 4 (energy management) goes "beyond the simple 'pitch for airspeed and power for altitude'": the throttle is "the total energy controller" | AFH 2021 ch. 4, pp. 4-3 to 4-6 | H |
| Trim order | "Pilots normally establish the desired power, pitch attitude, and configuration first, and then trim the aircraft" | FAA-H-8083-25B *PHAK* (2016) ch. 6, p. 6-10 | H |
| Fixed-trim descent | with trim fixed, "control the glide angle by adjusting power exclusively"; "nose down moment resulting from power reduction" | Cessna 172S Information Manual pp. 3-15/3-16 | MF |
| Stick-force gradient rule | transport: "not be less than 1 pound for each 6 knots" (14 CFR 25.173(c)); pre-2017 Part 23: only "clearly perceptible", speed must return within ±10 % of trim | eCFR / govinfo | H |
| Measured gradient | C150M cruise 0.066 daN/kt (≈ 1 lbf per 6.7 kt), landing flap 30° 0.020 daN/kt; C152 cruise 0.136 daN/kt (≈ 1 lbf per 3.3 kt) | Bromfield & Gratton, *Aeronautical Journal* 116(1179), 2012, Tables 10–11 | M |
| C172 trim system | tab 28° up / 13° down before 1981, 22° up / 19° down after; trim wheel about 4 turns stop to stop | forum posts quoting the service manual (excerpt only) | A |

No published "turns of trim wheel per 10 kt" or tab-degrees-per-knot curve for a light aircraft was found (AC 23-8C not read).

### What this means for the simulator

Real practice trims a model at its cruise power, not at a fixed fraction of a slow speed, and then expects exactly what the 50 % start now gives: full throttle climbs without elevator, half holds height, idle descends at roughly the trimmed speed. Keeping the trim fixed until the pilot moves it is also realistic: neither real radios nor the commercial simulators re-trim on their own (section 5); only autopilots and gyro-stabilised modes do. Two refinements are supported by the sources. First, the cruise throttle is type-specific: ½ for electric trainers, ¾ for electric scale/STOL models such as the Timber, ¼–⅓ for a glow trainer whose barrel carburettor delivers most of its power in the lower half (NITRO-06). A single 50 % for every airplane is right for the electric Stik and roughly right for the Timber (Horizon says ¾), but puts the glow, gasoline and turbine models near 3 Vs (section 2). Second, the simulator's 0.1° per key press matches a transmitter's fine/medium trim step, so the 15–30 presses a slow-to-cruise retrim needs (section 3) are what a real pilot clicks.

## 2. Percentage of throttle for level flight

### RC (adds to the Ultra Stick 0.55–0.83 already in NITRO-06)

| Airframe / source | Level-flight throttle | Label |
| --- | --- | --- |
| Electric trainers (Apprentice STS, Opterra, F-18 EDF) | ½ (manufacturer trim point) | MF |
| Electric scale, STOL, EDF (Timber, Turbo Timber, P-51D 1.5 m, AT-6, F-4) | ¾ (manufacturer trim point) | MF |
| Glow trainer PT-40 Mk II | ¼–⅓ with neutral trim | MF |
| Trainers (Pappas) | "just above half throttle" | H |
| UMN Ultra Stick 25e (Thor) sys-id flights | "straight and level flight at approximately 19 m/s"; "the throttle setting is fixed to 70%" (Dorobantu et al. 2012, sec. IV) | M (test procedure) |
| ArduPlane `TRIM_THROTTLE` default | 45 % (`ArduPlane/config.h`, master dc78bc54) | autopilot default |
| iNav `nav_fw_cruise_thr` default | 1400 µs ≈ 40 % of 1000–2000 µs | autopilot default |
| ArduPilot cruise-tuning doc example | "the throttle is at 38%" in CRUISE | A (doc example) |
| ArduPilot forum logs | 18 m/s at ≈ 45 % ("Kite3", 2026); 23 m/s at 35 % and 14–15 m/s at 20 % (two airframes, excerpt only); ~10 % in loiter, 35 % into a 20 km/h wind (2015) | A |
| Bixler 2 FPV | 60–80 % average throttle | A, excerpt only |
| Giant-scale electric (data logger) | 90 A static at full throttle, flight mostly 35–45 A (Gimlick, *MA* Dec 2006); 1/5 Bristol M.1C 12S averaged 20 A against 45 A projected full throttle (*MA* Jul 2020) | M (current, not stick) |
| Turbine sport jets | nothing usable (Skymaster MiG-29 manual: "use throttle to control the descent!") | – |

Cruise current of 40–50 % of the static value means a stick well above 40–50 %, because propeller power rises roughly with rpm³ (D).

### Full scale

Cessna 172S Information Manual (1998, rev. 5 2004), Fig. 5-8, 2550 lb, standard temperature (MF):

| Pressure altitude | rpm → % BHP, KTAS |
| --- | --- |
| 2000 ft | 2550 → 77 %, 118 kt · 2500 → 73 %, 115 · 2400 → 64 %, 110 · 2300 → 57 %, 104 · 2200 → 50 %, 97 · 2100 → 44 %, 90 |
| 8000 ft | 2700 → 77 %, 124 · 2600 → 68 %, 119 · 2500 → 61 %, 112 |

- Normal procedures: "2100-2700 RPM (No more than 75% is recommended)". Static full-throttle rpm 2300–2400, red line 2700.
- 75 % power is about 2525 rpm at 2000 ft (part throttle) and about 2680 rpm at 8000 ft, almost full throttle (D, interpolated). The POH gives no throttle-lever position.
- Measured (Bromfield & Gratton 2012): C150M and C152 level cruise at 53–54 % BHP and 84–89 kt (M).
- Jet cruise at 80–90 % N1: not verified.

### Cruise speed against stall speed

| Aircraft | Cruise / Vs | Source |
| --- | --- | --- |
| Ultra Stick 25e, Ultra Stick 120 (measured cruise) | 1.6–2.1 | NITRO-06 note (D from M) |
| Dorobantu Table 2.1 "cruise speed" | 1.8–2.3 | (stated) |
| C150M/C152 at 53–54 % BHP | ≈ 1.8 (84–89 kt over Vs ≈ 48 kt) | D |
| C172S at 64–73 % BHP, 2000 ft | ≈ 2.3–2.4 (110–115 KTAS over Vs1 48 KCAS) | D |
| Sim, 50 % start (from FT-05 trim sweep): Ugly Stik, Timber | ≈ 2.0–2.1 | D |
| Sim, 50 % start: glow Stiks, Extra, P-51, Ventage Jet | ≈ 2.9–3.1 | D |
| Sim glow Stik at ¼–⅓ stick (PT-40 practice) | ≈ 2.2–2.5 | D (FT-05: 20 % at 2.0 Vs, 33 % at 2.5 Vs) |

### What this means for the simulator

The measured and published cruise points cluster at 1.6–2.4 Vs, with the stick anywhere from ¼ (glow) to ¾ (electric scale) and autopilot defaults at 40–45 %. The old 1.6 Vs start (9–37 % stick) sat at the slow edge of that band. The 50 % start lands inside it for the electric Stik (20.6 m/s ≈ 2.1 Vs) and the Timber (16.2 m/s ≈ 2.0 Vs, although Horizon trims the Timber at ¾), but at about 3 Vs for the glow Stiks (30.5 m/s), the Extra (33 m/s), the P-51 (46 m/s) and the jet (56 m/s). That is consistent with real part-throttle physics (a glow barrel gives 78–96 % rpm at half stick; a JetCat ECU makes thrust proportional to stick), and it is why the PT-40 manual trims a glow trainer at ¼–⅓. A start defined by speed (about 2.0–2.3 Vs) or by a per-propulsion stick (electric ½–¾, glow ¼–⅓) would match practice better than one stick fraction for all; the sim's glow Stik already gives 2.2–2.5 Vs at ¼–⅓ stick. This is an operating-point choice for the owner, not a physics defect. No measured cruise stick exists for a glow .60, a 120 cc gasoline warbird or a turbine sport jet.

## 3. Trim change with speed (the trim curve)

### Method (UMN flight logs; D from M)

The UMN Ultra Stick logs contain almost no steady, level, constant-speed flight: the pilots fly race-track patterns with a turn every 15–20 s, and the programmes on disk are stall/spin tests (Baldr) and system-identification sorties (Thor). A strict "steady level" filter (|φ| < 8°, |climb| < 1 m/s, |dV/dt| < 0.4 m/s², ≥ 3 s) finds only 0–18 s per flight (`trim_curve.py`, `trim_curve_out.md`), too little to bin. Trim is a pitch-moment balance, so the analysis uses quasi-steady samples at any flight-path angle and computes CL from the measured load factor and pitot dynamic pressure, CL = m·n_z·g/(q·S). The level-flight trim curve follows from V_level = √(2mg/(ρ₀·S·CL)).

- Samples: 1 s moving averages, decimated to 2 Hz. Airborne (IAS > 12 m/s Baldr, > 9 m/s Thor; AGL > 15 m); |φ| < 15°; |n_z − 1| < 0.3; elevator moving slower than 2°/s; |dθ/dt| < 5°/s and |d²θ/dt²| < 4°/s². Pitch rates come from the EKF attitude, because the Baldr export's gyros carry an uncorrected bias. The flap command must sit at the flight's median: the Baldr flap channel holds a constant per-flight offset of −9.5 to +7.7°.
- Regression: δe = c0 + c1·CL + c2·q̂ + c3·throttle, with one offset per flight when pooling and q̂ = (dθ/dt)·c/(2V). Standard errors are inflated ×2 for autocorrelation (indicative only).
- Elevator: Baldr = mean of the left/right actuator commands (deg); Thor = the pilot command `de_in` in manual mode (rad → deg). Neither is a measured surface angle. Logged sign is negative = trailing edge up; **the tables below show up elevator as positive**, the convention of the simulator's FT-05 tables.
- Masses and areas: Baldr 7.41 kg, 0.77 m², c 0.43 m; Thor 1.90 kg, 0.32 m², c 0.30 m (Dorobantu 2013, Table 2.1). Baldr's mass per configuration is not reported (±10 % on CL).
- Files in `research/flight-dynamics/power-climb/trim-practice/`:
  - Scripts: `trim_cl.py` (regression and bins), `sensitivity.py` (filter variants), `trim_curve.py` (loaders and the strict filter), `model_check.py` (published linear models), `inverted_push.py` (section 4), `handsoff.py` (section 5).
  - Outputs: `*_out.md` and `trim_curve_segments.csv`.

### Elevator per unit lift coefficient

| Data set | Quasi-steady time | CL (p5–p95) | dδe/dCL, up elevator (deg per unit CL) | Four filter variants | Label |
| --- | ---: | --- | ---: | --- | --- |
| Baldr (Ultra Stick 120, 7.4 kg), nominal CG, flights 12 (2016-11-02) and 14 (2017-09-29) | 182–192 s | 0.18–0.35 | **9.8 ± 0.6** (F12 9.9, F14 9.2) | 7.9–12.1 | D from M |
| Baldr, aft CG (333 g block removed), flight 17 (2017-10-05) | 84 s | 0.27–0.42 | **6.2 ± 0.6** | 5.2–7.2 | D from M |
| Baldr, aft CG, flight 15 | 22 s | 0.19–0.28 | 46: rejected (narrow CL, rms 1.1°) | – | – |
| Baldr, wing masses, flight 16 | 50 s | 0.15–0.22 | 14.5 (high speed only) | – | D from M |
| Thor (Ultra Stick 25e, 1.9 kg), 2012 flights 34, 44, 46, manual | 121 s | 0.29–0.51 | **6.7 ± 0.9** | 3.8–7.5 (depends on the throttle term) | D from M |
| Thor 2013–14, flights 97, 98, 104, manual | 120 s | 0.36–1.12 | wrong sign (−2.3): rejected | – | – |

Thor 2013–14 was rejected for three reasons. It flies circles near the stall. Its air data disagree with themselves: the CL-equivalent speed reads 2–3 m/s below the logged IAS, where the 2012 flights agree. And the pilot's elevator zero moved between campaigns: `de_in` has a median of −1 to −2.5° in 2012 and +1 to +1.8° in 2013–14. The aft-CG result is robust: in every filter variant flight 17 needs 30–50 % less elevator per unit CL than flights 12 and 14, the textbook signature of a smaller static margin.

### Level-flight trim curves (up elevator positive)

Baldr, nominal CG (Vs ≈ 11.1–11.8 m/s):

| Level-flight speed (m/s) | V/Vs | CL | Up elevator (deg) | Throttle | Samples: actual IAS, climb |
| --- | --- | ---: | ---: | ---: | --- |
| 19 | 1.6–1.7 | 0.41 | 6.0 (7 samples) | 0.56 | 18.1 m/s, +2.0 m/s |
| 21 | 1.8–1.9 | 0.35 | 5.2 | 0.52 | 19.9, +1.1 |
| 23 | 2.0 | 0.29 | 4.3 | 0.64 | 21.5, +2.1 |
| 25 | 2.1–2.3 | 0.25 | 3.4 | 0.67 | 24.0, +0.9 |
| 27 | 2.3–2.4 | 0.21 | 3.0 | 0.69 | 26.9, −0.5 |
| 29 | 2.5–2.6 | 0.18 | 3.1 | 0.79 | 28.1, +2.2 |
| 31 | 2.6–2.8 | 0.16 | 2.3 (9 samples) | 0.90 | 29.9, +0.8 |

Slope about **−0.43°/(m/s)** from 19 to 25 m/s and −0.1 to −0.2°/(m/s) above 25 m/s. The regression gives −0.52, −0.25 and −0.14°/(m/s) at 18, 23 and 28 m/s. A different Ultra Stick 120 ("Ibis", 8.34 kg) trims at **4.37° up at 19.2 m/s**, α 4.47°, θ 5.47° (Lie 2014, Appendix D.3, sign checked on the rendered page). That is the same order as Baldr's 6.0° at 19 m/s.

Thor, 2012 manual flights (Vs ≈ 8.7–9.3 m/s; `de_in`'s zero is a transmitter value, so read the differences):

| Level-flight speed (m/s) | CL | Up elevator (deg) | Change from 15 m/s | Throttle |
| --- | ---: | ---: | ---: | ---: |
| 13 | 0.53 | 1.9 (10 samples) | +0.6 | 0.61 |
| 15 | 0.41 | 1.3 | 0 | 0.78 |
| 17 | 0.33 | 1.0 | −0.3 | 0.80 |
| 19 | 0.29 | 0.5 (6 samples) | −0.8 | 0.92 |

The slope is about −0.2 to −0.3°/(m/s) at 15–17 m/s; the regression gives −0.26°/(m/s) at 17 m/s and −0.58 at 13 m/s.

### Static margin implied by the trim gradient

Trim requires Cm_δe·dδe/dCL = −dCm/dCL = static margin, with CL_δe neglected. With each published model's elevator power (`model_check.py`):

| Airframe | Cm_δe (/rad), from | Static margin from the model's Mw, Zw | Static margin from the measured trim gradient | Model level-flight dδe/dV at 19 m/s |
| --- | --- | ---: | ---: | ---: |
| Ultra Stick 25e | −0.96, Dorobantu identified A/B (eq. 3.25), Iy 0.144 kg·m² | 12.8 % MAC | **11.3 %** (2012 flights) | −0.20 to −0.28°/(m/s) |
| Ultra Stick 120 (Ibis, Lie App. D) | −0.50, Lie Table D.2, Iyy 1.0095 kg·m² | 13.2 % MAC | Baldr nominal **8.6 %**, aft CG **5.4 %** (Ibis Cm_δe applied to Baldr) | −0.26 to −0.43°/(m/s) |

The two routes agree within 2–5 % MAC. A 3 % MAC aft shift from removing a 333 g block from a 7.4 kg airplane needs the block about 0.29 m ahead of the CG, which is plausible. These margins are derived numbers, each resting on one identified Cm_δe.

### Dorobantu 2013, Ultra Stick 25e longitudinal results

| Item | Value | Where | Label |
| --- | --- | --- | --- |
| Baseline model (tunnel Ultra Stick Mini + US120 rate derivatives) | phugoid 0.48 rad/s, ζ 0.43; no oscillatory short period (real poles 13.70 and 29.28 rad/s) | Table 3.2, p. 26–27 | model |
| Identified (CIFER, frequency sweeps) | short period **16.33 rad/s (2.6 Hz), ζ 0.83**; phugoid 0.51 rad/s, ζ 0.38, "time constant" 12.32 s (= 2π/0.51, the undamped period) | Table 3.4, p. 38 | M (short period); **phugoid not identified** |
| LOES fit of q/δe | ω 17.3 rad/s, ζ 0.65, K −107.4, zero 14.5 rad/s; actuator second order 50.27 rad/s, ζ 0.80; 50 ms delay | p. 37 | M |
| Why no phugoid | "the 10 second experiment time window for Thor implies that the phugoid mode cannot be excited"; its derivatives are "fixed to their baseline values" | pp. 34–35 | – |
| Spiral | pole near 0.05 rad/s, baseline model, not excitable | Table 3.3, p. 28 | model |
| Inertia (bifilar) | Ix 0.089, Iy 0.144, Iz 0.162, Ixz 0.014 kg·m² | Table 3.1 | M |

The thesis gives no trim curve and no static margin. Its identified matrix implies Cm_α −0.70/rad, CL_α ≈ 5.4/rad and a 12.8 % margin. The eigenvalues reproduce Table 3.4: 16.32 rad/s with ζ 0.833, and 0.513 rad/s with ζ 0.385 (damped period 13.3 s).

### Light aircraft (secondary)

No tab-angle-versus-speed table was found. The nearest measured quantity is the stick-force gradient at fixed trim (section 1): 1 lbf per 3–7 kt in cruise for a C150M/C152 (M).

### What this means for the simulator

The FT-05 trim sweep gives these elevator changes between 1.6 Vs and 2.5 Vs:

| Aircraft (sim) | Elevator change, 1.6 → 2.5 Vs |
| --- | --- |
| Ugly Stik | 1.5° |
| Glow Stiks | 1.8–2.4° |
| Extra | 2.2° |
| P-51 | 1.3° |
| Ventage Jet | 1.6° |
| Timber | 4.8° |

Over the same range, the measured gradients predict 1.1–2.2° for the Ultra Stick 25e and 2.0–3.5° for the Ultra Stick 120 at nominal CG (1.3–2.1° aft), taking CLmax 1.10–1.26 from the FASER tunnel bound (factor 0.2306·CLmax). Expressed per unit CL with CLmax assumed at 1.1–1.5, the sim fleet's 4–10°/CL sits inside the measured 4–12°/CL band; the Timber's 14–19°/CL follows from its 23–26 % STOL-tail margin. The sim Stik's 6.9–7.6 % static margin lies between Baldr's nominal 8.6 % and aft 5.4 % and below Thor's 11–13 %. The simulated trim curves therefore have a realistic slope. Moving from the slow 1.6 Vs start to cruise costs a real Stik-class model about 1.5–3° of down trim, which is 15–30 presses at 0.1° each. For an exact comparison, the lead should redo the per-CL conversion with each aircraft's measured Vs instead of the assumed CLmax.

## 4. Inverted flight

### RC practice by airfoil class

| Class / quantity | Value | Source | Label |
| --- | --- | --- | --- |
| All: CG decides the push | "CG is the dominant factor determining how much elevator input is needed to sustain inverted flight"; "It is not normal to fly inverted without needing any down elevator input" | D. Pappas, *MA* Aug 2011, https://library.modelaviation.com/article/if-it-flies-201108 | H (magazine) |
| All: speed | "A lower airspeed also will require you to push more forward-elevator to hold the plane level" | D. Scott, "Secrets to Inverted Flight", *Model Airplane News* (updated 2019) | H (instructor) |
| (a) Symmetrical, pattern/scale aerobatic | roll inverted "at maximum power"; "a touch of down-elevator (acceptable for a 'sequence-prone' model)" | J. Glezellis, *MA* Feb 2015, https://library.modelaviation.com/article/rc-scale-aerobatics-201502 | H |
| (a) Pattern (Goldsmith) | forward CG shows as "excessive down elevator needed for inverted flight"; climbing on an inverted 45° line shows an aft CG | Goldsmith via M. Hurley, *MA* 2005 | H |
| (a) 3D | rearward CG "flies inverted virtually hands off"; "barely have to push the elevator stick forward"; hands-off at half throttle upright or inverted | GiantScaleNews thread 6332, 2013 | A |
| (a/b) Rule of thumb | about ⅛ of stick travel down inverted = CG near the "sweet spot"; Somenzini: move the CG back "until it takes just a little bit of down" | RCU threads (excerpt only) | A |
| (b) Big Stik 60 (semi-symmetrical) | "Inverted flight required very little down elevator movement" | *RCM* review, Feb 1988 | A (review) |
| (b) Ultra Stick 1.1 m / 30 cc / Giant Big Stik XL | "Nearly zero input needed on the elevator"; 30 cc has a "thick, fully symmetrical airfoil"; Big Stik XL "basically hands off!" | *MA* Aug 2025; *MA* May 2017; FlyingGiants (excerpt only) | A (reviews) |
| (c) Flat-bottom trainer | "very little" push is good, "lots, almost full stick" means adjust; one reply: about 90 % of stick | RCU thread 891937 (excerpt only) | A |
| (c) Kadet Senior | "performs inverted flight well" (no number) | G. Gimlick, *MA* Jul 2014 | A (review) |
| (c) Timber 1.5 m with slats | "the inverted capabilities will suffer most"; "the elevator feels 'heavy' during inverted flight"; outside loops need more height | Gimlick, *MA* Mar 2017 | A (review) |
| (c) UMX Turbo Timber | loops, rolls, inverted flight; reviewer mixed down elevator with flaps | T. Dunn, *Park Pilot*, Summer 2020 | A (review) |
| Goldsmith CG Method Two | "If a lot of down elevator is needed to maintain level flight, add tail weight. If little down elevator is needed, add nose weight" (no numbers) | trimming chart, row 3 | H |
| Extra throttle inverted | not quantified anywhere; tests are flown at full power or half throttle | – | – |

### Quantifying the check (D)

In body axes, inverted level flight needs CL_body = −CL. With a linear pitching moment Cm = Cm0 + Cm_CL·CL + Cm_δe·δe, Cm0 cancels in the difference (camber, decalage, and the thrust line at equal power), so the push from the upright trim at the same speed is **|Δδe| = 2·CL·dδe/dCL = 2·CL·SM/|Cm_δe|**. A neutral-margin model flies hands-off both ways, which matches the 3D folklore. Flat-bottom wings cost more than this linear value because they fly closer to their negative stall, trainers carry larger margins and fly slower (higher CL), and profile drag is higher at negative CL. Practitioner support: E. Müller, quoted in IAC *Sport Aerobatics* Sept 2020, p. 21: "trim halfway between hands-off in normal flight and hands-off inverted: we call this the zero-g trim."

Measured trim gradients and the simulator (`inverted_push.py`; sim masses = inventory sums of `app/data/aircraft/*.json` at fbf6e97b, sim gradients = FT-05 1.6→2.5 Vs change ÷ (0.2306·CLmax), CLmax 1.1–1.26 assumed):

| Airframe | Speed (m/s) | CL | dδe/dCL (deg) | Predicted push (deg) | Sim push, FT-05 (deg) |
| --- | ---: | ---: | --- | --- | ---: |
| Ultra Stick 25e, measured | 17.0 | 0.33 | 3.8–7.5 | 2.5–4.9 | – |
| Ultra Stick 120 nominal CG, measured | 23.0 | 0.29 | 7.9–12.1 | 4.6–7.0 | – |
| Ultra Stick 120 aft CG, measured | 23.0 | 0.29 | 5.2–7.2 | 3.0–4.2 | – |
| Sim Ugly Stik (2.88 kg) | 19.6 | 0.26 | 5.2–5.9 | 2.7–3.0 | **1.2** |
| Sim Extra 300S (3.58 kg) | 24.6 | 0.20 | 7.6–8.7 | 3.0–3.4 | 2.4 |
| Sim P-51D (21.5 kg) | 34.9 | 0.21 | 4.5–5.1 | 1.9–2.1 | 1.6 |
| Sim Ventage Jet (11.44 kg) | 43.9 | 0.14 | 5.5–6.3 | 1.5–1.7 | 1.3 |
| Sim Timber (2.19 kg) | 18.1 | 0.33 | 14–19 | 9.2–12.4 | 8.8 |

### Full-scale aerobatic aircraft

| Item | Value | Source | Label |
| --- | --- | --- | --- |
| Pitts S-1/S-2 stick force | "A typical S-1 or S-2, trimmed for level upright, takes 5 to 8 pounds of forward pressure inverted"; the Model 12 "very little" | E. Wischmeyer, *Kitplanes*, 8 Apr 2011 | H (flight-test review) |
| Pitts S-2B vs S-2C | S-2B: "there's not enough down trim to keep the thing level"; S-2C: "move the trim handle only about a quarter of an inch ... you can let go, inverted" | A. Marsh, *AOPA Pilot*, Apr 1998 | H (review); Kitplanes says the opposite for the S-2C, unattributed |
| Attitude and AoA | a symmetric wing needs about 2–3° AoA inverted, "equivalent to that required right side up"; asymmetric wings fly inverted "only in a noticeably nose-high attitude"; "strong stick forces"; the book advises against retrimming | Szurovy & Goulian, *Basic Aerobatics*, 1994, pp. 70–72 | H (its lift explanation uses the equal-transit fallacy) |
| Inverted cruise | aerobatic trainer 125 mph, intermediate 145, unlimited monoplane 170 | same, p. 69 | H |
| Flat-bottom wing | elevator neutral point at about "−3 to −5 degrees AOA on flat bottom wings" | IAC, Penner on Cassidy, iac.org/aerobatic-trim-2 | H |
| Citabria (NACA 4412) vs Decathlon (1412) | Citabria must "hold the nose well above the horizon for sustained inverted flight" | D. McConnell, *Sport Aerobatics* Aug 2017 (forum repost) | A |
| Extra 300L | inverted flight "limited to max 4 minutes"; knife edge and zero-g ≤ 10 s; oil pressure flickers 10–30 psi going inverted; MA 15 S / MA 12 S symmetric wing; elevator ±25°; trim tab 40° up / 50° down | Extra 300L Information Manual §2.8.2, PDF pp. 12, 20, 22–23, 57 | MF |
| Super Decathlon | inverted header tank ≈ 2 min at full power, refills in about 1 min upright; inverted oil pressure 5–10 psi lower | 8KCAB POH pp. 1-5, 3-15 to 3-17 | MF |
| Pitts S-2A | "no arbitrary limit on the duration of inverted flight"; +6/−3 g | A. Cassidy, AOPA Technical Companion, 2011, p. 4 | H |

### What this means for the simulator

The practice scale runs from "a touch" (symmetrical aerobatic at a good CG) through "very little" (Stik family) and about ⅛ stick at a well-placed CG, to "almost full stick" on flat-bottom trainers. The heavy-elevator note on the slatted Timber matches that ordering. The simulator reproduces the ordering (Stik 1.2°, P-51 1.6°, Extra 2.4°, Timber 8.8° at 0.6 Vmax; Timber two-thirds of the throw at the slow start). The linear check above, a derived test rather than a measurement, gives three points:

- The Extra, P-51, jet and Timber pushes are 75–95 % of the value their own trim curves imply, which is plausible.
- The Ugly Stik pushes only 1.2°, about 40 % of the 2.7–3.0° its own trim slope implies. That is 6 % of its ±20° throw, against the ⅛ stick (2.5°) rule. Both point the same way: the sim Stik's inverted push looks low. Check its Cm(α) or elevator effectiveness at negative α.
- The measured Ultra Sticks imply 2.5–7° (12–35 % of a ±20° throw) at cruise, more than every sim aircraft except the Timber.

The simulator's inverted throttle rises by 0–0.06 of the stick. No RC or full-scale source quantifies this, so it cannot be judged; physically, equal |CL| gives equal induced drag, and only the profile drag at negative CL (cambered wings) adds.

## 5. Keeping level flight hands-off

### RC: descriptions

| Claim | Source | Label |
| --- | --- | --- |
| A trimmed model should "fly straight-and-level for several hundred feet without pilot intervention", on a calm day (≈ 5–10 s at 15–20 m/s) | J. Wells, *MA* May 2022, https://www.modelaviation.com/content/art-trimming | H |
| "A well-trimmed primary trainer will often fly and land itself without constant manipulation" | J. Waterman, *MA* Dec 1988, https://library.modelaviation.com/article/rc-trainers | H |
| "let go of the control sticks and the LT-40 will recover itself and return to level flight within seconds" | SIG LT-40 product page, https://sigmfg.com/products/sig-lt-40-trainer-kit | MF (marketing) |
| "Some of your turns will fall off into a spiral because of overbanking" | Krueger 2017 club manual | A (instructor) |
| "Too much fin or not enough dihedral and you get spiral instability"; most models near-neutral or slightly spiral-unstable ("graveyard spiral") | D. Stackhouse, 1998, Charles River RC | A (designer) |
| "If it porpoises during the glide and/or balloons under power – add down-trim until it glides smoothly" | TurboParker guide to the UMX Radian, 2017 | A |
| Forward CG: strong pitch restoring, hands-off porpoising; aft CG oscillation dies in 1–2 cycles | RCU thread 311712 (excerpt only) | A |
| Hands-off windows on small UAS are short: 15–25 s (KHawk Zephyr3-R), ≈ 10 s on the Ultra Stick 25e "due to trimming requirements" | Matt et al., AIAA 2023-0628; Dorobantu 2013 | M (context) |

No RC source gives measured height or heading wander over 10–30 s.

### RC: measured phugoid

| Airframe | Condition | Phugoid | Source | Label |
| --- | --- | --- | --- | --- |
| Ultra Stick 120 (Baldr F12), elevator fixed at its −3.07° trim, throttle 0.69, mean bank 8° | 16 s window after a turn exit, 23.7 m/s mean | IAS 21.7–27.6 m/s (swing 6.1 m/s), pitch swing 14°, height +27 m (range 32 m); fitted period **13.6 s** (Lanchester 10.7 s), ζ ≈ 0.1 over one cycle | `handsoff.py` | D from M |
| Ultra Stick 120 (F15, F17), aft CG, bank 22–25° | 10–13 s windows, 17–26 m/s | period 9.4–10.6 s, swings 5–10 m/s and 22–28° | same | D from M (turning) |
| Ultra Stick 25e (Thor F44), elevator fixed | 12 s, 17.9 m/s | IAS swing 3.6 m/s, pitch 8°, height range 16 m; period **8.0 s** (Lanchester 8.2 s) | same | D from M |
| KHawk Zephyr3-R flying wing, 2.18 kg | cruise 15–17 m/s | ωn 0.809 rad/s, ζ 0.13 (frequency domain); 7-peak time domain ωd 0.719 ± 0.075 rad/s (≈ 8.7 s), ζ 0.10 ± 0.08 | Matt, Chao, Shawon, Hagerott, Svoboda, AIAA SciTech 2023, doi 10.2514/6.2023-0628, Tables 3 and 5 | M |
| Ultra Stick 25e | 19 m/s | 0.48–0.51 rad/s, ζ 0.38–0.43 (12–13 s) | Dorobantu 2013 | model only |
| Ultra Stick 120 (Ibis) | 19.2 m/s | 0.348 rad/s, ζ 0.29 (18.9 s), from Lie Table D.2 eigenvalues | `model_check.py` | model (D) |
| Kadet Senior UAV (XFLR5) | 15 m/s | ωn 0.33 rad/s, ζ 0.63 | Jimenez, Silva, Hernandez, EUCASS 2017-411 | model, suspect (Lanchester ≈ 0.92 rad/s) |

Only 40 s of hands-off, near-wings-level data exist in the six Baldr and six Thor flights; the pilots almost never leave the elevator alone for more than 10 s. Each fit spans one to one and a half cycles, so the damping is poorly determined.

### Light aircraft

| Airframe | Condition | Value | Source | Label |
| --- | --- | --- | --- | --- |
| Cessna 172S, 2300 lb | cruise 110 KIAS, 2500 rpm; controls released after a 2 kgf out-of-trim push | phugoid "heavily damped with a period of 35-40 seconds"; first cycle ±2500 ft/min, ±300 ft, ±25 KIAS, ±1500 rpm | AAIB Bulletin 12/2020, G-CBXJ, pp. 26–28 | M (test pilot) |
| Same, hands-off lateral | cruise | strong dihedral and weathercock stability, but after a 2 cm right-rudder input "a spiral dive within 10 to 15 seconds" | same | M (qualitative) |
| Navion, 2750 lb | sea level, 53.6 m/s, CL 0.41 | phugoid ω 0.2137 rad/s, ζ 0.0801 (period 29.5 s, half amplitude 40.5 s); spiral stable, 1/T 0.00876/s (τ ≈ 114 s); short period 3.61 rad/s, ζ 0.70; Dutch roll 2.39 rad/s, ζ 0.20 | Teper 1969, NASA CR-96008, Fig./Tables X, p. 103 | H |
| Piper PA-28-180 | 50 m/s | phugoid ωn 0.247 rad/s, ζ 0.113 (25.6 s); spiral unstable, time to double 35.6 s | H. Smith, aircraftflightmechanics.com | H (online text, derivatives not cited) |
| Hands-off guidance | after a push "a series of slow pitching oscillations follows"; spiral divergence "so gradual the pilot can control the tendency without any difficulty"; "an aircraft cannot be flown 'hands off' indefinitely" | FAA-H-8083-25B ch. 5, pp. 5-17 to 5-20 | H |
| MIL-F-8785C | phugoid ζ ≥ 0.04 (Level 1); spiral time-to-double limits unverified | COBEM 2009 (secondary) | H (secondary) |

Lanchester's period, π√2·V/g ≈ 0.453·V s, is short of the measured values: 24.3 s for the Navion against 29.5 s (×1.21), and 25.6 s for the C172S against 35–40 s (×1.4–1.6). The RC measurements give ×1.0 (Thor), ×1.15–1.2 (KHawk) and ×1.27 (Baldr).

### Derived wander estimates (D)

- Phugoid height swing from the energy exchange: Δh ≈ V·Δu/g. A 2 m/s speed error at 16 m/s gives about ±3 m.
- Heading drift from residual bank: a 1° bank at 16 m/s turns at 0.61°/s, about 12° in 20 s; 2° of bank gives about 25° in 20 s.
- Phugoid damping estimate ζ ≈ 1/(√2·L/D) gives 0.09–0.14 for L/D 5–8.

### Commercial RC simulators and real autopilots

| Product | Start state | Trim | Source | Label |
| --- | --- | --- | --- | --- |
| RealFlight 9.5 / Evolution | Reset (space) returns to the "original takeoff position" (runway); "Remember Aircraft Position" (P) saves speed, attitude, heading for in-air restarts (temporary) | trims are the pilot's (transmitter or InterLink trim tabs, "trim memory within the simulation"); no auto-trim documented; "Autopilot Assist" levels the wings when the sticks are released; a "Servo Trim" failure can be injected; "The aircraft will climb when the throttle is increased" | RealFlight 9.5 manual pp. 35, 62–63, 73–74, 153–155, ~343; Evolution Help Guide 2024 | MF |
| RealFlight (forum) | – | trims saved per model; a `resettrims` console command exists | forums.realflight.com thread 27986 (2012) | A |
| RealFlight 6.5 (club manual) | – | "the program usually sets nominal pitch and roll trim so the airplane climbs slightly with wings level at high power with neutral sticks" | Krueger 2017 | A |
| Aerofly RC 7/8/10 | start positions per scenery; gliders by winch or helper, or dropped from 2 m or 50 m; auto-reset to start after a crash | the word "trim" does not appear in the RC7/RC8 manuals or the RC10 web manual; servo "Offset" in the model editor | IKARUS manuals 2015, 2018; https://www.ikarus.net/en/rc10-manual/ | MF |
| PicaSim (open source) | launched into the wind at "Launch speed" (default 6 m/s, 0–40 m/s) plus a launch angle | each model's XML carries a fixed `trimControl` bias (Spitfire −0.04): pre-trimmed by its author; on-screen trim off by default | github.com/Rowlhouse/PicaSim (Aeroplane.cpp, Wing.cpp, GameSettings.cpp) | source code |
| ClearView RC | `initModelPos`/`initModelRot`, `initSpeedVect` for hand launch | `elevCompCoef` "adds slight up trim so plane flies level" | ClearView manual v4.77 (2007); model parameter page | MF |
| Phoenix RC, neXt CGM, FMS | – | no manual found | – | – |
| ArduPlane | – | `SERVO_AUTO_TRIM` rewrites trims every 10 s with no pilot input, near-level, > 8 m/s, within about 20 % of travel; does not fix a wrong CG | https://ardupilot.org/plane/docs/auto-trim.html | MF |
| PX4 | – | `FW_DTRIM_*` adds trim at minimum and maximum airspeed and interpolates; nose-down moment "increases with airspeed" | https://docs.px4.io/main/en/config_fw/trimming_guide_fixedwing | MF |

### What this means for the simulator

**Phugoid period.** The sim's periods of 6.7–16 s at the start speed are 1.2–1.5 × Lanchester (FT-05). Every measured reference sits at 1.0–1.6 × Lanchester (RC 1.0–1.27, Navion 1.21, C172S 1.4–1.6), so the periods are realistic.

**Phugoid damping.** At the start speed the sim's ζ is 0.09–0.63, and at 0.8 Vmax it is 0.42–0.93 or overdamped. The measured light-aircraft values are 0.08–0.11, plus the C172S's qualitative "heavily damped". The RC values are 0.10–0.13 (KHawk) and roughly 0.0–0.3 from one-cycle Baldr and Thor fits. The sim's damping at cruise (Stik MAX-61FX 0.63 at the start, overdamped at 0.8 Vmax; Extra 0.48 and 0.93) is above every measured value. A real Stik-class model should porpoise visibly for two or three cycles after a disturbance: a ±3–6 m/s speed swing with ±10–30 m of height on the Ultra Stick 120. This is a candidate finding, not a verdict: the RC damping data are thin.

**Spiral.** The hands-off heading changes in FT-05 are 330–851° in 30 s on the Extra, Jet and Timber, roughly 11–28°/s. The measured references are different:

- Even a full-scale C172 needs a deliberate rudder input to enter a spiral dive in 10–15 s.
- The Navion is spirally stable.
- High-wing trainers are sold as self-recovering (LT-40).
- Designers call most models near-neutral or slightly spiral-divergent.

The Timber, a high-wing STOL airplane, diverging fastest is suspicious. It is consistent with the open fleet adoption of the D10-R5 dihedral-effect law, and is worth a lateral check by its owner.

**Start trim.** The commercial simulators start on the runway or at a saved state. They ship each model with an author-set fixed trim, keep the trim the pilot sets (per model), and neither auto-trim nor schedule trim with speed. Only autopilots do (ArduPilot `SERVO_AUTO_TRIM`, PX4 `FW_DTRIM`). The simulator's solved start trim with a pilot-only trim afterwards is at least as principled as theirs. Keeping the trim fixed matches both real radios and those products.

## Sources

| # | Source | URL / local file | Caveat |
| --- | --- | --- | --- |
| 1 | FAA, *Airplane Flying Handbook* FAA-H-8083-3C, ch. 3 (2021) and ch. 4 | `references/rc-trim-practice/a-faa-afh-ch3-basic-flight-maneuvers-2021.pdf`; faa.gov | H: doctrine, no numbers on trim travel |
| 2 | FAA, *Pilot's Handbook of Aeronautical Knowledge* FAA-H-8083-25B, ch. 5–6 (2016) | https://www.faa.gov/sites/faa.gov/files/07_phak_ch5.pdf | H: qualitative |
| 3 | E-flite Apprentice STS 1.5 m manual EFL3700 (Horizon Hobby, 2019) | local `a-eflite-apprentice-sts-...pdf` | MF: trim point, not a measured cruise |
| 4 | E-flite manuals EFL11450, EFL13950, EFL5250, EFL105250, EFL01250, EFL8750, EFL7950, EFL12750 (2018–2021) | horizonhobby.com …/Manuals/<SKU>-Manual-EN.pdf (read by the search agent, not saved) | MF: trim instructions only |
| 5 | Great Planes PT-20/PT-40 Mk II kit manual v1.2 (2004), incl. *Scale R/C Modeler* Aug 1983 chart | local `a-greatplanes-pt20-pt40-...pdf` | MF / H: design intent, not measured |
| 6 | Goldsmith aerobatic trimming chart (BMFA copy, 2006); Hurley, *MA* Feb/Apr 2005 | local `a-goldsmith-...pdf`; msrm.bmfa.uk Goldsmith-Trimming-Article.pdf | H: procedure, no numbers |
| 7 | D. Pappas, *Model Aviation* Jul and Aug 2006; Aug 2011 | library.modelaviation.com/article/if-it-flies-201108 (2011) | H (magazine) |
| 8 | J. Glezellis, *MA* Dec 2022 "Aircraft trimming"; Feb 2015 scale aerobatics | https://www.modelaviation.com/aircraft-trimming; library.modelaviation.com/article/rc-scale-aerobatics-201502 | H |
| 9 | EdgeTX manual, trims | https://manual.edgetx.org/color-radios/model-settings/model-setup/trims | MF |
| 10 | Sig Mfg product pages (LT-40, Kadet Mk II, Four Star 40) | sigmfg.com | MF (catalog) |
| 11 | D. Scott, *MA* Aug 2013; "Secrets to Inverted Flight", *Model Airplane News* (2019) | print/web, URL not retained | H (instructor) |
| 12 | Fly RC, "Aerobatic Trimming" (2011); GiantScaleNews, RCU, FlyingGiants threads | various | A; RCU/FlyingGiants excerpt only |
| 13 | ArduPilot `ArduPlane/config.h` and docs (tuning-cruise, auto-trim); iNav settings.yaml; PX4 trimming guide | github.com/ArduPilot/ardupilot; ardupilot.org/plane/docs/; github.com/iNavFlight/inav; docs.px4.io | autopilot defaults, not aircraft data |
| 14 | G. Gimlick, *MA* Dec 2006, Jul 2014, Mar 2017, Jul 2020; T. Dunn, *Park Pilot* 2020; *MA* Aug 2025, May 2017; *RCM* Feb 1988 | print | A/M: reviews; current logs only |
| 15 | Cessna 172S Information Manual (1998, rev. 5 2004), Fig. 5-8, pp. 3-15/16 | URL not retained | MF |
| 16 | Bromfield & Gratton, *Aeronautical Journal* 116(1179), 2012 (C150M/C152 stability tests) | print | M |
| 17 | 14 CFR 25.173; 14 CFR 23.173/175 (2014 edition) | law.cornell.edu; govinfo.gov | H |
| 18 | UMN UAV Lab flight logs: Baldr F12, F13 (2016-11-02), F14–F16 (2017-09-29), F17 (2017-10-05); Thor F34, F44, F46 (2012), F97, F98 (2013-11-05), F104 (2014-03-08) | `references/rc-validation-library-2026-10-18/ugly-stik/{university-flight-data,baldr-configurations}/`, `.../stik-analogues/logs/` | M: commanded, not measured, surfaces; few steady seconds; electric |
| 19 | A. Dorobantu, PhD thesis, UMN 2013; Dorobantu, Murch, Mettler, Balas 2012 (sys-id paper) | `references/rc-aero-data/dorobantu-2013-...pdf`, `dorobantu-2012-...pdf` | M (short period); phugoid not identified |
| 20 | H. Lie, PhD thesis, UMN 2014, Appendix D (Ultra Stick 120 "Ibis") | `references/rc-aero-data/lie-2014-...pdf` | identified linear model |
| 21 | Matt et al., KHawk Zephyr3-R, AIAA 2023-0628 | https://engrxiv.org/preprint/download/4463/7761/6406 | M (flying wing, not a Stik) |
| 22 | AAIB Bulletin 12/2020, G-CBXJ | local `c-aaib-...pdf` | M: one airplane, test-pilot observations |
| 23 | G. L. Teper, NASA CR-96008, 1969 (Navion) | local `c-teper-...pdf` | H: derivative-based modes |
| 24 | H. Smith, PA-28 example | https://aircraftflightmechanics.com/Dynamics/CherokeeExample.html | H: derivatives not cited |
| 25 | Szurovy & Goulian, *Basic Aerobatics*, ch. 7 (1994) | local `b-szurovy-goulian-...pdf` | H: flawed lift explanation |
| 26 | Extra 300L Information Manual; Super Decathlon 8KCAB POH; Cassidy, AOPA Pitts S-2A Technical Companion (2011) | local `b-extra-300l-...pdf`; flythedecathlon.com; skybrary.aero bookshelf 2757 | MF / H |
| 27 | Wischmeyer, *Kitplanes* 2011; Marsh, *AOPA Pilot* 1998; IAC *Sport Aerobatics* Sept 2020 and Aug 2017; iac.org/aerobatic-trim-2 | print/web | H/A: reviews; S-2C conflict |
| 28 | Caughey, Cornell MAE 5070 notes, ch. 3 | courses.cit.cornell.edu/mae5070/StaticLongitudinal.pdf | textbook |
| 29 | RealFlight 9.5 manual; RealFlight Evolution Help Guide 2024 | local `c-horizon-hobby-realflight-9-5-manual.pdf`; shared.steamstatic.com …/RealFlight_Help_Guide.pdf | MF |
| 30 | Aerofly RC7/RC8 manuals, RC10 web manual; PicaSim source; ClearView manual v4.77 | ikarus.net; github.com/Rowlhouse/PicaSim; rcflightsim.com | MF / source code |
| 31 | Krueger, Coachella Valley RC Club manual 2017; Stackhouse 1998; Wells *MA* 2022; Waterman *MA* 1988; SIG LT-40 page | cvrcclub.com; charlesriverrc.org; modelaviation.com; sigmfg.com | H/A |

## Not found

- **A trim speed.** No primary source gives the speed at which RC models are trimmed, only throttle fractions. No measured cruise stick exists for a glow .60, a 120 cc gasoline warbird or a turbine sport jet; no turbine ECU cruise log; no electric log pairing stick % with current.
- **Dave Scott and Lennon.** Dave Scott's trimming articles and *Model Airplane News* CG/inverted articles were paywalled or not found; Lennon's *Basics of R/C Model Aircraft Design* had no accessible text.
- **Charts and kit data.** No NSRCA or "Kirk" trimming chart; no IMAC throttle→elevator percentages beyond anecdotes; no Hangar 9 Ultra Stick, Sig LT-40 or Ugly Stik manual text on trim; the PT-40 downthrust angle is not printed.
- **Light-aircraft trim travel.** No trim-wheel turns or tab degrees per knot for a light aircraft; AC 23-8C not read. Jet cruise N1 not verified.
- **Measured RC inverted elevator, and inverted throttle.** No measured RC elevator upright versus inverted, and no source quantifying extra throttle inverted. No Extra 330, Cap 232 or Su-26 inverted stick-force numbers; no Pitts S-2B POH.
- **RC hands-off wander and spiral data.** No measured RC hands-off height or heading wander over 10–30 s. No measured RC spiral time constant. No measured C172 damping ratio or spiral time constant (only the AAIB qualitative account). No Beard & McLain Aerosonde eigenvalues or primary MIL-F-8785C spiral limits.
- **Simulator manuals.** No manual found for Phoenix RC, neXt CGM or FMS; no RealFlight aircraft-editor trim or incidence parameters documented.
- **Blocked.** RCUniverse (403), RCGroups and FlyingGiants (tollbit redirect), manualslib (403), Smithsonian (403); anything cited from them is an excerpt only.
- **Unusable logs.** In the UMN logs, Baldr flight 9 (2015) has constant elevator and throttle channels, and the Thor 2013–14 flights give an inconsistent trim gradient (section 3).
