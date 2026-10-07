# Desktop delivery research 07 — Release provenance and artifact promotion

2026-10-07 · Research round **DT-00-R1** · Item 07. Supports [DT-06–DT-09](../../../DESKTOP-DELIVERY-PLAN.md). This item number is research numbering; it is not plan milestone DT-07.

**Status:** code/workflow audit plus official-source research. No export, signature, upload, or release was run.

## Question

Can the release pipeline prove which source and toolchain produced the exact bytes users download, while preventing concurrent local builds or signing credentials from changing that chain?

## Audited implementation

| Path | Observed behavior |
| --- | --- |
| `app/export.sh` | Computes `git describe --tags --always --dirty`, HEAD, dirty suffix and commit date once; embeds this in `res://build_info.json`; uses `rm -rf "$ROOT/dist"`; exports all three presets into fixed `dist/` paths; checks Linux trace, pack resources, Windows/macOS numeric version fields; zips and writes SHA-256 sums at the end. |
| `app/app_state/build_info.gd` and `app/addons/build_info/export_plugin.gd` | The app reports source/describe/commit/dirty/date/numeric version and Godot version at runtime. The embedded file has no source-tree manifest, export-template identity, workflow run, or artifact digest. |
| `.github/workflows/ci.yml` | Export runs on Ubuntu after app CI, checks out full history/tags, runs `app/export.sh`, uploads the three ZIPs and `SHA256SUMS`. On a `v*` tag, a later job downloads that artifact and attaches those files; it does not rebuild. |
| `app/get-godot.sh`, `app/get-templates.sh` | Pin and verify engine/template downloads by SHA-512. This is strong input evidence, but those verified values are not in the release manifest. |

This was read from the working tree on 2026-10-07. It contains concurrent uncommitted work, so HEAD is not a description of the full observed tree.

## Findings

### 1. The displayed dirty marker misses a class of local input

`git describe --dirty` describes local modifications when the working tree differs from HEAD. Git status separately defines untracked files and says ignored files are not shown unless `--ignored` is requested. Therefore a new, non-ignored source/resource file can influence an export while `git describe` still emits no `-dirty` marker. This is a concrete identity gap, not a claim that every ignored file affects Godot export. [Git `describe`](https://git-scm.com/docs/git-describe), [Git `status`](https://git-scm.com/docs/git-status).

Public release jobs should reject any tracked or untracked changes before importing resources. Capture the machine-readable result of `git status --porcelain=v1 --untracked-files=all --ignore-submodules=none`; require it to be empty. Also record a separate ignored-path inventory before Godot's import step. Do not require an empty ignored inventory after import: `.godot` cache and other declared generated state may be expected. The safest release input remains an ephemeral checkout of the exact tag/commit, not the developer's shared tree.

The disposable probe [script](probes/git_untracked_identity.py) and [captured result](probes/git_untracked_identity.result.json) reproduce this Git behavior without touching the simulator checkout. It establishes the identity gap in a minimal tagged repository; it does not prove that a particular untracked file changes a Godot package.

### 2. Build identity, integrity and provenance answer different questions

The embedded `describe` and commit identify source intent; they do not identify the exact build environment or contents of the distributed archive. `SHA256SUMS` detects byte changes only when the expected checksum is trusted. A code signature identifies a signer and detects signed-file modification. A build attestation binds an artifact digest to a repository, commit, workflow and event. None alone proves the application is safe or bit-for-bit reproducible. GitHub explicitly describes attestations as a link to the source and build instructions, and says consumers must verify them and make their own risk decision. [GitHub artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations), [SLSA build levels](https://slsa.dev/spec/v1.0/levels).

Keep the visible build label, but add a release manifest next to the archives with: full commit SHA and tag/ref; clean-source result; Godot executable version and verified SHA-512; export-template SHA-512; preset names; relevant build-tool versions; workflow run URL/ID and event; target OS/architecture; final filenames and SHA-256; signature/notarization result where applicable. Do not put secrets, signing material, machine-specific paths, or user data in it.

`git describe` depends on available reachable tags. The export job's `fetch-depth: 0` is correct because checkout otherwise fetches one commit by default; retain it and fail clearly when a release tag does not resolve to the expected commit/version. [Checkout action documentation](https://github.com/actions/checkout#fetch-all-history-for-all-tags-and-branches).

### 3. Fixed output paths make local parallel export unsafe

`export.sh` removes the entire shared `dist/` before starting, and every preset writes to a fixed child path. Two invocations can delete or mix each other's intermediates. This is especially dangerous in the shared developer workspace. The CI job is isolated, but a CI-only fix would leave the local command hazardous.

DT-08 should build under a unique per-invocation staging directory, never recursively remove a shared `dist/`, and refuse to overwrite a published-name candidate. Validate all outputs there, then promote a complete set as one serialized operation. A lock only around final promotion is sufficient if compilation is fully isolated. Preserve failed staging as diagnostic evidence or clean only that invocation's own directory.

### 4. Release promotion already avoids a second build; preserve and verify it

The `release` job currently downloads `release-builds` from the successful `export` job in the same workflow and uploads those files to the tag release. This is the right promotion shape: build once, validate, then attach those bytes. Do not move export into `release` or rebuild after signing. GitHub's v4 artifact model is immutable unless deleted; artifact names must be unique per matrix member. The current single `release-builds` artifact avoids the common same-name matrix collision. [Upload artifact action](https://github.com/actions/upload-artifact#whats-new).

Before `gh release create`, verify that the downloaded archive's `SHA256SUMS` matches every exact expected package, that the artifact is from the current run and source SHA, and that there are no extra or missing public files. Record GitHub's artifact digest as transfer evidence, but separately verify the final archive hashes after download. Consider GitHub artifact attestations for release archives (or a manifest containing their hashes); only attest final bytes after platform signing, stapling and repackaging have finished. For public repositories, GitHub uses a Sigstore transparency log; the attestation still requires consumer verification. [Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations), [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).

### 5. Apply signatures before final archive hashes; validate again after every transform

Windows order: export the `.exe`; Authenticode-sign and RFC 3161 timestamp it; verify the signature; build the portable ZIP or installer from that signed executable; sign the installer itself if one is produced; verify extracted payload and installer signatures; then calculate final container SHA-256 and attest those bytes. Microsoft recommends SHA-256 and RFC 3161 timestamp options for SignTool. [Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool), [Authenticode timestamps](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures).

macOS order: sign executable code from inside out; verify the full bundle; notarize the distribution object; staple the ticket to the app or disk image; recreate a ZIP only after stapling its contained app; then hash and attest the final download. Apple says a ZIP cannot itself be stapled and recommends signing nested code inside out. If distributing nested containers, notarize the outermost container. Verify the actual downloaded file and an offline first launch. [Apple signing order](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [container packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

Every post-signature mutation (editing `Info.plist`, replacing a binary, changing a PCK, re-zipping before stapling, or rebuilding an installer) invalidates a prior proof for the changed bytes. Use explicit pipeline stages and retain their logs.

### 6. Isolate credentials from candidate code

The release workflow currently exports without signing credentials; the release job receives `contents: write` for tag publication. Keep unsigned build/test jobs credential-free. Put each platform signing operation in a narrowly scoped trusted release job/environment with tag/branch restrictions and only the required secrets or OIDC permissions. A manually dispatched export may target a non-release ref, so do not expose signing secrets to the general `workflow_dispatch` path without validating the ref. GitHub environments can gate branch/tag eligibility, approvals and access to environment secrets; fork `pull_request` runs intentionally lack secrets. [GitHub environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments), [secure use for untrusted PRs](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target), [workflow permissions](https://docs.github.com/en/code-security/tutorials/secure-your-organization/protect-against-threats).

## Plan improvements to carry into DT-08/DT-09

1. Add a clean-checkout preflight that rejects tracked and untracked changes before resource import; record ignored inputs separately and review allowlisted generated caches.
2. Make staging unique and promotion serialized; prove two simultaneous dry-run exports cannot remove or cross-contaminate one another before enabling parallel export.
3. Define the release manifest schema and generate it from values already checked by the pipeline, including engine/template hashes and final archive digests.
4. Preserve the current build-once/download/promote release graph; verify run ID, source SHA, artifact digest and archive checksum before attachment.
5. Add signing/notarization as explicit transformations before final checksum/attestation; rerun executable, pack and version checks on the exact signed outputs.
6. Restrict signing credentials to protected trusted-tag jobs. Continue testing unsigned candidate exports without secrets.
7. Change DT-07/08 wording from ambiguous “reproduces” to two separate claims: **clean-checkout build repeatability** (same declared files and checks) and **bit-for-bit reproducibility** (independent builds yield identical bytes), the latter unclaimed until measured. A signature, checksum or provenance attestation does not prove byte reproducibility.

## Proof design

| Claim | Minimum evidence |
| --- | --- |
| Exact source state | CI commit/tag, clean pre-import status, submodule state, ignored-input inventory and source-tree digest. |
| Declared tools | Godot version plus binary/template SHA-512; pinned Actions SHAs; pinned installer/zip/signing tool versions. |
| Safe local staging | Two concurrent staging-only invocations use distinct directories; each has its own complete package manifest; promotion cannot overwrite an existing release identity. Run only in an isolated temporary copy. |
| Same bytes promoted | The `export` artifact SHA-256 manifest verifies after `download-artifact`, and the attached release assets match those hashes exactly. |
| Trust chain | Windows `signtool verify`; macOS `codesign --verify --deep --strict`, `xcrun stapler validate`, notary log; final archive hash and attestation verify for the exact uploaded artifact. |

The first commands to capture during implementation are `git describe --tags --always --dirty`, `git rev-parse HEAD`, `git status --porcelain=v1 --untracked-files=all --ignore-submodules=none`, `"$(app/get-godot.sh)" --version`, and the SHA-512 values already enforced by the two download scripts. Commands are design notes; this report did not execute a release.

## Limits

This is a static audit, not a clean export, Windows trust test, Apple notarization, or compromise assessment. Godot/template hashes alone omit runner image drift, OS SDK/tooling, archive timestamps, environment inputs and hardware nondeterminism. Exact-byte reproducibility must be tested with independent clean builds and diffed outputs; signed/notarized bytes may legitimately differ due timestamps/tickets. Public code signing reduces OS trust friction but does not guarantee reputation or universal acceptance.

## Primary sources

- [Git `describe`](https://git-scm.com/docs/git-describe) and [Git `status`](https://git-scm.com/docs/git-status).
- [actions/checkout — full history and tags](https://github.com/actions/checkout#fetch-all-history-for-all-tags-and-branches).
- [Godot 4.7 command-line export](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html).
- [GitHub artifact immutability](https://github.com/actions/upload-artifact#whats-new), [attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations), and [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).
- [Apple signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), and [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
- [Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool) and [Authenticode timestamps](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures).
- [GitHub environment secrets](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments) and [workflow security](https://docs.github.com/en/code-security/tutorials/secure-your-organization/protect-against-threats).
