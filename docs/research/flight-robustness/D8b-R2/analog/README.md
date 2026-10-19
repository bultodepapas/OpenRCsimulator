# D8b-R2d: post-stall wing law against a measured Stik-class airframe (2026-10-19)

**Status: analog evidence, bench and an opt-in spanwise stall progression delivered; no production polar selected.** Production stays on the legacy blend.

- The legacy blend fails the measured static lift and the measured stall-onset roll damping of the NASA FASER (Ultra Stick 120).
- Candidates that meet both make the Stik stop spinning, although the real airframe spins with the same inputs.
- The quasi-steady strip law therefore trades realistic post-stall lift against autorotation. The missing piece is separated-flow dynamics.

Owning step: D8b-R2d in the [pull-up plan](../../../../UGLY-STIK-PULLUP-PLAN.md); method: [polar method review](../implementation/polar-method.md). Sources and caveats: [RC-class aerodynamic data sources](../../../flight-dynamics/rc-aero-data-sources.md).

## Measured targets

FASER is a Hangar 9 Ultra Stick 120: high wing, slab-sided, AR 4.78, the closest documented relative of the Jensen. [`faser_cl.py`](../../../../../research/flight-robustness/d8b-r2/analog/faser_cl.py) digitizes two of its wind-tunnel curves reproducibly. It checks each local PDF's SHA-256 against the source manifest and calibrates from the plots' own frame or gap-tolerant grid lines.

| Curve | Source | Result | Uncertainty |
| --- | --- | --- | --- |
| Static whole-aircraft CL, −4…30° ([CSV](../../../../../research/flight-robustness/d8b-r2/analog/faser_cl.csv)) | Owens, Cox, Morelli 2006, Fig. 2a (q 2 psf, Re ≈ 3.6·10⁵) | Slope 0.0736/deg, CLmax 0.937 at 15°; CL keeps 0.89–0.94 of CLmax to 30° | ±0.2°, ±0.015 |
| Roll damping, −5…40° ([CSV](../../../../../research/flight-robustness/d8b-r2/analog/faser_clp.csv)) | Hoe, Owens, Denham 2012, Fig. 14, forced oscillation, k 0.255 | −0.41…−0.45 to 13.5°, −0.31 at 17.5° (stable for about 5° past the stall), 0 at 20°, +0.08 at 25–30°, +0.19 at 35° | ±0.3°, ±0.01 |

The measured roll term is the forced-oscillation out-of-phase coefficient **Clp + Clβ̇ sin α** (Hoe's Table 2), and above the stall it depends on frequency and rate (Figs. 16 and 18).
- The model is quasi-steady and has no β̇ term. Its Clp is therefore compared only where sin α ≤ 0.3, from 10° to 17.5°.
- The deep-stall values are not like-for-like and are shown for reference only. An earlier version of this record treated them as a pure Clp target; that claim is withdrawn.
- The FASER flight spin is a separate held-out target ([D10-R4](../../../flight-dynamics/spin-post-stall-2026-10-19/README.md)): full up and full rudder give a steep spin at α 30°, β 5°.

## Bench

[`post_stall_sweep.gd`](../../../../../research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd) scores any aircraft JSON or candidate.
- **Method:** static whole-aircraft loads at 25 m/s, controls neutral, every 0.5°. Clp comes from dMx/dp at p = 0.
- **Retention:** CL/CLmax, aligned at the stall peaks (the lift maximum between 8° and 18°; FASER's is at 15°), with its RMS error over FASER 15–30°.
- **Damping:** RMS Clp error over 10–17.5°, and the number of unstable values there. Clp at 20, 25, 30 and 35° is printed for reference only.

## Results

All results come from the [bench output](sweep-production-law.md) on the production code. The long-spin results come from [D10-R4's probe](../../../flight-dynamics/spin-post-stall-2026-10-19/README.md#3-held-out-spin-with-the-candidates), 15–20 s, right spin.

| Data | RMS retention error | RMS Clp error, 10–17.5° | Unstable, 10–17.5° | Held-out long spin |
| --- | --- | --- | --- | --- |
| Stik legacy blend (production) | 0.327 | 0.957 | 4 of 6 | spins, steep (α 20.5°, r 93°/s) |
| `steep` fixture | 0.384 | 0.633 | 3 of 6 | spins (α 24.8°, β 29°) |
| `intermediate` fixture | 0.272 | 0.517 | 3 of 6 | spins (α 25.3°, β 26°) |
| `retained` fixture | 0.160 | 0.427 | 3 of 6 | spins, shallower (θ −55°) |
| `faser-analog`, uniform table | **0.022** | **0.130** | 0 of 6 | **no developed spin** |
| `post-stall-v2`, progression and fit | 0.037 | 0.165 | 0 of 6 | **no developed spin** |
| Legacy blend with spanwise progression ([output](sweep-legacy-progression.md), [patch](legacy-progression-experiment.patch); disposable copy) | 0.282 | 0.618 | 4 of 6 | spins (α 21.4°, r 100°/s) |

- **Legacy blend.** Every strip separates at the same geometric angle onto the flat plate. The lift falls to 45–56 % of its peak, and the roll instability concentrates at 14–16° (+0.86…+1.11), where FASER is stable (−0.41). That spike is the mechanism behind the violent stall wing drop of the [D8b-R2 diagnosis](../README.md).
- **`faser-analog`.** [`make_analog.gd`](../../../../../research/flight-robustness/d8b-r2/analog/make_analog.gd) solves a uniform table until the whole-aircraft retention matches FASER.
  - **`post-stall-v2`.** [`make_v2.gd`](../../../../../research/flight-robustness/d8b-r2/analog/make_v2.gd) fits four non-increasing post-peak knots with full progression to both measured curves together. Unconstrained, the fit chases oscillating shapes in the digitized curve; the monotone constraint removes them.
  - **Shared result.** Both match the static lift and the stall-onset damping. In flight, the Stik with full pro-spin controls settles into a slowly rotating descent (V 12–15 m/s, under 60°/s) instead of a spin.
- **Spanwise progression on the legacy blend.** It cuts the onset instability peak to +0.50, spread over 14–20°, and lowers the damping error by 35 %. It keeps the spin, but it does not change the lift collapse.

## Spanwise stall progression (implemented, opt-in)

`aero.wing_polar.spanwise_progression` is an evidence quantity g ∈ [0, 1] in the [aircraft contract](../../../../../AIRCRAFT_CONTRACT.md).
- **Law:** strip i reads the tabulated polar at its angle times fᵢ = 1 + g·(λᵢ − 1). λᵢ is the strip's induced-map row sum over the mean, computed once at load from the calibrated map. A rectangular wing's root therefore separates first, and a tapered wing's tip.
  - Stik: root 1.11, tip 0.84.
  - Timber: root 1.08, tip 0.88.
  - Extra: tip 1.01.
  - P-51: tip 1.04.
- **Absent or g = 0:** the shared table is unchanged bit for bit. The trace metadata names the progression.
- **Tests:** 15 checks in [`test_wing_polar.gd`](../../../../../app/tests/test_wing_polar.gd). They cover:
  - g = 0 bit-identity over the angle range with rates;
  - factors that average 1 and equal the loading;
  - root-first separation;
  - symmetry, passivity, wake consistency and small-angle identity;
  - five validation rejections.
- It is the spanwise ingredient that any future table law needs.

## Conclusions

1. **Structural trade-off.** In the quasi-steady strip law, autorotation comes only from a negative local lift slope.
   - A table that holds measured post-stall lift removes it, and the Stik stops spinning.
   - A table that keeps it collapses the lift, as the legacy blend does, and the spin is too steep.
   - The FASER airframe has both: high static lift and a spin.
2. **Missing physics.** The forced-oscillation and rotary-balance data say what is missing: rate- and history-dependent separated flow. FASER's damping depends on frequency and rate above the stall, its rotary-balance moments depend on rotation rate, and its measured roll term contains Clβ̇.
   - The standard reduced-order form is a separation state per strip that relaxes to its static value with a time constant and an input lag (Goman and Khrabrov 1994).
   - At steady state it returns the static table exactly, so the measured lift is kept.
   - In motion it produces hysteresis and autorotation, the effect the strip law lacks.
3. **Next step (D8b-R2d-v3).**
   - First, a feasibility experiment in a disposable copy: per-strip separation states on the `faser-analog` table with progression.
   - Fit its two time constants to Hoe's measured frequency trend.
   - Then fly the held-out FASER and Extra 260 spins and the D8b-R2 pull-up matrix.
   - It adds simulation state, so it needs a kernel and layout review with the simulation-foundation boundary before integration.
4. **Production stays on the legacy blend.** Promotion of any law needs the [pull-up plan](../../../../UGLY-STIK-PULLUP-PLAN.md) gates, including the owner's flight (D8b-R2h). The CLI `--experimental-aircraft-data` route already accepts these candidates, `spanwise_progression` included.

## Reproduction

From the repository root, with the [pinned Godot](../../../../TOOLS.md#developer-setup) as `$GD` and the local references:

```bash
python3 -I research/flight-robustness/d8b-r2/analog/faser_cl.py
$GD --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/make_analog.gd" -- --check
$GD --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/make_v2.gd" -- --check
C=$PWD/research/flight-robustness/d8b-r2/candidates
$GD --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd" \
  -- res://data/aircraft/jensen_ugly_stik_60.json $C/retained.json $C/faser-analog.json $C/post-stall-v2.json
```

For the legacy-progression row, apply the patch to a disposable copy of `app/`.

## Limits

- FASER is another airframe with its own airfoil, Reynolds number and tail.
- The curves are digitized from figures.
- The measured damping includes a β̇ term and frequency effects that the model does not have.
- The negative branch and the post-stall drag are not measured.
- The static bench does not include propeller or slipstream effects.
