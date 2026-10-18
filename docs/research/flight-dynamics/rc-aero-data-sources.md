# RC-class aerodynamic data sources

Status: sources retrieved and read 2026-10-18. This registry lists external measurements of RC-class airframes (flight identification, wind tunnel) and the method references behind the Stik lateral-directional work. Other airframes are comparisons, never Stik acceptance data. Their coefficients do not transfer without scaling, and several published values carry their own caveats, noted below.

- Manifest with URL, size, sha256, license and use of every file: [rc-aero-data-sources.json](rc-aero-data-sources.json).
- Local copies: `references/rc-aero-data/` (gitignored, reference only, not redistributable). To restore, download each manifest `url` into that folder under the manifest file name and check it with `sha256sum`.
- Structured comparison datasets live in [research/validation/references/](../../../research/validation/references/) (`openrc-reference v1`); their same-CL scaling method is described there and in the [validation README](../../../research/validation/README.md).

## Ultra Stick family

The Ultra Stick is the closest documented relative of the Ugly Stik: a high-wing, slab-sided, constant-chord sport model.

| Airframe | Source | Data | Project use |
| --- | --- | --- | --- |
| Ultra Stick 25e, 1.959 kg, b 1.27 m | Dorobantu PhD 2013 (UMN), sec. 3.5.2, eq. 3.26, tables 3.1/3.5; Dorobantu et al. 2012 | Flight-identified lateral matrices, bifilar inertias, modes; Ultra Stick Mini tunnel baseline | [us25e.json](../../../research/validation/references/us25e.json); derivative table in [D10-R2 evidence](stik-lateral-directional-2026-10-18/README.md) |
| Ultra Stick 120 (UMN), 8.338 kg | Lie PhD 2014, appendix D | Linear model at 19.2 m/s | [us120.json](../../../research/validation/references/us120.json) (inherited derivation) |
| Ultra Stick 120 (NASA LaRC FASER) | Owens, Cox, Morelli 2006; Hoe, Owens, Denham 2012; Denham, Owens 2016; Ritchie MSc 2013 | Geometry, mass properties, tunnel static/damping/rotary data, one flight spin | Not yet used |
| Ultra Stick 120 (UMN Baldr) | Flight report 2015-03-11 | Trim 23 m/s, pitch 5°, throttle 65 % | Context only |

**FASER**, a Hangar 9 Ultra Stick 120 kit (SI conversions of the printed values):

- **Geometry and mass.**
  - Geometry (table 1): S 0.769 m², b 1.917 m, c̄ 0.433 m, AR 4.78, dihedral 0.7°, untwisted. Fuselage 1.31 m long, 0.127 m high, 0.121 m wide.
  - Mass and inertias (table 2): 8.94 kg (19.72 lbf), CG at 0.25 c̄. Ix 0.672, Iy 0.889, Iz 1.578 and Ixz 0.759 kg·m² as printed. The tensor is positive definite, but an Ixz larger than Ix is unusual and needs checking before use.
- **Static tunnel data** (Owens 2006; Ritchie table 4.3).
  - Minor stall at α 12°, main stall at 15°.
  - Laterally stable to α 30°, slightly directionally unstable for α 17–20°.
  - Linear-region lift CL0 0.113 and CLα 0.0762/deg, at q 2 psf (about 96 Pa).
- **Damping, forced oscillation** (Hoe 2012; values in figures only).
  - Roll damping is stable through stall, nearly constant to α 15°, and falls to neutral or unstable between α 20° and 40°.
  - Yaw damping is stable below stall and matches DATCOM. It depends strongly on reduced frequency for α 10–20°.
  - The FASER linear model's Dutch roll is 0.53 Hz (a model value, not flight).
  - The UMN Ultra Stick 25 flights reached p̂ ≤ 0.1, at most 0.22.
- **Flight spin** (Denham 2016, table 2).
  - Entry: full up elevator, then full rudder. The result is a steep, oscillatory-pitch spin with roll rate above 200°/s (the gyro saturated) and yaw rate about 160°/s.
  - Estimated state: α 30°, β 5°, V 30.5 m/s, Ω 250°/s, so Ωb/(2V) ≈ 0.14.
  - These are video-corrected estimates, not clean measurements. The rotary-balance steady-spin prediction did not reproduce this spin.

## Other RC-class airframes

| Airframe | Source | Data and caveats |
| --- | --- | --- |
| ShowTime 50 (b 1.45 m, S 46.58 dm², 2.90 kg; Stik S 46.45 dm²) | Selig 2010 sec. III.C/IV.C; Selig 2014 table 1, figs. 20–23 | Component model behind FS One: fuselage segments with side lift over ±180°. **Simulated** knife-edge on held right rudder until the fuselage stalls near β −65°; side-force generators make it climb. A model, not a flight measurement. |
| Edge 540, Extra 260 EFL, Ultimate TOC | Selig 2014 table 1 | Specifications and simulated maneuvers (harrier, rolling harrier, inverted spin). |
| Extra 260 35 %, the UIUC Aero Testbed (17.01 kg, b 2.667 m, S 1.312 m²; Ixx 1.53, Iyy 4.86, Izz 6.06 kg·m²) | Ragheb, Selig 2013, table 1 and section IV | More than 20 flight spins recorded with an IMU. Baseline: power off, full rudder, full up, neutral ailerons, low rates. Measured: pitch −55 to −57°, sink 15.5–16.8 m/s, p 235–238°/s, r 150–155°/s, Ωb/2V 0.20. Pro-spin ailerons lower the nose 5°, raise the sink 66 % and roll rate 50 %, and halve Ωb/2V. |
| Sukhoi 29S 35 % (16.37 kg, 2.6 m, 130 dm²) | Dantsker, Selig 2015; Dantsker et al. 2013 | High-α flight data; coefficients in figures only. |
| Glow scale Cessna 182 (b 2.05 m, 4 kg) | Fischer et al., ICAS 2022-0873, table 1 | Output-error identification: CYβ −2.97, Clβ −0.050, Cnβ 0.161, Clp −0.068, Cmq −5.41. The normalization is not stated, and CYβ and Clp are far from typical values. Clr, Cnp, Cnr and Cnδa have Cramér-Rao bounds of 81–214 %, so they are unidentified. |
| Rudderless UAV, 1.28 kg, b 0.97 m | Venkataraman, Seiler 2019 | Flight Dutch roll ζ 0.12, ωn 4.8 rad/s (the initial model gave 0.06 and 7 rad/s); roll τ 0.078 s; spiral not excited. |
| NASA AirSTAR T-2: 5.5 % dynamically scaled twin-turbine jet transport (23.1 kg, b 2.088 m, S 0.548 m²; Ix 1.60, Iy 6.13, Iz 7.49, Ixz 0.29 kg·m²) | Morelli 2012, tables 3 and 6; Morelli 2011 (multi-sine maneuvers) | Global lateral model identified from flight, /rad: CYβ −0.548 (CYβα −4.04), Clβ −0.130 (Clβα −0.271), Cnβ 0.167 (Cnβα +0.342), Clp −0.317, Clr 0.285, Cnr −0.889, Cnp −0.447, plus α and control cross terms. The closest turbine-jet reference for the Avanti; a transport layout, not a sport jet. |
| Vector-P pusher UAV, 31.5 kg | Fischer et al., ICAS 2018-0764 | Clβ −0.0285, Cnβ 0.090, CYβ printed +0.029 (sign unexplained). Not an RC sport class. |

Identified Cnβ spans 0.046/rad (Ultra Stick 25e) to 0.167/rad (T-2), against the Stik's 0.074/rad after D10-R2. Directional stability follows each airframe's own tail volume and body. The spread bounds plausibility; it does not set a target.

## Lift, drag and propeller-drag references

- **Southampton FliTePlat** (Weishäupl, McLay, Sóbester 2024, open access): a 5.5 kg twin with b 1.96 m and S 0.488 m², stalling at 11 m/s.
  - Wind tunnel (table 2): CD0 0.0503, K 0.0764 (e 0.53), CL0 0.257, CLα 0.1122/deg.
  - Flight: automated glides and slow-downs recover CD0 within 10 %; manual glides miss it by about 70 %.
  - Stationary propellers add 0.01–0.03 to CD, depending on where the blades stop.
- **FASER tunnel** (Ritchie 2013): CL0 0.113, CLα 0.0762/deg (section "Ultra Stick family").
- **Low-Reynolds CLmax** (Vahora, Ananda, Selig 2018, UIUC GA-USTAR 1/5-scale RC Cessna 182). At the model's stall Re of 230,000, the full-scale NACA 2412 loses Clmax; full scale gives 1.75 (XFOIL) and 1.62 (measured at Re 3.1·10⁶). A new airfoil, VAS1715, was needed to match the full-scale lift slope and Clmax. A scale model with the full-size airfoil therefore stalls earlier than the airplane it copies.
- **Small-UAV identification, low relevance.** Jayanti et al. 2026 validate a 2.43 m, 7.5 kg twin's CFD model against flight. The BYU drag-polar thesis (Ostler 2006) was blocked (403) and is kept as a link.

## Spin, knife-edge and fuselage crossflow references

- **NASA spin-mode classes** (Burk et al. 1977, TP-1009), by angle of attack: steep 20–30°, moderately steep 30–45°, moderately flat 45–65°, flat 65–90°. In that spin-tunnel study, the tail configuration decided between flat and steeper modes.
- **NASA/Piper radio-controlled stall/spin models** (Burk, Wilson 1975, TM-80510). RC scale-model spins and recoveries correlated with the full-scale airplane. The paper warns that a dynamically scaled model has much less tail volume than a conventional RC model and reacts very differently to controls.
- **Method and niche cases.**
  - Bihrle 1976 (CR-144995) correlates analytical spin prediction with flight of a 1/10-scale RC fighter, as a method reference.
  - Blanchard 1981 (CR-156871): 1/6-scale RC Piper Tomahawk, ultra-deep-stall descents.
  - Langley 1979 (TP-1589): leading-edge droop study combining tunnel, RC model and full-scale flight; not yet read in detail.
- **Fuselage crossflow** (Polhamus 1959, TR R-29, which supersedes NACA TN 4176; companions TR R-46 and the 1984 review CR-3809).
  - Figure 11 gives the subcritical drag of square cylinders with the flow face-on: about 2.0 with sharp corners (r/b ≤ 0.021), 1.6 at r/b 0.08 and 1.2 at r/b 0.245. Beyond 30° of incidence it is about 1.5 for every radius. These values are read from the figure.
  - The corner radius strongly moves the critical Reynolds number. A Stik-sized slab side in knife-edge works near Re 10⁵, which is subcritical.
  - The section side force can be large and can change sign with Reynolds number.
- **Knife-edge practice, not measurements.**
  - The commercial Aerofly FS 2 simulator models the fuselage as 2–16 round or rectangular stations. Its starting values are a sideways drag Cdy of 1.0–1.5 and a side lift Cly of 0.6; a higher Cly holds a knife-edge with less sideslip.
  - Model Airplane News (2018) reports that side-force generators made a large Ultra Stick's knife-edge much slower.
  - No instrumented RC knife-edge flight was found.

## Method references

- F. Lutze, Virginia Tech AOE 3134 yaw-moment notes: DATCOM sidewash factor; z_w is positive down.
- Nicolosi, Ciliberti, Della Vecchia 2016, vertical-tail design review: high-wing sidewash, DATCOM accuracy.
- van Wonderen 2017, TU Delft MSc thesis: slipstream effect on directional stability; DATCOM vertical-tail accuracy.
- Raymer eq. 16.50 fuselage Cnβ, as implemented in FAST-GA (link in the manifest).
- Chambers et al., NASA TN D-5361: lateral-directional stability at high α (Cnβ,dyn, LCDP). This is a departure-criteria method, not RC data.

The manifest's `links` list records the leads without a downloaded file and why: blocked or record-only papers (MDPI Aerospace 10(4):350, the Piper Cub J-3 RPV identification), pages without numbers (Olson's Ultra Stick 120 spins), and unchecked candidates. The unchecked ones are UMN Baldr flights 12, 13 and 17, the UIUC unsteady high-α thesis, the GA rotary-balance and spin-tunnel companions, and two spin theses.

## Open uses

- [`spin_state.py`](../../../research/flight-test/spin_state.py) compares the flight-test battery's `spin` card with the FASER and Aero Testbed spins, which were flown with the same entry. On the D10-R2 run, Ωb/2V is close to both references and roll rate is similar, but both references show the same three differences:
  - **Less yaw.** The model's spins are roll-dominated: r 78–100°/s on the Stik variants and 99–112°/s on the Extra, against about 160 (FASER) and 150–155°/s (Extra 260).
  - **Lower α, nose lower.** The model flies α 19–23° and θ −62 to −66°. FASER flew α 30°, and the Extra 260 flew θ −55 to −57°, which implies α of about 33–35° for a near-vertical path.
  - **Far less vertical force.** The Extra 300S sinks 21.2–21.6 m/s at 7.1 kg/m², a vertical-force coefficient 2(W/S)g/(ρV²) of 0.25. The Extra 260 sinks 15.5–16.8 m/s at 13.0 kg/m², a coefficient of 0.74–0.86.

  The model's developed spin is therefore steeper and faster than the measured RC spins, with about a third of their vertical force. These are other airframes, with their own throws and inertias. The card's window, 4.0–6.25 s, is about three turns in, while the airspeed still rises about 1 m/s per second. So this is a consistent finding to investigate in the post-stall model, not yet a proven defect. A longer pro-spin hold would show whether the model settles at a higher α.
- [`polar_fit.py`](../../../research/flight-test/polar_fit.py) fits each aircraft's airframe polar from `aero_sweep` and compares it with the idle glides. Results on the D10-R2 run:
  - **Stik lift matches the Ultra Stick 120 tunnel.** CL at α 0 is 0.107 against FASER's 0.113, and CLα is 0.0799 against 0.0762/deg, both within 5 %.
  - **Fleet polars sit in the measured RC range.** CDmin is 0.029–0.043 and e 0.75–0.79, against CD0 0.050 and e 0.53 for the FliTePlat. The fit needs the offset CL at least drag: without it, the cambered Stik and Timber give e of about 1.7, which is a fitting artifact.
  - **Idle glides add 0.003–0.024 to CD on the glow-idling and turbine aircraft.** This is the propeller at idle plus trim drag, the same order as the FliTePlat's 0.01–0.03.
  - **The Timber's propeller stops at zero throttle, and the model then adds no drag.** [`propulsion.gd`](../../../app/physics/propulsion.gd) returns zero loads below 1 rpm for non-glow propellers. Scaled by propeller disc to wing area, the FliTePlat's stopped-propeller increment would be 0.006–0.019. That would lower the Timber's best idle glide ratio from 13.9 to about 10.6–12.6. This candidate gap belongs to the propulsion owners.
  - **The glow Stik variants do not descend at idle at 1.3 and 1.6 Vs.** Their idle turns 5,000–8,800 rpm in the glide. This is FT-01 finding 2, now seen in the glide.
- **Static lateral derivatives.** These come from `aero_sweep` row `beta_05` divided by 5° in radians, at each aircraft's trim α, on the D10-R2 run. Results:
  - **Avanti:** CYβ −0.90, Clβ −0.138, Cnβ 0.187. The T-2's flight model at α 4° gives −0.83, −0.149 and 0.191: the same order for a different jet layout.
  - **Stik:** Cnβ 0.062 lies within the identified range. Its Clβ of −0.079 at trim α is twice the Ultra Stick 25e's flight-identified −0.039; the D10-R2 table lists the base value, −0.0545. That points to a CL-dependent dihedral effect worth reviewing against the sister airframe.
  - **Others:** Extra CYβ −0.52, Clβ −0.024, Cnβ 0.162; P-51 −0.46, −0.064, 0.046; Timber −0.32, −0.080, 0.049.
- Check the aero model's roll and yaw damping against the FASER α trends: constant to stall, then loss of roll damping. The T-2 table gives a jet's Clp and Cnr for the same check on the Avanti.
- Use the Polhamus subcritical crossflow drag, 1.6–2.0 for the Stik's slab sides, in any knife-edge fuselage side-force estimate. The D10-R2 Allen–Perkins estimate assumed about 1.5.
- Add FASER as an `openrc-reference v1` dataset once a quantity with a printed value and a defined scaling is chosen.
