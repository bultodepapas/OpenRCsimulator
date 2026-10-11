# tools/world

Field world tools ([FIELD-WORLD-PLAN](../../docs/FIELD-WORLD-PLAN.md)). Python tools use the standard library only.

| Tool | Step | What it does |
| --- | --- | --- |
| `parity.sh <out> [--compare <manifest>]` | FW-01 | Renders 89 fixed views through every world-assembly site (flight, atmosphere fixture, Home, scenery views, runway scenario) plus a headless trace, and writes SHA-256 per output. FW-A steps must leave it unchanged on the same machine. Needs `xvfb-run` or a `$DISPLAY`; forces llvmpipe, one thread |
| `sky_table.py [--check]` | FW-21 | Physical sky per sun elevation → `app/data/sky/sky_table.json` (~30 s). `app/test.sh` runs `--check` |
| `stars.py [--check]` | FW-24 | Naked-eye stars from `assets/sky/bsc5.dat.gz` (SHA-256 checked) → `app/data/sky/stars.json`. `app/test.sh` runs `--check` |
| `capture_times.sh [out] [preset ...]` | FW-22…35 | Five views per time-of-day preset and a contact sheet (`index.html`) |

On WSL without root, `xvfb-run` is usually missing: WSLg's `$DISPLAY` works, and software GL is forced by the scripts (`LIBGL_ALWAYS_SOFTWARE=1`), so results compare only with runs on the same machine.
