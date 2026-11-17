# Proposed updater architecture

DT-UPD-00, 2026-11-17. This is an implementation contract to test, not implemented
runtime behavior. [Plan](../../../plans/github-updates.md) · [Sources](sources.md).

## 1. Components and boundaries

| Component | Responsibility | Cannot assume |
| --- | --- | --- |
| Existing game UI | Check policy, present update/release notes, consent, progress and graceful exit | It cannot safely replace its own loaded executable/libraries. |
| Discovery/verifier | Fetch a small bounded signed channel envelope; verify pinned trust and policy | API metadata, TLS or a colocated SHA256SUMS alone do not authenticate the publisher independently. |
| Transfer/staging worker | Stream bytes to a private partial file, resume correctly, hash, extract and verify a new generation | An HTTP success or ZIP hash alone does not establish safe extracted paths or a runnable install. |
| Native apply/recovery helper | Recheck the approved transaction; wait for owned processes; commit/recover using an OS adapter; launch the target | Generic directory rename sequences are not cross-platform atomic or automatically recoverable. |
| Release publisher | Preserve source/package qualification and publish exact tested bytes | A newer tag, successful cross-export or signed feed does not establish native lifecycle acceptance. |
| Channel publisher | Publish a signed pointer after verified public assets; serialize promotion | Release publication and Pages deployment are not one transaction. |

Keep these interfaces stable so an adapter can wrap a qualified existing framework.
Reuse mature HTTP, signature, archive and filesystem libraries rather than writing
cryptographic primitives or a ZIP extractor. DT-UPD-01 chooses language/libraries
and pins exact versions/licenses. Existing C++ build infrastructure is a useful
candidate; a small Rust helper is another, not a settled new dependency.

The installed, trusted helper performs security checks. Never download an unsigned
helper and run it to verify its own package. Updates to the helper are authenticated
by the previous trusted updater and preserve a compatible recovery copy outside
the generation being replaced. No runtime Python, Git, Godot editor or compiler
is required on a player's machine.

## 2. GitHub discovery and channels

Proposed URLs are /OpenRCsimulator/updates/stable.json and
/OpenRCsimulator/updates/preview.json on the existing GitHub Pages site. These
files do not exist as part of this research deployment. Do not put packages on Pages.

One response contains an envelope with a fixed protocol marker, key ID, exact
base64-encoded UTF-8 payload bytes and a detached Ed25519 signature. Sign a fixed
application/protocol domain prefix, validated ASCII key ID, a NUL separator and
those exact payload bytes. This also prevents changing a key alias without
re-signing. It avoids ambiguity
from JSON reserialization and the cache race of separately fetched payload and
signature files. Reject duplicate JSON keys, non-finite numbers, invalid UTF-8,
unknown fields/version, excessive sizes/depth and unsupported algorithms.

The production contract must bind:

- Repository and channel; a monotonically increasing per-channel sequence.
- Issued and expiry times; supported updater protocol/version.
- Release ID/tag/version, source commit and clean official release provenance.
- Exact release-manifest URL, byte length and SHA-256.
- Per-platform architecture, ZIP URL, byte length, SHA-256, expanded-byte and
  member-count bounds, plus OS/format requirements.
- Future withdrawal and key-transition types with separate, closed validation;
  they are not arbitrary remote commands.
- Future deltas' exact base identity, patch identity/algorithm/bounds and target
  identity, while retaining the corresponding full package.

URLs are exact HTTPS release-download paths under this repository and a fixed
tag/filename, not /latest links or arbitrary hosts. An install path, shell command,
post-install hook or executable argument never comes from the feed. Entrypoints
and supported layouts are compiled client policy plus verified package metadata.

Persist the highest authenticated sequence and payload hash per channel using a
durable atomic local replacement. Lower sequence is rejected; the same sequence
with different bytes is rejected. Repeated identical still-valid metadata is fine.
A higher sequence pointing to an older game must not cause automatic downgrade;
local restoration of a recorded previous generation is a separate recovery action.

The reference draft implements a stable-channel subset with fixed platform names,
a single pinned-key verifier and no install actions. It intentionally omits release
ID, root delegation, preview selection, withdrawal and deltas until their production
contracts are implemented and tested. It is not the production schema.

Check after Home is available, at most daily automatically, with cache, jitter and
bounded backoff. Check now has its own cooldown. ETags reduce bytes; anonymous
GitHub API 304 responses are not promised to be free of quota. Prefer the signed
Pages feed, retain the canonical Release page as manual fallback and avoid
automatically fanning out to API endpoints after every Pages failure.

Keep subscription channel distinct from artifact channel: a preview feed may
offer either a preview artifact or its final stable successor; a stable feed may
offer only stable artifacts. Reconcile the artifact channel with its tag and
release manifest, not by requiring equality with the subscription channel.
Keep a stable default and explicit preview opt-in. The current natural prerelease
ordering differs from strict SemVer; use a tested migration policy, not string
ordering. Reset/revalidate cached selection when channels change.

## 3. Trust and the zero-budget operating model

HTTPS protects transport; a pinned public key authenticates update metadata;
SHA-256 binds package bytes; OpenRC receipts bind build/runtime identity; OS
publisher signing affects platform trust prompts. These are separate boundaries.

For the initial bespoke design, use an offline-controlled Ed25519 release-signing
key, protected backups and a deliberate signing step after package verification.
The helper ships only public keys. Keep private keys out of Git, player builds,
logs and the repository's ordinary CI environment. This provides useful separation
from a repository-only compromise, at the cost of maintainer work.

**Deliberate threat limit:** the small single-key protocol does not recover safely
from compromise of its trusted signing key. An attacker able to sign arbitrary
replacement game code can also change future verifier behavior. Normal key
rotation can use a transitional release trusted by older clients; compromise or
loss without a usable prior trust path requires an independently obtained bootstrap.
A second interchangeable update key is not by itself a cure for that problem.

Before production, compare this operational burden with a maintained TUF client:
offline root, delegated online roles, expiry/version checks and threshold policies
provide a more established model, but require metadata and key operations.
Do not call the prototype TUF or invent an incomplete TUF implementation.
Keep signing authority independent of hosting when that is the claimed threat model.

Use a proposed 90-day metadata horizon and renew by day 60; renewals increment the
sequence. Expiry stops new installs while permitting offline play. Use wall time
for signed validity, a monotonic clock for in-process deadlines, and detect large
backward/forward clock anomalies against retained observations. Reject automatic
installation and explain correction when time cannot be trusted; do not silently
disable expiry. First-contact freshness and freezes within the valid period remain
limited. Local same-user malware, compromised signing/build machines and compromised
OS trust are outside the protection this protocol establishes.

GitHub release immutability and tag rules are desirable additional controls.
Enabling them is a separate future repository operation. Inspect current settings
and publisher semantics first; do not rewrite old tags or assume existing v0.2.8
assets became immutable retroactively.

## 4. Download and bounded preparation

Use the signed size to calculate progress and enforce a hard upper bound. Stream
to disk with bounded buffers, Accept-Encoding: identity, normal TLS verification,
bounded redirects and idle/progress timeouts distinct from overall transfer time.
A short metadata timeout is not a suitable overall timeout for a 1.5 GB download.

Follow only HTTPS redirects allowed by an explicit tested GitHub delivery policy.
Retain the canonical release URL, not an expiring signed CDN URL; reacquire redirects
on retry. Strip authentication and cookies across redirects; players send no token.
Do not log signed query strings. A changed CDN host requires qualified policy
maintenance, not an unrestricted URL fetch or disabled certificate check.

Partial-download state binds target URL/tag/hash/size and byte offset. When resuming:

| Response | Required action |
| --- | --- |
| 206 with the exact requested start, coherent range/total and matching bounded body | Append only those bytes, then retain the new durable offset. |
| 200 when Range was requested | Truncate/restart into a new full transfer; never append. |
| 416 | Rehash a local file only if its exact length already equals the signed target; otherwise restart. |
| Changed length, target, validator or inconsistent Content-Range | Discard/quarantine that partial state; reacquire a fresh transfer. |
| 403/429/5xx/network loss | Honor valid Retry-After, apply bounded backoff and preserve a valid partial; the installed game remains usable. |

Server Range support is an empirical qualification item. A precomputed patch is
an ordinary asset and does not require Range support; resumable downloads do.

Before extraction, require both signed exact length and SHA-256. Before apply,
also download/verify the bound release manifest, reconcile the source commit,
tag, artifact channel and selected ZIP identity/size, and check
the selected ZIP and staged runtime layout. A platform client need not download
the other two OS packages merely to update itself. It cannot invoke the current
six-file desktop verifier unmodified on one ZIP; add a deliberately scoped
single-target admission function with independent tests. The GitHub release ID
is observed and signed by the publisher; the current release manifest does not
contain it. The client cannot claim an independent API-ID comparison unless it
deliberately makes and verifies that separate API request.

Secure extraction must reject path traversal, absolute/drive/UNC names, NTFS
alternate streams, reserved names, normalization/case collisions, duplicate
members, hard links/devices and out-of-root destinations. Windows reparse points
and already-existing symlink parents are hazards even with clean ZIP names.
Create an exclusive private staging directory on the target filesystem and do
not follow existing links. Count actual bytes and files while expanding, not
only advertised ZIP sizes. Bound CPU/time and decompression ratios with real
package exceptions reviewed explicitly.

Windows/Linux initial policy can reject archive symlinks if their qualified
inventory permits. A Mac framework can legitimately contain relative symlinks:
if required, allow only validated links and targets wholly inside the staged
bundle, with an extraction order that cannot escape through them. Do not break
macOS bundles through a blanket rewrite. Preserve required modes, signed bytes,
bundle structure and receipt siblings.

Approximate free-space requirement before preparation is:

**new compressed package + new expanded generation + patch/output scratch (if any)
+ journal/data-migration backups + safety reserve**, in addition to already-used
space for the current installation and any previous retained generation.

Measure each filesystem separately if download storage differs from the final
install volume. Recheck throughout; never delete the active or only recoverable
old generation to make room. Report bytes to the player. Retain one previous
qualified generation by default; preserve user-selected historical builds and
let users explicitly remove additional cache. Archive caching for deltas must
be a measured tradeoff, not a hidden extra 1.5 GB requirement.

## 5. Apply, durable recovery and platform layout

The unit of installation is a complete immutable generation of managed files.
Do not overwrite an arbitrary extracted folder containing player-added files.
Inventory ownership at bootstrap; unknown/unmanaged additions cause assisted
migration or explicit preservation, not deletion.

Proposed state contract:

| State | Invariant / durable boundary |
| --- | --- |
| Offered | Only authenticated metadata is available; installed bytes unchanged. |
| Downloading | Private target-bound partial file; installed bytes unchanged. |
| Verified | Full archive identity verified; no archive content executed. |
| Staged | New complete generation admitted, same-volume commit strategy prepared. |
| Exit requested | Existing Workshop/recording transaction owns consent/save completion. Cancellation returns to ready. |
| Prepared | Per-install owner lock acquired, actual relevant game processes exited, journal and recovery path durable. |
| Applying | OS adapter performs its qualified commit; every interrupted substep has a specified recovery action. |
| Awaiting health | New generation is launched through its ordinary route, previous generation preserved. |
| Committed | Exact transaction/build reports qualified startup; retention can run later. |
| Recovery required | No mixing of generations, repeated destructive retry or profile overwrite; restore known complete bytes or present the tested repair action. |

Use native process handles/start identities and installed-root identity, not a
PID alone or a caller-supplied arbitrary path. Do not forcibly terminate the game
after a short timeout while it may be asking to save. Lock stale-owner recovery
must establish that the former owner is gone; unknown ownership means stop.

Journal writes need atomic replacement and appropriate flush/directory durability
for the qualified filesystem. This is an implementation/measurement obligation,
not a promise that a successful rename is power-loss durable.

### The missing-executable problem

If the algorithm renames the current install to backup and then staging to current,
power loss between the two can remove the player's normal launch target. The
new app cannot read the journal if it cannot start. A leftover helper process
does not survive a reboot, and this design does not install an always-on service.

The initial adapter therefore needs a recovery helper/entry **outside every moved
generation**, installed before mutation, plus a discoverable recovery action.
That is user-assisted repair after this class of crash, not unattended recovery.
A normal game icon should still start a complete old or new generation wherever
the OS/layout can guarantee it; qualify that separately. Never market the two-step
rename alone as seamless automatic rollback.

DT-UPD-01 must test two possible ways to improve this:
(1) a proven existing framework without a mandatory launcher;
(2) a packaging change that stages immutable generations and commits through one
qualified platform operation while every dependency/receipt refers to the same
generation. OS shortcuts, symlinks and directory exchanges have different
semantics; no generic recipe is approved here. Current fixed filenames/receipt
lookups must be updated and qualified if generation paths change.

| Platform | Specific proof required |
| --- | --- |
| Windows | Old process and loaded DLLs gone; antivirus/file locks; writable per-user portable/install path; Unicode/long paths; exact shortcut/taskbar/direct-EXE behavior after every interruption. A file replace does not atomically replace a multi-file release. No elevation by default. |
| Linux | Same-volume commit; execute bits and native libraries; actual entrypoint/symlink resolution; local filesystem durability. An already running unlinked executable is not proof that a new launch works. Keep AppImage conditional on its own track. |
| macOS | Swap a coherent .app and required sibling receipts; preserve seals/architectures/attributes; Finder launch, quarantine, translocation and writable location. A whole-bundle operation alone is insufficient for current external receipts. |

If these cannot be met on a target, retain assisted verified download until the
layout or adapter is fixed. Tests must use the ordinary user launch action after
crash/reboot, not just invoke a researcher-known backup path.

## 6. Health, restart and profile compatibility

Use the existing graceful quit/save flow. Handoff uses protected local transaction
state/IPC with a fresh nonce, bounded lifetime and exact install/target identity.
Do not append a new Godot user argument without explicit early parsing/stripping:
current routing interprets user arguments as a direct-flight request.

Distinguish:
- helper/engine started;
- package identity and mandatory resources admitted;
- Home successfully constructed and presented, with a bounded stable event loop;
- optional later native/flight diagnostics.

Only the agreed successful Home milestone can complete installation health.
Neither process creation nor home_build_pending becoming false proves readiness.
Engine/autoload/preload failures can occur before GDScript can report anything.
The watchdog must handle the renderer guard's intentional Compatibility restart
and bind its successor process to the same transaction; an initial PID exit alone
is not rollback evidence. Calibrate cold-start deadlines on target machines.

Health is software-startup evidence, not physical-model validation or comprehensive
GPU/radio/flight acceptance. Do not automatically roll back while a player is in
an active flight. Preserve logs and the old generation if diagnosis is inconclusive.

Keep application identity and user-data path unchanged. Preserve all user://
and external user files, including settings/display preferences, radio profiles,
calibration, flight logs/statistics/traces/spools, skins, race results, variants,
Creator objects/indexes and Workshop recovery. Do not copy that entire directory
back from a pre-update snapshot on rollback.

Data owners must specify reversible or forward-compatible migrations, write locks,
copy-on-write backup and old-writer behavior before enabling automatic rollback.
Multiple installed versions share a profile today. Options include safe
backward-compatible storage, version-aware read-only downgrade, or a deliberately
separate preview profile with an explicit import/export UX. No silent profile
split is approved by this plan.

An old build may omit a newly added field even at the same schema number; the
vehicle_skins source example demonstrates this. Retain newer bytes and explain
read-only/manual recovery when compatibility is unproven. Keep exact old game
versions obtainable for historical replay; upgrading does not make an old log's
solver identity equivalent.

## 7. Release and feed publication

Preserve current six-file output and release verification for the first
Pages-only signed-feed pilot. A feed envelope on Pages is not a seventh Release
asset. If release signatures, patch files or alternate packaging are later added
to Releases, explicitly version and update all strict inventories and consumers.

Proposed sequence:

1. Freeze source/tag and build with existing required gates. Generate bounds
   and target metadata from final artifacts, not mutable source strings.
2. Independently verify the complete release set and intended source/run identity.
3. Create the release and upload all assets before declaring it complete. If adopting
   immutable releases, adapt/rehearse the publisher's draft/upload/publish sequence;
   do not assume the present gh release create invocation is an equivalent atomic API.
4. Verify the public release identity and downloaded bytes using the existing
   independent expectations. Test redirects from the canonical public URLs.
5. Now sign the exact channel payload with the offline-controlled key, including
   the actual observed release ID. Store only the signed public envelope with the
   promotion evidence. The ID cannot be guessed or signed before release creation.
6. Under a lock shared by all promotions for that channel and by website publication,
   reject stale promotion attempts, commit the higher-sequence signed envelope in
   updates/, deploy Pages through the actual configured route and verify public bytes.
7. Record release commit, release ID, artifact hashes, envelope sequence/hash,
   Pages commit/deployment and actual test scopes. Never log credentials.

Current site/publish.py does not copy an updates/ source directory. A future
change must deliberately add/preserve that namespace and coordinate concurrent
website/feed pushes. Never put the feed under assets/, which the site publisher
replaces. Do not overwrite the rest of gh-pages with a feed-only deployment.
A GITHUB_TOKEN branch push alone may not trigger the branch-based Pages build;
use a supported deployment or the qualified existing publish route.

Per-tag release concurrency is insufficient to order vN and vN+1 feed promotion.
Use one channel-wide serialized promotion and a compare/revalidate operation
after any branch rebase/retry. A stale job cannot blindly overwrite the current
signed sequence. The public CDN can lag; failures keep the old app working.
No claim of atomic visibility across GitHub Release and Pages is made.

## 8. Delta extension contract

Start only after the full path passes. Bind exact source and target hashes, the
patch's own signature-bound hash/size, algorithm/version and resource limits.
Do not download an old package merely to construct a patch base; full target
download is then the sensible fallback. Rehash the actual base, not a version
label. Produce the target in staging and run the same whole-package validation.

An archive-to-archive patch must reconstruct the exact signed ZIP bytes. An
extracted-file patch cannot be compared directly to that ZIP hash: it needs a new
signed canonical inventory covering the complete managed file tree and relevant
modes/link/bundle metadata, plus equivalence to the full package's installed
generation. That is a separate versioned release/admission contract, not a free
optimization under today's ZIP-only artifact digest.

Never accept an unsigned fallback, a checksum mismatch, a chain of unbounded
patches or a partial application to live files. A smaller network transfer does
not excuse higher RAM that excludes the project's modest-machine targets.
Modular PCK work must revise composite runtime/replay identity and prove exact
base/load order before it becomes a production option.
