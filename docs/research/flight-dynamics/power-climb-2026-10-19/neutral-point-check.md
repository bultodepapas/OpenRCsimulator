# Fleet neutral-point check (2026-10-19)

This applies the D6e-R1 geometric neutral-point (NP) estimate to the five catalog airframes and compares it with the NP that each data file's pitch coefficients imply. It is research only: no file under `app/` or `research/` was changed.

- **Script:** `tmp/fleet_neutral_point.py` (read-only). Run it with `python3 tmp/fleet_neutral_point.py`.
- **Data:** the `app/data/aircraft/*.json` files at HEAD `12c2ac31`. They have no uncommitted changes, and the last commit to touch them was `be97a75a`.
- **Units:** positions are in metres, in each file's le frame (`x` aft of the wing root leading edge). Slopes are per radian. Margins are in % of `reference.mean_chord` (c_ref = S/b), not % MAC; the generators' own reports use % MAC, so a % MAC column is given for cross-checking.

## Result

"Wet" is the CG the loader actually flies: `cg_le = cg_inv`, the authored inventory CG including its fuel item (`app/physics/aircraft_data.gd:474`). "Dry" is `balance.plan_cg`, the empty-tank balance point. Finite-fuel sessions move the CG from wet toward dry as fuel burns.

| Aircraft | c_ref (m) | CLa (1/rad) | Cma (1/rad) | Cmq (1/rad) | x_arp (m) | x_cg wet (m) | x_cg dry (m) | NP data (m) | SM data wet / dry (% c_ref) | NP geo (m) | SM geo wet / dry (% c_ref) | NP data − geo |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik 60 | 0.3048 | 4.580 | −0.723 | −8.082 | 0.0844 | 0.1094 | 0.1209 | 0.1325 | +7.6 / +3.8 | 0.1365 (0.1325*) | +8.9 / +5.1 (+7.6 / +3.8*) | −4.0 mm (0.0*) |
| Timber | 0.2103 | 4.817 | −1.409 | −12.669 | 0.0532 | 0.0600 | 0.0600 | 0.1147 | +26.0 / +26.0 | 0.1077 | +22.7 / +22.7 | +7.1 mm (+3.4 % c) |
| Extra 300S | 0.2953 | 4.451 | −0.906 | −9.380 | 0.0868 | 0.0966 | 0.1088 | 0.1469 | +17.0 / +12.9 | 0.1468 | +17.0 / +12.9 | +0.1 mm (0.0 % c) |
| Avanti S | 0.3511 | 4.629 | −0.851 | −7.751 | 0.2063 | 0.2304 | 0.2400 | 0.2709 | +11.5 / +8.8 | 0.2410 | +3.0 / +0.3 | +29.9 mm (+8.5 % c) |
| P-51D | 0.4867 | 4.338 | −0.896 | −8.402 | 0.1139 | 0.1721 | 0.1778 | 0.2144 | +8.7 / +7.5 | 0.2487 | +15.7 / +14.6 | −34.3 mm (−7.0 % c) |

\* For the Stik, the starred values use D6e-R1's recomputed Helmbold tail slope, 1.632 instead of the file's 1.75.

**Method check.** With D6e-R1's own recipe, my code puts the Stik NP at 0.13253 m. The data's NP is 0.13252 m, which is 43.5 % c and matches `derive_pitch_reference.py`. The planar margin at the wet CG is 7.6 %. The published 6.9 % comes from central differences of the complete runtime loads (`root-cause-correction.json`: `static_margin` 0.06857, CLa 4.595). Those loads include the 7 cm ARP height and propulsion terms, which the planar formula omits. I did not decompose the 0.7-point gap. D6e-R1's "3.8 % before the height term" is the same planar NP measured at the dry plan CG.

## Formulas

Data margin:

    x_np,data = x_arp − (Cma/CLa)·c_ref
    SM_data   = −Cma/CLa + (x_arp − x_cg)/c_ref

Geometric NP (the D6e-R1 recipe, `research/flight-dynamics/climb-trim/derive_pitch_reference.py:44-56`):

    CLa_w   = 2π·AR / (2 + √((AR/κ)² + 4)),   κ = 0.9, AR = b²/S          (Helmbold, no sweep or dihedral corrections)
    a_t     = horizontal.lift_slope                                    (assumed already = a_h·η_h·(1 − dε/dα), η_h = 0.9)
    Cma_f   = K_f·W²·L / (MAC·S) · 180/π,   K_f = 0.008 /deg           (Raymer eq. 16.25, Fig. 16.14)
    x_ac,wb = x_ac,w − (Cma_f/CLa_w)·MAC
    CLa_geo = CLa_w + a_t·Sh/S
    x_np,geo = x_ac,wb + a_t·(Sh/S)·(x_h − x_ac,wb) / CLa_geo
    SM_geo  = (x_np,geo − x_cg)/c_ref

Inputs per aircraft:

- **Wing aerodynamic centre `x_ac,w`:** 25 % of the MAC behind the MAC leading edge, which is where every generator states it. For the rectangular Stik and Timber this is 25 % of the chord from the LE. For the tapered Extra and P-51 and the swept Avanti, the MAC LE lies aft of the root LE.
- **Fuselage length L and width W:** as each generator measures them. W is twice the maximum half-width of the fuselage stations. L runs from the spinner tip to the tail post (Stik: crash-hull spinner to tail end; Avanti: nose to tail cone).
- **`x_h`:** `aero.surfaces.horizontal.position[0]`.

## Inputs and intermediate values

| Aircraft | S (m²) | b (m) | AR | MAC (m) | MAC LE (m) | x_ac,w (m) | CLa_w Helmbold / file split (1/rad) | Sh (m²) | x_h (m) | a_t file | a_h free implied | dε/dα | V_h | W × L (m) | root c/4 at % body | Cma_f (1/rad, MAC) | dx_f (mm) | x_ac,wb (m) | CLa geo |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik 60 | 0.4645 | 1.5240 | 5.00 | 0.3048 | 0.0000 | 0.0762 | 3.974 / 4.220 | 0.0956 | 0.8409 | 1.750 | 3.58 | 0.457 | 0.516 | 0.104 × 1.320 | 31 | 0.046 | 3.6 | 0.0726 | 4.335 |
| Timber | 0.3270 | 1.5550 | 7.39 | 0.2129 | 0.0000 | 0.0532 | 4.443 / 4.329 | 0.0757 | 0.6598 | 2.110 | 3.74 | 0.373 | 0.660 | 0.139 × 1.029 | 33 | 0.131 | 6.3 | 0.0470 | 4.932 |
| Extra 300S | 0.4800 | 1.6256 | 5.51 | 0.3056 | 0.0172 | 0.0936 | 4.101 / 4.094 | 0.0994 | 0.8378 | 1.720 | 3.63 | 0.473 | 0.505 | 0.152 × 1.254 | 34 | 0.091 | 6.8 | 0.0868 | 4.457 |
| Avanti S | 0.7023 | 2.0000 | 5.70 | 0.3625 | 0.1183 | 0.2089 | 4.143 / 4.236 | 0.1648 | 0.9679 | 1.672 | 3.78 | 0.509 | 0.491 | 0.324 × 2.220 | 57 | 0.420 | 36.7 | 0.1722 | 4.536 |
| P-51D | 1.3725 | 2.8200 | 5.79 | 0.5088 | 0.0404 | 0.1676 | 4.165 / 3.996 | 0.2542 | 1.3913 | 1.843 | 3.65 | 0.439 | 0.445 | 0.259 × 2.323 | 36 | 0.103 | 12.5 | 0.1551 | 4.506 |

Notes on the columns:

- **CLa_w file split** = file CLa − a_t·Sh/S.
- **a_h free implied** = a_t / (0.9·(1 − dε/dα)). It is 3.6–3.8 /rad for every airframe, consistent with a Helmbold tail of aspect ratio 3.3–4.5.
- **V_h** = Sh·(x_h − x_ac,w)/(S·MAC).

## Sensitivities (NP in m, le frame)

| Aircraft | No fuselage term | K_f ×0.7 / ×1.3 | Wing CLa from the file split | Helmbold tail slope (a_t) | Wing ac at 0.25·c_ref from the origin | NP data / geo (% MAC) | CLq | Cmq about the CG in the oracle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik 60 | 0.1397 | 0.1375 / 0.1355 | 0.1332 | 0.1325 (1.632) | 0.1365 | 43.5 / 44.8 | 2.357 | −7.889 |
| Timber | 0.1133 | 0.1094 / 0.1060 | 0.1090 | 0.1099 (2.195) | 0.1071 | 53.9 / 50.6 | 4.442 | −12.526 |
| Extra 300S | 0.1530 | 0.1487 / 0.1450 | 0.1469 | 0.1468 (1.720) | 0.1287 | 42.5 / 42.4 | 5.644 | −9.193 |
| Avanti S | 0.2745 | 0.2511 / 0.2309 | 0.2404 | 0.2417 (1.691) | 0.1304 | 42.1 / 33.9 | 6.060 | −7.336 |
| P-51D | 0.2603 | 0.2522 / 0.2452 | 0.2518 | 0.2487 (1.843) | 0.2063 | 34.2 / 40.9 | 5.357 | −7.761 |

The column with the wing ac at 0.25·c_ref from the origin shows why the generator-stated ac must be used for tapered and swept wings. It would move the NP 18 mm forward on the Extra, 43 mm on the P-51 and 111 mm on the Avanti.

## Cause per aircraft (generator quotes)

**Ugly Stik 60: consistent by construction. Category (c), a borrowed coefficient, corrected through (a), the reference-point convention.**

`Cma` −0.723 and `CLa` 4.58 are borrowed from the UltraStick 25e. D6e-R1 places the ARP so that their ratio lands on the Stik's own NP:

- `derive_pitch_reference.py:51` `x_ac = 0.25 * c - cma_fus / cla_w * c`
- `:53` `x_np = x_ac - cma_ac / cla * c`
- `:56` `"arp_x": x_np - donor_margin * c`

The only residual (4 mm, 1.3 % c) comes from the tail slope. The file's provisional 1.75 /rad is used in my primary estimate, while D6e-R1 recomputed 1.632 /rad.

**Timber: data NP 7.1 mm (3.4 % c) aft of the geometric NP. Category (b): the generator has no fuselage term.**

TT-07 takes the tail-only moment about the bare wing quarter chord:

- `research/timber/tt07/derive_physics.py:117` `xarp = gv("wing","le_z") + 0.25*gv("wing","mac")`
- `:140` `lh, lv = xh-xarp, xv-xarp`
- `:159` `Cma=-ah*sh/s*lh/c`

Without the fuselage term my NP is 0.1133 m, against 0.1147 m in the data. The remaining 1.4 mm comes from TT-07's Helmbold variant `2 * math.pi * kappa * ar / (2 + math.sqrt(4 + ar * ar))` (`:43-44`), which gives CLa_w 4.33 rather than 4.44. With the file's wing slope and the Raymer term the NP is 0.1090 m. So the omitted fuselage term is worth 5.8 mm, or 2.7 % c. The cowl is 0.139 m wide, which makes that term larger than on the Stik. Both the data and geometric margins are very large: 26 % and 23 %, from a 0.66 tail volume.

**Extra 300S: consistent (0.1 mm). Category (d), but the generator's method is this method.**

`research/extra-300/ex05/derive_physics.py`:

- `:204` `K_f = ... 0.008`
- `:205` `cma_f_mac = K_f * fus_w ** 2 * fus_len / (mac * S) * 180 / math.pi`
- `:208` `x_arp = ... x_ac_w - dx_f`
- `:211` `Cma = -slope_h * Sh / S * l_h / c_ref`

D6e-R1 copied this recipe, so agreement is expected. It confirms that my independent arithmetic reproduces the file.

**Avanti S: data NP 29.9 mm (8.5 % c) aft of the geometric NP. Category (d): an NP anchor in the generator.**

The generator's own textbook NP, using Munk-Multhopp with Biot-Savart upwash, is 0.2404 m, or 33.7 % MAC. My Raymer estimate is 0.2410 m; the two fuselage terms happen to agree (Cma_f 0.418 against 0.420). The generator then overrides that result:

- `research/avanti-s/av06/derive_physics.py:346` `np_target = anchor["cg"] + anchor["static_margin"] * mac`
- `:347` `x_np_adopted = max(np_tb, np_target)`
- `:348` `x_arp = (x_np_adopted - r_t * xh_ac) / (1 - r_t)`

The anchor input reads: "the manual's aft-most CG (260 mm, 3D unlimited) taken as near-neutral, 3 % MAC". The derivation report (`derivation.md:67`) records the ARP "shifted +33.2 mm from the textbook value to meet the anchor (+9.2 % MAC)". The anchored NP of 0.2709 m lies close to the no-fuselage NP of 0.2745 m, so the anchor in effect cancels about 90 % of the fuselage term. On the blockout geometry the 240 mm manual CG is neutral (+0.3 %), and 260 mm would be −5.4 % c. Raymer's chart is read at 31–36 % body length elsewhere in the fleet. The Avanti's root quarter chord sits at 57 %, where the chart value is higher. I did not read it, so K_f 0.008 is probably not conservative here.

**P-51D: data NP 34.3 mm (7.0 % c) forward of the geometric NP. Category (d): a calibrated lumped term.**

`research/p51/p51-05/derive_physics.py:236-241` bisects K_f until the NP equals `NP_GLIDE = 0.342` (`:226`). The source text reads: "CALIBRATED hypothesis: the fuselage, belly scoop and windmilling-propeller term puts the power-off neutral point at the full-size airplane's measured stick-fixed glide value, 34.2 % MAC (NACA XP-51 ...)". The result is K_f = 0.0329 /deg, 4.1 × Raymer's 0.008. `derivation.md:214` adds "above Raymer's 0.005-0.015".

This is the only file in which the data is *less* stable than its geometry. It is also the only file whose runtime separately adds a propeller normal force, P-factor and slipstream (`propulsion.propeller.normal_force`, P51-06/12). The calibrated K_f already contains the windmilling-propeller contribution, so the glide margin may be double-counted toward instability. I have not quantified this.

## Cmq

File values and the reference each generator states:

- **Stik:** −8.082, ARP-referred (D11g).
- **Timber:** −12.669, `-2*ah_free*sh/s*((xh-cg_x)/c)**2`, tail only, about the 60 mm CG.
- **Extra:** −9.380, "tail damping about the CG ... x1.1".
- **Avanti:** −7.751, the same form.
- **P-51:** −8.402, the same form.

The global oracle applies `Cmq` and the `CLq` lift at the ARP and then transfers them by r × F (`app/physics/aero.gd:198-230`). The effective about-CG damping is therefore Cmq + CLq·(x_cg − x_arp)/c_ref. That gives the values in the last sensitivity column: Extra −9.19, Avanti −7.34, P-51 −7.76 and Timber −12.53, which are 1–8 % weaker than each generator intended. D6e-R1 already corrected this for the Stik. The local (strip and tail) regime computes tail damping from geometry and is not affected. This is a side observation; I did not test it in the runtime.

## Assumptions and limits

- `horizontal.lift_slope` already includes η_h = 0.9 and (1 − dε/dα). Every generator states this ("Helmbold x eta 0.9 x (1 - deps/dalpha)"), and the Stik's source string implies it. It is therefore not multiplied by η or (1 − dε/dα) again.
- Wing CLa_w uses Helmbold with κ = 0.9 and no sweep, dihedral or κ refinements, as in D6e-R1. Using the file split instead moves the NP by at most 3.3 mm: Stik −3.3, P-51 +3.1, Timber +1.3, the others under 1 mm.
- K_f = 0.008 /deg (±30 % shown) is applied uniformly. It is only a chart reading near 31–36 % body length.
- No propeller normal force, slipstream, wing-body interference, ARP or tail height terms, or elastic effects are included. These are planar, stick-fixed, power-off estimates from drawings and blockouts. None is a measured NP.
- The Avanti geometry is an AV-02 visual blockout. Its geometric NP inherits the blockout's longitudinal error, which is the error its generator's anchor is meant to absorb.
