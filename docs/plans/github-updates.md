# GitHub-only game updates

**Status:** proposed design and research draft, expanded 2026-11-17 with 27 additional repository studies. DT-UPD-04a (discovery and notice UX, below) is implemented; no download, verification or installation exists.
**Owner/prefix:** desktop delivery, **DT-UPD-00…12**; subordinate to DT-08/08a/09/12/13.
**Baseline:** main commit 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a.
**Constraints:** GitHub remains the distributor; no launcher, storefront, player account, paid infrastructure or mandatory update.

## Recommendation

Extend the existing Home update notice into a verified download and restart flow.
Keep complete platform ZIPs on GitHub Releases. Put small authenticated release
descriptors and trust metadata on the existing GitHub Pages site. **Prefer a
maintained TUF implementation for the trust layer**, subject to the native,
persistent-state and maintenance spike; retain the previous custom envelope only
as a comparison model. Use a bundled, short-lived native helper for installation
after the game exits. Players continue opening the game directly;
the helper is not a normal-startup stub, resident service or second product.

Start production delivery with complete packages. In parallel, measure existing
HDiffPatch and Butler/Wharf tools on actual OpenRC artifacts. Enable differential
downloads only after proving exact target identity and the qualified full-package
path: exact ZIP equality for archive deltas, or a new authenticated complete-tree
inventory and full-install equivalence for file deltas. Keep a complete-package
fallback permanently. Do not invent a new patch algorithm.

**Automatic installation is conditional on each platform's recovery proof.**
A two-rename directory replacement is not a portable atomic transaction. If a
power failure can remove the ordinary launch path, in-game recovery cannot repair
it. Prototype a stable, independently reachable recovery helper and an OS-specific
commit strategy; change packaging to immutable release generations if necessary.
Until that gate passes, the same UI should download, verify and explain installation.
Do not label that assisted path an automatic updater.

This is the selected research direction, not approval of an implementation or
a claim that all three operating systems are already supported. The native helper
implementation/library choice remains the DT-UPD-01 comparison outcome.

## Authoritative supporting documents

- [Dated audit and findings](../research/desktop-delivery-investigations/DT-UPD-00/README.md).
- [Alternatives and selection](../research/desktop-delivery-investigations/DT-UPD-00/options.md).
- [Proposed architecture and protocol](../research/desktop-delivery-investigations/DT-UPD-00/design.md).
- [Acceptance and fault-injection matrix](../research/desktop-delivery-investigations/DT-UPD-00/validation.md).
- [Primary source ledger](../research/desktop-delivery-investigations/DT-UPD-00/sources.md).
- [27 additional repository studies](../research/desktop-delivery-investigations/DT-UPD-00/game-update-survey.md).
- [Pinned source ledger](../research/desktop-delivery-investigations/DT-UPD-00/survey-evidence.json).
- [Reuse decisions and four investigation briefs](../research/desktop-delivery-investigations/DT-UPD-00/reuse-spikes.md).
- [Player help and interface copy draft](../research/desktop-delivery-investigations/DT-UPD-00/player-help-draft.md).
- [Executable envelope comparison model](../../research/github-updates/README.md).

The existing [desktop plan](../DESKTOP-DELIVERY-PLAN.md), [release tools](../../tools/release/README.md),
[Linux plan](linux-support-distribution.md), [Apple plan](apple-silicon-performance.md)
and [website publisher](../../site/README.md#preview-and-maintain) retain ownership of
their contracts. This plan does not supersede their platform qualification gates.

## Player experience

The first manually installed update-capable build is the bootstrap. Existing
versions cannot acquire this capability merely because a new GitHub asset appears.

| Situation | Proposed experience |
| --- | --- |
| Open Home, online | A small update card appears after an asynchronous, cached check. No focus theft or startup block. |
| New stable version | Show version, release notes, actual transfer size and required free space. Buttons: Download update, Later, Skip this version. |
| Preview channel | Explicit opt-in in Settings; stable remains default. Channel switching never silently downgrades. |
| Download | Progress, pause/cancel and honest retry status. Keep the current game usable. Pause heavy work during a flight by default. |
| Download verified | Offer Restart and update or Install when I exit. No forced restart or mid-flight replacement. |
| Unsaved Workshop or active recording | Reuse existing save/discard/recording exit guards. Cancelled or failed save cancels the apply request. |
| Successful restart | One acknowledgement of the new version; keep the previous complete install until health and retention checks pass. |
| Network failure / expired metadata | Keep playing; explain the update failure and offer the canonical GitHub page. No auth prompt. |
| Install not writable or platform adapter unqualified | Verified download plus Open download folder and clear platform instructions. No automatic elevation. |
| Update cannot start | Preserve the previous install and recovery route. Explain any user action needed without hiding it as success. |

Provide these states in the existing localization system and support keyboard,
gamepad and mouse. Review at 1920×1080 first, then above 1080p, then 1280×720.
A checking preference, manual Check now and an explicit automatic-download preference
belong in Settings. Default to checking automatically, asking before downloading.
No telemetry service is required; GitHub sees normal requests and their IP addresses.
Keep Not checked, Failed, Current and Unsupported distinct. Require a successful
trust refresh before granting apply; recheck its authorization/expiry after the
normal exit flow. Offline or failed refresh leaves the candidate ready for later
and the installed game playable. This bounds freshness; it cannot guarantee instant
withdrawal against replay of still-valid metadata. If a failed delta needs a larger
full download, show the new transfer size and request the player's consent.

## Required product properties

1. **Offline play survives update failures.** Never make the update feed a launch dependency.
2. **The full release is the unit of compatibility.** Executable, PCK, native libraries,
   package manifests and macOS sibling receipts must agree.
3. **Player files are not installation files.** Preserve the complete existing user-data
   directory and external files. Do not reset calibration, settings, Creator/Workshop
   content, skins, recordings or recovery data.
4. **Trust precedes extraction and execution.** Verify pinned-key metadata, signed length
   and SHA-256, then constrained extraction and the complete staged package.
5. **One installation transaction at a time.** Resolve real filesystem identity and use
   an owner-checked lock. A PID or a path string alone is insufficient.
6. **Recovery is explicit and durable.** Journal transitions, retain a complete previous
   generation, test interrupted operations and provide a separately reachable repair path.
7. **Rollback does not mean restoring an old whole profile.** Qualification includes old
   readers/writers and concurrent installs; new data must not be silently erased.
8. **Efficiency is measured.** Bound memory, CPU, disk and retry costs; do not promise a
   delta percentage before real artifact measurements.
9. **No permanent launch indirection is assumed.** Any framework requiring an always-used
   launcher stub must be evaluated against the user's constraint before adoption.
10. **Full packages remain available.** Repair, skipped releases, unsupported delta bases,
    offline transfer and bootstrap all need them.

## Owned paths and integration boundaries

| Scope | Ownership / proposed work |
| --- | --- |
| This branch | This plan; DT-UPD-00 research; research/github-updates/ draft only; navigation links. |
| Future product UI | Coordinate app/ui/update_notice.gd, Settings and localization with UI. |
| Future discovery | Extend or replace app/app_state/update_check.gd and update_checker.gd; preserve opt-out, cache, stable/preview and offline behavior. |
| Future lifecycle | Coordinate app/app_root.gd, startup.gd and renderer_guard.gd; preserve graceful exit and route selection. |
| Future helper | Proposed tools/updater/ build sources and packaged native binaries; not added by this research. |
| Future release metadata | Version existing tools/release/manifest.py and publish.py contracts deliberately; preserve six-file releases until the schema is changed. |
| Future website | Add a dedicated updates/ namespace and a serialized publisher preserving the whole existing site. |
| Future identity | Coordinate native_package.gd, native-stage admission and flight-log replay before any layout/PCK changes. |
| Future profile migration | Coordinate each data owner; no generic updater conversion of player content. |

## Implementation sequence and acceptance

Estimates below are engineering judgement for one experienced developer, not
measured delivery dates. They include implementation and review, not elapsed waiting
for native hardware. Steps can overlap only where contracts are already stable.

| ID | Work | Exit evidence / status |
| --- | --- | --- |
| DT-UPD-00 | Source audit, primary research, 27 additional repository studies, design/help drafts and negative protocol fixtures. | Research delivered; 115 pinned source files in the follow-up ledger; all 82 product acceptance cases remain unrun. |
| DT-UPD-01 | Compare a minimal helper with pinned Velopack no-stub, macOS Sparkle and, if useful, a per-user Windows installer. Establish legacy-install ownership, recovery topology and license/dependency lock. | Real OpenRC export launches directly, completes a trial update, preserves receipts, and proves the chosen ordinary/recovery paths. Estimated 3–5 days. |
| DT-UPD-02 | Qualify maintained TUF against the custom-envelope comparison; choose native/publisher libraries and descriptor format. | Native/reference interoperability, verified EOF before use, durable latest root/high-water state, corrupt-cache and role-rotation tests, offline key backup and renewal/recovery rehearsal. Initial spike estimated 3–5 days; persistence/integration fixes may extend it. |
| DT-UPD-03 | Integrate authenticated Pages metadata/descriptors and publication orchestration. | Exact public assets verified; immutable/versioned objects available before timestamp promotion; website/concurrent-tag jobs preserve metadata/root history. Estimated 3–5 days after trust selection. |
| DT-UPD-04a | Discovery and notice UX that the later download path reuses, with no trust or transfer claims: stable/preview subscription (default follows the running build), exact per-platform release ZIP (`openrc-simulator-<tag>-<os>-<arch>.zip`) with GitHub's size/digest observation, distinct Not checked / Current / Available / No package / Failed states, Later vs Skip this version, Settings → Interface rows (automatic checks, channel, Check now with a 30 s cooldown), one checker per session, cache format 2, 30 releases per list request. Known limits: no re-check during a session longer than a day; Check now from the pause menu may run its small request during a paused flight; an older build drops `[updates] channel` (the choice returns to following the build). | Done 2026-11-17: app/tests/test_update_check.gd (96 checks) and test_ui_update_notice.gd (46) pass, with test_ui_language, test_settings_ui, test_ui_settings_integration, test_ui_home, test_ui_home_rebuild, test_ui_preserved_choices and test_main_startup_cleanup; no native or 1080p visual review yet. |
| DT-UPD-04 | Home/Settings download UX and transport. | Bounded streaming/resume, cancellation, rate limits, offline play, localization/accessibility and existing update tests. Estimated 4–7 days. |
| DT-UPD-05 | Windows apply/recovery adapter. | Writable local install, locked DLLs, paths, process ownership, every fault boundary and real shortcut/reboot recovery. Estimated 5–10 days. |
| DT-UPD-06 | Linux apply/recovery adapter. | Executable modes, native sidecars, local filesystems, launch path and fault/reboot matrix. Estimated 3–6 days. |
| DT-UPD-07 | macOS apply/recovery adapter. | Universal .app plus receipts, quarantined download, translocation, permissions, process restart and failure matrix on native Mac. Estimated 5–10 days. |
| DT-UPD-08 | Startup health and profile compatibility. | Rendered Home acknowledgement with bound transaction identity; renderer fallback restart; data/Workshop/recording upgrade and rollback witnesses. Estimated 3–6 days. |
| DT-UPD-09 | Benchmark HDiffPatch and Butler/Wharf; librsync baseline, packaging churn, conditional chunk comparison. Research can run alongside the full-package implementation. | Real adjacent/skipped, code/asset/native/engine and same-source repeat exports; actual base availability, bytes, CPU, time, memory, disk and exact target identity. Estimated 3–5 days for the first matrix. |
| DT-UPD-10 | Adopt the winning optional delta route. | Exact-base matching, bounded patcher, no long chains, full fallback and unchanged package/replay identity. Conditional, estimated 5–10 days. |
| DT-UPD-11 | Rehearse downloaded releases and bootstrap migration. | Complete end-to-end native matrix; rollback, update withdrawal, stale channel, lost key and paused rollout rehearsal. Estimated 4–7 days. |
| DT-UPD-12 | Enable by qualified platform and record acceptance. | Opt-in testers first, then stable; release notes state exact scope and recovery limits. No service-side telemetry required. |

An assisted verified-download slice is approximately **1–3 developer weeks** after
the essential trust/publication decisions. A carefully qualified automatic updater
for all three systems is more plausibly **6–12+ developer weeks**; macOS receipt/layout
changes or a custom transactional installer can extend this. These ranges overlap
the step estimates and are not additive commitments. Delta optimization is a later
investment, approximately **2–4 additional weeks** if justified.

## Rollout, operation and stop conditions

Ship a complete bootstrap ZIP and clear upgrade instructions once. Exercise stable
and preview feeds without changing existing installed clients. Enable automatic
apply only for tested OS/filesystem/layout combinations; unsupported installations
retain assisted download.

Promote authenticated channel metadata only after the release is public and its
exact assets pass downloaded-byte verification. For the preferred TUF spike,
publish immutable descriptor targets and versioned metadata before advancing
timestamp.json; retain root history and revalidate concurrent publisher retries.
Withdrawal is authenticated policy and never rewrites published archives.
Metadata-version ordering and game-version downgrade policy are separate.

Role lifetimes and renewal operations are hypotheses in the
[trust spike](../research/desktop-delivery-investigations/DT-UPD-00/reuse-spikes.md#spike-a--standard-trust-on-static-github-hosting),
not adopted production settings. Online timestamp renewal cannot renew expired
offline-signed targets. A lapsed feed disables new automatic installation, not
the simulator. No workflow, key, recurring job, repository policy or deployment
is created in this branch.

Stop promotion if signatures, target bytes, package receipts, data compatibility
or recovery proof fail. Preserve the failed candidate and previous working build.
A release-version fallback is separate from undoing player-data migrations.
Document how to recover a bootstrap client that predates key rotation.

## Revisit conditions

Prefer a maintained framework if the DT-UPD-01 spike proves compliance and reduces
our security/lifecycle maintenance. Consider AppImageUpdate only if the Linux packaging
track adopts AppImage. Prefer maintained TUF now, but record concrete native,
persistence or maintenance blockers before selecting its production implementation.
Consider external PCK/content partitioning
only with composite build/replay identity and measured benefit. None of these choices
requires leaving GitHub or charging players.
