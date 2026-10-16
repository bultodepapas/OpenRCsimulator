# CR-38b — Price revision comparison and sale review

2026-10-16. The offline upkeep workflow now compares two frozen price-review snapshots and explicitly flags recorded sale quotes for rechecking. It never writes an offer into an aircraft, selects a repair, changes an incident or refreshes a saved bill.

## Reproduce

From the repository root:

```powershell
python research/crash-economics/audit_prices.py --as-of 2026-10-16 --out .tools/current-price-review.json
python research/crash-economics/compare_prices.py --before docs/research/crash-damage-investigations/CR-31g/price-review-2026-10-16.json --after .tools/current-price-review.json --out .tools/price-changes.json
python -m unittest discover -s research/crash-economics -p 'test_*.py'
```

The explicit review dates allow multiple revisions on one date. The output retains SHA-256 identities of both input snapshots, both recorded observations and their aircraft/component reference roles. JSON and Markdown outputs cannot overwrite an input snapshot or an unrelated existing file. Input JSON rejects duplicate keys, nonfinite numbers, invalid currencies/counts, duplicate offer IDs and invalid aircraft-reference quantities. Files are bounded to 16 MiB and 10,000 observations.

## Comparison rules

A signed price delta is per sold package, not per aircraft. It requires matching offer ID, brand, SKU, product name, package description, seller URL, currency, price kind, condition, market and tax/shipping terms. Changed product/package/seller terms, missing commercial terms, backwards observation dates and future-dated evidence receive a null delta and a review reason. Additions and removals also have null deltas: an absent offer is never treated as a zero-dollar price.

Availability changes and observation refreshes retain both seller texts/dates. Reference-only, direct unit-price and composite-constituent uses remain distinct. A changed allocation does not imply another purchase, and a comparable quote does not guarantee stock or fit. No percentage discount or aircraft bill is inferred from this comparison.

Review-date aging alone is not an offer change. Adding commercial metadata absent from an older snapshot alone also does not create a price change. Legacy snapshots remain readable; if their recorded price/evidence changes, missing commercial terms prevent a numeric delta until reviewed. The [age audit](../CR-38a/README.md) remains the source for calendar review/stale thresholds.

The audit now retains commercial terms and flags `live_retailer_sale_price` and `live_us_retailer_sale_price` observations when the catalog's `sale_price_requires_refresh` policy is enabled. A sale-recheck flag is separate from the age status: a fresh observation does not establish the promotion's expiry. New sale kinds must be explicitly added to the review policy vocabulary.

## Dated result

The [new review queue](price-review-2026-10-16.md), [structured review](price-review-2026-10-16.json), [change table](price-changes-2026-10-16.md) and [structured comparison](price-changes-2026-10-16.json) record 77 observations: six additions, 71 unchanged observations and three sale quotes requiring recheck. There are eight named-model service crosswalks. All six additions remain unallocated; the nine aircraft routes, five incomplete dossiers and existing installed subtotals remain unchanged. The baseline Stik remains a US$994.33 modeled assembled estimate, not a verified ready-to-fly retail quote.

The added [radio offers](../CR-36h/radio.md) are Spektrum AR620, Futaba R3006SB and RadioMaster ER6G, with their distinct protocols, supply ranges and package contents. The added [service offers](../CR-36i/service.md) are the Savox SC0252MGP case set and O.S. MAX-55AX gasket set/cylinder head. Unresolved stock and sale prices remain explicit. These price observations do not establish repairability or another manufacturer's partnership.

Thirteen comparison tests cover signed/zero prices, additions/removals, scope changes, missing commercial terms, dates, availability, reference roles, immutability, malformed input, historical snapshots and guarded output. The audit test also checks fresh sale quotes and disabling the explicit sale-review policy. Full focused results are linked from [CR-31h](../CR-31h/README.md).
