# 08 — Validating the simulator against real RC aircraft: measurement, flight testing, system identification and pilot evaluation

**Status:** research knowledge base, initially observed 2026-10-06; current validation status reconciled against the project audit dated 2026-10-06. **Serves:** ROADMAP rule 6 (verification ≠ validation), Gate 2 and Gate 2-R, D8b (independent validation), D10 (sensitivity → what to measure next), EX-09 and P51-09 (independent contrast), E3b/E3c proofs (takeoff and landing roll), G1/G2 (propeller, engine), M5 wind. **Read with:** [ROADMAP](../../../ROADMAP.md), [RESEARCH.md § Verification and real-world validation](../../../RESEARCH.md#verification-and-real-world-validation-are-different-and-both-can-start-cheaply), [RESEARCH.md § transfer](../../../RESEARCH.md#5-does-simulator-practice-transfer-to-real-rc-flying), [RESEARCH.md § learning parameters](../../../RESEARCH.md#10-learning-flight-model-parameters-from-recorded-data), [sensitivity results](../../../research/sensitivity/results.md), [flight-repair report](../flight-repair-implementation.md), [06 radio and latency](06-radio-input-servos-latency.md).

## Summary

- **D11a's rerun is complete.** The generated [`research/sensitivity/results.md`](../../../research/sensitivity/results.md) contains D8b, the like-for-like 25e comparison and the repaired D10 sweep; there are no refused variants. Current roll-pole gaps are 2.07× against the Froude-scaled US120 and 2.37× against the 25e. The earlier refusals and stale values describe the pre-D11a state only.
- **The Ultra Stick 25e flight identification is freely readable.** A UMN course page hosts a preprint of Dorobantu et al., the paper ROADMAP lists as "paywalled". At 19 m/s: SP 16.33 rad/s, ζ 0.83; roll pole 12.53 s⁻¹; dutch roll 4.96 rad/s, ζ 0.33; servo 50.3 rad/s second order plus 50 ms delay; swing-test inertia Ixx/Iyy/Izz 0.089/0.144/0.162 kg·m² [1].
- **The two independent flight IDs agree: the sim rolls 2–2.4× too fast.** In the current D11a like-for-like result at equal CL, the sim against the 25e gives roll 2.37×, SP 0.87× and DR 1.46× (derived). Most of the roll gap comes from the inertia ratio Ixx/(m·b²): 0.0172 in the sim against 0.0282 on the 25e swing-test model. The borrowed Clp remains less damped than the flight-identified 25e value.
- **OpenFlightSim's 25e inertia is not UMN's own swing-test value.** Iyy 0.0864 against 0.144 kg·m². Our plausibility warning ("Jyy 2.11× the scaled 25e") compares against the weaker number.
- **The #1 measurement is a bifilar swing test for Ixx.** It costs about $10 and 2 h. Even with Ixx and Iyy measured, flight data only identifies ratios such as Lp = q̄Sb²Clp/(2V·Ixx). The swing test is therefore the prerequisite for any coefficient identification.
- **Apparent (added) mass is large on a light RC wing.** In roll, the wing's added inertia is ρπc²/4·b³/12 ≈ 0.026 kg·m², i.e. 23 % of the sim's Ixx (derived). A swing test in air measures it (NACA TR 467 corrects for it [10]), and the real roll mode feels it. The sim has no such term.
- **Public flight logs exist.** UMN "Thor" flights 44/45 hold 1 s, 4° doublets on all three surfaces (2012, .mat 2.2 MB). They were flown with Dorobantu present (inference: the 25e campaign). The Baldr flights hold Ultra Stick 120 stall and spin test points. No licence is stated, so cite them and do not redistribute.
- **Use the flight controller as a passive logger.** A Matek F405-WING or H743-WING with ArduPilot and an ASPD-4525 pitot costs about $120–200. Split SBUS from the receiver so the FC logs RCIN, IMU, ATT, GPS, BARO and ARSP and never drives a servo. ArduPilot's SystemID mode only exists for QuadPlane modes, so on a fixed wing the pilot flies the excitation inputs [22][23]. EdgeTX SD logs are 10 Hz at best, which only suits slow quantities [26].
- **A 1 psi pitot is coarse at stall speed.** Its ±0.25 % span spec equals ±17 Pa, i.e. ±16 % of V at 9 m/s (derived). Zero it on the ground and calibrate it against reciprocal GPS runs, or measure stall another way.
- **Borrow the tolerance bands from FAA Part 60 FFS qualification [12].** Roll rate ±10 %, mode periods ±10 %, phugoid damping ±0.02, steady sideslip ±1° β, stall speed ±3 kt (scale this one to RC), time histories by Theil coefficient < 0.25 [1][2]. Collect them in a generated per-release **validation dashboard**.
- **Pilot ratings need numbers to be trusted.** With an assumed between-pilot SD of 0.8 on the −2…+2 scale, the 95 % CI is ±2.0 with 3 pilots and ±1.0 with 5. Treat one owner session as directional only. In a blind A/B test with 10 trials, 9 correct is needed for p < 0.05.
- **Golden flights compare at a 1e-6 tolerance, not bit-for-bit** (`tests/golden_flights.gd`). Add metamorphic tests: mirror symmetry, Froude-scaling invariance, and energy decrease with the engine off.

## Where the code stands

| Item | Fact (repo, 2026-10-06) | Gap for validation |
| --- | --- | --- |
| Verification of handling | [`test_handling.gd`](../../../app/tests/test_handling.gd): trim α 4.26° ± 0.5, coordinated roll 144/192 °/s ± 7 %, glide L/D 9.1 ± 2 %. These come from the same coefficients the sim uses (circular, rule 6) | No independent reference in CI |
| Flight modes | [`linearize.gd`](../../../app/physics/linearize.gd) (central differences, Faddeev–LeVerrier, Durand–Kerner); [`test_modes.gd`](../../../app/tests/test_modes.gd) bands ± 3 % at 10/15/25 m/s, recorded 2026-10-06. At 15 m/s: SP 1.495 Hz ζ 0.739, phugoid 0.103 Hz ζ 0.256, roll τ 0.0513 s, DR 0.773 Hz ζ 0.289, spiral eigenvalue +0.034 s⁻¹ | Regression only, not truth |
| D8b / D11a references | [`sensitivity.gd`](../../../research/sensitivity/sensitivity.gd) and generated [`results.md`](../../../research/sensitivity/results.md) contain US120 and the like-for-like 25e comparison. The D11a 15 m/s baseline matches `test_modes`; current roll gaps are 2.07× (US120) and 2.37× (25e) | Re-run after physics/data changes; there is not yet an automatic stale-result guard |
| D10 sweep | D11a repaired the mass, CG and fin-area perturbations through valid data paths. The generated table has no refused rows; Cnr still dominates the spiral crossing, followed by Clp, CD0, Ixx, Iyy, Izz, CLmax and Cmq | Preserve the no-refused-rows/output-count check on future runs |
| Golden flights | [`app/tests/golden/`](../../../app/tests/golden/): `glide_15`, `pull_throttle`, `roll_15`, `rudder_doublet`; replay tolerance 1e-6 m, m/s, rad/s; 1e-9 quaternion | Good regression net; no circuit (E4) |
| Trace | CSV `openrc-trace v3`, initial sample plus one row per 240 Hz tick; T key records in-app. [C7-R1](../trace-integrity/C7-R1/README.md) enforces completion/finiteness; [C7-R2](../trace-integrity/C7-R2/README.md) identifies configured model paths, state layouts and recording-start auxiliary state | No importer for real logs or recorded-input replay. The current header repairs the audit's false P-51 “no propwash” claim; exact input hashes and a complete replay/checkpoint contract remain DATA-3 and H8/H9 |
| Pilot feedback | [`.github/ISSUE_TEMPLATE/pilot_feedback.md`](../../../.github/ISSUE_TEMPLATE/pilot_feedback.md): free text on handling, visibility, setup | No task, standard or rating scale |
| Data provenance | Each number has {value, unit, kind, source}; kinds manual/measured/borrowed/estimated/derived | No `uncertainty` field (blocks Monte-Carlo); no "identified" kind |
| Measured hardware | Plan CG, plan nose and engine catalog values only. Throws, inertia, thrust, rpm, C_rr (0.10/0.20/0.30 FlightGear-scaled guesses in `app/data/ground/surface_friction.json`) and servo time are estimates | Everything below |

## Theory and models

### Fidelity levels of validation

| Level | Evidence | Answers | State |
| --- | --- | --- | --- |
| L0 verification | Known answers, golden flights, metamorphic and property tests | "Does the code solve our equations?" | Strong; add metamorphic tests |
| L1 public references | Flight-identified modes of related airframes (US120, 25e); public flight logs replayed | "Is the model the right class of airplane?" | US120 and 25e comparisons incorporated in D11a; public log replay remains open |
| L2 owner measurements | Mass, CG, inertia, throws, thrust, C_rr; tripod-video flight metrics | "Are the inputs right?" | None yet |
| L3 instrumented flight | Logged flights, system ID, tolerance tables, pilot-in-the-loop ratings | "Does it fly like the real Stik?" | Gate 2 / 2-R |

### Ground measurement equations

- **Three-scale CG** (airplane level on three scales): x_cg = Σ Rᵢxᵢ / Σ Rᵢ. **Vertical CG** by tilting the nose up by θ (wheelbase l, weight W, change of nose reaction ΔR_n): h = l·|ΔR_n| / (W·tan θ) above the axle line. The CG is above that line if R_n falls as the nose rises. Derived from statics.
- **Bifilar pendulum** (two vertical wires of length L, spacing D, symmetric about the CG, small amplitude, undamped): I = m·g·D²·T² / (16π²·L) [9]. Error budget δI/I ≈ δm/m + 2δD/D + 2δT/T + δL/L. With δm 5 g, δD 2 mm (D = 0.6 m), δL 5 mm (L = 2 m) and 20 periods timed, the result is ≈ 0.7 % RSS (derived). The **systematic** terms are larger: rig tare, wires not parallel, CG off the axis, pendulum sway, air damping (Jardin & Mueller add nonlinear damping terms [9]) and apparent mass.
- **Apparent mass** (NACA TR 467 [10]): air moved by the swinging airplane adds inertia. For roll, each wing section moves normal to its plane: ΔIx ≈ ρπc²/4 · b³/12. That gives 0.026 kg·m² (23 % of 0.115) for the Stik and 0.010 kg·m² (12 % of 0.089) for the 25e (derived). It is smaller in pitch (horizontal tail) and smallest in yaw. Record the rigid value and the apparent value separately.
- **Compound pendulum** for Iyy (knife edge at height h above the CG): I_cg = m·g·h·T²/(4π²) − m·h². This is the Gracey simplification of TR 467 (NACA TN 1629, cited in NTRS, not opened). For the Stik (k ≈ 0.39 m), h ≈ k minimises sensitivity: 2 mm error in h gives < 0.1 %; at h = 0.2 or 0.8 m it gives 0.7–0.8 % (derived).
- **Static thrust**: Ct = T/(ρn²D⁴). The sim predicts 41.3 N at 11,149 rpm (Ct 0.113, derived from the UIUC 11×6 static table, 12×6 diameter). rpm error doubles in thrust: 2 % rpm → 4 % T.
- **rpm by sound**: a single-cylinder two-stroke fires once per revolution (fundamental rpm/60 = 186 Hz at 11,149 rpm), and a two-blade prop's blade-pass frequency is 2·rpm/60 = 372 Hz. A phone FFT replaces an optical tachometer (inference; check against a tach once).
- **Rolling resistance**: towed at a steady walking pace, C_rr = F_pull/W. A coast-down gives a = −g·C_rr (aero drag is negligible below 2 m/s). Prop removed for safety.
- **Control throws**: δ = asin(d/c_s), with d the trailing-edge travel and c_s the surface chord. Measure at 5 stick positions to obtain the stick→surface curve (expo, end points).

### Flight-test relations

- **Stall**: CL_max = 2W/(ρ·S·V_s²), with ρ = p/(R·T) from the field's pressure and temperature. Entry deceleration ≤ 1 kt/s = 0.51 m/s² (14 CFR 25.103 [13]).
- **Airspeed**: V = √(2Δp/ρ). The ±17 Pa sensor spec gives V errors of 16 / 9 / 6 % at 9 / 12 / 15 m/s; at 2 Pa residual they are 2.0 / 1.1 / 0.7 % (derived).
- **Glide**: tan γ = (D − T)/L. At idle, compare the sim at the *same* idle rpm instead of correcting for thrust. A glow engine is not stopped in flight on purpose.
- **Phugoid sanity**: Lanchester's T ≈ π√2·V/g gives 6.8 s at 15 m/s; the sim gives 9.7 s (0.103 Hz). That is a cheap real check from baro or video altitude (inference: thrust variation with speed is the likely reason).
- **Roll rate from video**: p = 360°·N/(Δframes/fps). A full roll at 144 °/s lasts 600 frames at 240 fps, so ±2 frames ≈ 0.3 %. **Roll τ (0.04–0.1 s) is only 10–25 frames at 240 fps and 2–5 samples at 50 Hz.** It needs an onboard gyro at ≥ 200 Hz.

### Input design

| Input | Spectrum (computed, half-power band) | Use |
| --- | --- | --- |
| Doublet, 1.0 s period (UMN Thor 44: 4°) | peak 0.75 Hz, 0.38–1.12 Hz | Dutch roll (0.77 Hz), roll |
| Doublet, 0.5 s period | peak 1.5 Hz, 0.75–2.25 Hz | Short period (1.5 Hz at 15 m/s) |
| 3-2-1-1, Δt 0.15 s (1.05 s long) | 0.36–2.8 Hz | Short period and roll; hard to fly by hand |
| 3-2-1-1, Δt 0.3 s | 0.18–1.4 Hz | Dutch roll, phugoid onset |
| Log chirp 0.1–5 and 4–15 Hz, 4° (Dorobantu) | by design | Frequency-domain ID; needs automation |
| Orthogonal phase-optimised multisines (Morelli) | by design | All axes at once; "like light-to-moderate turbulence"; pilots can approximate them [16] |

Dorobantu's rules of thumb [1]: 10 s windows (so nothing below 0.1 Hz is identifiable: phugoid and spiral are excluded), response ≥ 3× the noise (≥ 6 °/s on rates with 2 °/s gyro noise at 70 % throttle), one surface at a time with the pilot holding the other axes. Phugoid and spiral need separate hands-off tests of 30 s or more.

### System identification (simplest first)

1. **Replay validation (no fitting):** drive the sim with the recorded surface commands from the recorded initial state over 2–10 s windows and score p, q, r and a_y with the Theil inequality coefficient TIC = √(Σ(x−x̃)²/n) / (√(Σx²/n) + √(Σx̃²/n)). TIC < 0.25 counts as accurate for fixed wings [1][2]. Dorobantu's identified 25e model scored roll 0.07, pitch 0.12, yaw 0.26.
2. **Equation error** (linear least squares; SIDPAC's core [17], Klein & Morelli [18]). Example for roll: Ixx·ṗ − Ixz·ṙ − (Iyy − Izz)qr = q̄Sb·(Clβ·β + Clp·p̂ + Clr·r̂ + Clδa·δa + Clδr·δr). θ̂ = (XᵀX)⁻¹Xᵀy, Cov = σ²(XᵀX)⁻¹. It needs ṗ (smoothed numerical derivative), β (vane, string or estimate) and **measured inertia**, otherwise only Clp/Ixx is identifiable.
3. **Frequency domain**: H(f) = G_uy/G_uu, with coherence as the quality weight. CIFER is the reference tool (Army/SJSU, free student version) [19]. Morelli's frequency-response-error (FRE) estimator [16]. UMN's OpenFlightAnalysis (`FreqTrans.py`, `GenExcite.py`, MIT) [7].
4. **Output error** (maximum likelihood, iterative, sensitive to the initial guess; Dutra's collocation variant handles unstable modes [21]). Use it last, once 1–3 work.

Rule: fit on one maneuver set, validate on another, and record in the reference file whether a value was used for tuning.

### Scaling and why borrowed references can mislead

- **Froude similarity** (Wolowicz et al., NASA TP-1435 [15]): length ×N, velocity and time ×√N, frequency ×1/√N, mass ×N³ (same air density), inertia ×N⁵. The repo's US120 → Stik step (lengths ×0.79, frequencies ×1.12) applies the kinematic part only.
- **Relative density is not matched.** A Froude-scaled US120 at the Stik's span would weigh 8.34·0.794³ = 4.17 kg; the Stik weighs 2.6 kg (0.62×). A scaled 25e would weigh 3.39 kg (Stik 0.77×). Lower relative density changes the nondimensional modes, so compare **nondimensional** quantities (ω·c/2V, λ·b/2V) at equal CL, and say so.
- **Reynolds number**: Stik at 15 m/s, c 0.305 m → Re ≈ 3.1·10⁵; 25e at 19 m/s, c 0.25 m → 3.25·10⁵ (ν 1.46·10⁻⁵ m²/s; derived). The 25e is Reynolds-matched; airfoils differ.
- **Results of the like-for-like scaling** (derived: ω̂ = ω·L/2V with L = c for pitch and b for lateral modes, Stik at the 25e trim CL):

| Mode | 25e flight ID, 19 m/s [1] | Nondim 25e | D11a sim at 18.8 m/s (same CL 0.28) | Nondim sim | Sim / 25e |
| --- | --- | --- | --- | --- | --- |
| Short period | 16.33 rad/s, ζ 0.83 | ωc/2V 0.1074 | 11.62 rad/s, ζ 0.75 | 0.0940 | 0.87 |
| Roll subsidence | 12.53 s⁻¹ | λb/2V 0.4188 | 24.58 s⁻¹ | 0.9944 | **2.37** |
| Dutch roll | 4.96 rad/s, ζ 0.33 | ωb/2V 0.1658 | 5.97 rad/s, ζ 0.28 | 0.2417 | 1.46 |

The flight data also checks the 25e model itself. Clp −0.4496 with OpenFlightSim's Ixx 0.0715 predicts a 25e roll pole of 18.3 s⁻¹, 1.46× the 12.53 measured; with the swing-test Ixx 0.089 it predicts 14.7 s⁻¹ (1.17×). The borrowed coefficient set is itself 15–45 % too crisp in roll before any transfer to the Stik. For nondimensional roll equality the Stik would need Ixx ≈ 0.27 kg·m² with the current Clp, or ≈ 0.23 with the flight-identified Clp. That means Rx ≈ 0.39 against 0.27 now and 0.34 for the 25e: a real airframe-dependent unknown that only a swing test resolves.

## Implementation options and trade-offs

| Option | Cost | Gives | Limits | Verdict |
| --- | --- | --- | --- | --- |
| Public mode tables (US120, 25e) | 0 | Class check, gap direction | Other airframes, other inertia | Completed for current Stik data in D11a |
| Public log replay (Thor 44/45) | 0 + tooling | Time-history TIC, tooling test bed | 25e, not Stik; licence unstated | Do after the replay harness |
| Ground measurements | $0–40, 1 day | Measured mass, CG, inertia, throws, thrust, C_rr | Inputs only, not handling | **Highest value per cost** |
| Tripod phone video (240 fps) | $0 | Roll rate, top speed, takeoff and landing roll, spin rate, stall behaviour | No rates or τ; perspective error; wind | Next after ground |
| EdgeTX + ELRS/FrSky telemetry logs | $0 if owned | Altitude, GPS speed, vario at ≤ 10 Hz | Slow quantities only | Glide, climb, top speed |
| FC passive logger + pitot | $120–200 (est.) | 100–400 Hz IMU, attitude, airspeed, stick | Mass +100–150 g (est.), vibration, setup time | Gate 2-R and D10 closure |
| Commercial ID tools (CIFER, SIDPAC) | Licence or request | Mature methods | Not open; SIDPAC needs MATLAB | Reference only |
| Python ID (numpy/scipy, OpenFlightAnalysis MIT) | 0 | Equation error, FRE, multisines | Our own code to verify | **Recommended** |
| Pilot ratings only | 0 | Feel | Subjective, one pilot | Complement, never alone |

**Recommendation:** D11a closed the current L1 sensitivity/reference rerun. Next, collect L2 ground measurements, then tripod-video metrics, then consider passive logging. Keep Python tooling outside `app/`; add a generated dashboard only when its schema and release use are scheduled.

## Godot / GDScript notes

- **Run validation scripts outside `res://`.** `sensitivity.gd` already runs through `--script "$PWD/research/..."`; keep it that way so `app/test.sh` never parses validation drafts. The completed D11a rerun took about 2 min headless and left the tree clean.
- **Replay determinism.** Replaying a real log at 240 Hz needs the log's 50–400 Hz inputs held or interpolated per tick. Use zero-order hold, matching how the radio is read once per tick (doc 06). Any interpolation choice must be explicit and also used in the synthetic round-trip test.
- **float64 everywhere.** Read CSV with `FileAccess.get_csv_line()` and `String.to_float()` (64-bit). Never pass through `Vector3`. HDF5 and `.mat` cannot be read in GDScript: convert to CSV in Python (h5py, scipy.io) first.
- **Monte-Carlo reproducibility.** Use a seeded `RandomNumberGenerator` (`seed` property, PCG32) per run and record the seed in the output. Cost: a 20 s flight is 4,800 ticks × ~0.5 ms ≈ 2.4 s, so 200 runs × 3 maneuvers ≈ 25 min headless. Mode analysis alone takes milliseconds per run, so do Monte-Carlo on modes first.
- **Keep sensitivity variants valid and count the outputs.** D11a perturbs CG, mass and Cnβ through valid data paths and produces no refused rows. Preserve an explicit row-count/refusal check so a future loader change cannot silently reduce the sweep.

## Reusable libraries, tools, code and datasets

| Name | Gives us | Licence | Link | Use here |
| --- | --- | --- | --- | --- |
| Dorobantu et al. preprint | 25e flight-ID modes, swing inertia, servo model, TIC values, input design | Paper (read, cite) | [1] | D11a reference rows; future flight-log replay |
| Dorobantu, Seiler, Balas 2013 | TIC + Monte-Carlo validation of an uncertain model | Paper | [2] | X-VAL-13 method |
| UMN Flight Data (Thor, Baldr, …) | HDF5/.mat flight logs with notes; Thor 44/45 doublets; Baldr 12/13 US120 stalls and spins | **Not stated** (cite; do not redistribute) | [3][4][5] | X-VAL-10 replay; spin qualitative check |
| OpenFlightAnalysis (UASLab) | Python frequency response, chirps, multisines, OMS, air-data calibration, servo model | MIT | [7] | Port or reuse in `research/validation/` |
| OpenFlightSim UltraStick25e | The borrowed coefficients plus mass file | MIT | [8] | Like-for-like 25e test aircraft |
| pymavlink (`DFReader`) | Parse ArduPilot `.bin` logs | LGPL-3.0+ (generated code MIT) | [24] | Offline converter only; never shipped |
| SysIdentPy | NARX/NARMAX black-box ID | BSD-3 | [20] | Low priority (not physical) |
| SIDPAC (NASA) | 300+ MATLAB ID routines | By request, not open source | [17] | Method reference |
| CIFER | Frequency-domain ID | Army/SJSU; free student version | [19] | Method reference |
| Kinovea | Frame-by-frame video, tracking | GPL-2.0 (Windows) | [27] | Owner video analysis (tool, not linked) |
| Tracker (OSP) | Video tracking, calibration stick, perspective filter, CSV export | GPL-3.0, Win/macOS/Linux | [28] | Owner video analysis on Linux/macOS |
| Hypothesis | Property-based tests with shrinking (Python) | MPL-2.0 (unverified on page) | [29] | Fuzz aircraft JSON / replay tooling |
| ArduPilot Plane | Logging FC firmware, MANUAL mode, AOA/SSA estimates | GPL-3.0 (firmware, not linked) | [22][23] | Passive logger |
| UIUC Aero Testbed (35 % Extra 260, Sukhoi 29S) | High-α flight data on giant-scale aerobatics | Papers | [30] | Future reference for the P-51/Extra class |

## Parameters and data

| Quantity | Typical / reference value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| Stik sim mass | 2.60 (plausible 2.3–3.4) | kg | derived / borrowed range | aircraft JSON |
| Stik sim Ixx, Iyy, Izz | 0.115, 0.387, 0.484 | kg·m² | derived (inventory) | measured on sim today |
| 25e swing test Ix, Iy, Iz, Ixz | 0.089, 0.144, 0.162, 0.014 (m 1.959, b 1.27, S 0.31, c 0.25) | kg·m², kg, m, m², m | measured | [1] |
| 25e OpenFlightSim Ixx, Iyy, Izz, Ixz | 0.0715, 0.0864, 0.1536, −0.014 | kg·m² | borrowed (method unknown) | [8] |
| 25e swing scaled by m·b² to the Stik | 0.170, 0.275, 0.310 | kg·m² | derived | this doc |
| Wing apparent roll inertia (Stik) | 0.026 (23 % of Ixx) | kg·m² | derived | ρπc²/4·b³/12 |
| 25e flight-ID SP, roll, DR at 19 m/s | 16.33 rad/s ζ 0.83; 12.53 s⁻¹; 4.96 rad/s ζ 0.33 | — | measured (identified) | [1] |
| 25e servo + delay | 2nd order 50.27 rad/s, ζ 0.80; 50 ms (20 ms is computation) | rad/s, s | measured (identified) | [1] |
| US120 flight-ID (Froude-scaled) | SP 1.30 Hz ζ 0.55; roll τ 0.116 s; DR 0.57 Hz ζ 0.31 | — | measured, derived | RESEARCH.md / Lie thesis |
| Sim now, 15 m/s | SP 1.495 Hz ζ 0.74; roll τ 0.051 s; DR 0.773 Hz ζ 0.29; spiral τ −29 s; stall 9.49 m/s; L/D 9.11; roll 145 °/s | — | measured on sim | today's run |
| Static thrust, max static rpm | 41.3 N at 11,149 rpm | N, rpm | derived | aircraft JSON |
| Idle | 2,800 rpm, 2.6 N | rpm, N | estimated | aircraft JSON |
| Engine lag τ | 0.25 | s | estimated | aircraft JSON |
| C_rr runway / mown / rough | 0.10 / 0.20 / 0.30 | — | estimated | `surface_friction.json` |
| Servo full throw | 0.14 | s | estimated | aircraft JSON |
| Throws a/e/r | 20 / 20 / 25 | deg | estimated | aircraft JSON |
| Gyro noise (25e, 70 % throttle) | ≈ 2 °/s; accel 0.5 m/s² | — | measured | [1] |
| MS4525DO 1 psi | ±0.25 % span = ±17 Pa | Pa | manual | [25] |
| EdgeTX SD log interval | 0.1–25.5 | s | manual | [26] |
| ArduPilot SystemID minimum log rate | 100 | Hz | manual | [23] |
| Giant scale: UIUC 35 % Extra 260 | 2.7 m, 17 kg, 12 kW, T/W > 2 | — | manual | [30] |

## Validation

### Verification with known answers (L0; CI)

- **Mirror symmetry (metamorphic).** Build a symmetrised airplane: inventory mirrored (Jxy = Jyz = 0), propeller torque and gyroscopic terms off, engine off. Then a left full-aileron roll must equal the right roll with v, p, r, φ, ψ negated, to 1e-12. *Mutation:* flip the sign of Cnδa_left only → must fail.
- **Froude-scaling invariance.** Data × (N, N³, N⁵; servo and engine times ×√N), dead stick, ρ unchanged. The trace at t·√N, V·√N must match the original (relative 1e-9). This tests the whole chain without any reference. *Mutation:* one hard-coded length (e.g. a strip offset in metres) → must fail. Ground contact is excluded: the spring rule ω·dt is not scale-free.
- **Energy.** Dead stick, no wind, no ground: E = ½mV² + mgh + ½ωᵀIω must not increase between ticks (> 1e-9 J), over random seeded attitudes (property test). The repair already proves passive aerodynamic power per element; this proves it end to end.
- **Replay tooling round trip.** Record a sim flight, add 2 °/s gyro noise and a 20 ms delay, replay it from the recorded inputs: TIC < 0.02 for p, q, r. *Mutation:* Clp ×1.5 in the replay model → TIC > 0.1.
- **Stale-output guard.** The dashboard's 15 m/s sim values must equal the `test_modes.gd` bands, or the release check fails.

### Independent validation (L1–L3): tolerance table

Adapted from 14 CFR Part 60 Appendix A, Table A2A [12] (airliner values; RC adaptation = estimated):

| Metric | Part 60 tolerance | RC band proposed | Reference source |
| --- | --- | --- | --- |
| Roll rate at given aileron | ±2 °/s or ±10 % (2.d.2) | ±10 % | Video (X-VAL-8), logger |
| Short period | ±1.5° pitch or ±2 °/s q, ±0.1 g (2.c.10) | ±15 % frequency, TIC < 0.25 | Logger + ID |
| Phugoid | ±10 % period; ±0.02 ζ (2.c.9) | ±10 % period | Baro/GPS log, side video |
| Dutch roll | ±0.5 s or ±10 % period; ±0.02 ζ (2.d.7) | ±10 % period | Logger |
| Spiral | correct trend, ±2° or ±10 % of φ in 20 s (2.d.4) | correct sign, ±5° in 20 s | Hands-off video or log |
| Steady sideslip | ±2° φ, ±1° β, ±2° aileron (2.d.8) | ±2° β, ±3° φ | Yaw string + onboard camera |
| Stall speed | ±3 kt (2.c.8) | ±0.5 m/s or ±6 % | Pitot or reciprocal GPS |
| Longitudinal trim | ±1° elevator (2.c.5) | ±1° elevator at 2 speeds | Post-flight trim measurement |
| Takeoff ground roll | ±1.5 s or ±5 % time; ±61 m or ±5 % distance (1.b.1) | ±10 % distance (grass) | Cones + side video |
| Transport delay | ≤ 300 ms (Level A/B); 100 ms (C/D) (6.a.1) | see doc 06 | Latency rig |
| Time histories | — | TIC < 0.25 per channel [1][2] | Replay |

### Flight-test cards (one card = one metric; all at a club field, wind < 3 m/s, ≥ 3 repeats, reciprocal headings)

| Card | Entry and input | Data | Metric → sim counterpart |
| --- | --- | --- | --- |
| T1 Trim | Level, hands-off at 3 throttle settings; land without touching trims | Elevator angle (throw meter) after landing; speed from passes | Trim elevator vs V → Cm0/CG check (trim solver) |
| T2 Stall | ≥ 60 m, idle, wings level, slow down ≤ 0.5 m/s² to the break; then 30° bank | Pitot or GPS; video of the wing drop | V_s, CL_max, drop direction → slow-flight maneuver (9.49 m/s) |
| T3 Roll | Full aileron, 2–3 rolls at 15 and 20 m/s, feet still and coordinated | 240 fps video from behind; gyro | °/s → 144/192 coordinated; τ from gyro |
| T4 Sideslip | Full rudder, opposite aileron to hold heading, wings near level | Yaw string on a boom in onboard video; φ from ATT | β, φ, aileron → β 14° (linear) |
| T5 Glide | Idle, trimmed 15 m/s, 15 s steady | Baro rate, airspeed, rpm (sound) | L/D at idle → sim at the same idle rpm |
| T6 Climb | Full throttle at best climb speed, 10 s | Baro rate | Climb rate → G1/G2 thrust |
| T7 Top speed | Level, full throttle, passes between cones 50–100 m apart | Side video timing, both directions | V_max → CD0, thrust |
| T8 Takeoff roll | From standstill on the mown strip, full throttle in 1 s | Cones every 5 m, side video, anemometer | Distance and time to lift-off → E3b |
| T9 Landing roll | Normal approach, idle, no brakes | Cones, video | Touchdown speed, roll-out → E3c |
| T10 Phugoid | Trimmed cruise; pull to lose 3 m/s, release; hands off 30 s | Baro/GPS altitude, side video | Period and damping → 9.7 s, ζ 0.26 |
| T11 Doublets | 0.5 s and 1 s doublets (e), 1 s (a, r), 3-2-1-1 Δt 0.15–0.2 s; ±4–5° | Logger ≥ 200 Hz | SP, DR, roll τ; TIC replay |
| T12 Spin | ≥ 100 m, idle, full up and full rudder at the stall; 2 turns; standard recovery | Video (turns/s), baro (sink) | Rotation rate, sink, turns to recover → `test_spin.gd` (≈ 1.2 turn/s, 11 m/s) |

### Mutation checks for the validation tooling

- Dashboard: Clp × 2 must turn the roll rows red, and Ixx × 2 must not change the stall row.
- TIC: replaying a time-shifted log (+100 ms) must raise TIC above 0.25 on rates.
- The equation-error estimator recovers synthetic Clp within 2σ, and its CR bound grows when β excitation is removed.

### Pilot-in-the-loop evaluation

- **Two scales per task.** The Gate 2 −2…+2 per axis gives *direction* ("sluggish/twitchy against a real Stik"), i.e. which parameter to move. Cooper–Harper HQR 1–10 [14] gives *acceptability under a defined task*: Cooper's method forces a defined task and its performance standards.
- **Tasks with standards measured from the trace (objective):**
  - Figure-eight at 30 m: desired ±5 m altitude, adequate ±10 m.
  - Axial roll: heading ±15° / ±30°.
  - Landing: touchdown in a 10 m box, wings level ±10°.
  - Stall recovery: altitude loss ≤ 10 m / 20 m.
  The sim scores them automatically: an advantage over a real field.
- **Blind A/B** of parameter sets (e.g. Ixx now vs measured). Randomised order, the same task, the pilot names the more Stik-like set. 10 trials: ≥ 9 for p < 0.05; 20 trials: ≥ 15 (binomial, derived). Add A/A trials (same set twice) to measure noise.
- **How many pilots:** n = 1 gives direction only; 5 pilots give a ±1 CI at SD 0.8 (assumed); 8 give ±0.67. At least two sessions on different days for test–retest. Record the radio, rates, expo, screen and latency (doc 06).
- **Transfer of training** stays out of scope for validation (see RESEARCH.md § 5). Nearest evidence: fixed-base vs motion-base hover training on a Robinson R44 showed no group difference, and the fixed base was judged more cost-effective (Fabbroni et al. 2018 [31]). A desktop RC sim may train without motion, but RC transfer is unverified.

## Pitfalls and risks

1. **Stale validation numbers:** D11a repaired this snapshot's D8b/D10 output. Physics or data changes can stale generated results again; regenerate from source, compare the 15 m/s baseline with `test_modes`, and retain the no-refused-rows check. Never hand-edit generated results.
2. **Mismatched condition** (mass, CG, throws, prop, rpm, speed) → every reference carries its conditions; the sim is flown in the same configuration, logger mass included.
3. **Circular tuning** (fitting to a reference, then "validating" on it) → `used_for_tuning` flag; held-out maneuvers.
4. **Wind and turbulence** bias glide, stall and top speed → wind < 3 m/s, reciprocal headings, averages, anemometer at 2 m.
5. **Pitot inaccuracy at 9 m/s** (±16 % worst case) → zero on the ground, calibrate against GPS reciprocal runs, report the uncertainty.
6. **Apparent mass in swing tests** (+23 % on Ixx) → report rigid and apparent values; decide which the sim uses (Decision 3).
7. **Swing-rig systematics** (tare, sway, amplitude) → validate the rig on a plank or bar of computable inertia to within 3 % before measuring the airplane; amplitude < 5°; 20 periods.
8. **Glow vibration aliasing the IMU** → soft-mount the FC, log ≥ 400 Hz raw (batch sampler), low-pass before decimating, check clipping.
9. **An FC in the control path is a new failure mode** → passive logger on an SBUS split; the receiver drives the servos.
10. **Video perspective and lens errors** → camera perpendicular to the flight line, baseline cones in the flight plane, whole-roll counting, Tracker's perspective filter.
11. **Open-loop replay diverges** (neutral or unstable phugoid and spiral) → 2–10 s windows reset to logged states; compare rates, not positions.
12. **Froude/US120 misuse** (relative density 0.62×) → compare nondimensional values; prefer the Reynolds-matched 25e.
13. **Pilot rating bias** (expectation, order, learning) → blinding, randomisation, A/A trials, task standards.
14. **Unlicensed datasets** (UMN logs have no stated licence) → keep them out of git; store a download script with checksums.
15. **Safety at stall and spin cards** → club rules, ≥ 2 mistakes high (≥ 60 m stall, ≥ 100 m spin), spotter, throttle-cut failsafe, national rules (EU 2019/947 operator registration and club authorisation; not verified in this pass).

## Proposed roadmap steps

| ID | Step | Proof | Depends on | Feeds |
| --- | --- | --- | --- | --- |
| X-VAL-1 | **Complete via D11a:** repaired D10 perturbations (CG, Cnβ, mass) and regenerated `results.md` | No refused rows; 15 m/s baseline equals the `test_modes` bands | — | D8b, D10 |
| X-VAL-2 | **Complete via D11a for the current reference comparison:** 25e flight-ID modes compared like-for-like with the Stik at equal CL | Generated table with current SP, roll and DR ratios; see `results.md` | X-VAL-1 | D8b |
| X-VAL-3 | `openrc-reference v1` file plus generated `research/validation/dashboard.md` (sim, ref, ratio, band, status, source, kind, used_for_tuning) | Dashboard lists US120 and 25e rows; Clp × 2 turns roll rows red | X-VAL-2 | Gate 2, releases |
| X-VAL-4 | Metamorphic tests: mirror symmetry, Froude invariance, energy non-increase | Pass at 1e-12 / 1e-9; the named mutations fail | — | Rule 6 (verification) |
| X-VAL-5 | Owner ground kit 1: weigh, three-scale CG (+ tilt), throws at 5 stick positions, post-flight trim, servo speed at 240 fps, tyre tow test on 3 surfaces | Measurements JSON + photos in `research/validation/X-VAL-5/`; kind "measured" | — | D10, E3b, Gate 2 |
| X-VAL-6 | Swing tests: bifilar Ixx and Izz, compound Iyy; rig validated on a known plank; apparent-mass estimate | Plank within 3 % of theory; Stik I ± % with error budget | X-VAL-5 (mass, CG) | D10, D8b roll gap |
| X-VAL-7 | Static thrust (luggage scale or load cell) + rpm (tach or audio FFT) + throttle-step lag | T and rpm vs 41.3 N / 11,149 rpm; τ vs 0.25 s | — | G1, G2, E3b |
| X-VAL-8 | Tripod-video session: cards T3, T7, T8, T9, T12 (+ T2 behaviour) | Frame-count CSVs + Tracker/Kinovea exports; dashboard rows | X-VAL-5 | D8b videos, E3b/E3c, Gate 2 |
| X-VAL-9 | Log tooling: `.bin`/`.h5` → `openrc-flightlog v1` CSV (Python, outside `app/`) + replay harness with TIC | Synthetic round trip TIC < 0.02; Clp × 1.5 gives > 0.1 | X-VAL-3 | D8b |
| X-VAL-10 | Replay UMN Thor 44/45 doublets through the X-VAL-2 model | TIC p, q, r table vs Dorobantu's 0.07/0.12/0.26 | X-VAL-2, X-VAL-9 | D8b |
| X-VAL-11 | Passive logger flights (SBUS split, pitot, FC ≥ 200 Hz): cards T1, T2, T4, T5, T6, T10, T11 | Logs + dashboard rows with uncertainties | X-VAL-6, X-VAL-9 | Gate 2-R, D10 |
| X-VAL-12 | Equation-error ID of Clp, Clδa, Cmq, Cmδe, Cnβ, Cnr with CR bounds; held-out validation | Estimates ± 2σ; held-out TIC < 0.25 | X-VAL-6, X-VAL-11 | D10, data kind |
| X-VAL-13 | Monte-Carlo envelope: unknowns sampled by kind/uncertainty, 200 seeded runs, 5–95 % bands per metric | Band table; each reference marked inside or outside | X-VAL-3, Decision 2 | D10, Gate 2 |
| X-VAL-14 | Pilot protocol: tasks with desired/adequate standards scored from traces, HQR + −2…+2, blind A/B | Protocol + one owner session + A/B binomial p | X-VAL-3 | Gate 2, Gate 2-R |
| X-VAL-15 | Per-aircraft contrast via the same dashboard (Extra: kit throws/CG, public roll-rate videos; P-51: AN data) | Dashboard rows per aircraft, labelled | X-VAL-3 | EX-09, P51-09 |

## Decisions to take now

1. **Reference-data schema.** Add `openrc-reference v1`: metric, value, unit, kind, source, uncertainty, conditions (mass, CG, V, throttle, surface, wind), used_for_tuning. *Recommended:* yes, before X-VAL-3. It mirrors the aircraft data rules.
2. **Uncertainty field in aircraft data.** Add an optional `uncertainty` ({σ} or {min, max}) to `{value, unit, kind, source}`; the loader validates it. Without it Monte-Carlo invents ranges. Consider a kind **"identified"** for flight-estimated values with their CR bounds. *Recommended:* add both while the schema is v1.
3. **Rigid vs apparent inertia.** Keep the data's inertia rigid-body and add a separate derived `apparent_inertia` term later (an added-mass model), rather than folding 23 % into Ixx silently. *Recommended:* decide before X-VAL-6 reports numbers.
4. **Passive-logger architecture.** The FC never commands surfaces during validation flights. *Recommended:* yes (safety, and the test does not change the airplane).
5. **Flight-log format aligned with `openrc-trace v3`.** Same column names and units where they overlap (p_radps, alt_m, speed_mps …), so one comparison tool serves both. *Recommended:* define `openrc-flightlog v1` in X-VAL-9.
6. **Validation is reported, not gating.** CI fails on verification (L0) and on stale dashboards. Misses against references are shown red in the release dashboard, not as build failures. *Recommended:* yes; otherwise every new reference breaks CI.
7. **Gate 2 sheet.** Replace the free-text pilot template with tasks, standards and both scales (X-VAL-14). This is an owner decision on the time per session (~45 min estimated).

## Sources

1. A. Dorobantu, A. Murch, B. Mettler, G. Balas, "System Identification for Small, Low-Cost, Fixed-Wing Unmanned Aircraft", J. Aircraft (doi:10.2514/1.C032065), preprint 2012, https://dept.aem.umn.edu/~mettler/Courses/AEM%205333%20(spring%202013)/AEM5333%20CourseDropbox/Week%207%20Identification/Ultrastick%20Identification/2012_AIAA_JA_SYSID.pdf — fetched (text extracted).
2. A. Dorobantu, P. Seiler, G. Balas, "Validating Uncertain Aircraft Simulation Models Using Flight Test Data", AIAA AFM 2013, https://dept.aem.umn.edu/~SeilerControl/Papers/2013/DorobantuEtAl_13AFM_ValidatingUncertainAircraftSimulationModels.pdf — fetched.
3. UMN UAV Laboratories, "Flight Data" collection (hdl 11299/163580), https://conservancy.umn.edu/collections/03a03027-857c-4a30-9e21-cd1df50211c4 — metadata fetched via the DSpace API (HTML is 403 to bots).
4. B. Taylor, "Thor Flight 44" dataset, 2012, https://hdl.handle.net/11299/174325 — API fetched; flight report PDF read (.h5 19.6 MB, .mat 2.2 MB).
5. R. Venkataraman, "Baldr Flight 13" (Ultra Stick 120 stall and spin), 2016, https://hdl.handle.net/11299/198142 — API metadata fetched.
6. A. Dorobantu, "Test platforms for model-based flight research", PhD thesis, UMN 2013, https://hdl.handle.net/11299/159691 — API metadata fetched.
7. UASLab, OpenFlightAnalysis (MIT), https://github.com/UASLab/OpenFlightAnalysis — fetched (file tree via the GitHub API).
8. UASLab, OpenFlightSim UltraStick25e MassOpenFlight.xml @b020511, https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/MassOpenFlight.xml — fetched (raw).
9. M. Jardin, E. Mueller, "Optimized Measurements of UAV Mass Moment of Inertia with a Bifilar Pendulum", AIAA 2007-6822 / J. Aircraft 46(3) 2009; Simulink model https://mathworks.com/matlabcentral/fileexchange/15854-measuring-mass-moment-of-inertia-with-a-bifilar-pendulum — File Exchange page fetched; paper search result only.
10. H. Soulé, M. Miller, "The experimental determination of the moments of inertia of airplanes", NACA TR-467, 1934, https://ntrs.nasa.gov/citations/19930091541 — fetched (abstract). NACA TN 1629 (Gracey, 1948) is referenced there, not opened.
11. (internal) RESEARCH.md plan review #3: US120 Ibis from Lie's thesis (UMN), NASA 6-DoF check cases, XFLR5 mode measurements, Simmons 2023, Macchiarella et al., Cardullo et al.
12. FAA, 14 CFR Part 60 (searchable version), Appendix A Table A2A, https://www.faa.gov/sites/faa.gov/files/about/initiatives/nsp/14CFR60_Searchable_Version.pdf — fetched (text extracted).
13. 14 CFR 25.103 Stall speed, https://www.law.cornell.edu/cfr/text/14/25.103 — fetched.
14. G. Cooper, R. Harper, "The use of pilot rating in the evaluation of aircraft handling qualities", NASA TN D-5153, 1969, https://ntrs.nasa.gov/api/citations/19690013177/downloads/19690013177.pdf — search result only.
15. C. Wolowicz, J. Brown, W. Gilbert, "Similitude requirements and scaling relationships as applied to model testing", NASA TP-1435, 1979, https://ntrs.nasa.gov/citations/19790022005 — search result only.
16. E. Morelli, "Practical Multiple-Input Design for Aircraft System Identification Flight Tests", AIAA Aviation 2021, https://ntrs.nasa.gov/api/citations/20210018281/downloads/Morelli_Practical_FTI_Aviation_2021_v1.pdf — fetched.
17. NASA, SIDPAC (LAR-16100-1), https://software.nasa.gov/software/LAR-16100-1 — search result only.
18. E. Morelli, V. Klein, *Aircraft System Identification: Theory and Practice*, 2nd ed., https://www.mathworks.com/academia/books/aircraft-system-identification-morelli.html — search result only.
19. SJSU Research Foundation, CIFER®, https://sjsu.edu/researchfoundation/resources/flight-control/cifer.php — search result only.
20. W. Lacerda Jr. et al., SysIdentPy (BSD-3), https://github.com/wilsonrljr/sysidentpy — search result only.
21. D. Dutra, "Collocation-Based Output-Error Method for Aircraft System Identification", 2019, https://arxiv.org/abs/1909.02838 — fetched (abstract).
22. ArduPilot, Plane onboard log messages, https://ardupilot.org/plane/docs/logmessages.html — fetched.
23. ArduPilot, System ID mode operation, https://ardupilot.org/plane/docs/common-systemid-mode-operation.html — fetched.
24. ArduPilot, pymavlink, https://github.com/ArduPilot/pymavlink — fetched.
25. Matek ASPD-4525 (MS4525DO) product pages, e.g. https://www.nextfpv.com/products/matek-digital-airspeed-sensor-aspd-4525 ; F405-WING V2 https://www.fpvfaster.com.au/products/matek-f405-wing-v2-flight-controller-glider-fixed-wing-30-5x30-5mm ; H743-WING V3 https://www.racedayquads.com/products/matek-h743-wing-v3-flight-controller — search results only (prices vary).
26. EdgeTX manual v2.11, Special Functions (SD Logs), https://manual.edgetx.org/v2.11/color-radios/model-settings/special-functions — fetched.
27. Kinovea, https://github.com/Kinovea/Kinovea — fetched.
28. Open Source Physics, Tracker, https://opensourcephysics.github.io/tracker-website/ — fetched.
29. HypothesisWorks, Hypothesis, https://github.com/HypothesisWorks/hypothesis — fetched (licence file not displayed).
30. O. Dantsker, R. Johnson, M. Selig, T. Bretl, "Development of the UIUC Aero Testbed", AIAA 2013-2807, https://m-selig.web.engr.illinois.edu/pubs/DantskerJohnsonSeligBretl-2013-AIAA-2013-2807-AeroTestbed.pdf — search result only.
31. Fabbroni et al., "Transfer-of-training: from fixed- and motion-base simulators to a light-weight helicopter", AHS Forum 2018, https://pure.korea.ac.kr/en/publications/transfer-of-training-from-fixed-and-motion-base-simulators-to-a-l/ — fetched (abstract).
