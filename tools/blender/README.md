# Blender MCP for agents

Agents can inspect and drive Blender through the official [Blender Lab MCP server](https://www.blender.org/lab/mcp-server/) ([source](https://projects.blender.org/lab/blender_mcp), GPL-3.0-or-later). It is pinned to v1.0.3 and runs with the project's Blender 5.2.2. Nothing is installed system-wide: the server, its Python packages and the Blender profile with the add-on live in `.tools/blender-mcp/`, which git ignores.

| File | Purpose |
| --- | --- |
| `mcp-setup.sh` | One-time, idempotent install. It clones the pinned tag and checks its commit, installs [requirements-mcp.txt](requirements-mcp.txt) (exact versions and hashes; CPython 3.12, Linux x86_64), then installs the SHA-256-checked add-on zip into an isolated Blender profile |
| `mcp-server.sh` | The stdio MCP server that [.mcp.json](../../.mcp.json) registers as `blender` |
| `mcp-bridge.sh` | Starts Blender with the add-on listening on `127.0.0.1:$BLENDER_MCP_PORT` (default 9876) |

## Use

```sh
tools/blender/mcp-setup.sh                         # once per machine (about 30 s)
tools/blender/mcp-bridge.sh path/to/file.blend     # background Blender: code, scene queries, renders
tools/blender/mcp-bridge.sh --gui path/to/file.blend   # full Blender under Xvfb at 1920x1080 (UI tools too)
```

The agent client starts `mcp-server.sh` itself after you approve the project server (`/mcp` in Claude Code). The bridge must be running for the live tools: `execute_blender_code`, `get_objects_summary`, `render_*`. The `*_for_cli` tools open a `.blend` in a background Blender of their own and need no bridge. The documentation tools (`search_api_docs`, `search_manual_docs`, `get_python_api_docs`) work offline.

## Facts and limits (2026-10-24, this VM)

- Blender refuses the add-on's socket unless online access is allowed, so the bridge passes `--online-mode`.
- Background mode answers only synchronous requests; deferred tools need `--gui`.
- On this GPU-less VM, `get_screenshot_of_window_as_image` returns a black image under Xvfb. `render_thumbnail_to_path` and `render_viewport_to_path` work. They write into Blender's temporary folder (`/tmp/blender_*/blender_mcp/`) whatever path is passed.
- Verified end to end with the MCP Python client: 26 tools listed; `execute_blender_code` and `get_objects_summary` on the Radiolink T12D delivery; a thumbnail render under `--gui`.
- **Security:** the server runs any Python an agent sends, with your user rights and no guard (Blender Lab's warning). It listens on localhost only. Run it on this development VM; stop the bridge when you are done.
- `--gui` runs Blender under `xvfb-run`; stopping the wrapper can leave Blender listening. Check with `ss -ltn | grep 9876` and stop the Blender process by its PID.
- Agent code runs in a weak sandbox that blocks only quitting Blender and resetting preferences; `result` must be a dict.
- Use one bridge per port. To run another, set `BLENDER_MCP_PORT` for both the bridge and the `.mcp.json` entry.
- The people generators (`tools/scenery/population/`) keep their own isolated profile in `.tools/sc-hum-authoring/` and do not use MCP.

## Skills

Agents get Blender craft from the [blender-skills](https://github.com/arjun988/blender-skills) pack (MIT, © blender-skills contributors). It is pinned at commit `8f778d2405a214b508d4c7d80742be8e43acdd52` (v1.3.0, 2026-07-10) and copied unmodified into `.claude/skills/` (Claude Code) and `.agents/skills/` (Codex). That is 94 skills plus their shared `references/`, with the licence in `blender-skills-LICENSE.txt`. Start with `blender-director`.

The pack targets the community `ahujasid/blender-mcp` server. The project skill [openrc-blender](../../.claude/skills/openrc-blender/SKILL.md) adapts it to the official server and this VM, and adds the repository rules (immutable deliveries, generator-only assets, no committed images). It wins on conflict.

To update the pack, clone the new commit and copy its `.claude/skills/*` over both folders. Review the diff for instructions that conflict with the project rules, and update the commit above.
