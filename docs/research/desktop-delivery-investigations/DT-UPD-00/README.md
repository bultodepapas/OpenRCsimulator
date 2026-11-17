# DT-UPD-00 — GitHub update investigation

**Date:** 2026-11-17. **Source:** 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a.
**Branch:** research/github-updates-20261117.
**Scope:** source inspection, primary-source research, protocol draft and bounded
offline checks. This is not a delivered game updater, a release, a package benchmark
or Windows/macOS installation acceptance.

[Active plan](../../../plans/github-updates.md) · [Options](options.md) ·
[Design](design.md) · [Validation](validation.md) · [Sources](sources.md) ·
[Draft code](../../../../research/github-updates/README.md)

## Conclusion

The best fit is an in-game update experience with GitHub Releases packages, a
signed small discovery feed on the existing GitHub Pages site and a temporary
native installation helper. Complete-package replacement is the correctness
baseline; differential download is a replaceable transport optimization.

The largest uncertainty is safe cross-platform installation with no permanent
launcher. The research therefore specifies a platform qualification gate and a
useful verified-download fallback. Generic two-rename code is insufficient.
Framework comparison remains open at a bounded integration spike; the design does
not require rebuilding every updater feature ourselves.

## Current-source findings

Paths below refer to the frozen baseline. Current files, not older research or a
cached website page, define implemented behavior.

| Evidence | Observed behavior | Design consequence |
| --- | --- | --- |
| app/app_state/update_check.gd | Requests ten releases from the GitHub REST API; caches one day; separates stable from prerelease; natural digit ordering inside prerelease identifiers; platform assets selected by filename substring. | Reuse player-facing policy, but automatic installation needs exact platform/architecture/tag/digest contracts and pagination-independent channel selection. Do not call the existing comparator unmodified strict SemVer. |
| app/app_state/update_checker.gd | Unthreaded HTTPRequest with processed-frame timeout and bounded small JSON; prior thread-join issue is documented in source. | Preserve nonblocking Home and cancellation. Do not blindly enable threaded HTTPRequest for multi-GB downloads. Measure a bounded worker/process route. |
| app/ui/update_notice.gd and app/app_root.gd | Download opens the release page; Hide persists by tag. No package download, verification, installation or rollback is implemented there. | Existing card is a suitable entry point, not an updater to turn on with one flag. |
| app/app_state/build_info.gd | Exported build_info.json, commit/describe/dirty data identify the build. Project version can be overridden. | Compare a signed target to actual exported identity; do not trust application/config/version alone. |
| app/export_presets.cfg | Windows/Linux embed PCKs in their executables; macOS is universal, ad-hoc signed and not notarized. | Embedded content can make a small source change replace a large executable. PCK-only updates cannot cover engine/native changes. |
| tools/release/manifest.py, publish.py and .github/workflows/ci.yml | Strict current manifest v2; exactly three ZIPs, linux-abi.json, release-manifest.json and SHA256SUMS. Publisher verifies expected commit/tag/run/repository and redownloaded bytes; different retries fail. | Preserve this foundation. Extra signature/delta assets require coordinated schema, inventory, publisher and CI changes. |
| app/app_state/native_package.gd and tools/release/macos_reference_receipt.py | Mac .app has a sibling reference receipt; experimental native bundles have another receipt. Linux native package receipt binds executable and library. | Stage, validate, apply and recover coherent release sets. A bundle-only updater can leave incompatible receipts. |
| app/sim/flight_log.gd | Packaged identity includes executable or bundle/receipt hashes and backend evidence. | An external PCK overlay could change scripts without the old identity changing; no silent content hot-patching. |
| app/app_root.gd, preferences*.gd and input/controller_profile_store.gd | Shared user:// stores settings, actual settings.cfg.display companion, profiles/calibration and recovery files. | Preserve the whole directory, not a guessed list. Per-install updater state must not collide with another install. |
| app/workshop/ and related stores | Creator/variants, content-addressed objects, indexes, compiler pins, drafts and recovery have versioned contracts. | Preserve them without updater-owned conversions or pruning. |
| app/app_root.gd quit_app()/exit guards | Unsaved Workshop and active recorder completion can defer or reject quitting. | Prepare installation only after the normal exit transaction accepts; never kill the game to meet a timeout. |
| app/app_root.gd route selection; ui/startup.gd; renderer_guard.gd | Any ordinary user argument can choose direct flight; renderer recovery can intentionally restart into Compatibility. | A naive --updated flag breaks Home routing. Health protocol must account for intended restart and actual successful Home readiness. |
| site/publish.py | Explicit root-file allowlist; assets/ is deleted and recopied in an isolated gh-pages checkout. | Use a coordinated updates/ namespace, not assets/. Adding a source JSON file alone will not publish it. |
| .github/workflows/ci.yml | Release concurrency is per tag; source-branch pushes only run CI for main, while PRs run CI. | Different release promotions need shared-channel serialization; a research-branch push alone is not a CI pass. |

### Player-data rollback is a real compatibility problem

The current preferences code adds vehicle_skins without changing its then-existing
schema. The v0.2.7 writer builds a new ConfigFile without that section. A player
using a new skin selection could therefore lose it after returning to v0.2.7 and
saving, even while schema guards accept the file. Creator selection also has a
future-schema path that old writers must leave read-only.

This is source-based risk evidence, not an executed user-data-loss experiment.
It demonstrates why binary rollback alone cannot certify preference rollback.
Preserve newer records, qualify each writer and avoid restoring an entire older
profile over concurrent or subsequent player activity.

## Published-package observation

The live Releases API reported v0.2.8, published 2026-11-14, as the newest entry
in the inspected five-release page. Both inspected v0.2.8 and v0.2.7 releases
reported immutable=false. This observation does not establish repository-wide
immutability settings. [Exact API evidence](release-observation.json).

| Platform | v0.2.7 ZIP bytes | v0.2.8 ZIP bytes | v0.2.8 decimal GB |
| --- | ---: | ---: | ---: |
| Windows x86_64 | 1,501,300,919 | 1,501,341,464 | 1.501 |
| Linux x86_64 | 1,495,524,385 | 1,495,576,887 | 1.496 |
| macOS universal | 1,523,598,778 | 1,523,644,106 | 1.524 |

A small difference in total ZIP size is **not** evidence that a binary patch is
small. No complete package pair was downloaded and no delta savings were measured.
At an ideal sustained 10 Mbit/s, the Windows v0.2.8 archive alone takes approximately
20 minutes; at 50 Mbit/s, approximately 4 minutes. These are calculated
size × 8 / link-rate illustrations, excluding overhead and installation.

All three packages remain below GitHub's documented per-asset limit of 2 GiB.
Their current size makes reliable resume, enough temporary disk space and an
eventual differential experiment materially useful.

A bounded request for the final 65,536 bytes of the Windows asset returned HTTP
501 in this execution environment; its body was not read. This is inconclusive
for GitHub/CDN Range behavior and must not be reported as GitHub lacking resume.
No signed redirect URLs or credentials are retained.

## Selection rationale

- **Adapted:** reuse the existing notice, version/build evidence, strict publication
  verification and external user data; require signatures before automatic execution.
- **Accepted for the research architecture:** separate discovery, transport,
  verification and platform apply. This allows full archives, a framework adapter
  or deltas to evolve without rewriting the whole UI.
- **Rejected as a complete first solution:** a browser redirect alone, in-place
  overwrite of a running game, git pull on player machines, PCK hot overlays,
  a new storefront, a permanent launcher or a paid update backend.
- **Kept as comparison candidates:** Velopack with an actually tested no-stub path,
  Sparkle for Mac if receipt/layout and signing constraints are solved,
  AppImageUpdate if the Linux delivery owner adopts AppImage.
- **Deferred:** delta and modular-content benefits until actual measurements;
  unattended rollback across incompatible data schemas; blanket atomicity claims.

Two bounded research helpers investigated platform frameworks and GitHub delivery.
A source follow-up identified package receipts, argument routing and user-data
ownership. An independent Good Enemy challenged recovery reachability, feed
publication ordering and downgrade data loss. The lead inspected the relevant
source, incorporated these constraints and owns the final proposal. Requested
helper settings were Terra/max; effective provider settings were not independently
verified.

## Evidence boundary and next decision

The next consequential decision is DT-UPD-01: a real package spike must show that
the chosen helper/framework can update OpenRC's exact release set while keeping
ordinary and recovery launches reachable after interruption. If no candidate
meets that contract with the current layout, change the packaging contract or ship
the assisted verified-download slice first.

Local protocol results and remaining unrun gates are recorded in
[validation](validation.md). No application source, workflow, production key,
release asset, Pages deployment or repository protection setting is changed by
this research.
