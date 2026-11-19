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
Show the operations available for the chosen artwork, with a short explanation
when an action is unavailable. Capabilities and approved variants are reviewed
per asset: do not assume that every sponsor permits rotation, pixel flips,
recoloring or distortion. Demonstrate unrestricted editing with project-owned
or test artwork rather than inferring a sponsor's permissions from its logo.
Keep software/permission details in developer intake and About, not in the
ordinary placement flow. Only admitted artwork is offered for placement in a
shipped catalog. The research study deliberately shows pending entries as source
references so maintainers can review the intake work. See
[investigation 57](../AE-24e-00-R1/investigations-31-60.md#57-catalog-transform-permissions-are-per-asset-not-a-universal-logo-switch).

## Main journey

1. Select a decal. A translucent ghost follows the valid surface under the pointer.
2. Click an eligible surface to place it; click empty space or press Escape to
   cancel. The ghost is not a saved placement.
3. Select a placed decal on the aircraft or in the layer list. A selected layer
   has an outline and controls for the transforms its asset permits. Transparent
   parts pass selection through to a visible layer below; cycling candidates and
   the layer list provide alternatives for tiny, hidden or covered decals.
4. Move the image along the aircraft, resize it proportionally and rotate it when
   that asset permits rotation. Use handles, visible step controls or exact fields.
   Keep its orientation steady during a continuous move; explain when a jump to
   an incompatible surface cannot be made.
5. Add the same or another sponsor, use Duplicate, enter Stamp mode for repeated
   placements, or make a readable copy on a paired opposite surface when the asset
   and pairing allow it. Every placement is an individually selectable layer.
6. Use visible layer-order commands; lock completed elements; hide elements
   temporarily; delete mistakes or Undo the complete action.
7. Save the design and Test Flight. Return to the same draft, selection and camera.
   A saved design can later be reopened, copied to a compatible aircraft or reset.

The aircraft remains visible when the library is empty. Unsupported surfaces show
one useful reason next to the pointer (for example, “Choose a painted body panel”)
and never accept an invisible placement. Reaching the candidate 64-instance cap
explains the limit and offers selection/removal, preserving the current draft.

## Input map

| Intent | Mouse / keyboard | Controller/focus equivalent |
| --- | --- | --- |
| Place or select | Click a surface or layer; cycle overlapping candidates | Select a card, confirm receiver and placement; use layer list or cycle |
| Move selected decal | Left drag, select then choose a destination, or use position fields and nudge buttons | Toggled Move mode, directional nudges, fields and Confirm |
| Orbit / pan / zoom camera | Right or middle drag; wheel over preview; selectable Camera mode | Toggled Camera mode with separate orbit and zoom actions |
| Resize | Corner handle, exact width, or visible smaller/larger steps | Toggled Size mode or focusable stepper |
| Rotate | Ring, numeric angle, or visible rotation steps | Toggled Rotate mode or focusable angle stepper |
| Snap / fine adjustment | Separate Snap and Normal/Fine controls; optional shortcut | The same focusable toggles and discrete steps |
| Flip artwork | Separate Horizontal and Vertical buttons when permitted | Same focusable buttons |
| Duplicate / stamp / delete | Visible Duplicate, Stamp and Delete; optional Ctrl+D / Delete | The same named, focusable actions |
| Layer order | Visible Up, Down, Top and Bottom commands | The same focusable order commands |
| Undo / redo | Ctrl/Cmd+Z; Ctrl/Cmd+Shift+Z or Ctrl+Y | Persistent focusable Undo / Redo |
| Cancel current gesture | Escape, pointer cancellation or lost interaction focus | Back/cancel |

These bindings are proposals and must be reconciled with current Workshop shortcuts
and platform conventions. All core actions need a single-pointer, keyboard-only
and gamepad-only path without compulsory held or simultaneous inputs. Modifiers
may be optional accelerators. Give modes and controls visible focus, use current
input mappings for button hints, and keep flight input inactive while the editor
owns focus. Text/numeric fields retain their normal keyboard editing. Wheel
scrolling over the library does not change decal scale or camera distance.

For the integration, give each pointer gesture one owner: idle, placement,
transform or camera. GUI controls consume their events before scene gestures;
the current left-drag orbit handler in `workshop_preview.gd` must yield to edit
mode. Convert the pointer into the actual rendered preview rectangle, reject
letterbox/outside points, and use the preview camera's ray origin and direction
for its projection. Qualify resizing, scaling, letterboxing and orthographic as
well as perspective views. Dragging into a UI panel must not place through it.
Escape, cancellation or lost focus releases the owner and restores the gesture
start. See [investigations 21–23](../AE-24e-00-R1/investigations-11-30.md#21-input-routing-before-camera-arbitration)
and [32–34](../AE-24e-00-R1/investigations-31-60.md#32-use-the-preview-cameras-complete-placement-ray).

Selection picking is distinct from surface placement: choose the topmost visible
layer whose artwork has sufficient alpha at the picked point, applying the same
image transform and flips. A bounded cached alpha mask is a candidate; avoid
per-pointer GPU readback. Alpha threshold, sampling tolerance and cycling order
need product testing, and the layer list remains the fallback. See
[investigation 52](../AE-24e-00-R1/investigations-31-60.md#52-visible-pixel-selection-and-geometric-ray-hits-are-different-editor-behaviors).

## Transforms and composition

**Proportions:** preserve the original image's complete content and aspect. A
numerical width updates height; do not silently stretch a sponsor wordmark.
Transparent clear-space padding is part of the mark unless its source explicitly
permits trimming. Initial placement uses a comfortable surface-relative size;
small/large are independent instances, not alternate bitmap files.

**Rotation and precision:** permit any angle only where the asset allows it. Rotate
around the image center in the local surface tangent frame; numeric values and
handles use the same canonical angle. As **untested starting proposals**, use
15° normal / 1° fine rotation steps and 5% normal / 1% fine size steps; use
receiver-relative movement with displayed centimeters. Optional snapping is
separate from fine adjustment. Switching modes keeps the current transform as the
new adjustment origin, without a jump. Validate step sizes at actual aircraft
scales before setting defaults. See
[investigations 53–54](../AE-24e-00-R1/investigations-31-60.md#53-gamepad-editing-needs-discrete-actions-and-visible-focus).

**Flip versus opposite-side copy:** Horizontal/Vertical Flip reverses the pixels
deliberately, only if that asset permits it. “Copy to other side” uses an authored
compatible paired receiver and reconstructs an upright frame so text remains
readable; it does not silently flip the artwork. Disable or omit paired copy with
a useful explanation when the asset disallows it or an authored pairing is
unavailable or incompatible.
It must not implement a negative scale of the aircraft root. A pair starts linked
only when the user chooses a link option; otherwise it is two independent
instances. Cross-aircraft placement requires review and a valid receiver map,
never a guessed scale of old coordinates.

**Layers:** the document array is bottom-to-top; the UI lists topmost first. Bring
forward/back and Top/Bottom change composition deterministically. Keep the selected
instance selected while editing or reordering; Duplicate selects its new instance,
and Stamp selects the last placed instance until the player changes selection.
Each layer has a name and thumbnail. Selection, visibility and lock states are
clear without relying on color alone. A locked layer cannot be dragged or deleted
accidentally; the list still allows selection, unlocking and visibility. Start with
independent sponsor instances. Saved groups, masks and group transforms/opacity
are later extensions, not required for the first slice. See
[investigation 55](../AE-24e-00-R1/investigations-31-60.md#55-repeated-logo-workflows-benefit-from-direct-layer-commands-and-stable-selection).

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
gizmo, numeric values and saved result must agree. Exercise transparent corners,
covered and tiny layers, cycle selection, and the complete select/place/edit/save/
cancel journey with keyboard only, gamepad only and without precise dragging.
Check mode switching for jumps and visible selection after repeated placements
and reordering. Low graphics, a reload, a trial, return, a crash and repair must
preserve the authored composition.

The study currently demonstrates a single flat top-view board. It allows positions
outside the silhouette and does not claim surface clipping, orbit, 3D picking,
opposite-side pairing, flight, `.orskin` import or production format compatibility.
