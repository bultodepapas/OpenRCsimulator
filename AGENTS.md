# Repository guidance

Build an RC airplane simulator incrementally. Prioritize robust physics, realistic flight behavior and evidence over feature breadth. The simulation kernel is a platform for every vehicle type, aircraft first: vehicle breadth enters only through the shared kernel and its contracts ([kernel contract](docs/STACK.md#boundaries-and-data-flow)), and each vehicle keeps its own validation gates. Keep each change small, working and independently reviewable.

Use U drive as cache and temp.
you are allowed to make commit or push or merge if you want to.


## Lead agent and subagents

The **main conversation's agent is the senior developer, technical orchestrator and final implementation owner**. The intended lead is the user's selected highest-capability reasoning model. Keep that lead responsible for architecture, difficult reasoning, the definitive code, integration and verification throughout the task. Repository instructions cannot upgrade a running model; report a known mismatch instead of claiming a capability or silently switching the lead to a helper model.

- **Use helpers actively where they contribute.** For substantial work, identify independent questions and dispatch one or two helpers whose results can change a decision; continue useful lead work in parallel. Normally include a **Good Enemy** for consequential code, architecture or agent-policy changes. Use zero helpers when work is short, tightly dependent or the setup/reconciliation cost exceeds the useful contribution; explain a material limitation. An existing tool or skill may already solve the step. Do not wait for the user to repeat this delegation request.
- **Select helper models explicitly.** Prefer **GPT-6.1 Terra with `max` reasoning in Codex** and **Sonnet with `high` effort in Claude Code**, when supported, especially for consequential uncertainty, substantive drafts and critical review. These are authorized helper choices. The lead may deliberately choose lighter supported effort for a bounded task with trustworthy acceptance checks and escalate if evidence is inadequate. Use the [model routing and fallback rules](docs/SUBAGENTS.md#model-routing-and-runtime-support); requested settings are not proof of the effective runtime or correctness.
- **Helpers supply evidence and drafts.** Treat subagents as bounded researchers, reviewers, assistants or junior developers, even when their model is highly capable. They investigate, compare alternatives, calculate, propose tests and return candidate patches. Any specialist or skill title, including "senior" or "orchestrator", remains subordinate to the main lead's assignment.
- **The lead produces the final solution.** Check material claims against their original evidence, resolve disagreements, and understand, deliberately accept/adapt, integrate and verify every accepted draft. Reviewed code may be applied directly. Distinguish requirements and concrete defects from optional preferences; a clean review is valid. Helper confidence, agreement or a passing report cannot replace inspection of the actual integrated candidate.
- **Match capabilities and bound authority.** Research, review and returned drafts are source-read-only by default. Check that the chosen helper actually has the tools its assignment needs. Any execution or file-writing assignment needs exact paths, the actual source/input state, resource ownership and a stop condition. Preserve permissions and user authorization. Track required results through assessment, independent resolution or an explicit unresolved limit; a timeout is not completion.

Use the [subagent collaboration guide](docs/SUBAGENTS.md) for the workflow, runtime profiles, 26 specialist roles and dispatch/return templates. [CLAUDE.md](CLAUDE.md) adapts the same policy for Claude Code. Load only the relevant specialist detail.

Reuse suitable freely available tools, assets and data before creating equivalents; preserve provenance and redistribution rights.

## Display resolution priorities

1. **Primary target: 1920×1080 (1080p).** Prioritize rendering, UI readability, visual quality and performance qualification at this resolution.
2. **Secondary desirable targets: resolutions above 1080p**, including 1440p and 4K (and higher). Pursue these after the primary target.
3. **Tertiary target: 1280×720 (720p), last in priority.** Treat it as a fallback/compatibility objective, after 1080p and higher-resolution objectives.

Use this order for planning, optimization and acceptance evidence. A 720p viewport default, capture fixture or historical benchmark does not make 720p the product target; 720p results cannot establish 1080p qualification. These are development priorities, not claims that any resolution is already qualified on particular hardware.

**Exception: Apple Silicon Macs on a Retina (2× backing scale) display.** This covers every MacBook Air/Pro and iMac built-in panel, and Retina external displays. The target is the display's **native pixel resolution** (for example 2560×1600, 2880×1864, 3024×1964, 3456×2234), not 1080p. On these Macs, performance assumptions, automatic defaults and acceptance evidence use the native panel. That includes full-screen output and the internal 3D resolution after MetalFX, where MetalFX is available. Godot reports the backing store, which can exceed the physical panel at scaled "looks like" modes. A 1080p result does not qualify a MacBook panel, and a native-panel result does not qualify 1080p elsewhere. Intel Macs, Macs on standard (1×) external displays, and every other system keep the 1080p-first order above. Record output, drawable and internal 3D pixels separately. The [Apple plan](docs/plans/apple-silicon-performance.md) owns Mac acceptance details.

## Tools

- Shared-host launch admission and session ownership: [test queue](tools/testqueue/README.md).
  On enrolled hosts use the returned session handle; a bridge port alone is not ownership.
- Route compatible independent headless GDScript checks through `sim_test_run` by default (launch
  and wait in one call; repeat with its request ID while running), or `sim_test_launch` +
  `sim_test_status` for detached batches; `sim_fleet` shows host availability.
  Use the [test pool CLI](tools/testqueue/README.md) if MCP is unavailable. Preserve the
  required OS; declare `any` only for reviewed portable checks. Graphics, performance,
  composite suites and interactive sessions retain their existing tool and admission paths.

- Find the tool for your task in the [tool index](docs/tools/README.md) before writing ad-hoc test, probe or debug code.
- For M1 access, native Mac tests or captures, read the [shared M1 guide](docs/tools/macos-m1.md): SSH, installed tools, isolated workspaces and evidence retention. Preserve its existing SSH keys and frozen campaigns.
- To inspect or drive a running app (state, live log, menus, keys, sticks, pause/step, screenshots, hitches, leaks,
  watchpoints, UI fuzzing), use the [debug bridge](tools/debug/README.md) instead of ad-hoc probes or mouse automation.
  `python3 tools/debug/debugctl.py smoke` is the one-command regression pass for the running app.
- Agent skills: `openrc-tools` (which tool for which task), `openrc-debug` (the running app), `openrc-blender`
  (Blender work, before the vendored blender-skills pack; [tools/blender](tools/blender/README.md)) and `openrc-skins`
  (vehicle skins, liveries, decals and material finishes; [tools/skins](tools/skins/README.md)), in `.claude/skills/`
  and `.agents/skills/`.

## Start here

- [STACK.md](docs/STACK.md): current architecture and dependencies.
- [docs/TOOLS.md](docs/TOOLS.md): setup, commands, tests, captures and exports.
- [docs/README.md](docs/README.md#tracks-plans-and-step-ids): track ownership and documentation homes.
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
