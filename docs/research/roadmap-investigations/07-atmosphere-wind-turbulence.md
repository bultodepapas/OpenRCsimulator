# 07 — Atmosphere, wind, turbulence, thermals and slope lift

**Status:** research knowledge base, 2026-10-06. **Serves:** ROADMAP M5 ([WIND-PLAN](../../WIND-PLAN.md) M5-W00…W08, Gates W-A/W-B), LANDSCAPE-PLAN L15a (windsock), [SMOKE-PLAN](../../SMOKE-PLAN.md) SM-09 (smoke drifts with wind), G2 (engine power vs density), every consumer of air density. **Read with:** [WIND-PLAN](../../WIND-PLAN.md), [wind-physics-primary-sources](../wind-physics-primary-sources.md), [wind-godot-integration](../wind-godot-integration.md), [wind-investigations](../wind-investigations/README.md), [RESEARCH: wind and thermals](../../../RESEARCH.md#wind-thermals-and-inexpensive-validation).

## Already settled elsewhere (not repeated here)

The Spanish wind documents settled these points:

- Conventions: W(x,t) in NED is where the air moves *to*. The UI shows "from" bearings. `v_air = v_ground − Rᵀ·W`. No extra wind force, no `−dW/dt` term. Trimmed start in moving air. ([WIND-PLAN §3](../../WIND-PLAN.md))
- Composition `W = mean + discrete gust (1−cos) + turbulence + local`. Each part can be switched off and traced. Calm is the default and must replay the goldens bit for bit. ([§4, §9](../../WIND-PLAN.md))
- The first turbulence is OU ("approximate correlated turbulence", not called Dryden). It uses an exact recurrence. RNG state is advanced once per tick, never inside `sample()`. Seed and RNG state are saved as decimal strings. ([§4.3, §6.2](../../WIND-PLAN.md), [inv. 02, 09](../wind-investigations/README.md))
- Dryden/von Kármán spectra, Taylor's hypothesis, the log law with z0 and d, and spanwise gradients are covered at the level of concepts and NASA sources. ([physics sources](../wind-physics-primary-sources.md))
- Tools are settled: Welch/CSD protocol, Van Loan discretisation of the noise covariance (verified for OU), JSBSim and TurbSim as offline oracles, ImmediateMesh diagnostics, and particle advection ownership. ([inv. 05–12](../wind-investigations/README.md))

**This report adds what those documents lack:** an atmosphere and density model, MIL low-altitude parameters in numbers for RC, the rotational turbulence components, an architecture for sampling wind at each surface that keeps the linear oracle valid, a PRNG that reproduces exactly, shear near the ground and the treeline wake, thermals, slope lift, dynamic soaring constraints, validation numbers, and new sub-steps.

## Summary

1. **Density changes more with heat than the code comment admits.** On a 35 °C day at sea level σ = ρ/ρ₀ = 0.935 (−6.5 %). A 1500 m field at 35 °C gives ρ = 0.956 kg/m³: σ = 0.78, density altitude ≈ 2510 m. Stall speed rises 13 %, and thrust at fixed rpm and glow power both fall about 22 %. ([computed](#parameters-and-data))
2. **The engine torque in the uncommitted G2 shaft model (P51-06) ignores ρ, but the propeller torque scales with it.** At low density the rpm would rise and the thrust would hardly fall, which is physically backwards. The engine's indicated torque must scale with σ, or with the SAE J1349 form.
3. **ISA computed from p/(R·T) gives 1.2250000181, not the literal 1.225.** The calm/ISA default must keep the literal constant, or the goldens change.
4. **MIL low-altitude Dryden for RC heights** (h in ft, clamped at 10 ft): σ_w = 0.1·W20 and σ_u = σ_w/(0.177+0.000823h)^0.4 ≈ 1.9·σ_w. At 10 m L_u ≈ 67 m. L_w is 10 m (MIL-F-8785C) or 5 m (MIL-HDBK-1797). MIL-F-8785C and MIL-HDBK-1797 differ by a factor of 2 in L_w and L_v. ([1](#sources), [3](#sources))
5. **WIND-PLAN's OU is the MIL-HDBK-1797 discrete form** when it is parametrised as τ = L/V, with L from height and σ from W20. It has the same integral scale as the second-order Dryden with twice the length. So W04a can be "MIL-1797 first-order" at no extra cost. The exact OU update stays stationary even when V changes every tick.
6. **For a 1.5 m span the rotational gusts are large.** At 10 m AGL in an 18 km/h wind, σ_p ≈ 20 °/s, against a full-aileron roll rate of about 150–190 °/s. Measured small-craft data show large spanwise fluctuations even at 0.45 m spacing ([12](#sources)). The rotational parts belong in the model; they are not decoration.
7. **Architecture:** each tick, sample W and its 3×3 gradient G at the CG once. Every surface then sees `flow_i = v_air + ω×r_i − G_b·r_i`, which is exact for linear fields. The oracle sees effective rates `p−∂W_z/∂y`, `q+∂W_z/∂x`, `r−∂W_y/∂x`. A uniform field leaves the loads unchanged. Rolling at p in still air equals a field with ∂W_z/∂y = p: this gives an exact test.
8. **Stochastic parts are held per tick. Deterministic fields (shear, wake, thermals, slope, dynamic soaring shear layers) are sampled at every RK4 stage.** At dynamic-soaring speeds the aircraft moves about 1 m per tick, so holding the field per tick would erase a thin shear layer.
9. **Own PRNG:** xoshiro128** (public domain) fits exactly in GDScript 64-bit ints with 32-bit masks. Tested here, its output matches the C reference bit for bit. Four normals plus 8 filter states cost **≈ 10 µs/tick** on the loaded dev VM (2 % of the budget).
10. **The surface layer near the ground is steep.** With z0 = 0.03 m, U(1 m) = 0.60·U(10 m). An approach from 10 m to 1 m in a 6 m/s wind loses 2.4 m/s of headwind. In a 60° bank at 3 m, the wingtips see 0.46 m/s difference. CRRCSim's shear stops at 10 m; above that its wind is constant.
11. **The field's treeline (trees 12–25 m tall, ring at 270–570 m) puts the flying box inside its wake for almost every wind direction.** Windbreak wakes reduce wind measurably out to about 30 H, i.e. 360–750 m here. Dense barriers add turbulence; porosity above about 30–40 % removes recirculation.
12. **Thermals and slope lift are cheap analytic fields once terrain and AGL exist.** Allen's model is public domain and has a check case: r2 = 79.4 m at z = 280 m. Slope lift starts from a 2D cylinder (w = U·R²/r² at 45°) and grows to CRRCSim-style panels. Dynamic soaring only requires that the API never prevents sharp shear layers.

## Where the code stands

| File | Fact (read 2026-10-06) | Missing |
| --- | --- | --- |
| [air_data.gd](../../../app/physics/air_data.gd) | `RHO_SEA_LEVEL := 1.225`. The comment says altitude below 500 m changes ρ by < 5 %. `compute(s, wind_ned, rho)` uses one wind vector | No T, p or humidity; heat alone changes ρ by 6.5 % (§Summary 1); no TAS/IAS distinction |
| [dynamics.gd](../../../app/physics/dynamics.gd) | `rho` and `wind_ned` are parameters; ρ reaches `Aero.loads` and `Propulsion.loads` | Wind is one vector for the whole aircraft |
| [aero.gd](../../../app/physics/aero.gd) | Global oracle: `qbar`, damping `k = 0.25·ρ·V`. Local model: 3 strips per side plus 2 tails, `flow = v_air + ω×r` with **the same `v_air` everywhere**, `½ρ…` | No per-surface wind; no gust rates in the damping terms |
| [propulsion.gd](../../../app/physics/propulsion.gd) (committed) | `T = Ct·ρn²D⁴`, `P = Cp·ρn³D⁵`; rpm follows a throttle-mapped target with no ρ | Engine power does not depend on density |
| propulsion.gd, `slipstream.gd`, `turbine.gd` (**uncommitted, other tracks, 2026-10-06**) | Shaft balance `engine_torque(rpm, throttle, prop)` has no ρ while `prop_torque ∝ ρ`. Slipstream and turbine take ρ (turbine thrust ∝ ρ/ρ_ref). The slipstream uses CG `air` | Re-read before implementing; engine torque needs σ |
| [flight_session.gd](../../../app/sim/flight_session.gd) | Trim validation and `_loads` pass `Air.RHO_SEA_LEVEL` and `[0,0,0]`; `_t` unused | Atmosphere and wind provider |
| [default.json](../../../app/data/fields/default.json) | 480 trees at 270–570 m radius, gaps at 30±8° and 210±10°; heights 12–25 m ([treeline.gd](../../../app/render/treeline.gd)); flat, visual only | Field elevation, roughness, treeline height and porosity as physics data |
| [trace.gd](../../../app/sim/trace.gd) | `openrc-trace v3` | ρ, W, G and turbulence seed columns or header |

## Theory and models

### A. Atmosphere

**ISA** (ICAO Doc 7488 / ISO 2533; [16](#sources)): T₀ = 288.15 K, p₀ = 101 325 Pa, ρ₀ = 1.2250 kg/m³, lapse 6.5 K/km, R = 287.05 J/(kg·K).
`p(h) = p₀(1 − L·h/T₀)^(g/(R·L))`, `ρ_ISA(h) = ρ₀(1 − L·h/T₀)^(g/(R·L) − 1)`.

**Moist air, non-standard day** (fidelity ladder):

| Level | Model | Error vs CIPM-2007 | Use |
| --- | --- | --- | --- |
| L0 | ρ = 1.225 constant | up to 30 % at hot/high fields | Today; calm default |
| L1 | Dry ideal gas `ρ = p/(R_d·T)`, with p from field elevation (ISA) or QNH | ≤ 1.3 % (ignores humidity) | Minimum useful |
| L2 | Partial pressures: `ρ = (p−e)/(R_d·T) + e/(R_v·T)`, with `e = RH·e_s(T)` and Buck `e_s = 611.21·exp((18.678 − t/234.5)·t/(257.14 + t))` Pa ([14](#sources)) | ≤ 0.03 % in our cases | **Recommended runtime** |
| L3 | CIPM-2007 (enhancement factor f, compressibility Z, x_CO2) ([13](#sources)) | reference | Offline oracle only. **Formally valid only for 600–1100 hPa and 15–27 °C** (Appendix A.3), so it is not a reference for 35 °C |

**Density altitude** is the ISA height with the same ρ: `DA = (T₀/L)·(1 − (ρ/ρ₀)^(1/(g/(R·L) − 1)))`. NWS uses a virtual-temperature form ([15](#sources)). DA is for display and pilot intuition; the physics consumes ρ.

**Variation with height in flight:** in ISA, ρ falls 0.5 % by 50 m, 1.4 % by 150 m and 2.8 % by 300 m (computed). This is negligible for sport flying (L1 per flight). An optional lapse per tick costs one `pow`.

**Where ρ must flow:**

| Consumer | Dependence | Now |
| --- | --- | --- |
| Aero oracle and local surfaces | ∝ ρ (qbar, damping) | ✅ via parameter |
| Propeller T, Q | ∝ ρ at fixed n, J | ✅ |
| Glow/gas engine indicated torque | ≈ ∝ σ (charge mass); friction does not scale with σ | ❌ (G2 slice) |
| Electric motor torque | independent of ρ: lower ρ means less prop load, slightly higher rpm, lower current | ❌ (future) |
| Turbine (AV-05) | gross thrust ∝ ρ/ρ_ref (uncommitted) | partial |
| Slipstream (E0b) | `T/(ρA)` disc velocity | ✅ (uncommitted) |
| Trim solver, linearise, HUD (IAS = TAS·√σ) | consistent ρ | ❌ literal constant |
| Reynolds number via μ(T) (Sutherland) | future Re-dependent polars | n/a |

**Engine power vs density.** Naturally aspirated piston engines lose power roughly in proportion to charge density. SAE J1349 (spark ignition, wide-open throttle) corrects with `cf = 1.18·(99/p_d[kPa])·√(T/298.15) − 0.18`, where p_d is dry-air pressure and the −0.18 term represents mechanical losses that do not scale ([17](#sources); intended range 15–35 °C, 900–1050 hPa). Gagg & Farrar (1934) give an aviation altitude correlation ([18](#sources); coefficients not verified here). In our cases J1349's relative power closely matches σ (table below), so **"indicated torque ∝ σ, friction constant"** is the recommended first model. It applies to glow fuel as well; this is unverified, since no glow-specific data was found.

Consequence with a shaft balance: if engine torque scales with σ and propeller torque with ρ·n², the equilibrium rpm stays nearly the same and thrust ∝ σ. With constant friction the rpm falls slightly. If engine torque ignores ρ (the uncommitted slice), n ∝ σ^−½ and the static thrust `ρn²` **stays constant at altitude**, which is wrong.

### B. Turbulence for small aircraft below 100 m

**MIL low-altitude parameters** (h < 1000 ft, h in ft; JSBSim and CRRCSim clamp h ≥ 10 ft) ([1](#sources), [3](#sources), [4](#sources)):

| Quantity | MIL-F-8785C | MIL-HDBK-1797 |
| --- | --- | --- |
| L_u | h/(0.177 + 0.000823h)^1.2 | same |
| L_v | = L_u | L_u/2 |
| L_w | h | h/2 |
| σ_w | 0.1·W20 (wind at 20 ft) | same |
| σ_u = σ_v | σ_w/(0.177 + 0.000823h)^0.4 | same |
| W20 categories | 15 kt light, 30 kt moderate, 45 kt severe | same |

For RC, treat W20 as the actual mean wind at 6.1 m, as CRRCSim does with `σ_w = 0.1·V_wind`. Do not use the light/moderate/severe categories: they are certification severities. Derived cross-check: surface-layer ratios σ_u ≈ 2.4u* and σ_w ≈ 1.25u* (textbook values, online source not verified) give σ_u/σ_w ≈ 1.9, as MIL does at h ≤ 30 ft. With the log law, `σ_w = 0.1·W20` then implies **z0 ≈ 0.036 m**, mown-grass roughness. So the MIL intensity matches an open grass field.

**Spectra** (one-sided, temporal, frozen field, V = airspeed): see [physics sources](../wind-physics-primary-sources.md) for Φ_u, Φ_v, Φ_w. Rotational parts (8785C form; signs differ between specifications) ([2](#sources)):
`H_p(s) = σ_w·√(0.8/V)·(π/(4b))^(1/6)/(L_w^(1/3)·(1 + (4b/(πV))·s))`,
`H_q(s) = ±(s/V)/(1 + (4b/(πV))·s)·H_w(s)`, `H_r(s) = ∓(s/V)/(1 + (3b/(πV))·s)·H_v(s)`.
Discrete forms used by JSBSim and CRRCSim: `σ_p = 1.9·σ_w/√(L_w·b)`, `L_p = √(L_w·b)/2.6`, `q_g ← (1 − πV·T/(4b))·q_g ± (π/(4b))·Δw_g`, and similarly for r_g with 3b ([3](#sources), [4](#sources)).
Physical meaning: p_g ≈ ∂w_g/∂y, q_g ≈ ∂w_g/∂x, r_g ≈ −∂v_g/∂x, i.e. gradients averaged over the span and length. The MIL equations imply a filter roll-off around 2–5 Hz for b = 1.5 m (table below).

**Validity limits for RC:**
- *Frozen field* requires the mean wind and RMS to be small relative to the encounter speed ([1](#sources)). Rough check: σ_u ≈ 1 m/s against V = 15–20 m/s is fine. In hover, 3D flight or slow landings the time scale L/V → ∞; real eddies evolve with lifetime ~L/σ. Use an encounter speed `V_enc = max(V_air, V_min)` with V_min ≈ 1 m/s (estimated).
- *Span vs scale:* b/L_w(1797) is 0.3 at 10 m, 0.6 at 5 m and 1.0 at the 10 ft clamp. Near the ground the RC aircraft is **as large as the vertical eddies**, so the span-averaged p_g approximation degrades. That is still better than nothing, and it is the regime where Thompson et al. measured large fluctuations even at 14–450 mm spacing, following a fractional power law, and tied them to roll-control difficulty growing as craft get smaller ([12](#sources)).
- *Frequency:* the Dryden and von Kármán transfer functions are cited as valid up to about 8 Hz (Gage, via [11](#sources)). At 240 Hz there is no aliasing concern.
- *Small-UAV evidence:* Patel et al. (small UAV, "moderately gusty" day) and Watkins & Vino (vehicle-mounted probes, below 610 m) found Dryden and von Kármán reasonable, with **somewhat more low-frequency energy than the model** ([11](#sources), secondary citation).
- *Non-Gaussian, non-stationary* near the ground; NASA-CR-2886 is already cited in the [physics sources](../wind-physics-primary-sources.md).

**Discretisation.**
- 8785C v and w are second order. The MIL-1797 discrete forms are first order: `x ← (1 − VT/L)·x + √(2VT/L)·σ·η`, an Euler-type OU. Its variance error is `2a/(1 − (1−a)²) − 1` with `a = 2VT/L`: **+1.5 % at 240 Hz, V = 18, L = 5 m** (computed). The error grows as L shrinks and V grows, and the form goes unstable at a > 1.
- **Use the exact OU** `a = exp(−V·dt/L)`, `x ← a·x + σ·√(1−a²)·η`. It is stationary for any per-tick a, so a varying V is harmless.
- Exact second-order Dryden: Van Loan gives A_d and Q_d. Verified here: L = 5 m, V = 18 m/s, σ = 0.5 m/s at 240 Hz gave a stationary discrete variance of 0.25000 exactly. A 1 h simulation had RMS 0.4975 and a median Welch/target ratio of 0.997 over 0.02–20 Hz (Hann, nperseg 16384, no detrend).
- Because V changes every tick, A_d and Q_d of the double-pole filter need closed forms or a small table in V. The alternative is to step the filter in *distance flown through the air*.
- First-order "1797" and second-order "8785C" with twice the scale have the same integral scale, Φ(0) = σ²L/(πV). The second-order model only adds energy at high frequency.

### C. Mean wind near the ground

The log law and its domain are in the [physics sources](../wind-physics-primary-sources.md). Numbers for our heights (U(z)/U(10 m), computed):

| z (m) | 0.5 | 1 | 2 | 5 | 10 | 30 | 100 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| z0 = 0.005 (smooth, runway) | 0.61 | 0.70 | 0.79 | 0.91 | 1 | 1.14 | 1.30 |
| **z0 = 0.03 (mown grass)** | 0.48 | 0.60 | 0.72 | 0.88 | 1 | 1.19 | 1.40 |
| z0 = 0.1 (rough grass, crops) | 0.35 | 0.50 | 0.65 | 0.85 | 1 | 1.24 | 1.50 |
| 1/7 power law | 0.65 | 0.72 | 0.79 | 0.91 | 1 | 1.17 | 1.39 |
| CRRCSim (1/7 up to 10 m, then constant) ([4](#sources)) | 0.65 | 0.72 | 0.79 | 0.91 | 1 | **1.00** | **1.00** |

z0 ranges: grassland 0.01–0.05 m, cropland 0.1–0.25 m, forest 0.5–1.0 m; displacement height d ≈ 2/3–3/4 of the obstacle height; the log law holds in the lowest ~100 m and in neutral conditions ([19](#sources)). Davenport class 1 is z0 = 0.03 m ([20](#sources)). The field's surface table (E3a) can carry z0 next to friction.

**Flight consequences** (U10 = 6 m/s, z0 = 0.03):
- Shear gradient: 1.03 s⁻¹ at 1 m, 0.52 s⁻¹ at 2 m, 0.10 s⁻¹ at 10 m.
- Descending from 10 m to 1 m loses 2.4 m/s of headwind, the classic "gradient" sink on finals.
- In a 60° bank at 3 m the wingtips differ by 0.46 m/s, about 5 % qbar asymmetry at 18 m/s, which rolls the aircraft further into the bank (low-turn hazard). At 10 m the difference is 0.14 m/s.
- These effects need per-surface sampling; a CG-only wind captures only the first.

### D. Obstacles: treeline wake, buildings

Windbreak agronomy data, measured at crop height:
- Wind is reduced upwind for 2–5 H and downwind up to 30 H. Gaps funnel and *accelerate* the wind. Dense windbreaks reduce wind the most, but they pull air downward behind them, which creates turbulence and shortens the protected zone. ([21](#sources))
- Reductions of 20 % or more extend to about 25 H; reductions are measurable to 50 H; low porosity means more downstream turbulence. ([22](#sources), secondary)
- Behind porous fences, recirculation disappears above about 30–40 % porosity. ([23](#sources), search result only)

Application here: H = 12–25 m gives a wake out to 30 H ≈ 360–750 m. The flying box lies 5–20 H downwind of the upwind ring for **every wind direction except through the two gaps**. The model needs (estimated, to be validated):
`U(x, z) = U_log(z)·(1 − D(x/H, z/H))`, `σ_i(x, z) = σ_i,open·(1 + K(x/H, z/H))`. D peaks at 3–6 H and recovers by about 30 H. The wake height growth and the values above about 1.5 H have **no data in these sources** (unverified). Treat the shape as estimated and validate it with pilot reports and windsock video. A hangar or building rotor is a separate bluff-body problem; it was not researched here (unverified).

### E. Thermals

**Allen (2006), NASA DFRC** ([8](#sources)):
- Mean updraft: `w̄ = w*·(z/zi)^(1/3)·(1 − 1.1·z/zi)`.
- Outer radius: `r2 = max(10, 0.102·(z/zi)^(1/3)·(1 − 0.25·z/zi)·zi)` (Lenschow).
- Inner radius: `r1/r2 = 0.0011·r2 + 0.14` for r2 < 600 m, otherwise 0.8.
- Peak: `w_peak = 3·w̄·(r2³ − r2²·r1)/(r2³ − r1³)`.
- Shape: bell form with constants k1–k4 per r1/r2 (Table 3) and a downdraft ring out to 2·r2.
- Environmental sink `w_e` from mass conservation; updraft count `N = 0.6·X·Y/(zi·r2)`; updrafts are held about 20 min (5–30 min).
- Data source: Desert Rock, NV. Monthly mean w* is 1.1–2.7 m/s and zi is 440–1975 m.
- The MATLAB check case is in the appendix: w* = 2.56 m/s, zi = 1401 m, z = 280 m gives **r2 = 79.4 m** and 5 updrafts per km². Reproduced here.
- NASA work; public domain is assumed for US-government work, but the report's terms are unverified.

Values at RC heights (w* = 2.56 m/s, zi = 1401 m; computed):

| z (m) | 30 | 60 | 100 | 150 |
| --- | --- | --- | --- | --- |
| w̄ (m/s) | 0.69 | 0.85 | 0.98 | 1.07 |
| r2 (m) | 39.5 | 49.5 | 58.2 | 66.0 |
| w_peak (m/s) | 1.71 | 2.08 | 2.36 | 2.56 |

A sport plane at 18 m/s crosses a 40–60 m core in 2–3 s. A 2 m/s core changes α by atan(2/18) = **6.3°**: this is the "rough summer air" pilots feel, not a gentle lift.

**Simpler models:**
- ArduPilot SITL: Gaussian `w = W·exp(−r²/R²)`. The core leans downwind by U·(height)/W (a rising bubble drifts at the wind speed), so the lean angle is atan(U/W). ([5](#sources))
- ArduSoar uses Wharington's Gaussian, assuming stationarity at each altitude. ([10](#sources))
- Lecarpentier et al. add drift, a life cycle (latency, growth, maturity, fade) and noise to Allen. ([9](#sources))
- CRRCSim adds a "vacuum-cleaner" inflow toward the core and a ring sink. ([4](#sources))
- Dust devils are not covered by these sources (unverified; omit).

### F. Slope lift and dynamic soaring

**Analytic 2D ridge (potential flow around a cylinder of radius R):**
- Crest speed `U·(1 + R²/r²)`.
- Maximum updraft on the 45° windward ray: `w = U·R²/r²`. For U = 8 m/s and R = 60 m: 6.8 m/s at 5 m above the surface, 3.6 m/s at 30 m, 2.0 m/s at 60 m (computed).
- Potential flow has no separation, so it overestimates lift and has no lee rotor.

**CRRCSim** ([4](#sources)):
- Mode 1 fits a plane to terrain samples in the vertical plane along the wind.
- Mode 2 solves a 2D **source-panel** potential flow over 11 panels whose spacing grows with height above the terrain.
- Built-in Cape Cod slope: `w += 0.4·U·sin²(…)`, tapered to zero between 100 and 250 ft.
- Dynamic-soaring scene: below 86 ft behind the ridge the wind *reverses*; a linear shear layer runs from 86 to 100 ft.
- GPL-2: ideas only.

**PicaSim** ([7](#sources)):
- Vertical wind = terrain slope along the wind (finite differences at a smoothing distance that grows with height), decaying exponentially with height.
- A "zero-wind height" and a rotor tendency produce reversed flow in the lee.
- Turbulence is prepared once per frame as a value plus spatial derivatives at a reference point, then linearly extrapolated to each component. This is the same per-point pattern we recommend.
- License: PolyForm Noncommercial 1.0.0, so ideas only, not code.

**Dynamic soaring:** energy is gained by crossing the boundary between a fast layer over the ridge and dead or reversed air in the lee. Top speeds are about 10× the wind; the reported RC ground speed is 908 km/h (2023, not sanctioned) ([24](#sources); Rayleigh 1883 cited there). Requirements that must not be blocked:
- A shear layer only a few metres thick, sampled at each RK4 stage. At 250 m/s the aircraft moves 1.04 m per tick (computed), so a per-tick hold aliases the layer.
- Per-surface gradients.
- Aero valid at high q. Compressibility is outside this report.

## Implementation options and trade-offs

| Topic | Option | Cost | Fidelity | Determinism | Verdict |
| --- | --- | --- | --- | --- | --- |
| Atmosphere | L0 constant | 0 | poor hot/high | trivial | keep as default path |
| | **L2 ideal gas + Buck, once per flight** | ~1 µs per flight | ≤ 0.1 % | pure | **adopt** |
| | CIPM-2007 at runtime | small | reference, but range limited | pure | offline oracle only |
| Turbulence | OU uniform (WIND-PLAN W04a) | ~3 µs/tick | integral scale only | own PRNG | first, parametrised by MIL |
| | **Dryden 1797 first-order + p,q,r** | ~10 µs/tick (measured) | MIL standard | own PRNG | **adopt as W04a+/W05d** |
| | Dryden 8785C second-order exact | +2 states per axis | high-frequency shape | same | W06a if pilots notice |
| | von Kármán (rational approximations) | +3–4 states | best fit to data | same | only with RC measurements |
| | 3D frozen grid (Mann/FFT, TurbSim) with trilinear lookup | memory MB, 8 lookups/point | true spatial coherence | precomputed | too slow in GDScript per point; GDExtension later |
| Spatial sampling | CG only | 0 | misses roll gusts and shear in banks | — | not enough |
| | Per-surface full `sample(x_i)` | N × field cost × 5 RK4 calls | exact for deterministic fields | pure | only for cheap analytic fields |
| | **CG value + 3×3 gradient G (analytic or finite differences) + Dryden p,q,r** | ~5 µs | exact for linear fields | pure | **adopt** |
| | Tail-delay buffer (frozen field: tail sees w(t − l_t/V)) | ring buffer | exact longitudinal | pure | alternative to q_g, never both |
| PRNG | Godot `RandomNumberGenerator` (PCG32, `real_t` normals) | native | float32 normals; algorithm may change | per version | not for physics |
| | **xoshiro128** in GDScript + polar normals** | 2.3 µs/normal | 53-bit uniforms | bit-exact vs C | **adopt** |

**Recommendation for this repo (ordered):**
1. Add `physics/atmosphere.gd`, a pure function. The weather preset supplies T, QNH and RH; the field file supplies elevation. The result is ρ, p, T, σ, DA, IAS factor and μ. The ISA default must return the literal 1.225.
2. Pass ρ through the session to trim, loads, HUD and engine. Scale engine indicated torque by σ in G2.
3. Turn WIND-PLAN W04a into MIL-1797 first-order: σ from W20 = U(6.1 m), L from AGL, exact OU with τ = L/V_enc.
4. Introduce `AirField.sample(x_ned, t) → W (3), J (3×3)` as a pure function for deterministic parts. The stochastic Dryden state is advanced once per tick in `pre_step`, next to rpm and servos, and gives W_t and ω_g.
5. In `Air.compute`, build `G_b = Rᵀ·J·R` and the turbulence rates. Aero consumes `flow_i = v_air + ω×r_i − G_b·r_i`; the oracle damping uses the effective rates.
6. Add analytic fields as separate steps, each with its own oracle: log shear, treeline wake, Allen thermals, cylinder ridge.

## Godot / GDScript notes

- **PRNG:** xoshiro128** 1.1 ([26](#sources)) uses only shifts, xors and multiplications by 5 and 9 on 32-bit values. In GDScript's signed 64-bit `int` with `& 0xFFFFFFFF` no intermediate exceeds 2³⁶, so there is no overflow and no undefined behaviour. **Tested in Godot 4.7.2 headless:** from state {1,2,3,4} the first four outputs [11520, 0, 5927040, 70819200] equal the C reference compiled with gcc. Build a 53-bit double from two outputs (`(hi>>5)·2²⁶ + (lo>>6)) / 2⁵³`). Use the Marsaglia polar method for normals; 200 k samples gave mean −0.0017 and variance 1.006.
- Seeding: SplitMix64 needs 64-bit wrap-around multiplies, which are unsafe in signed GDScript ints. Seed by hashing the decimal seed string offline-identically with 16-bit limb multiplies, or jump-split streams (`jump()` = 2⁶⁴ steps; [26](#sources)) into one independent stream per component (u, v, w, p, gust schedule, thermals, visual).
- `sqrt` is IEEE-exact, but `log`, `exp` and `sin` come from the platform libm. **Bit identity across Windows, Linux and macOS is not guaranteed**: the goldens already accept this ("same environment"). For cross-platform replay, record the realised wind (W, ω_g) per tick in the trace and replay from it.
- Measured cost (dev VM, load ~2, Godot 4.7.2): **2.3 µs per normal; ≈ 10 µs/tick for 4 normals + 8 filter states**. Per-surface gradient sampling is 7 matrix–vector products (estimated ≤ 5 µs). Allen thermals with N ≤ 10 and one `exp` each are cheap. The total stays under 5 % of the 500 µs budget if Dictionaries stay out of the hot path (compile presets to `PackedFloat64Array`).
- Do not use `Vector3`/`Basis` for G or W (float32 guard). Keep the 3×3 G as 9 floats.
- `FastNoiseLite` stays visual-only (`real_t`; [wind-godot-integration](../wind-godot-integration.md)). The windsock and trees get their own visual stream with matching σ and L, not the aircraft's realisation (the CG Dryden process has no spatial extent).

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use here |
| --- | --- | --- | --- | --- |
| JSBSim FGWinds.cpp | Milspec/Tustin Dryden incl. p,q,r; 10 ft clamp; POE table | LGPL-2.1+ | [3](#sources) | Offline oracle (as [inv. 07](../wind-investigations/05-08-analysis-tools.md)); port the equations, not the code |
| CRRCSim mod_windfield, wind_from_terrain | 1/7 shear, 1797 Dryden with wind-aligned σ/L tensors, thermals, 2D panel slope, DS shear | GPL-2 | [4](#sources) | Ideas and formulas only |
| ArduPilot SIM_Aircraft.cpp | Gaussian thermals with lean; turbulence as IIR 0.98 *per update*, so it depends on the rate, plus a random-walk azimuth | GPL-3 | [5](#sources) | Anti-pattern for turbulence; thermal lean idea |
| PX4 gazebo_wind_plugin | Gaussian draw per publish interval; ramped gusts | Apache-2.0 | [6](#sources) | Anti-pattern (white noise, no correlation) |
| PicaSim Environment.cpp | Value + gradient turbulence, slope from terrain, lee rotor | PolyForm NC 1.0.0 | [7](#sources) | Architecture idea only |
| Allen 2006 MATLAB | Updraft model + check case | NASA report (public domain assumed, unverified) | [8](#sources) | Port to GDScript with the check case as fixture |
| MathWorks Dryden blocks docs | Both MIL variants, discrete forms, 1000–2000 ft blending | docs | [1](#sources), [2](#sources) | Equation reference |
| xoshiro128** | PRNG | public domain (CC0-style dedication) | [26](#sources), [27](#sources) | Runtime PRNG |
| CIPM-2007 | Moist-air density oracle | paper | [13](#sources) | Offline test values |
| SciPy `welch`, `expm`, `solve_discrete_lyapunov` | PSD and discretisation checks | BSD-3 | (inv. 05–06) | `research/` scripts, as done here |

## Parameters and data

| Quantity | Typical RC value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| ρ ISA sea level | 1.2250 | kg/m³ | manual | [16](#sources) |
| ρ sea level 35 °C, 60 % RH | 1.131 (σ 0.923, DA 823 m) | kg/m³ | derived | L2 calc. |
| ρ sea level −5 °C, 50 % | 1.315 (σ 1.074) | kg/m³ | derived | L2 |
| ρ 600 m, 30 °C, 50 % | 1.075 (σ 0.877, DA 1343 m) | kg/m³ | derived | L2 |
| ρ 1500 m, 35 °C, 0 % / 40 % | 0.956 / 0.946 (σ 0.78/0.77, DA 2510/2609 m) | kg/m³ | derived | L2 (CIPM differs by 0.02 %) |
| Relative power (J1349) at the 1500 m / 35 °C cases | 0.779 / 0.755 | — | derived | [17](#sources) |
| W20 for practice | 0–8 (Beaufort 0–4: 4 = 6–8 m/s, 11–16 kt) | m/s | manual | [25](#sources) |
| Sport-flyer upper wind limit | ~7–8 m/s (25–30 km/h) | m/s | **estimated, unverified community value** | owner to confirm |
| σ_w, σ_u at 10 m, W20 = 5 m/s | 0.50, 0.94 | m/s | derived (MIL) | [1](#sources) |
| L_u at 2/5/10/30/100 m | 23*/37/67/153/263 (*clamped at 10 ft) | m | derived | [1](#sources) |
| L_w (1797) at 10 / 30 m | 5 / 15 | m | derived | [1](#sources) |
| σ_p at 10 m, W20 = 5, b = 1.524 m | ≈ 20 | °/s | derived | [3](#sources) formula |
| p_g / q_g filter corner, b = 1.524 m, V = 18 m/s | 2.7 / 2.4 | Hz | derived | — |
| Turbulence intensity σ_u/U at 10 m, z0 = 0.03 | 0.17 | — | derived (2.4u*, unverified ratio) | — |
| z0 mown grass / crops / forest | 0.03 / 0.1–0.25 / 0.5–1.0 | m | borrowed | [19](#sources), [20](#sources) |
| Treeline H (field) | 12–25 | m | estimated (visual layout) | default.json |
| Wake extent / ≥ 20 % reduction | ≤ 30 H / ≈ 25 H | — | borrowed (crop height) | [21](#sources), [22](#sources) |
| Allen w*, zi (annual mean) | 2.56, 1401 | m/s, m | measured (desert) | [8](#sources) |
| Thermal w_peak, r2 at 60 m | 2.1, 50 | m/s, m | derived | [8](#sources) |
| ArduPilot scenario thermals | W 2–5, R 30–80 | m/s, m | estimated (SITL) | [5](#sources) |
| DS top speed / wind | ≈ 10× | — | community | [24](#sources) |

## Validation

**Verification (known answers):**
1. Atmosphere: the default ISA returns the literal 1.225 and the goldens stay byte-identical. L2 is within 0.05 % of the CIPM fixture values from this report, inside CIPM's range. Density altitude at ISA 1500 m gives 1500 ± 1 m. 35 °C at sea level gives σ = 0.935.
2. Trim at σ = 0.78 gives the same α and CL, with V_trim × 1/√σ = 1.132 and thrust at fixed rpm × σ.
3. Engine with shaft model: at σ = 0.78 the static rpm stays within a few % and static thrust ≈ σ·T₀. A mutation where engine torque ignores σ must fail this (thrust ≈ T₀).
4. PRNG: the first 1000 outputs equal the C reference (fixture). Polar normals have mean and variance within bootstrap bands, using the [inv. 05](../wind-investigations/05-08-analysis-tools.md) protocol.
5. Turbulence: exact-OU variance σ² stays constant while V steps every tick. Welch PSD of u, v, w and p_g against the MIL targets, median ratio 1 ± 0.05 over 0.02–20 Hz (0.997 achieved here for w). σ = 0 gives zero output. 30/60/144 fps give the same series.
6. **Rotational equivalence:** a non-rotating aircraft in a linear field with ∂W_z/∂y = c (body) gives the same aero loads as the aircraft rolling at p = −c in still air (the sign follows from `flow = v + ω×r − G·r`). Same check for q and ∂W_z/∂x, and for r and ∂W_y/∂x. Agreement to 1e-12, in both the oracle and the local model.
7. A uniform field gives a load delta of 0 (already in WIND-PLAN §9). The log profile reproduces the table in §C. No NaN at z ≤ z0 + d (clamped).
8. Allen check case: r2 = 79.4 m and N = 5 at z = 280 m. The vertical-mass integral of updrafts + downdraft rings + sink over the test area is ≈ 0.
9. Cylinder ridge: crest speed U(1 + R²/r²) and w = U·R²/r² on the 45° ray.

**Independent validation against real RC behaviour:**
- Spectra and intensity: compare with Thompson et al. (spanwise, open terrain, MAV scale; [12](#sources)) and NASA-CR-2886. Expect more low-frequency energy than Dryden ([11](#sources)).
- Owner playtests with hidden presets at Beaufort 2/3/4 and a summer-thermal preset: rate "feels like my field" on drift, bumps in turns, the sink on finals in the gradient, and roughness behind the treeline by wind direction.
- Windsock video at the owner's field against the L15a windsock driven by the same σ and L.
- Optional later: an RC logger (airspeed, IMU) to measure σ_p at 10 m AGL.

**Mutation tests that must fail:**
- Flip the sign of p_g, or of the G term.
- Use the Euler "Milspec" form at 60 Hz with L = 1.5 m (variance error detected).
- Feed MIL formulas in metres instead of feet (L_u 3.3× off).
- Swap the 1797 and 8785C L_w.
- Consume RNG inside `sample()` (series changes with extra HUD queries).
- Hold deterministic fields per tick in the DS shear fixture (energy gain changes).
- Omit ρ in the propeller.
- Rotate G with R instead of Rᵀ.

## Pitfalls and risks

1. **ISA-from-constants ≠ 1.225** (1.2250000181). *Mitigation:* the calm/ISA path returns the literal value; re-record goldens only for a deliberate physics change.
2. **Feet vs metres in MIL formulas** (h, L, 10 ft clamp). *Mitigation:* convert at the boundary and add a unit-annotated test at h = 10 m.
3. **8785C vs 1797 conventions** (L_v, L_w factor 2; signs of q_g and r_g). *Mitigation:* name the variant in the data (`turbulence.spec = "MIL-HDBK-1797"`) and add a mutation test.
4. **Euler "Milspec" discretisation** biases variance and is unstable at a > 1. *Mitigation:* use the exact OU, or Van Loan for second order.
5. **V → 0** (hover, takeoff roll in calm). *Mitigation:* `V_enc = max(V_air, V_min)` with an estimated V_min; in calm with W20 = 0 there is no mechanical turbulence anyway.
6. **Double counting** p_g, q_g, r_g with a spatial field or the tail-delay buffer. *Mitigation:* one source of turbulence gradients per preset, enforced by the loader.
7. **A per-tick hold aliases thin shear layers** (DS, rotor edges). *Mitigation:* deterministic fields are pure and are sampled per stage; only stochastic states are held.
8. **Cross-platform libm** breaks bit identity. *Mitigation:* record W and ω_g per tick in traces; goldens stay per-environment as today.
9. **CIPM-2007 used outside 15–27 °C.** *Mitigation:* L2 at runtime, CIPM only inside its range.
10. **MIL severities are not RC conditions.** *Mitigation:* W20 = actual mean wind at 6.1 m. Presets are labelled estimated until playtested.
11. **Windbreak data comes from crop height (1–2 m).** Behaviour above 1–2 H is unverified. *Mitigation:* estimated shape, owner validation, opt-out flag.
12. **Allen is desert data and mixed-layer scaling**, extrapolated to 30–150 m. *Mitigation:* label as estimated and expose w* and zi.
13. **The log law is singular at z ≤ z0 + d;** the ground plane is at z = 0. *Mitigation:* clamp at z0 + d + 0.1 m (estimated) and use the same AGL as ground contact.
14. **License contamination** (GPL CRRCSim/ArduPilot, PolyForm PicaSim). *Mitigation:* derive from papers and specs; note provenance in comments.
15. **The engine ignores ρ** in the shaft slice. *Mitigation:* torque × σ before any hot/high preset ships.
16. **The HUD shows TAS** while pilots think in IAS. *Mitigation:* show both when σ ≠ 1.
17. **The slipstream increment uses the CG `air`.** With per-point wind the "free-stream" baseline of the tail increment must use the same per-surface flow. *Mitigation:* coordinate with E0b before W05c.

## Proposed roadmap steps

Status column: **exists** = already in WIND-PLAN (refined here); **new** = proposed by this report.

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| M5-ATM-1 (new) | `physics/atmosphere.gd`: ISA + T/QNH/RH, Buck, L2 density, DA, σ, IAS factor; ISA default returns literal 1.225 | Table of this report ±0.05 %; CIPM fixtures in range; goldens byte-identical | — |
| M5-ATM-2 (new) | Field `elevation_m` (openrc-field) + weather T/QNH/RH (openrc-weather); ρ through session, trim, HUD, trace header | Trim at σ = 0.78: V × 1.132 at the same α; trace records ρ | ATM-1, W01a |
| M5-ATM-3 (new) | Engine indicated torque × σ (constant friction) in the shaft model | Static thrust ≈ σ·T₀ at σ = 0.78; the "ignores σ" mutation fails | G2/P51-06 |
| M5-W01b (exists) | Uniform wind wired to Air/prop | WIND-PLAN | — |
| M5-W04a (exists, refined) | OU parametrised as MIL-1797 first-order: σ(W20 = U(6.1 m)), L(AGL), exact OU with τ = L/V_enc | Welch vs MIL PSD; variance constant with V steps; seed in header | W05a for AGL (else h fixed) |
| M5-W04c (new) | xoshiro128** + polar normals, per-component jump streams | First 1000 outputs equal C; normal statistics bands | — |
| M5-W05a (exists, refined) | Log profile with z0 (surface table) and d; clamp | U(z)/U(10) table; no NaN at z = 0 | E3a surfaces |
| M5-W05b (exists) | Analytic spatial fixture | WIND-PLAN | — |
| M5-W05c (exists, redesigned) | `AirField.sample → (W, J)` per stage; `G_b = RᵀJR`; local flow `−G_b·r_i`; oracle effective rates | Rotational-equivalence test 1e-12; uniform delta 0; banked-shear roll moment sign | W05b |
| M5-W05d (new) | Dryden p_g, q_g, r_g (or tail-delay buffer) into the effective rates | Welch p_g vs Φ_p; double-counting guard test | W04a, W05c |
| M5-W06a (exists) | Second-order 8785C exact (Van Loan, V-dependent closed form) | Median PSD ratio 1 ± 0.05 (0.997 achieved offline) | W04a |
| M5-W08a (new) | Treeline wake from field data (H, porosity, ring): deficit D and TI factor K | Profile at 2/5/10/20/30 H matches the sourced endpoints; gaps accelerate; owner A/B | W05c, L6 data |
| M5-W08b (new) | Allen thermals + lean + life cycle | Check case r2 = 79.4 m; mass-balance integral ≈ 0 | W05c |
| M5-W08c (new) | Slope lift: 2D cylinder analytic, then a panel method on L13 hills | Cylinder closed form; panel converges to the cylinder | L13 terrain, AGL contract |
| M5-W08d (new, long term) | DS shear layer + high-speed checks | Point-mass Rayleigh-cycle energy gain vs analytic; per-stage sampling test | W08c |
| X-WIND-1 (new) | Trace v4 columns: ρ, W, ω_g, seed; replay from recorded wind | Cross-platform replay equal when wind is recorded | W01d |

## Decisions to take now

1. **The wind API is a pure `sample(x_ned, t) → (W, J)` plus a once-per-tick `prepare_tick` for stochastic state.** Never a single vector inside `Air.compute`. A CG-only API would block shear, wake, thermals, slope and DS later.
2. **Aero consumes `(W_cg, G_body, ω_g)`**, local flow `v + ω×r − G·r`, oracle effective rates. This keeps Gate F's "local = oracle at small angles" true with wind.
3. **Atmosphere data lives in the weather preset (T, QNH, RH) and the field file (elevation).** ρ is computed once per flight. The default is the literal ISA 1.225.
4. **The physics PRNG is our own (xoshiro128**), never Godot's RNG.** The seed is a string in trace and golden headers.
5. **Turbulence is parametrised physically** (W20 from the mean profile, L from AGL, named MIL variant), not by τ in seconds. This supersedes WIND-PLAN's `tau_s` for new presets, with the OU kept as the 1797 discrete form.
6. **Engine torque scales with σ** in the shaft model now, before atmosphere presets exist.

**Owner decisions needed:**
- (a) Default field elevation and temperature: ISA sea level, or the owner's real field?
- (b) Are thermals and slope (gliders) in M5 scope, or later?
- (c) Accept that turbulence is bit-identical only per platform, with cross-platform replay from recorded wind?
- (d) Confirm the practical wind limit for presets (community estimate 25–30 km/h, unverified).

## Sources

1. MathWorks, *Dryden Wind Turbulence Model (Discrete)*, Aerospace Blockset docs. https://www.mathworks.com/help/aeroblks/drydenwindturbulencemodeldiscrete.html (fetched)
2. MathWorks, *Dryden Wind Turbulence Model (Continuous)*. https://www.mathworks.com/help/aeroblks/drydenwindturbulencemodelcontinuous.html (fetched)
3. JSBSim Team, `FGWinds.cpp` (master), LGPL-2.1+. https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/src/models/atmosphere/FGWinds.cpp (fetched)
4. CRRCSim 0.9.13 (Debian 0.9.13-3.2), `windfield.cpp`, `wind_from_terrain.cpp`, `crrc_builtin_scenery.cpp`, GPL-2. https://sources.debian.org/src/crrcsim/0.9.13-3.2/src/ (fetched)
5. ArduPilot, `libraries/SITL/SIM_Aircraft.cpp` (master), GPL-3. https://raw.githubusercontent.com/ArduPilot/ardupilot/master/libraries/SITL/SIM_Aircraft.cpp (fetched)
6. PX4, `gazebo_wind_plugin.cpp`, Apache-2.0. https://raw.githubusercontent.com/PX4/PX4-SITL_gazebo-classic/main/src/gazebo_wind_plugin.cpp (fetched)
7. D. Chapman, PicaSim `source/PicaSim/Environment.cpp` and LICENSE.txt (PolyForm Noncommercial 1.0.0). https://github.com/Rowlhouse/PicaSim (fetched)
8. M. J. Allen, *Updraft Model for Development of Autonomous Soaring Uninhabited Air Vehicles*, AIAA 2006 / NASA. https://ntrs.nasa.gov/api/citations/20060004052/downloads/20060004052.pdf (fetched)
9. E. Lecarpentier, S. Rapp, M. Melo, E. Rachelson, *Empirical evaluation of a Q-Learning Algorithm for Model-free Autonomous Soaring*, 2017. https://arxiv.org/pdf/1707.05668 (fetched)
10. S. Tabor, I. Guilliard, A. Kolobov, *ArduSoar: an Open-Source Thermalling Controller for Resource-Constrained Autopilots*, 2018. https://arxiv.org/pdf/1802.08215 (fetched)
11. K. Cole, A. Wickenheiser, *Spatio-Temporal Wind Modeling for UAV Simulations*, 2019, CC-BY 4.0 (cites Patel/Lee/Kroo 2008, Watkins & Vino 2004, Gage). https://arxiv.org/pdf/1905.09954 (fetched)
12. M. Thompson, S. Watkins, C. White, J. Holmes, *Span-wise wind fluctuations in open terrain as applicable to small flying craft*, Aeronautical Journal, 2011. https://www.cambridge.org/core/journals/aeronautical-journal/article/spanwise-wind-fluctuations-in-open-terrain-as-applicable-to-small-flying-craft/2EDCEDAC9C3A6F6616DF222BB4BE5FD1 (fetched, abstract)
13. A. Picard, R. S. Davis, M. Gläser, K. Fujii, *Revised formula for the density of moist air (CIPM-2007)*, Metrologia 45 (2008) 149–155. https://www.nist.gov/sites/default/files/documents/calibrations/CIPM-2007.pdf (fetched)
14. *Arden Buck equation*, Wikipedia. https://en.wikipedia.org/wiki/Arden_Buck_equation (search result only)
15. NWS El Paso, *Density Altitude* calculation sheet. https://www.weather.gov/media/epz/wxcalc/densityAltitude.pdf (fetched)
16. *International Standard Atmosphere*, Wikipedia (cites ICAO Doc 7488, ISO 2533). https://en.wikipedia.org/wiki/International_Standard_Atmosphere (fetched)
17. SAE J1349 correction factor: Wahiduddin, *Dyno correction factor* (reference conditions; formula shown as image) https://wahiduddin.net/calc/cf.htm (fetched); formula text from https://ddisoftware.com/tech-archive/tt-dyno/the-ambient-correction-factors/index.html (search result only)
18. S. D. Gagg, E. V. Farrar, *Altitude Performance of Aircraft Engines Equipped with Gear-Driven Superchargers*, SAE 340096, 1934. https://saemobilus.sae.org/content/340096 (search result only)
19. *Log wind profile*, Wikipedia. https://en.wikipedia.org/wiki/Log_wind_profile (fetched)
20. J. Wieringa et al., *The revised Davenport roughness classification for cities and sheltered country*, AMS 2000. https://ams.confex.com/ams/AugDavis/webprogram/Paper15611.html (search result only)
21. J. R. Brandle, X. Zhou, L. Hodges, *How Windbreaks Work*, UNL Extension EC02-1763, 2002. https://www.env.nm.gov/wp-content/uploads/sites/2/2017/02/How_windbreaks_work.pdf (fetched)
22. G. M. Heisler, D. R. DeWalle, *Effects of windbreak structure on wind flow*, Agric. Ecosyst. Environ. 22–23 (1988) 41–69, as cited in https://fs.usda.gov/nac/buffers/docs/3/3.2ref.pdf (search result only)
23. S.-J. Lee, H.-B. Kim, *Laboratory measurements of velocity and turbulence field behind porous fences*. https://remotecenter.postech.ac.kr/handle/2014.oak/20331 (search result only)
24. *Dynamic soaring*, Wikipedia (RC record 908 km/h, 2023; Rayleigh 1883). https://en.wikipedia.org/wiki/Dynamic_soaring (fetched)
25. Met Office, *Beaufort wind force scale*. https://weather.metoffice.gov.uk/guides/coast-and-sea/beaufort-scale (fetched)
26. D. Blackman, S. Vigna, `xoshiro128starstar.c` (v1.1, public-domain dedication). https://prng.di.unimi.it/xoshiro128starstar.c (fetched)
27. S. Vigna, *xoshiro / xoroshiro generators and the PRNG shootout*. https://prng.di.unimi.it/ (fetched)

Repository sources: [WIND-PLAN](../../WIND-PLAN.md), [wind-physics-primary-sources](../wind-physics-primary-sources.md) (NASA-CR-2886, NASA-CR-2288, NASA-TM-78141, Yeager CR-1998-206937), [wind-godot-integration](../wind-godot-integration.md), [wind-investigations](../wind-investigations/README.md), [RESEARCH](../../../RESEARCH.md#wind-thermals-and-inexpensive-validation), [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) (L6, L15a). Calculations: Python 3.12 / NumPy 1.26.4 / SciPy 1.11.4 and a Godot 4.7.2 headless benchmark, run in the session scratchpad (not committed).
