# Repository guidance

Build an RC airplane simulator incrementally. Prioritize robust physics, realistic flight behavior and evidence over feature breadth. The simulation kernel is a platform for every vehicle type, aircraft first: vehicle breadth enters only through the shared kernel and its contracts ([kernel contract](docs/STACK.md#boundaries-and-data-flow)), and each vehicle keeps its own validation gates. Keep each change small, working and independently reviewable. Use Terra 6.1 Max sub-agents when useful and assign clear file boundaries.

When delegating, use the [subagent collaboration guide](docs/SUBAGENTS.md) for specialist roles, task boundaries and evidence handoffs. Select only the specialists useful for the current task. Amost always use at least one extra sub agent the GOOD ENEMY.

do not create thing that you can free download

## Display resolution priorities

1. **Primary target: 1920×1080 (1080p).** Prioritize rendering, UI readability, visual quality and performance qualification at this resolution.
2. **Secondary desirable targets: resolutions above 1080p**, including 1440p and 4K (and higher). Pursue these after the primary target.
3. **Tertiary target: 1280×720 (720p), last in priority.** Treat it as a fallback/compatibility objective, after 1080p and higher-resolution objectives.

Use this order for planning, optimization and acceptance evidence. A 720p viewport default, capture fixture or historical benchmark does not make 720p the product target; 720p results cannot establish 1080p qualification. These are development priorities, not claims that any resolution is already qualified on particular hardware.

## Tools

- Shared-host launch admission and session ownership: [test queue](tools/testqueue/README.md).
  On enrolled hosts use the returned session handle; a bridge port alone is not ownership.

- Find the tool for your task in the [tool index](docs/tools/README.md) before writing ad-hoc test, probe or debug code.
- For M1 access, native Mac tests or captures, read the [shared M1 guide](docs/tools/macos-m1.md): SSH, installed tools, isolated workspaces and evidence retention. Preserve its existing SSH keys and frozen campaigns.
- To inspect or drive a running app (state, live log, menus, keys, sticks, pause/step, screenshots, hitches, leaks,
  watchpoints, UI fuzzing), use the [debug bridge](tools/debug/README.md) instead of ad-hoc probes or mouse automation.
  `python3 tools/debug/debugctl.py smoke` is the one-command regression pass for the running app.
- Agent skills: `openrc-tools` (which tool for which task), `openrc-debug` (the running app) and `openrc-blender`
  (Blender work, before the vendored blender-skills pack; [tools/blender](tools/blender/README.md)), in `.claude/skills/`
  and `.agents/skills/`.

## Start here

- [STACK.md](docs/STACK.md): current architecture and dependencies.
- [docs/TOOLS.md](docs/TOOLS.md): setup, commands, tests, captures and exports.
- [docs/README.md](docs/README.md#tracks-plans-and-step-ids): track ownership and documentation homes.
- [ROADMAP.md](ROADMAP.md): main-line steps and acceptance gates.
- [AIRCRAFT_CONTRACT.md](docs/AIRCRAFT_CONTRACT.md): aircraft authoring and extension rules.
- [LEARNINGS.md](docs/LEARNINGS.md): reusable technical lessons.

The production application is `app/`. The three.js bake-off in `prototypes/stage0/three/` is frozen. Runtime code, configuration and accepted data define implemented behavior; plans describe remaining work, and research records dated evidence.

Make visual enhancements optional and scalable from modest computers to high-end PCs through quality presets and independent controls for geometry detail, vegetation density, lighting, shadows, reflections and effects. Recommend an initial preset using detected hardware and measured performance, and preserve saved user overrides. Optimize CPU, GPU, RAM and VRAM use at every quality level, including maximum settings; disabled features must avoid unnecessary processing and memory allocations. Graphics settings must leave simulation physics unchanged. Validate performance on real hardware, following the 1080p-first resolution priorities above.

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
- Keep drafts outside `app/` until they parse. Follow the [verification scope](docs/tools/shared.md#verification-scope): **select local checks by actual behavior and dependencies, not by habit**. Parse modified GDScript, run the smallest relevant existing tests while editing, and verify affected consumers and boundaries on a stable candidate. For Home/menu-only changes, prefer UI/layout tests and targeted visual review; for radio calibration, prefer calibration/profile/controller tests. See [local impact examples](docs/tools/shared.md#local-impact-examples).
- **Do not reflexively run `app/test.sh`, `app/capture.sh`, `tools/ci/check-local.sh full` or all native jobs for each localized edit.** Those are broad verification gates, not the default edit loop. Escalate to local full coverage for shared/cross-cutting changes, uncertain dependencies, release preparation, or when required CI cannot qualify the candidate. Re-run an unchanged check only after changed inputs, failure or inconclusive evidence. `app/test.sh` in full mode parses every GDScript file; required CI currently retains full production coverage in shadow mode. Focused local checks never replace required CI. Run deliberate mutations on disposable copies.
- Re-record golden flights only for an intentional, explained physics change. Software verification does not establish physical validation.
- For flight-feel, controls or aircraft-physics tuning, use the [flight logging workflow](docs/FLIGHT-LOGGING.md): preserve a baseline `.orfl`, verify exact replay, then compare one explicit candidate using the same tick/input tape. Retain source/config identities, markers, CSV and reports with the owning track's evidence. Check `solver_changed` and `complete`; recovered prefixes and candidate runs never establish exact equivalence or physical realism. Keep the recorder read-only and bounded; use existing free plotting tools for visualization.
- Before moving or renaming files, search the whole repository for their old paths. Update affected references. Verify path, ignore-rule and generated-output changes from a fresh clone.
- Pin exact dependency versions and upgrade one at a time.

## Documentation and evidence

Write documentation in English, short and precise. Give each topic one authoritative home and link to it. Preserve valuable research, primary references and technical findings under `docs/research/`; keep dated evidence distinct from current operating instructions.

Use the owning track's step IDs. Include proof in commit messages: test, capture, trace or measurement. Record reusable lessons using [LEARNINGS.md's criteria](docs/LEARNINGS.md#keeping-this-useful); routine results belong in the existing evidence report. Record design decisions in [DECISIONS.md](docs/DECISIONS.md).

Keep active plans and required evidence. Once a plan is complete or superseded, consolidate needed rationale and links into its canonical guide or existing evidence, then delete it. Do not create new archives or cleanup reports. Follow the [documentation conventions](docs/README.md#conventions-for-documents).

DO NOT SAVE INNESARY IMAGES IN THE GIT REPO.
