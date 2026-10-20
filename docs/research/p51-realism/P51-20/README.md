# P51-20: planform-specific ground effect for the P-51

2026-10-14 · Revision 1 · **Status: implemented and software-verified; flare/liftoff acceptance against a pilot or video remains open.** Prefix: P51-20. [Plan](../../../P51-PLAN.md) · [Tools](../../../../research/p51/p51-20/README.md)

## Finding

The P-51 did not declare the shared [M5-GE-1 ground-effect module](../../ground-effect/M5-GE-1/README.md); only the Stik family did. With its low wing, the P-51 needs it more. The aero reference point sits 0.34 m above the main-wheel contact in a level attitude (h/b 0.121), against 0.215 for the Stik. Its stabilizer is 0.26 m above the wing and 1.28 m behind it, while the Stik's tail sits slightly below its wing. The Stik's constants are fitted to that geometry, so they cannot simply be copied.

## Method

[`ground_effect_vlm.py`](../../../../research/p51/p51-20/ground_effect_vlm.py) models this wing as an image-method Weissinger vortex lattice: 80 cosine-spaced panels, taper 0.46, 5° dihedral, 1.88° washout and the swept leading edge, from `geometry.json`. The ground is a mirror plane parallel to the free stream. In free air the lattice gives CLα 4.51/rad (Helmbold with a 2π section: 4.48), Trefftz e 1.00, and tail dε/dCL 0.121 rad (the generator's elliptic estimate is 0.110). It fits the module's faded law, exactly as `GroundEffect.law()` evaluates it, against x = ARP height / span over 0.06–1.5.

| x = h/b | 0.10 | 0.12 (wheels) | 0.20 | 0.50 | 1.00 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Induced drag at the same CL, VLM | 0.585 | 0.626 | 0.745 | 0.915 | 0.973 |
| Tail downwash per unit lift, VLM | 0.574 | 0.618 | 0.754 | 0.934 | 0.982 |
| Lift at the same α, VLM | 1.246 | 1.193 | 1.097 | 1.024 | 1.007 |
| Raymer 33x^1.5 (Stik induced law, faded) | | 0.58 | | | |
| Stik tail law 25x² (faded) | | 0.27 | | | |

The fits are: induced c 15.34, e 1.027 (RMS 0.010); tail c 19.59, e 1.145 (RMS 0.015). Copying the Stik constants would have overstated the P-51's tail-downwash relief by about 2.3× on the wheels; the induced reduction is also weaker than Raymer's flat-wing form, partly because the 5° dihedral raises the outer wing. The generator writes the four constants into `aero.ground_effect` with their source. No other value changes.

## Runtime evidence

[`ge_probe.gd`](../../../../research/p51/p51-20/ge_probe.gd) ([output](ge-probe-candidate.txt)) holds the 1.3 Vs approach trim (20.4 m/s, α 6.8°, CL 0.59) at fixed α while the CG descends:

| CG height | σ mean / tail | L/L∞ | D/D∞ | ΔCm (elevator equivalent) |
| --- | --- | ---: | ---: | --- |
| 4.0 m | 0.990 / 0.992 | 1.003 | 0.999 | −0.0002 (0.01° up) |
| 1.0 m | 0.840 / 0.854 | 1.052 | 0.977 | −0.0058 (0.37° up) |
| 0.5 m | 0.685 / 0.688 | 1.105 | 0.946 | −0.0151 (0.96° up) |
| 0.439 m (on the wheels) | 0.647 / 0.647 | 1.118 | 0.937 | −0.0177 (1.13° up) |

At the same lift on the wheels, α falls from 6.78° to 5.95° and total drag drops 11.5 %. The runtime σ follows the VLM within 0.03. The lift gain is smaller than the VLM's +19 %, because the shared law reduces only the induced angle and has no bound-vortex image, as documented for M5-GE-1.

Flight comparisons ran in a clean worktree at `6a7c624d` (which contains P51-19); only the P-51 JSON and Workshop descriptor were swapped ([identity](identity.txt), [summary](compare-240.md)):

- All 34 airborne probe cases end with **identical** metrics. The module is exactly inactive above its 7.05 m reach.
- Heading-hold takeoff: lift-off 4.554 → 4.517 s, 49.9 → 49.1 m, 25.29 → 25.17 m/s. Unguided: 63.7 → 63.3 m.
- Approach and flare: touchdown sink 0.860 → 0.809 m/s at 19.84 → 19.96 m/s. Contact-path distance 118 → 140 m after the first contact. In `test_p51_ground`, rollout grows from 154 to 170 m past touchdown with no brakes.
- 240 → 480 Hz: every takeoff and landing event agrees within 0.51 %.
- `test_ground_effect` (50), `test_aircraft_data` (87) and `test_trim` (14) pass. No P-51 check changes status. The three P-51 failures present at `HEAD` remain ([logs](tests/)).

## Pre-existing failure explained

`test_p51_handling`'s "inside loop at 0.7 stick" fails at `HEAD` with or without this step. A trace shows that it is not a loop. At 0.75 s the pull reaches α 17.7°, an accelerated stall at about 2.9 g from 1.7 Vs. The airplane snap-rolls left (p up to −5 rad/s), autorotates and spirals into the ground by 7.5 s. Ground effect only touches the last metres, which is why the integrated pitch shifts from 347° to 343°. A left wing drop under a hard power-on pull is typical Mustang behaviour. The test expects a clean loop with no pilot roll correction or α limit, so the scenario, or the propwash changes that alter it, belong to the test owner and the physics-audit track.

## Limits

- The VLM has no fuselage, no rolled-up wake, and no viscous or separated flow. The runtime law ignores dihedral in the strip heights (the fit absorbs it at level attitude) and leaves the slipstream tail increment unchanged.
- Strip heights follow the attitude, including the 13.9° three-point pitch and bank. The tail factor, however, uses the wing's mean height rather than the stabilizer's own distance from the ground.
- Software evidence only. Whether the float and nose-down trim change match a real 1/4-scale P-51 needs flare traces from a pilot or video.
