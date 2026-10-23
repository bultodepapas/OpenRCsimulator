# VQ-01c: runtime stability and presentation follow-up

2026-10-23, baseline `fa679fc1725d85f05a59f34773230e2b83de6cce`.
Windows, Ryzen 9 5900X, RTX 3090 / driver 617.42, official Godot 4.7.2,
Compatibility renderer, native fullscreen 1920×1080, 60 Hz VSync, no extra FPS cap.
This is bounded engineering evidence, not hardware or flight-model qualification.

## Changes and observed results

- `main.gd`, `ground_gear.gd`, `timber_visual_motion.gd`: held sessions present
  the latest accepted tick instead of the still-changing engine interpolation fraction.
  A native Avanti chase-view probe sampled 120 rendered frames while paused:
  position span **0.1654 m before, 0 m after**; simulation bytes/tick stayed unchanged
  within each run. Pause-entry ticks differed; this is a freeze check, not exact replay.
- `app_root.gd`: validate/create the flight before detaching Home or the Natural
  Random briefing. A null factory previously caused script errors and removed the
  usable screen. Current tests preserve Home/briefing, show the error and permit retry.
- `airfield_lighting.gd`: skip redundant zero-output fixture writes when exposure
  changes in daylight. Preserve regional updates, snapshots and invalidation on
  rebind/profile/activation. Five alternating batches of 5,000 calls measured median
  **9.93 → 1.76 μs/call**; 22 exact exposed-state parity cases passed.
  This is CPU method cost, not GPU time or an FPS improvement.

## Native pacing screen

Same Avanti half-power start, pilot camera, normal keyboard input path, 10 seconds
warmup and 60 seconds measured; diagnostics/RSS sampling disabled for both runs.
Each completed 3,600 frames, remained focused/unpaused/uncrashed, and advanced
14,396 measured physics ticks. No physics, shader, quality setting or asset was changed.

| Metric | Before | After |
| --- | ---: | ---: |
| Mean FPS | 59.9996 | 59.9999 |
| p50 frame, ms | 16.653 | 16.656 |
| p95 frame, ms | 17.802 | 17.740 |
| p99 frame, ms | 18.914 | 18.735 |
| Maximum frame, ms | 22.449 | 23.384 |

One matched pair shows no gross pacing regression. The small differences do not
establish a gain, causality or completion of the multi-run performance gate.

## Verification and limits

Checked passes: crash/pause presentation **281**, Home preview/failure **25**,
Natural Random lifecycle/failure **30**, gear flex **27**, wheel contacts **100**,
P-51 lights **13**, lighting **73**, twilight **394**, and **4 golden flights**.
The real-app fixed-step input tape at 30/60/144 render FPS retains the baseline
state and full checkpoint hashes (480 ticks); no goldens were re-recorded.
Native engine-parsed keyboard QA passed **30** assertions on Stik/Timber controls,
cameras, restart, pause/settings, End and aircraft switching. This is not human
piloting or OS-to-display latency measurement.
The native Settings integration suite also passed live FPS/MSAA preview, Revert,
Keep and nested-menu hold checks using isolated preferences.

Five baseline Home/Fly cycles took **1.67–4.12 s** to first draw. Resource/node
counts were stable across that bounded run; it does not establish leak freedom.
Companion stress testing was refused by a pre-existing solver qualification mismatch:
current/HEAD normalized solver `96ee1e49…` versus profile `29ac7fe9…`.
Admission remains intact and the unverified companion presentation experiment was
reverted. Companion rendering still uses the changing interpolation fraction while
frozen; that separate pause defect needs verification after qualification is restored.
Full-suite, long-session, export, other-platform, high-resolution and
physical display/input-latency qualification remain open.

[Receipt](receipt.json) retains commands, raw-artifact/log hashes, changed runtime
source identities and numeric results. Full raw arrays/logs and temporary probes
remain under `tmp/game-engineering-20261023/`; no images were added to Git.
Use the [existing measurement tools](../../../../../research/performance/README.md)
for future qualification. Independent regression and evidence reviews accepted
the narrow claims and rejected a whole-game speedup claim.
Good Enemy independently passed the 281 crash/pause, 73 lighting, 25 preview and
30 Natural Random checks, found no blocking objection, and retained the companion
pause defect above as an explicit residual.
