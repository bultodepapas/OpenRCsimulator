# Repository guidance

Build OpenRC Simulator incrementally: robust physics, realistic behavior and evidence before feature breadth. Production lives in `app/`; the three.js prototype is frozen. Aircraft come first; vehicle families share the simulation kernel and retain separate validation gates. Keep changes small, working and independently reviewable.

## Start here

- Check `git status` and the current branch before editing. Preserve unrelated work and stage only your changes. Commits, pushes and merges are permitted within the user's requested scope; honor the requested branch and existing gates.
- Before editing a path, read the applicable nested `AGENTS.md` files between the repository root and that path. A session started at the root may not have loaded them. Pass relevant scoped rules to helpers.
- Current code, configuration and accepted data establish implemented behavior. Plans describe remaining work; dated research records evidence. Read the documents needed for the task:

| Task | Read |
| --- | --- |
| Setup, launch, dependencies or exports | [Tooling guide](docs/TOOLS.md) |
| Architecture or shared interfaces | [STACK](docs/STACK.md); [track ownership](docs/README.md#tracks-plans-and-step-ids) |
| Godot scenes, resources or worker jobs | [Godot runtime boundaries](docs/STACK.md#godot-runtime-boundaries) |
| Choose a test, capture or debugging tool | [Tool index](docs/tools/README.md); [verification scope](docs/tools/shared.md#verification-scope) |
| Aircraft data, geometry or generators | [Aircraft contract](docs/AIRCRAFT_CONTRACT.md); the owning aircraft guide |
| Flight handling, controls or physics tuning | [Flight logging workflow](docs/FLIGHT-LOGGING.md) |
| Delegate research, drafts or review | [Subagent guide](docs/SUBAGENTS.md) |
| Update documentation or instructions | [Documentation map and conventions](docs/README.md) |

For a fresh checkout, follow [developer setup](docs/TOOLS.md#developer-setup). These Bash commands use the repository's pinned engine; shared-host launches also require the admission rules below:

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --import
"$(app/get-godot.sh)" --path app
```

## Discover code

Use codebase-memory-mcp when available: `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, then `get_architecture`; create a missing index when supported. Verify graph results against current source. Use `rg` for literals, configuration and non-code files, or when the graph tool is unavailable or insufficient.

## Tools

- Reuse the [tool index](docs/tools/README.md) before writing an ad-hoc probe. For a running app, use the [debug bridge](tools/debug/README.md); `python3 tools/debug/debugctl.py smoke` checks its regression flow.
- Use the configured [test pool](tools/testqueue/README.md) for compatible independent headless GDScript checks: `sim_test_launch`, then `sim_test_status`; retain the request ID for `sim_test_recover`. Use its CLI if MCP is unavailable. Reconcile uncertain submissions before retrying; report configured-service failures instead of launching duplicates. Preserve the required OS; `any` is only for reviewed portable checks.
- On enrolled hosts, retain the owning session handle and follow admission through teardown. A bridge port is not ownership; an unavailable authority is not permission to bypass it. When no pool is configured, use the [checked local runner](docs/tools/shared.md#one-godot-script), obtaining local admission on enrolled hosts. Graphics, performance and interactive work keep their dedicated routes.
- For native M1 access or captures, follow the [M1 guide](docs/tools/macos-m1.md), preserving SSH keys and frozen campaigns. For scratch storage, including the owner's Windows `U:` preference, use [scratch and caches](docs/TOOLS.md#scratch-and-caches).
- Use the relevant existing OpenRC skill: `openrc-tools`, `openrc-debug`, `openrc-blender` or `openrc-skins`. Read `openrc-blender` before the vendored Blender pack; load only task-relevant procedures.

## Simulation and verification

- Keep simulation state float64 and do not introduce 32-bit Godot math types in `app/sim/` or `app/physics/`. The guard in `app/test.sh` scans for noncomment matches of `Vector2`, `Vector3`, `Vector4`, `Basis`, `Quaternion` and `Transform3D` anywhere under `app/sim/` and `app/physics/`, including Markdown. Convert to rendering types only at the boundary; never feed rendering values back into simulation.
- Install one `VehicleModel` per session. The shared kernel reads layout and evaluators from that model; keep vehicle-specific laws and branches outside the kernel ([contract](docs/STACK.md#boundaries-and-data-flow)).
- Aircraft data uses `openrc-aircraft v2`; quantities carry `{value, unit, kind, source}` and capabilities/modules are explicit. Invalid data cannot fly; v1 is historical research.
- Regenerate geometry and physics data from their owning source pipelines. Preserve aircraft node/hinge names (`airplane`, `propeller`, `*_hinge`). Pin dependencies and upgrade one at a time.
- App shaders, including embedded shader code, must not read `TIME`. Use the accepted simulation clock; [rendering rules](app/render/AGENTS.md) describe world and isolated Workshop clocks. Do not name constants after Godot classes such as `Panel` or `Label`.
- Keep broken drafts outside `app/`. Parse changed GDScript and select existing checks by affected behavior and consumers. Use the checked runner because Godot can report script errors while exiting zero.
- Follow [verification scope](docs/tools/shared.md#verification-scope): focused checks during edits, affected boundaries on a stable candidate, and required CI before claiming complete automated verification. Full app/capture/native suites are for broad changes, uncertain impact, releases or missing CI coverage; do not repeat unchanged checks without a reason. Run deliberate mutations on disposable copies.
- Documentation-only changes need content, local-link/anchor and import checks plus `git diff --check`. Search for inbound references before removing a path or heading; verify path, ignore-rule and generated-output changes from a fresh checkout.
- Re-record golden flights only for an intentional, explained physics change. For handling/controls/physics tuning, preserve a baseline `.orfl`, verify exact replay and compare one explicit candidate using the same tick/input tape. Retain source/config identities, markers, CSV and reports with the owning track's evidence; check `solver_changed` and `complete` as specified in the [flight-log guide](docs/FLIGHT-LOGGING.md). Keep recording read-only and bounded; recovered prefixes and candidate runs do not prove exact equivalence.
- Software checks, physical validation, pilot acceptance and target-hardware performance are separate claims. State the scope of results and any missing evidence.

## Display resolution priorities

- General order: **1920×1080 first**, resolutions above 1080p second, **1280×720 last**. A default viewport or historical capture does not qualify another resolution.
- **Apple Silicon with a Retina (2×) display:** target that display's native pixels, including built-in panels and Retina external displays, for full-screen output and the internal 3D result after MetalFX where available. Intel Macs and standard (1×) external displays keep the general order. Record output, drawable and internal 3D pixels separately; the [Apple plan](docs/plans/apple-silicon-performance.md) owns acceptance details, including MetalFX. A result qualifies only the measured configuration.
- Keep visual enhancements optional and scalable through presets and independent controls for geometry detail, vegetation density, lighting, shadows, reflections and effects. Recommend initial settings from hardware and measured performance; preserve saved overrides. Optimize CPU, GPU, RAM and VRAM at every quality level, including maximum; disabled features must avoid unnecessary work and allocations. Graphics settings must leave simulation physics unchanged. Validate performance claims on real hardware at the applicable display target.

## Lead agent and subagents

The main agent remains the senior developer and final implementation owner: it chooses the design, checks material evidence, understands and integrates accepted drafts, and verifies the result. Keep the user's selected lead model; repository text cannot change the running model.

Use one or two helpers for useful independent work and normally a **Good Enemy** for consequential changes. Zero helpers is appropriate when coordination outweighs the benefit. Prefer **Terra/max in Codex** and **Sonnet/high in Claude Code** when supported, following the [routing and fallback rules](docs/SUBAGENTS.md#model-routing-and-runtime-support).

Research/review helpers are source-read-only by default. Give each helper a bounded question, actual inputs, relevant rules, required tools and a stop condition; writers need exact paths and exclusive ownership. Review the integrated candidate independently of its author. Collect required results or state what remains unresolved; a timeout is not completion. The [subagent guide](docs/SUBAGENTS.md) owns profiles, lifecycle details and specialist briefs.

## Documentation and evidence

Write short, precise English. Give each topic one authoritative home and link to it. Preserve active plans, valuable research, primary references and required evidence; consolidate useful material before deleting completed or superseded plans. Do not create cleanup archives or routine cleanup reports.

Reuse suitable free tools, assets and data; preserve licenses, provenance and redistribution rights. Keep unnecessary images, raw logs and temporary outputs out of Git; follow the [evidence conventions](docs/README.md#conventions-for-documents).

Use the owning track's step IDs and include verification evidence in commit messages. Record decisions in [DECISIONS](docs/DECISIONS.md) and reusable lessons under [LEARNINGS criteria](docs/LEARNINGS.md#keeping-this-useful). Keep changing status and dated results out of these instructions.
