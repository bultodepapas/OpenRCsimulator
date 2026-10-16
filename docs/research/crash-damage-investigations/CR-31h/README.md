# CR-31h — Pending salvage is unknown

2026-10-16. An explicit total-loss assessment with an `inspect` or `unknown` component previously returned `salvage_minor: 0` even while the same report said salvage or condition was unresolved. Zero is a known value and incorrectly implied that no recovery value remained possible.

The calculator now returns `salvage_minor: null` for those pending dispositions unless `salvage_eligible: false` explicitly rules out credit. This applies whether the component price is known or missing. A complete no-salvage assessment still returns zero. Confirmed reuse still creates the existing negative credit lines and reduces the known subtotal once; when another component is pending, the aggregate salvage value remains unknown. This change does not authorize reuse or add a new probability, recovery interval or physical inspection rule.

Existing read-only accident archives remain as recorded. The corrected semantics apply to newly calculated assessments; this change does not rewrite historical reports.

The focused regression includes known-price and unpriced pending components, unknown condition, mixed confirmed/pending recovery, explicit ineligibility and complete loss. [Verification](verification-2026-10-16.json) records **899 Godot checks across 18 focused suites and 60 Python tests**, all passing, plus generator freshness. This is not the full application test matrix. Software checks do not establish physical crash or fire validation.

The accompanying [CR-38b workflow](../CR-38b/README.md) adds frozen price-revision comparison and sale-quote review. Six new radio/service offers expand the catalog to 77 observations while leaving all installed aircraft costs unchanged. See the [radio](../CR-36h/radio.md) and [service-part](../CR-36i/service.md) evidence for exact source dates and compatibility limits. The [active plan](../../../plans/crash-damage-economics.md) retains structural/thermal qualification and complete fleet valuation as open work.
