# Recovered aircraft Blender sources

Local recovery snapshot from 2026-10-28. These are source copies only; no file here is registered with or imported into the simulator. The original files were left in place.

The search covered the local `C:`, `D:` and `G:` drives (`G:` had no `.blend` files). The mapped `Z:` NAS was outside this local-drive snapshot. It found 675 loose aviation-related Blender files outside the existing source area. SHA-256 comparison identified 473 distinct contents missing from the repository. A conservative cleanup removed 122 local copies of early numbered versions (1.91 GiB); 351 distinct copies remain (9.51 GiB):

| Group | Distinct recovered files |
| --- | ---: |
| F4U Corsair | 194 |
| Sbach 342 | 105 |
| Skyhunter / RC aircraft | 43 |
| Aircraft engine and propeller components | 8 |
| Skywalker X8 | 1 |

The Avanti S, Turbo Timber and HX-700 files found on the drives match existing repository sources byte for byte, so they were not copied again. The search also checked 141 nearby ZIP archives. Their 181 aviation Blender members match loose files byte for byte; no archive extraction was needed.

Each aircraft now has three folders:

| Folder | Files | Contents |
| --- | ---: | --- |
| `models/` | 126 | Delivered or otherwise unmarked model files; this label does not establish final quality |
| `drafts/` | 128 | Working folders, revisions, trials and candidates |
| `backups/` | 97 | `.blend1` files, pre-edit saves and explicit backups |

Within each folder, files retain their original location and relative path. [manifest.csv](manifest.csv) records every loose file and ZIP member, with size and SHA-256. Active records point to a representative repository copy. Records marked `pruned-local-copy` retain the former repository path and the reason for removal; their original loose files were verified byte for byte and left in place. The removed copies had explicit early version markers: F4U `g1_01–19` and `R01–29`, Sbach `v01–07`, and Skyhunter reference `v01–03` and refinement `01–06`. Existing integrated aircraft sources were not changed. Repeated paths in the manifest point to one content-identical copy. The manifest contains machine-local source paths for recovery provenance.

The `.blend` copies are ignored by Git because this local collection is large and one file exceeds the repository's 100 MiB push limit. The manifest and this guide remain visible to Git. Related textures, scripts and other package files were not copied in this Blender-only recovery.
