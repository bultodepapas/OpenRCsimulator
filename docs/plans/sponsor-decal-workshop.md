# Sponsor decal Workshop

**Owner:** Aircraft Workshop (AE), appearance subtrack **AE-24e-00…10**.
**Created:** 2026-11-18. **Research expanded:** 2026-11-19. **Status:** 60 sequential
investigations in batches of 10, 20 and 30, integrated design, source assets, an
offline interaction study, 37 executable arithmetic/ownership cases and proposed
data contracts delivered. Production editor, rendering and
fleet/performance qualification remain pending.

The player should open **Workshop → Appearance → Decals**, choose a supporter
sticker, place it directly on the aircraft, and build a personal livery from many
large or small copies. Movement, proportional resizing, rotation, horizontal and
vertical flips, duplication, layer order and Undo/Redo are first-class controls.
The catalog also explains each partner's contribution and links to its official
site, making the feature a visible thank-you to the people helping OpenRC.

## Start here

| Need | Authoritative handoff |
| --- | --- |
| 60 investigations, three syntheses and revised decisions | [Sequential research R1](../research/aircraft-editor/AE-24e-00-R1/README.md) |
| What the existing code actually does | [Dated source audit](../research/aircraft-editor/AE-24e-00/README.md) |
| Player workflow, controls and edge cases | [Interaction design](../research/aircraft-editor/AE-24e-00/interaction-design.md) |
| Rendering, model binding, persistence and integration | [Architecture](../research/aircraft-editor/AE-24e-00/architecture.md) |
| Organizations, logo sources and recorded scopes | [Sponsor register](../research/aircraft-editor/AE-24e-00/sponsor-register.md) |
| Exact original images, catalog, examples and runnable study | [Research pack](../../research/aircraft-editor/sponsor-decals/README.md) |
| Acceptance, measurements and current verification | [Validation](../research/aircraft-editor/AE-24e-00/validation.md) |
| Engine and asset research | [Primary source register](../research/aircraft-editor/AE-24e-00/sources.md) |

The [parent AE plan](aircraft-editor.md) retains the current Workshop's status.
This subplan owns image decals; it does not replace existing paint, fixed text
markings, smoke, lighting or mechanical-audio profiles.

## Product scope

The first playable slice covers a procedural aircraft and an imported aircraft
with explicitly authored rigid, opaque receivers. Start with Ugly Stik and the
Vantage Jet because their mirrored/repeated UVs expose real failure cases. Their
names select qualification fixtures, not hard-coded runtime dispatch. Register
other aircraft through the same generated receiver contract after proof.

The initial design target is **64 saved decal instances and 16 unique images per
aircraft**, including repeated copies of one sponsor. These are proposed product
and resource bounds, not measured frame-rate claims. A single part must support
more than eight visible decals, including dense overlapping layers. Lower quality
may reduce texture resolution; it must preserve the saved composition and order.

The player can add, move, scale, rotate, explicitly flip, duplicate, mirror the
placement to an authored opposite part while keeping letters readable, reorder,
hide, lock, delete, undo, redo, save, reopen and test-fly a design. A whole drag is
one history action. Save and Test Flight operate on an accepted, frozen revision.
Leaving the page retains the existing save/discard/recovery protections.

An aircraft's selected stock paint or imported `.orskin` forms the explicit visual
base. Decals are a separate editable layer. The result must match in the Workshop,
saved-build thumbnail, trial, return, restart and supported ordinary flight path.
Damaged parts keep the corresponding cosmetic result; repair restores it.

All sponsor entries remain free. There is no ad tracking, remote image fetch during
flight, purchase flow, new account or online service. Community galleries and Steam
Workshop are a possible later distribution feature, separate from this in-game
Workshop. Personal PNG import follows a later bounded input/portability step.

## Decisions for implementation

1. **Preserve the admitted legacy presentation path.** Prototype a separate v5
   facade/envelope, explicit visual base, decal stack and source-proof package.
   Existing proof-covered files include `presentation.gd` itself; do not casually
   modify them and regenerate every old companion. Retain the canonical legacy
   projection/identity and dispatch it to every legacy effect consumer. The
   [compatibility route](../research/aircraft-editor/AE-24e-00/architecture.md#6-persistence-migration-and-portability)
   defines the source, storage and exported-package gates. Old builds are not
   promised to import v5.
2. **Keep decals outside simulation identity.** Geometry selection, sticker bytes,
   transforms and rendering caches are presentation inputs. They must not enter
   aircraft parameters, physical model/dependency hashes, mass, inertia, contact,
   fixed-tick state or replay solver identity.
3. **Prove projected overlay meshes as the dense-stack default.** Clip stickers to
   authored semantic regions on rigid receivers, preserve source UVs/materials,
   use explicit layer order and cache the accepted result. Adjacency alone is not
   a paintable-region contract; bounded UVs alone do not prove a valid projection. Native Godot projectors are a bounded
   preview/alternative, not one unlimited projector per saved sticker. The pinned
   4.8 beta supports Compatibility decals, but its per-receiver limit and shared
   view budget remain material constraints. No renderer change is required.
4. **Use original assets and explicit catalog scope.** Preserve source bytes and
   provenance, then generate approved runtime derivatives. Brand-specific
   transformation/distribution rules come from recorded permission. Support or a
   public download is not automatically a freeform decal grant. This branch
   prepares all work without sending new permission requests.
   The [R2 preparation guide](../research/aircraft-editor/AE-24e-00/artwork-preparation.md)
   adds verified vector/color/icon sources, derivative decisions and independently
   enforced study capabilities; production admission remains part of this sequence.
5. **Reuse the editor's transaction and save boundaries.** Extend the shared history,
   recovery, immutable saved revisions, visual identity and bundle validation.
   Reuse `StrictJSON` and the reviewed custom-skin admission foundations. Own
   mutable job outputs per generation; revision tokens alone cannot prevent stale
   writes into a frozen design.
6. **Admit aggregate resources and complete visual dependencies.** Image count,
   file size and GPU memory are different budgets. Sixteen 1024² RGBA8 mip chains
   require 89,478,464 bytes before any other resource, so the 32 MiB candidate
   target cannot admit that combination. Portable export must include the exact
   required custom `.orskin` base as well as sticker bytes, or explicitly declare
   a dependency-requiring package. Preserve local work when an export is unavailable.

The [architecture decision and alternatives](../research/aircraft-editor/AE-24e-00/architecture.md#rendering-choice)
defines the proof that can change the rendering choice. The offline study is an
interaction artifact, not evidence that any 3D option has passed.

## Ownership and proposed paths

This branch owns this plan, `docs/research/aircraft-editor/AE-24e-00/`,
`docs/research/aircraft-editor/AE-24e-00-R1/` and
`research/aircraft-editor/sponsor-decals/`. Existing global navigation remains unchanged.
All runtime paths below are **proposed**, not implemented here.

| Owner / seam | Proposed work |
| --- | --- |
| AE | `app/workshop/decal_catalog.gd`, `decal_stack.gd`, `decal_assets.gd`, separate `presentation_facade.gd`/v5 validator and visual proof package; intentional dispatch through `store.gd`, `draft_store.gd`, `trial.gd`, `bundle.gd`, `profile_transfer.gd`; preserve legacy proof-covered sources |
| AE + UI | `app/ui/workshop_decals.gd`; small integration into existing Workshop customization and preview; i18n strings and focus navigation |
| AE + rendering | `app/render/decals/`; read-only source mesh selection, projection, material isolation, cache and lifecycle |
| AS + aircraft owners | Authored cosmetic receiver IDs, exact topology/LOD identities, hinge and opposite-side maps generated through the owning source pipeline |
| UI / session / aircraft builders | Explicit base-paint selection through preview, saved build, thumbnail and flight; retain existing owner entry points |
| CR | Wreck-section remapping, cosmetic-only exclusion from bounds/grouping/contact calculations and repair lifecycle |
| AE + WEB / maintainer | Approved catalog/source records; current `site/BRANDS.md` stays authoritative for existing relationship scope |

## Implementation packages and acceptance

| Step | Small reviewable change | Required proof / status |
| --- | --- | --- |
| AE-24e-00 / R1 | Audit, source inventory, exact image pack, interaction study, proposed schema, 60 sequential investigations with three syntheses, 37 offline exercises and integrated handoff | Delivered in this branch; [bounded verification](../research/aircraft-editor/AE-24e-00/validation.md). No production feature claim |
| AE-24e-01 | Two-family rendering spike: native projector vs projected geometry; 0/1/2/8/9/32/33/64 instances, identical and different images, overlapping and separated | **Pending.** Capture side/top/bottom, moving control surfaces, camera reversal, low/high detail, source immutability, scaling, occlusion and dense layer order on pinned engine |
| AE-24e-02 | Generated receiver contract and identity: opaque surface allowlist, local frame, LOD and part pairing | **Pending.** Invalid/stale receivers refuse explicitly; no triangle index assumed stable; source geometry/UVs and physics unchanged |
| AE-24e-03 | Separate v5 facade/envelope, legacy projection, trusted registry/proof admission, own export marker and catalog/image helpers; 64 KiB whole-profile candidate | **Pending.** Baseline-admitted v1–v4 remain usable with unchanged legacy identity/effects in source and exported PCK. New composite identity changes; physical bytes/hashes do not. Forged/stale/missing proofs refuse without replacing work |
| AE-24e-04 | Playable editor slice: picker, exact picking, placement/transform, duplicates, list, layer order and shared Undo/Redo | **Pending.** One gesture = one undo; pointer cancel/focus loss restores start; camera orbit does not compete with placement; numeric/keyboard/controller controls match gizmos; alpha-aware selection has list/cycle fallback; Duplicate/Stamp and ordering keep selection |
| AE-24e-05 | Freeze and apply the explicit stock/custom base plus decal stack through preview, Library thumbnail and trial/return/restart | **Pending.** Same source identities and visible result everywhere; no factory fallback when custom image is unavailable; original skin bytes unchanged |
| AE-24e-06 | Atomic named save, detached recovery, reopen and compatible-only copy; user asset lifecycle | **Pending.** Process-boundary failures preserve last accepted revision; undo/recovery references retain their image bytes; incompatible copy reports omitted placements |
| AE-24e-07 | Bounded portable package and optional personal PNG import | **Pending.** Fresh-install round-trip with admitted logo bytes and exact custom-base archive; complete encoding/decoded/peak budgets; missing/corrupt/oversized input has no partial publication. Unapproved brand export stays unavailable with an explanation |
| AE-24e-08 | Crash, detached parts, repair, replacement meshes and display-detail transitions | **Pending.** Actual synchronized LOD selection or proven geometry equivalence, correct section remapping, no ghost overlays, identical wreck grouping/bounds/contact with decals on/off; owned-job and frozen-output cleanup |
| AE-24e-09 | Hardware and accessibility qualification; expand receivers to the fleet | **Pending.** [Measurement matrix](../research/aircraft-editor/AE-24e-00/validation.md), readable controls, translations, native focus/controller routes, off-state resource behavior |
| AE-24e-10 | Approved sponsor pack activation, attribution, distribution review and current player documentation | **Pending.** Each shipped asset has admitted scope/source/transform flags, final preview and owner-required credit; source and build manifests agree |

AE-24e-01 is the first rendering task. In parallel, a bounded AE-24e-03 call-site
and source-proof feasibility check must confirm the proposed facade route before
any legacy pinned file is changed. Do not begin a fleet-wide asset conversion
until the two-family spike resolves layer order, UV-independent placement, LODs,
hinges and wreck behavior. Asset intake and UX review can proceed independently.

## Definition of done

A player can place nine logos on the same qualified body part and at least 32
across the aircraft without missing or camera-dependent layers; the 64-instance
candidate boundary is qualified or explicitly revised using evidence. A tiny logo
and a large logo preserve proportions; a deliberate flip is distinct from a
readable copy to the other side. Save/reopen, failed import, Undo/Redo, recovery,
trial/return, crash/repair and all accepted graphics tiers preserve the design.

The delivered evidence identifies source commit, pinned engine, operating system,
renderer, GPU and actual pixels. Standard desktop review is 1920×1080 first.
Apple Silicon on a Retina display follows the native physical-panel exception in
[AGENTS](../../AGENTS.md#display-resolution-priorities), recording output, drawable
and internal 3D pixels separately. The feature is cosmetic at every quality tier.

## What the expanded research changed

The [three-stage synthesis](../research/aircraft-editor/AE-24e-00-R1/README.md#staged-synthesis)
turns the investigation into implementation decisions: authored paint regions,
independent alpha/order oracles, renderer-specific picking and LOD gates, owned
asynchronous outputs, aggregate texture admission, complete custom-base
portability and a concrete legacy-proof-preserving facade proposal. Game/editor
examples informed the controls without importing their advertised performance.
All first-slice limits remain candidates until measured; the offline study and
37 exercises do not close the native matrix.
