# Phoenix RC aircraft corpus: discovery and inspection

Date: 2026-11-17 (America/Bogota). Network and probe observations continued on 2026-11-18 UTC.

Status: source discovery and research-tool observations for [AC-PX-00](../../plans/phoenix-aircraft-import.md). The production importer, GEO decoder and flight gates remain open. This record extends the [initial investigation](phoenix-2026-11-17.md) and [hardening follow-up](phoenix-hardening-2026-11-17.md); it does not replace their pinned baseline specimens.

## What this round established

- Six bulk ZIP central directories expose **1,289 candidate entry occurrences**: 746 PKG, 165 PHX, 372 MOD and six VAR. These are neither unique aircraft nor successful imports. Nested archives are not expanded.
- Twenty creator release records, including AW109, give individual model links. Two creator pages explicitly offer separate OBJ downloads; the model/OBJ pairs have not been inspected.
- Thirteen forum indices and 51 exact index-linked post leads broaden the search. One additional release/attachment link is supported by a saved original post. Current attachment access is not established.
- Twenty-five PKGs in two locally captured ZIPs were inspected: 20 match the current observed container profile; five do not. Thirteen MOD definitions parse in the observed grammar, seven do not; no MOD result is available for the five rejected containers.

Machine-readable records: [source catalog](phoenix-corpus-catalog-2026-11-17.json), [directory candidate index](phoenix-corpus-archive-index-2026-11-17.json), and [package/definition inspection receipts](phoenix-corpus-inspection-2026-11-17.json). Each has an explicit evidence scope. No third-party model assets are committed.

## Bulk archives

The first six rows are measured directory contents, not the host’s advertised aircraft counts. Reported archive lengths come from HTTP Content-Range; member payloads and CRCs were not validated by directory reads. Decimal MB/GB are used below.

| Archive and direct link | Reported size | Observed entries relevant to testing | Test value and limitation |
| --- | ---: | --- | --- |
| [AllPublic.zip](https://rc-thoughts.com/phx/AllPublic.zip) | 1.261 GB | 631 PKG + 10 nested ZIP; 642 total entries | Broad community corpus; wrappers, revisions and schemes need separate identities. |
| [Phoenix_113_Models.zip](https://rc-thoughts.com/phx/Phoenix_113_Models.zip) | 214.9 MB | 100 PHX + 13 PKG; 113 total | Legacy PHX discovery alongside PKG; no PHX support claim. |
| [Phoenix_63_Models.zip](https://rc-thoughts.com/phx/Phoenix_63_Models.zip) | 213.2 MB | 65 PHX + one directory; 66 total | Host label says 63; parent folder says 65. Names include apparent sites/tools, so aircraft classification is required. |
| [Jets.zip](https://rc-thoughts.com/phx/Jets.zip) | 141.5 MB | 40 MOD + 40 GEO + one VAR; 527 total with textures and folders | Installed-directory inputs, texture closure and variants. Names also include propeller aircraft and biplanes. |
| [Models.zip](https://flugsimulatoren.schraemli.net/Files/PhoenixRC/Models.zip) | 1.176 GB | 332 MOD, 330 GEO, 10 PKG, five VAR, 41 ZIP, six RAR; 2,471 total | Large mixed directory corpus, gliders, helicopters and other vehicles. Different MOD/GEO counts alone do not prove missing dependencies. |
| [OfficialPhoenixModels.zip](https://flugsimulatoren.schraemli.net/Files/PhoenixRC/OfficialPhoenixModels.zip) | 257.5 MB | 92 PKG + 12 directories | PKG paths split into Official 34, User-made 51 and Pending seven; filename alone does not establish provenance. |
| [Planes.zip — freakware](https://www.freakware.de/technik/Phoenix-Sim/Modelle/Planes.zip) | 63.2 MB captured | 22 PKG payloads inspected | Smaller first corpus; contains helicopters as well as airplanes. |
| [Helis.zip — freakware](https://www.freakware.de/technik/Phoenix-Sim/Modelle/Helis.zip) | Host lists 33.30 MB | Host link only | Rotorcraft boundary cases; contents still need inspection. |
| [UserModelle.zip — freakware](https://www.freakware.de/technik/Phoenix-Sim/Modelle/UserModelle.zip) | 1.261 GB | Same central-directory bytes as AllPublic.zip | Probable mirror; excluded from the core count. Whole archive byte equality is unproven. |

Primary landing pages: [RC-Thoughts](https://rc-thoughts.com/phoenix-sim/index.html), [freakware model directory](https://www.freakware.de/technik/Phoenix-Sim/Modelle/), [Swiss Phoenix page](https://www.flugsimulatoren.ch/Phoenix-RC.php), and its [alternate download directory](https://flugsimulatoren.schraemli.net/Files/PhoenixRC/). RC-Thoughts also links [AllPlanes.zip](https://rc-thoughts.com/phx/AllPlanes.zip) and [AllChoppers.zip](https://rc-thoughts.com/phx/AllChoppers.zip); range requests returned 403 here, so they are not asserted to match the freakware archives.

### Overlap and counting

The AllPublic/UserModelle central-directory SHA-256 is `0bf483cf00a931dcf943a4483ed432600551d80e5c183487cd70404357571f73` and both reported archive lengths are 1,260,906,736 bytes. This digest covers the directory only. An independent metadata review also found 54 size-and-CRC matches between the 113 and 63 packs, and matches for all 41 Jets candidates in Swiss Models. Such matches prioritize deduplication; they are not cryptographic proof of payload equality.

Keep archive occurrence, package identity, model family, revision, variant and paint scheme separate. Hash captured payloads before asserting exact duplicates. A MOD, its source PKG and a folder copy can represent the same model. A VAR can depend on an existing model. Count inspected bytes and format profiles independently from aircraft families.

## Individual creator releases

The [SupermotoXL catalog](https://supermotoxl.com/?id=76&view=category) supplies creator descriptions and direct ZIP links. Its [installation guide](https://www.supermotoxl.com/resources/guides-tutorial/3d-models-creation-and-simulator/how-to-install-custom-models-in-phoenix-rc.html) describes PKG installation. Except for the separately hosted AW109 capture, these rows are release-page evidence: the ZIP contents were not validated. Test purposes are proposed coverage, not observed runtime behavior.

| Model / release page | Model download | Proposed coverage |
| --- | --- | --- |
| [Wing Wing Z-84](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/wing-wing-z-84-phoenix-rc-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_wing_wing_z84_xl.zip) | Flying wing, elevon and pusher; creator reports 912 vertices / 1,026 faces including collision meshes. |
| [Durafly Zephyr V-70](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/durafly-zephyr-v-70-phoenix-rc-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_zephyrv70_xl.zip) | Electric ducted fan glider with V-tail, crash breakaways, and a documented revision. |
| [MACROSS DELTA VF-31J Siegfried](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-delta-vf-31j-siegfried-phoenix-rc-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf31j_xl.zip) | One of two creator-labeled simulator/OBJ pairs; two packaged size variants are described. |
| [MACROSS VF-1S Valkyrie](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-vf-1s-valkyrie-phoenix-rc-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf1s_xl.zip) | Two size variants in a package, 2m and 4m, with retracts, wing flaps, airbrakes and complex landing gear. |
| [MACROSS VF-31A Kairos](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-vf-31a-kairos-phoenix-rc-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf31a_xl.zip) | Two package variants 2m and 3m; related to the VF-31J base, useful for variant comparisons. |
| [Durafly P-51D Mustang Ferocious Frankie](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/durafly-p-51d-mustang-ferocious-frankie-phoenix-rc-simulator.html) | [ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_p51d_ff_xl.zip) | Conventional propeller warbird with two scales, a documented 1.1m and 5.4m; reported ZIP exceeds the 16 MiB download cap. |
| [MACROSS FRONTIER VF-25F Messiah](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-frontier-vf-25f-messiah-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf25f_xl.zip) | Two turbine aircraft variants, 2m and 3m, with separate named .pkg files according to the author. |
| [MACROSS PLUS YF-19 Excalibur](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-plus-yf-19-excalibur-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_yf19_xl.zip) | Forward swept wing with two size variants, each described as a .pkg file. |
| [MACROSS VF-4 Lightning III](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-vf-4-lightning-iii-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf4_xl.zip) | Two size variants with canards, twin turbines, airbrakes and retracts. |
| [MACROSS PLUS VF-11B Thunderbolt](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-plus-vf-11b-thunderbolt-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf11b_xl.zip) | Twin-scale 2m/3m fictional turbine aircraft for comparison against related models. |
| [MACROSS PLUS XF-20A Switchblade](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-plus-xf-20a-switchblade-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_xf20a_xl_3m.zip) | A distinct 3m fictional turbine aircraft ZIP; useful for mesh, pivot and material diversity. |
| [MACROSS PLUS YF-21 Sturmvogel](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-plus-yf-21-sturmvogel-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_yf21_xl.zip) | Two 2m and 3m variants with separate named .pkg files according to the author. |
| [De Havilland Canada DHC-6 Twin Otter](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/de-havilland-canada-dhc-6-twin-otter-phoenix-r-c-simulator.html) | [ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_dehavilland_dhc6_xl.zip) | Conventional twin-engine scale aircraft and a second documented revision. |
| [Dancing Wings Hobby E19 Eagle II](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/dancing-wings-hobby-eagle-ii-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_eagleii_xl.zip) | Bird-shaped electric glider with a distinctive silhouette and texture. |
| [Align T-REX 100s](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/align-t-rex-100s-micro-helicopter-phoenix-r-c-simulator.html) | [ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_aligntrex100s_xl.zip) | Rotorcraft boundary case: main and tail rotors, fixed pitch, flybar and breakable parts; author reports 6,114 vertices / 6,715 faces including collision meshes. |
| [Hobby King Pitts Special](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/hobby-king-pitts-special-bi-plane-phoenix-r-c-simulator.html) | [ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_hk_pittsspecial_xl.zip) | Aerobatic biplane; second creator-labeled simulator/OBJ pair, valuable for comparing model and source mesh if obtained. |
| [Zeta Ultra-Z Blaze](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/zeta-ultra-z-blaze-pusher-jet-phoenix-r-c-simulator.html) | [ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_ultrazblaze_xl.zip) | Hand-launched delta/pusher with elevons; author reports 4,119 vertices / 5,052 faces including collision. |
| [Sky Flight Hobby / LanXiang SR-71 Blackbird](https://www.supermotoxl.com/projects-articles/ready-to-drive-fly-models/sky-flight-hobby-lanxiang-sr-71-blackbird-phoenix-r-c-simulator.html) | [ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_sr71_blackbird_xl.zip) | Twin electric ducted fans, narrow dark fuselage, and distinctive control-surface geometry. |
| [Agusta Westland AW 109 Da Vinci REGA](https://www.flugsimulatoren.ch/Phoenix-RC.php) | [ZIP](https://www.flugsimulatoren.ch/Files/AW-109-Davinci-REGA.zip) | Three captured PKGs: v3, v4 and v4 Skids; version identity, repeated display name and rotorcraft boundary. |
| [MACROSS VF-1EX Walkure](https://supermotoxl.com/projects-articles/ready-to-drive-fly-models/macross-delta-vf-1ex-walkure-valkyrie-phoenix-r-c-simulator.html) | [ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf1ex_xl.zip) | Creator-described variant bundle; inspect internal packages and distinguish variants from unique airframes. |

### Creator-labeled OBJ companions

These two links are explicitly labeled as OBJ files by their release pages. They are promising comparison inputs for a future GEO decoder, once model/source correspondence, scale, object naming and complete dependencies are checked. The existence of an OBJ link does not establish a ready conversion or matching revision.

- **MACROSS DELTA VF-31J Siegfried:** [Phoenix ZIP](https://www.supermotoxl.com/images/downloads/sim_models/phoenix_rc_macross_vf31j_xl.zip) and [OBJ ZIP](https://www.supermotoxl.com/images/downloads/sdk/OBJ%20files%20only%20-%20Macross%20Delta%20VF-31J.zip). Creator labels separate link OBJ model files only; contents not inspected. Shell HEAD of both simulator and OBJ ZIP returned HTTP 403 in this environment.
- **Hobby King Pitts Special:** [Phoenix ZIP](https://supermotoxl.com/images/downloads/sim_models/phoenix_rc_hk_pittsspecial_xl.zip) and [OBJ ZIP](https://supermotoxl.com/images/downloads/sdk/OBJ%20files%20only%20-%20Hobby%20King%20Pitts%20Special.zip). Creator labels separate link OBJ model files only; contents not inspected. Simulator ZIP shell HEAD timed out in this environment.

The Pitts and VF-31J pages state non-commercial distribution conditions. Preserve source notices and assess the intended use before distributing models or converted assets. Download availability is not a project redistribution grant.

### Other collections and standalone formats

- [FRCFoamies collection](https://www.frcfoamies.com/simdownloads): its page describes a 2019 update including Lancaster, Highlander and MiG-29; the [installation guide](https://www.frcfoamies.com/howtoinstall) describes PKGs and credits Rick P. The download control leads to a cart URL, which was not used; no direct archive was verified.
- [SAB Goblin 700 PHX](https://rc-thoughts.com/phx/phoenixRC_goblin700.phx), [Henseleit TDR PHX](https://rc-thoughts.com/phx/phoenixRC_henseleitTDR.phx), and [T-Rex 700 3G PHX](https://rc-thoughts.com/phx/phoenixRC_trex700e3G.phx): exact links from RC-Thoughts, useful for separately qualifying legacy framing. This round did not capture these standalone payloads.
- [Historical FliteTest model index](https://forum.flitetest.com/index.php?threads/flitetest-in-phoenix-rc-model-index.27096/): retriever redirected to the forum home; keep as a historical lead. The bulk archives already list many FT candidates.
- [Historical Ultimate Phoenix Plane Pack](https://flugsimulatoren.ch/Files/UltimatePhoenixPlanePack.zip): unavailable through the web retriever in this round; not a verified working download.

## RCGroups discovery paths

These exact links came from public HTML captured on 2026-11-17. Sample ordinary requests in this round returned HTTP 202 with a JavaScript challenge; no access gate was bypassed. The curator of an index is not automatically the author of every linked model. Forum indices and attachment URLs are discovery evidence, not downloaded or qualified aircraft.

| Index | Link |
| --- | --- |
| User-Built Models for PhoenixRC — main thread | [Open index](https://www.rcgroups.com/forums/showthread.php?2382571-User-Built-Models-for-PhoenixRC) |
| Recent New Models | [Open index](https://www.rcgroups.com/forums/showpost.php?p=53763271&postcount=1) |
| Amphibious Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041553-PhoenixRC-Amphibious-Model-Index) |
| Cartoon Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4214147-PhoenixRC-Cartoon-Model-Index) |
| Civilian Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041561-PhoenixRC-Civilian-Model-Index) |
| Flying Wing Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041549-PhoenixRC-Flying-Wing-Index) |
| Glider Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041551-PhoenixRC-Glider-Model-Index) |
| Helicopter Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041547-PhoenixRC-Helicopter-Model-Index) |
| Military:  WW-I Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041559-PhoenixRC-WW-I-Military-Model-Index) |
| Military:  WW-II Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041557-PhoenixRC-WW-II-Military-Model-Index) |
| Military:  Post WW-II  Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4041555-PhoenixRC-Post-WW-II-Military-Model-Index) |
| Miscellaneous Model Index | [Open index](https://www.rcgroups.com/forums/showthread.php?4040147-PhoenixRC-Miscellaneous-Models-Index) |
| Paint Scheme Index (schemes, not independent aircraft) | [Open index](https://www.rcgroups.com/forums/showthread.php?4358919-Paint-Scheme-Index-A-through-F) |

**One additional captured release:** [FRCFoamies Su-35 v30 post](https://www.rcgroups.com/forums/showpost.php?p=43938699&postcount=3975) and its [ZIP attachment](https://www.rcgroups.com/forums/showatt.php?attachmentid=13222785). The saved author post describes a pusher-prop repaint of the FRC SU-37; it is distinct from the baseline Freewing twin-EDF Su-35. The attachment bytes were not captured in this round.

Selected index-linked targets below are deliberately varied. Their destination posts, authors, formats and attachments remain unverified; the complete 51-link list is in the catalog JSON.

| Indexed title | Exact post |
| --- | --- |
| Bristol Type 72 Amphib | [Post](https://www.rcgroups.com/forums/showpost.php?p=55232701&postcount=22635) |
| P-51D "Big Beautiful Doll" Glider | [Post](https://www.rcgroups.com/forums/showpost.php?p=55218781&postcount=22614) |
| C-141 Starlifter | [Post](https://www.rcgroups.com/forums/showpost.php?p=55173957&postcount=22545) |
| Skywing Yak-54 v3 | [Post](https://www.rcgroups.com/forums/showpost.php?p=55151369&postcount=22523) |
| Eflite Eratix 3D SWS | [Post](https://www.rcgroups.com/forums/showpost.php?p=55005621&postcount=22342) |
| ShinMaywa US-2 | [Post](https://www.rcgroups.com/forums/showpost.php?p=54994991&postcount=22316) |
| Swift S1, Hacker | [Post](https://www.rcgroups.com/forums/showpost.php?p=54972519&postcount=22260) |
| Eflite Conscendo 2.0m | [Post](https://www.rcgroups.com/forums/showpost.php?p=54926663&postcount=22159) |
| Aermacchi M-346 | [Post](https://www.rcgroups.com/forums/showpost.php?p=52323769&postcount=16748) |
| B-1B Lancer | [Post](https://www.rcgroups.com/forums/showpost.php?p=53939413&postcount=20155) |
| B-2 Spirit | [Post](https://www.rcgroups.com/forums/showpost.php?p=43680077&postcount=3872) |
| C-17A Globemaster III | [Post](https://www.rcgroups.com/forums/showpost.php?p=50041621&postcount=8123) |

## Actual package observations

The unchanged research code at `6f2b05000bd72e8dd5ef4939924115c114c06914` inspected captured bytes. ZIP member reads checked CRCs. The existing package probe validated its observed framing and member hashes; MOD bytes were sliced from the validated reconstructed body and checked against those hashes before parsing. No package paths were extracted onto the filesystem and no model code, installer or simulator was executed.

| Captured archive | PKG observations | MOD observations |
| --- | --- | --- |
| Planes.zip | 22 inspected; 17 observed-profile, five outside profile | Ten parsed; seven outside grammar; five not reached |
| AW-109-Davinci-REGA.zip | Three inspected; all three observed-profile | All three parsed |

Full captured archive SHA-256 values:

- Planes.zip: `e59a722798df2d024fe60b93238ace6099e96f669f7fbedb2991423cdf3fdeca` (63,166,915 bytes).
- AW109: `9c4aa7b935fbea92cc208ac183a248f7bcebebfd66013dbe1e526119c8e3f196` (8,020,104 bytes).

### Immediate regression specimens

| Specimen inside Planes.zip | Observed result | Follow-up |
| --- | --- | --- |
| A6M Zero, F-16, F-18 turbine PKGs | Container header numeric string `1.0` is outside the current strict profile | Determine its actual framing before adding an explicit profile. Do not relabel the header as a simulator version. |
| Turbine MIG 31.pkg; typhoon3.pkg | Probe reports `zero padding limit exceeded` | Inspect bounded remaining bytes first. The diagnostic does not prove all bytes are zero or the package is corrupt. |
| Carbon-Z Yak, Carbon-Z Cub, H9 Inverza, KDS Agile, Hirobo Quark, Mini Titan, Raptor E700 | Container inspected; MOD is outside the observed text grammar, with binary-looking prefixes | Keep as opaque-definition cases. A first line-ending diagnostic does not justify rewriting bytes or interpreting the input as ordinary text. |
| Harrier, B-52H, C-5, P-47D, RareBear, two F-14 packages, Great Lakes biplane, P-38, Su-37 | Container inspected and MOD grammar parsed | Candidate definition corpus; geometry, semantics and complete conversion still need independent checks. |
| AW109 v3, v4 and v4 Skids in the separate ZIP | Container and MOD grammar parsed; all use display name AW109 | Distinguish exact package/revision and structural target; do not key records by display name. Rotorcraft support remains a separate gate. |

The unchanged probe profiles were retained. This discovery pass did not loosen parsers to force acceptance of new specimens. Su-37, Carbon-Z Yak and AW109 v4 overlap the earlier baseline, and AW109 revisions are not three different aircraft families.

## Suggested acquisition and test order

1. **Small captured corpus:** start with the two inspected ZIPs and their 25 PKG observations. Preserve accepted and unsupported cases; use the latter to specify diagnostics and future profiles.
2. **Folder inputs:** use Jets.zip to qualify directory closure, material/texture resolution, variants and cancellation on a manageable collection. Then expand to Swiss Models. Matching metadata suggests substantial overlap, so hash selected content before adding duplicate fixtures.
3. **Community scale:** use AllPublic.zip for nested wrappers, naming collisions, schemes and revision selection. Suggested names from its directory include `Tiny Trainer 3CH V07.pkg`, `Tiny Trainer 4CH V08.pkg`, `FT Simple Cub Floatplane v10.pkg`, `FT Corsair v08.pkg`, `Discus 2c v06.pkg`, `Twin Otter v15.pkg`, and `FRC Highlander v10.pkg`. These names establish candidates, not their internal features.
4. **Legacy and mixed content:** sample the 113 and 63 packs independently. Classify PHX as model, site, tool or other before choosing a reader; never assume the PKG grammar from the Phoenix brand.
5. **Geometry reference pairs:** acquire the Pitts and VF-31J OBJ/model pairs through their normal creator links when accessible. Confirm correspondence before treating a source mesh as a decoder oracle.
6. **New releases and special layouts:** follow amphibian, glider, flying-wing and recent-model indices. Capture source post, author, revision, exact bytes and rights evidence with each chosen specimen.

Record each stage independently: link found, directory listed, bytes captured, container parsed, definition parsed, geometry decoded, preview admitted and flight qualified. Source type or file extension alone cannot advance a stage. Use existing AC-PX resource, dependency, provenance and lifecycle gates.

## Verification and limits

The directory count arithmetic, package/definition totals, probe source hashes, candidate row schema, local documentation links and unchanged baseline inventory were checked before publication. A separate reviewer checked misleading pack labels, overlap and the distinction between listing, payload inspection and importer support. This is a metadata/documentation change; no runtime or parser code changed, and no application test suite was warranted.

The recorded 26 selected-member range attempts all returned 403, so no payload checks are claimed for those candidates. Directory reads remain independently evidenced. Download access may differ by request or later date; retain host pages as recovery links rather than guessing replacement paths. The catalog carries unverified and historical leads explicitly. Public availability or discontinuation does not establish redistribution rights.
