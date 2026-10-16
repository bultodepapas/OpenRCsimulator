# CR-36a — Stik engine/propeller economic variants

2026-10-15. Implements the next bounded fleet slice of the [accident economics plan](../../../plans/crash-damage-economics.md). The baseline and 61FX dossiers retain their existing figures. The 55AX and FS-64V now have their own selected engine/silencer and propeller groups; the other five aircraft routes remain incomplete. This is complete coverage of the modeled inventory with estimates, not a physically qualified assembly or a retail ready-to-fly quote.

## Price evidence and package coverage

| Installed model / selected offer | USD | Observation and limitation |
| --- | ---: | --- |
| APC Sport LP12070 12×7 | 5.39 | [Manufacturer page](https://www.apcprop.com/product/12x7/?v=84de8e2b14bb), accessed 2026-10-15: product code, price and cart control shown; no inventory count. One propeller. |
| Master Airscrew K Series 14×6 | 11.65 | [Manufacturer page](https://www.masterairscrew.com/products/k-series-14x6-propeller), accessed 2026-10-15: sold out. Storefront labels the amount a sale price but gives no comparison price. One propeller. |
| O.S. MAX-55AX + E-3071 muffler | 249.99 | [Horizon OSMG0557](https://www.horizonhobby.com/product/os-engines-55ax-abl-.55-airplane-glow-engine-with-muffler/OSMG0557.html), rechecked 2026-10-15: backorder expected November 2026; muffler is included. The simulation's borrowed 121 g stock-silencer revision is not confirmed as this E-3071, so the combined economic group remains a price proxy. |
| O.S. FS-64V + F-4051 silencer | 549.99 | [Horizon OSMG901](https://www.horizonhobby.com/product/os-engines-o.s.-fs-64v-61t2-with-f-4051-silencer/OSMG901.html), rechecked 2026-10-15: in stock; one engine and one silencer. [O.S. 3AY00](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html) identifies the F-4051 and 442 g/44 g engine/silencer masses. |

These are observed listing values, excluding tax/shipping; no checkout or stock guarantee is implied. The two new propeller observations live in `research/crash-economics/price-research-components.json`; existing engine observations retain their original identities and amounts. `build_catalog.py` generates 34 products and 36 offers. Price research does not change partner status or hardware in the solver.

The Master Airscrew page does not publish a manufacturer SKU. The stored `MAS1460` is the [AMain retailer identifier](https://www.amainhobbies.com/master-airscrew-14x6-kseries-propeller-mas1460/p97682), corroborating the K Series model; its June 2026 backorder date is stale and is not used for current availability. No invented `K1460` manufacturer code is used. The manufacturer lists 58.1 g; the physical model retains its existing 60 g estimate. O.S. FS-64V's Horizon SKU is `OSMG901`, not an inferred zero-padded identifier.

## Reconciliation and arithmetic

The authored [fleet costing source](../../../../research/crash-economics/aircraft-costing.json) inherits the baseline and replaces two whole economic groups: `engine_and_muffler` and `propeller`. Each group retains its physical coverage and quantity. Explicit expected name, mass, position and energy-source fields bind all three changed physical items. Expected propulsion names bind the installed configuration and its contact ID. Every other nonvirtual inventory item must match the baseline signature. Added/removed items or changed quantities require a separately authored BOM.

The generator rejects missing/duplicate pins, partial coverage groups, unknown offers, propulsion mismatches and unreviewed inherited hardware differences. Replacement by group ID prevents charging both the old engine and its replacement, or charging an included muffler twice. The runtime format and shared simulation kernel need no new aircraft-specific branches.

| Configuration | Engine/silencer | Propeller | Estimated assembled replacement | Conditional two-servo reuse |
| --- | ---: | ---: | ---: | ---: |
| Baseline / 61FX | 249.99 proxy | 5.39 | 994.33 | 926.35 |
| 55AX | 249.99 group proxy | 5.39 | 994.33 | 926.35 |
| FS-64V | 549.99 | 11.65 | 1,300.59 | 1,232.61 |

FS-64V arithmetic in integer cents: `99,433 - 24,999 - 539 + 54,999 + 1,165 = 130,059`. The illustrative two-servo credit is `2 × 3,399 = 6,798` cents. Reuse must be explicitly established by an assessment; these fixtures do not infer surviving servos from a crash.

Seven shared groups remain unchanged: constructed airframe/installation allowance, three fuselage servos, central aileron servo, receiver, NiMH pack, onboard fuel and final assembly. Their estimate/proxy notes and exclusions remain visible. In particular, four generic physical servos are valued with the existing SAVOX proxy; this does not install SAVOX hardware. Airframe/mount compatibility, experimental propeller performance, individual repair recipes and service/inspection rates remain unresolved physical or economic work. Stock availability is separate from cost coverage.

## Verification

Pinned Godot 4.7.2 Windows headless and Python. [Verification record](verification.json) includes commands, result counts and relevant source hashes.

- Python runtime contract: 16 tests, including variant replacement, unchanged shared groups, deliberate in-memory authoring mutations and a price refresh that leaves physical identity/baseline data unchanged. No deliberate mutation touches a live aircraft file.
- Godot catalog: 69 checks; all nine routes load and exactly five retain missing coverage.
- Godot calculator: 43 checks; replacement totals, one engine/propeller line, incomplete inspection totals and conditional reuse arithmetic.
- Godot production integration: 51 checks; existing baseline/lifecycle/cadence checks plus both variant prop strikes and the sold-out offer in the frozen FS-64V report.

The variant fixture invokes the real glow starter, places the initialized aircraft at a controlled endpoint with 1 mm prop-disc penetration, then calls the production contact callback and frame-boundary report path. It proves source-to-report integration, not a naturally flown nose-over trajectory. An earlier attempt to reuse the baseline's unstarted runway trajectory fixture reached a rejected glow joint step; it is not accepted as flight evidence. The variants retain their existing experimental-physics warnings. No solver, mass, propeller coefficients, golden flight or geometry changes are part of CR-36a.

Reproduce:

```powershell
python research/crash-economics/build_catalog.py --check
python research/crash-economics/build_runtime.py --check
python research/crash-economics/test_runtime_data.py
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_economy_catalog.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_economy_calculator.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_accident_integration.gd
```

CR-36 remains partial: Extra, P-51, Avanti, Turbo Lumber and X-Cell need reconciled dossiers. CR-33–35 structural, gear/scenery and thermal assessments, physical salvage qualification and full packaged-target acceptance remain open. This slice does not rerun the whole repository suite.
