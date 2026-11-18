# Reuse decisions and executable investigation briefs

DT-UPD-00 follow-up, 2026-11-17. **Proposed experiments, not executed results.**
[Active plan](../../../plans/github-updates.md) · [27 repository studies](game-update-survey.md) ·
[Architecture](design.md) · [Acceptance](validation.md) · [Player help draft](player-help-draft.md).

## Decisions strengthened by the survey

| Decision | Evidence that changes the plan | OpenRC action |
| --- | --- | --- |
| Reuse a trust protocol before inventing key management | Warzone's signed announcements have a narrower trust boundary than installing code; TUF clients already model root rotation, metadata versions and expiration. G04, U06–U07. | Make maintained TUF the preferred trust candidate in DT-UPD-02. The existing custom envelope remains a comparison model, not the default production format. |
| Keep the game as the player interface | DDNet exposes download/restart states; ScummVM hands installation to native update frameworks after a normal close request. G01, G16. | Retain Home/Settings and graceful exit; compare existing native adapters against the no-normal-launcher constraint. |
| Reuse patch generation and application | Butler/Wharf, HDiffPatch and librsync already implement distinct delta algorithms. U01–U03, U05. | Benchmark existing tools. Do not write a new delta format or patch algorithm. |
| Keep reconstruction separate from activation | Butler commits its output before optional signature validation; several game/content updaters modify installed files directly. G01, G09, G14, G17, U02. | Always use an isolated output; independently authenticate and admit the complete candidate before the native apply transaction. |
| Preserve exact release publication | Endless Sky and Cataclysm pipelines demonstrate moving tags, incremental uploads and asset-count retries. G11–G13. | Preserve OpenRC's stronger exact-inventory publisher; promote channel metadata only after public-byte verification. |
| Make unknown/error states truthful | Shattered Pixel Dungeon maps one SSL failure to no update found; announcement systems do not establish package eligibility. G18. | Keep Failed, Not checked, Current and Unsupported distinct; no green success after an unverifiable check. |
| Treat packaging as part of efficiency | Naev separates internal content artifacts; Luanti/Wesnoth update content independently of engines. G09, G14, G19. | Measure packaging churn before changing embedded PCKs; retain exact runtime/replay identity and full packages. |

These are architecture proposals. None of the inspected game flows establishes
all of OpenRC's required multi-file, user-data and native recovery properties.
Similarity to another project is evidence for a spike, not acceptance.

## Spike A — standard trust on static GitHub hosting

**Owner:** DT-UPD-02, coordinated with DT-UPD-01 and DT-UPD-03.
**Question:** can maintained TUF provide the required trust lifecycle with a small
native helper, static GitHub hosting and an operating routine this team can sustain?

Compare the existing envelope model with **tough 0.24.0** as a native Rust candidate
and **python-tuf 7.0.1** as a maintainer/reference candidate. Those release versions
are investigation pins, not adopted dependencies; the survey records inspected
source SHAs separately. Pin source, toolchain, lockfile, build features and actual
binary hashes in the spike. Observed candidate release refs resolve to:

| Candidate | Exact release source commit |
| --- | --- |
| tough 0.24.0 / tuftool 0.17.0 | 98d8eb8b2ce63515d9b4981c938ef6453c5b5771 |
| python-tuf 7.0.1 | 49eb1da48c58cf0cbb0f2e490f7ad39fbd8c1f15 |
| HDiffPatch 5.1.3 (Spike C) | 3b9dca715ca492873bf2c49e22e5d5b7d2a78620 |

The survey's Python-TUF/HDiffPatch inspected HEADs are later, separately recorded
source snapshots. Recheck the exact release code before execution/adoption.
Do not use an unversioned install command.

The Rust route adds a toolchain and crypto/HTTP dependencies; a C++ helper does not
gain a maintained C++ TUF implementation just because Rust was studied.

### Proposed layout and trust boundary

Keep large packages on GitHub Releases. Use the existing Pages updates/ namespace
for TUF metadata and small authenticated release descriptors:

| Logical resource | Contents / purpose |
| --- | --- |
| TUF metadata | Root, targets, snapshot and timestamp roles; retain versioned root history and consistent-snapshot metadata. |
| TUF targets | Small stable/preview descriptors, published with the library's required hash-prefixed naming. |
| Descriptor payload | Closed OpenRC schema: subscription/artifact channel, release ID/tag/source, exact platform ZIP and manifest URLs, SHA-256, lengths, OS/architecture, bounds and updater requirements. |
| GitHub Release assets | Existing complete ZIPs and current six-file release set; descriptor references authenticate their bytes. |
| Trusted local state | Latest verified root and metadata high-water state, separate from replaceable game generations; explicit locking and crash-safe retention. |

This indirection avoids renaming all GitHub assets to TUF hash-prefixed filenames
or placing 1.5 GB packages on Pages. It is a **proposed integration**, not behavior
provided automatically by TUF: the helper must verify the descriptor as a TUF
target, parse its bounded schema, download only its authorized ZIP, and check the
ZIP and bound release manifest before extraction/activation. TUF does not validate
OpenRC's bundle receipts or perform the installation.

Use the four top-level roles initially. Stable and preview are separate target
descriptors within the targets role; this is not delegated-channel key isolation.
Do not introduce a second nested TUF implementation or a redundant homegrown
signature format inside those verified targets.

### Key and maintenance proposal

Keep root and targets signing keys offline with independent protected backups.
Use distinct snapshot/timestamp keys for automation if qualified; they may live
in a restricted GitHub signing workflow. A compromised freshness key alone must
not authorize a new executable. Putting every role's key in the same ordinary
release job would defeat the intended separation. Multiple keys stored together
are not independent custodians. Thresholds above one require actual independent
custodians and an affordable recovery process; none is assumed.

For the spike, evaluate timestamp 7 days, snapshot 30 days, targets 90 days and
root 365 days, daily off-hour freshness renewal, and targets renewal before day
60. These are OpenRC operational hypotheses, not TUF mandates or qualified
freshness guarantees. Record what an attacker can replay within each validity
window. Test long inactivity and a maintainer unable to renew. Expiry blocks new
automatic installation; it never blocks the installed game.

GitHub schedules can be delayed or dropped and public-repository schedules can
be disabled after 60 days without activity. Provide manual dispatch, public
freshness verification and an explicit maintainer check; the same stalled
scheduler cannot be the only detector of its own failure.
[GitHub schedule contract](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
No workflow, secret or recurring job is created by this research.

### Required discriminating evidence

- Publish a disposable local/static fixture with complete versioned metadata and
  descriptors; verify it with both selected implementations where their supported
  formats overlap. Do not assume identical support from a README.
- Rotate root and targets keys; test a client missing several releases, an expired
  previous root, a missing intermediate root, and stale CDN files. Preserve all
  required intermediate roots. Never repair corrupt state by silently trusting
  the bundled old root again. A client with no evidence of a higher root can
  accept still-valid older metadata when the next root is unavailable; test and
  disclose that first-contact/freeze limit rather than expecting impossible detection.
- In tough, explicitly select the latest trusted root for the next process.
  Its loader takes caller-supplied root bytes; supplying the original bootstrap on
  every run does not establish persistent root advancement.
- Set a persistent datastore, keep expiration enforcement enabled, and test power
  loss during writes. Inspected tough datastore writes are ordinary file writes
  with process-local locks; they do not establish cross-process exclusion or
  durable atomic storage. Integrate a qualified state adapter or resolve upstream
  rather than claiming the library supplies those guarantees. Some previous-version
  checks are skipped if cached metadata does not parse: distinguish a legitimate
  root-authorized role rotation from corrupt/lost established trust state and refuse
  silent high-water reset.
- Complete and verify the bounded descriptor stream before parsing or acting on
  it; tough's streaming API can expose bytes before its final checksum succeeds.
- Test timestamp/snapshot key compromise, wrong descriptor/channel/architecture,
  stale versions, clock changes, replay after binary rollback, and truncated cache.
  A fresh reinstall has first-contact limitations; data loss must not silently
  downgrade an existing installation's trusted state.
- Complete a public GitHub/Pages fixture with canonical URLs, bounded redirects,
  stale metadata combinations and interrupted promotion. Publish/verify immutable
  descriptor targets and versioned targets/snapshot before timestamp.json; retain
  root history and the whole website. Preserve the existing six-file Releases
  contract. Online timestamp renewal cannot extend offline targets expiry.
- Verify the built dependency graph against applicable advisories. The 2026 tough
  bulletin fixes affected versions in 0.22.0 / tuftool 0.15.0; the candidate pins
  must include those fixes and any later applicable fixes. A patched version is
  not proof that OpenRC's integration is correct.
  [Vendor bulletin](https://aws.amazon.com/security/security-bulletins/2026-019-aws/).

**Decision rule:** prefer maintained TUF if the native integration, durable state,
publisher interoperability and renewal/recovery rehearsal pass. If it fails,
record the concrete blocker and revisit the implementation/library choice before
standardizing a smaller custom format. Do not silently ship the comparison model
or advertise signing-key compromise recovery that it cannot provide.

## Spike B — existing native installer adapters

**Owner:** DT-UPD-01 and DT-UPD-05…08.
**Question:** which existing adapter can install the actual OpenRC package while
keeping direct game launch, graceful exit and an independently reachable recovery
route?

Compare the already identified pinned Velopack no-stub candidate, Sparkle on macOS,
and a minimal native helper using established OS/library primitives. Add a
**per-user Windows installer** comparison if portable-directory recovery proves
more complex: an installer need not introduce a launcher, but requires deliberate
packaging, upgrade/uninstall and profile-preservation contracts. Unciv and ScummVM
are evidence for exploring that option, not proof that it works for OpenRC.

Use a real exported package, not a one-file hello-world. Preserve Godot startup,
embedded PCK/native identity, exact Mac sibling receipts and current direct-launch
arguments. Keep trusted verification outside any framework path that could fetch
or install a different package. Prove what happens when the new app crashes before
Home, the renderer guard intentionally restarts, or the helper itself changes.

Required outputs are the platform/layout matrix, ordinary/recovery entry paths,
dependency/license lock, failure boundaries, profile behavior and native evidence.
Prefer the maintained adapter when it meets those gates with less owned code.
If no adapter passes on one platform, retain verified download and the
[assisted-install help](player-help-draft.md); this does not block other qualified
platforms or offline play.

## Spike C — existing delta tools on actual OpenRC packages

**Owner:** DT-UPD-09; may run as research in parallel with full-package work.
Enabling deltas remains DT-UPD-10 after the full path is qualified.

### Candidate order

| Priority | Candidate | Why investigate / limitation |
| --- | --- | --- |
| 1 | HDiffPatch 5.1.3, streaming mode | C/C++ integration matches existing native tooling; can reconstruct exact files/ZIPs with bounded configured caches. Actual decompressor/window memory still counts. |
| 1 | Butler at c0e529f2e31c82b0d6e785d2a6be908390b05ecc with Wharf c844818e4eba2bafea8b054063a95c9b2e06ef7f | Offline directory pipeline, cross-file reuse and checkpoints. Requires a Go helper/dependency build and a new authenticated complete-tree inventory for extracted-file use. |
| 2 | librsync at 271744de428c0177e993f95c045d70b8cf2558f2 | Useful baseline for detached block signatures; caller must validate the exact basis; assess LGPL obligations for the chosen integration. |
| Defer | casync indexed chunk store | Valuable content-defined chunk reference; nested addressable chunks and native Windows support are unproven under our GitHub-only contract. |

Upstream timing/size tables do not predict this game's savings. Verify exact
release tool sources and licensing again before building an experimental binary;
the upstream source HEAD and a published release tag are different identities.
Tool-specific checksums and Wharf's .sig file are not publisher signatures.

### Reproducible input matrix

Use actual downloaded and independently verified N−1→N and N−2→N packages for each
OS, plus controlled code-only, scenery, native-library and engine-change exports.
Add repeat exports of the same source/toolchain to measure packaging churn.
Current export.sh uses recursive ZIP compression for Windows/Linux; no repeat-build
byte determinism is established merely by recording a commit-based build date.
Compare exact ZIP bytes and complete extracted trees as separate experiments.

Record whether the old ZIP is genuinely present. Do not download an old ZIP just
to manufacture a favorable delta case. Include helper bytes for the first capable
build, metadata/signature bytes, retries and any full fallback in transfer totals.
Changing file order/timestamps/compression or externalizing the PCK is a separate
build-contract experiment, preserving native receipts, OS signatures and replay
identity. No new PCK overlay may bypass those contracts.

### Command drafts

Run only on disposable copies with verified, pinned developer-built tools.
The old input is read-only, candidate/staging paths must be fresh and exclusive,
and no path is a live install or the player's profile. Commands are examples to
qualify against the pinned binary; none was executed in this research.

~~~sh
# HDiffPatch: exact archive, uncompressed baseline.
hdiffz old.zip target.zip candidate-raw.hdiff -SD-256k -s-64 -p-1
hpatchz -s-8m -p-1 old.zip candidate-raw.hdiff reconstructed-raw.zip
# Separate compressed arm: first lock and record the linked zlib implementation.
hdiffz old.zip target.zip candidate-zlib.hdiff -SD-256k -s-64 -p-1 -c-zlib-9
hpatchz -s-8m -p-1 old.zip candidate-zlib.hdiff reconstructed-zlib.zip
# Independently compare each reconstructed ZIP length + SHA-256 to the trusted target.

# Butler: directory experiment; --dir prevents the default in-place destination.
butler diff old-tree/ target-tree/ candidate.pwr --verify
butler apply --staging-dir patch-scratch/ --dir candidate-tree/ --signature candidate.pwr.sig candidate.pwr old-tree/
# Independently verify the complete candidate inventory before any activation.

# librsync: per-file baseline; source/target authentication is an outer contract.
rdiff signature old-file basis.sig
rdiff delta basis.sig target-file candidate.rdiff
rdiff patch old-file candidate.rdiff reconstructed-file
~~~

The HDiffPatch draft uses the -SD single-stream format; that flag alone does not
select a compressor. The first arm is an explicitly uncompressed baseline; the
second selects zlib level 9 after its exact implementation/version is locked.
Neither arm assumes the newer window format is qualified. Record compression
settings/dependencies in the receipt. The 8 MiB cache option is **not** a
whole-process memory ceiling. Cap and measure decompressor allocations, stream
windows, total output, CPU and open files. Prohibit self-extracting patch execution.

For each case retain exact package/patch/tool hashes, source and target inventories,
input eligibility, requests/bytes, create/apply/verification wall and CPU time,
peak RSS, bytes read/written, peak additional disk per volume, hardware/OS/filesystem,
cache conditions, and final admission/replay results. Keep large artifacts outside
Git; retain small receipts and regeneration instructions. Collect enough repeated
runs to support any percentile claimed; one timing is not p95.

### Accepting a delta

For an exact-ZIP route, require equality to the descriptor-authenticated target ZIP digest. For a
file-tree route, first define and authenticate the canonical whole-tree contract:
relative paths, file types, sizes, SHA-256, modes and allowed link targets, including
all native libraries and Mac sibling receipts. Prove equivalence with a full-package
install. Do not compare a directory to an archive digest.

Use 70% of complete-download bytes as an initial screening threshold, then compare
total time, RAM and disk on modest hardware. This threshold is a proposal. A delta
must also win a real user case with an available exact base. Start with at most
two supported source generations and one patch hop; no chain is required.

Reproduce modified/missing basis, interrupted checkpoints, changed target,
corrupt patch/signature, duplicate/escaping paths, extra unmanaged files, locked
files, cancellation and disk exhaustion. Candidate failure never mutates the
active install. Offer a full download when eligibility or validation fails.
When fallback would increase the previously approved download size, disclose the
new size and ask within the game; do not silently consume another 1.5 GB.

## Spike D — help and maintenance rehearsal

**Owner:** DT-UPD-04, DT-UPD-11 and DT-UPD-12.

Run the player help against actual native installs: first bootstrap, download
pause, invalid/expired trust, read-only location, game still running, renderer
restart, failed activation, newer profile with an older executable, and an
unreachable ordinary launch path. Do not promise a Repair button before the
independent entry exists. Let players export a redacted local diagnostic bundle;
do not add telemetry or require an account.

Rehearse release withdrawal, missed freshness renewals, publisher retry/out-of-order
jobs and compromised freshness keys without changing live releases. For future
publication, retain qualified evidence in the existing track homes. The active
plan alone owns step status; this document owns the experimental briefs.
