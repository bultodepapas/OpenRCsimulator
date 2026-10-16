# CR-38a — Offline price upkeep

2026-10-16. [`audit_prices.py`](../../../../research/crash-economics/audit_prices.py) builds an actionable review queue from the validated source catalog and aircraft dossiers. It uses only Python's standard library and the existing generator. It does not fetch prices or modify any source, runtime catalog, incident or inventory.

From the repository root:

```powershell
python research/crash-economics/audit_prices.py --as-of 2026-10-16 --out .tools/price-review.json
python -m unittest discover -s research/crash-economics -p 'test_*.py'
```

The command writes JSON plus a Markdown companion and refuses to overwrite unrelated existing files. The explicit review date makes output repeatable. A generated report can be retained with a research review; it is not an automatically updated operating guide. The [dated queue](price-review-2026-10-16.md) and [structured details](price-review-2026-10-16.json) record this review.

## Review rules

Each offer keeps its own observation date, original availability text, sold-package description and source link. Age is computed in calendar days. The existing catalog policy marks observations `review_due` at 90 days and `stale` at 180 days, inclusively; these are upkeep thresholds, not a guarantee of current price or stock. Observations later than the supplied date are explicitly `future_observation`, never silently treated as fresh. A newer catalog snapshot cannot reset an older offer's age.

The queue records direct unit prices, constituent quantities for composite estimates, and advisory-only references separately. Variants use their authored overrides. An unmapped offer stays research/comparison evidence; the audit cannot assign a gear set, receiver or service part to an aircraft merely because its name looks similar.

Per-aircraft output distinguishes known partial subtotals, missing prices, approximations and complete *modeled* inventory estimates. An aircraft without any priced rows has a null subtotal, not zero. Complete inventory coverage can include proxies and labor assumptions; it is not a ready-to-fly retail quote or an installation qualification. Physical exclusions and aircraft-source identities remain governed by the existing dossier contract.

The audit also retains validated `service_parts` product-family crosswalks and whole-unit price references. These cannot establish installed fit or select a repair. [CR-31g](../CR-31g/README.md) records this extension and a new snapshot; the original dated queue above remains historical evidence.

## Verification

Eleven focused audit tests cover inclusive date thresholds, leap days, future observations, malformed policy/date rejection, mixed observation dates, inherited engine/prop overrides, composite quantities, unallocated comparator offers, unknown totals, deterministic output source immutability and guarded report output paths. The dated [CR-31f verification](../CR-31f/verification-2026-10-16.json) also runs generator freshness and the existing economics regressions.
