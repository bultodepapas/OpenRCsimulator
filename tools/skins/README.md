# Skywalker X8 skin starter

The player kit is generated from the verified default runtime GLB, not the
owner's editable delivery. It preserves Blender's imported mesh, material
slots and UVs; its packed textures include the existing 2048 × 2048 livery.
The embedded exporter writes only an `openrc-skin` v1 manifest and PNG color
textures. Other material channels and aircraft geometry remain in the stock
model. See [the player guide](../../app/assets/skin-kit/guide.html) and
[skin contract](../../docs/AIRCRAFT-SKINS.md).

Regenerate with Blender 5.2.2 after changing the tool or guide:

```sh
blender --background --factory-startup --python-exit-code 1 \
  --python tools/skins/build_skywalker_x8.py
```

This writes `app/assets/skin-kit/skywalker-x8.zip` containing the `.blend`,
exporter, offline guide and README. The generator checks the current GLB
against its expected SHA-256 before import; changing that aircraft requires
reviewing the compatibility contract. ZIP entries have fixed metadata, but
Blender's `.blend` bytes need not be byte-identical across rebuilds. The
generator doesn't modify source deliveries or the shipped GLB.

For a focused check, extract the ZIP into `tmp/skin-kit/roundtrip/`, then run:

```sh
blender --background --factory-startup tmp/skin-kit/roundtrip/Skywalker-X8.blend \
  --python-exit-code 1 --python tools/skins/test_skywalker_x8.py
blender --background --factory-startup tmp/skin-kit/roundtrip/Skywalker-X8.blend \
  --python-exit-code 1 --python "tmp/skin-kit/roundtrip/Export OpenRC Skin.py" -- \
  --output tmp/skin-kit/roundtrip/example.orskin --label "My design"
```

The check exercises dirty paint pixels, material identity, packed-image
reopening, UV, image mapping and unsupported-shader rejection, image limits, and preservation
of an existing output on failure. Check a produced `.orskin` with the runtime
importer too; a Blender-only test does not prove the in-app flow.
