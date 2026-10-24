# Tools

- Index of every tool by task: [docs/tools/README.md](../docs/tools/README.md). Rendering checkers: [graphics](../docs/tools/graphics.md#area-capture-checkers); Godot runner: [tools/godot](godot/README.md).
- Each `tools/<area>/README.md` owns its commands. Many show PowerShell with the Windows engine; on Linux use `"$(app/get-godot.sh)"`.
- Use a new `--out` under `tmp/` for every run.
- Running app (menus, keys, state, logs, hitches, leaks, UI fuzzing, regression smoke): [tools/debug](debug/README.md#i-want-to).
- Blender from an agent (MCP server `blender` in `.mcp.json`; skills `openrc-blender` first, then the blender-skills pack): [tools/blender](blender/README.md).
