# How other open games update

**DT-UPD-00 follow-up · 2026-11-17 · same research branch.**
[Active plan](../../../plans/github-updates.md) · [Reuse and experiment briefs](reuse-spikes.md) ·
[Machine-readable source ledger](survey-evidence.json) · [Player help](player-help-draft.md).

This follow-up adds **27 distinct repositories: 20 game/game-engine projects and 7 supporting tools**, with **115 distinct commit-pinned source, workflow, documentation or license files** plus the additional guidance below. These cases are additional to the initial 44-entry source ledger; older Sparkle/Velopack/AppImage studies are not counted again. Supporting feed and dependency repositories do not inflate the 27-case total.

## Method and evidence limits

Each case traces a specific mechanism at an exact source revision, records what it actually does, and states an OpenRC design implication. Observed means code/configuration inspection; documented means an upstream statement; the OpenRC decision is our inference. Source HEADs are not proof that published binaries have those exact bits. Naev and Hedgewars are explicitly identified as mirrors. No third-party game/updater was executed and no OpenRC delta savings or native installation behavior was measured.

A notification, a content updater, a package pipeline and an executable installer solve different problems. Missing behavior in a cited flow is not a repository-wide absence claim. License observations concern the cited code, not all dependencies/assets; no third-party implementation is imported in this branch. OpenRC is MIT-licensed, so any future copied source or linked component needs deliberate compatibility, attribution and redistribution review.

## Comparison index

| Case | Project | Mechanism inspected |
| --- | --- | --- |
| G01 | DDNet | Optional in-game per-file application |
| G02 | Mindustry | Bleeding-edge Java self-update |
| G03 | Unciv | GitHub archives and native Windows installer upgrades |
| G04 | Warzone 2100 | Signed expiring announcement feed with GitHub Pages publication |
| G05 | OpenTTD | Release orchestration and checksums |
| G06 | OpenRCT2 | Cached GitHub check, changelog and browser handoff |
| G07 | SuperTux | Configurable small GitHub version notice |
| G08 | SuperTuxKart | Consent-gated news and platform release packaging |
| G09 | Luanti | Asynchronous ContentDB content updates |
| G10 | OpenRA | Optional version notice and separate content installer |
| G11 | Endless Sky | Mutable continuous release and separate platform packaging |
| G12 | Cataclysm Dark Days Ahead | Per-build prerelease publication and save-risk guidance |
| G13 | Cataclysm Bright Nights | Nightly publication retry and manual update guidance |
| G14 | Battle for Wesnoth | Versioned add-on full/update packs |
| G15 | OpenMW | Side-by-side installs with shared player data |
| G16 | ScummVM | Native Sparkle and WinSparkle integration |
| G17 | The Powder Toy | Whole-executable replacement with OS-specific handoff |
| G18 | Shattered Pixel Dungeon | GitHub release discovery and browser handoff |
| G19 | Naev | Separate internal data artifact and platform assembly |
| G20 | Hedgewars | Protocol compatibility notice and separate macOS Sparkle adapter |
| U01 | Wharf | Block-based cross-file delta and output validation |
| U02 | Butler | Offline diff/apply with checkpointed staging |
| U03 | librsync | Detached basis signature, delta and output file |
| U04 | casync | Content-defined chunk index and reusable store |
| U05 | HDiffPatch | Streaming binary/file-tree delta engine |
| U06 | tough | Native Rust TUF client and tuftool publisher |
| U07 | python-tuf | Reference TUF metadata/client and maintainer tooling |

## What changes for OpenRC

The game remains the interface, GitHub remains the distributor, and complete packages remain the correctness baseline. The new evidence makes reuse more concrete: compare maintained TUF before standardizing a custom trust protocol, compare native frameworks before owning installation code, and benchmark HDiffPatch/Butler rather than inventing a patcher. Keep reconstruction separate from activation and preserve the exact release publisher already in OpenRC.

The most useful negative evidence concerns partial replacements, unsigned content hashes, a post-commit verification step, mutable release publication, stale trust state and shared player data. The [qualification briefs](reuse-spikes.md) turn those observations into specific experiments and [T63–T82](validation.md#survey-derived-qualification-cases) extend the acceptance matrix.

## G01 DDNet

**Repository:** ddnet/ddnet · **Reviewed commit:** 07693dc68335798c06e15c73a9102656cf8ce8e3.

**Observed:** The build defaults automatic updating off and update notices on. With the updater enabled, the menu exposes download, failure and restart states. HTTPS metadata lists files to fetch/remove; filenames depend on platform. Downloaded files enter an update directory, then libraries/executables receive partial .old backups and individual replacements. Unsaved editor work or an online session changes restart behavior.

**OpenRC decision:** Reuse explicit states and restart timing. The inspected flow does not establish authenticated package digests, a complete multi-file rollback, or recovery after every interrupted replacement. Its project-hosted endpoint is outside our hosting design. A compiled updater's existence also does not prove the default distributed build enables it. Do not copy per-file live replacement as the transaction for native libraries and embedded PCKs.

**License observation:** zlib-style code license; asset terms differ.

**Primary evidence:**

- [src/engine/client/updater.cpp](https://github.com/ddnet/ddnet/blob/07693dc68335798c06e15c73a9102656cf8ce8e3/src/engine/client/updater.cpp#L47).
- [src/game/client/components/menus_start.cpp](https://github.com/ddnet/ddnet/blob/07693dc68335798c06e15c73a9102656cf8ce8e3/src/game/client/components/menus_start.cpp#L182).
- [CMakeLists.txt](https://github.com/ddnet/ddnet/blob/07693dc68335798c06e15c73a9102656cf8ce8e3/CMakeLists.txt#L119).
- [license.txt](https://github.com/ddnet/ddnet/blob/07693dc68335798c06e15c73a9102656cf8ce8e3/license.txt).

## G02 Mindustry

**Repository:** Anuken/Mindustry · **Reviewed commit:** c2f74b91a7f2591c5bb795c987f09988558d4d6b.

**Observed:** The update controller is active for non-Steam bleeding-edge builds; checks are additionally gated by initialization, platform and settings. It queries a separate GitHub build repository, chooses a desktop/server JAR, shows progress/cancellation, launches the new Java process and copies the JAR to the old path. The server path saves state and relies on an external restart script.

**OpenRC decision:** Reuse explicit preview eligibility and cancellation. This is not evidence that Mindustry's ordinary stable channel uses the same mechanism. The reviewed flow does not verify a publisher signature or show transactional rollback. JVM/JAR replacement assumptions do not transfer to a large native executable, loaded DLLs, receipts and a complete Godot release. A new process starting is not a successful OpenRC Home acknowledgement.

**License observation:** GPLv3 code license.

**Primary evidence:**

- [core/src/mindustry/net/BeControl.java](https://github.com/Anuken/Mindustry/blob/c2f74b91a7f2591c5bb795c987f09988558d4d6b/core/src/mindustry/net/BeControl.java#L23).
- [core/src/mindustry/ui/fragments/MenuFragment.java](https://github.com/Anuken/Mindustry/blob/c2f74b91a7f2591c5bb795c987f09988558d4d6b/core/src/mindustry/ui/fragments/MenuFragment.java#L98).
- [core/src/mindustry/core/Version.java](https://github.com/Anuken/Mindustry/blob/c2f74b91a7f2591c5bb795c987f09988558d4d6b/core/src/mindustry/core/Version.java#L10).
- [LICENSE](https://github.com/Anuken/Mindustry/blob/c2f74b91a7f2591c5bb795c987f09988558d4d6b/LICENSE).

## G03 Unciv

**Repository:** yairm210/Unciv · **Reviewed commit:** 82edba7216ae98319be36f09acc3661ede23c6c4.

**Observed:** The release workflow packages platform ZIPs, JARs and an MSI, distinguishing release and test tags. WiX uses a stable upgrade code, detects newer versions and normally refuses downgrades. Its installed shortcut supplies an AppData directory; the desktop application otherwise defaults its data directory to the current directory.

**OpenRC decision:** An optional per-user installer deserves comparison with portable-folder replacement if it simplifies lifecycle while preserving direct game launch. Installation and mutable data need explicit separate paths for every entry route, including direct executable launch. These files demonstrate packaging/installer policy, not an in-game authenticated updater or crash rollback. A WiX checksum attribute is not an independent publisher-signature trust chain. Preserve OpenRC's existing user-data identity instead of assuming an installer shortcut alone solves it.

**License observation:** MPL-2.0 except separately noted components.

**Primary evidence:**

- [.github/workflows/buildAndDeploy.yml](https://github.com/yairm210/Unciv/blob/82edba7216ae98319be36f09acc3661ede23c6c4/.github/workflows/buildAndDeploy.yml#L192).
- [.github/workflows/unciv.wxs](https://github.com/yairm210/Unciv/blob/82edba7216ae98319be36f09acc3661ede23c6c4/.github/workflows/unciv.wxs#L5).
- [desktop/src/com/unciv/app/desktop/DesktopLauncher.kt](https://github.com/yairm210/Unciv/blob/82edba7216ae98319be36f09acc3661ede23c6c4/desktop/src/com/unciv/app/desktop/DesktopLauncher.kt#L88).
- [README.md](https://github.com/yairm210/Unciv/blob/82edba7216ae98319be36f09acc3661ede23c6c4/README.md#L29).

## G04 Warzone 2100

**Repository:** Warzone2100/warzone2100 · **Reviewed commit:** a954eb2f1873eb20e510be67e6c01628ed387c36.

**Observed:** The client pins a public key and verifies byte-exact signed JSON through libsodium. Cached information must match the build, signature and expiry. The feed generator sets a 25-hour validity period; a daily workflow signs with an Actions secret and publishes to Pages. Channel/build conditions determine a notification and browser link.

**Boundary:** On the last network source, parseable invalid/expired information can still produce a notice using a fixed fallback URL. Valid signed links are checked by accepted scheme, not a GitHub host allowlist. The inspected flow does not bind binary hashes, install packages, persist a monotonic accepted feed version, or establish signing-key compromise recovery.

**OpenRC decision:** Reuse static signed metadata, explicit channel eligibility and expiry as concepts. An announcement fallback cannot authorize execution. Prefer a maintained trust protocol for key/version lifecycle; enforce authenticated artifact identity and fail-closed installation. Scheduled renewal and client clocks are operational dependencies. Older still-valid metadata can replay within its freshness window.

**License observation:** Game licensing varies by file (GPL family); independent EmbeddedJSONSignature verifier is MIT.

**Primary evidence:**

- [src/updatemanager.cpp](https://github.com/Warzone2100/warzone2100/blob/a954eb2f1873eb20e510be67e6c01628ed387c36/src/updatemanager.cpp#L388).
- [src/urlhelpers.cpp](https://github.com/Warzone2100/warzone2100/blob/a954eb2f1873eb20e510be67e6c01628ed387c36/src/urlhelpers.cpp#L75).
- [Warzone2100/update-data/ci/generate_updates_json.py](https://github.com/Warzone2100/update-data/blob/8a8c40f850ef134c607d402002d9a3ced85b8f06/ci/generate_updates_json.py#L140).
- [Warzone2100/update-data/.github/workflows/generate_updates_json.yml](https://github.com/Warzone2100/update-data/blob/8a8c40f850ef134c607d402002d9a3ced85b8f06/.github/workflows/generate_updates_json.yml#L38).
- [past-due/EmbeddedJSONSignature/src/EmbeddedJSONSignature.cpp](https://github.com/past-due/EmbeddedJSONSignature/blob/2a571b0cbe8f8bdeacb02361fcf8be7c687f7778/src/EmbeddedJSONSignature.cpp#L144).
- [past-due/EmbeddedJSONSignature/include/EmbeddedJSONSignature.h](https://github.com/past-due/EmbeddedJSONSignature/blob/2a571b0cbe8f8bdeacb02361fcf8be7c687f7778/include/EmbeddedJSONSignature.h#L1).
- [Warzone2100/update-data/.github/workflows/schedued_updates.yml](https://github.com/Warzone2100/update-data/blob/8a8c40f850ef134c607d402002d9a3ced85b8f06/.github/workflows/schedued_updates.yml#L1).
- [README-LICENSING.md](https://github.com/Warzone2100/warzone2100/blob/a954eb2f1873eb20e510be67e6c01628ed387c36/README-LICENSING.md).

## G05 OpenTTD

**Repository:** OpenTTD/OpenTTD · **Reviewed commit:** 8164fde864149aba7d8eef0ff294c871717725f3.

**Observed:** Maintainer instructions classify beta/RC releases; workflows coordinate source and platform builds before upload. A CDN workflow emits SHA-256 and legacy checksum sidecars. A Windows workflow uses configured signing credentials for installers.

**OpenRC decision:** Adopt coordinated publication and explicit channel labels while keeping our exact source/asset verification. A digest next to a package does not independently authenticate it. This inspected pipeline uses a separate CDN and configured signing service, so its deployed hosting/certificate assumptions do not meet our GitHub-only, zero-new-spend design automatically. These workflows do not establish native in-game application or rollback; the separate content browser must not be counted as executable updating.

**License observation:** GPL-2.0 code license; inspect applicable component notices.

**Primary evidence:**

- [docs/releasing_openttd.md](https://github.com/OpenTTD/OpenTTD/blob/8164fde864149aba7d8eef0ff294c871717725f3/docs/releasing_openttd.md#L41).
- [.github/workflows/release.yml](https://github.com/OpenTTD/OpenTTD/blob/8164fde864149aba7d8eef0ff294c871717725f3/.github/workflows/release.yml#L13).
- [.github/workflows/upload-cdn.yml](https://github.com/OpenTTD/OpenTTD/blob/8164fde864149aba7d8eef0ff294c871717725f3/.github/workflows/upload-cdn.yml#L23).
- [COPYING.md](https://github.com/OpenTTD/OpenTTD/blob/8164fde864149aba7d8eef0ff294c871717725f3/COPYING.md).
- [.github/workflows/release-windows.yml](https://github.com/OpenTTD/OpenTTD/blob/8164fde864149aba7d8eef0ff294c871717725f3/.github/workflows/release-windows.yml#L94).

## G06 OpenRCT2

**Repository:** OpenRCT2/OpenRCT2 · **Reviewed commit:** 683f454670c5776a6d6e9e8966b6762f7c4b42dd.

**Observed:** An asynchronous startup check calls GitHub's latest-release endpoint and throttles successful checks to 24 hours. The code reads tag/name/body, exposes a notification and changelog, and opens the release download website. The inspected comparison is based on a tag prefix rather than a demonstrated complete semantic version ordering.

**OpenRC decision:** Preserve nonblocking checks, useful notes and an always-reachable manual route. This is discovery and handoff, not automatic archive installation. Use OpenRC's tested stable/preview ordering and authenticated descriptor rather than copying the prefix comparison or treating /latest as a complete multi-channel policy. A failed check must remain distinguishable from a successful Current result.

**License observation:** GPLv3 source headers.

**Primary evidence:**

- [src/openrct2/Version.cpp](https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2/Version.cpp#L74).
- [src/openrct2/Context.cpp](https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2/Context.cpp#L1194).
- [src/openrct2-ui/windows/Changelog.cpp](https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/src/openrct2-ui/windows/Changelog.cpp#L146).
- [licence.txt](https://github.com/OpenRCT2/OpenRCT2/blob/683f454670c5776a6d6e9e8966b6762f7c4b42dd/licence.txt).

## G07 SuperTux

**Repository:** SuperTux/supertux · **Reviewed commit:** 2975428aef94fdc3d6b6ec04cc94ec7a98b116eb.

**Observed:** Network and release checking default off in the inspected configuration. When enabled, startup reads a small version file from a separate GitHub repository, compares it with compiled version information and offers a website link. Windows packaging creates portable ZIPs and MSI artifacts for draft tagged releases.

**OpenRC decision:** Reuse explicit network/check preferences and a lightweight announcement. A single latest field and version inequality do not prove upgrade direction, architecture or channel compatibility. This path does not install binaries or demonstrate signed metadata/rollback. Keep OpenRC's proposed automatic-check default as a product choice, not an alleged industry rule; download and restart consent remain separate.

**License observation:** GPL-3.0-or-later in inspected source.

**Primary evidence:**

- [src/supertux/main.cpp](https://github.com/SuperTux/supertux/blob/2975428aef94fdc3d6b6ec04cc94ec7a98b116eb/src/supertux/main.cpp#L858).
- [src/supertux/gameconfig.cpp](https://github.com/SuperTux/supertux/blob/2975428aef94fdc3d6b6ec04cc94ec7a98b116eb/src/supertux/gameconfig.cpp#L99).
- [.github/workflows/windows.yml](https://github.com/SuperTux/supertux/blob/2975428aef94fdc3d6b6ec04cc94ec7a98b116eb/.github/workflows/windows.yml#L179).
- [SuperTux/addons/ver_info.nfo](https://github.com/SuperTux/addons/blob/54937b677232e66746c07e799ac9d571892eba81/ver_info.nfo).
- [LICENSE.txt](https://github.com/SuperTux/supertux/blob/2975428aef94fdc3d6b6ec04cc94ec7a98b116eb/LICENSE.txt).

## G08 SuperTuxKart

**Repository:** supertuxkart/stk-code · **Reviewed commit:** b2a9f223326422aa2dd4eea28319b0c5115fde03.

**Observed:** Background news loading waits for internet permission, caches messages and supports version-conditioned notices. Windows CI produces architecture-labelled ZIPs/installers and prerelease classifications; macOS also publishes a ZIP. Add-on revisions concern tracks and karts.

**OpenRC decision:** Keep network activity visible and off the UI thread; separate content compatibility from the game release. The inspected news path uses an add-on service and does not establish signed executable delivery, installation or rollback. Package labels are useful, but the authoritative OS/CPU identity must be checked against actual artifacts. Workshop updates must never become an implicit executable-update mechanism.

**License observation:** GPL-3.0-or-later code; media have separate terms.

**Primary evidence:**

- [src/addons/news_manager.cpp](https://github.com/supertuxkart/stk-code/blob/b2a9f223326422aa2dd4eea28319b0c5115fde03/src/addons/news_manager.cpp#L76).
- [src/addons/news_manager.cpp](https://github.com/supertuxkart/stk-code/blob/b2a9f223326422aa2dd4eea28319b0c5115fde03/src/addons/news_manager.cpp#L545).
- [.github/workflows/windows.yml](https://github.com/supertuxkart/stk-code/blob/b2a9f223326422aa2dd4eea28319b0c5115fde03/.github/workflows/windows.yml#L151).
- [COPYING](https://github.com/supertuxkart/stk-code/blob/b2a9f223326422aa2dd4eea28319b0c5115fde03/COPYING).

## G09 Luanti

**Repository:** luanti-org/luanti · **Reviewed commit:** 8bb14e85d21a09d37961ed97548f6a9f71349422.

**Observed:** The menu queries content releases for mods, games and texture packs using engine/protocol compatibility, caches successful information for 24 hours, and selects installed identifiable writable content. Downloads/extraction use temporary locations, but installation deletes the old target before copying the new content; errors are reported without a complete rollback in the inspected functions.

**OpenRC decision:** Reuse asynchronous status, compatibility filtering and the distinction between engine and user content. ContentDB is an external service and its content installer does not prove engine self-update. Do not adopt delete-before-copy for an executable release or allow the updater to prune Workshop files. Absence of signature checks in these functions is scoped evidence, not a claim about every Luanti subsystem.

**License observation:** LGPL-2.1-or-later in updater files; media terms differ.

**Primary evidence:**

- [builtin/mainmenu/content/update_detector.lua](https://github.com/luanti-org/luanti/blob/8bb14e85d21a09d37961ed97548f6a9f71349422/builtin/mainmenu/content/update_detector.lua#L16).
- [builtin/mainmenu/content/contentdb.lua](https://github.com/luanti-org/luanti/blob/8bb14e85d21a09d37961ed97548f6a9f71349422/builtin/mainmenu/content/contentdb.lua#L29).
- [builtin/mainmenu/content/pkgmgr.lua](https://github.com/luanti-org/luanti/blob/8bb14e85d21a09d37961ed97548f6a9f71349422/builtin/mainmenu/content/pkgmgr.lua#L613).

## G10 OpenRA

**Repository:** OpenRA/OpenRA · **Reviewed commit:** b4d95a56717d8d0070f195e343f6c2728ce87900.

**Observed:** A setting controls the background version notice. A project endpoint distinguishes outdated/unknown/playtest states. A separate content installer streams to a temporary file, supports cancellation/retry, optionally checks SHA-1, extracts configured entries and removes written files on some errors. Packaging distinguishes x64/arm64 and setup/portable variants.

**OpenRC decision:** Reuse clear status and transport controls, with authenticated SHA-256 and complete staging. Removing files written during a failed extraction is not proof that overwritten originals were restored. Project-specific endpoints and optional content checks do not satisfy the GitHub-only application trust contract. Keep all platform and format choices explicit in the release descriptor.

**License observation:** GPL-3.0-or-later source headers.

**Primary evidence:**

- [OpenRA.Mods.Common/WebServices.cs](https://github.com/OpenRA/OpenRA/blob/b4d95a56717d8d0070f195e343f6c2728ce87900/OpenRA.Mods.Common/WebServices.cs#L17).
- [OpenRA.Mods.Common/Widgets/Logic/MainMenuLogic.cs](https://github.com/OpenRA/OpenRA/blob/b4d95a56717d8d0070f195e343f6c2728ce87900/OpenRA.Mods.Common/Widgets/Logic/MainMenuLogic.cs#L235).
- [OpenRA.Mods.Common/Widgets/Logic/Installation/DownloadPackageLogic.cs](https://github.com/OpenRA/OpenRA/blob/b4d95a56717d8d0070f195e343f6c2728ce87900/OpenRA.Mods.Common/Widgets/Logic/Installation/DownloadPackageLogic.cs#L162).
- [packaging/windows/buildpackage.sh](https://github.com/OpenRA/OpenRA/blob/b4d95a56717d8d0070f195e343f6c2728ce87900/packaging/windows/buildpackage.sh#L67).

## G11 Endless Sky

**Repository:** endless-sky/endless-sky · **Reviewed commit:** 0ccd5b9af613dc6da179763eb3beeb4208852af0.

**Observed:** The continuous workflow force-moves a tag and replaces platform assets individually; some upload steps continue after errors. Separate release builds create platform-specific archives/installers. Source separates resources from the user's saves/preferences/plugins.

**OpenRC decision:** Keep mutable channel selection separate from immutable artifact identity. Existing OpenRC exact-name/hash/source verification is a stronger foundation than treating a moving tag as completion. Promote authenticated discovery only after every required public artifact is verified. Preserve user:// outside installed generations. A stable-versus-development policy and source path separation are useful precedents; these inspected files do not establish an in-game self-installer or complete atomic publication.

**License observation:** GPL-3.0-or-later source headers.

**Primary evidence:**

- [.github/workflows/cd.yaml](https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/.github/workflows/cd.yaml#L182).
- [.github/workflows/cd_release.yaml](https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/.github/workflows/cd_release.yaml#L69).
- [source/Files.cpp](https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/source/Files.cpp#L145).
- [docs/CONTRIBUTING.md](https://github.com/endless-sky/endless-sky/blob/0ccd5b9af613dc6da179763eb3beeb4208852af0/docs/CONTRIBUTING.md#L85).

## G12 Cataclysm Dark Days Ahead

**Repository:** CleverRaven/Cataclysm-DDA · **Reviewed commit:** 81697c422b6246c6bee5779064c04f4186e488aa.

**Observed:** The workflow creates a timestamped experimental release before matrix builds finish uploading platform assets. It records the source commit and distinguishes package variants. One Android matrix row names its artifact android-x64 while selecting arm64. The in-game message explains stable/experimental tradeoffs and save risk.

**OpenRC decision:** A visible GitHub Release can still be incomplete. Keep the signed channel pointer last and verify exact target metadata and actual CPU architecture. Filename substring matching cannot authorize installation. Explain preview compatibility and preserve player records, while qualifying old/new writers independently. The cited workflow and guidance do not demonstrate client-side signatures or native update rollback.

**License observation:** Repository states CC BY-SA 3.0, with separately licensed components.

**Primary evidence:**

- [.github/workflows/release.yml](https://github.com/CleverRaven/Cataclysm-DDA/blob/81697c422b6246c6bee5779064c04f4186e488aa/.github/workflows/release.yml#L1).
- [data/motd/en.motd](https://github.com/CleverRaven/Cataclysm-DDA/blob/81697c422b6246c6bee5779064c04f4186e488aa/data/motd/en.motd#L24).
- [build-scripts/windist.ps1](https://github.com/CleverRaven/Cataclysm-DDA/blob/81697c422b6246c6bee5779064c04f4186e488aa/build-scripts/windist.ps1#L56).
- [LICENSE.txt](https://github.com/CleverRaven/Cataclysm-DDA/blob/81697c422b6246c6bee5779064c04f4186e488aa/LICENSE.txt).

## G13 Cataclysm Bright Nights

**Repository:** cataclysmbn/Cataclysm-BN · **Reviewed commit:** 9c0b7e7c9efa0153e0903aa36d0683bf41211a25.

**Observed:** The canonical repository is cataclysmbn/Cataclysm-BN. Its nightly workflow creates a dated prerelease against a source SHA and retries asset upload when fewer than 15 assets exist. Build jobs identify platforms and perform selected package checks. The manual distinguishes stable/nightly, recommends save backups and separates reserved base data from user modifications.

**OpenRC decision:** Preserve resumable publishing, but check exact expected identities rather than only an asset count. Fifteen wrong or stale assets are still fifteen assets. Base-game files and user-owned content need separate ownership, including assisted installation. Backups and a version smoke check do not prove that a native updater can recover or that an old executable can safely write a new profile.

**License observation:** Repository lists CC BY-SA 3.0; component/script terms require specific inspection.

**Primary evidence:**

- [.github/workflows/release.yml](https://github.com/cataclysmbn/Cataclysm-BN/blob/9c0b7e7c9efa0153e0903aa36d0683bf41211a25/.github/workflows/release.yml#L1).
- [.github/workflows/build.yml](https://github.com/cataclysmbn/Cataclysm-BN/blob/9c0b7e7c9efa0153e0903aa36d0683bf41211a25/.github/workflows/build.yml#L26).
- [docs/en/install/install.md](https://github.com/cataclysmbn/Cataclysm-BN/blob/9c0b7e7c9efa0153e0903aa36d0683bf41211a25/docs/en/install/install.md#L3).
- [LICENSE.txt](https://github.com/cataclysmbn/Cataclysm-BN/blob/9c0b7e7c9efa0153e0903aa36d0683bf41211a25/LICENSE.txt).

## G14 Battle for Wesnoth

**Repository:** wesnoth/wesnoth · **Reviewed commit:** d95858d3638d87c89a415aeb7ce02997179a8b90.

**Observed:** The add-on manager distinguishes local-only, equal, upgradeable and locally newer versions and protects locally published/version-controlled content. The server can send a complete pack or add/remove lists. The incremental client validates names, applies removals/additions and explicitly leaves hash verification as a TODO in the inspected path.

**OpenRC decision:** Protect local ownership and make content version state understandable. An add/remove list is insufficient for executable updating: require exact-base and final complete-release authentication, constrained paths and an isolated candidate. This is a dedicated add-on service, not GitHub-only game self-update. Do not infer rollback or integrity from the term update pack.

**License observation:** GPL-2.0-or-later source headers.

**Primary evidence:**

- [src/addon/state.cpp](https://github.com/wesnoth/wesnoth/blob/d95858d3638d87c89a415aeb7ce02997179a8b90/src/addon/state.cpp#L28).
- [src/addon/client.cpp](https://github.com/wesnoth/wesnoth/blob/d95858d3638d87c89a415aeb7ce02997179a8b90/src/addon/client.cpp#L470).
- [src/gui/dialogs/addon/manager.cpp](https://github.com/wesnoth/wesnoth/blob/d95858d3638d87c89a415aeb7ce02997179a8b90/src/gui/dialogs/addon/manager.cpp#L863).

## G15 OpenMW

**Repository:** OpenMW/openmw · **Reviewed commit:** 77eec0471802676324fb014d4d465ea652a8ec27.

**Documented/observed:** The installation manual directs users to GitHub Releases and describes separate version directories with shared saves/config. Windows source puts user data outside the executable directory. Packaging builds installers and draft prereleases.

**OpenRC decision:** Side-by-side generations are a useful recovery topology, but their shared profile is an independent compatibility boundary. OpenMW's compatibility statement does not qualify OpenRC's preferences, Workshop objects or flight logs. Retain old binaries without copying an old whole profile over newer data. Account for expanded generations and archive cache in disk budgeting. The reviewed files do not demonstrate automatic rollback or a safe downgrade after an incompatible migration.

**License observation:** Project identifies GPLv3; check individual files before reuse.

**Primary evidence:**

- [docs/source/manuals/installation/install-openmw.rst](https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/docs/source/manuals/installation/install-openmw.rst#L4).
- [.github/workflows/windows.yml](https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/.github/workflows/windows.yml#L159).
- [components/files/windowspath.cpp](https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/components/files/windowspath.cpp#L83).
- [LICENSE](https://github.com/OpenMW/openmw/blob/77eec0471802676324fb014d4d465ea652a8ec27/LICENSE).

## G16 ScummVM

**Repository:** scummvm/scummvm · **Reviewed commit:** ed3502c5216cc244c0428eff255cffb57bc96ee8.

**Observed:** A common interface exposes checking, enablement/unsupported state and intervals. Windows initializes WinSparkle and posts a normal window-close request when installation asks for shutdown. macOS delegates to Sparkle and its bundle configuration pins an EdDSA key. The inspected Windows integration does not independently establish its full signature configuration.

**OpenRC decision:** This is strong evidence for using an existing native installer adapter while the game owns consent and graceful exit. It does not qualify stock Godot startup integration, Windows portable ZIP application, Linux support, macOS sibling receipts or recovery on our machines. Evaluate exact current framework versions and the existing Mac signing posture; preserve authenticated package admission at the adapter boundary.

**License observation:** GPL-3.0-or-later source headers; framework terms are separate.

**Primary evidence:**

- [backends/updates/win32/win32-updates.cpp](https://github.com/scummvm/scummvm/blob/ed3502c5216cc244c0428eff255cffb57bc96ee8/backends/updates/win32/win32-updates.cpp#L37).
- [backends/updates/macosx/macosx-updates.mm](https://github.com/scummvm/scummvm/blob/ed3502c5216cc244c0428eff255cffb57bc96ee8/backends/updates/macosx/macosx-updates.mm#L37).
- [dists/macosx/Info.plist](https://github.com/scummvm/scummvm/blob/ed3502c5216cc244c0428eff255cffb57bc96ee8/dists/macosx/Info.plist#L73).
- [common/updates.h](https://github.com/scummvm/scummvm/blob/ed3502c5216cc244c0428eff255cffb57bc96ee8/common/updates.h#L37).

## G17 The Powder Toy

**Repository:** The-Powder-Toy/The-Powder-Toy · **Reviewed commit:** dc5de9c0aa345a2b5e02e08a1111c2d0565de485.

**Observed:** The updater downloads and bzip2-decompresses a complete executable into memory. POSIX writes an adjacent file, changes mode, renames it over the executable and execs it. Windows renames the running executable, writes/starts the new one and later removes the old executable. Its inspected checks cover response/format/decompression, not a complete authenticated multi-file package.

**OpenRC decision:** OS-specific replacement and restart behavior is real; a one-file path cannot establish coherent native-library/PCK/receipt replacement. Whole-payload memory buffering is unsuitable to assume for our roughly 1.5 GB archives. A failed write or launch needs a tested reachable recovery route, not just leftover renamed files. Study the handoff, while retaining independent trust, streaming and complete generations.

**License observation:** GPLv3 license file; component notices apply.

**Primary evidence:**

- [src/gui/update/UpdateActivity.cpp](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/dc5de9c0aa345a2b5e02e08a1111c2d0565de485/src/gui/update/UpdateActivity.cpp#L27-L111).
- [src/common/platform/PosixProc.cpp](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/dc5de9c0aa345a2b5e02e08a1111c2d0565de485/src/common/platform/PosixProc.cpp#L40-L68).
- [src/common/platform/Windows.cpp](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/dc5de9c0aa345a2b5e02e08a1111c2d0565de485/src/common/platform/Windows.cpp#L313-L395).
- [LICENSE](https://github.com/The-Powder-Toy/The-Powder-Toy/blob/dc5de9c0aa345a2b5e02e08a1111c2d0565de485/LICENSE).

## G18 Shattered Pixel Dungeon

**Repository:** 00-Evan/shattered-pixel-dungeon · **Reviewed commit:** 57a4e06a4caf162446d1c28caa7983f0493fecf0.

**Observed:** The GitHub update service filters prereleases and platform eligibility, extracts an internal numeric version from release-body text and opens the chosen release page. Desktop builds include that service. One SSLProtocolException branch reports no update found rather than connection failure.

**OpenRC decision:** Reuse discovery/installation separation and explicit preview policy. Put machine-readable identity in authenticated metadata rather than a changelog regex. Distinguish failed checks from Current in our UI; preserve offline play and manual GitHub access. This source does not download/apply desktop patches or establish automatic rollback. The TLS error mapping is a concrete negative fixture for truthful status, not a recommendation to suppress errors.

**License observation:** GPLv3 license file; asset/dependency terms differ.

**Primary evidence:**

- [services/updates/githubUpdates/src/main/java/com/shatteredpixel/shatteredpixeldungeon/services/updates/GitHubUpdates.java](https://github.com/00-Evan/shattered-pixel-dungeon/blob/57a4e06a4caf162446d1c28caa7983f0493fecf0/services/updates/githubUpdates/src/main/java/com/shatteredpixel/shatteredpixeldungeon/services/updates/GitHubUpdates.java#L38-L151).
- [desktop/build.gradle](https://github.com/00-Evan/shattered-pixel-dungeon/blob/57a4e06a4caf162446d1c28caa7983f0493fecf0/desktop/build.gradle#L112-L128).
- [LICENSE.txt](https://github.com/00-Evan/shattered-pixel-dungeon/blob/57a4e06a4caf162446d1c28caa7983f0493fecf0/LICENSE.txt).

## G19 Naev

**Repository:** naev/naev · **Reviewed commit:** 65cf3a39b892614c003ac13d24e43855e98fa36b.

**Observed:** The inspected GitHub repository is a mirror of an upstream now on Codeberg. Its workflow separately archives ndata as an internal handoff; a deployment script combines that content with Windows binaries/DLLs, while using an AppImage and macOS app bundle elsewhere. The script targets itch and other workflow paths serve additional distribution channels.

**OpenRC decision:** Internal content/runtime separation can reduce redundant work, but this does not prove separate end-user patch delivery. Study build assembly while retaining GitHub-only publication. Externalizing OpenRC's PCK still requires composite runtime/replay identity, native compatibility and a full fallback. A mirror or historical workflow is evidence for a mechanism, not a promise about current release operations.

**License observation:** Generally GPLv3 code with contribution-specific later-version terms; assets separately licensed.

**Primary evidence:**

- [LICENSE](https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/LICENSE).
- [.forgejo/workflows/naev_release.yml](https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/.forgejo/workflows/naev_release.yml#L211-L254).
- [utils/ci/itch/ItchDeploy.sh](https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/utils/ci/itch/ItchDeploy.sh#L110-L124).
- [meson.build](https://github.com/naev/naev/blob/65cf3a39b892614c003ac13d24e43855e98fa36b/meson.build#L83-L98).

## G20 Hedgewars

**Repository:** hedgewars/hw · **Reviewed commit:** 8923d31ee92c115154a0aa30167fe38969535f1d.

**Observed:** The official GitHub repository is a mirror of Mercurial. Server code keeps latest-release and earliest-compatible protocol values and chooses an old-client download message. A distinct macOS Objective-C++ adapter delegates background/manual checking to Sparkle.

**OpenRC decision:** Compatibility with a protocol is different from exact game/build identity. Use a clear newer-version notice and platform-specific capability boundary. Neither the server message nor the small Mac adapter establishes Windows/Linux deltas, coherent receipt replacement or a GitHub-only installed solution. Treat the mirror's pinned source as an integration precedent, and qualify the exact framework independently.

**License observation:** GPLv2 code per README; assets have separate terms.

**Primary evidence:**

- [README.md](https://github.com/hedgewars/hw/blob/8923d31ee92c115154a0aa30167fe38969535f1d/README.md#L113-L138).
- [gameServer/CoreTypes.hs](https://github.com/hedgewars/hw/blob/8923d31ee92c115154a0aa30167fe38969535f1d/gameServer/CoreTypes.hs#L289-L319).
- [gameServer/Actions.hs](https://github.com/hedgewars/hw/blob/8923d31ee92c115154a0aa30167fe38969535f1d/gameServer/Actions.hs#L86-L105).
- [QTfrontend/util/platform/SparkleAutoUpdater.mm](https://github.com/hedgewars/hw/blob/8923d31ee92c115154a0aa30167fe38969535f1d/QTfrontend/util/platform/SparkleAutoUpdater.mm#L21-L54).

## U01 Wharf

**Repository:** itchio/wharf · **Reviewed commit:** c844818e4eba2bafea8b054063a95c9b2e06ef7f.

**Observed:** The reviewed revision is the exact dependency used by the Butler case, rather than a different newer HEAD. Its block library reuses matching data across files/renames and uses MD5 as a matching hash. Container signatures describe blocks; explicit validation queues all signature-listed files, and a separate tree check detects extra entries.

**OpenRC decision:** Reuse an established algorithm through a qualified helper; a matching hash or .sig file does not authenticate the publisher. Authenticate exact source, patch and target identities outside the algorithm. A directory candidate needs a signed complete inventory and full-package equivalence. Cross-file reuse may help content rearrangements, but no savings on OpenRC's compressed archives or embedded PCKs have been measured. Treat dependency footprint and modes/links as acceptance inputs.

**License observation:** MIT; inspect its dependency graph before redistribution.

**Primary evidence:**

- [LICENSE](https://github.com/itchio/wharf/blob/c844818e4eba2bafea8b054063a95c9b2e06ef7f/LICENSE).
- [wsync/algo.go](https://github.com/itchio/wharf/blob/c844818e4eba2bafea8b054063a95c9b2e06ef7f/wsync/algo.go#L1-L39).
- [pwr/sign.go](https://github.com/itchio/wharf/blob/c844818e4eba2bafea8b054063a95c9b2e06ef7f/pwr/sign.go#L18-L27).
- [pwr/validator.go](https://github.com/itchio/wharf/blob/c844818e4eba2bafea8b054063a95c9b2e06ef7f/pwr/validator.go#L243-L250).

## U02 Butler

**Repository:** itchio/butler · **Reviewed commit:** c0e529f2e31c82b0d6e785d2a6be908390b05ecc.

**Documented/observed:** Offline commands reproduce diff/apply without an itch account or network. The reviewed commit pins Wharf c844818e4eba2bafea8b054063a95c9b2e06ef7f. Applying is in-place by default; --dir selects a fresh destination and --staging-dir holds intermediate state. Source calls the bowl's Commit before optional --signature validation and the extra-file check.

**OpenRC decision:** Benchmark it with an isolated output and independent complete-target verification before activation. Staging alone is not verify-before-modification. The general documentation says unchanged in-place files are unchecked, while explicit post-commit validation walks the signature-listed set: qualify the pinned binary and extra-file behavior instead of promising mod preservation. The local patcher supplies neither GitHub trust nor native installation recovery. Optional rediff is a separate CPU/RAM experiment, not a guaranteed win.

**License observation:** MIT; binary and dependency notices still need qualification.

**Primary evidence:**

- [LICENSE](https://github.com/itchio/butler/blob/c0e529f2e31c82b0d6e785d2a6be908390b05ecc/LICENSE).
- [go.mod](https://github.com/itchio/butler/blob/c0e529f2e31c82b0d6e785d2a6be908390b05ecc/go.mod#L1-L38).
- [docs/offline.md](https://github.com/itchio/butler/blob/c0e529f2e31c82b0d6e785d2a6be908390b05ecc/docs/offline.md#L2-L109).
- [cmd/apply/apply.go](https://github.com/itchio/butler/blob/c0e529f2e31c82b0d6e785d2a6be908390b05ecc/cmd/apply/apply.go#L196-L248).

## U03 librsync

**Repository:** librsync/librsync · **Reviewed commit:** 271744de428c0177e993f95c045d70b8cf2558f2.

**Documented/observed:** rdiff creates a block signature of the basis, then a delta from that signature and new bytes, then reconstructs a separate output. Its documentation explicitly says it does not verify that the correct basis is supplied and cannot patch in place. Source implements copy/literal instructions. CI defines Linux/macOS/Windows jobs; their existence is not proof of a passing reviewed run.

**OpenRC decision:** Useful measured baseline for individual files. Require exact basis SHA-256 before applying and exact target authentication afterward. It supplies no release hosting, complete directory metadata, profile protection or native activation. Count both old and new files in peak disk usage. Reusing this engine still leaves wrapper/resource/packaging work; no OpenRC patch-size benefit is established.

**License observation:** LGPL-2.1-or-later in inspected library header; integration obligations depend on use.

**Primary evidence:**

- [src/librsync.h](https://github.com/librsync/librsync/blob/271744de428c0177e993f95c045d70b8cf2558f2/src/librsync.h#L1-L11).
- [doc/rdiff.md](https://github.com/librsync/librsync/blob/271744de428c0177e993f95c045d70b8cf2558f2/doc/rdiff.md#L104-L119).
- [src/patch.c](https://github.com/librsync/librsync/blob/271744de428c0177e993f95c045d70b8cf2558f2/src/patch.c#L93-L105).
- [.github/workflows/check.yml](https://github.com/librsync/librsync/blob/271744de428c0177e993f95c045d70b8cf2558f2/.github/workflows/check.yml#L13-L69).

## U04 casync

**Repository:** systemd/casync · **Reviewed commit:** b4b7e5606f785572b78a43626a27a45fe3df2fbd.

**Documented/observed:** casync stores variable chunks by content digest, retains an ordered index and can seed from local data. Source verifies chunk digests and expects nested digest-prefix chunk paths. Build dependencies/features are Linux-oriented; native Windows suitability was not demonstrated. Some README example operations are marked unimplemented.

**OpenRC decision:** Keep as a comparison for content addressing, not the first shipping candidate. GitHub Release assets do not automatically provide its nested chunk-store addressing; an explicit mapping/adapter and request/asset budget need proof. Bundling a whole store can remove selective-download benefits. A verified chunk hash authenticates bytes relative to an index, not the publisher of that index. A qualified signed complete generation remains necessary.

**License observation:** LGPL-family notices; verify chosen files/dependencies.

**Primary evidence:**

- [meson.build](https://github.com/systemd/casync/blob/b4b7e5606f785572b78a43626a27a45fe3df2fbd/meson.build#L1-L13).
- [README.md](https://github.com/systemd/casync/blob/b4b7e5606f785572b78a43626a27a45fe3df2fbd/README.md#L18-L45).
- [src/castore.c](https://github.com/systemd/casync/blob/b4b7e5606f785572b78a43626a27a45fe3df2fbd/src/castore.c#L134-L217).
- [src/cachunk.c](https://github.com/systemd/casync/blob/b4b7e5606f785572b78a43626a27a45fe3df2fbd/src/cachunk.c#L446-L460).

## U05 HDiffPatch

**Repository:** sisong/HDiffPatch · **Reviewed commit:** 06961361340085ddb2a551775dc402172b8ca67c.

**Observed:** The repository supplies C/C++ diff/patch APIs and command-line tools with streaming modes, configurable cache/window behavior and file/directory support. Published release 5.1.3 is the proposed experiment pin; inspected HEAD is recorded separately. In-memory diff mode has substantial input-size-dependent memory; a small patch cache is not a whole-process cap. Defaults use non-authenticating checksum families, with optional in-place and self-extracting paths.

**OpenRC decision:** Preferred first native patch-engine candidate to measure alongside Butler. Use a fresh output and verified external source/patch/target identities; exclude in-place and self-extracting execution. Exact ZIP reconstruction can retain the future descriptor-authenticated ZIP identity. Directory mode needs a versioned complete inventory and extraction-equivalence contract. Pin compression dependencies and measure memory/CPU/disk on our packages; upstream benchmarks do not establish any OpenRC percentage savings.

**License observation:** MIT plus included component notices.

**Primary evidence:**

- [README.md](https://github.com/sisong/HDiffPatch/blob/06961361340085ddb2a551775dc402172b8ca67c/README.md).
- [libHDiffPatch/HPatch/patch.h](https://github.com/sisong/HDiffPatch/blob/06961361340085ddb2a551775dc402172b8ca67c/libHDiffPatch/HPatch/patch.h).
- [hpatchz.c](https://github.com/sisong/HDiffPatch/blob/06961361340085ddb2a551775dc402172b8ca67c/hpatchz.c).
- [CHANGELOG.md](https://github.com/sisong/HDiffPatch/blob/06961361340085ddb2a551775dc402172b8ca67c/CHANGELOG.md).
- [LICENSE](https://github.com/sisong/HDiffPatch/blob/06961361340085ddb2a551775dc402172b8ca67c/LICENSE).

## U06 tough

**Repository:** awslabs/tough · **Reviewed commit:** 98d8eb8b2ce63515d9b4981c938ef6453c5b5771.

**Observed:** Cargo identifies tough 0.24.0. The client implements root, timestamp, snapshot and targets validation; expiry enforcement defaults on. The caller supplies trusted root bytes. Without a datastore it creates temporary state; persistent datastore writes use ordinary file writes and process-local locks. Old timestamp/snapshot comparisons are conditional on cached data parsing successfully. read_target exposes bytes before final checksum validation. Current delegation code contradicts an older header claim that delegation is unsupported.

**OpenRC decision:** Preferred native trust candidate for a bounded spike, with explicit durable latest-root selection, corruption recovery and cross-process ownership. Buffer the small descriptor and wait for verified stream completion before using it. The 2026 vendor bulletin fixes affected versions in 0.22.0/tuftool 0.15.0; use patched exact pins and inspect later advisories. Do not equate maintained TUF semantics with a qualified OpenRC trust-store adapter, filesystem transaction or instant revocation. The first spike uses only four top-level roles.

**License observation:** MIT OR Apache-2.0.

**Primary evidence:**

- [tough/Cargo.toml](https://github.com/awslabs/tough/blob/98d8eb8b2ce63515d9b4981c938ef6453c5b5771/tough/Cargo.toml).
- [tough/src/lib.rs](https://github.com/awslabs/tough/blob/98d8eb8b2ce63515d9b4981c938ef6453c5b5771/tough/src/lib.rs).
- [tough/src/datastore.rs](https://github.com/awslabs/tough/blob/98d8eb8b2ce63515d9b4981c938ef6453c5b5771/tough/src/datastore.rs).
- [tuftool/README.md](https://github.com/awslabs/tough/blob/98d8eb8b2ce63515d9b4981c938ef6453c5b5771/tuftool/README.md).
- [LICENSE-MIT](https://github.com/awslabs/tough/blob/98d8eb8b2ce63515d9b4981c938ef6453c5b5771/LICENSE-MIT).
- [LICENSE-APACHE](https://github.com/awslabs/tough/blob/98d8eb8b2ce63515d9b4981c938ef6453c5b5771/LICENSE-APACHE).

## U07 python-tuf

**Repository:** theupdateframework/python-tuf · **Reviewed commit:** d7b4f7c3e3399f2343636a3f1f439d0ed35e317c.

**Observed:** The project supplies a metadata API, ngclient and a repository API explicitly outside its stable API promise. The client models trusted metadata state, validates target length/hashes before copying downloaded output, and retains versioned roots. Metadata writes use temporary files and replacement; that does not alone establish power-loss durability. Latest observed release 7.0.1 fixes client/dependency/delegation and Windows path issues; the reviewed development SHA is a separate identity.

**OpenRC decision:** Use for maintainer publishing and interoperability fixtures if selected, without adding Python to player requirements. Prefer the maintained metadata API over reproducing canonical signing/key-rotation logic. Qualify the exact release's formats with the native candidate and the proposed GitHub Pages descriptor layout. It does not extract archives, preserve Mac receipts, replace a native install or solve profile migrations. Store role-specific signing keys and test renewal/recovery operations.

**License observation:** MIT OR Apache-2.0, reflected in source headers and license files.

**Primary evidence:**

- [README.md](https://github.com/theupdateframework/python-tuf/blob/d7b4f7c3e3399f2343636a3f1f439d0ed35e317c/README.md).
- [tuf/ngclient/updater.py](https://github.com/theupdateframework/python-tuf/blob/d7b4f7c3e3399f2343636a3f1f439d0ed35e317c/tuf/ngclient/updater.py).
- [tuf/ngclient/_internal/trusted_metadata_set.py](https://github.com/theupdateframework/python-tuf/blob/d7b4f7c3e3399f2343636a3f1f439d0ed35e317c/tuf/ngclient/_internal/trusted_metadata_set.py).
- [examples/manual_repo/basic_repo.py](https://github.com/theupdateframework/python-tuf/blob/d7b4f7c3e3399f2343636a3f1f439d0ed35e317c/examples/manual_repo/basic_repo.py).
- [LICENSE](https://github.com/theupdateframework/python-tuf/blob/d7b4f7c3e3399f2343636a3f1f439d0ed35e317c/LICENSE).
- [LICENSE-MIT](https://github.com/theupdateframework/python-tuf/blob/d7b4f7c3e3399f2343636a3f1f439d0ed35e317c/LICENSE-MIT).

## Additional current guidance

| ID | Primary document | What it supports |
| --- | --- | --- |
| N01 | [N01](https://aws.amazon.com/security/security-bulletins/2026-019-aws/) | tough/tuftool affected and patched versions |
| N02 | [N02](https://github.com/awslabs/tough/security/advisories/GHSA-4v58-8p28-2rq3) | delegated metadata validation vulnerability and fix |
| N03 | [N03](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule) | delayed/dropped schedules and inactivity disablement |
| N04 | [N04](https://theupdateframework.io/docs/metadata/) | roles and consistent metadata relationships |
| N05 | [N05](https://github.com/theupdateframework/python-tuf/releases/tag/v7.0.1) | published client fixes; source HEAD and release are distinct |
| N06 | [N06](https://github.com/awslabs/tough/releases/tag/tuftool-v0.17.0) | published tuftool candidate and tough 0.24.0 dependency |
| N07 | [N07](https://github.com/sisong/HDiffPatch/releases/tag/v5.1.3) | published patch-tool candidate version |

The root reviewer checked decision-driving original files and resolved the helper findings; a separate adversarial review challenged trust-state persistence, root bootstrap, stream verification, publication order and first-install ownership. Research source revisions and dependency revisions are deliberately distinct. Current source and release/advisory status must be rechecked at implementation time.
