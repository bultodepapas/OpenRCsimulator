# Stutter map: three-aircraft tour on Windows and M1

Where the [performance tour](../../../tools/godtest/PERFORMANCE_TOUR.md) detected
frame drops and freezes on 2026-11-21. This record **marks** the problems; it does
not diagnose or fix them. Each result is one rendered pass per aircraft, with
native physics and sound muted. It is not a hardware qualification, a repeated
campaign or a regression baseline.

| Host | GPU and output | Source | Suite result |
| --- | --- | --- | --- |
| Windows workstation | RTX 3090, 1920×1080 window, Forward+/Vulkan | `1f24cb067` + `8a76c4b22` | valid, complete (Corsair retried after a desktop focus loss) |
| ANGEL, MacBook Air M1 | 1920×1080 borderless on a mirrored external display, Mobile/Metal | `ac33ae1b6` candidate | valid, complete |

Frame times are callback intervals in milliseconds. The 1 % and 0.1 % lows are the
reciprocals of the mean of the slowest tail intervals. A *stall* is an interval the
continuous frame watcher classified as a freeze. Raw runs, frame streams and
watcher incidents are retained outside Git.

## Summary

| Area | Windows | M1 | Severity |
| --- | --- | --- | --- |
| Loading a flight | freezes up to 1.1 s; 8–10 frames > 100 ms | freezes up to 2.8 s; 6–9 frames > 100 ms | high |
| Home → selection | 2.8 s freeze on the first launch (Stik); 0.54–0.56 s otherwise | 0.30–0.34 s | high (first launch), medium |
| Opening Settings from Pause | 280–315 ms freeze | 285–320 ms | medium |
| Opening Controls from Pause | 640–760 ms freeze | 415–460 ms | medium |
| Lighting Apply (Settings) | 350–640 ms freeze | 320–530 ms | medium |
| Return to Home | 370–760 ms freeze | 405–705 ms | medium |
| Home screen frame rate | 206–264 FPS | **42–51 FPS** | medium (M1) |
| Flight, runway circuit | smooth: 0–3 frames > 33 ms | 12–92 frames > 33 ms; 5–6 % of frames > 16.7 ms on jet and Corsair | low (Windows), medium (M1) |

On both hosts, steady flight is not where the freezes are. They sit in **flight
loading and in every menu transition**, and the menu freezes are similar on both
machines. The M1 adds a slow Home screen and frequent sub-60 FPS dips in flight,
with the GPU at 94–96 % mean utilization.

## Flight, runway circuit

| Host / aircraft | FPS mean | 1 % low | 0.1 % low | > 16.7 ms | > 33 ms | > 50 ms | Worst |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Windows Stik | 174 | 76 | 57 | 4 | 0 | 0 | 29 ms |
| Windows jet | 185 | 71 | 54 | 14 | 0 | 0 | 27 ms |
| Windows Corsair | 182 | 65 | 43 | 45 | 3 | 0 | 49 ms |
| M1 Stik | 97 | 34 | 22 | 164 | 12 | 1 | 55 ms |
| M1 jet | 79 | 28 | 19 | 626 | 65 | 8 | 68 ms |
| M1 Corsair | 74 | 24 | 17 | 770 | 92 | 13 | 71 ms |

The circuits last 67 s (Stik), 156 s (jet) and 136 s (Corsair). Every case kept
simulation pace at 1.000. In this fourth consecutive M1 run, the jet's and Corsair's
circuit p99 was 27–33 ms. An earlier M1 run met the 25 ms target. Thermal state on
the fanless Air was not recorded separately.

## Marked freezes by phase

Worst single interval per phase, with the number of frames above 100 ms in brackets.

| Phase | Windows Stik | Windows jet | Windows Corsair | M1 Stik | M1 jet | M1 Corsair |
| --- | --- | --- | --- | --- | --- | --- |
| `selection` (Home → selected) | 2798 ms [1] | 559 ms [1] | 536 ms [1] | 302 ms [1] | 338 ms [1] | 344 ms [1] |
| `loading` | 1101 ms [9] | 1077 ms [8] | 1036 ms [10] | 2668 ms [7] | 2651 ms [6] | 2849 ms [9] |
| `home` (first) | 42 ms | 164 ms [2] | 235 ms [2] | 49 ms | 240 ms [2] | 83 ms |
| `menu_settings` | 297 ms [1] | 281 ms [1] | 314 ms [1] | 318 ms [1] | 295 ms [1] | 285 ms [1] |
| `menu_controls` | 757 ms [1] | 643 ms [1] | 670 ms [1] | 415 ms [1] | 458 ms [1] | 457 ms [1] |
| `settings` (lighting Apply) | 354 ms [2] | 352 ms [2] | 639 ms [3] | 343 ms [2] | 320 ms [1] | 530 ms [1] |
| `home` (return) | 763 ms [5] | 370 ms [3] | 710 ms [4] | 705 ms [2] | 409 ms [3] | 669 ms [3] |

Each menu phase opens the real screen through Pause, dwells and returns. The single
> 100 ms interval in `menu_settings` and `menu_controls` is therefore one freeze per
screen transition, not repeated stutter while the screen is open.

## Home and menu frame rate on M1

| Phase | Windows FPS range | M1 FPS range |
| --- | --- | --- |
| Home (first) | 206–264 | 42–51 |
| Pause | 218–275 | 74–89 |
| Settings / Controls open | 239–298 | 57–82 |
| Lighting Settings | 167–240 | 42–48 |
| Home (return) | 180–226 | 35–39 |

The M1 Home screen and the lighting Settings run below 60 FPS while the flight
behind them is paused.

## What to investigate next

These are detection results only. Use the diagnostics in the tour guide's
[investigation table](../../../tools/godtest/PERFORMANCE_TOUR.md#investigate-and-optimize-from-the-evidence)
and compare a matched before/after run on the same machine:

1. Flight loading freezes (1–2.8 s) on both platforms.
2. The first Home → selection freeze on a fresh Windows launch (2.8 s).
3. One freeze per menu transition: Settings, Controls, lighting Apply and Home return.
4. M1 Home/menu frame rate and in-flight sub-60 FPS dips at full GPU load.

Repeat with `--repeats 3` and an idle, unlocked desktop before claiming any change.
