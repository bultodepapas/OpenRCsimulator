# HELI-06: X-Cell tail-rotor reference

**Date:** 2026-10-13. **Scope:** source audit and standalone tail-rotor load reference. The Python kernel and oracle are implementation evidence; they do not establish flight-data validation or a complete rotorcraft model.

## Source equations and conventions

The primary source is Gavrilets, Mettler, and Feron, “Dynamic Model for a Miniature Aerobatic Helicopter,” AIAA 2001-4333, especially §4.1.1 Eqs. 4–7 and §4.1.2 Eqs. 11–12 for the momentum, blade-element, and torque relations, and §4.6 Eqs. 43–50 for the tail rotor. [Paper PDF](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf). X-Cell parameter provenance is recorded in [HELI-01](../HELI-01/README.md#11-mit-x-cell-60-se-gavrilets-mettler-feron-1-f).

Section 4.6 says the tail rotor sees conditions where thrust–inflow iteration can fail, including its own wake at low in-plane airspeed. The authors instead linearize tail thrust around several axial velocities, zero normal flow, and the trim collective. Their source does not give a tail inflow time constant or prescribe a fixed number of iteration passes. The plan's earlier five-pass/approximately 5 ms proposal was therefore replaced. This reference uses the source’s linear thrust law and a bounded scalar root only to derive its trim slopes.

The rotor solidity is `σtr = N c/(π Rtr)`. At zero normal flow, let `μ` be the tail advance ratio, `A = 1/3 + μ²/2`, and `λtrim` be the positive root of the source momentum and blade-element equations:

```text
F(λ) = 2 η λ √(μ² + λ²) + (a σtr/4) λ − (a σtr/2) δtrim A = 0
```

`F` is strictly increasing for `λ ≥ 0`. For positive trim pitch, `F(0) < 0`, while `F(2 δtrim A) > 0`; that gives a finite bracket for bisection or safeguarded Newton. This is a bounded residual solve, not a fixed-pass approximation. `η` is explicit in the model profile. The paper’s `ηw = 0.9` is stated for the main-rotor momentum model; §4.6 does not publish a tail-specific efficiency, so carrying it into the tail-slope derivation is an inferred parameter choice.

The two local derivatives follow by implicit differentiation at `μz,tr = 0` and `δr = δtrim`. With `s = √(μ² + λtrim²)`, `D = 2η(μ² + 2λtrim²)/s`, and `E = −2ηλtrim²/s`:

```text
∂C T/∂δr   = (a σtr/2) A D / (D + a σtr/4)
∂C T/∂μz,tr = (a σtr/4) (D + E) / (D + a σtr/4)
```

At hover with `η = 1`, these reduce to the source’s printed Eqs. 9–10. Those equations omit `ηw`, so they are an analytic check distinct from the test profile’s explicit `η = 0.9`. The published tail coefficient plots in Figs. 8–9 are not digitized here; this derivative construction is not claimed to reproduce their empirical curves.

For runtime flow, this reference follows Eq. 47 literally as a through-origin relation using actual tail blade pitch, including the trim offset described in §5:

```text
CT,linear = (∂CT/∂δr) δr + (∂CT/∂μz,tr) μz,tr
CT        = clamp(CT,linear, −CTmax,tr, +CTmax,tr)
```

Eq. 47 prints no affine intercept or `(δr − δtrim)` term. The resulting global use of its local slopes is an explicit extrapolation. A trim root at or above `CTmax,tr` is rejected because its local derivative is saturated. The source force cap is:

```text
ft       = 1 − 3 Svf/(4 π Rtr²)
Ωtr      = ntr Ωmr
T        = ft CT ρ (Ωtr Rtr)² π Rtr²
|T|      ≤ ft CTmax,tr ρ (Ωtr Rtr)² π Rtr²
```

The tail speed and tip speed diagnostics are positive magnitudes. `rotation_sense` is the tail shaft direction about body `+y`; it changes the shaft reaction moment, not the source’s collective-to-thrust law. For the source X-Cell orientation, positive local thrust `T` acts along body `−y`, so `Ftr = (0, −T, 0)`. With `rtr = (−ltr, 0, −htr)`, the hub moment is `rtr × Ftr = (−htr T, 0, ltr T)`. The added shaft reaction is `(0, −rotation_sense Qtr, 0)`. This signed-spin interface is a simulator convention; the paper treats one X-Cell rotor direction.

Body axes are FRD: `+x` forward, `+y` right, `+z` down. The paper’s hub-relative air velocities follow from the point velocity at `rtr`:

```text
ua         = CG forward air velocity
wtr        = wa + ltr q − Kλ Vimr
vtr        = va − ltr r + htr p
μtr        = √(ua² + wtr²)/(Ωtr Rtr)
μz,tr      = vtr/(Ωtr Rtr)
```

The source wake ramp uses signed forward airspeed, not `|ua|`. Let
`gi = (ltr − Rmr − Rtr)/htr`, `gf = (ltr − Rmr + Rtr)/htr`, and
`z = ua/(Vimr − wa)`. Eq. 48–49 give:

```text
Kλ = 0                         if Vimr ≤ wa or z ≤ gi
Kλ = 1.5                       if z ≥ gf
Kλ = 1.5 (z − gi)/(gf − gi)   otherwise
```

Thus the wake contribution to `wtr` has the paper’s explicit minus sign; body pitch rate contributes `+ltr q`, and `p` and `r` enter only the tail rotor’s normal velocity above. The source uses CG forward velocity `ua`, omitting the full point-velocity correction `−htr q` there; q still affects the in-plane speed through `wtr`. `gf > gi` follows from positive `Rtr` and `htr`.

The induced inflow used by the vertical-fin model follows Eq. 50, after thrust capping and with `CT` normalized before the geometric blockage factor:

```text
λ0,tr = μz,tr − 2 [ 2 CT/(a σtr) − δr (1/3 + μtr²/2) ]
Vitr  = λ0,tr Ωtr Rtr
```

The tail torque adapts Eqs. 11–12 with tail-rotor parameters and the capped aerodynamic coefficient:

```text
CQ,tr = CT (λ0,tr − μz,tr) + (CD0,tr σtr/8)(1 + 7 μtr²/3)
Qtr   = CQ,tr ρ (Ωtr Rtr)² π Rtr³
```

The reference is azimuth-averaged. At `Ωmr = 0`, it returns zero tail loads and induced velocity, omits coefficient and flow-ratio conversions, and may still report the geometric main-rotor wake factor. Parked tail-blade mechanics are outside this slice.

The explicit parameter contract requires positive density, rotor dimensions, chord, lift slope, thrust cap, speed ratio, hub offsets, trim pitch, and wake efficiency; it requires exactly two blades, `0 < σtr < 1`, `0 < δtrim ≤ π/2`, `0 < η ≤ 1`, `0 < ft ≤ 1`, nonnegative section drag and fin area, and `rotation_sense ∈ {−1,+1}`. Runtime main-rotor speed must be nonnegative and actual tail collective must lie in `[−π/2,+π/2]`. For numerical safety, active evaluations reject `μ > 10⁶` or `|μz,tr| > 10⁶`; these guards are implementation limits, not a claimed physical operating envelope. Evaluation also rejects trim thrust at or above the configured cap because the local unsaturated derivatives are then undefined.

## Reference and evidence

[`tail_rotor.py`](../../../../research/helicopter/reference/tail_rotor.py) requires a complete flat parameter mapping and returns a read-only prepared model. Density, geometry, trim pitch, wake efficiency, and shaft direction are explicit inputs; there are no aircraft defaults. Runtime input is CG air velocity and body rates in FRD plus main-rotor induced velocity, main speed, and actual tail collective.

[`tail_rotor_oracle.json`](../../../../research/helicopter/reference/tail_rotor_oracle.json) contains an explicit X-Cell test profile, equation anchors, and independent known-answer cases for hover, negative collective, forward and reversed translation, wake-ramp boundaries, positive and negative thrust caps, stopped rpm, body-rate hub offsets, and shaft-reaction reflection. [`make_tail_rotor_oracle.py`](../../../../research/helicopter/reference/make_tail_rotor_oracle.py) re-derives those results without importing the reference module. These numeric checks establish implementation consistency only; they do not validate the extrapolated tail law against flight measurements.

Run the standard-library checks from the repository root:

```powershell
python research/helicopter/reference/test_tail_rotor.py
python research/helicopter/reference/make_tail_rotor_oracle.py --check
```

## HELI-06a native kernel

[`tail_rotor.gd`](../../../../app/physics/rotorcraft/tail_rotor.gd) prepares a detached, flat read-only context. Operating density is explicit and changing it requires preparation again. The active stage uses dimensional CG air velocity, body rates and main induced velocity; all arithmetic and returned loads use float64. The trim solver has a cancellation-safe hover quadratic and at most 12 safeguarded Newton proposals followed by bounded bisection, with a relative residual check. It solves coefficient trim only, not a nonlinear actual-flow equilibrium.

[`test_heli_tail_rotor.gd`](../../../../app/tests/test_heli_tail_rotor.gd) passes 917 checks with the 13-case independent oracle on Godot 4.7.2 Windows and Ubuntu/WSL. Analytic anchors include the constructed hover root, printed η=1 hover derivatives, blocked force cap, Ω² capped authority, Eq. 50 inflow, unblocked aerodynamic power balance, p/q/r point-velocity signs and one-count hub moments. Central differences of independently bisected nonlinear Eqs. 4/5 check both coefficient derivatives at μ = 0, 0.05, 0.15 and 0.3. Compact/full evaluations return byte-identical six-component loads for every oracle case. No persistent flow/load cache is used.

Both languages check the relative trim residual with a 1e−100/rad lift-slope stress input at μ = 0, 0.1 and 0.5. This is a numerical stress case, not a physical rotor. The independent Python bisection needed a scale-aware upper bracket and explicit residual refusal; 80 subdivisions of the geometry-only bracket were insufficient at this scale. The native solver already used scaled linear/quadratic bounds. Ordinary oracle values remain unchanged.

The power check uses unblocked aerodynamic thrust because the source applies fin blockage to side force, while its rotor torque adapts the unblocked aerodynamic coefficient. It is a source component-law check, not an energy balance for the entire tail/fin/wake assembly. Saturated Eq. 50 inflow is a reconstruction; it need not satisfy momentum equilibrium and is not a dynamic wake state.

Three disposable native defects—omitting blockage, reversing the yaw arm, and reversing the hub roll-rate contribution—fail the tests without script errors. The source file is never deliberately mutated. The shared [verification runner](../../../../research/helicopter/verify_kernels.py) and `app/test.sh` include the reference, freshness and native tail checks.

The focused verification passed on Windows and Ubuntu/WSL: all 12 HELI scripts parse, the existing inflow/swash/dynamic/main/stage suites pass, four airplane golden flights pass, and airplane body-state hashes match at 30/60/144 FPS per platform. All nine disposable HELI defects are rejected. Working-tree summaries are `.tools/heli-tail/windows-proof/summary.json` and `linux-proof/summary.json`. After the final reference-bracket stress check, all 55 Python reference tests pass, the tail oracle remains current, and the focused native tail reruns pass 917 checks on both platforms (`reference-final.log`, `tail-final-windows.log`, `tail-final-linux.log` in that folder). This increment did not run the full `app/test.sh` or an application-wide parse sweep. It edits no airplane physics path or golden flight.

```powershell
$TailOracle = (Resolve-Path research/helicopter/reference/tail_rotor_oracle.json).Path
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_tail_rotor.gd -- --oracle="$TailOracle"
```

Airframe/fin/stabilizer loads, tail control, drive/rotor momentum and complete-session integration remain open. Sideways tail VRS and physical transient response are not modeled or validated by this slice. HELI-09 complete-load performance remains an integration gate.

## HELI-09c isolated tail cost

[`bench_tail_rotor.gd`](../../../../research/helicopter/bench_tail_rotor.gd) measures the compact tail evaluation with validation and trim solving included. Windows, Ryzen 9 5900X, Godot 4.7.2 official, 2026-10-13; 20 warmed batches of 500 calls:

| Tail fixture | Median batch mean (µs/call) | p95 batch mean (µs/call) |
| --- | ---: | ---: |
| Hover | 22.56 | 25.58 |
| Forward/main wake | 24.43 | 26.88 |
| Reverse | 23.07 | 26.98 |
| Capped | 20.72 | 24.37 |

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/helicopter/bench_tail_rotor.gd
```

These are batch means on the development host, not individual-tick p95, the H15 host or complete-load acceptance. Combined with [HELI-09b's main-stage diagnostic](../HELI-05/README.md#heli-09b-isolated-stage-cost), they confirm that full-component profiling/redesign is needed before session integration; summing separate runs is not a measured joint-stage latency.

