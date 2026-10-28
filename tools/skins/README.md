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

Runtime verification on Windows with the pinned Godot 4.8-beta1, 2026-10-28:
custom-skin tests 36/36, skin-dialog tests 25/25, existing livery-picker tests
285/285, stock-livery tests 179/179 and preview-request tests 25/25 passed.
The language suite passed for all eight translated catalogs. Using the debug
bridge and an isolated profile at 1920 × 1080, the exported painted package
was imported through the dialog callback, selected on Home, retained in the
flight route, and restored after an application restart. A second export with
a bright teal image visibly changed the stock X8; choosing Abisal restored
the default selection. Review captures remain in ignored `tmp/`, not the kit.
App shutdown reported no crashes or leaked objects. This verifies the source
workflow, not a published desktop package or target-hardware performance.

The full `app/test.sh` run was started but stopped when unrelated runtime
changes continued in the shared checkout; it is not a full-suite pass. A
duplicate stock-livery run under concurrent workloads also hit its 90-second
timeout; the separate completed 179-check run above is the accepted focused
result. Complete the full suite on a stable source snapshot before release.

## Verification receipt (2026-10-28)

- Windows, Blender 5.2.2 LTS. Default GLB SHA-256:
  `3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac`.
- Generated kit: 7,928,474 bytes, SHA-256
  `219b9bdca51ec2bfb7be06342a9ba5b4a37870dc5bd5e4b5075df32463868413`.
  The extracted guide and exporter match their source files, and the embedded
  Blender text matches the exporter. The kit has four expected entries.
- The commands above passed on the extracted kit. A hidden Blender GUI smoke
  on the same template and exporter also ran the embedded script, opened its
  file selector, and saved a valid `gui-export.orskin`; the filename became
  the manifest label. Its SHA-256 was
  `5701abde021d2444463da6403c522baf57d0b17006b56bf3b34da615d34306e2`.
  The GUI smoke preceded the final guide-only wording change.
- Godot's headless runtime accepted and applied a painted package generated
  by the exporter. Scratch packages, including the bright teal render proof,
  are under `tmp/skin-kit/` and are not shipped as additional artwork.
