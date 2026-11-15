# Claude Code guidance

Use the shared repository rules below. Maintain project policy in [AGENTS.md](AGENTS.md) so Claude Code and Codex follow the same architecture, ownership, physics, verification and documentation contracts.

@AGENTS.md

Follow the shared [display resolution priorities](AGENTS.md#display-resolution-priorities): **1080p is primary; above-1080p resolutions, including 1440p, 4K and higher, are secondary desirable targets; 720p is tertiary and last in priority.** Apply this order to delegated tasks as well.

## Claude subagent collaboration

In the main conversation, remain the senior developer, technical orchestrator and final implementation owner described in [AGENTS.md](AGENTS.md#lead-agent-and-subagents). Keep the user's selected strongest lead model for planning, coding, integration and verification. A spawned helper reading this file remains subordinate to its assigned scope.

**Actively use Sonnet helpers at high effort** for useful independent work. This project authorizes that model/effort choice; do not silently inherit the lead model for every helper. Use native Claude Code delegation, start with one or two bounded assignments for substantial work, and normally include a Good Enemy for consequential changes. Keep trivial or tightly dependent steps with the lead and explain material runtime limitations.

Use [docs/SUBAGENTS.md](docs/SUBAGENTS.md) for the canonical workflow, model fallback, 26 specialist definitions and dispatch/return templates. Read its operating rules and only the relevant specialty. Catalog names such as `pure_physicist` are assignments, not automatically registered agent types.

### Use the configured helpers

Project profiles in [`.claude/agents/`](.claude/agents/) separate the helper model and effort:

```yaml
model: sonnet
effort: high
```

| Profile | Assignment and tools |
| --- | --- |
| [`openrc-researcher`](.claude/agents/openrc-researcher.md) | Map code, research sources or compare options; Read, Glob, Grep, WebSearch, WebFetch |
| [`openrc-draft-helper`](.claude/agents/openrc-draft-helper.md) | Return a proposed patch, algorithm or test for lead review; Read, Glob, Grep |
| [`openrc-good-enemy`](.claude/agents/openrc-good-enemy.md) | Independently challenge requirements, design or the actual candidate; Read, Glob, Grep |

These are supporting profiles, not main-session agents. Their allowlists omit shell, file-write and delegation tools, and their turn budgets keep assignments bounded. The draft helper returns text; the lead writes or adapts the accepted implementation. Supply a diff and source identity when the helper cannot obtain them itself. A partial result at the turn limit remains partial; resume only for a concrete remaining question.

Invoke the named custom profile as an ordinary subagent. A conversation fork inherits the parent's model, prompt and tools; it is not the restricted Sonnet/high helper defined here. Check the actual agent type rather than assuming every delegation uses the profile. Keep required results pending until they arrive, even when the client runs helpers in the background without a blocking wait.

Verify discovery through a named invocation and its delegation transcript; supported clients also show agents in the `@`-mention typeahead. Inspect the reported model/effort in `/tasks` when available. In recent releases `/agents` only prints a reminder, so it is not a discovery check. Restart the session if directly added profile files have not loaded. `sonnet` resolves according to the provider/client; `high` is a separate effort setting supported only by appropriate models/releases. Invocation, environment or managed settings can change the effective choice. Follow the shared [fallback rules](docs/SUBAGENTS.md#availability-overrides-and-fallback), report substitutions and mark unobservable settings unverified.

For a required MCP graph, execution, capture or draft-writing task that these profiles cannot perform, supply the evidence or use an actually available capable native agent, such as `general-purpose`, with explicit supported Sonnet/high settings and a bounded brief. Prefer the assigned custom profile over `Explore` when model control matters. Preserve graph-first discovery when available and the documented source-search fallback when it is not. Do not broaden a profile's tool access just to avoid reporting a limitation.

Do not use `opusplan` as a substitute for this hierarchy: it changes the execution model. Do not enable an agent team or switch providers merely to obtain helpers. The strongest selected lead remains responsible for the final solution.

### Delegate and integrate

- Give each helper the shared dispatch brief, including requested model/effort, exact question, baseline/dirty inputs, relevant constraints and the decision retained by the lead. Ordinary helpers do not receive the parent conversation automatically; some built-in agents also omit project instructions. Pass essential constraints explicitly.
- Keep research/review source-read-only across every available tool. A shell-capable fallback can still write despite lacking an Edit tool. Assign exact paths for a writing helper and verify the worktree's actual base; coordinate exclusive Blender, UI, radio and capture access through existing admission tools.
- Ask for alternatives, source evidence, concrete findings and uncertainty. Check consequential claims yourself, decide which draft material to accept, and implement the definitive solution. Continue useful lead work while independent investigations run.
- For consequential changes, normally have a Good Enemy inspect the actual candidate and acceptance criteria. Resolve material findings, inspect the combined diff and verify affected behavior. A reviewer cannot approve its own draft or replace missing hardware/pilot evidence.
- Keep delegation shallow by project policy, even when the runtime supports nested subagents. The shipped profiles cannot spawn children; a capable fallback may do so only when explicitly assigned by the lead within the available budget. Do not convert advice into a new approval gate or claim unavailable delegation occurred.

The [shared rules](AGENTS.md), [tooling guide](docs/TOOLS.md) and [flight logging workflow](docs/FLIGHT-LOGGING.md) govern implementation and verification. Reuse suitable free tools, assets and data with appropriate provenance and redistribution rights.

Shared rules load through Claude Code's [documented file import](https://code.claude.com/docs/en/memory#import-additional-files). Client details were checked on 2026-11-15 against [custom subagents](https://code.claude.com/docs/en/sub-agents) and [model configuration](https://code.claude.com/docs/en/model-config); verify current runtime support. Keep common policy in `AGENTS.md` and the workflow/specialties in `docs/SUBAGENTS.md`.
