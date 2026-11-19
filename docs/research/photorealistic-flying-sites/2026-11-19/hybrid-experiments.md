# Hybrid scenery: concrete experiments and integration plan

2026-11-19. Proposed evidence work for the
[hybrid design](hybrid-scenery.md), using the
[existing-asset audit](hybrid-reuse-audit.md) and
[documented precedents](hybrid-precedents.md). No HX experiment below has run.
The [SC-PHOTO plan](../../../plans/photorealistic-flying-sites.md) remains the
only status ledger; HX identifiers name comparison cases, not extra delivery
tracks or claims of implementation.

## Sequence and decision points

| Case | Decision it resolves | Existing step / proof owner |
| --- | --- | --- |
| HX01 | Can a fixed-eye photograph and the current 3D trees form one convincing, correctly occluding scene? | SC-PHOTO-02; C01–03; Q01/Q03/Q04 |
| HX02 | Can a photographed object be replaced without leftover silhouette, shadow or reveal artifacts? | Synthetic subset in 02; real-site work in 01/07; C02/C03/C07; Q02–04/Q10 |
| HX03 | Which local ground, lighting, shadow and reflection composition actually works? | Synthetic subset in 02; integration in 05; C03/C04; Q04/Q05 |
| HX04 | Which current mesh/card/filter/wind/batching choices preserve detail at an acceptable cost? | Subset in 02; final 05/07/09; C03/C05/C09; Q03/Q06/Q11 |
| HX05 | Does the accepted hybrid remain correct through normal use, failure, settings and export? | SC-PHOTO-03…10, including 04a/required 04b; Q06–12 |
| HX06 | How much real geometry is needed before moving cameras can be admitted? | Conditional SC-PHOTO-11/12; later stereo in 13; full view/contact/platform evidence |

First prove the proposed SC-PHOTO-02 synthetic opaque projection/color fixture.
Then run HX01 and the
necessary HX03 receiver/light subsets together; no full site capture is needed.
HX02 is required only where a real asset replaces photographed content. HX04
first checks existing behavior, then runs only alternatives motivated by an
observed defect or bottleneck. HX05 qualifies the selected result. HX06 is a
separate product/camera decision; success in HX01 never unlocks it implicitly.

## Shared fixture and evidence contract

Use the exact Godot pin `4.8.beta2.official.cafc17a19`. Record source/derivative,
physical-inventory and export identities separately under C07. Keep the same
accepted aircraft state/input sequence, camera projection, image transform,
light reference and visible object inventory for every meaningful A/B comparison.
A visual-only diagnostic scene may not be presented as a flyable field.

The first synthetic layout is deliberately small and reproducible. Proposed
authoring coordinates below are NED metres and refer to object ground origins;
they are **fixture values, not a new runtime schema or a real-field survey**.

| Element | Proposed fixture placement / role |
| --- | --- |
| Pilot eye | N=0, E=0, D=−1.65; fixed translation throughout the first cases |
| Flat reference runway | N=30…40, E=−50…50, D=0, east/west alignment; ground/support semantics retained from the approved fixture |
| Pine | `landscapelab_pine`, N=65, E=−30, D=0, target height 10 m |
| Beech | `landscapelab_fagus`, N=75, E=30, D=0, target height 12 m |
| Opaque reference obstacles | Known boxes outside the runway corridor, with independent dimensions and front/behind aircraft samples |
| Local visual ground | Bounded patch large enough to contain selected visible contact and shadow footprints; record exact final bounds after choosing sun direction |
| Distant geometry in reference A | Independently specified static prism bounds N=650…670, E=−230…−200, D=−50…0, plus a known distant ground/horizon mesh; retain their exact authoring coordinates |
| Distant appearance in B | Capture that same distant geometry/ground and sky from the fixed eye, with local trees, boxes, patch and aircraft excluded; preserve the clean reference and image transform |
| Aircraft samples for this render diagnostic | Fully contained within N=0…150, E=−80…80, D=−60…0 after including full aircraft extent; they cannot pass behind the specified distant prism |

These exact close trees are **direct factory placements in a non-flyable
rendering fixture**: `fit_to_height` → `queue` → `build`. The existing validated
treeline route rejects these distances/clearances, and `FieldTreeDetail` hashes
species and height rather than accepting the requested named trees. No change
to `FieldLoader` is implied by this diagnostic. Its known geometric reference
is not an already admitted physical inventory. Before live use, choose supported
validated placements or implement/review the SC-PHOTO-04 builder and any required
site/corridor rules; then run the physical checks in HX05.

Ground anchoring, source bounds and shadow footprint determine the final patch;
do not select an arbitrary radius and hide the resulting edge. If these tree
sizes/transforms do not satisfy the current wind/collision assumptions, keep
them static or revise the fixture before the animated comparison. The render
transforms do not become solver input. Set and record the per-batch caster flag:
the distant-tree wrapper disables shadows, whereas direct factory builds enable
them. Keep that choice identical in A/B; qualify any new local casting/receiving
behavior in HX03 before making a photorealism claim.

Use the existing Blender asset workflow for a future synthetic photographic
reference. Record the camera, scene, source hashes, lighting and color transform,
including both original and cleaned renders. Geometry/visibility truth must
come from independently known placement, not fitting the candidate to its own
output. Q04's independent color reference remains necessary even if two Godot
paths agree. No Blender render has been generated by this planning revision.

Every receipt includes exact OS/GPU/driver, renderer/backend, output/drawable/
internal pixels, MSAA/upscaler, FOV, eye, exposure, background/asset identities,
weather, graphics settings and accepted simulation time. Apply 1080p-first
priorities except the existing Apple Silicon Retina native-panel requirement.
Record stills plus temporal sequences where motion, shimmer or a transition
is the actual question.

## HX01 — fixed-eye hybrid control

**Variants.** A is a known ordinary 3D reference with a sky-only background,
the independently modeled distant prism/ground, the two local trees, reference
boxes and local patch. B retains exactly those local objects and the known
obstacle reference but replaces the distant scenery with the calibrated capture
defined above. Any admitted physical data is identical; this diagnostic itself
does not claim a flyable field. Local materials, placements, sun, camera and
aircraft states remain equal.

Hold ambient, radiance/reflection reference, probe policy, exposure/tonemap and
fog constant too. Use a shared independently specified lighting setup, or an
explicitly limited diagnostic with sky-derived ambient/reflections disabled in
both variants. Merely swapping a Sky can relight local objects and is not an
isolated background comparison. Actual aircraft reflections and the selected
production lighting still require HX03. Record what each sky/probe captures.

Keep the simpler full-photo/proxy candidate from SC-PHOTO-02 as a separate
production option. A fair later comparison against it must show the same tree
inventory in its photograph and supply qualified tree occlusion; it is not
valid to benchmark a tree-free image against a scene containing extra trees.
Neither a background-only diagnostic with invisible contacts nor a cardboard
silhouette that fails Q03 can be a release candidate.

**Stimulus.** Sweep the supported headings, the panorama seam and vertical FOVs 120°, 75°,
45°, 15°, 6° and 1°. Place the aircraft immediately in front of, behind, above
and beside the known boxes and tree crown/trunk boundaries, including crown
openings. Use near-clearance and far-depth cases from Q03. Keep wind off for the
initial composition, then pass supported real trees to HX04.

The stated aircraft samples, including their geometry, all stay in front of
the distant prism. Verify that bound independently. If the chosen physical/view
coverage later lets an aircraft pass behind a photographed hard edge, that edge
needs a measured visual proxy and additional front/behind Q03 cases. Passing
local tree/box cases alone does not establish photographic distant occlusion.

**Evidence and decision.** Apply Q01/Q03 synthetic projection and visibility
oracles, Q04 independent color and Q02's distinction between background softness
and wrong aircraft visibility. No duplicate trunk/crown, wrongly hidden aircraft
or unexplained collider is acceptable. Record asset/ground scale and local/photo
edge crops. A tree that is detailed in isolation but mismatched in color or size
is not an improvement. If the photo/3D composition fails, change that interface
before adding more species or importing an entire forest package.

**Output.** One versioned fixture manifest, matched reference/candidate captures,
object/visibility masks, camera table, measured defects and a decision to retain,
revise or reject this fixed hybrid. This closes only its synthetic subset, not
real-field calibration, lifecycle, hardware or export acceptance.

## HX02 — clean replacement and revealed background

**Variants.** Use the known synthetic scene to render a photographed tree, then
compare: original capture with that tree; a deliberately bad overlay retaining
both trees; cleaned background with the same real 3D tree replacing it. The bad
overlay is a diagnostic negative control, never a shippable option. Keep physical
inventory stable and do not score a missing obstacle as a visual improvement.

**Stimulus.** Compare the full original silhouette, holes through the crown,
trunk/ground junction and photographed shadow. If wind is admitted, include both
extremes of the source-specific motion envelope, pause/reset and resumed motion.
Inspect the horizontal panorama seam and final mip levels if cleanup crosses it.
Use only the fixed eye here; translated-view inspection belongs to HX06.

**Evidence and decision.** Retain original/clean derivative hashes, repair masks,
source references, artist decisions and an unchanged measured-object identity.
The known clean render is the visibility/reveal oracle. No fragment of the old
trunk/crown or incompatible old shadow may reappear in the admitted views/motion.
Compare the repair at actual zoom; an acceptable thumbnail is insufficient.
For real photography, unseen content is explicitly an authored approximation;
additional photographs improve that evidence but do not replace survey data.

If cleanup cannot be made credible, keep the object photographic with a qualified
proxy, choose a different addition/location during authoring, or select a more
suitable field. Do not obscure the defect with unmeasured foliage or claim that
image inpainting reconstructed a physical scene. A later moving-camera route
requires additional geometry and hidden-surface evidence regardless of this result.

## HX03 — ground, light, shadows and reflections

**Variants.** Compare the same bounded ground shape with (A) captured-appearance
photo projection and (B) the existing lit ground/material path with an authored
transition. Begin with fixed exposure and a known sun/reference. A separate
visible/radiance sky is a second, isolated lighting comparison only if the simple
path fails. Do not change ground material, exposure, sky and foliage filtering
together and then attribute a win to one technique.

**Stimulus.** Inspect the patch boundary in all admitted headings/zooms; cross
it with the aircraft's projected shadow. Exercise each requested shadow setting
from C04 and the effective fallback explanation. Place a real tree so its shadow
is entirely on a qualified real patch first, then explicitly test the boundary
case before admitting it. Check a photographed shaded area, real tree shadow on
the aircraft, and the reverse case of a photo-baked occluder affecting real geometry.
If that last interaction has no qualified solution, exclude it from the first
field's critical corridor and record the limitation.

Use neutral color targets and a matte/rough/glossy diagnostic set to check light
direction, energy, color transform and reflections; also inspect the actual
aircraft material. Keep optional lake reflections outside the first scene.
Check photo-projected geometry from an actual reflection-probe viewpoint before
including it in probe capture. A correct pilot view is not a reflection oracle.
If a probe-specific exclusion/representation is chosen, document and evaluate
the missing-reflection tradeoff instead of calling it physically exact.

**Evidence and decision.** Apply Q04/Q05 limits and the explicit interaction
table in the design. Require one aircraft-ground owner, no double-darkened
static shadow, no gap across the real/photo boundary, and no unintended World
refresh relighting. A native cast-shadow path on photographic ground must be
proved on each admitted renderer; it is not inherited from the projected
aircraft cue. Preserve the player's requested settings. If the patch cannot
conceal the join credibly under the intended fixed capture condition, the first
site stays photographic there or uses a different composition.

## HX04 — foliage detail, wind and batching

**Baseline first.** Keep the adopted maple import and existing LandscapeLab
foliage/bark/wind settings described in the reuse audit. Start with one source
mesh and its genuinely matched current card. The stable old slot name is not
proof of species identity. Do not repeat the rejected L8b atlas unmodified or
call coverage-preserving mipmaps a new invention.

**Stimulus.** Use the same source placement/size/contact identity across tiers,
subpixel camera phases, dark/bright photographic backgrounds, back/front light
and the full practical FOV set. Inspect silhouette coverage and aircraft
visibility through foliage over time, not only net green pixel area. Include
the transition's cast/received shadows; current far cards and the detailed
treeline wrapper do not cast native shadows. Direct factory placement has a
different default. A dither transition may overlap two representations under
one logical tree/physical ID with controlled coverage and shadow contribution.
Where a transition cannot be qualified, keep a fixed admitted
representation for that region instead of fading away the error.

Supported real 3D trees may run the accepted-time wind path. Verify fixed roots,
source-specific maximum displacement, normal-only flutter, pause, reset and
the 1,024-second clock wrap. Unsupported source/material/transform cases retain
the static fallback. No wall-clock `TIME` replacement is introduced. Physical
obstacles and their identity remain unchanged across wind and quality variants.

**Conditional comparisons.** Isolate alpha-scissor threshold, import coverage,
alpha-border handling, LOD and dither as separate changes. Alpha hash and
coverage-preserved alpha-test mips are not automatically a compatible recipe.
Do not require MSAA alpha-to-coverage on Compatibility. If submission/culling is
a measured problem, compare the current factory/batches with individual meshes
or alternative existing cell sizes at the same visible workload. No automatic
selection of smaller cells, more atlases or a new impostor generator follows
from theory alone.

**Evidence and decision.** Q03 controls visibility; Q06 controls physical and
accepted-state consistency; Q11 controls performance. Record temporal defects,
material/import identities and image/texture-memory deltas. Use Q11's paired
differences of run-level p95 GPU times and A/A noise bound, not editor FPS or a
single still. If a difference is below measurement noise, record inconclusive.
Do not trade away a flight-critical silhouette for a marginal timing benefit.

## HX05 — integrated hybrid site and delivery

This case begins only after selecting the composition. It reuses the existing
Q06–Q12 protocol rather than inventing a separate lifecycle or export checklist.

**Data and routes.** Bind the role/placement sidecar to validated source,
derivative and physical identities. Reject a missing clean derivative, unknown
asset, unrepresentable reachable obstacle, unsupported destructible photo object
or invalid transform before activation. Keep fixed-eye and activity admission
at UI and direct route entry; retain separate runway-start/Natural Random
predicates. A new JSON descriptor must not silently relax `openrc-field v1`.

**Normal use.** Exercise Club → selected hybrid → Green → Club, Home/flight,
pause/reset/crash, saved/direct/CLI requests, secondary cameras and cold-start
failure. Retain the prior group's one-owner loading/activation/retirement
contract. Count and inspect surviving sky, material, tree, light, reflection and
shadow resources: no residue or stale writer may cross a site switch. Hybrid
assets participate in the same peak-memory budget and bounded request group.

**Physics.** Use the same accepted input/state fixture across presentation tiers
and renderer choices. Check ordinary and terminal impacts, then the Q06 second
live pass or independent contact/visibility probe **before reset** so reset
cannot hide a wrongly broken obstacle. Check reset and checkpoint restore
separately, including the nondestructible-object policy. A rendering mask or a missing tree
card is not permission to change contacts. Preserve numerical replay's actual
scope; do not invent a visual replay player or claim image identity from it.

**Delivery.** Inventory every actually exported panorama, cleaned derivative,
tree image/mesh, atlas and required notice. Avoid packaging unused masters or
alternative variants merely because they live below `res://`. Q10's source,
physical and export identities and download/installed/peak/resident budgets
remain applicable. Existing textures reused by another field may reduce package
delta; they do not automatically remove scene residency or loading cost.
Run the resulting offline archive on its actual admitted target under the
existing desktop/native gates, including missing/corrupt-resource recovery.

**Perceptual decision.** After hard correctness and platform gates pass, propose
a small, explicitly limited review with at least three RC pilots. Randomize the
labels/order of matched A/B clips and identical live tasks; record integration,
depth/readability and landing confidence separately. Prefer the hybrid only if
at least two prefer it and no unresolved critical visibility/grounding defect
remains. This is a proposed small-panel decision rule, not statistical proof of
all users' preference. If only developers review it, report developer review,
not independent pilot validation. Re-estimate production effort from the actual
capture, cleanup and qualification work before expanding to more fields.

## HX06 — moving hybrid and bounded parallax

**Admission.** This is SC-PHOTO-11 work after the selected moving-view need and
physical representation are approved. Build an ordinary mesh reference with
actual local ground/trees/props first. Compare a hybrid retaining that geometry
while replacing only the demonstrably distant content with a photo/sky. An
existing Godot forest controller or a photo-site catalog entry does not admit
FPV, chase, head translation or new vehicle routes in OpenRC.

**Stimulus.** Define an explicit camera-position volume, actual FOVs, travel
speeds, height range and supported output/upscale settings. Use the full view
projection and independently known distant depths to compare reference and
candidate at the volume corners, seams, occluder edges and newly exposed
surfaces. Keep physical coverage separately defined. The 25 cm/2-pixel
[analytical example](hybrid-scenery.md#why-there-is-no-universal-nearfar-radius)
is planning evidence only; do not treat its depth table as a renderer pass.

**Decision.** If distant parallax or disocclusion remains visible in task views,
move that region into real geometry, obtain additional view information, reduce
the explicitly offered camera volume, or reject the photographic representation.
Do not silently restrict existing camera laws or stretch one photo over missing
surfaces. Ordinary meshes remain the baseline before Terrain3D or a special
distant pass is considered. VR/stereo depth-warp experiments stay separately
scoped under SC-PHOTO-13, with their own rights and eye-specific visibility proof.

## Deliverables of a successful implementation phase

Keep evidence under the existing SC-PHOTO owning step, with a small index mapping
HX case, Q case, source commit, scene/data identities and receipt paths. Preserve
large capture masters outside normal Git history according to the existing
asset/evidence workflow. A reviewable first result contains:

- One rights-cleared, fixed-eye field with an explicit camera/physical envelope
  and a documented choice between photographic and hybrid presentation.
- A contributor recipe covering representation roles, clean derivatives,
  existing-asset placement, lighting/shadows and generated output provenance.
- Matched before/after visual evidence and the actual platform/memory/package
  results, including rejected variants and unresolved limitations.
- Normal-use, recovery, contact and offline-package proof for the selected
  configuration; other platforms and moving-camera modes remain conditional.

These deliverables belong to future implementation. This branch currently
delivers the source-backed design, reuse audit, comparison procedures, search
record and a reproducible parallax calculation.
