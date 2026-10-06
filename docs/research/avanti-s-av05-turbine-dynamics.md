# Avanti S AV-05: JetCat P100-RX thrust, spool and throttle model

2026-10-06 · AV-05 research · **Research done; no app change.** Steady thrust(rpm), the ECU throttle law and the speed lapse are supported by P100 or JetCat-ECU data. Spool rates, installed losses, rotor inertia and the fuel-cut rundown are labelled estimates calibrated to the ranges below.

Baseline: JetCat P100-RX, 2017 catalog, non-BL (see [avanti-s-turbine-research.md](avanti-s-turbine-research.md)). Labels: **measured** (a test of a real engine; "fit" = coefficients identified from that test), **manufacturer**, **derived** (computed here from cited data), **estimate** (engineering judgement with stated reasoning). "Other engine" marks JetCat data that is not from a P100.

## 1. Baseline confirmed

The 2017 catalog table was re-read: 44,000/154,000 rpm, 2/100 N, 80/390 ml/min (0.064/0.312 kg/min), 0.23 kg/s, 1565 km/h, pressure ratio 2.9, 1080 g "incl. valves", 97 × 241 mm, all "at STP ±3 %; 15 °C, 1013 mbar". Additional values from the same table:

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| EGT range, idle to max | 490–720 | °C | manufacturer | [JetCat catalog 2017](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf), p. 26 |
| SFC at max rpm | 0.187 | kg/(N·h) | manufacturer | same |
| Fuel | "Jet-A1 with 5 % oil" | – | manufacturer | same |
| Nozzle outer diameter, nozzle length | 60, 40 | mm | manufacturer (drawing) | [JetCat P100 RX Size.PDF](https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX%20Size.PDF) |
| Measured static thrust, idle / top step (Ohio, ambient not given) | ≈2.6 / ≈95.5 | N | measured (read from plot) | [Wright et al. 2023, Fig. 7](https://arxiv.org/pdf/2312.09978) |

## 2. Steady thrust, air flow and fuel vs rpm

No P100 thrust-vs-rpm table was found. Two P100 papers fit thrust to rpm, but their coefficients are unusable: TUM's quartic map does not reproduce 100 N as printed, and the IIT model uses PWM as input. JetCat's own ECU data on the P160 and P220 gives a power law with an offset, `T = a·ω^b + c` (ω in krpm), with **b = 3.136 and 3.205** and RMSE of 1.2 and 2.05 N ([Momin et al. 2022, Table V](https://arxiv.org/pdf/2205.08330)). A pure power law through the two P100 catalog points gives **b = ln(100/2)/ln(154/44) = 3.12**. Normalised, it matches the P160/P220 measured shapes within 2 % of max thrust from 50 % rpm upward. Thrust is **not ∝ rpm²**. One P100 paper's remark that thrust is "approximately quadratic" in shaft speed is a modelling motivation, not a fit.

| rpm | n/n_max | Thrust `100·(n/154k)^3.12` | P160 shape (other engine) | Air flow `0.23·n/154k` | Fuel (estimate) | Jet velocity F/ṁ |
| --- | --- | --- | --- | --- | --- | --- |
| 44,000 | 0.286 | 2.0 N | 4.7 % | 0.066 kg/s | 80 ml/min | 31 m/s |
| 50,000 | 0.325 | 3.0 N | 5.6 % | 0.075 | 83 | 40 |
| 70,000 | 0.455 | 8.5 N | 11.0 % | 0.105 | 101 | 82 |
| 90,000 | 0.584 | 18.7 N | 20.8 % | 0.134 | 133 | 139 |
| 110,000 | 0.714 | 35.0 N | 36.6 % | 0.164 | 184 | 213 |
| 130,000 | 0.844 | 58.9 N | 59.9 % | 0.194 | 260 | 304 |
| 154,000 | 1.000 | 100 N | 100 % | 0.230 | 390 | 435 |

- Thrust column: **derived** from the manufacturer endpoints, with the exponent supported by **measured** P160/P220 fits.
- Air flow: **derived**. TUM identified a P100 compressor flow linear in shaft speed, ṁ₃ = ṁ₃,₁·n, with ṁ₃,₁ = 1.46e-6 kg/s/rpm, giving ≈0.225 kg/s at 154k ([Many et al. 2021, Tab. 5](https://www.dglr.de/publikationen/2022/550281.pdf)). The column anchors that linear law to the catalog 0.23 kg/s.
- Fuel: **estimate**, linear in thrust between the catalog points. It implies SFC ≈0.22 kg/(N·h) at 50 N, against 0.187 at max, the expected part-load rise. No P100 fuel-vs-rpm data was found.

## 3. Throttle mapping (stick → rpm demand)

| Fact | Label | Source |
| --- | --- | --- |
| "ThrStick Curve — Gaskurve, Werkseinstellung ist 3.0. Bei diesem Wert verlaufen Schub und Gasknüppelstellung proportional. Beim Wert 1.0 ist die Drehzahl proportional zur Gasknüppelstellung. Bereich 0.1 bis 5.0" | manufacturer | [JetCat RX manual (DE), Limits menu, p. 49](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf) |
| Without an airspeed sensor the ECU always runs "Thrust-control": "vom Piloten über den Gasknüppel direkt der Turbinenschub vorgegeben" | manufacturer | same, Anhang Airspeed-Sensor |
| Stick idle = "Minimum RPM" (idle rpm), full stick = "Maximum RPM" | manufacturer | same, Limits menu |
| JetCat ECU maps input u ∈ [0, 100] to an rpm set-point and closes a loop on pump voltage. In thrust-proportional mode the measured steady state is `ω = a1·u^b1 + c1` with **b1 = 0.3338 (P160) and 0.3332 (P220)**, c1 = idle krpm, R² 99.92 % | measured, other engine | [Momin et al. 2022, Sec. II-C, Table III](https://arxiv.org/pdf/2205.08330) |

Inference (**derived**): the curve parameter c acts as `n_cmd = n_idle + (n_max − n_idle)·s^(1/c)`, with s the stick from 0 to 1. With c = 1 the manual's "rpm proportional" holds exactly, and with c = 3 the result is the measured exponent of 1/3. Applied to the P100 thrust law, half stick gives ≈61 % thrust and quarter stick ≈38 %. JetCat's "thrust-proportional" is therefore approximate, and the P160 fit gives the same 61 %. The P100 identified models (IIT, TUM) show thrust nearly linear in PWM, but their PWM endpoints relative to the ECU's learned stick range are not stated: idle sat at 25 % (IIT) and 33 % (TUM). They do not settle the question.

## 4. Spool dynamics

| Evidence | Value | Label | Source |
| --- | --- | --- | --- |
| P100 thrust/throttle corner frequency, multi-sine, 46–85 % throttle | ≈0.4 Hz (first-order τ ≈ 0.4 s) | measured | [Many et al. 2021, Sec. 3.3](https://www.dglr.de/publikationen/2022/550281.pdf) |
| Same engine, step-based estimate | ≈1 Hz (τ ≈ 0.16 s) | measured | same |
| Large sweeps: "the engine could not follow the directed throttle input anymore" above ≈0.6 Hz; smaller amplitudes followed up to ≈1.2 Hz | amplitude-dependent bandwidth, i.e. **rate limiting** | measured | same |
| P100 second-order thrust model, Table IV EKF parameters, simulated here: 15 → 73 N in 2.0 s with a convex rising curve; down 87 → 15 N reaches 63 % in 0.7 s and 90 % in 1.4 s | up slower than down; acceleration grows with rpm | derived from measured fit | [L'Erario et al. 2020](https://arxiv.org/pdf/1909.13296) |
| P100 bench step traces: up-steps of 14–35 N take ≈2–3 s; an 88 → 58 N down-step ≈2 s; from idle the first step is slowest. The command ramp of the test's microcontroller is unknown, so these are upper bounds | seconds, not tenths | measured (read from plots) | [Wright et al. 2023, Figs. 6–7](https://arxiv.org/pdf/2312.09978) |
| ECU options: IdleThrResponse Fast/Normal/Slow ("Slow ≈ old P160 and already very fast"); FullThrResponse Normal/Fast acts "ab ca. 70000 U/min". The manual says "Standard RX-Einstellung ist Normal" on p. 13 but marks "Fast (=Standardeinstellung)" in the Limits table | two regimes; no seconds given | manufacturer | [JetCat RX manual, pp. 12–13, 49](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf) |
| Low-idle → idle: "benötigt die Turbine je nach Type 2–5 Sekunden" | 2–5 s | manufacturer | same, Limits menu |
| JetCat PRO engines: idle → max "5 s (5 % to 95 % thrust)", deceleration to idle 5 s (95 → 5 %) | 5 s each | manufacturer, other engine (250 N) | [P250-PRO-S technical information](https://www.jetcat.de/jetcat/anleitungen/JetCat-P250-PRO-Basic-Technical-Information-V1-2.pdf) |
| Scaling: spool time ∝ Jω²/P ∝ rotor diameter. P100 ≈0.6× the P250 diameter gives ≈3 s for 5 → 95 % | ≈3 s | derived (estimate) | – |
| Forum reports of P120/P160 idle → full 3.3–4 s, surfaced by search; the pages were not readable (HTTP 403) | 3–4 s | anecdotal, unverified | RCU threads, not linked |

## 5. Thrust vs flight speed

Net thrust is `F = ṁ_g·V8 − ṁ_a·V0` for an adapted nozzle ([Many et al. 2021, Eq. 18](https://www.dglr.de/publikationen/2022/550281.pdf); [NASA Glenn](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/)). The ECU holds rpm, so ram raises inlet total pressure, mass flow and nozzle pressure ratio together. No measured P100 (or JetCat) thrust-vs-airspeed data was found. Table **derived** from a fixed-rpm cycle model: corrected flow constant, isentropic nozzle, EGT fixed at the catalog value for that rpm, ideal ram recovery. The naive `F_static − ṁV` bound is shown alongside.

| rpm | V = 0 | 20 m/s | 40 m/s | 60 m/s | 70 m/s | 85 m/s | Naive at 70 m/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 154,000 | 100 N | 96.0 | 93.0 | 91.2 | 90.6 | 90.2 | 83.9 |
| 130,000 | 58.9 | 55.6 | 53.3 | 51.9 | 51.6 | 51.5 | 45.4 |
| 110,000 | 35.0 | 32.3 | 30.6 | 29.8 | 29.8 | 30.0 | 23.5 |
| 44,000 (idle) | 2.0 | 1.6 | 2.1 | 2.8 | 3.2 | 3.9 | −2.6 |

At full power the lapse is ≈9 % at 70 m/s, or 10–11 % with 80 % ram recovery; the bound is 16 %. At idle the sign is uncertain. Holding EGT fixed makes the hot core act like a weak ramjet, which inflates idle thrust. In reality the ECU cuts fuel to hold idle rpm against the ram, pushing behaviour toward a cold duct, where net thrust ≈ 0.

## 6. Installed losses (intake ducts + thrust tube)

| Item | Value | Label | Source / reasoning |
| --- | --- | --- | --- |
| Correct engine-to-tube gap: "Schubverlust gleich Null oder sehr klein"; gap too small: "hoher Schubverlust"; too large: recirculation and "Schubverlust" | qualitative | manufacturer | [JetCat RX manual, p. 60](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf) |
| Bad duct systems or long tubes can cause compressor stall on fast throttle → use FullThrResponse "Normal" | qualitative | manufacturer | same, p. 13 |
| Thrust sensitivity to intake total-pressure loss at fixed rpm (ṁ ∝ pt2, V8 from NPR 1.41) | ≈2.4 % thrust per 1 % pressure loss | derived | cycle above |
| Fuselage side intakes + single-wall tube, static | **0.92** of bare thrust (range 0.85–0.97) | estimate | 1–3 % duct pressure loss → 2.5–7 % thrust, plus 0–5 % tube friction/mixing. No measured model-jet tube data found |

## 7. Rotor and gyroscopic momentum

| Quantity | Value | Unit | Label | Source / reasoning |
| --- | --- | --- | --- | --- |
| Rotor inertia used by TUM (assumed, not measured): ½ · 0.2 kg · (0.025 m)² | 6.25e-5 | kg·m² | estimate (third party) | [Many et al. 2021, Tab. 2](https://www.dglr.de/publikationen/2022/550281.pdf) |
| Compressor tip diameter | 55–62 | mm | estimate | PR 2.9 at η ≈ 0.75 needs Δh ≈ 137 kJ/kg; work coefficient 0.6–0.7 → U ≈ 440–480 m/s at 154k rpm. KJ66 (110 mm OD) uses a 66 mm wheel ([GTBA](https://www.gtba.co.uk/engine_designs/kj66.htm)). No P100 figure found |
| Rotating assembly: Al impeller ≈45 g, Inconel axial turbine ≈70 g, r ≈ 28–30 mm | J ≈ **3.5e-5** (range 2e-5–6.25e-5) | kg·m² | estimate | k·m·r² with k = 0.3 (impeller), 0.4 (disc) |
| Angular momentum at 154k rpm (ω = 16,127 rad/s) | **0.56** (0.32–1.0) | N·m·s | derived from estimate | H = Jω |
| Gyroscopic moment at 3 rad/s body rate | ≈1.7 (1.0–3.0) | N·m | derived from estimate | M = Ω × H |
| Rotation direction | unknown | – | not found | JetCat manuals, catalog and drawings checked; not stated |
| Compressor power at max (consistency check) | ≈31.6 | kW | derived | ṁ·cp·ΔT, ΔT = 288·(2.9^0.286 − 1)/0.75 |

## 8. Idle, shutdown, flameout, taxi

| Fact | Value | Label | Source |
| --- | --- | --- | --- |
| Auto-off: rpm held at ≈55,000 then shut off after ≈6 s; starter cool-down until EGT < 100 °C | – | manufacturer | [JetCat RX manual, p. 31](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf) |
| SlowDown state: pump off, kero valve closed, stays until rpm < 800 and EGT < 95 °C | – | manufacturer | [JetCat RX/RXi manual 2015, p. 38](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_RXi_120218.pdf) |
| Low-battery/fuel warning: above 50 % stick the ECU drops to idle for 5 s, back for 10 s, repeating (off by default) | – | manufacturer | RX manual p. 32 |
| Fuel-cut rundown, max → idle speed: compressor power ∝ n³ with no turbine work gives dn/dt = −n²/(n_max·t_c), t_c = Jω_max²/P_c ≈ 0.29–0.52 s → idle speed in **0.7–1.3 s**; thrust < 10 % in < 0.5 s | – | derived (lower bound: residual turbine work slows it) | – |
| Coast below idle to near-stop | ≈10–30 s | estimate | bearing/windage only; in flight, ram may keep it windmilling. No data |
| Taxi: catalog idle 2 N, measured ≈2.6 N vs rolling resistance of a ≈13 kg model: 2.6–5 N on pavement (C_rr 0.02–0.04), ≈13 N on mown grass (C_rr 0.10, project ground data) | idle taxis on pavement only; grass needs ≈80k rpm (≈13 N) | derived | `app/data/ground/surface_friction.json` |

## 9. Fuel density and tank

| Quantity | Value | Unit | Label | Source |
| --- | --- | --- | --- | --- |
| Jet A-1 at 15 °C, typical / spec range | 0.804 / 0.775–0.840 | kg/L | manufacturer (spec) | [Wikipedia, Jet fuel](https://en.wikipedia.org/wiki/Jet_fuel) |
| Turbine oil (Mobil Jet Oil II) at 15 °C | 1.0035 | kg/L | manufacturer | [ExxonMobil PDS](https://www.exxonmobil.com/en/aviation/products-and-services/Products/mobil-jet-oil-ii) |
| Jet A-1 + 5 % oil | **0.814** | kg/L | derived | volume-weighted mix |
| Density implied by the JetCat table (0.312 kg/min ÷ 0.390 L/min) | 0.80 | kg/L | manufacturer (implied) | catalog 2017 |
| Avanti S A200 tank capacity | not published by SebArt | – | – | [controls and installation](avanti-s-controls-and-installation.md) |
| Forum: replacement main tank "same physical size and capacity at 150 oz" (≈4.4 L); another at ≈136 oz (≈4.0 L) | ≈4.0–4.4 L | anecdotal | RCU thread "sebart avanti s fuel tank option" (Dec 2014; URL not recovered) |
| Fuel mass at 4.0 L; endurance at full / ≈half thrust | 3.3 kg; ≈10 / ≈17 min | derived | 0.814 kg/L; 390 / ≈232 ml/min (50 N) |

## Recommended model

1. **Thrust(rpm, V)**: `ṁ(n) = 0.23·n/154000`, `F_s(n) = η_inst·100·(n/154000)^3.12`, `Vj = F_s/ṁ`. Net thrust is `F = ṁ·(1 + V²/193000)·(√(Vj² + k(n)·V²) − V)`, with `k(n) = 1 + 2·(n − n_idle)/(n_max − n_idle)`: 1 is the cold-duct limit at idle, 3 the hot core at max (k ≈ T_t8/T0·NPR^−0.25). This reproduces the cycle table at full power: 90.0 N at 70 m/s. At idle it gives ≈0.4 N at 70 m/s (110k rpm: 28.1 N). η_inst = 0.92.
2. **Throttle**: `n_cmd = n_idle + (n_max − n_idle)·s^(1/c)`, c = 3.0 (factory). Keep c as data so 1.0 (rpm-linear) can be tested.
3. **Spool** (state n): `dn/dt = clamp((n_cmd − n)/τ, −r_dn·n, +r_up·n)`, with τ = 0.4 s (DGLR small-signal), r_up = 0.4 s⁻¹ and r_dn = 0.6 s⁻¹ (estimate). Simulated: idle → 95 % thrust 3.6 s after the command, 5 → 95 % 2.6 s, 15 → 87 N 1.7 s, max → idle 95 → 5 % 1.4 s. The rate ∝ n gives the measured convex spool-up. Optionally a separate r_up above 70k rpm (FullThrResponse).
4. **Fuel cut / flameout**: fuel flow 0, `dn/dt = −n²/(n_max·0.4 s)`, then a slow coast. No relight.
5. **Gyroscopic**: `H = J·ω` along the engine axis, J = 3.5e-5 kg·m², with a sign parameter (direction unknown).

## What this does not prove

- No P100 thrust is measured at intermediate rpm: the 3.12 law rests on two catalog points plus other JetCat engines.
- No JetCat or P100 data exists for thrust vs airspeed. The lapse is a cycle model with fixed EGT and corrected flow, and the idle-in-flight sign is unresolved.
- Spool constants are calibrated to mixed evidence: identified models, test traces with unknown command ramps, small-signal frequency data, PRO-series specs and scaling. No P100 rpm-vs-time trace for a single idle → max step at a known ECU response setting was found.
- Where the ECU's "Fast/Normal" default sits is ambiguous (the manual contradicts itself).
- Rotor inertia, wheel diameters and rotation direction are not published. H may be off by 2×.
- Installed loss is an estimate. Hot day and altitude are not covered: at fixed rpm thrust scales roughly as δ·θ^−1.56 (derived from corrected parameters, not checked).

## Sources

- JetCat, catalog 2017 (Lieferprogramm): https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf
- JetCat, RX turbines manual (DE): https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf
- JetCat, RX/RXi manual (DE, March 2015): https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_RXi_120218.pdf
- JetCat, P100 RX dimension drawing: https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX%20Size.PDF
- JetCat, P250-PRO-S basic technical information V1-2: https://www.jetcat.de/jetcat/anleitungen/JetCat-P250-PRO-Basic-Technical-Information-V1-2.pdf
- JetCat, P1000-PRO basic technical information 2023 (5 s / 5 s, other engine): https://www.jetcat.de/jetcat/anleitungen/P1000-BasicTechn-Information-2023-01-02.pdf
- L'Erario et al., "Modeling, Identification and Control of Model Jet Engines for Jet Powered Robotics", IEEE RA-L 2020 (P100-RX, P220-RXi): https://arxiv.org/pdf/1909.13296
- Momin et al., "Nonlinear Model Identification and Observer Design for Thrust Estimation of Small-scale Turbojet Engines", 2022 (P160, P220): https://arxiv.org/pdf/2205.08330
- Many et al., "System Identification of a Turbojet Engine Using Multi-Sine Inputs in Ground Testing", DLRK 2021 (P100-RX): https://www.dglr.de/publikationen/2022/550281.pdf
- Wright et al., "Small jet engine reservoir computing digital twin", 2023 (P100-RX bench data): https://arxiv.org/pdf/2312.09978
- NASA Glenn, thrust equation: https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/
- GTBA, KJ66 design data: https://www.gtba.co.uk/engine_designs/kj66.htm
- Wikipedia, Jet fuel: https://en.wikipedia.org/wiki/Jet_fuel
- ExxonMobil, Mobil Jet Oil II: https://www.exxonmobil.com/en/aviation/products-and-services/Products/mobil-jet-oil-ii
