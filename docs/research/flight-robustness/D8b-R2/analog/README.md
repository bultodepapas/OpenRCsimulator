# D8b-R2d: post-stall wing law against a measured Stik-class airframe (2026-10-19)

**Status: analog evidence and test bench delivered; no production polar selected.**

- The legacy law fails both measured post-stall constraints of the NASA FASER (Ultra Stick 120).
- Every tested candidate fails at least one.
- The measurements also show which structure a passing law needs.

Owning step: D8b-R2d in the [pull-up plan](../../../../UGLY-STIK-PULLUP-PLAN.md); method: [polar method review](../implementation/polar-method.md). Sources and caveats: [RC-class aerodynamic data sources](../../../flight-dynamics/rc-aero-data-sources.md).

## Measured targets

FASER is a Hangar 9 Ultra Stick 120: high wing, slab-sided, AR 4.78, the closest documented relative of the Jensen. [`faser_cl.py`](../../../../../research/flight-robustness/d8b-r2/analog/faser_cl.py) digitizes two of its wind-tunnel curves reproducibly. It checks each local PDF's SHA-256 against the source manifest and calibrates from the plots' own frame or grid lines.

| Curve | Source | Result | Uncertainty |
| --- | --- | --- | --- |
| Static whole-aircraft CL, −4…30° ([CSV](../../../../../research/flight-robustness/d8b-r2/analog/faser_cl.csv)) | Owens, Cox, Morelli 2006, Fig. 2a (q 2 psf, Re ≈ 3.6·10⁵) | Slope 0.0736/deg, CLmax 0.937 at 15°; after the stall CL keeps 0.89–0.94 of CLmax to 30° | ±0.2°, ±0.015 |
| Roll damping C̄lp, −5…40° ([CSV](../../../../../research/flight-robustness/d8b-r2/analog/faser_clp.csv)) | Hoe, Owens, Denham 2012, Fig. 14, forced oscillation, k 0.255 | −0.41…−0.45 to 13.5°, still −0.31 at 17.5° (stable for about 5° past the stall), 0 at 20°, +0.08 at 25–30°, +0.19 at 35° | ±0.3°, ±0.01 |

Hoe's Figs. 16 and 18 show the post-stall damping becoming *more* unstable at lower frequency and smaller rate amplitude. At 0.25 Hz it is +0.06 at 20° and +0.21 at 35°; at the smallest rate it is +0.45 at 35°. A quasi-steady linear model (k → 0, p → 0) should therefore be at least as unstable as the C̄lp row from 20° to 35°.

The FASER flight spin, at α 30° and β 5°, sits inside that band ([D10-R4](../../../flight-dynamics/spin-post-stall-2026-10-19/README.md)).

## Bench

[`post_stall_sweep.gd`](../../../../../research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd) scores any aircraft JSON or candidate against both curves.
- **Method:** static whole-aircraft loads at 25 m/s, controls neutral, every 0.5°. Clp comes from dMx/dp at p = 0.
- **Metrics:**
  - RMS error of the retention CL/CLmax, aligned at the two lift peaks, over 15–30°;
  - RMS error of Clp over 10–35°;
  - the number of unstable Clp values below 17.5°;
  - Clp at 20, 25, 30 and 35°.

## Results

Production law ([output](sweep-production-law.md)):

| Data | CLmax at α | RMS retention error | RMS Clp error | Unstable below 17.5° | Clp at 20 / 25 / 30 / 35° |
| --- | --- | --- | --- | --- | --- |
| FASER, measured | 0.937 at 15.0° | – | – | 0 of 4 | +0.00 / +0.08 / +0.08 / +0.19 |
| Stik legacy blend (production) | 1.094 at 12.5° | 0.327 | 0.697 | 3 of 4 | −0.23 / −0.24 / −0.25 / −0.27 |
| `steep` fixture | 1.107 at 13.0° | 0.384 | 0.541 | 2 of 4 | +0.41 / −0.20 / −0.32 / −0.38 |
| `intermediate` fixture | 1.107 at 13.0° | 0.272 | 0.426 | 2 of 4 | +0.14 / −0.12 / −0.25 / −0.32 |
| `retained` fixture | 1.107 at 13.0° | 0.160 | 0.351 | 2 of 4 | −0.10 / −0.13 / −0.19 / −0.23 |
| `faser-analog` candidate | 1.085 at 13.5° | **0.022** | 0.280 | **0 of 4** | −0.18 / −0.23 / −0.24 / −0.21 |

- **Legacy blend:** every strip stalls at the same geometric angle. The roll instability is therefore concentrated in a band about 10 times the measured magnitude, +0.86…+1.11 at 14–16°, just where FASER is still stable. Beyond 18° the flat-plate branch is stable, the wrong sign against the measurement.
  - This explains two findings: the violent stall wing drop of the [D8b-R2 diagnosis](../README.md), and the steep, low-α spin of [D10-R4](../../../flight-dynamics/spin-post-stall-2026-10-19/README.md), whose autorotation exists only in that narrow band.
- **`faser-analog`:** [`make_analog.gd`](../../../../../research/flight-robustness/d8b-r2/analog/make_analog.gd) builds it with the fixture recipe, but its post-peak lift knots are solved until the whole-aircraft retention matches FASER (within 0.002 at the knots); beyond the last measured angle it continues by Viterna; `--check` verifies it.
  - It meets the static curve and removes the early instability.
  - Its deep stall is stable, so on the held-out [long-spin probe](../../../flight-dynamics/spin-post-stall-2026-10-19/README.md#3-held-out-spin-with-the-candidates) the Stik cycles through wing drops without a developed spin. The FASER airframe does spin with those inputs, so the candidate fails the held-out maneuver.

Spanwise stall progression ([patch](spanwise-progression-experiment.patch), [output](sweep-spanwise-progression.md)). In a disposable copy, each strip's separation angle was scaled by its attached loading relative to the wing mean, λᵢ = Rᵢ/mean(R). Rᵢ is the induced-map row sum the model already derives, so the change is explicit, has no iteration and needs no new data.
- **λᵢ by planform:**
  - rectangular Stik: root 1.11, tip 0.84, so the root stalls first;
  - Timber: root 1.08, tip 0.88;
  - tapered Extra: root 0.96, tip 1.01;
  - tapered P-51: root 0.95, tip 1.04, so the tip stalls first.

| Data, with progression | CLmax at α | RMS retention error | RMS Clp error | Unstable below 17.5° | Clp at 20 / 25 / 30 / 35° |
| --- | --- | --- | --- | --- | --- |
| Stik legacy blend | 1.035 at 12.0° | 0.282 | 0.498 | 3 of 4 | +0.16 / −0.24 / −0.25 / −0.27 |
| `retained` fixture | 1.079 at 13.0° | 0.140 | **0.271** | 1 of 4 | −0.07 / −0.12 / −0.16 / −0.19 |
| `faser-analog`, refitted with progression | 1.078 at 13.0° | **0.006** | 0.320 | 0 of 4 | −0.47 / +0.16 / −0.29 / −0.23 |

Progression halves the legacy instability peak and spreads it over 14–20°, cutting the Clp error by about 30 %. It does not raise the post-stall lift, because every stalled strip still falls to the flat plate, 0.46 at 25° against FASER's 0.835.

## Conclusions for D8b-R2d

1. **Structure.** No tested quasi-steady variant has a mildly unstable deep stall (20–35°) together with the measured static plateau.
   - Strip roll damping follows the wing's local lift slope. The measured combination therefore implies a wing whose section slope is slightly negative after the stall.
   - The whole-aircraft plateau then comes from that wing plus the positive high-α lift of tail and fuselage. NACA TN 3551 measured the fuselage part at about 0.75 sin²α per plan area for a square body.
   - Spanwise progression, as tested here, spreads the stall onset the way the planform dictates.
2. **Next candidate.** Each strip carries a section table with a mildly negative post-stall slope, plus spanwise progression, plus fuselage crossflow lift.
   - Score it on this bench against both curves first.
   - Then fly the held-out long spin (FASER α 30°, β 5°; Extra 260 θ −55°) and the D8b-R2 pull-up matrix.
   - Then the owner's A/B flight (D8b-R2h) through the existing `--experimental-aircraft-data` route.
3. **Production stays on the legacy blend.** Its failures are documented, but every candidate so far fails at least one measured constraint or the held-out spin.

## Reproduction

From the repository root, with the [pinned Godot](../../../../TOOLS.md#developer-setup) as `$GD` and the local references:

```bash
python3 -I research/flight-robustness/d8b-r2/analog/faser_cl.py
$GD --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/make_analog.gd" -- --check
C=$PWD/research/flight-robustness/d8b-r2/candidates
$GD --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd" \
  -- res://data/aircraft/jensen_ugly_stik_60.json $C/steep.json $C/intermediate.json $C/retained.json $C/faser-analog.json
```

For the progression rows, apply the patch to a disposable copy of `app/`. In that copy, regenerate `faser-analog` with `make_analog.gd` before running the sweep.

## Limits

- FASER is another airframe with its own airfoil, Reynolds number and tail.
- The curves are digitized from figures.
- The damping is a finite-frequency measurement, against which a quasi-steady model is compared.
- The negative branch and the post-stall drag are not measured.
- The static bench does not include propeller or slipstream effects.
