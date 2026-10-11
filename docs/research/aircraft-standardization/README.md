# Aircraft standardization evidence

**Status: AS-00–03 implemented; AS-04/05 verification in progress, 2026-10-11.**

The owner-requested root [plan](../../../AIRCRAFT_STANDARDIZATION_PLAN.md) records scope, ownership, risks and acceptance. The [contract](../../../AIRCRAFT_CONTRACT.md) defines configuration, derived-model and runtime-state boundaries.

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

No aircraft force equation or calibration change is intended. Source/version identity changes deliberately; measured aircraft mass properties, low-Reynolds-number data and physical ground/flight validation remain open. Unsupported features are rejected, not inferred from hardware names.
