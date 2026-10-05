# 10 · Testing and measuring landscape work automatically

Date: 2026-10-05. **Question:** which tools and methods can give every L step an objective, repeatable proof (image diffs, counters, readability, frame time), and what harness should L0 build?

## Findings

**1. The plan's "counters measured headlessly" cannot work.** `--headless` selects the `headless` display server, and its only rendering driver is `dummy` ([display_server_headless.h @4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/display/display_server_headless.h) [src]). So every `RENDER_*` monitor reads 0 there [inference]: read counters in the Xvfb + `opengl3` capture run.

**2. What Compatibility actually counts** ([gles3 scene](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp), [utilities.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/utilities.cpp) [src]; [Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html), [Viewport](https://docs.godotengine.org/en/stable/classes/class_viewport.html) [doc]):

| Counter | Source | Use |
| --- | --- | --- |
| draw calls, primitives, objects | `Viewport.get_render_info(TYPE, INFO)` with `RENDER_INFO_TYPE_VISIBLE` and `..._SHADOW` kept separate | L3: shadow-pass cost alone (PSSM draws once per split) |
| `RENDER_VIDEO_MEM_USED` | GLES3: **Godot's own byte tally**, not a driver query | Deterministic: a texture budget test (L9, L10, L16) |
| GPU time | `viewport_set_measure_render_time` → `glQueryCounter(GL_TIMESTAMP)`, **only when `is_gles_over_gl()`** | Desktop GL only; 0 on WebGL [src]; never under llvmpipe |

`Performance.TIME_PROCESS` updates once per second and godot-benchmarks reports averages ([manager.gd](https://github.com/godotengine/godot-benchmarks/blob/main/manager.gd) [src], MIT); `--print-fps` prints 1-second FPS after a warm-up ([main.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp) [src]). None gives a p95.

**3. Byte equality fits one pinned renderer; CI does not pin Mesa.** `ci.yml` runs `apt-get install libgl1-mesa-dri` without a version. This VM has Mesa `25.2.8-0ubuntu0.24.04.2` [measured]. Renders are byte-reproducible "in single threaded mode"; multithreading can add small variations ([godot-benchmarks#34](https://github.com/godotengine/godot-benchmarks/issues/34) [iss]). `LP_NUM_THREADS` defaults to the core count ([Mesa env vars](https://docs.mesa3d.org/envvars.html) [doc]), so CI and this VM can differ. Mesa's CI keeps expectations per driver ([Mesa CI](https://docs.mesa3d.org/ci/index.html) [doc]): **key our golden hashes by renderer string** too.

**4. Godot has no official visual-regression suite.** The proposal is open ([godot-proposals#1760](https://github.com/godotengine/godot-proposals/issues/1760) [iss]); [Calinou/godot-rendering-tests](https://github.com/Calinou/godot-rendering-tests) (MIT, WIP) uses `dssim`, which is **AGPL-3.0** ([repo](https://github.com/kornelski/dssim) [repo]): excluded. Unity's model is better: per-pixel ΔE, average error and **ratio of incorrect pixels** ([ImageComparisonSettings](https://docs.unity3d.com/Packages/com.unity.testframework.graphics@7.8/api/UnityEngine.TestTools.Graphics.ImageComparisonSettings.html) [doc]).

**5. Mean image metrics miss a small airplane.** I tested FLIP 1.7 and SSIM (scikit-image 0.26.0) on a 1280×720 pilot capture [measured]:

| Change | mean FLIP | SSIM | pixels with FLIP > 0.1 |
| --- | --- | --- | --- |
| identical | 0 | 1 | 0 |
| ±1 level noise on 5 % of pixels (Mesa-like) | 0.0030 | 0.9992 | **0** |
| whole image +2 levels | 0.0529 | 0.9999 | **0** |
| 16×16 px block turned red (≈ airplane at 100 m) | **0.0004** | 0.9995 | **608** |

The real regression scores *lower* than the noise on both means: **the tolerant gate must count pixels above a per-pixel threshold**, like Unity. FLIP takes ~0.9 s per 720p pair [measured]; pass `-vc 0.7 0.6 1280` (default is a 4K screen at 0.7 m) [doc: `flip -h`].

**6. Readability without a shader.** Rendering is deterministic, so capture each view with and without the airplane: differing pixels are the mask, the hidden frame is the *true local background*. Weber contrast ([Peli 1990](https://pelilab.partners.org/papers/Contrast%20in%20Complex%201990.pdf) [AP]) of mask vs a surrounding ring is a trackable number [inference]. Horizon: per column, the row of maximum vertical luminance step, the simplest form of MAV horizon detection ([Ettinger et al. 2003](http://mil.ufl.edu/nechyba/www/mav/iros2002.pdf) [AP]); its spread measures silhouette variety, its step size the "hard edge".

```python
# readability.py: our code (MIT). Needs numpy 2.5.3 and pillow 12.3.0 (or rewrite with Godot Image).
import numpy as np; from PIL import Image
def lum(p):
    a = np.asarray(Image.open(p).convert("RGB"), np.float64) / 255
    a = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)  # sRGB -> linear
    return a @ [0.2126, 0.7152, 0.0722]
def plane_contrast(with_plane, without_plane, ring_px=6):
    L1, L0 = lum(with_plane), lum(without_plane)
    mask = np.abs(L1 - L0) > 1e-6                  # deterministic renderer: only the plane differs
    ys, xs = np.nonzero(mask); y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    ring = np.zeros_like(mask); ring[max(y0-ring_px,0):y1+ring_px+1, max(x0-ring_px,0):x1+ring_px+1] = True
    ring &= ~mask
    bg = L0[ring].mean()
    return (L1[mask].mean() - bg) / max(bg, 1e-4), int(mask.sum())  # Weber contrast, size in px
def horizon_rows(path):
    g = np.abs(np.diff(lum(path), axis=0))         # vertical luminance step
    return g.argmax(axis=0), g.max(axis=0)          # per column: row and sharpness
```

**7. Frame time needs our own logger:** per-frame `Time.get_ticks_usec()` deltas, V-Sync off, warm-up skipped, p50/p95/p99 plus GPU ms (GPU power states inflate GPU time under a cap: [RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html) [doc]).

```gdscript
# perf_log.gd: our code (MIT). Usage: game -- --perf-log=/tmp/p.json --perf-frames=1800
extends Node
var _dt: PackedFloat64Array = []; var _gpu: PackedFloat64Array = []
var _last := 0; var _skip := 120; var _n := 1800; var _out := ""
func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last != 0 and _skip <= 0:
		_dt.append((now - _last) / 1000.0)
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_skip -= 1; _last = now
	if _dt.size() >= _n: _finish()
func _p(a: PackedFloat64Array, q: float) -> float:
	var s := a.duplicate(); s.sort(); return s[mini(int(q * s.size()), s.size() - 1)]
func _finish() -> void:
	var r := {adapter = RenderingServer.get_video_adapter_name(), frames = _dt.size(),
		p50_ms = _p(_dt, .5), p95_ms = _p(_dt, .95), p99_ms = _p(_dt, .99), gpu_p95_ms = _p(_gpu, .95)}
	FileAccess.open(_out, FileAccess.WRITE).store_string(JSON.stringify(r)); get_tree().quit()
```

**8. Manual tools.** RenderDoc supports OpenGL **core 3.2–4.6** ([docs](https://renderdoc.org/docs/behind_scenes/opengl_support.html) [doc]); Godot's X11 driver requests 3.3 core ([gl_manager_x11.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/x11/gl_manager_x11.cpp) [src]): use it to explain a draw-call jump, not in CI. Movie Maker (`--write-movie x.png --fixed-fps N --quit-after F`) writes numbered PNG strips with perfect pacing ([docs](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html) [doc]): fit for L4 and L8 strips.

## Libraries / tools found

| Name | Version / last release | License | Compatibility / web? | Fit for us |
| --- | --- | --- | --- | --- |
| [FLIP](https://github.com/NVlabs/flip) `flip-evaluator` | 1.7, 2025-11-07 | BSD-3 | offline tool | **Yes:** tolerant tier, error maps for review, CLI and numpy API, cp312 wheels |
| numpy / Pillow | 2.5.3 / 12.3.0 | BSD-3 / MIT-CMU | offline | Yes: readability and horizon scripts |
| scikit-image | 0.26.0, 2025-12-20 | BSD-3 | offline | Optional: SSIM for reports; pass `data_range` ([doc](https://scikit-image.org/docs/stable/api/skimage.metrics.html)) |
| [pixelmatch](https://github.com/mapbox/pixelmatch) | 7.2.0 | ISC | JS (Node) | Only for the archived three.js build |
| ImageMagick `compare` | 7.1.2-32 | ImageMagick (Apache-style) | system package | Fallback; unpinned apt dependency ([doc](https://imagemagick.org/compare/)) |
| dssim | 3.4.0 | **AGPL-3.0** | — | **Excluded** |
| RenderDoc | v1.46 | MIT | desktop GL 3.3 core ✅ | Manual frame inspection |

## What this changes in LANDSCAPE-PLAN.md

- **Budgets bullet:** replace "measured headlessly" with "measured in the Xvfb/`opengl3` capture run (`--headless` uses the dummy renderer)". Add a **VRAM (Godot tally)** budget test and report **shadow-pass primitives** separately.
- **Split L0 into four steps:**
  - **L0a, review views and manifest.** `--capture` also writes `<view>.json`: SHA-256, visible/shadow draw calls, primitives, objects, VRAM, `get_video_adapter_name()` (Mesa/LLVM), Godot version, `LP_NUM_THREADS`. *Proof:* two runs give identical manifests; counters non-zero.
  - **L0b, determinism probe.** `LP_NUM_THREADS=1` vs default, on this VM and CI. *Proof:* a recorded byte-match table; pin the winning value in `capture.sh`; log or pin the Mesa version (`libgl1-mesa-dri=<ver>`).
  - **L0c, two-tier compare** (`tests/compare_captures.py`, with pinned and hashed `requirements-visual.txt`: flip-evaluator 1.7, numpy 2.5.3, pillow 12.3.0). Tier 1: SHA-256 when the renderer string matches the golden's. Tier 2 (Mesa changed): `n(FLIP > 0.1) ≤ 50` (estimate, set from L0b noise), error map uploaded. *Proof:* a 16×16 mutation on a copy fails, ±1-level noise passes.
- **Add L0d, readability baseline:** the with/without-airplane pairs at 30, 100 and 200 m give Weber contrast and mask size per view. *Proof:* baseline numbers in the plan.
- **Sharper proofs for later steps:**
  - **L1:** horizon row from `horizon_rows` within 2 px of the projected horizon.
  - **L2:** max horizon step below threshold.
  - **L3:** the shadow-pass counters added are within budget.
  - **L6:** Weber contrast vs trees next to vs sky; horizon-row std > 0 (varied silhouette).
  - **L8:** Movie Maker strip: no FLIP-count spike between consecutive frames at the switch distance.
  - **L9:** edge contrast measured with the same Weber function.
- **Gate L:** add `--perf-log` (p50/p95/p99 frame time plus GPU p95) on the owner's slowest machine and a laptop iGPU. llvmpipe numbers stay excluded.

## Not confirmed

- Whether llvmpipe output is bit-identical across thread counts or CPU types (AVX2 vs AVX-512). L0b measures it.
- Whether Movie Maker frames are byte-identical between runs under llvmpipe.
- Whether sky radiance (QUALITY) adds draw calls only in early frames.
- The FLIP pixel-count threshold of 50 is a guess until L0b noise data exists.
