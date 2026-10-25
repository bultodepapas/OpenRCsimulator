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
