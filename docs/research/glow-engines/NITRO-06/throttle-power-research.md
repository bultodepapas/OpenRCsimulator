# Part-throttle power, idle and cruise: external evidence for RC aircraft

2026-10-19 · research note for the part-throttle climb investigation (NITRO-06 / D6e-R3), written by a delegated literature search and kept as dated evidence. Nothing under `app/` was changed or read for tuning. Downloaded files and hashes: [sources.md](sources.md) (local copies under ignored `references/rc-throttle-power/`). Scripts used for the derived numbers are in the session scratchpad and are reproduced as formulas below.

Evidence labels used throughout:

- **M** measured (instrumented test by the named source)
- **MF** manufacturer data or manual
- **D** derived here from cited data (arithmetic shown; not evidence on its own)
- **A** anecdotal (forum, magazine review, pilot practice)

## Key numbers at a glance

| Quantity | Value | Label | Source |
| --- | --- | --- | --- |
| Fixed-prop rpm at ½ throttle, gasoline 100 cc, butterfly carb | 96 % of WOT rpm, 88–89 % power | D from M | Moulton 2007 [S1] |
| Fixed-prop rpm at ¼ throttle, same engine | 79–83 % rpm, 49–57 % power, ≈62–69 % static thrust | D from M | [S1] |
| Power at ¼ throttle vs WOT at the same rpm (5,500–8,500 rpm) | 62–66 % | M | [S1] Table 4.1 |
| O.S. 46 FX glow, barrel half open vs WOT | peak power 174–215 W vs 269–314 W; operating band ~0.75× rpm | M (read from figure) | Menon 2010 [S2] Fig. 7-11 |
| Same, projected onto a WOT-matched prop | ½ barrel → 78–84 % rpm, 47–59 % power | D from M | [S2] |
| O.S. FX 10 cc + 12×6, full throttle | static 10,791 rpm, 41.6 N; 30 m/s: 11,000 rpm, 16.5 N, 0.617 N·m, 710 W, 1.76 L/h | M | Glassock 2012 [S3] |
| O.S. 61FX static thrust, other props | APC 12.5×6 4.21 kgf (41.3 N), 13×6 4.46 kgf, 13×4 6.23 kgf; 12×6 ≈5.0–5.2 kgf | M (low quality) | [S4], [S5] |
| Glow ground idle | 2,500 rpm run-in, 3,000 rpm new; O.S. 61FX practical floor 2,000 rpm | A / MF | [S6], [S7] |
| 12×6 load at 2,800 rpm static | 16 W, 0.056 N·m, 2.3 N thrust | D | UIUC APC Sport 11×6 data [S8] |
| In-flight idle rpm, 12×6, 15–25 m/s glide | ≈4,000–6,200 rpm (1.4–2.2× ground idle); thrust +0.7 to −1.4 N | D | [S8] + idle model |
| Windmill thresholds, APC Sport 11×6 | CT = 0 at J ≈ 0.75–0.77; CP = 0 at J ≈ 0.85–0.86 | M (+ short extrapolation) | [S8] |
| Elevator change idle→full power at matched speed, Ultra Stick 120 (electric) | 0.1–0.4°, within noise (few seconds per bin) | D from M | UMN Baldr flights 12/13/17 [S9] |
| Level-flight stick, Ultra Stick 25e "Thor" (electric) | median 0.78–0.83 at 15–17 m/s | D from M | UMN Thor flights 34/44/46 [S10] |
| Level-flight stick, Ultra Stick 120 "Baldr" (electric) | 0.55–0.65 at 20–23 m/s; report trim 23 m/s at 65 % | D from M / M | [S9], [S11] |
| Turbine stick law, JetCat RX ECU | default curve 3.0: thrust ∝ stick; 1.0: rpm ∝ stick | MF | JetCat RX manual 2011 p. 49 [S12] |
| JetCat P100-RX | idle 44,000 rpm / 2 N, max 154,000 rpm / 100 N; 80 / 390 ml/min | MF | JetCat catalog 2017 [S13] |

## 1. Throttle position versus rpm and power

### Measured data

**Moulton 2007, 3W-100i B2 (100 cc two-stroke gasoline, Walbro-type butterfly carb, hobby servo on the throttle)** [S1]. Dynamometer, 19 runs averaged, Table 4.1 (PDF p. 50). Power in hp:

| rpm | WOT | ¾ | ½ | ¼ |
| ---: | ---: | ---: | ---: | ---: |
| 2,500 | – | – | – | 1.75 |
| 3,500 | – | – | 3.47 | 2.81 |
| 4,500 | – | 4.92 | 4.88 | 3.36 |
| 5,500 | 5.99 | 6.16 | 5.95 | 3.88 |
| 6,500 | 7.70 | 7.54 | 7.37 | 5.08 |
| 7,500 | 8.94 | 8.75 | 8.07 | 5.53 |
| 8,500 | 9.32 | 9.11 | 8.36 | 5.85 |

- At fixed rpm (5,500–8,500), ¾ throttle gives 98–103 % of WOT power, ½ gives 90–99 %, ¼ gives 62–66 %. Almost all control authority lies below ½.
- Torque at ¼ throttle is nearly flat: 4.13 lb·ft at 3,500 rpm, 3.54 at 8,500 (−14 % over 2.4× rpm). Power at ¼ therefore **rises** 2.1× with rpm. This is not the "torque ∝ 1/rpm" choked limit; at ¼ the butterfly still passes most of the flow.
- Moulton's own explanation (p. 43): closing the throttle restricts air but not fuel, so part throttle runs rich; below 4,000 rpm "the throttle becomes less effective because the flow rate and pumping losses are lower". That is the behaviour of a throttle orifice in series with the engine: the restriction matters more at high flow.
- **D, fixed prop.** Taking a prop that absorbs WOT power at 8,500 rpm (P ∝ n³) and intersecting with each throttle curve: ¾ → 99 % rpm / 97 % power; ½ → 96 % / 89 %; ¼ → 83 % / 57 % (static thrust ∝ n² ≈ 69 %). With the prop matched at 7,500 rpm: ½ → 96 % / 88 %, ¼ → 79 % / 49 % (thrust ≈ 62 %).
- Caveat: "¼ throttle" is the dyno's throttle setting (servo travel), not a measured plate angle or area; butterfly, not barrel.

**Menon 2010, O.S. 46 FX glow engine (7.5 cc, rotary barrel carb), engine–generator tests** [S2], Fig. 7-11 (PDF p. 373), read from the figure (±0.01 N·m, ±100 rpm). Throttle "half open" vs "fully open", rich and lean needle settings (Table 7-3):

| Condition | Torque at the slow end | Torque at the fast end | Power range |
| --- | --- | --- | --- |
| Half open, rich | 0.32 N·m at 5,250 rpm | 0.24 N·m at 6,050 rpm | 174 → 154 W |
| Half open, lean | 0.34 N·m at 6,050 rpm | 0.25 N·m at 7,000 rpm | 215 → 182 W |
| WOT, rich | 0.36 N·m at 7,200 rpm | 0.26 N·m at 8,300 rpm | 269 → 226 W |
| WOT, lean | 0.375 N·m at 8,000 rpm | 0.27 N·m at 9,400 rpm | 314 → 264 W |

- Half-open barrel shifts the operating band to about 0.75× the rpm and 0.55–0.70× the power of WOT.
- All four sets fall on torque ∝ n^−1.9…−2.2 (power ∝ ~1/n). Because WOT shows the same slope, this is the falling side of the torque curve under a resistive load, not proof of throttle choking.
- **D, fixed prop.** Extrapolating the half-open curves (power law fitted to the end points) onto a prop that absorbs WOT-lean power at 8,800–9,400 rpm: half open → **78–84 % rpm, 47–59 % power, ≈61–70 % static thrust**. The extrapolation runs ≤ 900 rpm past the measured half-lean points.

**Glassock 2012, O.S. "FX series 10 cc" glow two-stroke (the 61FX is the only 10 cc FX) with 12×6** [S3]. Full-throttle operating points only (Tables 8-1, 8-5, 8-7):

| Condition | rpm | Thrust | Torque / power | Fuel |
| --- | ---: | ---: | --- | --- |
| Static, engine only | 10,791 | 41.6 N | – | – |
| 30 m/s, engine only | 11,000 | 16.5 N | 0.617 N·m / 710 W | 1.76 L/h (29.3 ml/min) |

The text says the torque-curve points "corresponded to increments of throttle opening", but throttle values are not published. Caveat: hybrid rig with a geared electric motor attached (extra friction); tunnel 30 m/s.

**Turbine (for comparison)** [S12], [S13]. The JetCat RX ECU parameter "ThrStickCurve": factory 3.0 makes thrust proportional to stick; 1.0 makes rpm proportional to stick (manual dated August 2011, p. 49). P100-RX catalog points give thrust ∝ rpm^2.9–3.1 between idle and maximum (D: ln(2/100)/ln(44/154) = 3.1; 2.9 with the 2011 manual's 40,000 rpm idle).

### Anecdotal practice (A)

- RC forums (FlyingGiants and RCU, via search excerpts; threads not readable, HTTP 403): a gasoline engine makes about 85 % of its rpm at half-open carb, with the last 10–15 % in the upper half; glow is said to be closer to 1:1. Pilots offset the servo arm 10–15° at mid stick, use expo, or give the top half more servo travel, because with a linear linkage the response "will be more sensitive on the bottom than on the top" [S14].
- Nitro helicopter setup advice: match the barrel so that 50 % on the curve gives 50 % barrel opening; start linear (0-25-50-75-100) [S15]. This assumes the barrel, not rpm, is the controlled quantity.
- No source gave a measured rpm(stick) curve for a glow barrel carb with a linear servo linkage on a fixed prop. The Dias et al. 2011 MAX-61FX paper and Kamal et al. 2013 (ASAT-15) could contain one; both were unreachable.

### Throttle-flow physics

- An orifice chokes when downstream/upstream pressure ≤ 0.528 (air, isentropic). Choked mass flow depends only on effective area and upstream stagnation state, not on downstream pressure (Heywood 1988, *Internal Combustion Engine Fundamentals*, Appendix C, flow through a restriction; [S16] lab handout gives the same 0.528 result). Real throttles choke at lower ratios, 0.4 or below (search excerpt, [S16]).
- Mean-value engine models (Hendricks & Sorenson 1990, SAE 900616 [S17]; Guzzella & Onder, *Introduction to Modeling and Control of IC Engine Systems*, ch. 2) write throttle flow as `ṁ = Cd·A(α)·p0/√(R·T0)·Ψ(pm/p0)` and engine flow as `ṁ = λ(n,pm)·V_d·n·pm/(k·R·Tm)`. In steady state the two are equal. If the throttle is choked, ṁ is fixed by A(α); mass per cycle ∝ ṁ/n, so indicated torque ∝ 1/n and indicated power ≈ constant at that opening. Brake power then falls with rpm by friction.
- What the measurements add: the choked, constant-power regime applies only at small openings (idle and just above). At ¼ butterfly (Moulton) torque is almost flat with rpm, so the constant-power law is wrong there. Between these limits a two-orifice model (throttle area in series with the engine's own flow capacity) reproduces both ends. Section numbers in Heywood and Guzzella & Onder were not re-checked in this pass.
- Two-stroke specifics: Blair (*Design and Simulation of Two-Stroke Engines*, SAE 1996) treats part throttle as reduced delivery ratio with higher trapping efficiency. Not re-read here; no number is taken from it.
- **Barrel geometry (D, illustration only).** For a round barrel bore moving across a round port, open area is roughly the overlap of two equal circles with centre offset `c = d·(1−u)`, u = fraction of opening rotation. Normalized area `f(u) = (2/π)[acos(1−u) − (1−u)·√(1−(1−u)²)]` gives 14 %, 39 %, 68 % at u = 0.25, 0.5, 0.75. Put in series with an engine whose own effective area is 0.5–1.0× the full carb area, the mass flow at fixed rpm becomes 20–31 %, 52–69 %, 80–90 % of WOT. Real barrels have shaped idle cut-outs; this only shows why the curve is top-heavy.

### What this implies for a simulator throttle law

Both measured carburetted engines put most of the power change in the lower half of travel. On a WOT-matched fixed prop, half throttle gives about 78–96 % of maximum rpm and 47–89 % of maximum power; quarter throttle still gives about 80 % rpm on the gasoline engine. A law that is linear in power or rpm versus stick is therefore not "realistic" for a linear barrel linkage; it is closer to what pilots achieve with expo or an offset linkage. A defensible engine law is: (a) a WOT torque curve; (b) an air-flow limit from a throttle-area function A(stick) in series with the engine's pumping capacity, so torque ∝ 1/rpm only near idle; (c) the stick→A mapping as an explicit, documented installation choice (linear barrel, offset linkage, or transmitter curve). If the simulated models climb at part stick, first check what shaft power the model delivers at 25–50 % stick against the 49–89 % band above, then check the level-flight power requirement (section 4): a .60 Stik needs only about 13 % of WOT shaft power for level flight at 20 m/s, so any law that is top-heavy will make it climb at mid-stick. Real glow pilots therefore cruise at low stick or use a transmitter curve; only anecdotal evidence exists for where they put it.

## 2. Idle in a glide (glow .60, 12×6)

### Ground idle

| Engine | Idle | Label | Source |
| --- | --- | --- | --- |
| Glow, run-in / new | 2,500 / 3,000 rpm (target 2,500–3,000) | A (tuning guide) | Hynes, RC Aerobase 2015 [S6] |
| O.S. MAX-61FX | practical lower limit 2,000 rpm; no idle rpm published | MF | O.S. manual, as recorded in the repo's NITRO-61FX dossier [S7] |
| O.S. FS-64V (4T) | practical floor 2,400 rpm | MF | [S7] |
| 3W-28i HFE (heavy fuel) | stable idle 1,500 rpm | MF (press release) | search excerpt only |

### Prop load at idle (D from M)

Surrogate: UIUC APC Sport 11×6 (the repo's Stik already uses this file, scaled) [S8]. Static CT 0.092–0.10 and CP 0.050–0.051 at 1,750–3,000 rpm. Scaled to a 12×6 (D = 0.3048 m) at 2,800 rpm: **P = CP·ρ·n³·D⁵ = 16.4 W, Q = 0.056 N·m, T = 2.3 N**. With the repo's estimated 61FX friction (`k·(0.008+2e-6·rpm)`, k = 1.114, an estimate), gross idle output is about 21 W.

### Windmill thresholds

| Prop | CT = 0 | CP = 0 (zero shaft torque) | Label | Source |
| --- | --- | --- | --- | --- |
| APC Sport 11×6, 5,000–6,000 rpm | J ≈ 0.75–0.77 | J ≈ 0.85–0.86 (linear extrapolation from J 0.79) | M | [S8] |
| Mejzlik 26×12 2-blade | J ≈ 0.72 | CP still +0.003 at J 0.93 | MF (simulated) | Mejzlik datasheet [S18] |
| 16×6 (brand not stated) in tunnel | – | zero generator output at 4,500 / 5,350 / 6,000 rpm for 20 / 25 / 30 m/s (J ≈ 0.64–0.74) | M | Glassock Figs 10-12/10-13 [S3] |
| 12×6 in tunnel | – | negative torque (windmilling) at 0 rpm in 30 m/s | M (figure) | Glassock Fig. 7-4 [S3] |

Glassock's 16×6 also gives windmill drag of 8, 10.5 and 13.5 N peak at 20, 25 and 30 m/s while extracting 25–60 W (Fig. 10-14).

### In-flight idle equilibrium (D)

Torque balance `engine net torque = prop torque`, with prop coefficients from [S8], linearly extrapolated past J = 0.79, for three idle-engine assumptions:

| Idle engine model | 15 m/s | 20 m/s | 25 m/s |
| --- | --- | --- | --- |
| Constant gross power 21 W (choked idle) | 3,960 rpm, +0.2 N | 4,860 rpm, −0.55 N | 5,870 rpm, −1.4 N |
| Constant gross torque (unchoked) | 4,290 rpm, +0.7 N | 5,200 rpm, +0.2 N | 6,220 rpm, −0.5 N |
| Dead engine, friction only (no compression loss) | 3,130 rpm, −1.0 N | 4,330 rpm, −1.6 N | 5,510 rpm, −2.3 N |

- In-flight idle rpm is about **1.4–2.2× ground idle**: roughly 4,000 rpm at 15 m/s and 5,000–6,000 rpm at 20–25 m/s.
- Thrust is near zero: at most +0.7 N at 15 m/s, and a drag of 0.5–1.4 N at 20–25 m/s.
- Compare a 3 kg Stik's glide drag at 20 m/s, about W/(L/D) ≈ 30 N / 8 ≈ 3.7 N. Idle prop drag adds 0–40 % (ΔCD ≈ 0.005–0.012 on S = 0.4645 m²). This agrees with the stopped-prop increment Southampton measured (0.01–0.03), already in `docs/research/flight-dynamics/rc-aero-data-sources.md`.
- For a large gasoline prop (26×12, J at zero torque ≈ 1.0), the windmill rpm at 25 m/s is only about 2,300 rpm, close to a gasoline ground idle. The rpm rise is specific to small-diameter, low-pitch glow props.

**Not found.** No measured in-flight idle rpm for a glow or gasoline RC engine (telemetry logs, Eagle Tree, Jeti) was located; the forum hits concern sensor problems. The derived table rests on UIUC coefficients slightly extrapolated, and on an estimated friction law.

### What this implies for a simulator throttle law

At idle in a 15–25 m/s glide, a .60 glow engine on a 12×6 should run at about 4,000–6,000 rpm, not at its 2,500–3,000 rpm ground idle, and the propeller should give roughly zero to −1.5 N, never the static idle thrust (2.3 N). A model that holds idle rpm or uses static idle thrust in flight adds about 2–4 N of spurious thrust, which is 50–100 % of the glide drag and will flatten glides and make part-throttle level flight need less stick. The idle state should come from the same torque balance as any other throttle setting: air-limited engine torque (near-constant power at idle) against the prop's CQ(J), including J > J(CQ=0).

## 3. Power–pitch coupling and trim

### Measured (UMN flight data on disk; analysis D)

**Baldr, Ultra Stick 120, electric (Actro 40-4, APC 18×12), 7.41 kg** [S9], [S11]. Steady wings-level windows (|φ| < 15°, |q| < 0.05 rad/s, |a_z + g| < 1.5 m/s²), mean elevator (L/R average, deg, sign as logged) at matched airspeed:

| Flight, speed band | Idle (stick < 0.2) | Cruise (0.60–0.72) | Full (≥ 0.8) |
| --- | --- | --- | --- |
| 12, 19–22 m/s | −3.70° (3 s), climb −3.2 m/s | −3.34° (8 s), +0.5 m/s | – |
| 12, 22–25 m/s | – | −3.11° (36 s), −0.1 m/s | −3.03° (3 s), +2.4 m/s |
| 17, 16–19 m/s | −4.10° (1 s), −2.8 m/s | −4.33° (13 s), +4.3 m/s | – |
| 17, 19–22 m/s | – | −4.03° (12 s), +3.2 m/s | – |

- The elevator moved by **0.1–0.4°** between idle, cruise and full power at the same speed, with the pilot flying manually; the sample is a few seconds per cell.
- Throttle mainly changed the flight-path angle: in flight 12, stick 0.6–0.7 → level (−0.2 m/s); 0.7–0.8 → +1.8 m/s; 0.8–1.0 → +2.6 m/s; 0.5–0.6 → −1.7 m/s; below 0.5 → −1.9 to −2.3 m/s. Flight 17 (different mass/CG configuration, flaps up) climbed +2.7 m/s at 0.6–0.7 and +4.8 m/s at 0.7–0.8.
- A regression of elevator on stick and 1/V² over level windows gave +2.1, +2.8 and +13° per unit stick for flights 12, 13 and 17 (10–23 s of data each). That is not identifiable; do not use it.

**Thor, Ultra Stick 25e, electric (E-flite Power 25), 1.90 kg** [S10]. Too few steady windows. Elevator input differed by 0.3–0.7° between throttle bands with no consistent sign.

### Build data (MF/A)

| Airframe | Thrust line | Source |
| --- | --- | --- |
| Top Flite Giant P-51D kit | 1.75° down | kit manual (local `references/p51-mustang/manuals/topflite_TOPA0400_giant_p51d_kit_manual.pdf`) |
| GP Extra 300S .60 | 0.5° down, 2° right (plan notes) | repo transcription in `app/data/aircraft/gp_extra_300s_60.json` (EX-01) |
| Balsa USA 1/3 Fokker Dr.1 (giant) | 2° down, 2° right | Model Airplane News, G. Yarrish, 2012/2015 [S19] |
| Seagull Classic Ugly Stick 70 | right thrust built into offset F1; no degrees given | kit manual (local) |
| Jensen Ugly Stik (repo model) | 0°/0° (`estimated`, NITRO-02) | repo data |

A generic "2–3° downthrust on sport/trainer models" was not confirmed by a primary source in this pass; the documented values above span 0.5–2°.

### Pilot practice and engineering defaults (A/MF)

- **Goldsmith Trimming Chart** [S20]: pull to a vertical line; if the model pitches to the canopy, add downthrust. Item 13 adds idle-to-elevator mixing when the model pulls to the canopy on a downline at idle. Item 10 does the same for rudder at low throttle.
- **Balsa Workbench** (undated): a high-wing trainer "pitches upward when the throttle is advanced". Trimming down-elevator to hide it leaves a model whose "nose drops when you cut the throttle" [S21].
- **Cox Engine Forum** (opinion): downthrust "doesn't have to fully remove the tendency for the trainer to climb, it just climbs out more slowly".
- **RCU thread "trim for level flight throttle settings"** (search excerpts, HTTP 403): trim level at about ½ throttle; another pilot trims at about ¾, notes the model "will gently climb" at full throttle and descends below ½ [S22].
- **RCM 1988, Great Planes Big Stik 60** (Super Tigre 60): "the first plane we have ever flown that needed no trim adjustments" [S23].
- **RCM April 2000, GP Extra 300S 60** (J. J. Joseph, O.S. .61FX, 3.52 kg): straight flight and turns "accomplished with minimal settings of the control trims" [S24].
- **ArduPlane** source defaults: `KFF_THR2PTCH`, "pitch up to add in proportion to throttle", range −5…+5°, default 0. `STAB_PITCH_DOWN` adds down pitch below cruise throttle, default and "recommended for most planes" 2° [S25].

### What this implies for a simulator throttle law

For a speed-stable sport model, adding power at a fixed elevator should mostly produce a climb at nearly the trimmed airspeed (Baldr: about +2 to +5 m/s from cruise to full stick at 7.4 kg). The elevator needed to hold speed changes by well under 1° from idle to full power on a Stik-class layout. Large power-induced pitch-up is a defect that kits remove with 0.5–2° downthrust and pilots remove with mixes; it is not a target. When the simulator climbs at part throttle, separate two causes: (1) excess thrust at that stick (section 1 law and section 4 power required), and (2) a power-dependent pitching moment (thrust-line offset, slipstream on the tail, missing downthrust). The flight-log test is a fixed-stick throttle step at trim speed: compare the flight-path change and the elevator needed to hold speed with the Baldr numbers above.

## 4. Cruise operating points and static thrust-to-weight

### Measured cruise (electric Ultra Sticks, UMN)

| Airframe | Level flight | Throttle use | Est. Vs (D) | Cruise / Vs |
| --- | --- | --- | --- | --- |
| Ultra Stick 25e "Thor", 1.90 kg, S 0.32 m² | 15–17 m/s; level-window stick p25/p50/p75 = 0.71/0.78/0.90 (F44), 0.81/0.83/0.86 (F46) | 0.7–0.9 for 54–73 % of airborne time; 0.9–1.0 for 15–16 % | 8.7–9.3 m/s (CLmax 1.1–1.26) | 1.6–2.0 |
| Ultra Stick 120 "Baldr", 7.41 kg, S 0.77 m² | 20–23 m/s; stick p50 0.55–0.65; report trim 23 m/s at 65 % stick, pitch 5° | 0.6–0.7 for 29–47 % of airborne time | 11.1–11.8 m/s | 1.7–2.1 |
| Dorobantu 2013, Table 2.1 | "cruise speed" 17 m/s (25e), 25 m/s (120) | – | – | 1.8–2.3 |

Caveats: electric ESC throttle, not a carburettor. The ESC mapping is unknown (statically, rpm roughly ∝ stick, so power ∝ stick³). The airframes carry instrumentation, and Thor's stick input `dthr_in` is a normalized command. Vs uses the FASER tunnel CL at 15° (0.113 + 0.0762·15 = 1.26) as an upper bound.

### Other classes

| Class | Data found | Label |
| --- | --- | --- |
| (a) .60 Ugly Stik / Ultra Stick glow | No measured cruise throttle. Pilot advice: trim level at ½ (or ¾) throttle [S22]. O.S. manual: 350 cm³ lasts 12–13 min on the 61FX (27–29 ml/min) [S7]. Glassock measured 29.3 ml/min at **full throttle** at 30 m/s [S3], so the manual's flight time does not show part-throttle use. D: level flight at 20 m/s needs ≈ 3.8 N thrust from a 12×6 at ≈ 6,600 rpm, ≈ 130 W shaft, about 13 % of WOT power; Vs ≈ 9.1–9.8 m/s for 3.03 kg, S 0.4645 m². | A / M / D |
| (b) .60 Extra 300 | RCM 2000: GP Extra 300S 60, 3.52 kg RTF, 0.48 m², O.S. .61FX; "at 1/3 throttle, the tail lifted off the ground" in taxi tests [S24]. No cruise number. | A (review) |
| (c) 1/4-scale 120 cc P-51 | No cruise data found. DA-120 manual: butterfly carb; recommended props 28×10 and 29×10 wood, Mejzlik 27×12TH, 28×12, 29×10S, 26×12 three-blade; normal peak 5,700–6,800 rpm after break-in [S26]. | MF |
| (d) 1.5 m Turbo Timber | Flying weight 1.61–1.70 kg; 800 Kv, 11×7.5 three-blade, 50 A ESC; flight time 6–8 min (FliteTest spec, pack unstated) [S27]. Static 44 A / 660 W on 4S with the stock prop (Hobby Squawk); 52 A on a 4S 2200 70C pack (RCGroups, Evolution version) [S28]. D: 6–8 min on 80 % of a 4S 3200 pack ≈ 280–380 W average, about half the static input. | MF / A / D |
| (e) 2 m sport jet, 100 N turbine | JetCat P100-RX: 100 N max, 2 N idle, 80/390 ml/min [S13]; ECU default thrust ∝ stick [S12]. RCU anecdote: a P100-RX in a 24 lb (10.9 kg) F-86 flies "7–8 min easily with ample reserve" on 90 oz (2.66 L), i.e. ≤ ~300 ml/min average, ≈ 70 % of maximum fuel flow (D). No measured cruise throttle. | MF / A / D |

### Static thrust and T/W

| Setup | Static thrust | Label | Mass used | T/W |
| --- | --- | --- | --- | --- |
| O.S. 61FX + 12×6 | 41.6 N at 10,791 rpm (hybrid rig) [S3]; 49–51 N (5.0–5.2 kgf) [S5] | M | Stik 3.03 kg (repo) | 1.40–1.72 |
| O.S. 61FX + APC 12.5×6 / 13×6 | 41.3 N / 43.7 N peak [S4] | M | Extra 3.52 kg (RCM) | 1.20–1.48 (any of the above) |
| Prediction check, APC Sport 11×6 coefficients scaled to 12×6, CT0 0.113 | 43.9 N at 11,500 rpm | D | – | – |
| DA-120 + Mejzlik 26×12 2-blade (simulated CT0 0.0889, CP0 0.0316) | 168 N at 5,400 rpm (3.5 kW); 207 N at 6,000 rpm (4.9 kW) | MF (simulated) | P-51 21.5 kg (repo) | 0.80–0.98 |
| DA-120 + Mejzlik 26×12 3-blade (CT0 0.116, CP0 0.0442) | 219 N at 5,400 rpm (5.0 kW) | MF (simulated) | 21.5 kg | 1.04 |
| JetCat P100-RX | 100 N | MF | Avanti 11.44 kg (repo) / 11.7 kg | 0.89 / 0.87 |
| Turbo Timber, 4S, 660 W input | ≈ 22–26 N (motor+ESC η 0.8, figure of merit 0.5–0.65) | D | 1.61–1.70 kg | 1.35–1.6 |
| UIUC Aero Testbed (Extra 260 35 %, electric, 17 kg) | 76 lb (338 N) at 6,936 rpm | M (published spec) | 17 kg | 2.05 |

### What this implies for a simulator throttle law

Real sport models carry a large power surplus: a .60 Stik has static T/W of about 1.4–1.7 and needs only about 13 % of WOT shaft power to fly level at 20 m/s (2.1 × Vs). Climbing at part throttle is therefore physically expected unless the part-throttle law delivers little power at that stick, and the measured carburettor data say it delivers a lot (section 1). The only measured stick-at-cruise data are electric: 0.55–0.65 stick (Ultra Stick 120, 20–23 m/s) and about 0.8 stick (Ultra Stick 25e, 15–17 m/s), with an ESC whose power grows roughly as stick³. They should not be used as the glow target. For glow, the evidence supports a target of "level at a cruise speed of 1.8–2.5 × Vs with the stick somewhere in the lower half, climb of a few m/s at full stick for heavy models and near-vertical for the Stik". The exact cruise stick remains unmeasured; any number the simulator needs must be labelled `estimated`. Turbine models follow a different law: with the JetCat default, thrust is linear in stick, so a P100 jet at T/W ≈ 0.9 should need well under half stick for level cruise if its drag is plausible.

## Side finding for the fuel/engine owners

Glassock measured 1.76 L/h (29.3 ml/min, 10 % nitro, 20 % castor) at full throttle, 11,000 rpm and 710 W at 30 m/s. The repo's NITRO-61FX candidate reports 38.8 ml/min at its 10,976 rpm static root and 46.0 ml/min at 12,550 rpm. The conditions differ (static vs 30 m/s, hybrid rig, fuel blend), but the gap is about 25–35 %. The O.S. statement of 12–13 min per 350 cm³ (27–29 ml/min) agrees with Glassock, not with the model. Worth a check by the FUEL/NITRO owners; not part of this question.

## Sources

| # | Source | URL / local file | Quality caveat |
| --- | --- | --- | --- |
| S1 | N. L. Moulton, *Performance Measurement and Simulation of a Small Internal Combustion Engine*, MS thesis, Univ. Maryland, 2007 (3W-100i B2), Table 4.1 | https://drum.lib.umd.edu/handle/1903/6905; `references/rc-fuel-systems/moulton-2007-umd-ms-3w100i-performance.pdf` (sha256 89fd0df3…) | Good dyno with uncertainties; gasoline butterfly; throttle "¼" etc. = servo setting, not area. |
| S2 | S. Menon, *The Scaling of Performance and Losses in Miniature IC Engines*, PhD thesis, Univ. Maryland, 2010, ch. 7, Fig. 7-11 (O.S. 46 FX) | http://hdl.handle.net/1903/11180; `references/rc-fuel-systems/menon-2010-umd-phd-scaling-miniature-ic-engines.pdf` (sha256 8e50a2d0…) | Measured; values read from a figure; generator load, only "half open" vs WOT. |
| S3 | R. R. Glassock, *Design, Modelling and Measurement of Hybrid Powerplant for UAVs*, MEng thesis, QUT, 2012 | https://eprints.qut.edu.au/61052/1/Richard_Glassock_Thesis.pdf; `references/rc-throttle-power/` | Measured in a tunnel with a hybrid rig (extra friction); few points per curve; some 30 m/s torque points conflict with UIUC coefficients. |
| S4 | Ribeiro, Sobreira, Cimini Jr., Barros, *Análise estática de hélices comerciais para motor OS.61 FX…*, CREEM 2002 | https://abcm.org.br/app/webroot/anais/creem/2002/AR/AR004.pdf; local | Short student abstract; 3 runs per prop; curve fits only. |
| S5 | J. E. de Matos Júnior, UFG TCC, 2019 (O.S. 61FX test stand) | https://repositorio.bc.ufg.br/items/d9331f23-e711-486a-b95f-30f064779eea; local | Undergraduate thesis; noisy Arduino load cell; prop brand not stated. |
| S6 | B. Hynes, "IC Glow Engine off tune (Tuning Protocol)", RC Aerobase, 2015 (updated 2016) | https://rcaerobase.ipjdev.co.uk/index.php/power/power-piston/38-ic-engine-running-badly | Experienced-hobbyist guide, not a measurement. |
| S7 | O.S. MAX-50SX/40–91FX manual and catalog 17750, as recorded in the repo dossier | `docs/research/glow-engines/NITRO-61FX/README.md`; https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf | Manufacturer; no idle rpm published. |
| S8 | UIUC Propeller Database vol. 1, APC Sport 11×6 (`apcsp_11x6_*`), Brandt & Selig | `references/rc-validation-library-2026-10-18/propulsion/UIUC-propDB.zip` | Measured, low Re; 11×6 is a surrogate for 12×6; data end at J 0.79, CP=0 point extrapolated. |
| S9 | UMN UAV Lab, Baldr (Ultra Stick 120) flights 12, 13 (2016-11-02) and 17 (2017-10-05), MATLAB logs | `references/rc-validation-library-2026-10-18/ugly-stik/university-flight-data/` (sha256 98fea7a4…, 3762f057…, f9bdc1b6…); UMN Conservancy | Measured, manual flight; few steady seconds per bin; electric; elevator is actuator command in deg. |
| S10 | UMN UAV Lab, Thor (Ultra Stick 25e) flights 34 (2012-03-30), 44 and 46 (2012-05-21) | `references/rc-validation-library-2026-10-18/stik-analogues/logs/` (sha256 645533a8…, 353a9504…, 7ca6bf0d…) | Measured; `dthr_in` normalized, ESC mapping unknown; flights are test sorties, not cruise. |
| S11 | UMN Baldr flight report 2015-03-11; Dorobantu PhD 2013, Table 2.1 | `references/rc-aero-data/baldr-2015-03-11-flight-report-us120.pdf`; `references/rc-aero-data/dorobantu-2013-umn-phd-test-platforms.pdf` | Test-card values, not measured statistics. |
| S12 | JetCat, *Bedienungsanleitung Strahlturbinen, JetCat RX Turbinen*, Stand August 2011, p. 49 | `references/avanti-s/turbine/jetcat-rx-manual-de.pdf` (sha256 abbe031b…) | Manufacturer; later PRO ECUs reportedly use 2.0 for linear thrust (manualslib, not read). |
| S13 | JetCat catalog 2017, P100-RX table | `references/avanti-s/turbine/jetcat-catalog-2017.pdf`; values as recorded in `docs/research/avanti-s-turbine-research.md` | Manufacturer, STP ±3 %. |
| S14 | FlyingGiants "Throttle servo set up", "More Throttle"; RCU "throttle curve or servo limits" | https://www.flyinggiants.com/forums/showthread.php?t=262451, https://www.flyinggiants.com/forums/showthread.php?t=230691, https://www.rcuniverse.com/forum/beginners-85/11442977-throttle-curve-servo-limits-engine-idle.html | Anecdotal; read through search excerpts only. |
| S15 | Model Airplane News, "Throttle setup tips" / nitro helicopter barrel matching | https://www.modelairplanenews.com/throttle-setup-tips/ | Setup advice; search excerpt. |
| S16 | Choked flow (0.528): UT Austin ChE 253M handout; Wikipedia "Choked flow"; Heywood 1988 App. C | http://willson.cm.utexas.edu/Teaching/Che253M/Files/EXP%202%20Compressible%20Gas%20Flow%2008-15.pdf; https://en.wikipedia.org/wiki/Choked_flow | Textbook physics; Heywood section not re-read. |
| S17 | Hendricks & Sorenson, "Mean Value Modelling of Spark Ignition Engines", SAE 900616, 1990; Guzzella & Onder 2010, ch. 2 | https://saemobilus.sae.org/content/900616 | Abstract only read; model form from general knowledge, equation numbers not verified. |
| S18 | Mejzlik 26×12 2B GAS (PN 226120) and 26×12 3B GAS-N datasheets, rev. 3.0, 2025-12-18 | `references/p51-mustang/propellers/` (sha256 cd1ab931…, ce084e9e…) | Manufacturer **simulated** coefficients at 5,400 rpm. |
| S19 | G. Yarrish, "Engine and firewall setups: tips for down and side thrust", Model Airplane News, 2012/2015 | https://www.modelairplanenews.com/engine-and-firewall-setups-tips-for-down-and-side-thrust/ | Single kit example. |
| S20 | Goldsmith Trimming Chart (Clovis RC handout) | https://clovisrc.com/wp-content/uploads/Goldsmith-Trimming-Chart.pdf; local | Pilot practice. |
| S21 | "Why RC planes have down and right engine thrust", Balsa Workbench (undated) | https://www.balsaworkbench.com/?p=2714 | Opinion; no numbers. |
| S22 | RCU "Trim for level flight throttle settings" | https://www.rcuniverse.com/forum/beginners-85/1802191-trim-level-flight-throttle-settings.html | Anecdotal; search excerpt (HTTP 403). |
| S23 | RCM product review, Great Planes Big Stik 60, 1988 | `references/rc-validation-library-2026-10-18/ugly-stik/field-reports/rcm-1988-great-planes-big-stik-60-review.pdf` (sha256 e22790a4…) | Magazine review. |
| S24 | J. J. Joseph, RCM product review "Extra 300S 60", RCM April 2000 | `references/extra-300/gp-extra-300s-60/Extra_300S_60_oz10977_review_RCM.pdf` (sha256 46d255f4…) | Magazine review. |
| S25 | ArduPilot `ArduPlane/Parameters.cpp` (master, read 2026-10-19) | https://raw.githubusercontent.com/ArduPilot/ardupilot/master/ArduPlane/Parameters.cpp | Autopilot defaults, not aircraft data. |
| S26 | Desert Aircraft DA-120 owner's manual, 2018-01-08 | `references/p51-mustang/engines/da120_owners_manual_2018-01-08_desertaircraft_au.pdf` (sha256 d5f0d666…) | Manufacturer; no power curve, no idle rpm. |
| S27 | FliteTest, "New E-Flite Turbo Timber 1.5m" (spec listing) | https://www.flitetest.com/articles/new-e-flite-turbo-timber-1-5m | Retail spec; pack for flight time unstated. |
| S28 | Hobby Squawk Turbo Timber review; RCGroups Turbo Timber Evolution thread p. 97 | https://www.hobbysquawk.com/forum/rc-airplanes/rc-propeller-airplanes/183838-new-e-flight-turbo-timber-review; https://www.rcgroups.com/forums/showthread.php?3904021-NEW-E-flite-Turbo-Timber-Evolution-1-5m/page97 | Anecdotal wattmeter readings via search excerpts. |
| S29 | UIUC Aero Testbed spec (Dantsker et al., AIAA 2013-2807) | `references/rc-aero-data/dantsker-2013-aiaa-2013-2807-aero-testbed.pdf` | Published spec table. |

## Not found or not reachable

- A measured rpm(stick) or power(stick) curve for a glow **barrel** carburettor with a linear servo linkage on a fixed propeller. Leads: Dias, Violato & Martins 2011 (MAX-61FX, publisher 403) and Kamal et al. 2013 ASAT-15 (host unreachable).
- Any measured in-flight idle rpm (glow or gasoline) during a glide or dive.
- Measured cruise throttle for a glow .60 Stik or Extra, a 120 cc P-51, a Turbo Timber or a P100 sport jet. Only electric UMN logs and anecdotes exist.
- A primary source for a generic "2–3° downthrust" on sport/trainer models. Documented values found: 0.5–2°.
- Four-stroke part-throttle data (FS-64V, Saito). None found.
