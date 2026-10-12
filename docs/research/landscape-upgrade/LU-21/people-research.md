# LU-21 — Human source and authoring record

Date: **2026-10-12**. **Status: three static human poses are integrated and native-verified; combined timing and acceptance are in the final LU-21 report.** Step: LU-21.

## Source route

The accepted people use the MakeHuman male1591 proxy with CC0 skin, eyes, eyebrows, short hair, casual clothes and shoes. MPFB 2.0.18 in Blender 5.2.2 assembled and textured the character; the poses are frozen into ordinary meshes for Godot, without a skeleton or runtime animation. The standing/pilot base pose is MakeHuman's CC0 **standing02**. The seated pose uses **Anrico's anrico_sitting03**, listed as CC0 on the poses01 catalog and confirmed by the included pose metadata. The two records and selected assets agree; the earlier `callharvey3d_sittingdefault` candidate was excluded because its package metadata conflicted with the catalog.

Primary license evidence and exact download hashes are recorded in [HUMAN_LICENSES.md](../../../../assets/scenery/population/HUMAN_LICENSES.md) and [HUMAN_SOURCES.json](../../../../assets/scenery/population/HUMAN_SOURCES.json). Only 0.7 MiB of selected small source references are vendored: clothing/proxy/material descriptors and the standing and seated BVHs with their metadata/thumbnails. The 267.7 MiB system-assets archive and full pose/tool archives remain in ignored `.tools/` storage; the complete system pack is still needed to rebake source textures.

The portable authoring recipe is [generate_people.py](../../../../tools/scenery/population/generate_people.py). It accepts one of `standing`, `seated` or `pilot`, an MPFB user-data directory containing the installed system assets, and an output directory. For an isolated authoring session, use Blender 5.2.2 with MPFB 2.0.18 installed in a task-local Blender extension location and set `BLENDER_USER_CONFIG`, `BLENDER_USER_SCRIPTS`, `BLENDER_USER_DATAFILES` and `BLENDER_USER_EXTENSIONS` to task-local folders before launch. The recipe redirects MPFB's user-data preference in-process; it does not save or change Blender preferences. A typical PowerShell invocation is:

```powershell
$stage = '.tools/lu21-human-authoring/blender-user'
$env:BLENDER_USER_CONFIG = "$stage/config"
$env:BLENDER_USER_SCRIPTS = "$stage/scripts"
$env:BLENDER_USER_DATAFILES = "$stage/datafiles"
$env:BLENDER_USER_EXTENSIONS = "$stage/extensions"
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' `
  --background --factory-startup `
  --python tools/scenery/population/generate_people.py -- `
  --pose seated `
  --mpfb-user-data .tools/lu21-human-authoring/mpfb `
  --output-dir .tools/lu21-human-authoring/output
```

Use `--pose standing` or `--pose pilot` for the other variants. The seated run defaults to the vendored Anrico BVH; the other two default to the vendored standing02 BVH. An alternate BVH can be supplied with `--pose-file`. The script writes separate glTF, binary buffer, image maps, a Blender source scene and a preview into its output directory. The final accepted exports were generated and verified before the script was made portable; this edited recipe received static syntax validation only, not a new Blender run.

## Geometry and fit

| Pose | Bounds (width × height × depth) | Triangles | Mesh parts / surfaces / materials | Nodes |
| --- | ---: | ---: | ---: | ---: |
| Standing | 0.6195 × 1.750 × 0.330 m | 7,332 | 6 / 6 / 6 | 7 |
| Seated | 0.5873 × 1.4435 × 0.7252 m | 7,333 | 6 / 6 / 6 | 7 |
| Pilot | 0.6475 × 1.750 × 0.4341 m | 7,880 | 7 / 7 / 7 | 8 |

The pilot's project-authored transmitter adds 548 triangles. All models are centered in X/Z, touch the ground at Y=0 and face Godot −Z. The seated rear-buttock/upper-thigh contact measurement is **Y=0.47421 m** from 375 imported mesh samples against the existing **0.48 m** bench surface; its feet stay grounded at Y=0. The landscape lead has reviewed the poses in-field and accepted the seated fit and pilot silhouette. Seven exported texture maps are shared across all poses by content hash and total **4,267,570 bytes**. The isolated Godot 4.7.2 Compatibility import probe passed: no Skeleton3D or AnimationPlayer remains in any pose.

At thirteen placements, the static geometry represents roughly 95,000–102,000 triangles before renderer culling. Per-instance transform, draw batching, final memory accounting and final capture timing belong to the integrating landscape track. The three poses share one male body, face, hair, outfit and texture set, so repeated placement needs careful orientation and spacing to avoid obvious repetition. The pilot fingers are intentionally relaxed/open around the radio; fine finger grip was not authored.

## Local settings note

The first MPFB startup created a 14-byte file at `%APPDATA%/Blender Foundation/Blender/5.2/mpfb/config/log_levels.json` (`{"default": 3}`). An attempt to remove it was rejected by the environment. It remains untouched; no further cleanup was attempted. Subsequent authoring sessions used task-local Blender user directories. This file is outside the repository and has no simulator runtime role.
