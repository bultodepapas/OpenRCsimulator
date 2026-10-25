# VQ-07d: optional FSR2 on the RTX 3090

2026-10-24. The owner requested FSR2 integration and identified an NVIDIA RTX 3090
as the only available test GPU. This is an optional High feature; Native remains
the default. [Operating instructions](../../../../../tools/graphics/README.md#fsr2-reconstruction-vq-07d),
[owning plan](../../../../plans/advanced-graphics.md#vq-07d-preserve-a-small-moving-aircraft),
and [source investigation](../../../advanced-graphics-2026-10-21/dlss-fsr-2026-10-24.md).

## Implemented boundary

- Stock Godot FSR2 in the main viewport, enabled only when the native High profile
  is actually active. No SDK, engine fork, GPU-brand whitelist or frame generation.
- Native, FSR2 Native AA (scale 1), and FSR2 Quality (scale 2/3). Quality is an
  explicitly requested experiment, not a newly qualified performance preset.
- Additive schema-1 display preference; older files default to Native. Keep/Revert,
  timeout, close, graphics defaults and relaunch use the existing settings transaction.
- FSR2 replaces main-view MSAA while active; Native/Standard restore the saved MSAA
  choice. UI and auxiliary viewports are not rescaled. The Standard settings screen
  explains when an FSR2 preference is stored but inactive.
- Direct launches can choose the candidate through `OPENRC_RECONSTRUCTION` without
  reading player preferences. Home uses saved preferences. Frame/capture metadata
  records the scaling mode; diagnostics retain requested/effective mode and scale at
  start and report time, including after observer shutdown.
- The graphics panel accommodates the added row; English and Spanish labels and
  accessible text-scale layouts were exercised. No simulation or aircraft-data edits.

## Verification scope

Host: Windows, NVIDIA GeForce RTX 3090 (24 GiB), driver 617.42, AMD Ryzen 9 5900X,
Godot 4.7.2-stable official `ed1daf0bf`, Vulkan 1.4.351 / Forward+.

The checked runner retained logs and receipts under ignored `tmp/fsr2-work/checks/`.
Tests run serially. No images or raw frame arrays are committed.

| Check | Result |
| --- | --- |
| Reconstruction policy, headless and native Forward+ | 14 checks each; native run exercises real FSR2 mode, scale, MSAA replacement and Standard fallback |
| Display preferences | 64 checks; legacy migration, allowed-mode round trips and malformed-mode rejection |
| Advanced graphics transaction | 63 headless checks; 80 native checks including EN/ES captures, timeout, kept preference and shell recreation |
| Settings integration | Passed; Home and paused-flight transactions retain their existing control/tick behavior |
| High restart contract | 42 checks; restart guards and preference rollback |
| Settings layout | Passed after accommodating the extra row; initial failure was retained locally rather than weakening the no-scroll assertion |
| Frame diagnostics | 25 checks; reconstruction identity survives observer shutdown; native frame receipt independently contains start/final identity |
| Final parse | Main flight script parsed through the checked runner after adding scaling-mode capture identity |

Final headless regression receipts are under `tmp/fsr2-work/final-checks/`, using an
isolated profile. The full app suite, full visual capture campaign and packaged
export tests were not run for this bounded optional integration.

Native UI captures initially used an actual drawable **1920×1061** window due to
desktop window limits; they are layout evidence, not 1080p qualification. A requested
1920×1080 size alone is not sufficient. Native diagnostics must confirm actual
1920×1080 output before being considered primary-resolution evidence.

The native runs printed `OpVectorExtractDynamic is not supported yet.` compiler
messages. The native baseline also prints them; they are not evidence of a new
FSR2-only regression. The first native frame collection emitted the already recorded
seven Texture-RID leak warning for High's stock ReflectionProbe. Keep this warning
visible; the [existing attribution](../planar-lake-2026-10-22/README.md#engine-lifetime-attribution-and-session-context-2026-10-22)
owns it. No engine fix is included here.

## Measurement exclusions and remaining gates

The first `native-1.json` collection completed at actual 1920×1080 but overlapped
another session's loading benchmark on this GPU. It is **excluded** from performance
comparisons. Other sessions were not stopped or modified. Software/native activation
checks do not establish an FPS gain.

Remaining qualification: matched uninterrupted GPU measurements, moving distant
aircraft/attitude recognition, camera-cut history, propeller/rotors, smoke, animated
vegetation, water and night scenes; pilot preference and input-to-display latency;
packaged exports; Linux/macOS and AMD/Intel or other NVIDIA hardware. Do not promote
High, lower the minimum GPU, or claim cross-vendor qualification from this one card.

## Follow-up: scale and sharpening options

2026-10-24, requested by the owner. Added custom 85%, AMD Balanced (1/1.7) and
Performance (1/2), alongside Native AA and Quality. Native remains the default.
RCAS strength is adjustable from 0–100% in 5% steps; 0 disables it. Initial 90%
preserves Godot's previous 0.2 setting rather than claiming a tuned optimum.
The same transaction covers mode and sharpening, including timeout, defaults,
Keep/Revert, file validation and shell recreation. The UI describes nominal input
dimensions; diagnostics retain these, strength/activation and additional mip bias.

[Further source research](../../../advanced-graphics-2026-10-21/dlss-fsr-2026-10-24.md#follow-up-practical-fsr2-controls-2026-10-24)
records exact engine mapping and limitations around camera cuts, transparency masks,
mip bias and dynamic scaling. No engine dependency changed.

Checked-runner evidence under ignored `tmp/fsr2-options/`:

| Check | Result |
| --- | --- |
| Reconstruction policy | 39 headless checks; scale/fallback, inverted sharpness, finite-value defense and receipt activation |
| Preferences | 79 checks; all modes and sharpening round trips, legacy defaults, malformed-value rejection |
| Native High transaction on RTX 3090 | Final 102 checks, zero failures; all modes switched with rendered frames, sharpening preview/timeout, persisted off state after shell recreation |
| Settings layout | Passed at logical 1920×1080, including default no-scroll and 200% accessibility checks |
| Settings integration / High restart | Passed; restart 42 checks; paused-flight tick and controls contracts retained |
| Frame diagnostics | Existing 25 checks passed with extended reconstruction metadata |

EN/ES native captures at 100%/200% are retained locally in `captures-final/`.
The 100% Spanish capture was visually inspected: the 85% selector and usable 35%
slider fit with actions visible. Actual window output is 1920×1061, so these remain
layout evidence. No images are committed.

The first native attempt exposed a tooltip reading its viewport during construction;
fixed by checking scene-tree membership and refreshing after layout. The same attempt
used fullscreen against a test expecting an initially windowed baseline; rerunning
with its intended startup mode restored the geometry checks. Initial logs remain.
An initially narrow slider was corrected to share the existing slider layout rules;
final checks assert a usable width. Shader compiler messages noted above persist.

### Short native GPU comparison

Same host/engine as above; High, actual 1920×1080 fullscreen, VSync off, uncapped,
scripted fixed view (`--scripted --look_az=0 --look_el=0`), default Ugly Stik,
5 seconds warm-up and 15 measured seconds per run. Native uses 4× MSAA; FSR2 owns
AA and uses 35% sharpening. This compares player-visible configurations, not an
isolated FSR dispatch. The launcher checked for another rendered Godot before each
run; no other rendered process was seen in intermediate inventories. The host was
not exclusively reserved. All four runtime source-hash maps match.

| Sequence / mode | Frames | GPU p50 / p95 (ms) | Whole-frame p50 / p95 (ms) |
| --- | ---: | ---: | ---: |
| 1. Native | 6,629 | 1.569 / 1.810 | 2.096 / 2.889 |
| 2. FSR2 85% | 6,509 | 1.382 / 1.616 | 2.256 / 3.240 |
| 3. FSR2 Quality | 7,944 | 1.102 / 1.329 | 1.711 / 2.793 |
| 4. Native repeat | 6,805 | 1.566 / 1.818 | 2.080 / 2.803 |

GPU percentiles use nearest rank over positive root-viewport samples; every measured
sample was positive. Whole-frame values come from the existing frame report/reducer.
All runs completed, had actual 1080p output and passed `frame_diagnose.py` validation;
no sampled frame exceeded 16.667 ms. Raw reports, provenance, logs and diagnoses
remain under `tmp/fsr2-options/perf/` and `perf-checks/`.

In this short workload, Quality reduced median GPU time by about 30% and median
whole-frame time by about 18% against both native endpoints. 85% reduced GPU time
by about 12% but **worsened** whole-frame p50/p95. Do not present that mode as a
demonstrated FPS win, or extrapolate either result to active flight, 4K or weaker
GPUs. Candidate repeats, longer runs, latency and moving-aircraft recognition remain
open. These are exploratory measurements, not the VQ qualification campaign.

Every run retained the known seven Texture-RID warning. The final Native repeat
also reported four ObjectDB instances at exit; their origin was not attributed in
this comparison. This extra baseline warning is not evidence of an FSR2-specific
leak. None of these runs is claimed to have a warning-free shutdown.

Reproduce each run through `tools/godot/run_checked.py` with a new output path,
isolated APPDATA, `OPENRC_GRAPHICS_PROFILE=high`, `OPENRC_FSR2_SHARPNESS=0.35` and
the respective `OPENRC_RECONSTRUCTION` value. Engine arguments:
`--path app --rendering-method forward_plus --resolution 1920x1080 --fullscreen
--disable-vsync --max-fps 0 --audio-driver Dummy`; app arguments:
`--scripted --look_az=0 --look_el=0 --frametimes=<absolute-new.json>
--frame-diagnostics --warmup=5 --t=15`. Use the native executable directly for timeout
ownership and the existing frame diagnosis tool; do not run another renderer alongside it.

### Further refinement: drag handling and trustworthy captures

The source audit confirmed buffer reconfiguration on changed FSR sharpness. Pointer
dragging now updates its label without applying intermediate values; release applies
the final preview once. Keyboard adjustment remains immediate. Headless transaction
checks: 87 passed. Native High transaction checks: 96 passed (no optional capture
checks in this run), including unchanged renderer strength during drag, final strength
on release and timeout restoration. Reconstruction checks: 43 passed. Receipts are
under `tmp/fsr2-options/followup-checks/`.

Main-flight captures and frame reports now include the full reconstruction receipt
even without frame diagnostics. Static FSR2 captures allow history after the final
pose: two jitter cycles for supported scales, bounded at 64 drawn frames. Native
keeps its existing two-frame wait. A native Quality capture at actual 1920×1080
completed with `capture_settle_frames=36`, nominal input 1280×720, strength 0.35,
visual clock 1.5 and simulation tick/time 0. The synthetic aircraft inspection was
visually opened; this verifies the capture path and recorded state, not pilot
attitude recognition or temporal artifact freedom. The image remains ignored locally.

A first sharpening-cost sequence stopped after its Native-AA/off run because the
launcher detected another rendered Godot. That incomplete sequence under
`sharpening/` is excluded from paired performance claims. No other session was stopped.

The retry under `sharpening-retry/` also encountered contention: another native
OpenGL model benchmark was observed while the second (Native AA, 35%) run was
active. Only our matching benchmark process was stopped; its checked-runner receipt
records that termination. The incomplete retry is excluded from paired RCAS-cost
or Native-AA performance claims. The first four-run comparison above remains a
separate collection; no sharpening-on/off speedup is established here.
