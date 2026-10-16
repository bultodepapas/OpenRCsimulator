# CR-36c — Fleet component valuation

2026-10-15. The canonical source is `research/crash-economics/aircraft-costing.json`; dated offers live in `price-research-components.json` and `price-research-fleet.json`. Generate their runtime artifacts with the documented CR-29 commands. The catalog now contains 48 products and 55 observations; existing offer IDs and old report snapshots are preserved.

| Route | Known parts subtotal | Replacement completeness |
| --- | ---: | --- |
| Turbo Lumber Evolution | $332.94 | Five commercial proxy rows; seven physical groups and assembly remain unpriced. |
| P-51D 120 | $2,006.71 | DA-120 plus seven large-control and two throttle/choke servo proxies. Airframe, propeller, retracts and other rows remain unpriced. |
| Avanti S A200 / P100-RX | $6,559.12 | Matched no-retract ARF, legacy P100-RX, optional A200-16 tank, and eight servo proxies split by the manual's recommended classes. Pneumatic gear and additional installation rows remain unpriced. |
| X-Cell research | Unknown | The physical route has no inventory IDs/counts. No HX-700 visual-model prices or invented physical BOM are assigned. |

These are **known parts subtotals**, not complete replacement prices, checkout quotes or automatic accident bills. Full replacement and upper loss bounds remain null. Four Stik routes retain their existing complete estimated inventory coverage; the Extra retains CR-36b partial coverage. All nine routes are discovered from the application catalog.

See [electric sources and package decisions](electric.md) and [large-aircraft/X-Cell sources](large-aircraft.md). The electric propeller row also contains its spinner, so a single propeller offer is not attached to that entire row or billed automatically. PNP/BNF packages, spare wing/gear assemblies and unrelated retract kits remain comparison offers until their coverage is reconciled. The Avanti tank is optional in the manufacturer's manual and absent from the seller's listed ARF contents; separate costing is an explicit package-scope inference. Its priced ARF is not combined with the alternative ARF-plus-electric-gear offer.

Each independent dossier pins the reviewed physical file hash, maps nonvirtual inventory once, retains null prices, and carries aircraft-specific servo counts and contact mappings. Unit-price references never change physical mass, power, torque or installation compatibility. The price-class proxy review changed the large aircraft from the baseline's low-cost standard servo to appropriate commercial comparison classes; this is still not a hardware qualification.

Python and Godot tests verify physical coverage, exact subtotals, null whole-aircraft totals, unique allocation, package exclusion, and the absence of a fabricated X-Cell BOM. Evidence and limits of the surrounding implementation are in CR-31b/c, CR-33a/b and CR-35a. Complete fleet prices, individual repair kits, physical failure thresholds and damage-to-flight coupling remain open.
