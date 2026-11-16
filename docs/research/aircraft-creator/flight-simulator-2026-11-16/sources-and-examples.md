# Flight Simulator sources, examples and conversion tools

**Research date:** 2026-11-16. **Scope:** public primary documentation, source repositories and selected text/configuration/glTF JSON. The [research index](README.md) distinguishes repository facts from proposals; the [AC-FS plan](../../../plans/flight-simulator-aircraft-import.md) owns implementation. No aircraft was converted, rendered or flown in OpenRC during this investigation. Source availability, technical compatibility and permission to reuse are separate findings.

## Tool assessment

| Tool or reference | Evidence and useful role | Proposed decision / limit |
| --- | --- | --- |
| Asobo MSFS 2020 glTF Blender IO | Official source glTF importer/exporter, separately licensed Apache-2.0; documentation describes a pure Khronos glTF export option | Optional author-controlled preparation workflow. Its README explicitly excludes glTF already built into a simulator package. This is not a universal Community-package decoder. [F08, F09] |
| Khronos glTF 2.0 / conventional Blender export | Documented interchange with explicit required extensions and local buffers/images | Normalize into Creator's strict self-contained GLB, then re-admit through the existing reader. Unsupported required extensions cannot be ignored. Generic glTF acceptance is broader than Creator's current subset. [F19, F30] |
| ModelConverterX, Arno Gerretsen / SceneryDesign.org | Author lists FS2004, FSX and Prepar3D MDL and glTF among supported formats | Optional user-operated legacy geometry preparation. The manual's section 10.1.7 limits glTF animation/visibility export from compiled MDL/BGL, with only a narrow scenery exception. Expect control re-rigging and material review. No in-app binary dependency is selected. [F04, F15] |
| `bestdani/msfs2blend` | Apache-2.0 Blender importer aimed at livery painting and mesh/UV recovery | Experimental prior art. Author warns about incomplete reconstruction and unsupported bone animation/incorrect rotations. Do not promise a faithful aircraft export. [F17] |
| Microsoft DirectXTex / `texconv` | Image conversion tool with DDS support | Optional DDS-to-PNG preparation; verify alpha, color space, normal orientation, mip handling and decompression budgets. Image conversion does not convert the MSFS material graph or grant rights in textures. [F18] |
| `LievreAI/msfsLegacyImporter` | MIT-labeled FSX-to-MSFS project; configuration splitting and AIR migration | Study explicit migration diagnostics. AIR migration depends on an AirUpdate text dump; intended input is native FSX, not every FS9/P3D model. Audit file-level origin before reusing code. [F16] |
| `marcosox/fs-parse` | Partial FSX/FS9 MDL/BGL parser; author acknowledges FS9 limitations | Research reference only. No root license was observed in this inspection; do not integrate without an established license and bounded-reader review. [F20] |

The proposed first product route accepts a user-prepared GLB with readable source configuration. Automatic modern-source normalization follows AC-FS-04's comparison spike. The comparison should use independently authored asymmetric geometry, visible texture/normal markers and known control pivots; accepting the same input is insufficient evidence of equal output. The production desktop application should not require Blender, the Microsoft SDK or ModelConverterX to launch.

## Additional mod, forum and tool investigations

The [24-question follow-up](follow-up-24-investigations/README.md) adds dated primary-source evidence, including first-person discussions on Microsoft Flight Simulator Community, Microsoft DevSupport and FSDeveloper, plus maintainer issues and author release histories. It qualifies reported symptoms separately from reproduced behavior. Its [tooling backlog](follow-up-24-investigations/tooling-and-fixtures.md) evaluates Khronos Validator, glTF Transform, gltfpack, selected standards fixtures, low-Re tools and measurement references without installing or adopting dependencies.

| Aircraft/mod case | Evidence added | Design use |
| --- | --- | --- |
| C152X / JPLogistics | Stock dependency and simulator-update changes | Preserve base/overlay/build identity |
| MGouge425 / Bagolu C172 | Cross-file circuit and mod-version interactions | Diagnose dependency and precedence conflicts |
| Savage Carbon | Author-reported geometry, engine, balance and later retuning | Keep datum/CG/installation roles separate |
| AS33 Me / B21 | Ballast migration, runtime propeller and tow behavior | Preserve unsupported systems and attributed dynamic observations |
| VL3 Rotax 915 | README documents different visual/physical blade count | Discrepancy report and explicit RC installation |
| A32NX | Historical merged SU9 engine-control fix | Custom-runtime and host-build context |

Per-case source links, dates, permissions gaps and proposed fixtures are in [R07–R12](follow-up-24-investigations/aircraft-mod-cases.md). These cases add documentary evidence; no package was imported or flown. The three pinned source inspections below remain separate and retain their original measured scope.

## Inspected aircraft

Three repositories were inspected at pinned commits. The inspection read repository metadata, source trees and selected UTF-8 files. It did **not** download or decode BIN, DDS, Blender or executable assets. glTF counts below are declared counts from triangle-mode primitive accessors, not decoded-buffer validation, instantiated triangle totals or performance measurements.

| Aircraft | Pinned revision | What this inspection establishes | Best use in this project |
| --- | --- | --- | --- |
| Flying Brick | `e816b6b86bfbd16183ed5784b3336a0338b8315b` | Readable CFG/XML and Blender source; generated glTF/BIN absent; own code MIT; custom WASM flight behavior | Configuration and missing-dependency examples; possible author-controlled export exercise |
| Delta Simulations C-17 | `75d119d6cd3bfc163f073a75277f8ffb70007b05` | Substantial aircraft source tree, exterior/interior LODs, structured configuration; mixed code/art rights | Later authorized package, LOD and discrepancy tests; no first-release flight claim |
| FlyByWire A32NX | `753bbdd744d26d76b600c5f23ee59ece4f68341f` | Source model carries optimized/vendor data, required DDS extension, animations and submodule dependencies; mixed rights | Required-extension, material, dependency and unsupported-systems cases |

### Flying Brick

[Pinned source tree](https://github.com/tml1024/flying-brick/tree/e816b6b86bfbd16183ed5784b3336a0338b8315b), [README](https://github.com/tml1024/flying-brick/blob/e816b6b86bfbd16183ed5784b3336a0338b8315b/README.md), [LICENSE](https://github.com/tml1024/flying-brick/blob/e816b6b86bfbd16183ed5784b3336a0338b8315b/LICENSE).

The tree contains `aircraft.cfg`, `flight_model.cfg`, model configuration/XML and a Blender source model. The model-directory ignore file excludes generated `*.gltf` and `*.bin`; this checkout therefore cannot directly supply a finished source glTF to OpenRC. The license file is MIT, Tor Lillqvist, 2021, blob `4f2d24aecd574ab41765f443f488f8da52ba6e76`.

The README describes WASM overriding ordinary flight dynamics and controls affecting velocity directly. Flight configuration includes deliberately unrealistic values and dummy-wing comments. An ordinary CFG reader cannot reconstruct that behavior. Referenced base-game avatars/effects are separate dependencies whose rights are not conveyed by the repository's MIT license.

**Finding:** useful for dependency diagnostics and explaining the boundary between a configuration and executable flight logic. It is not an aerodynamic oracle, a conventional RC reference or a ready-to-import complete geometry fixture. [F21]

### Delta Simulations C-17

[Pinned source tree](https://github.com/Delta-Simulations/MSFS-C-17/tree/75d119d6cd3bfc163f073a75277f8ffb70007b05), [README](https://github.com/Delta-Simulations/MSFS-C-17/blob/75d119d6cd3bfc163f073a75277f8ffb70007b05/README.md), [flight configuration](https://github.com/Delta-Simulations/MSFS-C-17/blob/75d119d6cd3bfc163f073a75277f8ffb70007b05/PackageSources/SimObjects/Airplanes/C17/flight_model.cfg), [aircraft configuration](https://github.com/Delta-Simulations/MSFS-C-17/blob/75d119d6cd3bfc163f073a75277f8ffb70007b05/PackageSources/SimObjects/Airplanes/C17/aircraft.cfg), [LOD01 model JSON](https://github.com/Delta-Simulations/MSFS-C-17/blob/75d119d6cd3bfc163f073a75277f8ffb70007b05/PackageSources/SimObjects/Airplanes/C17/MODEL/C17_LOD01.gltf).

The source tree includes paired exterior glTF/BIN, an exterior LOD, an interior model/LOD, CFG and XML. It is a substantive source aircraft, not only a livery or stock-aircraft override. `MODEL/model.CFG` selects `exterior=C17.xml` and `interior=C17INT.xml`; resolution needs the actual model-selection keys and case handling, not a hard-coded `normal=` assumption.

The inspected LOD01 JSON, blob `6d27e41daa4f8c97921969da164544a8b4077fc5`, declares glTF 2.0, **1 node, 1 mesh, 2 materials and 7,583 triangles**, with a **299,612-byte** external BIN. It declares no animations or texture images and uses Asobo extensions including invisible/shadow material semantics. A small LOD can be syntactically useful while omitting the visible textured exterior and moving parts the player expects. Selection must report what it actually contains.

Structured `max_gross_weight=585000` in `flight_model.cfg` conflicts with `875000` in aircraft performance-description prose. These values are source declarations in pounds, not independently verified aircraft specifications. Preserve the discrepancy and prefer structured field semantics; never extract authoritative physics silently from marketing/performance prose. The respective file blob hashes are `575a468420842b9de802a7436ad67d4072d4e6cb` and `d7173e7a07b95ebb6f0f61324f35370dd62a9ffa`.

The flight-model file declares `major=6.0` while aircraft configuration declares `major=1`. These are format/section version values; neither identifies a Flight Simulator product generation. Version detection must inspect capabilities and source shape.

The README separates GPLv3 original code, CC BY-NC 4.0 original 3D assets and Microsoft-derived content under separate terms. **Finding:** a useful later authorized stress case, with real contradictions and model-selection issues. It is not a permissive bundled fixture or a configuration the current single-tractor Creator can faithfully fly. [F23]

### FlyByWire A32NX

[Pinned source tree](https://github.com/flybywiresim/aircraft/tree/753bbdd744d26d76b600c5f23ee59ece4f68341f), [README](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/README.md), [flight configuration](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/base/flybywire-aircraft-a320-neo/SimObjects/AirPlanes/FlyByWire_A320_NEO/flight_model.cfg), [LOD06 model JSON](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/fbw-a32nx/src/model/a320-exterior/A320_NEO_LOD06.gltf).

The exterior source tree contains glTF/BIN assets from LOD00 to LOD06. The repository also references an aircraft-large-files submodule. A top-level Git checkout is not evidence that every dependency is available locally.

LOD06 JSON, blob `b25ccf4c9183195d25442f2bd186b3fc4507942d`, declares **159 nodes, 31 meshes, 4 materials, 29 animations and 3,272 triangles**, with an **858,976-byte** external BIN. It contains **12 DDS image URIs**, requires `MSFT_texture_dds`, and carries `ASOBO_asset_optimized` version 4.2, material-detail/blend extensions and DirectX normal conventions. Even a file under a source directory needs content and required-extension probing. This file cannot pass the present PNG-only, rigid Creator GLB path unchanged.

The configuration includes two jet engines, source mass/inertia, control and gear data. Reproducing the installed aircraft would additionally require systems and flight-control behavior outside this adapter. Its use of `empty_inertia_tensor` also demonstrates why the documented array order and frame must be interpreted explicitly rather than copied into the OpenRC tensor.

The README distinguishes GPLv3 original code, CC BY-NC 4.0 original 3D assets and separately governed Microsoft-derived content. **Finding:** a valuable real-world compatibility counterexample. It is not a first-release RC topology, a plain-glTF fixture or evidence that source configuration reproduces the A32NX systems. [F22]

### Other candidates reviewed

| Candidate | Evidence | Disposition |
| --- | --- | --- |
| Newly authored minimal conventional trainer | Proposed fixture, not created in this branch | Best required-CI basis: known units, deliberately asymmetric landmarks, authored materials, known hinges and independent physical values; chosen project-compatible license |
| Headwind A339X | README states a specific third-party A330neo model exception; the model is not open source and reuse needs the creator's permission | Dependency/rights example and possible later authorized case, not a freely reusable model. [F24] |
| `ronalove/fs2020-vl3-rotax915` | README describes modification of the stock VL-3 912; no root license was observed | A configuration mod does not supply the base model or establish permission to reuse it. [F25] |
| Heavy Division B78XH | README describes modification of the default 787-10 and requires Premium Deluxe | Demonstrates a missing separately supplied base aircraft; not a standalone freely reusable 787. [F26] |
| Official SDK SimpleAircraft / DA62 | Microsoft documents complete sample projects | Public documentation can explain package structure. Do not select these sample assets as OpenRC fixtures under the current SDK terms. [F27–F29] |

No inspected realistic aircraft was established as a complete, dependency-free, permissively redistributable end-to-end fixture. A suitable conventional source aircraft and its exact rights remain AC-FS-01 work. Source-level feasibility examples must not become a list of advertised supported airplanes.

## Rights and fixture policy

The current Microsoft SDK EULAs restrict SDK purpose, sample use and development of a competing simulator. This plan therefore excludes SDK installation/compilation, SDK sample copying and SDK-based benchmarking as assumed OpenRC dependencies. Any proposed exception needs the relevant permission and a review of the exact use. Separately licensed open-source tooling is evaluated under its own terms; an SDK restriction does not by itself establish the license of an independently published tool. [F28, F29]

Record the aircraft code, geometry, textures, sounds and inherited base assets separately: source URL and revision, copyright/author, exact license text, modification rights, redistribution conditions and required attribution. A repository license badge does not override specific asset exceptions. Freeware availability, a purchase receipt or an unencrypted file does not establish permission to redistribute the converted aircraft.

Required CI should use original synthetic files and an independently authored minimal trainer. Optional local corpus runs may reference lawfully available third-party source without committing it. A portable OpenRC bundle must either include dependencies whose export is permitted or explicitly refuse a purported self-contained export. A user attestation is a recorded declaration, not verified authorship or permission. Local inspection does not authorize decryption, download of missing paid content or execution of bundled gauges/WASM/DLLs/installers.

This branch stores links, findings, source identifiers and proposed contracts only. No Microsoft SDK binary, aircraft geometry, texture, sound or third-party executable has been added to the repository.

## Format and package sources

All consulted on 2026-11-16. These are public primary references, not automatic runtime download dependencies. Moving documentation and tool repositories should be rechecked when implementation begins; pinned aircraft observations above remain tied to their exact commits. F15 was inspected through the relevant indexed manual excerpt; the full PDF could not be opened because of its size. General format statements in the [research index](README.md) and [plan](../../../plans/flight-simulator-aircraft-import.md) use this register.

- **F01 — Microsoft:** [MSFS 2020 Using the SDK](https://docs.flightsimulator.com/html/Introduction/Using_The_SDK.htm). Package manifests, VFS and compilation pipeline.
- **F02 — Lockheed Martin:** [Prepar3D v5 Simulation Objects](https://www.prepar3d.com/SDKv5/sdk/simulation_objects/simulation_objects_overview.html). SimObject containers, MDL models and aliases.
- **F03 — Lockheed Martin:** [Aircraft Configuration Files](https://www.prepar3d.com/SDK/SimObject%20Creation%20Kit/SimObject%20Container%20SDK/Aircraft%20Configuration%20Files.htm). AIR aerodynamic data and geometry caveats.
- **F04 — SceneryDesign.org / Arno Gerretsen:** [ModelConverterX](https://www.scenerydesign.org/modelconverterx/). Supported model formats.
- **F05 — Microsoft:** [MSFS 2020 aircraft.cfg](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/aircraft_cfg.htm). File versions, optional split sections and base containers.
- **F06 — Microsoft:** [model.cfg](https://docs.flightsimulator.com/html/Content_Configuration/Models/model_cfg.htm). Model selection and XML references.
- **F07 — Microsoft:** [Model CFG and Aircraft XML](https://docs.flightsimulator.com/html/mergedProjects/How_To_Make_An_Aircraft/Contents/Files/model.htm). Exterior/interior and LOD resolution.
- **F08 — Asobo Studio:** [MSFS 2020 glTF Blender IO](https://github.com/AsoboStudio/Microsoft-Flight-Simulator-2020-glTF-Blender-IO). Source importer scope, package-built limitation and Apache-2.0 license.
- **F09 — Asobo Studio:** [Blender IO documentation](https://github.com/AsoboStudio/Microsoft-Flight-Simulator-2020-glTF-Blender-IO/blob/main/Documentation/Documentation.md). Pure Khronos glTF export option.
- **F10 — Microsoft:** [MSFS 2024 Modular SimObject Project Structure](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/modular-simobjects/modular-simobject-project-structure/). Common, preset, attachment and livery structure.
- **F11 — Microsoft:** [MSFS 2024 CFG Files General Information](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/cfg-files-general-information/). Dynamic parameters and override behavior.
- **F12 — Microsoft:** [MSFS 2024 Using the SDK](https://docs.flightsimulator.com/msfs2024/retail/introduction/using-the-sdk/). KTX2/KTX2P, build transformations, DRM and runtime modules.
- **F13 — Microsoft:** [MSFS 2024 Virtual File System Information](https://docs.flightsimulator.com/msfs2024/retail/devmode/menus/tools_info/virtual-file-system/virtual-file-system-information/). Local packages and incomplete streamed-package contents.
- **F14 — Microsoft:** [MSFS 2024 glTF Format](https://docs.flightsimulator.com/msfs2024/retail/models-and-textures/msfs-2024-gltf-format/). Material and normal conventions, unsupported standard features.
- **F15 — SceneryDesign.org:** [ModelConverterX manual](https://www.scenerydesign.org/latest-release/ModelConverterX.pdf), section 10.1.7. Compiled MDL/BGL animation and visibility export limits; bounded excerpt inspection.
- **F16 — Project author:** [LievreAI/msfsLegacyImporter](https://github.com/LievreAI/msfsLegacyImporter). Native-FSX conversion scope, AIR dump dependency and known limitations.
- **F17 — Project author:** [bestdani/msfs2blend](https://github.com/bestdani/msfs2blend). Livery-painting mesh/UV scope and reconstruction limitations.
- **F18 — Microsoft:** [DirectXTex](https://github.com/microsoft/DirectXTex), [Texconv documentation](https://github.com/microsoft/DirectXTex/wiki/texconv). DDS/image-format conversion.
- **F19 — Khronos registry:** [MSFT_texture_dds](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Vendor/MSFT_texture_dds/README.md). Texture extension and fallback requirements.
- **F20 — Project author:** [marcosox/fs-parse](https://github.com/marcosox/fs-parse). Partial legacy parsing and FS9 limitations; no dependency adoption selected.
- **F21 — Tor Lillqvist:** [Flying Brick](https://github.com/tml1024/flying-brick/tree/e816b6b86bfbd16183ed5784b3336a0338b8315b). Pinned source and MIT license; custom flight behavior.
- **F22 — FlyByWire Simulations:** [Aircraft README](https://github.com/flybywiresim/aircraft/blob/753bbdd744d26d76b600c5f23ee59ece4f68341f/README.md). Project scope and separate code/art/derived-content terms.
- **F23 — Delta Simulations:** [C-17 README](https://github.com/Delta-Simulations/MSFS-C-17/blob/75d119d6cd3bfc163f073a75277f8ffb70007b05/README.md). Separate code/art/derived-content terms.
- **F24 — Headwind Simulations:** [Aircraft repository](https://github.com/headwindsim/aircraft). Explicit third-party model exception.
- **F25 — Project author:** [VL-3 Rotax 915](https://github.com/ronalove/fs2020-vl3-rotax915). Stock-aircraft modification and base dependency.
- **F26 — Heavy Division:** [B78XH](https://github.com/Heavy-Division/B78XH). Required default Premium Deluxe aircraft.
- **F27 — Microsoft:** [SimpleAircraft](https://docs.flightsimulator.com/msfs2024/retail/samples-tutorials/samples/simobjects-aircraft/simpleaircraft/), [DA62](https://docs.flightsimulator.com/msfs2024/retail/samples-tutorials/samples/simobjects-aircraft/da62/). Sample project descriptions, not an OpenRC reuse grant.
- **F28 — Microsoft:** [MSFS 2020 SDK EULA](https://docs.flightsimulator.com/html/Introduction/SDK_EULA.htm), sections 1(a), 1(b), 1(g). Purpose, sample and competition terms.
- **F29 — Microsoft:** [MSFS 2024 SDK EULA](https://docs.flightsimulator.com/msfs2024/retail/introduction/sdk-eula/), corresponding sections. Current SDK terms.
- **F30 — Khronos:** [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html). Coordinate system, units, containers, transforms and required extensions.

## Physics and units sources

These support the [conversion and scaling specification](conversion-and-scaling.md). P9 and F03 cover the same documentation family; register IDs are references, not a count of distinct publications. Dimensional scaling derived in the specification is explicitly distinguished from simulator-defined field semantics and measured RC evidence.

- **P1 — Microsoft:** [MSFS 2020 Aircraft SimObjects](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/Aircraft.htm). Aircraft file organization.
- **P2 — Microsoft:** [MSFS 2020 Flight Model Physics](https://docs.flightsimulator.com/html/Samples_And_Tutorials/Primers/Flight_Model_Physics.htm). Simulator aerodynamic interpretation and modern/legacy distinction.
- **P3 — Microsoft:** [MSFS 2020 flight_model.cfg](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model_cfg.htm). Mass, scalar inertia, positions and field units.
- **P4 — Microsoft:** [MSFS 2020 Airplane Geometry](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model/geometry.htm). Span, area, geometry and coordinate semantics.
- **P5 — Microsoft:** [MSFS 2024 flight_model.cfg](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/flight_model.cfg/). Tensor layout and validity/override rules.
- **P6 — Microsoft:** [MSFS 2024 Physics Objects Information](https://docs.flightsimulator.com/msfs2024/retail/content-configuration/cfg-files/flight-model/physics-objects-information/). Left-handed source basis, inertia and negative mass-product convention.
- **P7 — Microsoft:** [MSFS 2020 Aerodynamics](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model/aerodynamics.htm). Derivatives, table axes, active modes and mesh-relative aerodynamic-center exception.
- **P8 — Microsoft:** [ESP Flight Models](https://learn.microsoft.com/en-us/previous-versions/microsoft-esp/cc526961(v=msdn.10)). Legacy configuration and AIR relationships.
- **P9 — Lockheed Martin:** [Prepar3D Aircraft Configuration Files](https://prepar3d.com/SDK/SimObject%20Creation%20Kit/SimObject%20Container%20SDK/Aircraft%20Configuration%20Files.htm). Legacy field meanings and performance caveats.
- **P10 — Microsoft:** [MSFS 2020 engines.cfg](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/engines_cfg.htm). Engine/propeller fields and limitations of rated-power metadata.
- **P11 — Brandt and Selig:** [Propeller Performance Data at Low Reynolds Numbers, AIAA 2011-1255](https://m-selig.ae.illinois.edu/pubs/BrandtSelig-2011-AIAA-2011-1255-LRN-Propellers.pdf). Measured propeller coefficient conventions and low-Re performance.
- **P12 — Microsoft:** [MSFS 2020 Contact Points](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model/contact_points.htm). Mixed contact-array units and meanings.
- **P13 — NASA:** [Modeling Flight](https://www.nasa.gov/wp-content/uploads/2015/01/601262main_modelingflight-ebook.pdf), chapter 1 scaling table (printed page 10; PDF page 19). Dynamic-similarity scaling and density assumptions.
- **P14 — NASA Glenn:** [Similarity Parameters](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/similarity-parameters/). Reynolds and Mach similarity constraints.
- **P15 — NASA Glenn:** [Lift Equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/lift-equation/). Lift, density, velocity, area and lift coefficient.
- **P16 — UIUC Applied Aerodynamics Group:** [Wind Tunnel Data](https://m-selig.ae.illinois.edu/pd.html). Low-Re airfoil/propeller evidence and data-use conditions; evaluate each dataset's actual domain and terms.
- **P17 — NIST:** [Guide to the SI, Appendix B.8 conversion factors](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8). Imperial/SI unit conversion reference; the specification identifies mechanical horsepower and mass versus force pounds.
