# T01 — Metadata-only discovery and soft asset references

**Decision:** adopt the architectural boundary in UI-VS-06; implementation remains pending. **Researched:** 2026-11-17. [Twenty-investigation index](README.md).

## Question and search vocabulary

Can a 1,000-entry vehicle/skin catalog open and filter without loading its 3D assets or inspecting every archive?

Queries used included `site:dev.epicgames.com "asset registry" "gameplay code" "not currently loaded"` and searches for `Asset Registry metadata without loading assets soft references`. The useful vocabulary is **asset registry**, **soft reference**, **metadata snapshot**, and **incremental discovery**. This separates discovery from the selected asset's dependency loading, investigated in T06.

## Primary evidence and transfer limits

[Epic's asynchronous asset-loading documentation](https://dev.epicgames.com/documentation/unreal-engine/asynchronous-asset-loading-in-unreal-engine) describes querying unloaded gameplay assets through registry metadata and referencing assets indirectly before requesting them. Its [Asset Registry guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/asset-registry-in-unreal-engine) describes incremental discovery and incomplete-list notifications. These are Unreal mechanisms; OpenRC should borrow the separation of metadata and payload, not introduce Unreal APIs. Both were accessed on 2026-11-17; the live documentation can change independently of OpenRC's pinned engine.

In OpenRC, [VehicleRoster](../../../../../app/app_state/vehicle_roster.gd) already gives the UI a mixed-vehicle view, while [CustomSkin.choices](../../../../../app/aircraft/custom_skin.gd#L129-L178) still performs directory and archive work. The [existing audit](../code-audit.md) distinguishes that cost from image decoding. A dictionary containing names is not cheap if constructing it synchronously opens and hashes every archive.

## Application to OpenRC

Publish an immutable catalog snapshot from existing stock metadata and the admitted import library. Suggested record fields are stable source-qualified ID, content revision, display name, family, registered launch adapter, availability, skin IDs/count, thumbnail keys, and preview descriptor key. This is a proposal for the UI adapter, not a replacement aircraft schema.

The navigation path reads only that snapshot. Search operates on normalized text/tags; skin counts and names come from indexed summaries. Heavy validation and derivative generation belong to admission and bounded reconciliation. An imported record cannot confer flight capability, register executable code, or choose an arbitrary adapter path. The existing admission owner remains authoritative.

Use generation numbers to publish a complete new snapshot atomically. Readers finish against the previous snapshot; selection and logical focus reconcile by stable ID. A selected item missing from a partial initial scan remains in a distinct checking state until discovery can determine whether it is absent. Preserve saved desired skin identity during that interval.

Legacy installations need a first-upgrade path: discover a bounded number of entries, inspect them through existing limits, publish partial progress, and resume after interruption. Invalid records are isolated with a recoverable status. Do not run the whole migration in the button handler or discard the user's files to repair an index.

## Counterexample and risks

Putting PackedScenes, textures, or eager `preload` dependencies inside the catalog resource can recreate the load storm behind a metadata-looking interface. Treat metadata dependency closure as a reviewable invariant. A stale index can also show a valid-looking thumbnail for replaced content; selection and launch must still resolve the exact admitted revision. A persistent database is unnecessary for the present catalog size unless measurements expose a need.

## Experiment and decision gate

Compare current enumeration with a published snapshot using 13, 100 and 1,000 descriptors. Instrument archive opens, resource requests, full-model builds, query latency, first usable catalog frame, metadata bytes, and index-repair progress. Exercise missing/corrupt indexes and external replacement while the catalog is open.

Accept when navigation performs no synchronous archive or model work, 1,000 metadata entries meet the catalog target, and partial discovery preserves selected identity. Reject a design that merely moves the same blocking scan into every menu-open callback. Real heavy-asset traversal remains a separate memory test under T12.

**Plan impact:** UI-VS-06 now needs an explicit metadata/payload dependency boundary and interruption-safe bootstrap, with UI-VS-07 consuming snapshots rather than storage internals.
