# Create an aircraft skin with AI

The current-source skin kit supports **Skywalker X8** (`skywalker-x8`). A skin changes the aircraft's paint, not its shape or flight model. You can use an AI assistant to help design and paint it, then import the result into OpenRC Simulator. The in-app guide is available offline in Spanish and English.

## 1. Get the starter kit

1. On Home choose **Aircraft → Skywalker X8 → Choose paint → Create a skin**. In **Skin tools**, select **Save Blender template…** and save `skywalker-x8.zip`.
2. Extract the ZIP into its own folder. It contains `Skywalker-X8.blend`, `Export OpenRC Skin.py`, `README.txt` and the offline `guide.html`. The template has the aircraft and its existing 2048 × 2048 paint image. Keep a copy of the unedited kit.
3. Select **Open skin guide** in the same dialog for the offline, bilingual version of this tutorial and editable copy buttons for the AI prompt.
4. Install [Blender](https://www.blender.org/download/) on your computer. The template was saved with Blender 5.2.2; use that version or a compatible newer version. The download and AI services need an internet connection; the guide itself does not.

## 2. Pick an idea and a way to work

Start with one sentence, for example: “Make me a skin inspired by a great white shark.” Add colors, placement, a name and any reference images you are allowed to use. Describe which features matter, such as a dark upper surface, pale underside and a simple fin-like stripe. Keep the aircraft readable from above and below in flight. Use your own references or materials you have permission to use, and keep a record of their source and any conditions on reuse. A reference to an idea is different from copying a logo or artwork; permission to share those assets is your responsibility.

Choose one of these routes:

- **Codex on your computer:** open the extracted kit folder in a local Codex session and provide the prompt below. Let it locate and test the installed Blender or use your configured Blender MCP connection. Give it the reference files and the ability to write to the kit folder. A local CLI may be started from that folder with `codex`, if installed. The assistant should say what it actually ran and where it saved the outputs.
- **Claude Desktop with Blender:** open the `.blend` in Blender. Set up and start the [Blender connector](https://academy.claude.com/tutorials/using-the-blender-connector-in-claude), then supply the prompt in Claude Desktop and any reference images. Anthropic documents Blender 4.2 or newer for its connector; the kit's newer Blender requirement still applies. The connector acts on the open scene; save it in Blender afterwards.
- **Claude in a browser or another cloud assistant:** upload the ZIP and references if that service accepts them. First ask it to **demonstrate that it can run Blender or `bpy` and open the template**. Cloud file creation is sandboxed and does not imply Blender is installed. The Blender Desktop connector is not available in Claude's browser. If the test fails, use a local route above; do not accept a text response or a renamed image as a completed skin. Depending on the service, you may instead download an edited `.blend` and finish the export locally.

The services and their features may change. See [Claude's file-creation documentation](https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude), [Claude's connector tutorial](https://academy.claude.com/tutorials/using-the-blender-connector-in-claude), and the [Codex CLI documentation](https://developers.openai.com/codex/cli/).

## 3. Give the assistant a complete brief

Replace the first sentence with your idea. Attach or point to the extracted kit and authorized references. The offline guide provides this prompt in both languages.

```text
Make me a skin inspired by a great white shark.

Use my attached OpenRC Skywalker X8 starter kit. Inspect the template and my reference images first. Check and show that you can actually open the .blend using Blender/bpy or a connected running Blender before claiming you can produce files. If you cannot, tell me and give me the next local step; do not invent an export.

Create a striking, flight-readable paint scheme that follows my idea. Use the existing x8_livery Base Color image and existing material Base Colors. Keep the aircraft geometry, silhouette, objects, transforms, pivots, hinges, UVs, material names and hierarchy intact. Do not change physics, add aircraft parts or rely on procedural shading that is not baked into the paint image. Keep markings and colors legible from above and below. Use only artwork and references I have permission to use; describe any outside material you used.

Keep the paint image at 2048 × 2048 unless there is a good reason to change it. Each PNG must be no larger than 4096 × 4096, with no more than 16,777,216 decoded pixels in total. Do not use 8K textures. Save the painted image itself, pack any newly linked resources, then save an editable .blend and reopen it to verify the paint survived. Use the supplied Export OpenRC Skin.py to produce an .orskin for this kit; do not make up the manifest or simply rename another file. Also provide a 1920 × 1080 preview showing the paint, and state which views you actually checked. The preview is a review image, not the texture.

Give me the actual .orskin, editable .blend and preview file paths or download links. Report the Blender version and what you verified. If an export cannot run in your environment, say so and provide the edited .blend and the exact local steps instead.
```

The kit has one paint image for `x8_livery`; other existing materials can use their Principled Base Color. The exporter supports a directly connected image and material base colors, not arbitrary shader effects. Bake any desired procedural appearance to the supported image first; keep the other shader channels as they are. Transparency is not guaranteed. Do not rename the materials or change their UV mapping. One 2048² PNG is the recommended starting point; the importer's combined limit is 16,777,216 decoded pixels across all PNGs. A single 4096² PNG consumes that entire allowance. Other limits are 32 MiB for the `.orskin`, 16 MiB per PNG, and at most nine materials/textures.

## 4. Save, preview and export

The assistant may perform these steps for you. If it returns an edited Blender project without the final package, finish them yourself:

1. Open the edited `.blend` in Blender. Inspect the upper surface, underside and sides in Material Preview. Check seams, mirrored areas, markings and the moving surfaces. An AI-generated preview is useful, but the simulator's view is the final check.
2. In an **Image Editor**, select the painted image (initially `x8_abisal_base_color`) and choose **Image → Save**. For newly linked external images also choose **File → External Data → Pack Resources**. Then **File → Save As** a new `.blend` and reopen it to check your paint survived. Packing resources alone does not save changes to the already-packed paint image. This keeps an editable copy; a `.blend` alone is not an importable skin. See [Blender's packed-data guide](https://docs.blender.org/manual/en/5.0/files/blend/packed_data.html).
3. In Blender's **Scripting** workspace, open the kit's `Export OpenRC Skin.py` in the Text Editor and choose **Run Script**. In the save dialog, choose a location and a name ending in `.orskin`. The filename becomes the paint name, up to 48 printable characters. The exporter writes the supported paint and the matching aircraft identity into that file. Keep the `.blend` for later edits.
4. For a shareable review image, frame the aircraft in Material Preview. Set the output resolution to **1920 × 1080 at 100%**, use the 3D Viewport's **View → Viewport Render Image**, and save the result from the image window. Repeat from another angle if needed. This 1080p image is a preview; it is separate from the 2048² paint texture and from the package. The kit does not include a camera or automatically generate a preview. Blender documents [viewport rendering](https://docs.blender.org/manual/en/latest/editors/3dview/viewport_render.html).

For an assistant using a terminal, the supplied exporter also supports a headless run from the extracted kit folder, with Blender on the command path:

```sh
blender --background Skywalker-X8.blend --python "Export OpenRC Skin.py" -- --output my-design.orskin --label "My design"
```

When exporting an edited project, replace `Skywalker-X8.blend` with its path. If `blender` is not on the path, use the installed Blender executable's full path. A GUI export is equally valid.

## 5. Load and fly

In OpenRC select **Aircraft → Skywalker X8 → Choose paint → Load new skin…**. In **Skin tools**, select **Load new skin…** and choose the exported `.orskin`. The new paint is selected automatically on a successful import; inspect it on Home and in flight. Imported skins and the selected paint are retained across restarts. To return to the original appearance, choose a built-in paint in the gallery.

If the simulator rejects the file, read its message. Check that it is a real `.orskin`, was made from the X8 kit for the current model, and meets the limits above. A skin for another aircraft or a different model version cannot be used here: download a fresh kit and export again. A rejected import leaves the current selection unchanged. If a design looks incomplete, inspect the saved image and UV placement in Blender, export again and load the new file. Up to 32 custom paints may be installed for the X8; loading the same bytes again does not create another entry.

Keep the `.blend`, source images and references for future changes. Sharing the `.orskin` is separate from sharing the aircraft template or third-party artwork: check the applicable permissions first.
