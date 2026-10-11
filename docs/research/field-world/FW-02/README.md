# FW-01/FW-02 — Parity harness and the one world composer

**Status:** done 2026-10-10. Code: [world.gd](../../../../app/render/world/world.gd), call sites in `main.gd`, `ui/home_scene.gd`, `scenery/capture_views.gd`, `scenery/runway_scenario.gd`. Harness: [parity.sh](../../../../tools/world/parity.sh).

## What was done

- **FW-01:** `tools/world/parity.sh` renders 89 fixed views through every world-assembly site: 15 flight views (eight horizon views, top-down, 30 m, 3 m low pass, sun, 100 m, close-up, two scenery-on views), the frozen L1–L4 atmosphere fixture, Home, the scenery evidence views and 51+ runway-scenario frames, plus a headless 3 s trace. It hashes each PNG and the trace without its wall-clock `created_utc` line (the only line that differs run to run).
- **FW-02:** `World.build(parent, field, build_field, conditions)` is now the only code that creates the flight `Environment`, the field and the sun; `World.update` advances the shader clock and cloud drift. Main's `_build_field` seam (overridden by the atmosphere fixture) is passed as a callable. The later time-of-day, stars, field lights and night kit are added in this one place.

## Results (WSL2 + WSLg, llvmpipe forced, one thread, 1280×720)

| Run | Images | Trace content |
| --- | --- | --- |
| Baseline at `28cd5c6` | 89 hashed | `a11b9064…` |
| Baseline repeated | 89/89 identical | identical |
| FW-02 composer | 89/89 identical | identical |
| All FW work of 2026-10-10 (time of day off by default) | 89/89 identical | identical |
| + FW-27 Home time button, view adaptation, AgX at night | 88/89 identical; `home.png` differs only inside the menu column (x ≤ 446 px: the new button), the 3D backdrop is identical | identical |

`app/test.sh` passes with the same changes (158 sections, exit 0; 159 with the FW-27 UI test).

## What it does not prove

Hashes are tied to this machine's Mesa build; CI's llvmpipe may produce other bytes, which is why the comparison is always against a baseline from the same machine. The harness does not run the readability or golden-flight checks: those stay in `app/capture.sh` and `app/test.sh`.

## Reproduce

`tools/world/parity.sh /tmp/base` on the old revision, then `tools/world/parity.sh /tmp/new --compare /tmp/base/manifest.txt` on the new one.
