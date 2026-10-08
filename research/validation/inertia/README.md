# VAL-6a — Swing-test reducer

**Status:** offline tooling verified with synthetic fixtures; physical VAL-6 measurements remain open. Python 3 standard library; no Godot dependency or aircraft-data writes. [Evidence and sources](../../../docs/research/validation/VAL-6a/README.md).

From the repository root:

```sh
python3 research/validation/inertia/test_reduce.py
python3 research/validation/inertia/reduce.py research/validation/inertia/synthetic.json
```

The CLI prints a deterministic JSON report to stdout, including exact input-byte and reducer SHA-256 hashes. Invalid data exits 1 with no report. A plank outside the 3% nominal band is a successful diagnostic report, not a program failure. The example is entirely synthetic; never relabel it as measured aircraft evidence.

## Input contract

Use [synthetic.json](synthetic.json) as a structural example. All fields are required unless specified below; unknown fields and duplicate JSON keys are refused.

| Field | Meaning |
| --- | --- |
| `format` | `openrc-swing-test v1` |
| `evidence` | `synthetic` or `measured`; measured campaigns cannot contain synthetic quantities |
| `configuration` | Aircraft/plank, installed equipment, fuel, axis setup and raw-record identifiers |
| `gravity` | Quantity ID for acceleration in `m/s^2`; local estimate or identified reference |
| `quantities` | IDs → `{value, unit, u, kind, source}`; finite positive values, nonnegative standard uncertainty `u` in the same unit; kinds `measured`, `estimated`, `derived`, `reference`, `synthetic` |
| `experiments` | Nonempty list with unique `id`, `axis` (`Ixx`, `Iyy`, `Izz`), `method` (`bifilar`, `compound`), `loaded`, `tare`, `notes`, optional `plank` |
| `loaded`, `tare` | Each run has quantity IDs for `mass` (kg), `elapsed` (s), and integer `cycles` (complete oscillations). Bifilar adds `spacing` and `length` (m); compound adds `height` (m). `tare: null` explicitly means negligible fixture inertia; justify this in `notes`. |
| `plank` | Optional uniform rectangular-prism check: quantity IDs `dimension_a`, `dimension_b` for the two dimensions perpendicular to the CG axis, plus `source` describing uniformity and measurements |

`spacing` means full wire separation, not half-spacing. `height` means each configuration's combined CG distance below the shared pivot, not the aircraft-only CG height. Record loaded and empty-rig mass separately. Repeat timings should be separate experiments; this version does not average them or infer timing uncertainty.

Use `u` as a one-standard-deviation uncertainty, not an instrument resolution or maximum error. Record its derivation in `source`. Reuse a quantity ID only for the **same measurement** shared between calculations (for example unchanged wire spacing). The reducer sums sensitivities before squaring, retaining this covariance. Different IDs are assumed independent; equal values do not make them correlated. Common calibration biases between distinct readings and partial correlations need a fuller uncertainty model, outside this version.

## Equations and limits

For `T = elapsed / cycles`, bifilar inertia is `J = m*g*D²*T²/(16*pi²*L)`. The object CG must lie on the rotation axis; tare rotates about that same axis. Subtract the empty rig's axis inertia from the loaded axis inertia. Loaded and tare spacing/length values must match; common axis alignment is an unchecked assumption recorded in `notes`.

For a compound run, pivot inertia is `J = m*g*h*T²/(4*pi²)`. Let `M = m_loaded - m_tare` and `Q = m_loaded*h_loaded - m_tare*h_tare`. Then object CG height is `H = Q/M`, and its inertia is `I = J_loaded - J_tare - Q²/M`. The report retains `net_swing_axis_inertia` before the shift. Without tare, the tare terms are zero. This avoids subtracting inertias referred to different CG axes. The optional uniform plank reference uses `I = M*(a²+b²)/12`.

Uncertainty is first-order propagation: `u(I) = sqrt(sum((dI/dx * u(x))²))`, with one term per distinct input ID. Output contributions are signed and have the output quantity's unit. The report also propagates uncertainty in the relative plank discrepancy, including the mass shared by measurement and theory. It flags `u(I) >= I`; large relative errors can invalidate linear propagation even below that threshold. For an untared compound run, `stationary_height_warning` flags a height sensitivity no larger than the omitted quadratic scale `M*u(h)`. A zero first derivative does not prove zero physical uncertainty; compound tare can also have nonlinear terms that this flag does not assess. A 3% comparison uses nominal values only, not a confidence interval.

The model assumes small amplitude, negligible damping, rigid attachments, matched axes, parallel equal-length bifilar wires, and negligible buoyancy. It does not estimate aerodynamic added inertia or certify these assumptions from the input. The output is an **in-air estimate**, not a corrected rigid-body coefficient for the aircraft JSON. For compound runs, `effective_cg_inertia` applies a rigid-mass parallel-axis shift: transfer of aerodynamic added inertia between axes remains unresolved. Its `cg_estimate_definition` records this distinction; retain the net pivot result for later air corrections. A tare can remove fixture inertia, but cannot guarantee cancellation of interacting aerodynamic effects.

For physical VAL-6 work, preserve video/raw timing, amplitude and decay observations, rig/axis photographs, alignment checks, repeated runs, uncertainty sources and a known-plank test. Compare at least two compound pivot offsets. A passing synthetic plank proves algebra only; the real rig must still meet the roadmap's 3% comparison, with uncertainty and systematic limits assessed, before using aircraft results.
