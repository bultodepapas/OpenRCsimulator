# F4U-20: all thirteen paint schemes on the g2 model (g2.2)

Reviewed and integrated 2026-10-24 for the [F4U plan](../../../F4U-PLAN.md). The owner asked for every existing paint on the g2 model ([DECISIONS](../../../DECISIONS.md), F4U-20). The author delivered `F4U_Corsair_g2_2_All_Paints`: the g2.1 airframe with thirteen schemes, Coastal Three Tone from g1 included.

## Review

| Check | Result |
| --- | --- |
| Package integrity | 638/638 files match `SHA256SUMS.txt`; the ZIP matches its `.sha256` |
| Preflight, `--profile f4u-g2` | All 13 GLBs PASS without warnings: 337,664 triangles, 46 meshes, 57–58 surfaces, 14–15 materials and 6–9 images each ([log](checks/preflight-g2_2.log)) |
| Same airframe as g2.1 | In all 13, every node keeps its parent, section and rest transform. Every mesh has g2.1's positions, normals and UV0, compared triangle by triangle per mesh. Eight schemes give the spinner cap its own material, hence 58 surfaces |
| Naval 308 | Re-exported (GLB `9fa3b86a…ba2c0851`, was g2.1's `cf4cdad6…`) with the same geometry |
| Visual review | Godot bench, 1920×1080, left and right three-quarter views of every scheme. Lettering reads correctly on both sides ("308", "U.S. NAVY", "Blue Angels", "Thunderbirds", "CHROME", "40", "12"), and insignia and wing markings are consistent. Sheets are outside the repository under `D:\OpenRCsimulator-evidence\f4u-detail-20261024\results\bench-g22-liveries\` |
| Open from g2.1 | The blade material still has no normal map in any of the thirteen schemes ([request](../../../F4U-G2-1-REQUEST.md#after-g21)) |

## Integration

| Step | Change |
| --- | --- |
| Contract | The livery limit rises from 8 to 16 in `app/aircraft/model_manifest.gd`, `research/aircraft-standardization/build_models.py` and [AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract). The suite's over-limit mutation now uses unique ids. The old one added duplicate ids, so it was refused for the duplicate, not the limit |
| Freeze | `assets/source-deliveries/f4u-corsair-g2-2/`: 135 files, 316 MB. Omitted, with author hashes in the source manifest: textures, previews, the twelve other `.blend` sources and the 152 MB UV cache, which exceeds GitHub's file limit |
| Generators | `manifest.py` reads the author's `SHA256SUMS.txt` and the livery list from `metadata.json`. `compile_model.py` reads that list in g2.2's format and proves all 13 are the default's airframe. `install_liveries.py` installed twelve GLBs with the default's import settings; Godot's import assigned their uids. `liveries_path` is back in the Corsair's `model-bindings.json` entry. `gear-samples.json` changes only its source hash. `build_models.py`, `build_descriptors.py` and `build_customization.py` are regenerated; physics and costing are unchanged |
| Tests | `verify_f4u.gd` pins the g2.2 default. `test_aircraft_liveries.gd` lists the thirteen ids, and its registry and Home checks find schemes by id. `livery_check.gd` cycles every scheme, and waits for UI-34c's staged flight start |

## Verification (Windows, Godot 4.7.2)

| Check | Result |
| --- | --- |
| Generators, `--check` | All current. `test_customization.py` OK, `test_preflight_glb.py` 17/17, large-file check passes (largest GLB 27.6 MB) |
| `verify_f4u.gd` | 33/33 with no engine error |
| `test_aircraft_liveries.gd` | 115/115: every scheme builds through the production adapter, passes the derived check and paints differently from the default; contract mutations, on-use hashing, preferences and Home's row |
| Related suites | 38 of 40 pass ([list](checks/integration-suites.txt)). The other two fail the same way on a clean checkout before the integration ([F4U-19](../F4U-19/README.md#integration-of-g21-2026-10-24)) |
| Production shell, 1920×1080, OpenGL | Livery check 32/32: Home cycles all thirteen and saves each; the backdrop and Fly build the chosen scheme; `--livery=blueangels` flies, and an unknown id is refused ([checks](checks/livery-check.json)). Retracts, flaps and smoke 15/15 ([checks](checks/systems-check.json)); wing fold 8/8 ([checks](checks/fold-check.json)) |

## Cost

| Item | Size |
| --- | ---: |
| Runtime GLBs in `app/assets/aircraft/f4u-corsair-250/` (stored once in git, shared with the freeze) | 263 MB |
| Imported scenes (`.godot/imported`), one per scheme | 714 MB (47–65 MB each) |
| Export package: the scenes plus the GLBs kept as proof | about 1 GB |

Flight displays the chosen scheme, while Home retains a bounded cache of recent previews. F4U-20-R1 below corrects an extra GLB load during export-package validation. The duplicated geometry still costs download and disk size. A texture-only paint switch on one shared geometry would bring the package close to one scheme plus thirteen texture sets. That needs authored material bindings per scheme ([F4U-16 decision](../../../DECISIONS.md)).

## F4U-20-R1: senior integration review, 2026-10-25

Reviewed the current working tree on Windows, Godot 4.7.2 Compatibility, including the newer Home flight-preparation work. Two defects were corrected:

- **Paint disappeared above the catalog viewport.** Opening Aircraft scrolls to the selected Corsair, hiding the old paint row. Home now pins the row below navigation. Aircraft → Down reaches Paint; Paint → Down reaches the selected aircraft. At large text sizes, navigation and paint share the scrollable page so neither consumes the entire body. The row disappears outside Aircraft and for models without selectable paints.
- **Export validation loaded an unselected GLB.** The previous package checker loaded the default asset during `describe()`, then the alternate asset during livery validation, before the importer built the selected scene. GLB checks now verify resource existence and source-proof hashes without loading the scene. The importer still loads and validates the selected `PackedScene`; other dependency types keep their loadability checks. This corrects the earlier “only the chosen scheme loads” statement for exported builds. No reduction in package size is claimed.

### Verification

| Check | Result |
| --- | --- |
| `test_aircraft_liveries.gd` | 179/179: all thirteen builds and identities, invalid data, preference persistence, menu layout at 1080p/1440p/4K/720p in EN/ES, 100%/200% text, and real Down-key navigation at 200% |
| `test_aircraft_package_proofs.gd` | 34 parent checks pass, including an isolated PCK overlay with the actual Corsair proof. A resource-loader spy detects eager GLB loads; tampered hashes remain rejected, and the real scene subsequently loads with the cache bypassed |
| `verify_f4u.gd` / `test_imported_aircraft_model.gd` | 40/40 and 68/68 |
| Home regression suites | `test_ui_home`, `test_ui_home_layout`, `test_ui_aircraft`, `test_ui_change_aircraft` pass |
| Rendered production shell, 1920×1080 | [32/32](checks/senior-review-liveries-2026-10-25.json): all thirteen previews and saved choices, wrap to default, aircraft switching, selected paint in flight, valid/invalid CLI livery IDs. Captures stay in ignored `tmp/`; Midnight, Spectrum and Chrome menu captures were visually inspected |
| Debug-bridge regression | `tools/debug/scenarios/corsair_paint.txt` passes at a confirmed 1920×1080 viewport: select paint, launch, return Home, retain selection |
| Repeated lifecycle | Same scenario: one warm-up plus three measured cycles; 962 nodes and zero orphan nodes each time, zero monotonically growing counters, zero engine errors, zero leaked objects at final exit |

### Remaining limits

- **Cold switching is still expensive.** Before the fix, an isolated rendered Home run on an RTX 3090 at 1920×1080 recorded a 1,294.76 ms frame when first selecting Coastal Three Tone. Median was 16.64 ms and p95 17.04 ms across that 164-frame window. This is a short Home observation, not flight-performance qualification or a measured before/after improvement. The source-tree cold path is unchanged by the package-only loading fix. Later verbose runs also show repeated BasisU texture transcoding; its share of the rendered hitch has not been isolated.
- The disk/package duplication described above remains. Texture/material-only variants on shared geometry are the larger optimization opportunity; this review does not replace the author's delivered models.
- One earlier two-cycle debug session reported four leaked objects on exit without verbose identities. A fresh verbose single-cycle run and the four-cycle soak both exited with zero leaked objects. Treat the first observation as unresolved, not as a demonstrated persistent Corsair leak. The three known `MOON_UMBRA_*` unclaimed StringNames remain outside this change.
- This is focused software verification. The full application suite and a new complete export were not run; the export-path regression uses a PCK overlay. F4U-14 physical validation and the g2.3 blade-normal/cowl-flap work remain open.
