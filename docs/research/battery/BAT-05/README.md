# BAT-05 — Cell fits and generated battery data

2026-10-19 · **Status:** dated evidence for BAT-05 (cell fitting and pack generation) and the BAT-03 Python reference. Plan: [battery realism](../../../plans/battery-realism.md). Formats and law: [BAT-04 specification](../BAT-04/specification.md). Tools: [research/battery](../../../../research/battery/README.md).

**Evidence level:** evidence constrained, experimental. Both templates come from free measured data (tier A), but no simulated pack has been measured. The LiPo class packs use estimated class magnitudes. Nothing here physically validates a pack that the simulator flies.

Every number below comes from [`fit_results.json`](../../../../research/battery/bat-05/fit_results.json) (sha256 `9d727b3e…c212`) or from the generated files.

## Data

| Dataset | Licence | Used files (sha256 in `fit_results.json` and the local `fetched.json`) |
| --- | --- | --- |
| Galeotti et al. 2023, BAK LP-503562 3.7 V 1.1 Ah LiPo pouch, 25 °C Peltier. Mendeley doi:10.17632/stcppt2r68.1; article Data in Brief 50:109561 | CC BY 4.0 | Five cells, cycle 0: 1 A partial-discharge ladder `1_0_*`, 1 A standard discharge `0_0_1`, 3 A stress discharges `2_0`/`2_1`. Cell a18937dc (the template cell) also has cycles 45/90/270/540 (109 files). |
| Kollmeyer et al., LG INR18650HG2 3 Ah NMC, one cell, chamber 0/10/25/40 °C (tests 585/575/549/555). Mendeley doi:10.17632/b5mj79w5w9.2 | CC BY 4.0 | `HPPC`, `C20DisCh`, `Dis_0p5C`, `Dis_2C` per temperature, plus `551/552_Cap_1C` for the repeatability margin (18 files). |

Datasheets used for limits and masses: BAK/Dubilier LP-503562-1S-3 specification (2012) and LG Chem PS-HG2 Rev 5 (2017). The source sentence of each quantity in the generated files names them.

Data facts that shape the method:
- The Galeotti files record only loaded samples, starting 0.43 s after current onset. The 300 s rest plus EIS between ladder pulses is not recorded.
- In all five LiPo cells, the 1 A standard discharge starts 17–33 mV below the first 1 A ladder pulse. Both start from full charge at the same current. Over SOC ≥ 0.2 it stays below the ladder by a median of 10–22 mV at equal extracted charge. No state-free model reproduces both. This is probably an undocumented protocol difference.
- The HG2 cell lost capacity during the campaign. The C/20 capacity was 2.781 Ah at 25 °C, then 2.690 Ah at 40 °C, 2.649 Ah at 10 °C and 2.599 Ah at 0 °C, in test order. The 40 °C value is lower than 25 °C, so temperature alone cannot explain the trend. The two 1C checks at 25 °C, two days apart, gave 2.726 and 2.693 Ah.
- Every HG2 discharge ends at 2.8 V. The LG specification end voltage is 2.0 V, so the dataset never reaches it.

## Method

**Common.**
- Model: the BAT-04 §4 cell law, `V = OCV(z,T) − R0·I − Σ v_k`, with 0, 1 or 2 RC branches.
- Grid: 27 SOC knots and the temperature knots 273.15/283.15/298.15/313.15 K.
- Time constants are bounded to [1, 5000] s. Faster dynamics are lumped into R0. This matches the 1 s LiPo sampling and the plan §9 stiffness guard (τ ≥ 0.83 s at 240 Hz).
- **Selection rule:**
  - Score = the mean over held-out runs of the loaded-voltage RMSE at SOC ≥ 0.2 (the plan §10 acceptance band).
  - Choose the least complex candidate whose score is within the repeatability margin of the best eligible score.
  - The margin is the RMS difference between two repeated discharges of the same cell in the same band.
  - Complexity order: K0 < K1 < K2, then constant R < SOC-dependent RC resistances < SOC-dependent R0 and RC resistances.
  - A candidate with a time constant on its bound is reported but not eligible.
  - Full-range errors are reported alongside the score.

**LiPo (BAK, 25 °C).**
- Reference capacity: 1.02504 Ah, the charge of the 1 A standard discharge of cell a18937dc down to 2.75 V. SOC 0 is that floor.
- Fit set: the cycle 0 pulse ladder (ordered by starting voltage, 300 s rests simulated as RC decay) and the 3 A stress discharge `2_0`. These two rates separate R0 from the RC branch.
- Held-out set: the 1 A standard discharge and stress cycle `2_1` of the same cell, and every fresh run of the other four cells. Each held-out cell uses its own 1 A capacity; resistance scales ∝ 1/Q per §2.
- OCV: monotone knots with a weak second-difference penalty. Samples below SOC 0 are excluded.
- Margin: 3.9 mV (`2_0` against `2_1`).

**HG2.**
- **OCV(z,T):** the C/20 discharge at each temperature, with SOC normalised by that test's own C/20 capacity. Corrected by `+I·(R0+ΣR_k)` from the HPPC fit (at most 12–20 mV), then made monotone by isotonic regression.
- **R0:** at each HPPC SOC level, the median of the current-onset and current-interruption voltage steps (0.1 s sampling) of the full-length 1C–6C discharge pulses.
- **RC branches, one window per SOC level:** the window covers the 0.9 A SOC step, the 1 h rest and the pulse block, simulated on a 0.1 s grid.
  - Free parameters: an OCV offset and R_k, τ_k, with R0 fixed.
  - τ_k is then fixed at the per-temperature median over the levels with SOC ≥ 0.1, and R_k is refitted.
- **Template rows:** the resistances are shifted from the measured mean cell temperature to the knot temperature with the fitted activation energy (measured means 272.8, 282.4, 297.1 and 311.7 K, so shifts of at most 1.4 K).
- **Held out:** `Dis_0p5C` and `Dis_2C` at all four temperatures, replayed with the measured cell temperature.
  - The score normalises each test by its own C/20 capacity, which removes the campaign fade.
  - Errors with the single 25 °C template capacity are reported too.
- Margin: 3.3 mV (`551` against `552`).

**Arrhenius.**
- Pooled fit `ln R = a_z + Ea/(R_g·T)` with a separate intercept per SOC, at z = 0.2…0.9 on each temperature's level table.
- T is the measured mean cell temperature during the HPPC, not the chamber set point.

**Thermal.**
- Fit `C_th·dT/dt = Q − hA·(T − T_amb)` jointly to the four `Dis_2C` runs.
  - Q comes from the fitted model: `I²R0 + Σ v_k²/R_k`. Entropic heat is omitted.
  - T_amb is the rest temperature before each discharge, or the first sample at 25 °C.
- The cell mass is 48.0 g (LG Rev 5 maximum).
- `Dis_0p5C` runs are held out.

**Aging (LiPo cell a18937dc).**
- Capacity: the 1 A standard discharge and the ladder total.
- Apparent resistance: `(OCV_cycle0(z) − V(0.43 s))/I` at pulse starts with SOC between 0.15 and 0.95.
- Rest recovery: the voltage rise across each unrecorded rest.

## Results

### Chosen structures

| LiPo candidate | Parameters | Fit RMSE (mV) | Held-out score (mV) | Same-cell score (mV) |
| --- | --- | --- | --- | --- |
| K0, constant R | 28 | 14.8 | 30.9 | 25.2 |
| K0, R(z) | 33 | 11.6 | 28.7 | 20.1 |
| **K1, constant R (chosen)** | 30 | 9.0 | **25.6** | 18.4 |
| K1, R0 constant, RC(z) | 35 | 4.5 | 24.0 | 14.7 |
| K1, R(z) | 40 | 3.5 | 23.3 | 13.6 |
| K2, constant R (τ2 at bound, not eligible) | 32 | 6.3 | 23.6 | 12.9 |
| K2, R0 constant, RC(z) | 42 | 2.6 | 22.6 | 12.4 |
| K2, R(z) | 47 | 2.5 | 22.4 (best) | 12.1 |

The threshold is 22.4 + 3.9 = 26.3 mV, so the rule selects **K = 1 with SOC-independent resistances**.

| HG2 candidate | Window fit RMSE (mV) | Held-out score (mV) | Time-weighted sensitivity (mV) |
| --- | --- | --- | --- |
| K0 | 28.9 | 96.3 | — |
| K1 | 18.8 | 63.5 | 33.0 |
| **K2 (chosen)** | 13.6 | **28.6** | 43.6 |

The rule selects **K = 2**. Sensitivity: weighting window residuals by sample duration, instead of per sample, reverses the K1/K2 order (33.0 against 43.6 mV), and both stay above the unweighted K2 result. The branch split is therefore only moderately identified from HPPC, while the K2 total resistance predicts the held-out discharges best.

### Held-out errors of the chosen templates

Values are in mV. The score is the RMSE at SOC ≥ 0.2; the remaining columns cover all samples down to the 2.75 V / 2.8 V floor.

| Run (LiPo, K1) | Score | RMSE | Max | Bias |
| --- | --- | --- | --- | --- |
| a18937dc 1 A standard (same cell) | 22.6 | 34.8 | 253 | +25.9 |
| a18937dc 3 A stress cycle 1 (same cell) | 14.2 | 16.1 | 88 | −3.0 |
| Other cells, pulse ladders | 7.1–26.9 | 15.1–44.8 | 306 | +6.9…+33.5 |
| Other cells, 1 A standard | 19.2–41.3 | 31.8–50.4 | 260 | +21.7…+44.9 |
| Other cells, 3 A stress | 12.3–66.0 | 17.7–80.4 | 321 | −0.1…+61.7 |

Notes on the LiPo held-out errors:
- The 1 A standard-discharge bias is the protocol offset described under Data.
- Cell 8779fdf1 is the outlier. Its 3 A capacity is 0.82 Ah, against 0.93–1.00 Ah for the other cells.
- The large maxima occur at the knee near SOC 0.

| Run (HG2, K2) | Score (session capacity) | RMSE | Max | Bias | Score (25 °C template capacity) |
| --- | --- | --- | --- | --- | --- |
| 25 °C 0.5C | 10.3 | 18.4 | 52 | −0.8 | 10.3 |
| 25 °C 2C | 19.8 | 59.5 | 183 | −19.4 | 19.8 |
| 40 °C 0.5C | 6.3 | 18.1 | 50 | −7.8 | 13.3 |
| 40 °C 2C | 15.0 | 54.3 | 155 | −22.8 | 22.2 |
| 10 °C 0.5C | 27.2 | 32.8 | 140 | +27.0 | 46.5 |
| 10 °C 2C | 43.9 | 59.4 | 169 | −1.4 | 64.5 |
| 0 °C 0.5C | 47.3 | 52.0 | 148 | +48.8 | 76.0 |
| 0 °C 2C | 58.6 | 60.6 | 110 | +19.1 | 93.1 |

At 0 and 10 °C the model under-predicts the sag of continuous discharges (positive bias), even though R(T) is identified at those temperatures. The HPPC-identified branches (τ ≤ 52 s) do not carry the slow, current-dependent diffusion polarisation of a long low-temperature discharge.

**Reference cross-check.** Each chosen template, replayed through the independent law `ecm_reference.py` (RK4, 1 s ticks, prescribed cell temperature), agrees with the fitting simulator:
- within 0.23 mV (LiPo, 1 A) and 0.30 mV (LiPo, 3 A)
- within 0.04–0.66 mV (HG2), on all held-out runs up to exhaustion

The located exhaustion of the LiPo 1 A replay is at 3690.427 s, the last data sample, as the SOC 0 definition requires.

### Parameters (template values at SOC 0.5)

| Template | T (K) | OCV (V) | R0 (mΩ) | R1 (mΩ), τ1 (s) | R2 (mΩ), τ2 (s) |
| --- | --- | --- | --- | --- | --- |
| LiPo `lipo-bak503562-galeotti-v1` | 298.15 (fitted) | 3.7922 | 115.2 | 58.0, 36.6 | — |
| LiPo, borrowed rows | 273.15 / 283.15 / 313.15 | 3.7922 | 203.0 / 159.9 / 85.7 | 105.5 / 82.0 / 42.4, 36.6 | — |
| HG2 `liion-lg-hg2-kollmeyer-v1` | 273.15 | 3.7493 | 33.7 | 8.08, 1.58 | 34.2, 51.4 |
| | 283.15 | 3.7521 | 25.1 | 5.69, 2.44 | 26.5, 52.4 |
| | 298.15 | 3.7276 | 17.3 | 4.04, 2.13 | 17.8, 43.4 |
| | 313.15 | 3.7468 | 14.4 | 4.16, 1.59 | 12.2, 35.9 |

Uncertainty of the LiPo values:
- **Spread across the five cells** (same K1 structure, each cell's own fit set; mean ± sample SD):
  - R0 = 114.3 ± 7.8 mΩ (107.5–126.6)
  - R1 = 64.5 ± 5.0 mΩ
  - τ1 = 36.1 ± 3.1 s
  - OCV(0.5) = 3.787 ± 0.009 V
- **Rest-length sensitivity:** with 450 s rests instead of 300 s, the template cell's values change by less than 0.03 %.
- **Cross-checks:**
  - The model-free two-rate resistance (1 A against 3 A, steady part) is 153–170 mΩ. R0 + R1 = 173 mΩ.
  - The datasheet gives 95 mΩ typical AC impedance at 1 kHz, including a protection board of 50 mΩ typical.

HG2 identifiability, from per-level free fits, interquartile range at 25 °C:
- τ1: 1.7–2.3 s
- τ2: 39–62 s

At 0 °C, τ1 spans 1.0–2.0 s and τ2 41–77 s. R0 at SOC 0.2–0.9 is 17.6–18.2 mΩ at 25 °C, inside the LG limit of ≤ 20 mΩ at 1 kHz.

### Arrhenius activation energies (HG2)

| Resistance | Ea (J/mol) | Standard error | R² within SOC | Per-SOC range |
| --- | --- | --- | --- | --- |
| R0 | 15 333 | 451 | 0.980 | 14 841–15 588 |
| R1 (τ ≈ 2 s) | 14 813 | 1 261 | 0.857 | 12 064–19 840 |
| R2 (τ ≈ 45 s) | 16 197 | 500 | 0.979 | 13 279–18 428 |

The LiPo template borrows R0 → Ea(R0) and its single branch (τ = 36.6 s) → Ea(R2), the HG2 branch with the nearest time constant.

### Thermal

The thermal parameters are **not identifiable for the cell.**
- The joint fit gives C_th = 256 J/K (relative SE 4 %) and hA = 0.394 W/K, with correlation −0.85.
- That is an apparent c_p of 5335 J/(kg·K), five times the published whole-cell range of 800–1400 J/(kg·K).
- The per-run C_th ranges from 217 to 345 J/K.
- The thermocouple, the soldered 10 AWG leads and the chamber dominate the response.
- The fixture model still predicts the held-out 0.5C temperature to 0.13–0.21 K RMSE.

The templates therefore use `estimated` medians from Steinhardt et al. 2022 (J. Power Sources 522:230829): 912 J/(kg·K) for cylindrical cells (HG2) and 1168 J/(kg·K) for pouch cells (LiPo). Maleki et al. 1999 measured 960–1040 J/(kg·K) on an 18650.

### Aging trend (LiPo cell a18937dc, evidence for a later health model)

| Cycle | 1 A capacity (Ah) | Ladder charge (Ah) | Apparent R (mΩ) | Rest recovery (mV) |
| --- | --- | --- | --- | --- |
| 0 | 1.025 | 1.040 | 112.7 | 61 |
| 45 | — | 1.028 | 104.2 | 59 |
| 90 | — | 1.023 | 102.7 | 59 |
| 270 | 0.976 | 0.991 | 102.2 | 64 |
| 540 | 0.646 | 0.651 | 144.0 | 137 |

Capacity fades slowly to cycle 270, then falls 34 % by cycle 540. The apparent resistance and the polarisation recovery rise sharply only in the last interval. The apparent R assumes the cycle 0 OCV(z), so treat it as a trend, not a value. The templates do not use these data.

## Reference law checks (BAT-03 part)

`research/battery/ecm_reference.py` implements BAT-04 §2/§4/§5/§6 from the text, independently of `app/physics/battery/`. Its 19 tests pass:
- the 1-RC step response, to within 1e-10 relative
- the motor closed form, including the one-quadrant clamp and duty limiting
- energy closure, pointwise at 200 random states (1e-12) and integrated over a 120 s motor run (1e-9)
- RK4 refinement ratios between 14 and 18 under halving
- exhaustion located to 1e-9 s, followed by I = 0 and V = E_oc
- weak-cell SOC and path resistance
- supervisor debounce, soft ramp reaching `soft_limit` at `soft_ramp_s`, hard cut with frozen timer, throttle reset, latched mode and mode off
- auto cell detection, including a 4S pack resting at 3.2 V/cell that is detected as 3S, so a 3.2 V/cell LVC does not trip until the pack falls to 9.6 V

Five deliberate mutations on disposable copies were all detected:
- RK4 weight
- dropping the (n−1) RC heat factor
- the soft-ramp formula
- the sign of the detection tolerance
- dropping the weak-cell resistance factor

## Generated files

`python3 -I research/battery/bat-05/build_batteries.py` writes these files. Pack values are at SOC 0.5 and 298.15 K, per parallel group.

| File | sha256 | S·P | Rated (Ah) | R0 (mΩ) | RC (mΩ) | R_w (mΩ) | Mass (kg) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cells/lipo-bak503562-galeotti-v1.json` | `d291e8222c4664b44179e04c60efa8a14f372bb211f51c78856d1c7420c86633` | | 1.02504 | | | | |
| `cells/liion-lg-hg2-kollmeyer-v1.json` | `1a65da8c45affeefa4e075b9cae01a0f45875d269c280042aa12af9fa627129c` | | 2.78074 | | | | |
| `packs/lipo-3s1p-2200-25c-class.json` | `5d972f35595220bcf201fc7429a174c04028802636e45e4d28ab140d5340ba23` | 3·1 | 2.2 | 7.27 | 3.66 | 2.0 | 0.170 |
| `packs/lipo-4s1p-2200-30c-class.json` | `81a549b020e795d1f60085560dc2630090795f16256fcf732469d524ac8ebf42` | 4·1 | 2.2 | 7.27 | 3.66 | 2.0 | 0.227 |
| `packs/lipo-4s1p-3200-30c-class.json` | `cdf90adb42613419665d7a6976c94a8b937abb4984c366610181026be9c20b09` | 4·1 | 3.2 | 5.00 | 2.52 | 2.0 | 0.330 |
| `packs/lipo-4s1p-5000-30c-class.json` | `78d3c4b0eba0af115a650840efd70c4f4afa7d54fb073cea2181e9550cbadd2e` | 4·1 | 5.0 | 3.20 | 1.61 | 2.0 | 0.516 |
| `packs/lipo-6s1p-2200-30c-class.json` | `b7d674e377282b9f4d4907f03b0453a466d98a6f61cdd09d5e85945c11adb495` | 6·1 | 2.2 | 7.27 | 3.66 | 2.0 | 0.340 |
| `packs/lipo-6s1p-5000-30c-class.json` | `c930ba3bf6283b03b4e2d99471b73e6994670ad2a6322d6ed46701b7acbd5cf9` | 6·1 | 5.0 | 3.20 | 1.61 | 2.0 | 0.773 |
| `packs/liion-4s1p-3000-hg2.json` | `5a2f33dd7843f3cf7e5b6133e10cebd331a0d8d2b45977fb0b5c5425b4077afe` | 4·1 | 2.78074 | 17.35 | 4.04 + 17.78 | 5.6 | 0.231 |
| `packs/liion-4s2p-6000-hg2.json` | `8e8f7ae2175f56299bcdb793873085d7e5bfa7ec5dbe5e2ed8b3220e90a606a4` | 4·2 | 5.56148 | 8.67 | 2.02 + 8.89 | 3.8 | 0.447 |

Pack rules. Each rule is stated again in the source sentence of the field it sets.
- **LiPo resistance:** `resistance_scale = 0.135464` sets the pack R0 at SOC 0.5 and 298.15 K to 5.0 mΩ·(3.2 Ah/Q) per cell. The anchor is `estimated` from Bauersfeld & Scaramuzza 2022 (4.5 mΩ/cell minimum), Di Nisio et al. 2023 (5.2 mΩ/cell) and the PX4 docs (5 mΩ/cell). The RC branch scales by the same factor. The C label is never used.
- **LiPo mass:** the Timber anchor is 0.33 kg exactly (EFL105250B manual: 2190 − 1860 g). The other classes scale ∝ series·capacity.
- **LiPo box:** the Timber box is [0.14, 0.043, 0.032] m. Length and width scale by (Q/3.2)^(1/3); height scales by (S/4)·(Q/3.2)^(1/3).
- **HG2 packs:**
  - Cells are 48.0 g (LG Rev 5 maximum), plus 6 g per cell and 15 g per pack of assembly allowance.
  - Interconnects: (S−1)·1.2 mΩ/P for the nickel strip, plus 2 mΩ for leads and connector.
  - The rated capacity is P × 2.781 Ah measured, against 3.0 Ah nominal, so `resistance_scale = 1` reproduces the real cell.
- **Heat transfer:**
  - Still air: 5 W/(m²·K)·A (Incropera Table 1.1 free-convection range 2–25).
  - Forced: A·0.664·k·Pr^(1/3)/√(ν·L) (laminar flat plate, eq. 7.30; air at 300 K). It excludes the installation airflow fraction, which the aircraft supplies.

The existing GDScript loader test (`app/tests/test_battery_data.gd`, owned by BAT-04/09) loads every shipped pack with its pinned template: 39 checks, 0 failures on the pack checks. Its one failure, "pack aircraft file parses", concerns the Timber `pack_ecm` aircraft variant, which does not exist yet and is not part of BAT-05.

## Limits and caveats

- **The LiPo shape comes from a small consumer cell.** The 1.1 Ah BAK pouch, at 1–3 A (≤ 3C), is transferred to RC packs used at 10–30C. The class anchor fixes the magnitude only. The R0/R1 ratio and τ come from the small cell, whose measured resistance probably includes a protection board (datasheet 35–60 mΩ). No current-dependence (Butler–Volmer) is modelled: at the first 3 A sample the template over-predicts the drop by 39 mV, against 1 mV on the first 1 A pulse.
- **LiPo temperature dependence is borrowed.** LiPo data exist only at 25 °C. The rows at 0/10/40 °C borrow the HG2 activation energies. OCV and τ are copied unchanged.
- **The data floor sits above usual LVC settings.** For the LiPo template, SOC 0 under 1 A is reached at 3.00 V loaded, with a rested OCV of 3.18 V, because the template cell's ladder runs above its 1 A discharge. The pack therefore disconnects through the exhaustion event before an ESC cutoff below about 3.0–3.1 V/cell can act. The HG2 floor is 2.8 V.
- **HG2 capacity is temperature-independent by construction (plan principle 3).** The OCV rows are tabulated on each session's own normalised SOC. A runtime pack at 0 °C therefore gets the 25 °C capacity, and cold capacity loss emerges only through resistance and cutoff. In this dataset, campaign fade and temperature cannot be separated.
- **HG2 OCV rows differ by up to about 25 mV between temperatures at mid SOC.** Part of this is the per-test SOC normalisation, not entropy.
- **Low-temperature continuous discharges are under-predicted in sag** by up to 50–60 mV RMSE at 0 °C.
- **Class anchors are estimates:** resistance, mass, box, wiring, h_nat and the assembly allowances are all `estimated`.
- **No pack is validated.** Owner bench data (BAT-27) and flight telemetry (BAT-28) are required for that.

## Spec issues found (reported, not changed)

1. **HG2 `v_cutoff`.** BAT-04 §1 defines SOC 0 as "discharge to `v_cutoff` at the reference rate" (the data floor). The HG2 data stop at 2.8 V, so the template uses 2.8 V (`derived`), not the requested datasheet 2.5 V. The current LG specification gives 2.0 V; Rev 0 gave 2.5 V. The 2.0 V value is used as `v_damage_floor`. §1 makes `v_cutoff` both the data floor and the chemistry limit; a separate `data_floor_v` would remove the conflict.
2. **ESC supervisor sample order (§6).** The reference applies the debounce test in the same sample as the 0 → 1 transition, so a debounce of 0 cuts on the first low sample. It evaluates throttle-reset recovery before the phase 2 timer advances. The text implies both but does not state the order.
3. **"Not the connected left limit" (§4).** The reference reads this as a discrete exhausted flag, set at the located event. The step that reaches `q_w = 0` is evaluated as connected. One explicit sentence would avoid divergent readings.
4. **`label.c_rating_burst`.** §2 lists it, but class packs have no burst rating. The generator writes `null`; the spec does not say whether `null` is allowed.
5. **One reference capacity per template.** §1 has no per-temperature capacity, which forces the normalisation choice described above for multi-temperature datasets. This is consistent with plan principle 3, but worth stating in §1.

## Reproduce

```sh
python3 -I research/battery/test_ecm_reference.py                       # 19 tests, OK (about 7 s)
python3 -I research/battery/bat-05/fit_cells.py \
  references/battery-energy/galeotti-lipo-dataset references/battery-energy/kollmeyer-hg2-dataset   # about 5 min
python3 -I research/battery/bat-05/build_batteries.py                   # writes the 10 files above
python3 -I research/battery/bat-05/build_batteries.py --check           # "input hashes: 127/127 ...", "check: OK"
```

Software: Python 3.12.3, NumPy 1.26.4, SciPy 1.11.4 (recorded in `fit_results.json`). A second `fit_cells.py` run reproduced `fit_results.json` byte for byte (`cmp`, 2026-10-19).
