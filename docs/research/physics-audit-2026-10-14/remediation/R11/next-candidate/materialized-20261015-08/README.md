# R11 local export integration: candidate -08

This report records a local package diagnostic on the physical Linux candidate `/home/bulto/openrc-r11-package-20261015-08`, based on commit `7c47c7ba02f7d2c874ec92a381ea73ef967069d6`. The source manifest contains 14,923 entries with tree SHA-256 `84fdc89552592750909ab85407b4e7ded9aa18327d8dd22da6e3c7d3d69a51a1`; its manifest SHA-256 is `f61830ce291e789a76d43d059a5d6253ffa2d367e8857a9fa322ebc1e2b4f5f4`. The candidate is the reviewed -07 tree plus the staged historical Windows native DLL and updated trimmed-trace checker. The [materialization receipt](../../native-package-staging/derived-package-20261015-08/materialization-receipt.json) and [candidate source manifest](../../native-package-staging/derived-package-20261015-08/candidate-after-overlays.json) bind that allowlist, native provenance and Linux-only build receipt.

The pinned Godot 4.7.2 Linux binary was physically copied from -07 into `.tools/` as a separate support input (SHA-256 `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`, 146,414,384 bytes, link count 1). Installed export templates were the pinned `4.7.2.stable` set recorded in [pinned-support.json](pinned-support.json); `.tools`, `.git`, the fresh import cache, and `dist/` are separate from the source manifest.

## Local export result

The exact candidate `app/export.sh` bytes had SHA-256 `53469f21c4f897036b571c19c628e8749e5a2282d0462794219aa01a9a5ad369`. Running `./export.sh` in the candidate's `app/` imported the project and generated Linux, Windows and macOS preset outputs. The script also passed the compiled Linux trimmed-level-flight check (720 ticks, 3.0 s; finite samples; altitude 30.000 to 30.000 m; speed 15.0000 m/s), macOS universal/ad-hoc bundle check, and executable/Info.plist version checks for 0.1.1.

The script then failed with exit 1 during the first rotorcraft main-pack check. Eight resource assertions reported 0 failures, but the editor process emitted a GDExtension loader error because it could not find `native/ground_vehicle/libopenrc_ground_vehicle.so` beside the editor executable. The export script treats that engine error as failure and stopped before checking the Windows and macOS packs or producing the final aggregate release archive/checksum output. This is the same editor-sidecar lookup limitation observed in the -07 main-pack diagnostic; it is not evidence that the Rotorcraft assertions failed. The run is a local integration diagnostic, not an all-platform package acceptance or release result. Full command output is [export-01.log](export-01.log), SHA-256 `d279aed2d55bbdd8ebbd84869496915814d45628327b507f30ec64f189506cd4`.

The generated `dist/` files are preserved and separately hashed:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `linux/openrc-simulator.x86_64` | 158,725,584 bytes | `89042d0be5cf9813e6cbeb1d3fb5f47f9ec881eae0a9ab565c39c55b1ddb049d` |
| `linux/libopenrc_ground_vehicle.so` | 979,304 bytes | `08c8c08e74bd9c9465d1c0f732b082fc23829dcf243287eac51f25ed4e98f3a3` |
| `windows/OpenRC Simulator.exe` | 194,333,856 bytes | `854c42136d75124963cf817fde465aa633fddd374706947ba7965fc034ff7b8c` |
| `windows/openrc_ground_vehicle.dll` | 445,952 bytes | `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c` |
| `macos/OpenRC Simulator.zip` | 133,585,806 bytes | `1ce5ca017f6d3cf989b4d06566ad0df71aa0ad29773505a195086fdaa0c54590` |

The package staging receipt has only a Linux build receipt (`be1d0b04910c8a98b630b0db6616f650d5c61e8bc60900cf4b4af48a43e306ec`). The Windows DLL is a separately staged historical artifact with its own provenance; this export run did not test Windows native loading or backend selection. The macOS preset excludes `native/ground_vehicle/*`. No target-platform physical runtime result is claimed.

## Fresh-path late-mount probe

The requested follow-up used the current live `rotorcraft_package_smoke.gd` source (SHA-256 `929aa191632812c9083f909771c99d125c0d9c05b1ab59c8acf72076a49d3cae`) directly with `--script` and a fresh, empty `--path` for each pack, without `--main-pack`. The Linux executable, Windows executable and the single PCK extracted from the macOS archive each produced the same script errors and reached the 60 s timeout (GNU timeout exit 124): `Identifier not found: HeliRotorBlur`, followed by a failed load of `res://render/rotor/heli_rotor_blur.gd` and a call to missing `measured_profile`. The source declares `class_name HeliRotorBlur`; an empty project path does not initialize the application's generated global-script-class registry. That registry explanation is an inference from the empty launch path and identical parser error; the failure occurs before the probe emits its check summary and does not establish whether any of the three packs lack resources.

The missing-pack negative control returned 1 immediately with `Could not mount rotorcraft pack`, no engine-error marker, and no loose-resource fallback. Positive and negative raw outputs, commands, input hashes, time caps and outcomes are in [package-mount-01/results.json](../../export-resource-probes/package-mount-01/results.json), SHA-256 `5bcaa1ddaae41d6d9ae72ab6ea35b0eaca2df764da91f40f01f358ce83110554`. The three positive logs are byte-identical (SHA-256 `5aeb9ab99c7498b78dfd8b3696268ffd979635aad0060b17d24b1aaa203a1043`); the negative-control log is `780879a1d1fe2f423fb88ee49ca1fa56294c9ba8c801509317f4ccacff36a334`. The runner source is [run_pack_mount_probes.py](../../export-resource-probes/run_pack_mount_probes.py), SHA-256 `8b419c7fb1a7358f53ba3fafe4c8304f1ed19aee5b295bc0c8ba609fb2b4e4af`. The current live export harness SHA is `4cd5e5d259f255327ed75d4ded074db0431fb3589225402e10eb98956e25dd6f`; it differs from the frozen candidate script used for the -08 export.

## Post-run integrity and reproduction

Every -08 manifested source path/mode/hash matches the pre-run manifest. The one additional path is the 20-byte Godot-generated `app/native/ground_vehicle/openrc_ground_vehicle.gdextension.uid` sidecar. Candidate HEAD, the 67-entry Git status and clean staged diff match the materialization receipt. `post-run-source-01.json` preserves the raw path/hash reconciliation; `postrun-classification-01.json` verifies all additions are classified and all manifested source is unchanged. The export outputs remain under `dist/`, outside the source manifest.

The export was run from the candidate copy, not the shared workspace:

```bash
cd /home/bulto/openrc-r11-package-20261015-08/app
./export.sh
```

The late-mount diagnostic command was run by:

```bash
python3 /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/export-resource-probes/run_pack_mount_probes.py
```

That runner pins the live probe hash, uses the candidate's exported artifacts and a fresh empty project directory for each invocation, imposes a 60 s cap, and refuses to overwrite its output directory. The source hashes and raw outcomes are frozen in `package-mount-01/results.json`. Neither failed diagnostic was treated as a passing package gate.
