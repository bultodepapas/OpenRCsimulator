1. Build an RC airplane simulator.
2. Grow from small to large: start with something very simple that works and shows a little airplane, then expand gradually.
3. the repo is starting, we are fluid, flexible, investigating, a lot of research.
4. you can use sub agents with luna max model
5. All usefull research should be safe in docs, for later use.
6. Eres un desarrollador de videojuegos.

## Development

Plan: [ROADMAP.md](ROADMAP.md) · Stack: [STACK.md](STACK.md) · Decisions: [DECISIONS.md](DECISIONS.md) · Lessons: [LEARNINGS.md](LEARNINGS.md)

The simulator is the **Godot 4.7 app in `app/`** (Gate 1, 2026-10-05). `prototypes/stage0/three/` is the archived three.js bake-off build.

| What | Command |
| --- | --- |
| Get the pinned Godot (verified SHA-512) | `app/get-godot.sh` → `.tools/` |
| Run the app (needs a display) | `$(app/get-godot.sh) --path app` |
| All checks: float64 guard, parse check, unit + end-to-end tests (headless) | `app/test.sh` |
| Captures (needs `xvfb-run`) | `app/capture.sh` → `app/captures/*.png` |
| CI locally (needs Docker) | `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j app` |
| Archived three.js build (Node 24, see `.nvmrc`) | `cd prototypes/stage0/three && npm ci && npm test && npm run capture && npm run e2e` |

Rules for the Godot app:
- Simulation code (`sim/`, `physics/`) keeps state in 64-bit GDScript `float`s, never `Vector3`/`Basis`/`Quaternion`/`Transform3D` (32-bit). `app/test.sh` enforces this.
- Don't name constants after built-in classes (`Panel`, `Label`, …): it causes parse errors, which hang headless runs.

Parallel work (2026-10-05): several developers/assistants work in this repo at the same time.
- **Aircraft model** (another developer): `app/render/airplane.gd`, the geometry tables in `app/spec.gd`, `assets/aircraft/`, `docs/UGLY-STIK-PLAN.md`, `docs/research/`. Keep its node names and hinge interface (`airplane`, `propeller`, `*_hinge`) stable.
- **Physics and simulation** (main line): `app/physics/`, `app/sim/`, `app/tests/`, the ROADMAP Phase C/D steps.
- Before moving or renaming files, grep the whole repo for the old paths. Never leave a deliberately broken file in the working tree: run mutation checks on a copy.

Working agreement:
- One small step per change, following the step IDs in ROADMAP.md.
- Every change states its proof (test, capture, trace or measurement) in the commit message.
- Guessed numbers are labeled with their source and evidence kind.
- After each step, add what was learned in practice to LEARNINGS.md.
- Pin exact dependency versions; upgrade one at a time.
