# Create an aircraft skin with AI

The current-source skin kit supports **X8 Wing** (`skywalker-x8`). It changes
paint while retaining the verified geometry, articulation and physics.
The complete [offline player tutorial](../app/assets/skin-kit/guide.html) has
editable prompts in all nine simulator languages: English, Spanish, Simplified
Chinese, Brazilian Portuguese, German, French, Italian, Russian and Japanese.
Opening it from the game selects the interface language. The downloaded copy
follows the browser language; both provide language links.

## Player flow

1. **Aircraft → X8 Wing → Choose paint → Create a skin → Save Blender template…**
   saves `skywalker-x8.zip`. Extract it and keep an untouched copy.
2. Open `guide.html`, choose a workflow, edit the idea and copy its complete prompt.
3. Produce a real `.orskin` with the supplied tool. A `.blend` is an editable
   project and a PNG is an image; neither alone replaces that package.
4. **Choose paint → Load new skin…** imports the package and selects it. Inspect
   Home and flight views. The choice persists across restarts; built-in paints
   restore the original appearance. Rejected imports retain the current choice.

## Authoring routes

The Blender route uses `Skywalker-X8.blend` and `Export OpenRC Skin.py`, with
Blender 5.2.2 or a compatible newer version. Claude Desktop controls local Blender
through its connector; local Codex can use the executable or configured MCP tools.
Cloud code execution does not guarantee Blender or `bpy`: its prompt requires a
real template-open check and an explicit local fallback.

The **experimental image-only route** uses `X8-Paint.png`, the original 2048²
color atlas, and `X8-UV.png`, its boundary reference. Edit the atlas with an image
editor or image-generation assistant. Run the supplied `pack_image.py` using
standard-library Python 3 to produce the `.orskin`, without Blender. An assistant
with Python execution can perform that packaging. The guide includes a separate
image-edit prompt and the exact command. The simulator still imports `.orskin`,
not the loose PNG.

An image generator may move islands, mirror lettering or break seams. A photo or
perspective image of a shark/aircraft is not an atlas. File validation cannot
prove visual alignment. Start with recoloring or large motifs; use Blender's 3D
painting for precise placement and seam repair. Both prompts require references
with a clear purpose and actual model inspection. See the [dated prompt research](research/aircraft-skin-prompts-2026-10-28.md).

## Limits and submissions

Prefer one **2048 × 2048** sRGB paint PNG. Maximums: 4096 pixels per side,
16,777,216 pixels across all PNGs, 16 MiB per PNG, 32 MiB per archive and nine
material/texture records. Review at **1920 × 1080** first; review resolution is
separate from texture dimensions. The direct image packer changes only
`x8_livery`; the simulator preserves the other channels. Save changed image data,
pack dependencies, save the project and reopen it to verify retention.

Up to 32 custom X8 paints may be installed. Identical bytes are deduplicated;
another aircraft or stock-model hash is rejected. Platform-specific installed
copy locations and recovery steps are in the player guide.

Want a skin included in the game? Send it to
[bultodepapas@gmail.com](mailto:bultodepapas@gmail.com?subject=OpenRC%20X8%20skin)
and it will be added in the next release. Include the `.orskin`, a 1920 × 1080
preview, skin name and desired author credit, using artwork you may share.
These instructions appear in every translation.

## Maintenance

`tools/skins/locales/*.json` owns player copy and prompts. Run
`python tools/skins/build_guide.py`, then `--check`; the generator checks coverage
against `app/i18n/languages.gd` and shared limits. Do not hand-edit the generated
HTML. Rebuild the ZIP after guide or tool changes; [toolkit instructions](../tools/skins/README.md)
own the commands and verification results.
