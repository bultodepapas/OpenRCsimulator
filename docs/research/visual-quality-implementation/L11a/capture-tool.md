# L11a capture and review tool

Date: 2026-10-07. **Status: engineering captures pass; human and target-GPU review remain open.** Step prefix: **L**. This note documents the focused L11a GPU evidence producer and checker.

## Run

```sh
"$(app/tests/visual-env.sh)" tools/grass/check_grass.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l11a-grass \
  --baseline-app /path/to/frozen-pre-l11a/app
"$(app/tests/visual-env.sh)" tools/grass/check_grass_seam.py \
  --captures /tmp/l11a-grass/candidate-repeat-1 \
  --out /tmp/l11a-grass/seam-summary.json --self-test
```

The output directory must be new or empty. The checker refuses stale files, performs two independent Compatibility-renderer processes for each capture set, and writes logs, per-process PNGs and manifests, then `capture-summary.json`. To compare grass-off output with a frozen pre-L11a app, add `--baseline-app /path/to/baseline/app`; every paired grass-off image must then be byte-identical. The baseline project may predate `Field/NearGrass`.

The candidate set has 12 matched grass-off/on views: pilot height 1.7 m at azimuths 0°, 90°, 180° and 270°, each at elevations −10° and −25°; a 3 m raised low-pass view; a near-runway edge view; a 3 m raised view aimed to project the 25–35 m ground band; and a 35 m raised camera looking down at −60° to exercise camera-distance collapse. The checker requires that last grass-off/on pair to be byte-identical. It reads the effective 22 m and 30 m fade parameters from the ShaderMaterial, falling back to `RenderingServer.shader_get_parameter_default` for compiled shader defaults. The set also captures a zero-wind t=1 s image and nonzero-wind images at t=0, t=1 and t=1024 s. Ground, sky and clouds stay at t=0 during these clock checks. The pilot azimuth 0° / elevation −10° / grass-on image supplies the zero-wind t=0 reference.

A separate two-image integration set launches with `--scenery=on`, checks that the production Scenery child and SC-16 flower MultiMeshes exist without duplicate names, then compares the same view with grass hidden and visible. When requested, the baseline adds 12 grass-off views per process. The current set contains 28 candidate PNGs and two integration PNGs per process.

## Checks

The capture producer registers `ShaderClock` before building the field, then uses `FieldBuilder.build`, `Atmosphere.environment` and the production sun. It toggles only the `NearGrass` child for each matched image. The producer rejects a missing grass node on candidate runs; only baseline mode permits its absence.

The checker reads back the GPU-mode MultiMesh instance transforms and verifies the one NearGrass node, at most four chunks, no more than 6,000 seven-triangle clumps, a 30 m pilot radius, no instances on the runway, no shadow casting, and the UV-weighted fixed-root wind contract. It measures visible draw and primitive increments from the renderer and enforces +5 draws and +100,000 primitives. A ray-plane projection defines the image-space 0–36 m grass envelope; a grass A/B difference outside it fails. Its whole 25–35 m annulus channel mean is a broad diagnostic. The local acceptance check is `tools/grass/check_grass_seam.py`: 1 m radial bins × eight screen strips, mean channel change ≤3%, and FLIP p99 ≤0.1. Run it with `--self-test`; a copied 25 cm dark seam segment must fail.

Two independent processes must produce byte-identical PNGs and manifests for the candidate, scenery and optional baseline sets. Zero wind at t=0 and t=1 must be identical; nonzero wind must move grass between t=0 and t=1 while leaving the projected background unchanged; the t=1024 image must match t=0. Source hashes are recorded before and after capture for runtime app files outside `app/tests/` and for both evidence producers. Any changes during capture fail the run.

## Engineering result

The 2026-10-07 software OpenGL run passed with a frozen pre-L11a app. The default field built 4,843 clumps in four MultiMeshes (33,901 triangles), all within the 30 m radius, with no runway instances or shadows. Across 12 matched views, the largest measured increment was +2 draws and +20,552 visible primitives; every changed pixel stayed within the projected grass envelope. The candidate grass-off images matched all 12 baseline images byte for byte. Candidate, baseline and scenery sets repeated byte for byte across two independent processes. The SC-16 integration view contained 19 unique flower MultiMesh nodes. The 35 m camera-distance fade pair had zero changed pixels and identical PNG hashes; its effective shader defaults were 22 m and 30 m.

The raised-view radial seam check passed at 0.2621% maximum local channel mean and 0.05971 FLIP p99; the dark-seam mutation was rejected at 6.7114% and 0.2391 FLIP p99. The broad 25–35 m band mean was 0.0238% of the no-grass image. Zero-wind t=0/t=1 and wind t=0/t=1024 were byte-identical. With a 5 m/s eastward wind vector, t=0/t=1 changed 79,363 pixels inside the grass envelope and none outside. Mesh readback found 14 ground-root vertices with UV.y=0, and the shader weights sway by UV.y², supporting fixed roots. The GPU capture checks placement in the default field; placement clipping for other field rectangles is a separate code-level check.

Software OpenGL proves deterministic images and renderer counter budgets. It does not establish frame time on the owner's GPU or human approval of the grass appearance.
