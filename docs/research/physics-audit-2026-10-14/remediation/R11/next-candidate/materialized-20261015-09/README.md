# R11 package verification: materialized -09

This records a local export and package smoke for the frozen -09 source candidate. It does not certify physical realism or replace the full application test gate.

## Candidate and export

The candidate is `/home/bulto/openrc-r11-package-20261015-09`, with approved source manifest SHA-256 `bd9cc04069b725b1317bb3125c5f06bb0d338336d1f5e41b93c81e552ce3eebc` (14,924 entries, 2,097,084,555 bytes). Its three explicit overlays are the merged native receipt (`8718896783cb792f949732a5a4d74c6d08a1bde0bd52c43f9d1982efb3fd9ff7`), `app/export.sh` (`dd7230a202a0ca01f805a6797963c37ece39306d8fbed956f5ed8d733c2a75e4`), and `app/tests/check_native_pack.gd` (`2249f62dfa8a4c8ffdabe78cab853a6247044be329d94c382c612e91f516d3ba`). The materialization receipt and manifest are in [candidate staging](../../native-package-staging/derived-package-20261015-09/README.md).

The pinned Linux Godot 4.7.2 editor was copied as a separate support input, SHA-256 `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`; the support receipt also binds the installed 4.7.2 export templates.

The canonical command `./app/export.sh`, run from the candidate root, exited 0. Its log is [export-01.log](export-01.log), SHA-256 `c34f4657792d7c17ff30969e951539a181b00c39719731901203b3696a7e3f68`. The Linux trace and trimmed-flight checker passed; Linux, Windows, and macOS resource checks passed; and all three ZIP CRC checks passed. The export log contains 216 UID fallback warnings and no `ERROR:`, `SCRIPT ERROR:`, or `SHADER ERROR:` lines. The build identity is `7c47c7b-dirty` at Git HEAD `7c47c7ba02f7d2c874ec92a381ea73ef967069d6`.

An independent review rechecked archive SHA-256 values, ZIP CRCs, and the exported Linux/Windows executable and native library bytes. See [root-package-review-01.json](root-package-review-01.json). Archive hashes are Linux `4a71dbba9a3834a870a1b074fdd186eb02471523698f6c086cf6a630e0cdd9c7`, Windows `bd45461b0afb031524676044dbe5393003f600bea2055a5980a23f192b63d567`, and macOS `5f86318f54030a7eb66e14517cb102a54b1d0dec058c606b0455ed2a51586380`.

## Host-native and application checks

The exported Windows pack was opened with the pinned Windows Godot 4.7.2 editor from an empty project directory, using the exact exported DLL beside the editor and `check_native_pack.gd` as an external script. The probe passed: the Windows receipt row, native ClassDB identity, `VehicleDynamics` identity, sidecar hash, and ABI all matched. It exited 0 with no engine-error lines. Full command, input hashes, and report are in [windows-native-01/run.json](windows-native-01/run.json); the independent byte review is [root-windows-review-01.json](root-windows-review-01.json). This checks the packaged host-native integration, not cross-platform execution.

The exported Windows application itself also ran directly, without an external script, for each audited aircraft. Both runs used a three-second trace, produced 721 rows covering ticks 0–720, and passed the candidate's `check_trimmed_flight.py --duration=3` check. The root's independent review confirmed finite states, contiguous 240 Hz timestamps, build and aero identity, and aircraft input hashes against the frozen manifest.

| Aircraft | Direct application arguments | Result | CSV SHA-256 |
| --- | --- | --- | --- |
| Jensen Ugly Stik 60 | `--headless --audio-driver Dummy -- --trace=<csv> --t=3` | 720 ticks; level at 15 m/s; checker passed | `dce7a4aabe3646744d54b8143dba18134f9e3b988dd67a2cb3578bd3cf3ad1e3` |
| Jet / SebArt Avanti S A200 P100RX | `--headless --audio-driver Dummy -- --aircraft=sebart-avanti-s-a200-p100rx --trace=<csv> --t=3` | 720 ticks; level at 29 m/s; checker passed | `db0c961b9df1d4ac3a4ccccc952d5f4d2dc2103ece0974a21981d1fb28df3287` |

The run records, CSVs, stdout/stderr, and checker logs are in [windows-release-traces-01](windows-release-traces-01/). The trace header's build identity was `7c47c7b-dirty`; the source input hashes were `bdcf4d64c45676a112d837513ee1eef7ed017c39fa8b39b21236cd801950f723` for the Stik and `68d3fd42b28e30bf1dc210b838d945d517f062506749af14f995a5a5f39a83b6` for the Avanti. These are application smoke traces, not physical validation.

As a negative control, the same Windows host probe was run against the older -08 Windows pack, which lacks a Windows receipt row, with its DLL adjacent. It exited 1 in 0.865 seconds, found the expected `receipt has no row for host platform: windows` error, selected the GDScript reference backend, and emitted no engine-error lines or timeout. The control detects the reference-backend fallback despite the DLL and native class being present. Its complete record is [windows-missing-row-control-08/run.json](windows-missing-row-control-08/run.json).

## Post-export source integrity and limits

The read-only verifier [verify_post_export_source.py](verify_post_export_source.py), SHA-256 `b91b51980ae587f18718eeec15e196cb9e2bcf2de712d9fa0d5bc6e8097e2862`, compared the exported candidate against the approved source manifest after export. Its [post-export report](post-export-source-audit-01.json), SHA-256 `d3bb77ae3d545441ccd2a48626ec99917db861609027a708858580a29545ab32`, reports zero missing and zero changed source entries and zero unclassified extras. The 454 additional entries are 442 generated `.godot` import-cache files, 9 export artifacts, 2 generated UID sidecars, and the separately recorded pinned engine. The generated `app/tests/check_native_pack.gd.uid` is 20 bytes, SHA-256 `4c8ab00399609dfad1b292bc167c82295577b9858cc2386949e466e881550605`; the other UID sidecar is `app/native/ground_vehicle/openrc_ground_vehicle.gdextension.uid`, SHA-256 `aa79a6e4136d7e3aaaa5d8aa62eb409d79a0688d27a2b36f0836d6a8dedd4b0c`.

The report records Git HEAD, branch, and post-export dirty status separately from the approved source manifest. This run covers `app/export.sh` and the listed package checks; it is not a repeat of `app/test.sh`, a macOS runtime test, a published release, or evidence of real-aircraft validation.

The retained source-audit script emits a JSON report rather than encoding its verdict in the process status. Check `source_manifest_matches` and the missing/changed/unclassified arrays. It writes a fixed report path; a reproduction must use fresh candidate and output paths instead of overwriting this historical evidence. Dual-platform CI artifact assembly remains [unqualified in the current native workflow](../../../../../../../research/rc-monster-truck/native/README.md#installing-and-exporting).
