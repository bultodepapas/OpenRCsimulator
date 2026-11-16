# Software, aircraft assets and partner licenses

Reviewed 2026-11-16. This is an **operational licensing and release checklist**, not a legal opinion, an automatic grant of rights, or proof that any particular asset is cleared. It does **not** change an existing copyright owner's license, existing contributor rights, or previous distribution agreements. For uncertain designs, trademarks, reciprocal licensing, or commercial contracts, obtain qualified legal advice before release.

## Read this first: MIT code does not mean MIT aircraft

- **Software:** Original OpenRC Simulator software is published under the repository's [MIT license](../LICENSE), subject to contributor ownership and file-specific third-party notices. Preserve its exact license text; do not append bespoke restrictions to it.
- **Assets:** Aircraft meshes, Blender/CAD files, liveries, textures, sounds, photographs, fonts, landscapes, logos and branding **can have different owners and terms**. A public path, an accessible download, the absence of a license file, and a Github “MIT” badge do **not** establish a transferable MIT license for every file.
- **Bundled games:** The binary/ZIP, its data packs and the repository's automatically generated source archives are different distribution surfaces. Every distributed file needs rights covering the **actual recipients, formats, territory, versions and uses**. A permission to use a plane “in the game” is not necessarily permission to publish its editable GLB on GitHub.
- **Trade names and designs:** Rights to a 3D mesh, a manufacturer's name/logo, a particular paint scheme, and a full-scale/RC design may belong to different parties. A model author cannot automatically license another company's trademark or someone else's art.
- **Documentation is not magic:** A new notice does not revoke rights already granted or turn restricted material into freely licensed material. Existing commits, forks and release archives may already expose tracked data; moving a file later does not undo prior distribution.

This is a **mixed-license project**: make a positive claim only for the exact material and rights verified. Describe it publicly as *open-source simulator software with separately licensed assets*; do not promise every aircraft or asset is open source.

For aircraft-specific identity, trademark and existing-model decisions, continue using [AIRCRAFT-LICENSING.md](AIRCRAFT-LICENSING.md). For geometry, pivots and deliverables, use [BLENDER-AIRCRAFT-DELIVERY.md](BLENDER-AIRCRAFT-DELIVERY.md).

## License and packaging decision matrix

| Input | Public GitHub source + generated source archives | Public binaries / game packs | Action |
| --- | --- | --- | --- |
| Original OpenRC software, cleared MIT contributions | Yes, with MIT notice | Yes, with notices | Preserve MIT and third-party dependency licenses. |
| Original asset expressly CC0 / CC BY / MIT / similarly permissive | Only after verifying provenance, coverage, required credits and any third-party contents | Usually, subject to exact terms | Record exact asset license and rights holder. |
| CC BY-SA or GPL asset | Conditional: check the version, source/attribution obligations, adaptation and combination issues | Conditional: comply with all applicable terms | Review separately; do not presume it relicenses all independent program code or that bundling solves copyleft. |
| CC BY-NC, non-commercial-only or “free to print” | **No by default** for an unrestricted downstream/commercial distribution policy | **No by default** | Obtain a separate written commercial/redistribution grant or replace. |
| CC BY-ND when transformation is needed, “personal use”, no-redistribution or no-license | **No** unless a separate grant covers our actual use | **No** unless separately authorized | Do not infer commercial or derivative rights from downloads. |
| Partner-owned, proprietary, simplified *demo* aircraft | **Only if the written license explicitly permits public raw/editable source, forks and downstream redistribution** | Only for separately authorized release modes | Two packaging options below; no blanket claim that MIT covers the demo. |
| Manufacturer marks and product liveries | Permission for exact use where necessary | Permission for exact use where necessary | Document independently from the mesh license. |
| Unverified owner, attribution, embedded resource or scope | **Hold** | **Hold** | Research rights; do not merge or ship pending evidence. |

**CC0** may waive copyright rights to the extent possible, but trace provenance; **CC BY** requires appropriate attribution; **CC BY-SA** requires compatible ShareAlike for adaptations; **NC** and **ND** have material limitations. See the exact license and version, not merely “Creative Commons.” Packaging a resource separately does not automatically defeat copyleft, attribution, or any other conditions.

## Two viable arrangements with a commercial aircraft designer

### A. Public-source demo asset (best for reproducible community builds)

The creator retains their *manufacturing master*. They grant a **specific license for the reduced game model only**: exterior shell and basic textures, independent moving control surfaces, suitable pivots, light geometry for Godot; no internal manufacturing structures or printable engineering files. The agreement must permit us and downstream recipients, as applicable, to store, download, modify, fork and redistribute the **simplified** GLB/BLEND (plus included textures) in public source archives, community builds and possibly paid releases.

Preferred terms when offered voluntarily: a clearly attributed open content license such as **CC BY 4.0** for the exact game asset. Alternatively, a **written bespoke non-exclusive grant** can cover the agreed uses, but then the asset should **not** be described as open-source/open-content unless the actual terms meet that definition. Retain the agreement and its limits with the asset record.

A public demo must be treated as *actually redistributable*. An “unprintable” shell can still be copied, converted or reverse-engineered; never promise it cannot be reconstructed.

### B. Restricted optional aircraft pack (when the designer will not authorize public source)

OpenRC code remains public, but the proprietary asset is **not committed, mirrored or included in public source archives**, including asset caches, Git LFS objects, example bundles or tagged versions. Use a private licensed supply path and a documented optional installation/packaging mechanism, or an independently licensed replacement in reproducible public builds.

A **separate agreement** must specify whether the designer allows game-binary distribution, paid/free release, downloads, embedded/compiled resources, extraction risk, updates, refunds and user access. Godot `.pck` packaging or encryption is not a substitute for actual rights or a guarantee against extraction. If the agreement bars delivery of extractable geometry, the requested packaging may be impractical and requires negotiation.

This option needs **release-engineering changes and an asset supply mechanism**; this document does **not** assert they exist today. Do not move partner assets into an existing public path as a quick workaround.

## What OpenRC requests from partners

A game asset is **not** a manufacturing model. For initial discussions, request only:

- Exterior fuselage, wings, tail, canopy and clearly recognizable silhouette; a lawful, lightweight paint scheme.
- Separate ailerons, elevator, rudder and applicable flaps, propeller, wheels, retracts or wing-fold parts, with usable hinges/pivots.
- Model scale and basic dimensions, author/rights-holder identity, license scope, and GLB/FBX or editable simplified Blender source **if those specific files may be licensed**.
- OpenRC will handle flight physics, control mapping, integration, gameplay and per-aircraft optimization.

Do **not** request master CAD, STEP/SolidWorks production designs, printable STL components, internal ribs/spars, servo fittings, construction tolerances, confidential electronics or detailed commercial textures merely to make the aircraft fly in the simulator. Exact geometry and verification requirements live in the [Blender delivery guide](BLENDER-AIRCRAFT-DELIVERY.md).

**Partner-facing explanation (English):**

> OpenRC Simulator's software is MIT-licensed, but aircraft models and other creative assets may use separate, expressly documented licenses. We are not asking for manufacturing-ready CAD or printable STL files. We only need a simplified, game-ready **exterior visual shell** with independently moving flight controls. You keep your full commercial product and all rights not expressly granted. For a model publicly included on GitHub, we need specific permission to modify and redistribute the simplified asset and its simplified editable source, including forks and potential commercial releases. If you prefer to keep the asset proprietary, we can instead discuss a separately licensed optional pack; that route requires suitable distribution rights and technical arrangements and is not automatically available.

## Mandatory per-asset rights record

For each imported or partner-provided aircraft, create or link a manifest beside the existing provenance/source package. Record:

1. **Identity:** aircraft/model ID, version, owner(s), origin URL, author(s), date, exact source/derived file names and SHA-256 hashes.
2. **Component scope:** mesh, rig, textures, liveries, fonts, sounds, photos, logos; list mixed licensors separately.
3. **License:** full name/version/SPDX identifier where appropriate, exact terms/URL, required credits, modification notices and separately supplied license text. Preserve any existing notice.
4. **Grant evidence:** written permission from someone with authority, agreement reference/location, date and territory, approved uses, release/version scope, duration, termination and rights of modification.
5. **Distribution rights, separately marked:** public repository (raw files), source archives and forks; free binary; commercial binary; optional downloadable pack; generated screenshots/video; source availability; permitted redistribution by recipients.
6. **Project readiness:** Blender/GLB technical review, public-asset eligibility, marketing/branding clearance, build exclusions, reviewer/date and outstanding questions.

An asset with uncertain provenance or an unavailable rights record remains **NOT CLEARED** for new distribution. Internal experimentation is not proof of a publication right. An earlier beta-specific waiver is not blanket authorization for later tags.

Do not store private negotiations or personal correspondence publicly without consent. Keep confidential proof of permission securely, and publish a non-sensitive summary identifying the scope.

## Release checklist — no clearance from a file extension or folder name

1. Review every new/changed distributed byte in **public Git history, branches/tags, GitHub-generated ZIP/TAR source archives, release ZIPs, Godot exports, CI artifacts, downloadable packs and previews**. Git LFS is not a permission mechanism.
2. Confirm each included asset's exact version/hash, license and intended distribution mode; do not assume a website label covers independently sourced textures.
3. Include required license notices, attribution and modifications in a retrievable credits/notice document in public source **and in the downloadable game** where required. Preserve engine/Godot and third-party notices.
4. Keep restrictive/uncleared materials out of the public source and public builds until rights are established; re-check optional partner binary licenses separately.
5. Review trademarks, names, liveries, promotional screenshots and community workshop/repaint permissions.
6. Verify the complete generated package and source archive, not only the intended `app/assets/` folder. Document release/tag and reviewer.
7. Do not treat previous publication as retroactive clearance. If a historical release or file has unresolved rights, escalate for owner/legal review and a release remediation plan.

### Known OpenRC records needing reconciliation

The current [aircraft legal guide](AIRCRAFT-LICENSING.md) documents beta-specific authorizations for **Turbo Lumber Evolution** and **MoonRunner X99**, while their delivered `LICENSE.txt` files still have earlier “NOT YET SET” language. The same guide records provenance/rights uncertainty for **HX-700** and other individual materials. **Do not infer** that these notices authorize every later version, source fork, commercial pack, or right to sublicense. Inventory subsequent written permissions and **which published versions actually contain each asset**, then resolve any gaps with the rights holder and release manager. This statement is a documentation risk, **not** a determination that a particular release is unlawful.

## Primary references and precedent

- [Choose a License — Non-software licenses and mixed projects](https://choosealicense.com/non-software/) — explicitly scoped licenses for code, media and other material.
- [Godot — Complying with licenses](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html) — engine MIT and game/third-party asset notices.
- [Godot — Exporting packs, patches, and mods](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html) — optional PCK/ZIP packs, distribution and copying risks.
- [GitHub — Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) and [source archives](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives) — repository licensing and distributed snapshots.
- [Creative Commons — License types](https://creativecommons.org/cc-licenses/), [FAQ](https://creativecommons.org/faq/) — BY, SA, NC, ND and adaptation rules.
- [SPDX — Handling license info](https://spdx.dev/learn/handling-license-info/) and [REUSE FAQ](https://reuse.software/faq/) — per-file identification and retaining license texts.
- [0 A.D. project overview](https://play0ad.com/game-info/project-overview/) — code GPL, content CC BY-SA.
- [OpenMW FAQ](https://openmw.org/faq/) — open-source engine with separately controlled game assets.
