# Mac graphics-option ladder (DT-MAC-03b)

Measures how a Mac responds to each player graphics option in the **real app route** (Home → Fly) on its real
display. It complements the direct-route [sustained fixture](../README.md#repeatable-active-flight-dt-mac-03),
which cannot apply the player's saved shadow, lens, bird, flag or meadow settings, and GOD TEST, whose runner
refuses macOS. The [Apple plan](../../../docs/plans/apple-silicon-performance.md#dt-mac-03b--attribution-and-baseline-soak)
owns acceptance; results live in the dated
[DT-MAC-03b evidence](../../../docs/research/desktop-delivery-investigations/DT-MAC-03b/README.md).

| File | Role |
| --- | --- |
| `ladder.py` | Orchestrator. Per run: seeds `user://settings.cfg.display` (the file AppRoot reads), launches the app through `tools/debug/debugctl.py`, checks the saved and effective settings, measures Home, flies, measures two-lap windows, dives at the pilot station and measures the crash. |
| `circle_pilot.py` | Closed-loop pilot over the bridge's `state`/`sticks`: a clockwise orbit of 90 m radius centred 68 m north of the pilot, at 40 m, passing over the clubhouse (one lap ≈ 24 s); then a guided dive at the pilot station. The stick is a rate command, so a fixed deflection rolls the aircraft over. |
| `make_plan.py` | Writes the 139-run plan: cumulative ladder L00 (every option at minimum) to L15 (everything at maximum on Forward+) in five passes of alternating direction, a reference run every ten runs, a resolution/MetalFX/renderer sweep, VSync, landscape, night and two soaks. Pass 5 is appended after the soaks, so the first 101 run indices match the original four-pass plan. |
| `analyze.py` | Per-config headline values, per-segment values, REF-normalised fps, ascending-minus-descending gap, step deltas paired within each pass with a 95 % interval, crash results and reference drift, as JSON and Markdown. Host changes during a campaign go in `<runs>/conditions.json` as `segments` (`name`, `from_run`, `note`), a `primary` segment for the headline values and the `normalize` segments pooled by scaling each to the primary segment's REF mean; the module docstring has the format. |

## Run

Prepare a task workspace as in the [M1 guide](../../../docs/tools/macos-m1.md): a verified source snapshot in
`<work>/src` with a checked import, the engine path in `<work>/engine-path.txt` and the
[host-state helper](../../../tools/godot/README.md#optional-macos-host-state-companion-dt-mac-02e) built at
`<work>/host-build/host-state`. **Rename `config/name` in the snapshot's `app/project.godot`**: macOS keeps
`user://` under `~/Library/Application Support/Godot/app_userdata/<name>`, and `ladder.py` refuses the
player's `OpenRC Simulator` profile. Copy this folder to `<work>/ladder/`, then, logged in at the Mac's
unlocked desktop with the display awake:

```sh
python3 ladder/make_plan.py plan.json plan-smoke.json
nohup /usr/bin/caffeinate -dis /usr/bin/python3 ladder/ladder.py --work "$PWD" --plan plan-smoke.json --out smoke &
nohup /usr/bin/caffeinate -dis /usr/bin/python3 ladder/ladder.py --work "$PWD" --plan plan.json --out runs &
python3 ladder/analyze.py runs plan.json summary
```

`--out` resumes: completed runs are skipped and a failed run's folder is kept with a `.failed-<time>` suffix.
Between runs the orchestrator idles at least `--cooldown` seconds (45) and then waits up to `--thermal-wait`
(240) for macOS thermal state `nominal`. Each run folder holds `result.json`, the seeded settings,
`pilot.csv`, `host-state.jsonl`, the engine and bridge logs and, when requested, `clubhouse.jpg` and
`crash.jpg`. Keep these outside Git.

## Metrics and limits

- Frame times are copied from the bridge's raw frame ring every 3 s, so a window is never truncated by its
  7,200-frame capacity; percentiles and the 1 % low use the bridge's definitions. Each window starts at the
  orbit's west point and lasts exactly two laps, so every configuration renders the same views.
- GPU utilisation is the AGX `PerformanceStatistics` from `ioreg` (no root; it includes WindowServer), sampled
  every 2 s; CPU is the difference of the game's CPU time over the window (100 % = one core). Metal's
  per-viewport GPU timers undercount on Apple's tile GPU, so the windows run with the bridge's GPU timing
  off and compare wall time and utilisation instead.
- The pilot adds about 24 bridge requests per second (~0.1 ms each) to every configuration.
- Uncapped runs (VSync off) measure render throughput, not what a 60 Hz display shows; the VSync runs
  measure the 60 Hz experience. A cumulative step's delta is the marginal cost on top of the earlier
  steps, not the option's standalone cost. Neither is a sustained product qualification, and a run on one
  Mac qualifies only that Mac and display.
- The crash includes first-use shader compilation the first time a configuration crashes, and its
  impact point varies by a few metres. Thermal state is macOS `ProcessInfo.thermalState`: coarse, and it
  does not report clock speed. On a fanless MacBook Air it stays `fair` while the GPU throttles, so a heat-soaked
  run can lose a quarter of its frame rate without a state change. Cool the Mac externally to measure option
  cost; measure fanless separately for the sustained player experience, and record any change in
  `conditions.json`.
- Disconnect remote-desktop viewers before a campaign. An attached RustDesk session cost the M1 8 % of its
  frame rate (`pmset -g log` shows its assertions); the REF runs are what expose such a change.
- The effective-setting check compares MSAA, size, VSync and renderer, not the scaling mode: confirm that a
  requested reconstruction is available (MetalFX Temporal is trial-gated and Forward+-only).
