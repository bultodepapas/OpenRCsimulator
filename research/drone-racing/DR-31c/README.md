# DR-31c: real FPV OSD conventions (research, 2026-11-12)

This research shaped the FPV quad OSD (`app/vehicles/multirotor/osd_model.gd`, `osd_painter.gd`, `osd_settings_panel.gd`). The behaviour was read from the firmware sources. No code, fonts or glyphs were copied: both projects are GPL-3.0, including their `.mcm`/HD fonts.

## Versions and sources read

- **Betaflight** 2026.6.2 (newest stable, 2026-09-16), compared with 2025.12.5 and 4.5.5. Files: `src/main/osd/osd.c`, `osd_elements.c`, `osd_warnings.c`, `osd.h`, `drivers/osd_symbols.h`, `fc/runtime_config.c`, and Configurator `src/components/tabs/osd/osd.js`. Docs: <https://www.betaflight.com/docs/wiki/app/osd-tab>.
- **INAV** 9.1.0 (2026-07-09), with the header diffed against 10.0.0-rc2. Files: `src/main/io/osd.c`, `osd.h`, `osd_common.c`, `osd_hud.c`, `osd_grid.c`, `osd_utils.c`, `fc/multifunction.c`, `docs/OSD.md`, `docs/Settings.md`. Repository: <https://github.com/iNavFlight/inav/tree/9.1.0>.
- Community sources were thin: Oscar Liang blocks automated fetches and Reddit was unreachable. Pilot preferences below are therefore weakly sourced.

## Conventions adopted

| Convention | Betaflight | INAV | OpenRC |
| --- | --- | --- | --- |
| Warnings | One 12-character slot, highest priority wins. Arming-disabled reasons only while the arm switch is on. | 10-character multi-function slot plus 28-character messages. | One slot by priority: arming refusal (THROTTLE, ARM SWITCH, RXLOSS, CRASH), then CRASH, BATT EMPTY, LAND NOW, LOW BATTERY, BATT < FULL (only before the first arm), and the ARMED notice. |
| Blink | 2 Hz, 50 % duty (element not drawn in the off half) | Hardware blink, or blink drawn by the goggle | 2 Hz, 50 % |
| HD colour | DisplayPort font pages: white / green / amber / red by severity | Mono white | HD style uses severity colours; analog style is all white |
| Refresh | `osd_framerate_hz` default 12 | Configurable | Analog style refreshes at 12 Hz; HD every frame |
| Mode name | `ACRO`, `ANGL`, `HOR`… | Same 4-letter set | `ACRO`, `ANGL` |
| Alarms | Altitude 100 m; timer alarm 10 min (red, blinking); capacity 2200 mAh | Time 10 min, altitude 100 m, g-force 5 g | Timer 10 min, altitude 100 m (while armed), 5 g |
| G-force | `1.0G` | 2 decimals, PT1 filter with 0.2 s time constant | Specific force from consecutive accepted ticks, 0.2 s filter, 2 decimals |
| Remaining time | `--:--` until 10 % of the capacity alarm is used | Remaining flight time before RTH | `--:--` until 10 % of the pack is used, then time to 80 % used at the mean draw since arming |
| Efficiency | `mAh/km` | `mAh/km`, shows `---` below 1 m/s | Live `mAh/km` (`mAh/mi`), `---` below 1 m/s; total in the statistics after 200 m of path |
| Statistics | After disarm. Closed by throttle-high or pitch-high stick, or after 60 s | Two pages, closed by stick or 60 s | One screen after a real flight. Closed by throttle-high or pitch-forward (once the sticks were seen low) or after 60 s |
| Up/down reference | `U`/`D` when the zenith or nadir is within 25° of the view | — | Same |
| Crosshair | 3 glyphs | Styles DEFAULT, AIRCRAFT, TYPE3–7 | Default, aircraft, cross, dot |
| Layouts | 3 OSD profiles; positions shared between them | 4 layouts | Off, Race, Freestyle, Full, plus Custom (one check per element) |

## Not adopted

- RSSI, link quality, dBm, SNR, VTX, GPS satellites and coordinates: the simulator has no radio link or GNSS to measure, and the OSD does not invent values.
- Glyph fonts and fixed character grids. Analog uses 30×16 (PAL) or 30×13 (NTSC); HD uses 53×20 on DJI and Walksnail and 50×18 on HDZero. OpenRC draws vector elements with a system monospace at 1080p-first sizes.
- A clamped character-cell horizon (Betaflight ±20° pitch, ±40° roll). OpenRC keeps the true camera-projected horizon and pitch ladder.
- RTH, waypoints, radar and wind elements: they need navigation features the multirotor does not have.

## Gate guide

The next-gate marker and edge arrow follow racing-simulator practice, not flight-controller firmware. Betaflight's lap timer is GPS-based and draws no gate guide. The race-course session exposes the gate data (`race_course_visual.gd`).

## DR-31d performance (2026-11-12)

### Method

- The test is the HUD alone in a headless Godot 4.8-beta2 process on the Windows development PC, at a 1920×1080 root with frames capped at 144.
- Telemetry changes every frame, as in real flight. Each run lasts 600 frames per layout and reports the median per frame.
- `update()` and every OSD canvas item's draw callback were timed directly.
- Each version ran in its own process, alternating old and new three times. The baseline is commit `5d488a50d`. The `osd` single layer was measured before the split.
- Interleaving two HUDs in one process is not valid: they share the text server's shaping cache.
- Whole-frame wall time in headless runs was too noisy (±14 ms in warm-up) to use.

### Findings

| Layout | Draw before | Draw after | `update()` |
| --- | --- | --- | --- |
| Race | 88–105 µs | 22–37 µs | ~180–260 µs, unchanged within noise |
| Freestyle | 304–377 µs | 171–304 µs | unchanged within noise |
| Full | 503–756 µs | 231–333 µs | unchanged within noise |

### What helped

- **Three canvas items.**
  - Picture-bound geometry is drawn every frame.
  - The heading tape is drawn only when the heading moves 0.5°.
  - Fixed-place values are drawn at 30 Hz, still above the 12 Hz default of Betaflight's `osd_framerate_hz`.
- **A per-locale `tr()` cache.** `update()` was 15–25 µs faster in 8 of 9 paired runs.

### What did not help (reverted)

- **Keeping `TextLine` objects per string.** Draw time rose by about 2× when numbers change every frame; the text server's cache behind `draw_string` is cheaper.
- **Batching tick strokes into `draw_multiline_colors`.** Sidebars took 30 → 39 µs: building the arrays in GDScript costs more than the calls it saves.

### Remaining costs

- `update()`, about 140 µs. It is spread evenly over 14 sections of interpreter overhead; the largest are battery (20 µs), arm/timer (18 µs) and the draw-state dictionary (18 µs).
- The compass loop: about 90–130 µs per redraw.
- The sidebars: about 46 µs per frame while flying.
- Throttling label text to 30 Hz would save about 55 µs per frame but would show one-frame-stale states. It was rejected.

## DR-31e performance (2026-11-12)

### Research behind it

| Fact | Status | Source |
| --- | --- | --- |
| A canvas item keeps its recorded commands until `queue_redraw` clears and re-records them; `canvas_item_set_transform` only stores a matrix | confirmed | `scene/main/canvas_item.cpp`, `servers/rendering/renderer_canvas_cull.cpp` |
| `draw_colored_polygon` triangulates on the CPU, creates GPU buffers on every redraw and never batches | confirmed | `renderer_canvas_render_rd.cpp`, `rasterizer_canvas_gles3.cpp` |
| `Font` keeps shaped strings in an LRU of 64 by default (`set_cache_capacity`) | confirmed | `scene/resources/font.h` |
| Headless runs use the dummy canvas rasterizer, so they leave out batching and buffer work | confirmed | `servers/rendering/dummy/rasterizer_canvas_dummy.h` |
| Retained or pre-rendered tapes and low-rate instrument updates are common practice | as documented | Unreal Retainer Box `PhaseCount`; Betaflight `osd_framerate_hz` 12 |

### Changes

- **Recorded tapes.** The heading tape (−60…420°) and the sidebar tick strips (periodic every 5 ticks) are recorded once into their own canvas item RIDs. Each sits under a clipping parent (a scissor clip, not `clip_children`, which needs an offscreen canvas group). The tapes move with one `canvas_item_set_transform` per frame, sent only when the offset changes.
  - Only the boxed heading is redrawn, when the whole degree changes.
  - The tapes no longer fade toward their ends.
- **Primitives.** The triangles, the home arrow, the home icon and the gate arrow use primitives instead of polygons.
- **Font cache.** The OSD font keeps 512 shaped strings.

### Measured

Each version ran in its own process against the DR-31d state, alternated three times. Figures are median draw µs per frame.

| Layout | Headless | Real 1080p window |
| --- | --- | --- |
| Freestyle | 156–179 → 74–84 | 318–319 → 116–142 |
| Full | 210–252 → 154–176 | 418–437 → 220–260 |
| Race | unchanged (~21–37); it has no tapes | unchanged |

- The total per frame with `update()` fell in every Freestyle and Full pair.
- `update()` itself moved within noise (±40 µs). It now includes the tape placement.
- In a real window the drawing cost about twice the headless figure, so headless comparisons understate both the cost and the saving.
- A 1080p capture checked the tape geometry: heading 122° puts E, SE and S at 800, 1025 and 1250 px, predicted versus drawn within 1 px.
