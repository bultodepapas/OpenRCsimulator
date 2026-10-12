# Landscape upgrade evidence

Status: implementation and evidence delivered, 2026-10-11. Linux regression: 207/208 GDScript tests pass; one atmosphere-trim platform discrepancy and nearby collision-query budget remain open. Track: **LU-00–06**. Owner: environment integration lead.

The requested [implementation plan](../../../LANDSCAPE_UPGRADE_PLAN.md) was written before application edits. The installed target is Godot **4.7.2**, Compatibility/OpenGL.

| Step | Evidence |
| --- | --- |
| LU-00 | [Repository audit and research](LU-00/README.md), [resources, licenses and rejected alternatives](LU-00/resources.md) |
| LU-01/02 | [Vegetation, people, parking and complete parked fleet](LU-02/README.md) |
| LU-03 | [Lamp hardware, windows and exposure integration](LU-03/README.md) |
| LU-04/06 | [Final native screenshots, glare checks, frame measurements and regression results](LU-06/README.md) |
| LU-05 | [Swept scenery collision, responses, checkpoints and cost](LU-05/collision-report.md) |

The source/license ledger is [UPGRADE_CREDITS](../../../app/assets/landscape/UPGRADE_CREDITS.md). No third-party asset or runtime plugin was added. Existing exact-package CC0 evidence remains authoritative; current author-wide licensing is not substituted for it.
