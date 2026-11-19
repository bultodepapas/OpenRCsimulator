# AE-24e-00 — Sponsor decal Workshop investigation

**Reviewed:** 2026-11-18 (America/Bogota).
**Source baseline:** `cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c` from `main`.
**Branch:** `plan/sponsor-decal-workshop-2026-11-18`.
**Scope:** developer preparation, source images, proposed contracts and a runnable
flat interaction study. Runtime code and shipped behavior are unchanged.

## Expanded research — 2026-11-19

The [R1 research index](../AE-24e-00-R1/README.md) adds **60 sequential investigations**
in batches of 10, 20 and 30, with synthesis after each stage, pinned repository
follow-ups and 37 executable offline cases. Architecture, interaction, plan and
validation documents now incorporate those findings. The source follow-ups use
branch commit `0d251cb`; original asset and study results below retain their date.
No runtime decal editor or native rendering/performance result is claimed.

## Handoff in five minutes

1. Read the [plan and implementation sequence](../../../plans/sponsor-decal-workshop.md).
2. Open the [offline study](../../../../research/aircraft-editor/sponsor-decals/workshop-preview.html)
   from a local clone and try repeated decals, drag, size, rotation, flips and layers.
3. Review the [architecture](architecture.md), especially explicit base paint,
   dense rendering, presentation migration and wreck remapping.
4. Review the [14-organization register](sponsor-register.md) and
   [checksum-locked original image pack](../../../../research/aircraft-editor/sponsor-decals/asset-lock.json).
5. Start AE-24e-01 with the exact two-family matrix in [validation](validation.md).

## Current implementation, verified in source

| Seam | Observed behavior and consequence |
| --- | --- |
| [`app/get-godot.sh`](../../../../app/get-godot.sh), [`project.godot`](../../../../app/project.godot) | Pins `4.8.beta2.official.cafc17a19`; Compatibility is the ordinary renderer, with Apple Silicon Mobile/Metal selection. Older stable Godot decal guidance is insufficient for this build |
| [`workshop_customization.gd`](../../../../app/ui/workshop_customization.gd), [`aircraft_customization.gd`](../../../../app/render/aircraft_customization.gd) | Appearance edits include paint and fixed authored registration text. Markings create `Label3D` children at registered targets, not draggable arbitrary sponsor images |
| [`presentation.gd`](../../../../app/workshop/presentation.gd) | Current version is **4**, with exact allowed keys, canonical presentation identity, a 65,536-byte profile cap and up to 16 fixed text entries. The parent plan retains some historical v1 delivery descriptions; current code owns the version |
| [`workshop_preview.gd`](../../../../app/ui/workshop_preview.gd) | `set_aircraft()` builds `AirplaneBuilder.build(id)` without a chosen livery. Current preview does not inherit Home's selected skin automatically |
| [`main.gd`](../../../../app/main.gd) | `_build_world()` passes an empty livery for Workshop trials. Explicit visual-base propagation is required for decals over a selected paint |
| [`airplane.gd`](../../../../app/render/airplane.gd), [`vehicle_paint.gd`](../../../../app/render/vehicle_paint.gd), [`custom_skin.gd`](../../../../app/aircraft/custom_skin.gd) | Existing stock and `.orskin` paths already apply per-instance appearance with source/family identity checks. Preserve them and their immutable materials/archives |
| [`trial.gd`](../../../../app/workshop/trial.gd) | `freeze()` constructs a separate presentation identity; the physical trial identity derives from recipe, source, descriptor, model, dependencies and compiler. Cosmetic work must preserve this separation |
| [`workshop.gd`](../../../../app/ui/workshop.gd) | `_history_snapshot()` includes recipe and presentation profile; existing Undo/Redo is shared. Recovery and named revisions have different save boundaries |
| [`store.gd`](../../../../app/workshop/store.gd), [`draft_store.gd`](../../../../app/workshop/draft_store.gd) | Immutable revisions and detached recovery already exist. Editor-buffer fields are strict; image dependencies and pending gestures need explicit admission |
| [`profile_transfer.gd`](../../../../app/workshop/profile_transfer.gd), [`bundle.gd`](../../../../app/workshop/bundle.gd) | Transfer knows named appearance domains and versions through 4; the portable bundle is closed v1 JSON with a 24 MiB cap and no image-payload collection. Hash-only local images cannot provide a fresh-install round-trip |
| [`crash/effects.gd`](../../../../app/render/crash/effects.gd) | Existing ground marks allocate a bounded pool of up to eight native decals per world, with a fallback. Native decal capacity is already shared with other effects |
| [`section_splitter.gd`](../../../../app/render/crash/section_splitter.gd), [`wreck.gd`](../../../../app/render/crash/wreck.gd) | Crash partitioning replaces source mesh nodes with section siblings and frees the original node. A sticker child cannot be assumed to survive. Added meshes can also affect wreck grouping/bounds unless excluded |
| [`tools/skins/README.md`](../../../../tools/skins/README.md) | Stik and Avanti have shared, mirrored, repeated and overlapping UV regions, unequal texel density and separately moving parts. A generic bake into their existing UVs cannot guarantee independent readable lettering |

The preview currently uses left-button drag for camera orbit. A decal gizmo must
change input arbitration intentionally; simply adding another left-drag handler
would make the camera and sticker move together.

## Engine correction that changes the design

Godot's stable and even a class-documentation snapshot say Compatibility decals
are unsupported. The official 4.8 dev 4 release notes introduce Compatibility
support through GH-118070. Beta 2 identifies build `cafc17a19`; the **actual
GLES3 source at that commit contains decal pairing, uniforms and shading**.
The [source register](sources.md#engine-version-and-rendering) records both
the contradictory documentation and direct source evidence.

This is source evidence, not a rendered qualification. The advertised limits
(eight per receiver/surface, hardware-limited default 64 per frame/view) still
prevent a naive unlimited projector list. The exact source pairs a bounded decal
array to a geometry instance, so count all intersecting projectors, not just
visible logo pixels or nominally different material surfaces. Do not spend the
entire view budget without accounting for ground marks and scenery.

## What is delivered

The branch includes the staged plan, actual source integration map, input and
layer semantics, rendering alternatives, persistence/migration design, performance
and regression matrix, official source inventory, exact-byte reference images,
an offline interaction study, a closed JSON proposal with two synthetic examples,
and reproducible asset/contract checks. All production step statuses remain in
the [plan](../../../plans/sponsor-decal-workshop.md#implementation-packages-and-acceptance).

Two bounded researchers inspected architecture and sponsor evidence; an independent
UI draft supplied the initial study. The lead verified decisive source claims,
resolved the Godot documentation conflict using exact upstream code, found the
Hitec MIME mismatch, integrated the study and owns the final package. Recommended
overlay geometry and source-scope distinctions were accepted. Universal UV baking,
unlimited native projectors and automatically treating support as a decal license
were rejected for the concrete reasons above. Final review and executed checks
are recorded in [validation](validation.md).
