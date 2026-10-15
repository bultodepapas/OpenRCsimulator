# R11 derived Windows package candidate

This is a separate physical copy of frozen-07 prepared for a later Windows package export. No export, import, tests, or runtime smoke were run on this candidate.

The base is frozen-07’s captured final source manifest, [`post-overlay-initial.json`](../../next-candidate/materialized-20261015-07-01/post-overlay-initial.json), SHA-256 `7f7d14b202a18d270dbb1cc8c04aaad6471318a0f0a3a9f9b75e21a4cce804f6`, tree SHA-256 `b9108ec7cfa993a396a218fd809f9d58bee6e9e54d299424a6a42599f6f77e5c`. The materializer checked every source file against that manifest and copied all 14,922 files (2,096,622,953 bytes) to `/home/bulto/openrc-r11-package-20261015-08` with distinct inodes. It copied `.git` separately as `build_info` support. It did not copy `.tools`, `app/.godot`, `dist`, or `tmp`.

The only source-tree changes from the pre-overlay manifest are:

| Path | Frozen-07 | Derived candidate |
| --- | --- | --- |
| `app/native/ground_vehicle/openrc_ground_vehicle.dll` | absent | added from the staged historical Windows binary, SHA-256 `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c` |
| `app/tests/check_trimmed_flight.py` | SHA-256 `55c6d0f6a9ddf088c60de1050b964250f0af39ea36d1268574319273d9a69295` | replaced with the authorized exact-R02-identity checker, SHA-256 `bcaa40377bda39fc8e8e7a2be6753fc41441bf2901b0ca60d8c5feb11c203d81` |

`app/test.sh` is unchanged at SHA-256 `dae260326426be613b065b0ae00f040842c310fab217979b537a274b3b36b7d6`. The atmosphere tests `app/tests/test_atmosphere_column.gd` and `app/tests/test_atmosphere_column_session.gd` are unchanged at `a8afca6bdb619d71dc23c3d5e17b9da03007bb19099a592953dccc0f9e55dd3d` and `bc6fc303a22044ff63c10f3c38845ab5c5044b1d7c0979355d04e47041f5d1ec`, respectively. The frozen-07 checker and native directory remain unchanged; frozen-07 still has no Windows DLL.

The copied `.git` identity is branch `r11-linux-source-snapshot`, HEAD `7c47c7ba02f7d2c874ec92a381ea73ef967069d6`. The candidate Git status adds only the trim-checker modification relative to frozen-07; the DLL is present in the candidate tree even though Git ignores it. The tree manifests record one added path, one changed path, zero removed paths, and zero hardlinks.

The DLL is the previously retained Windows ABI 1 / native-v2 / RK4-v3 artifact. Its original Windows receipt and 50-check Godot 4.7.2 parity log are linked from the adjacent [native staging evidence](../README.md) and hashed in [`manifest.json`](../manifest.json). Its native-source SHA-256 is `e2ae0a5ffebc8d81636302d66238348035ee92bf51d2f40965db7053bb251541`, matching frozen-07. The historical builder fingerprint caveat in that manifest remains: the receipt was produced with the historical shared builder’s module-docstring hash, while frozen-07 contains a different builder-file hash with the executable AST otherwise verified equal. This task copied the retained, parity-checked binary; it did not rebuild it or claim a fresh build from the frozen builder.

[`overlay-allowlist.json`](overlay-allowlist.json), [`materialize_derived_candidate.py`](materialize_derived_candidate.py), [`candidate-before-overlays.json`](candidate-before-overlays.json), [`candidate-after-overlays.json`](candidate-after-overlays.json), and [`materialization-receipt.json`](materialization-receipt.json) capture the exact inputs, physical-copy result, Git identity, hashes, and two-file delta. The after-manifest SHA-256 is `f61830ce291e789a76d43d059a5d6253ffa2d367e8857a9fa322ebc1e2b4f5f4` (tree SHA-256 `84fdc89552592750909ab85407b4e7ded9aa18327d8dd22da6e3c7d3d69a51a1`).
