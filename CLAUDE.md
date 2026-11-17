# Claude Code guidance

Use the shared repository rules below. Maintain project policy in [AGENTS.md](AGENTS.md) so Claude Code and Codex follow the same architecture, ownership, physics, verification and documentation contracts.

@AGENTS.md

Apply the shared [display resolution priorities](AGENTS.md#display-resolution-priorities) to delegated tasks as well.
Use U drive as cache and temp.
## Claude subagent collaboration

In the main conversation, remain the senior developer, technical orchestrator and final implementation owner described in [AGENTS.md](AGENTS.md#lead-agent-and-subagents). Keep the user's selected strongest lead model for planning, coding, integration and verification. A spawned helper reading this file remains subordinate to its assigned scope.

**Actively use Sonnet helpers at high effort** for useful independent work, especially consequential uncertainty, substantive drafts and critical review. This project authorizes that choice; do not silently inherit the lead for every helper. Start with one or two bounded assignments when their results can change a decision, and normally include a Good Enemy for consequential changes. Use zero helpers when dependencies or coordination cost outweigh the contribution. The lead may deliberately choose lighter supported effort for bounded work with trustworthy acceptance checks, preserving any explicit user choice.

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

These are supporting profiles, not main-session agents. Their declared allowlists omit shell, writes, MCP, `Skill` and `Agent`. The draft helper returns text; the lead understands, accepts/adapts, integrates and verifies it. Supply a diff and source identity when the helper cannot obtain them. A partial result at the turn limit remains partial. Session/plugin command hooks execute outside the model's allowlist, so a verified ordinary profile is a tool restriction, not a whole-process guarantee.

Invoke the named custom profile as an ordinary subagent, with explicit model/effort arguments when the live tool supports them. A conversation fork inherits the parent's model, prompt and tools instead. Check the actual agent type; a task label does not select a profile. Track required results until collected and assessed, independently resolved, or explicitly reported unresolved. A wait timeout does not stop the helper; inspect status before resuming or duplicating work.

At first use or after relevant changes, verify discovery through a named invocation and delegation transcript; supported clients also show agents in the `@`-mention typeahead. Check for shadowed definitions. `/tasks` reports model/effort in supported releases; request/transcript metadata can expose a different model. Record the verification basis and mark missing settings unverified. In recent releases `/agents` only prints a reminder. Restart if directly added profiles have not loaded. Aliases, invocation, environment, managed settings and spawn hooks may affect routing. Follow the shared [fallback rules](docs/SUBAGENTS.md#availability-overrides-and-fallback).

Match tools to the assignment before dispatch. For required graph MCP, execution, capture or writing, supply evidence or use an already-permitted capable native agent, such as `general-purpose`, with supported settings and a bounded brief. Prefer the assigned profile over `Explore` when model control matters. Preserve graph-first discovery and its documented source-search fallback. The shipped helpers cannot invoke `Skill`; supply essential constraints or have them read the precise relevant skill/reference files. Do not broaden tools merely to avoid a limitation.

Do not use `opusplan` as a substitute for this hierarchy: it changes the execution model. Do not enable an agent team or switch providers merely to obtain helpers. The strongest selected lead remains responsible for the final solution.

### Delegate and integrate

- Give each helper the shared dispatch brief, including requested settings, exact question, actual baseline/input state, constraints and retained decision. Ordinary helpers do not receive the parent conversation or its invoked skills automatically; some built-in agents omit project instructions. Follow already-loaded rules, read missing ones and pass essential constraints explicitly. Check that task-critical inputs reached the helper when context is uncertain.
- Keep research/review source-read-only across every available tool. A shell-capable fallback can still write despite lacking an Edit tool. Assign exact paths for a writing helper and verify the worktree's actual base; coordinate exclusive Blender, UI, radio and capture access through existing admission tools.
- Ask for alternatives, source evidence, concrete findings and uncertainty. Verify material claims actually relied on, decide what to accept and implement the definitive solution. Distinguish the helper's delta from inherited dirty inputs. Continue useful lead work while independent investigations run.
- Normally have a Good Enemy inspect consequential candidates. Separate requirements, concrete regressions and optional style; clean reviews are valid. Resolve material findings and verify affected integrated behavior with independently grounded expected results. A reviewer cannot approve its own draft or replace missing hardware/pilot evidence.
- Keep delegation shallow. The declared ordinary profiles exclude the `Agent` tool; a capable fallback may spawn only when the lead explicitly assigns it within budget and the runtime permits it. Stop superseded work where supported, check late results and resource teardown, and report unresolved required work. Advice creates no approval gate.

The [shared rules](AGENTS.md), [tooling guide](docs/TOOLS.md) and [flight logging workflow](docs/FLIGHT-LOGGING.md) govern implementation and verification. Reuse suitable free tools, assets and data with appropriate provenance and redistribution rights.

Shared rules load through Claude Code's [documented file import](https://code.claude.com/docs/en/memory#import-additional-files). Client details were checked on 2026-11-15 against [custom subagents](https://code.claude.com/docs/en/sub-agents) and [model configuration](https://code.claude.com/docs/en/model-config); verify current runtime support. Keep common policy in `AGENTS.md` and the workflow/specialties in `docs/SUBAGENTS.md`.
