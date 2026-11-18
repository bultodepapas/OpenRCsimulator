# VQ-07h: Mac display probe on ANGEL (M1)

2026-11-18. ANGEL is a MacBookAir10,1 with an Apple M1 (7-core GPU), running macOS 27.0 on AC power. The official Godot `4.8.beta2.official.cafc17a19` arm64 build was used: the ZIP SHA-512 matched the published list and `codesign --verify --deep --strict` passed. The Mac was in use during the run.

## Purpose

This probe checks, on real hardware, what Godot reports to the [Mac native-resolution rule](../../../../../AGENTS.md#display-resolution-priorities) and what `gpu_capability.gd` decides from it. The probe is a minimised, unfocused 320×200 project; it does not run the game.

Files:

- [`probe_project.godot`](probe_project.godot) is the project.
- [`probe_main.gd`](probe_main.gd) is the script.
- [`angel-result.json`](angel-result.json) is the output.
- `render/gpu_capability.gd` and `data/gpu/capability.json` were copied unchanged from the working tree.

The run used `--rendering-method mobile --rendering-driver metal`.

## Observed

| Item | Value |
| --- | --- |
| Engine banner | `Metal 4.0 - Forward Mobile - Using Device #0: Apple - Apple M1 (Apple7)` |
| `get_video_adapter_name()` | `Apple M1 (Apple7)` → table row `apple_m1` (rel 0.055) |
| Screens reported | 1: 1920×1080, scale 1.0, 60 Hz, usable 1920×1050 |
| macOS display state | External 1080p display, master of a mirror; built-in 2560×1600 Retina LCD online as a hardware mirror; lid open |
| `mac_native_target` | false |
| `first_run_settings` | `{}`: windowed, MSAA 4×, no frame cap |
| Scene detail Automatic | Medium |

## Findings

1. **Adapter name format confirmed.** Godot reports the Apple GPU family suffix (`(Apple7)`), and `normalize()` removes it as designed.
2. **Mirroring is handled.** When a 1× external display is the mirror master, Godot reports only that display. The rule then keeps 1080p windowed defaults, which matches the output the GPU actually produces.
3. **The 7-core bin is the measured one.** Both available M1 Macs have the 7-core GPU, so the M1 calibration (DT-MAC-00-R4) is the lower bin. The table's conservative lowest-bin policy agrees with it.

## Still open

The probe did not exercise the Retina branch: no screen reported a scale of 2, so there was no native full screen, MetalFX Automatic or ProMotion. That branch needs the built-in panel used alone, with mirroring off, or a Retina external display. Run it when the owner is not using the Mac.

The probe workspace stays at `/Users/g/OpenRC-m1-work/display-probe-20261118/` with the verified engine in `engine/`.
