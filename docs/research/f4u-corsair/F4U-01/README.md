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
| Outer-panel dihedral, root incidence | Values lost in OCR ("8.5" appears near the sweepback line) | NACA RM A7C05; measure from g1 instead |
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

| Candidate | Span / length | Power and gear | Mass evidence | Fit |
| --- | --- | --- | --- | --- |
| [FokkeRC Vought F4U-1D Corsair 1/5](https://www.fokkerc.com/product/vought-f4u-1d-corsair-1-5/) | 2,500 mm / 2,052 mm | DLE-111/120 gasoline boxer; Robart #150 rotating pneumatic main retracts; Robart #160 1/5 mechanical tail retract | Not published | **Recommended:** exact 1/5, F4U-1D, rotating retracts match R59's 90° wheel twist. Laser-cut wood kit with 1:1 plans, 297 mm composite cowl. FokkeRC is already cited by the P-51 data |
| [TopRC F4U Corsair ARF](https://www.gator-rc.com/products/f4u-corsair-top-rc-model-no-retracts-blue-scheme) | 93 in (2.36 m) | 60–100 cc gasoline; detachable wing | ≈37 lb (16.8 kg) flying, retailer estimate | Mass anchor for the size class |
| [Seagull FG-1D Corsair ARF](https://www.gator-rc.com/products/f4u-goodyear-limited-edition-seagull-model) | 87 in (2.21 m) | 60–70 cc gasoline | 30 lb (13.6 kg) flying, retailer figure | Mass anchor for the size class |
| CARF-Models F4U-1D | 1:4.5 (≈2.78 m), folding-wing option | Not checked | Not checked | Not 1/5; [Model Aviation profile](https://library.modelaviation.com/article/about-us-carf-models-limited) |

Cross-checks with the FokkeRC kit: its 2,052 mm length is within 1.1 % of the published full-size length at 1/5 (2,030 mm), supporting the R59 length finding. Its 297 mm cowl agrees with R59's 1.507 m cowl width × 0.2 = 301 mm.

**Mass inference, not a source.** Scaling the two mass anchors to 2.50 m span by span³ gives 19.7–19.9 kg; by span² (constant wing loading) 17.4–18.8 kg. A placeholder range of 16–21 kg flying mass is reasonable until a kit manual or builder log is found. For comparison, the P-51 data uses 18–24 kg for a 2.82 m, 120 cc model.

## Rights notes

The [licensing guide](../../../AIRCRAFT-LICENSING.md) classifies the Corsair as a conditional historical replica and records licensing activity for the name. R59 lists the Royal RC F4U-1D plan and the CARF manual among its references and packs two plan scans; the g1 request asks for their removal and a reference list. Kit plans are reference material only; no kit drawing, CAD or artwork is imported.
