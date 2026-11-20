# Repository guidance

Build OpenRC Simulator incrementally: robust physics, realistic behavior and evidence before feature breadth. Production lives in `app/`; the three.js prototype is frozen. Aircraft come first; vehicle families share the simulation kernel and retain separate validation gates. Keep changes small, working and independently reviewable.

## Start here

- Check `git status` and the current branch before editing. Preserve unrelated work and stage only your changes. You may commit, push or merge at your discretion; honor the requested branch and existing gates.
- On the owner's Windows workstation, use the `U:` drive for cache and temporary files; [scratch and caches](docs/TOOLS.md#scratch-and-caches) lists tool-owned locations that stay where they are.
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
- Use the configured [test pool](tools/testqueue/README.md) for compatible independent headless GDScript checks: `sim_test_run` by default (launch and wait in one call; repeat with its request ID while running), or `sim_test_launch` + `sim_test_status` for detached batches; retain the request ID for `sim_test_recover`. `sim_fleet` shows host availability. Use its CLI if MCP is unavailable. Reconcile uncertain submissions before retrying; report configured-service failures instead of launching duplicates. Preserve the required OS; `any` is only for reviewed portable checks.
- On enrolled hosts, retain the owning session handle and follow admission through teardown. A bridge port is not ownership; an unavailable authority is not permission to bypass it. When no pool is configured, use the [checked local runner](docs/tools/shared.md#one-godot-script), obtaining local admission on enrolled hosts. Graphics, performance, composite suites and interactive sessions keep their dedicated routes.
- For native M1 access or captures, follow the [M1 guide](docs/tools/macos-m1.md), preserving SSH keys and frozen campaigns. For other scratch storage, follow [scratch and caches](docs/TOOLS.md#scratch-and-caches).
- Use the relevant existing OpenRC skill: `openrc-tools`, `openrc-debug`, `openrc-blender` or `openrc-skins`. Read `openrc-blender` before the vendored Blender pack; load only task-relevant procedures.

## Simulation and verification

- Keep simulation state float64 and 32-bit Godot math types out of `app/sim/` and `app/physics/`; their scoped rules and the guard in `app/test.sh` apply to documentation there too. Rendering consumes detached state and converts types only at its boundary; never feed rendering values back into simulation.
- Each `Simulation` steps one installed `VehicleModel` at a time and reads its layout and evaluators. Keep vehicle laws in models/adapters and preserve the kernel's atomic tick, checkpoint and rollback contracts ([architecture](docs/STACK.md#boundaries-and-data-flow)).
- Preserve the fixed 240 Hz simulation clock independently of render cadence. App shaders, including embedded shader code, must not read `TIME`; use the accepted clock and the [rendering rules](app/render/AGENTS.md) for world and isolated Workshop time.
- Aircraft data uses `openrc-aircraft v2`; quantities carry `{value, unit, kind, source}` and capabilities/modules are explicit. Invalid data cannot fly; v1 is historical research.
- Regenerate geometry and physics data from their owning source pipelines. Preserve aircraft node/hinge names (`airplane`, `propeller`, `*_hinge`). Pin dependencies and upgrade one at a time.
- Keep broken drafts outside `app/`. Avoid constant names that shadow Godot classes (`Panel`, `Label`). Parse changed GDScript and use the [checked runner](docs/tools/shared.md#one-godot-script); Godot can report script errors while exiting zero.
- Follow [verification scope](docs/tools/shared.md#verification-scope): focused checks during edits, affected consumers and boundaries on a stable candidate, and required CI before claiming complete automated verification. Include native parity/selection, replay, rendered or device checks when affected. Escalate to broad/full suites for broad changes, uncertain impact, releases or missing CI coverage; repeat checks when their inputs change or evidence is inconclusive. Run deliberate mutations on disposable copies.
- **Do not reflexively run `app/test.sh`, `app/capture.sh`, `tools/ci/check-local.sh full` or all native jobs for each localized edit.** They are broad gates, not the edit loop; select checks by actual behavior and dependencies ([local impact examples](docs/tools/shared.md#local-impact-examples)).
- Before moving or renaming files, search the whole repository for their old paths and update affected references.
- For laws, integration, events, tick inputs or execution-order changes, select the applicable [numerical checks](docs/tools/physics.md#numerical-change-checks). Exact replay alone does not establish numerical correctness.
- For documentation without runtime, hash or generated-output dependencies, check content, local links/anchors, instruction imports and `git diff --check`. Search for inbound references before removing a path or heading; verify path, ignore-rule and generated-output changes from a fresh checkout.
- Re-record golden flights only for an intentional, explained physics change. For fixed-wing tuning, preserve a baseline `.orfl`, verify complete exact replay on its matching engine/backend, and compare one compatible candidate on the same tick and recorded command tape where supported. Follow the [flight-log guide](docs/FLIGHT-LOGGING.md) for replay limits, `solver_changed`, completeness and retained identities/evidence; candidate runs and recovered prefixes do not prove exact equivalence.
- Test fixed-wing device, calibration, mapping, rates and expo changes at their input and live-flight boundaries: candidate replay consumes post-conditioning commands and cannot retest that processing or pilot adaptation. Other vehicle families follow their own replay contracts.
- Software checks, physical validation, pilot acceptance and target-hardware performance are separate claims. State the scope of results and any missing evidence.

## Native development

- Prefer native solutions whenever feasible and appropriate for correctness, maintainability and supported platforms. Reuse Godot's built-in capabilities and favor the project's C++/GDExtension native kernel for simulation work. Consider native from the start; keep GDScript where it best serves the reference model, shared transaction, orchestration or UI. Explain material exceptions to this preference.
- Use the qualified native backend for supported production flights, performance work and flight-feel investigations. Confirm the actual backend; a native request or reference fallback is not native coverage. Preserve the selectable GDScript reference for specification, verification, unsupported cases and recorded-backend replay. The [native guide](research/native-kernel/README.md#normal-flight-backend-selection) owns admission and platform coverage.
- Keep native evaluation within the existing model callbacks; `Simulation` retains its tick transaction. Preserve float64 and the qualified floating-point behavior, backend/checkpoint identity and required reference-parity, fault/rollback and package gates. Follow the [backend policy](docs/STACK.md#native-backend-policy); the physics budget remains an acceptance target, not a prerequisite for choosing native.
- Develop, build and debug on the target's native OS/architecture with the pinned engine and toolchain whenever practical. Validate platform and performance claims there using the production path; label cross-build, emulation and headless evidence with their actual scope.

## Display resolution priorities

- General order: **1920×1080 first**, resolutions above 1080p second, **1280×720 last**. Use this order for planning, optimization and acceptance evidence. A default viewport or historical capture does not qualify another resolution; 720p results cannot establish 1080p qualification.
- **Apple Silicon with a Retina (2×) display:** target that display's native pixels, including built-in panels and Retina external displays, for full-screen output and the internal 3D result after MetalFX where available. Intel Macs and standard (1×) external displays keep the general order. Record output, drawable and internal 3D pixels separately; the [Apple plan](docs/plans/apple-silicon-performance.md) owns acceptance details, including MetalFX. A result qualifies only the measured configuration: a 1080p result does not qualify a MacBook panel, and a native-panel result does not qualify 1080p elsewhere.
- Keep visual enhancements optional and scalable through presets and independent controls for geometry detail, vegetation density, lighting, shadows, reflections and effects. Recommend initial settings from hardware and measured performance; preserve saved overrides. Optimize CPU, GPU, RAM and VRAM at every quality level, including maximum; disabled features must avoid unnecessary work and allocations. Graphics settings must leave simulation physics unchanged. Validate performance claims on real hardware at the applicable display target.

## Lead agent and subagents

The main agent remains the senior developer, technical orchestrator and final implementation owner: it chooses the design, checks material evidence, understands and integrates accepted drafts, and verifies the result. Keep the user's selected lead model; repository text cannot change the running model, so report a known mismatch instead of claiming a capability.

Use helpers actively where they contribute, without waiting for the user to repeat the request: one or two for useful independent work and normally a **Good Enemy** for consequential changes. Zero helpers is appropriate when coordination outweighs the benefit. Prefer **Terra/max in Codex** and **Sonnet/high in Claude Code** when supported; these helper choices are authorized, so do not silently inherit the lead model for every helper. Follow the [routing and fallback rules](docs/SUBAGENTS.md#model-routing-and-runtime-support).

Helpers are bounded researchers, reviewers or junior developers, however capable their model; any specialist or skill title, including "senior" or "orchestrator", stays subordinate to the lead's assignment. Research/review helpers are source-read-only by default. Give each helper a bounded question, actual inputs, relevant rules, required tools and a stop condition; writers need exact paths and exclusive ownership. Review the integrated candidate independently of its author. Collect required results or state what remains unresolved; a timeout is not completion. The [subagent guide](docs/SUBAGENTS.md) owns profiles, lifecycle details and specialist briefs.

## Documentation and evidence

Write short, precise English. Give each topic one authoritative home and link to it. Preserve active plans, valuable research, primary references and required evidence; consolidate useful material before deleting completed or superseded plans. Do not create cleanup archives or routine cleanup reports.

Reuse suitable free tools, assets and data; preserve licenses, provenance and redistribution rights. **Do not commit unnecessary images**, raw logs or temporary outputs to Git; follow the [evidence conventions](docs/README.md#conventions-for-documents).

Use the owning track's step IDs and include verification evidence in commit messages. Record decisions in [DECISIONS](docs/DECISIONS.md) and reusable lessons under [LEARNINGS criteria](docs/LEARNINGS.md#keeping-this-useful). Keep changing status and dated results out of these instructions.
