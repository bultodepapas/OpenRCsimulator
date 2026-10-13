# HELI-05: X-Cell main-rotor reference

**Date:** 2026-10-13. **Scope:** standalone source-based main-rotor loads and first-order tip-path-plane flapping. This Python reference and its oracle are numerical implementation evidence; they do not establish flight-data validation or a complete rotorcraft model.

## Source equations and conventions

The primary source is Gavrilets, Mettler, and Feron, “Dynamic Model for a Miniature Aerobatic Helicopter,” AIAA 2001-4333, especially §§4.1.1–4.1.3 and Eqs. 5–6 (printed p. 6), Eqs. 11–12 (p. 8), Eqs. 17–23 (pp. 9–10), and Eqs. 25–27 (pp. 11–12). [Paper PDF](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf). Parameter provenance is recorded in [HELI-01](../HELI-01/README.md#11-mit-x-cell-60-se-gavrilets-mettler-feron-1-f).

Retained page renders for equation review: [6](references/heli05-page-06.png), [7](references/heli05-page-07.png), [8](references/heli05-page-08.png), [9](references/heli05-page-09.png), [10](references/heli05-page-10.png), [11](references/heli05-page-11.png), [12](references/heli05-page-12.png). These are source excerpts, not simulator output.

The main rotor is a two-blade, no-twist rotor. The paper uses one uniform collective pitch, θ0; it does not give a root-to-0.75R conversion for this no-twist case. This reference therefore sets θ0 equal to the supplied 0.75R collective θ75 without extrapolation. With solidity σ = N c/(πR), total in-plane advance ratio μ, axial ratio μz = w/(ΩR), and λ0 = vi/(ΩR), the ideal thrust coefficient is

```text
CT,ideal = (a σ / 2) [ θ75 (1/3 + μ²/2) + (μz − λ0)/2 ]
CT       = clamp(CT,ideal, −CTmax, +CTmax)
T        = CT ρ πR² (ΩR)²
```

The source omits cyclic and roll-rate effects on thrust as second-order terms in its identified μ < 0.15 range. The symmetric hard clamp follows the paper; it is not a smooth saturation. Negative loading is retained algebraically. The fixtures do not claim inverted-flight or high-μ physical validation.

The source torque coefficient uses constant section drag CD0 and the 7/3 advance-ratio term:

```text
CQ = CT (λ0 − μz) + (CD0 σ/8) (1 + 7 μ²/3)
Q  = CQ ρ πR³ (ΩR)²
```

This reference does not substitute a quadratic profile-drag law or a 4.65 multiplier.
The paper omits the main rotor's in-plane force from its load calculation and lumps it with fuselage forces. This kernel likewise emits no separate rotor in-plane drag or side force.

The TPP equations use the source first-order lumped response. In the FRD mapping below, p and q are already rates in rad/s and sit outside the `1/τe` aerodynamic bracket:

```text
τe = 16/(γfb Ω)
∂a1/∂μx = 2 Kμ (4 θ75/3 − λ0)
∂b1/∂μy = −∂a1/∂μx
∂a1/∂μz = Kμ 16 μ² / [(1 − μ²/2)(8 μ + a σ)] sign(u)
ȧ1 = −q + [−a1 + (∂a1/∂μx) μx + (∂a1/∂μz) μz − A δforward]/τe
ḃ1 = −p + [−b1 + (∂a1/∂μx) μy + B δright]/τe
```

The `∂a1/∂μz` expression uses total in-plane μ in both terms, following the paper's magnitude definition, and `sign(u)` to carry the axial term into backward flight. The paper does not define that backward-flow sign construction; it is an explicit interpretation. Pure sideflow sets this derivative to zero. Eq. 26 produces the positive `(+∂a1/∂μx) μy` term shown in `ḃ1`. API forward cyclic is positive forward and maps to negative paper longitude input so steady a1 is negative; positive right cyclic maps directly to positive b1. The gains scale as `(Ω/Ωnom)²`. The equations omit flap cross-coupling and cyclic thrust terms.

Body axes are FRD: +x forward, +y right, +z down. Positive a1 tilts the thrust aft and gives a nose-up spring moment; positive b1 tilts it right and gives a positive roll spring moment. The exact normalized force direction

```text
n = normalize(−sin(a1), sin(b1), −cos(a1) cos(b1))
F = T n
M = r_hub × F + (Kβ b1, Kβ a1, 0) + (0, 0, −rotation_sense Q)
```

is a kinematic extension selected for finite TPP angles. The paper's hub-force moment is shown in small-angle form; applying the thrust at `r_hub` supplies its `T hmr` contribution, so the direct spring is added only once. Clockwise from above uses `rotation_sense=+1`; positive pitch moment is nose-up.

The source identified μ < 0.15 and small flapping (|a1|, |b1| < 10°). The output exposes those as separate flags. Eq. 27's real algebraic denominator requires μ < √2; values between 0.15 and √2 are computed only as an algebraic extension and are flagged outside the identified range. No result in that region is a physical qualification.

## Test profile and derived anchors

[`main_rotor_oracle.json`](../../../../research/helicopter/reference/main_rotor_oracle.json) contains a test-only parameter profile and independent known-answer fixtures. The profile follows the X-Cell table values: R = 0.775 m, c = 0.058 m, N = 2, a = 5.5/rad, Iβ = 0.038 kg·m², Kβ = 54 N·m/rad, γfb = 0.8, Kμ = 0.2, Ωnom = 167 rad/s, nominal cyclic gains 4.2, hmr = 0.235 m, CD0 = 0.024, and CTmax = 0.0055. HELI-01 marks blade lift slope, CD0, CTmax, and γfb as borrowed or estimated; the source parameter categories remain explicit there.

The fixture density ρ = 1.225 kg/m³ is an assumed operating condition for repeatable tests, not an aircraft parameter. Any future weather or atmosphere integration must supply density explicitly at the model boundary. These parameters are not defaults for an authored aircraft.

With the fixture density and measured blade inertia, the independently derived Lock number is 3.7097956289 (source check 3.71). The diagnostic scale `16/(Lock Ωnom)` is 25.8258 ms. It is distinct from the paper's 5% bare-flap settling estimate `24/(Lock Ωnom)`, about 39 ms, and the effective flybar-lumped `τe = 16/(γfb Ωnom)` from Eq. 23, 119.7605 ms. The diagnostic bare-flap value is not substituted for the effective flybar response.

The oracle includes a hover collective solved analytically to produce 8.2 kg × 9.81 m/s², a zero-thrust profile-torque case that isolates the 7/3 term, forward and backward in-plane flow, pure sideflow, symmetric positive and negative hard clamps, a flagged algebraic extension, finite-angle normal behavior, and the stopped-disk closure. The oracle generator duplicates the equations and does not import the reference implementation. This kernel has no Johnson VRS branch, ground-effect correction, or dynamic-inflow state or coupling.

## API and verification

[`main_rotor.py`](../../../../research/helicopter/reference/main_rotor.py) exposes:

- `prepare(parameters)` requires the complete flat parameter mapping and returns a validated read-only model. There are no parameter defaults.
- `evaluate(model, inputs)` requires Ω, one explicit inflow form (`induced_velocity_m_s` or `lambda0`), hub-relative air velocity and body rates in FRD, θ75, forward/right cyclic, a1, and b1. Supplying both inflow forms is rejected. The dimensional induced-velocity path is the intended runtime interface; the ratio path supports equation checks.
- Inputs must be finite, Ω must be nonnegative, and runtime angles must lie in [−π/2, +π/2]. The model rejects μ ≥ √2 because the selected Eq. 27 expression is outside its real algebraic domain.

At Ω = 0 the azimuth-averaged rotor is inactive: thrust, torque, force, moment, and flap rates are zero. The output has no λ/μ/coefficient or effective-time-constant values and does not convert between λ and vi. This closure excludes parked-blade mechanics and does not assert a physical stopped-rotor model.

Run the standard-library checks and freshness test from the repository root:

```powershell
python research/helicopter/reference/test_main_rotor.py
python research/helicopter/reference/make_main_rotor_oracle.py --check
```

The tests cover source-form thrust and torque, hard clamp behavior, pitch/cyclic signs, the body-rate terms outside the lag bracket, the Eq. 26 lateral-flow sign, backward-flow inference, FRD force and moment composition, explicit inflow forms, finite/domain rejection, the Ω = 0 closure, and deterministic oracle generation. Passing them establishes consistency between two implementations and the declared analytic anchors only; it does not validate the helicopter against flight data.

## GDScript kernel

[`main_rotor.gd`](../../../../app/physics/rotorcraft/main_rotor.gd) prepares a flat read-only scalar context; its hub arm is detached from the source array. Density is an explicit operating condition in this standalone context, so a density change requires a newly prepared context. No defaults or authored-aircraft data are supplied. Evaluation takes dimensional vi and packed float64 FRD hub velocity/body rates; the Python ratio path remains research-only.

The main-rotor suite passes 768 checks on Godot 4.7.2 Windows and Ubuntu/WSL, including the ten independent oracle cases, hard clamp and power anchors, body-rate dimensions, source lateral-flow sign, one-count hub moment, context/input refusal and immutable preparation. Compact and full diagnostic evaluations return byte-identical loads and flap derivatives for every oracle case. The compact path avoids diagnostic-vector/dictionary allocation; input/context checks remain active. Three disposable defects—dividing q by the lag time, changing the lateral-flow sign and doubling the hub-arm moment—are rejected by the tests.

```powershell
$MainRotorOracle = (Resolve-Path research/helicopter/reference/main_rotor_oracle.json).Path
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_main_rotor.gd -- --oracle="$MainRotorOracle"
```

The shared [verification runner](../../../../research/helicopter/verify_kernels.py) supplies absolute paths and checks both reference freshness and native behavior.

## Joint main-rotor stage

[`main_rotor_stage.gd`](../../../../app/physics/rotorcraft/main_rotor_stage.gd) evaluates the main rotor once, uses that stage's actual thrust to obtain the literal Johnson target, and returns both loads and `[a1, b1, vi]` derivatives. The prescribed Ω is supplied by the caller; drive dynamics, tail rotor, airframe and rotor momentum are absent. Inflow uses the paper's shaft/body-frame approximation. Projecting flow into the exact tilted TPP would need a separate qualification. Swash harmonic phasing is also unresolved: the pure swash's geometric outputs cannot yet be connected directly to the identified logical cyclic inputs.

The 25-check stage suite drives three continuous states through the existing nonautonomous RK4 core while holding the body and shaft speed fixed. It checks query purity, actual stage-vi feedback into thrust, signed reflection, residual wake at rotor stop and compact/full payload equivalence. With unsaturated hover `T=A-Bvi` and the ideal target `vi²=T/(2ρA_disk)`, the settled vi agrees with the independently solved positive quadratic root at h, h/2 and h/4. Cyclic flap targets also settle. This stand is not a whole-helicopter hover trim or a flight.

All 42 Python reference tests and freshness checks pass. The application-wide Windows parse sweep covered 507 scripts; later main-kernel optimizations also pass focused parsing and execution on both platforms. Existing airplane goldens and 30/60/144 FPS body-state identity pass on Windows and Ubuntu/WSL. One Linux frame-run process initially timed out; its focused rerun and the subsequent native-only suite passed. This track changes no airplane runtime path or golden file. The full application test suite and physical acceptance remain outside this report.

## HELI-09b isolated stage cost

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/helicopter/bench_main_stage.gd
```

Windows, Ryzen 9 5900X, Godot 4.7.2 official, 2026-10-13; 20 warmed batches of 500 calls per regime, run alone:

| Stage fixture | Median batch mean (µs/call) | p95 batch mean (µs/call) |
| --- | ---: | ---: |
| Hover | 22.07 | 24.11 |
| Forward | 25.98 | 29.19 |
| VRS crossflow | 41.24 | 42.83 |
| Windmill crossflow | 27.87 | 30.30 |

The first diagnostic-heavy implementation cost about 46–61 µs in a separate run. That sequential observation is not a paired speedup proof; compact/full exact payload checks establish numerical preservation. The table measures main-disc/wake work only, excluding tail, airframe, drive, body and seam localization. It is not individual-tick latency, the H15 host, HELI-09 acceptance or the 500 µs whole-tick gate. The VRS fixture leaves insufficient margin against the planned full-load budget; complete-stage profiling/redesign must precede session integration.
