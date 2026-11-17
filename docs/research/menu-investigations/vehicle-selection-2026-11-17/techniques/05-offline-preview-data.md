# T05 — Cook repeatable preview work into generated data

**Decision:** pilot the dominant measured geometry-preparation stage in UI-VS-04. **Researched:** 2026-11-17. [Twenty-investigation index](README.md).

## Question and search vocabulary

Which geometric calculations can be performed once at accepted import/build time instead of during each uncached vehicle selection?

Queries used: `site:dev.epicgames.com documentation derived data cache disposable generated assets build data runtime` and `site:docs.godotengine.org EditorScenePostImport post import scene tool import process`. The useful terms are **cooking**, **derived data**, **deterministic recipe**, **dependency fingerprint**, and **import-time preprocessing**. T14 separately addresses cache publication and invalidation.

## Primary evidence and transfer limits

[Epic's Derived Data Cache guide](https://dev.epicgames.com/documentation/unreal-engine/using-derived-data-cache-in-unreal-engine?lang=en-US) describes rebuildable derived formats distinct from source assets. It is conceptual evidence for computing reusable outputs, not a proposal to install Unreal's cache service. Accessed 2026-11-17.

Godot's pinned [EditorScenePostImport class](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/EditorScenePostImport.xml) provides an editor post-import hook; its XML marks it as an editor API. It cannot simply become a runtime importer inside an exported game. OpenRC must use its existing stock generation pipeline and a separately admitted runtime-import path where needed.

OpenRC currently computes render-only [gearless hull support and propeller clearance](../../../../../app/ui/home_presentation.gd#L77-L140), [projected-shadow geometry](../../../../../app/render/projected_shadow.gd#L37-L78), and [geometry snapshots](../../../../../app/ui/home_preview_geometry.gd#L6-L119). These are source-visible work sites; their current latency shares remain unmeasured.

## Application to OpenRC

Define small independently versioned outputs: local bounds, accepted parked alignment/contact points, propeller display angle where applicable, a compact projected-shadow representation, material-slot map and default light anchors. Choose the first output from attribution, not from how large its function looks.

Each output records exact source identity, relevant pose/visibility/material dependencies, algorithm version, coordinate conventions, dimensions and integrity digest. The authoring generator produces it alongside existing manifests. The production preview verifies the descriptor identity and consumes it without opening all vertex arrays merely to reconstruct the same answer.

Keep dependency sets precise. A solid color change may preserve support and bounds; a geometry adaptation or alpha-masked shadow may not. Avoid invalidating every descriptor for a harmless label edit, but never reuse a pose from another topology. Use owner-defined numeric tolerances and corresponding visual checks; this is render geometry, not a new physical ground-contact model.

Older stock assets and admitted imports without derivatives retain the current validated computation as fallback. A background admission task can create a derivative after validating the source. Publication follows T14's completed-generation rule; navigation sees either a verified descriptor or an explicit missing state.

Ship the necessary stock outputs with exported packages. A cache populated in a developer editor is not proof that a clean installation has them. Keep large debug mesh dumps out of Git; reproducible compact generation recipes and owning manifests are the durable artifacts.

## Counterexample and risks

If generation requires loading the same full asset during every menu visit, the cost was relocated within the critical path rather than removed. Large shadow dumps can cost more to deserialize than recomputation. Dynamic customization can invalidate the derivation frequently. Generated descriptors also cannot substitute for aircraft provenance, importer limits, model bindings or flight validation.

## Experiment and decision gate

For a representative wheeled model, gearless MoonRunner and helicopter, compare runtime preparation to generated outputs on the same accepted assets. Record source/generator identities, descriptor bytes, phase time, maximum main-thread slice and total first requested draw. Verify support pose, propeller clearance, camera framing, day/night appearance and shadow parity at 1080p. Corrupt or change each dependency to verify fallback.

Accept only if the complete workload improves with equivalent approved presentation and correct invalidation. Reject an output whose loading cost or maintenance complexity outweighs the measured stage. Preserve the fallback while expanding coverage.

**Plan impact:** UI-VS-04 now requires a per-output dependency contract, package inclusion and generated-versus-runtime evidence; T08 remains an option for unavoidable runtime work.
