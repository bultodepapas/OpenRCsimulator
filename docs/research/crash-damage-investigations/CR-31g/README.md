# CR-31g — Repair scope and service-reference integrity

2026-10-16. This increment preserves the scope of an explicitly selected repair, exposes its itemized cost in the accident report and carries service-part evidence through the research generator and offline audit. The [active plan](../../../plans/crash-damage-economics.md) owns remaining work.

## Comparable repair decisions

An inspected covering patch and a grouped airframe replacement do not necessarily cover the same work. Previously the planner could correctly mark replacement as noncomparable, but the calculator ranked the selected repair against the dossier price anyway. A cheap reference price could silently turn the selected repair into a replacement.

Planner-selected repair decisions now retain `replacement_comparable: bool` through the inspection receipt. `false` preserves the selected known repair cost and inspection fee, with an unknown replacement comparator; it does not make the known repair bill incomplete. `true` retains same-scope comparison. Omitted flags preserve legacy receipt behavior. The flag is valid only on repair rows and cannot be a string or number. Checkpoint reconstruction and saved report evidence preserve the choice.

## Current repair breakdown

The expanded report shows the selected material costing basis, purchase versus consumption cost, labor mode and time, repair subtotal and separate inspection cost. It derives these from the existing receipt and frozen recipe provenance. Only the latest inspection affecting that component can support the displayed repair. Superseded, ambiguous or malformed choices are omitted; opening the report never recalculates a charge or changes the headline amount.

The native capture fixture uses a synthetic inspected 10.5-square-inch covering patch: US$0.14 consumed material, 30 minutes of paid labor at US$45/hour (US$22.50), and US$5.00 inspection, for **US$27.64**. The alternative cash material purchase is shown separately and is not added to the consumed-material bill. This is a software presentation fixture, not a measured crash or quoted repair-shop invoice.

## Service references and price upkeep

The research catalog now emits `service_parts` crosswalks for the five [SAVOX/O.S. service offers](../CR-31f/service-prices.md). Each binds the exact named product family, supporting URLs and a known whole-unit price reference. Generation rejects missing pairs, duplicate identities, unknown/self references, service-to-service chains, unsupported evidence fields and malformed source URLs. Runtime generation rejects a missing or changed generated crosswalk even when its price source hashes still match.

These rows explicitly retain `aircraft_applicability: not_established` and `automatic_repair_selection: false`. They are research evidence, not installed BOM additions or qualified repair recipes. A whole-engine price proxy cannot establish that its internal parts fit the simulated installation.

The refreshed [price-review queue](price-review-2026-10-16.md) and [JSON](price-review-2026-10-16.json) preserve these relationships alongside 71 observations, nine aircraft routes and five incomplete dossiers. The two new USD offers remain unallocated; existing prices and installed subtotals are unchanged. New [receiver-power/fuel research](../CR-36g/power.md) records candidate offers and package/electrical gaps separately from installed valuations.

## Verification

The [verification record](verification-2026-10-16.json) records **895 Godot checks across 18 focused suites and 46 Python tests**, all passing, plus generator freshness and source identities. Seven new Python tests exercise service crosswalk preservation, mutation rejection and isolation from aircraft BOMs. Runtime regressions exercise repair scope, receipt types, provenance, supersession and display arithmetic.

Native [English](repair-details-en-1280x720.png) and [Spanish](repair-details-es-1280x720.png) captures retain the large total above the scrollable repair detail. Their manifests check panel/action bounds at 1280×720, 1920×1080 and 3840×2160. Reproduce with:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --script ../research/crash-economics/capture_report.gd -- --repair-details --lang=es --size=1280x720 --out=<absolute.png>
```

These are focused software checks, not the complete application matrix or physical crash/fire validation. Automatic structural and thermal billing still requires the measurement and aircraft qualification gates in CR-33…37.

The standard `app/test.sh` entry point now discovers all economics Python tests, including the service-reference, audit and observation-date checks. Its existing GDScript discovery includes the new repair-detail suite.
