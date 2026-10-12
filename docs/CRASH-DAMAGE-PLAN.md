# Crash, damage and destruction

2026-10-12 · Revision 7 · Step prefix: **CR-** · Gate: **CR**

**Status:** CR-01 diagnostics remain partial. Owner-prioritized experimental crash audio, particles, severity estimate, wreck presentation, ground marks and fire are implemented in bounded slices. Physical failure thresholds, calibrated damage, damaged flight and Gate CR remain open.

**Owns:** crash research and presentation boundaries listed in the [track registry](README.md#tracks-plans-and-step-ids). Physics-side contact and state changes are implemented with the physics owner; aircraft geometry and crash UI remain with model and menu owners.

## Current behavior

The existing airframe crash detector still ends the flight. Experimental crash presentation is enabled on ordinary interactive flight and can be disabled with --crash-effects=off. Partial C0–C2 labels and the severity estimate describe presentation only; they do not establish structural strength or a flyable damaged-aircraft state.

Static landscape contacts are now implemented through [LU-05](research/landscape-upgrade/LU-05/collision-report.md). The immutable float64 collision world covers field trees and nearby scenery, buildings, vehicles, lights and parked aircraft, with swept contacts and bounded response classes. It is not triangle-accurate; proxy dimensions and nonterminal response thresholds are estimates. Trees do not bend, break or retain the wreck. Nearby query cost remains open. The LU-05 report records the tests, measured costs and limits.

Experimental delivery evidence:

| Slice | Result |
| --- | --- |
| CR-01a/b/c | Typed crash snapshot, crossing reconstruction and crash-pose display are implemented. CR-01 remains partial until component labels and crossing-time kinematics are complete. See [CR-01c](research/crash-damage-investigations/CR-01c/README.md). |
| CR-02a / CR-03a | Spatial crash audio, bounded particles, dust and surface marks are implemented in the experimental presentation path. See [CR-02a](research/crash-damage-investigations/CR-02a/README.md) and [CR-22a integration](research/crash-damage-investigations/CR-22a/README.md). |
| CR-08a | A pure mass/speed/angle/surface severity estimate is present and explicitly uncalibrated. See [severity report](research/crash-damage-investigations/CR-08a/severity.md). |
| CR-09a / CR-19a | Shared-mesh wreck, staged breakup, bounded debris, persistent wreck marks and inspection view are implemented. See [CR-09a](research/crash-damage-investigations/CR-09a/README.md) and [CR-22a integration](research/crash-damage-investigations/CR-22a/README.md). |
| CR-22a | A bounded fuel/hot-turbine/estimated-rupture fire presentation is implemented. It does not model measured fuel burn or validated rupture thresholds. See [CR-22a](research/crash-damage-investigations/CR-22a/README.md). |

These slices do not close the broader CR-02/03/04/05 contracts, CR-07–10 structural work, or CR-19/20–27 roadmap work.

## Remaining work and dependencies

| Area | Remaining scope |
| --- | --- |
| Diagnostics | Finish CR-01 component labels and crossing-time kinematics. Preserve explicit unknown values where current model data cannot support a claim. |
| Structure evidence | CR-07 must find aircraft-specific material/joint evidence with uncertainty before any strength threshold or resolver. CR-08 video observations can challenge outcome classes but cannot substitute for that evidence. See [crash investigations](research/crash-damage-investigations/README.md). |
| Breakable models | CR-06 section contracts and CR-09 breakup tied to supported structure evidence remain incomplete. Current wreck presentation does not prove validated failure. |
| Damaged flight | CR-11–15 depend on E3d contact semantics, H8 state/replay foundations, G4b mass updates and CR-07 evidence. Persistent aircraft damage stays off until these prerequisites are accepted. |
| Terrain and trees | CR-16 still needs the shared L12 terrain sampler. LU-05 provides static tree/scenery contacts for CR-17, but lodged wrecks, broken branches and tree-specific damage remain open. |
| Fire and replay | CR-20–27 retain the full engine-specific damage, replay, report, camera and durability requirements; bounded CR-22a presentation does not complete them. |

Use scalar simulation state and contact snapshots as the authority. Godot presentation bodies never decide flight physics. Keep incident energy separate from material strength, and label estimated coefficients as estimates. The independent Gate CR asks whether structural outcomes and damaged flight are plausible; software integration alone cannot close it.
