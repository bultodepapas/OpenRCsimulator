# Graphics-option ladder (macOS and Windows)

Measures how one computer responds to each player graphics option in the **real app route** (Home → Fly) on
its real display. It complements the direct-route [sustained fixture](../README.md#repeatable-active-flight-dt-mac-03),
which cannot apply the player's saved shadow, lens, bird, flag or meadow settings, and the scripted
[per-setting GPU costs](../../../docs/research/visual-quality-implementation/VQ-07/knob-costs-2026-11-18/README.md),
which time one view rather than flight. Evidence:
[M1, DT-MAC-03b](../../../docs/research/desktop-delivery-investigations/DT-MAC-03b/README.md) (owned by the
[Apple plan](../../../docs/plans/apple-silicon-performance.md#dt-mac-03b--attribution-and-baseline-soak)) and
[RTX 3090 at 4K, VQ-07h](../../../docs/research/visual-quality-implementation/VQ-07/graphics-ladder-2026-11-19/README.md)
(owned by the [automatic graphics plan](../../../docs/plans/automatic-graphics.md)).

| File | Role |
| --- | --- |
| `ladder.py` | Orchestrator. Per run: seeds `user://settings.cfg.display` (the file AppRoot reads), launches the app through `tools/debug/debugctl.py`, checks the saved and effective settings and the host identity, measures Home, flies, measures two-lap windows, dives at the pilot station and measures the crash. A config's `app_dir` launches a sibling snapshot copy with the same project name (same `user://` and caches), for example one without `app/native`. |
| `circle_pilot.py` | Closed-loop pilot over the bridge's `state`/`sticks`: a clockwise orbit of 90 m radius centred 68 m north of the pilot, at 40 m, passing over the clubhouse (one lap ≈ 24 s); then a guided dive at the pilot station. The stick is a rate command, so a fixed deflection rolls the aircraft over. |
| `make_plan.py` | `make_plan.py plan.json smoke.json` writes the 139-run Mac plan (1080p ladder L00 → L15 in five alternating passes, a MetalFX/resolution/renderer sweep, VSync, landscape, night, two soaks). `make_plan.py --windows plan.json smoke.json` writes the 138-run Windows plan (4K ladder L00 → L14 in four passes, renderer/API matrix, windowed 1080p/1440p, FSR2, VSync and frame caps, GDScript-physics controls, landscape, night, one soak). A REF run (L09) repeats every ten runs. |
| `analyze.py` | Per-config headline values, per-segment values, REF-normalised fps, ascending-minus-descending gap, step deltas paired within each pass with a 95 % interval, crash results and reference drift, as JSON and Markdown. Host changes during a campaign go in `<runs>/conditions.json` as `segments` (`name`, `from_run`, `note`), a `primary` segment for the headline values and the `normalize` segments pooled by scaling each to the primary segment's REF mean; the module docstring has the format. |

## Prepare a snapshot

Use a frozen source snapshot in `<work>/src` with a checked import and the engine path in
`<work>/engine-path.txt`. **Rename `config/name` in the snapshot's `app/project.godot`** so its `user://` is not
the player's profile; `ladder.py` refuses `OpenRC Simulator`. The snapshot needs `app/`, `tools/`, `assets/`
(aircraft model sources are read from the repository root) and `research/performance/`. Copy this folder to
`<work>/ladder/`.

- **macOS:** follow the [M1 guide](../../../docs/tools/macos-m1.md) and build the
  [host-state helper](../../../tools/godot/README.md#optional-macos-host-state-companion-dt-mac-02e) at
  `<work>/host-build/host-state`. `user://` lives under `~/Library/Application Support/Godot/app_userdata/<name>`.
- **Windows:** `user://` follows `--profile` (APPDATA, default `<work>/profile`). Keep it on the system drive, like a
  player's profile: the app does some `user://` file I/O on the main thread, and a profile on a USB flash drive
  turned a periodic controller-store lock into a 26 ms stall twice a second (VQ-07h). The local native kernel's receipt hashes the
  main working tree's exact bytes, which mix CRLF and LF there; a fresh checkout with either line-ending setting
  silently runs the GDScript reference physics. Copy the tracked `app/`, `assets/` and `AGENTS.md` bytes from the
  main tree into the snapshot, copy `app/native/`, and confirm `physics_backend` reads `native` in the smoke results.
  Set `OPENRC_TESTQUEUE_ROOT` to an empty directory so the launch is local; the orchestrator refuses an enrolled
  host. It needs `psutil` and `nvidia-smi` (NVIDIA only).

## Run

```sh
# macOS, logged in at the unlocked desktop with the display awake
python3 ladder/make_plan.py plan.json plan-smoke.json
nohup /usr/bin/caffeinate -dis /usr/bin/python3 ladder/ladder.py --work "$PWD" --plan plan-smoke.json --out smoke &
nohup /usr/bin/caffeinate -dis /usr/bin/python3 ladder/ladder.py --work "$PWD" --plan plan.json --out runs &
python3 ladder/analyze.py runs plan.json summary
```

```powershell
# Windows, at the unlocked desktop; the orchestrator keeps the display awake
python ladder/make_plan.py --windows plan.json plan-smoke.json
$env:OPENRC_TESTQUEUE_ROOT = 'U:\OpenRC\testqueue'   # an unenrolled directory
$ladderProfile = "$env:APPDATA\OpenRC-ladder-profile"   # user:// on the system drive
python ladder/ladder.py --work <work> --profile $ladderProfile --plan plan-smoke.json --out smoke --cooldown 10 `
  --thermal-wait 60 --expect-screen "(3840, 2160)" --expect-refresh 120
python ladder/ladder.py --work <work> --profile $ladderProfile --plan plan.json --out runs --cooldown 10 `
  --thermal-wait 60 --expect-screen "(3840, 2160)" --expect-refresh 120
python ladder/analyze.py runs plan.json summary
```

`--out` resumes: completed runs are skipped and a failed run's folder is kept with a `.failed-<time>` suffix.
Between runs the orchestrator idles at least `--cooldown` seconds and then waits up to `--thermal-wait` for
macOS thermal state `nominal` or, on Windows, a GPU at or below 55 °C. On Windows it also checks the driver,
user dir, screen size and refresh rate of every launch, stops after `--max-failures` consecutive failures and
before a run when free disk falls below 5 GB on the work drive or 2 GB on `C:`. The smoke plan doubles as a
shader-cache warm-up; first-use compilation otherwise lands in the first pass. Each run folder holds
`result.json`, the seeded settings, `pilot.csv`, host state (`host-state.jsonl` on macOS, `gpu.jsonl` from
`nvidia-smi` on Windows), the engine and bridge logs and, when requested, `clubhouse.jpg` and `crash.jpg`.
Keep these outside Git.

## Metrics and limits

- Frame times are copied from the bridge's raw frame ring every 3 s, so a window is never truncated by its
  7,200-frame capacity; percentiles and the 1 % low use the bridge's definitions. Each window starts at the
  orbit's west point and lasts exactly two laps, so every configuration renders the same views.
- GPU utilisation is the AGX `PerformanceStatistics` from `ioreg` on macOS (no root; it includes WindowServer),
  sampled every 2 s, and `nvidia-smi` device utilisation, clocks, board power and temperature at 1 s on Windows.
  CPU is the difference of the game's CPU time over the window (100 % = one core); on Windows the busiest
  threads are listed too, and a thread near 100 % is the frame-rate limit. Metal's per-viewport GPU timers
  undercount on Apple's tile GPU, so Mac windows run with the bridge's GPU timing off.
- The pilot adds about 24 bridge requests per second (~0.1 ms each) to every configuration.
- Count long frames per second before comparing smoothness. A rate that is identical in every configuration is
  periodic work, not an option's cost: the Windows campaign's exactly 2.0 frames over 25 ms per second were the
  controller service's 0.5 s refresh. The bridge's `frames hitch_ms=15` records each with its `process_ms`.
- Uncapped runs (VSync off) measure render throughput, not what the display shows; the VSync and frame-cap
  runs measure that. A cumulative step's delta is the marginal cost on top of the earlier steps, not the
  option's standalone cost. Neither is a sustained product qualification, and a run on one computer qualifies
  only that computer and display.
- The crash includes first-use shader compilation the first time a configuration crashes, and its impact point
  varies by a few metres.
- Record host changes in `conditions.json`; the REF runs are what expose them. On a fanless MacBook Air,
  `thermalState` stays `fair` while the GPU loses up to a third of its throughput, and an attached RustDesk
  viewer cost the M1 8 %. Each run records competing engines and incoming remote-desktop sessions in
  `host_activity`.
- The effective-setting check compares MSAA, size, VSync and renderer, not the scaling mode: confirm that a
  requested reconstruction is available (MetalFX Temporal is trial-gated and Forward+-only; FSR2 needs
  Forward+ and turns MSAA off, which shows as an expected MSAA mismatch).
- Any app argument after `--` makes AppRoot start a direct flight instead of Home, so per-run app arguments
  cannot be combined with this route; use `app_dir` for variants.
