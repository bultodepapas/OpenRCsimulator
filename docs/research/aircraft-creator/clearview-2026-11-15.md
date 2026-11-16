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
