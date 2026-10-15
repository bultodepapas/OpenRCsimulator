# Crash, damage and destruction

2026-10-14 · Revision 9 · Step prefix: **CR-** · Gate: **CR**

**Status:** CR-01 diagnostics remain partial. Owner-prioritized experimental crash audio, particles, severity estimate, wreck presentation, ground marks and fire are implemented in bounded slices. Physical failure thresholds, calibrated damage, damaged flight and Gate CR remain open.

**Owns:** crash research and presentation boundaries listed in the [track registry](README.md#tracks-plans-and-step-ids). Physics-side contact and state changes are implemented with the physics owner; aircraft geometry and crash UI remain with model and menu owners.

## Current behavior

On interactive flights, crash-hull points are soft contacts ([E3d1](research/crash-damage-investigations/E3d1/README.md)): a wingtip brush, tail touch or belly slide continues, and only a C2-grade new impact or a deep crush ends the flight (`--soft-contacts=off` restores "any contact is a crash"; scripted, capture and trace routes keep it). Experimental crash presentation is enabled on ordinary interactive flight and can be disabled with --crash-effects=off. Partial C0–C2 labels and the severity estimate describe presentation only; they do not establish structural strength or a flyable damaged-aircraft state.

Static landscape contacts are implemented through [LU-05](research/landscape-upgrade/LU-05/collision-report.md). [CR-17a](research/crash-damage-investigations/CR-17a/README.md) adds committed local scenery damage, matching fence/flightline-barrier geometry, material-specific aftermath and checkpoint/reset behavior. The source float64 inventory remains immutable; a per-flight damage mask removes broken pieces from later contacts. Large structures retain collision. Proxy dimensions and failure cutoffs remain gameplay estimates; sparse hull coverage, tree lodging and nearby query cost remain open.

Experimental delivery evidence:

| Slice | Result |
| --- | --- |
| CR-01a/b/c | Typed crash snapshot, crossing reconstruction and crash-pose display are implemented. CR-01 remains partial until component labels and crossing-time kinematics are complete. See [CR-01c](research/crash-damage-investigations/CR-01c/README.md). |
| CR-02a / CR-03a | Spatial crash audio, bounded particles, dust and surface marks are implemented in the experimental presentation path. See [CR-02a](research/crash-damage-investigations/CR-02a/README.md) and [CR-22a integration](research/crash-damage-investigations/CR-22a/README.md). |
| CR-08a | A pure mass/speed/angle/surface severity estimate is present and explicitly uncalibrated. See [severity report](research/crash-damage-investigations/CR-08a/severity.md). |
| CR-01d | Every aircraft names its crash-hull points (`crash_hull_components`); crash presentation reports the struck component from data instead of a geometric guess. See [CR-01d](research/crash-damage-investigations/CR-01d/README.md). |
| CR-01e | The crash card and log name the cause (stall, tip stall, spin, dive, hard landing, prop strike, obstacle, dead stick…) from the last 5 s of telemetry. See [CR-01e](research/crash-damage-investigations/CR-01e/README.md). |
| CR-08b | Effective-mass, per-kg grading with slapdown and abrasion channels replaces the CR-08a joule bins; still uncalibrated. See [CR-08b](research/crash-damage-investigations/CR-08b/README.md). |
| CR-09b | Breakup is proportional: C2 loses only the small struck part, C3 the struck section and its neighbours, released in order of distance from the contact; scatter follows the momentum. See [CR-09b](research/crash-damage-investigations/CR-09b/README.md). |
| CR-03b / CR-02b | Dust, sparks, chips and sound follow the surface, the struck part and the class; no spherical dust burst or chip fountain; chips use the airframe's colours. See [CR-03b](research/crash-damage-investigations/CR-03b/README.md). |
| CR-09a / CR-19a | Shared-mesh wreck, staged breakup, bounded debris, persistent wreck marks and inspection view are implemented. See [CR-09a](research/crash-damage-investigations/CR-09a/README.md) and [CR-22a integration](research/crash-damage-investigations/CR-22a/README.md). |
| CR-17a | Local fences, lightweight props and shrubs can break; large obstacles show marks/chips. Damage commits after an accepted tick and survives compatible checkpoints. [Implementation and evidence](research/crash-damage-investigations/CR-17a/README.md). |
| E3d2 | A turning propeller that reaches the field breaks: the engine stops and the flight goes on; blades vanish, fragments fly. See [E3d2](research/crash-damage-investigations/E3d2/README.md). |
| CR-09d1 | Wreck sections carry the inventory's real masses and centres of mass (the intact wreck's centre of mass is the aircraft CG). See [CR-09d](research/crash-damage-investigations/CR-09d/README.md). |
| CR-09d2 / CR-22d | The wreck slides and rebounds per surface (one friction table with the abrasion grade); a fuel fire starts with a Roberts-sized ignition flash, never for glow or LiPo. See [CR-09d](research/crash-damage-investigations/CR-09d/README.md), [CR-22d](research/crash-damage-investigations/CR-22d/README.md). |
| CR-09c | Imported models break into their real parts: Blender `openrc_section` extras, or a generated section map for a merged mesh (the Timber has 8 real sections); a missing section never leaves a crash with nothing to release. See [CR-09c](research/crash-damage-investigations/CR-09c/README.md). |
| CR-22b | Fire and smoke follow the tagged energy source: kerosene fire, glow-fuel stain, rare gasoline fire, delayed LiPo venting. See [CR-22b](research/crash-damage-investigations/CR-22b/README.md). |
| CR-22a | A bounded fuel/hot-turbine/estimated-rupture fire presentation is implemented. It does not model measured fuel burn or validated rupture thresholds. See [CR-22a](research/crash-damage-investigations/CR-22a/README.md). |
| CR-22c-R1 | Prepared BVHs replace per-contact scuff triangle scans. Compatibility crash shaders are warmed during flight setup; only applicable emitters start at impact. Native ground-impact comparisons cover all eight airplane configurations with unchanged physical impact states. Residual frame spikes and the full class/distance budget remain open. See [crash-stutter evidence](research/crash-damage-investigations/CR-22c-R1/README.md). |

CR-22c-R2 avoids repeated soft-contact feedback at the same simulation tick, reuses unchanged wreck shadow projections and calculates each scenery sort distance once. See [measurements and regressions](research/crash-damage-investigations/CR-22c-R2/README.md).

CR-22c-R3 stops scanning resting chips, shares per-frame ballistic increments and updates particle clocks only on pause transitions. Delayed energy effects remain active. See [state parity and CPU evidence](research/crash-damage-investigations/CR-22c-R3/README.md).

These slices do not close the broader CR-02/03/04/05 contracts, CR-07–10 structural work, or CR-19/20–27 roadmap work.

## Remaining work and dependencies

The active execution plan for proportional outcomes, crash causes, energy-source fire and effects cost is [crash realism](plans/crash-realism.md).

| Area | Remaining scope |
| --- | --- |
| Diagnostics | CR-01d named the hull points; finish CR-01 crossing-time kinematics. Preserve explicit unknown values where current model data cannot support a claim. |
| Structure evidence | CR-07 must find aircraft-specific material/joint evidence with uncertainty before any strength threshold or resolver. CR-08 video observations can challenge outcome classes but cannot substitute for that evidence. See [crash investigations](research/crash-damage-investigations/README.md). |
| Breakable models | CR-06 section contracts and CR-09 breakup tied to supported structure evidence remain incomplete. Current wreck presentation does not prove validated failure. |
| Damaged flight | CR-11–15 depend on E3d contact semantics, H8 state/replay foundations, G4b mass updates and CR-07 evidence. Persistent aircraft damage stays off until these prerequisites are accepted. |
| Terrain and trees | CR-16 still needs the shared L12 terrain sampler. CR-17a supplies local scenery damage and trunk/crown impact presentation; lodged wrecks, branch mechanics, structural calibration and support-collapse propagation remain open. |
| Fire and replay | CR-20–27 retain the full engine-specific damage, replay, report, camera and durability requirements; bounded CR-22a presentation does not complete them. |

Use scalar simulation state and contact snapshots as the authority. Godot presentation bodies never decide flight physics. Keep incident energy separate from material strength, and label estimated coefficients as estimates. The independent Gate CR asks whether structural outcomes and damaged flight are plausible; software integration alone cannot close it.
