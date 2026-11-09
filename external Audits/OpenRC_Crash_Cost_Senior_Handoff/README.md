# OPEN RC SIMULATOR — crash-cost implementation handoff

**For:** the senior developer responsible for game implementation. **Prepared:** 2026-11-09. **Purpose:** turn the external crash-cost audit into a concrete, bounded engineering plan that works across the existing airplane fleet and establishes a standard for future aircraft.

Start with [01_EXECUTION_PLAN.md](01_EXECUTION_PLAN.md). The package contains 19 sequenced work packages, source-linked runtime and data specifications, a per-aircraft price workbook, 46 proposed acceptance cases, eight release gates, dated research and a verified portable reproduction tool. The combined reading copy is [OPENRC_CRASH_COST_SENIOR_HANDOFF.md](OPENRC_CRASH_COST_SENIOR_HANDOFF.md). The modular documents are the editing homes; regenerate the combined copy after changing them.

**Main recommendation:** retain the useful economics foundation and finish the path from accepted local contact to automatic game assessment, compatible repair/purchase choices and an explainable cost. Preserve surviving components where the declared policy supports them. Keep missing facts and prices explicit. Remove the economics experimental label only after useful common-incident coverage and the actual player flow pass for the promised configurations.

## Files and reading order

| File | Use |
| --- | --- |
| [01_EXECUTION_PLAN.md](01_EXECUTION_PLAN.md) | Product boundary, existing reuse, 19 work packages CC-00–18, owners, dependencies, exact done conditions, merge order and first developer session |
| [02_RUNTIME_IMPLEMENTATION_SPEC.md](02_RUNTIME_IMPLEMENTATION_SPEC.md) | Current call graph; accepted observations, batching, bounded summaries, damage assessment, component progression, receipts, aftermath and restore boundaries |
| [05_DATA_CONTRACT_AND_AUTHORING_STANDARD.md](05_DATA_CONTRACT_AND_AUTHORING_STANDARD.md) | Closed v1 constraints; proposed companion profile, physical/financial identities, zones, fingerprints, prices/packages/recipes, migration and future authoring rules |
| [04_FLEET_AND_PRICE_WORKBOOK.md](04_FLEET_AND_PRICE_WORKBOOK.md) | All 12 catalog routes, actual component IDs and quantities, 27 reviewed observations, 17 additional/rechecked observations, two unpriced leads and source-specific blockers |
| [03_TEST_AND_RELEASE_SPEC.md](03_TEST_AND_RELEASE_SPEC.md) | 46 proposed cases, independent arithmetic, real player journey, checked commands, eight gates, independent-review objections and portable baseline reproduction |
| [06_RESEARCH_AND_BASELINE_NOTES.md](06_RESEARCH_AND_BASELINE_NOTES.md) | GitHub drift, existing project documents, why ranges widen, new findings, research queue, 40/500 km/h reasoning and exact verification limits |
| [data/acceptance_matrix_proposed.json](data/acceptance_matrix_proposed.json) | Machine-readable cases and handoff clarifications; every case remains proposed/unexecuted |
| [data/price_observations_reviewed_2026-11-09.json](data/price_observations_reviewed_2026-11-09.json) and [data/additional_price_research.json](data/additional_price_research.json) | Prospective import evidence; keep native currencies, sold quantities, compatibility limits and correction history |
| [tools/reproduce_baseline.py](tools/reproduce_baseline.py) | Verified portable reconstruction and execution of the historical focused economics tests; requires the exact repository revision and engine |
| [evidence/verification_scope.json](evidence/verification_scope.json), [evidence/reproducer_verification/summary.json](evidence/reproducer_verification/summary.json) and retained reports | Distinguish historical execution, fresh isolated reproduction and unexecuted future acceptance |

Repository paths in prose are relative to the repository checkout. Handoff links are relative to this folder. Pinned GitHub links retain audit line locations even when current `main` moves. Generated JSON/schema fragments in files 02/05 are **proposed interfaces**, not production-ready files that can be pasted into closed v1 data.

## Source baseline and limits

The audited source is `f47d1dc6cccb141936407d0217eafdc465558190`. During preparation, GitHub `main` was observed at `f7b58bd830d4a5eb78901d00514ce1fc18286477`, nine commits ahead. The reviewed comparison contains 217 changed paths; all 13 economics GDScript blobs match the audit commit. Nearby flight/session/graphics changes mean the implementation base and integration evidence still require a fresh explicit choice. File 06 explains this distinction.

Production source was not changed for this handoff. No new game implementation, PR, deployment, normal graphical flight or release qualification is claimed. The portable reproducer did execute a fresh isolated import, 12 existing scripts with 674 assertions, and ten current-behavior probes successfully at the pinned old commit. Those probes include demonstrations of defects; passing them does not mean those defects were fixed. The 46 proposed acceptance cases are separate work for the developer.

The delivery goal is all 11 fixed-wing configurations, including three retained glow variants. Every essential affected group for the declared common incident classes must have an applicable price or reviewed game allowance, along with a working assessment path. One propeller bill per route is an early vertical-slice demonstration, not completion. The X-Cell research helicopter is separately gated; it cannot inherit prices from its visual surrogate or be reported as free because its inventory is empty.

## Decisions already made in this handoff

- Use an automatic deterministic game assessment as the minimum normal-player experience. Receipts preserve provenance and revision control; a debug-injected final inspection is not an acceptable implementation of that experience.
- Preserve physical inventory and generated physics. Use versioned companion financial children and coverage mappings where a lump contains separately assessable purchasable parts.
- Use accepted local evidence, bounded episode summaries and supported proxies. A terminal flight flag or forward speed alone cannot identify every destroyed part. The first release must add the ordinary gear observation/proxy needed by its own normal/hard landing claims.
- Keep incident completeness separate from the whole-build price book. Explain unresolved damage, source-price variation and alternate repair plans separately.
- Support bounded package pairs, surplus and overlap without a persistent inventory or cash-sale system. Charge a supplied unit once; reuse and unvalued surplus are different facts.
- Preserve frozen historical prices at P0. A new quote is a separate optional version. Timed thermal aftermath is conditional on a declared capability; deterministic pending/disclosure and accepted-hazard preservation are mandatory.
- Review the Corsair wing source conflict before exact import. The reviewed price JSON corrects eight overstrong variant/coverage labels across P16–P22 and P24, including Corsair gear/fuselage and the A200 commercial-package revision.
- Require actual normal-route owner/assessment/report/archive evidence, 1080p usability, candidate-specific required CI and independent critique before removing the relevant experimental label.

These decisions bound the first release. They do not require a finite-element model, universal real-world survival percentages, a shopping service, a campaign wallet or flying arbitrarily damaged aircraft. Useful, consistent local game outcomes with disclosed assumptions are the intended result.

## Evidence and correction policy

The original audit evidence is retained under `evidence/`. Its price observations and 43-case matrix remain historical. Current prospective price research is under `data/`, with explicit variant and package-coverage corrections. The current acceptance matrix retains all original IDs and adds AC-44–46; its labeled handoff clarifications resolve release-scope and priority details without asserting execution.

The reproducibility record includes manifests, logs, checked reports and probe output. Generated copies of repository source/data, Godot imports and an isolated user profile are omitted from the deliverable; reconstruct them from the exact repository with the included tool. Do not execute the historical path-specific runner as though it were portable. No engine binary is bundled.

Use the module owning each topic as authoritative: file 01 for promised product scope and sequence, 02 for runtime flow, 05 for data/validation, 04 for research, and 03 for acceptance. If a future change creates a contradiction, resolve it in all affected homes and record the decision before implementing. Existing production code remains the authority for what is implemented; the handoff specifies what should change.

## Suggested handoff note

Please implement the crash-cost work in the order defined in file 01, beginning with baseline reconciliation, the companion identity contract and discriminating regression fixtures. Preserve the useful existing economics code and the repository's generated-data, transaction and verification boundaries. Deliver a complete normal-player automatic assessment path for each supported airplane, with localized parts/labor costs, compatible packages, appropriate component reuse and visible assumptions. Return the candidate commit, per-route coverage ledger, executed test/gate evidence, price-source decisions, migration/rollback behavior and remaining limits. Do not mark the model standard solely by removing a label or making a range look narrower.
