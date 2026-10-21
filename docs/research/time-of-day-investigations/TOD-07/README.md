# TOD-07 — Render compatibility and cloud occlusion

2026-10-10 · **Status: rendered matrix and production-sky controls complete; hardware and pilot validation remain open.**

Owning plan: [TIME-OF-DAY-PLAN](../../../TIME-OF-DAY-PLAN.md). This report records the integrated render captures and a bounded cloud/horizon shader control. It does not claim calibrated sky radiance, aircraft visibility acceptance, or target-GPU performance.

## Render matrix

The 16-case direct-flight matrix ran against the integrated working tree at 1280×720 with pinned Godot 4.7.2, OpenGL Compatibility, Mesa 25.2.8 llvmpipe and Xvfb. All captures exited successfully; the runner found no engine, script or shader errors. Results, capture JSON, process logs and hashes are in [`evidence/working-tree/summary.json`](../../../../research/time-of-day/tod-07/evidence/working-tree/summary.json) and the [checksum manifest](../../../../research/time-of-day/tod-07/evidence/working-tree/SHA256SUMS). Representative images: [midnight](../../../../research/time-of-day/tod-07/evidence/working-tree/images/default-00-00.png), [noon](../../../../research/time-of-day/tod-07/evidence/working-tree/images/default-12-00.png), and [Sun-centered 18:00](../../../../research/time-of-day/tod-07/evidence/working-tree/images/sun-centered-18-00.png).

Cases cover the legacy default; 00:00, 05:45, 06:00, 12:00, 18:00 and 18:30; all four catalog aircraft at noon and night; scenery enabled at noon and night; and an 18:00 view aimed at the selected Sun. The astronomical fixture is 2026-03-20 at a synthetic reference site (0° latitude, 0° longitude, UTC+00:00), not the real field.

An earlier 13-image scratch-copy capture is omitted because every PNG was byte-identical to its retained working-tree counterpart. The [scratch summary](../../../../research/time-of-day/tod-07/evidence/scratch/summary.json), sidecars, logs and [checksum manifest](../../../../research/time-of-day/tod-07/evidence/scratch/SHA256SUMS) remain as dated records; their PNG paths and hashes describe files that are no longer retained.

The legacy PNG matches the [TOD-01 production baseline](../TOD-01/README.md) byte-for-byte: SHA-256 `98368c07ecbbe69c8064679226b2bda9c0ae37c3ad52a29c55c2098b0ed1a855`; decoded comparison reports 0 changed pixels at 1280×720. A second default 18:00 capture after the stdout shadow-projection clamp fix has the same PNG hash as the original matrix (`4718f02db9b3c25790dd52a7a002e7e8d96056ae31304d1425265f7c1f4f8ad5`). Its sidecar differs only in the recorded `res://main.gd` source hash. The [post-fix one-case summary](../../../../research/time-of-day/tod-07/evidence/post-diagnostic-fix/summary.json) omits the legacy comparison case, so its legacy-comparison flag is not a test result.

The recorded directional-light energy is 0 at midnight and 1.15 at noon. A metadata-projected aircraft context patch has mean Rec.709 code luma 0.123–0.125 at midnight and 185.75–186.73 at noon (0–255 scale). At noon it differs from an adjacent same-height background patch by only 0.9–1.8 code values. Each patch includes surrounding pixels and is not a model mask, so these values do not measure silhouette visibility. With scenery enabled, the night capture reports 140 visible draw calls / 238,459 primitives and the noon capture 154 / 239,163; those are diagnostic counts from llvmpipe only. The Sun-centered 18:00 capture places the projected Sun center 5.3 px from frame center.

## Cloud and horizon control

The [probe](../../../../research/time-of-day/tod-07/probe_cloud_occlusion.gd) instantiates the production `Atmosphere.environment` and `render/sky.gdshader`. It holds zenith, haze, cloud color/seed/scale, cirrus parameters, exposure, Sun direction and offset fixed, then compares `sun_lin` on/off at cloud coverage 0 and 1. `sun_scatter` is set to zero in each pair to isolate the visible disc/halo term. The [analysis](../../../../research/time-of-day/tod-07/evidence/cloud-occlusion/analysis.json) compares a centered 41×41 pixel patch in the 1280×720 sRGB output:

| Control | Mean `sun_lin` on-minus-off Rec.709 code luma |
| --- | ---: |
| Clear (`cloud_coverage=0`) | 85.8537 |
| Full coverage (`cloud_coverage=1`) | 0.00514 |
| Full / clear solar delta | 0.0000598 (99.994% lower) |
| Below-horizon control | 0.0000; max RGB change 0 |

The high Sun is at 12:00 with geometric elevation 88.1334° and direct energy 1.15. For the horizon control, the geometric elevation is −5.6540° and the apparent disc is at −5.0873° (18:30). The shader receives the nonzero high-Sun `sun_lin` deliberately in this control even though the selected below-horizon lighting has zero direct energy; the centered patch is unchanged because the shader clips solar output below the natural horizon. The full-coverage case is an extreme cloud input. Its near-white background is not a cloud realism judgment. Code luma and its on/off difference are image-space comparisons, not physical radiance.

The [probe output](../../../../research/time-of-day/tod-07/evidence/cloud-occlusion/probe.json), [checksum manifest](../../../../research/time-of-day/tod-07/evidence/cloud-occlusion/SHA256SUMS), six PNG controls and analysis preserve the capture values. Compare [clear](../../../../research/time-of-day/tod-07/evidence/cloud-occlusion/high-cloud-0-sun-on.png), [full coverage](../../../../research/time-of-day/tod-07/evidence/cloud-occlusion/high-cloud-1-sun-on.png) and [below-horizon](../../../../research/time-of-day/tod-07/evidence/cloud-occlusion/below-sun-sun-on.png) renders. The test passed its three checks: clear Sun contribution is present, full coverage reduces that difference by at least 99%, and the below-horizon control has zero RGB change.

## Reproduction and limits

Run the 16-case capture matrix from the repository root with:

```sh
python3 research/time-of-day/tod-07/run_capture_matrix.py \
  --project "$PWD/app" \
  --out-dir "$PWD/research/time-of-day/tod-07/evidence/reproduction-run" \
  --xdg-root /tmp/openrc-tod07-xdg-reproduction \
  --run
```

Run the bounded cloud/horizon control and image analysis with:

```sh
mkdir -p /tmp/openrc-tod07-cloud-xdg/{config,cache,data,state}
XDG_CONFIG_HOME=/tmp/openrc-tod07-cloud-xdg/config \
XDG_CACHE_HOME=/tmp/openrc-tod07-cloud-xdg/cache \
XDG_DATA_HOME=/tmp/openrc-tod07-cloud-xdg/data \
XDG_STATE_HOME=/tmp/openrc-tod07-cloud-xdg/state \
LP_NUM_THREADS=1 \
TOD07_CLOUD_OUT="$PWD/research/time-of-day/tod-07/evidence/cloud-occlusion" \
xvfb-run -a -s '-screen 0 1280x720x24' "$(app/get-godot.sh)" \
  --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-07/probe_cloud_occlusion.gd"
python3 research/time-of-day/tod-07/analyze_cloud_occlusion.py \
  research/time-of-day/tod-07/evidence/cloud-occlusion
```

The ROI numbers come from CPU readback of a software-rendered frame; they are neither physical radiance nor aircraft detection scores. No human readability session or supported-GPU run was performed. The English and Spanish 800×600 WeatherDialog screenshots are already preserved by [TOD-06](../TOD-06/README.md). Broader test, lint and export results are in [integration verification](verification.md).
