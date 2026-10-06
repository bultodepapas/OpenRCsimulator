1. Build an RC airplane simulator.
2. Grow from small to large: start with something very simple that works and shows a little airplane, then expand gradually.
3. the repo is starting, we are fluid, flexible, investigating, a lot of research.
4. you can use sub agents with luna max model
5. All usefull research should be safe in docs, for later use.
6. Eres un desarrollador de videojuegos.
7. be robust on phisics and realism.

## Development

Plan: [ROADMAP.md](ROADMAP.md) · Stack: [STACK.md](STACK.md) · Decisions: [DECISIONS.md](DECISIONS.md) · Lessons: [LEARNINGS.md](LEARNINGS.md)

The simulator is the **Godot 4.7 app in `app/`** (Gate 1, 2026-10-05). `prototypes/stage0/three/` is the archived three.js bake-off build.

| What | Command |
| --- | --- |
| Get the pinned Godot (verified SHA-512) | `app/get-godot.sh` → `.tools/` |
| Run the app (needs a display) | `$(app/get-godot.sh) --path app`: opens on Home (Fly/Language/Quit, keyboard or mouse; a radio never navigates menus; English by default, Spanish from `app/i18n/es.po`, choice saved in `user://settings.cfg`); Fly starts trimmed level flight, engine running. `-- --quick-flight` skips Home (any `--` argument does, so traces and captures run as before). Add `-- --scripted` for the Stage 0/1 circle. Keys: arrows/A/D fly, W/S throttle, R restart, P resume, C camera, T record trace. A USB radio/joystick flies instead while connected (EdgeTX: AETR order; the throttle stays at idle until moved to low = armed; unplugging pauses; K calibrates, Enter per step, Esc cancels) |
| Headless flight trace | `$(app/get-godot.sh) --headless --path app -- --trace=/tmp/t.csv --t=3` (CSV `openrc-trace v2`, one row per 240 Hz tick) |
| All checks, headless (~45 s): float64 guard, parse check of every script, unit tests, end-to-end input tests (keyboard and a fake radio), flight modes, flown handling/stall/spin/crash checks, golden flights (`tests/golden/`, re-record only for a deliberate physics change with `tests/record_golden.gd`), the model team's contract (`aircraft/verify_model.gd`), the real app's trimmed flight (`--trace` + `tests/check_trimmed_flight.py`), frame-rate independence with injected keys (30/60/144 fps), and failure on any engine error | `app/test.sh` |
| Captures (needs `xvfb-run`) | `app/capture.sh` → `app/captures/*.png` (not tracked in git; CI uploads them as artifacts) |
| Release builds (Windows, Linux, macOS) with smoke tests, zips and `SHA256SUMS` | `app/export.sh` → `dist/` (downloads the 1.28 GB export templates once, SHA-512 verified). CI runs it on `main` and `v*` tags; a `v*` tag also publishes a GitHub prerelease |
| Physics cost per tick | `$(app/get-godot.sh) --headless --path app --script res://tests/bench_physics.gd` |
| Sensitivity sweep and validation table | `$(app/get-godot.sh) --headless --path app --script "$PWD/research/sensitivity/sensitivity.gd"` |
| CI locally (needs Docker) | `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j app` |
| Archived three.js build (Node 24, see `.nvmrc`) | `cd prototypes/stage0/three && npm ci && npm test && npm run capture && npm run e2e` |

Rules for the Godot app:
- Physics data lives in `app/data/aircraft/*.json` (format `openrc-aircraft v1`): every value carries `{value, unit, kind, source}`. The loader refuses invalid data, and the app then refuses to fly.
- Simulation code (`sim/`, `physics/`) keeps state in 64-bit GDScript `float`s, never `Vector3`/`Basis`/`Quaternion`/`Transform3D` (32-bit). `app/test.sh` enforces this.
- Don't name constants after built-in classes (`Panel`, `Label`, …): it causes parse errors, which hang headless runs.

Parallel work (2026-10-05): several developers/assistants work in this repo at the same time.
- **Aircraft model** (another developer): `app/aircraft/`, `app/render/airplane.gd`, the geometry tables in `app/spec.gd`, `assets/aircraft/`, `docs/UGLY-STIK-PLAN.md`, `docs/research/`. Keep its node names and hinge interface (`airplane`, `propeller`, `*_hinge`) stable.
- **Physics and simulation** (main line): `app/physics/`, `app/sim/`, `app/data/aircraft/` (physics data), `app/tests/`, the ROADMAP Phase C and milestone steps (D, E, F, G). Physics reads span, chord, leading edge and thrust line from the model team's generated `ugly_stik_geometry.gd`; `tests/test_aircraft_data.gd` checks that both agree.
- `app/test.sh` parses **every** script in `app/`, so work in progress that doesn't parse breaks everyone's run and CI. Run `app/test.sh` before saving scripts into `app/`, or keep drafts outside it.
- Before moving or renaming files, grep the whole repo for the old paths. After changing `.gitignore`, paths or generated outputs, verify from a fresh `git clone`: `act` copies untracked folders and hides missing-directory bugs. Never leave a deliberately broken file in the working tree: run mutation checks on a copy.

Working agreement:
- One small step per change, following the step IDs in ROADMAP.md.
- Every change states its proof (test, capture, trace or measurement) in the commit message.
- Guessed numbers are labeled with their source and evidence kind.
- After each step, add what was learned in practice to LEARNINGS.md.
- Pin exact dependency versions; upgrade one at a time.
