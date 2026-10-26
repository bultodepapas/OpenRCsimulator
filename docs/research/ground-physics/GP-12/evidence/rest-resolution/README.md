# GP-12 assembly resolution and accuracy cohort

2026-10-26 · **1,433 checks across six selected scripts**, all complete with exit 0 and no engine diagnostics. Official Windows Godot `4.8.beta1.official.4d10419ca`, headless/Dummy audio. [Manifest and source hashes](manifest.json).

| Script | Checks | Receipt |
| --- | ---: | --- |
| Assembly-resolution certificate | 53 | [report](checks/test_contact_assembly_resolution/report.json) |
| Strict traction QP | 659 | [report](checks/test_ground_traction/report.json) |
| Common aircraft impulse | 314 | [report](checks/test_aircraft_ground_impulse/report.json) |
| Existing Lie step, before two-sided extension | 127 | [report](checks/test_aircraft_ground_step/report.json) |
| Fixed-voltage aircraft integration | 196 | [report](checks/test_aircraft_ground_electric/report.json) |
| Complete-path numerical accuracy | 84 | [report](checks/test_aircraft_ground_accuracy/report.json) |

The exact Sym16 assembly accepts zero impulse under a distinct verified objective-resolution certificate. Its strict KKT refusal remains an explicit oracle. Original caps, work and common-mass checks remain active; genuine motion does not accept zero. The [draft numerical derivation](draft-analysis/review.md) and exact binary proof inputs are retained separately from production sources and receipts. Its 51-check draft count predates two production publication-guard checks.

This collection pairs the genuine 127-check Step receipt with its exact retained source/test hashes. A concurrent Step167 promotion raced packaging; the manifest records the initially observed newer hashes and replacement with the prior retained Step127 files **before publishing this cohort**. No test receipt or earlier cohort was changed. Later two-sided integration requires its own evidence.

Selected source files were captured at packaging; this is not a complete repository dependency freeze. Reports retain original main-tree commands/paths. The earlier [traction acceleration cohort](../traction-acceleration/README.md) remains unchanged and establishes a different source snapshot. Preserve both identities when reproducing regressions.

These results establish numerical assembly and local-policy software behavior. They do not establish six-second aircraft rest, loaded touchdown refinement, calibrated RC gear, stock advanced-contact activation, performance, native audio or 1080p acceptance.
