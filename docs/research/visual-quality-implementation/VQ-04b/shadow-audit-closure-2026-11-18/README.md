# Shadow audit closure measurements

2026-11-18 · VQ-04b, [shadow audit](https://github.com/bultodepapas/OpenRCsimulator/blob/audit/shadows-2026-11-17/docs/research/shadow-audit-2026-11-17/findings.md) SA-02 … SA-26 · Windows 11, NVIDIA GeForce RTX 3090, official Godot 4.8-beta2 (`cafc17a19`), High = Forward+/Vulkan, Standard = Compatibility/OpenGL.

The [shadow plan](../../../../plans/shadows.md) owns what changed and why; this page keeps the measurements. Images were inspected during the work and are not retained in the repository. Everything below is static-fixture or single-pose evidence on one machine; it does not qualify moving flights, other GPUs, Mobile or macOS.

## Shadow cost matrix (SA-25, SA-26)

[`tools/shadows/shadow_cost.py`](../../../../../tools/shadows/README.md#shadow-cost-matrix), production producer, 4× MSAA, 10 s warm-up then 8 s per run, three repeats with alternating technique order. The aircraft view draws the production planar cue and spins the Ugly Stik 1° per frame; the pavilion view is static. Root GPU is the main viewport; "offscreen" is a SubViewport's own GPU time when it redrew.

### 1920×1080

| Profile | View | Off | Projected | Native | Auto | Offscreen redraws | Spread |
| --- | --- | --- | --- | --- | --- | --- | --- |
| High (Forward+) | aircraft, moving | 1.232 | 1.260 (+0.028) | 1.739 (+0.507) | 1.673 (+0.441) | aircraft mask 0.060 (Projected only) | ≤ 0.058 |
| High (Forward+) | pavilion | 1.312 | 1.349 (+0.037) | 1.995 (+0.683) | 1.883 (+0.571) | none | ≤ 0.010 |
| Standard (Compatibility) | aircraft, moving | 1.036 | 1.181 (+0.145) | 1.405 (+0.369) | 1.394 (+0.358) | aircraft mask 0.373 (Projected only) | ≤ 0.024 |
| Standard (Compatibility) | pavilion | 1.068 | 1.126 (+0.058) | 1.350 (+0.282) | 1.440 (+0.372) | none | ≤ 0.115 |

GPU medians in ms; parentheses are the delta against Off in the same profile and view. Spread is the largest max − min of per-run medians in the row; smaller deltas are not resolved.

Readings:

- Native maps dominate the shadow cost: +0.5–0.7 ms on Forward+ (High's 8192² atlas, four cascades, PCSS) and +0.3–0.4 ms on Compatibility at 1080p.
- Auto costs Native minus the planar cue: within native range the SA-02 handoff hides the cue, so its mask never redraws (no offscreen time in Auto).
- A moving aircraft's mask costs 0.06 ms on Forward+ but 0.37 ms on Compatibility. It is paid only by Projected (or Auto beyond native range); its root share is the receiver.
- Static field masks redraw only when the light or source changes; in steady state they cost nothing per frame.

### 2560×1440 and 3840×2160

Two repeats each, same method:

| Profile | View | Width | Off | Projected | Native | Auto | Aircraft mask | Spread |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| High | aircraft, moving | 2560 | 1.900 | +0.069 | +0.729 | +0.718 | 0.062 | ≤ 0.009 |
| High | aircraft, moving | 3840 | 3.801 | +0.107 | +1.181 | +1.148 | 0.063 | ≤ 0.173 |
| High | pavilion | 2560 | 1.977 | +0.074 | +0.915 | +0.780 | — | ≤ 0.080 |
| High | pavilion | 3840 | 3.713 | +0.157 | +1.517 | +1.351 | — | ≤ 0.017 |
| Standard | aircraft, moving | 2560 | 1.367 | +0.175 | +0.435 | +0.420 | 0.383 | ≤ 0.030 |
| Standard | aircraft, moving | 3840 | 2.263 | +0.137 | +0.485 | +0.551 | 0.383 | ≤ 0.016 |
| Standard | pavilion | 2560 | 1.315 | +0.081 | +0.317 | +0.428 | — | ≤ 0.179 |
| Standard | pavilion | 3840 | 2.062 | +0.143 | +0.376 | +0.580 | — | ≤ 0.267 |

- Native cost grows with the pixel count on High (+0.5–0.7 ms at 1080p, +0.7–0.9 at 1440p, +1.2–1.5 at 4K): High's soft PCSS filtering is per-pixel work, not only shadow-map rendering. Compatibility's PCF grows much less (+0.3–0.5 ms at 4K).
- The aircraft mask stays at its fixed 256² cost on every output size (0.06 ms Forward+, 0.38 ms Compatibility), so Projected is the cheapest direct-shadow route at every resolution.
- On Compatibility, Auto is not cheaper than Native in the static pavilion: Auto keeps the projected field receivers next to the native sun (its documented ownership), and these rows also have the largest spread.
- Compatibility's moving-aircraft mask (0.38 ms; 165k triangles into a 256² target, so probably vertex-bound, not tested) is the one measured efficiency opportunity: a decimated silhouette for every aircraft, like the Corsair's admitted LOD proxy, would remove most of it. It is not implemented here (it needs its own visual-parity gate).

## Native caster semantics (SA-05)

A floating box per material over a lit plane, straight-down sun, ground luminance under each box relative to lit ground (1.0 = no shadow), both renderers:

| Material | Forward+ | Compatibility |
| --- | --- | --- |
| Opaque; opaque with alpha 0.45 (transparency disabled); depth pre-pass at 0.45; plain shader; shader with `depth_prepass_alpha` writing ALPHA 0.5 | 0.27 (casts) | 0.22 (casts) |
| Blend at alpha 0.45 or 0; blend with `shadow_to_opacity`; shader writing ALPHA 1.0 or 0.5; shader with `blend_add` | ≈ 1.0 (none) | ≈ 1.0 (none) |
| Scissor at alpha 0 | ≈ 1.0 (none) | ≈ 1.0 (none) |
| Hash at alpha 0.5 | dithered, partial | dithered, partial |

Fleet effect: the P-51 canopy and windscreen and the Extra 300 canopy (about 2,000 triangles each) left the aircraft mask; Timber glass is forced opaque at runtime and keeps casting in both routes.

## Other measurements

| Finding | Measurement |
| --- | --- |
| SA-02 | 1080p Forward+ High, Stik on the ground: Auto showed the native and planar shadows overlapping (darker, doubled edge). After the handoff Auto matches Native; at 270 m the cue appears as the native fades. |
| SA-16 | Lake at 1080p, water shader with the custom `light()` against the original at zero cloud strength: max 1/255 (Forward+), max 2/255 on 6 pixels (Compatibility). With the cloud shade forced to full strength the change is confined to the water, ≤ 7/255. |
| SA-17 | Night runway chase capture, landing light shadow on vs off: the whole beam darkens by up to 36/255, identical for shadow bias 0.2/0.5/1.0 with normal bias 2/4/6 (airframe occlusion, not acne). Not adopted. |
| SA-18 | Pavilion, Native: 8 alpha-cut people batches admitted. Per scenery tier: low 12 meshes, 0 people; balanced/high 10 meshes, 8 people, 2 shelters; no exclusions. 1080p, three alternating runs: Forward+ 2.146 → 2.179 ms, Compatibility 1.417 → 1.324 ms (within spread). |
| SA-19 | Tagged blades equal the meshes each blur hides on all fixed-wing aircraft and the HX-700 main/tail rotors; a parked Stik blade adds its line to the projected shadow (max 45/255 on 47 pixels). |
| SA-21 | Snapshot sweep 04:00–19:30: daytime direct-shadow strength 1.0 from 0.5° apparent elevation (previously 0.70 at 6°, 0.81 at 30°). |
| SA-22 | Forward+ Ultra: Native→Projected kept 332.5 MiB of textures before; 76.5 MiB now (256 MiB atlas released). Compatibility's counters omit the atlas. |
| SA-23 | Disabled-cue bind collection: 0.9–22 ms warm per stock aircraft (Corsair 321k triangles the largest), ≤ 148 ms first cold call, 0.9–11 MiB retained, once per session load. |

## Follow-up experiments (same day)

**Aircraft mask cost.** Production cue on the Stik spinning 1°/frame, the mask's own GPU time (median, 8 s after warm-up) and, where noted, the frame's wall time:

| Change to the 256² mask | Compatibility mask ms | Forward+ mask ms |
| --- | --- | --- |
| Current (165,768 triangles, MSAA 4×) | 0.397 | 0.059 |
| meshoptimizer silhouette, 42,501 / 21,582 / 10,470 triangles (error 3 / 6 / 12 mm) | 0.385 / 0.371 / 0.384 | 0.036 / 0.032 / 0.029 |
| MSAA off / 2× | 0.398 / 0.385 | 0.040 / 0.048 |
| Positional shadow atlas 0 (was 2048) | 0.374 | — |

Compatibility's mask cost is a fixed per-viewport overhead: 94% fewer triangles, no MSAA or no positional atlas leave it unchanged. Its real frame cost is smaller than the GLES3 timer suggests: redrawing every frame adds +0.22 ms of wall time (2.00 vs 1.79 ms) against +0.07 ms on Forward+. Simplification would save 0.03 ms on Forward+ for a 240 ms bind (weld 93 ms + LOD 147 ms), so it was not adopted. The remaining lever is redraw frequency, a quality trade that needs integrated-GPU measurement.

**Field flood shadows (VQ-04b-S08).** Night pilot view (23:30, Stik on the runway under the 12 m mast), the four floods and the windsock lamp with `shadow_enabled` on vs off: Compatibility 289 → 718 draw calls and a broad, unlocalized darkening of the runway (up to 32/255, default bias); High 293 → 436 draw calls and a pixel-identical image. Not adopted.

## Limits

- One GPU (RTX 3090), Windows, 1080p first; Mobile/Metal, integrated GPUs and Macs are unmeasured.
- Static fixtures and single poses: no moving-flight frame-time tails, no camera motion beyond the spinning aircraft, no cloud-bake or reflection cold costs.
- The managed launcher on this host refuses the junctioned import cache, so running-app captures used the app's own `--capture` mode.
