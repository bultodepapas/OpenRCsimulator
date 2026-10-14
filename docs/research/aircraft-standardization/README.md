# Aircraft standardization evidence

**Status: AS-00–05 delivered, 2026-10-11.** Software verification passed with the documented reruns; physical calibration and tight performance qualification remain open.

**2026-10-13 continuation:** [AS-06–14 foundation](AS-06-14/README.md) adds shared modules, generated visual manifests, Workshop v2 presentation pinning, conventional controls and single-installation/contact adapters. Full step acceptance and AS-15–18 remain tracked in the [active plan](../../plans/aircraft-standardization.md).

The [AS-13 continuation](AS-13/README.md) implements accepted contact observations, transactional collision publication and versioned checkpoint history without changing the physical laws.

The [AS-09/10 import continuation](AS-09-10-import/README.md) migrates Timber to a common declarative Blender builder with checked gear/rotor construction and retained version 1 procedural adapters. A second distinct Blender delivery remains an onboarding gate.

The [contract](../../../AIRCRAFT_CONTRACT.md) defines configuration, derived-model and runtime-state boundaries. [AS-05](AS-05/README.md) records delivered scope, verification and remaining acceptance.

| Evidence | Content |
| --- | --- |
| [AS-00 configuration audit](AS-00/config-audit.md) | Loader, defaults, quantity validation, consumers and inconsistencies |
| [AS-00 physics comparison](AS-00/physics-audit.md) | Independent four-aircraft assessment, deepest Stik findings and primary sources |
| [Ugly Stik reference review](AS-00/ugly-stik-reference.md) | Detailed donor/CG/inertia/propeller/gear evidence, resolved datum warning and remaining physical discrepancies |
| [AS-00 lifecycle audit](AS-00/lifecycle-audit.md) | Catalog, controls, rendering, damage, reset, replay and shared ownership |
| [AS-01 parameters](AS-01/parameters.md) | All 148 quantity paths, units, bounds and consumers |
| [AS-01 module semantics](AS-01/module-semantics.md) | Conditional wake, polar, electric and tire laws and dependencies |
| [AS-01 schema/loader agreement](AS-01/schema-v2-loader-agreement.json) | Independent structural/branch mutations and coupled-physics boundary |
| [AS-02 migration](AS-02/README.md) | Source generators, numeric parity and reusable template |
| [AS-04 verification](AS-04/README.md) | Exact same-platform model/flight comparison, lifecycle and measured load/tick cost |
| [Final contract checks](AS-04/focused-final/README.md) | Live schema/loader agreement, 1,906 contract checks and 170 actual-model hinge checks |
| [Models, flights and packaging](AS-04/model-and-flight/README.md) | Five model/clearance contracts, four real-app trimmed flights, exported schema/data availability |
| [Complete regression coverage](AS-04/full-suite/README.md) | 195 GDScript tests and 27 integration sections resolved; failures, fixes, reruns and exact snapshot boundaries |
| [AS-05 delivery](AS-05/README.md) | Final results, reusable authoring commands, remaining measurement/coordination gates and ownership |
| [AS-06–14 foundation](AS-06-14/README.md) | Seven configurations/five visual families; common source/package preflight, generated descriptors, exact fourteen-case flight/replay comparison and remaining acceptance |
| [AS-13 contact observations](AS-13/README.md) | Contact lifecycle, accepted-impact commit/rollback, checkpoint/reload compatibility and exact isolated fleet comparison |

No aircraft force equation or numeric calibration changed. Source/version identity changes deliberately; measured aircraft mass properties, low-Reynolds-number data and physical ground/flight validation remain open. Unsupported features are rejected, not inferred from hardware names.
