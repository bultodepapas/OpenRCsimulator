# Intel render internals: sixteen follow-up investigations

Date: 22 November 2026. Owner: VQ-07h-A2-R1 / PT1h-R15 / GOD-12/13.
Reviewed source: `81b48307c36323ac007a282183db63da81433764` on
`investigate/intel-gpu-performance-2026-11-22`. Engine: the repository's
Godot 4.8-beta2, `cafc17a19`.

This extends the [Intel investigation](2026-11-22-intel-gpu-investigation.md)
with sixteen code-linked research questions, primary-source searches and an
audit of the pinned OpenGL engine. The [research ledger](2026-11-22-intel-render-internals.json)
records queries, references, source identities, existing guards and falsifiers.
**These are source-confirmed mechanisms and proposed experiments, not measured
performance improvements.** No runtime, graphics preset, driver or host setting
is changed by this follow-up. All proposed device experiments use the existing
Intel installation and the [same-hardware protocol](2026-11-22-intel-gpu-experiments.md).

**Priority correction after adversarial review:** the [current-main audit](2026-11-22-intel-plan-adversarial-audit.md)
and [low-end execution plan](../../plans/low-end-gpu-performance.md) supersede
this report's original mechanism-first ranking. Existing scale/effective-state
checks and ground-heavy Home attribution come first; loading runs as a separate
workstream. R01–R16 remain source-backed hypotheses, selected only when active
and material to the measured view. The retained ledger describes the original
research, not a measured ranking or sixteen mandatory implementation tasks.

## Engineering assessment

There is useful software work left to investigate before assigning the remaining
cost to the UHD 630 itself. A significant source finding is that the selected root
viewport's settings do not describe every render target: the animated windsock
can request a separate 512×512 mask while its receiver is offscreen, and the
aircraft silhouette has its own 256×256 target with a default of 4× MSAA. A Low
scene also retains the default field's distant tree cards in broad batches.
These mechanisms can matter during ordinary flight, unlike optional lighting
skin composition or a first-use cloud bake. Their source visibility does not
establish their contribution or priority above pixel/ground attribution.

| Corrected placement | Source-confirmed mechanism | Scope and principal uncertainty |
| --- | --- | --- |
| Conditional L4.1: R01 | A changed windsock pose/clock can schedule `UPDATE_ONCE` without a receiver-frustum test. | Requires an active projected cue and visible source; actual GPU executions and cost need capture. |
| Conditional L4.2: R03 | Low retains tree cards in at most eight sector batches, merging near and far bounds. | A visible batch submits its instances; wasted work depends on the camera and finer batches add draws. |
| L2 material attribution before L4.6: R04, R06 | Ground shaders contain uniform anchor arithmetic and six photo-detail sampling expressions. | Existing distance/footprint guards and Mesa compiler optimization reduce the possible saving; R05's loop has only two rectangles in the default field. |
| Conditional L4.1: R02 | Aircraft shadow MSAA is independent of the root viewport. | Changing it risks thin-wing silhouettes and motion shimmer; four samples do not imply four fragment shader executions. |
| Parallel L3 attribution: R13–R15 | Some GPU data is copied back before CPU work, and first Home construction has a synchronous phase. | These can explain stalls, not automatically sustained flight FPS. Caches already avoid repeated work. |
| Conditional L4.5: R11–R12 | Changing controls rebuild static HUD draw commands; invisible afterimages still prepare arrays. | Likely smaller CPU opportunities; instrumentation must establish whether they matter. |

The earlier Proxmox/driver conclusion is unchanged: retained evidence identifies
hardware rendering on the Intel device and specific environment problems, but
does not establish defective hardware. This audit adds application and engine
mechanisms; it does not retroactively attribute an old frame-time spike to one
of them. The historical M1 runs remain unmatched comparisons, as explained in
the parent investigation. No cross-device experiment is needed for this work.

## Sixteen investigations

### R01. Avoid scheduling an invisible windsock shadow

**Question and sources:** Can a render-to-texture update survive ordinary camera
culling? Godot's [SubViewport update modes][S01] distinguish requested updates
from texture-use-driven updates. The pinned
[viewport scheduler][G10] explicitly marks an active, valid, sufficiently sized
non-XR `UPDATE_ONCE` viewport visible without consulting `render_target_was_used`.

**Code:** [Field projectors](../../../app/render/field_projected_shadows.gd)
choose 512² for moving socks and explicitly disable their MSAA.
[Windsock refresh](../../../app/render/windsock_projected_shadow.gd) invalidates
the signature when its accepted clock, deformation or bounds change.
[Projected refresh](../../../app/render/projected_shadow.gd) checks source/tree
visibility and schedules `UPDATE_ONCE`; it has no receiver-frustum check.
The [shadow field policy](../../../app/render/shadow_field_policy.gd) still
controls whether the cue is shown. Near-zero inflation suppresses clock-only
flutter, frozen poses reuse the mask, and Off/Native/night can release targets.

**Candidate:** Keep the latest accepted pose but defer a mask update while its
receiver is outside every relevant view. Redraw before the first visible use.
Test the receiver footprint, not just the sock: an offscreen caster can cast an
onscreen shadow. Preserve low-sun extent, camera cuts, zoom, multiple consumers,
pause and replay. Compare request counts, actual render activity and frame time;
`redraw_count` currently counts requests, not observed GPU completions. Reject
the change if it cannot save work or causes a stale first-visible shadow.

### R02. Treat aircraft shadow antialiasing as a separate budget

**Question and sources:** Does turning off the main viewport's MSAA cover auxiliary
targets? [Viewport documentation][S02] describes independently rendered targets;
the decisive settings are in the application.

**Code:** [Aircraft shadow installation](../../../app/render/shadow.gd) calls
`Projected.setup(model, shape)` without overriding antialiasing.
[That setup](../../../app/render/projected_shadow.gd) defaults to 256² and
`MSAA_4X`. This applies only when an enabled cue installs a nonempty shape;
cue-off defers binding and empty shapes retain the legacy fallback. Pose and
part-signature caches already skip unchanged masks. The qualified
[aircraft proxy](../../../app/render/aircraft_shadow_proxy.gd) is also existing
work, not a new proposal. The receiver performs a separate
[13-tap softening operation](../../../app/render/projected_shadow_receiver.gdshader).

**Candidate:** Isolate 4×, 2× and disabled MSAA on this target while keeping the
main view unchanged. Compare moving silhouettes, thin wings, propeller/gear
poses, low-angle sun, zoom and the pilot's height cue. Do not assume the receiver
blur makes sample coverage irrelevant. Record allocation and GPU-time changes;
pixel count × samples is not a measured memory total or shader-work multiplier.
Only a repeatable saving with acceptable imagery justifies a profile control.

### R03. Give tree instancing a useful spatial granularity

**Question and sources:** When does a larger batch defeat culling? Godot's
[MultiMesh guidance][S03] states that visibility is decided for the whole batch,
with no individual-instance frustum culling.

**Code:** [Treeline construction](../../../app/render/treeline.gd) sorts near and
far cards into eight angular sectors, then merges each nonempty sector into one
MultiMesh with a combined, wind-expanded AABB. The [default field](../../../app/data/fields/default.json) contains 1,680
card positions: 480 at radii up to 600 m and 1,200 beyond. Low and Medium set the
[detailed-tree half angle](../../../app/render/scene_detail.gd) to zero, so these
positions remain cards. This is at most eight nonempty batches, not proof that
every card is drawn from every camera. High-detail field trees already use
[256 m spatial cells](../../../app/render/field_tree_detail.gd).

**Candidate:** Compare the existing sectors with separate near/far sectors or a
bounded grid, preserving placements, material, wind bounds and collision
selection. Measure visible/submitted instances, draw calls, CPU culling and GPU
time on identical views. Smaller batches may cost more CPU than they save.
Preserve the `near_instance_count` prefix used by
[horizon captures](../../../tools/terrain/capture_horizon.gd) and
[treeline tests](../../../app/tests/test_treeline.gd), or deliberately update
those consumers in the same change. At exactly 600 m, the CPU near prefix uses
`<= 600`, while the shader's `step(600, radius)` uses far-alpha treatment;
preserve that boundary if moving shader work into group uniforms. Do not remove the far landscape as a proxy
for proving better culling.

### R04. Compute the grass tone anchor once per material state

**Question and sources:** Is invariant fragment work worth moving out of the
shader? Intel's [Gen9 OpenGL guidance][S04] motivates reducing unnecessary
shader work and register pressure; it does not predict Mesa's generated code.

**Code:** [Shared grass colour](../../../app/render/grass_surface.gdshaderinc)
evaluates three noise octaves at uniform `pilot_xz` when `pin != 1.0`.
[Field setup](../../../app/render/field.gd) sets that pilot location per material.
This expression is independent of the fragment, but its branch is already
limited to the pilot pin region. Ground, near grass and the
[lake bank shader](../../../app/render/lake/bank.gdshader) consume this include.

**Candidate:** Precompute a render-only scalar when the pilot location or noise
recipe changes, and supply it consistently to every material copy. First check
the generated/observed shader cost: uniform arithmetic may already be optimized.
CPU float64 evaluation does not guarantee the shader's float32 result. Compare
translated fields, negative coordinates, pin boundaries and all three visual
consumers. Keep this wholly outside simulation state.

A secondary ALU experiment in [the ground shader](../../../app/render/ground.gdshader)
can compare squared distances for nine parcel candidates and take square roots
only for the nearest two. Preserve tie order and border width. The existing
parcel-weight guard and its far-distance band make this lower priority for a
normal pilot view; do not count the source expression reduction as an FPS gain.

### R05. Skip relief rectangles that provably contribute zero

**Question and sources:** Can spatial guards remove analytic shader work without
breaking derivatives? [GLSL 3.30][S05] defines derivative limitations under
nonuniform control flow; [Intel's guidance][S04] supplies a reason to investigate
work reduction, not a guarantee that additional branches are faster.

**Code:** `terrain_amplitude()` in
[ground.gdshader](../../../app/render/ground.gdshader) calls `terrain_rect_mask()`
for each configured surface, up to a capacity of 32. This runs only with relief
enabled, inside its near-distance range (default end 80 m), and with meaningful
distance/footprint weight. The separate surface-colour loop already has union
and per-rectangle bounds checks; that optimization should not be proposed again.
The checked-in default field has only two eligible non-rough rectangles,
runway and rotorpad. This lowers the likely default-path value of the idea;
larger accepted custom layouts are a separate measurement population.

**Candidate:** Add a conservative outside check only where both the relief mask
and its gradient are zero. Retain ordered overlaps, cubic feather, runway and
rotorpad precedence, edge rounding and signed-zero behavior. Keep `fwidth` and
other required derivatives before divergent branches. Compare finite valid
layouts, boundary pixels and rendered normals, then time views with few and
many surfaces. Thirty-two is a maximum, not the default iteration count.
Reject an extra branch if SIMD divergence or instruction overhead erases savings.

### R06. Reduce photo-detail texture accesses with compatible packing

**Question and sources:** Can related texture channels share accesses? Godot's
[GPU optimization discussion][S06] and [image import reference][S07] support
investigating bandwidth and storage, subject to actual formats and filtering.

**Code:** [Ground detail sampling](../../../app/render/rc_ground_detail.gdshaderinc)
contains two `textureGrad` accesses each for albedo, normal and roughness: six
source-level accesses across two UVs. [Default field setup](../../../app/render/field.gd)
configures this material independently of the enhanced near-grass preset.
The [ground fragment](../../../app/render/ground.gdshader) already gates it on
positive photo weight, with distance and footprint fades. Low does not by
itself prove this branch is absent.

**Candidate:** Keep albedo in its correct colour space and consider a linear
texture carrying normal RG plus roughness. This can reduce six sampling
expressions to four on the active path. It is not a promise of one-third less
GPU time: cache behavior, filtering, import compression and register use matter.
An existing two-channel compressed normal may lose precision or compression
efficiency when repacked. Preserve normal reconstruction, UVs, mip generation,
asset provenance and package imports. Compare close grass, oblique views and
the fade band before accepting either image quality or performance.

### R07. Optimize foliage-mask storage without breaking the atlas contract

**Question and sources:** Is every stored texture channel useful? The
[image import reference][S07] distinguishes GPU storage and mip behavior from
source-file size. Integrated-memory bandwidth is a reason to measure this,
not evidence of the current limiting unit.

**Code:** [Treeline shading](../../../app/render/treeline.gdshader) samples the
colour atlas and a same-size foliage mask. The [tree pipeline](../../../tools/trees/README.md)
and [asset checks](../../../app/tests/test_tree_assets.gd) intentionally require
lossless RGBA8 atlas data and matching alpha at every mip. The 1024² inputs are
already mipped. Blindly enabling lossy compression would violate that contract.

**Candidate:** Evaluate an explicit runtime one-channel foliage-mask
representation while preserving the source assets, sampled mask values,
coverage alpha and mip chain. Confirm the shader and import/export contract
first; a base-level conversion alone is insufficient. The nominal channel-byte
reduction is not a measured bandwidth ratio. Price the original RGBA texture's
lifetime and any conversion/readback peak: creating an R8 copy while retaining
the original can increase residency. Reject changes that alter foliage
tint, far alpha compensation, thin branches or the three-card silhouette. This
is separate from R06: it tests storage format rather than combining sampling
operations in the ground material.

### R08. Check whether tree rejection can happen before expensive shading

**Question and sources:** Can invisible leaf-card fragments exit earlier?
[Godot's 3D guidance][S08] explains transparency costs, while [GLSL 3.30][S05]
constrains derivatives after divergent discard.

**Code:** Trees already use instancing and alpha scissor. The custom
[fragment code](../../../app/render/treeline.gdshader) samples both textures and
computes its tint before the engine's discard. In the pinned
[GLES3 scene shader][G08], custom `FRAGMENT` code precedes the generated scissor
test. Its `RENDER_MATERIAL` path treats alpha specially instead of discarding,
so an unconditional custom discard is not automatically equivalent.

**Candidate:** First measure overdraw and inspect the actual generated variant.
An experimental early alpha rejection may skip mask/shading work, provided
required gradients are computed before divergence and every applicable pass
retains its semantics. Compare leaf edges, wind motion, all mips and material
passes. Compiler reordering, depth behavior and SIMD occupancy can make this
slower. Do not present adding alpha scissor as an improvement: it is already on.

### R09. Optimize sky work within the actual Compatibility implementation

**Question and sources:** Do generic sky optimizations apply to this renderer?
[Sky shader documentation][S09] describes reduced-resolution passes, but the
pinned engine determines their availability.

**Code:** [Sky colour encoding](../../../app/render/sky.gdshader) performs a
Compatibility-specific inverse transform with `pow` and three Newton steps.
It covers visible sky pixels; substituting an ordinary sRGB conversion would
change the current appearance. Separately, pinned [GLES3 material parsing][G07]
recognizes half/quarter-resolution flags, but the [GLES3 sky shader][G09] and
[scene renderer][G06] do not schedule those reduced-resolution sky passes.
Parsing a render mode does not prove that the optimization exists in this path.

**Candidates:** Measure a bounded approximation or reduced iteration count
against bright sun, twilight, night, horizon/fog joins and radiance consumers.
Reuse the existing [cloud density-bound variants](../../../app/render/cloud_shader_variants.gd)
only as experiments. They are off by default, and
[earlier strict numerical checks](../desktop-delivery-investigations/DT-MAC-00-R4/README.md)
already rejected some candidates; this is not a newly discovered ready-made win.
[Atmosphere](../../../app/render/atmosphere.gd) already throttles cloud-drift
radiance changes and uses incremental radiance processing. Other appearance
edits can still trigger updates. Keep visible sky work, radiance work and the
bounded cloud cache separate when measuring. Avoid unsupported render-mode tips.

### R10. Coalesce lake reflection refresh only when it cannot be seen

**Question and sources:** Can lighting changes cause secondary scene captures?
The [ReflectionProbe reference][S10] documents refresh-on-transform behavior and
the cost of capturing the environment. Older documentation claiming no
Compatibility probes does not describe this pinned engine: [GLES3 scene
rendering][G06] contains a reflection-probe framebuffer/render path.

**Code:** [Lake construction](../../../app/render/lake/lake_terrain.gd) chooses
`UPDATE_ONCE`; [its updater](../../../app/render/lake/lake_reflection.gd) compares
four water-lighting parameters and nudges the probe on a changed signature.
[World lighting](../../../app/render/world/world.gd) already steps the normal
update at 30 sky seconds (1.5 flight seconds at the ×20 sky rate). This is not
an every-frame cube capture. Explicit sky edits have a refresh path too.

**Candidate:** Count actual probe activity before changing it. If material,
mask and receiver inspection proves no visible consumer needs the result,
coalesce pending refreshes and update before reentry. Preserve other reflective
consumers, moving sun, paused edits and night ambient. Refresh counters alone
do not establish completed captures. The per-frame signature allocation is a
separate CPU hypothesis; `get_shader_parameter()` is not evidence of a GPU
readback. The existing [probe test](../../../app/tests/test_lake_probe_ambient.gd)
checks behavior, not target-GPU performance.

### R11. Separate static transmitter artwork from moving controls

**Question and sources:** What does a custom UI redraw invalidate? Godot's
[custom drawing documentation][S11] explains that drawing commands are cached
until a redraw is requested.

**Code:** The default Pilot [overlay settings](../../../app/render/overlays/overlay_settings.gd)
include the transmitter. [Its renderer](../../../app/render/overlays/transmitter.gd)
already skips identical inputs, but a changed stick redraws the same CanvasItem
containing the static transmitter artwork, rings and moving gimbals. LCD values
have a different useful change rate.

**Candidate:** Keep static artwork and dynamic controls in separate cached
CanvasItems and invalidate LCD drawing on the displayed value. Maintain full
input responsiveness; do not quantize control processing to save drawing.
Measure CPU draw-command rebuild time and resulting draw calls with still,
moving and noisy controls. Preserve trim/mode/model changes, layout resizing,
scaling and image parity. More CanvasItems can introduce their own overhead,
so this is a measured UI experiment rather than an assumed Intel GPU fix.

### R12. Avoid preparing an afterimage that will remain invisible

**Question and sources:** Does hiding an effect eliminate its CPU work? Godot's
[Node processing reference][S12] separates process callbacks from visual
visibility; the actual order is established by application source.

**Code:** [Sun glare](../../../app/render/landscape_upgrade/sun_glare.gd) advances
the accepted afterimage state, then its eye-view path constructs eight patch
records and two packed arrays and calls two shader setters before returning
whether any alpha exceeds 0.002. A rested eye has no active patches according
to [sun optics](../../../app/render/sun/sun_optics.gd). The layer is hidden after
this preparation. Setter calls prove CPU work, not a GPU upload or barrier per
call.

**Candidate:** Decide whether any patch can be visible before allocating and
packing the presentation arrays. Keep state advancement, cloud/skyline
occlusion, recovery and diagnostic metadata; publish the full current payload
before visibility resumes. Verify threshold crossings, sun entering/leaving
view, eyewear, camera modes, pause and replay. Measure CPU/allocation savings
with inactive and active patches. Disabling the whole process would break the
state evolution this optimization must preserve.

### R13. Measure the cloud cache's first-use GPU-to-CPU-to-GPU round trip

**Question and sources:** Does unified memory make texture readback free?
Godot warns about [Texture2D image retrieval][S13]; the [OpenGL specification][S14]
and [pixel-buffer guidance][S15] distinguish ordered access from asynchronous
transfer. Shared physical memory does not remove synchronization or copying.

**Code:** A miss in the bounded [cloud map cache](../../../app/render/cloud_shadow_map.gd)
creates a 2048² HDR 2D SubViewport, requests one render, waits three process
frames, calls `get_image()`, validates 16 seed-specific points, converts to
`FORMAT_RGH`, then creates an ImageTexture. The pinned
[GLES3 texture storage][G05] uses client-memory `glGetTexImage` on its desktop GL
branch, or a `glReadPixels` fallback in the other path. The editor's optional
image cache excludes render targets. Three process frames are not a measured
GPU completion fence.

The final two-channel half-float image is logically **16 MiB per 2048² tile**;
four ready entries would total **64 MiB** without mips. That excludes transient
images, staging, render targets and allocation overhead. Four entries also
include pending/failed states, so 64 MiB is not a claim of constant residency.
Capacity, weak consumers, generation checks, validation, retry limits,
eviction/rebinding and analytic fallback are already implemented. Sky may keep
a tile in use even when ground shadows are off. This is not a per-frame bake.

**Candidates:** Compare validated 1024² and 2048² tiles, or spread owned bake
completions if they coincide. A GPU-resident design with smaller validation
readback is a larger experiment: it must preserve numerical checks, lifetime,
capacity and fallback, and account for the retained render-target footprint.
A PBO followed by an immediate wait is not a solution; a modern RenderingDevice
async-readback API is not a drop-in Compatibility implementation. Measure first
Home/seed change separately from steady flight and include moving cloud imagery;
the existing 16 validation points are not a full-image equivalence proof.

### R14. Account for mesh readback before worker computation

**Question and sources:** Can a worker remove the cost of extracting GPU-backed
mesh data? The [thread-safety guide][S16] warns that GPU interaction can still
synchronize. The pinned implementation supplies a stronger source-level trace:

`ArrayMesh.surface_get_arrays()` → RenderingServer surface extraction →
GLES3 `mesh_get_surface()` → `Utilities::buffer_get_data()` →
`glMapBufferRange(..., GL_MAP_READ_BIT)`, copy, unmap.

The exact implementation is in [mesh resources][G01], [RenderingServer][G02],
[GLES3 mesh storage][G03] and [buffer utilities][G04]. Mapping for a read can
wait for relevant outstanding work under [OpenGL rules][S14]; no duration was
measured here. `Mesh.get_faces()` has a triangle-mesh cache: do not assume every
call repeats extraction.

**Code:** [Home geometry snapshots](../../../app/ui/home_preview_geometry.gd)
perform whole surface reads on main, duplicate arrays, then yield between
surfaces with a 3 ms budget. One indivisible engine read can exceed that budget.
The worker transforms points and expands indices into triangle vertices.
The 96 MiB input accounting covers `12V + 4I`, not every concurrent allocation:
copies, transformed points, engine arrays and `12I` expanded triangle storage
can coexist. This night-layout path is conditional; it is not established as
the cause of the default daytime stall.

**Candidates:** Retain compact derived geometry/layout within the existing
bounded owner, keyed to immutable mesh revision and relevant pose, and examine
indexed processing instead of flattening all triangles. Preserve authored
anchors, material/visibility filters, articulation, triangle-strip fallback,
livery identity, cancellation and cache limits. Count first-use and cache-hit
surface reads, maximum main-thread chunk, peak memory and layout parity. Adding
more workers cannot remove a read that precedes the job.

### R15. Separate resource loading, construction and shader warmup

**Question and sources:** Why can a threaded load still produce a loading stall?
[Background loading][S17] concerns resource acquisition; [pipeline compilation
guidance][S18] distinguishes Compatibility's behavior from modern renderer
precompilation techniques.

**Code:** [Flight loading](../../../app/ui/flight_scene_load.gd) already has an
owned worker and joins after it finishes. [Home resource preparation](../../../app/ui/home_preview_resources.gd)
checks completion before retrieving a resource and maintains a two-resource
LRU. Later [Home selections](../../../app/ui/home_scene.gd) have staged work and
a three-model cache. These should not be reported as missing threading.
However, [first Home startup](../../../app/app_root.gd) completes its background
resource/world stages and then calls `finish_construction()` synchronously.
That path calls `show_aircraft()` and performs model construction before the
first 3D frame, bypassing the later preview broker's phased route.

There is also deliberate [crash shader warmup](../../../app/render/crash/shader_warmup.gd):
on a non-headless Compatibility run it creates an isolated 64² target and calls
`force_draw(false)` twice, without and with the extra Omni fire light; a
directional sun may be present in both passes. Removing it can move the stall
to a crash. Some [Home presentation](../../../app/ui/home_presentation.gd)
geometry scans are specifically for gearless models; do not attribute them to
every tested aircraft.

**Candidate:** Attribute resource acquisition, validation/build, geometry,
texture work, shader warmup and first draw separately before choosing a change.
Stage accepted construction in bounded main-thread phases or reuse compact
derived data with correct invalidation. Keep active nodes/GPU operations on
their supported thread path. Preserve validation, warmup variant coverage,
cancellation and the latest selection. Measure cold and warm entry/selection
separately; a faster warm repeat cannot qualify first Home.

### R16. Reject or reuse lighting-skin image work before expensive extraction

**Question and sources:** Can an input guard or a cache key cause avoidable
image work? [Texture2D][S13] and [ImageTexture][S19] describe retrieval and
allocation; texture updates are only reusable when size, format and mip
configuration match.

**Code:** Optional [lighting-skin composition](../../../app/render/lighting/lighting_skins.gd)
calls `albedo_texture.get_image()` before checking its 2048-pixel input cap.
Its per-rig cache key includes both texture identity and tint, so different
tints can revisit the same source image. Accepted inputs are converted and
sampled in a 512² CPU mask loop, mipped and uploaded. Enabled zones, supported
aircraft/materials, target caps and the composed-texture cache already limit
reachability. This is neither every-frame work nor an established baseline
flight cost. An editor-side image cache can also change the extraction cost.

**Candidate:** Where metadata reliably reports the actual stored dimensions,
reject oversized input before retrieval; account for size overrides first.
Reuse a bounded source-image or tint-independent intermediate within one
configuration operation. Preserve colour/UV semantics, mipmaps, material and
livery isolation, and resource ownership. Do not replace new immutable textures
with updates to a texture another scene still owns. The [ground tile byte
cache](../../../app/render/ground.gd) already deliberately separates CPU data
reuse from per-owner mutable textures. Measure this only with the feature
enabled and representative accepted/oversized sources.

## Experiment order and acceptance

Keep the [existing protocol](2026-11-22-intel-gpu-experiments.md) authoritative
for admission, native backend, effective pixels, raw evidence and paired runs.
The [corrected plan](../../plans/low-end-gpu-performance.md#5-phases-and-subphases)
owns order: L0/L1 effective baseline and pixel response, L2 bounded Simple
ground if attribution supports it, parallel L3 loading, then an active L4
residual candidate. Automatic promotion and scoped integration are L5/L6;
a manual candidate does not wait for every policy refactor or another machine.
Use 1920×1080 output first; record the existing Automatic internal scale and
every auxiliary target explicitly. A new internal optimization should initially
change one cause while holding that baseline constant. Native 1080p internal
qualification remains a separate claim.

The following observations select among residual hypotheses; their row order
is not an execution schedule or a requirement to run all sixteen candidates.

| Residual area | Questions | Minimal discriminating observation | Reject or deprioritize when |
| --- | --- | --- | --- |
| A: inventory | R01–R03, R10 | Root and secondary target sizes/AA, update requests versus actual draws, visible tree batches, actual reflection activity. | The relevant path is inactive in the retained slow phase. |
| B: recurring GPU work | R01, R03, R04, R06; then R02 and R05 | Paired identical-camera runs, CPU/GPU frame time, tail/stutter behavior, draw/instance counts, motion imagery. | Savings are within run noise, another stage worsens, or visual/cue parity fails. |
| C: loading attribution | R13–R15 | Cold and warm phase spans, readback/compilation/build markers, cache-hit identity, maximum main chunk and memory. | A candidate only moves the stall to first visible use or expands residency beyond the budget. |
| D: smaller CPU work | R11–R12 | Allocations and command rebuilding with active versus inactive inputs/effects. | The path is negligible or added scene structure costs more. |
| E: conditional/higher risk | R07–R10, R16 | Feature reachability, source-format/pass checks and focused visual gates before a full tour. | Baseline has no consumer, the pinned renderer lacks support, or coverage/precision contracts fail. |

Use interleaved baseline/candidate repetitions and preserve each raw run, not
just averages. A diagnostic disable can establish a feature's upper-bound cost;
it does not qualify removing that feature. Existing script tests can protect
contracts, but cannot establish image parity, presentation quality or GPU
performance. Keep physics at 240 Hz and animation on the accepted simulation
clock. None of these ideas requires another machine or a different graphics card.

## Research boundaries and rejected shortcuts

- Intel's 2017 Gen9 guide is architecture-relevant, but explicitly does not cover
  Linux driver implementations. Its Windows/D3D thresholds and tooling are not
  Mesa 25.0.7 OpenGL facts. No blanket `mediump`, compiler flag or cache deletion
  is recommended from that document.
- Generic sky half/quarter-resolution advice was checked against the pinned
  GLES3 source and rejected as an available switch in this path. Conversely,
  stale documentation excluding Compatibility reflection probes was not used.
- Instancing, alpha scissor, mipmaps, near-grass Low caps, surface-colour bounds,
  asynchronous resource loading and bounded caches already exist. The default
  field uses [imported near grass](../../../app/scenery/imported_near_grass.gd);
  optimizing an unused procedural fallback would not establish a baseline win.
- No source inspection measures EU utilization, memory bandwidth saturation,
  driver stalls, thermal throttling or the actual contribution of Proxmox.
  Those remain receipt-backed device questions in the parent investigation.

## Verification and review

Two source-read-only specialists independently investigated shader work and
render scheduling/loading. A separate Good Enemy reviewer checked the integrated
findings against source and challenged hidden-path, caching, culling and
measurement claims. The lead checked the material engine paths against
`cafc17a19`; the ledger retains upstream blob identities and application hashes.

Verification for this documentation-only follow-up covers research/source
consistency, calculated card/storage counts, new local links/anchors, JSON
integrity and `git diff --check`. No GDScript, shader, physics or rendered test
was executed by this follow-up. The existing workspace still lacks the pool
configuration needed to contact the Intel test service, and the original raw
GPU campaign remains outside Git. No FPS gain, CI completion or live-hardware
qualification is claimed.

## Primary sources

Accessed 22 November 2026. The ledger records search questions and applicability.
Godot documentation versions are explicit below; implementation-sensitive
conclusions use the pinned source, not an assumption that stable/latest equals
the project binary.

| ID | Primary source | Use and limitation |
| --- | --- | --- |
| S01 | [Godot SubViewport][S01] | Update-mode semantics; paired with the pinned scheduler. |
| S02 | [Godot Viewports][S02] | Independent render targets and camera/layer context. |
| S03 | [Godot MultiMesh optimization][S03] | Whole-batch culling; page carries an update notice, and local source confirms grouping. |
| S04 | [Intel Graphics API Performance Guide 2.5][S04] | Gen9/OpenGL architecture motivation; 2017, no Linux-driver implementation coverage. |
| S05 | [Khronos GLSL 3.30 specification][S05] | Derivatives, divergent control flow and discard. |
| S06 | [Godot 4.3 GPU optimization][S06] | General fragment/bandwidth tradeoffs only; no old backend-specific assertion imported. |
| S07 | [Godot 4.7 image import][S07] | Mipmaps, storage/compression and format tradeoffs. |
| S08 | [Godot 3D optimization][S08] | Visibility, overdraw and transparency concepts. |
| S09 | [Godot 4.7 sky shaders][S09] | Candidate discovery; renderer support checked in pinned GLES3. |
| S10 | [Godot 4.6 ReflectionProbe][S10] | Refresh behavior and Compatibility support; actual activity still requires capture. |
| S11 | [Godot custom 2D drawing][S11] | Draw-command caching and invalidation. |
| S12 | [Godot Node][S12] | Processing lifecycle, separate from visual visibility. |
| S13 | [Godot Texture2D][S13] | Image extraction; actual backend path checked separately. |
| S14 | [Khronos OpenGL 3.3 core specification][S14] | Buffer mapping, ordered resource access and readback semantics. |
| S15 | [Khronos Pixel Buffer Object guidance][S15] | Asynchronous-transfer design limits; search-readable primary wiki page. |
| S16 | [Godot thread-safe APIs][S16] | Scene/resource ownership and GPU synchronization limitations. |
| S17 | [Godot background loading][S17] | Completion polling and retrieval; does not eliminate later construction. |
| S18 | [Godot pipeline compilations][S18] | Compatibility limitations and first-use/warmup distinction. |
| S19 | [Godot ImageTexture][S19] | Allocation versus compatible in-place updates. |

Pinned engine files: [mesh resources][G01], [RenderingServer][G02],
[GLES3 mesh storage][G03], [buffer utilities][G04], [texture storage][G05],
[scene renderer][G06], [material storage][G07], [scene shader][G08],
[sky shader][G09], [viewport scheduler][G10].

[S01]: https://docs.godotengine.org/en/stable/classes/class_subviewport.html
[S02]: https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html
[S03]: https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
[S04]: https://cdrdv2-public.intel.com/671201/graphics-api-performance-guide-2-5.pdf
[S05]: https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.3.30.pdf
[S06]: https://docs.godotengine.org/en/4.3/tutorials/performance/gpu_optimization.html
[S07]: https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html
[S08]: https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html
[S09]: https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html
[S10]: https://docs.godotengine.org/en/4.6/classes/class_reflectionprobe.html
[S11]: https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html
[S12]: https://docs.godotengine.org/en/stable/classes/class_node.html
[S13]: https://docs.godotengine.org/en/stable/classes/class_texture2d.html
[S14]: https://registry.khronos.org/OpenGL/specs/gl/glspec33.core.pdf
[S15]: https://wikis.khronos.org/opengl/Pixel_Buffer_Object
[S16]: https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
[S17]: https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html
[S18]: https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
[S19]: https://docs.godotengine.org/en/stable/classes/class_imagetexture.html
[G01]: https://github.com/godotengine/godot/blob/cafc17a19/scene/resources/mesh.cpp
[G02]: https://github.com/godotengine/godot/blob/cafc17a19/servers/rendering/rendering_server.cpp
[G03]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/storage/mesh_storage.cpp
[G04]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/storage/utilities.cpp
[G05]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/storage/texture_storage.cpp
[G06]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/rasterizer_scene_gles3.cpp
[G07]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/storage/material_storage.cpp
[G08]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/shaders/scene.glsl
[G09]: https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/shaders/sky.glsl
[G10]: https://github.com/godotengine/godot/blob/cafc17a19/servers/rendering/renderer_viewport.cpp
