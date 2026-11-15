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
