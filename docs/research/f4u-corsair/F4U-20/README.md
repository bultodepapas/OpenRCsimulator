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

## F4U-20-R2: reuse parked lighting measurements, 2026-10-25

Evening Home traced the same airframe again for every new paint: wing skins, belly strip, tips and landing-light seat. Home now shares these compact numeric measurements between validated imported liveries with the same manifest and local node transforms. Propeller scale, articulation, source revision and authored landing-seat policy participate in the identity. The existing three-preview eviction bounds their lifetime; the Corsair layout serializes to 1,060 bytes and contains no nodes, materials, meshes or full triangle buffers.

Each preview still builds its own kit, resolves its own authored anchors and crash hosts, and controls its own light mode. Every selected asset still passes normal validation. Daylight does not compute an unused layout. Ordinary flight dressing computes its own measurements, independent of Home.

### Measured effect at 1920×1080

Godot 4.7.2 Compatibility, RTX 3090, fullscreen Home. In one session, cycle Midnight → Three Tone → Scarlet → Splash, exceeding the three-preview cache. Compare the normal cache against a control that erases only the retained layout keys before each selection. Block order is control, cached, cached, control: eight selections per variant. Assets were previously loaded; these are preview misses, not cold disk starts. [Raw frame samples, source hashes and method](checks/light-layout-cache-2026-10-25.json).

| Maximum frame during each selection | Without layout reuse | With layout reuse |
| --- | ---: | ---: |
| Median of eight selections | 800.40 ms | 352.94 ms |
| Range | 717.49–929.26 ms | 285.25–402.96 ms |

The median hitch falls **55.9%**. This shared-workstation observation measures menu switching, not flight FPS or a hardware qualification. A visible pause remains. Initial model loading, validation, texture transcoding and shadow construction still cost time; the first lighting layout still requires tracing. Package size is unchanged.

### Verification

| Check | Result |
| --- | --- |
| `test_ui_home_preview_cache.gd` | 118/118: all thirteen cached layouts equal fresh layouts byte for byte; independently constructed kits have identical transforms, mesh vertices and crash-host paths. Checks pose/scale/revision/anchor invalidation, root-local authored seats, mode independence, bounded retention and daylight behavior |
| `test_night_kit.gd` / `test_aircraft_light_control.gd` | 36/36 and 173/173; fleet lighting, crash attachments and light-state policy remain intact |
| `test_ui_preview_resources.gd` | 20/20: bounded asynchronous resource ownership, latest intent and shutdown |
| `test_aircraft_liveries.gd` | 179/179: all paints, provenance, preferences and responsive menu/keyboard checks |
| Rendered debug-bridge lifecycle | `corsair_paint.txt`: one warm-up plus three measured cycles, including paint selection → runway flight → Home. Each measured sample has 963 nodes, zero orphans and 1,129 resources; zero growing counters or errors. Final exit has zero leaked objects and no crash |
| Visual inspection | Coastal Three Tone at 1920×1080; paint control remains visible and aircraft/light placement is intact. Capture stays in ignored `tmp/` |

No physics, delivered assets or generated manifests changed. The full suite and export were not rerun. The known three `MOON_UMBRA_*` unclaimed StringNames still appear at exit.

## F4U-20-R3: direct paint gallery, 2026-10-25

Home's highlighted **Choose paint (13)** button now opens a gallery instead of advancing to the next paint. All thirteen previews and their full names fit at 1920×1080 with normal text; the current paint has a check mark and selected styling. Choosing any paint takes two activations, regardless of its position. Keyboard arrows navigate the cards, Enter selects, and Back/Escape closes without changing the aircraft and restores focus. Larger text uses fewer columns and scrolling. Choosing the current paint closes without another model request.

The gallery uses thirteen 288×162 PNGs, **185,527 bytes in total**, rendered from validated production builds with a neutral reflection sky for metallic finishes. Each filename includes its source GLB's full SHA-256. Missing or outdated previews retain a named, usable card. [Generator and regeneration command](../../../../assets/aircraft/f4u-corsair-250/README.md#pipeline).

Opening and navigating the gallery never loads a livery GLB. One thumbnail is loaded per frame; reopening reuses a small cache owned by the current Home aircraft. Closing cancels pending thumbnail work, and changing aircraft replaces that cache. Home also reuses its menu choices when resolving paint IDs, removing three repeated manifest reads per selection. The model builder still performs fresh provenance and selected-asset validation; this is not a global validation cache.

### Verification

The shared tree changed engine versions and received an unrelated Ugly Stik merge during this work. Final integration checks use Godot 4.8-beta1 in an isolated checkout of `3ad5cd591`, with the final gallery, thumbnails and tests overlaid. Its Godot-generated import settings and dependent manifests were refreshed through their generators. After the merge, the current main tree also passed import, the 256-check picker suite and the rendered debug-bridge scenarios. The tested gallery, Home, AppRoot, builder and test sources match between the two trees ([source hashes and native observations](checks/gallery-review-2026-10-25.json)). These focused checks do not qualify the engine upgrade or the Ugly Stik changes.

| Check | Result |
| --- | --- |
| `test_livery_picker.gd` | 256/256: thirteen decoded previews, EN/ES at 1080p/1440p/4K/720p and 100%/200% text, complete names, selection visibility, real keyboard navigation/activation/cancel, single selection, no GLB loads, one thumbnail per frame, bounded reuse and cancellation |
| `test_aircraft_liveries.gd` | 179/179: all thirteen builds and identities, malformed/tampered assets, saved/default choices, direct gallery entry, retained menu metadata, responsive Home layout and keyboard access |
| Rendered production shell | [32/32](checks/gallery-production-2026-10-25.json), no engine errors: every paint selected directly and saved, default restoration, aircraft switching, selected paint in flight and valid/invalid CLI IDs. The fast-close path exposed a deferred-focus call after removal; the fix is covered by the picker suite and this clean rerun |
| Current-tree lifecycle at 1920×1080 | `corsair_gallery.txt`: one warm-up plus three measured samples, each with 1,076 nodes, zero orphans and 1,272 resources; the bridge reports zero growing counters and zero errors. Reselecting the current paint does not advance the preview generation. `corsair_paint.txt` exercises selection → flight → Home. Final engine log has no errors or shutdown leak messages |
| Visual inspection | Spanish gallery at 1920×1080: all thirteen cards, complete names, highlighted current paint, silver Chrome preview and Back fit. Capture remains in ignored `tmp/` |

The first implementation uploaded every thumbnail synchronously and showed 125–129 ms opening frames under Godot 4.7.2. It was replaced by progressive loading and Home-owned reuse. Final current-tree observations under 4.8-beta1 recorded a **66.34 ms** maximum frame on first opening (120-frame window, p95 17.07 ms) and **59.09 ms** on cached reopening (79 frames, p95 17.04 ms). Each window still contains one frame above 50 ms. The engine versions differ, so these are not a matched before/after benchmark or evidence of a percentage improvement.

These are short menu observations on a shared RTX 3090 workstation at 1920×1080, not flight-performance qualification. Cold loading of a newly selected GLB and the package duplication described above remain; this change avoids loading intermediate paints rather than changing their delivered geometry or materials. The full application suite and a new export were not run.

## F4U-20-R4: reuse the current menu theme, 2026-10-25

Opening the gallery now shares Home's current theme instead of constructing another complete theme and its styles. `Screen.mount` accepts this optional owner-supplied theme; other screens retain their existing behavior. Crystal effects still duplicate their own style overrides, leaving the shared theme intact. There is no global theme cache: reopening takes Home's current theme after accessibility or compact-layout changes.

The review also found that explicit card font overrides retained their opening size after a live theme replacement. Both visible names and accessible button text now follow the replacement theme. Font overrides and keyboard neighbor paths are refreshed only when the font size or column count changes.

### Evidence

Godot 4.8-beta1 Compatibility, RTX 3090, 1920×1080; four cached reopenings per variant after one warm-up. The median maximum frame was **36.86 ms before and 35.80 ms after** (ranges 36.14–37.06 and 35.06–36.70 ms). This small difference is a short shared-workstation observation, not a statistically qualified speedup. [Raw samples, source hashes and checked-runner reports](checks/gallery-theme-2026-10-25.json).

| Check | Result |
| --- | --- |
| `test_livery_picker.gd` | 285/285: previous layout/input/loading gates, owner-theme reuse across the EN/ES resolution matrix, unchanged shared styles after decoration, live 100%/200% text and compact-theme replacements, complete labels and refreshed keyboard columns |
| `test_ui_screen_stack.gd` | 38/38: modal isolation, focus return, nested menus and five Home → Fly → End cycles without node growth |
| Final native gallery soak | One warm-up plus three measured samples; 1,076 nodes, zero orphans and 1,272 resources at every sample. Zero growing counters, engine errors or warnings; final shutdown reports zero leaked objects and no crash |

The larger cold GLB loading cost remains. Physics, aircraft assets and provenance checks were not changed. The full suite and export were not rerun. An exploratory session emitted a Thread shutdown warning that did not recur in the separate final run; it is not claimed fixed.
