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
