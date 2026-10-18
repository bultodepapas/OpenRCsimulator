# Repository guidance

Build an RC airplane simulator incrementally. Prioritize robust physics, realistic flight behavior and evidence over feature breadth. The simulation kernel is a platform for every vehicle type, aircraft first: vehicle breadth enters only through the shared kernel and its contracts ([kernel contract](STACK.md#boundaries-and-data-flow)), and each vehicle keeps its own validation gates. Keep each change small, working and independently reviewable. Use Luna Max sub-agents when useful and assign clear file boundaries.


do not creat thing that you can free download

## Start here

- [STACK.md](STACK.md): current architecture and dependencies.
- [docs/TOOLS.md](docs/TOOLS.md): setup, commands, tests, captures and exports.
- [docs/README.md](docs/README.md#tracks-plans-and-step-ids): track ownership and documentation homes.
- [ROADMAP.md](ROADMAP.md): main-line steps and acceptance gates.
- [AIRCRAFT_CONTRACT.md](AIRCRAFT_CONTRACT.md): aircraft authoring and extension rules.
- [LEARNINGS.md](LEARNINGS.md): reusable technical lessons.

The production application is `app/`. The three.js bake-off in `prototypes/stage0/three/` is frozen. Runtime code, configuration and accepted data define implemented behavior; plans describe remaining work, and research records dated evidence.

## Discover code

 

Prefer codebase-memory-mcp: `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, then `get_architecture`. Index the repository first if absent. Stored line ranges may lag the working tree; verify the current source before editing. Use `rg` for literals, configuration, non-code files or insufficient graph results.

## Preserve parallel work

Several tracks share this tree. Read `git status` before editing, especially shared documentation or runtime integration files. Preserve all unrelated edits; stage only your own paths. Consult the [ownership registry](docs/README.md#tracks-plans-and-step-ids) and coordinate shared interfaces with their owners.

Keep aircraft node/hinge names (`airplane`, `propeller`, `*_hinge`) stable. Generated aircraft geometry and physics data must be regenerated through their source pipelines, never hand-edited. Each aircraft guide identifies its generator.

## Simulation and verification

- State in `app/sim/` and `app/physics/` uses 64-bit GDScript `float` and packed float64 arrays. Do not use `Vector3`, `Basis`, `Quaternion` or `Transform3D` for simulation state. Rendering converts at the boundary.
- Aircraft data uses `openrc-aircraft v2`; quantities carry `{value, unit, kind, source}`. Capabilities and conditional modules are explicit. Invalid data cannot fly. V1 is an explicit historical-research path.
- Do not name constants after built-in classes such as `Panel` or `Label`.
- A session installs one `VehicleModel` (`app/sim/vehicle_model.gd`) into `Simulation`; the kernel reads layout and evaluators only from that model. Do not add vehicle-specific branches or callbacks to the kernel.
- Keep drafts outside `app/` until they parse. `app/test.sh` parses every GDScript file; validate scripts before integration and run the relevant checks after integration. Run deliberate mutations on disposable copies.
- Re-record golden flights only for an intentional, explained physics change. Software verification does not establish physical validation.
- For flight-feel, controls or aircraft-physics tuning, use the [flight logging workflow](docs/FLIGHT-LOGGING.md): preserve a baseline `.orfl`, verify exact replay, then compare one explicit candidate using the same tick/input tape. Retain source/config identities, markers, CSV and reports with the owning track's evidence. Check `solver_changed` and `complete`; recovered prefixes and candidate runs never establish exact equivalence or physical realism. Keep the recorder read-only and bounded; use existing free plotting tools for visualization.
- Before moving or renaming files, search the whole repository for their old paths. Update affected references. Verify path, ignore-rule and generated-output changes from a fresh clone.
- Pin exact dependency versions and upgrade one at a time.

## Documentation and evidence

Write documentation in English, short and precise. Give each topic one authoritative home and link to it. Preserve valuable research, primary references and technical findings under `docs/research/`; keep dated evidence distinct from current operating instructions.

Use the owning track's step IDs. Include proof in commit messages: test, capture, trace or measurement. Record reusable lessons using [LEARNINGS.md's criteria](LEARNINGS.md#keeping-this-useful); routine results belong in the existing evidence report. Record design decisions in [DECISIONS.md](DECISIONS.md).

Keep active plans and required evidence. Once a plan is complete or superseded, consolidate needed rationale and links into its canonical guide or existing evidence, then delete it. Do not create new archives or cleanup reports. Follow the [documentation conventions](docs/README.md#conventions-for-documents).
