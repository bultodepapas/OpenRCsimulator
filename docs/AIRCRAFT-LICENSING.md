# Aircraft licensing and copyright guide

Research checked: **2026-10-15**. Scope: aircraft depictions, source assets, names and distribution in OpenRCsimulator. This is a practical release guide, not a legal opinion or a completed trademark/design clearance. Colombia/Andean law, US law and EU design rules are considered because development and worldwide distribution can involve different territories. A US defense is not worldwide permission. Obtain jurisdiction-specific counsel for a disputed replica or a commercial branded release.

## The practical answer

**We can build original aircraft and independently recreate many real aircraft. There is no universal requirement to buy an aircraft license just to simulate flight or reproduce functional dimensions.** However, writing every vertex ourselves does not automatically clear the aircraft's name, distinctive appearance, livery, plans, photographs or supplied assets.

Use three routes:

1. **Original aircraft:** our own design, distinctive name and artwork, with documented contributor rights. This is the simplest route for an unrestricted, commercially reusable repository.
2. **Independent replica:** our own geometry and physics from lawful factual sources, original paint, and a recorded assessment of the name and any surviving appearance rights. A real type designation may be defensible; renaming is an option, not a universal legal requirement.
3. **Licensed replica:** written permission covering the particular branding/assets and our actual distribution model, including source, forks and commercial reuse where needed.

No named aircraft below is established to be permanently impossible to include. **“Do not distribute now” means the current asset or presentation lacks the necessary clearance, not that the aircraft type is forbidden forever.** Conversely, this investigation cannot certify any third-party aircraft as “without issues” in every country.

## Aircraft decision table

These are recommended release decisions based on the evidence inspected, not newly implemented export controls. “Rename” below means a conservative presentation choice if we do not pursue branded clearance; it never clears the underlying asset by itself. Candidate replacement names also require a conflict check.

| Aircraft / family | Current evidence | What we can do | Naming and release decision |
| --- | --- | --- | --- |
| Entirely original OpenRC aircraft | New geometry, artwork and design can be contributed under explicit open terms. | Publish original work after confirming authorship, dependencies and name availability. | **Preferred low-risk route.** No aircraft-manufacturer permission needed merely because it is an airplane. No current asset is certified original solely by this category. |
| **Jensen Ugly Stik** — the aircraft meant by “Griesty”; includes glow and synthetic electric variants | [Asset guide](../assets/aircraft/ugly-stik-60/README.md) identifies Jensen plan geometry and a photo-informed classic finish. [Reference index](research/aircraft-reference-index.md) distinguishes it from Ultra Stick and MoJo. | Retain independently implemented trainer geometry and derived physics; verify the plan's terms and replace any unlicensed expressive graphics. Age and downloadable plans do not establish public-domain status. | **Conditional replica.** For the conservative route use an independently cleared trainer name and original livery. Keeping “Jensen Ugly Stik” needs a name/presentation assessment or appropriate permission. Engine changes do not reset the airframe's rights. |
| **Extra 300S .60 / GPMA0236**, currently our Great Planes reference | [Asset guide](../assets/aircraft/extra-300s-60/README.md) documents measured plan geometry, photo-adapted red/white/blue finish and a pilot derived from a plan figure. | Keep independently authored functional reconstruction where justified. Review the livery and pilot separately; an original shader can still reproduce someone else's artwork. Review both the full-size reference and the RC kit layer. | **Conditional replica; prioritize artwork review.** A generic aerobatic name and new paint remove some branding exposure. Retaining Great Planes/EXTRA branding requires a documented legal basis or permission for the relevant rights. |
| **Extra 300/S**, independently recreated from the full-size aircraft | EXTRA's [technical service page](https://extraaircraft.com/tech-service/) identifies EA 300/S and EXTRA NG separately. It is technical information, not a reproduction license. | Build our own scaled aircraft using lawful dimensions and observations, without importing kit CAD or commercial graphics. | **Possible, not automatically cleared.** A factual “Extra 300/S” depiction may be supportable after review. For the conservative route use a distinct name and artwork; assess shape rights independently. |
| **Extra NG**, including Pilot-RC or other RC adaptations | Modern full-size design and distinct RC implementations. A kit seller's right to sell its kit is not a sublicense to us. | Choose whether we are recreating the full-size type or a particular kit. Independently author geometry; check current design rights and the artwork's owner. | **Conditional; higher priority for design review.** Renaming or removing Pilot-RC does not remove an EXTRA/design-owner issue. For an exact branded kit seek the relevant permissions; otherwise create a genuinely independent aerobatic design. |
| **P-51D Mustang**, current quarter-scale model | [Asset guide](../assets/aircraft/p51d-mustang-120/README.md) documents full-size dimensions, AN 01-60-3 silhouettes and an original generic finish without unit artwork. The guide calls the three-view public domain; its exact authorship/publication basis still needs to be retained. | Strong candidate for the independent historical-replica route. Verify source status, retain original paint, and avoid kit-maker logos and proprietary CAD. | **Conditional, favorable geometry provenance. No automatic rename required.** Assess use of “P-51D Mustang” as historical identification. Boeing offers licensing if a branded route is desired; neither military origin nor age clears every mark. |
| **F4U Corsair 1/4.5** (`f4u-corsair-250`) | Owner decision F4U-13, 2026-10-23 ([DECISIONS](DECISIONS.md)), on an intellectual-property lawyer's advice. The project modelled the original aircraft from scratch, from publicly available specifications and photographs; manufacturers' RC models and plans were internal references only. | Distribute with the project; keep the original markings. | **No licence required (owner decision).** Keeps the historical name "F4U-1D Corsair 1/4.5". |
| **SebArt Avanti S A200 → Vantage Jet** | [Current asset guide](../assets/aircraft/avanti-s-a200/README.md) identifies a supplied Blender master with textures. The user describes it as inspired by other aircraft and requested its inclusion in this beta. | Preserve provenance and inventory the master and textures; the inclusion decision does not independently establish authorship or asset terms. | **User-directed beta inclusion.** Do not describe the asset as officially licensed or infer an MIT asset grant. |
| **Turbo Lumber Evolution / Turbo Timber Evolution** | The original [source manifest](../assets/aircraft/turbo-lumber-evolution/source-manifest.json) and [delivery license](../app/assets/aircraft/turbo-lumber-evolution/LICENSE.txt) preserve terms as received. On 2026-10-30 the user confirmed authority to authorize its model and source distribution in this beta. | Retain the attribution and the [beta distribution notice](../app/assets/aircraft-notices/turbo-lumber-evolution.txt) with the original license. | **Authorized for this beta's binary and source distribution.** Other uses and releases are not covered by the notice; the asset is not thereby MIT-licensed. |
| **MoonRunner X99 / Skywalker X8 r4** | The original [delivery license](../app/assets/aircraft/skywalker-x8/LICENSE.txt) preserves the terms as received. On 2026-10-30 the user confirmed authority to authorize its model and source distribution in this beta. | Retain the attribution and the [beta distribution notice](../app/assets/aircraft-notices/moonrunner-x99.txt) with the original license. | **Authorized for this beta's binary and source distribution.** Other uses and releases are not covered by the notice; the asset is not thereby MIT-licensed. |
| **HX-700 / X-Cell research helicopter** | The original [source manifest](../assets/aircraft/hx-700/source-manifest.json) records unknown provenance/license and clearance=false. The user describes the visual as inspired by other aircraft and requested its inclusion in this beta. | Preserve the original provenance record. The user's inclusion decision does not independently establish authorship or asset terms. | **User-directed beta inclusion of the existing visual.** The separate [articulated delivery](../assets/aircraft/hx-700/articulated/README.md) is excluded from standard binary presets but its tracked files appear in automatic source archives. Its provenance remains undocumented; no separate grant is established for it. Do not infer an MIT asset grant. |
| **Airliners and modern general aviation**, e.g. Airbus, Boeing, Cessna | Manufacturer names, product names, modern appearance, cockpit graphics and airline liveries can involve different owners. | Use independent functional modeling and original airline/paint identities, or license the particular branded presentation. | **Case by case.** A generic airliner is viable; an exact branded aircraft needs review or permissions. Neither all commercial types nor all real names are categorically prohibited. |
| **Ultra Stick 120 and MoJo reference packages** | [Reference index](research/aircraft-reference-index.md) records unresolved redraw/manual relationships and incomplete drawing identity. These are separate from the Jensen model. | Research lawful facts; establish authorship and terms before importing or publishing drawings/CAD. | **Unresolved source assets.** Do not treat an accessible DWG or a supplied archive as an open license. |

Physics variants inherit the visual asset's status. A synthetic battery configuration is not evidence of an independently designed airframe. The table covers the inspected aircraft families and requested additions, not a complete audit of every repository texture, historic commit or release archive.

## Which rights matter?

### Copyright: our work versus someone else's expression

US copyright excludes ideas, systems and methods, while protecting original expression. Government-work treatment under section 105 depends on authorship, not military procurement or a document being hosted by a government. A contractor's work is not automatically a US government work. Verify the exact source, edition and territorial basis before calling a drawing public domain. [US Copyright Act, sections 101–106](https://www.copyright.gov/title17/92chap1.html)

The US Copyright Office distinguishes a useful object's functional design from the drawing or photograph depicting it. This supports independent use of aircraft measurements; it does not authorize copying illustrations, photographs, mesh files or separable decorative art. A digital model is itself expressive content: the useful-article rule is not a blanket exemption for every digital replica. [Copyright Office: Useful Articles](https://www.copyright.gov/register/va-useful.html)

For this project, record separately: dimensions and performance facts; our equations and code; mesh authorship; textures and liveries; cockpit/instrument artwork; pilot figures; photographs; sounds; and source plans. Buying an RC model or taking our own photograph does not necessarily confer rights in artwork depicted on it. Credit is useful provenance, but is not a substitute for permission where permission is required.

### Trademarks, trade dress and truthful identification

The issue is not simply whether a word belongs to a brand. US law addresses confusing claims of origin, affiliation or sponsorship; it also protects qualifying trade dress and famous marks under distinct rules. Functional shape has important limits on trade-dress protection. A factual reference in research differs from using a logo as the simulator's identity or claiming an official partnership. [15 USC 1125](https://www.law.cornell.edu/uscode/text/15/1125)

Therefore, “we cannot mention Pilot-RC without authorization” is too broad. Necessary factual identification may be lawful. Our conservative release recommendation is to omit manufacturer logos and promotional branding unless cleared, use only necessary plain-text references, and avoid endorsement claims. Disclaimers help explain independence but cannot cure otherwise infringing content.

There is a meaningful route for realistic depictions: in **AM General v. Activision** (SDNY, 2020), the court rejected the challenged Humvee trademark/trade-dress claims involving Call of Duty. This supports considering expressive-use arguments, not a rule that all vehicles are free to copy. It was a specific US district-court case. [Court opinion](https://cases.justia.com/federal/district-courts/new-york/nysdce/1:2017cv08644/483511/218/0.pdf?ts=1585819322)

In **Jack Daniel's v. VIP Products** (US Supreme Court, 2023), the Court held that the special Rogers threshold does not apply when the challenged mark is being used as a designation of source for the defendant's own goods. Do not turn a realistic in-game reference into our own brand and assume the same defense applies. [Supreme Court opinion](https://www.supremecourt.gov/opinions/22pdf/22-148_3e04.pdf)

### Colombia/Andean rules and international distribution

Andean Decision 351 distinguishes expression from ideas and technical content. Decision 486 article 157 permits qualifying good-faith informational uses of signs without treating them as one's own mark, subject to its conditions, including avoiding confusion. It also regulates industrial designs, including technical-function exclusions and a ten-year registration term. These provisions support a fact-based reconstruction strategy, but do not establish that any particular aircraft passes the tests. [WIPO-hosted Decisions 351 and 486](https://www.wipo.int/edocs/mdocs/tk/en/wipo_grtkf_ic_1/wipo_grtkf_ic_1_11.pdf)

EU design reform expressly includes non-physical products and strengthens protection concerning certain design files. Digital-only use is therefore not a reliable general escape. The exact registered design, protected appearance, term, territorial scope and applicable exceptions must be checked. Do not assume a new digital depiction automatically infringes, or that the reform revives expired historical designs. [EUIPO design reform overview](https://www.euipo.europa.eu/en/designs/design-reform-hub)

Patents, copyright and trademarks protect different subject matter. A mathematical simulation of an airplane is not automatically manufacture of a patented airplane; any patent issue depends on actual claims and acts. For an old airframe, focus the investigation on surviving names, artwork and modern adaptations rather than assuming its original engineering monopoly still exists. [USPTO explanation](https://www.uspto.gov/trademarks/basics/trademark-patent-copyright)

## What changes actually help?

| Proposed change | Benefit | What it does not establish |
| --- | --- | --- |
| Change only the aircraft name | Reduces use of that wordmark in menus and marketing. | Rights in geometry, art, files or distinctive appearance are unchanged. A confusingly similar replacement can create another problem. |
| Remove logos and create a new livery | Removes specific brand/art elements when genuinely replaced. | No automatic clearance of the underlying model or its source license. Merely repainting copied artwork may retain protected expression. |
| Slightly alter the nose, tips, canopy or dimensions | Can reflect our own engineering choices. | There is no safe “change 10%/30%” rule. Small differences may leave the relevant protected appearance/expression intact. |
| Rebuild the same replica from scratch | Avoids taking someone else's mesh, topology, rig and textures if independently authored. | Reimplementation can still reproduce protected expression or appearance. Independent creation does not defeat every registered design right. |
| Use different or slightly modified plans | Can supply independent factual corroboration. | A redraw may derive from the same protected drawing. Multiple sources do not wash away their terms. |
| Design a genuinely new aircraft | Gives the strongest basis for licensing our own contribution and branding. | Still requires clean dependencies, contributor rights and checking the chosen name and any relevant third-party rights. |
| Make it free, open source or “experimental” | Helps access and collaboration. | None is a general IP exemption. Public Git hosting is distribution even without a downloadable game build. |

These are applications of the distinctions above, not quantitative legal tests. We should preserve realistic flight behavior instead of making arbitrary geometry changes solely to claim a legal percentage. For a replica, pursue a defensible replica route. For an original design, document actual independent design choices.

### Use our existing workflow in the repository's favor

Our procedural builders, authored Blender sources, metrology and per-quantity evidence already help demonstrate what we made. Improve the rights record without discarding that work:

1. Extract necessary factual measurements from lawfully accessed sources; retain citations, edition, access date and uncertainty. Avoid committing source scans, traced plan artwork or commercial CAD without a redistribution basis.
2. Cross-check geometry using independent dimensions, our observations and photographs we may use. Distinguish functional outlines from decorative contours and artwork. Do not falsely label a source-dependent reconstruction “clean room.”
3. Keep our own paint and graphics as the default. Replace a plan's pilot illustration with a cleared figure; audit packed Blender textures as carefully as the mesh.
4. Record why a plan is usable: permission, an applicable license, verified public-domain status, or use limited to unprotected facts. “Found online,” “free download,” “different plan” and “the manufacturer is gone” are insufficient.
5. Preserve true source names in provenance and technical citations. A display-name change should not erase evidence or falsify authorship. Stable internal IDs need not be renamed merely because they identify the reference; evaluate their actual presentation and use.

These steps reduce avoidable dependence on third-party expression. They do not replace legal assessment of a recognizable modern design.

## Warbirds, commercial aircraft and licensed branding

**Warbirds:** original historical geometry is often a promising starting point. However, government designations, manufacturer marks, restored-aircraft paint, nose art, squadron badges and modern RC-kit adaptations are separate questions. Do not infer that every wartime photograph or manual is public domain. Our P-51's original generic finish is a useful advantage over copying a famous restored aircraft's complete appearance.

**Boeing:** its official licensing page explicitly includes video games and flight simulators in consumer-product licensing. Its separate simulator-data program concerns access to flight/maintenance data for training devices; that is not evidence that our independently derived RC physics needs that data agreement. Boeing's [historical product record](https://www.boeing.com/content/dam/boeing/v2/company/history/pdf/Boeing_Products.pdf) includes the P-51. Use its [consumer licensing channel](https://www.boeing.com/company/licensing) for a proposed branded grant; ask about the precise names and assets rather than assuming all rights are covered.

**Airbus and other civil manufacturers:** Airbus has publicly described a licensing program for flight entertainment simulations, games, apps and add-ons. This is an available commercial route, not a court ruling forbidding independent depictions. An aircraft maker's permission does not necessarily cover an airline's logo, a cockpit supplier's graphics or third-party sounds. [Airbus simulation licensing announcement](https://www.airbus.com/en/newsroom/news/2017-04-officially-licensed-projecting-airbus-brand-and-image-in-the-computer)

**EXTRA and RC manufacturers:** distinguish the full-size aircraft, the RC manufacturer's adaptation and the livery designer. Request only rights actually needed, from parties able to grant them. Avoid assuming that permission from Pilot-RC or Great Planes would cover every underlying EXTRA right, or that EXTRA could license another company's mesh. A factual full-size reconstruction can avoid importing an RC manufacturer's creative contributions.

**SebArt:** the earlier request remains unanswered. The user's beta-inclusion decision is recorded above; it is not a manufacturer endorsement or an independent grant of model and texture rights.

## Relationship to this repository's MIT license

The root [LICENSE](../LICENSE) is MIT. It permits redistribution, modification, sublicensing and sale of covered contributions with the required notice. It cannot grant rights our contributors do not possess and does not override an asset-specific restriction. Its warranty disclaimer is not third-party clearance.

Keep these layers explicit:

| Layer | Recommended treatment |
| --- | --- |
| Our simulation code and original documentation | Continue MIT, subject to contributor ownership and any existing exceptions. |
| Our original mesh, rig, textures and generators | Obtain an explicit contributor grant and state the chosen asset license. MIT or CC0 can support broad reuse; choose deliberately rather than inferring from a file's location. |
| Third-party open assets | Preserve the exact license, attribution and notices. CC BY allows commercial adaptations with conditions; CC BY-SA adds share-alike obligations for adaptations. These do not automatically change the license of independent simulator code. |
| Noncommercial, no-derivatives or redistribution-prohibited assets | Do not present them as MIT. For the unrestricted default package, replace them or obtain broader permission; ND is unsuitable where the required adaptation cannot be shared under its terms. |
| Trademark/manufacturer permission | Keep its scope separate. Permission for this project may not authorize forks, source redistribution, resale or modifications. |

Creative Commons licenses differ materially; a free download is not necessarily open for our intended use. [Creative Commons license descriptions](https://creativecommons.org/cc-licenses/)

The practical goal is an **MIT codebase with clearly documented asset terms**, preferably a fully reusable default asset set. A restrictive optional aircraft package may be possible if its license permits that packaging and delivery, but it must remain explicitly separate and must not be included in a source archive or download that lacks permission. Optional distribution does not cure infringement.


## Permission request and release record

A useful permission request should attach the exact proposed presentation and explain:

- Independent RC entertainment simulation; aircraft name, model revision, livery, logos and any supplied references requested.
- Public source repository, editable Blender/mesh files, generated exports, binary builds, mirrors, forks and modifications.
- Free and paid redistribution, worldwide access and duration; whether downstream recipients receive rights directly or through sublicensing.
- Screenshots, videos and marketing; crash/damage simulation and user-created variations, so approval is not based on a different product.
- Required credits, quality approvals, fees, termination and treatment of already distributed versions; proof the grantor controls the rights granted.

A vague “you may use it in your simulator” is not a dependable basis for promising downstream MIT-style freedoms. If the owner will approve only this project's binaries, keep that limitation explicit and evaluate a separate package rather than relicensing their rights.

For each aircraft maintain one concise rights record beside its existing asset provenance: exact asset/source hashes; authors and licenses; source-plan basis; mesh/texture/livery permissions; proposed display name; relevant trademark/design searches by territory and goods/services; written grants or counsel's independent-use assessment; permitted distribution modes; reviewer/date and unresolved items. Use official registers such as USPTO, EUIPO and Colombia's SIC as applicable. A web search or an empty register result alone is not complete clearance, especially for unregistered rights.

Before release, review the actual archive and repository contents, including embedded textures, screenshots and bundled notices. Apply the decision to the delivered bytes, not just the catalog label. Renames or geometry changes must follow existing source pipelines and aircraft validation rules; do not hand-edit generated data or silently invalidate replay identities for a licensing change.

## Current priorities

1. Retain the beta-specific distribution notices for Turbo Lumber Evolution and MoonRunner X99 with their original attribution and terms. Further use needs its own terms.
2. Preserve the HX-700 and Vantage Jet provenance records and distinguish the user's beta-inclusion decision from independent evidence of authorship or a broader asset grant.
3. Audit Extra's photo-adapted paint and plan-derived pilot, and the Ugly Stik's plan/finish basis. Use original artwork and distinct names if selecting the conservative route.
4. Prioritize the P-51 as an independent historical replica, retaining proof for the exact AN 01-60-3 source and a name-use assessment. Apply the same process to other warbirds; do not assume all of them are rights-free.
5. For a future Extra NG or airliner, decide early between a licensed exact replica, an independently justified factual depiction and a genuinely original aircraft. Avoid spending effort on cosmetic changes that do not address the actual right.

**Release categories:** original and properly licensed assets are the clear route; recognizable independently authored replicas are conditional; renamed replicas remain conditional. The beta inclusion decisions recorded above do not independently resolve unknown provenance or grant broader rights. No rename-only shortcut resolves asset terms.
