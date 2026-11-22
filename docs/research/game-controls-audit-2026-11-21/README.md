# Game controls audit — 21 November 2026

Senior engineering review of device ownership, calibration, conditioning, profiles,
menu routing and activity recovery. Baseline: `main` at
`57abea025f62b20233ca281d58d2acbee4ab8b8e`. **Final delivery branch:**
`audit/game-controls-2026-11-21`. Production application files are unchanged.

## Start here — consolidated final delivery

This branch contains the complete controls audit, its diagnostic evidence and
the latest adversarial implementation plan. Continue development on this branch.
The original audit at `895dd4352c5191f1539a8b8f4df1996cd33eb86f` and the refined
plan at `2e812ef2b8184733f7dd45b7bfd50e119c5ae82c` are preserved in its history;
the latter already includes the original plan and both review refinements.

| Read first | Purpose |
| --- | --- |
| [Master implementation plan](../../plans/vehicle-runtime-consolidation.md) | Sole VRC-00…VRC-11 status ledger, sequencing, owners and acceptance gates |
| [Implementation blueprint](../vehicle-runtime-consolidation-2026-11-21/IMPLEMENTATION-BLUEPRINT.md) | Module ownership, first consumer, persistence, recovery and ordered developer work packages |
| [Adversarial review and source maps](../vehicle-runtime-consolidation-2026-11-21/README.md) | Opposing reviews, control contract, migration decisions, primary sources and action-consumer coverage |
| [Controls acceptance matrix](../vehicle-runtime-consolidation-2026-11-21/CONTROL-ACCEPTANCE.md) | Forty proposed cases, all UNRUN; canonical definitions remain in the linked JSON ledger |
| [Combined-branch plan verification](../vehicle-runtime-consolidation-2026-11-21/consolidated-plan-verification.json) | Fresh static plan/data/reference check; historical runtime receipts below retain their original scope |

The final deliverable is the audit and development plan. The five GCA defects
remain unfixed and VRC implementation remains open. Consolidation does not turn
historical diagnostic results or proposed acceptance cases into repaired-control
qualification. Existing dated receipts retain their original bytes and snapshot
identities; the combined-branch receipt checks the current plan artifacts only.

## Original audit and evidence

| Deliverable | Purpose |
| --- | --- |
| [Audit report](AUDIT.md) | Findings, severity, causal paths, evidence limits, prior-audit reconciliation and optimization opportunities |
| [Repair sequence](REMEDIATION.md) | Small implementation units, existing owners, acceptance criteria and regression boundaries |
| [Qualification matrix](QUALIFICATION.md) | Required device, activity, failure and platform checks; executed software evidence stays separate |
| [Verification record](VERIFICATION.md) | Actual commands/results, preparation failures, source identity and independent review disposition |
| [Finding register](findings.json) | Machine-readable defects, gaps, opportunities and acceptance criteria |
| [Verification receipt](verification.json) | Checked run outcomes, completion markers, observations and hashes |
| [Source manifest](source-manifest.json) | Baseline and hashes of inspected production/evidence inputs |
| [Reproduction tools](../../../research/game-controls-audit-2026-11-21/README.md) | Existing-suite runner, targeted diagnostics and deterministic legacy-write experiment |

`GCA-*` identifiers are local to this dated audit, not a new implementation
ownership track. Repairs remain with D6/F3/UI controller owners, DR multirotor,
BL airship and the relevant session owners. Historical CTRL-01–15 corrections
remain recorded in their [original evidence home](../controller-support-2026-10-14/README.md#external-controls-audit-corrections-2026-11-14).

The five defect witnesses reproduced within the report's evidence limits.
The serial regression attempt passed 22 of 27 existing programs; five failed or
incomplete runs remain unqualified after missing scene/vehicle assets and three
timeouts. See [VERIFICATION](VERIFICATION.md) for the complete disposition.

The retained diagnostics characterize undesirable baseline behavior. Their
successful completion is evidence that a witness was reproduced, **not that a
repair passed**. Software results do not qualify physical transmitters, USB or
Bluetooth transport, RF loss, target graphics, exported packages or pilot feel.
