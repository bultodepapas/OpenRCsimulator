# DT-LNX-02c/03a — release manifest and final ZIP ABI inventory

2026-10-28. Second implementation increment in the [Linux execution plan](../../../plans/linux-support-distribution.md), following [02a/b](README.md). Current commands and contracts live in [release tools](../../../../tools/release/README.md).

## Implemented

The exporter captures source, actual editor/templates, native receipts and relevant tool/lock hashes before exporting; it rejects drift before final metadata generation. The corrected macOS template is included separately from the official source ZIP. Public records omit private filesystem paths and do not require the downloaded template archive to remain cached.

The Linux scanner inventories every ELF in the final ZIP using GNU readelf, without running the payload. Required version maxima come from version needs rather than definitions. It records GNU stack/property information while explicitly leaving full ISA, dlopen and driver closure uncertified. It rejects malformed/ambiguous metadata, unsafe archive members, wrong architecture and empty inventories. A strict report validator checks the schema without invoking readelf.

Finalization compares Linux executable/kernel/ground library hashes to the existing package/build receipts, then emits a versioned release manifest and checksums. Three ZIPs, two JSON files and SHA256SUMS form the exact public set; previous package filenames remain unchanged. CI verifies digests, sizes, inventory and independently expected commit/tag/run/repository after transfer. It rechecks the current remote tag's peeled commit and refuses automatic creation of a missing tag. Tag protection/immutability remains necessary for the check-to-publication race.

The independent review found three gaps corrected in this increment: malformed ABI report rows accepted by an envelope-only check, zero-byte untracked project files incorrectly rejected during dirty-source capture, and final ZIP native bytes needing explicit receipt binding. A separate remote-tag publication risk was also addressed. No simulator/runtime/physics changes were made.

## Evidence and limits

[manifest-abi-validation.json](manifest-abi-validation.json) records source HEAD, LF-normalized code hashes and fresh scoped-checkout commands/results. The checkout contains relevant tracked subtrees plus the exact working-file overlays; it is not a clean release candidate.

| Check | Result / scope |
| --- | --- |
| Release tools | 29 passed: 18 static ABI/parser/schema cases and 11 input/manifest/transfer cases |
| Export identity and packaging | 27 passed; real ZIP/readelf/manifest/transfer commands on disposable host-ELF payloads and synthetic native receipts |
| CI partitions | 9 passed |
| Shell syntax | Export and offline tool runners passed on LF checkout files |
| Existing website download tests | 5 passed; public ZIP names retained |

The integrated package fixture rejects malformed ELF and a still-valid executable changed after its qualification receipt. It verifies that failures emit no successful CI output handle. Separate compiled C/C++ fixtures exercise actual version needs and native readelf output. Manifest unit fixtures mock ABI/payload validation to isolate metadata cases; the packaging fixture invokes the real validators. An independent Terra 6.1 Max reviewer also ran both 27-test suites and found no further concrete blockers within this scope.

The [real-input scanner record](inspector-real-inputs.json) covers the available cached editor and ground-vehicle library, not an exported application. This additional check exposed GNU readelf 2.42's nonzero return for FDO dlopen notes. A narrowly recognized fallback now records that note-decoding limit while keeping core ELF inspection strict; malformed FDO and unrelated corrupt GNU properties remain rejected by regression tests. The cached editor requires up to `GLIBC_2.34`; the available ground library requires up to `GLIBC_2.38`. These are observations about the hashed cached files, not a release ABI floor; the final template/export and kernel library still need measurement.

No fully provisioned Godot/native application export, GitHub Actions upload or publication, ARM64 execution, distro ABI-floor acceptance or native GPU/controller/1080p qualification was performed. No packages were published. The recorded manifests are consistency evidence, not publisher authentication, SBOMs or full reproducible-build provenance. Application ABI floors remain unmeasured until this tooling runs on the provisioned exported payload.

## Primary references

- [GNU readelf](https://sourceware.org/binutils/docs/binutils/readelf.html) documents the static header, program-header, dynamic, version and note inspection used here.
- [Binutils 2.42 readelf source](https://gnu.googlesource.com/binutils-gdb/+/refs/tags/binutils-2_42/binutils/readelf.c), especially `print_fdo_note` and `process_notes_at`, explains the FDO-note compatibility case and framing checks.
- [GitHub Actions variables](https://docs.github.com/en/actions/reference/workflows-and-actions/variables) defines the allowlisted run, repository, workflow and ref identities recorded by capture.
- [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create) documents automatic tag creation and `--verify-tag`; repository-side tag protection remains a separate control.

Next run a provisioned export, retain its actual ABI inventory and select a measured runtime floor before implementing package wrappers. Complete source archive identity, SBOM/license closure, build-image identity and signed provenance under the remaining 02/13 gates.
