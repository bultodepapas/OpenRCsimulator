# ClearView aircraft import research

**Date:** 2026-11-15. **Scope:** primary-source documentation, seven downloaded archives and the current OpenRC source. **Repository baseline:** `c930dcdbfe16d0f94f25d36c64e4384069730714`, including inspection of the working-tree Creator implementation. **Result:** a staged compatibility adapter is technically plausible; automatic faithful flight-physics conversion is not established. The [implementation plan](../../plans/clearview-aircraft-import.md) owns proposed steps and acceptance.

## 1. What was actually inspected

The [ClearView community catalog](https://rcflightsim.com/models.html) distributes downloadable models, including v5/v6 collections, aircraft packs and individual contributions. It links model-conversion and v6 authoring documentation. Its content and download availability were checked on the date above; that is not a release date or a guarantee that old links remain accessible.

Downloaded ZIPs were read as data with Python's standard-library `zipfile`; no downloaded program, script, scene or simulator was executed. Archives, images, audio and document originals were kept in the OS temporary directory, outside the Git tree. The [source inventory](clearview-source-inventory-2026-11-15.json) records exact URLs, bytes, SHA-256 hashes, member counts and per-model observations. No third-party asset is included with this report.

| Download | Compressed bytes | File entries | Model roots | Selection reason |
| --- | ---: | ---: | ---: | --- |
| [Ken Northup Plane Pack 1](https://time2rc.s3.amazonaws.com/kendata/cvplanepaks/CVPlanesPk1.zip) | 10,557,890 | 373 | 20 | Pack layout, naming, older models and varied provenance |
| [MC Extra 330 Red](https://time2rc.s3.amazonaws.com/mc-models/RP17/MC_3D_Hobby_Shops_Extra_330_Red.zip) | 1,414,972 | 15 | 1 | v6 aerobatic model, BMP paint and articulated objects |
| [Calmato 40 Sports](https://time2rc.s3.amazonaws.com/tb-models/Calmato_40_sports.zip) | 1,183,603 | 14 | 1 | Conventional fixed-gear aircraft, distinct visual filename |
| [MC Tiburon biplane](https://time2rc.s3.amazonaws.com/mc-models/OP/MC_Tiburon-bipe-7-2.zip) | 580,124 | 12 | 1 | v5 controls, multiple ailerons and `PlaneParamModel.ac` |
| [V-22 Osprey](https://time2rc.s3.amazonaws.com/tb-models/V-22_Osprey.zip) | 633,845 | 21 | 1 | Multiple motors, moving geometry and duplicate parameter location |
| [MC 300S Air Guard](https://time2rc.s3.amazonaws.com/mc-models/NP22/MC_300S-Air_Guard.zip) | 1,301,722 | 15 | 1 | Listed as a paint scheme, but contains a complete parameterized model |
| [F-117](https://time2rc.s3.amazonaws.com/tb-models/F117.zip) | 923,682 | 12 | 1 | Non-conventional appearance and non-default visual filename |

The [DHC-2 Beaver URL](https://time2rc.s3.amazonaws.com/pb-models/DHC-2_Beaver.zip) returned HTTP 403 both through the web fetcher and direct HTTP retrieval. This observation does not establish that the model is permanently unavailable. The fetcher's unsupported-ZIP error on other links was a tool limitation: direct retrieval of the seven archives above succeeded.

This is a deliberately varied sample, not a census. Other plane packs, other individuals, helicopters and landscapes were not downloaded. No importer, full AC3D parser, image decoder, flight or performance benchmark was run.

## 2. Findings from the actual archives

### Packaging and version selection

There are **26 model roots: 20 with `verNumber 5.0`, six with `6.0`**. The observed v5 files use flat parameters; the v6 files use typed sections. There are **121 `.ac` members under model `data/` directories**, all starting with `AC3Db`. A header scan does not prove that the complete files are valid or supported.

The root parameter file identifies the render model. Examples are `tomboscalmato.ac` for Calmato and `TombosF-117.ac` for F-117. The Extra uses `body.ac`; v6 models also contain `fmodel.ac` and `colbody.ac`. The v5 biplane instead names `PlaneParamModel.ac`. Smoke meshes are additional AC3D files. Loading every `.ac` as visible geometry would mix unrelated representations.

The V-22 also carries `wavdata/params.txt`, in addition to its actual model-root parameters. A recursive search for every parameter file would invent a second aircraft. Its top-level `modelMotors` lists `leftMotor rightMotor`; its presence in a plane download list does not make it a conventional single-prop aircraft.

The sampled Air Guard paint download contains geometry, `params.txt`, collision/physics geometry and WAVs. A “paint scheme” catalog category is therefore insufficient to classify a package as texture-only.

### Case and path portability

Five visual references fail an exact case-sensitive archive lookup but have a unique case-insensitive match:

| Reference in parameters | Actual ZIP member |
| --- | --- |
| `701F2/data/Body.ac` | `701F2/data/body.ac` |
| `701f/data/Body.ac` | `701f/data/body.ac` |
| `Agri Duck Duster/data/Body.ac` | `Agri Duck Duster/data/body.ac` |
| `Bellanca C-27/data/Body.ac` | `Bellanca C-27/data/body.ac` |
| `Beluga/data/beluga.ac` | `Beluga/data/Beluga.ac` |

V-22 references `V-22.JPG`; its texture member is `V-22.jpg`. All selected visual and texture references in this lexical scan resolve after unique case-insensitive matching. This does not establish that every dependency has been identified. A production resolver must reject two conflicting matches, rather than selecting one according to archive order or host OS behavior.

### Geometry, materials and syntax

After resolving those paths, selected render files contain 20–95 `OBJECT` records, 697–13,933 declared vertices and 579–19,049 declared surfaces. These are lexical declaration totals, **not triangulated counts**, decoded mesh sizes or hardware measurements. Selected render-model texture filename sets include JPEG, BMP and GIF. Brown-B1 references `smoke.gif` within its render scene, so ignoring all GIF-related objects requires an explicit effect classification.

The samples contain names such as `LAeleron`, `RAeleron`, `Ruder`, parent-qualified `*.XYZObject` nodes, separate propeller disks and controls; the biplane has additional left/right ailerons. Preserve source names and local parent transforms before creating stable output identities. Names are useful semantics, not a reliable universal rig schema.

Parameters include repeated `breakPart` directives, an identical repeated `motorRotatingMassDiam` in the Extra motor section, `//` comments and unmarked human annotations after numeric values. Whole-file dictionary parsing, last-value-wins behavior and permissive partial number conversion would lose evidence or accept ambiguous input. The actual version and section grammar must govern parsing.

The v5 biplane specifies `gravity 11.1`; that is a direct example of source settings that must not change OpenRC's shared environment. The Extra's aerodynamic sections refer to named airfoils, scale adjustments and prop wash; the Calmato motor has a power-curve record and an `OS61FX` label. Neither label nor field presence establishes a calibrated OpenRC installation.

## 3. Primary format documentation

### AC3D

The [Inivis AC3D format specification](https://www.inivis.com/ac3d/man/ac3dfileformat.html) describes a text hierarchy with version header, material palette, `OBJECT`, local `loc`/`rot`, texture coordinates and indexed surface references. `kids` defines children; object `data` has a declared length. The header's `b` denotes hexadecimal version 11. This is a concrete basis for a bounded legacy reader, not evidence of compatibility with newer AC3D variants.

The [Assimp AC importer source](https://github.com/assimp/assimp/blob/master/code/AssetLib/AC/ACLoader.cpp) provides an existing implementation to evaluate before creating equivalent geometry code. It handles AC object/material conversion and retains scene nodes; configuration includes subdivision and backface-culling handling. Its [license](https://github.com/assimp/assimp/blob/master/LICENSE) permits source/binary redistribution under notice and other conditions; this license does not grant rights to arbitrary imported models. No Assimp build or conversion was tested here, and `master` is an inspected source URL, not an approved dependency pin.

### Legacy hinges, contacts and scale

The official [control-surface guide](https://rcflightsim.com/fms2cv/pc_preparing_surfaces.html) explains `XYZGroup` and the hinge line from `OCoord` to `ZCoord`, plus multiple control/propeller instances. Preserve its local coordinate construction; a global Z-axis hinge guessed from a part's name is insufficient.

The [control-point guide](https://rcflightsim.com/fms2cv/pc_adding_control_points.html) distinguishes wheel and airframe reference markers. `COORD_TWHEEL` serves a tail wheel/skid or a nose wheel, depending on aircraft arrangement. A marker supplies a candidate location, not OpenRC tire, suspension or ground-support data.

The [tidying and scale guide](https://rcflightsim.com/fms2cv/pc_tidying_up.html) explicitly compares a model span of about two units with a documented 730 mm aircraft and leaves rescaling to a later exercise. It measures span on the example's Z axis. Consequently neither universal scale nor full axis-sign/datum equivalence can be assumed. A model-specific transform and real-dimension confirmation are required.

### Version 6 authoring documents

The four DOCX originals were downloaded directly, their XML text inspected, and hashes independently checked. The filenames and catalog link labels do not match the internal lesson order:

| Source URL | Internal subject | SHA-256 |
| --- | --- | --- |
| [Creating ClearView Models](https://time2rc.s3.amazonaws.com/CVManuals/Creating%20ClearView%20Models_.docx) | Introduction and v6 object/parameter structure | `bb8b866867cc0cf58f717b60520e388e0a4561035749e2bc81b32c1c67bc3dc0` |
| [Create plane model 1](https://time2rc.s3.amazonaws.com/CVManuals/Create%20plane%20model%201.docx) | Internal Part 3: collision and breakable parts | `d9ab9df86d72f7b8ffd5c8595ef52a267b4dc27862c1bcfeb12b374123538ca8` |
| [Create plane model 2](https://time2rc.s3.amazonaws.com/CVManuals/Create%20plane%20model%202.docx) | Internal Part 1: model physics | `26077ec40ae6c4be45022311a6042216efee621e638cbe01271d8c0141284f74` |
| [Create plane model 3](https://time2rc.s3.amazonaws.com/CVManuals/Create%20plane%20model%203.docx) | Internal Part 2: visualization | `4d563a72b5190e0a2965b9dee4fbeaed9ebd862341b23c8edde1ddb424e8f5b8` |

Spaces encoded as `%20` work for these downloads. The catalog's `+` encoding did not work through the web fetcher's rewriting. Identify documents by their contents and hashes when reproducing research.

The introduction identifies `verNumber 6`, typed parameter objects and separate physics, collision and render representations. The physics lesson links local coordinate objects, lifting surfaces, servos and motors. Its propeller example warns that drawn propeller geometry does not define physical propeller size. The visualization lesson associates moving render groups with physics objects by name. The collision lesson uses a simplified collision scene and special gear/propeller objects. These distinctions support separate extraction passes; they do not supply a universal OpenRC force-law translation.

### Parameter semantics and transfer limits

The [legacy plane parameter reference](https://www.rcflightsim.com/ClearViewPlaneModelParameterDefinitions.html) contains solver-specific tuning and incompletely explained fields. It labels `modelMass` as kilograms, describes adjustable gravity, and describes inertia-like and wash/damping coefficients rather than a full inertia tensor. Its `maxThrust` unit and its stated radians-to-degrees example are questionable. Do not use it as an unquestioned quantitative mapping or as a complete v6 specification.

The v6 documents and samples offer explicit inch, RPM and watt fields. An exact inch-to-metre conversion is possible; the receiving field's physical meaning still needs confirmation. Referenced built-in airfoil data are not necessarily contained in a ZIP. Unknown polars, power-curve axis semantics, source calibration, servo travel, complete mass distribution and ground laws remain separate authoring questions. Do not download or copy undocumented simulator tables to fill those gaps.

## 4. Existing OpenRC architecture and material constraints

Current source was checked directly after the graph index returned no Creator definitions and showed stale catalog information. The following references describe the inspected tree, not future line-number stability:

| Source seam | Observation | Implication |
| --- | --- | --- |
| [`source_importer.gd`](../../../app/workshop/creator/source_importer.gd), `capture_and_inspect` / `inspect_bytes` | Captures/hashes bytes, admits supported STL/GLB, refuses other formats | Add an upstream adapter; feed its normalized GLB back through admission |
| [`limits.gd`](../../../app/workshop/creator/limits.gd) | 32 MiB source, 200,000 triangles, 512 GLB nodes, 32 materials, 16 images and finite image/store budgets | Conversion output must fit existing ceilings or receive a separately justified policy change |
| [`visual_builder.gd`](../../../app/workshop/creator/visual_builder.gd), `_glb_scene` | Uses `GLTFDocument.append_from_buffer`, builds a runtime scene, checks allowed node classes and scripts | Works without editor import in principle; exported-target evidence is still required |
| [`visual_parts.gd`](../../../app/workshop/creator/visual_parts.gd) and [`placement.gd`](../../../app/workshop/creator/placement.gd) | Binds mesh-carrying nodes around their origins on local cardinal axes, at most two per role; placement derives a right-handed basis | Normalize/re-pivot representable legacy rigs and frames; refuse or version unsupported bindings rather than assuming arbitrary hinge support |
| [`compiler.gd`](../../../app/workshop/creator/compiler.gd), `compile_candidate` | Conventional single tractor electric, finite pack, gearless; exact v2 record reload and domain validation | A Calmato, aerobatic Extra, V-22 or F-117 is not admitted because its mesh loads |
| Same compiler, `KIND_SOURCES` | Only measured/manual/estimated authoring kinds, with generic source text | Extend provenance deliberately to carry attributed imported values; v2's broader vocabulary alone does not implement this |
| [`trial.gd`](../../../app/workshop/creator/trial.gd), `freeze` / `verify` | Requires accepted candidate; pins/reloads physical and visual identity | Converted source remains distinct from a flyable candidate |
| [`store.gd`](../../../app/workshop/creator/store.gd), publication boundary | Immutable source/definition blobs and revisions, one source slot limited to 32 MiB; storage does not judge physics | Save success cannot imply flight qualification; a retained larger ZIP needs a separate bounded blob/schema, not that source slot |
| [`main.gd`](../../../app/main.gd), `_requested_stage_backend` | Creator trials force `gdscript_reference` | Native stock qualification cannot silently cover imports |
| [`flight_log.gd`](../../../app/sim/flight_log.gd) and session recorder identity | Records physical data and source identity, not the visual source bytes | Replay needs an explicit visual closure/resolution policy |

The [aircraft contract](../../AIRCRAFT_CONTRACT.md) requires sourced quantities, complete capabilities and inventory, correct LE/FRD transforms, full derived mass properties and shared admission. It explicitly separates valid data from realistic behavior. [AC-12](AC-12-numerical-campaign.md) passed 8 of 17 preregistered cases and did not close its numerical gate; [AC-18/19](../../plans/aircraft-creator.md) Home/bundle foundations remain open. Those dependencies belong on the critical path to “import and use.”

Godot documents [runtime model loading](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html) and [`GLTFDocument`](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html). Its [`Image` API](https://docs.godotengine.org/en/stable/classes/class_image.html) has BMP/JPEG/PNG buffer decoders, but those methods do not establish bounded hostile-input safety. [`StreamPeerGZIP`](https://docs.godotengine.org/en/stable/classes/class_streampeergzip.html) provides streaming GZIP/deflate facilities; existing Creator evidence demonstrates zlib/PNG behavior, not a ZIP reader with exact raw-DEFLATE/CRC validation. Probe the pinned `4.8.beta2.official.cafc17a19` engine; online stable documentation alone is insufficient for these implementation guarantees.

## 5. Asset rights and distribution

The official [conversion guide](https://rcflightsim.com/fms2cv/preparing_to_convert.html) asks converters to check original and subsequent authors, particularly before distributing conversions. The [ClearView EULA](https://rcflightsim.com/license.html) restricts the simulator and derivative distribution. The examined pages do not resolve every community asset's rights or provide a blanket grant for OpenRC bundles. This report makes no legal determination about an individual download or private conversion.

The actual archives reinforce the need for a per-asset ledger. The Extra readme credits an original FMS author, conversion/modification author and paint contributor. The pack's Bell X-5 and 701f readmes have unresolved original attribution. Beluga contains a free-distribution/modification statement; Beech99 mentions a FlightGear source and an original GPL release. These statements require individual follow-up and, for copyleft material, preservation of applicable source/license obligations; they cannot authorize unrelated assets in the same pack.

Ship importer code independently from community assets. Retain authorship, source links, exact original/readme hashes and applicable permissions separately for geometry, textures, audio and any imported tables. Establish the needed rights before bundling, publishing fixtures or offering portable exports that redistribute those assets. Local file import and OpenRC-curated redistribution are distinct product actions; neither the download page nor an import checkbox settles all rights. No author was contacted during this research.

## 6. Engineering conclusions and unresolved work

Adopt the existing Creator intake, representation, compiler, trial and store. An upstream AC3Db adapter plus a source-aware physical authoring extension is smaller and more consistent than a new catalog/renderer/solver. Evaluate freely available converters before writing geometry code, but make tool selection depend on bounded parsing, fidelity, maintainability and packaged desktop cost.

The key unresolved questions have discriminating checks: prove bounded ZIP expansion and exact endings; compare a known asymmetric AC3D hierarchy/UV/hinge fixture against an independent converter; establish original image decoder limits in exported builds; select one corpus aircraft that actually fits a supported physical domain; close that domain's numerical gate; demonstrate source-aware save/Home/restart/replay; and measure the complete path at 1080p. No amount of visual inspection alone answers the physical questions.

Independent design review identified concrete gaps in hinge representability, source-archive storage and native image-decoder assurance. The plan now requires mesh re-pivoting/axis alignment or a versioned binding extension, a separate bounded original-package record, and a defined decoder subset with malformed/resource evidence. It also explicitly normalizes frame handedness before strict GLB admission. These are adopted implementation obligations, not proof that conversion or flight works.
## 7. Implementation evidence

**2026-11-15, AC-CV-01…03; experimental visual slice.** The adapter under `app/workshop/creator/clearview/` captures a local archive, inventories aircraft roots, parses v5/v6 observations and the declared render scene, and produces a self-contained GLB that is re-admitted by the existing `SourceImporter`. It does not compile legacy physics, execute scripts, load audio, read sibling host files or download missing dependencies. The Creator integration uses worker jobs, a pack picker, cancellation, stale-result rejection and the existing draft library. [Player instructions](../../AIRCRAFT-WORKSHOP.md#aircraft-creator-experimental).

### Implemented boundaries

- ZIP32: ASCII paths, stored or raw DEFLATE, single disk, consistent local/central headers, exact stream consumption and IEEE CRC32. No extraction. Ceilings are 64 MiB archive, 256 MiB advertised expansion, 4,096 entries, 64 model roots and 32 MiB per selected member. Actual expanded size must equal its checked header size. Capture reads and hashing poll cancellation in 1 MiB batches; indexing, inflate and CRC also poll. A blocking filesystem operation or native image decode is not interruptible within that call.
- A narrow corpus exception admits explicitly marked empty directories with method 0, zero compressed bytes and zero CRC but nonzero advertised size. Matching headers and aggregate size bounds still apply; directories are never readable payload. The receipt retains the explanation. UI explanations are capped at 32 individual directory hints plus a count.
- AC3Db: bounded hierarchy, local matrices, materials, surface flags, texture scale/offset and per-reference UVs. Concave polygons are triangulated on their Newell plane. Intersecting polygons, excessive position quantization and collapsed/flipped render triangles are refused. Short legacy polygons are reported, omitted from rendering and retained as marker metadata. Marker references have an additional 4,096-reference ceiling.
- Images: the existing strict PNG validator; a local 24-bit BI_RGB/BITMAPINFOHEADER BMP decoder; and a conservative JPEG preflight followed by the pinned engine decoder on the same bytes. JPEG admits SOF0/8-bit/three components, one interleaved Huffman scan, 4:4:4 or 4:2:0 sampling, checked quantization/Huffman tables and complete entropy, including restart intervals and padding. Progressive/arithmetic/multiple-scan images and unqualified APP metadata are refused. APP1/APP2/APP13 are currently outside the subset. JFIF and the bounded Adobe transform subset are checked; comments are counted and reported. Image dimensions, aggregate pixels and byte limits are checked before native decoding. This is not exported-platform native-decoder memory/CPU qualification.
- Original Phong material parameters, ordered raw parameter observations, marker geometry, archive/member SHA-256 values and unique case-adjustment flags are retained in `asset.extras.openrc_clearview`. Material rendering uses a documented Phong-to-PBR approximation. The normalized GLB is the existing immutable source blob; the original ZIP remains external. This does not implement the separate original-package blob or portable-source closure from AC-CV-07.
- Converted bytes never grant flight admission. Orientation, scale, datum, physical authoring and moving-part bindings remain explicit Creator operations. A worker opening a saved draft checks both document identity and a user-typing generation before replacing the current draft, including invalid UI-owned numeric text. Navigation alone is not an edit. Cancel/failure preserve the current document; teardown can back up the current draft while a candidate is pending.

### Corpus outcomes

The [conversion matrix](clearview-conversion-matrix-2026-11-15.json) binds each result to the original archive hash. All 26 selected model roots passed parameter/declared-render parsing. The initial Windows visual campaign admitted 17 GLBs and refused nine; the coordinate-marker correction below admits B-52 as an eighteenth visual. This includes previews of layouts that the Creator cannot physically author, such as V-22. It establishes no automatic flight compatibility.

The initial refusals comprised three required GIF/unsupported texture cases, three JPEG metadata/encoding cases, two polygon cases and one render-precision case. Initial Extra 330 Red had 3,794 triangles and seven short-marker records. AirGuard's `Fuse` polygon 129 is independently confirmed as a proper planar bow-tie: its four references have the same x coordinate and crossing edges in the y/z plane. Ascent's `fuse` polygon 91 repeats a corner with different UVs; its touching-edge diagnostic also remains a refusal. The importer does not replace either case with a triangle fan or discard one UV. B-52's precision failure was confined to coordinate markers and is resolved below. These are diagnosed model outcomes, not ignored test failures.

### Tool choice and remaining qualification

The [Godot ZIPReader API](https://docs.godotengine.org/en/stable/classes/class_zipreader.html) returns a complete member buffer and exposes no raw-stream consumption/output-budget interface. The existing PNG inflater handles zlib, not a proven ZIP raw-DEFLATE boundary. This slice therefore uses a bounded raw decoder and archive reader, without changing direct Creator source admission.

The [Assimp AC importer](https://github.com/assimp/assimp/blob/master/code/AssetLib/AC/ACLoader.cpp) was considered as an upstream alternative. No Assimp or Blender implementation is copied or installed into the application. The portable GDScript adapter remains an experimental choice: an executed independent Assimp/Blender fidelity comparison, rendered reference checks, exported desktop decoder/resource campaigns and target-hardware peaks remain AC-CV-02/03/09 gates. Source review is not a completed comparator campaign. No performance threshold or physical qualification is inferred from these development checks.

### Verification receipts

Checks use generated fixtures; community ZIPs and images remain outside Git and required CI. New `test_creator_clearview_*.gd` tests are discovered by the existing test roster. Evidence below is focused software verification, with the pinned `4.8.beta2.official.cafc17a19` engine; it does not replace required CI or the open AC-12 numerical gate.

| Campaign | Evidence | Outcome |
| --- | --- | --- |
| Synthetic reader/visual foundation and 26-root parse, macOS arm64 | `clearview_visual_20261115_d`, jobs `f4136629cbcc4b1ea59b0280a7101eb2`, `3223853776ed43ee9f2c0d6d01843623`, `a2c0c72b66d44931b212bd52ad8f4a24` | Passed before subsequent UI/report hardening. |
| JPEG known pixels, restart/padding/stuffing, ZRL, predictor resets, all-prefix truncation and entropy mutations, macOS arm64 | `clearview_final_units_20261115_i`, job `04001df5ff6c4de1b421dfd985c28b17` | 363 checks, zero failures/errors/warnings, confirmed cleanup. |
| Real visual conversion, macOS arm64 | Same request, job `ffe9d66590094400a0654df4c125f597` | Passed; 16 conversions and 10 explicit refusals, 26 outcomes, zero engine errors/warnings, confirmed cleanup. |
| Final reader boundary, Windows x86_64 | `clearview_preview_windows_20261115_m`, job `ca3ac15a04af4828af94e14626febd50` | 87 checks, zero failures/errors/warnings, confirmed cleanup. |
| Final visual boundary, Windows x86_64 | CLI checked batch on snapshot `final-snapshot2`; job `e999974a67f148bcbdd4a697b8b340d7` | 48 checks, zero failures/errors/warnings, confirmed cleanup. Includes actual float32 edge collapse, translated source-collinearity, nonflat concavity, hierarchy, alpha and malformed receipt fields. |
| Final corpus, Windows x86_64 | Same CLI batch, job `1bfe8813af2e4dbc89aac6d03786b3f7` | Passed; 17 conversions and nine explicit refusals, 26 outcomes, zero engine errors/warnings, confirmed cleanup. |
| JPEG boundary, Windows x86_64 | `clearview_visual_diagnostic_20261115_o`, job `db86cd69fb944ef288baec825ae9c81d` | 363 checks, zero failures/errors/warnings, confirmed cleanup. |
| Creator ZIP journey, existing UI, persistence and language, Windows x86_64 | `clearview_wizard_windows_20261115_n`; jobs `bc79330f246f4b2d996d1ba6cf819a01`, `8e39c1bd0f8f46a79656f3535e2c5198`, `6285574ff5ed4f7e9c7ed99a472ace8c`, `739784f21a2e40f2a3917c68667192ef` | All passed: new journey 28 checks, existing UI 201, persistence 95, language zero failures. Zero engine errors/warnings; confirmed cleanup. Layout assertions use 1920×1080, headless. |


Failed development attempts remain available in the test pool. The first corpus run exposed the legacy directory hints and short marker polygons; later real conversions exposed the need for a Newell-plane projection. Reader test compilation briefly failed on a duplicate local variable, and the new UI test needed an explicit string type; both were corrected. A concave visual fixture was initially flat on an axis and was rejected by existing source admission, not by triangulation. The fixture was tilted into z=y; an unneeded replacement triangulator was discarded. A separate float32 edge-collapse fixture justified checking actual emitted triangle area and winding against float64 source geometry. The strengthened corpus check exposed translated collinear source faces whose Newell sums retained floating-point residue. Independent source-point subtraction proved their zero area; they are now reported and omitted before normal generation. This restored Extra, Beluga, A-10 and BD-5J; the initial final result was 17 conversions. BD-5J's `Pilot` polygon 610 is collinear, while Ascent and AirGuard remain refused. This corrects an earlier narrative that had reversed the BD-5J/Ascent outcomes; the retained matrix and logs were authoritative throughout. Full-app Mac import attempts timed out before test execution. A smaller test copy initially lacked transitive glTF binary/texture resources and also failed before execution; its dependency closure was completed. None of those infrastructure or compilation failures counts as passing coverage.

Independent read-only review prompted bounded empty-block work, cancellable CRC/capture, Unicode path-extra rejection, descriptor disambiguation, preservation of material/marker/alpha metadata, invalid-parent handling, provenance-note persistence and the open/edit race guard. Each was resolved in the lead-owned candidate. Original assets are not redistributed, and no author permission or physical validation is implied.

Subsequent Mac attempts were refused before execution because another Godot process was detected; it was not touched. Two detached snapshot attempts hit Windows Git DLL-initialization failures before dispatch. The documented CLI snapshot/batch route completed the final checks instead. Runtime source hashes in the final matrix bind the integrated adapter; required CI, exported builds, independent visual comparison and physical qualification remain open.

### Rendered integration and picker correction

Windows, Compatibility/OpenGL 3.3 on NVIDIA GeForce RTX 3090 (driver 617.42), actual window and root viewport **1920×1080** on a 3840×2160 display. Admitted debug sessions `T-5570b6a1231e4b26b1b95d8e7ee17a16` and `T-944d5cfc3a90441a921a3e50f1c8d852` used isolated profiles. The final frozen source digest is `2a5f52f74c4ab079a2d1efcfaff7fbacd31dd45366a7f68950145729d1cc9e6a`.

The actual Extra ZIP imported and rendered with its textures and 3,794 triangles. Saving and reopening its draft preserved the source and all four conversion explanations, including eight omitted zero-area surfaces and the empty-directory hint. The real Ken pack exposed all 20 model choices; Cancel retained the Extra, and selecting B-25 imported `B-25.glb`. Spanish labels and diagnostics were visually reviewed. Both owned sessions stopped with confirmed cleanup.

The first rendered picker overlapped its instructions with the first row. A VBox now separates the wrapped instructions from the list. The added non-overlap assertion passes in the updated 29-check UI journey: native job `T-462621a0d0fc423ea12457efe4b341a9`, zero errors/warnings, complete evidence and confirmed cleanup. The final 1080p capture confirms distinct instructions, readable rows, scrolling and both actions within the window. Two necessary captures remain outside Git under `D:/OpenRCsimulator-clearview-scratch/` (`clearview-preview-1080.png`, `clearview-pack-picker-1080.png`).

The session reported scene/resource and catch-up hitches around 0.85–1.16 s while opening views; this is functional visual evidence, not a performance qualification. Phong-to-PBR appearance remains approximate. Exported-platform fidelity, allocation peaks, cancellation latency and the physical/numerical gates remain open. Completed test/runtime copies were retained on D: to restore free space on C:; logs, reports and frozen source identities remain available.

### Coordinate frames and manual hinge proposals

**AC-CV-03/04, 2026-11-15 continuation.** Render-member `.XYZObject` coordinates are ordinary polygons, so the first adapter mistakenly rendered their triangles. The [official model-authoring manual](https://time2rc.s3.amazonaws.com/CVManuals/Create%20plane%20model%202.docx), Step 2, defines the moving-part naming convention and orders axis lengths Y < X < Z. Its captured SHA-256 is `26077ec40ae6c4be45022311a6042216efee621e638cbe01271d8c0141284f74`. The manual does not assign fixed vertex indices or a universal propeller axis.

The restricted recognizer accepts a qualified leaf poly with four vertices, two triangular `0x30` surfaces, no opaque `data`, a shared origin/X edge, one near-orthogonal origin and a right-handed frame. Normalized pairwise dot products must be at most `0.001`; adjacent ordered lengths must differ by a factor of at least `1.1`. Exact 2:1:3 lengths are not required. Unsupported or ambiguous reserved markers stop conversion with a named correction. All **261 render markers across 26 selected roots** satisfy this policy; 25 reference textures, which are not required for hidden helper geometry. The selected corpus does not establish support for older `XYZGroup`/`OCoord`/`ZCoord` layouts.

`motion.gd` retains original vertices, faces/UVs, local transforms, source node/parent identity and composed frames in the optional `openrc-clearview-frames-v1` receipt component. Floats use tagged IEEE-754 binary64 little-endian hex, preserving their parsed bits through JSON. The containing receipt retains member/archive hashes. This is source evidence, not authenticated metadata or executable rigging; saved sources are never re-rigged from extras.

Hinge proposals follow `params.modelServos` → one listed `servo.*` rotation → a `liftsurface.*` target → its explicit `renderGroupName` → one render frame. Input-only throttles and explicit `none` targets are not missing hinges. Unlisted sections cannot invalidate an active group's mapping. Multiple servos for one group, conflicting declarations, missing frames, foreign/unqualified descendants, nested frame identities, multiple parents and non-rigid parent frames remain unresolved. This increment does not inspect `fmodel.ac` to establish physical surface existence or reproduce ClearView mixers, channels, servo ratios, gear or propeller behavior.

An eligible group gets an appended pivot node whose local X follows the declared source axis; original node indices and names remain stable. Full affine inversion preserves neutral transforms without assuming rounded rotations are exactly orthogonal. A second check composes float32 render transforms and compares transformed bounds within `1e-5` of the part's extent. Precision loss, depth/node limits and a failed final rig admission retain the admitted static hierarchy. At most 32 eligible requests are examined; the first 16 unresolved entries have named explanations built from a closed reason table. Unknown saved messages and control characters are ignored.

The existing v1 bindings remain presentation only. The selector now includes proper subset groups with aggregate subtree bounds/triangles and both allowed slots for every control role. A closed, optional generic node axis hint supplies an editable default after manual selection; role and direction still require preview confirmation. Old GLBs without the new receipt component or hint keep their existing behavior.

The updated [Windows matrix](clearview-conversion-matrix-2026-11-15.json) records **18 admitted visuals, eight refusals, 203 retained frames in admitted sources and 50 unbound hinge proposals**. Extra now has 3,776 triangles, nine coordinate frames and six proposals. B-52 is the additional admission: independent source-order arithmetic found its first former precision failure at `RWWheel.XYZObject` (`body.ac:1446`); all 20 nodes failing the old precision predicate were coordinate markers, and no visible node failed. Hiding those markers fixes the refusal without relaxing visible-geometry checks. The eight remaining refusals are three unsupported textures, three JPEG cases and two polygon cases.

Focused checked evidence uses engine `4.8.beta2.official.cafc17a19`. Final motion/consumer source digest: `25d58e2f6e5157fe2dc02e0550852cadfe6df06ed96447065816d4b9c2ceb72f`. Every integrated Creator module and UI consumer matched that frozen input byte for byte.

| Check | Native job | Result |
| --- | --- | --- |
| Frames, proposals, actual bound ±30° preview, render precision, manual picker, Authoring restore, safe notes and eight locales; Windows | `cb6f235c32784a32b8fe43183cdb8290` | 221 checks, zero failures |
| Same motion test; Mac ARM64 | `e017107be6ea435ca6e7fb046dfdc00a` | 221 checks, zero failures |
| Readers; Windows | `f8158217dbe84fd6801d6e5ab641937b` | 87 checks, zero failures |
| Existing Creator persistence/UI; Windows | `29b0bbc0339247f0aaf87fdc72e3f5cf`, `cb7b574e6147432c9c68da05cc1f1670` | 95 and 201 checks, zero failures |
| Existing Creator language; Windows | `033583a44449427cadb196ecb1836833` | Zero failures |
| Existing visual consumer with expanded group contract; Mac | `0f05cafee1ac4c6182738166b42003e7` | 231 checks, zero failures |
| ClearView visual/UI; Mac | `a6170f054a9c42fd9c9271a9e2990b3d`, `61056c18031346828956ef4d6919d5d8` | 48 and 29 checks, zero failures |
| Final 26-root corpus and 261-frame classification; Windows | `7470490ad7454e60b49d266662939046` | Passed; 18/8 outcomes, zero failures |

These individual passing jobs have complete collected evidence, zero engine errors/warnings and confirmed cleanup. The consumer batch as a whole failed because its private corpus probe had an untyped local; that probe was corrected and passed separately on unchanged production modules. Earlier draft failures include explicit GDScript typing, an incorrect group-bound expectation, a valid unchanged German “Propeller” caption and an obsolete 17-conversion corpus assertion. They are retained, not counted as passes. One source freeze raced a still-running copy and was refused before dispatch; another hit the known detached Windows Git DLL failure. Synchronous snapshots completed the final verification. Completed private copies were retained under `D:/OpenRCsimulator-clearview-scratch/retired-motion/` to release C: space; logs and receipts remain in the test pool.

Rendered Creator check `T-8d2f0f6f0fc2421c87e86d93a6241aed` passed at an actual **1920×1080** root viewport on NVIDIA RTX 3090, OpenGL 3.3 / Compatibility, driver 617.42: zero errors/warnings, complete checked evidence and confirmed cleanup. The focused scene used the production Creator, import worker, theme and visual builder; it showed the actual Extra ZIP, named unresolved mapping, five manually assigned groups including the second rudder slot, and movement. Two inspected captures remain outside Git at `D:/OpenRCsimulator-clearview-scratch/clearview-motion-source-1080.png` and `clearview-motion-controls-1080.png`. This establishes functional UI/render evidence, not independent fidelity or performance qualification.

An interactive full-app journey (`T-0cbe45b430484738b4582019610ee823`) also preserved all five selected group bindings through Save draft → Open. Its test copy lacked stock authoring source files, causing an unrelated background Workshop contract error, so it is not a clean full-app gate. The 27 missing source inputs were supplied in a separate frozen copy; its retry (`T-c784cb387ab4432e97a56dfc4e46528b`) exhausted C: during unrelated asset imports and was stopped. Both sessions have confirmed cleanup. Automatic review refused deleting the completed first session's generated cache; moving that cache intact to `retired-motion/desktop-first-generated-cache` released space. The final focused check avoided those unrelated full-app imports and passed on unchanged production modules.

AC-CV-04 remains partial: V5 and propeller semantics, independent animation comparison, full source-package persistence and exported-platform qualification remain open. No flight, Home, numerical or physical gate is closed by these visual tests.

### Parameter declaration review (AC-CV-05, 2026-11-16)

The [official parameter table](https://www.rcflightsim.com/ClearViewPlaneModelParameterDefinitions.html), retrieved again on November 16, explicitly documents `modelMass` in kg. Its `pWingCG`/`pBodyCG` entries describe tuning offsets rather than a measured structural CG; `xRotMass`/`yRotMass`/`zRotMass` do not define an inertia tensor. Setup rates do not establish physical control travel. Gravity is an environment parameter, not an aircraft input. The retained HTML SHA-256 is `b35d96c218eadc5d0be929b0fa3dfc6f0ff1877f38c5c80f5a68ba71a163b0de`.

The private 26-root sample contains 20 v5 and six v6 declarations of `modelMass`. V6's shared spelling does not independently establish its unit: the report labels that interpretation inferred. The v6 guide and sample keys `propDiamInch`, `propPitchInch` and `maxRPM` support field-name inferences only. Extra declares 10.1 for mass, an 18×7 propeller and 17000 RPM; Calmato declares 2.0, 14×8 and 13000 RPM. Osprey has two motors and B52 has eight, so component namespaces must remain separate. These are source declarations, not measurements or flight configurations.

| Declaration | Review policy |
| --- | --- |
| v5 root `modelMass` | kg documented by the table; finite positive scalar only |
| v6 `params/modelMass` | kg inferred from the shared key; independent confirmation required |
| v6 `propeller.<id>/propDiamInch`, `propPitchInch` | inches inferred from spelling; reference conversion uses 0.0254 m/in |
| v6 `motor.<id>/maxRPM` | RPM inferred from spelling; each component retained separately |
| CG, rotational mass, gravity, setup/control rates and other selected keys | Unit or meaning unresolved; no physical mapping |
| Repeated keys, malformed/full-token failures, nonpositive dimensional values, shortened raw text | No numeric reference selected |

The converter optionally embeds the exact bounded `params.txt` bytes in GLB extras. On the import worker, the observer verifies canonical base64, member hash and safe root/member association, reparses those bytes, and derives a closed `openrc-source-observations v1` context. Numeric references use binary64 little-endian hex strings to survive JSON round trips. The display is capped at 128 rows and 256 raw characters per row; omitted rows remain available in the embedded member. The context is capped at 128 KiB. The existing 2 MiB GLB JSON and 32 MiB model ceilings stay unchanged. A real over-budget fixture proves the optional payload can be omitted while preserving visual admission, with a distinct explanation that survives reopen.

`CheckedReport` binds the worker's result to the same admitted source object. Like the existing `InspectedSource`, sealing is an internal GDScript ownership convention. Authoring accepts that typed receipt, not an arbitrary report dictionary, and performs no full source parse on the UI thread. Serialized member integrity remains a declaration; standalone compilation advertises `structure_only`. A parameter hash does not authenticate ZIP membership, authorship or physical truth. A saved revision's snapshot and normalized definition are compared on reopen; the inherited Store still does not prove semantic equivalence between that definition and the saved raw physical record.

Only documents carrying this extension use `openrc-creator-document v2` and `openrc-creator-definition v2`. Ordinary v1 snapshots keep their existing shape. Reopen compares the saved context against the newly derived report before replacing the current document. Source replacement clears the context and preserves independently entered fields. Compilation includes the context in definition identity, then removes it before physical generation: an enriched definition and its v1 physical equivalent emit identical aircraft bytes. No legacy declaration is adopted automatically. Total mass belongs to the inventory, the current power package fixes its components, and legacy servo timing lacks a verified mapping.

Independent review identified arbitrary report acceptance, repeated parsing on the UI thread, misleading over-limit reimport guidance and an unverified standalone integrity label. The lead replaced dictionary acceptance with the source-bound worker receipt, added a specific omission reason, and separated structural validation from integrity claims. Hostile-type execution also exposed unsafe Variant comparisons; explicit type checks now precede them. An initial fixture incorrectly rejected empty observation arrays; empty reports are valid and the assertion was corrected. The minimal test project's missing 240 Hz setting caused existing donor loads to fail a stiction gate at Godot's default 60 Hz; the project was aligned with the production setting without modifying physics or donor records.

The final frozen source digest is `3c1bc85012b1b90b40a419d5fb31ab0dc77c5c93537ee164ea1ea51017a72e66`; all 19 changed Creator files and catalogs match it. The earlier common candidate supplied the unchanged observer/compiler/parts consumers; subsequent UI checks cover rejected-open recovery, the platform-correct persistence fixture and a caption-only correction found during rendered review. Checks use the pinned `4.8.beta2.official.cafc17a19` engine. Each passing receipt below has complete verified evidence, confirmed cleanup and zero engine errors/warnings.

| Check | Native platform / receipt | Result |
| --- | --- | --- |
| Source declarations, hostile types and extras, real metadata-size fallback, v1/v2 persistence and unchanged physical bytes | macOS arm64, `831bce24615449cc80876442a3120689` | 289 checks, zero failures |
| Existing compiler and loader boundary | macOS arm64, `5c45bbc0259d4612afffdf50f197a240` | 196 checks, zero failures |
| Existing Creator UI | macOS arm64, `b630a061c13f42a0af9511f107770909` | 201 checks, zero failures |
| Existing persistence, save shortcut and publication | macOS arm64, `dbcd961f2e914df09fa9ff76354692d1` | 95 checks, zero failures |
| Existing language journey and eight catalogs | macOS arm64, `399dce1cdbd14458bc539c3455bdf63a` | Zero failures; all 18 new messages also checked in all eight catalogs |
| Existing frame/hinge and visual boundaries | macOS arm64, `e5bb28cf835a47eea61e4bc536e346f8`, `9f647eb240e1406881e10a4268154170` | 221 and 48 checks, zero failures |
| Current private seven-ZIP corpus | macOS arm64, `d86264218894435e86cf75e1536bc0f1` | 26 outcomes: 18 converted, eight refused; all 261 frames classified; 203 retained frames and 50 unbound pivot proposals |
| ZIP → report → draft → reopen → publish → revision reopen; inconsistent revision rejection restores import controls | macOS arm64, `666ea0f4a36a449690e6dbc880074cbb` | 41 checks, zero failures |
| Source declarations and the same complete ZIP/library journey | Windows x86_64, `34896d6ec0d542dbaaad56f1e7e77100`, `09d7f83df36e47c79b32cf521726057f` | 289 and 41 checks, zero failures |
| Final report caption and source boundaries | Windows x86_64, `f07a3cd1ac674511b1c60941e05d9aef` | 289 checks, zero failures |
| Final real-Extra report and preview, Spanish, actual 1920×1080 | Windows, `T-7246c7b32351487a80b4d6b9e048e5d4` / `A-5ac7b097808f44a7a0de311f9bd966a8` | Passed; 18 scoped declarations; NVIDIA RTX 3090, OpenGL 3.3 Compatibility, driver 617.42 |

The first persistence run used Control+S on macOS although the application expects Command+S; its two failures are retained under `434168637a2f407eb099abd3c781baf0`. The fixture now emits the native platform modifier and passed unchanged production persistence code. Superseded unplaced requests were stopped before dispatch. Completed writable test copies were released only after terminal-state and evidence checks; frozen input archives, inventories and reports remain. Identical completed Mac input archives share verified identical data without changing paths or bytes.

The separate `extra300-nose-20261116` session initially blocked Windows admission. The user chose to wait; its processes were preserved, and the checks ran when the host became available. Initial capture `T-6c481968494b4d91ac032d4dc21f8c07` passed, but visual review found a repeated unresolved-unit caption. The corrected panel passed the targeted observer check and final capture above. The inspected image remains outside Git at `C:/Users/bulto/AppData/Local/Temp/openrc-clearview-evidence-20261116/clearview-observations-1080.png`, SHA-256 `ff90dce1a14deda6ef9109961459ba7c356cb5895a7b86c9a3ab1795292f84c4`. This is functional/rendered evidence, not a performance or independent fidelity qualification.

Shared disk pressure filled D: and later C:. Two caption source preparations were stopped without dispatch; production files and earlier frozen candidates stayed intact. The final caption check used a separate C: working copy. Completed writable Windows copies were released after verifying terminal outcomes, confirmed cleanup, complete reports and retained frozen inputs. The earlier failed/incomplete development receipts remain available and are not counted as passes.

Required CI, independent fidelity, exported-platform/resource checks, physical adoption, flight qualification, Home integration and original-ZIP persistence remain open. AC-CV-05 is partial.

### Independent estimated configuration and flight admission (AC-CV-05/06, 2026-11-16)

The Creator now requires an explicit independent estimated configuration for a recognized ClearView source. Recognition caches the presence of `asset.extras.openrc_clearview` during existing GLB admission; absent, malformed or omitted optional parameter data cannot bypass the choice. A tag is a declaration, not origin authentication, and an untagged source cannot be identified by this mechanism. No model bytes are reparsed on the UI thread to make this decision.

The declaration binds the exact visual SHA-256, report availability/digest and versioned airframe/power package IDs. Confirmation checks both the proposal and document revision. Source replacement clears the choice while preserving entered values, inventory and provenance for review. Layout, power and gear cards remain unselected proposals until confirmation, including in Review; package read-outs remain unavailable. This does not adopt a detected ClearView installation or relabel retained measurements.

Definitions and snapshots with this declaration use v3. Historical v1/v2 documents remain readable without implicit migration, but a recognized source needs a choice before compilation; standalone v2 compilation also refuses an implicit package. Fresh references can be reviewed without changing historical document identity. Reopen compares definitions when either saved or restored member is v2/v3, preventing a downgraded v1 snapshot from silently discarding a saved declaration. Compilation strips review/choice metadata before physical emission: the explicit configuration changes definition identity and preserves the equivalent v1 aircraft bytes.

AC-12/G05 remains unqualified. Recognized ClearView sources are therefore refused at both trial creation and verification, including historical trials and sources without a usable report. Publishing is unavailable in both the button and handler; preview, editing and draft saving remain available. Ordinary v1 sources retain their existing behavior. The low-level Store still preserves opaque members independently; this slice adds no definition-to-physical-record authentication or Home resolver.

Independent review found the either-side canonical comparison and inconsistent Review/package-selection state; both were corrected and exercised. A newly available report is also displayed before confirmation without migrating the saved context. Development failures were retained: an unadmitted Python cache stopped an input archive before execution; direct parsing exposed the reserved `namespace` parameter and a fixture name shadowing `convert`; a reduced harness initially omitted required scenery preloads. The final harness restores actual dependencies. Successful editor import alone was not counted as a script parse pass.

The focused harness uses production files based on `6dfe1b9179af408f6b765b91ca164e626570db9f`, not a whole-app/export checkout. Final source digest: `c6da0762cae872869d9ee66744c88d58d2ecb9cda8a4fae37c3df2c1c91330fc`; all 21 integrated code/catalog files match the final frozen inputs. The common boundary checks used digest `5a88a697988beb74ccd2ccdce15851d7449711c81a824f5b16f2870ee29ac8b8`; subsequent differences are package-card/Review status and their assertions, covered on the final candidate. All passing checked receipts below use pinned Godot `4.8.beta2.official.cafc17a19`, complete verified evidence, confirmed cleanup and zero engine errors/warnings.

| Check | Native receipt | Result |
| --- | --- | --- |
| Namespace presence, absent reports, stale confirmation, v1/v2/v3 persistence, hostile declaration types, source/candidate joins, historical trial refusal and unchanged physical bytes | macOS `b69296207717493f9557d6dc1b6ea93d`; Windows `39bc3a6e30da4da1a522293bff82313c` | 88 checks on each OS, zero failures |
| ZIP → explicit choice → v3 draft → reopen; historical revisions and downgraded snapshots; consistent package proposals | macOS `ce4215e636c94a59af793e3d29d4f899`; Windows `a49233118f214461bf7bfbe056a13096` | 68 checks on each OS, zero failures |
| Existing source observations and physical-byte equivalence | macOS `403f3ce7aef44d3481a7a5fa9a8c1d67` | 290 checks, zero failures |
| Existing compiler and loader | macOS `d8dd23e8ad0a44bf98e232fd834b96f4` | 196 checks, zero failures |
| Existing GLB admission | macOS `e91510714c1840018e3ccea125a58176` | 356 checks, zero failures |
| Existing ordinary-source trial, snapshot and start boundaries | macOS `be54a719766d42ba8ecb913efb2d746d` | Zero failures |
| Existing Creator UI journey | macOS `1e7efb8cda4b4df19cc246bfd15ebabc` | 201 checks, zero failures |
| Existing persistence/publication journey | macOS `4f7d4d74bbed4142a0f0d99ee4a7bcbd` | 95 checks, zero failures |
| Existing language journey and 96 new translations in eight catalogs | macOS `a4a449c0539a43c7b21e74ff8713524e` | Zero failures |
| Real Extra ZIP, Spanish Import and Power views, actual 1920×1080 | Windows `T-97406822dd894a58a61809a6e92a2503` / `A-b63e248739d541eeb7660ef3756425a5` | Passed; 18 scoped declarations; RTX 3090, OpenGL 3.3 Compatibility, NVIDIA 617.42 |

The two inspected captures remain outside Git under `C:/Users/bulto/AppData/Local/Temp/openrc-clearview-evidence-20261116/`: `clearview-installation-import-1080.png` SHA-256 `0372262d1149de18d716d6bf39e76cff599143ff6be5d1bb94b070f35ba69cc4`, and `clearview-installation-power-1080.png` SHA-256 `5279ce176bed018194468ce4b2c053f095138dd3f476f26dce06851cab617196`. This establishes functional 1080p layout evidence, not performance, independent visual fidelity or physical qualification.

Superseded unplaced supervisors were stopped before dispatch; failed inputs and reports remain available. Shared storage pressure required releasing only completed owned writable copies after checking terminal state, complete evidence and cleanup. Exact historical/current Mac input archives were retained with verified SHA-256 under `D:/OpenRCsimulator-clearview-scratch/retained-mac-inputs-20261116/`; native inventories and logs remain at their original locations. Windows admission resumed after the host left DRAINING, without closing another task's session. The simulation kernel, physical packages and generated aircraft data were not changed. Parameter adoption, numerical/domain flight qualification, Home, portable closure, required CI and exported/resource gates remain open; no AC-CV step is closed by this slice.

### Concise player guide and source recheck (AC-CV / WEB-11, 2026-11-19)

Reviewed current source `b2f81d1771031964446a1cbddd83770d6d1c87ff` from Workshop and the ZIP picker through archive/parameter/visual conversion, source declarations, motion proposals, draft persistence and trial/publication/Home refusals. The [quick guide](../../../site/clearview-import-en.md) documents the existing preview/draft workflow in all eleven website languages. Its Markdown and static website editions share the same localized copy. No application or physics source changed.

[ClearView's community catalog](https://rcflightsim.com/models.html) and [Gary Gunnerson's ClearView catalog](https://gunnerson.homestead.com/files/clearview_models.htm) were reachable; six actual ZIP downloads were inspected. The latter is an additional source, not a compatibility promise. The official catalog mixes airplanes, helicopters and landscapes. Its paint-scheme section can contain complete models; complete packaging does not guarantee conversion. The [Absolute RC page](https://rcflightsim.com/models1.html) describes that simulator's URL/`.lst` workflow, which OpenRC does not implement. The DHC-2 Beaver link still returned HTTP 403. The website's v0.2.7 download predates ZIP import: the [tagged Creator](https://github.com/bultodepapas/OpenRCsimulator/blob/v0.2.7/app/ui/aircraft_creator.gd) offers only STL/GLB, unlike the reviewed current source.

The [dated check record](clearview-guide-checks-2026-11-19.json) retains engine/source identity, archive URLs and SHA-256s, per-model outcomes and check-log hashes. On official Linux x86_64 Godot `4.8.beta2.official.cafc17a19`, unchanged production readers/converter and downstream GLB admission gave:

| Actual download | Result |
| --- | --- |
| MC Extra 330 Red | Admitted visual, 3,776 triangles; the short guide's tested example. Read the import notes: marker/zero-area omissions and unbound hinge proposals remain. |
| Ken Northup Plane Pack 1 | 20 model roots; 14 admitted visuals, six refusals. Select one model; the whole pack is not declared compatible. |
| Calmato 40 Sports; Gunnerson Firebird Stratos | Refused unsupported JPEG encoding/metadata. |
| MC 300S Air Guard | Refused intersecting edges in `Fuse` polygon 129 despite being a complete repaint/model package. |
| Gunnerson FMS-PT-17 Stearman | Refused a `$`-prefixed parameter field. This is the parser's current subset limit, not a damaged ZIP; “FMS” names the model manufacturer here. |

Six focused checked suites passed **1,097 checks**, with complete runs and zero engine errors/warnings: readers 87, visual 48, JPEG 363, motion 221, source observations 290 and publication binding 88. The isolated project used unchanged production dependencies; the full application was not imported. Initial motion/observation harness attempts lacked catalogs/data and were corrected. A separate source-installation/trial run emitted errors from missing scenery assets and is **not** counted as passing, regardless of its zero-failed-assertion line.

Website verification: all eleven generated pages and Markdown guides are current; seven static locale/publication tests and eight existing download tests pass. The guide is complete without JavaScript, preserves exact translated app button labels where those app languages exist, and uses English UI labels for Korean/Arabic. Browser layout review was unavailable: standalone Chromium could not create a required socket and the cloud browser could not reach the local preview. This review establishes neither rendered fidelity nor flight, exported-platform, performance or physical qualification. It does not close the existing ClearView flight gates.

### Importer v1 coverage and parity (AC-CV, 2026-11-19)

Reran the six-archive corpus of the [check record](clearview-guide-checks-2026-11-19.json) through unchanged archive/package capture, conversion and GLB admission in the full application, using Godot 4.8 beta2 on Windows. Before this change, 15 of 25 model roots were admitted. Every refusal had a concrete cause:

| Cause | Models | Change |
| --- | --- | --- |
| JPEG APP1 (EXIF), APP2 (ICC) or APP13 (Photoshop) segments; Godot decodes the images | Calmato 40, Beech99, Bellanca C-27, Firebird Stratos | APPn segments other than JFIF/Adobe are skipped as opaque metadata, at most 1 MiB in total, with a note. Progressive and other codings stay refused |
| `smoke.gif` on `Prop`/`PropDisk` objects | 701f, 701F2, Brown-B1 Racer | New bounded GIF87a/89a first-frame decoder. The real file's RGBA is bit-identical to Pillow's (SHA-256 `f24565cd9b557d5cbe40b5806d83fbbde1acbb2f5eee07161f788da92321af4c`) |
| Quad with two coincident consecutive corners | Ascent Park Glider, `fuse` polygon 91 | Exact duplicates collapse before the intersection test; shape and UVs are unchanged |
| Genuine bow-tie, about 1.5 × 18 mm | MC 300S Air Guard, `Fuse` polygon 129 | Omitted and reported; more than 16 refuse the model. Exactly cancelling bow-ties remain refused |
| `$PlaneMidWindDhD01 paramsAgriDuck` first line | FMS-PT-17 Stearman | `$` tag lines are ignored and counted; they cannot supply identity keys |

After the JPEG fix, the Bellanca C-27 exposed a further case. Ear clipping of its 64-corner `Ruder` outline produced a triangle from three exactly collinear corners. Its float64 source cross product is exactly zero, so it covers no area, and it is now skipped. Previously admitted models cannot contain such a triangle or the changed polygons, so their GLB bytes are unchanged. The new receipt field appears only when nonzero.

**Result: 25 of 25 model roots admitted.** Corpus ZIPs stay outside Git under the owner's scratch path, verified by the recorded SHA-256s.

Parity, per the [DECISIONS entry](../../DECISIONS.md#ac-cv-v1-parity): after the configuration is confirmed, ClearView models test-fly and save through the same gates as STL/GLB.

- The trial identity pins the confirmed configuration, and `verify` refuses a ClearView trial without it.
- The store refuses a definition or snapshot whose configuration names another model.
- The resolver, `published_trial.prepare` and v4 capture keep their refusals. Published flight remains closed for all Creator aircraft.

An independent read-only review found two problems in the first design, and both were corrected before integration:

- Production publishes through the legacy flat path. No production code selects the v4 servo law, so changes to v4 capture alone would have been dead code.
- Removing the resolver's ClearView refusal would have let unconfirmed legacy records resolve.

Verification: each suite below completed with zero failures and no `SCRIPT ERROR`/`ERROR:` lines.

| Suite | Checks |
| --- | --- |
| GIF (new) | 144 |
| JPEG | 376 |
| Readers | 91 |
| ClearView visual | 56 |
| Observations | 290 |
| Motion | 221 |
| Source installation | 89 |
| Servo document | 72 |
| Compile binding | 88 |
| ClearView UI | 70 |
| Store | 509 |
| Publication UI | 28 |
| Persistence UI | 95 |
| Source reference | 230 |
| Published trial | 62 |
| Selection state | 43 |
| Creator UI | 201 |
| Compiler | 196 |
| Flight | 56 |
| GLB | 356 |
| Creator visual | 231 |
| STL | 262 |
| PNG | 207 |

Language, trial, flow, import and bytes also passed.

Website: `build_locales.py --check`, seven locale tests and eight download tests passed. Rendered browser layout was not reviewed. This establishes conversion coverage on this corpus and parity with the existing experimental Creator gates. It does not establish physical realism, packaged-target behaviour, or saved-aircraft flight.
### Owner download corpus (AC-CV, 2026-11-19)

The owner's local download folder held 123 ZIPs. Of these, 59 contain a ClearView `params.txt`. After SHA-256 deduplication, 49 are new archives with 172 model roots. They are kept outside Git. Before this round the importer admitted 105 roots. Every in-scope airplane refusal had a concrete cause:

| Cause | Real models | Change |
| --- | --- | --- |
| Unreadable `.XYZObject` marker: extra vertices, or axis lengths within the 10% separation rule (0.063/0.0665/0.0758) | 18 airplanes, including Avro Lancaster, Eflite P-47, Cap 232, Edge 540, SU-26/31, IAF Kfir and RN Buccaneer | Marker hidden and recorded as `unreadable_frames`. Its hinge is unresolved with reason `unreadable_render_frame`, and the player binds it manually. A marker with children, or more than 64 vertices, still refuses |
| AC3D `subdiv` | GP Cap 232, Twist 3D 40, Hawker Hunter (plus 9 helicopters) | Control shape shown unsmoothed with a warning; receipt `unsubdivided_parts` |
| Adobe APP14 flags `0x8000`/`0xC000` | Mig-15, Parkzone Vapor, Eflite P-47 | Encoder-hint flags ignored; only transform 0/1 is accepted |
| Collinear triangle whose float64 cross product is about 1e-20 (prints as `-0.0`) | DR 107, two MC Cap 580 packages | Array equality distinguished `-0.0`, so zero tests are now numeric. Collapsing ears with doubled area at or below extent² × 1e-9 are dropped. Visible flips still refuse |
| Point/line or two-point `COORD_*` helper held to render precision | E-starter, Force One | Nodes with no face of three distinct corners render nothing and are skipped |
| 14.5 mm aerial 5 m from its node origin; float32 rounding 1.6e-5 of its size | RN Buccaneer | Precision bound changed from 1e-5 to 1e-4 of the part's size. The 1e8-offset and collapsed-edge refusal tests still pass |
| Exactly cancelling bow-tie | Red Arrows, both variants | Omitted and counted with other self-intersecting surfaces |
| BMP with 2 trailing alignment bytes, declared in the file size | Sopwith Camel | Up to 3 trailing bytes accepted |
| `.bmp` referenced, same-named `.jpg` shipped | SU-31 Matador | The single same-named image in the folder is used, with a warning. Two candidates keep the missing-file refusal |

Converting only the changed cases keeps earlier admitted GLBs byte-identical: every new receipt field appears only when nonzero. An empty primitive left after a fully dropped sliver is no longer emitted, because its infinite bounds were refused by GLB admission.

**Result: 148 of 172 roots admitted; the first corpus stays 25/25.** Remaining refusals are out of v1 scope:

- Helicopter packs in another parameter dialect (16).
- The Blade mSR helicopter (precision).
- VTOL and blimp parameter formats: Harrier, VJ-101, XFV-1, Hindenburg.
- Two landscape packs.

One in-scope airplane remains refused: Wee Jock has 142 meshes, against the Creator-wide 128-mesh limit.

All 28 `test_creator_*` suites passed with zero engine errors. Visual: 71 checks. JPEG: 379. Motion: 225.
### Helicopters, VTOL dialects and the mesh-limit exception (AC-CV, 2026-11-19)

At the owner's request, the 24 remaining refusals in the download corpus were reworked. Helicopter pack 1 now expands to 20 roots, so the corpus has 191 roots.

| Cause | Real models | Change |
| --- | --- | --- |
| Flat `verNumber` 0 to 3 with no `modelName` (helicopter packs use v3 with `modelType 0`) | CVHeliPak 1 and 2, Harrier, VJ-101, XFV-1, Hindenburg | Flat dialects v0 to v5 are accepted, and sectioned files stay v6 only. Before v5, a missing `modelName` defaults to `data/body.ac` with a note; every helicopter root ships that file |
| Helicopter flight model | All `modelType 0` | A visual-only import. The GLB carries `openrc_clearview_rotorcraft` and gets no fixed-wing configuration. Choosing a configuration, compiling, `check_pair`, trials and publishing all refuse with a dedicated message. The tag can only remove capability. Helicopters converted before this change carry no tag |
| 142 meshes against the 128-mesh limit | Wee Jock | The first pass is unchanged. Only when the emitted meshes exceed the limit is the model converted again, with static, undotted, rigid leaf parts merged per parent and their transforms baked in float64. The node limit is also checked. Models that fitted before keep their exact bytes |
| 35 or 36 distinct colour and texture combinations | T-Rex SA White and Orange | The Creator-wide `GLB_MATERIALS` limit is raised from 32 to 64. Past the limit, identical materials are reused |
| Absolute texture path on the author's PC | Cobra (`C:/Program Files/SVKSystems/…/mapping.jpg`, absent) | The texture is looked up by file name in the model folder. If it is absent, those parts get the plain material colour, with a warning. A relative missing texture still refuses |
| JPEG luma sampling 4:2:2 (`0x21`) | EF-Sabre | The MCU walk is generalized to h×v ∈ {1,2}² |
| Corners 1e-9 m apart that project to one float32 point | Honey Bee FP Flames | Such corners collapse like exact duplicates; fewer than 3 corners counts as zero area |
| 1.6 mm part 6 m from its node origin (0.24 µm rounding) | Blade mSR V2 | An absolute floor of 1 µm is added to the 1e-4 relative render-precision bound |

An independent read-only review of the integrated diff found three defects, all fixed before integration:

- Absent external textures were counted toward the image limit.
- The merge was triggered by "renderable" nodes rather than meshes actually emitted, which could have changed models that previously fit. A regression test now pins this with collinear parts.
- The node limit was ignored.

The same review added a defensive rotorcraft refusal in `check_pair` and loosened rotation rigidity to 1e-5, because AC3D prints six decimals.

**Result: 189 of 191 roots admitted. The only refusals are the two landscape packs, which contain no aircraft. The reference corpus stays 25/25.** All 28 `test_creator_*` suites passed with zero engine errors. The ClearView visual suite has 90 checks, JPEG 383 and readers 96. The website guide now states that helicopters are preview/draft only in all eleven languages: `build_locales.py --check`, seven locale tests and eight download tests passed.

### Closeout: every corpus aircraft flies (AC-CV, 2026-11-20)

The uncommitted 2026-11-17 closeout worktree (automatic setup, size classes, park jets, X8 and X-Cell donors; see its [packet log](import-closeout-2026-11-17/closeout-plan.md#6-implementation-status)) was committed as `9d11d13a6` and merged with main. Conversion stays main's (25/25 and 189/191); the merge kept main's parity decision and removed the old servo-interval refusal. Changes on top:

| Gap | Change |
| --- | --- |
| Helicopters were visual-only on main | **Fly as a helicopter** on the X-Cell .60 physics; the Creator panel now shows for rotorcraft, and a reopened helicopter draft keeps the offer (stale flag found by the Good Enemy review, regression test checked by mutation) |
| Seven aircraft could not compile an estimate | A body longer than the reach limit is proposed smaller (IAF Kfir now flies its own estimate). The rest (Kellett autogyro, Hindenburg, XFV-1, Tricopter, two Meteor F8: balance 0.006 against 0.08) are offered the stock electric trainer physics with the reason |
| Liveries looked washed out at 1080p | Textured AC3D emission (0.57–0.72 on the Extra 330 and Roboheli skins) was a flat grey emissive; it is now the texture at 35 % |

**Flight probe** (scratch, headless Windows, Godot 4.8 beta2; not in Git): every root of both corpora through package → conversion → automatic setup or donor → compile → frozen trial → airborne start check → 10 s hands-off, full-aileron and full-elevator pulses in the session loop; helicopters start the real `helicopter_main` donor route and fly 6 s. **214 of 214 aircraft roots fly**: 149 on the estimated configuration, 10 flying wings on the X8, 49 helicopters on the X-Cell .60, 6 on the trainer. The only refusals are the two landscape packs. Zero script errors, no NaN, no crash; every flight responded to both pulses (roll > 30 °/s, pitch > 20 °/s). This proves startup and controllability, not handling realism.

**Real renderer, 1920×1080:** Extra 330 Red, Avro Lancaster, Sopwith Camel, Spitfire, Zagi (X8), Harrier, Meteor F8 (trainer), IAF Kfir, Roboheli Red and T-Rex G4 (X-Cell), Hindenburg (trainer), chase and close-up views, 35–120 fps. Liveries show their source colours after the emission change.

**Checks:** all 31 `test_creator_*` suites pass (new: trainer fallback and its UI offer, long-body reach, reopened helicopter draft, textured emission). Companion pins renewed for the `app_root.gd`/`main.gd` edits (`test_companions_profiles` 95/0, `test_companions_behavior_manifest` 39/0); `test_workshop_integration`, `test_workshop_trial`, `test_main_startup_cleanup`, `test_heli_session`, `test_heli_visual`, `test_heli_crash_presentation`, `test_airship_workshop_flow` pass. Website: `build_locales.py --check` and 7 locale tests pass.

**Limits:** donors fly the donor's mass, size and power; donor elevons and rotors do not move; a T-Rex 450 is shown 2.2–2.4× larger on the X-Cell; drafts converted before this change keep their washed-out GLB until re-imported. Saved-aircraft flight from Home (AC-18) remains a Creator gate.
