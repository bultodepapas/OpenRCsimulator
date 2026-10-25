# GDU-03: native GPU correctness and ReflectionProbe lifetime

2026-10-25, Windows x86-64, RTX 3090, official Godot
`4.8.beta1.official.4d10419ca`. The nine existing color/shadow oracle runs pass
with zero engine errors or warnings. The existing ReflectionProbe lifetime
controls still reproduce the pinned-engine leak.

| Existing GPU oracle | Profiles | Result |
| --- | --- | --- |
| Ridge color | Standard, High | 11 cases each pass the independent-reference and 3.5/255 gates |
| Shadow energy | High | All three unoccluded panels resolve; shadow on/off maximum RGB difference is zero, within 2/255 |
| Pilot-station color | Standard, High | Nine cases each pass; resolved reference anchors and zero RGB difference |
| Barrier/shelter material tags | Standard, High | 15 cases each pass; resolved reference anchors and zero RGB difference |
| Lily leaf/flower color | Standard, High | Eight cases each pass; resolved reference anchors and zero RGB difference |

The 86 color cases retain their existing tolerances. No `--capture-only` route
was used. The pilot-station, material-tag and lily probes render fixed 1920×1080
SubViewports. Ridge retains its 800×800 diagnostic viewport and shadow energy
its 512×256 viewport. All root launches requested 1920×1080 fullscreen to avoid
Windows' decorated-window clamp; these tests do not report the root drawable
size, so the root resolution is not separately claimed as measured.

## Stock ReflectionProbe leak remains

The unchanged [minimal fixtures](../../../../visual-quality-implementation/VQ-07/planar-lake-2026-10-22/engine-lifetime/)
build a procedural sky, camera and box, draw 40 frames, free their world and wait
ten frames before exit. Their native Forward+/Vulkan results match the historical
4.7.2 pattern:

| Existing lifetime control | Leaked Texture RIDs | Checked verdict |
| --- | ---: | --- |
| Root world, no probe | 0 | Pass |
| Root world, probe | 7 | Fail: warning |
| One isolated world, probe | 7 | Fail: warning |
| Four isolated worlds, probe | 28 | Fail: warning |
| Four isolated worlds, no probe | 0 | Pass |
| Four isolated worlds, explicit UPDATE_ONCE probe | 28 | Fail: warning |

All six controls reach their required completion markers with zero engine
errors. The four leak warnings remain checked failures; warnings were neither
suppressed nor reclassified as passes. Their diagnostics report
`rendering_device.cpp:9156`. This is resource-lifetime evidence, not a measured
per-frame or real Home/Fly leak rate. No app workaround or engine patch was made.

## Reproduction and retained evidence

The existing [graphics tool guide](../../../../../../tools/graphics/README.md#focused-verification)
owns the commands and independent-reference gates. Runs used its `launch.py`
from the frozen `D:/OpenRCsimulator-experiments/gdu03-suite` tree, the explicit
official 4.8 console executable, `--fullscreen --resolution 1920x1080`, Dummy
audio and `tools/godot/run_checked.py` with warnings treated as errors. The
production shaders and literal code dependencies match current root bytes in
all 39 recorded files. TEMP, TMP, LOCALAPPDATA and APPDATA were isolated on D.

[Verification](verification.json) retains all seven JSON oracle reports, the two
ridge log verdicts through checked receipts, exact commands, source/engine/log
hashes and all six lifetime verdicts. [Source identities](source-manifest.json)
identify the frozen inputs. Raw reports, PNGs and checked logs remain outside
Git at `D:/OpenRCsimulator-experiments/gdu03-gpu-correctness-20261025/`.

Native runs were sequential and the GPU reservation has been released. Other
headless suites were active; these checks make no quiet-host performance,
full-flight visual quality or general lifecycle qualification claim.
