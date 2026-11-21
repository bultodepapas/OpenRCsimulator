# Vehicle runtime consolidation — source review and adversarial controls audit

**2026-11-21.** Runtime baseline `57abea025f62b20233ca281d58d2acbee4ab8b8e`; original published plan `542d92b304fc3b82678c4a90b848a88d82df0b22`. Three independent source-review contexts challenged architecture, controls and evidence and then reviewed the lead's revised proposal. This is an automated external-style plan audit, not third-party certification or runtime qualification.

**Result:** ten plan findings addressed; forty explicit acceptance cases proposed and **UNRUN**. The existing five GCA defects remain unfixed by this branch. The [master plan](../../plans/vehicle-runtime-consolidation.md) owns VRC-00…VRC-11 status; all implementation remains open.

| Read | Purpose |
| --- | --- |
| [EXTERNAL-AUDIT.md](EXTERNAL-AUDIT.md) | Findings, pinned evidence, adversarial decisions and scope |
| [CONTROL-CONTRACT.md](CONTROL-CONTRACT.md) | Authority, temporal input, family policy, persistence, lifetime and response obligations |
| [CONTROL-ACCEPTANCE.md](CONTROL-ACCEPTANCE.md) | Generated human-readable forty-case acceptance matrix |
| [control-cases.json](control-cases.json) | Canonical case IDs, owners, triggers, oracles, test starting points and UNRUN statuses |
| [QUALITY-GATES.md](QUALITY-GATES.md) | Baseline/runner, replay identity, native, real UI/device, response, promotion and rollback gates |
| [MIGRATION-MATRIX.md](MIGRATION-MATRIX.md) | What to retain/share/defer and the smallest useful first bridge |
| [SOURCE-INVENTORY.md](SOURCE-INVENTORY.md) and [inventory.json](inventory.json) | Corrected ten-file scan with pinned identities and reproducible counting method |
| [audit-findings.json](audit-findings.json) | Machine-readable findings and case/source traceability |
| [verification.json](verification.json) | Dated static verification result and artifact hashes |
| [Checker and rerun guide](../../../research/vehicle-runtime-consolidation/README.md) | Reproduce static checks and regenerate the matrix; no engine launch |

The [prior controls audit](https://github.com/bultodepapas/OpenRCsimulator/blob/895dd4352c5191f1539a8b8f4df1996cd33eb86f/docs/research/game-controls-audit-2026-11-21/AUDIT.md) supplies five baseline defect witnesses and the historical 22-of-27 regression result, with five failed/incomplete programs. Its scripts/evidence remain at that commit; they were not rerun here. A passing adverse witness is not a repaired control path.

The first proposed migration is one fixed-wing status/pause/resume consumer through its full existing shell/activity gate. Other operations and families remain with their current owners until individually justified and proven. Optional consolidation does not block an independently completed controls repair.
