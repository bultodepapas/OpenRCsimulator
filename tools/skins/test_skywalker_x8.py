"""Exercise the extracted starter in Blender, including dirty paint and rejection.

blender --background --factory-startup tmp/skin-kit/roundtrip/Aircraft.blend \
  --python-exit-code 1 --python tools/skins/test_skywalker_x8.py
"""

import json
from pathlib import Path
import tempfile
import zipfile

import bpy


ROOT = Path(__file__).resolve().parents[2]
EXPORTER = ROOT / "tools/skins/export_openrc_skin.py"
OUT = ROOT / "tmp/skin-standard-kits/tests"
LIB = {"__name__": "openrc_export_test"}
exec(compile(EXPORTER.read_text(encoding="utf-8"), str(EXPORTER), "exec"), LIB)


def expect_rejection(operation, text):
    try:
        operation()
    except ValueError as error:
        if text not in str(error):
            raise AssertionError(f"Wrong rejection: {error}") from error
    else:
        raise AssertionError(f"Expected rejection containing: {text}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    baseline = LIB["_baseline"]()
    assert len(baseline["meshes"]) == 11
    assert len(baseline["materials"]) == 9
    for image in bpy.data.images:
        if image.source == "FILE":
            assert image.packed_file is not None, image.name
    material = bpy.data.materials["x8_livery"]
    shader = LIB["_shader"](material)
    image = shader.inputs["Base Color"].links[0].from_node.image
    assert tuple(image.size) == (2048, 2048)
    original_path, original_format = image.filepath, image.file_format

    # A renamed Blender datablock retains the GLB identity. Current, unsaved
    # Texture Paint pixels must be captured without changing the source image.
    material.name = "Renamed paint"
    image.pixels[:4] = (0.9, 0.2, 0.05, 1.0)
    image.update()
    assert image.is_dirty
    package = LIB["export_skin"](OUT / "painted.orskin", "Painted test")
    assert image.is_dirty and image.filepath == original_path and image.file_format == original_format
    with zipfile.ZipFile(package) as archive:
        assert set(archive.namelist()) == {"manifest.json", "texture-01.png"}
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["format"] == "openrc-skin" and manifest["version"] == 1
        assert manifest["aircraft_id"] == "skywalker-x8"
        assert manifest["base_asset_sha256"] == "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac"
        assert manifest["label"] == "Painted test"
        assert [entry["name"] for entry in manifest["materials"]] == baseline["export_materials"]
        painted = next(entry for entry in manifest["materials"] if entry["name"] == "x8_livery")
        assert painted["texture"] == "texture-01.png"
        png = archive.read("texture-01.png")
    with tempfile.TemporaryDirectory(prefix="openrc-skin-check-") as scratch:
        path = Path(scratch) / "paint.png"
        path.write_bytes(png)
        check = bpy.data.images.load(str(path), check_existing=False)
        assert tuple(check.size) == (2048, 2048)
        actual = check.pixels[:4]
        assert all(abs(a - b) <= 0.01 for a, b in zip(actual, (0.9, 0.2, 0.05, 1.0))), actual
        bpy.data.images.remove(check)

    # Unsupported node edits and UV changes must fail, without replacing an
    # existing destination if a user accidentally picks it again.
    destination = OUT / "keep.orskin"
    destination.write_bytes(b"keep this file")
    nodes, links = material.node_tree.nodes, material.node_tree.links
    old_link = shader.inputs["Base Color"].links[0]
    old_output = old_link.from_socket
    mix = nodes.new("ShaderNodeMixRGB")
    links.new(mix.outputs["Color"], shader.inputs["Base Color"])
    expect_rejection(lambda: LIB["export_skin"](destination), "bake procedural")
    assert destination.read_bytes() == b"keep this file"
    nodes.remove(mix)
    links.new(old_output, shader.inputs["Base Color"])

    obj = bpy.data.objects["wing_left_fixed"]
    uv = obj.data.uv_layers.active.data[0].uv
    x = uv.x
    uv.x += 0.05
    expect_rejection(lambda: LIB["export_skin"](destination), "UVs")
    obj.data.uv_layers.active.data[0].uv.x = x
    assert destination.read_bytes() == b"keep this file"

    # An oversized image must be rejected before it is written to the package.
    oversized = bpy.data.images.new("Too large", width=4097, height=1)
    image_node = shader.inputs["Base Color"].links[0].from_node
    image_node.image = oversized
    expect_rejection(lambda: LIB["export_skin"](destination), "dimensions")
    image_node.image = image
    bpy.data.images.remove(oversized)
    image_node.extension = "CLIP"
    expect_rejection(lambda: LIB["export_skin"](destination), "original UV mapping")
    image_node.extension = "REPEAT"
    uv_node = nodes.new("ShaderNodeUVMap")
    links.new(uv_node.outputs["UV"], image_node.inputs["Vector"])
    expect_rejection(lambda: LIB["export_skin"](destination), "original UV mapping")
    nodes.remove(uv_node)
    assert destination.read_bytes() == b"keep this file"

    # The equivalent of Image > Save updates a packed dirty image. Saving and
    # reopening the .blend must retain the paint for later editing.
    image.pack()
    saved = OUT / "reopened-edit.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(saved), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(saved))
    reopened = bpy.data.images["x8_abisal_base_color"]
    assert tuple(reopened.size) == (2048, 2048) and reopened.packed_file is not None
    assert all(abs(a - b) <= 0.01 for a, b in zip(reopened.pixels[:4], (0.9, 0.2, 0.05, 1.0)))
    print(f"OpenRC skin starter checks passed; painted package: {package}")


if __name__ == "__main__":
    main()
