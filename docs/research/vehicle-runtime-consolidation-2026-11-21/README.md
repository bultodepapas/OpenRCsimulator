# Vehicle runtime consolidation — source review and adversarial controls audit

**Final delivery:** all audit evidence and the latest plan are together on
`audit/game-controls-2026-11-21`. The [delivery entry point](../game-controls-audit-2026-11-21/README.md)
links the complete package; the master plan below remains the sole VRC status ledger.

**2026-11-21.** Runtime baseline `57abea025f62b20233ca281d58d2acbee4ab8b8e`; original published plan `542d92b304fc3b82678c4a90b848a88d82df0b22`. Three independent source-review contexts challenged architecture, controls and evidence and then reviewed the lead's revised proposal. This is an automated external-style plan audit, not third-party certification or runtime qualification.

**Result:** ten plan findings addressed; forty explicit acceptance cases proposed and **UNRUN**. The existing five GCA defects remain unfixed by this branch. The [master plan](../../plans/vehicle-runtime-consolidation.md) owns VRC-00…VRC-11 status; all implementation remains open.

**Organization refinement:** continued from `8d61ca900a30686bc00eaf5ce80bee664e592a46`, with three fresh, bounded source-review contexts for persistence, control routing and an opposing architecture review. The lead traced material counterexamples and integrated the simpler alternatives. The new blueprint resolves module ownership, the fixed-wing PauseMenu retain-or-extract decision, route scope, save/activation/failed-restoration outcomes, stale-editor/legacy-origin conflicts and developer work packages. Primary research is version-scoped guidance. These source-derived scenarios are not additional executed gameplay findings.

| Read | Purpose |
| --- | --- |
| [IMPLEMENTATION-BLUEPRINT.md](IMPLEMENTATION-BLUEPRINT.md) | Concrete organization, first consumer, save/recovery design, conflict policy and ordered work packages |
| [organization-map.json](organization-map.json) | 24 pinned source files, 114 symbol anchors, route/observation/work-package references and 26 existing test starting points |
| [action-consumers.json](action-consumers.json) | All 37 semantic action definitions, six AUX channel names and five UNRUN quad examples; other combinations remain uncharacterized |
| [PRIMARY-SOURCES.md](PRIMARY-SOURCES.md) | Official Godot/SDL and platform documentation, applicability, unavailable pinned-engine proof and resulting decisions |
| [EXTERNAL-AUDIT.md](EXTERNAL-AUDIT.md) | Findings, pinned evidence, adversarial decisions and scope |
| [CONTROL-CONTRACT.md](CONTROL-CONTRACT.md) | Authority, temporal input, family policy, persistence, lifetime and response obligations |
| [CONTROL-ACCEPTANCE.md](CONTROL-ACCEPTANCE.md) | Generated human-readable forty-case acceptance matrix |
| [control-cases.json](control-cases.json) | Canonical case IDs, owners, triggers, oracles, test starting points and UNRUN statuses |
| [QUALITY-GATES.md](QUALITY-GATES.md) | Baseline/runner, replay identity, native, real UI/device, response, promotion and rollback gates |
| [MIGRATION-MATRIX.md](MIGRATION-MATRIX.md) | What to retain/share/defer and the smallest useful first bridge |
| [SOURCE-INVENTORY.md](SOURCE-INVENTORY.md) and [inventory.json](inventory.json) | Corrected ten-file scan with pinned identities and reproducible counting method |
| [audit-findings.json](audit-findings.json) | Machine-readable findings and case/source traceability |
| [verification.json](verification.json) | Preserved initial audit receipt for the artifacts at `8d61ca9`; not a current badge |
| [organization-verification.json](organization-verification.json) | Preserved static receipt for the refined snapshot at `2e812ef`; its navigation-file hashes describe that snapshot |
| [consolidated-plan-verification.json](consolidated-plan-verification.json) | Fresh static plan/data/reference receipt for the combined branch; no runtime execution |
| [Checker and rerun guide](../../../research/vehicle-runtime-consolidation/README.md) | Reproduce static checks and regenerate the matrix; no engine launch |

The [prior controls audit](../game-controls-audit-2026-11-21/AUDIT.md) supplies five baseline defect witnesses and the historical 22-of-27 regression result, with five failed/incomplete programs. Its report, scripts and evidence are now included in this branch, preserved from `895dd4352c5191f1539a8b8f4df1996cd33eb86f`; they were not rerun during consolidation. A passing adverse witness is not a repaired control path.

The chosen first consumer is fixed-wing PauseMenu and its full existing Continue chain. Retain its current reads unless a candidate projection removes a named duplicated decision/dependency; the required intent boundary may remain the existing proven AppRoot route. Other operations/families remain with their owners. Optional consolidation does not block confirmed controls repairs.

Nine case definitions were refined in the organization continuation; the human matrix is regenerated from the same canonical JSON, with all forty executions still UNRUN. The [initial published snapshot](https://github.com/bultodepapas/OpenRCsimulator/tree/8d61ca900a30686bc00eaf5ce80bee664e592a46/docs/research/vehicle-runtime-consolidation-2026-11-21) preserves the original wording and receipt. The organization receipt hashes the artifacts published at `2e812ef`; both historical receipts remain unchanged. Consolidation updates navigation, so their historical navigation hashes are not current-tree badges. The separate combined-branch receipt hashes the current plan artifacts and verifies the initial receipt's preservation. Requested helper settings for the organization review were `gpt-6.1-terra` / `max`; effective runtime routing was not independently observable. Review consensus is not acceptance evidence.
