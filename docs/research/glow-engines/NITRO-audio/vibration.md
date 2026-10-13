# NITRO source-excitation observer

Status: implemented software model; inputs are partly inferred. This is not measured engine, mount, airframe, or cockpit vibration validation.

## Inputs and provenance

The candidate profiles carry manufacturer bore, stroke, and dry engine mass. O.S. lists the MAX-55AX at 23.0 mm bore, 21.5 mm stroke, and 404 g; it lists the FS-64V at 25.0 mm, 21.3 mm, and 442 g. The profiles convert these units to SI. A profile-load check reconstructs swept volume as `π bore² stroke / 4` and requires agreement with the rounded manufacturer displacement within 0.5%.

The internal connecting rod is not dimensioned in the public installation data. Both candidate profiles use an explicitly estimated connecting-rod/crank-radius ratio of 3.5. Reciprocating equivalent mass is estimated as 2.5% of each manufacturer dry engine mass: 10.10 g for the MAX-55AX and 11.05 g for the FS-64V. This is a provisional unmeasured assumption, not a component mass or family-specific gain. A 1–5% dry-mass fraction changes calculated force linearly from 0.4× to 2× the nominal estimate. Results should be read with that uncertainty.

## Calculation and outputs

For crank radius `r = stroke/2`, rod length `l = 3.5r`, crank phase `θ`, and `q = sqrt(l² − r² sin²θ)`, piston travel from TDC toward BDC is

`s(θ) = r(1 − cos θ) + l − q`.

Its first two phase derivatives are

`s′ = r sin θ + r² sin θ cos θ / q`

`s″ = r cos θ + r²[(cos² θ − sin² θ)/q + r² sin² θ cos² θ/q³]`.

The instantaneous slider-crank acceleration includes changing shaft speed:

`a_p = s″ ω² + s′ α`, where `ω` is rad/s and `α = dω/dt` is rad/s².

The observer reports the equal-and-opposite reciprocating-mass reaction along the cylinder axis, `F_source = −m_rec a_p`, plus signed cosine/sine coefficients and peaks at 1X and 2X from a 256-point Fourier integration of the exact slider-crank position `s(θ)`. For local constant `ω` and `α`, displacement coefficient `c_n` gives force coefficients `F_cos = m_rec c_n n²ω²` and `F_sin = m_rec c_n nα`; their resultant peak is `sqrt(F_cos² + F_sin²)`. A caller that supplies zero angular acceleration receives `constant_speed_assumption = true`; this marks the common current-RPM estimate as constant-speed. Prepared geometry and result dictionaries are read-only and contain no references to the source profile. Runtime evaluation does not mutate profile or flight state.

The cycle family comes from the loaded profile: a 2T opportunity is order 1 per crank revolution, while a 4T opportunity is order 0.5. The reported mean successful-fire rate multiplies that profile cadence by observed firing fraction. It does not synthesize combustion pressure or torque pulses. No family multiplier changes inertial force; identical geometry, mass, phase, and shaft motion produce identical source force for either family.

The allowed connecting-rod/crank-radius ratio is at least 2, which keeps the exact square root real throughout crank rotation. Derived lengths, their squares, Fourier positions, and coefficients must remain finite and representable; underflowing or overflowing geometry is rejected. Input speed must be finite and nonnegative; phase and angular acceleration must be finite; firing fraction must be within `[0, 1]`.

## Scope limits

This output is source excitation at an ideal rigid engine origin. It does not predict engine-case, mount, airframe, or cockpit acceleration. Those require a measured mount/body transfer response, including mass, damping, stiffness, and installation geometry. The observer omits connecting-rod side force, rotating-mass imbalance, 4T valve-train force, port events, and combustion torque ripple. A valve-torque loss curve and successful-fire counters are not substitutes for cam lift/moving mass or crank-angle pressure. The audio voice uses only the signed 1X/2X coefficients at audio rate, aligned to the accepted crank phase. Its single `0.0003 normalized-PCM/N` conversion and `0.12` combined source-layer peak bound are authored presentation values, not an acoustic or mount calibration. Invalid/mismatched source telemetry selects the previous authored mechanical fallback. Do not feed the high-frequency source force waveform into the 240 Hz rigid-body or render path. No observer output feeds flight dynamics or visual jitter.

The model is software-checked for the derivative formula, variable-`ω`/`ωdot` terms, signed order spectra, family invariance, extreme finite-input rejection, input immutability, and mass sensitivity. Audio checks cover shared gain, geometry-driven amplitude ratios, phase-aligned source orders, limiter bounds, invalid-data fallback, and immutable telemetry. Physical force amplitudes, mount response, synchronized vibration spectra, pilot assessment, and acoustics remain open validation work.

## References

- O.S. Engines, [MAX-55AX manufacturer specifications](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15610.htm).
- O.S. Engines, [FS-64V manufacturer specifications](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html).
- Penn State ME 481, [Shaking Force for Slider Crank](https://www.me.psu.edu/sommer/me481/notes_08_04.pdf), slider-crank acceleration and reciprocating inertia.
- Tsitsilonis et al., [Systematic Investigation of a Large Two-Stroke Engine Crankshaft Dynamics Model](https://strathprints.strath.ac.uk/72400/1/Tsitsilonis_etal_Energies_Systematic_investigation_of_a_large_two_stroke_engine_crankshaft.pdf), *Energies* 13 (2020), 2486; pressure-derived gas torque and inertia excitation requirements.
- Zhang et al., [Vibration characteristic analysis of single-cylinder two-stroke engine and mounting system optimization design](https://pmc.ncbi.nlm.nih.gov/articles/PMC10451931/), mount response requiring mass, damping, and stiffness.
