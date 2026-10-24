---
name: openrc-blender
description: OpenRC rules for any Blender work in this repository — start the Blender MCP bridge, map the blender-skills pack (blender-director, vehicle-artist, godot-export, …) onto the official Blender Lab server, keep owner deliveries and generated assets intact, export GLB for Godot. Use with or before any Blender, 3D asset, model, .blend, GLB or MCP task here; it overrides the generic blender-skills where they disagree.
---

# Blender work in OpenRC

The blender-skills pack (blender-director first, then the specialists it routes to) supplies production craft. This file supplies the repository and machine rules, and wins on conflict.

## Connect

1. Run `tools/blender/mcp-setup.sh` once, then `tools/blender/mcp-bridge.sh <file.blend>`. Use `--gui` for UI or deferred tools. Details: [tools/blender/README.md](../../../tools/blender/README.md).
2. The MCP server is the official **Blender Lab** server (`blender` in `.mcp.json`), not `ahujasid/blender-mcp`, which the pack's `references/mcp-tools.md` describes. List the tools first. Mapping:
   - scene info → `get_objects_summary`, `get_blendfile_summary_*`, `get_object_detail_summary`;
   - all edits → `execute_blender_code`;
   - unopened files → `*_for_cli`;
   - API and manual → `search_api_docs`, `search_manual_docs`.
   There are no Poly Haven, Hyper3D or Hunyuan tools.
3. **Viewport screenshots are black on this GPU-less VM.** For visual checks, use `render_thumbnail_to_path` or `render_viewport_to_path`, or an Eevee render through `execute_blender_code`. The render tools write under `/tmp/blender_*/blender_mcp/`; copy the result into the session scratchpad to view it.

## Files

- **Owner deliveries are immutable.** These include `assets/source-deliveries/**` and the aircraft and vehicle `source/` folders. Never `save_mainfile` over them. Open them, then `save_as_mainfile` to `tmp/<task>/` or `.tools/`. The pack's "always save the .blend" means "save your working copy".
- **Shipped assets come only from their generators.** Each asset guide names its generator, for example `tools/scenery/population/` for people, the aircraft generators and `tools/landscape/`. Change the generator or its inputs and rerun it; never hand-edit a shipped `.glb`. Follow [AIRCRAFT_CONTRACT.md](../../../docs/AIRCRAFT_CONTRACT.md) and keep node names such as `airplane`, `propeller` and `*_hinge` stable.
- **Prefer free downloads to modelling** (CC0 or a compatible licence, with provenance recorded in the area's sources manifest).
- **Do not commit images** unless they are required evidence. Put renders in the scratchpad or `tmp/`.

## Export to Godot (pack: godot-export)

- glTF 2.0 / GLB, metres, +Y up (the exporter converts), `export_apply=True`, no animation unless needed. Godot's front is −Z.
- The runtime is Godot 4.7.2's Compatibility renderer:
  - one material per draw where possible;
  - shared atlases;
  - VRAM-compressed textures with mipmaps.
  Godot generates LODs. Check the area's triangle and draw budgets (`tools/scenery/budget.sh`, per-area tests).
- Verify in the game, not only in Blender: run the area checker or capture in [docs/tools/README.md](../../../docs/tools/README.md), at 1920×1080 first.

## Safety

The server runs any code you send with the user's rights. Keep it on localhost and this VM, and stop the bridge when done. Use one bridge per port: `BLENDER_MCP_PORT` for both the bridge and the `.mcp.json` entry.
