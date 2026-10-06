# Aerodynamic repair diagnostics

2026-10-06 · Research on the current, still provisional flight-repair model. The runs below use Godot 4.7.2 and the aircraft JSON hash recorded in each result file. They are numerical coherence checks, not flight validation.

## Passivity sweep

[Reproducible Godot sweep](repair-fuzz.gd) · [Full result](repair-fuzz-results.json).

The sweep evaluated 229,933 deterministic states: body speed 0–40 m/s, angle of attack ±180°, sideslip ±90°, body rates through ±100 rad/s, and independent endpoint/neutral values for elevator, both ailerons and rudder. It includes a dense transition grid and 27,783 zero-COM-speed combinations. No sample had aerodynamic power above `1e-7 W`; the largest sampled value was exactly zero at zero translation and zero rotation. The transition grid occupied all ten weight bins from 0 to 1.

Zero speed at the centre of mass does not mean zero flow at the surfaces. In 27,702 zero-COM samples, rotation produced nonzero loads; none produced positive power. For example, the largest zero-COM load norm in this sweep came from `ω = (−5,−20,−20) rad/s` and had `P = −963.47 W`.

For the complete local-surface branch, passivity follows from its construction. For a panel at arm `rᵢ`, let `vᵢ = v_CG + ω × rᵢ`. Its drag is `F_Dᵢ = −½ρ Aᵢ CDᵢ |vᵢ| vᵢ`, its lift is perpendicular to `vᵢ`, and its moment is `rᵢ × Fᵢ`. Therefore

```text
P = F · v_CG + M_CG · ω
  = Σ Fᵢ · (v_CG + ω × rᵢ)
  = −Σ ½ρ Aᵢ CDᵢ |vᵢ|³ ≤ 0
```

provided `CDᵢ ≥ 0` and the surfaces are fixed. This argument includes rotational flow when `v_CG = 0`; it excludes servo work, propulsion and gravity. The finite sweep also covers the blended and global branches, but does not prove their passivity for every real-valued state. No arbitrary `max(CD, 0)` clamp is supported by these results. If a future state reveals `P_global > 0` while the local branch has `P_local ≤ 0`, the load blend `L=(1−λ)L_global+λL_local` is passive for `λ ≥ P_global/(P_global−P_local)`; this is a derived constraint, not a coefficient correction, and its smoothness should be checked before implementation.

The fast `--quick` mode evaluates 10,871 directed/random samples in 1.68 s in this environment. It can seed a bounded CI check; the full sweep remains a research command.

## Coupled modal check

[Godot matrix extractor](repair-modes-probe.gd) · [Raw matrices](repair-modes-input.json) · [NumPy eigenanalysis](repair-modes-eigen.py) · [Results](repair-modes-results.json).

`FlightModes.analyze()` reports spiral time from a 4×4 lateral projection. The NumPy check instead eigensolves the complete 8×8 Jacobian exported from production `app/`. The Jacobian comes from `Dynamics.evaluate()` at level trim with controls frozen and includes the propeller’s derived rotor momentum. `FlightModes` itself still reports the projection, so its spiral time is not a full coupled stability result.

| V (m/s) | Trim α | Projected spiral τ (s) | Largest real root of full Jacobian (s⁻¹) | Full-matrix e-fold τ (s) |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 11.03° | −2.90 | +0.34818 | −2.87 |
| 15 | 4.26° | −29.22 | +0.04372 | −22.87 |
| 20 | 1.82° | −118.21 | +0.02089 | −47.86 |
| 25 | 0.69° | +4982.52 | +0.01535 | −65.14 |

Negative `τ` denotes divergence. At 25 m/s the projected lateral mode appears almost neutral and stable, while the full matrix has a slow positive real root whose eigenvector is dominated by bank angle, forward/lateral velocity and yaw rate. This is the effect of omitted longitudinal/lateral coupling, not evidence that the projection is numerically wrong.

Treat this as an open validation limit. At 10 m/s, trim α≈11.03° and `local_flow_weight≈0.856`: it lies in the oracle-to-local blend from 8° to the positive stall-start angle of about 12.13°. Its local mode is especially sensitive. At 15 m/s the attached-oracle trim shows a much slower spiral-like divergence of about 23 s per e-fold; that rate can be plausible for an airframe but has not been checked against a physical Ugly Stik. The 25 m/s coupled divergence is also slow, about 65 s per e-fold. The new `Cnb≈0.1214` is derived from estimated tail geometry while much of the lateral derivative set remains borrowed, so do not alter it simply to force a stable spiral sign. Compare hands-off bank/heading drift and coupled manoeuvres against pilot or airframe evidence before treating these modes as acceptance targets.

Reproduce the matrix and eigenvalue files from the repository root:

```bash
FLIGHT_REPAIR_MODES_OUT="$PWD/docs/research/flight-robustness/repair-modes-input.json" \
  $(app/get-godot.sh) --headless --path app \
  --script "$PWD/docs/research/flight-robustness/repair-modes-probe.gd"
python3 docs/research/flight-robustness/repair-modes-eigen.py \
  --input docs/research/flight-robustness/repair-modes-input.json \
  --output docs/research/flight-robustness/repair-modes-results.json
```
