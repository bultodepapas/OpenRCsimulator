# DT-11a — remove repeated clamping in the fallback shadow blur

2026-10-14. `Shadow._blur()` now calculates row offsets once per row and left/right
indices once per pixel. The nine taps are explicit and retain the original
row-major addition order, float32 output and division. This removes the two inner
loops and repeated clamping without changing the two-pass box filter. There is
no cache, generated asset, shader, simulation or per-frame update change.

`Shadow.create()` still creates the generic height-cue mask before a model-derived
shadow is bound, and retains it for fallback. Earlier loading attribution found
roughly 25 ms in carrier creation. The [preceding geometry repair](../shadow-geometry/README.md)
targets binding; this slice targets mask/carrier creation separately.

## Measurements and output

Five fresh native processes, ten alternating reference/candidate pairs per
workload in each process, reversing the initial order between processes. Windows,
Godot 4.7.2 `ed1daf0bf`, Compatibility, RTX 3090 / NVIDIA 610.88, Ryzen 9 5900X.
The shared host was not idle or power/clock controlled. These are synchronous
constructor timings; texture readback and equality checks are outside timing.

| Workload | Original median | Adopted median | Reduction |
| --- | ---: | ---: | ---: |
| Mask generation, pairs 1–9 | 34.373 ms | 15.175 ms | 55.9% |
| Complete carrier creation, pairs 1–9 | 34.835 ms | 17.271 ms | 50.4% |
| First mask call per variant/process | 34.098 ms | 17.109 ms | 49.8% |

Warm rows pool 45 samples per variant. All five per-process warm medians improve
for both workloads; [summary.json](summary.json) retains those values. First mask
calls exclude process/script loading and do not represent cold Home startup.
The first carrier call occurs after mask probes and is retained separately in
raw data; it is not described as a process-cold carrier.

All **100 native pairs** preserve complete RGBA8 image bytes, all seven mip levels,
format and dimensions. Carrier pairs also preserve plane arrays, transform,
shadow flag and the configured material values. Every call still creates its
own image, texture, material and mesh. No memory-retention tradeoff is introduced.

This comparison uses the current collector/shaders/spec from the working tree,
with their hashes checked before and after timing. The two external shadow
scripts differ only in `_blur()`. The [source manifest](source-before.json) pins
the starting HEAD and relevant dependencies; retained source copies allow this
targeted comparison to be reconstructed without treating the entire shared tree
as a clean checkout.

## Checks and limitations

The new test passes **50 assertions** headless and with the native renderer:
13 inputs (zero, constant, nine impulses, signed seeded samples and mixed
magnitudes), complete float32 parity for two passes, source-array isolation,
explicit corner/edge weights, image/mip identity and independent carrier
materials/textures. Texture edits and opacity changes cannot affect another
carrier or a later construction.

Integrated focused checks pass **143 headless assertions** (blur 50, projected
shadow 37, presentation 17, field integration 39) and **87 native assertions**
(blur 50, projected shadow 37), without engine errors or warnings. Draft checks
are retained separately and are not added to these totals.

A disposable mutation substituting the current row for the previous row fails
24 assertions. The first mutation runner incorrectly expected the top-left corner
weight to fail, although clamping leaves that point unchanged; its report is
retained. The corrected runner requires the actual adjacent-edge failure and all
24 expected failures. No production file was mutated for this check.

This measures mask and carrier construction, **not FPS, GPU frame time, complete
Home/Fly loading or package acceptance**. Full CI, exports, foreground loading,
visual flight coverage, soak and native Linux/macOS qualification remain open.
No goldens changed. The renderer still supplies the same fallback and bound
shadow behavior.

## Reproduce and continue

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_shadow_blur.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_projected_shadow.gd
```

Omit `--headless` for native checks. `app/test.sh` discovers the new test. For
paired timing, decompress `reference.gd.gz`, `candidate.gd.gz` and `probe.gd.gz`
outside `app/`, use identical pinned dependencies, and run the probe natively
with `-- --directory=<scripts> --output=<new.json>`. Optional `--reverse` swaps
the initial order. [Evidence manifest](evidence-manifest.json) hashes sources,
commands, raw reports, checks and the runtime patch.

Continue the [global plan](../../../../../plans/global-performance-visual-quality.md):
attribute remaining initial Home/first-Fly work on a consistent current snapshot
and reserve foreground host time for loading and pacing acceptance. These small
construction gains must not be summed into an unmeasured total startup gain.
