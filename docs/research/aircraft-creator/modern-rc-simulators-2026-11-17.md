# Modern RC simulator models and expansion compatibility

Date: 2026-11-17. Status: dated source research and laboratory conversion evidence. No new OpenRC runtime importer or flight qualification is delivered. This is the authoritative modern-ecosystem follow-up to the [earlier RC survey](rc-simulator-sources-2026-11-17.md); that survey retains the older/open-format comparison. The [machine-readable inventory](modern-rc-source-inventory-2026-11-17.json) records exact sample identities, results and limitations.

The [Aircraft Creator plan](../../plans/aircraft-creator.md), [ClearView subplan](../../plans/clearview-aircraft-import.md) and proposed [Flight Simulator import plan](../../plans/flight-simulator-aircraft-import.md) retain implementation ownership and gates. Research base: `6d4678c6d284789de5a5f90720970870156e702a`; previously inspected runtime: `a986b99ca453db90f0a05399483c11cc55d17afd`. No new accepted step IDs, dependencies or aircraft are introduced here.

## Decision

For a **modern RC content** objective, provisionally investigate **HELI-X V11 first, aerofly RC10 second and RealFlight Evolution third**. This is a product/engineering judgment based on available geometry-bearing samples and demonstrated decoding, not a measured ranking of implementation effort, visual quality, flight accuracy or legality. HELI-X has simpler standard geometry but unresolved scaling and no rendered conversion; Aerofly has the strongest actual static reconstruction result. Aerofly may deserve first priority depending on target aircraft, team skills and catalog value.

| Ecosystem | Current evidence | Models and expansion delivery | OpenRC input feasibility demonstrated |
| --- | --- | --- | --- |
| HELI-X V11 | Official V11 demo inspected; two fixed-wing packages contain primary geometry and accompanying assets | Stock catalog and in-app resource updates; many catalog entries are only metadata in the demo | Main visual OBJ, MTL, images, collision geometry and XML exist for Extra330SC-UL_FC and Stearman; missing-material caveat below; no OpenRC conversion yet |
| aerofly RC10 | Official user Panda package decoded and reconstructed as a static textured GLB | Base editions, two Steam expansion packs, free user aircraft and author sources | One compiled TMB/TTX sample successfully reconstructed; author-source BLEND path separately tested; controls and physics remain open |
| RealFlight Evolution | Current 2026 DLC verified; public EA and AV samples inspected | Stock aircraft, quarterly/year passes, community EA/AV/CS | Plain RFX metadata readable in samples; compiled KEX mesh reader unproven; selected public FBX/BLEND sources exist separately |
| neXt 2.090 | Official 2026 release notes and product catalog | Advertises 26 fixed-wing models; new models through 2.x updates | Setup-string sharing confirmed; aircraft mesh package, authoring SDK and decoder not established |
| SeligSIM 2026a | Author's current manual, release notes and migration document | Prior 2024.5 DLC included; no separate 2026 DLC listed yet | CFG folder structure documented; OHM geometry sample/decoder not established |
| Wings Simulator | Direct product available; Steam page still says Coming soon | Advertises 32 included aircraft, customization and user tracks | No complete arbitrary-aircraft source/export path established |
| AccuRC 2 | Official product, fixed-wing catalog and workbench documentation | Stock aircraft and component configuration | No complete fixed-wing asset sample or reverse geometry path established |
| REFLEX XTR2 6.02.0 | Still sold, but latest advertised application release dates to 2019 | Stock aircraft and community downloads | Two MOD/PAR packages inspected; readable records plus embedded JPEG; full geometry/physics semantics unresolved |

These are different evidence levels. A simulator offering a model, a user being entitled to fly it, readable geometry, correct control animation, a valid OpenRC flight definition and permission to redistribute the result are separate claims. None of the packages studied here has completed an OpenRC flight validation campaign.

## HELI-X V11: first candidate for a modern prototype

### Version and resource compatibility

The [official download page](https://www.heli-x.info/cms/download-2/) identifies V11.0 as current and advertises a functional demo with two planes, two helicopters and a multicopter. [Release notes](https://www.heli-x.info/cms/release-notes/) date revision 2675 to 2025-04-20. [New aircraft and airports](https://www.heli-x.info/cms/questions-and-answers-qa/) are obtained through Options > Look for new. Registered users receive updates, and the [V11 upgrade instructions](https://www.heli-x.info/cms/update-to-v10/) describe installing the new major version separately.

An [official forum administrator](https://forum.heli-x.info/viewtopic.php?t=2760) explicitly says V10 and V11 models are not compatible and should be updated in V11. Treat them as distinct adapter versions. The [V11 manual](https://www.heli-x.info/help11/UsersManualV11.pdf) includes a developer section still marked as V8 material, so it is a useful starting point rather than a complete V11 specification. Its modern material chapter documents additional MTL fields.

### Inspected V11 aircraft files

The vendor-linked [Linux V11 archive](https://www.heli-x.info/2675/HELI-X11.tar.gz), 492,613,770 bytes, was downloaded and inspected as data. Its SHA-256 is `88f4a77ca8715ce1996249b4a5d5201d5aceec83d677f1bee76c95b92c6f3675`. No simulator executable was run. Successful full archive traversal established gzip/tar readability.

It contains **41 plane directories**. Exactly two include their same-name primary aircraft OBJ and associated geometry/material assets; the other 39 contain XML and a preview image only. This agrees with the advertised two-plane demo but does not independently verify the application's selection or activation behavior.

| Geometry-bearing sample | Directly observed geometry | Useful configuration | Remaining issues |
| --- | --- | --- | --- |
| Extra330SC-UL_FC | Main OBJ: 3,656 vertices, 6,240 triangular faces; collision OBJ; separate Mainrotor OBJ/MTL; JPG/PNG textures and sound | XML credits Jan Stauffacher; declares 0.800 m visual span, 0.884 m aerodynamic WingSpan, 0.13 kg and NewElectric powertrain; names ailerons, elevator, rudder, wheels, propeller and linkage parts | Resolve scale/pivots, extended materials, control relationships and physics semantics; asset permission not established |
| Stearman | Main OBJ: 27,527 vertices, 50,081 triangular faces; collision and propeller meshes, textures, sound and XML | XML describes a 3 m biplane; bundled attribution to Emmanuel Baranger's FlightGear original | Two material names used by 244 faces are absent from the supplied MTL; GPL notice scope/version and adapted components need provenance review |

Counts and member hashes were independently checked by the lead against the extracted files. Stearman's missing names are `DefaultWhite_turn.png` (240 faces) and `DefaultWhite_alt.png` (4). This is a concrete reason to support recoverable missing-material diagnostics; HELI-X's own rendering fallback was not tested.

The [website catalog](https://www.heli-x.info/cms/models/) includes Edge540, Extra300/330, Pitts Challenger, F4U Corsair, Funray, ASW28, AlphaJet and Dassault Mystere. Actual V11 metadata also includes ExtraNG103 and ExtraNG67. Their complete geometry was not in the inspected demo. Catalog image URLs using `models10` do not establish the installed V11 model revision.

The V11 Swift_S1 XML describes a 3.85 m glider with a retractable Ceflix500 impeller and 12S battery. The [fan manufacturer's specifications](https://www.schubeler.com/product/cowling-51-hst-93mm/) establish an electric ducted-fan system, but the simulation XML uses generic `Jet` powertrain type. This is evidence for an EDF-powered sailplane description, not complete bundled geometry, an EDF sport jet, or a validated electric propulsion model. AlphaJet and Dassault Mystere also use `Jet`; their propulsion should not be labeled EDF from that field alone.

### Adapter work

An OBJ reader alone is insufficient. The observed XML has master/slave/rod relationships, pushrod anchors, pivots, second points and wheel rotation. The Extra's MTL uses `Kb`, `glossiness`, `specular`, `metallic` and `roughness`, beyond an ordinary diffuse-texture pipeline. The manual additionally documents packed metal/roughness maps, emissive and transparent materials.

Scale must be derived from the source definition. Extra's OBJ spans about 5.62 units across its visual wing axis while XML declares `VisualWingSpan` 0.800; assuming one OBJ unit equals one meter would be wrong. The exact runtime normalization remains unverified. Actual V11 XML also changes wheel/contact field families relative to public V10 files and includes profile/powertrain enum values absent from the old developer chapter. Preserve and report unknown semantics.

The first acceptance target should be a correctly scaled, textured, named visual assembly with demonstrated neutral and endpoint control poses. A flight-capable conversion then needs an independently justified mapping of dimensions, inertia, airfoils, control authority and propulsion. Simulator-specific coefficients are not interchangeable merely because their names resemble OpenRC fields.

## aerofly RC10: strongest new compiled-format result

### Editions and expansions

RC10 is a current RC product, separate from the full-size Aerofly FS line. Its official storefronts describe different packages:

| Channel/package | Advertised content | Scope of the statement |
| --- | --- | --- |
| [IKARUS Starter controller bundle](https://shop.ikarus.net/en/simulator-fuer-einsteiger/967-set-aeroflyrc10-starter-with-usb-flightcontroller-758176912084.html) | 12 models, 3 sceneries | Windows entry bundle; its full-upgrade text says 304/61 |
| [IKARUS Standard](https://shop.ikarus.net/en/aerofly-rc10-standard/969-aeroflyrc10-standard-with-rc-simconnector.html) | 100 models, 20 sceneries | Direct Standard bundle |
| [IKARUS full Windows version](https://www.ikarus.net/en/rc10-purchase/) | 300+ models, 60+ sceneries | Broad full-version catalog claim |
| [Steam base RC10](https://store.steampowered.com/app/2394350/) | Main description: 105 models, 22 sceneries | Same page also retains a conflicting 64/15 feature bullet |
| [Steam Expansion Pack 1](https://store.steampowered.com/app/2615690/) | Adds 100 models, 20 sceneries | Emphasis on aerobatics and high-performance aircraft |
| [Steam Expansion Pack 2](https://store.steampowered.com/app/2615700/aerofly_RC_10__Expansion_Pack_2/) | Adds 100 models, 20 sceneries | Emphasis on scale aircraft |

Do not merge these into one verified cross-channel total or claim that all entries are unique fixed-wing geometries. Models include other vehicle types and variants. The historic Standard/Professional/Ultimate names on [IKARUS's history page](https://www.ikarus.net/en/about-us/) concern RC7. Ultimate in the RC10 Pack 1 list is an aircraft name, not evidence of an RC10 Ultimate edition.

Useful stock examples are CAP 232, Edge 540 arTistic, EXTRemA 330S, Slick X360 and Yak 55. Pack 1 includes Extra 260/330S, Edge540T, CAP10 and Pitts Python. Pack 2 includes Sbach342, Yak54, Yak-SP55M, Christen Eagle, Spitfire Mk9, P-40E and B-17G. The DLC descriptions establish purchase/use within RC10, not a standalone OpenRC asset license or verified access to all underlying files.

### User aircraft and authoring sources

The [official free user-model catalog](https://www.ikarus.net/en/aeroflyrc10-usermodels/) supplies RC10 ZIPs for Panda, Fox, Twinstar II, Robbe Charter, Paperwing, Hawker Hunter and others. It also states that RC9 authors can convert their **source 3D geometry and textures** into RC10. This is not a guarantee that every old compiled runtime package loads directly in the new version.

The [RC10 workshop](https://www.ikarus.net/en/rc10-model-workshop/) and [Blender workshop](https://www.ikarus.net/en/aeroflyrc10-blender-workshop/) provide editable MQO/BLEND examples plus TMD/TMC and texture sources. Jean-Pierre Aria's [RC8-RC10 TMD generator](https://jaria-simulator.com/aerofly/tmdgenerator/) links an inspected [demo ZIP](https://jaria-simulator.com/aerofly/aircrafts/demo.zip) containing `demo.mqo`, `demo_generator.mqo`, BMP sources, definition variants and RC9/RC10 converter configurations. His [aircraft catalog](https://jaria-simulator.com/aerofly/) includes modern Yak54, ExtraNG, Laser260 and Edge540T examples; editable sources were not established for those specific offerings.

The source files provide a useful additional author collaboration route. They do not themselves grant cross-simulator redistribution rights. A tool that compiles into RC10 also does not demonstrate reverse conversion.

### Laboratory result 1: editable Deproni source

The official [Blender example ZIP](https://www.ikarus.net/downloads/workshops/rc10_blender_model.zip), SHA-256 `961d32f3d524eca7fab048726cec6f8ee046d5806e468c6dacbf303ee3bb3ca1`, was opened in Blender 4.3.2 with factory startup and automatic script execution disabled. Its 21 mesh objects include fuselage, wings, ailerons, elevators, rudder, wheels and propeller.

A temporary GLB contains 21 named meshes, 8 materials, 5 embedded images and 4,392 triangles, with no skins or animation clips. The original mesh input has 2,386 vertices and 2,397 polygons. This validates one author-source visual path only; TMD motion and physics do not automatically appear in glTF. Output identity is recorded in the inventory, and neither source nor derived aircraft is distributed in this repository.

### Laboratory result 2: compiled Panda to static textured GLB

This materially improves on the earlier survey's unresolved TMB/TTX status. The [official Panda ZIP](https://www.ikarus.net/downloads/rc10-user-aircraft/rc10_as-panda.zip), SHA-256 `c59ff43167ea15ca6076c830bd841f9bbdac5ca0b34986ce5414750031c53cfd`, contains TMB geometry, twelve TTX files and TMD/TMC definitions. It has no editable BLEND/MQO source or license file.

The [AeroflyFS-Native-Converter](https://github.com/RishiK-06/AeroflyFS-Native-Converter/tree/b7863b9ace57d0b0b82b7d286affd8739ff63d6c), v1.1.3, has an MIT root license and a generic TMB container-to-text parser. Although intended for Aerofly FS, its parser was **actually tested on this RC10 package**. Its bundled WASM provenance was unclear; that binary was not used. Source-built MIT-licensed `pylzham` 0.1.3 supplied LZHAM decompression instead. This decoded a compressed container; no encrypted-content or entitlement bypass was performed.

Observed stages:

1. TMB and three color TTX containers decompressed, with CRC-32 checks passing.
2. TMB exposed named mesh parts, vertex attributes, normals/UV layout, material IDs, index lists and triangle strips. All 14 parts' vertex and nondegenerate triangle counts matched their embedded declarations; index bounds matched.
3. Color textures decoded: Panda 1024x1024 BC1/DXT1 with eleven mip levels, interiors 512x512 BC1, glass 64x64 BC3/DXT5.
4. A temporary static GLB was assembled through Blender: 14 named meshes, 4,673 triangles, 3 materials and 3 embedded images. The lead independently verified its header, counts and SHA-256 `ad2164a1fc0fd2ee123b57eec4f603a60a88efba3ba987a1ec26f39c6112cd15`.
5. Re-import/render produced a recognizable orange textured Panda with decals. Measured span was 1.3200004 m, consistent with the catalog's 1.32 m.

This proves one static mesh/units/color-texture path. It does not prove general TMB version coverage, premium DLC compatibility, correct normal/specular/glass rendering, hinge animation, source flight dynamics or permission to redistribute Panda. The temporary scene builder used source positions/UVs but omitted the decoded source normals; it did not qualify every material or normal-map property. No skins or animation clips were produced.

The finished OpenRC user flow should select an authorized local package and convert inside the app. Blender here is an engineering instrument, **not a mandatory manual player step**. A production path still needs a bounded parser, vetted decompression dependency, support for observed mesh/material variants, TMD control interpretation and a separately qualified flight-data mapping. The existing MIT parser is a starting point, not an already complete aircraft importer.

## RealFlight Evolution: valuable recent catalog, unresolved compiled mesh

### Current aircraft and expansions

The [publisher's release feed](https://steamcommunity.com/app/2069310/allnews/) identifies Evolution 10.10.249 as current in November 2026. Its recent free additions include helicopters; do not describe every software update as an airplane expansion. Evolution's [base product description](https://www.realflight.com/product/realflight-evolution-rc-flight-simulator-software-only-steam-digital-download/RFL2001D.html) also advertises more than 100 models previously sold separately in expansion packs, which is catalog inclusion rather than proof that old installers work.

| Modern content | Verified delivery/version | Representative fixed-wing aircraft |
| --- | --- | --- |
| [2025 Year Content Pass](https://store.steampowered.com/app/3483210/RealFlight_Evolution_2025_Year_Content_Pass/) | All four packs released; last pack requires 10.10.193+ | Hangar9 J-3 Cub10cc, E-flite 4-Site800mm, Twin Otter1.4m, Eratix1.6m, SNJ-5 1.5m |
| [2026 Quarterly Pack 1](https://store.steampowered.com/app/4343140/RealFlight_Evolution_2026_Year_Content_Pass/) | Released; 10.10.203+ | Beechcraft RC-45J1.5m, GeeBeeR2 1m, Timber10-year1.5m, UMX Eratix450mm, UMX Viper30mmEDF, Koi F3P-A |
| 2026 Quarterly Pack 2 | Released; 10.10.215+ | Conscendo2m, Super Decathlon1.2m, UMX GeeBee510mm, V1200 1.2m2026; Las Vegas Soaring Club field |
| 2026 Quarterly Pack 3 | Released October 1; 10.10.239+ | Habu SS50mmEDF, Micro OV-10 Bronco645mm, P-51D1.5m Big Beautiful Doll, Pilatus PC-21 1.3m, Hangar9 Hawk/T-45 turbine; also a Blade helicopter |
| 2026 Quarterly Pack 4 | Still listed as a future Q4 unlock when checked | Do not count its promised content as already delivered |

The [2026 pass](https://www.realflight.com/product/realflight-evolution-2026-year-content-pass/RFL2026YCP.html) advertises 20 aircraft and two fields across the completed annual offering. That is neither 20 already released planes nor 20 verified unique meshes. DLC unlocks through Steam and requires Evolution. No purchased vendor DLC bytes were inspected, so its exact packaging, protection or extraction feasibility remains unknown; do not invent a DCK/KEX layout for those packs.

### Compatibility families that must remain separate

The publisher's [legacy compatibility chart](https://www.realflight.com/rfl-kb-rf9.html) distinguishes original Add-Ons, Expansion Packs and Mega Packs. Original Add-Ons 1-5 disks support G2/G3 but not G4-G9; separate redeveloped free versions are described for G4-G8. Expansion Packs 1-4 support G3.x, 1-6 G4.x, and all eight G5.x-G9.x. Mega Packs are listed for RF6-RF9. RF-X is excluded from those expansion/mega-pack paths. These old charts do not establish Evolution installer compatibility.

For community sharing, **EA** means an entire-aircraft package, **AV** is a variant requiring a base aircraft, and **CS** is a color scheme requiring geometry. A collection of AVs or paints is not a collection of standalone airframes. [KEmax](https://forums.realflight.com/KEmax/) and the [Blender RealFlight exporter](https://github.com/robertlong13/io_scene_realflight) create RealFlight inputs; neither is a verified KEX-to-OpenRC reader.

Evolution 10.10.203 changed imported-content protection: missing-base AV imports are rejected, and other people's imported RFX geometry cannot simply be overwritten or re-exported as an EA. Author-imported FBX work remains supported; physics/paint edits can be shared as AV/CS. Read the [publisher's explanation](https://steamcommunity.com/app/2069310/allnews/) rather than designing around an assumed export loophole.

### Actual EA versus AV inspection

The public [ArduPilot SITL_Models repository](https://github.com/ArduPilot/SITL_Models/tree/28de13e4011096a403f3cf3e0119e5062a1305d5/RealFlight) was pinned to `28de13e4011096a403f3cf3e0119e5062a1305d5`. Its aircraft files are not automatically covered by ArduPilot's software license; the inspected model paths did not supply a general asset reuse grant.

| Sample | Inspected contents | What this establishes |
| --- | --- | --- |
| [Multiplex Acro Master EA](https://github.com/ArduPilot/SITL_Models/tree/28de13e4011096a403f3cf3e0119e5062a1305d5/RealFlight/Released_Models/Planes/AcroMaster) | 1,084,370-byte ZIP with KEX, BSE, RFVEHICLE, color scheme, TGA, battery, preview and `g3x.enc` | Readable visual references and 30,995-byte plain physics/radio/config text; binary mesh not reconstructed |
| [HobbyZone AeroScout APM AV](https://github.com/ArduPilot/SITL_Models/tree/28de13e4011096a403f3cf3e0119e5062a1305d5/RealFlight/Released_Models/Planes/Aeroscout) | 51,443-byte ZIP with RFVEHICLE, JPG and `g3x.enc`; no KEX or BSE | Concrete variant lacking its own mesh; exact base not independently identified |
| [Skywalker X8 QuadPlane](https://github.com/ArduPilot/SITL_Models/tree/28de13e4011096a403f3cf3e0119e5062a1305d5/RealFlight/Released_Models/QuadPlanes/Skywalker_X8_QuadPlane) | RFX with associated FBX, BLEND and TGA source files in its CAD folder | A real author-source route exists for selected community aircraft; file revisions are not proven identical and this VTOL is outside the current Creator flight domain |

The EA and AV samples have no ZIP encrypted-member flags, but their `g3x.enc` contents were not decoded. Do not turn the outer ZIP observation into a claim that all contents are plain or all RFX formats are unprotected. AcroMaster KEX is binary and its known header/model name is insufficient to establish a geometry decoder.

The plain AcroMaster RFVEHICLE includes component span/chord, airfoil, weight, servo and deflection fields. For example, a 0.5588 m span entry belongs to a component, not necessarily the whole aircraft. Treat these as source observations with units and context; a direct name/value copy would not reproduce RealFlight's solver.

The [myergo/mike326 author catalog](https://www.catv296.ne.jp/~myergo/rf_hangar.html) provides modern acrobatic leads such as Edge540T104, ExtraNG, LaserV3, Sbach and CLIK25. Some downloads require a forum login; no account was used. A practical intermediate feature is a local RFX dependency/metadata inspector. Full visual import requires a proven KEX decoder or separately authorized original geometry.

## Other modern products

### neXt: current fixed-wing development, no demonstrated aircraft export

The [official release notes](https://www.cgm-online.com/rc-flight-simulator/download_e.html) list 2.090 dated 2026-09-29. March 2026 updates added the 0.73 m Chekker, another Pilot-RC ExtraNG2.61m livery and fixed-wing center-of-gravity behavior changes; August adjusted the Karat biplane. Other listed aircraft include Robbe Limit Pro, Rasant and Tomahawk Integral.

The [product page](https://www.cgm-online.com/rc-flight-simulator/rc-flight-simulator_e.html) advertises 26 fixed-wing models plus helicopters and multicopters, with more content through free 2.x updates. Its [forum](https://next-rc-heli-simulator.xobor.de/) explains sharing model **setup strings**. The [FAQ](https://www.cgm-online.com/rc-flight-simulator/next-faq_e.html) and [scenery workshop](https://www.cgm-online.com/rc-flight-simulator/next-scenery-construction_e.html) support custom scenery, not a demonstrated complete airplane mesh exchange format.

No public aircraft SDK, complete small aircraft source package or working reverse mesh reader was established in this bounded search. Unity release-note references and scenery AssetBundles do not prove how every airplane is stored or that it can be exported. Keep neXt as an author/vendor source opportunity, not a committed importer target yet.

### SeligSIM 2026: documented definitions, unknown OHM mesh

The [dated release notes](https://www.seligsim.com/manual/release_notes.html) identify 2026a v20.1 revision6571, released 2026-09-20. The [home page](https://www.seligsim.com/) and older download page still describe 2024.5, a site freshness discrepancy. The [2026 Getting Started guide](https://www.seligsim.com/manual/getting_started.html) says prior 2024.5 DLC is included and no separate 2026 DLC exists yet. The prior orange Pawnee DLC is a reskin, not a new underlying airframe. Older marketing distinguishes 50+ stock aircraft and about 90 variants; do not present 140+ unique meshes.

The author's [migration instructions](https://www.seligsim.com/manual/files/AIRPLANE_MIGRATION_2024_5_TO_2026_USER.md), linked from [Documentation](https://www.seligsim.com/manual/documentation.html), identify two matching aircraft folders:

- `Aircraft/FixedWing/<name>/`: physics/configuration, including `Info.cfg` and `ModelObj.cfg`.
- `Graphics/Aircraft/FixedWing/<name>/`: `.ohm` geometry and textures.
- Registration uses an AddNew marker and `Lists.cfg`; Power Tools updates the catalog.

The author says 2026 can read 2024.5 user fixed-wing files without conversion. That is an internal migration guarantee, not an OpenRC import guarantee. Generated `AirplaneSpecs.txt` and `GeometryData.txt` aid interpretation but do not specify OHM. The [Scaling Wizard](https://www.seligsim.com/manual/scaling_wizard.html) copies/tunes existing aircraft; that does not establish arbitrary external geometry import. No small OHM sample or verified decoder was obtained, and no installer was run. The owner explicitly calls the simulator free but not open source.

### Wings Simulator: useful modern foam/FPV catalog

The [official site](https://www.wings-sim.com/) advertises 32 included aircraft, with Flite Test, TBS, Strix and TBRC examples: Simple Scout, Mighty Mini Mustang/Corsair, Kraken, CaipirinhaII, Nano Goblin, Stratosurfer, Reflex and Warlock. Its [Steam page](https://store.steampowered.com/app/5158720/Wings_Simulator/) says the product has been available since 2020 but the Steam release is still Coming soon as checked.

Plane paint/decals, rates, throws and CG customization are useful features. The [tutorials](https://www.wings-sim.com/Tutorials.php) document track creation and other tools, not a verified arbitrary-aircraft source pipeline. No downloadable full aircraft SDK/source sample or separate model-expansion market was established. A modern-looking simulator does not by itself supply portable aircraft assets.

### AccuRC 2: available fixed-wing catalog, uncertain source access

The [official catalog](https://accurcsimulator.com/models/) lists Alpha40 electric/nitro, Sebart AngelS50E, AT-6 Texan, P-51 Mustang and Spitfire variants alongside its much larger helicopter offering. The [FAQ](https://accurcsimulator.com/faqs/) describes configurable parts/workbench features. The product is AccuRC2; third generation is marketing wording, not evidence of a released AccuRC3.

The catalog displays Download Blend File labels, but no actual complete fixed-wing BLEND download was verified. The read-only HTTP inspection client received 403 for that page; the rendered public text remained accessible to search. These labels therefore remain leads, not inspected editable files. The published FAQ also states a Mac fixed-wing limitation pending physics work; no current installed Mac build was tested, so do not generalize that older FAQ into verified present behavior.

No complete aircraft sample, general import/export SDK, modern fixed-wing DLC inventory or reverse geometry implementation was established. AccuRC remains below the three candidates with actual inspected asset packages.

### REFLEX XTR2: still available, with an older release and a concrete format lead

The [current download page](https://www.reflex-sim.net/download-en) still lists V6.02.0; [official news](https://www.reflex-sim.net/news-en) dates it to 2019-11-03. It is a currently sold ecosystem, but this evidence does not place it among products with verified 2026 software updates. The [features page](https://www.reflex-sim.net/features-en) advertises EDF, aerobatic/3D, gliders and retractable gear. A [model creator's catalog](https://www.catv296.ne.jp/~myergo/rmk.html) adds Edge540 and Edge580 Pro aircraft and reports demonstrations in 6.02.0, including a fix required for one model that previously worked in 5.x.

Two small community ZIPs were actually inspected. [Edge540 Superlite FREAKSHOW](https://www.catv296.ne.jp/~myergo/rmk.files/plane/edge540v3_sl_fs.zip) contains a 518,844-byte MOD and 618-byte PAR. The MOD starts with RMK V2.44.5 export metadata, readable point/surface/material/control records, then a length-delimited `TEXDATA` block containing a validated 471,062-byte 1004x1012 JPEG. [Edge580 Pro Blue](https://www.catv296.ne.jp/~myergo/rmk.files/plane/edge580pro_blue.zip) contains the same broad mixed text/binary pattern with a different embedded JPEG. This is neither an ordinary OBJ nor a wholly text format; decode records only outside the declared binary blocks.

The Edge540 PAR has mostly positional numeric values, a model reference and an external `IKARUS/Axi` sound reference; the ZIP contains no sound. Its `VERSION=5` is a file field, not proof of application-version compatibility. A [historical author tutorial](https://www.catv296.ne.jp/~myergo/rmkguide.html) explains RMK authoring and normalized geometry, but no complete current V6 format specification or decoder was established. Record semantics, scale/axes, animation and flight conversion remain open. These samples improve the importer lead without establishing coverage of other authors' packages or permission to bundle the models.

## Implementation and permission boundaries

The desired player experience is automatic local package/folder selection, dependency capture, conversion and a reviewable draft. The importer should identify simulator and version, distinguish complete aircraft from variants/paints, preserve provenance and source units, and report unsupported parts. No external manual Blender stage is part of the proposed product flow.

Recommended engineering sequence:

1. **HELI-X V11 visual adapter:** bounded OBJ/MTL/XML, scale resolution, named parts, textures and useful diagnostics against a separately cleared fixture. Then qualify XML motion and justified flight observations.
2. **Aerofly RC10 prototype:** reproduce the Panda result with an in-app data path, vetted LZHAM implementation and additional legally acquired fixtures; then extend materials, TMD controls and version coverage. Success with a simple glider does not qualify turbine, biplane, complex landing gear or premium DLC assets.
3. **RealFlight metadata and source route:** bounded RFX inspection, EA/AV/CS dependencies, selected plain fields and original author geometry where available. Gate KEX geometry support on an actual decoder and test vector.
4. **Other ecosystems:** acquire one complete authorized airplane and establish its mesh/texture/definition path before scheduling broad support.

Current Creator scope is a target domain of conventional aft-tail, single-tractor electric aircraft with a finite battery and gearless airborne/hand launch; numerical qualification remains open in the owning plan. A visual draft for a jet, biplane, glider, VTOL or retractable-gear plane is not proof of supported flight behavior. Engine-specific stabilizers, mixers, ground contact and propulsion require explicit capabilities and validation. Do not silently label an aircraft flight-ready after mesh import.

The [RealFlight EULA](https://store.steampowered.com/eula/2069310_eula_0) and HELI-X manual contain use, copying/derivative and reverse-engineering restrictions; their legal reach depends on the precise activity and applicable law. This record does not adjudicate an independent importer's legality. Buying a simulator or downloading a free airplane does not itself demonstrate a grant to redistribute its models in OpenRC. User-supplied files, independently authored compatibility code, author-source permission and stock/DLC redistribution are separate analyses. A disclaimer shifting responsibility to users is not a substitute for that analysis.

For a distributable test/catalog model, verify the geometry, textures, sounds and adapted definitions together. Stearman's GPL attribution is a promising provenance lead, not an automatic clearance of the entire HELI-X adaptation. Record required attribution/license terms and the exact permitted derivative/distribution scope. No third-party aircraft, textures, source code, render or derived GLB is included in this research commit.

## Verification and limits

Primary product/developer sources were consulted on 2026-11-17. Dates, storefront inventories and future DLC can change. The inventory distinguishes archive inspection, laboratory reconstruction, source documentation and catalog-only evidence. SHA-256 identities are reproducibility markers, not authenticity or legal clearance.

The lead inspected the actual HELI-X OBJ/material data, AcroMaster ZIP members, Aerofly experiment scripts and converter license; independently checked both GLB structures/hashes and viewed the Panda render. This validates the stated bounded observations, not a production importer. No paid DLC was acquired, protection bypassed, source simulator executed, production dependency adopted or OpenRC runtime modified. Local derived aircraft are research intermediates only. Focused Markdown/link, JSON and hash checks apply to this documentation update; no broad application test suite is justified by it.
