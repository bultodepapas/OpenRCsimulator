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
Admission remains intact and the first-round companion presentation experiment was
reverted. The separate companion pause defect was subsequently reproduced and
fixed in the bounded render-method fixture described below; admitted AI flight
remains unverified.
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

## Second engineering pass

Baseline `06deedf99dd2cb24e485788670f3bb1b7d365655`, same native hardware and
1080p target. No simulation equations, aircraft data, shaders or quality settings
were changed.

- `main.gd`: skip reapplying an unchanged initial fuel fill. The setter invalidated
  the trim cache even at the existing full-tank value, so the final reset repeated
  an identical 14-step Extra cruise-trim search costing **7.33–7.86 s**. Two measured
  instrumented Home/Fly launches took **18.399 / 16.845 s before**, **9.078 / 8.775 s
  after**. Fully configured tick-zero snapshots and complete tick-480 checkpoints
  were byte-identical across all four launches with the same input sequence.
  This avoids repeated work; it does not simplify the trim solver.
- `ai/companions/agent.gd`: frozen, paused, crashed or failed companions render
  the accepted pose. The baseline fails five pose assertions; the candidate passes
  24 headless and 25 native checks, including active interpolation and unchanged
  simulation bytes. This exercises the real session and model builder directly;
  it does not bypass or establish companion qualification.
- `render/landscape_upgrade/ridges.gd`: retain four immutable CPU geometry buffers;
  each world still creates its own mesh and lighting material. Seven alternating
  native batches measured warm construction **40.747 → 0.926 ms**. First process-local
  construction remained **44.297 / 44.069 ms**. Exact mesh-data parity, independent
  resource ownership and profile-reload invalidation passed. Serialized cached
  buffers total 675,468 bytes; this is not an RSS measurement.

A four-process ABBA comparison of the unchanged Home/Fly probe found no consistent
Fly loading gain from the ridge cache: pooled warm ready medians **1,659.951 /
1,675.721 ms**, first draw **1,776.433 / 1,782.847 ms** (four observations per variant).
Home return medians were **899.915 / 869.342 ms**. The approximately 31 ms reduction
is consistent with the isolated construction result but does not establish causality.

Native P-51 night and Extra daytime QA exercised keyboard controls, cameras,
restart, pause/settings, End, aircraft switching, smoke, lights and engine start/cut.
These captures show ground interaction, not airborne flight. A later open-loop
Extra flight crashed after 4.84 seconds; its paused frame samples are excluded from
performance evidence. A cyan band in the night horizon remains unattributed.

The Avanti half-power/pilot-camera flight completed at native 1080p with ordinary
keyboard input enabled. An initial candidate sample measured 56.654 FPS / 32.766 ms
p99. A subsequent fresh-process ABBA comparison used 10 seconds warmup and 60
seconds measurement per run, with no resource sampler:

| Run | Mean FPS | p95, ms | p99, ms | Max, ms |
| --- | ---: | ---: | ---: | ---: |
| Baseline A1 | 59.984 | 17.700 | 18.568 | 39.047 |
| Candidate B2 | 57.928 | 21.435 | 30.153 | 40.702 |
| Candidate B3 | 59.983 | 17.743 | 18.895 | 38.375 |
| Baseline A4 | 55.666 | 27.089 | 40.687 | 52.859 |

All four ended focused, unpaused and uncrashed, with physics active and no engine
diagnostics. Both versions showed substantial run-to-run variability; the cause
is unresolved. These refresh-capped samples establish neither an FPS improvement
nor a candidate-specific pacing regression, and do not qualify sustained smoothness.
All adverse samples are retained.

Independent focused verification passed all 14 checked invocations: import,
four golden flights, companion rendering (24 headless checks), ridge caching (13),
horizon (48), fuel (67), trim selection (47), runway starts (18), start choice (36),
atmosphere flight (142), seven weather CLI tests, and fixed-step input runs at
30/60/144 render FPS. Those three 480-tick runs retain the previous state hash
`16156a30…7d857` and complete checkpoint hash `5593cdb7…72143`.
The Extra and Avanti startup pairs additionally retain exact complete checkpoint
bytes at ticks zero and 480; partial fuel still invokes the setter and a changed trim.
A corrected hot-high startup asserted the accepted custom atmosphere (1,500 m,
35°C) and performed the required changed trim on reset, with no engine diagnostics.
The canonical Linux `app/test.sh` and `app/capture.sh` launches failed before Bash/Godot with
`Wsl/Service/CreateInstance/E_FAIL`; this is an environment limitation, not a full
test-suite result. The native focused tests above remain separate evidence.
Good Enemy found no blocking correctness or visual-quality objection and independently
reran companion rendering at native 1080p: 25 checks passed without engine diagnostics.
Its receipt-inventory omission was corrected by including that checked run. It retained
the inconclusive pacing, unqualified companion admission and unavailable Linux-suite
coverage as limitations; this is not a whole-game performance qualification.

[Second-pass receipt](round2-receipt.json) records source identities, exact commands,
decoded checkpoint hashes, individual timings and raw artifact/log hashes.
Raw probes and captures remain under `tmp/game-engineering-round2/`; no images
were added to Git. Early scratch-probe failures and the first weather probe (which
changed only Home's display value) are excluded from successful validation claims.

Applicable engine references: [Godot 4.7 renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html),
[GPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html),
and [4.7.2 GLES3 implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp).
Compatibility-renderer observations on this GPU do not qualify other backends or hardware.
