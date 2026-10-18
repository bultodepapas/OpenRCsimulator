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

## 2026-10-18 integration follow-up

The Windows Desktop export preset produced a 165,047,292-byte PCK, SHA-256 `d3021eda0847b19780c948fafdd1803e68493ae4c22cf5902fb1652f3bd00af5`. A headless resource probe mounted it from an otherwise empty project and passed **83 checks**. All three Grass001 maps remain 2048×2048 with mipmaps; eight checked textures match source-project imported decoded data and import artifacts. Both material profiles, all three quality tiers, source geometry, scene-owned material isolation, separate grass/RC bindings and six catalog/license/field identities pass. Three stale glTF UID warnings fell back to text paths; all three meshes loaded with the expected triangle counts. This checks packaged resources, not launching a distributed executable or packaged GPU rendering. [Pack receipt](evidence/pack-2026-10-18/pack-smoke.json).

Pack-probe development exposed two invalid setups: starting the resource-only pack as an application required its external native extension, and raw JPEG decoding was not an appropriate equality reference for imported compressed textures. The final probe mounts resources explicitly and compares imported artifacts/decodes. The initial development logs were not retained; no native packaged-application success is claimed. The successful export and resource-check logs are retained beside the receipt.

The production Home → fixed-wing → Home → Bisonte → Home → Monster Car 2 → Home lifecycle passes with private preferences: **452 checks over two native default cycles**, and **4,502 checks over 20 native enhanced cycles**. The enhanced run records 140 route observations, 568 Home nodes and 3,692 live objects after its first warm cycle, with no subsequent growth. Scene/field weak references expire on exit; mutable ground/grass materials stay private; source meshes and the intended RC dirt surface retain their contracts. The headless default two-cycle check separately passes 448 checks. [Default native report](evidence/raw/lifecycle-2026-10-18/default-native-2/lifecycle.json), [enhanced native report](evidence/raw/lifecycle-2026-10-18/enhanced-native-20/lifecycle.json).

Each native run retains four 1280×720 first-cycle images: Home startup, fixed-wing startup waiting for radio, and both RC vehicles paused. They establish scene framing/material integration, not active flight, driving, moving grass continuity or owner preference. [Enhanced Bisonte](evidence/raw/lifecycle-2026-10-18/enhanced-native-20/rc-mt8-bisonte.png), [enhanced Monster Car 2](evidence/raw/lifecycle-2026-10-18/enhanced-native-20/rc-monster-car-2.png). This bounded sequence does not close the separate Workshop/reset and long-duration DT soak gate. During harness development, the RC track material's presence in the field's lighting-update registry initially looked like shared surface ownership; inspecting active mesh materials corrected that false assertion without changing runtime rendering. The raw successful reports are unchanged; the [tool identity note](evidence/raw/lifecycle-2026-10-18/run-tool-source.txt) records the later wording-only scope clarification.

The seam checker now accepts the imported route and projects its 25–35 m mask about the **pilot**, rather than incorrectly moving the mask center with its offset camera. It retains failed comparisons and refuses to overwrite evidence. The negative control compares an identical reference against a separately darkened copy, so a failing real comparison cannot make that control pass vacuously. Four regression tests cover fixed placement origin, translation invariance, existing evidence preservation and retention of a failed imported comparison with independent controls.

Both retained native imported comparisons fail the unchanged local FLIP p99 limit of 0.1: maximum **0.620415** in default and enhanced modes. Their maximum local channel change is **1.698776%**, within the 3% limit; 20 default cells and 14 enhanced cells fail FLIP. The identical-image control passes, and the copied 202-pixel dark seam is rejected (12.147827% maximum channel change). [Default result](evidence/raw/seam-2026-10-18/seam-default.json), [enhanced result](evidence/raw/seam-2026-10-18/seam-enhanced.json).

This is a static grass-hidden/visible comparison: visible clump silhouettes and FLIP's spatial filtering contribute to the score. It does not by itself establish a moving boundary pop or attribute a defect to the new shader. Keep the seam gate open; reproduce the boundary in motion and isolate silhouette coverage before choosing a geometric fade. No threshold was relaxed and no runtime geometry was hidden to force a pass. The reduction used Windows CPython 3.11.9, NumPy 2.4.6, Pillow 12.3.0 and an isolated FLIP evaluator 1.7 wheel (SHA-256 `12ccbc9e91eed9b0e6422dddcfaa2836a0b0edac1bbc241d9058742188af88c5`); it is not the separate Linux visual environment pinned by `requirements-visual.txt`.

The new native-session runner requires five alternating pairs and passes **15 focused Python tests**. It uses the existing native reducer's collection, duration, active-simulation and pacing policy, retains eligible pacing misses, and stops on invalid runs or provenance changes. A bounded pre-launch process inventory prevents knowingly starting beside another Godot instance. It does not disable focus protection or automate inputs. Existing frame-time metadata verifies the live-input route and camera/render settings but omits effective grass/scenery selection; those settings remain requested intent in the campaign record.

A frozen local app snapshot matched all **1,028 runtime source/config/asset files**, including native libraries and glTF buffers. Its fresh headless import completed without errors or runtime-source changes; identities for 444 imported artifacts are retained separately. On this host (RTX 3090, driver 617.42, Balanced power plan, 350 W GPU limit), the new campaign stopped **before its first launch** because unrelated Godot PID 12796 was already running. No flight timing or completed pair was collected, and that process was not terminated. The earlier focus-paused attempt remains ineligible; full-session performance acceptance is still open. [Campaign and snapshot receipts](evidence/followup-artifacts-2026-10-18.json).

## 2026-10-18 audit and optimization

The imported layout now caches deterministic per-species rank indices and stops accepting rows when each quota is filled. It retains 6,000 packed 64-bit keys (48,000 payload bytes, plus container overhead), not scene objects or placement dictionaries. Field coordinates and exclusion masks are reevaluated for each call. Row count, seed and species signature invalidate the ranking cache. The source geometry, species quotas, selected rows, result order and transform inputs stay unchanged. The audit found no reproduced defect in fixed roots, wind direction, normal correction, phase encoding or bend-expanded culling bounds. The adapter's staged private mesh copy remains: removing its atomic-failure protection was not justified by a measured benefit.

The independent old-algorithm comparison passes **92 checks**, including both profiles, all three tiers, translated/narrow fields, mask edges, an irrelevant distant mask and cache reconstruction. The existing imported-grass and wind checks also pass (59 and 167). [Parity receipt](evidence/raw/audit-2026-10-18/layout/parity.json).

An isolated headless CPU run used nine alternating old/new measurements per case after warmup. These are **layout-selection times**, not full loading times or frame-rate gains:

| High-tier case | Default old → new median, ms | Enhanced old → new median, ms |
| --- | ---: | ---: |
| Open field | 53.116 → 0.955 | 49.721 → 0.887 |
| Narrow rough field | 44.994 → 1.014 | 44.486 → 0.899 |
| Nearby exclusion mask | 51.392 → 1.055 | 50.241 → 1.022 |

The first open-field call, including rank-cache construction with already loaded source rows/assets, took 6.353 ms default and 5.093 ms enhanced. [Default log](evidence/raw/audit-2026-10-18/layout/initial-quiet-default.log), [enhanced log](evidence/raw/audit-2026-10-18/layout/initial-quiet-enhanced.log). That producer printed medians but did not retain individual samples; the updated benchmark now records raw microsecond arrays, source/tool hashes and rejects unknown options. Earlier timings collected alongside image captures are not used here.

The new scene observer lives in `app/render/grass_scene_snapshot.gd`, separate from the frame collector. It inspects active material bindings, shader defaults, texture paths, actual MultiMesh allocations and scenery quality **once after collection**. Hidden nodes and reduced `visible_instance_count` reject qualification. It does not measure frustum visibility or GPU submission. The profile runner requires the expected actual default/enhanced routes and hashes both the Windows console launcher and its sibling engine executable before/after the campaign. The complete grass Python suite passes **44 tests**; frame-collector/scene-observation checks pass **64**. [Check logs](evidence/raw/audit-2026-10-18/inventory.json).

Native moving-boundary diagnosis completed **1,104 images / 552 matched poses**: default/enhanced × low/balanced/high, 0.55 m and 1.7 m eyes, 22–38 m outbound/return sweeps, calm/wind and boundary camera cuts. All capture logs are free of engine errors and the complete matrix validates. Same-pose hidden references isolate grass from background movement. Temporal residuals still include expected perspective motion, so this is not a new automatic pop threshold or a pass of the earlier static FLIP seam gate. No fade or coverage change was introduced to conceal that failure. [Full reduction, gzip](evidence/raw/audit-2026-10-18/transition/report.json.gz), [enhanced low view just outside the boundary](evidence/raw/audit-2026-10-18/transition/enhanced-high/low_rc_calm_return_return_30p25_sweep_06_visible.png), [inside](evidence/raw/audit-2026-10-18/transition/enhanced-high/low_rc_calm_return_return_29p75_sweep_07_visible.png).

The photographic sampling check passes at both heights against independent raw LOD0 8×/16× references. It retains high-resolution texture sampling/coverage while preserving base-pixel photo/turf fade weights and terrain-relief footprint. The photographic on/off residual includes its suppression of the old turf layer. Both spatial and camera-motion error improvements exceed twice the 8×/16× reference disagreement:

| Eye height | Spatial linear-RGB RMS, raw → filtered | Temporal residual-error RMS, raw → filtered |
| --- | ---: | ---: |
| 0.55 m | 0.037675 → 0.010128 | 0.053283 → 0.013247 |
| 1.7 m | 0.032917 → 0.005851 | 0.046505 → 0.006969 |

All six filtered 1× poses exactly match the active production shader, and the independent filtered run is byte-identical. The reducer checks active ground/texture bindings, shader-default provenance, SDR sRGB decoding and crop projection. Synthetic zero-detail/self-comparison checks were removed from capture acceptance because they were tautological; reducer sanity tests remain separate. An unset bool override must resolve from its unique hashed shader declaration, not be confused with a missing effective value. [Sampling result](evidence/raw/audit-2026-10-18/filter/comparison.json). This bounded two-view experiment supports the existing filtering; it does not prove universal shimmer absence or justify removing texture fetches without GPU evidence.

Fresh Stik and P-51 runway tapes each pass complete exact preflight and produce **2,881 byte-identical CSV rows** across actual default/enhanced field bindings, with `solver_changed=false`. In each process, Bisonte and MonsterCar2 separately pass 240-tick/241-sample GDScript recorder/checkpoint replay and identical state/control/recording hashes across grass modes. All 12 bracketed grass/checker source hashes remain unchanged. These headless checks omit only the independent treeline object and render no GPU frame; they establish numerical invariance, not physical or driving acceptance. The older tape correctly rejected a different solver. An existing-output regression verifies that failed invocations preserve previous evidence. [Final state inventory](evidence/raw/audit-2026-10-18/state-final/inventory.json). The earlier unbracketed run is retained separately and explicitly labels its producer hashes as retention-time observations.

The final full-session attempt used a stable imported app snapshot with only the grass layout/observer changes overlaid; concurrent tree/audio work was excluded. **Preflight stopped before launch** because another native tree capture (Godot PID 53792) was running. No new full-session timing pair is qualified, and the other process was left alone. The preview remains opt-in; active-session headroom, the static seam gate, owner/readability review and other-hardware acceptance remain open. [Campaign receipt](evidence/raw/audit-2026-10-18/session/campaign.json.gz).

The [artifact inventory](evidence/raw/audit-2026-10-18/inventory.json) records exact byte hashes and retention limits. Complete transition PNGs and the 8×/16× reference PNGs remain in local `tmp/grass-completion`; retained boundary/native images, every manifest and full reductions support review. Missing PNGs must be recaptured before a complete reduction on another machine. The first live-tree filter matrix and the v2 null-override failure are retained as diagnostics, not qualification. Visual captures used the earlier stable snapshot; the exact layout-parity check covers the later selection optimization. No simulation kernel, physics data or golden flight was changed.

## 2026-10-18 second audit: measurement integrity and material fidelity

Scope: L9e-R2/L11a-R1/L15c follow-up on the existing grass implementation. No new asset, density, shader or simulation change was adopted in this round.

| Finding | Correction | Runtime scope |
| --- | --- | --- |
| A missing native report produces `pacing_gate: null`; the runner dereferenced it and lost the run record. The campaign remained `in_progress` despite having a finish timestamp. | Retain the invalid run with no pacing verdict; finalize unexpected collection failures as stopped and retain attempted report/log paths. | Offline collection tool. |
| Two ground materials could have identical texture-path sets with different albedo/normal assignments and still verify. The profile validator also accepted expected maps in the wrong combined ground channel list. | Compare uniform-to-resource bindings, publish the slot map, and require the intended turf/photo maps in their exact uniforms. | One report-time observation; no frame-loop work. |
| The grass wind adapter accepted material options its replacement shader cannot preserve, including distance/proximity fading and additional material passes. Its transmittance property name was also wrong. | Reject unsupported source features before replacing any mesh, material or culling margin; preserve the static imported fallback. | Scene construction only; supported pinned source materials retain their appearance. |

A fresh nine-sample alternating CPU run reconfirms the **previously implemented** rank-cache optimization. This is not a new speedup from the validation changes:

| High-tier case | Default legacy → cached median, ms | Enhanced legacy → cached median, ms |
| --- | ---: | ---: |
| Open field | 64.856 → 0.951 | 52.298 → 0.883 |
| Narrow rough field | 50.723 → 0.930 | 48.439 → 0.906 |
| Nearby exclusion mask | 81.866 → 1.714 | 57.765 → 1.091 |

The first open-field call, including rank-cache construction with source assets already loaded, took 9.303 ms default and 6.924 ms enhanced. All five benchmark assertions passed per mode. Raw sample arrays, alternating order and source/tool hashes are retained in [default](evidence/raw/audit-r2-2026-10-18/layout-default.json) and [enhanced](evidence/raw/audit-r2-2026-10-18/layout-enhanced.json). These numbers measure layout selection, not whole-scene loading or FPS; no new GPU improvement is claimed.

The native session attempt passed process preflight and launched the default live-input flight. Its log records a prop strike and landing-gear crash with closed throttle; the process ended without a frame-time JSON. The old collector then threw `AttributeError` on the null pacing result. Keep the [original campaign](evidence/raw/audit-r2-2026-10-18/native-campaign-original.json.gz), [engine log](evidence/raw/audit-r2-2026-10-18/native-engine.log) and [collector traceback](evidence/raw/audit-r2-2026-10-18/native-collector.log) unchanged as failure evidence. No enhanced run or completed pair exists. The fixed collector's regression exercises the actual native reducer with a missing report, separately from an injected collection exception; these checks are not flight timings.

A proposed shader experiment moved grass UV anti-tiling calculations inside the existing photo-detail branch. Its baseline capture encountered `Woodland edge recipe is missing or invalid` while another track was changing woodland data; an unrelated headless scenery test was also observed. The capture is diagnostic only. No candidate capture, paired timing, pixel-parity claim or production shader edit was accepted. The [baseline log](evidence/raw/audit-r2-2026-10-18/uv-baseline.log), compressed manifest and temporary probe source are retained; its PNG set stays in local `tmp/grass-audit-r2/uv-baseline` and is not qualification evidence.

Verification passes **51 Python tests**, **68 frame-snapshot checks**, **204 grass-wind checks**, **38 ground-material checks** and **59 imported-placement checks**. The final headless editor import exits cleanly. The first full Python invocation lacked FLIP on its module path; reusing the existing isolated FLIP 1.7 wheel resolves that environment error without changing dependencies. Interruption tests also verify terminal pair status and retention of the original cause when final provenance inspection fails. Verification receipts and exact retained-byte hashes are listed in the [round inventory](evidence/raw/audit-r2-2026-10-18/inventory.json). The enhanced preview remains opt-in. Full-session pacing, the existing static seam limit, owner/RC moving-view review and other-hardware acceptance remain open.

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
