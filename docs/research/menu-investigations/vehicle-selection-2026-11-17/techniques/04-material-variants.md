# T04 — Shared geometry with transactional material variants

**Decision:** early pilot in UI-VS-03; expand only through proven compatibility in UI-VS-11. **Researched:** 2026-11-17. [Twenty-investigation index](README.md).

## Question and search vocabulary

Can changing paint become a small appearance transaction instead of rebuilding the whole vehicle?

The targeted query was `site:github.com/KhronosGroup/glTF KHR_materials_variants materials mappings variants geometry`. Related vocabulary is **material variants**, **shared immutable geometry**, **copy-on-write appearance**, and **atomic appearance commit**. This investigation concerns reuse within an accepted vehicle, not a general 3D object pool.

## Primary evidence and transfer limits

[KHR_materials_variants](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_variants/README.md) defines alternative material mappings over shared primitives, including fallback to the base material when no mapping applies. The specification also discusses optional lazy texture requests. Accessed 2026-11-17. It is useful as an authoring contract; it does not establish OpenRC support for importing that extension.

The pinned Godot [Resource contract](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Resource.xml#L58-L79) distinguishes shallow duplication and shared nested resources. Private material ownership therefore needs explicit design; calling duplicate does not prove every mutable dependency became independent.

OpenRC's [VehiclePaint.apply](../../../../../app/render/vehicle_paint.gd#L62-L119) already uses origin materials and per-instance paint copies, while [CustomSkin.apply](../../../../../app/aircraft/custom_skin.gd#L181-L238) prepares a validated patch before application. These are foundations with different contracts, not interchangeable drop-in services.

## Application to OpenRC

Create an owner-approved appearance descriptor keyed by base geometry revision, hierarchy/binding signature, material-slot schema, skin revision, adapter version and relevant visual features. The fast route is admitted only when all geometry/pose invariants match. Resolve from the verified base plus selected layers on every change, so A→B→Default removes B completely.

Prepare candidate materials and texture references without changing the displayed root. Share immutable meshes and textures; copy every material state that will mutate. Validate all targets before one bounded main-thread commit, then update displayed appearance identity and observe its first draw. On failure or supersession, keep the previous appearance and release the candidate.

Reuse derived bounds, support pose and shadows only when their keys remain valid. Transparent parts, emissive paint, light anchors, procedural adaptations and alpha-dependent shadows can alter those dependencies or shader variants. Encode such capabilities rather than infer them from a common vehicle name.

Start with Bisonte or another material-painted car, then one appropriate aircraft. Keep separate-GLB Corsair, MoonRunner and airship variants on full construction until their source pipeline proves equivalent geometry and bindings. If later converting them to shared geometry, generate the mapping and equivalent output from source assets; do not patch delivery files by hand.

## Counterexample and risks

A skin can be a geometry-changing adapter or select a different model. Deep-copying every mesh/texture to isolate paint can also destroy the memory benefit. Loading every possible variant texture while building the shared geometry defeats lazy appearance loading. Creator currently rejects extensions outside its allowlist, including an unadmitted material-variant extension; the pilot uses existing validated paint inputs.

## Experiment and decision gate

Compare the current full-preview path against the pilot for cached colors, a texture miss and a rejected custom appearance. Measure geometry builds, preparation phases, texture requests, temporary/resident bytes and first requested draw. Verify A→B→Default equality, two simultaneous independent instances, a live flight unaffected by menu edits, cancellation, missing texture and revision replacement.

Accept only if compatible changes avoid geometry reconstruction and preserve complete appearance/ownership parity. Reject any optimization that silently broadens compatibility or leaves partially painted models. Record the exact family/adapter qualified; one successful car does not qualify all 49 appearances.

**Plan impact:** specify a prepared appearance transaction and explicit compatibility evidence in UI-VS-03; UI-VS-11 owns authoring conversion and wider adapter coverage.
