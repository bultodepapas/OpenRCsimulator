# D10-R4: developed spin and post-stall lift against measured RC data (2026-10-19)

**Status: investigation complete; no runtime or aircraft-data change.**

- The model's developed spin is steady and steeper than two measured RC spins.
- A measured Ultra Stick 120 whole-aircraft polar shows that the production post-stall lift loss is about twice too deep for this class. This is analog evidence for the open step D8b-R2d.
- Restoring the measured retention explains about a third of the spin's missing vertical force. It does not explain the low yaw rate, the low α or the large sideslip.

Sources and caveats: [RC-class aerodynamic data sources](../rc-aero-data-sources.md). Origin: [FT-03 finding 1](../../flight-test/FT-03/README.md#findings-for-the-owning-tracks).

## 1. The developed spin is steady, not cut short

The flight-test card averages its spin over 4.0–6.25 s, about three turns in, while airspeed still rises. [`long_spin.gd`](../../../../research/flight-dynamics/spin-post-stall/long_spin.gd) flies the same entry (trimmed at 1.2 Vs, then idle, full up and full rudder from 0.25 s) for 20 s. It reproduces the card window exactly: Extra right, α 23.3°, p 264, r 113°/s, θ −63°, sink 21.2 m/s. Then it settles by 6–10 s into a steady spin, with sink acceleration 0.00–0.04 m/s². Window means over 15–20 s ([tables and 4 Hz CSV](results/)):

| Case | α (°) | \|β\| (°) | V (m/s) | \|p\| (°/s) | \|r\| (°/s) | θ (°) | Ωb/2V | Sink (m/s) | Vertical-force coeff. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Extra 300S, right / left | 23.5 / 23.1 | 19.6 / 21.5 | 23.1 / 23.9 | 286 / 262 | 122 / 110 | −65 / −65 | 0.194 / 0.172 | 22.7 / 23.4 | 0.22 / 0.21 |
| Stik, right / left | 20.5 / 19.6 | 19.9 / 18.5 | 23.5 / 23.0 | 244 / 250 | 93 / 81 | −65 / −60 | 0.161 / 0.164 | 22.9 / 21.9 | 0.19 / 0.21 |
| Aero Testbed 35 % Extra 260, measured | ≈ 33–35 (from θ) | – | – | 235–238 | 150–155 | −55 … −57 | 0.20 | 15.5–16.8 | 0.74–0.86 |
| FASER Ultra Stick 120, measured (video-corrected) | 30 | 5 | 30.5 | > 200 | ≈ 160 | – | 0.14 | – | – |

The vertical-force coefficient is m(g − a_sink)/(½ρV_sink²S); in a steady spin it equals 2(W/S)g/(ρV_sink²). The Extra 260 airframe is a 35 % scale model at 13.0 kg/m², with low-rate throws of elevator ±14° and rudder ±29°. Our Extra 300S .60 has 7.1 kg/m² and its own throws, so only the dimensionless quantities compare directly. FASER's 30.5 m/s, scaled to the Stik's wing loading, is 22.3 m/s. That matches the model's 23 m/s, so the Stik-class reference does not show a vertical-force deficit: the large deficit appears against the aerobatic Extra 260. Both references show the same composition, which the model does not reproduce:
- a yaw rate of 150–160°/s against 81–122;
- α of about 30–35° against 20–24°;
- small sideslip (FASER 5°) against 19–22°.

## 2. Post-stall lift retention: the production law against a measured RC airframe

The NASA FASER airframe is a Hangar 9 Ultra Stick 120: high wing, slab-sided, AR 4.78, the closest documented relative of the Jensen. Its static whole-aircraft wind-tunnel lift curve (Owens, Cox, Morelli 2006, Fig. 2a) runs from −5° to 30°.

[`faser_cl.py`](../../../../research/flight-robustness/d8b-r2/analog/faser_cl.py) digitizes it reproducibly:
- It checks the local PDF's SHA-256 against the source manifest.
- It renders the page at 400 dpi and calibrates the axes from the detected frame and axis lines.
- It takes the median of the curve's pixels at each degree.

The uncertainty is about ±0.2° and ±0.015 CL ([CSV](../../../../research/flight-robustness/d8b-r2/analog/faser_cl.csv)). The result is CL(0) 0.053 and lift slope 0.0736/deg; Ritchie's 2013 fit of the same tunnel data gives 0.0762. There is a minor break at 11–13°, CLmax 0.937 at 15°, then a plateau of 0.83–0.88 to 30°.

The Stik rows below are the committed whole-aircraft totals of the [D8b-R2 candidate screen](../../flight-robustness/D8b-R2/implementation/candidate-screen.json) at 25 m/s with controls neutral. D10-R2 changed only sideslip terms, so lift at β = 0 is unchanged. The cells are CL(α)/CLmax, which removes the airfoil and CLmax differences between the airframes ([table](results/faser-retention.md)):

| Polar | CLmax | 15° | 16° | 17° | 18° | 20° | 22° | 25° | 28° | 30° |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FASER, measured (analog) | 0.937 | 1.00 | 0.99 | 0.95 | 0.94 | 0.91 | 0.89 | 0.89 | 0.91 | 0.94 |
| Stik legacy (production) | 1.105 | 0.83 | 0.68 | 0.53 | 0.45 | 0.46 | 0.47 | 0.50 | 0.54 | 0.56 |
| Stik `steep` fixture | 1.160 | 1.00 | 0.98 | 0.95 | 0.90 | 0.78 | 0.64 | 0.53 | 0.54 | 0.55 |
| Stik `intermediate` fixture | 1.163 | 1.00 | 1.00 | 0.98 | 0.96 | 0.90 | 0.81 | 0.72 | 0.69 | 0.68 |
| Stik `retained` fixture | 1.182 | 0.99 | 0.99 | 1.00 | 1.00 | 0.99 | 0.95 | 0.89 | 0.84 | 0.82 |

- **Legacy blend:** it keeps 45–56 % of its peak between 18° and 30°; the measured RC airframe keeps 89–94 %.
- **Fixtures:** `retained` is the only one within 0.1 of the measurement to 28°; `intermediate` falls below from 22° and `steep` from 20°.
- **Caveats:** this is a static, analog airframe at its own Reynolds number, about 3.6·10⁵ on its chord at 2 psf. It bounds the post-stall shape for a Stik-class airplane; it is not a Jensen measurement.

This is the kind of evidence the [polar method](../../flight-robustness/D8b-R2/implementation/polar-method.md) asks for before a production polar is selected: matched data, or defensible bounds.

## 3. Held-out spin with the candidates

The spin was not used to choose anything. The same probe flies the Stik with each D8b-R2 fixture (15–20 s, right spin unless noted):

| Polar | α (°) | \|β\| (°) | \|r\| (°/s) | θ (°) | Sink (m/s) | Vertical-force coeff. |
| --- | --- | --- | --- | --- | --- | --- |
| Legacy | 20.5 | 19.9 | 93 | −65 | 22.9 | 0.19 |
| `steep` | 24.8 | 29.4 | 114 | −57 | 20.3 | 0.24 |
| `intermediate` | 25.3 | 26.4 | 120 | −61 | 19.6 | 0.26 |
| `retained` (left) | 20.9 (22.4) | 16.3 (17.2) | 88 (104) | −55 (−65) | 17.5 (19.0) | 0.32 (0.27) |

With `retained`, the right spin's nose rises to the Extra 260's −55°, sink falls by 5.4 m/s and the vertical force rises by 70 %; the left spin improves less. No fixture moves α toward 30°, cuts β toward 5° or raises r toward 150–160°/s. The fixtures that raise yaw do so with even more sideslip.

## 4. Reading and next steps

- **Two separate defects.** The post-stall lift collapse is one; it is directly contradicted by measured data for this airframe class. The spin's composition (low yaw, low α, large sideslip) is another, which the wing polar does not touch.
  - Its likely owner is the side force and yaw of the fuselage and fin at large sideslip. This is the same missing fuselage side force that keeps the knife-edge short ([D10-R2 evidence, section 7](../stik-lateral-directional-2026-10-18/README.md#7-knife-edge-the-ft-batterys-finding-measured-in-flight)).
  - FASER's Fig. 2b shows the directional characteristics changing through stall: Cnβ near zero at α 17–20°, then rising, and Clβ about five times larger at 25° than at 0°. That makes the high-α lateral terms a candidate.
- **D8b-R2d.** The measured retention supports a `retained`-like post-stall shape for the Stik class and rules out the legacy depth as a realistic bound.
  - Promotion still needs what the [pull-up plan](../../../UGLY-STIK-PULLUP-PLAN.md) lists: a candidate built from supported knots with stated bounds, re-running the D8b-R2 matrix and handling checks, held-out maneuvers, and the owner's flight review (D8b-R2h).
  - Normal flights keep the legacy blend.
- **Measurements that would close it.** A filmed spin of the owner's Jensen Stik with a stopwatch: turns, height lost per turn and nose attitude. Each closes a quantity in this report without new tooling.

## Reproduction

From the repository root, with the [pinned Godot](../../../TOOLS.md#developer-setup) as `$GD`:

```bash
python3 -I research/flight-robustness/d8b-r2/analog/faser_cl.py      # needs references/rc-aero-data/ (local)
$GD --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/spin-post-stall/long_spin.gd" \
  -- --aircraft=jensen-das-ugly-stik-60 --hold=20 [--side=-1] [--data=$PWD/research/flight-robustness/d8b-r2/candidates/retained.json]
```

The probe is deterministic: repeated runs reproduce every table digit.

## Limits

- The references are other airframes with their own throws, inertias and Reynolds numbers.
- The FASER spin is a video-corrected estimate with a saturated roll gyro.
- The FASER polar is static and digitized from a figure.
- The probe holds full controls with the propeller at idle and no wind.
- The fixtures are synthetic sensitivity models, not calibrated candidates.
