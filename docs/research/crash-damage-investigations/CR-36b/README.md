# CR-36b — Independent partial Extra 300S economics

2026-10-15. Implements another slice of [CR-36](../../../plans/crash-damage-economics.md). Software verification, not crash/installation qualification.

The `gp-extra-300s-60` dossier now maps its own physical inventory, excluding virtual balance, and adds unpriced assembly labor. It has three fuselage servos and two aileron servos. Engine, Slimline exhaust, spinner, mount, fixed gear, airframe, receiver/switch, battery and fuel remain independent unpriced rows. Neither the Ugly Stick build nor the unrelated electric 60E ARF is substituted as a complete replacement.

## Dated sources and amounts

| Item | Observed USD | Use and limits |
| --- | ---: | --- |
| [APC LP12060, 12×6 Sport](https://www.apcprop.com/product/12x6/?v=84de8e2b14bb) | 5.39 | Manufacturer page reopened on this date. Matches the simulated propeller; historical prototype prop identity is not established. Spinner is separate. Reuses catalog offer `apc-lp12060`. |
| [SAVOX SC-0252MG+](https://www.adrenalinercracing.com/products/savox-sc-0252mg-standard-digital-metal-gear-servo) | 33.99 each | Retailer page reopened: sale price, 43.99 comparison price, only two units left. Reuses `savox-sc0252mgp` as a value proxy for five generic servos, not a confirmed installation or five-unit purchase quote. Existing application/compatibility limitations remain. |
| Slimline #3217 / SLIG2217 | Unknown | The [Great Planes instruction manual](https://outerzone.co.uk/download_file.asp?FileType=Supp&Filename=Extra_300S_60_oz10977_manual.pdf&planID=10977) identifies this in-cowl exhaust for its .61FX prototype. No current exact USD quote was verified in this review. Other Slimline models, CAD Bisson replacements and old engine packages are not equivalent offers. |

These observed unit prices give a **known parts subtotal of $175.34** (five servo proxies plus one prop), not an aircraft price. An explicit assessment that two aileron servos are reusable credits $67.98 once and leaves $107.36 of known losses. Unknown rows still prevent a full loss/replacement amount or upper bound. No automatic servo-survival rule is introduced. A confirmed prop strike costs the prop only ($5.39 known subtotal); engine, mount, spinner and forward structure need inspection. Taxes, shipping, availability and installation qualification are not inferred.

## Implementation

`research/crash-economics/aircraft-costing.json` owns the independent authoring dossier. Its exact physical-source hash prevents regeneration from silently accepting changed hardware. Independent authoring cannot also inherit the baseline. The generator reuses existing integer-cent lines, validates contacts/coverage/offers, derives missing reasons for unpriced rows and preserves unresolved candidate packages. Python and Godot reject a complete dossier containing null prices, including a tampered dossier whose missing list was cleared.

This extends the [aircraft contract](../../../../AIRCRAFT_CONTRACT.md#damage-and-cost-authoring-dossier) without changing the physical aircraft, simulation kernel, price offers or runtime schema. The existing accepted-contact observer, frame-boundary calculator, large report and archive consume the generated dossier. No manual edits to generated data are required.

## Verification

See [verification.json](verification.json) for commands and counts. Native Windows Godot 4.7.2 tests cover loader rejection, five-servo counting, partial replacement, conditional salvage and real production contact-to-report wiring. The Extra fixture starts the production runway session, places the disc 1 mm into contact and invokes the production session callback. It verifies a nonterminal prop strike and a frozen $5.39 offer with an unresolved total. This is a controlled endpoint integration case, not a flown crash trajectory or a physical failure-threshold experiment.

Four Stik routes retain their existing complete estimated inventory coverage; the Extra remains economically incomplete with useful priced components; four other routes still have no reconciled priced component mappings. Fleet BOM completion, repair recipes, structural/thermal resolution and physical validation remain open.
