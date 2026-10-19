# D10-R4: developed spin and post-stall lift against measured RC data (2026-10-19)

**Status: investigation complete; no runtime or aircraft-data change.**

- The model's developed spin is steady and steeper than two measured RC spins.
- Measured Ultra Stick 120 curves show that the production post-stall law loses about twice too much lift and has the wrong roll-damping sign in deep stall. This is analog evidence for the open step D8b-R2d.
- The narrow autorotation band explains the spin's low α. No tested candidate meets both measured curves and the held-out spin.

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

## 2. Post-stall lift and roll damping against a measured RC airframe

The NASA FASER airframe (Hangar 9 Ultra Stick 120) has two measured wind-tunnel curves that bound the post-stall law of a Stik-class airplane: static whole-aircraft lift, and forced-oscillation roll damping. Their digitization, the scoring bench and every candidate result live in the [D8b-R2d analog evidence](../../flight-robustness/D8b-R2/analog/README.md). In short:
- **Lift.** The production legacy blend keeps 45–56 % of its peak lift between 18° and 30°; FASER keeps 89–94 %.
- **Roll damping.** The legacy blend concentrates its roll instability at 14–16°, about 10 times the measured magnitude, where FASER is still stable. From 18° up it is stable. FASER is mildly unstable from 20° to 35°, and more so at lower frequency.

## 3. Held-out spin with the candidates

The spin was not used to choose anything. The same probe flies the Stik with each D8b-R2 fixture (15–20 s, right spin unless noted):

| Polar | α (°) | \|β\| (°) | \|r\| (°/s) | θ (°) | Sink (m/s) | Vertical-force coeff. |
| --- | --- | --- | --- | --- | --- | --- |
| Legacy | 20.5 | 19.9 | 93 | −65 | 22.9 | 0.19 |
| `steep` | 24.8 | 29.4 | 114 | −57 | 20.3 | 0.24 |
| `intermediate` | 25.3 | 26.4 | 120 | −61 | 19.6 | 0.26 |
| `retained` (left) | 20.9 (22.4) | 16.3 (17.2) | 88 (104) | −55 (−65) | 17.5 (19.0) | 0.32 (0.27) |
| `faser-analog` (left) | 17.9 (17.9) | 15.1 (14.8) | 42 (27) | −30 (−24) | 6.2 (5.3) | – (no developed spin) |

With `retained`, the right spin's nose rises to the Extra 260's −55°, sink falls by 5.4 m/s and the vertical force rises by 70 %; the left spin improves less. No fixture moves α toward 30°, cuts β toward 5° or raises r toward 150–160°/s. The fixtures that raise yaw do so with even more sideslip. The `faser-analog` candidate matches the static lift curve but makes the deep stall stable in roll. The Stik then only cycles through wing drops (bank up to 110°, nose −70…−87°, back to near level every 3–4 s) without a developed spin, while the FASER airframe spins with these inputs.

## 4. Reading and next steps

- **Mechanism.** The model's autorotation, its roll instability, exists only in a narrow band just past the stall (14–20°). So the developed spin settles at α ≈ 20°, steep and roll-dominated.
  - FASER's measured roll damping is mildly unstable from 20° to 35°, and its spin sits there at α 30°.
  - The lift collapse explains part of the missing vertical force; the roll damping sign in deep stall explains the low α.
  - A fuselage side force is not the main lever here: NACA TN 3551 measures it at about CY 0.015 at 20° for a Stik-like square body.
- **Next.** The candidate law that the [D8b-R2d analog evidence](../../flight-robustness/D8b-R2/analog/README.md#conclusions-for-d8b-r2d) describes should be scored on both measured curves first, then flown on this probe.
  - The law has section tables with a mildly negative post-stall slope, spanwise stall progression and fuselage crossflow lift.
  - Promotion still needs the [pull-up plan](../../../UGLY-STIK-PULLUP-PLAN.md)'s gates, including the owner's flight review (D8b-R2h). Normal flights keep the legacy blend.
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
