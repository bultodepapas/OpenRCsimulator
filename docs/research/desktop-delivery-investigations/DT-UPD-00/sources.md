# Primary source ledger

Accessed 2026-11-17. Upstream documentation can change; this ledger records what
informed this proposal, not qualification of a particular installed updater.
Local code findings refer to baseline 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a.
Inferences and untested behavior are identified in the report/design.

## GitHub delivery

| ID | Primary source | Narrow finding / use |
| --- | --- | --- |
| G1 | [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) | Up to 1,000 assets per release; each below 2 GiB; no stated total-release or release-bandwidth limit. This is not an SLA or perpetual-price guarantee. |
| G2 | [REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) | Anonymous primary quota is 60 requests/hour per originating IP. |
| G3 | [REST best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api) | Respect rate/redirect semantics; conditional-request quota exemption is stated for authenticated requests. |
| G4 | [Release API](https://docs.github.com/en/rest/releases/releases) | Latest excludes drafts/prereleases; latest designation is not simply application SemVer maximum. |
| G5 | [Release asset API](https://docs.github.com/en/rest/releases/assets) | Binary download may return bytes or a redirect; API exposes asset size/digest. No universal Range guarantee was found here. |
| G6 | [Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits) | 1 GB published-site limit, 100 GB/month soft bandwidth and possible 429. Feed only; game packages remain in Releases. |
| G7 | [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) | Protects released tag/assets and creates attestation; title/notes/latest/prerelease labels remain mutable. |
| G8 | [Prevent release changes](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes) | Future-release setting and draft/upload/publish guidance; inspect actual policy before relying on it. |
| G9 | [Creating a Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site) | Publication is asynchronous; a GITHUB_TOKEN commit does not itself trigger a Pages build. |
| G10 | [Choosing a runner](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job) | Standard hosted public-repository runners are free; larger runners are not. |
| G11 | [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) | Artifact/cache/storage accounting is separate from free public compute. Keep player distribution in Releases. |
| G12 | [Actions limits](https://docs.github.com/en/actions/reference/limits) | Hosted job time and concurrency limits still apply; do not plan unbounded delta production. |

## Frameworks and platform distribution

| ID | Primary source | Narrow finding / use |
| --- | --- | --- |
| V1 | [Velopack repository and MIT license](https://github.com/velopack/velopack) | Open-source framework candidate; review dependencies as well as its top-level license. |
| V2 | [Velopack C/C++ integration](https://docs.velopack.io/getting-started/cpp) | Native API and startup integration; Godot applicability needs a real export spike. |
| V3 | [Velopack Windows packaging](https://docs.velopack.io/packaging/operating-systems/windows) | Default stub/current layout and portable packaging; not assumed to satisfy no-launcher. |
| V4 | [Velopack releases](https://github.com/velopack/velopack/releases) | Inspected stable 1.2.161 and pre-release 1.3.39-g8d2844f; --noStub appears in the latter. Recheck when selecting a dependency. |
| V5 | [Velopack integration overview](https://docs.velopack.io/integrating/overview) and [packaging](https://docs.velopack.io/packaging/overview) | Delta/full fallback and platform packaging tradeoffs. |
| V6 | [Upstream issue 975](https://github.com/velopack/velopack/issues/975) | Security questions to resolve against the pinned build; an issue report alone does not establish all-version behavior. |
| S1 | [Sparkle setup/security/distribution](https://sparkle-project.org/documentation/) | Native framework setup, archive signing and appcast workflow; distinguish archive signatures from Developer ID. |
| S2 | [Sparkle binary deltas](https://sparkle-project.org/documentation/delta-updates/) | Native Mac differential candidate; must measure actual OpenRC bundles. |
| S3 | [Sparkle repository/license](https://github.com/sparkle-project/Sparkle) | MIT framework candidate and release/version context. |
| W1 | [WinSparkle](https://github.com/vslavik/winsparkle) | MIT Windows library with C API. |
| W2 | [WinSparkle integration](https://github.com/vslavik/winsparkle/wiki/Basic-Setup) | Installer-oriented update integration; portable transaction still needs design. |
| L1 | [AppImageUpdate repository](https://github.com/AppImageCommunity/AppImageUpdate) | MIT Linux differential updater; upstream cautions require qualification. |
| L2 | [AppImage update specification](https://github.com/AppImage/AppImageSpec/blob/master/draft.md#update-information) | Embedded update metadata and GitHub release transport; not a Windows/Mac solution. |
| A1 | [Apple Developer enrollment](https://developer.apple.com/programs/enroll/) | Standard annual membership is USD 99; eligible waiver categories exist but no OpenRC eligibility is assumed. |
| A2 | [Godot macOS export](https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_macos.html) | Ad-hoc signing versus Developer ID/notarization. Latest documentation does not prove the pinned export's behavior. |
| A3 | [Apple packaging and distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) | Quarantine/translocation and downloaded installation must be tested on native Mac. |
| A4 | [Apple fee-waiver requirements](https://developer.apple.com/help/account/membership/fee-waivers) | Qualifying legal entities only; individuals and sole proprietors are excluded. Open-source status alone does not qualify. |
| P1 | [SignPath Foundation](https://signpath.org/) | Free signing for accepted open-source projects; an optional opportunity, not established OpenRC acceptance. |
| P2 | [SignPath conditions](https://signpath.org/terms) | Licensing, provenance, approval-role and upstream-binary restrictions require an eligibility review. No submission or third-party service enrollment performed. |

## Protocol, Godot and trust

| ID | Primary source | Narrow finding / use |
| --- | --- | --- |
| H1 | [RFC 9110, Range/Content-Range](https://www.rfc-editor.org/rfc/rfc9110.html) | Servers may ignore Range; 200 is not resumable append; validate 206 ranges and treat 416 carefully. |
| E1 | [Godot packs/patches, 4.5](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_pcks.html) | Resource packs and early-load/override semantics. |
| E2 | [Godot packs/patches, latest](https://docs.godotengine.org/en/latest/tutorials/export/exporting_pcks.html) | Later docs describe delta/load-order tradeoffs and patch security; exact pinned 4.8-beta2 feature availability remains an experiment. |
| E3 | [Godot HTTPRequest](https://docs.godotengine.org/en/4.5/classes/class_httprequest.html) | File-backed transfer and bounds exist, but OpenRC's documented thread/cancellation history must govern implementation. |
| E4 | [Godot Crypto](https://docs.godotengine.org/en/stable/classes/class_crypto.html) | Do not assume its documented RSA-oriented API exposes the same Ed25519 verifier as a native library. |
| E5 | [Godot OS](https://docs.godotengine.org/en/stable/classes/class_os.html) | Process creation and executable paths are available; they do not provide a transactional updater. |
| E6 | [Godot data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html) | user:// persistence is distinct from installed res:// resources. |
| T1 | [TUF overview](https://theupdateframework.io/docs/overview/) | Established update threat model and metadata roles; compare before inventing broad key/delegation machinery. |
| T2 | [TUF FAQ](https://theupdateframework.io/docs/faq/) and [security](https://theupdateframework.io/docs/security/) | Trust/compromise/freeze tradeoffs; a single signed JSON file is not TUF. |
| T3 | [libsodium Ed25519 signatures](https://doc.libsodium.org/public-key_cryptography/public-key_signatures) | Native detached-signature implementation candidate; not hand-rolled crypto. |
| T4 | [Minisign](https://github.com/jedisct1/minisign) | Free Ed25519-based signing tool candidate; its file format is not interchangeable with raw signatures. |
| T5 | [Cryptography Ed25519 API](https://cryptography.io/en/50.0.0/hazmat/primitives/asymmetric/ed25519/) | API used by the isolated Python reference verifier/tests; pin is 50.0.0. |
| T6 | [RFC 8032 Ed25519 test vectors](https://www.rfc-editor.org/rfc/rfc8032.html#section-7.1) | Independent known-answer verification for the draft, distinct from self-generated fixtures. |

## Reproducible repository evidence

Read the exact baseline through Git, for example:

~~~sh
git show 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a:app/app_state/update_check.gd
git show 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a:tools/release/publish.py
git diff v0.2.7 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a -- app/app_state/preferences.gd
~~~

The [API observation](release-observation.json) records package sizes and API-provided
digests without claiming to have verified downloaded bytes. Primary technical
sources were preferred over aggregator articles. Dates, versions, limits and
framework capabilities must be rechecked before implementation.

## Additional game and component research

The same-branch follow-up is indexed separately to keep each source's scope and
revision reviewable: [27 repository case studies](game-update-survey.md) and the
[machine-readable ledger](survey-evidence.json). It adds 20 game/game-engine
projects and seven supporting tools, covering 115 distinct commit-pinned source,
workflow, documentation and license files. Main cases are counted once; Warzone's
feed/verifier and SuperTux's version repository are supporting sources.

The ledger also records the 2026 tough security bulletin/advisory, GitHub's schedule
contract, TUF role documentation, and exact candidate release references. These
references support the [reuse spikes](reuse-spikes.md), not a claim that native
updating or delta savings have been demonstrated. Mutable upstream documentation
and release/advisory status need a fresh check when selecting dependencies.
