# Release metadata and Linux ABI inventory

DT-LNX-02c/03a. `app/export.sh` invokes these tools after the existing native/package checks. They use Python 3.11+, Git, ZIP and GNU `readelf` (binutils); no Python packages are required. Use an isolated Linux checkout. See [release preparation](../../docs/TOOLS.md#release-sequence).

## Export and transfer contract

Each successful export produces exactly six public files at its output root:

- The existing Linux x86_64, Windows x86_64 and macOS universal ZIP filenames.
- `linux-abi.json`: static inspection of every ELF in the final Linux ZIP.
- `release-manifest.json`: versioned source, build/input, artifact and incomplete-qualification metadata.
- `SHA256SUMS`: five hashes, covering the three ZIPs and both JSON files; it never hashes itself.

`manifest.py capture` runs after import and before the first export. Its private `.release-inputs.json` records the source identity, tracked diff and untracked project content identity, actual editor and templates (including the corrected macOS ZIP), native receipt hashes, tool scripts, toolchain locks, packer and readelf executable hashes. `finalize` rejects source/input drift, binds the Linux executable and two required native libraries to the package/build receipts, writes new metadata exclusively, and verifies the resulting set. Source commit date is the timestamp; the tool does not claim a reproducible build timestamp or source archive identity. Private input paths and staging directories are excluded from published assets.

CI transfers only the six named files. Its verifier takes independent commit, tag, Actions run and repository expectations before publication. It then fetches the remote tag, checks the peeled commit and uses `gh release create --verify-tag`; protection against tag changes during publication still requires repository tag protection/immutability policy.

To inspect a downloaded set, put exactly the six files into an otherwise empty directory:

```sh
python3 tools/release/manifest.py verify --directory /path/to/downloaded-release \
  --expected-tag vX.Y.Z --expected-commit FULL_REVIEWED_COMMIT
```

Use `--expected-run-id` and `--expected-repository` when independently known. For a local exporter output with its three working directories and private input snapshot, add `--allow-staging`. The default rejects extra files/directories, symlinks, missing or changed bytes, duplicate JSON keys, unexpected schema fields, incorrect platform/architecture filenames and noncanonical checksum inventory. Existing metadata is never overwritten.

The schemas are versioned by `openrc-release-manifest-v1` and `openrc-linux-abi-v1`; their executable validators are `manifest.validate_metadata` and `elf_audit.validate_report`. Unknown versions fail. The release schema currently fixes the three existing ZIP targets. It provides hashes and sizes for downloads; new formats/architectures require an explicit schema/consumer change. There are no speculative ARM64 or installer assets.

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
