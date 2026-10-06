# 02 — Aerodynamics at RC scale: coefficients, stall, post-stall, unsteady effects and ground effect

**Status:** research knowledge base, 2026-10-06. **Serves:** Gate 2-R and the D8b/D10 follow-ups (roll and pitch faster than the UMN Ultra Stick 120), E0a (tail downwash and its lag), M5 (stall hysteresis, post-stall extension, ground effect), every new aircraft's `derive_physics.py` (EX-05, P51-05, AV). **Read with:** [aero.gd](../../../app/physics/aero.gd), [flight repair report](../flight-repair-implementation.md), [robustness audit](../flight-model-robustness-audit.md), [FLIGHT-MODEL-ROBUSTNESS-PLAN](../../FLIGHT-MODEL-ROBUSTNESS-PLAN.md), [sensitivity results](../../../research/sensitivity/results.md), [EX-05 derivation](../../../research/extra-300/ex05/derivation.md), [P51-05 derivation](../../../research/p51/p51-05/derivation.md), RESEARCH.md sections [Flight physics](../../../RESEARCH.md#flight-physics-several-useful-levels-of-approximation), [RC-scale aerodynamics](../../../RESEARCH.md#rc-scale-aerodynamics-and-model-authoring) and [Full-envelope flight models](../../../RESEARCH.md#full-envelope-flight-models-in-rc-simulators). Propeller and propwash: doc 03 of this folder (not repeated here).

Numbers marked **measured** were measured on our simulator for this report (working tree of 2026-10-06, which contains another track's uncommitted E0b/P51-12 slipstream work; the Ugly Stik data does not use it). **Derived** numbers come from the scratch calculations described next to them. Kinds follow the data convention (measured / manual / borrowed / estimated / derived).

## Summary

1. **The roll gap is real and is mostly inertia.** At the same CL and Froude-scaled, the sim's roll time constant is **2.13× shorter than the flight-identified Ultra Stick 25e and 2.16× shorter than the US120** (derived). Roll subsidence is `L_p = ρ V S b² Clp / (4 Ixx)`. Decomposition: roll radius of gyration² **1.62–1.64×**, Clp **1.13–1.18×**, wing loading lighter than Froude-scaled **1.10–1.18×** (a real property of the Ugly, not an error). Ugly `Ixx/(m b²)` = 0.0172; both UMN Sticks (bifilar swing tests) = **0.028**.
2. **Steady roll rate already matches.** The sim's `pb/2V` per radian of aileron (Clδa/Clp = 0.366) is within 2 % of the 25e identification (0.373, derived; aileron-sign convention assumed equal). Only the response time is off: τ 0.041 s vs 0.088 s, both shorter than the 0.14 s servo slew. Flight data identifies `L_p` (Clp/Ixx), never Clp and Ixx separately.
3. **The 1.45× pitch gap is obsolete.** It predates D1-R1, which raised Iyy from 0.218 to 0.387 kg·m². The production Jacobian now gives a short period of **1.45 Hz at 14.5 m/s vs 1.31 Hz for the US120 (1.11×)** and **1.85 Hz at 18.8 m/s vs 2.43 Hz for the 25e (0.76×)**, both measured and Froude-scaled. The two Sticks bracket the sim, and they differ from each other by 1.9×.
4. **Dorobantu et al. 2013 is freely available.** The 25e identification that ROADMAP lists as "paywalled, library" is online as a preprint on a UMN course server, with swing-test inertias and identified A/B matrices [S1]. Our borrowed UltraStick25e Clp (−0.4496) is **18 % larger** than the value implied by its identified L_p and measured Ixx (−0.381).
5. **New defect: damping changes by regime.** Measured at 15 m/s: effective **Clp goes from −0.45 to −0.78 (1.73×)** and **Cmq from −13.6 to −4.4 (0.32×)** as α goes from 4° to 10°, i.e. from the oracle to the local model. A landing approach at 1.3 V_s (α ≈ 7°) sits in this blend. Cause: the strips use the whole-airplane CLα with no induced flow, and the local tail uses a downwash-reduced slope for the pitch-rate term without adding Cmα̇. Fix this before adding any new effect.
6. **Strip count is not the problem; induced coupling is.** Our 100-line vortex lattice gives an AR 5 rectangular wing **Clp −0.40, CLα 3.98/rad**, in line with the identified US120 (−0.398, AR 4.8) and 25e (−0.381, AR 5.2). Three equal strips integrate `y²` to 97 % of the continuum. Per-strip ε(α) tables (Selig style) still give ≈ −0.65, because antisymmetric loading induces more downwash. Use a precomputed n×n induced-flow map.
7. **Selig's FS One model is the L3 reference** [S2, S3]: ~20 strips per wing, 360° tables of Cl/Cd/Cm per strip and per control deflection, nonlinear lifting-line induced-angle tables, flow-shadow maps, fuselage segments, RK4 at 300 Hz. It deliberately omits **dynamic stall** and **downwash lag**. Most of its value is in authored data, not code.
8. **Unsteady effects matter only in snaps.** The flow is quasi-steady while `k = α̇ c/(2V) < 0.05` [S4]. For the Ugly that means α̇ < 179°/s at 9.5 m/s and < 282°/s at 15 m/s: only snaps, blenders and tail-slide entries cross it. A Goman–Khrabrov separation state (one ODE per strip) is cheap and gives stall hysteresis and dynamic overshoot. Its time constants are borrowed, with roughly ±50 % uncertainty.
9. **Tail downwash lag.** The lag is `l_t/V`, 48 ms at 15 m/s. Derived values: CLα̇ ≈ 1.43 and Cmα̇ ≈ −3.4 (the data has CLadot 1.97, unused). Implement it as an explicit downwash state on a tail with its true slope (a_t η ≈ 3.2). The same state then carries ground effect at the tail and the collapse of downwash at stall.
10. **Ground effect is relevant in every flare.** The Ugly's wing stands at h/b ≈ 0.17 on its wheels. The image-method VLM (derived) gives lift **+16 %** at the same α, induced drag **−34 %** at the same CL, and tail downwash **−51 %**. That is ΔCm ≈ −0.06, about **4° more up-elevator** in the flare. Wieselsberger's formula matches the VLM within 1 %. McCormick's `(16h/b)²` form is much weaker (0.88 vs 0.67). The effect is < 3 % above h/b 0.5 (0.76 m).
11. **CLmax 1.1 and CD0 0.0434 are plausible.** The borrowed polar's L/D is not: CL_minD 0.23 with e 0.78 gives an airframe L/D_max of **11.5 at 11.4 m/s** (derived), optimistic for a fixed-gear box fuselage. Check it with a Raymer drag buildup (the EX-05 method). Wing Re: 2.0e5 at stall to 6.6e5 at top speed; tail Re: 1.1–3.7e5.
12. **Cost.** Measured `Aero.loads` per call on the dev VM: oracle path **44 µs**, local **85 µs**, blend **116 µs**. With 4 RK4 stages that is **177–462 µs per tick**, about 10 µs per surface in GDScript. L3 with ≥ 40 strips needs flattened data or a GDExtension.

## Where the code stands

- **[aero.gd](../../../app/physics/aero.gd)**: loads are blended between two models.
  - **Oracle:** the whole-aircraft linear derivatives (UltraStick25e, OpenFlightSim), dimensionalized with `¼ρV·rate·L`, so they stay finite at V → 0.
  - **Local model:** 3 equal-area strips per side ([`station_ys`](../../../app/physics/aircraft_data.gd), taper supported) plus a horizontal and a vertical tail. Flow at each surface is `v + ω×r`; lift is perpendicular to the flow in the surface plane and drag is parallel to it. The moment is exactly `r × F`, which makes each element passive.
  - **Blend:** `local_flow_weight` runs a smoothstep from 8° (`attached_limit`) to the wing stall start (12.13°, solved so that the peak equals CL_max 1.1) or to the tail's 12°. It uses local angles including rates, incidence and controls.
  - **Post-stall:** `CL = ½·CD90·sin2α` (CD90 1.2, Viterna with AR 5) blended over 6°. Tail stall runs from 12° to 24°.
  - **Controls:** an aileron is an angle shift of 0.144 rad per rad on its strip. The elevator uses `control_effectiveness` 1.174 = Cmde/Cma, a calibration that "also represents omitted effects such as downwash" ([report](../flight-repair-implementation.md)).
- **Data ([jensen_ugly_stik_60.json](../../../app/data/aircraft/jensen_ugly_stik_60.json)):**
  - **Borrowed:** CLa 4.58, Clp −0.4496, Cmq −13.57, Cnr −0.1833, CD0 0.0434, k 0.0815 (e 0.78), CL_minD 0.23.
  - **Estimated:** CL_max 1.1 and CL_min −0.8.
  - **Derived from one fin model:** CYdr, Cndr, Cldr and Cnb.
  - **Mass:** inventory Ixx/Iyy/Izz = 0.1154 / 0.3871 / 0.4841 kg·m² at 2.885 kg (derived from the inventory here). That gives roll and pitch radii of gyration Rx 0.262 and Ry 0.535 (fuselage length 1.37 m).
- **Missing:**
  - Downwash: the tail uses an effective slope `a_t η (1 − dε/dα)` and never sees ε. CLadot is in the data and unused.
  - Ground effect, dynamic stall and hysteresis, apparent mass, fuselage segments, tail shielding, Reynolds dependence.
  - Per-deflection polars: controls are linear angle shifts at all α.
  - Propwash and P-factor (doc 03).
  - The working tree has an uncommitted opt-in tail slipstream and per-strip incidence hook from another track (`app/physics/slipstream.gd`, `surfaces.station_incidence`).
- **Generated aircraft (EX-05, P51-05):** Helmbold CLα, elliptic dε/dα ≈ 0.47, η_t 0.9, Oswald e 0.78/0.80, CLmax 1.05/1.15 estimated, strip-theory Clda. Their own notes say "the local wing strips use the whole-airplane CLa, so local lift is ~7–8 % high". Clp (−0.597/−0.599) comes from a strip formula, about 1.4× a VLM value for AR 5.5–5.8 (−0.43 to −0.45, derived).
- **Measured blend inconsistency (this report, `Aero.loads` central differences at 15 m/s, Ugly):**

| α (°) | local weight | Clp | Cmq |
|---:|---:|---:|---:|
| 0 | 0.00 | −0.451 | −13.57 |
| 4 | 0.00 | −0.451 | −13.67 |
| 7.9 | 0.54 | −0.620 | −11.24 |
| 9 | 0.90 | −0.737 | −7.25 |
| 10–12 | 1.00 | −0.774…−0.784 | −4.40…−3.15 |
| 13 / 15 | 1.00 | +0.242 / +1.663 (autorotation, expected) | −2.50 / −1.33 |

## Theory and models

### T1. Low-Reynolds aerodynamics (Re 1e5–6e5)

- **Operating range (derived, ν = 1.46e-5 m²/s).** Ugly wing (c 0.305 m): Re 2.0e5 at stall (9.5 m/s), 3.1e5 at 15 m/s, 6.6e5 at 31.5 m/s. Tail (c ≈ 0.17 m): 1.1–3.7e5. The P-51 1/4 is around 7e5–1e6. Foamies sit below 1e5, where Oswald e collapses (< 0.4 measured for some sUAVs at Re < 6e4 [S17]).
- **Laminar separation bubble (LSB).** Below about 3e5 the laminar boundary layer separates, transitions and reattaches. The bubble raises drag, makes lift nonlinear near α = 0 for thick symmetric sections (a "dead band"), and moves CLmax. Thick sections (≥ 12 %) are the most Re-sensitive. Anyoji et al. found little lift response to 0–3° of flap below α 5° for NACA 0012 at Re 2e4 ([RESEARCH.md](../../../RESEARCH.md#low-speed-stall-control-and-propwash-evidence-for-the-first-60-stick)). Our tails are at 1.1e5 when slow.
- **Hysteresis.** Stall and reattachment angles differ at low Re: about 12° vs 11.3° on an AR 2.5 NACA 0018 wing at Re 8–10e4 (Toppings & Yarusevych, in RESEARCH.md). A single α threshold makes stall artificially reversible.
- **Section CLmax vs Re** (XFOIL, Ncrit 9, airfoiltools.com polars fetched [S18]; computed, not measured; XFOIL tends to over-predict Clmax near stall [S19]):

| Section (typical use) | Re 1e5 | Re 2e5 | Re 5e5 | α_Clmax at 2e5 | Cd_min at 2e5 |
|---|---:|---:|---:|---:|---:|
| Clark Y 11.7 % (trainers, Stik-like flat bottom) | 1.37 | 1.40 | 1.43 | 12.5° | 0.0101 |
| NACA 2415 (semi-symmetric sport) | 1.34 | 1.37 | 1.39 | 17.5° | 0.0108 |
| NACA 0012 (aerobatic, symmetric) | — | 1.11 | 1.24 | 12.3° | 0.0102 |

- **From section to wing.** A finite unswept rectangular wing reaches about 0.9·cl_max (DATCOM rule, as used in EX-05/P51-05). Trimming the tail costs another 2–5 %. So CL_max(airplane) ≈ 1.0 for a symmetric section and ≈ 1.25 for a semi-symmetric one. **Ugly CL_max 1.1 is mid-range (estimated, ±0.15).**
- **Drag.** CD0 0.0434 is in the expected band for a fixed tricycle gear, an exposed glow engine and a slab-sided fuselage: EX-05's Raymer buildup gives 0.031 for a cleaner Extra with wheel pants, and P51-05 gives 0.045 gear-down. **The borrowed polar's L/D_max of 11.5 is the suspect part** (CL_minD 0.23, k 0.0815). Its CL-dependent profile drag at low Re is probably under-represented.
- **Measured 360° data.** Sheldahl & Klimas measured NACA 0009/0012/0012H/0015 through 0–180° at moderate Re and synthesized 1e4–1e7 [S20]. UIUC LSAT volumes 1–5 cover 3e4–5e5 [S21]; the airfoil data are marked "GPL'd Data" (RESEARCH.md), so validate against them and do not bundle them.

### T2. Coefficients from geometry instead of borrowing

**Handbook core** (Etkin/Nelson/Raymer/DATCOM forms; the textbooks were not fetched in this pass; the forms match those coded in EX-05/P51-05):

| Quantity | Formula | Ugly value (derived) |
|---|---|---|
| Wing CLα | Helmbold `2πA/(2+√(A²+4))`, times the section factor | 4.25 (thin); VLM 3.98 |
| Downwash gradient | elliptic `2CLα,w/(πA)`; VLM at the tail point | 0.50; **VLM 0.457** |
| Tail volume | `V_H = S_t l_t/(S c)` | 0.486 |
| Tail Cmq | `−2 a_t η V_H l_t/c` | −7.4 (a_t η 3.22) |
| Downwash-lag CLα̇ | `2 a_t η (S_t/S)(l_t/c) dε/dα` | 1.43 |
| Downwash-lag Cmα̇ | `−CLα̇ · l_t/c` | −3.4 |
| Roll damping, strip theory | `−a/6` for a rectangular wing; 3 strips `−0.162a` | −0.74 at a = 4.58 |
| Roll damping, lifting surface | VLM | **−0.40** |
| Fin Cnβ | `a_v (1+dσ/dβ) η_v S_v l_v/(S b)` | +0.121 (data) |
| Fuselage Cnβ | `−K_N K_Rl (S_side/S)(L/b)` (DATCOM) | omitted by the v1 contract (EX-05 note) |

**Vortex lattice: our known-answer check** (derived; horseshoe VLM, cosine spacing, flat wing, scratch script):

| Wing | CLα (1/rad) | Clp | Identified / reference |
|---|---:|---:|---|
| AR 4.0 rectangular | 3.67 | −0.344 | — |
| AR 4.8 (US120 geometry) | 3.96 | −0.391 | US120 flight: **−0.398** [S6] |
| AR 5.0 (Ugly), 20×1 / 40×4 / 80×6 panels | 4.05 / 4.02 / 3.99 | −0.404 / −0.402 / −0.397 | borrowed −0.4496 |
| AR 5.2 (25e) | ≈4.06 | ≈−0.41 | 25e flight: **−0.381** [S1] |
| AR 5.5, taper 0.5 (Extra-like) | 4.26 | −0.407 | EX-05 strip: −0.597 |
| Coarse coupled 6 / 10 / 16 equal strips, AR 5 | 4.32 / 4.17 / 4.08 | −0.481 / −0.449 / −0.427 | converges to −0.40 |

**Tools.** Licenses verified where marked; see the library table.
- **AVL 3.52** (Drela; GPL; Windows 3.52, Linux/macOS 3.40b) [S7, S8]. Extended VLM plus slender bodies, trim, eigenmodes, stability and control derivatives (`ST` in stability axes, `SB` in body axes), CDCL polars and `CLAF` thickness correction.
  - **Validity:** thin surfaces at small α/β, quasi-steady, and `|pb/2V| < 0.10`, `|qc/2V| < 0.03`, `|rb/2V| < 0.25`. Our full-aileron steady roll is pb/2V = 0.128, outside that range.
  - **Bodies:** "should be done with caution"; the primer suggests omitting the fuselage.
- **flow5/XFLR5:** GPL, XFLR5 closed 2026-06-30 (RESEARCH.md).
- **OpenVSP + VSPAERO:** NOSA 1.3 [S9].
- **AeroSandbox:** MIT [S10]; its VLM, AVL/XFOIL wrappers and NeuralFoil (MIT) make a pure-Python pipeline possible.
- **USAF Digital DATCOM:** a handbook-method code; license and maintenance unverified in this pass.

**Pipeline proposal (repo):**
1. `assets/aircraft/<id>/geometry.json` (measured) goes to `research/aero/avl/make_avl.py`, which writes `<id>.avl` and a `.mass` file built from the inventory boxes.
   - **Surfaces:** wing sections at chord and dihedral breaks; aileron, elevator and rudder as `CONTROL` with hinge x/c from the geometry and `SgnDup −1` for the ailerons.
   - **Bodies:** fuselage omitted, wing bridged through it (primer advice).
   - **Section data:** `CLAF = 1 + 0.77 t/c`, CDCL from XFOIL/NeuralFoil at cruise Re.
2. A pinned `avl` binary (SHA-256 recorded, external tool, never shipped; its numeric output is not GPL-encumbered) is driven by a stdin command file: `LOAD`, `MASS`, `OPER`, `a c <CL>`, `x`, `st <file>`, `sb <file>`, `quit`. Run at 3 CLs.
3. A parser writes `research/aero/avl/<id>-derivatives.json`. Each value is `{value, unit, kind: "derived", source: "AVL 3.52 sb, geometry sha256 …, CL 0.47"}`.
4. A comparison table lists AVL vs in-repo VLM vs borrowed vs flight-identified (25e/US120) for CLα, Cmα, Cmq, Clp, Clr, Cnr, Cnβ, Clβ, Clδa, Cmδe, Cnδr. Write it into the aircraft data only after the regime-consistency fix (step X-aero-5).
5. **Conventions:** AVL's geometry axes are x aft, y right, z up. The derivative names follow standard stability-axis signs. Convert to our FRD body axes and our δ signs ("TE down +" for elevator/aileron, "TE left +" for rudder) in one tested function, with a known-answer test using a symmetric wing at α = 0.

### T3. Why roll is ~2× faster and pitch no longer is

- **Roll subsidence:** `τ = −1/L_p = 4 Ixx /(ρ V S b² |Clp|)`. At matched CL (`V = √(2mg/(ρ S CL))`): `τ = √(m/(ρS)) · √(CL/(2g)) · Rx²/|Clp|`, with `Rx = 2√(Ixx/m)/b`.
- **Froude scaling** (length ratio k): V, t ∝ k^½; m ∝ k³; I ∝ k⁵; Re ∝ k^1.5. It preserves `m/(ρ S b)` (μ_b), Rx and every nondimensional coefficient.

| | Ugly sim | UMN 25e (flight ID, swing test) [S1] | UMN US120 (flight ID) [S6] |
|---|---:|---:|---:|
| m (kg), b (m), S (m²) | 2.885, 1.524, 0.4645 | 1.959, 1.27, 0.31 | 8.338, 1.917, 0.769 |
| Ixx (kg·m²), Ixx/(m b²) | 0.1154, **0.0172** | 0.089, **0.0282** | 0.857, **0.0280** |
| Rx | 0.262 | 0.336 | 0.334 |
| m/S (kg/m²); μ_b | 6.21; 3.33 | 6.32; 4.06 | 10.84; 4.62 |
| Trim V (m/s), CL | — | 19.0, 0.280 | 19.2, 0.471 |
| L_p (1/s) | — | −12.47 | −7.73 |
| Clp implied (`4Ixx L_p/(ρVSb²)`) | −0.4496 (borrowed) | −0.381 | −0.398 |
| Sim at matched CL, V (m/s) | — | 18.84 | 14.53 |
| τ sim / τ ref Froude-scaled (s) | — | 0.041 / 0.088 → **2.13×** | 0.054 / 0.115 → **2.16×** |
| Decomposition (wing loading × Rx² × Clp) | — | 1.105 × 1.635 × 1.179 | 1.178 × 1.623 × 1.129 |
| Short period, sim (production Jacobian, measured) | — | 1.85 Hz, ζ 0.75 | 1.45 Hz, ζ 0.74 |
| Short period, ref Froude-scaled | — | 2.43 Hz, ζ 0.81 → 0.76× | 1.31 Hz, ζ 0.53 → 1.11× |
| Cmα; Cmq+Cmα̇ implied | −0.723; −13.57 | −0.86; −21.1 | −0.52; −4.2 |

**Candidates, quantified (derived):**
1. **Ixx is too low.** The UMN ratio 0.028 would give 0.188 kg·m² (+63 %). The inventory wing is a 0.52 kg uniform box (Ixx_wing ≈ m b²/12 ≈ 0.10 kg·m²). Both UMN airframes imply a wing-equivalent mass of ~34 % of total. That is either heavier wings and tip hardware, or swing-test inflation by entrained air (Wolowicz & Yancey, NASA TR, cited by [S17]; not fetched).
2. **Apparent (added) mass in roll.** A flat-plate strip carries `m' = ρπc²/4`, so `I_add = m' b³/12` = **0.026 kg·m² (23 % of Ixx)** for the Ugly (2-D upper bound; finite-span relief not computed), against 11 % for the 25e and US120. The Ugly's low μ_b (3.3) makes it relatively large. This is physical in flight, so add it explicitly as non-circulatory inertia (`Ixx_eff = Ixx + I_add`, roll axis only; pitch and yaw contributions ≈ 2 %).
3. **Clp borrowed 12–18 % high.** The VLM (−0.40) and both identifications (−0.38/−0.40) agree.
4. **Aileron effectiveness.** It changes p_ss, not τ, and p_ss already matches. Do not touch it to fix τ.
5. **Servo dynamics.** Identified responses include actuators: the 25e has a 50 rad/s, ζ 0.8 actuator and a 50 ms delay [S1]. Our modes are bare-airframe, which is correct for this comparison. The pilot-felt roll-in time is ≈ τ + ½·servo slew: 0.11 s vs 0.16 s (derived).
6. **Ixz coupling** (25e Ixz 0.014) is a ≤ 5 % effect here.

A fix that keeps everything physical: VLM Clp (×0.89) plus explicit apparent roll inertia (+23 %) closes **1.4×** of the 2.1×. The rest needs a measured Ixx (bifilar swing of a built wing and airframe). **Do not tune Clp to close τ.** Pitch is no longer an outlier, so the next sensitivity run must use the post-D1-R1 baseline.

### T4. Stall and post-stall models (static and dynamic)

| Model | Equations | Cost | Notes |
|---|---|---|---|
| **Flat plate** (today) | `CL = ½CD90 sin2α`, `CD = CD0 + CD90 sin²α`; 2-D CD90 ≈ 1.98, AR 5 ≈ 1.2 | trivial | Normal force only. Missing: the CL ≈ CD/tanα check, the moment migration to 0.5c |
| **Viterna–Corrigan** (stall…90°) | `CD = B1 sin²α + B2 cosα`, `CL = A1 sin2α + A2 cos²α/sinα`, B1 = CDmax = 1.11 + 0.018AR, A1 = B1/2, A2 = (CLs − CDmax sinαs cosαs) sinαs/cos²αs, B2 = (CDs − CDmax sin²αs)/cosαs | trivial | Continuous at stall by construction. Wind-turbine origin; reflect for 90–180° (RESEARCH.md, AirfoilPreppy) |
| **Lindenburg / Selig 3-D post-stall** | `CN = CD90 sinα[1/(0.56+0.44 sinα) − 0.41(1−e^(−17/AR))]` for 90°; Selig scales 2-D data by `1 − w(1 − Cd90/2.2)` with a cosine weight over the post-stall range, applied to Cl, Cd and Cm alike, keeping CL/CD ≈ 1/tanα [S2] | offline table | Handles any α; one table per strip and per deflection |
| **Kirchhoff / Helmholtz** (separation point X) | `CL = CLα sinα ((1+√X)/2)²`; static `X0(α)` from inverting the measured CL(α) | trivial | X = 0 still leaves `CLα sinα/4` (≈ 1 at 90°): use it only to ~25–30°, then blend to the flat plate (Khan [S4]) |
| **Goman–Khrabrov** [S11, S12] | `τ1 dX/dt + X = X0(α − τ2 α̇)`, lift through Kirchhoff | 1 state per strip | τ2 is the stall delay, τ1 the relaxation. Khan uses τ_TE,1 = 0.52 c/V and τ_TE,2 = 4.5 c/V (NACA 0015, from GK 1994) [S4]. Ayancik & Mulleners fit τ1 ≈ 4.24 c/U (OA209, Re 9.2e5) [S12] |
| **Beddoes–Leishman** | indicial attached flow, TE-separation lag, LE vortex shedding | 4–8 states, ~12 constants | Rotorcraft; overkill here (Khan rejected it for UAVs [S4]) |
| **Tabulated hysteresis** (JSBSim) | separate up/down stall branches switched by a flag | trivial | Discontinuous switch; GK is smoother |

- **Ugly GK constants (derived):** at 15 m/s τ2 = 0.091 s, so α̇ = 1 rad/s delays stall by 5.2°. τ1 is 0.011–0.086 s depending on the source. A slow-flight stall (α̇ ≈ 0.05–0.2 rad/s at 10 m/s) is delayed by 0.4–1.6°. A snap pull-up overshoots CLmax briefly, which is real dynamic lift.
- **Passivity.** A memory state can return energy within a cycle (stall flutter), so per-state passivity sweeps must exempt it and check cycle-averaged power instead (the robustness plan already says to include memory contributions).

### T5. Unsteady and apparent effects, spin, knife-edge, controls

- **Downwash lag.**
  - **Tail angle:** `α_t = α_body + i_t − ε(t) + q l_t/V + δe τ_e`, with `ε(t) = ε0 + (dε/dCL_w)·CL_w(t − l_t/V)`, expanded in Taylor form to give CLα̇ and Cmα̇.
  - **State:** a first-order lag with `τ = l_t/V` has the same first-order effect as a pure delay. At 240 Hz it is 11.5 ticks at 15 m/s.
  - **Limits:** clamp τ for V → 0 (e.g. V_min 2 m/s) and freeze ε in reverse flow.
  - **Consequence:** `a_t η` returns to ~3.2, the `(1 − dε/dα)` and elevator-effectiveness fudges disappear, and the q-induced tail angle gets the full slope. That restores tail Cmq ≈ −7.4, and with Cmα̇ −3.4 and the wing term, total pitch damping lands near the oracle's −13.6.
  - **Ground effect:** this is also where it scales ε.
  - **Stall:** when CL_w collapses, ε drops, the tail gains α, and the nose pitches down, which is a real stall-recovery cue.
- **Apparent mass.** It is a non-circulatory force `ρπc²/4 · ẇ` per strip [S4, eq. 3.30]. Only the roll-axis inertia part matters here (T3). The heave and pitch parts are < 3 % of mass and inertia for the Ugly (derived).
- **Circulatory lag** (Theodorsen/Jones, 2 states per strip [S4]): skip while k < 0.05.
- **Strip count and tip effects.** The midpoint sum of `y²` with n strips per side equals `1/3 − 1/(12n²)`: 97.2 % at n = 3, 99.0 % at n = 5, 99.8 % at n = 10. Lift distribution and stall progression need the induced map, though. Without it, uniform strips put too much load at the tips, so a rectangular wing stalls everywhere at once instead of root-first.
  - **Ugly:** n = 4–6 per side with a precomputed induced map. 20 per side as in Selig is needed only for flaps, propwash bands and taper.
  - **P-51 / Extra** (taper ~0.5, tip-stall prone): ≥ 5 per side, with a strip edge at each control break.
- **Spin.** Selig models tail shielding with flow-shadow maps `η_s = V_local/V_total = f(u, v)`. The NACA tail-damping-power factor was found unreliable [S2]. Without shielding, the fin keeps full authority in a flat spin and recovery is too easy. D9b already showed that a developed spin does not recover with neutral controls; keep its standard-recovery test as the regression.
- **Knife-edge and high-α fuselage.**
  - **Today:** the fuselage exists only inside the borrowed CYb (−0.489, linear, then sin β past 15–25°).
  - **Selig:** fuselage segments with a 360° side-force table; a ShowTime 50 without side-force generators "stalls" in knife edge near β ≈ 65° [S2].
  - **Model:** crossflow drag per segment, `dF = ½ρ (V sinβ_local)² · C_dc · h(x) dx` (Allen/Jorgensen crossflow theory; C_dc ≈ 1.2 round, ≈ 2 for a sharp-edged box, Hoerner; not fetched, estimated).
  - **Pitfall:** count the fin and fuselage once. CYb today includes both.
- **Controls at large deflection.** Linear angle shifts overstate authority at large deflections and in stalled flow. Selig uses per-deflection 360° polars (0/15/30/50°) [S2]; PicaSim drops control effectiveness to 30 % when stalled (RESEARCH.md). Anyoji shows a near-zero response band at low Re. A cheap bridge is to cap the effective angle shift as the strip stalls.
- **Adverse yaw and aileron reversal.** Both emerge from strip drag once each strip's CD includes its deflection: the down aileron's strip has more α, more induced and profile drag, and stalls first near CLmax. That gives the reduced or reversed roll a pilot knows from slow-flight aileron turns. Check the sign with a flown test, not with a data-only Cnδa.
- **Flaps.** Plain-flap section ΔClmax ≈ 0.9 and slotted ≈ 1.3, scaled by S_flapped/S·cosΛ (Raymer table; not fetched, estimated). P-51 flaps are fixed today; a flap is one more strip deflection with its own table.

### T6. Ground effect

- **Physics.** The image vortex system reduces downwash at the wing (more lift at the same α, less induced drag at the same CL) and at the tail, which gives a nose-down Δ: more lift at the tail. Influence ratios depend on h/b, aspect ratio, planform and CL, not on h/b alone (Phillips & Hunsaker 2013 [S13]; formulas behind a 403, not read). OpenAeroStruct implements a mirror plane parallel to the freestream [S14]. NASA TN D-926 and the FAA PHAK give qualitative and experimental checks (RESEARCH.md).
- **Derived (image-method Weissinger VLM, AR 5 rectangular, α 4°, tail point 0.72 m aft and 0.05 m below):**

| h/b | CL / CL∞ (same α) | CDi / CDi∞ (same CL) | Wieselsberger `1 − (1−1.32h/b)/(1.05+7.4h/b)` | McCormick `x²/(1+x²)`, x = 16h/b | tail ε / ε∞ |
|---:|---:|---:|---:|---:|---:|
| 0.10 | 1.35 | 0.51 | 0.52 | 0.72 | 0.27 |
| **0.17 (Ugly on wheels)** | **1.16** | **0.67** | 0.66 | 0.88 | **0.49** |
| 0.25 | 1.09 | 0.77 | 0.77 | 0.94 | 0.67 |
| 0.50 | 1.03 | 0.91 | — | 0.99 | 0.90 |
| 1.00 | 1.01 | 0.97 | — | 1.00 | 0.98 |

- **Wing height.** The Ugly's wing is ≈ 0.26 m above the ground on its gear (gear contact z −0.258 m, wing at the LE datum; estimated), so h/b = 0.17.
- **Flare estimate (derived):** dε/dα 0.457 free vs 0.257 at h/b 0.17. At α ≈ 11.6°, Δε ≈ 2.3°, giving ΔCm = −a_t η V_H Δε ≈ −0.063, about 4.3° more up-elevator. Pilots feel this as "float plus nose heaviness".
- **Per strip.** Use the strip's quarter-chord height above the terrain (bank changes h per strip, giving a roll moment near the ground). Fade to zero by h/b ≈ 1. Use the CL ratio at the same α (multiply the strip CLα, or reduce its induced angle) and the ε factor at the tail. No effect in separated flow (Selig: "ground-effect correction … through a downwash correction" [S2]).

### T7. Speed, energy and scaling checks

| Check | Ugly sim | Physical expectation | Status |
|---|---|---|---|
| 1-g stall | 9.49 m/s (repair report) | √(2mg/(ρS·1.1)) = 9.51 m/s | consistent; CLmax ±0.15 gives ±0.6 m/s |
| Wing loading | 62.1 g/dm² | Selig's ShowTime 50 (1.45 m, 2.9 kg): 61.5 g/dm² [S2] | same class |
| Top level speed | ≈ 31.5 m/s (trim ok at 30, fails at 32; measured, WIP propulsion tree) | below the APC 12×6 zero-thrust speed J₀·n·D ≈ 0.62·n·0.305 → needs ≥ 10 000 rpm in flight | plausible; no independent .60 measurement found in this pass |
| Glide | L/D 9.11 at 15 m/s (repair report) | borrowed polar: L/D 9.4 at 15 m/s, max 11.5 at 11.4 m/s, min sink ≈ 1.0 m/s (airframe only) | max L/D optimistic; verify with drag buildup and stopped-prop drag (doc 03) |
| Re mismatch when borrowing | 25e → Ugly k = 1.2: Re ×1.31 | Re affects CLmax and CD0 more than CLα and Clp | borrow damping derivatives, not CLmax/CD0 |

## Implementation options and trade-offs

**Fidelity ladder** (per-call costs measured on the dev VM in GDScript; ×4 per tick for RK4; L1–L3 costs estimated from ~10 µs per surface):

| Level | Content | Per tick (GDScript) | What it buys |
|---|---|---:|---|
| **L0 (today)** | oracle + 6 strips + 2 tails, flat-plate post-stall, blend | 177 µs (oracle) / 341 (local) / 462 (blend), measured | stable, passive, continuous; damping changes by regime |
| **L1 (consistency)** | local model everywhere: VLM induced map on the strips (wing-alone slope), true-slope tails with an explicit lagged ε, apparent roll inertia, ground effect (wing + ε); oracle kept as the test | ≈ 360 µs (+1 aux state, a 6×6 mat-vec) | one damping in every regime; CLα̇/Cmα̇; flare; removes the blend cost |
| **L2 (stall dynamics and tables)** | 8–10 strips per side, per-strip 360° tables (Viterna/Lindenburg + deflection), GK state per strip, fuselage crossflow segments, tail shielding map | ≈ 1.0–1.3 ms (GDScript) → needs flattening/GDExtension | hysteresis, snap entries, tip stall, knife-edge, spin realism |
| **L3 (Selig-class)** | ~20 strips per wing, nonlinear-LL induced tables per deflection, propwash bands (doc 03), slipstream swirl, biplane/SFG shielding, full 360° α/β tail tables | ≈ 30–80 µs in C++ (estimated: 50–100× GDScript) | the FS One envelope (harriers, blenders, rolling harriers) |

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| Keep borrowing a whole-aircraft derivative set | Flight-identified source | Wrong airframe, inertia mismatch, regime split | Keep only as oracle/test |
| AVL/VLM-derived derivatives per aircraft | Geometry-true, repeatable, same pipeline for EX/P51/AV | Inviscid, small-angle, no fuselage, no Re | **Yes**: provenance "derived (AVL)" |
| Strip model with a precomputed induced map | Exact in the linear range (CLα and Clp both right), any n, cheap | Approximate in stall (map built for attached flow) | **Yes (L1)** |
| Selig per-strip ε(α) tables | Nonlinear, handles deflection | ≈ 1.6× roll damping (antisymmetric loading not captured) | Combine with the map, do not replace it |
| Runtime nonlinear lifting line | Best physics | Iterative, nondeterministic convergence, cost | No |
| GK per strip | 1 ODE, smooth hysteresis, borrowed constants | Constants uncertain; memory breaks the per-state passivity test | **Yes (L2)** after L1 |
| Beddoes–Leishman | Complete | 12 constants, rotor-oriented | No |

**Recommendation.** Do L1 now, in this order: regime-consistency red test → VLM tool → induced map → tail ε state with lag → apparent roll inertia → ground effect. Re-run D8b/D10 after it. L2 waits for Gate 2 ratings and a performance decision (flattened data or GDExtension). Never fit Clp or Cmq to close a mode gap; measure Ixx instead.

## Godot / GDScript notes

- **Auxiliary states** (ε lag, GK X per strip) follow the servo and rpm pattern: advance once per tick in `pre_step` with the exact update `x += (x_target − x)·(1 − e^(−dt/τ))` and hold them across the RK4 stages. That is unconditionally stable for τ < dt (a jet at 60 m/s with c 0.25 m has τ1 = 0.52c/V ≈ 2 ms < 4.17 ms) and bit-reproducible at 30/60/144 fps.
- **Splitting error.** Inputs to X0 (α, α̇) come from the state at the start of the tick. `α̇` should be the analytic `(u·ẇ − w·u̇)/(u²+w²)` from the previous derivative, not a finite difference (noise and frame dependence). The 240 vs 480 Hz convergence test must be extended to cover the new states.
- **Precision.** Everything in float64 `PackedFloat64Array`. The induced map is an n×n `PackedFloat64Array` built at load time; no `Vector3`/`Basis` (enforced by `app/test.sh`).
- **Cost.**
  - **Breakdown:** Dictionary lookups (`model.aero.CLa` and similar) dominate. The measured `tanh+exp` takes 0.105 µs and a 1-D table lerp 0.128 µs.
  - **Precompile:** turn each aircraft into a flat "aero plan" at load: strip arrays of y, chord, area, table offsets and map rows.
  - **Blend cost:** the oracle path still runs `local_flow_weight` (44 µs per call), and the blend region pays for both models. L1's "local model everywhere" removes both.
- **Tables.** Store 360° per-strip tables as `PackedFloat64Array` with a fixed α step (1–2°) and wrap index arithmetic. Interpolate linearly (Selig does the same [S2]). Never use `Curve` resources: they are 32-bit and sample in float.
- **GDExtension.** C++ with `double` is the escape hatch for L2/L3. Keep the GDScript implementation as the reference for golden flights.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use it here |
|---|---|---|---|---|
| AVL 3.52 / 3.40b | VLM stability and control derivatives, trim, eigenmodes | GPL (stated, version unspecified) | [S7] | External offline tool; numbers only, provenance-stamped |
| AeroSandbox | Python VLM, AeroBuildup, NeuralFoil, AVL/XFOIL wrappers | MIT | [S10] | Pinned in a research venv; cross-check AVL |
| NeuralFoil | Fast airfoil polars with confidence | MIT | RESEARCH.md | Section tables at strip Re; mark low-confidence regions |
| XFOIL | Section polars with LSB | GPL | [S19] | Offline polars ≤ stall |
| OpenVSP / VSPAERO | Geometry, VLM/panel, Python API | NOSA 1.3 | [S9] | Optional; heavier than AVL |
| flow5 / XFLR5 | GUI LLT/VLM/panel for model aircraft | GPL (XFLR5) | RESEARCH.md | Manual cross-check only |
| In-repo minimal VLM (this report's scratch script, ~100 lines numpy) | CLα, Clp, ground effect by images | ours (MIT) | — | Commit as `research/aero/vlm.py` with known-answer tests |
| UIUC LSAT vol. 1–5 | Measured low-Re polars (3e4–5e5) | "GPL'd Data" terms | [S21] | Validation only; do not bundle |
| Sheldahl & Klimas SAND80-2114 | NACA 00xx 0–180° measured + synthesized | US government report | [S20] | 360° shape check for symmetric tails |
| UMN 25e identification | m, swing-test I, identified A/B, CR bounds | paper (copyright) | [S1] | Independent validation numbers (cite; no data copied into the app) |
| UMN US120 (Lie thesis App. D) | mass, I, identified derivatives at 19.2 m/s | thesis | [S6] | Already used in D8b |
| NASA/UMN US120 wind-tunnel lookup model | Large α/β nonlinear tables, "made publicly available by NASA" [S5] | unverified | not located in this pass | Lead: a measured large-envelope Stik dataset |
| Selig 2014 / 2010 papers | Component-buildup method, Lindenburg 3-D correction, shadow maps | paper | [S2, S3] | Method reference for L2/L3 |
| Khan thesis (McGill 2016) | Full-envelope segment model, GK constants, propwash, k criterion | thesis | [S4] | Constants and validation method |
| airfoiltools.com polars | XFOIL polars, CSV | site data (computed) | [S18] | Quick screening only |

## Parameters and data

| Quantity | Typical RC value | Unit | Kind | Source |
|---|---|---|---|---|
| Wing Re, .60 sport (c 0.3 m, 9.5–31.5 m/s) | 2.0e5–6.6e5 | — | derived | T1 |
| Tail Re (c 0.17 m) | 1.1e5–3.7e5 | — | derived | T1 |
| Section clmax at 2e5: Clark Y / NACA 2415 / 0012 | 1.40 / 1.37 / 1.11 | — | derived (XFOIL) | [S18] |
| Airplane CLmax, .60 Stik (flaps none) | 1.0–1.25 (use 1.1) | — | estimated | T1 |
| CD0, .60 fixed-gear sport | 0.035–0.05 | — | estimated / borrowed 0.0434 | EX-05, P51-05, data |
| Oswald e at Re 2–5e5, AR 5 | 0.7–0.8 | — | estimated | EX-05; [S17] trend |
| CLα wing, AR 5 rectangular | 3.98 (VLM), 4.25 (Helmbold) | 1/rad | derived | T2 |
| Clp, AR 4.8–5.5 straight wing | −0.38…−0.43 | 1/rad | derived (VLM) / measured flight [S1, S6] | T2 |
| dε/dα at the tail, AR 5 | 0.46 (VLM), 0.50 (elliptic) | — | derived | T2 |
| a_t η (true tail slope), Ugly | ≈ 3.2 | 1/rad | derived from 1.75/(1−0.457) | T2 |
| CLα̇ / Cmα̇, Ugly | 1.43 / −3.4 | 1/rad | derived | T2 |
| Downwash lag l_t/V | 76 ms (9.5 m/s) … 23 ms (31.5 m/s) | s | derived | T5 |
| Ixx/(m b²), Stik family | 0.028 (25e, US120); Ugly inventory 0.0172 | — | measured (swing) / derived | [S1, S6] |
| Apparent roll inertia, Ugly (2-D bound) | 0.026 | kg·m² | derived | T3 |
| GK τ2 (stall delay) | 4.5 c/V | s | borrowed (NACA 0015) | [S4] |
| GK τ1 (relaxation) | 0.52 c/V … 4.24 c/V | s | borrowed | [S4, S12] |
| Quasi-steady limit k = α̇c/2V | 0.05 | — | borrowed | [S4] |
| CD90 finite wing (Viterna) | 1.11 + 0.018 AR (1.2 at AR 5); 2-D 1.98 | — | borrowed | RESEARCH.md |
| Stall hysteresis (low Re, AR 2.5) | stall 12°, reattach 11.3° | deg | measured (wind tunnel) | RESEARCH.md (Toppings) |
| Ground effect at h/b 0.17 | CL +16 %, CDi −34 %, ε −51 % | — | derived (VLM) | T6 |
| Selig wing elements per wing; integration | ~20; RK4 at 300 Hz | — | manual (paper) | [S2] |
| Giant scale (P-51 1/4): Re, c/V at 22 m/s | ~7.6e5; 0.023 s | — | derived | P51-05 geometry |
| Foamies (< 1 m): Re | < 1e5; e < 0.5 possible | — | measured trend | [S17] |

## Validation

**Verification (known answers):**
1. VLM: an elliptic planform gives Helmbold's `CLα = 2πA/(2+√(A²+4))` within 3 %. The rectangular AR 5 Clp converges (−0.404 → −0.397 from 20 to 480 panels). Ground-effect CDi ratio matches Wieselsberger within 2 % for h/b 0.1–0.25.
2. Strip model with induced map: linearized CLα and Clp within ±3 % of the fine VLM for n = 3, 5 and 10 per side.
3. **Regime consistency:** linearized Clp, Cmq(+Cmα̇), Cnr and CLα at α = 0, 4, 8, 10 and 11° within ±10 % of each other. Today this fails (1.73×, 0.32×), so the test is red first.
4. Downwash lag: the response to an α step at fixed q shows the tail-force lag `τ = l_t/V` (fit within 5 %). Linearized CLα̇ equals 1.43 ± 15 %.
5. Ground effect: a fixed-α sweep down to h/b 0.1 reproduces the table in T6. Effect < 0.5 % at h/b > 2. Continuous (no jump) as the wing crosses the fade height. Banked: the low wing gets more lift, the sign is correct.
6. GK: with α̇ = 0, X → X0 and loads equal the static curve bit-for-bit (oracle). A step response has time constant τ1. A ramp at α̇ = 1 rad/s delays the CL peak by `τ2·α̇` ± 10 %. A slow cycle gives a hysteresis loop that closes.
7. Energy: per-state passivity holds for all memory-free parts. For memory states, average power over a closed α cycle at fixed V ≤ 0 under quasi-static motion.

**Independent validation:**
- Roll τ and short period vs **both** 25e and US120 at matched CL (table in T3), reported as bands, not targets.
- Steady pb/2V per aileron degree vs the 25e (0.373/rad).
- 1-g stall speed vs owner video (frame counting, ROADMAP).
- Float distance and elevator in the flare vs owner rating.
- Spin: a recovery-turns band from pilot reports, labelled pilot judgement.

**Mutation tests that must fail:** Ixx ×2 (the roll band moves); dropping the ε lag (CLα̇ check fails); a ground-effect sign flip; applying the strip map twice (Clp halves); GK τ2 = 0 (the ramp delay test fails); `wing_aileron_effectiveness` without the induced map (the Clp consistency test fails).

## Pitfalls and risks

1. **Calibrating damping to close an inertia gap.** Flight τ only fixes Clp/Ixx. Mitigation: measure Ixx; keep Clp from VLM/AVL; label apparent mass separately.
2. **Treating the oracle as truth.** It is a different airframe (25e). Its Clp is 18 % above the 25e's own identification. Mitigation: oracle = regression test only; derived values go into the data with provenance.
3. **Strip theory with a 3-D or airplane CLα.** It double-counts the tail (EX-05/P51-05 notes: 7–8 %) and overstates roll damping 1.6–1.9×. Mitigation: wing-alone section slope plus induced map.
4. **AVL outside its envelope** (pb/2V > 0.1, α > ~10°, fuselage). Mitigation: use AVL only for linear derivatives at 2–3 CLs; post-stall from tables.
5. **Sign and axis conventions** (AVL stability vs body axes; δ signs). Mitigation: one conversion function with a symmetric-wing known-answer test and the existing loader relations (`Cndr = −CYdr l/b`).
6. **Double counting the fuselage** (CYb already contains fuselage and fin). Mitigation: when fuselage segments are added, re-derive CYb from the fin only.
7. **GPL contamination.** Mitigation: AVL, XFOIL and XFLR5 are external tools only; UIUC data stays outside `app/`; the source of each number is recorded.
8. **GK constants from the wrong airfoil and Re** (NACA 0015 and OA209 at higher Re). Mitigation: label them borrowed, sweep ±50 % in D10, and gate on Gate 2 ratings.
9. **Memory states versus determinism.** Restart and trace must reset aux states. The trim solver must solve with X = X0 and ε = steady. Mitigation: aux states live in the state packet that traces hash.
10. **Ground-effect height taken from the CG or wheels** (high-wing vs low-wing confusion; RESEARCH.md). Mitigation: per-strip quarter-chord height.
11. **Cost blow-up in GDScript** (≈ 10 µs per surface). Mitigation: flat aero plan first, measure µs/tick per step (rule 7), GDExtension before L2.
12. **XFOIL Clmax optimism and LSB dead bands at tail Re.** Mitigation: compare UIUC measured points where the airfoil exists; keep CLmax as a labelled estimate with ±0.15 in sensitivity.

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
|---|---|---|---|
| X-aero-1 | Re-run D8b/D10 on the post-D1-R1 baseline; add the 25e comparison at matched CL with the T3 decomposition | `research/sensitivity/results.md` regenerated; table with both Sticks; mutation Ixx×2 moves roll τ by ≈2× | — |
| X-aero-2 | Regime-consistency test (red first): linearized Clp, Cmq, Cnr, CLα at α 0…11° | Test fails today with 1.73× / 0.32×; documented | — |
| X-aero-3 | Commit the minimal VLM (`research/aero/vlm.py`) with known-answer tests | Elliptic CLα within 1 %; AR 5 Clp −0.40; Wieselsberger within 2 % | — |
| X-aero-4 | AVL pipeline for Ugly, Extra and P-51 (pinned binary, command file, parser) | Derivative comparison table AVL vs VLM vs borrowed vs flight ID; no data change | X-aero-3 |
| X-aero-5 | Wing strips: wing-alone section slope plus precomputed n×n induced map; aileron as a strip deflection | X-aero-2 passes for Clp and CLα; goldens re-recorded deliberately; µs/tick | X-aero-2, 3 |
| E0a-2 | Tail with true slope plus explicit ε state, lag `l_t/V`; remove the effectiveness fudges | X-aero-2 passes for Cmq+Cmα̇; CLα̇ 1.43 ± 15 %; lag fit within 5 % | X-aero-5 |
| X-aero-6 | Apparent roll inertia (roll axis, labelled derived) and an owner Ixx swing test of the built airframe | Roll τ vs both Sticks within ±30 %; swing-test data with method | X-aero-1 |
| X-perf-1 | Flatten aircraft aero data into a load-time "aero plan"; decide on GDExtension | µs/tick before/after on the dev VM and the owner's slowest machine | X-aero-5 |
| M5-GE-1 | Ground effect on wing strips (per-strip height, Wieselsberger or VLM table, fade by h/b 1) | T6 table reproduced; continuity; banked sign | E0a-2 |
| M5-GE-2 | Ground effect on tail downwash | Flare trace: ≈ 4° extra up-elevator at h/b 0.17 (± 50 %); on/off traces | M5-GE-1 |
| M5-STALL-1 | Per-strip 360° tables (Viterna/Lindenburg 3-D) replacing analytic flat plate; data format v2 | Continuity sweep; CL/CD ≈ 1/tanα post-stall; CD90(AR) | X-aero-5, X-perf-1 |
| M5-STALL-2 | Goman–Khrabrov separation state per strip (Kirchhoff to ~25°, then flat plate) | α̇ = 0 bit-identical to static; ramp delay τ2·α̇; closed hysteresis loop; cycle passivity | M5-STALL-1 |
| M5-STALL-3 | Control effectiveness vs strip separation (per-deflection tables or a capped shift) | Slow-flight aileron reversal sign test; PicaSim-like 30 % stalled authority band | M5-STALL-1 |
| M5-SPIN-1 | Fuselage crossflow segments; CYb re-derived from the fin only | Knife-edge holds with β band; no double count (CYb identity test) | X-aero-4 |
| M5-SPIN-2 | Tail shielding (flow-shadow map) for fin and stab | Spin recovery turns vs pilot band; neutral-control spin behaviour documented | M5-SPIN-1 |

## Decisions to take now

1. **One aerodynamic model in all regimes.** Recommended: the local model everywhere once it matches VLM/AVL linear derivatives (X-aero-5, E0a-2), with the oracle kept as a test. It removes the damping discontinuity and the blend's double cost. Revisit the DECISIONS row "local passive loads".
2. **Data schema v2 now, before more aircraft.** Proposed shape: `aero.wing.strips[]` with `{y, chord, area, incidence, polar_id, induced_row}`, `aero.tail` true slopes, `aero.downwash {deps_dCL, eps0, lag: "l_t/V"}`, and separate 360° polar files carrying `{source, Re, method, interval: measured | computed | extrapolated}`. Generated aircraft (EX/P51) then stop encoding downwash inside slopes.
3. **Inertia policy.** Recommended: Ixx is measured or inventory-derived, labelled. Apparent roll inertia is a separate derived term. Damping coefficients never compensate inertia.
4. **Aux-state convention.** Recommended: aerodynamic memory states are advanced in `pre_step` with exact exponentials, are part of the hashed state, and are reset by restart and trim.
5. **License line.** Recommended: GPL tools and data never enter `app/`; numbers carry provenance. Confirm with the owner.
6. **Performance gate for L2.** Recommended: no strip count above 6 per side in GDScript until X-perf-1 has measured the flattened path on the owner's slowest machine.

## Sources

1. Dorobantu A., Murch A., Mettler B., Balas G., "System Identification for Small, Low-Cost, Fixed-Wing Unmanned Aircraft," J. Aircraft 50(4), 2013 (preprint), https://dept.aem.umn.edu/~mettler/Courses/AEM%205333%20(spring%202013)/AEM5333%20CourseDropbox/Week%207%20Identification/Ultrastick%20Identification/2012_AIAA_JA_SYSID.pdf — fetched.
2. Selig M.S., "Real-Time Flight Simulation of Highly Maneuverable Unmanned Aerial Vehicles," J. Aircraft 51(6), 2014, https://m-selig.web.engr.illinois.edu/pubs/Selig-2014-JofAC-FlightSim-FINAL.pdf — fetched.
3. Selig M.S., "Modeling Full-Envelope Aerodynamics of Small UAVs in Realtime," AIAA 2010-7635, https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7635-FullEnvelopeAeroSim.pdf — search result only (journal version fetched).
4. Khan W., "Dynamics modeling of agile fixed-wing unmanned aerial vehicles," PhD thesis, McGill, 2016, https://mcgill.scholaris.ca/items/56b70b0e-1f76-48ba-b973-d3b841d659ed — fetched (PDF bitstream).
5. Dorobantu A., "Test Platforms for Model-Based Flight Research," PhD thesis, U. Minnesota, 2013, https://dept.aem.umn.edu/~SeilerControl/Thesis/2013/Dorobantu_13PhD_TestPlatformsForModelBasedFlightResearch.pdf — fetched.
6. Lie F.A.P., "Synthetic Air Data Estimation," PhD thesis, U. Minnesota, Appendix D (Ultra Stick 120), https://conservancy.umn.edu/server/api/core/bitstreams/3eaa84c3-81fc-41ed-ae56-65f3ea700347/content — fetched.
7. Drela M., Youngren H., AVL home page (v3.52, GPL), https://web.mit.edu/drela/Public/web/avl/ — fetched.
8. Drela M., Youngren H., AVL 3.40 user primer, https://web.mit.edu/drela/Public/web/avl/avl_doc.txt — fetched.
9. OpenVSP repository (NOSA 1.3), https://github.com/OpenVSP/OpenVSP — fetched.
10. Sharpe P., AeroSandbox repository (MIT), https://github.com/peterdsharpe/AeroSandbox — fetched.
11. Goman M., Khrabrov A., "State-space representation of aerodynamic characteristics of an aircraft at high angles of attack," J. Aircraft 31(5), 1994 — not fetched; cited via [4] and [12].
12. Ayancik F., Mulleners K., "All you need is time to generalise the Goman-Khrabrov dynamic stall model," arXiv:2110.08516, 2022, https://arxiv.org/pdf/2110.08516 — fetched.
13. Phillips W.F., Hunsaker D.F., "Lifting-Line Predictions for Induced Drag and Lift in Ground Effect," J. Aircraft 50(4):1226–1233, 2013, https://digitalcommons.usu.edu/mae_facpub/81 — landing page fetched; PDF returned 403.
14. MDO Lab, OpenAeroStruct ground-effect documentation, https://mdolab-openaerostruct.readthedocs-hosted.com/en/latest/_sources/advanced_features/ground_effect.rst.txt — fetched.
15. Selig M.S., "Modeling Propeller Aerodynamics and Slipstream Effects on Small UAVs in Realtime," AIAA 2010-7638, https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7638-PropAeroSim.pdf — search result only (for doc 03).
16. Shen J. et al., "Calculation and Identification of the Aerodynamic Parameters for Small-Scaled Fixed-Wing UAVs," Sensors 18(1):206, 2018, https://pmc.ncbi.nlm.nih.gov/articles/PMC5795544/ — fetched via Europe PMC. It reports Ixx 0.0014 kg·m² for a 1.72 kg, 1.2 m Extra 300 (≈ 50× below the Stik ratio): an example of why published inertias need a plausibility check.
17. Ouhabi M.E.M., Narsipur S., "Off-board aerodynamic measurements of small-UAVs in glide flight using motion tracking," Aeronautical Journal 129:803–824, 2025, doi:10.1017/aer.2024.131 — fetched.
18. airfoiltools.com XFOIL polars (Clark Y, NACA 2415, NACA 0012; Re 1e5/2e5/5e5), e.g. http://airfoiltools.com/polar/details?polar=xf-clarky-il-200000 — fetched (CSV).
19. Drela M., Youngren H., XFOIL primer, https://web.mit.edu/drela/Public/web/xfoil/xfoil_doc.txt — via RESEARCH.md.
20. Sheldahl R.E., Klimas P.C., SAND80-2114, 1981, https://www.osti.gov/biblio/6548367 — fetched (abstract).
21. Selig M.S. et al., UIUC Low-Speed Airfoil Tests, volumes 1–5, https://m-selig.ae.illinois.edu/uiuc_lsat.html — fetched.
22. Viterna L.A., Corrigan R.D., NASA (via RESEARCH.md), https://ntrs.nasa.gov/api/citations/19830010962/downloads/19830010962.pdf — via RESEARCH.md.
23. Toppings C., Yarusevych S., transient stall and reattachment at low Re, JFM — via RESEARCH.md.
24. Anyoji M. et al., control effectiveness at low Re, J. Fluid Sci. Tech. — via RESEARCH.md.
25. NASA TN D-926 (ground effect, rectangular wings) and FAA PHAK ch. 5 — via RESEARCH.md.
26. CRRCSim, PicaSim, YASim, JSBSim source/manual notes — via RESEARCH.md (full-envelope table).
27. Beard R., McLain T., *Small Unmanned Aircraft* (sigmoid stall blend) — via RESEARCH.md.
28. Ananda G., Deters R., Selig M., propeller-induced flow on a low-Re wing, AIAA J. 2018 — via RESEARCH.md (for doc 03).
