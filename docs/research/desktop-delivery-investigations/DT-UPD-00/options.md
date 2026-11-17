# Update options and decision

2026-11-17; DT-UPD-00. [Plan](../../../plans/github-updates.md) ·
[Primary sources](sources.md). Ratings below are engineering assessments for
OpenRC's current layout, not benchmarks or vendor rankings.

## Comparison

| Approach | Player effort | Fit with GitHub and zero service cost | Main engineering burden | Assessment |
| --- | --- | --- | --- | --- |
| Current notice → browser ZIP | Download, extract and replace manually | Already implemented | Better instructions only | Retain as universal fallback; insufficient as the desired end state. |
| In-game verified download, assisted install | One download action; installation still manual | Strong; reuses current archives | Signed feed, transport, clear OS instructions | Valuable first product slice and fallback for unsupported installs. |
| In-game UI + temporary native apply helper | Download, then restart when ready | Strong; no normal-start launcher | Secure transport/extraction, OS transactions, health, recovery and data compatibility | Recommended architecture to qualify, using existing libraries where suitable. |
| Velopack | Potentially the same in-game UX | MIT; GitHub source available | Godot startup integration, package changes, no-stub proof, trust and receipts | Best cross-platform framework spike, not a proven drop-in. |
| Sparkle on Mac + separate Windows/Linux adapters | Native update prompts or integrated UI | MIT; static appcast and GitHub assets | Native bridge, bundle/helper packaging, receipt compatibility and unsigned-Mac qualification | Strong Mac candidate after layout/signing investigation. |
| WinSparkle | Native Windows update experience | MIT; static appcast | Documented flow launches an installer; portable replacement still needs a solution | Useful if Windows install lifecycle is deliberately adopted. |
| AppImageUpdate / zsync | Small Linux transfers and integrated update possibility | MIT; supports GitHub Releases metadata | Change Linux ZIP to AppImage, integration, trust/recovery qualification | Conditional on Linux packaging owner; not universal solution. |
| Godot resource PCK patches | Potentially much smaller content updates | Uses existing engine and release hosting | Pack ordering, base identity, early loading, patch compaction, signature and native/engine fallback | Optional later content strategy; not a complete safe updater today. |
| Precomputed binary patch assets | Potentially smaller downloads, same installed release | Patches are ordinary GitHub assets | Exact-base detection, bounded patcher, target reconstruction and benchmarks | Preferred first efficiency experiment after full-package correctness. |
| Versioned content packs / content-addressed chunks | Reuse unchanged content across releases | Can use Release assets; no custom server inherently needed | New export/runtime identity, asset-count/request budget and cache GC | Larger architecture investment; justify with actual release measurements. |
| OS package managers, Flatpak, winget | Convenient for some users | Software may be free; can source GitHub packages | External catalog/service and package-specific lifecycle | Optional future distribution, outside the requested GitHub-only core. |
| git pull, rsync, generic folder sync | Poor for ordinary players | Free tools, but GitHub is not an rsync endpoint | Dev dependencies, source assets, dirty/mixed installs and no trusted package contract | Reject for player updates. |

## Velopack: investigate before adopting or rejecting

The upstream project is MIT-licensed, documents a GitHub update source, supports
deltas/full fallback and exposes C/C++ integration. Its normal Windows portable
layout includes a launcher stub that enters the current version directory. That
default does not meet a strict no-launcher interpretation.

The inspected upstream release page lists **1.3.39-g8d2844f as pre-release** and
includes --noStub; stable latest on that snapshot is 1.2.161. Do not generalize
pre-release behavior to stable or assume omitting the stub solves shortcuts,
restart and recovery. Pin the candidate and record direct normal launch, updating
with the engine still loaded, crash/reboot recovery and the old entry path.

Its C++ guide expects initialization at main() before application startup.
A GDExtension-only integration in stock Godot may be too late; prove it before
planning around an engine fork. The documented Linux format is AppImage, which
changes current packaging. Mac receipt siblings and the existing release-manifest
inventory remain OpenRC obligations. Upstream security issue #975 is a question
to inspect against the pinned version, not proof that every version is insecure.
Source: ledger V1–V5.

## Sparkle and WinSparkle

Sparkle has mature Mac update packaging, Ed25519 archive signatures and optional
deltas. Its current documentation also distinguishes signed-feed support by
version. It still needs native integration and correctly packaged helper frameworks.
Its guidance recommends an archive containing the app alone, whereas OpenRC
currently needs sibling receipts. Test that conflict explicitly; do not silently
discard the receipts or amend a signed bundle after packaging.

Mac Developer ID identity, notarization, Sparkle's update signature and OpenRC's
replay receipts solve different problems. A free Ed25519 key does not become
Apple-recognized publisher identity. The current $0 plan retains ad-hoc signing
and honest platform launch instructions unless an existing funded membership or
eligible fee waiver is established. No waiver is assumed.

WinSparkle's documented installer handoff can simplify Windows update prompting
and verification, but it does not by itself specify transactional portable-ZIP
replacement. Adopting a per-user installer is allowed by the broader project
request if it improves lifecycle without adding a launcher; it still needs
rollback, uninstall and data-preservation acceptance. Sources S1–S3, W1–W2, A1–A2.

### Free OS-signing opportunities are conditional

SignPath Foundation offers free code signing for accepted open-source projects.
Its conditions include licensing, approval roles, provenance and restrictions on
signing upstream binaries. OpenRC's exported Godot executable and any proprietary
optional components require an eligibility review; neither acceptance nor coverage
of every game binary is established here. This is an optional Windows/helper
trust investigation, not a hosting change, application submission or dependency
of the core updater. It does not establish that all Windows warnings will vanish.
Sources P1–P2.

Apple's waiver requires a qualifying legal entity and excludes individuals/sole
proprietors. An open-source repository by itself does not qualify. The $0 core
plan therefore makes no paid-certificate or waiver assumption. Source A4.

## Why full packages first

A verified complete new generation gives one coherent target. It covers Godot
runtime, scripts, assets, GDExtensions, manifests and receipts together, and works
after many skipped releases. It is easier to repair and reason about than a
chain of layered patches.

The cost is bandwidth and temporary disk, significant for current ~1.5 GB ZIPs.
Reliable streaming/resume and a clear restart flow provide immediate value while
delta experiments proceed. Full packages remain the recovery reference even if
most users later receive patches.

A short-lived updater helper is infrastructure internal to the game: it runs
only to prepare/apply/recover an update and terminates. This design excludes a
new storefront UI, resident service, account and mandatory launch stub. It does
not pretend that a helper can replace files robustly without platform work.

## Efficiency experiments

| Candidate | What to measure | Failure/fallback |
| --- | --- | --- |
| Exact old ZIP → new ZIP binary delta | Transfer bytes; compression sensitivity; generation/apply time; peak RSS; whether old ZIP is cached | Base ZIP often absent after a manual install; fetch full target instead of downloading an old ZIP just to patch it. |
| Extracted embedded executable/PCK → new exact files | Changes in binary layout; native sidecar inventory; final complete-generation equivalence | Exact base mismatch, changed engine or receipts: reconstruct from a complete package. |
| External main PCK and separate engine/native components | Reuse across script, scenery and engine-only updates; import/export determinism; start time | Requires revised export, signing and replay identities, not just a preset toggle. |
| Godot patch PCKs including delta encoding | Exact pinned engine support; base/order dependency; startup/resource cost; deletion behavior; compaction | Latest docs may describe newer features. Do not claim support without a 4.8-beta2 experiment. |
| Content-addressed chunks / zsync-like retrieval | Total requests, hash-index size, shifted compressed data, CDN Range behavior, cache use | Unavailable Range or high request cost: use precomputed deltas/full assets. |

Use at least code-only, large-scenery, native-library and engine-upgrade pairs,
plus a skipped-version and damaged-base case, on all shipped platforms.
A delta is an optimization: authenticate its own bytes, verify the exact old
base, reconstruct in staging, then require the same signed target hash and full
package checks as a complete download. Here "same signed target hash" applies to
exact ZIP reconstruction. Extracted-file deltas need a newly specified signed
complete-file inventory and installed-generation equivalence; today's ZIP digest
cannot directly verify a directory. Never patch the live installation.

Provisional experiment thresholds: prefer a patch only below 70% of full transfer,
with acceptable target-machine time/RAM/disk and no recovery regression. This is
an initial decision rule, not an achieved reduction. Keep at most the last two
qualified base versions initially; no patch chain is required. Record the first
update's base-cache absence rather than concealing it in a favorable benchmark.

## Decision changes that would be justified

Choose Velopack if a pinned release passes direct launch, stock-Godot integration,
authenticated package acceptance, receipts and interrupted lifecycle with less
maintenance than the bespoke adapter. Choose Sparkle on Mac if its packaged
install path preserves coherent receipts and works under the actual zero-budget
trust posture. Adopt AppImageUpdate only with Linux packaging acceptance.
Adopt modular PCKs only if measured bandwidth savings outweigh additional identity,
startup and release complexity.
