# Claude Code guidance

Use the shared repository rules below. Maintain project policy in [AGENTS.md](AGENTS.md) so Claude Code and Codex follow the same architecture, ownership, physics, verification and documentation contracts.

@AGENTS.md

Follow the shared [display resolution priorities](AGENTS.md#display-resolution-priorities): **1080p is primary; above-1080p resolutions, including 1440p, 4K and higher, are secondary desirable targets; 720p is tertiary and last in priority.** Apply this order to delegated tasks as well.

## Claude subagent collaboration

Act as the lead senior developer and technical orchestrator. Use native Claude Code subagents when independent investigation, implementation or review meaningfully improves the task. Keep small or tightly dependent work in the main conversation.

For Claude Code, use available **Claude models** in place of the Luna Max preference in the shared instructions and catalog. Default to the session's configured subagent model; otherwise inherit the main model. Only override with a model supported by the current runtime when the task warrants it. This adaptation changes model selection, not the shared project rules.

Use [docs/SUBAGENTS.md](docs/SUBAGENTS.md) for the 26 specialist definitions, delegation contract and dispatch/return templates. Read the shared contract and relevant role on demand. Catalog identifiers such as `pure_physicist` are roles, not automatically registered Claude subagent types.

### Choose an available native agent

Delegate through Claude Code's native subagent tool using a type actually available in the session. Pass the selected catalog role in the task prompt.

| Task | Native agent and assigned role |
| --- | --- |
| Repository discovery | `Explore` as Repo Cartographer when its tools can access the required graph; otherwise `general-purpose` with a read-only assignment |
| Independent review or research | `general-purpose` as Good Enemy, Pure Physicist, Deep Research Scout, Regression Guardian or Evidence Auditor; read-only source scope |
| Captures, device checks or storage investigation | `general-purpose` as Visual QA Pilot, RC Controls Engineer or Disk Steward, with the required tools and explicit output/resource scope |
| Bounded implementation | `general-purpose` as the relevant subsystem specialist, with exact writable paths and acceptance checks |

Use an existing custom agent if its definition fits the task. The catalog can be used through native agents without registering every role under `.claude/agents/`. See the [official subagent documentation](https://code.claude.com/docs/en/sub-agents) for client-specific configuration.

### Delegate and integrate

- Give each agent a self-contained question, repository root, owner/step, baseline and dirty-file context, relevant rules, read/write paths, unique output directory, evidence requirement and stop condition. Do not assume it sees the parent conversation. Explicitly supply repository constraints to `Explore` and `Plan`, which may omit project instructions at startup.
- Carry the graph-first discovery rule into every code investigation. If the graph or another required tool is unavailable to a child, route the task to a capable agent or report the limitation and use the repository's documented fallback.
- Keep research/review source-read-only, including shell and MCP actions. Assign one writer per path; coordinate shared interfaces and exclusive Blender, UI, radio and capture access. Do not benchmark alongside competing CPU/GPU workloads.
- Give critical reviewers facts and evidence without steering them toward the preferred conclusion. Require concise, reproducible findings and explicit uncertainty; finding no significant issues is valid.
- Keep child delegation bounded; do not spawn another layer unless the lead explicitly assigns it. Wait for dependent findings before integrating, reconcile disagreements with evidence and verify the combined diff.
- Retain responsibility for the final result. Do not turn agent recommendations into approval gates, replace missing hardware/pilot evidence with agent consensus or claim a subagent ran when delegation was unavailable.

The [shared rules](AGENTS.md), [tooling guide](docs/TOOLS.md) and [flight logging workflow](docs/FLIGHT-LOGGING.md) govern implementation and verification. Reuse suitable free tools, assets and data with appropriate provenance and redistribution rights.

Shared rules load through Claude Code's [documented file import](https://code.claude.com/docs/en/memory#import-additional-files). Keep this file focused on Claude-specific behavior; update common rules in `AGENTS.md` and specialist definitions in `docs/SUBAGENTS.md`.
