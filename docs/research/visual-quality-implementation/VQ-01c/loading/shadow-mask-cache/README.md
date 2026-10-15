# DT-11a — reuse fallback shadow pixels

2026-10-15. Follow-up to [shadow blur indexing](../shadow-blur/README.md).
`app/render/shadow.gd` caches the deterministic mask's RGBA8 mip bytes after the
first generation. Later calls reconstruct a fresh `Image`; every carrier still
owns its own image texture, material and mesh. The two blur passes and first
generation arithmetic are unchanged.

The cache holds one **87,380-byte CPU payload** (about 85.3 KiB, plus container
overhead). It does not retain GPU textures or scene nodes and cannot grow with
the number of scenes. Its inputs are the script's fixed silhouette constants.
Home, flight and runway scene creation use the same shadow API. Switching an
aircraft within an existing Home already reuses its carrier; this change targets
later carrier construction, not that existing selector fast path.

Sharing mutable `Image`/`ImageTexture` resources was rejected: one carrier's edits
must not affect another. Lazy bytes plus [Image.create_from_data](https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-create-from-data)
preserve this ownership contract. No downloaded/generated asset, shader,
simulation, aircraft data or per-frame update changed.

## Measurements

Five fresh native processes, ten alternating reference/candidate pairs per
workload, reversing the starting order between processes. Godot 4.7.2 `ed1daf0bf`,
Windows, Compatibility/OpenGL, RTX 3090 / NVIDIA 610.88. Shared host; no claim of
isolated clocks or complete startup performance. Equality/readback is outside
the timer. Each workload's warm table pools pairs 1–9 (45 samples per variant).

| Workload | Reference median | Candidate median |
| --- | ---: | ---: |
| Repeated mask construction | 14.316 ms | 0.005 ms |
| Complete carrier construction after mask generation | 16.266 ms | 0.853 ms |
| First mask call per fresh process | 14.059 ms | 15.919 ms |

Repeated carrier construction saves about **15.4 ms / 94.8%** in this experiment.
The first call still performs generation and retains its bytes: it does **not**
show a consistent improvement. Its five samples span 11.903–17.930 ms for the
reference and 11.380–16.245 ms for the candidate. The higher candidate cold-call
median is retained, not treated as a startup non-regression pass. Carrier timing
follows the mask workload, so even its pair 0 is not a cold carrier measurement.
See `summary.json` and all `native-*.json`/logs.

All **100 native pairs** have identical complete image bytes, seven mip levels,
dimensions and format; carrier comparisons also preserve plane arrays,
transform, shadow flags and material values. This is constructor cost, **not FPS,
complete Home/Fly latency or package acceptance**. The accepted tradeoff is a small
fixed CPU allocation for later construction; cold-load qualification remains open.

## Checks

Existing regressions pass unchanged:

- Shadow blur, exact float32 filter outputs, image/texture mutation isolation and
  later construction: **50/50** headless and **50/50** native.
- Projected shadow binding, fallback and lifecycle: **37/37** headless and native.
- Pilot aids: **22/22** headless.
- Field integration and complete Home UI navigation: passed headless.
- Home model selection/reuse/eviction and shadow lifecycle: **18/18** headless and
  native.

The ownership tests deliberately alter a returned image, clear its mipmaps and
update a carrier texture; other and later instances retain the original pixels.
No new implementation-mirroring test was needed. No full CI, export, loading
campaign, visual flight soak or Linux/macOS qualification is claimed.

## Reproduction

`source-before.json` pins the initial HEAD and shadow dependencies; `source-after.json`
checks that only the shadow script changed among those dependencies. Compressed
reference/candidate sources are retained. The probe reuses the preceding shadow
blur campaign's exact-output comparison. Run on an imported project:

```text
python research/visual-quality/shadow-mask-cache/run.py --godot PATH_TO_GODOT --app app --out tmp/shadow-mask-cache-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_shadow_blur.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_projected_shadow.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

The comparison requires a native renderer and a new output directory; `--runs 1`
is a short runner check. Omit `--headless` for native regression checks. Tests use
Dummy audio and keep existing aircraft-data warnings. Changes from other tracks
in the shared working tree are preserved.
