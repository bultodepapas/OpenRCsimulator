# Time of day: selectable light and night

2026-10-12 · Revision 9 · Step prefix: **TOD**

**Status:** fixed selectable lighting, paused editing and saved visual checkpoints are implemented. The Home Evening preset can also flow through the FW world path at 20×. Full tick-anchored progression, target-GPU cost and owner readability remain open. The full-moon, richer aircraft lighting and glare studies are optional later slices.

**Owns:** time-of-day research, config and timeline modules, and tests listed in the [track registry](README.md#step-id-namespaces). Field rendering and the Home menu remain shared through the FIELD-WORLD and UI owners.

## Current behavior

Home stores the selected time. Day uses the legacy calibrated fixed sun; Evening starts at golden hour and advances at 20× through the field-world path. Direct technical launches do not read Home preferences. Use explicit arguments to select a frozen time or time scale:

    $(app/get-godot.sh) --path app -- --quick-flight --time_of_day=night
    $(app/get-godot.sh) --path app -- --quick-flight --time=18:30 --date=2026-06-21 --lat=40 --lon=-3.7 --utc_offset=2

The independent lighting-config route accepts a validated fixed-time profile and preserves physics state. A missing time selection retains the calibrated legacy scene. CLI/environment values override the saved Home choice.

## Completed implementation

TOD-02a/b validate configuration and compute solar events from date and location. TOD-03a/b connect the legacy reference and selectable sky/light curves. TOD-04a/b cover sun-dependent shadows, aircraft and scenery. TOD-05/06 deliver CLI, recording context, Home selection and persistence. TOD-08a/b deliver paired visual-context restore and paused edits. TOD-09a/b/c1 implement exact tick-based clock records, in-place lighting and progressing history/checkpoint contracts. Evidence remains in the [TOD-00 sources](research/time-of-day-investigations/TOD-00/README.md), especially [TOD-07](research/time-of-day-investigations/TOD-07/verification.md), [TOD-08a](research/time-of-day-investigations/TOD-08a/README.md), [TOD-08b](research/time-of-day-investigations/TOD-08b/README.md), [TOD-09a](research/time-of-day-investigations/TOD-09a/README.md), [TOD-09b](research/time-of-day-investigations/TOD-09b/README.md) and [TOD-09c1](research/time-of-day-investigations/TOD-09c1/README.md).

## Open steps and acceptance

| ID | Remaining work | Status |
| --- | --- | --- |
| TOD-01 | Compare sky update modes and measure target-GPU frame cost. | Reproducibility verified on llvmpipe; target GPU remains open. |
| TOD-03b | Calibrate estimated daylight/twilight/night curves against reference displays. | Implemented; display calibration remains open. |
| TOD-07 | Owner review of fixed selectable time, night readability and exported build. | Software/export checks are recorded; target GPU and pilot acceptance remain open. |
| TOD-09c2 | Enable full tick-anchored progression through Home, pause, restart and saved checkpoints. | Partial: FW-61 supplies a deterministic Evening flow path at 20×. Exact fractional-clock restoration, edit lifecycle, midnight/year rollover and full controls remain open. |
| TOD-09d | Select a supported accelerated rate beyond the named Evening preset. | Open; 30× remains a candidate until cost and transition behavior are measured. |
| TOD-10/11/12 | Optional Moon/stars extension, broader night equipment and glare experiment. | Parked; none is a prerequisite for TOD-07. The moon part is proposed under [FW-MOON](plans/moon.md) (decision M-D1), including a moon on the astronomical TOD route (FW-MOON-09). |

Do not claim the FW-61 visual flow proves the full TOD-09c2 checkpoint and UI contract. Keep celestial time outside physical weather hashes and aerodynamic state. Pauses freeze the world with simulation time; captures use equal simulation ticks for comparison. Calibration and hardware costs remain separate from pilot acceptance.

Research includes [primary field-world sources](research/field-world/web-research-2026-10-10.md), the source notes and verification reports in [TOD-00 sources](research/time-of-day-investigations/TOD-00/README.md), and [TOD-09c1](research/time-of-day-investigations/TOD-09c1/README.md).
