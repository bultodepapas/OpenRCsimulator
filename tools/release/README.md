# Release metadata, Linux ABI inventory and Mac reference identity

DT-LNX-02c/03a. `app/export.sh` invokes these tools after the existing native/package checks. They use Python 3.11+, Git, ZIP and GNU `readelf` (binutils); no Python packages are required. Use an isolated Linux checkout. See [release preparation](../../docs/TOOLS.md#release-sequence).

## Export and transfer contract

Each successful export produces exactly six public files at its output root:

- The existing Linux x86_64, Windows x86_64 and macOS universal ZIP filenames.
- `linux-abi.json`: static inspection of every ELF in the final Linux ZIP.
- `release-manifest.json`: versioned source, build/input, artifact and incomplete-qualification metadata.
- `SHA256SUMS`: five hashes, covering the three ZIPs and both JSON files; it never hashes itself.

`manifest.py capture` runs after import and before the first export. Its private `.release-inputs.json` records the source identity, tracked diff and untracked project content identity, actual editor and templates, native receipt hashes, tool scripts, toolchain locks, packer and readelf executable hashes. It requires one correctly named and platformed preset per desktop target. Linux and Windows custom release templates are rejected until their actual inputs can be recorded; their receipts must describe the official templates actually selected. The macOS preset may select the official `macos.zip` or a project-local custom template with its receipt. Ambiguous presets, unsupported custom paths and incomplete custom receipts fail closed. `finalize` rejects source/input drift, binds the Linux executable and two required native libraries to the package/build receipts, writes new metadata exclusively, and verifies the resulting set. Source commit date is the timestamp; the tool does not claim a reproducible build timestamp or source archive identity. Private input paths and staging directories are excluded from published assets.

Worktree hashing streams the binary Git diff with the same digest convention,
rather than retaining the complete patch in RAM. Stderr is drained concurrently
and retained up to 64 KiB for failures. Untracked app paths are still collected
and sorted in memory; this does not bound Git's own memory or execution time.

CI transfers only the six named files. Its verifier takes independent commit, tag, Actions run and repository expectations before publication. It then fetches the remote tag, checks the peeled commit and uses `gh release create --verify-tag`; protection against tag changes during publication still requires repository tag protection/immutability policy.

After reserving an output directory, a failed export retains the latest engine log as `export-failure.log` and a pathname-only source inventory as `export-source-status.txt` there. Diagnostic collection is best effort and does not change the failure result. CI retains these two files separately for seven days; they are not release assets. Keep generated `.uid` sidecars tracked with application scripts and shaders so a fresh import does not change the selected source identity; the early CI preflight checks their presence.

Import, each desktop export and each package-resource smoke use the [checked Godot runner](../godot/README.md). Their existing 600-second import/export and 60-second smoke limits remain; engine/script/shader errors fail even when the process exits zero, while warnings remain recorded and allowed. The field and rotorcraft probes must print their complete successful terminal markers, and the host-native probe must emit exactly one successful JSON report. Empty output cannot qualify a package smoke. Each invocation retains a bounded engine log and checked report under `tmp/nk3-export-*/checks`, already collected by the CI native-export diagnostic artifact. The runner's 8 MiB per-invocation log cap fails closed on overflow. These checks supplement the existing archive, identity, ABI and exported-flight gates; Linux-hosted pack inspection does not execute the Windows or macOS application on those operating systems.

The workflow invokes `tools/release/publish.py` for this same-run handoff. It also checks the checkout/origin and tagged notes. If the release exists, it verifies published/draft and prerelease state, title/notes, the exact six assets and their downloaded bytes; an identical retry is a no-op. Incomplete drafts or different files/metadata fail without overwriting assets. Newly created downloads are verified too. All credentials remain in the environment. Publication tests use disposable Git remotes and mocked GitHub calls; a passing fixture is not a real package/publication rehearsal.

To inspect a downloaded set, put exactly the six files into an otherwise empty directory:

```sh
python3 tools/release/manifest.py verify --directory /path/to/downloaded-release \
  --expected-tag vX.Y.Z --expected-commit FULL_REVIEWED_COMMIT
```

Use `--expected-run-id` and `--expected-repository` when independently known. For a local exporter output with its three working directories and private input snapshot, add `--allow-staging`. The default rejects extra files/directories, symlinks, missing or changed bytes, duplicate JSON keys, unexpected schema fields, incorrect platform/architecture filenames and noncanonical checksum inventory. Existing metadata is never overwritten.

New exports write `openrc-release-manifest-v2`; the Linux inventory remains `openrc-linux-abi-v1`. Their executable validators are `manifest.validate_metadata` and `elf_audit.validate_report`. Generic verification still accepts historical manifest v1 sets for integrity checks, without a Mac reference-identity claim. Current publication and downloaded retry verification require v2. Unknown versions fail. The release schema fixes the three existing ZIP targets; new formats/architectures require an explicit schema/consumer change.

## Patient release automation

The repository skill is [openrc-release](../../.agents/skills/openrc-release/SKILL.md).
Use it for preparation, publication or resumption. The
[release sequence](../../docs/TOOLS.md#release-sequence) owns the gates;
`watch.py` observes an existing tag CI run and performs no GitHub writes.
Python 3.11+ and an authenticated `gh` CLI are sufficient. Its offline tests
need neither GitHub access nor Godot.

### Select and freeze

Inspect local changes and remote main before choosing a candidate. Compare with
the latest **published** release and all existing tags: failed tags are retained,
so a new release needs a suitable unused version. A resumed release keeps its
explicitly pinned candidate and tag. Keep unrelated edits and successful evidence. Record a small
checkpoint in a fresh ignored `tmp/` directory: base/candidate commit, version,
tag, required checks and evidence paths, CI run ID, download directory and the
first unmet gate. Never record tokens, environment dumps or private credentials.

A numeric version bump changes D11g's qualified project inventory. Reconstruct
the qualified baseline and candidate, compare the complete inventory and retained
numerical/provenance fields, then renew both guards and exercise positive and
disposable source/version negative controls. The
[D11g contract](../../docs/research/aero-consistency/D11g/README.md#r02-provenance-qualification-for-v4)
owns that review; matching rounded values alone do not justify new hashes.
Physics/simulation/failure edits also need the existing
[companion rebind](../companions/README.md). Do not rerun or re-record unrelated
flight goldens for release metadata.

Use sequential checked imports on isolated projects. Reusing an imported-resource
cache can avoid expensive unchanged asset work; it does not replace the next
project's checked import or source-drift check. Select local checks by actual
dependencies. A local quick pass is partial; the final tag workflow still supplies
its required full tests, native checks, captures, export and publication gates.

### Observe one exact run

After the reviewed annotated tag and commit are pushed atomically, resolve its
tag-push run once. A simultaneous `main` run can have the same commit; its success
does not qualify publication. Pin the full commit, tag, run ID and repository:

```sh
python3 tools/release/watch.py --repository bultodepapas/OpenRCsimulator \
  --run-id RUN_ID --expected-commit FULL_REVIEWED_COMMIT --expected-tag vX.Y.Z
```

`--once` inspects without sleeping. Repeating this command with the same identity
resumes observation; it does not trigger another workflow. Polling uses real
sleeps and backs off while the observed state is unchanged. Output is limited to
state transitions, observed failures and the terminal verdict. Failures identify
the job/step and a command to obtain its log. An alert arrives on the next poll,
not as an instantaneous push notification. API errors have bounded retries;
timeout, identity mismatch and unavailable state never become successful results.
The CLI's `--help` owns interval, deadline and exit-code details.

For an AI client, launch one asynchronous monitor and retain its process handle.
Wait with the client's nonblocking wait/sleep facility; consume only new bounded
output. Keep user updates at the active session's required cadence, using useful
milestones. Do not fetch every job through another tool in parallel, print full
logs into context or rerun unchanged checks because a poll was quiet. Retain a
failing log locally and read its failing step or bounded tail first. If the user
requests other work while waiting, preserve this candidate and its monitor.

On failure, inspect the first actionable gate. A deterministic failure requires
a reviewed fix and a new candidate identity; preserve failed tags and evidence.
Retry only an identified transient infrastructure failure, with a stated finite
retry budget and unchanged inputs. The monitor never reruns jobs, cancels another
session, changes a tag, publishes assets or chooses a fallback workflow. Exhausted
retries, a cancelled workflow or missing evidence require an explicit status
report, not an invented pass.

### Finish the delivery

A successful monitor means the pinned run is terminal and its `CI required`,
`Release builds (Windows, Linux, macOS)` and `GitHub release (v* tags)` jobs all
succeeded. Report the overall workflow conclusion separately: informational
jobs, including NK-4 Windows, are outside the publication dependencies and can
fail without blocking those gates. Their alerts remain visible. A skipped,
missing or ambiguous publication gate cannot establish success. GitHub's run
API exposes the ref name, not an independently authenticated ref type; use the
tag's peeled commit and the actual publication jobs as additional evidence.
Confirm the actual release is published with the expected title/notes and exact six assets, download
them into a fresh directory and run `manifest.py verify` with independent
commit/tag/run/repository expectations. The existing same-run publisher remains
responsible for idempotent publication; never replace different existing assets.

```sh
gh release download vX.Y.Z --repo bultodepapas/OpenRCsimulator --dir tmp/NEW_DOWNLOAD_DIRECTORY
python3 tools/release/manifest.py verify --directory tmp/NEW_DOWNLOAD_DIRECTORY \
  --expected-tag vX.Y.Z --expected-commit FULL_REVIEWED_COMMIT \
  --expected-run-id RUN_ID --expected-repository bultodepapas/OpenRCsimulator
python3 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); sys.exit(0 if d.get("format")=="openrc-release-manifest-v2" else "Current releases require manifest v2")' \
  tmp/NEW_DOWNLOAD_DIRECTORY/release-manifest.json
```

The extra format check is intentional: generic manifest verification also accepts
historical v1 sets, while current publication and downloaded-retry checks require
v2. All commands above must pass. For large Windows downloads, follow the
[temporary-storage guidance](../ci/README.md#local-entrypoint).

Only after download verification, update README and the localized website links
and release copy together. Use the existing locale generator/tests, review
English/Spanish at 1920×1080 and publish through
[the website publisher](../../site/README.md#preview-and-maintain). Verify public
deployment bytes and links. On resumption, continue from the first unmet gate;
do not repeat a completed download, import, test or publication unless its inputs
changed, it failed or its evidence is inconclusive.

Report the actual state: prepared, tag pushed, CI passed, published, downloaded
and verified, website updated. Keep automated software/integrity proof separate
from native-device, GPU, pilot and physical qualification.

## Mac reference bundle identity (DT-MAC-02h)

`macos_reference_receipt.py` provides a separate, reference-only identity for a
Mac `.app` with one executable and one separate Godot PCK. Capture its private
build-input snapshot before export, then create the receipt beside the final
`.app` **after** signing/notarization/stapling:

```sh
python3 tools/release/macos_reference_receipt.py capture --editor /path/to/Godot \
  --template /path/to/macos-template.zip --output /new/path/mac-inputs.json
python3 tools/release/macos_reference_receipt.py finalize \
  --inputs /path/to/mac-inputs.json /path/to/OpenRC.app
python3 tools/release/macos_reference_receipt.py verify \
  /path/to/OpenRC.app/Contents/MacOS/OpenRC
```

`capture` checks the current Git source and selected inputs. `finalize` refuses
source drift, missing/changed PCK, unsafe bundle entries and unsupported Mach-O
architecture, then writes a new external receipt without changing signed bytes.
The receipt binds every regular bundle file and the declared source/probe inputs;
it proves artifact consistency, not signing trust or source-to-binary
reproducibility.

`app/export.sh` now invokes `package-zip` on the staged Godot Mac archive. It copies
that archive to a new output and adds one sibling
`OpenRC Simulator.app.openrc-reference-receipt`, leaving the signed app files
unchanged. Finalization compares bundle content, architectures, creator and
permission attributes against the staged archive. It does not independently
compare timestamps or ZIP extra fields. Manifest v2 binds the receipt, private
input-snapshot and probe hashes; transfer verification checks the archived bundle
and these public digests. The private input snapshot is not published. The
receipt travels inside the Mac ZIP, so the public set still has six files.

Keep the matching receipt beside the `.app` when extracting or moving it.
Downloaded/quarantined launch needs native testing: macOS path translocation may
prevent access to sibling files ([Apple distribution guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)).
Moving both files before launch is the intended installation route, not a verified
quarantine workaround. A missing receipt cannot establish exact package replay.

ZIP verification streams member contents without extracting another app, but
member-count and expanded-size limits apply after Python parses the central
directory. Source fixtures and an M1 development export passed ZIP preservation,
strict signature verification, the packaged session probe and exact flight replay.
The complete release pipeline and downloaded/quarantined launch remain open in the
[Apple Silicon plan](../../docs/plans/apple-silicon-performance.md#dt-mac-02h--reference-release-identity-independent-of-nk-3).

## Experimental native Mac bundle identity (DT-MAC-04n3)

The native experiment retains the reference receipt above and adds a separate
`.openrc-native-receipt`. Its `macos-arm64-native-bundle-v1` identity binds that
reference receipt, the embedded `package-macos.json`, the descriptor at
`Contents/Resources/openrc_native_kernel_macos.gdextension` and the signed ARM64
dylib at `Contents/Frameworks/libopenrc_native_kernel.dylib`. The descriptor uses
`../Frameworks/libopenrc_native_kernel.dylib`. A reference flight still uses
`macos-reference-bundle-v1`. The fixed packaged diagnostics are session cost,
native stage, lifecycle and replay; helicopter diagnostics are outside this scope.

On the frozen Mac source and verified installation, `package.py prepare-macos`
revalidates the exact oracle reports cited by its installed receipt. Export with
`OPENRC_EXPERIMENTAL_NATIVE_MACOS_PACKAGE=1`, then use `package.py stage-macos`
before signing the outer app. Preserve the qualified dylib bytes. Capture source
inputs before export; finish signing/notarization/stapling before writing either
external receipt. The [native guide](../../research/native-kernel/README.md#experimental-macos-arm64)
owns build and admission prerequisites.

`macos_reference_receipt.py finalize-native` / `verify-native` operate on a final
extracted bundle. `package-native-zip` / `verify-native-zip` handle the separately
versioned ZIP containing both sibling receipts. They refuse altered artifacts,
unsafe paths and incorrect slices. Runtime independently checks the actual
PCK-embedded manifest and diagnostics before loading the dylib. Missing or
changed evidence cannot establish exact native replay.

For a Developer ID candidate, separately audit the final ARM64 host and dylib
before trusting a same-team loading claim:

```sh
python3 tools/release/macos_reference_receipt.py verify-native-signing \
  "/path/to/OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator" \
  --team-id "$TEAM_ID" --dylib-certificate-sha1 "$CERT_SHA1"
```

This macOS-only audit requires actual Developer ID Application signatures, the
same Team ID, the pinned dylib certificate and Hardened Runtime. It rejects
library-validation disabling and either `get-task-allow` entitlement. The receipt
readers remain integrity checks. The signing audit does not check secure
timestamps, notarization or quarantine, and never substitutes for executing the
exact signed package. The builder separately requires a secure timestamp for its
Developer ID dylib; the app's timestamp and distribution gates remain required.

This is an experimental artifact contract. The existing reference ZIP verifier
and public six-file release manifest retain their original scope. Ad-hoc signing
and portable fixtures do not establish Developer ID, notarization, quarantine,
Intel/Rosetta, display or performance qualification.

## Static Linux inspection

```sh
python3 tools/release/elf_audit.py /path/to/linux-release.zip --output tmp/new-linux-abi.json
```

The scanner reads every ZIP member, identifies ELF magic regardless of filename, extracts only ELF candidates into a temporary directory, and invokes GNU readelf. It records interpreter, architecture, `DT_NEEDED`, RPATH/RUNPATH, required GLIBC/GLIBCXX/CXXABI versions and numeric maxima, GNU stack permissions and GNU property notes. Version definitions are excluded from required-version maxima. It refuses unsafe/duplicate archive paths, links/special files, wrong architecture, malformed or incompletely decoded ELF, changed archives and empty inventories. Limits are 4 GiB per member and 8 GiB total expanded data. `--architecture arm64` selects static ARM64 inspection; ARM64 application qualification remains open.

This is a measured metadata inventory, not a distro compatibility certification or automatic dependency installer. No payload is executed and `ldd` is not used. Dynamic loading, graphics/audio/input drivers, complete CPU instruction requirements, native desktop tests, SBOM/license closure and publisher attestation remain explicit pending gates. Schema validation and consistent hashes do not authenticate a publisher or independently rederive ABI facts. No signed provenance, build-image digest, source archive, download URL or support claim is invented.

GNU readelf 2.42 cannot decode the pinned editor's newer FDO dlopen notes and returns nonzero for that case. Core ELF inspection stays strict; narrowly recognized note output is recorded as `notes_status: fdo_dlopen_unsupported`. Other note scans record `readelf_ok`, which means the command succeeded, not that every vendor note was decoded. Corrupt/incompletely accounted note output still fails. The report never treats this workaround as complete dlopen dependency discovery.

## Focused checks

```sh
python3 -m unittest discover -s tools/release -p 'test_*.py'
python3 app/tests/test_export_identity.py
python3 app/tests/test_ci_partitions.py
```

`research/test-tools.sh` includes the release-tool suite. Linux tests use compiled C/C++ fixtures and host ELF files. The packaging-tail test exercises the actual ZIP, readelf, manifest and transfer-verification commands with disposable receipts; it does not run Godot. [Dated evidence](../../docs/research/desktop-delivery-investigations/DT-LNX-02/manifest-abi.md) records the exact tested source and limits.
