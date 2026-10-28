# X8 skin prompts and image-only authoring

Research checked 2026-10-28. Current instructions: [skin guide](../AIRCRAFT-SKINS.md).

## Evidence applied to the prompts

- [Anthropic's prompting guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices): explicit outputs, context and ordered steps. Separate the idea, execution environment and paint contract; request actual deliverable files rather than vague quality claims.
- [Blender's official MCP examples](https://www.blender.org/lab/mcp-server/): inspect actual scene data and object/material relationships. Identify the supplied materials and UV islands before painting; do not assume a generic image fits.
- [Texture Paint](https://docs.blender.org/manual/en/5.2/sculpt_paint/texture_paint/introduction.html): save edited image data explicitly. Save the image, pack dependencies, save the project and reopen it before declaring delivery complete.
- [UV seams](https://docs.blender.org/manual/en/5.2/modeling/meshes/uv/unwrapping/seams.html) and [paint options](https://docs.blender.org/manual/ja/5.2/sculpt_paint/texture_paint/tool_settings/options.html): inspect shared/mirrored texture space and island edges. Extend edge colors into available margins without contaminating neighbors; no fixed bleed distance is guaranteed safe for this dense atlas.
- [Claude's connector tutorial](https://academy.claude.com/tutorials/using-the-blender-connector-in-claude) uses local Blender; [cloud file creation](https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude) supplies a sandbox, not guaranteed Blender availability. The cloud prompt requires a real template-open test and an honest local fallback.

Blender Lab currently lists Blender 5.1+ while the Claude tutorial mentions 4.2+.
The template was saved with 5.2.2, so its actual requirement takes precedence.
OpenRC's existing importer defines texture limits and protected geometry; these
are project constraints, not guarantees from an AI provider. Neutral lighting,
multiple views and reduced on-screen size are practical flight-readability checks.

## Image-only assessment

The pinned X8 GLB uses one 2048² sRGB paint atlas on `x8_livery` across nine mesh
objects. Inspection found 34,111 distinct UV polygons and 10,593 boundary segments.
An exact-polygon check found no identical cross-object duplicates; that does not
exclude partial overlap or mirroring. The real mapping remains authoritative.

The importer already supports one material record. A PNG plus a matching manifest
can therefore replace that color image without Blender. `pack_image.py` implements
this with standard-library Python, while the kit supplies the original atlas and
a boundary reference derived from the pinned GLB. Other material channels and
geometry stay in the simulator.

This is an **atlas-editing workflow**, not automatic projection of a subject photo.
Generative tools may move islands, distort details or paint perspective lighting.
PNG/ZIP checks cannot detect those artistic failures. Inspect the result on the
actual X8 and use Blender for precise seam work. No creative image-generation
service has been qualified end to end here; packaging compatibility is separate
from image-model quality. Commands and concrete results live in the
[toolkit guide](../../tools/skins/README.md).
