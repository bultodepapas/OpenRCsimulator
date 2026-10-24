# F4U-01: Corsair sources and RC reference candidates

Researched 2026-10-21 for the [F4U plan](../../../F4U-PLAN.md). This is dated evidence: values are copied from the cited sources with their uncertainty, not yet adopted as aircraft data. Selection of the hardware reference remains an owner decision.

## Full-size geometry and aerodynamics

| Quantity | Value | Source and confidence |
| --- | --- | --- |
| Span | 40.90 ft (12.47 m); 41 ft 0 in elsewhere | [Vought Heritage F4U-1 specification](https://vought.org/products/html/f4u-1spec.html); NACA RM A7C05 lists 40.98 ft for the F4U-4 |
| Length | 33.30 ft (10.15 m) | Vought Heritage F4U-1. R59 measures 10.718 m, 5.6 % longer |
| Wing area | 314 sq ft (29.17 m²) | [Patriots Point FG-1D](https://patriotspoint.org/things-to-do/aircraft/fg-1d-corsair); NACA WR L-440 model 41.6 sq ft × 2.75² = 314.6 sq ft. RM A7C05's OCR line implies 276.3 sq ft with aspect ratio 6.08, probably a different area definition; unresolved |
| Mean aerodynamic chord | 94.00 in (2.388 m) | NACA RM A7C05; WR L-440 model 2.85 ft × 2.75 = 7.84 ft agrees |
| Root / tip chord | 105.00 in / 71.38 in | NACA RM A7C05 (OCR); the tip value is probably a theoretical tip, not the rounded tip |
| Wing sections | NACA 23018 root, NACA 23009 tip | NACA RM A7C05 table; [UIUC airfoil usage guide](https://m-selig.ae.illinois.edu/ads/aircraft.html) "Vought V-166 F4U". The same guide lists 23015 root for the Goodyear FG-1, F2G and Brewster F3A; treat root thickness 15–18 % as uncertain |
| Outer-panel dihedral, root incidence | Dihedral lost in OCR ("8.5" appears near the sweepback line); wing incidence +2°, thrust line to wing chord line | Dihedral: NACA RM A7C05, measure from g1 instead. Incidence: AN 01-45HA-1 (F4U-1 pilot's handbook, [vmfa251.org](https://www.vmfa251.org/pdffiles/Corsair%20Manual.pdf)), Appendix I p. 64 |
| Horizontal tail | 55.9 sq ft total, span 16.5 ft, stabilizer incidence 1.25°; elevator 21.9 sq ft aft of hinge, 5.4 sq ft balance | NACA RM A7C05 (F4U-4) |
| Vertical tail | 22.00 sq ft total; fin 7.34 sq ft, **fin offset 2° left**; rudder 13.0 sq ft aft of hinge, 1.66 sq ft balance | NACA RM A7C05 (F4U-4) |
| Ailerons | 18.1 sq ft both, aft of hinge; span 7.48 ft each; balance tabs 0.56 sq ft; trim tab left only 0.74 sq ft | NACA RM A7C05. R59 also models a left-only trim tab |
| Flaps | Slotted, 36.4 sq ft total | NACA RM A7C05; WR L-440 tested slotted flaps at 50° |
| Control travels | Not recovered (OCR) | Needed from another source or the RC kit |
| Propeller | F4U-4: Hamilton Standard four-blade 6501A-0, 13.167 ft. F4U-1/-1D: three-blade, ≈13 ft 4 in (not yet sourced) | NACA RM A7C05; R59 note cites Fortitudine vol. 16 no. 3 for 13 ft 2 in |
| Engine | P&W R-2800-8, 2,000 hp (F4U-1); R-2800-18W (F4U-4) | Vought Heritage; NACA RM A7C05 |
| Weights | F4U-1: 8,982 lb empty, 14,009 lb gross | Vought Heritage. Full-size weights do not set RC mass |

### Measured behavior worth matching

- **Maximum lift, NACA WR L-440** (1/2.75 model, 19-ft pressure tunnel, Re ≈2.6–2.8 × 10⁶ power-off): slotted flaps 50° with ailerons drooped 9.5° gave CL_max 2.13 power-off and 2.46 power-on; adding 0.30c outboard split flaps at 40° gave 2.32 power-off. Clean CL_max was not recovered from the OCR. Split flaps reduced aileron effectiveness.
- **Flying qualities, NACA RM A7C05** (F4U-4, Ames, 1947): stick-free neutral points ≈30 % MAC (flaps and gear up) and 27 % MAC (down), power on; tested CG 26.5–32.5 % MAC. Full-aileron rudder-fixed rolls reached only pb/2V = 0.064 at low and normal speeds. Static directional and stick-fixed lateral stability positive over ±15° sideslip. Stall warning inadequate in all configurations, with prompt recovery.
- **NACA RM SL7E20** (0.182-scale F4U-1 with external stores, 1947) is available for drag increments if stores are ever modeled. g1 is clean.

These are full-scale or large-model Reynolds numbers. A 1/5 model with a 0.48 m MAC flies at roughly Re 0.6–1.0 × 10⁶; the derivation must account for the difference instead of copying CL_max.

Source texts: [WR L-440](https://ntrs.nasa.gov/citations/19930093637), [RM A7C05](https://ntrs.nasa.gov/citations/20050081862), [RM SL7E20](https://ntrs.nasa.gov/citations/20090022392). The OCR text is degraded; recheck any adopted value against the PDF page images.

## 1/5 RC hardware reference candidates

Superseded on 2026-10-22 by the [giant-scale reference](#giant-scale-reference-2026-10-22); kept as the evidence the 1/5 derivation used.

| Candidate | Span / length | Power and gear | Mass evidence | Fit |
| --- | --- | --- | --- | --- |
| [FokkeRC Vought F4U-1D Corsair 1/5](https://www.fokkerc.com/product/vought-f4u-1d-corsair-1-5/) | 2,500 mm / 2,052 mm | DLE-111/120 gasoline boxer; Robart #150 rotating pneumatic main retracts; Robart #160 1/5 mechanical tail retract | Not published | **Recommended:** exact 1/5, F4U-1D, rotating retracts match R59's 90° wheel twist. Laser-cut wood kit with 1:1 plans, 297 mm composite cowl. FokkeRC is already cited by the P-51 data |
| [TopRC F4U Corsair ARF](https://www.gator-rc.com/products/f4u-corsair-top-rc-model-no-retracts-blue-scheme) | 93 in (2.36 m) | 60–100 cc gasoline; detachable wing | ≈37 lb (16.8 kg) flying, retailer estimate | Mass anchor for the size class |
| [Seagull FG-1D Corsair ARF](https://www.gator-rc.com/products/f4u-goodyear-limited-edition-seagull-model) | 87 in (2.21 m) | 60–70 cc gasoline | 30 lb (13.6 kg) flying, retailer figure | Mass anchor for the size class |
| CARF-Models F4U-1D | 1:4.5 (≈2.78 m), folding-wing option | Not checked | Not checked | Not 1/5; [Model Aviation profile](https://library.modelaviation.com/article/about-us-carf-models-limited) |

Cross-checks with the FokkeRC kit: its 2,052 mm length is within 1.1 % of the published full-size length at 1/5 (2,030 mm), supporting the R59 length finding. Its 297 mm cowl agrees with R59's 1.507 m cowl width × 0.2 = 301 mm.

**Mass inference, not a source.** Scaling the two mass anchors to 2.50 m span by span³ gives 19.7–19.9 kg; by span² (constant wing loading) 17.4–18.8 kg. A placeholder range of 16–21 kg flying mass is reasonable until a kit manual or builder log is found. For comparison, the P-51 data uses 18–24 kg for a 2.82 m, 120 cc model.

## Additions, 2026-10-22

| Topic | Source | Value used |
| --- | --- | --- |
| Section maximum lift and slope at model Reynolds numbers | [NACA TR 586](https://ntrs.nasa.gov/citations/19930091662), Table I, report pp. 39–40, checked against the page images 2026-10-23 ([recheck](../F4U-07/tr586-recheck-2026-10-23/README.md)) | 23012 cl_max 1.19 / 1.28 / 1.41 at effective Re 0.449 / 0.884 / 1.760 million; slope ≈0.096/deg; 23015 α₀ −1.1°, Cm −0.008. XFOIL (Ncrit 9) runs about 16 % high on cl_max and 20 % high on slope at these Reynolds numbers |
| Thickness trends of the 230 series | [NACA TR 610](https://ntrs.nasa.gov/citations/19930091685) | Slope falls slightly with thickness; cl_max peaks near 12–13 % thickness, so the 9–11 % outer sections should stall earlier than the clamped model |
| Slotted flaps | [NACA TR 664](https://ntrs.nasa.gov/citations/19930091739); Roskam Part VI Figs. 8.17, 8.31–8.34 as digitized by [FAST-GA](https://fast-ga.readthedocs.io/en/stable/_modules/fastga/models/aerodynamics/components/figure_digitization.html) | TR 664: 23012 with the 0.2566c flap 2-h reaches cl_max 2.86 at Re 8 million, increment nearly Reynolds-independent; Roskam's chain gives 1.19 on that flap against TR 664's ≈1.1 |
| Corsair setups | [Black Horse BH64 manual](https://www.lindinger.at/media/f2/5a/bd/1602008047/9774576_EN_Manual.pdf) (2.28 m), [Seagull FG-1D manual](https://www.skyraccoon.com/assets/pdf/Corsair-F4U-Goodyear-FG-1D_4444.pdf) (2.21 m), Phoenix PMMA1845 (1.8 m) | CG 128 / 120 / 110 mm behind the root leading edge; throws and flap settings in mm (Black Horse: measured at each surface's widest point) |
| Mass | Black Horse 9.6–10 kg on 94.6 dm² (gasoline 55–65 cc, rotary air retracts); Seagull 14 kg | Constant-wing-loading scaling of the gasoline Corsairs to 2.5 m: 11.8, 17.9 and 18.8 kg (mean 16 kg) |
| DLE-111 installed power | [Team Flying Circus](http://www.teamflyingcircus.com/forum/showthread.php?t=5561), [RCU](https://www.rcuniverse.com/forum/gas-engines-142/9214721-dle-111-rpm-numbers.html), [rc-network](https://www.rc-network.de/threads/dle-111-mit-28x12-drehzahl.665634/); [Mejzlik 27x10 2B datasheet](https://www.mejzlik.eu/files/27x10-2b-gas-datasheet.pdf) | Mejzlik 27x10 "a hair over 6800 rpm" static, static Cp 0.027 → 7.3 kW installed; spread 6,250–6,900 rpm on 27x10 propellers, 5,300–6,600 rpm on 28x12 |
| Propeller | Mejzlik 26x12 3B GAS N datasheet rev. 3.0 | Values in `research/p51/p51-06/mejzlik_26x12.json` rechecked; the calibrated BEM over-predicts thrust by 17–37 % at J 0.59–0.67 |
| Full-size handling | NACA RM A7C05 text | Clean pb/2V 0.064 (required 0.09); flaps and gear down 0.060–0.076; power-on stall rolls off to the left; lateral oscillation damped at low altitude, rudder oscillation lightly damped |

## Giant-scale reference, 2026-10-22

The owner asked for a bigger, realistic Corsair with a Moki radial and, preferably, a three-blade propeller. The common configuration of that kind is the CARF-Models F4U-1D 1:4.5 with a Moki S250 five-cylinder radial. It supersedes the 1/5 candidates above as D1.

| Topic | Source | Value |
| --- | --- | --- |
| Kit | [CARF-Models F4U-1D / F4U-4 1:4.5](https://carf-models.com/en/products/f4u-1d-corsair); dealers [Nexus Models](https://nexusmodels.co.uk/products/carf-f4u-1d-corsair-1-4-5-790000), 8fly.it | 2,800 mm (110 in) span, 2,200 mm (87 in) length, 18–21 kg (39–46 lb) dry; designed around the Moki 250 cc radial with a 32 in three-blade; also allows 80–150 cc gas engines; Sierra Giant Scale retracts, optional hydraulic wing fold |
| Flown example | [Model Airplane News review](https://www.modelairplanenews.com/carfcorsair) (December 2011) | 53 lb (24.0 kg), 2,090 sq in (1.348 m²), Moki 250, SEP 32x18 two-blade, Sierra retracts, hydraulic fold |
| Setup | [CARF manual](https://carf-models.com/files/product/34/ed/06/corsair_manual.pdf), "Important Values" and engine installation | CG 10–12 mm ahead of the main spar (spar station not given); aileron 20 mm up / 15 down; elevator 20/20 mm (35 mm up for take-off only); rudder 70 mm; flaps 45° maximum, 35° useful, 30° recommended on approach; 2.5° right thrust, 0.5° up-thrust. Take off at 50 % power; full power can nose the model over because the low-rate elevator cannot hold the tail; no take-off flap; land tail-up; never noticeably exceed 200 km/h |
| Engine | [Moki S250 operating instructions](https://www.heilemann-sternmotoren.de/images/pdf-dokumente/MOKI_250_S_Radial_Operating_Instructions.pdf); [CARF Moki S250 page](https://carf-models.com/en/products/moki-s250) | 250 cc, bore 42 mm, stroke 36 mm, 15 bhp, 5.4 kg (CARF: about 15.5 PS DIN, 5,100 g); Menz 32x18 two-blade at 4,300 rpm, SEP 30x18 three-blade at 4,400 rpm; 26–40 oz tank; petrol 50:1; ignition with overspeed cut-off. No rated rpm published |
| Engine limits | [CH Ignitions CDI for the Moki S215/S250/S300](https://ch-ignitions.com/product/ch-cdi-moki-s215-s250-s300/); [Seidel SP-250-X](https://seidel-props.de/en/sp-250-x-beschreibung/) | Rev limiter 6,000 rpm; idle 900 rpm on the ground, 6,000 rpm in a deep dive; "15 hp (Data Airworld)" |
| Engine, field reports | RCU "MOKI RADIAL Care and Maintenence" thread (search summaries, pages not read in full) | Moki S300 with a SEP 34x18 at 3,950 rpm pulled 29.92 kg; S250 on 32x18 two-blades: SEP 4,200 rpm, Engel 5,200 rpm; factory: about 4,200 rpm as the most efficient static speed |
| Bigger engine | Moki S400 operating instructions | 400 cc, 23 bhp, 9.6 kg; SEP 38x18 two-blade at 3,800 rpm, SEP 36x18 three-blade. For 1/3.5–1/3 models, not used |
| Propeller tables | Mejzlik datasheets rev. 3.0, 2025-12-18 (simulated): [32x18 2B GAS](https://www.mejzlik.eu/files/32x18-2b-gas-datasheet.pdf) at 4,300 rpm, [31x12 3B GAS](https://www.mejzlik.eu/files/31x12-3b-gas-datasheet.pdf), [30x13 3B GAS EVO](https://www.mejzlik.eu/files/30x13-3b-gas-evo-datasheet.pdf) | 32x18 2B: 334 g, static Ct 0.0961, Cp 0.0367, limit 5,600 rpm. No 30–32 in high-pitch three-blade table is published; CARF's 32 in ground-adjustable scale three-blade has no data |
| Propeller mass | Earlier search: Biela 32x18 two-blade semi-scale for the Moki 215 | About 475 g |

The Moki manual's two static points agree within 13 % in torque on the Mejzlik coefficients (13.1 and 14.9 N·m), and the Mejzlik 32x18 thrust coefficient reproduces the measured Moki S300 thrust within 3.5 %. Larger Corsairs exist (1/4 at about 3.1 m, Moki S400 or geared drives such as the Seidel SP-250-X with a 38 in scale propeller), but none was found with a published setup comparable to CARF's.

No F4U sideslip derivatives were found in NTRS beyond RM A7C05's figures (RM SL7E20 covers store drag and buffet only). Transferring the P-51's flight-calibrated body-yaw ratio (3.6 × DATCOM) would make the Corsair directionally unstable, against RM A7C05's measured stability over ±15°, so it is not used.

## Rights

No licence is required ([owner decision F4U-13](../../../DECISIONS.md), 2026-10-23). R59 lists the Royal RC F4U-1D plan and the CARF manual among its references and packs two plan scans; the g1 request asks for their removal and a reference list. Kit plans are reference material only; no kit drawing, CAD or artwork is imported.
