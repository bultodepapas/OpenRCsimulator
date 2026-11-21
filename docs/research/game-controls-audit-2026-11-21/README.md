# Game controls audit — 21 November 2026

Senior engineering review of device ownership, calibration, conditioning, profiles,
menu routing and activity recovery. Baseline: `main` at
`57abea025f62b20233ca281d58d2acbee4ab8b8e`. Work branch:
`audit/game-controls-2026-11-21`. Production application files are unchanged.

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
