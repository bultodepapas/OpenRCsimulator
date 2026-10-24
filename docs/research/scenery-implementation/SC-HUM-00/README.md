# SC-HUM-00 — Baseline: authoring toolchain and sources

Status: **partial, 2026-10-24.** The authoring toolchain and source intake are verified. The scene-budget re-baseline, the camera census and the reference photo board are still open. Plan: [field people plan](../../../plans/field-people.md).

## Toolchain (local, untracked under `.tools/`)

| Item | Version and check |
| --- | --- |
| Blender | 5.2.2 LTS, official `blender-5.2.2-linux-x64.tar.xz`, SHA-256 verified against the release's `blender-5.2.2.sha256` |
| MPFB | 2.0.18, GitHub tag archive; SHA-256 `ADA7C4FF…` matches [HUMAN_SOURCES.json](../../../../assets/scenery/population/HUMAN_SOURCES.json) exactly |
| MakeHuman system assets, system poses, poses01 | SHA-256 match `HUMAN_SOURCES.json` exactly |

The MakeHuman server has two mirrors. On 2026-10-24, `files.makehumancommunity.org` delivered about 690 KB/s and `files2` about 13 KB/s for the same file; the hashes confirm the bytes are identical.

Isolated setup on Linux, equivalent to the PowerShell example in the [LU-21 people research](../../landscape-upgrade/LU-21/people-research.md):

```sh
ST=$PWD/.tools/sc-hum-authoring
export BLENDER_USER_CONFIG=$ST/blender-user/config BLENDER_USER_SCRIPTS=$ST/blender-user/scripts \
  BLENDER_USER_DATAFILES=$ST/blender-user/datafiles BLENDER_USER_EXTENSIONS=$ST/blender-user/extensions
# MPFB's src/mpfb goes to $ST/blender-user/extensions/blender_org/mpfb (the recipe imports bl_ext.blender_org.mpfb);
# the CC0 archives are extracted into $ST/mpfb/data.
blender --background --factory-startup --python tools/scenery/population/generate_people.py -- \
  --pose standing --mpfb-user-data $ST/mpfb --output-dir $ST/out/standing
```

## The portable recipe reproduces the frozen people

LU-21 recorded that the relocated, parameterized recipe had "static validation only". Its first real run, on Linux, regenerated all three poses. The packaged GLBs are not byte-identical to the frozen assets, so the meshes were compared in Godot 4.7.2 (`GLTFDocument`, per part):

| Pose | Triangles | Parts | Index buffers | Max position delta | Max UV delta |
| --- | ---: | ---: | --- | ---: | ---: |
| Standing | 7,332 | 6 | all equal | 1.9 µm | 4.4 × 10⁻⁶ |
| Seated | 7,333 | 6 | all equal | 2.8 µm | 7.8 × 10⁻⁶ |
| Pilot (body) | 7,880 total | 6 of 7 | all equal | 1.5 µm | 4.4 × 10⁻⁶ |
| Pilot transmitter | 548 of the above | 1 | **differ** | 0.07 µm | 0.36 |

Bounds match the documented values (standing 0.6195 × 1.750 × 0.330 m). The body, clothing, hair and eyes therefore regenerate within float noise. The project-authored transmitter, built from Blender primitives, keeps its shape but not its vertex order or UVs; it is replaced by the owner's transmitter models in SC-HUM-01, so this is recorded rather than fixed.

## Additional CC0 sources downloaded (not yet shipped)

Downloaded from the fast mirror into `.tools/sc-hum-sources/` with a local `INTAKE.json` (URL, SHA-256, size, catalog page and hash). They enter `HUMAN_SOURCES.json` only when an asset ships.

| Pack | Content used for | Licence evidence |
| --- | --- | --- |
| hats01, glasses01, bodyparts05 | Caps, glasses, beards | Catalog "shared under CC0"; `license CC0` in each asset |
| shirts01, pants01 (incl. cargo pants and jeans shorts), shoes01 | Field clothing | Catalog per-asset CC0; `license CC0` in each asset |
| eyebrows01, eyelashes01 | Faces | Catalog per-asset CC0; `license CC0` in each asset |
| skins01, skins02, system_eye_materials01 | Skin and eye variety | Catalog "shared under CC0" (no licence line inside the material files) |

`pants01` provides CC0 shorts, so the CC-BY question in plan decision D9 now matters only for items CC0 lacks.

## Open in this step

- Scene budget per preset with `tools/scenery/budget.sh`.
- Camera census: per camera mode, each person's in-frustum share and head size in pixels.
- Reference photo board for the owner's silhouette overlay.
