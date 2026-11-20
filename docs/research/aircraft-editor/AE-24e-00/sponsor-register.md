# Sponsor and collaborator asset register

**Reviewed 2026-11-19.** This is the Workshop intake record for the 17 organizations
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
| **GEMFAN** | Public README / BRANDS | Names and simplified propeller representations with brand/product links; no separate logo/CAD grant | Exact official header PNG retrieved and hashed; metadata-only public entry. Establish decal scope before promoting the artwork |
| **KONTRONIK** | Public README / BRANDS | Independently recreated products and names; no logo/CAD grant | Exact red and black screen PNGs retrieved from official downloads and hashed; metadata-only public entry. Confirm logo/decal use and select an approved variant |
| **Leomotion Drives** | Public README / BRANDS | Selected product representations; named/branded models need render approval before publication; no logo license recorded | Exact official header PNG retrieved and hashed; metadata-only public entry. Confirm exact decal treatment and the required preview review |
| **REVOC Custom** | Public README / BRANDS | Community-supporter credit, logo and link in the simulator and on GitHub; preview requested | Exact download PNG included. Strong candidate for an approved supporter treatment; confirm repeated arbitrary placement, flips and player export rather than treating a credit grant as unrestricted artwork |
| **Aloft Hobbies** | Public README / BRANDS | Forum sharing, knowledge and feedback; no brand/model/logo or financial grant | Two official-site CDN variants retrieved and hashed; metadata-only public entry. Website terms require prior express authorization for reproduction; establish applicable scope before publication |
| **OpenAI** | [README development support](../../../../README.md#development-support), BRANDS | ChatGPT Pro development support and named Codex contribution; official marks have prescribed attribution, context and modification rules | Exact official wordmark included as reference. Keep development credit; a freely modified aircraft sticker needs a separately approved treatment |
| **JETI model** | [D6-JETI-00](../../radio-input/D6-JETI-00/README.md); [existing sponsor-livery source](../../../../app/assets/vehicle-paints/avanti-s-a200/sponsors/SOURCE.txt) | Technical help and owner-reported project support. Existing baked logo source explicitly requests written confirmation before distributing builds showing it | Exact existing header logo included. Resolve that release follow-up and record editable-decals scope; technical assistance alone is not a blanket asset grant |
| **Jumper RC** | [Existing sponsor-livery source](../../../../app/assets/vehicle-paints/avanti-s-a200/sponsors/SOURCE.txt) | Owner-reported support; same written redistribution follow-up as the existing sponsor livery | Exact existing header logo included; record written intended-use and distribution scope before Workshop activation |
| **RadioLink** | [Public T16D source record](../../../../assets/ui/radiolink-t16d/README.md) | The existing public source record documents a specific simulator-image context; it does not establish a reusable Workshop logo grant | Exact 2754 × 434 transparent header PNG retrieved and hashed; metadata-only public entry. Establish precise decal scope before activation |
| **GM Propellers** | [Official website](https://gmpropellers.com/) | Public artwork/source lead only in this handoff; an accepted collaboration or decal scope is not established by the cited public evidence | Exact official header PNG retrieved and hashed; metadata-only public entry. Establish intended-use scope before activation |
| **ProModeler** | [Official website](https://www.promodeler.com/) and its [cross-linked article](https://www.promodeler.com/profiles/NPL-ProModeler-and-steering-lasers) | Public brand-source candidate only; this row establishes no collaboration, sponsorship or logo permission | A transparent 512 × 512 seal is now verified through the linked site's media record. Metadata-only entry; a standalone wordmark/vector remains unresolved |
| **FEETECH** | [Official website](https://www.feetechrc.com/) and its linked [documentation wiki](https://ftservo.github.io/ftservo-wiki/) | Public artwork-source candidate only; this row establishes no collaboration, sponsorship or logo permission | Direct manufacturer-domain 600 × 200 transparent color PNG now improves the earlier bitmap-wrapped wiki SVG. Metadata-only entry; a vector master and intended-use scope remain open |
| **Hiwonder** | [Official website](https://www.hiwonder.com/) | Public artwork-source candidate only; this row establishes no collaboration, sponsorship or logo permission | Exact path-only header SVG and social PNG retrieved and hashed; metadata-only public entry. Review dimension handling and intended-use scope before promotion |

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

## Earlier source intake, 2026-11-19

The first [technical receipt](../../../../research/aircraft-editor/sponsor-decals/logo-source-intake.json)
records **11 exact downloaded files for eight organizations**, plus one unresolved
ProModeler lead. It includes complete URLs, byte sizes, SHA-256 values, dimensions,
source variants and quality caveats. These newly located image files are not
added to the public asset pack. Its existing 12 locked images remain unchanged;
the nine organizations below retain metadata-only catalog entries. This table
preserves the first pass's findings. R2 below supplies the newer ProModeler and
FEETECH choices as well as additional variants.

| Organization | Verified source and quality | Developer handoff |
| --- | --- | --- |
| GEMFAN | [Manufacturer header](https://img03.71360.com/w3/5p3560/20251023/3bd8255a2faebfb9aa84e31300555ab5.png), 1807 × 462 transparent PNG | Exact unqueried PNG response retained; the homepage uses the same URL with a WebP query |
| KONTRONIK | [Official downloads](https://kontronik.com/en/downloads), red and black transparent PNGs, each 1772 × 263 | Keep variant identity explicit. These are raster screen files; the separately offered EPS files were not retrieved or inspected |
| Leomotion | [Official header](https://leomotiondrives.com/assets/img/logo.png), 540 × 106 transparent PNG | Preserve proportions; test the limited vertical resolution at the intended on-screen size |
| Aloft Hobbies | [Official website](https://alofthobbies.com/), 300 × 180 and 280 × 168 transparent CDN PNGs | The larger response was inferred by removing a Shopify size suffix; it is not a verified authoring master. [Terms](https://alofthobbies.com/policies/terms-of-service) require prior express authorization for reproduction |
| RadioLink | [Official header](https://www.radiolink.com/icon/radiolink_logo.png), 2754 × 434 transparent PNG | Strong source resolution; no extraction from product photography is needed |
| GM Propellers | [Official header](https://gmpropellers.com/assets/media-27e15c6f0560d7.png), 680 × 226 transparent PNG | Use the exact hash in the receipt; establish intended-use scope before activation |
| ProModeler | [Official-site lead](https://dev.promodeler.com/index.php), image retrieval returned HTTP 403 | No image bytes, dimensions or visual identity were verified. Obtain a clean original; do not substitute a banner/product photograph |
| FEETECH | [Pinned official-wiki SVG](https://github.com/ftservo/ftservo-wiki/blob/5637b7985bffb9baa3cda9d0f266be9c1714eb84/docs/assets/feetech-logo-white.svg), declared 194 × 67 | Embeds a 200 × 200 PNG and uses a white filter. This is not a clean scalable vector master; review raster quality and filter support, and prefer a better original for large marks |
| Hiwonder | [Official website](https://www.hiwonder.com/), header SVG with viewBox `0 0 472.07 57.14`; social PNG 497 × 325 | The header uses seven paths and no embedded bitmap/text. Its viewBox-only fractional dimensions are unsupported by the current pack reader. Preserve the source and review a separate raster derivative or a scoped reader extension. The social PNG has substantial whitespace and a nearly opaque background |

Availability on an official website establishes source authenticity, not the new
Workshop permission. Keep exact original bytes and the reviewed source URL after
intake; changes on a live website must not silently replace saved art.

## R2 source choices

The [R2 receipt](../../../../research/aircraft-editor/sponsor-decals/logo-variant-intake-r2.json)
adds 14 new artwork originals for six brands, one guidance document and three
original archives. Some form of logo artwork has now been located for all
17 catalog organizations; this counts ProModeler's seal as an icon, not a full
wordmark. No new image binaries are added to this public pack.

SAVOX supplies dark-background and monochrome PNG variants plus vector masters;
KONTRONIK supplies red/black EPS print masters; REVOC supplies a vector PDF.
FEETECH now has a better direct color raster, and Leomotion Drives has a small
dedicated icon. See [artwork preparation](artwork-preparation.md) for exact source
choices, brand-book/master disagreements, excluded lookalike/other-entity assets,
texture budgets and the source-to-runtime recipe. New sources do not change the
recorded relationship or permission scope above.

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

Once a treatment is established, the concrete promotion sequence is:

1. Select the exact approved source/variant from the technical receipt; compare its
   SHA-256 and retain the original without overwriting it with a derivative.
2. Put approved distributable bytes in a tracked source location with a minimal
   public source/scope record. For any prepared derivative, record its source hash,
   preparation parameters and new hash separately.
3. Fill the catalog's `source_path`, `source_sha256`, `asset_filename`, `width`,
   `height` and source revision fields. Match the actual encoded format; a filename
   suffix alone is not evidence. Resolve unsupported SVG geometry/filters before
   adding a source to this pack.
4. Run `build_catalog.py`, then its `--check`, `validate_pack.py --self-test` and
   `node check_study.cjs` from the documented working directory. Review the byte
   lock, generated catalog and exact source/scope evidence together.
5. Treat study placement and production release as separate decisions. The study
   now requires explicit `study_capabilities` for `rotate`, `flip_x`, `flip_y`,
   `repeat` and `export`, in addition to `demo_placement`. Unsupported restrictions
   (for example a prescribed aircraft or size range) still need implementation
   before activation. Capabilities are technical configuration, not proof of a grant.
