# Validation record and future acceptance matrix

DT-UPD-00, 2026-11-17. [Plan](../../../plans/github-updates.md) ·
[Design](design.md) · [Protocol draft](../../../../research/github-updates/README.md).

## What was actually checked

| Check | Result | Boundary |
| --- | --- | --- |
| Frozen source audit | Completed at 2a3cf04dbbdaf486b9c9c8e983463d828f90c64a | Source analysis, not executed package lifecycle. |
| Live GitHub Releases metadata | v0.2.8/v0.2.7 sizes, names, API digests and immutable flags retained | No full archives were downloaded or independently hashed. |
| Bounded real-asset Range probe | HTTP 501 in this environment; no body consumed | Inconclusive for GitHub/CDN resume; not a negative platform result. |
| Offline draft protocol suite | 30 tests passed; includes malformed subcases, key-alias substitution and independent RFC 8032 vector | Signature/metadata and response-decision model only. |
| Documentation checks | 36 relative links checked; no missing targets/anchors; staged whitespace check clean | New packet and added navigation links, not a whole-repository documentation audit. |
| Runtime game, installer and platform lifecycle | Not run | Production application and packaging are unchanged. |
| Delta benchmark | Not run | No percentage reduction, apply time or memory saving is claimed. |
| GitHub Actions / real release publication / Pages promotion | Not run for this research branch | No deployment, tag, release, key or repository-policy mutation. |

Recorded local environment: Python 3.12.14, Cryptography 50.0.0.
Command:

~~~sh
python3 -m unittest discover -s research/github-updates -p 'test_*.py' -v
~~~

The dependency was already installed. No virtual environment, package installation,
runtime dependency or production key was added. The tests contain only generated
memory-local fixture keys and public RFC verification material.

The independent review specifically examined ordinary-launch disappearance during
interrupted replacement, Mac sibling receipts, Pages allowlisting/concurrency,
update argument routing, renderer restarts and same-schema preference loss.
Those findings became requirements or explicit non-claims in the design; they
are not closed native implementation gates. Candidate review also found and
resolved release-ID/signing order, signature-bound key IDs, preview subscription
versus artifact channel, and extracted-tree versus ZIP-digest distinctions.

The independent closure review found no remaining mismatch in the four corrected
findings; three focused signature tests also passed. A branch push alone does not
run the current main/PR CI workflow.

## Acceptance rule

For every supported platform/layout, retain before/after package and profile
hashes, exact source/tool/OS/filesystem identities, command/launch path, transaction
journal and test result. A synthetic model or cross-export cannot substitute for
a native downloaded-artifact test. Mark cases as pass, fail or inconclusive;
never infer pass from a missing log, launched process or timeout.

The local case numbers below are acceptance identifiers within this document,
not new global roadmap steps. **All product cases remain UNRUN.** Some individual
parser/HTTP decisions have draft-unit coverage; that does not pass their complete
end-to-end cases.

## Trust, feed and selection

| Case | Exercise | Required result |
| --- | --- | --- |
| T01 | Valid stable release on each supported platform | Correct archive, architecture, exact source and manifest selected; installed version bound. |
| T02 | Change one signed-payload byte; alter signature/key ID | Reject before payload interpretation, download or extraction. |
| T03 | Unknown key, invalid signature, malformed base64/UTF-8, duplicate fields, NaN, huge/deep JSON | Bounded deterministic refusal; no crash, side effects or fallback to unsigned metadata. |
| T04 | Expired/future feed, clock moved backward/forward, first-contact stale metadata | Respect documented validity/clock policy; offline play continues. |
| T05 | Older sequence; same sequence with different bytes; intact same-sequence cache | Reject rollback/equivocation; accept only valid identical cache. |
| T06 | Wrong repository/product/channel, unsupported protocol/OS/architecture | No automatic install; meaningful manual fallback. |
| T07 | Stable/preview transitions, preview → final stable, skipped versions, equal version, downgrade | Distinguish subscription and artifact channels; no unintended prerelease or downgrade. |
| T08 | Key rotation, client missing the transition, signing-key loss/compromise | Exercise the documented trust path or independent bootstrap; no claim old-key-only rotation repairs compromise. |
| T09 | Canonical URL changed, HTTPS downgrade, unexpected redirect host, redirect loop | Stop safely; no credentials leaked; never execute remote path/arguments. |

## Transfer

| Case | Exercise | Required result |
| --- | --- | --- |
| T10 | Slow 1.5+ GB download, including cold Home and low bandwidth | Bounded RSS/CPU, responsive UI, useful progress, no inappropriate metadata-sized deadline. |
| T11 | Interrupt, pause, cancel, sleep and resume transfer | Installed app untouched; valid partial state is recoverable or safely discarded. |
| T12 | Range accepted with 206 | Exact offset/total/body bounds; final target hash matches. |
| T13 | Range ignored with 200 | Restart/truncate; never append a full response to partial bytes. |
| T14 | Wrong Content-Range/length, multipart, compression or 416 | No unsafe append; verify complete local bytes or restart as appropriate. |
| T15 | CDN redirect expiry, 403/429/5xx, DNS/TLS failure, corrupt partial cache | Canonical-URL retry and bounded backoff; normal TLS; no retry storm. |
| T16 | Disk fills mid-download, target filesystem disappears | Stop without corrupting active/previous installs; clear cleanup/retry route. |
| T17 | Archive has correct length but altered content | Signed SHA-256 rejection before extraction. |
| T18 | Two downloads/instances, target version changes while downloading | Isolated target-bound files; explicit revalidation, no mixed package or cross-install cancellation. |

## Archive and package admission

| Case | Exercise | Required result |
| --- | --- | --- |
| T19 | Absolute, parent-traversal, UNC/drive/ADS, reserved, duplicate or Unicode/case-colliding names | Reject before any out-of-root effect. |
| T20 | Symlink/hardlink/reparse/device and preexisting parent-link attacks | Enforce qualified platform policy; no link escape. Preserve legitimate admitted Mac bundle structure. |
| T21 | ZIP bomb, misleading expanded size/count, truncated metadata, extreme nesting | Enforce actual stream limits, disk budget and bounded work. |
| T22 | Missing/wrong executable, native library, mode or architecture | Reject staged generation; never install a plausible partial set. |
| T23 | Correct Mac .app plus absent/stale/mismatched reference or native receipt | Reject incoherent release; preserve old app and exact receipt pair. |
| T24 | Signed archive disagrees with signed-bound release manifest/source | Reject; no trust by filename or tag alone. |
| T25 | Current runtime integrity and exact-replay package checks after update | Same identity contract as a complete qualified release; no silent script/PCK overlay. |
| T26 | Dirty/custom install or unmanaged files inside target folder | No destructive sync/delete; assisted migration or explicitly preserved managed-generation policy. |

## Commit, recovery and restart

| Case | Exercise | Required result |
| --- | --- | --- |
| T27 | Unsaved Workshop, active recorder, failed save or player cancels quit | Existing exit transaction wins; no forced kill or file replacement. |
| T28 | Another instance or stale lock with reused PID | Ownership-safe wait/refusal; no interference with another live installation/process. |
| T29 | Stop helper before/after every journal write and flush | A specified recoverable state; no invented transaction completion. |
| T30 | Stop helper between each rename/replace; reboot there | Ordinary launch or the documented separately reachable repair works; old/new coherent generation, never an absent unrepairable app. |
| T31 | Locked DLL/executable, antivirus interference or permission loss | Bounded failure/recovery; no partially reported success. |
| T32 | Disk full during extraction, commit, journal or rollback | Active/last recoverable generation retained; no destructive space reclamation. |
| T33 | Cross-volume staging, removable/network/filesystem variants | Refuse unsupported semantics or use the separately qualified strategy. |
| T34 | Restart through actual shortcut/direct binary/Finder entry | Correct complete new version; no stale link or dependency mix. |
| T35 | Naive extra user argument, protected transaction signal replay/spoof | Test deliberate routing/IPC design; Home is reached, unrelated direct-flight behavior preserved. |
| T36 | Engine/autoload/preload/script/resource failure before Home | No false health acknowledgement; preserve/recover old version and diagnostic evidence. |
| T37 | Renderer guard intentionally restarts in Compatibility | Bind successor to the transaction; no premature rollback based only on initial PID exit. |
| T38 | Slow cold startup, hidden/minimized app, early user exit, genuine crash | Correct classified outcome; no short false timeout or rollback during active player work. |
| T39 | Helper update fails or new helper is incompatible with old journal | Old trusted recovery route remains callable; no unverified helper execution. |
| T40 | Cleanup interrupted, retry repeated, recovery invoked twice | Idempotent bounded behavior; never delete active/needed previous or user-selected historical build. |

## Player data and native platforms

| Case | Exercise | Required result |
| --- | --- | --- |
| T41 | Real settings, settings.cfg.display, radio calibration/profiles and backup/lock files | Preserve bytes unless an explicitly tested owner migration is required; no apparent reset. |
| T42 | Creator objects/indexes, drafts/recovery, variants/compiler pins, skins | Content remains discoverable and admissible; no updater rewrites or recovery pruning. |
| T43 | Recordings, exact replays, traces/spools, statistics and race data | Preserve originals and correct historical compatibility; do not claim new solver equivalence. |
| T44 | Upgrade then rollback across newer schemas | Preserve unsupported records; qualified read-only/recovery path, no blind profile restore. |
| T45 | Same-schema new field: vehicle_skins versus v0.2.7 writer | Demonstrate no silent newer-value loss, or explicitly block unsafe writable rollback. |
| T46 | Two installations/versions share the same user-data directory | Locks/migrations preserve concurrent or subsequent player changes. |
| T47 | Paths with spaces/non-ASCII/long names; per-user versus read-only install | Correct normal/recovery entry paths; no default elevation or shell quoting injection. |
| T48 | Windows native downloaded update and realistic antivirus/file-lock behavior | Actual normal launch/update/recovery on each declared supported Windows baseline. |
| T49 | Linux native archive permissions, libraries and qualified local filesystem | Actual direct launch, native admission and interrupted update behavior. |
| T50 | macOS downloaded/quarantined universal .app in Downloads/Applications/read-only location | Correct trust UX, attributes, receipts and translocation handling; never disable Gatekeeper as the updater's remedy. |
| T51 | macOS Intel and Apple Silicon, explicit Rosetta if supported | Match architecture/renderer/native identity; do not infer from a Linux-hosted ZIP inspection. |

## Release operations and efficiency

| Case | Exercise | Required result |
| --- | --- | --- |
| T52 | Partial release upload, duplicate retry, deleted asset or wrong public bytes | Feed not promoted; existing publisher refusal/provenance retained. |
| T53 | New immutable-release policy plus draft/assets/publication | All assets attached before publish; real retry and failure semantics qualified. |
| T54 | Different-tag release jobs finish out of order | Channel-wide monotonic promotion; older job cannot regress the feed. |
| T55 | Concurrent website publish and feed publish; later normal site refresh | Whole site and updates/ remain intact; actual Pages build/deploy occurs. |
| T56 | CDN stale envelope, delayed Pages visibility, Pages 429/outage | Authentic target consistency; retry without blocking play or using unsigned data. |
| T57 | Withdraw a faulty release and renew same-version metadata | Higher-sequence signed policy works; no replacement of old published bytes. |
| T58 | Actual code-only/asset/native/engine version pairs | Measured delta bytes, generation/apply time, p50/p95, peak RSS/disk and final exact hash. |
| T59 | Skipped release, missing base archive, modified base, corrupt/oversized patch | Full-package fallback; never download a base just to save a smaller patch. |
| T60 | Native PCK/chunk experiment with exact-replay and bundle/native identity | Composite identity preserved or new contract explicitly admitted; startup/load cost measured. |
| T61 | Offline use, opt-out, manual checks, UI navigation/localization | Game remains usable; explicit consent; 1080p-first review without focus theft. |
| T62 | First bootstrap install and long-inactive client | Clear one-time manual upgrade; old client/key/protocol recovery is real and documented. |

## Benchmark receipt to produce later

Retain the following for every efficiency experiment:

- Old/new published tag, source commit and independently verified archive SHA-256.
- Actual old base availability, file inventory and exact engine/export/patcher versions.
- Scenario (code, scenery, native library, engine or skipped version) and platform.
- Full/patch/metadata bytes and request count, excluding neither a fetched base nor fallback.
- Generation and application time, peak memory, peak additional disk and cold-start effect.
- Exact reconstructed target hash, package/receipt/replay validation and failure outcome.
- Modest-machine and representative higher-end machine results at declared hardware/OS.

Keep full-size assets external to Git. Retain small summaries, hashes and a
regeneration/download recipe. No benchmark number is accepted solely because
the total sizes of two ZIPs are nearly equal.
