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
Blender exporter, offline guide, multilingual README, image packer, original
paint atlas and UV-boundary reference. The generator checks the current GLB
against its expected SHA-256 before import; changing that aircraft requires
reviewing the compatibility contract. ZIP entries have fixed metadata, but
Blender's `.blend` bytes need not be byte-identical across rebuilds. The
generator doesn't modify source deliveries or the shipped GLB.

## Image-only experiment

The kit also includes `X8-Paint.png`, the original 2048 × 2048 albedo atlas,
and `X8-UV.png`, a black-on-white boundary reference derived from the stock
`x8_livery` UVs. A user or assistant can edit the atlas and package the result
using Python 3 and only its standard library:

```sh
python pack_image.py X8-Paint-edited.png --output my-design.orskin --label "My design"
python tools/skins/test_pack_image.py
```

Run the first command in the extracted kit folder; run the second from the
repository root. The packer validates PNG dimensions, size, chunk checksums,
image-data bounds and scanline filters; it emits a manifest pinned to the
stock GLB and one `x8_livery` texture, leaving other materials unchanged.
The runtime remains the final file validator. An ordinary aircraft photo is
not a UV atlas. Image generators can rearrange islands or misplace marks,
and the packer cannot detect such visual problems. Inspect the result on the
actual aircraft, and use Blender for 3D painting if seams or marks need work.
No AI image-generation service has been qualified for this task.

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

The localized guide covers all nine simulator languages, including the community
submission address and both workflows. `build_guide.py --check` verifies its
current sources. In Chrome opened directly from `file:`, all nine language
sections fit 1920 × 1080 and a 360-pixel-wide viewport without horizontal overflow.
Provider switching, edited-text copying and denied-clipboard manual fallback
were exercised. The guide has no remote resource dependencies. The focused Godot
skin-dialog test passed 114 checks, including all locales and app-language guide
selection.

- Windows, Blender 5.2.2 LTS. Default GLB SHA-256:
  `3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac`.
- Generated kit: 13,326,567 bytes, SHA-256
  `bd2243323df444b1717d5f95e1a8eb91cd0d01c01fc1c847c350af0c4a2821d8`.
  Its seven entries pass ZIP CRC checks; the guide, both scripts and embedded
  Blender text match their sources. The quick-start includes the six relevant
  guide fields for each of nine locales, and `build_guide.py --check` passed.
- The commands above passed on the extracted kit. A hidden Blender GUI smoke
  on the same template and exporter also ran the embedded script, opened its
  file selector, and saved a valid `gui-export.orskin`; the filename became
  the manifest label. Its SHA-256 was
  `5701abde021d2444463da6403c522baf57d0b17006b56bf3b34da615d34306e2`.
  The GUI smoke preceded the final guide-only wording change.
- Godot's headless runtime accepted and applied a painted package generated
  by the exporter. Scratch packages, including the bright teal render proof,
  are under `tmp/skin-kit/` and are not shipped as additional artwork.
- Five focused image-packer tests passed, including PNG color modes and Adam7,
  corrupted data, limits and atomic failure. The extracted kit's packer
  produced `tmp/skin-image-only/final-image-only.orskin` from its paint atlas.
  A Godot 4.8-beta1 headless check of the prototype package passed 19/19:
  all nine `x8_livery` surfaces received the PNG with matching mipmaps, and
  the other 15 material surfaces, non-albedo properties and meshes stayed
  unchanged. The checked package used the unedited atlas and does not prove
  visual quality for an AI-generated design.
  The paint atlas and UV reference SHA-256 values are, respectively,
  `e93ab2b7c40de3cff5a20df33e17553254cc65d0a620e0064be242a1a34edb67`
  and `933c51830569be235c75dfd554c52c181722f512524ce88423661b9cc21d0b21`.
  A sample of 2,000 source and packaged-atlas pixels matched exactly after
  decoding in Blender.
  Compared with Blender's full UV wireframe, 99.974% of boundary pixels were
  within two pixels at 2048 × 2048. No image-generated design was evaluated.
