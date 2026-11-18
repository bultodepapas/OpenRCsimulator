# Proposed updater architecture

DT-UPD-00, 2026-11-17. This is an implementation contract to test, not implemented
runtime behavior. Expanded after the [27-repository survey](game-update-survey.md).
[Plan](../../../plans/github-updates.md) · [Sources](sources.md) · [Spikes](reuse-spikes.md).

## 1. Components and boundaries

| Component | Responsibility | Cannot assume |
| --- | --- | --- |
| Existing game UI | Check policy, present update/release notes, consent, progress and graceful exit | It cannot safely replace its own loaded executable/libraries. |
| Discovery/verifier | Verify maintained trust metadata and a bounded release descriptor; enforce product policy | API metadata, TLS or a colocated SHA256SUMS alone do not authenticate the publisher independently. |
| Transfer/staging worker | Stream bytes to a private partial file, resume correctly, hash, extract and verify a new generation | An HTTP success or ZIP hash alone does not establish safe extracted paths or a runnable install. |
| Native apply/recovery helper | Recheck the approved transaction; wait for owned processes; commit/recover using an OS adapter; launch the target | Generic directory rename sequences are not cross-platform atomic or automatically recoverable. |
| Release publisher | Preserve source/package qualification and publish exact tested bytes | A newer tag, successful cross-export or signed feed does not establish native lifecycle acceptance. |
| Channel publisher | Publish authenticated selection after verified public assets; serialize promotion | Release publication and Pages deployment are not one transaction. |

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

The preferred investigation uses maintained TUF metadata in a dedicated
/OpenRCsimulator/updates/tuf/metadata/ namespace on the existing GitHub Pages site.
Small release descriptors are TUF targets under updates/tuf/targets/, using the
selected library's hash-prefixed names for consistent snapshots. These namespaces
have not been deployed. Large packages stay on GitHub Releases.

This is an OpenRC integration proposal: TUF authenticates a small descriptor, and
that descriptor binds the actual release ZIP and release manifest. It preserves
the current six-asset Release inventory and avoids trying to fit GitHub's existing
asset names to a chunk store or hash-prefixed target layout. The implementation
must qualify this indirection; TUF does not itself understand OpenRC packages.

Use four top-level roles in the first spike. Stable/preview are target descriptors,
not independently delegated channel keys. The descriptor's closed, bounded schema
must bind:

- Repository, product, subscription channel and artifact channel.
- Release ID/tag/version, source commit and clean official release provenance.
- Exact release-manifest URL, byte length and SHA-256.
- Per-platform OS/architecture, ZIP URL, byte length, SHA-256, expanded-byte and
  member-count bounds, package/OS requirements and minimum updater capability.
- Authenticated withdrawal/eligibility state with explicit closed semantics;
  no arbitrary remote command, filesystem destination or executable argument.
- Optional deltas' exact source, patch identity/algorithm/resource bounds and
  complete target identity, always retaining a full-package alternative.

A streamed TUF target can expose bytes before its final checksum passes. Buffer
these small descriptors within a hard limit and wait for successful complete
length/hash validation before parsing them for any product decision. Reject
unsupported formats, duplicate keys, invalid UTF-8, non-finite numbers and excessive
size/depth. Package download begins only after descriptor authentication and policy
selection. Actual archive bytes remain bounded, streamed and hashed separately.

URLs are exact HTTPS release-download paths under this repository and fixed
release tag/filename. The feed never supplies a shell command or executable path.
Check the resulting artifact's architecture and internal package identity rather
than trusting a filename substring. Native entrypoints are compiled policy plus
verified package metadata.

TUF metadata versions prevent the class of rollback defined by the selected
client/specification when trusted state persists correctly. They do not mean a
newly signed descriptor cannot name an older game. Independently enforce OpenRC's
installed-version, channel and updater-compatibility policy. Local restoration of
a recorded previous generation is a separate recovery operation, with profile
compatibility and trust-state preservation.

Keep subscription channel distinct from artifact channel: a preview subscription
may offer a preview or its final stable successor; stable offers only stable.
Reconcile artifact channel against the tag and release manifest. Preserve the
current natural prerelease ordering through a tested migration; do not substitute
string ordering or unmodified SemVer assumptions. Revalidate selection on a channel
change and preserve relevant trusted-state history.

Check after Home is available, at most daily automatically, with cache, jitter and
bounded backoff. Check now has a cooldown. Prefer Pages metadata and retain a
canonical GitHub manual route; do not fan out to repeated API requests after every
failure. ETags can reduce bytes; anonymous API 304 quota exemption is not assumed.
Distinguish Current from Failed, Not checked and Unsupported.

### The earlier envelope remains a comparison model

The prior stable.json/preview.json proposal and executable Python model use one
Ed25519 signature over a fixed domain, ASCII key ID, NUL and exact payload bytes.
They model a per-channel sequence, expiry and target hashes, with 30 negative and
positive tests. They do not implement TUF, persistent trust, root rotation, release
withdrawal or native installation. Those tests remain useful comparison evidence;
they cannot qualify the preferred TUF route or lock its production wire format.
Do not layer a second custom signature protocol inside authenticated TUF targets.

## 3. Trust and the zero-budget operating model

HTTPS protects transport. TUF's trusted roles authorize descriptors. Descriptor
hashes bind package bytes. OpenRC receipts bind build/runtime identity. OS publisher
signing affects platform trust prompts. These are separate boundaries; none alone
qualifies installation or exact replay.

The survey promotes maintained TUF over extending a homegrown key-lifecycle
protocol. The initial candidates are tough 0.24.0 for a native Rust helper and
python-tuf 7.0.1 for maintainer/reference work. A library/toolchain is selected only
after [Spike A](reuse-spikes.md#spike-a--standard-trust-on-static-github-hosting).
Player systems do not require Python. A C++ implementation route needs a qualified
library/integration choice, not an assumption that the Rust candidate is drop-in.

Keep root and targets keys offline; separate snapshot/timestamp authority if
GitHub automation renews freshness. Never use the example's one key for every role
as the production compromise-isolation design. Protect backups and rehearse normal
rotation and recovery. A compromised root or malicious authorized executable is
not magically repaired by adding TUF. Define the actual threat model and retain
an independent manual bootstrap route.

### Persistent trust is a separate acceptance boundary

Store the latest verified root, required root history and metadata high-water state
outside every replaceable game generation. Preserve it across binary rollback.
Use explicit owner-checked locking if multiple installations share a trust store;
installation journals remain bound to their own real install roots.

The inspected tough loader takes the caller's trusted root bytes. Passing the
original bundled root on every run does not establish root advancement. Its
optional datastore defaults to temporary storage, uses process-local locks and
ordinary writes, and skips some previous-version comparisons when cached metadata
does not parse. These observations make the integration gate concrete:

- Select and durably retain the latest verified root, with qualified crash recovery.
- Keep expiry enforcement enabled and establish persistent state before use.
- Treat missing/corrupt established trust state as recovery-required; never quietly
  reset to the old bundled root or erase high-water marks to make an update pass.
- Distinguish a legitimate root-authorized role-key rotation from unexplained loss
  of old metadata. Test torn writes, concurrent processes, old helper versions and
  stale CDN/root history explicitly.
- Complete target streams and independent descriptor length checks before use.
  Do not rely on a successful stream-open call as verification.

The source header's old delegation limitation conflicts with current code; neither
that comment nor a broad feature list establishes exact interoperability. Initial
scope uses top-level roles; later delegation needs its own fixtures. Applicable
security advisories are a dependency-selection input, not a whole-product verdict.

### Freshness and applying a prepared update

Require a successful trust refresh before granting automatic apply. Persist the
accepted target/authorization with the transaction; after graceful exit, recheck
its validity, the target's eligibility in that accepted authorization and the
installed-version policy before mutation. Authorization validity includes the
earliest expiry of the complete accepted root/timestamp/snapshot/targets chain
and any future delegated roles, plus any stricter descriptor validity. Persist
and revalidate the authenticated evidence; a descriptor-local expiry alone is
insufficient. Failed/offline refresh leaves the candidate ready for later and the
current game usable. An expired authorization cannot install silently just because
its download once passed. Recovery to an already recorded local generation is a
separately qualified action.

A refresh cannot prove global newest information against replay of still-valid
metadata; retain high-water marks and state the remaining freshness window.
A withdrawal published after the successful pre-exit refresh can remain unseen
at the local post-exit check and may be installed while that authorization remains
valid. Withdrawal is not instantaneous revocation. A first/long-inactive client
with no evidence of a higher root cannot distinguish a withheld next root from
an absent newer root while older metadata remains valid. Use wall time for signed
validity, monotonic time for deadlines, and qualify backward/forward clock anomalies.
Never disable expiry to cure a clock problem. First-contact/reinstallation and
local same-user compromise remain explicit limits.

Role-specific validity/renewal hypotheses and missed-schedule exercises are in the
trust spike. Online timestamp renewal cannot extend an expired offline-signed
targets role. The previous 90-day single-envelope policy applies only to the
comparison model. No production key, schedule or signing workflow exists in this
branch. Paid KMS, certificates or hosting are not dependencies of the proposal.

GitHub immutable releases and tag rules remain useful additional controls. Inspect
current policy and publisher semantics before changing them; existing assets do
not become retroactively immutable. No repository setting is changed here.

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
Establish ownership at bootstrap; unknown/unmanaged additions cause assisted
migration or explicit preservation, not deletion. A version string, ZIP digest or
selected native receipt does not inventory a legacy installed tree. Establish a
complete baseline from an authenticated archive/derived inventory, introduce a
qualified signed inventory, or use conservative side-by-side/assisted migration.
Do not fetch an old 1.5 GB archive merely to create an eligible delta base. No
automatic pruning of a legacy folder is allowed without known ownership.

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

## 7. Release and metadata publication

Preserve current six-file output and release verification for the first Pages
metadata pilot. Descriptors and trust metadata on Pages are not additional Release
assets. If patches, signatures or alternate packaging later enter Releases,
explicitly version all strict inventories and consumers.

Proposed dependency order:

1. Freeze source/tag, build through existing required gates and generate identities
   from final artifacts. Verify the exact complete release set and source/run.
2. Create/upload/publish the release using a rehearsed publisher. If adopting
   immutable releases, explicitly qualify draft/upload/publish semantics.
3. Verify the actual public release ID and downloaded bytes, including canonical
   redirect handling. A tag, release object or asset count alone is not completion.
4. Create bounded descriptor targets from those verified facts, including the
   observed release ID. Obtain the required offline targets signature. Every new
   descriptor or targets-expiry renewal needs that role's signing authority.
5. Under a channel/website-wide serialized publisher, reject stale promotion and
   publish the immutable/hash-prefixed descriptor objects, versioned targets and
   snapshot metadata, and any required versioned roots. Retain root history and
   objects needed by supported inactive clients; verify their public availability.
6. Advance timestamp.json last, then verify its public bytes and consistency with
   the intended snapshot/targets/descriptors. For an already qualified alternative
   protocol, retain its equivalent authenticate-complete-state-before-promotion rule.
7. Record release/source/run, archive hashes, role/descriptor versions and hashes,
   Pages commit/deployment and actual qualification scopes. Never log credentials.

Publication is not an atomic cross-service transaction. Pages/CDN visibility may
lag and clients can encounter an old valid timestamp or a temporarily unavailable
referenced file. Retry without mixing generations, bypassing authentication or
blocking play. Serving immutable objects before the mutable selector reduces this
risk but does not eliminate cache races. Keep public objects reachable for the
qualified support window; do not garbage-collect root history during site refresh.

site/publish.py does not copy a new updates/ source directory automatically and
replaces assets/. Deliberately integrate the updates/ namespace and serialize
website/feed publishers. Never replace the entire website with a metadata-only
deployment. A GITHUB_TOKEN branch push may not trigger branch-based Pages; use the
supported, qualified deployment route.

Per-tag release concurrency does not order different tags or shared timestamps.
Revalidate after rebase/retry and never let an older job overwrite newer authorized
selection. Expiry renewal is a real maintenance operation: daily freshness jobs,
manual recovery and offline targets/root renewal need named procedures. No such
live publishing operation is performed by this research.

## 8. Delta extension contract

Enable production deltas only after the full path passes; research benchmarks can
run in parallel. Compare HDiffPatch and Butler/Wharf using the
[qualified command drafts](reuse-spikes.md#spike-c--existing-delta-tools-on-actual-openrc-packages),
with librsync as a baseline. Bind exact source and target hashes, the
patch's own signature-bound hash/size, algorithm/version and resource limits.
Do not download an old package merely to construct a patch base; full target
download is then the sensible fallback. Rehash the actual base, not a version
label. Produce the target in staging and run the same whole-package validation.

An archive-to-archive patch must reconstruct the exact ZIP bytes authenticated by
the verified descriptor. An
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

Butler's optional signature validation occurs after committing its output. A
fresh isolated output directory is therefore mandatory in that experiment; its
staging flag alone does not satisfy verify-before-activation. Matching checksums
from any patch tool are not publisher signatures. Independently verify the entire
authenticated target and retain profile/ownership boundaries. If full fallback
increases the approved transfer, disclose the new download size and request consent.
