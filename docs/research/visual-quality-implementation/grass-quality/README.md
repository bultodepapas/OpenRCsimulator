# Grass quality implementation

2026-10-17. Owner: landscape L, coordinated with VQ and RCV. Implemented as an opt-in preview; verification results and unresolved gates are separated below. The [plan](../../../plans/grass-quality.md) owns remaining acceptance; the [44 investigations](../../grass-quality-2026-10-17.md) own external references. This report owns the experiment decisions below.

Set `OPENRC_GRASS_QUALITY=enhanced` before launching to preview the combined change. Otherwise, including unknown selector values, the original ground binding, static imported materials and original allocation remain selected. [Launch and tool commands](../../../../tools/grass/README.md#enhanced-grass-preview).

## Frozen comparison

Baseline: `9e721d479ab14f2d2da614f305012241004576c7`. Separate imported worktrees prevent unrelated work in the shared checkout from changing a comparison. Native renderer: Godot `4.7.2.stable.official.ed1daf0bf`, Windows, OpenGL Compatibility, RTX 3090, NVIDIA 617.42, 1280×720, 4× MSAA. This driver differs from the historical L9e evidence; old timing results are not reused.

`quality_capture.gd` builds the production field with high scenery and freezes node processing. Camera, lighting, wind and wrapped simulation clock are explicit. Images cover the pilot edge, a 0.55 m low view, overhead, zoom and a 12-step, 3 m camera traverse. These are renderer fixtures, not complete flight or driving sessions. GPU work runs serially. Headless checks establish resource/code contracts only.

## Decisions and implementation

| Step | Finding / disposition |
| --- | --- |
| VQ-02a | The three grass sources are opaque, double-sided, per-pixel Burley/Schlick-GGX materials with the same retained palette texture. Import→static→adapter properties agree. Source glTF contains nonwhite vertex colors, but the effective imported material disables them. Preserve that effective setting; enabling it would change the baseline. |
| VQ-02a filtering | The imported palette atlas has no mip chain despite the source sampler requesting mip filtering. It is a narrow color-ramp atlas, not a detailed blade photograph. No import setting is changed without a reproduced sampling defect and an edge-bleed comparison. The retained photographic grass maps already have mipmaps. |
| L9e-R1 | Reject the three-band Laplacian candidate after visual screening. It preserves disabled-detail and aerial pixels exactly, but gives no clear improvement to the needle-like close texture. It requires eight source-level filtered fetches instead of two. No runtime timing or performance benefit is claimed for the rejected candidate. |
| L9e-R2 | Candidate: reuse retained ambientCG Grass001 albedo/normal/roughness at the existing 1.4 m scale in shared ground. A separate grass binder enables grass without enabling RC soil. The RC binder and track coverage retain their existing route. The photograph gives more convincing close turf than the procedural blade pattern. |
| L15c | Candidate: a grass-only material adapter and opaque vertex shader. Source geometry, UVs, scalar PBR settings, vertex-color enablement and source texture are retained. Root-weighted bending follows existing world-space render wind. Trees, flowers and the scenery-off fallback keep their existing paths. |
| L11a-R1 | Preview allocation: short/tall/wispy = 100/30/20 at high, 50/16/10 at balanced and 25/8/5 at low. The high tier keeps 150 clumps and three batches, reducing source triangles from 49,579 to 37,720 (23.92%). Source rows, yaw, height range, nested subsets and exclusions are retained. The pilot-edge comparison preserves the visible foreground silhouettes. No additional habitat noise, ordering or mesh authoring is justified by this comparison. |
| L11a-R2 | No batch partition or geometric fade added. The wind displacement margin is included explicitly. The bounded comparison did not identify a new culling defect; broader range/FOV and driving qualification remains open rather than being inferred from these captures. |

The rejected Laplacian experiment retains its [patch](evidence/laplacian-rejected.patch), [five-pose comparison](evidence/laplacian-comparison.json), and close views for the [current blend](evidence/raw/laplacian/baseline/close_detail-on.png) and [candidate](evidence/raw/laplacian/candidate/close_detail-on.png). Pixel error quantifies change, not visual quality; rejection is the visual/cost decision above.

Ground detail remains in the existing ground pass. The photographic weight attenuates the older turf detail and fades with distance/pixel footprint; it does not stack full-strength normals. Dirt requires both `rc_surface_enabled` and `rc_track_surface`. Every scene owns its material; the immutable imported textures are shared. No new textures or meshes are generated or downloaded by this slice.

Wind uses `sim_clock`, not wall time. Both frequencies are integer multiples of 1/1024 Hz. Roots at the source bounds' base remain fixed; squared relative height increases bending toward tips. Horizontal displacement is capped at 12% of plant height (at most 3 cm for a 25 cm clump), including gust and flutter. The inverse-transpose of the bending shear adjusts normals. Each batch expands its cull margin by its maximum displacement. There is no per-frame CPU plant loop, collider, transparent pass or grass shadow casting.

## Material and motion evidence

The native fixture contains all three species, four yaw rotations and two supported uniform heights, translated to distinct positions: 24 plants in three source batches. It tests front light, back light, a shadow-casting occluder and a warm local light.

- Source versus adapted material with zero wind: **exact pixels in all four lighting cases**.
- Calm at times 0 and 1, wind time 0 repeated, and time 0 versus wrapped time 1024: **exact pixels in all four cases**.
- Nonzero wind changes the silhouette over time and reverses direction with reversed wind. A sample 1 ms before wrap changes only 142–154 pixels of 921,600; this is a near-boundary sample, not a proof of every animated frame.
- An earlier candidate explicitly flipped `NORMAL` for back faces and failed source parity. That extra flip was removed. The final result is established for the pinned engine and these source materials, not asserted as a universal shader rule.

Root darkening was not adopted. No emission, universal upward-normal replacement, vertex-color importer change, new alpha technique or mesh replacement is bundled with the wind change.

## Field controls

[Final baseline, low view](evidence/raw/field/final-baseline/low_near_grass.png) · [Final enhanced, same view](evidence/raw/field/final-enhanced/low_near_grass.png) · [Enhanced pilot edge](evidence/raw/field/final-enhanced/pilot_runway_edge.png). The earlier [photographic detail probe](evidence/photo-probe.png) isolates the ground experiment before species reallocation.

The default-mode control retains identical mesh and instance hashes. Of 58 matched images, 53 are pixel-identical; the other five moving frames differ in only 1–3 pixels, by one 8-bit channel level at most. This is a bounded numerical difference, not a claim of universal byte identity. All repeat/wrap controls are exact within each run.

Before reallocating species, grass-only binding versus the existing RC photographic probe produces exact pixels in all four fixed daytime views. This isolates the new grass binder from changes to clump allocation. The final baseline/enhanced midnight fixtures match in all 58 images. Midnight does not exercise lit grass detail; the local-light material fixture supplies the separate lighting control.

The complete-field draw/primitive counters match in the four fixed views even though MultiMesh instance allocation changes. These engine counters are retained separately from the expanded source-triangle sum; their equality is not evidence of equal instanced geometry work or a GPU speedup.

Native full-session attempt: 10 s warmup, 60 s measured, 3,594 frames; p95 17.321 ms and p99 18.342 ms. **Ineligible:** simulation paused for about 30 s after focus loss, with simulation/wall ratio 0.5008. The collection is valid, but its pacing result is not an active-flight performance pass. Focus safety was not disabled. This is the reason default adoption remains blocked by qualification, not evidence that the new grass exceeds its budget.

## Five-pair render measurement

Five serial, alternating baseline/enhanced pairs each completed 10 s warmup and at least 60 s measurement. All paired camera, engine, field, wind and clock inputs match. The high tier uses the fixed low view at 720p with uncapped offscreen rendering; this is not the 60 Hz full-session gate. Windows power plan: Balanced; NVIDIA power limit: 350 W. No other Godot process was admitted during this campaign.

| Pair | Baseline wall p95, ms | Enhanced wall p95, ms | Wall p95 delta, ms | Viewport GPU p95 delta, ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 2.257 | 1.963 | -0.294 | -0.169 |
| 2 | 1.839 | 2.061 | +0.222 | +0.099 |
| 3 | 2.104 | 1.987 | -0.117 | -0.045 |
| 4 | 1.751 | 1.778 | +0.027 | +0.033 |
| 5 | 1.803 | 2.180 | +0.377 | +0.202 |

Median paired wall-p95 change: **+0.027 ms**; worst pair: **+0.377 ms**. Median GPU-p95 change: **+0.033 ms**. These measurements do not establish a speedup, other hardware performance, or the combined budget of concurrently developed scenery features. [Reduction](evidence/profile-comparison.json), [raw records and hashes](evidence/retained-artifacts.json). All eight grass-owned runtime files in the integrated checkout match the frozen, profiled candidate [byte for byte](evidence/runtime-identities.json).

## Integration verification

The native integration import and load check loaded **989 GDScripts** without null resources or engine errors. Eleven related test scripts passed: imported near grass (59 checks), wind adapter (167), grass ground binding (38), procedural fallback (38), mask bounds (23), RC material, imported vegetation, terrain (21), ground surfaces, shader clock (7), and flight logging/replay (3,247). This is a targeted verification set, not a claim that the entire `app/test.sh` suite ran. [Retained logs](evidence/raw/checks/parse-all.log).

The final native material fixture passes all source/calm/repeat/wrap controls under four lighting arrangements. Its 36 PNGs, manifest and [machine-readable result](evidence/material-final-comparison.json) are retained under [material evidence](evidence/raw/material/manifest.json). World-direction/root/displacement contracts are checked separately in the adapter tests; a changed image alone would not prove them.

The integrated field contract also passes in independent native processes: two default runs with two images each, and two enhanced runs with seven images each. Each pair has byte-identical images and manifests. Enhanced grass visibility adds three draws and 1,103 reported primitives; its 891 changed pixels stay inside the projected grass footprint. Wind changes 410 pixels between t=0 and t=1, all inside that footprint. Calm, post-probe calm repeat and the 1024 s wrap are exact. [Field contract result](evidence/field-contract-final.json); complete images/manifests are retained under `evidence/raw/field-contract/`.

That field harness now uses a v3 capture contract: 12 warmup frames with grass visible, three settled frames per pose, camera interpolation off, and private grass clock/wind inputs while global inputs remain zero. Source material identity is checked before replacing only the two global uniform declarations in capture-owned shader copies. An earlier test mixed in other scenery animation and exposed a separate 601-pixel horizon difference in its first capture. The visible-grass warmup removed that initial difference; its internal GPU mechanism was not established. The production wind shader and the independently timed fixture were not changed by this harness correction. The isolated material fixture above separately verifies the actual production global-uniform path.

Stik and P-51 each produce **721 identical trace samples over 3 seconds** between frozen baseline and enhanced snapshots. The comparison excludes only the creation timestamp; remaining metadata and rows match. [Trace result](evidence/state-trace-comparison.json). This is numerical invariance for those scripted trim scenarios, not physical validation or a substitute for an interactive recorded-flight comparison.

The existing placement generator initially failed its exact-byte check on Windows because Git had converted its final LF to CRLF. A narrow `.gitattributes` rule now preserves LF; regeneration used `tools/grass/place.py`. The row digest remains `5d5345f1fdf447a9e77e2a53112556e9ae888751694a63aeb92782d1a5b2ee34`: no placement changed. Generator checks and all five placement tests pass locally and in a fresh local clone with `core.autocrlf=true` and the new attributes applied before checkout.

The [default comparison](evidence/default-comparison.json), [enhanced comparison](evidence/enhanced-comparison.json) and [night comparison](evidence/night-comparison.json) retain every frame's metrics and identity. Four fixed-view PNGs per run are retained here; remaining traverse PNGs remain in local `tmp/grass-quality/final-*`. Compressed manifests and all ten raw timing records preserve their original bytes. The [artifact inventory](evidence/retained-artifacts.json) records hashes and decompression instructions; missing traverse PNGs must be recaptured before rerunning a complete image reduction on another machine.

## Reproduction and limits

Use the same external capture script with `--path` pointing to each imported app snapshot. Output directories must be new. Inspect engine logs as well as exit status.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path <app-snapshot> --audio-driver Dummy `
  --script "$PWD/tools/grass/quality_capture.gd" -- --mode=capture --out=<new-absolute-directory>
& .tools/Godot_v4.7.2-stable_win64_console.exe --path <candidate-app> --audio-driver Dummy `
  --script "$PWD/tools/grass/material_capture.gd" -- --out=<new-absolute-directory>
python tools/grass/material_compare.py <new-absolute-directory>/manifest.json --out <new-report.json>
```

`--ground=photo` is an explicit research probe using the existing RC binder; it is not the production grass-only binding. Add `--night` for the matched midnight fixture. `--mode=profile --variant=baseline|candidate --pair=1..5` uses 10 s warmup and 60 s measured wall time. Profiles exercise nonzero wind with a recorded clock protocol and contain no image readback during measurement. Wall interval, viewport CPU and viewport GPU metrics remain separate; unsupported zero GPU readings are unavailable.

The complete-session p95/p99 and simulation/wall-ratio gates, owner flight/readability review, both RC vehicles in actual sessions, packaging/lifecycle soak and lower-end/other-OS GPU acceptance are independent gates. Offscreen screenshots and render timings cannot close them. No physics or handling calibration is inferred from animation.
