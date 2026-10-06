1. Build an RC airplane simulator.
2. Grow from small to large: start with something very simple that works and shows a little airplane, then expand gradually.
3. the repo is starting, we are fluid, flexible, investigating, a lot of research.
4. you can use sub agents with luna max model
5. All usefull research should be safe in docs, for later use.
6. Eres un desarrollador de videojuegos.
7. be robust on phisics and realism.
8. all docs in english, short, consise, precise.

## Development

Plan: [ROADMAP.md](ROADMAP.md) · Stack: [STACK.md](STACK.md) · Decisions: [DECISIONS.md](DECISIONS.md) · Lessons: [LEARNINGS.md](LEARNINGS.md) · Documentation map, track registry and writing conventions: [docs/README.md](docs/README.md) · Research index: [docs/research/README.md](docs/research/README.md)

The simulator is the **Godot 4.7 app in `app/`** (Gate 1, 2026-10-05). `prototypes/stage0/three/` is the archived three.js bake-off build.

| What | Command |
| --- | --- |
| Get the pinned Godot (verified SHA-512) | `app/get-godot.sh` → `.tools/` |
| Run the app (needs a display) | `$(app/get-godot.sh) --path app`: opens on Home (Fly/Language/Quit, keyboard or mouse; a radio never navigates menus; English by default, Spanish from `app/i18n/es.po`, choice saved in `user://settings.cfg`); Fly starts trimmed level flight, engine running; Esc (or losing focus) opens the pause menu: Continue, Restart flight, End flight (back to Home), Quit. `-- --quick-flight` skips Home (any `--` argument does, so traces and captures run as before). Home's arrows choose the aircraft (Ugly Stik, Extra 300S experimental, P-51D Mustang 1/4 experimental, Avanti S preview: Fly disabled), remembered in `user://settings.cfg`; on the direct route `-- --aircraft=gp-extra-300s-60` (catalog IDs in `app/app_state/aircraft_catalog.gd`; a preview only with `--scripted`). Add `-- --scripted` for the Stage 0/1 circle. Keys: arrows/A/D fly, W/S throttle, R restart, P resume, C camera, T record trace. A USB radio/joystick flies instead while connected (EdgeTX: AETR order; the throttle stays at idle until moved to low = armed; unplugging pauses; K calibrates, Enter per step, Esc cancels) |
| Headless flight trace | `$(app/get-godot.sh) --headless --path app -- --trace=/tmp/t.csv --t=3` (CSV `openrc-trace v2`, one row per 240 Hz tick) |
| All checks, headless (~45 s): float64 guard, parse check of every script, unit tests, end-to-end input tests (keyboard and a fake radio), flight modes, flown handling/stall/spin/crash checks, golden flights (`tests/golden/`, re-record only for a deliberate physics change with `tests/record_golden.gd`), the model team's contract (`aircraft/verify_model.gd`), the real app's trimmed flight (`--trace` + `tests/check_trimmed_flight.py`), frame-rate independence with injected keys (30/60/144 fps), and failure on any engine error | `app/test.sh` |
| Captures (needs `xvfb-run`) | `app/capture.sh` → `app/captures/*.png` (not tracked in git; CI uploads them as artifacts); includes the L6c readability run and the blinded attitude kit for the owner's playtest (`app/captures/l6c/kit/index.html`, scored with `tests/treeline_readability.py score`) |
| Release builds (Windows, Linux, macOS) with smoke tests, zips and `SHA256SUMS` | `app/export.sh` (no version argument: the build identity is `git describe`, written into the pack and checked in the exported binary) → `dist/` (downloads the 1.28 GB export templates once, SHA-512 verified). CI runs it on `main` and `v*` tags; a `v*` tag also publishes a GitHub prerelease |
| Physics cost per tick | `$(app/get-godot.sh) --headless --path app --script res://tests/bench_physics.gd` |
| Sensitivity sweep and validation table | `$(app/get-godot.sh) --headless --path app --script "$PWD/research/sensitivity/sensitivity.gd"` |
| CI locally (needs Docker) | `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j app` |
| Archived three.js build (Node 24, see `.nvmrc`) | `cd prototypes/stage0/three && npm ci && npm test && npm run capture && npm run e2e` |

Rules for the Godot app:
- Physics data lives in `app/data/aircraft/*.json` (format `openrc-aircraft v1`): every value carries `{value, unit, kind, source}`. The loader refuses invalid data, and the app then refuses to fly.
- Simulation code (`sim/`, `physics/`) keeps state in 64-bit GDScript `float`s, never `Vector3`/`Basis`/`Quaternion`/`Transform3D` (32-bit). `app/test.sh` enforces this.
- Don't name constants after built-in classes (`Panel`, `Label`, …): it causes parse errors, which hang headless runs.

Parallel work (2026-10-05; registry 2026-10-06): several developers/assistants work in this repo at the same time. The full registry of tracks, plans, step-ID prefixes and owned paths is in [docs/README.md](docs/README.md#tracks-plans-and-step-ids); the bullets below are the short form. Before editing a shared document (ROADMAP, LEARNINGS, DECISIONS, AGENTS), run `git status`: if another track has uncommitted changes in it, add your lines without touching theirs.
- **Aircraft model** (another developer): `app/aircraft/`, `app/render/airplane.gd`, the geometry tables in `app/spec.gd`, `assets/aircraft/ugly-stik-60/`, `docs/UGLY-STIK-PLAN.md`, `docs/UGLY-STIK-VISUAL-PLAN.md`, `docs/research/ugly-stik-*`, `research/ugly-stik/`. Keep its node names and hinge interface (`airplane`, `propeller`, `*_hinge`) stable.
- **P-51D Mustang 1/4 (120 cc) track** ([P51-PLAN](docs/P51-PLAN.md)): `assets/aircraft/p51d-mustang-120/` (source.json → geometry.json → `app/aircraft/p51d_geometry.gd`, generated), `app/aircraft/p51d_model.gd`, `verify_p51.gd`, `inspect_p51.gd`, `research/p51/`, `app/data/aircraft/p51d_mustang_120.json` (generated by `research/p51/p51-05/derive_physics.py`), `app/tests/test_p51_handling.gd`. Regenerate through the scripts; never hand-edit the generated files.
- **Extra 300S and Avanti S tracks** ([EXTRA-300-PLAN](docs/EXTRA-300-PLAN.md), [AVANTI-S-PLAN](docs/AVANTI-S-PLAN.md)): `assets/aircraft/extra-300s-60/`, `assets/aircraft/avanti-s-a200/`, `app/aircraft/extra_300s_*.gd`, `extra_clearance.gd`, `verify_extra.gd`, `inspect_extra.gd`, `app/aircraft/avanti_s_*.gd`, `verify_avanti.gd`, `research/extra-300/`, `research/avanti-s/`, `app/tests/test_extra_handling.gd`; `app/data/aircraft/gp_extra_300s_60.json` is generated by `research/extra-300/ex05/derive_physics.py`.
- **Menus and product shell** ([MENU-PLAN](docs/MENU-PLAN.md)): `app/app_root.*`, `app/ui/`, `app/app_state/`, `app/addons/build_info/`, `app/i18n/`, `app/tests/ui_driver.gd`, `app/tests/test_ui_*.gd`, `docs/research/menu-investigations/`.
- **Visual quality and landscape** ([VISUAL-QUALITY-PLAN](docs/VISUAL-QUALITY-PLAN.md), [LANDSCAPE-PLAN](docs/LANDSCAPE-PLAN.md)): `app/render/` except `airplane.gd` (ground, sky, atmosphere, field, treeline, shader clock, visual evidence), `app/data/fields/`, `app/data/field_loader.gd`, `app/assets/landscape/`, `assets/landscape/`, `tools/trees/`, `app/capture.sh` and the capture checks in `app/tests/`, `docs/research/visual-quality-*`, `docs/research/landscape-*`.
- **Physics and simulation** (main line): `app/physics/`, `app/sim/`, `app/data/aircraft/` (physics data), `app/tests/`, the ROADMAP Phase C and milestone steps (D, E, F, G). Physics reads span, chord, leading edge and thrust line from the model team's generated `ugly_stik_geometry.gd`; `tests/test_aircraft_data.gd` checks that both agree.
- `app/test.sh` parses **every** script in `app/`, so work in progress that doesn't parse breaks everyone's run and CI. Run `app/test.sh` before saving scripts into `app/`, or keep drafts outside it.
- Before moving or renaming files, grep the whole repo for the old paths. After changing `.gitignore`, paths or generated outputs, verify from a fresh `git clone`: `act` copies untracked folders and hides missing-directory bugs. Never leave a deliberately broken file in the working tree: run mutation checks on a copy.

Working agreement:
- One small step per change, following the step IDs in ROADMAP.md.
- Every change states its proof (test, capture, trace or measurement) in the commit message.
- Guessed numbers are labeled with their source and evidence kind.
- After each step, add what was learned in practice to LEARNINGS.md.
- Documents follow [docs/README.md](docs/README.md#conventions-for-documents): one language per file, a status line and a registered step-ID prefix per plan, a step's status in its plan (ROADMAP keeps one line per track), evidence folders named by step ID, no links into gitignored folders.
- Pin exact dependency versions; upgrade one at a time.
