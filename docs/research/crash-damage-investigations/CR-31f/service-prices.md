# CR-31f — Service-part price evidence

2026-10-16. Five US-dollar service-part listings are integrated in the [canonical component price research](../../../../research/crash-economics/price-research-components.json) and generated price/runtime catalogs. The figures are part-specific repair candidates, not complete replacement quotes. No aircraft BOM or repair recipe automatically selects them.

| Part | Explicit model link | Price | Quantity and page state |
| --- | --- | ---: | --- |
| Savox `CSC0254MG` case set | SC0254MGP product page lists this case under Spare Parts | $5.49 | One top-and-bottom set with screws; Add to Cart, stock count not shown |
| Savox `SGSB2270SG` gear set with bearings | SB2270SGP product page lists this gear set under Spare Parts | $38.99 | One gear-set package; Add to Cart, stock count not shown |
| O.S. `25702000` crankshaft | MAX-55AX parts list identifies this crankshaft | $49.99 | One crankshaft; Tower says In Stock |
| O.S. `4AY02000` crankshaft | Tower identifies it as the FS-64V crankshaft; the O.S. FS-64V manual is the model parts reference | $54.99 | One crankshaft; Tower says In Stock |
| O.S. `40625010` F-4051 silencer | Tower identifies it for FS-64V; O.S. describes the F-4051 as its FS-V-series silencer | $44.99 | One silencer; Add to Cart, explicit stock state not shown |

The Savox fit links are from their Plus-model product pages, which list the suffixless part codes in the Spare Parts section. The listed packages therefore have a manufacturer crosswalk to the priced Plus models; the pages do not establish repair success after a crash or installation in any Ugly Stik servo position. The O.S. parts are tied only to their named engine variants. In particular, the MAX-55AX crankshaft must not be applied to the physical MAX-61FX/E-4010 group: the MAX-55AX engine price is only an economic proxy there.

For integration, use a part price only after inspection identifies damage to that part and the matching engine or servo model. Price the repair option separately from whole-unit replacement, and do not charge both for the same unit. These listings include no labor, diagnostic fees, repair probability, or salvage credit; prices exclude tax and shipping. No foreign-currency conversion is used.

## Sources

- Savox price listings: [CSC0254MG case](https://servos.net/products/savcsc0254mg-top-bottom-servo-case-with-4), [SGSB2270SG gear set](https://servos.net/collections/replacement-parts/products/savsgsb2270sg-gear-set-with-bearings). Their compatibility crosswalks are shown on the [SC0254MGP page](https://servos.net/collections/servos/products/savsc0254mgp-standard-digital-servo-0-14sec) and [SB2270SGP page](https://servos.net/collections/servos/products/savsb2270sgp-high-voltage-brushless-digital).
- O.S. price listings: [MAX-55AX crankshaft](https://www.towerhobbies.com/product/crankshaft-55ax/OSMG4467.html), [FS-64V crankshaft](https://www.towerhobbies.com/product/crankshaft-o.s.-fs-64v/OSMG903.html), and [FS-64V F-4051 silencer](https://www.towerhobbies.com/product/f-4051-silencer-o.s.-fs-64v/OSMG906.html). Manufacturer compatibility references: [MAX-55AX parts diagram/list](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/pdf/15612_55AX.pdf), [FS-64V product page](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html), and [FS-64V manual](https://www.os-engines.co.jp/english/line_up/engine/air/single/img/manual/3AY00.pdf).

The canonical JSON retains observation details, availability wording, structured `service_compatibility` evidence and `whole_unit_reference` links. The generated offers retain price/date/source/notes. Adding these offers does not alter any aircraft valuation, physical configuration, repair recipe or salvage outcome.
