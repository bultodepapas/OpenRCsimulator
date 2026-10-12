# Landscape upgrade evidence

Status: implementation and evidence delivered through LU-14, updated 2026-10-12. Latest continuation: 28/28 focused scripts pass, 56/56 native crash/reset checks, 76 images. Prior Linux regression: 207/208 GDScript tests pass; one atmosphere-trim platform discrepancy and nearby collision-query budget remain open. Track: **LU-00–14**. Owner: environment integration lead.

The requested [implementation plan](../../../LANDSCAPE_UPGRADE_PLAN.md) was written before application edits. The installed target is Godot **4.7.2**, Compatibility/OpenGL.

| Step | Evidence |
| --- | --- |
| LU-00 | [Repository audit and research](LU-00/README.md), [resources, licenses and rejected alternatives](LU-00/resources.md) |
| LU-01/02 | [Vegetation, people, parking and complete parked fleet](LU-02/README.md) |
| LU-03 | [Lamp hardware, windows and exposure integration](LU-03/README.md) |
| LU-04/06 | [Final native screenshots, glare checks, frame measurements and regression results](LU-06/README.md) |
| LU-05 | [Swept scenery collision, responses, checkpoints and cost](LU-05/collision-report.md) |
| LU-07–10 | [Connected crowns, gravel shoulders, service details, marker optics and detector optimization](LU-07/README.md) |
| LU-11–14 | [Filtered gravel, construction details, twilight palette, collision coverage, native evidence and cost](LU-11/README.md); [resources/licenses](LU-11/resources.md) |
| LU-15 | [Review of 14 native images and selection of the next upgrades](LU-15/README.md); LU-16–20 are planned, not implemented |

The source/license ledger is [UPGRADE_CREDITS](../../../app/assets/landscape/UPGRADE_CREDITS.md). No third-party asset or runtime plugin was added. Existing exact-package CC0 evidence remains authoritative; current author-wide licensing is not substituted for it.
