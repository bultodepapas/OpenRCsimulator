# SUN-10: sun, cloud light and optics source audit

2026-11-15 · Research and design evidence · [Authoritative sun plan](../../../plans/sun.md)

## 1. Scope and identity

| Item | Reviewed identity |
| --- | --- |
| Repository / base | `bultodepapas/OpenRCsimulator`, `main` at `273a7e4c0617fdf4cacc39c360796fd79afa5f2c` |
| Application | 0.2.8, from `app/project.godot` |
| Engine | `4.8.beta2.official.cafc17a19`, from `app/get-godot.sh`; official source `cafc17a192acf67903910a68aeb3c076c0907a4b` |
| Rendering routes | Compatibility by default; `arm64` override selects Mobile; product High uses Forward+ and checks the effective renderer |
| Deliverable | Documentation and research on `docs/sun-atmosphere-realism-20261115` |
| Performed | Pinned source/configuration/test inspection, existing evidence reconciliation, official engine-source/documentation and primary graphics research |
| Not performed | Current build import/run, new screenshots, player flights, target-GPU timing, engine modification, clinical or display calibration |

The repository was inspected through a sparse text checkout. Omitted binary assets do not establish their absence from the product. Graph tools were unavailable; `rg` and current source were used. The [consolidated audit queue](../../../../external%20Audits/CONSOLIDATED-AUDITS.md) and [completed ledger](../../../../external%20Audits/COMPLETED-AUDIT-WORK.md) were consulted before findings were classified.

Source identity is fixed. Later commits on `main` require a focused delta review; this document does not claim to audit them. See [sources](sources.md) for engine applicability and [experiments](experiments.md) for the checks still required.

## 2. Findings and disposition

These are implementation facts and design limitations. A source-derived mismatch identifies a useful experiment; it does not by itself prove that a player has seen an artifact.

### A. Preserve the delivered optics stack

**Implemented.** The sky draws limb darkening, low-sun flattening and an aerosol aureole. `SunGlare` derives its source from the live sky, distinguishes eye/lens views, samples clouds, and uses a skyline fallback. The shader samples the opaque solar disc in nine places. Eye views have a veil and local afterimage; lens views have a smaller veil, aperture spikes and five coloured ghosts.

Evidence: [sky source, lines 140–180](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/sky.gdshader#L140-L180), [source and process, 121–206](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/landscape_upgrade/sun_glare.gd#L121-L206), [depth and lens shader](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/landscape_upgrade/sun_glare.gdshader#L95-L181).

**Disposition:** improve and qualify these components under SUN-11…19. Adding a new flare addon or an unrelated day/night controller would duplicate working ownership. The user's desired temporary loss of model visibility already has a software mechanism; SUN-08 still owns its flight acceptance.

### B. The cloud attenuation model is a visual surrogate

**Code-proven approximation.** Layered sky colours use alpha compositing. Their accumulated opacity proxy becomes the solar attenuation `exp(-8 * (density + cirrus_amount))`. `SkyMirror` reproduces that proxy on the CPU. This is a deliberate coherent approximation, not a volume integral with measured extinction coefficients.

Evidence: [sky layers and solar composition, 215–321](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/sky.gdshader#L215-L321), [CPU mirror, 55–116](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/sun/sky_mirror.gd#L55-L116).

**Disposition:** keep the old optical-model identity as a comparison. SUN-13 should separate coverage, beam transmission and scattered radiance, using an explicitly defined new model. Do not simply rename the old alpha proxy “physical optical depth.” Validate density monotonicity, thin cirrus, partial disc coverage and thick overcast before changing presets.

### C. Sky and ground use different spatial sampling assumptions

**Code-proven boundary; visible impact unmeasured.** The sky samples a layer from `EYEDIR`, altitude/scale and offset, without observer translation. The CPU mirror does the same. Ground shadows intersect a sun ray from `world_pos`. Storm geometry uses world-space centres and selects a periodic copy around the camera.

Evidence: [sky coordinates, 223–227](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/sky.gdshader#L223-L227), [mirror coordinates, 99–100](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/sun/sky_mirror.gd#L99-L100), [ground projection, 313–324](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/ground.gdshader#L313-L324), [bank translation, 116–167](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/weather/storm_bank.gd#L116-L167).

**Disposition:** SUN-11/E1 compares views at the pilot station, translated chase positions and different heights. A world-space candidate must update sky, mirror, stars, shadow receivers and reflections together. Camera-position-driven cubemap invalidation is a material cost, not a free coordinate fix.

### D. Transparent storm lobes are outside glare's current occlusion model

**Code-proven integration gap; visual severity unmeasured.** `storm_bank.gdshader` uses `depth_draw_never` and texture alpha. `SunGlare` reads the angular cloud-deck mirror and opaque screen depth; it does not integrate those separate storm-lobe opacities. Their partial transmission cannot be reconstructed from opaque depth alone.

Evidence: [storm material, 1–36](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/weather/storm_bank.gdshader#L1-L36), [glare cloud inputs, 21–24 and 164–179](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/landscape_upgrade/sun_glare.gd#L164-L179).

**Disposition:** SUN-13/E3 should place the sun behind actual bank lobes and edges. Add a shared opacity/transmission contribution or a documented bounded approximation, with camera/scene identity. A third unrelated density field is not a coherent solution.

### E. Ground cloud shadows cover one selected layer and limited receivers

**Code-proven approximation.** `_shadow_layer_index()` chooses the lowest eligible deck and excludes cirrus/anvil. `_set_profile_shadow_uniforms()` applies that layer to ground and near grass. Their custom light functions attenuate directional illumination. The sky/glare can include up to eight layers, and `light_energy()` uses preset-wide `sun_intensity`, not the aircraft's local cloud sample.

Evidence: [layer selection, 283–298](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/atmosphere.gd#L283-L298), [receiver selection, 655–677](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/atmosphere.gd#L655-L677), [light energy, 529–532](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/atmosphere.gd#L529-L532), [ground direct-light attenuation, 394–397](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/ground.gdshader#L394-L397).

**Disposition:** inventory receivers before claiming scene-wide moving cloud shadows. SUN-15 should compare ground, aircraft, vegetation, buildings and reflections, preserving sky fill and local/emissive lights. Use a consistent direct-light budget; preset dimming plus spatial transmission must not count the same extinction twice. Native directional projectors are absent in the pinned engine; see sources G11.

### F. Dose and visible veil have different geometry information

**Known limit, still present.** The shader veil uses opaque depth; afterimage dose is calculated from clouds and the CPU skyline. A moving aircraft or transparent canopy is not included in that dose visibility. The skyline itself has a fixed per-frame construction allowance and a fallback while incomplete.

Evidence: [dose path and skyline, 174–227](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/landscape_upgrade/sun_glare.gd#L174-L227), [existing SUN-09 limitations](../SUN-02b-06-09/README.md#limits).

**Disposition:** SUN-14 compares render-derived visual proxies and a GPU-resident alternative. Avoid synchronous GPU readback. Retain explicit stale-result/fallback behavior and independent mask evidence. This is not a newly discovered regression in a feature previously claiming dynamic-dose occlusion.

### G. Exact dose integration does not prove moving-sweep frame invariance

**Coverage gap, not a reproduced visual defect.** The dose integrator solves constant-input evolution exactly. Existing multi-rate equivalence tests hold dose/direction constant; the moving sweep uses one sampled sequence. Runtime supplies the current view direction and dose for the elapsed presentation interval.

Evidence: [runtime update, 290–306](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/landscape_upgrade/sun_glare.gd#L290-L306), [test cases, 159–220](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/tests/test_sun_optics.gd#L159-L220).

**Disposition:** E4 samples the same continuous angular trajectory at 30/60/120 fps and during a frame hitch. Compare peak dose, patch locations and recovery curves. Add bounded presentation resampling only if a material discrepancy is demonstrated.

### H. Cloud motion deliberately trades continuity for update cost

**Implemented tradeoff; perceptibility unmeasured here.** `Spec.ATMOSPHERE.cloud_update_s` is 1.0. `CloudTransport` quantizes accepted time; `Atmosphere.update_clouds()` pushes coherent offsets. Atmosphere comments retain historical radiance-refilter cost, and High already uses a realtime 256-pixel sky for flowing worlds.

Evidence: [spec, 52–56](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/spec.gd#L52-L56), [quantized transport, 157–181](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/weather/cloud_transport.gd#L157-L181), [offset publication, 860–871](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/atmosphere.gd#L860-L871), [High sky policy, 131–143](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/high_graphics_profile.gd#L131-L143).

**Disposition:** reuse FW-81-R1 and DT-MAC evidence. Smooth animation is a coordinated sky/shadow/optics/reflection experiment; a shader `TIME` shortcut or unconditional per-frame cubemap update violates existing requirements.

### I. Exposure and post-processing already have owners

**Implemented.** `World.adapt()` advances log exposure with separate light/dark rates and writes `tonemap_exposure` plus the shared exposure signal. `SunGlare` uses that exposure. `LensStack` consumes solar metadata and draws above the SUN afterimage layer. High already configures solar PCSS and four cascades; shadow preferences have their own owner.

Evidence: [World adaptation, 1114–1128](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/world/world.gd#L1114-L1128), [lens integration plan](../../../plans/lens-screen-effects.md#3-what-already-exists-ground-truth-2026-11-12), [High sun](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/high_graphics_profile.gd#L115-L129), [shadow owner](../../../../app/render/shadow_settings.gd).

**Disposition:** an auto-exposure or compositor prototype needs explicit ownership and pass-order handoff. Preserve RC FOV and camera cuts. Do not stack a second exposure loop or independently allocate a new shadow atlas. Source/API support does not establish resulting color or performance.

### J. Legacy disc occlusion depends on the selected presentation path

**Deliberate compatibility behavior.** Classic fixed lighting starts with the historical disc-occlusion setting. TOD snapshots/layered appearance enable it; attached `SunGlare` also forces it on. `World` attaches that node only when the landscape-upgrade option is enabled. Thus a fixed classic world with that option off can retain an unobscured legacy solar disc.

Evidence: [TOD flag](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/time_of_day_lighting.gd#L42), [glare-side mutation](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/landscape_upgrade/sun_glare.gd#L164-L166), [conditional attachment](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/world/world.gd#L434-L446), [legacy test](../../../../app/tests/test_sky_render.gd).

**Disposition:** SUN-11 should make appearance ownership explicit and preserve a legacy reference. The plan proposes moving sky/disc policy to the atmosphere owner; it does not silently redefine historical effects-off pixels.

### K. Controls and evidence are narrower than a complete product feature

**Implemented controls:** `--sun-glare` and `--pilot-eyewear` with environment equivalents. No matching persisted sun/eyewear UI preference was found in the reviewed preferences/UI source. Existing `AFTER_RECOVER_S = 8`, patch count/radius and maximum masking are presentation constants awaiting SUN-08. Historical SUN captures primarily use Godot 4.7.2 Compatibility/llvmpipe and include 720p fixtures.

Evidence: [option parser](../../../../app/render/landscape_upgrade/options.gd), [optics constants](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/render/sun/sun_optics.gd#L67-L95), [historical evidence scope](../SUN-01-05/README.md), [current preference source](../../../../app/app_state/preferences.gd).

**Disposition:** add independent, translated glare/afterimage/flare/eyewear controls through UI ownership, preserve saved overrides and qualify native 1080p on each supported route. A source review cannot certify an attractive image or a comfortable duration.

### L. Baseline tools need explicit case and renderer receipts

**Code-proven evidence limitation.** `capture_landscape_upgrade.gd` records a hard-coded `renderer = "gl_compatibility"`; that report field cannot identify the effective renderer on every route. `glare_contrast.py` requires at least six complete angle rows, while some other fixture checks consider only cases present in the input folder. A four-image single-angle example is insufficient for the current contrast checker's passing contract.

Evidence: [capture metadata, 290–292](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/app/tests/capture_landscape_upgrade.gd#L290-L292), [contrast input/coverage and checks, 76–114](https://github.com/bultodepapas/OpenRCsimulator/blob/273a7e4c0617fdf4cacc39c360796fd79afa5f2c/tools/landscape/glare_contrast.py#L76-L114).

**Disposition:** SUN-10's native baseline needs an independently retained effective-renderer identity, or a small qualified diagnostic repair before cross-renderer reuse. The [command example](experiments.md#2-existing-tools-and-runnable-entry-points) provides six complete angle groups and does not treat the report's current label as runtime proof. No capture-tool code is changed in this documentation delivery.

## 3. Existing work that must remain closed or correctly scoped

| Existing item | Required treatment in this program |
| --- | --- |
| SUN-00…05, -02b, -05b, -06 CLI, -09 | Preserve delivered software and historical evidence. Renew qualification only for changed behavior/current targets. |
| SUN-07 / FW-MOON-08 | The shared source selection is implemented. See [FW-MOON-08 evidence](../../field-world/FW-MOON-08/README.md); thin-cloud/owner/platform gates remain separate. |
| A34 cache seed binding and copied-material publication | Delivered repairs remain delivered. Do not reproduce an obsolete implementation and call it current. |
| A34 seed/capacity permutations | Continue the named current follow-up; pending capacity/reuse states are not new duplicate defect counts. |
| A28 / DT-MAC-06b asynchronous cloud readback | Attribute current load cost before adopting an async API. Preserve validated copied textures, generations, cancellation and analytic fallback. |
| A28 lens-ghost support guard | An offscreen solar source can produce onscreen ghosts. Do not use source-offscreen as a general cull rule. Measure conservative support rejection on native GPUs. |
| SUN-09 / SUN-08 glare-off skyline lead | Existing performance lead; qualify all dependents before skipping work. Zero alpha is not proof of zero CPU/GPU/resource cost. |
| FW-79/80/81-R1/83 and VQ-04b | They retain cloud appearance, light integration, motion, storm geometry and shadow ownership. The SUN plan links their work rather than creating competing tracks. |

## 4. Recommended decisions

Adopt incremental improvement of the existing 2.5D system as the first delivery. Make spatial identity, transmission and view visibility explicit before increasing artistic intensity. Keep ordinary glare and afterimage available on all current rendering paths. Use exact beta 2 API/source evidence rather than assuming an older manual describes every current capability.

Defer replacing the sky with `PhysicalSkyMaterial`, mandatory physical-light-unit migration, a new renderer default, scene-wide engine shadow modification and full volumetric cloud replacement. Each would enlarge scope and can discard valuable calibration. A separate FW-85/SUN-17 experiment can establish whether a more expensive technique is justified.

The lead accepted the independent audit's spatial, transparency, receiver and moving-sweep coverage findings after reading the source. Generic recommendations to add already implemented optics were rejected. Technical source review and independent plan review support the design; neither substitutes for new rendered or hardware evidence.

## 5. Verification of this documentation delivery

This change is confined to Markdown plans, source research, examples and navigation/status links. Delivery checks cover the final diff, referenced repository paths, Markdown fences, and branch/commit publication. Example arithmetic can be checked independently without launching the game. No game test, visual gate, benchmark or pilot-acceptance pass is claimed for this documentation branch.

Pre-publication checks on the initial four-document candidate, delivered as `4e1d79704a5b71865e0817d7f18692edea28d171` (the counts below do not include the later investigation survey):

| Check | Result and scope |
| --- | --- |
| Repository links and anchors | 81 relative repository links and 15 Markdown anchors resolve across the four sun documents and the changed index lines. Sparse-checkout targets were checked against the tracked tree. |
| Pinned source evidence | 30 source permalinks resolve to tracked files at the audited base; referenced line ranges are in bounds. The technical claims were also inspected in source. |
| Formatting and examples | Markdown fences balanced; `git diff --check` clean; the shell example parses. Only its pure case-name construction was evaluated: six historical angles × four controls = 24 unique names. |
| Numerical examples | E1 intersection, E2 transmission/product and forward-lobe sign, and E4 decay/time-constant arithmetic checked independently. This does not execute the proposed renderer. |
| Independent technical review | Complete candidate reviewed; substantive findings resolved, including cirrus preservation, sun/moon shadow ownership, correlated visibility, recovery-trajectory controls and capture-tool evidence limits. |

Publication identifies the final documentation commit on the named branch. Runtime implementation and its CI, native rendering, target-hardware performance and owner flight acceptance remain the separate phase exits above.

## 6. Expanded research survey

The follow-up [28 investigations](investigations.md) cover eight official Godot topics/demos, six sky/cloud repositories, five optics/color repositories and nine rendering-library/production-research/visual-reference questions. Each contains inspected primary evidence, an OpenRC integration analysis, a bounded experiment and an adoption/reference decision. Sixteen external addon/library repositories, the engine and official demos use exact code revisions; paper/manual sources identify their separate retrieval limits.

The survey's [priorities and visual ideas](investigations.md#6-decisions-for-openrc) feed Revision 3 of the sun plan. Source discovery and relevant code/license inspection were completed with independent review; no addon was installed or executed, and no new native image or timing is claimed. The initial code audit remains fixed to its stated application baseline.
