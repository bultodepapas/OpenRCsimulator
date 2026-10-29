# Create an aircraft skin with AI

Every selectable airplane and the X-Cell helicopter has a model-specific paint
kit. The four Ugly Stick engine configurations share one visual family and kit.
Skins change paint, retaining the stock geometry, articulation and physics.
The [offline player tutorial](../app/assets/skin-kit/guide.html) includes editable
image and Blender prompts in all nine simulator languages. Opening it from the
game selects the interface language and aircraft; the downloaded guide also
identifies its model and follows the browser language.

## Player flow

1. **Aircraft → choose a model → Choose paint → Create a skin → Save skin template…**.
   Extract the ZIP and keep an untouched copy.
2. Open `guide.html`. For the image route, give the assistant `kit.json`, the
   matching `Paint-NN.png` and `UV-NN.png` files, your design references and the
   complete image-edit prompt. Change the idea and selected model as needed.
3. Replace only the corresponding `Paint-NN.png` files. Preserve canvas shape,
   island positions, orientation and material mapping. Some models have several
   paint images; edit and return each separately. Keep original files for groups
   you do not change. UV lines are reference only, not part of the final paint.
4. In the extracted folder, run
   `python pack_image.py --output my-design.orskin --label "My design"`.
   A coding assistant with Python can package it; Blender is not required.
5. **Choose paint → Load new skin…** imports the `.orskin` and selects it. Inspect
   Home, flight, both sides, undersides and moving surfaces. Selection persists
   across restarts; choosing the original paint restores stock appearance.
   Rejected imports retain the current choice.

A PNG is an image and a `.blend` is an editable project; the simulator imports
the `.orskin` package. Templates and packages belong to their visual family and
stock revision. A skin for a different model or revision is rejected. Existing
X8 packages remain compatible; Ugly Stick variants share installed paints.

## Reference mapping

| Visual family | Image references |
| --- | --- |
| Ugly Stick (all four configurations) | Existing covering atlas |
| Extra 300S | Neutral six-view paint mapping |
| P-51D Mustang | Neutral six-view paint mapping |
| Turbo Lumber | Neutral six-view exterior paint mapping |
| Vantage Jet | Four original atlas groups, including repeated UV regions |
| F4U Corsair | Shared original exterior atlas |
| MoonRunner X99 | Original livery atlas |
| X-Cell / HX-700 helicopter | Separate canopy and tail-boom images |

The kit identifies paint groups and their exact material assignments. Extra, P-51
and Turbo Lumber use neutral six-view starters, not reproductions of stock paint;
packaging them without edits produces neutral paint. Generated
mappings are applied to an instance-owned copy for custom skins; stock builds
remain unchanged. The procedural models retain their material finish shaders.
A six-view mapping can overlap parts: image editing cannot independently paint
surfaces that share coordinates. Use the supplied reference rather than inventing
island outlines. The helicopter tail source is reduced proportionally from
8192 × 880 to 4096 × 440 to fit the runtime limit.

## Authoring routes and quality

The image route is the standard starting workflow. Image generation remains
approximate: a generator can shift islands, mirror marks or break seams. The X8
shark trial produced a usable skin at 1254 × 1254 from a 2048-square source, with
visible asymmetric wing bands and panel discontinuities. File validation cannot
prove visual alignment. Prefer recoloring and broad motifs for early attempts;
review every returned image on its actual model.

For detailed placement, open `Aircraft.blend` and use `Export OpenRC Skin.py`.
Claude Desktop uses local Blender through a configured connector; local Codex can
use the executable or configured MCP tools. Cloud execution does not guarantee
Blender or `bpy`: the prompt requires checking the template can actually open and
provides a local fallback. Do not edit geometry, names, pivots, UVs or material
assignments. Save changed image data, pack dependencies and reopen the project
to verify retention. See the [dated prompt research](research/aircraft-skin-prompts-2026-10-28.md).

Keep each image's reference dimensions and aspect ratio; 2048 × 2048 is a useful
target for square atlases, not a rule for rectangular images. Maximums: 4096 pixels
per side, 16,777,216 pixels across all PNGs, 16 MiB per PNG, 32 MiB per archive and
nine material records. Up to 32 custom paints may be installed per visual family.
Review at **1920 × 1080** first; screen resolution is separate from texture size.

Want a skin included in the game? Send it to
[bultodepapas@gmail.com](mailto:bultodepapas@gmail.com?subject=OpenRC%20skin)
and it will be added in the next release. Include the `.orskin`, model and skin
name, a 1920 × 1080 preview and desired author credit, using artwork you may share.
These instructions appear in every translation.

## Maintenance

`app/assets/skin-kit/models.json` owns kit identity and paint groups.
`tools/skins/locales/*.json` owns player copy and prompts. Run
`python tools/skins/build_guide.py`, then `--check`; the generator validates
coverage against `app/i18n/languages.gd`. Rebuild kits after guide, exporter,
paint mapping or stock-source changes. [Toolkit instructions](../tools/skins/README.md)
own generation and verification commands. Do not edit generated ZIPs or the
stock models by hand. Skin changes never qualify aircraft physics.
