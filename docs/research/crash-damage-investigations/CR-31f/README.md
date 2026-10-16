# CR-31f — Estimate integrity and service-price research

2026-10-16. This increment strengthens the [replacement comparison](../CR-31e/README.md), its archived arithmetic and the public calculator boundary. [Service-price evidence](service-prices.md) records the accompanying SAVOX/O.S. research; [gear evidence](../CR-36f/gear.md) records package overlap and remaining fleet gaps.

## Calculation and archive behavior

An explicit affected component quantity must be positive. The calculator now rejects `replace` with `quantity: 0`, rather than returning a complete zero-cost replacement line. An empty assessment remains a valid no-damage result, and omitted quantity retains the existing installed-quantity behavior. This aligns the public calculator with inspection receipt and checkpoint validation.

Replacement comparisons now retain `selected_lines`: each selected candidate's ID, integer-cent price and sorted covered-unit IDs. New incident reports save `openrc-replacement-comparison v2`. Reopening checks the selected IDs, exact once-only unit coverage, bounded integer sum, reported total and status flags. A changed total, repeated/missing unit, unknown selected ID or missing itemized selection rejects the report. Unknown-cost and unfinished searches can retain no selected cover and a null price; they do not become zero-dollar repairs.

These checks establish internal consistency. They do not authenticate a file against deliberate coordinated editing, rerun the optimality search, verify retailer availability, or certify physical fit. The existing read-only archive cannot credit a wallet or alter a flight.

Version 1 comparison archives remain readable. Their UI uses a provisional historical label because itemized coverage was not saved. New v2 archives preserve the evidence needed for consistency checks. Reports without any comparison retain their existing behavior.

## Price details

The report labels the shared date as **Catalog snapshot** and keeps each offer's **Observed** date separate. When available, it displays **Availability when observed** using the frozen seller text. This makes an old backorder or sold-out listing visible without claiming a live inventory check. English and Spanish labels retain the prominent accident total and scrollable details.

The [offline upkeep tool](../CR-38a/README.md) supplies a dated price-review queue, per-aircraft gaps and composite reference counts. It does not automatically change incident valuations or install service parts.

## Verification

The [verification record](verification-2026-10-16.json) records **827 Godot checks across 17 focused suites and 39 Python tests**, all passing, plus catalog generator freshness and source identities. This is not the full application test matrix. The catalog contains 62 products and 69 price observations. Five aircraft dossiers remain incomplete; adding service offers does not close those gaps.

New regressions exercise zero versus positive affected counts, JSON-round-tripped selected packages, inconsistent sums/coverage/flags, unresolved comparisons, legacy archives and localized historical availability. Native [English](price-sources-en-1280x720.png) and [Spanish](price-sources-es-1280x720.png) captures show the US$5.39 incomplete lower bound beside dated seller availability. Their manifests check panel and action bounds at 1280×720, 1920×1080 and 3840×2160. Reproduce from the repository root:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --script ../research/crash-economics/capture_report.gd -- --price-sources --lang=es --size=1280x720 --out=<absolute.png>
```

Software checks do not validate structural failure, thermal thresholds or serviceability.
