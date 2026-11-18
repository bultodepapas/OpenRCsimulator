# DT-UPD-00 custom-envelope comparison model

This is an **offline research model**, not a deployable updater. It performs no
network requests, package extraction, filesystem replacement, process launch,
key generation on disk or GitHub mutation.

The 2026-11-17 [game-survey follow-up](../../docs/research/desktop-delivery-investigations/DT-UPD-00/game-update-survey.md)
prefers a maintained TUF trust implementation for the next qualification spike.
This earlier custom envelope remains a bounded comparison and negative-fixture
reference. It does not implement or test TUF; its passing tests do not select a
production wire format or qualify native trust persistence.

[Active plan](../../docs/plans/github-updates.md) ·
[Architecture](../../docs/research/desktop-delivery-investigations/DT-UPD-00/design.md) ·
[Evidence and acceptance](../../docs/research/desktop-delivery-investigations/DT-UPD-00/validation.md)

## Purpose

Make the most consequential metadata/download rules reviewable and exercise
negative cases before native updater work starts:

- Exact payload-byte Ed25519 verification with a fixed product/protocol domain
  and the validated ASCII key ID. The signed message is the fixed DOMAIN bytes,
  followed by key_id ASCII bytes, one NUL byte and the exact payload bytes.
- Closed, bounded JSON envelope and stable-channel payload.
- Repository/tag/architecture binding, release-manifest hash/size and exact URLs.
- Metadata validity/sequence and same-sequence equivocation rejection.
- Clear non-newer-version result, including same-version feed renewals.
- HTTP 200/206/416 handling that cannot mistake an ignored Range for append.

The cryptographic primitive comes from Cryptography, not this project.
Tests include an independent RFC 8032 known-answer vector and tampering/malformed
cases; round-tripping a self-generated signature is not the only cryptographic check.

## Run the isolated checks

Python 3.11+ and the exact dependency in requirements.txt are needed only by developers.
The recorded environment already contained Cryptography 50.0.0; the task did not
install or upgrade it. For another machine, use an isolated virtual environment.

~~~sh
python3 -m unittest discover -s research/github-updates -p 'test_*.py' -v
~~~

channel-payload.example.json is deliberately synthetic and unsigned. Its URLs,
hashes, sizes and synthetic timestamps are not release evidence and it cannot authorize
an installation. Test keys are generated in memory for each fixture and are never
written to the repository. Do not copy fixture keys into a shipped game.

## Supported subset and deliberate limits

The only accepted payload marker is openrc-update-payload-draft-v1; it is not a
reserved production wire format. The model accepts stable numeric tags only.
Preview channels, withdrawal/control records, release IDs, OS requirements,
source/manifest reconciliation, key delegation/rotation, persistence and clock
anomaly handling are **not implemented**.

Trusted keys and the previous sequence/hash are supplied by the caller. The
model does not prove where trust came from or that the high-water mark was
atomically persisted. Returned dictionaries must be treated as untrusted again
if a production caller permits mutation; a production API should use immutable
validated values or revalidate at every boundary.

The 8 GiB expanded-size ceiling, 100,000 member ceiling, 90-day metadata horizon
and five-minute forward-clock allowance are proposed fixture policy. They have
not been calibrated against actual packages/target machines. A real extractor
must enforce actual streaming totals and path/link rules independently.

range_action decides what a response means; it does not make HTTP requests,
follow redirects, implement retries, persist partial files or verify final ZIP
hashes. Header checks must happen before writing, with streaming bounds and
completion checks afterward. It returns verify-existing for a length-matching
416; that is an instruction to hash and validate the local file, not success.

No passing check establishes secure extraction, resumable network operation,
durable install/rollback, ordinary launch after power loss, Mac quarantine handling,
player-data compatibility or a shipping update system. Those require the native
matrix in the evidence document.

## Implementation draft boundary

Use these fixtures to compare product invariants during DT-UPD-01/02. Qualify the
chosen standard protocol/library directly; do not port this model as a homemade
TUF client or stack another custom signature format inside TUF targets.
Do not ship Python or require players to run it. Use the existing game UI and
a bundled helper, keeping player consent, save/recording exit guards and per-OS
installation details separate. Full authenticated package archives stay the correctness baseline.
