# TT-20 visual reference notes

Research checked 2026-10-20 for the Turbo Timber Evolution 1.5 m, B revision (EFL105250B). This is a visual-reference record for the aircraft and its presentation. It is not flight-validation evidence.

## Variant and physical anchors

Use the B revision as the visual target. E-flite identifies the 2024 revision by its heavier-duty landing-gear springs and 70 A Smart Lite ESC; the B manual identifies the 1,555 mm wingspan, 1,040 mm length, 1,860 g no-battery mass, 2,190 g with a 4S 3,200 mAh pack, 800 Kv motor, 11 × 7.3 three-blade propeller, and six servos. The 2021 official overview video predates the B revision and explicitly shows the earlier 60 A ESC; it supports shared shape and flight-pose review only.

The current imported r2 asset measures about 1.5455 m skin span and 1.116 m length. That is about 9.5 mm short in span and 76 mm (7.3%) long in overall length against the manual. Do not uniformly scale it: the span is already close, and scaling would disturb its other authored landmarks. Preserve this discrepancy as an explicit limitation until the source is corrected and geometry is regenerated. The asset guide and TT-19 report retain the model provenance and measurements: [aircraft guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md), [TT-19](../TT-19/README.md).

## Observed construction and appearance

The official product photos show a high-wing, strut-braced EPO foam aircraft with a red, white, and black applied finish, gray transparent-looking canopy, black turboprop-style nose, three-blade propeller, broad flaps, fixed spring main gear, oversized black foam tires, and a small tailwheel. Close views show subtle bead-like foam texture, molded seams, hinges, and surface controls beneath the smooth printed/painted graphics. Keep the EPO grain restrained at normal camera distance; treat it as a fine material cue rather than a coarse bumpy silhouette. The manufacturer describes the airframe as lightweight composite-reinforced EPO and its manual says foam repairs can use common adhesives. Foam crush, dents, tears, and repair seams are reasonable visual interpretations; these sources do not quantify crash response or support changing damage physics.

For the selected light layout, use these observations and keep the distinction between photo evidence and interpretation:

- **Wingtip navigation lenses — observed:** the photos show small inset/clear capsules at both tips; the A52 flight photo visibly lights one tip green. Red on the opposite tip is the likely paired navigation color, but the manual does not diagram the system.
- **Landing lamps — observed:** A51 shows two bright white lamps on the low forward nose, one on either side beneath the spinner. A31 gives a close side view of an inset lower-cowl lens. Forward/down aim follows the visible mounting and landing-light role; the manual does not publish a beam diagram. Do not move these to the wing root or gear.
- **Anti-collision strobes — observed:** A33/A53 show a red dome on the fuselage spine just behind the wing trailing/root area; A37 shows a red dome on the underside. The underside white pair in A37 are Phillips screw heads on the wing-retaining plate, not lights.
- **System naming — manufacturer-confirmed:** E-flite describes factory-installed landing, navigation, and strobe LEDs. The current B manual lists an LED controller and a receiver channel for lights, but does not identify lamp count, strobe cadence, or exact coordinates.

Avoid broad emissive orientation strips. Use the aircraft’s physical lenses; the white wing stripes are finish markings, not lighting. Do not infer a flash cadence or ground illumination spread from these stills.

The B manual lists half/full flap travel of 20/35 mm with 16%/30% down-elevator compensation. Product close-ups show split flaps, molded hinge lines, control horns/linkages, and leading-edge slat pockets. Slats and floats are optional equipment; the standard wheeled configuration has the fixed gear above.

## Flight footage inspected

I downloaded and inspected the official [E-flite Turbo Timber Evolution 1.5 m BNF Basic and PNP overview](https://www.youtube.com/watch?v=qVAveeNrDVY) by Horizon Hobby Products (published 2021-05-27, 4:11). A video-only 720p/60 fps stream was sampled at five-second intervals through 0:00–4:00. The temporary video and contact sheets are under `tmp/timber-visual-references/`; they are research-only and are not part of this deliverable.

Frames show a short paved takeoff roll, low slow passes over grass, steep banked turns, rolling/inverted sport passes, and optional float operations over water with water rudders. This is edited promotional footage, not a measured flight test. It predates the 2024 B revision and should not be used to infer the B springs, exact control law, or verified aircraft performance.

## Images and asset rights

The current B product gallery at [EFL105250B](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html) was inspected locally; useful frames include A30/A35 (wingtips), A31 (lower cowl lens and foam surface), A33 (dorsal red dome), A34/A36 (flaps and hinges), A37 (ventral dome and wing screws), A47 (spring gear and tires), and A51–A53 (lights in flight). Local research-only copies live under `tmp/timber-visual-references/official-gallery/`. The B manual is [here](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dwb7e67f91/Manuals/EFL105250B-Manual_EN.pdf). Photos and manual pages are reference evidence only; do not ship copies as simulator assets.

The [Poly Haven Polystyrene PBR texture](https://polyhaven.com/a/polystyrene) is CC0 and includes normal/roughness maps. Its preview is visibly worn and pitted, so it is only a candidate for very subtle foam micro-normal detail; it is not a good full-color replacement for the clean EPO finish. Search did not find a suitable free flight-ready Turbo Timber Evolution model. The exact-name free result inspected was a BY-SA printable display miniature made with image-to-model AI, not a simulator model ([model page](https://3dgo.app/models/makerworld/2717669)); do not substitute it for the existing r2 aircraft.

The supplied r2 asset’s redistribution terms remain unresolved, as recorded in the [aircraft guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md). No photos, manual pages, or model files were copied into tracked assets.

## Damage-report display audit

The indexed code graph is ready but stale for the current tracked `app/ui/accident_report.gd` (`search_graph` has no matching node). After graph search proved insufficient, a read-only live-tree inspection found the report’s `RepairDetails` dependency, amount/status derivation, warning captions, priced actions, detailed line items, and replacement comparison. The Timber identity ribbon/color treatment is presentation-only: preserve those values, calculations, status/warning text, report actions, and expansion behavior. The current file’s `TT-20` comment marks the presentation hook: [accident report](../../../../app/ui/accident_report.gd).

## Primary references

- [E-flite current B-revision product page](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html) — new-for-2024 ESC and heavier springs; gallery.
- [E-flite B-revision instruction manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dwb7e67f91/Manuals/EFL105250B-Manual_EN.pdf) — dimensions, construction, gear installation, control throws, repairs, and parts.
- [E-flite Turbo Timber 1.5 m product page](https://www.e-fliterc.com/product/turbo-timber-1.5m-bnf-basic-with-as3x-and-safe-select-includes-floats/EFL15250.html) — official landing/navigation/strobe wording for the shared light system.
- [Official E-flite overview video](https://www.youtube.com/watch?v=qVAveeNrDVY) — inspected flight and water-operation footage; pre-B hardware revision.
- [Poly Haven Polystyrene](https://polyhaven.com/a/polystyrene) — CC0 material candidate.
