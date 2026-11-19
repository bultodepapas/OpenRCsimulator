# Sponsor and collaborator asset register

**Reviewed 2026-11-18.** This is the Workshop intake record for the 14 organizations
identified in the inspected project acknowledgments, source assets and official
website leads. It is not a claim that every organization is a financial
sponsor or that the list covers future agreements. The source of current public
acknowledgment scope remains [`site/BRANDS.md`](../../../../site/BRANDS.md) and the
linked project records.

## Organization-by-organization handoff

| Organization | Evidence of relationship | Existing scope relevant to this task | Decal handoff / remaining action |
| --- | --- | --- | --- |
| **Savox** | Public README, BRANDS and [D6-SAV-00](../../servos/D6-SAV-00/README.md) | Product representations authorized; official media-kit images available | Exact original color logo included as a reference. Confirm editable player-decal and redistribution scope; preserve brand-book proportions/clear space |
| **SonicModell** | Public README / BRANDS | Appearance, names and branding of covered models including Skyhunter, with the recorded conditions | Exact header logo included. Extend scope before putting it on unrelated aircraft or making it freely reusable/exportable |
| **Hitec RCD** | Public README / BRANDS | Published servos may be featured with official product links; no separate general logo license is documented | Exact footer logo included. Confirm decal scope. The original `.png` is actually WebP; this pack uses `.webp` with the same bytes |
| **FLYWING** | Public README / BRANDS | Covered names/exterior models/color schemes; logo acknowledgment expressly covers README/website. Model terms include attribution, disclaimer and revocation | Exact storefront logo included as reference. Do not expand website attribution to player stickers automatically; confirm new use and track withdrawal status |
| **GEMFAN** | Public README / BRANDS | Names and simplified propeller representations with brand/product links; no separate logo/CAD grant | Official header-image source identified; metadata-only entry. Obtain approved artwork and decal scope before adding playable art |
| **KONTRONIK** | Public README / BRANDS | Independently recreated products and names; no logo/CAD grant | Official PNG/EPS download page identified; metadata-only entry. Confirm logo/decal use and select an approved variant |
| **Leomotion Drives** | Public README / BRANDS | Selected product representations; named/branded models need render approval before publication; no logo license recorded | Official PNG source identified; metadata-only entry. Confirm exact decal treatment and the required preview review |
| **REVOC Custom** | Public README / BRANDS | Community-supporter credit, logo and link in the simulator and on GitHub; preview requested | Exact download PNG included. Strong candidate for an approved supporter treatment; confirm repeated arbitrary placement, flips and player export rather than treating a credit grant as unrestricted artwork |
| **Aloft Hobbies** | Public README / BRANDS | Forum sharing, knowledge and feedback; no brand/model/logo or financial grant | Named/link acknowledgment and metadata-only intake. Obtain artwork and usage scope before a playable logo |
| **OpenAI** | [README development support](../../../../README.md#development-support), BRANDS | ChatGPT Pro development support and named Codex contribution; official marks have prescribed attribution, context and modification rules | Exact official wordmark included as reference. Keep development credit; a freely modified aircraft sticker needs a separately approved treatment |
| **JETI model** | [D6-JETI-00](../../radio-input/D6-JETI-00/README.md); [existing sponsor-livery source](../../../../app/assets/vehicle-paints/avanti-s-a200/sponsors/SOURCE.txt) | Technical help and owner-reported project support. Existing baked logo source explicitly requests written confirmation before distributing builds showing it | Exact existing header logo included. Resolve that release follow-up and record editable-decals scope; technical assistance alone is not a blanket asset grant |
| **Jumper RC** | [Existing sponsor-livery source](../../../../app/assets/vehicle-paints/avanti-s-a200/sponsors/SOURCE.txt) | Owner-reported support; same written redistribution follow-up as the existing sponsor livery | Exact existing header logo included; record written intended-use and distribution scope before Workshop activation |
| **RadioLink** | [Public T16D source record](../../../../assets/ui/radiolink-t16d/README.md) | The existing public source record documents a specific simulator-image context; it does not establish a reusable Workshop logo grant | Metadata-only standalone-logo intake. Obtain an approved logo and precise decal scope; do not crop a mark from a transmitter photograph and infer broader permission |
| **GM Propellers** | [Official website](https://gmpropellers.com/) | Public artwork/source lead only in this handoff; an accepted collaboration or decal scope is not established by the cited public evidence | Metadata-only candidate. Obtain a clean original and public scope record before activating a player decal |

The register distinguishes publicly recorded relationships from artwork/source
leads. A listed organization is not automatically an accepted sponsor or a
playable decal. Only public repository records and official sites support the
published entries; private correspondence and derived private summaries are
excluded. No outreach was sent for this task.

## Included image pack

Eight external brand images are copied **unchanged** from the existing repository
into the small research pack. OpenRC's existing master and three original geometric
fixture SVGs provide four usable interaction-study entries. The
[asset lock](../../../../research/aircraft-editor/sponsor-decals/asset-lock.json)
is authoritative for complete source and output SHA-256 values and dimensions.

| Image | Source dimensions | Pack handling |
| --- | --- | --- |
| Savox color mark | 4167 × 1417 | PNG original, full clear-space canvas retained |
| SonicModell header | 350 × 59 | PNG original; limited source resolution is explicit |
| Hitec footer | 255 × 94 | Actual WebP bytes retained; filename extension corrected in the copy |
| FLYWING storefront | 600 × 173 | PNG original |
| REVOC Custom | 2000 × 420 | PNG original |
| JETI model | 542 × 150 | Indexed PNG with transparency retained |
| Jumper RC | 658 × 256 | PNG original with alpha retained |
| OpenAI wordmark, black | SVG viewBox 1212 × 542 | Original vector and spacing retained |

These files are research/attribution references, not a new freely licensed logo
collection. The branded entries have `demo_placement=false` and
`workshop_release_status=scope_confirmation_needed`. The study does not put
unconfirmed marks onto an aircraft. This distinction is an asset-readiness field,
not a reason to delay engineering with the supplied project/test artwork.

The JETI/Jumper originals live under a `.gdignore` directory, but their existing
paint generator bakes them into the Verde Neón Carbono textures. Their source
permission follow-up therefore concerns those builds too; do not claim that
ignoring the source files makes the baked marks absent from runtime. This branch
does not alter the existing paint or resolve its release review.

## Official source candidates for missing images

| Organization | Official source to use for intake |
| --- | --- |
| GEMFAN | [Manufacturer](https://www.gemfanhobby.com/) and [header image](https://img03.71360.com/w3/5p3560/20251023/3bd8255a2faebfb9aa84e31300555ab5.png?ct=webp) |
| KONTRONIK | [Official downloads](https://kontronik.com/downloads), [red PNG](https://kontronik.com/wp-content/uploads/2023/03/kontronik_rgb.png), [black PNG](https://kontronik.com/wp-content/uploads/2023/03/kontronik_rgb_schwarz.png) |
| Leomotion | [Manufacturer](https://leomotiondrives.com/) and [official logo](https://leomotiondrives.com/assets/img/logo.png) |
| Aloft Hobbies | [Official website](https://alofthobbies.com/); a standalone approved original was not located in the bounded review |
| RadioLink | [Official website](https://www.radiolink.com/en/) and [T12D page](https://www.radiolink.com.cn/en/t12d); product photography is not a standalone logo |
| GM Propellers | [Official website](https://gmpropellers.com/); a standalone approved original is still needed |

Availability on an official website establishes source authenticity, not the new
Workshop permission. Keep exact original bytes and the reviewed source URL after
intake; changes on a live website must not silently replace saved art.

## Promotion checklist for the maintainer/developer

For each catalog entry record: intended in-game placement, allowed aircraft,
approved artwork/variants, proportional resize and rotation, any flip/recolor
restrictions, clear space, required credits/product links, public-repository and
distributed-build rights, player screenshot/export rights, allowed derivatives,
revocation/version behavior and any required final preview. Store the written
record privately and a minimal public scope summary with the asset. All artwork
stays outside the simulator code's MIT grant unless separately licensed that way.

The maintainer can approve an intended treatment through the existing relationship
process. Engineering should consume that explicit record, not infer approval from
a successful download, an earlier product-model permission or this planning branch.
