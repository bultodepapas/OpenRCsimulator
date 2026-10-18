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
| Sukhoi 29S 35 % (16.37 kg, 2.6 m, 130 dm²) | Dantsker, Selig 2015; Dantsker et al. 2013 | High-α flight data; coefficients in figures only. |
| Glow scale Cessna 182 (b 2.05 m, 4 kg) | Fischer et al., ICAS 2022-0873, table 1 | Output-error identification: CYβ −2.97, Clβ −0.050, Cnβ 0.161, Clp −0.068, Cmq −5.41. The normalization is not stated, and CYβ and Clp are far from typical values. Clr, Cnp, Cnr and Cnδa have Cramér-Rao bounds of 81–214 %, so they are unidentified. |
| Rudderless UAV, 1.28 kg, b 0.97 m | Venkataraman, Seiler 2019 | Flight Dutch roll ζ 0.12, ωn 4.8 rad/s (the initial model gave 0.06 and 7 rad/s); roll τ 0.078 s; spiral not excited. |
| Vector-P pusher UAV, 31.5 kg | Fischer et al., ICAS 2018-0764 | Clβ −0.0285, Cnβ 0.090, CYβ printed +0.029 (sign unexplained). Not an RC sport class. |

Identified Cnβ spans 0.046/rad (Ultra Stick 25e) to 0.161/rad (scale Cessna), against the Stik's 0.074/rad after D10-R2. Directional stability follows each airframe's own tail volume and body. The spread bounds plausibility; it does not set a target.

## Method references

- F. Lutze, Virginia Tech AOE 3134 yaw-moment notes: DATCOM sidewash factor; z_w is positive down.
- Nicolosi, Ciliberti, Della Vecchia 2016, vertical-tail design review: high-wing sidewash, DATCOM accuracy.
- van Wonderen 2017, TU Delft MSc thesis: slipstream effect on directional stability; DATCOM vertical-tail accuracy.
- Raymer eq. 16.50 fuselage Cnβ, as implemented in FAST-GA (link in the manifest).
- Chambers et al., NASA TN D-5361: lateral-directional stability at high α (Cnβ,dyn, LCDP). This is a departure-criteria method, not RC data.

The manifest's `links` list records the leads without a usable file: MDPI Aerospace 10(4):350 (PDF returned 403), the Piper Cub J-3 RPV identification (record only), Olson's Ultra Stick 120 spin page (no numbers), unchecked UMN Baldr flights 12, 13 and 17, and an unchecked UIUC thesis on unsteady high-α aerodynamics.

## Open uses

- [`spin_state.py`](../../../research/flight-test/spin_state.py) compares the flight-test battery's `spin` card with the FASER spin. On the D10-R2 run, every Stik variant matches FASER's airspeed once scaled to its wing loading: 21–23 m/s against 21–22. Its Ωb/2V is close (0.16–0.19 against 0.14), and its pitch oscillates in the same way. The spin is made up differently, though. The model's is roll-dominated (r 78–100°/s) at α 19–21° with |β| 16–21°. FASER's had r about 160°/s at α 30° and β 5°. This is a different airframe with a large printed Ixz, and there is no Stik spin measurement, so this is an observation, not a defect.
- Check the aero model's roll and yaw damping against the FASER α trends: constant to stall, then loss of roll damping.
- Add FASER as an `openrc-reference v1` dataset once a quantity with a printed value and a defined scaling is chosen.
