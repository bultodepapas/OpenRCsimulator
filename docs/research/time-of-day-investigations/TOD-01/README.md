# TOD-01: Compatibility sky and radiance probe

2026-10-10 · **Status: rendered Compatibility experiment complete; no production renderer changes.**

Owning plan: [TIME-OF-DAY-PLAN](../../../TIME-OF-DAY-PLAN.md). The probe compares the pinned production sky's QUALITY, INCREMENTAL and REALTIME radiance update modes, and records the existing app's default legacy capture before implementation.

## Result

The initial custom night environment is dark on its first completed frame when the selected sun, sky, haze, cloud, scatter and fog values are zeroed before the environment enters the rendered tree. The measured maximum RGB channel across sky, matte and metallic probe regions is `0.0005082`, below the probe threshold of `1/255 = 0.0039216`; the matte and specular regions measure zero. This verifies initialization and renderer behavior, not a calibrated night sky.

| Radiance mode | Day → night settles | First-frame distance to dark target | Night → day settles | Day → night frame interval, ms (p50 / p95 / p99 / worst) |
| --- | ---: | ---: | ---: | ---: |
| QUALITY | 1 | 0.000000 | 1 | 109.481 / 127.785 / 178.446 / 178.446 |
| INCREMENTAL | 6 | 0.815774 | 6 | 103.110 / 112.614 / 170.302 / 170.302 |
| REALTIME | 1 | 0.000000 | 1 | 102.053 / 109.346 / 153.744 / 153.744 |

Settle means the first frame of eight consecutive samples whose largest absolute RGB-channel difference from the same-renderer target was at most `1/255`, across the sky, rough white matte sphere and roughness-0.08 metallic sphere patches. INCREMENTAL leaves measurable daylight in the diffuse/specular probe on frame 1 in both directions; the displayed transition converges at frame 6. QUALITY and REALTIME match the target on the first sampled transition frame. Cloud uniforms were advanced once through the production `Atmosphere.update_clouds` path at its configured one-second cadence in each mode.

The production default capture is retained as a visual baseline at [legacy-production.png](../../../../research/time-of-day/tod-01/evidence/legacy-production.png), with its [capture metadata](../../../../research/time-of-day/tod-01/evidence/legacy-production.json) and [engine log](../../../../research/time-of-day/tod-01/evidence/legacy-production.log). It is the existing `--scripted --capture` route at 1.5 seconds on the default aircraft, before any renderer edits. The per-frame [CSV](../../../../research/time-of-day/tod-01/evidence/modes/frame-metrics.csv) contains patch RGB means, target distances, draw calls and primitive counts for 457 samples. The [probe script](../../../../research/time-of-day/tod-01/probe.gd), [summary JSON](../../../../research/time-of-day/tod-01/evidence/modes/summary.json), selected frame images and [SHA-256 manifest](../../../../research/time-of-day/tod-01/evidence/SHA256SUMS) preserve the full run.

## Reproduction and limits

Source baseline: commit `7fe3d84f869172df5992c7602ddd40f045a0c044`, captured 2026-10-10. Engine: Godot `4.7.2-stable.official.ed1daf0bf`, archive SHA-512 `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`. Renderer: `gl_compatibility`, OpenGL 4.5 Core Profile, Mesa 25.2.8 and llvmpipe (LLVM 20.1.2, 256 bits), under Xvfb with one llvmpipe thread. This is software rendering; the timings are not target-hardware performance evidence.

Run from the repository root (the two runs use an isolated user-data root):

```sh
mkdir -p /tmp/tod01-xdg/{config,cache,data,state}
XDG_CONFIG_HOME=/tmp/tod01-xdg/config XDG_CACHE_HOME=/tmp/tod01-xdg/cache XDG_DATA_HOME=/tmp/tod01-xdg/data XDG_STATE_HOME=/tmp/tod01-xdg/state LP_NUM_THREADS=1 \
  xvfb-run -a -s '-screen 0 1280x720x24' "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy -- \
  --scripted --capture --t=1.5 --autozoom=0 --out="$PWD/research/time-of-day/tod-01/evidence/legacy-production.png"
XDG_CONFIG_HOME=/tmp/tod01-xdg/config XDG_CACHE_HOME=/tmp/tod01-xdg/cache XDG_DATA_HOME=/tmp/tod01-xdg/data XDG_STATE_HOME=/tmp/tod01-xdg/state LP_NUM_THREADS=1 \
  xvfb-run -a -s '-screen 0 1280x720x24' "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-01/probe.gd" -- --out-dir="$PWD/research/time-of-day/tod-01/evidence/modes"
```

The probe sampled rendered images through CPU readback every frame, wrote CSV telemetry and saved selected PNGs. Its frame intervals therefore include screenshot readback and file output; they cannot isolate radiance-update cost. The short 60-frame transitions establish correctness and relative settling behavior only on this software adapter. The run logged the Xvfb driver's unsupported V-sync warning. The legacy capture also emitted the existing aircraft-data warning for `Jyy`; neither run logged a script or shader error. The legacy metadata and stdout differ slightly in reported draw/primitive counters, so use the captured image/hash as the baseline and treat those counters as diagnostic only.

TOD-01 supports keeping a fixed-time initial lighting snapshot fully assigned before the environment is first rendered or field objects are built. It supports QUALITY as the conservative first implementation path pending target-GPU evidence; REALTIME also passed this probe, but its radiance quality was not comparatively reviewed. Do not expose INCREMENTAL updates as complete until stale ambient/reflection lighting has converged, or prepare the replacement environment before exposing it. No production script, project setting, asset, physics value or dependency changed for this experiment, and `app/test.sh` was not run by this research task.
