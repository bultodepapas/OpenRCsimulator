# R11 native package candidate -09

This is a separate physical candidate prepared for the canonical package lane. No export or Godot runtime test was run during materialization.

The source is `/home/bulto/openrc-r11-package-20261015-08`, captured by [`candidate-after-overlays.json`](../derived-package-20261015-08/candidate-after-overlays.json), SHA-256 `f61830ce291e789a76d43d059a5d6253ffa2d367e8857a9fa322ebc1e2b4f5f4`, tree SHA-256 `84fdc89552592750909ab85407b4e7ded9aa18327d8dd22da6e3c7d3d69a51a1`, 14,923 entries. The materializer checked every manifested source entry before copying, physically copied the source files and `.git` support tree, and verified the source and Git metadata remained unchanged afterward.

The -08 directory also contained 449 unmanifested generated outputs. Their individual paths and hashes are recorded in [`source-unmanifested-output-inventory.json`](source-unmanifested-output-inventory.json): 442 Godot cache files under `app/.godot/`, five `dist/` export outputs, the pinned `.tools/Godot_v4.7.2-stable_linux.x86_64`, and one generated GDExtension UID sidecar. They were classified, excluded from the -09 copy, and verified unchanged after materialization. `.git` was copied separately; no `.tools`, `app/.godot`, `dist`, or `tmp` files were copied.

The only source-tree changes from the -08 manifest are the three allowlisted overlays:

| Path | -08 | -09 |
|---|---|---|
| `app/native/ground_vehicle/build-receipt.json` | SHA-256 `be1d0b04910c8a98b630b0db6616f650d5c61e8bc60900cf4b4af48a43e306ec` | merged Linux and historically verified Windows platform rows, SHA-256 `8718896783cb792f949732a5a4d74c6d08a1bde0bd52c43f9d1982efb3fd9ff7` |
| `app/export.sh` | SHA-256 `53469f21c4f897036b571c19c628e8749e5a2282d0462794219aa01a9a5ad369` | cross-platform receipt/artifact preflight and host-side pack checks, SHA-256 `dd7230a202a0ca01f805a6797963c37ece39306d8fbed956f5ed8d733c2a75e4` |
| `app/tests/check_native_pack.gd` | absent | native class, backend, ABI, receipt, and sidecar identity probe, SHA-256 `2249f62dfa8a4c8ffdabe78cab853a6247044be329d94c382c612e91f516d3ba` |

[`overlay-allowlist.json`](overlay-allowlist.json) records those three files and their input hashes. The final candidate has 14,924 entries, tree SHA-256 `28f30fec6d54b54d6b8606a3c28381ee5b14695f434d65fe44306c80df3678fb`, and manifest SHA-256 `bd9cc04069b725b1317bb3125c5f06bb0d338336d1f5e41b93c81e552ce3eebc`. It has zero removed paths and zero hardlinks. The copied Git identity is branch `r11-linux-source-snapshot`, HEAD `7c47c7ba02f7d2c874ec92a381ea73ef967069d6`.

[`materialization-receipt.json`](materialization-receipt.json) captures the exact manifests, delta, Git identity, excluded-output inventory, and physical-copy result. [`materialize_derived_candidate_09.py`](materialize_derived_candidate_09.py) contains the pinned source identities and refuses to overwrite an existing candidate or evidence output.

Before any runtime/tool staging, root independently read all 14,924 candidate files (2,097,084,555 bytes), checked every SHA-256, size and mode against the final manifest, required one link per regular file, recomputed the manifest's tree digest, and compared the complete source path set. [Independent review](root-source-review-01.json): no changed, missing or extra source path. This approves the captured source for verification; it is not an export or runtime result.

Before materialization, the updated Python preflight passed six independent cases: the merged receipt and both platform binaries passed; missing Windows row, boolean ABI, per-platform source mismatch, optional envelope source mismatch, and a corrupted DLL each failed closed. Results and exact inputs are in [`export preflight evidence`](../../package-smoke/export-preflight-01/README.md). The Godot probe parser check and the expected missing-row failure also passed on -08; those checks are retained in [`parse-04`](../../package-smoke/native-package-draft-parse-04/check-only.log) and [`missing-row expected-negative`](../../package-smoke/linux-missing-windows-row-expected-negative-02/probe.log). The existing -08-only Windows-row rejection is expected because its original receipt did not contain a Windows row.
