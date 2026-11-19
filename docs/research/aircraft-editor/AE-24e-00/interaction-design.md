# Player experience: a livery Workshop

This is the proposed production interaction contract for
[AE-24e](../../../plans/sponsor-decal-workshop.md), not a description of shipped UI.
The [flat interaction study](../../../../research/aircraft-editor/sponsor-decals/workshop-preview.html)
demonstrates a subset with local images and no network dependency.

## Entry and screen composition

Enter **Workshop → Appearance → Decals** on the currently selected aircraft and
visual base. Keep the aircraft large and well lit in a neutral hangar. Show an
obvious unsaved-change indicator and the existing Save / Test Flight / Back flow.

At 1920×1080, use a roughly 260-pixel searchable library on the left, a flexible
3D preview in the center and a roughly 300-pixel layer/transform panel on the
right. These are layout starting points, not fixed pixel assumptions: scale for
UI size and localization, collapse the library or inspector on narrower views,
and avoid shrinking the aircraft to fit a long sponsor list. Above-1080p and
native Retina targets retain readable physical control sizes.

The library groups **Sponsors & supporters**, **OpenRC**, and later **My decals**.
An approved card shows the real artwork on switchable light/dark contrast,
organization name and a short contribution credit. An About action opens its
official website; selecting a card never opens an external link unexpectedly.
Keep software/permission details in developer intake and About, not in the
ordinary placement flow. Only admitted artwork is offered for placement in a
shipped catalog. The research study deliberately shows pending entries as source
references so maintainers can review the intake work.

## Main journey

1. Select a decal. A translucent ghost follows the valid surface under the pointer.
2. Click an eligible surface to place it; click empty space or press Escape to
   cancel. A selected layer has a bounding outline, corner scale handles and a
   rotation ring. The ghost is not a saved placement.
3. Drag the image to move it along the aircraft. Drag a corner to resize with
   original proportions. Drag the ring for unrestricted rotation. Exact fields
   expose width, angle and local position for fine adjustments.
4. Add the same or another sponsor again, use Duplicate, or copy to a paired
   opposite surface. Every instance is individually selectable in the layer list.
5. Reorder overlapping layers; lock completed elements; hide elements temporarily;
   delete mistakes or Undo the complete action.
6. Save the design and Test Flight. Return to the same draft, selection and camera.
   A saved design can later be reopened, copied to a compatible aircraft or reset.

The aircraft remains visible when the library is empty. Unsupported surfaces show
one useful reason next to the pointer (for example, “Choose a painted body panel”)
and never accept an invisible placement. Reaching the candidate 64-instance cap
explains the limit and offers selection/removal, preserving the current draft.

## Input map

| Intent | Mouse / keyboard | Controller/focus equivalent |
| --- | --- | --- |
| Place or select | Left click; layer-list click selects hidden/occluded layers | Select a card, confirm receiver, then confirm placement |
| Move selected decal | Left drag on the decal or move handle | Move mode; left stick/D-pad with fine/coarse modifier |
| Orbit / pan / zoom camera | Right drag or Alt+left drag; middle drag; wheel over preview | Camera mode with separate orbit and zoom actions |
| Resize | Corner handle; exact width; smaller/larger buttons | Scale mode or focusable stepper |
| Rotate | Ring; numeric angle; Q/E steps when viewport owns focus | Rotate mode or focusable angle stepper |
| Snap / fine adjustment | Shift: 15° rotation snap; fine numeric steps; arrow nudges in active local axes | Explicit Snap and Fine controls |
| Flip artwork | Separate Horizontal and Vertical buttons | Same focusable buttons |
| Duplicate / delete | Ctrl+D / Delete, with visible buttons | Duplicate / Delete actions |
| Undo / redo | Ctrl/Cmd+Z; Ctrl/Cmd+Shift+Z or Ctrl+Y | Persistent focusable Undo / Redo |
| Cancel current gesture | Escape, pointer cancellation or lost interaction focus | Back/cancel |

These bindings are proposals and must be reconciled with current Workshop shortcuts
and platform conventions. Text/numeric fields retain their normal keyboard editing.
Wheel scrolling over the library does not change decal scale or camera distance.
The current left-drag orbit handler in `workshop_preview.gd` must yield to edit mode.
Dragging into a UI panel does not place a sticker through that panel.

## Transforms and composition

**Proportions:** preserve the original image's complete content and aspect. A
numerical width updates height; do not silently stretch a sponsor wordmark.
Transparent clear-space padding is part of the mark unless its source explicitly
permits trimming. Initial placement uses a comfortable surface-relative size;
small/large are independent instances, not alternate bitmap files.

**Rotation:** any angle is supported for artwork whose treatment permits it. Rotate
around the image center in the local surface tangent frame; numeric values and
handles use the same canonical angle. A brand may later restrict transforms through
its approved entry. The underlying editor still supports both flips for OpenRC and
personal/test artwork.

**Flip versus opposite-side copy:** Horizontal/Vertical Flip reverses the pixels
deliberately. “Copy to other side” uses an authored paired receiver and reconstructs
an upright frame so text remains readable. It must not implement a negative scale
of the aircraft root. A mirrored pair starts linked only when the user chooses a
link option; otherwise it is two independent instances. Cross-aircraft placement
requires review and a valid receiver map, never a guessed scale of old coordinates.

**Layers:** the document array is bottom-to-top; the UI lists topmost first. Bring
forward/back changes composition deterministically. Selection, visibility and lock
states are clear without relying on color alone. A locked layer cannot be dragged
or deleted accidentally; the list still allows selection, unlocking and visibility.
Group/multiselect transforms are a later extension, not required for the first slice.

**Surface boundaries:** initially place within one rigid opaque receiver. A decal
that crosses a hinge or separate part is clipped to its selected receiver, with a
visible result; it must not bridge the moving gap or project through the fuselage.
Later “split across parts” is one document operation that creates linked fragments
with independent local attachments. Glass, propellers/rotor blur, fabric deformation
and skinned receivers remain unavailable until their own proof exists.

## Transactions, save and recovery

Pointer-down captures the accepted starting state. Pointer motion changes a preview
transaction; pointer-up validates and records one shared history entry. Escape,
pointer cancellation or losing the owning viewport restores the start. Invalid
numeric text remains editable recovery state and cannot become a frozen flight
profile. Undoing a drag must not walk through hundreds of pointer positions.

Reset is scoped: **Reset selected decal**, **Clear decals**, or the existing
Appearance reset. Clear decals is a reversible single history action and does not
change the selected base skin, paint colors, smoke, lighting, sound or physics.
Leaving with unsaved work uses the existing full-draft guard. Auto-recovery is not
named Save. Failed writes/imports keep the last accepted design and original assets.

Loading a design whose source image is missing displays that layer's preserved
placeholder and an actionable explanation. The user can relink a compatible image
or remove that layer explicitly. Never silently replace a sponsor with a different
mark, clear a saved placement, or revert the whole airplane to factory paint.

## Acceptance visible to the player

Test tiny and large versions of the same logo, repeated stickers on one panel,
intentional overlap, 180° rotations, both explicit flips, readable opposite sides,
camera orbit behind/under the model and fully deflected controls. The pointer,
gizmo, numeric values and saved result must agree. Low graphics, a reload, a trial,
return, a crash and repair must preserve the authored composition.

The study currently demonstrates a single flat top-view board. It allows positions
outside the silhouette and does not claim surface clipping, orbit, 3D picking,
opposite-side pairing, flight, `.orskin` import or production format compatibility.
