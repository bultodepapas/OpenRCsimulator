# GDU-03 release export evidence

2026-10-25. Official Godot `4.8.beta1.official.4d10419ca` produced Linux x86_64, Windows x86_64 and macOS universal release archives. All three pass the existing package gates, ZIP CRC checks and streaming SHA256 verification. Nothing was published. This is prerelease engine adoption evidence.

The isolated project and full original checked logs are under `D:/OpenRCsimulator-experiments/gdu03-packages`. [Source receipt](source-receipt.json) binds the frozen 34,670-file manifest, authorized final overlays, native receipt and actual export build identity `5e5243dd-dirty` / numeric `0.1.8`. The Git commit alone does not reconstruct the overlaid project. The final official-editor import resnapshotted all 422 tracked import sidecars: only Carbon and Italy differ from the original frozen manifest. Italy now has the valid owner-generated import metadata; no sidecar contains `valid=false`.

Four later parallel UI edits to AppRoot, Screen, the livery picker and its test
were verified separately in the [current-source continuation](../suite/late-ui/README.md).
These archives retain the earlier bound snapshot; their compiled UI results
must not be attributed to those later source bytes. Subsequent integration-only
fit/checker changes also do not alter these runtime archives.

## Build and checks

The official Windows console editor ran the existing `Linux`, `Windows` and `macOS` release presets headlessly, with one shared `OPENRC_BUILD_*` identity and isolated profiles. The macOS preset used the verified project-local universal-template correction documented in [macOS evidence](../macos/README.md). Import and all three export invocations passed without engine errors or warnings.

After export, WSL ran the exact unchanged tail of `app/export.sh`, beginning at the native package artifact check. Its SHA256 is `0a974443377de34e089ed00bec9baf0862e74bba3f50101455e7f6c53323a14a`; exact equality to the production script tail was checked. This preserves the existing validators, ZIP commands and checksum generation. The separate checked preset calls avoid repeated slow WSL scans/import over NTFS; they do not replace the package checks. The production script needed one narrow portability fix: strip a trailing CR while reading `project.godot`'s numeric version, preserving the actual file bytes and strict numeric/tag guards. The existing export-identity suite, including a CRLF fixture, passed 7 tests with explicit Git Bash.

[Check summaries](export-checks.json) retain original report/log paths and hashes. They are compact summaries of those original checked-runner report/log pairs.

| Gate | Result |
| --- | --- |
| Exported Linux/Windows native binaries | Both receipt rows and exact binary hashes match |
| Actual Linux and Windows release startup | Three-second trim, 720 ticks, finite trace, expected aircraft input and build identity |
| All three packs, empty project | Field, lake bake, landscape, imported grass, textures, materials and 1,680-tree field pass |
| Rotorcraft, all three packs | 8 checks per pack pass |
| Linux and Windows host-native load | Exact matching native backend and float64 IEEE754 ABI pass |
| macOS archive | arm64+x86_64 executable, mode 0755 and ad-hoc signature structure pass |
| Mach-O minimum OS readback | arm64: macOS 13.0; x86_64: macOS 11.0; both declare SDK 26.5 |
| Windows/macOS numeric metadata | PE FileVersion/ProductVersion `0.1.8.0`; Info.plist `0.1.8` pass |
| Final Windows compiled UI | Existing responsive modal test: [672 cases, zero failures](responsive-modals.log) |
| Final Windows compiled livery UI | [256 checks, zero failures](livery-picker.log), including 13 decoded textures |
| Final archives | All three ZIP CRC scans and SHA256 checks pass; [checksums](SHA256SUMS) |

The modal test runs unchanged externally against the final Windows main pack. The livery test substitutes only the path of the excluded `tests/ui_driver.gd` helper; all assertions and production `res://` paths remain unchanged. Its adapter identity is retained in the check summary.

Installed LLVM 22.1.8 `llvm-readobj --file-header --macho-version-min` read both `LC_BUILD_VERSION` commands directly from the final archive's extracted executable. [Minimum OS receipt](macos-minimum-os.json) binds the archive, executable and tool hashes; [raw tool output](macos-load-commands.log) retains both slices. These are declared binary minimums, not native macOS compatibility test results.

Field checks retain 104 nonfatal glTF resource UID warnings per pack (312 across the three final pack checks). Godot falls back to the valid text paths and the resource assertions pass. These logs are not warning-free.

## Native 1080p capture

The actual final Windows release executable ran fullscreen at **1920×1080**, using the built-in `--capture --t=1.5 --out=...` path with GL Compatibility / OpenGL3 on an NVIDIA RTX 3090, driver 617.42. The checked process exited successfully with no engine errors. Pillow fully decoded the PNG; the built-in image/hash/scene/engine/renderer and render-counter fields passed validation. [Capture receipt](capture-1080p.json) binds the executable, image and original manifest.

Image, kept outside Git: `D:/OpenRCsimulator-experiments/gdu03-packages/tmp/exports/packaged-1080p/release-flight-1080p.png`. SHA256: `24c02276c7789c1607e3e4e4cfa2aeccd74e3d75af49a57896a9054a0b9befc7`.

Both reviewers observed a normal scene/aircraft silhouette, clouds/horizon and readable HUD, without a blank frame, missing sky or obvious shader failure. The aircraft occupies few pixels; detailed model materials require the separate native gallery evidence. The older capture-runner helper fixes 1280×720 and POSIX process groups, so it was neither used nor weakened for this native 1080p capture. No image is retained in Git. The GPU was released after capture.

## Scope

macOS checks validate the archive and load its resources using the Linux editor; they do not execute the macOS app. WSL checks qualify headless Linux CLI behavior, not a Linux desktop/display session. This capture establishes asset/render loading at the primary resolution, not performance acceptance, controller behavior or physical validation.

Companion strict profile qualification hashes loose source bytes and passes separately in [companion evidence](../companions/README.md). In compiled packs, the existing loader reports validation errors and refuses companion profile admission when solver source identity is `unavailable-export`. Packaged companion support therefore remains unavailable through this strict path; the resource checks do not qualify it. This existing limitation was not introduced by the engine switch, and no admission guard was weakened.

Final archive files remain under the isolated project's `dist/` directory. Their identities are in [SHA256SUMS](SHA256SUMS) and the check summary. Lake owner regeneration and unchanged geometry proof are recorded separately in [lake evidence](../lake/README.md).
