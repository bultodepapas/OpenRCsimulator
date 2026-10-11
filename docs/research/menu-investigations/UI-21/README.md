# UI-21 · Shared screen lifecycle and navigation

**Date:** 2026-10-11. **Status:** implemented and software-verified. **Plan:** [MENU-REDESIGN-PLAN](../../../MENU-REDESIGN-PLAN.md). **Baseline:** `38847b4f8d65af8c1fb2424b2f7eda3e007e950d`; isolated snapshots retain identical physics, aircraft data and rendering. This step changes menu architecture; the visual redesign starts at UI-22.

## Change

- `Screen` supplies dimming, centring, sidebar fade, Esc handling, focus return and recursive input isolation. Home inherits it. Existing CanvasLayer screens mount it without changing their wrappers, node paths or layers.
- `ScreenStack` owns membership, rejects duplicate/attached nodes, activates only the top screen and keeps nested CanvasLayers above their parent. Blocking flight screens hold `menu`; popping the final screen releases that hold without resuming the flight. Nonblocking hints and toasts stay outside navigation.
- `Widgets` supplies shared labels, buttons, action rows, gaps and sidebar fades. Theme values, dimensions and translation policy stay unchanged.
- `app_root` retains read-only compatibility getters for existing tests/captures. It stores one stack instead of a separate reference and return-focus variable for each menu. Flight, the Home world, launch rollback, held-key masking and trace-save policy retain their owners.

## Proof

Results: [verification.json](verification.json), [parity.json](parity.json), [screen-stack.log](screen-stack.log), [full suite log](app-test.log) and [Windows results/logs](native-windows.json).

| Check | Result |
| --- | --- |
| `app/test.sh`, isolated baseline plus UI-21 with real Git metadata | Exit 0; 180 GDScript test scripts, all parse/data/model/trace/frame-rate checks; no unexpected engine errors |
| Existing menu tests plus the new stack regression | 16/16 on Linux and 16/16 on Windows; the 15 existing test sources are unchanged |
| EN/ES paired capture matrix | 16/16 PNG hashes identical |
| Three-second direct flight | 721 samples and stable metadata identical; no player settings created |
| Five Home → Fly → End cycles | 234 Home nodes after every cycle, on both platforms |
| Native Windows app-root parse and shared-checkout integration | Exit 0; the Windows report records its source commit and individual logs |

The new regression uses real keyboard/mouse events to check top-screen focus, covered Fly, duplicate refusal, controls rebuilt under a modal, nested shortcut isolation and five Home → Fly → End cycles. Independent review also identified toast isolation, invalid ownership and CanvasLayer ordering; the implementation rejects nonblocking/attached entries and raises nested layers when required.

The paired capture matrix covers Home, Help, Pause, Flight conditions (Wind/Turbulence/Atmosphere) and the pause lighting editor in EN/ES; Home also runs at 1920×1080. Every pair must have the same PNG SHA-256. The direct flight check compares all 721 samples and all stable metadata; only `created_utc` is excluded because it records the wall-clock time of each run. It also checks that the direct route creates no player settings.

Reproduce with two isolated source snapshots (before UI-21 and after), the pinned engine and a working display:

```sh
python3 docs/research/menu-investigations/UI-21/verify.py \
  --before /path/to/before --after /path/to/after \
  --godot "$(app/get-godot.sh)" --out /path/to/fresh-output
app/test.sh
```

The comparison runner imports each snapshot, checks exit status and engine errors, isolates its user data and refuses an existing output directory. Linux headless checks and WSLg/X11 llvmpipe captures use Godot 4.7.2 (`ed1daf0bf`). They establish software behaviour and visual preservation, not radio hardware, GPU cost, fullscreen or pilot acceptance.

## Capture limitation and correction

UI-20 retained JPEGs and hashes of PNGs produced on an older source snapshot under Xvfb. Matching those historical hashes from this WSLg environment would mix source and renderer changes. UI-21 instead compares paired pre/post-refactor snapshots on the same host.

An initial lighting-editor pair differed only in the moving flight backdrop: its existing capture waits 0.5 s before pausing, which does not select an exact physical tick. For the paired proof, `verify.py` copies that capture script to a temporary file and pauses immediately after Fly in both snapshots. Production capture scripts are unchanged. The complete controlled matrix must pass, including the frozen-background EN/ES lighting editor; the mismatch is not accepted as a refactor difference.
