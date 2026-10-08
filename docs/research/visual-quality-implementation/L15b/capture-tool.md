# L15b · Deterministic tree-wind capture

Date: 2026-10-08. **Status: guarded software OpenGL capture passes; target-GPU and human visual acceptance remain pending.** Step prefix: **L**.

Run the checker from the repository root with the pinned Godot executable and the frozen pre-L15b app:

```sh
"$(app/tests/visual-env.sh)" tools/trees/check_wind.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l15b-wind \
  --baseline-app /path/to/pre-L15b/app
```

The output directory must be new or empty. `--smoke` limits the GPU run to one zoom view and one process; it checks plumbing, not full acceptance. The full run captures calm and wind at four cardinal azimuths, zoomed production trees, same-input/replay/disabled snapshots and 1,024-second wrap cases, plus a fixed-camera eight-frame time strip. The same-input and replay images are deterministic snapshots, not live application pause or restart tests. Candidate and baseline captures run in separate processes.

The checker verifies the exact production shader include through GPU color readback using production card-mesh vertices and exact-origin roots, and checks that readback against the saved probe PNG. It checks directional lean, root position, length preservation, displacement bounds, seeded phase variation, time advance, raw GPU clock wrap, the final 1/1024-second step, quadratic low-speed response and saturation. It also checks image hashes, repeatability, calm parity against baseline, a tree-only image mask, east/west motion between t=0 and t=1, each time-strip interval, and renderer counter parity. A copied-data self-test rejects a t=1 image substituted with a static t=0 image and a corrupted image hash.

The 2026-10-08 guarded run passed on Godot 4.7.2 Compatibility / Mesa llvmpipe: 104 candidate images were byte-identical across two processes; all eight calm views were byte-identical to the frozen baseline. The GPU probe read 201 samples, with a maximum production-card displacement of 0.288367 m and six final-clock-step deltas no larger than 0.000220 m. All 16 east/west t=0→t=1 view pairs changed inside the tree mask, and all seven time-strip intervals changed only inside that mask. Tree wind changed no renderer counters; the existing tree contribution used 1–4 draws and no shadow draws. Source guards and copied-data checker self-tests passed.

`capture-summary.json` records the full roster, source hashes before and after each run, GPU probe measurements, parity, repeatability, and limitations. Software OpenGL results do not establish target-GPU frame time or subjective motion quality; see the L15b evidence record for those acceptance limits.
