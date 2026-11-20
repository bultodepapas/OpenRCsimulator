# RC simulator aircraft sources and importer candidates

Date: 2026-11-17. Status: source research and implementation recommendation; no new runtime importer, conversion, flight qualification or redistribution permission is delivered by this record.

Later same-day evidence: the [modern RC follow-up](modern-rc-simulators-2026-11-17.md) now documents complete HELI-X V11 plane assets, an aerofly RC10 static TMB/TTX reconstruction, RealFlight EA/AV inspections and two REFLEX MOD/PAR samples. It owns the current modern-ecosystem assessment; the original inventory here remains a record of the earlier inspection scope.

This extends the [Aircraft Creator evidence](README.md) and the [Flight Simulator research](flight-simulator-2026-11-16/README.md). It identifies RC-specific inputs for the same automatic in-app conversion goal. The [Creator plan](../../plans/aircraft-creator.md), [ClearView plan](../../plans/clearview-aircraft-import.md) and proposed [Flight Simulator plan](../../plans/flight-simulator-aircraft-import.md) retain their implementation and qualification ownership. This record neither creates new accepted step IDs nor expands their completed scope.

Runtime inspected: OpenRC main `a986b99ca453db90f0a05399483c11cc55d17afd`. Research branch base: `09ff600a362e9d2bc847882fcfa4be9665220e68`. The [source inventory](rc-simulator-source-inventory-2026-11-17.json) distinguishes downloaded packages, repository files, catalog-only leads and unresolved geometry. Hashes establish which bytes were inspected, not their authenticity, license or compatibility.

## Recommendation

For older/open-format sources, start with **CRRCSim**, then build a shared **DirectX X geometry path for FMS and RC Desk Pilot**. Keep PicaSim technically close to CRRCSim but make asset permission a separate acquisition task. Consider SSS as an additional 3DS/DAT source after the first adapters work. For the user's subsequent modern-content priority, use the [follow-up recommendation](modern-rc-simulators-2026-11-17.md#decision): HELI-X V11 and aerofly RC10 have substantially stronger new evidence, while general compatibility remains unqualified.

| Source | Evidence actually obtained | Main geometry / definition | Engineering priority | Content position |
| --- | --- | --- | --- | --- |
| CRRCSim | Actual aircraft repository files; three community ZIPs inspected | AC3D or 3DS + XML; SGI RGB textures in inspected AC examples | First: reuse part of ClearView's AC3Db work | Project GPL and contributor notices; separately verify aircraft rights |
| FMS, Flying Model Simulator | Five aircraft ZIPs downloaded and inspected | DirectX X + two different PAR grammars + BMP | First group with RC Desk Pilot | Free downloads do not grant blanket cross-project rights |
| RC Desk Pilot | Source tree, Xtra PAR, mesh and loader read | DirectX X + XML in PAR; PNG/JPG/DDS | First group with FMS | Root GPLv3 coexists with a restrictive legacy EULA; clarify asset scope |
| PicaSim | Official aircraft definitions, source tree and loader read | AC3D, some 3DS + XML + ordinary images | Technically promising; obtain authorized examples | Current PolyForm Noncommercial covers code/text/XML; models/images require separate permission |
| SSS | Author's complete distribution downloaded as data | 3DS or generated components + DAT | Complementary legacy source | Package GPLv2; inspect contributed-model provenance |
| Aerofly RC10 | Original package audit; later Panda static TMB/TTX reconstruction documented in modern follow-up | TMB/TTX runtime; MQO or BLEND author sources; TMD/TMC | Modern follow-up owns updated priority | No cross-project license found in inspected ZIPs |
| Phoenix RC | Author catalog and separate Pitts OBJ link confirmed | PKG / compiled geometry; separate OBJ source offered for one aircraft | Defer generic decoder; pursue authorized author sources | Pitts author states noncommercial distribution; conversion scope unresolved |
| RealFlight | Original official-doc/catalog audit; later actual EA/AV inspection in modern follow-up | RFX/G3X container; KEX mesh | Metadata/source route possible; generic KEX reader unproven | Per-aircraft permission; EA, AV and CS differ |
| HELI-X | Original EasyStar XML audit; later two complete V11 geometry packages inspected | OBJ/MTL/XML confirmed for two V11 demo planes | Modern follow-up owns updated priority | Simulator EULA is not a general asset-reuse grant |
| REFLEX XTR² | Author-maintained fixed-wing catalog and format description | MOD + PAR, commonly delivered through installers | Defer until MOD/source geometry is demonstrated | Author and component-specific permissions |

Priority is an engineering judgment from inspected formats and OpenRC's existing seams. It is not an estimated schedule, measured importer success rate or legal opinion.

## CRRCSim: closest to the existing geometry work

The [original project](https://sourceforge.net/projects/crrcsim/) and the inspected [community repository snapshot](https://github.com/gcmcnutt/CRRCsim/tree/14b5311add9492a96fce1898c2b6345d1c12bd7e) provide readable model data. The snapshot is a continuation/mirror, not evidence that every file is maintained by the original project.

| Aircraft | Definition | Geometry | Relevant evidence |
| --- | --- | --- | --- |
| Angel S30E | `models/Angel_S30E.xml` | `objects/Angel_S30E.ac` | AC3Db header; named control hinges; electric power dependencies; SGI `angel_s30e.rgb` |
| Wasabi | `models/wasabi.xml` | `wasabi_wr.ac`, `wasabi_yr.ac` | Two graphical variants and control mixing |
| Sport | `models/sport.xml` | `objects/sport.ac` | Surface and gear definitions; `sport_tex.rgb` |
| Pilatus B4 | `models/PilatusB4.xml` | `objects/PilatusB4.ac` | Glider example; `PilB4Texture.rgb`; additional size variant exists |

Primary implementation references: [XML format](https://github.com/gcmcnutt/CRRCsim/blob/14b5311add9492a96fce1898c2b6345d1c12bd7e/documentation/file_format/airplane02.html), [Angel definition](https://github.com/gcmcnutt/CRRCsim/blob/14b5311add9492a96fce1898c2b6345d1c12bd7e/models/Angel_S30E.xml), [visual loader](https://github.com/gcmcnutt/CRRCsim/blob/14b5311add9492a96fce1898c2b6345d1c12bd7e/src/mod_video/airplane_vis.cpp), [model loader](https://github.com/gcmcnutt/CRRCsim/blob/14b5311add9492a96fce1898c2b6345d1c12bd7e/src/mod_fdm/xmlmodelfile.cpp).

The adapter must preserve configuration and graphical variants, named objects, two-point hinge axes, gains and travel, model-to-body transforms and external motor/battery dependencies. Units belong to individual XML sections: Angel mixes SI aerodynamic/mass sections with imperial wheel definitions. Its explanatory text and parameters also contain source-level inconsistencies and tuning assumptions. They are imported observations, not measured physical truth.

The current ClearView reader explicitly accepts AC3Db only and refuses unknown records. A matching header is useful evidence, not proof that all CRRC scenes are already accepted. Add coverage for observed nodes/materials and SGI RGB decoding, with bounded dimensions and expansion, before reporting compatibility.

### Additional downloadable examples

The [DESIGNER2010 author page](https://sites.google.com/site/crrcsiminfo/new-models-created-for-crrcsim) links three inspected [SourceForge packages](https://sourceforge.net/projects/threedairplanemodels/files/):

| ZIP | Files actually present | Qualification consequence |
| --- | --- | --- |
| `OuraganEDF_V2.zip` | `OuraganEDF_V2.3ds`, `OuraganEDF_V2.xml` | XML also names an absent alternate `zagi-xs.ac`; that variant is incomplete |
| `YE2_V32.zip` | `YE2_V32_OneTen.3ds`, matching XML | Additional 3DS case; source flight configuration inherits legacy definitions |
| `PC9TenScaleV2.zip` | `PC9TenScaleV2/PC9TenScale_v10rG.3ds`, `pc910scale.xml` | Nested geometry path and retractable gear case |

None includes a README or LICENSE. The author page states GPL while the linked project description refers to personal simulator use with acknowledgement. Record that conflict instead of silently selecting the more permissive statement.

Fedora's [add-on package](https://packages.fedoraproject.org/pkgs/crrcsim-addon-models/crrcsim-addon-models/index.html) is the strongest additional licensing lead found. Its [official manifest](https://packages.fedoraproject.org/pkgs/crrcsim-addon-models/crrcsim-addon-models/fedora-rawhide.html) lists ten aircraft definitions and original licensing correspondence. An actual Fedora RPM obtained from a third-party mirror was inspected as data; its publisher signature was not independently verified.

The RPM contains Attribution 3.0 Unported legal text and June 2013 correspondence proposing that license, with Arthur Frenslich's agreement. Jan Reucker agrees but says he does not own the original models. Nine XML changelogs explicitly credit Arthur with original geometry, texture and flight definition; later contributors remain identified. Arthur's informal business remark is recorded for scope review, not silently converted into a noncommercial license. [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) permits commercial use subject to its conditions. This is meaningful positive evidence, while still requiring component-level attribution and grant review for a redistributed selection.

Ellipse 2V is a concrete starting candidate: `EllipseV2.xml`, `Ellipse2V.ac` and `ellipse2v.rgb` are present with explicit author credits. The mesh names an old absolute Windows texture path; resolve only through an explicit captured-package compatibility rule, never by reading that host path. The add-on also references base-installation sounds. Other examples demonstrate real dependency problems: Fireworks names a missing first mesh variant, and Sting names `sting.png` while only `sting.rgb` is packaged. Do not hide these differences behind automatic filename guessing. This glider corpus is useful for visuals and rights review, but is outside the current electric Creator flight domain.

## FMS: five downloads and a candidate shared X reader

Here FMS means **Flying Model Simulator**, not the FMS aircraft manufacturer.

[Hitec Multiplex Japan's download page](https://hitecrcd.co.jp/support/fms/) publishes MiniMag, FunJet, EasyStar, EasyGlider and EasyGlider Electric packages. [Gary Gunnerson's model catalog](https://gunnerson.homestead.com/files/fms_models.htm) remains reachable through direct HTTP retrieval; his [original aircraft announcement](https://www.rcuniverse.com/forum/rc-flight-simulator-software-138/3187782-2-new-fms-alpha-8-models-4f-51-3d-begin-air-rtf.html) identifies 4F-51 and BeginAir.

| Downloaded aircraft | ZIP bytes | Actual relevant contents |
| --- | ---: | --- |
| [MiniMag](https://hitecrcd.co.jp/material/software/fms/m_minimag.zip) | 807256 | X, positional PAR, three BMPs, preview, WAV, README |
| [FunJet](https://hitecrcd.co.jp/material/software/fms/m_funjet.zip) | 649663 | X, positional PAR, four BMPs, preview, WAV, README |
| [EasyStar](https://hitecrcd.co.jp/material/software/fms/m_easystar.zip) | 508491 | X, positional PAR, seven BMPs, preview, WAV, README |
| [4F-51](https://gunnerson.homestead.com/files/4F-51.zip) | 336765 | X, MQO source, VERSION 1.0 PAR, BMP, preview, WAV, README |
| [BeginAir](https://gunnerson.homestead.com/files/beginair.zip) | 493502 | X, MQO source, VERSION 1.0 PAR, BMP, preview, WAV, README |

All five X files inspected begin `xof 0302txt 0064`. Two contain editable Metasequoia source as well. A subsequent TextureFilename scan found all sixteen referenced BMP names as exact archive members. Header inspection found thirteen uncompressed 8-bit indexed BMPs and three uncompressed 24-bit BMPs, all using a 40-byte DIB header. The existing ClearView BMP reader accepts only 24-bit uncompressed BITMAPINFOHEADER: these FMS samples therefore require additional bounded palette decoding. These are dependency/header observations, not a full mesh/image decode or an OpenRC conversion.

There are at least two PAR dialects in this small sample: compact positional values with comments, and a versioned document with INFO, AIRPLANE and MAIN sections. Read numeric tokens independently from trailing comments; recognize the grammar before interpreting positions. Legacy encodings and names such as `MiniMagWeiß.bmp` need explicit path/encoding handling. Free-form descriptions can disagree with numeric model parameters; preserve both and show a meaningful conflict rather than silently prefer a plausible value.

[ClearView's own FMS conversion tutorial](https://www.rcflightsim.com/fms2cv/preparing_to_convert.html) corroborates the X/PAR/BMP/MQO workflow. It is a source-format reference, not a finished runtime importer dependency. Original author notices must follow conversions where their terms require it.

The Hitec page says it distributes with author permission and retains author rights. The inspected README files provide credits but no broad cross-simulator redistribution license. Thus these are practical local input candidates and permission leads, not automatically cleared additions to OpenRC's bundled catalog.

## RC Desk Pilot: structured controls with the same geometry family

The [author's website](https://rcdeskpilot.com/) links the [source repository](https://github.com/davyloots/rcdeskpilot/tree/6a3b987475830ba20d4cdde0efb1089ad3d8624a). Its aircraft tree contains Contender, Depron P-51, FT Baby Blender v2, SF260, Slope soarer, Cessna, Extra, glider and trainer folders, plus a Tiger helicopter folder. Do not count every directory or configuration as a different fixed-wing aircraft.

The inspected [Xtra PAR](https://github.com/davyloots/rcdeskpilot/blob/6a3b987475830ba20d4cdde0efb1089ad3d8624a/RCSim/Aircraft/extra/Xtra.par) is XML, despite the same extension as FMS. It references separate fixed body, elevator, rudder, left/right aileron, tailwheel, propeller and propeller-disk X meshes, with placement, rotation axis, input channel, reversals and travel. The inspected body uses the same DirectX text header as the five FMS samples. These examples justify a shared geometry reader with separate simulator-specific adapters.

Read the [parameter loader](https://github.com/davyloots/rcdeskpilot/blob/6a3b987475830ba20d4cdde0efb1089ad3d8624a/RCSim/DataClasses/AircraftParameters.cs), [airplane assembly](https://github.com/davyloots/rcdeskpilot/blob/6a3b987475830ba20d4cdde0efb1089ad3d8624a/RCSim/AirplaneModel.cs) and control-surface transforms before mapping axes. Some axis vectors are non-cardinal and not unit length. Scale must apply consistently to body geometry, component offsets and pivot placement.

Images include PNG/JPG and DDS; the inspected tree has large DDS textures. Reuse qualified image handling where possible, but add preflight dimensions, supported-compression checks and total decoded-byte accounting. A geometry library does not automatically decode every external image.

A [Flite Test article by the model creator](https://www.flitetest.com/articles/36-add-on-planes-for-rc-desk-pilot) publishes a collection described as 36 add-on planes and a Google Drive download. The article and link were verified; the archive was not downloaded. It discusses editable artwork and some SketchUp sources, but establishes no blanket cross-project commercial license.

**Licensing requires clarification:** the repository root [LICENSE](https://github.com/davyloots/rcdeskpilot/blob/6a3b987475830ba20d4cdde0efb1089ad3d8624a/LICENSE) is GPLv3, while [RCSim/license.txt](https://github.com/davyloots/rcdeskpilot/blob/6a3b987475830ba20d4cdde0efb1089ad3d8624a/RCSim/license.txt) retains restrictive legacy terms covering software/media. This coexistence may be historical, but does not justify declaring all aircraft cleared. Write independent adapters or separately assess any copied code. Never execute a supplied simulator flight-model DLL as part of import.

## PicaSim: accessible data, explicit permission boundary

Inspected official snapshot: [Rowlhouse/PicaSim](https://github.com/Rowlhouse/PicaSim/tree/5b2c5871b82aecae4ae6293b862f31600a6a949c). Actual `data/SystemData/Aeroplanes/` folders include Extra3D, Jackdaw, ASW15, F18Jet and GeeBee, with Aeroplane.xml and AC meshes; some other aircraft use 3DS. Ordinary image files and some editable artwork are also present.

The [author's customization guide](https://rowlhouse.co.uk/PicaSim/customisation.html) and [graphics loader](https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/source/PicaSim/AeroplaneGraphics.cpp) make an adapter plausible. Extra3D has a `model3DS` attribute naming an AC file, `modelScale="0.0254"`, mirrored/copied surfaces, named controls and two-point hinges. Do not select a codec from the attribute name alone. Transform geometry, surface offsets and hinges consistently. Some definitions have multiple top-level XML sections; shared aerofoils and presets can live outside the aircraft folder.

The current [README license notes](https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/README.md#notes-on-the-licence) put code and text/XML data under PolyForm Noncommercial 1.0.0. Images and models have separate origins and permission for PicaSim/direct derivatives; use in another project requires permission from the relevant author. This affects physics XML as well as artwork. Historical licensing was not audited.

The [community master list](https://www.tapatalk.com/groups/picasim/master-list-user-created-models-scenery-packaged-f-t436.html) is a source-acquisition lead for models such as Yak54, Su31, Extra330SC and A-10. Community availability and forum attachments do not establish permissions. Prioritize an explicitly authorized model instead of treating the official repository as an unrestricted asset library.

## SSS: additional standard geometry and readable definitions

The [original author](https://rowlhouse.co.uk/sss/index.html) publishes [downloads](https://rowlhouse.co.uk/sss/download.html) and [documentation](https://rowlhouse.co.uk/sss/documentation.html). The inspected `sss-2.19.3-skybox.zip` is 36029880 bytes and includes source code, GPLv2 text, 33 3DS files and 64 `glider_*.dat` files. These are file counts, not counts of distinct airplanes; definitions include variants, adapters and non-aircraft objects.

ASK13, Mustang, Phase6 and Weasel have concrete mesh/definition examples. Some definitions generate graphics from components instead of naming an external mesh. Relevant original readers are `src/glider_graphics_3ds.cpp`, `src/3ds.cpp`, `src/config_file.cpp` and `src/glider_aero_component.cpp`.

A DAT adapter plus a qualified 3DS geometry reader could recover surfaces, mass/inertia observations and visual assets. The package credits many model authors, including CRRCSim contributions; check their individual provenance before distributing selected content. Reusing GPL reader implementation is a separate licensing decision from independently implementing the documented format.

## Other catalogs: useful aircraft, incomplete generic import paths

### Aerofly RC10

The [official catalog](https://www.ikarus.net/en/aeroflyrc10-usermodels/) includes MPX Panda/Fox/Twinstar II, Robbe Charter, Hawker Hunter and Paperwing. The inspected [Panda ZIP](https://www.ikarus.net/downloads/rc10-user-aircraft/rc10_as-panda.zip) contains TMB geometry, TMD/TMC definitions and TTX textures/preview. It has no MQO, BLEND, TGI, BMP or license file.

The [official workshop](https://www.ikarus.net/en/rc10-model-workshop/) documents authoring and compilation. Its inspected [Metasequoia example](https://www.ikarus.net/downloads/workshops/rc10_metaseq_model.zip) contains MQO/TMD/TMC/BMP; its [Blender example](https://www.ikarus.net/downloads/workshops/rc10_blender_model.zip) contains BLEND/TMD/TMC/BMP. Neither supplied an explicit cross-project license.

Author sources can enable selected aircraft. A one-way compiler into Aerofly does not establish a TMB/TTX reader, and compiled binary does not itself mean encrypted. Do not promise arbitrary RC7/RC9/RC10 ZIP compatibility from the editable examples.

**Updated evidence:** the [modern follow-up](modern-rc-simulators-2026-11-17.md#aerofly-rc10-strongest-new-compiled-format-result) now records an independently decoded and rendered static Panda GLB and a separate Deproni BLEND conversion. These are laboratory visual results, with controls, flight mapping, full material fidelity and general version/DLC coverage still open.

### Phoenix RC

Follow-up: the [dedicated Phoenix investigation](phoenix-2026-11-17.md) now records seven decoded PKG containers, including the author's Freewing SU-35 and recent forum releases, plus readable MOD declarations and a proposed [AC-PX plan](../../plans/phoenix-aircraft-import.md). This advances the acquisition evidence below; complete GEO conversion and flight support remain unproven. The original Pitts-source download limitation still applies.

[SupermotoXL's Pitts Special release](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/hobby-king-pitts-special-bi-plane-phoenix-r-c-simulator.html) offers both Phoenix and separate OBJ source ZIPs. The author's Wing Wing Z-84 and Durafly P-51D releases provide further real candidates. The [installation guide](https://www.supermotoxl.com/resources/guides-tutorial/3d-models-creation-and-simulator/how-to-install-custom-models-in-phoenix-rc.html) describes PKG installation.

The Pitts OBJ and Z-84 package links returned HTTP 403 to the binary inspection client. Contents, dependencies and hashes were not verified. The author permits free noncommercial distribution; that is not an unrestricted commercial conversion grant. No general PKG/compiled-geometry reader was established. An OBJ offered by one author is a source route for that aircraft, not proof of a generic Phoenix importer.

### RealFlight

The [official KEmax documentation](https://forums.realflight.com/KEmax/) distinguishes proprietary KEX meshes, RFX interchange packages and older G3X packages. KEmax exports models into RealFlight; it is not evidence of reverse conversion. Distinguish EA (entire aircraft), AV (variant requiring a base aircraft) and CS (paint requiring a base mesh).

[The mike326/myergo catalog](https://www.catv296.ne.jp/~myergo/rf_hangar.html) links EA downloads for Extreme Flight Edge540T 104, Pilot RC Laser V3 103, Skywing Edge540 104, Pilot RC Sbach 342 V2 103 and RC Factory CLIK25. The CLIK25 resource page was readable through HTTP but required login to download; no RFX was inspected. These are attractive RC examples, not demonstrated OpenRC-compatible assets.

The [official 10.10.203 release announcement](https://steamcommunity.com/app/2069310/allnews/) changes re-export behavior for imported RFX geometry and checks base dependencies for AV imports. Do not base a conversion design on opening any imported RFX and re-exporting its entire geometry. A KEX reader or original author source plus permission remains a prerequisite.

**Updated evidence:** the [modern follow-up](modern-rc-simulators-2026-11-17.md#realflight-evolution-valuable-recent-catalog-unresolved-compiled-mesh) inspects public AcroMaster EA and AeroScout AV files plus associated Skywalker FBX/BLEND sources. Plain metadata is readable in the samples, but KEX geometry decoding remains unproven. The CLIK25 download above was not obtained.

### HELI-X and REFLEX

[HELI-X's official catalog](https://www.heli-x.info/cms/models/) includes EasyStar, Extra300/330, PiperJ3, Funray and ASW28. The [V11 manual](https://www.heli-x.info/help11/UsersManualV11.pdf) documents PlaneMonoStandard parameters and an older developer section describing OBJ/XML. The actual [EasyStar XML](https://www.heli-x.info/models10/EasyStar/EasyStar.xml) was read. A complete current fixed-wing geometry package was not obtained; a same-basename OBJ URL returned 404. Do not generalize legacy OBJ documentation into verified availability for every current plane. The simulator's private-use EULA does not clear cross-project asset reuse.

[Burkhard Erdlenbruch's REFLEX catalog](https://erdlenbruch.de/Burkhard/Modellflug/textReflex.html) includes Ugly Stik, Kwik Fli III, Telemaster, MDM-1 Fox and Bergfalke. He describes PAR physics and MOD visuals created through RMK. No qualified MOD decoder or original geometry package was demonstrated. Import should consume captured data, not execute model installers.

**Updated evidence:** the [modern follow-up](modern-rc-simulators-2026-11-17.md) obtained complete Extra330SC-UL_FC and Stearman OBJ/material/XML packages from the official HELI-X V11 demo, distinguished them from 39 metadata-only plane folders and documented V10/V11 incompatibility. It also inspected two REFLEX MOD/PAR packages with embedded JPEG blocks. Those findings supersede the earlier sample-availability limitations here without establishing production import or flight qualification.

## Shared automatic pipeline

The player selects a downloaded package or model folder. OpenRC identifies the family, captures dependencies, converts supported visuals, imports declared observations and proposes a usable draft. Questions are reserved for ambiguous variants, missing data, unsupported capabilities or decisions affecting the result. A mandatory external Blender conversion would not fulfill the project's automatic-import objective.

| Stage | Reuse / implementation decision | Required evidence before claiming success |
| --- | --- | --- |
| Capture and identify | Reuse bounded capture/archive mechanisms; inspect content and version, not extension alone | FMS positional PAR, FMS VERSION 1.0 PAR and RC Desk Pilot XML PAR remain distinct; no missing dependency silently substituted |
| Geometry | Reuse qualified AC3Db portions; evaluate a shared X reader; add 3DS only with justified coverage | Correct hierarchy, names, winding, normals, materials and transforms for accepted dialects |
| Images | Existing qualified PNG/JPEG/BMP path where applicable; add indexed BMP and SGI; assess DDS support in the pinned Godot build | Bounded decoded bytes, supported formats, visible correct textures, meaningful failure |
| Motion | Simulator adapter maps component names, hinge points, channel signs, travel and mixing | Correct neutral and endpoint poses after scale/axis conversion; independent instances |
| Observations | Preserve source path/hash, native units, section/configuration identity and disagreements | Explicit dimensional conversion and provenance; unknown semantics remain unresolved |
| OpenRC flight definition | Map only justified fields to the existing authoring/domain model | Capabilities supported, trim/control signs/envelope validated; no claim of solver equivalence |
| Persistence and export | Existing admitted GLB, draft, qualification, Store and portable-package paths | Save/reopen fidelity, dependency completeness, atomic replacement, intended export scope |

Current seams to inspect/reuse: [AC3D reader](../../../app/workshop/creator/clearview/ac3d.gd), [archive reader](../../../app/workshop/creator/clearview/archive.gd), [converter](../../../app/workshop/creator/clearview/converter.gd), [images](../../../app/workshop/creator/clearview/images.gd), [motion](../../../app/workshop/creator/clearview/motion.gd), [observations](../../../app/workshop/creator/clearview/observations.gd). Do not move files or generalize ClearView prematurely; extract shared code after a second adapter demonstrates the common contract.

The first targeted Creator flight domain is conventional aft-tail, single-tractor electric, finite-battery, hand-launch/airborne and gearless; numerical and flight qualification remain open. Many listed sources have gear, glider-only configurations, pusher/delta layouts, multiple motors or combustion power. They can be visual research inputs without being qualified flight inputs. Do not silently remove gear, replace propulsion or label a generic trainer conversion as faithful to the original aircraft.

### Reuse available libraries before writing a new codec

[Assimp's format list](https://github.com/assimp/assimp/blob/master/doc/Fileformats.md) includes X, AC/AC3D, 3DS and OBJ; its [license](https://github.com/assimp/assimp/blob/master/LICENSE) is BSD-3-Clause with separate dependency/test-asset notices. Its presence is a credible alternative to a new X or 3DS parser, not proof that the inspected aircraft convert correctly.

Keep the existing bounded GDScript AC path for the first CRRCSim trial. Compare a narrowly scoped X implementation against a pinned Assimp build using the actual FMS and RC Desk Pilot corpus. Assimp needs an aiScene-to-admitted-GLB/scene adapter and format-specific metadata processing. Its [memory import API](https://github.com/assimp/assimp/blob/master/include/assimp/Importer.hpp) does not solve all external-file dependencies; a captured-only IOSystem is required for those cases.

A [GDExtension](https://docs.godotengine.org/en/4.4/tutorials/scripting/gdextension/gdextension_cpp_example.html) requires binaries for each supported export target. [Runtime GLB loading](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html) is supported by Godot, but native codec integration, image modules and web export constraints must be verified against OpenRC's pinned engine. A generic codec's post-parse memory report is not a hard peak-memory bound. Evaluate bounded readers or an appropriately isolated desktop conversion worker before adopting it for untrusted input. No dependency is adopted by this research.

## Recommended implementation sequence and acceptance

1. **Establish a small, rights-tracked corpus.** Use original synthetic fixtures in the repository and legitimate external samples locally. Record authors, permission terms, complete dependencies, format variants and expected geometric/motion facts. Downloaded availability, permission to convert and permission to redistribute are separate fields.
2. **CRRCSim vertical slice.** XML + AC3Db + SGI to textured preview and articulated draft. Exercise Angel-like power/configuration variants and Wasabi-like mirrored controls. Use complete captured dependencies; missing variants stay explicitly incomplete. Close the existing shared qualification gates before advertising a flyable import.
3. **Shared X proof, then FMS and RC Desk Pilot adapters.** Compare existing codec options on all five FMS samples and Xtra component meshes. Implement FMS dialect detection separately from RC Desk Pilot XML and pose assembly. Establish bounds, encodings and error behavior with authored fixtures.
4. **Authorize and add PicaSim examples; broaden 3DS only when justified.** Preserve multi-section XML, shared presets, mirrored components and transforms. SSS and CRRC community 3DS packages can then share the geometry layer.
5. **Investigate compiled ecosystems only against a concrete stop condition.** Obtain a complete legal sample and demonstrate geometry/material/hierarchy decoding for one version before scheduling general Phoenix, RealFlight, Aerofly runtime or REFLEX compatibility. An editable source route is recorded separately.

A release candidate must demonstrate: correct visual scale and controls; preserved source/configuration identity; no DLL/script/installer execution; actionable missing-dependency diagnostics; cancellation and resource bounds; save/reopen and portable export through existing contracts; and explicitly qualified OpenRC physics for the supported target domain. Unsupported aircraft can remain visual drafts without misleading flight-readiness labels.

## Verification boundary

Actual binary inspection covered five FMS aircraft, three CRRCSim community ZIPs, the Fedora CRRCSim add-on RPM, RC10 Panda, two RC10 authoring examples and the SSS distribution: thirteen packages. Repository inspection covered concrete CRRCSim, RC Desk Pilot and PicaSim data/loaders. Catalog-only leads and failed/download-gated attempts are labeled separately in the inventory.

No vendor executable was run. No third-party aircraft mesh, texture, source ZIP or permission email is included in this change. No new importer, rendered conversion, exported-build check, numerical-flight campaign or performance measurement was performed. This record is the evidence and next-work recommendation, with licensing and decoder uncertainties left explicit.

