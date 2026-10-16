# CR-31e — replacement comparison in the accident report

2026-10-16. The replacement comparison connects the bounded [package optimizer](../CR-31d/README.md) to an assessed aircraft's replacement rows. It is a parts estimate, separate from the repair/loss calculation and any eventual inventory transaction.

## Scope

`ReplacementQuote.quote(dossier, assessment, package_candidates, search_limit)` first validates the dossier and assessment with the existing calculator. It builds explicit installed-unit coverage for rows whose calculated action is replacement. Inspection, reuse, salvage and repair-only rows do not become replacement purchases. A whole-aircraft total-loss assessment requires its existing salvage calculation and is outside this helper's scope.

Each affected unit receives a deterministic `component_id:index` coverage token within the quote, bounded to 64 units. These indexes enumerate fungible replacement quantities; they do not identify physical positions, serials or independently simulated actuators. Default individual candidates use the frozen dossier's unit estimate, including null prices. Their eligibility is an economic comparison assumption, not a stock check or proof of physical fit. An authored alternative must supply its exact coverage, integer-cent price or null, availability, compatibility and provenance. The helper never guesses package contents from a product name. Overlapping candidates cannot both be selected.

An optimal replacement subset does not make the whole accident estimate complete. Unknown prices or a search limit prevent a proven minimum. A failed or empty comparison never becomes a zero-dollar repair. Selected packages are alternatives to individual replacements, not extra charges; the existing calculator remains the sole source of the accident headline and salvage credit.

## Incident and UI boundary

The incident calculates its default comparison at the existing frame-boundary report publication, outside accepted physics callbacks. The report stores a bounded, view-only comparison beside the frozen catalog identity. Archive reopening displays that snapshot; checkpoint continuation derives it again from the restored assessment and frozen dossier.

The expanded English/Spanish report shows the replacement estimate, whether it is proven or provisional, and remaining inspection uncertainty. The large accident amount and its existing completeness label remain the primary result. No live pricing request, purchase, automatic option application or wallet change occurs.

The incident's explicit comparison API also accepts authored alternatives for a caller's review. A retail package authoring/selection screen and workshop inventory transactions remain separate work; the production default comparison does not silently install aftermarket components.

## Verification

The [focused verification record](verification-2026-10-16.json) reports **802 Godot checks across 17 suites and 27 Python tests**, with zero failures; both catalog generators pass freshness checks. It records commands and source/output hashes. This is not the full application test matrix.

The adapter's 29 checks cover actual Stik prop pricing, grouped units, unknown values, package overlap, explicit compatibility/availability, bounded search, invalid inputs and input purity. Production tests exercise contact → frame-boundary comparison → archive → checkpoint and confirm the accident amount is not doubled. UI tests cover proven/provisional/unknown states, localization and panel/action bounds. The same focused run includes the [isolated resolver's](../CR-33c/resolver-contract.md) 35 checks and the [fleet proxy update](../CR-36e/fleet.md). These checks establish software behavior and readability, not structural or return-to-service qualification.

Native captures: [English](parts-comparison-en-1280x720.png), [Spanish](parts-comparison-es-1280x720.png). Both retain the large US$5.39 lower bound and a separate parts comparison. The capture manifests check panel and action bounds at 1280×720, 1920×1080 and 3840×2160. Reproduce from the repository root:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --script ../research/crash-economics/capture_report.gd -- --parts-comparison --lang=es --size=1280x720 --out=<absolute.png>
```
