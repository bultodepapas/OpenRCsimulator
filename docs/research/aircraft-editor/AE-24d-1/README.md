# AE-24d.1 — Saved-variant thumbnail lifecycle

**Date:** 2026-10-19. **Status:** native and headless software checks pass on the recorded configuration; broader platform and resource acceptance remains open.

This phase adds a bounded still-image service for complete, saved Workshop variants. The service freezes the stored record through `Trial.freeze`, derives a cache identity from physical and presentation identities, scale, fixed camera settings, Godot version, renderer, and display server, then renders the static built model in a temporary `SubViewport` with its own 3D world. It copies the finished frame into an RGBA8 `ImageTexture`; it does not use the interactive preview, advance a flight or smoke clock, or cache a `ViewportTexture`.

Implementation: [thumbnail service](../../../../app/ui/workshop_thumbnail.gd), [copied-pixel LRU](../../../../app/workshop/thumbnail_cache.gd), [focused test](../../../../app/tests/test_workshop_thumbnails.gd), and the reusable [native capture runner](../../../../research/aircraft-editor/capture_thumbnails.gd).

## Fixed render and evidence

The renderer outputs a 320×192 RGBA8 image with a 38° vertical field of view, yaw 225°, pitch 16°, and a fixed camera-fit policy (`FIT_FILL=0.89`, `SAFE_FILL=0.93`). The camera specification is versioned as `workshop-thumbnail-camera-v1` and included in the thumbnail identity. Rendering is awaited through `RenderingServer.frame_post_draw` before reading pixels.

| Saved aircraft | Capture | Foreground bounds (x, y, w, h) | Nearest image edge |
| --- | --- | --- | --- |
| Jensen-Das Ugly Stik 60 | [PNG](stik_thumbnail.png) | 83, 65, 149, 69 | 58 px |
| GP Extra 300S 60 | [PNG](extra300s_thumbnail.png) | 89, 61, 134, 76 | 55 px |

Bounds use the capture runner's fixed-background RGB tolerance. Both inspected images show the complete aircraft with margin. [Native capture JSON](thumbnail-evidence.json) records pixel hashes, saved variant/trial/presentation identities, renderer identity, cache counters, bounds and every cancellation result. The [native console log](thumbnail-native.log) records **32 checks, 0 failed** on Godot 4.7.2 official build `ed1daf0bf`, Windows, OpenGL Compatibility, NVIDIA GeForce RTX 3090 driver 617.42.

The native run rendered the two families above with no smoke nodes. It then ran **20 cancellation cycles**, each after the isolated model and viewport were observed: all 20 suppressed publication and released their stage/viewport; the final preview-isolation check passed. The two frames had distinct pixel hashes. Headless logic and cache coverage is in [thumbnail-headless.log](thumbnail-headless.log): **45 checks, 0 failed**, including identity separation, request cancellation, late-result suppression, LRU byte/count bounds, and a mipmapped-image regression.

## Cache bounds and accounting

The copied-pixel cache allows at most **16 entries**, **4 MiB (4,194,304 bytes)** and a **512-pixel maximum dimension**. The native report held two 320×192 images, **491,520 accounted bytes** total (245,760 bytes each at four bytes per pixel). The cache clears mipmaps and verifies the copied RGBA8 data length before accounting it.

These are limits on the cache's retained base-level image pixels. They are **not** a measured GPU or VRAM cap. A render target, GPU attachments and pixel readback are transient allocations outside that cache accounting. A consumer may also retain the currently displayed `ImageTexture` after cache eviction; that live display reference is outside the cache counters. The tests assert software accounting and lifecycle, not hardware memory use.

## Reproduction

Run these PowerShell commands from the repository root. The native command supplies an explicit phase-folder output path so generated evidence stays with this record.

Headless suite:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_thumbnails.gd 2>&1 | Tee-Object -FilePath docs/research/aircraft-editor/AE-24d-1/thumbnail-headless.log
if ($LASTEXITCODE -ne 0) { throw "Headless thumbnail checks failed: $LASTEXITCODE" }
```

Native capture and cancellation suite:

```powershell
$repo = (Get-Location).Path
$evidence = Join-Path $repo 'docs/research/aircraft-editor/AE-24d-1'
$script = Join-Path $repo 'research/aircraft-editor/capture_thumbnails.gd'
& (Join-Path $repo '.tools/Godot_v4.7.2-stable_win64_console.exe') --path (Join-Path $repo 'app') --script $script -- "--out-dir=$evidence" 2>&1 | Tee-Object -FilePath (Join-Path $evidence 'thumbnail-native.log')
if ($LASTEXITCODE -ne 0) { throw "Native thumbnail checks failed: $LASTEXITCODE" }
```

## Limits

Native pixel evidence covers two saved fixed-wing families on one Windows/GPU/renderer configuration. Headless execution cannot validate rendered pixels. These checks do not measure GPU/VRAM consumption, cover all aircraft or export targets, establish cross-driver image equality, or complete platform, accessibility, or user-acceptance testing. Thumbnails are static library images, not evidence of flight behavior or physical performance.

## Godot API references

The implementation follows the pinned Godot 4.7 API: [Viewport and separate 3D worlds](https://docs.godotengine.org/en/4.7/classes/class_viewport.html), [SubViewport](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html), [Viewport texture readback](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-get-texture), [RenderingServer frame-post-draw signal](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-signal-frame-post-draw), and [Image mipmap and raw-data methods](https://docs.godotengine.org/en/4.7/classes/class_image.html#class-image-method-clear-mipmaps). Godot documents `frame_post_draw` as the point after the RenderingServer has updated all Viewports, and demonstrates awaiting it before saving a viewport texture. The image cache relies on the documented raw pixel data and `clear_mipmaps()` behavior.

## Selected source hashes

SHA-256 of the current working-tree source after LF line-ending normalization (UTF-8). These hashes identify the thumbnail implementation snapshot associated with the logs above; they are not Git object IDs. The root-owned Workshop UI integration file is omitted pending its final integration snapshot.

| Source | SHA-256 |
| --- | --- |
| `app/ui/workshop_thumbnail.gd` | `18c66d76f34776339cb09fa710ceeaaeaf66b12ce6651bc722a95d5af13ea90f` |
| `app/workshop/thumbnail_cache.gd` | `121c783fe3a5bd4b2413657817875fdda431007cd652f53f87cfc824b2a5b1c0` |
| `app/tests/test_workshop_thumbnails.gd` | `e35764bab9775fca47369bb5eaab3a9749f8ce1fe2e2005694d32be0df8ccb25` |
| `research/aircraft-editor/capture_thumbnails.gd` | `59bbe794a2a8c804eebc2e0ac1819743e2f066cdf074d937937afd5d8457b6c6` |


