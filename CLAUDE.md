# Claude Code

@AGENTS.md

Keep shared project policy in [AGENTS.md](AGENTS.md). This explicit import supports sessions that do not load `AGENTS.md` natively; do not copy its rules here. Before editing, read the applicable nested `AGENTS.md` files as the shared rules require.

For delegation, use the ordinary named profiles in [`.claude/agents/`](.claude/agents/):

| Profile | Use |
| --- | --- |
| `openrc-researcher` | Source research and alternatives |
| `openrc-draft-helper` | A text patch or test proposal for lead integration |
| `openrc-good-enemy` | Independent challenge of the actual candidate |

These profiles request `sonnet` with `high` effort. Use them actively; the project authorizes that choice, so do not silently inherit the lead model for every helper. They omit shell, writes, MCP, `Skill` and `Agent`; supply missing evidence or use an already-permitted capable helper for work needing those tools. A conversation fork does not select an ordinary profile.

Follow [model routing, discovery and fallback](docs/SUBAGENTS.md#claude-code). Check startup instruction files under `/context all` → Memory files; read applicable nested rules separately. Verify requested versus observable helper settings without claiming an unobserved runtime. Keep client details in that guide and shared rules in `AGENTS.md`.
