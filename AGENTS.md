1. Build an RC airplane simulator.
2. Grow from small to large: start with something very simple that works and shows a little airplane, then expand gradually.
3. the repo is starting, we are fluid, flexible, investigating, a lot of research.
4. you can use sub agents with luna max model
5. All usefull research should be safe in docs, for later use.

## Development

Plan: [ROADMAP.md](ROADMAP.md) · Stack: [STACK.md](STACK.md) · Decisions: [DECISIONS.md](DECISIONS.md) · Lessons: [LEARNINGS.md](LEARNINGS.md)

Commands (Node 24, see `.nvmrc`):

| What | Command |
| --- | --- |
| three.js prototype: install | `cd prototypes/stage0/three && npm ci` |
| three.js: dev server | `npm run dev` |
| three.js: type check | `npm run typecheck` |
| three.js: unit tests | `npm test` |
| three.js: keyboard end-to-end test (headless browser) | `npm run e2e` |
| three.js: headless captures | `npm run capture` → `prototypes/stage0/capture-three*.png` |
| Godot prototype: get pinned Godot | `prototypes/stage0/godot/get-godot.sh` → `.tools/` |
| Godot: parse check + unit + end-to-end tests (headless) | `prototypes/stage0/godot/test.sh` |
| Godot: headless captures (needs `xvfb-run`) | `prototypes/stage0/godot/capture.sh` → `prototypes/stage0/capture-godot*.png` |
| CI locally (needs Docker) | `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j three` (or `-j godot`) |

Working agreement:
- One small step per change, following the step IDs in ROADMAP.md.
- Every change states its proof (test, capture, trace or measurement) in the commit message.
- Guessed numbers are labeled with their source and evidence kind.
- After each step, add what was learned in practice to LEARNINGS.md.
- Pin exact dependency versions; upgrade one at a time.
