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

The workflow invokes `tools/release/publish.py` for this same-run handoff. It also checks the checkout/origin and tagged notes. If the release exists, it verifies published/draft and prerelease state, title/notes, the exact six assets and their downloaded bytes; an identical retry is a no-op. Incomplete drafts or different files/metadata fail without overwriting assets. Newly created downloads are verified too. All credentials remain in the environment. Publication tests use disposable Git remotes and mocked GitHub calls; a passing fixture is not a real package/publication rehearsal.

To inspect a downloaded set, put exactly the six files into an otherwise empty directory:

```sh
python3 tools/release/manifest.py verify --directory /path/to/downloaded-release \
  --expected-tag vX.Y.Z --expected-commit FULL_REVIEWED_COMMIT
```

Use `--expected-run-id` and `--expected-repository` when independently known. For a local exporter output with its three working directories and private input snapshot, add `--allow-staging`. The default rejects extra files/directories, symlinks, missing or changed bytes, duplicate JSON keys, unexpected schema fields, incorrect platform/architecture filenames and noncanonical checksum inventory. Existing metadata is never overwritten.

New exports write `openrc-release-manifest-v2`; the Linux inventory remains `openrc-linux-abi-v1`. Their executable validators are `manifest.validate_metadata` and `elf_audit.validate_report`. Generic verification still accepts historical manifest v1 sets for integrity checks, without a Mac reference-identity claim. Current publication and downloaded retry verification require v2. Unknown versions fail. The release schema fixes the three existing ZIP targets; new formats/architectures require an explicit schema/consumer change.

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
