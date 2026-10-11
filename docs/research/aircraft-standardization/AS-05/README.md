# AS-05: Standardization delivery

**Status: Delivered and reviewed, 2026-10-11.** Software verification passed through the documented continuation/reruns; physical calibration and tight performance qualification remain open below. Owner: aircraft standardization lead. Prefix: AS-.

The four catalog aircraft and four existing electric specimens now use `openrc-aircraft v2`. The [plan](../../../../AIRCRAFT_STANDARDIZATION_PLAN.md) was completed before implementation. The [contract](../../../../AIRCRAFT_CONTRACT.md), [versioned schema](../../../../app/data/schema/openrc-aircraft-v2.schema.json), [runtime preflight](../../../../app/physics/aircraft_contract.gd), [148-path consumer register](../AS-01/parameters.md) and [module semantics](../AS-01/module-semantics.md) form the authoring boundary. The normal catalog route checks version and selected aircraft identity before flight; historical v1 experiments remain explicitly supported.

## Delivered behavior

| Baseline inconsistency | Delivered resolution |
| --- | --- |
| Permissive objects, silently ignored coefficients and branch-specific validation | Closed v2 objects and quantity records, finite values, exact units/types, actionable paths, explicit conditional modules and coupled Godot checks |
| Hidden start, planform, propulsion, point-mass and steering defaults | Explicit migrated intent; zero remains valid where physical, and null/missing/inapplicable remain distinct |
| Free-text propeller direction without a solver effect | Enforced supported rotation convention; unsupported configurations rejected |
| Required `CLadot` advertised beside active derivatives without a consumer | Preserved as reference evidence; no implied alpha-dot force |
| Physics/visual selection could disagree | Catalog version/ID guard plus actual-model control direction and authored-throw checks |
| Generated models could diverge from migrated files | Extra, P-51 and Avanti generators emit v2; freshness checks and exact numeric migration guard |
| Gear hardware names could imply unsimulated behavior | Explicit fixed, locked-down or locked-up configurations; contact-module/topology consistency; neutral unsimulated flaps |
| New aircraft had no consolidated authoring boundary | Borrowed-data template, add/tune guide, parameter meanings, extension rules and retained evidence |

The [migration comparison](../AS-02/numeric-parity.json) preserves all **2,815 original numeric leaves**, with eight reference-only CLadot path moves and 286 explicit compatibility-default leaves. No force equations or numerical aircraft calibration changed; no golden flights were rerecorded. The [fleet audit](../AS-00/physics-audit.md) evaluates each aircraft independently. The deeper [Ugly Stik review](../AS-00/ugly-stik-reference.md) distinguishes its datum correction from unresolved physical calibration.

## Verification and limits

| Boundary | Result and durable proof |
| --- | --- |
| Runtime/offline contract | [1,906 Godot contract checks, 170 hinge checks and 62 schema/loader cases](../AS-04/focused-final/README.md); the two intentional schema/runtime differences are coupled physical constraints |
| Historical compatibility | [1,873 v1 schema cases](../AS-04/v1-compatibility.md), with documented runtime-only physical constraints |
| Numerical migration/lifecycle | [Eight exact normalized models and every recorded float64 flight state](../AS-04/README.md); reset, pause/checkpoint/replay, cross-model refusal and malformed reload rollback |
| Production models and flight | [Five model/clearance contracts and four real-app trimmed flights](../AS-04/model-and-flight/README.md), each 721 finite samples at 240 Hz |
| Template | Offline structural validation and [production Godot loader acceptance](../AS-04/focused-final/template-loader.json); donor evidence remains borrowed, not physical acceptance |
| Packaging | [PCK resource inspection](../AS-04/model-and-flight/README.md) found both v2 schema resources and all eight data files; pack-only, not a release-platform certification |
| Complete regression coverage | [195 GDScript tests and all 27 integration sections resolved](../AS-04/full-suite/README.md) through the fresh-copy official run, continuation and documented reruns; application source bytes stayed unchanged during the continuation |
| Performance | [Alternating baseline/candidate and paired measurements](../AS-04/paired-metadata-benchmark.md). Seven aircraft's paired median tick ratios were near 1; P-51's longer repeat was 0.986. No persistent slowdown was reproduced, but shared-host variability prevents certifying the 5% target. Validation adds load-time work; no configuration parsing enters the tick. |

Final freshness checks passed for the schema, parameter register, all eight migrations and all three generated aircraft/reports; migration unit tests passed 5/5. Three generated research polar candidates also migrated through their existing pipeline, preserving [all 1,023 original numeric leaves](../AS-02/polar-candidate-parity.json); freshness, schema and experimental-flight CLI checks passed. The combustion propeller [range auditor](../AS-04/focused-final/range-audit-v2-compatibility.md) now accepts v2 with exact source-format/hash checks (23 tests).

## Remaining gates and ownership

| Gap | Owner and completion evidence |
| --- | --- |
| Stik virtual balancing mass, inertia warning, borrowed aero/propeller map, 37/46 g rotor-source discrepancy and estimated controls | Aircraft physics/model owners: weigh and balance a specified assembly, measure inertia and installed propeller/engine response, then held-out flight identification; see the ordered [measurement work](../AS-00/ugly-stik-reference.md#follow-up-measurements-in-order) |
| Stik wheel/contact vertical difference of approximately 5 mm | Model and ground owners: reconcile datum/undeformed wheel geometry, then before/after sag, rollout and crash-clearance evidence; no unmeasured contact retune in AS |
| Extra, P-51 and Avanti experimental coefficients and inferred inventories | Respective model/physics tracks: independent aircraft-specific measurements; sharing a contract does not make Stik a calibration oracle |
| Tight performance qualification | Performance owner: repeat retained paired driver on an otherwise idle host with adequate run length; publish p50/p95 spread and a stated statistical criterion before claiming ≤5% |
| Concurrent wheel profiles, spin, brakes and live wheel presentation | GP owns its separately versioned schema/solver. AS documents and validates the file-loader attachment seam; frozen migration parity excludes later GP force changes. Current aircraft profiles remain unbraked. |
| Crash fuel effect still recognizes an inventory-name prefix; part identity remains geometric estimation | Crash/model owners: replace this presentation-only heuristic with explicit equipment/part semantics before expanding damage. It does not consume fuel or alter mass, force, CG or inertia. |
| Visual revision is not fully identified by physics trace metadata | Model/visual owners: add render revision/source identity before using physics traces as proof of equivalent appearance. Current model/source manifests retain the tested geometry. |
| EDF, pushers, multiple engines, active retracts/flaps, fuel burn and persistent structural damage | Unsupported and rejected as active v2 configurations. Add a documented module, consumer, complete runtime lifecycle and independent tests before feature implementation. |

Three bounded Luna/max contributions were reviewed and integrated by the lead. External ground/crash/audio/UI/model changes were preserved. Exact snapshots separate migration evidence from concurrent work; the registry records an ownership reservation, not an acknowledgement from inaccessible sessions. No commit or release was issued by this task.

[Final artifact hashes](artifact-hashes.json) identify 33 delivered contract, schema, runtime, test, generator, template and aircraft files. Final scoped whitespace and local documentation link checks passed.

## Reproduce or add an aircraft

Start with the contract's [five-step add/tune guide](../../../../AIRCRAFT_CONTRACT.md#adding-and-tuning-an-aircraft) and [synthetic template](../../../../research/aircraft-standardization/template/openrc-aircraft-v2.template.json). Keep generated aircraft changes in their source pipelines. Use the repository's pinned schema-test environment described in [schema tooling](../../../../research/aircraft-data/schema/README.md).

```text
python research/aircraft-data/schema/check.py <aircraft.json>
python research/aircraft-standardization/build_schema.py --check
python research/aircraft-standardization/parameter_register.py --check
python research/aircraft-standardization/migrate.py --check-known
python research/aircraft-standardization/test_migrate.py
bash app/test.sh
```

For an unregistered file, `research/aircraft-data/schema/loader_probe.gd` accepts one user argument: a JSON array of absolute aircraft-file paths. Run it with pinned Godot, `--headless --path app --script <absolute-probe-path> -- <manifest-path>`. Require every emitted `DATA4A` result to have `ok: true`; its process exit alone is not an acceptance result. Then exercise trim, controls, propulsion, ground and lifecycle in an aircraft-specific test before adding a catalog entry. Offline validation cannot replace Godot's coupled checks or physical measurement.

Primary references and their applicability are retained in the [plan](../../../../AIRCRAFT_STANDARDIZATION_PLAN.md#as-00-findings-and-technical-basis), [physics audit](../AS-00/physics-audit.md) and quantity-level provenance. They define methods and conventions; they do not supply measured validation for these complete virtual builds.
