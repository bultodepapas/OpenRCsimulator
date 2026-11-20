# Validation record and future acceptance matrix

DT-UPD-00, 2026-11-17. [Plan](../../../plans/github-updates.md) ·
[Design](design.md) · [Protocol draft](../../../../research/github-updates/README.md).

## What was actually checked

The original checks below belong to the first research commit. This follow-up
changes documentation and evidence only; it retains the existing 30-test result
without presenting it as TUF coverage or rerunning unchanged model code.

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

## Follow-up source review

The [27-case survey](game-update-survey.md) and [JSON ledger](survey-evidence.json)
add 20 game/game-engine projects and seven update/security tools, with 115 distinct
commit-pinned primary files. Three bounded researchers supplied source evidence;
the lead inspected decision-driving original files, reconciled the claims and
authored the integrated design. An independent Good Enemy challenged the result.
Requested helper settings were Terra/max; effective provider settings were not
independently verified.

Accepted review findings include latest trusted-root selection, persistent cache
corruption, cross-process ownership, verified stream completion, product-version
policy separate from metadata versions, bounded withdrawal freshness, authenticated
legacy-install ownership and timestamp-last publication. A categorical claim that
tough lacks delegation was withdrawn after checking current implementation and the
vendor advisory against a stale source-header comment. Initial scope remains four
top-level roles; no delegated-channel isolation is claimed.

The fixed-head comparison to main 08f948265d40d83fbb4726a302b9e1c9490ccfce found
the reviewed updater/export/release/receipt/profile boundaries unchanged from the
original baseline. Nearby queue-trigger changes are not native updater evidence.
No merge/rebase, third-party updater execution, patch benchmark, key generation,
production dependency change or live deployment is part of this follow-up.

Final review corrections distinguish indirect descriptor authentication from a
direct ZIP signature; bound unknown/new root and unseen-withdrawal expectations;
require the earliest expiry of the complete accepted trust chain; and distinguish
HDiffPatch's single-stream format from actual compression selection. The lead
checked the pinned source and resolved these before publication.

Integrated follow-up verification:

| Check | Result | Boundary |
| --- | --- | --- |
| Relative documentation links | 78 resolved, including 8 anchors; no missing target/anchor | Owning research packet and changed navigation links, not every link in the repository. |
| Evidence ledger | 27 distinct case repositories; 20 game/engine + 7 tools; 115 distinct pinned file URLs; seven additional guidance records | SHA/URL structure, unique counts and Markdown/JSON agreement checked; source inspection is not upstream execution. |
| Acceptance register | T01–T82 unique and sequential, all UNRUN | Qualification requirements, not 82 passing tests. |
| Change boundary | Runtime, export/release tools, workflows, website code, dependency pin and Python comparison-model code/tests unchanged | Documentation/evidence continuation only. |
| Targeted independent review | Concrete trust, delta, publication and help findings resolved through source inspection and document corrections | Does not certify future native implementations. |
| Earlier protocol suite | Existing 30-test result retained; unchanged code not rerun in this follow-up | Custom-envelope comparison only; no TUF test result claimed. |

Staged whitespace validation passed for the 13 documentation/evidence files.
Product cases T01–T82 remain **UNRUN**.

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
| T02 | Change authenticated metadata/descriptor bytes; alter signature/key ID | Reject before authorizing a package download or extraction; use the chosen protocol's verification workflow. |
| T03 | Unknown key, invalid signature, malformed base64/UTF-8, duplicate fields, NaN, huge/deep JSON | Bounded deterministic refusal; no crash, side effects or fallback to unsigned metadata. |
| T04 | Expired/future feed, clock moved backward/forward, first-contact stale metadata | Respect documented validity/clock policy; offline play continues. |
| T05 | Older metadata/sequence; changed same-version immutable object; intact cache | Reject rollback and changed immutable identities under the chosen protocol; the comparison envelope also rejects same-sequence equivocation. |
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
| T24 | Descriptor-authenticated archive disagrees with its bound release manifest/source | Reject; no trust by filename or tag alone. |
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
| T56 | CDN stale metadata, delayed Pages visibility, Pages 429/outage | Authentic target consistency; retry without blocking play or using unsigned data. |
| T57 | Withdraw a faulty release and renew same-version metadata | Newer authenticated policy works within documented freshness limits; no replacement of old published bytes. |
| T58 | Actual code-only/asset/native/engine version pairs | Measured delta bytes, generation/apply time, p50/p95, peak RSS/disk and final exact hash. |
| T59 | Skipped release, missing base archive, modified base, corrupt/oversized patch | Full-package fallback; never download a base just to save a smaller patch. |
| T60 | Native PCK/chunk experiment with exact-replay and bundle/native identity | Composite identity preserved or new contract explicitly admitted; startup/load cost measured. |
| T61 | Offline use, opt-out, manual checks, UI navigation/localization | Game remains usable; explicit consent; 1080p-first review without focus theft. |
| T62 | First bootstrap install and long-inactive client | Clear one-time manual upgrade; old client/key/protocol recovery is real and documented. |

## Survey-derived qualification cases

These 20 additions make the new source findings falsifiable. They supplement
T01–T62; they are neither implemented tests nor passing upstream results.
G/U identifiers refer to the [repository survey](game-update-survey.md).

| Case | Concrete fixture / precedent | Required result |
| --- | --- | --- |
| T63 | TUF descriptor stream returns useful-looking bytes, then hash/length error (U06) | No descriptor interpretation, download decision or execution before verified completion; bounded buffering. |
| T64 | Rotate root, skip releases, then restart or roll back the game with stale bundled root (U06) | Latest verified root remains authoritative. A known newer-root requirement or unverifiable chain causes refusal; a client with no higher-root evidence may accept still-valid old metadata. Never silently reset established trust. |
| T65 | Tear/truncate timestamp/snapshot/root/cache files; distinguish legitimate role-key rotation (U06) | Established high-water state is recovered or updates stop; malformed local state cannot silently erase rollback protection. |
| T66 | Two installs refresh one trust store while one crashes during persistence (U06–U07) | Cross-process ownership and durable state remain coherent; each apply journal stays bound to its own install. |
| T67 | Attacker controls only timestamp or snapshot key (U06–U07) | Cannot authorize a new executable/descriptor without targets authority; freshness/denial limits are explicit. |
| T68 | Versioned targets/snapshot or hash-prefixed descriptor unavailable when timestamp appears (U06–U07) | Consistent retry/refusal, no mixed generation; publisher verifies immutable objects before promoting timestamp. |
| T69 | Scheduled job delayed/disabled; targets expires while timestamp renews (G04, N03) | Offline play continues; update blocked with accurate help; offline targets signing and manual renewal are actually rehearsed. |
| T70 | SSL, parsing, rate-limit or offline failure during a check (G06, G18) | Failed or Not checked, never a falsely successful Current result; retain last successful check time. |
| T71 | Notification-only/content-only/unqualified native capability (G05, G08–G10, G14) | UI exposes only available actions; an assisted download is not labelled automatic installation. |
| T72 | Legacy install has unknown custom files and no complete trusted baseline inventory (G03, G15) | Preserve old tree; establish ownership from trusted evidence or offer side-by-side/assisted migration; no guessed cleanup. |
| T73 | Butler output commit succeeds, then optional validation fails (U01–U02) | Only isolated candidate is affected; independently verify every target before any OpenRC activation. |
| T74 | Correct-looking version but wrong/mutated rdiff or binary-patch basis (U03, U05) | Exact source identity rejected before patching; no garbage candidate becomes active. |
| T75 | Directory patch omits a library/receipt/mode/link, or includes extra files (G14, U01–U02) | Full authenticated inventory and full-install equivalence fail; no comparison of a directory to a ZIP digest. |
| T76 | First capable update after manual ZIP was deleted (U02–U05) | Record actual base eligibility; select full target when needed, never download an old ZIP just to claim delta savings. |
| T77 | Repeat export of identical source/toolchain with different timestamps/order/compression (G19, U05) | Attribute measured byte churn; preserve signing/receipt/replay identity before any packaging change. |
| T78 | Delta fails and full fallback exceeds approved transfer bytes (U02–U05) | Explain new size and obtain download consent; installed game remains usable. |
| T79 | Large compressed executable, adversarial patch windows or decompressor allocation (G17, U05) | Real RSS/CPU/output/disk limits hold; a cache flag or payload header is not mistaken for a whole-process bound. |
| T80 | Mutable nightly tag, complete-looking asset count, misleading architecture filename (G11–G13) | Exact source/OS/CPU/asset identities verified and descriptor promoted only after public byte checks. |
| T81 | Prepared target expires or is withdrawn before/after pre-exit refresh; refresh unavailable (G04, U06–U07) | Require pre-apply refresh; after exit recheck observed eligibility and earliest expiry of the entire accepted chain. An unseen later withdrawal may remain installable within validity; failed refresh stays ready. |
| T82 | Old helper restored with old binary but newer trust state/profile remains (G15, U06–U07) | Compatible use or explicit refusal/recovery; no trust/profile reset and no false claim that binary rollback restores all state. |

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
