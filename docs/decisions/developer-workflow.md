# Developer and agent workflow

Scope: the decisions, alternatives and evidence behind developer and agent workflow. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Use the debug bridge and engine diagnostics for agent work

**PT1h-R7/R8.** The opt-in debug-only loopback bridge provides stable state/input/UI operations, invalid-line rejection and main-thread scene mutation. The launcher issues a per-session token; a manually enabled bridge checks a token when configured. Engine profiling and compiler diagnostics avoid implementing another debugger protocol or depending on a stale language parser. The bridge is not exact replay authority; flight logs retain that role. PT1h-R9 attributes GPU cost by elimination (interleaved A-B-A ablation with Godot's measured render times) instead of a GPU capture tool, and rewinds through the existing session checkpoint boundary, handing input back to the pilot by default. PT1h-R10 draws flight-model gizmos with the repository's `ImmediateMesh` overlay pattern instead of a native debug-draw addon, and carries bug reports as the session's own checkpoint JSON (BugIt/BugItGo). PT1h-R11 gives agents an accessibility-style snapshot with per-control refs and field names, one `choose` verb and validated `setup`, and exposes them through a standard-library stdio MCP server instead of an SDK dependency. [Design choice](../../tools/debug/README.md#choice-of-design), [limits](../../tools/debug/README.md#how-it-works-and-limits), [tool index](../tools/README.md).

## Preserve Git history and limit future artifact growth

The adopted repository policy retains history rather than rewriting active clones or migrating existing evidence to LFS. Full history supports build identity; re-encoding tracked evidence would retain its old blobs and can destroy pixel-level proof. Bound new artifacts with the [large-file check](../../tools/repo/check_large_files.py) and [evidence conventions](../README.md#conventions-for-documents). Historical disk totals and provider quotas are not ongoing design assumptions. Reopen only with an explicit repository migration requirement and a coordinated plan.

## Keep a senior lead with bounded, evidence-producing helpers

**DX-06 agent-guidance follow-up, 2026-11-15; documentation and local profiles.**
The user's selected strongest lead retains design, definitive implementation,
integration and verification. Prefer Terra/max and Sonnet/high helpers for useful
independent investigation, drafts and challenge; choose task fit and actual
capabilities before dispatch. The lead may apply examined drafts directly and
resolve findings itself. Zero helpers or lighter supported effort can be appropriate
when the task and acceptance checks justify them, subject to explicit user choices.

The [21-question investigation](../research/agent-orchestration-2026-11-15.md) supports
bounded briefs, actual input identities and evidence-based acceptance, while finding
no universal benefit from more agents, maximum effort or a copied framework.
Preserve native delegation and existing permissions instead of adding a separate
orchestration service. [SUBAGENTS](../SUBAGENTS.md) owns current behavior and runtime
limits. Register named Codex roles without global helper-default or concurrency
keys: integration on 0.144.5 found that the proposed newer scalar fields caused
configuration fallback. Keep model/effort pins in the profiles and observe native
runtime limits. Revisit routing and budgets when client behavior changes or representative
OpenRC outcomes demonstrate a better tradeoff; this policy is not a measured gain.

## One shared agent rule source, with task-specific detail

**DX-06 instruction audit, 2026-11-19.** Keep durable project rules in `AGENTS.md` and a small `CLAUDE.md` with an explicit import. Read applicable nested instructions before editing; keep detailed delegation, commands, architecture, current work and dated evidence in their existing homes. This removes repeated startup context without removing the selected lead, helper preferences, physics/evidence contracts or existing authorization.

Current Claude Code can load AGENTS natively, but compatibility and loading vary by client/session configuration. Retain the import rather than a second copy or a Windows-sensitive symlink. Repository prose does not enforce permissions or prove discovery. The [source review](../research/agent-orchestration-2026-11-15.md#instruction-file-audit--2026-11-19) records official guidance, GitHub counterexamples and the source audit; [maintenance conventions](../README.md#agent-instruction-files) own future edits. No runtime performance or instruction-adherence improvement is claimed without measurement.
