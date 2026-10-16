# CR-36d electric replacement-price evidence

The Horizon Hobby US replacement-part offers cited below were observed on 2026-10-15 and 2026-10-16, in USD before tax and shipping. The canonical [price-research-fleet.json](../../../../research/crash-economics/price-research-fleet.json) preserves each offer and its observation date; the integrated row estimates and constituent offers are recorded in [aircraft-costing.json](../../../../research/crash-economics/aircraft-costing.json). These are commercial reference parts for the fictional Turbo Lumber inventory; they do not establish that the fictional aircraft contains those exact products. The physical inventory is [turbo_lumber_evolution.json](../../../../app/data/aircraft/turbo_lumber_evolution.json), SHA-256 `61b0e5329732a8cabaf2deef11e9c297d8e745bb724370348609909b03c8e1ee`.

## Integrated composite row estimates

The costing record now estimates two rows from separate, non-overlapping replacement-part offers. Each estimate retains its constituent offer IDs and quantities; neither is a single retail offer.

| Inventory row | Source-backed constituents | Integrated estimate | Scope and confidence |
|---|---|---:|---|
| `propeller_main` | One [EFL5962 11 x 7.3 three-blade propeller](https://www.horizonhobby.com/product/3-blade-propeller-11-x-7.3/EFL5962.html), $7.99, plus one [EFL17553 Turbo Timber spinner](https://www.horizonhobby.com/product/spinner-turbo-timber/EFL17553.html), $8.99 | $16.98 | High coverage for the two parts named by the inventory row; moderate confidence as a proxy for the fictional build. The two offers were observed 2026-10-15 and are separate listings, not a kit. Automatic propeller damage billing stays disabled because the economic row also prices the spinner. Keep `propeller_component_id` empty and `propeller_inspection_ids` empty unless the model separates the two parts. |
| `wing_main` | One [EFL105252 wing set](https://www.horizonhobby.com/product/wing-turbo-timber-evolution-1.5m/EFL105252.html), $59.99, plus four [SPMSA370 9g servos](https://www.horizonhobby.com/product/a370-digital-9g-metal-gear-aircraft-servo/SPMSA370.html) at $13.99 each | $115.95 | The wing listing says servos are not included. The [manufacturer manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250B-Manual_EN.pdf) identifies two aileron, two flap, one elevator, and one rudder servo. The four wing servos and two already-priced tail servos partition those six reference positions without overlap. This is a reference-aircraft proxy, not proof of the fictional build. The wing and servo offers were observed 2026-10-15; the servo listing was backordered with an October 2026 estimate at that observation. |

The five previously priced rows total $332.94. With these two integrated estimates, the known subtotal is $465.87 across seven of the twelve physical inventory groups. This is a partial proxy subtotal, not a replacement total. Five physical groups and final assembly and commissioning remain unpriced; `replacement_total_minor` stays null. The virtual `ballast_reference` is excluded.

## Remaining rows and candidate offers

New prices below were captured on 2026-10-16. They provide source-backed part candidates, but they are not counted in the $465.87 subtotal because they do not establish complete, non-overlapping coverage of an economic row.

| Candidate | Price and listing state | Listed scope and valuation limit |
|---|---:|---|
| [EFL105251 fuselage](https://www.horizonhobby.com/product/fuselage-turbo-timber-evolution-1.5m/EFL105251.html) | $54.99, in stock; observed 2026-10-15 | Fuselage listing. The scope does not confirm all canopy and fittings required by `fuselage_main`. |
| [EFL105253 battery hatch](https://www.horizonhobby.com/product/battery-hatch-turbo-timber-evolution-1.5m/EFL105253.html) | $9.99, in stock | Exact reference-model hatch, but it does not close the fuselage group by itself. |
| [EFL105258 cowl](https://www.horizonhobby.com/product/cowl-turbo-timber-evolution-1.5m/EFL105258.html) | $14.99, in stock | Separate reference-model cowl. Do not add it to the fuselage offer as a complete-row total without a source inventory crosswalk. |
| [EFL5259 horizontal stabilizer and tube](https://www.horizonhobby.com/product/horizontal-stabilizer-with-tube-timber/EFL5259.html) | $19.99, in stock; observed 2026-10-15 | Prices the horizontal stabilizer only. The modeled `tail_surfaces` row also includes the vertical tail, for which no separate price was verified. Reusing the fuselage offer for the vertical fin would overlap `fuselage_main`. |
| [EFL105254 landing gear](https://www.horizonhobby.com/product/landing-gear-turbo-timber-evolution-1.5m/EFL105254.html) | $16.99, in stock | Exact aircraft compatibility and part name; the listing does not enumerate contents or confirm wheels, springs, retainer, or tailwheel coverage. |
| [EFL105255 gear retainer](https://www.horizonhobby.com/product/landing-gear-retainer-turbo-timber-evolution-1.5m/EFL105255.html) | $5.99, in stock | Two retaining plates and mounting screws. It is not a full gear assembly. |
| [EFL5258 wheel set](https://www.horizonhobby.com/product/wheel-set-timber/EFL5258.html) | $19.99, in stock | Two 108 mm main wheels plus one tailwheel. The pack crosses `gear_main` and `gear_tail`; count it at most once and do not imply it includes the tailwheel fork. |
| [EFL5268 landing-gear springs](https://www.horizonhobby.com/product/landing-gear-springs-pair-timber/EFL5268.html) | $4.99; stock not stated in the captured listing | One pair. It may overlap the existing [EFL-1249 updated gear set](https://www.horizonhobby.com/product/e-flite-complete-updated-landing-gear-set-with-heavy-duty-springs-turbo-timber-evolution-1.5m/EFL-1249.html), observed at $16.99 on 2026-10-15; do not add both without itemized scope. |
| [EFL105257 wing plug set](https://www.horizonhobby.com/product/wing-plug-set-turbo-timber-evolution-1.5m/EFL105257.html) | $14.99, backorder estimated January 2027 | Two wing plugs. The fictional inventory has no connector row, so this stays unassigned. |
| [EFLA521 LED controller](https://www.horizonhobby.com/product/led-controller-timber/EFLA521.html) | $13.99, in stock; observed 2026-10-15 | Controller only. No current source-backed price for the modeled wiring and navigation LEDs was found. |

Keep `fuselage_main`, `tail_surfaces`, `gear_main`, `gear_tail`, and `wiring_lighting` null. The gear candidates represent different revisions or bundled subparts, and the wheel set contains wheels for both landing-gear rows. The official replacement-parts list also names fuselage, battery hatch, cowl, wing set, gear, gear retainer, wheel set, horizontal stabilizer, LED controller, and individual propeller and spinner parts; this breakdown does not document every bundle's contents or an exact fictional build bill of materials.

## Whole-aircraft package scope

The [PNP package](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-pnp-includes-floats/EFL105275B.html) was listed at $299.99, and the [BNF Basic package](https://www.horizonhobby.com/product/turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html) at $349.99. Both pages list an aircraft, six metal-geared servos, motor, 70 A ESC, optional-use slats, and floats; BNF adds an AR637TA receiver. PNP requires a receiver, while both packages require a compatible transmitter, flight battery, and charger. These prices are alternatives to the component build and are not added to each other or the standalone line values.

The parts prices are current commercial proxies for the fictional inventory. No complete replacement valuation, assembly and commissioning labor amount, or foam repair recipe was established.
