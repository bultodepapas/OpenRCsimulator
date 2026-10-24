# SC-HUM-00 — Baseline: authoring toolchain and sources

Status: **done except the reference photo board, 2026-10-24.** Toolchain, source intake, camera census and the scene-budget re-baseline (after SC-HUM-02…08) are complete. Plan: [field people plan](../../../plans/field-people.md).

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

`pants01`'s CC0 jeans shorts turned out to be women's short shorts, so CC0 still lacks men's shorts and baseball caps; plan decision D9 stays open for those ([SC-HUM-07](../SC-HUM-07/README.md)).

## Camera census (2026-10-24)

[camera_census.gd](../../../../tools/scenery/population/camera_census.gd) drives the production `CameraRig` along a 101 s reference sortie at the default field (take-off, circuit at 40 m, low pass at 4 m, approach, landing; 1,014 samples). For each camera view it projects every person's head (0.23 m) at 1920×1080, inside a 1080p viewport so the pilot auto zoom behaves as in play. Geometry only: occlusion by shelters and trees is not modelled, so "in frame" is an upper bound. Raw output: [camera-census.json](camera-census.json).

| View | Flight-line pilots | Pits standing | Pit workers | Spectators and veranda |
| --- | --- | --- | --- | --- |
| Pilot (auto zoom) | **18.9 % in frame, head 31.6 px median, 52.1 px max** | 0.1 %, 7 px | 1.0 %, 6 px | 0 % |
| Chase | 18.6 %, 2.9 px (max 10.4) | 16.2 %, 2.6 px | 12.8 %, 2.6 px | 15.7 %, 2.3 px |
| Orbit | 47.8 %, 1.8 px (max 16.5) | 46.0 %, 1.9 px | 40.1 %, 2.0 px | 46.4 %, 1.6 px |
| Close-up | 15.7 %, 4.3 px (max 14.9) | 14.1 %, 3.7 px | 12.0 %, 3.8 px | 14.4 %, 3.3 px |

Consequences for the plan:
- In flight, the **flight-line pilots are the only people seen at readable size**. The auto zoom makes their heads larger than the plan's 50° estimate (17–20 px). Their transmitters (SC-HUM-01) and faces matter most.
- Pits, workers and spectators are behind the pilot. In the flight cameras they are a few pixels tall. Their detail serves ground, taxi, Home and trailer views, not flight.

## Scene budget after SC-HUM-02…08 (2026-10-24)

`OPENRC_SCENE_DETAIL=high tools/scenery/budget.sh` (1280×720 qualification viewport, llvmpipe; the guard's own convention). [Summary](budget/summary-high.md), [JSON](budget/summary-high.json). Compared with the previous High run ([L8a-R1](../../visual-quality-implementation/L8a-R1/budget/summary-720.md)):

| Measure | Before | After |
| --- | ---: | ---: |
| `scenery_Population` draws, pilot / ground / aerial | 49 / 49 / 49 | **40 / 41 / 41** |
| `scenery_Population` drawn primitives, pilot max | 272,487 | 254,803 |
| Pilot-view total draws, worst view (limit 360) | 350 | 342 |
| Renderer texture estimate | 473 MiB | 471 MiB |
| `scene_budget.json` | pass | **all limits pass** |

Six different people, with mipmapped VRAM-compressed atlases, cost no more texture memory than LU-21's single uncompressed person set, and free about 8–9 draws in every view class. The whole-scene totals also include other tracks' concurrent changes, so the population line is the attributable figure.

## Open in this step

- Reference photo board for the owner's silhouette overlay.
