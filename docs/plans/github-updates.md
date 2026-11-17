# GitHub-only game updates

**Status:** proposed design and research draft, 2026-11-17. No production updater is implemented by this branch.
**Owner/prefix:** desktop delivery, **DT-UPD-00…12**; subordinate to DT-08/08a/09/12/13.
**Baseline:** main commit 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a.
**Constraints:** GitHub remains the distributor; no launcher, storefront, player account, paid infrastructure or mandatory update.

## Recommendation

Extend the existing Home update notice into a verified download and restart flow.
Keep complete platform ZIPs on GitHub Releases. Put a small signed channel document
on the existing GitHub Pages site. Use a bundled, short-lived native helper for
installation after the game exits. Players continue opening the game directly;
the helper is not a normal-startup stub, resident service or second product.

Start with complete packages. Add differential downloads only after measuring
actual OpenRC artifacts and proving that the reconstructed package is byte-identical
to the signed target. Keep a complete-package fallback permanently.

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
- [Executable protocol draft](../../research/github-updates/README.md).

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
| DT-UPD-00 | Source audit, primary research, design and negative protocol fixtures. | Research delivered in this branch; implementation and native qualification remain open. |
| DT-UPD-01 | Compare the bespoke helper with pinned Velopack no-stub and a macOS Sparkle spike. Establish recovery topology and license/dependency lock. | Real OpenRC export launches directly, completes a trial update, preserves receipts, and proves the chosen ordinary/recovery paths. Estimated 3–5 days. |
| DT-UPD-02 | Specify and implement signing, trust bootstrap, sequence/expiry state, bounded parsers, platform selection and release identity. | Adversarial fixtures and independent signature vectors; offline key backup and rotation/recovery rehearsal. Estimated 3–5 days. |
| DT-UPD-03 | Integrate signed Pages feed and publication orchestration. | Exact source/assets verified before feed promotion; concurrent different-tag and website publishes cannot regress or lose the feed. Estimated 3–5 days. |
| DT-UPD-04 | Home/Settings download UX and transport. | Bounded streaming/resume, cancellation, rate limits, offline play, localization/accessibility and existing update tests. Estimated 4–7 days. |
| DT-UPD-05 | Windows apply/recovery adapter. | Writable local install, locked DLLs, paths, process ownership, every fault boundary and real shortcut/reboot recovery. Estimated 5–10 days. |
| DT-UPD-06 | Linux apply/recovery adapter. | Executable modes, native sidecars, local filesystems, launch path and fault/reboot matrix. Estimated 3–6 days. |
| DT-UPD-07 | macOS apply/recovery adapter. | Universal .app plus receipts, quarantined download, translocation, permissions, process restart and failure matrix on native Mac. Estimated 5–10 days. |
| DT-UPD-08 | Startup health and profile compatibility. | Rendered Home acknowledgement with bound transaction identity; renderer fallback restart; data/Workshop/recording upgrade and rollback witnesses. Estimated 3–6 days. |
| DT-UPD-09 | Measure differential strategies. | Real N→N+1, N−2→N, code/asset/engine changes; bytes, CPU, time, memory, disk, failure and exact target hashes. Estimated 3–5 days. |
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

Promote a signed channel envelope only after the release is public and its exact
assets pass downloaded-byte verification. A withdrawn update stops being offered
through a higher-sequence signed control record in the future production protocol;
this research verifier deliberately does not implement withdrawal. Never rewrite
an already published archive or silently relabel a different binary as the same version.

Use a 90-day metadata lifetime as an initial operational proposal, with renewal
before 60 days and on each release. Refresh does not require a new game version.
No scheduled task, key, repository policy or deployment is created in this branch.
A lapsed feed disables new automatic installations, not the installed simulator.

Stop promotion if signatures, target bytes, package receipts, data compatibility
or recovery proof fail. Preserve the failed candidate and previous working build.
A release-version fallback is separate from undoing player-data migrations.
Document how to recover a bootstrap client that predates key rotation.

## Revisit conditions

Prefer a maintained framework if the DT-UPD-01 spike proves compliance and reduces
our security/lifecycle maintenance. Consider AppImageUpdate only if the Linux packaging
track adopts AppImage. Consider TUF when role delegation, multiple publishers or
compromise recovery becomes necessary. Consider external PCK/content partitioning
only with composite build/replay identity and measured benefit. None of these choices
requires leaving GitHub or charging players.
