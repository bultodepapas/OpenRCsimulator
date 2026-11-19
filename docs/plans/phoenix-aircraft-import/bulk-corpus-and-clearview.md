# Phoenix bulk ZIP corpus scanner and ClearView integration audit

Status: research-only, 2026-11-18. This document adds implementation evidence to [the Phoenix plan](../phoenix-aircraft-import.md), not a runtime support claim.

## Audited baselines and findings

- Phoenix plan branch starting at `0358c66df67c77e1dce6d41cd7474e4b601e9ec2`; ClearView/Creator application inspected on main `f7b348e40aa5a44c4cc091d540fbffb55016e583`. These branches have diverged. Reconcile current main at integration time; do not blindly merge.
- The live [Creator UI](https://github.com/bultodepapas/OpenRCsimulator/blob/f7b348e40aa5a44c4cc091d540fbffb55016e583/app/ui/aircraft_creator.gd) routes ZIP files by extension into ClearView. Phoenix requires shared bounded content discovery and explicit provider/candidate selection, with no silent fallback after a chosen reader fails.
- The existing [ClearView archive](https://github.com/bultodepapas/OpenRCsimulator/blob/f7b348e40aa5a44c4cc091d540fbffb55016e583/app/workshop/creator/clearview/archive.gd) implements strict ZIP32, ASCII names, raw DEFLATE, 64 MiB outer files, 256 MiB aggregate declared expansion, 4096 members and 32 MiB per member. Phoenix ZIP archives can be 1+ GiB, and their PKG payloads use framed zlib. Reuse its security principles and its targeted tests, not its reader without an owner-reviewed generalized contract.
- [ClearView converter](https://github.com/bultodepapas/OpenRCsimulator/blob/f7b348e40aa5a44c4cc091d540fbffb55016e583/app/workshop/creator/clearview/converter.gd) converts AC3Db to self-contained GLB and then calls the shared [SourceImporter](https://github.com/bultodepapas/OpenRCsimulator/blob/f7b348e40aa5a44c4cc091d540fbffb55016e583/app/workshop/creator/source_importer.gd). Its receipt has `physics_imported=false`. Phoenix should follow the same admission boundary only *after* its own GEO profile is proven, not use a generated GLB as flight admission.
- [ClearView motion](https://github.com/bultodepapas/OpenRCsimulator/blob/f7b348e40aa5a44c4cc091d540fbffb55016e583/app/workshop/creator/clearview/motion.gd) checks ownership, hierarchy, rigid frames, neutral poses, overlapping movement and budget limits. Reuse tested hinge-frame algebra if the source coordinate convention is independently proven; do not copy AC3D-specific marker guessing into Phoenix.
- The current [SourceInstallation](https://github.com/bultodepapas/OpenRCsimulator/blob/f7b348e40aa5a44c4cc091d540fbffb55016e583/app/workshop/creator/source_installation.gd) is tied to `openrc_clearview`. Phoenix requires a new closed provider schema and explicit source-to-member-to-visual-to-definition-to-physical association checks.

## Delivered research code

- [scan_bulk_zip.py](../../../research/aircraft-creator/phoenix/scan_bulk_zip.py): local read-only, bounded ZIP32 census. Requires the exact outer ZIP SHA-256, validates the ZIP directory before constructing members, preserves each ZIP entry occurrence, sorts PKG work deterministically, refuses unsafe/colliding decoded names, and reads/CRC-checks only explicitly selected PKGs.
- [test_scan_bulk_zip.py](../../../research/aircraft-creator/phoenix/test_scan_bulk_zip.py): 16 synthetic cases covering selection, duplicates, case collisions, traversal, damaged CRC, wrong hash, unsafe symlink, exclusive report, ZIP end-record limits, declared expansion and per-window work limits.
- The scanner uses Python's `zipfile` and the existing research `inspect_pkg.py`. It never extracts paths, executes models, decodes GEO, installs third-party assets or produces flight-ready files.

### Run on a permitted local, immutable sample

    sha256sum /path/to/Planes.zip
    python3 research/aircraft-creator/phoenix/scan_bulk_zip.py /path/to/Planes.zip --sha256 EXACT_OUTER_SHA256 --start 0 --limit 25 --report /path/to/new-census.json
    cd research/aircraft-creator/phoenix && python3 -m unittest -v test_scan_bulk_zip

An existing output file is refused. The historical catalog's central-directory SHA is **not** an outer archive SHA. A scan window that has no skipped members is not proof that all members, dependencies or aircraft families in the ZIP are valid.

### Limits and truthful evidence

Default research limits: outer ZIP 2 GiB, 10,000 entries, 8 MiB central directory, 8 GiB aggregate *declared* uncompressed content, 64 MiB per selected PKG, 256 MiB total selected PKG bytes per scan, 128 selected PKGs, 1 MiB JSON report. These are not measured peak RSS, CPU time or cross-platform guarantees. The scanner verifies outer SHA before/after, but this does **not** establish atomic filesystem capture. Python zipfile decodes member names; raw ZIP filename bytes are not preserved and the census cannot be used as an authoritative runtime namespace. Only selected members have verified bytes/CRC.

### Test evidence and limitation

On Linux/Python 3.13, 16 local synthetic scanner tests passed. **Important:** the local environment did not have the repository's `inspect_pkg.py`; to exercise the wrapper we used an original, temporary minimal PKG stand-in (not committed). These results validate the ZIP wrapper boundaries and test harness against that stand-in, **not** integration with the real repository PKG inspector. The developer must rerun all tests against the real checked-out `inspect_pkg.py`, then repeat with pinned real samples and record exact source/fixture hashes, memory/time, reasons for refusal and application/engine versions. Godot, Builder, actual Phoenix samples and flight were not executed in this round.

## Implementation steps (proposed, not delivered)

1. AC-PX-00: run the tool against permitted exact local bulk ZIPs and compare its selected PKG summaries with the existing pinned seven/25-package receipts, distinguishing unsupported legitimate dialects (short numeric header, padding variation) from corruption.
2. AC-PX-01: add a content-first, bounded ZIP/PKG dispatcher at Creator's worker boundary. A ZIP may contain ClearView, Phoenix, both, or neither. Require explicit provider selection when ambiguous. Preserve old ClearView controls/tests and never route an unsupported ZIP into the STL fallback.
3. AC-PX-01: port PKG framing and bounded zlib to GDScript, preserving raw name identities and full tree including empty directories; prohibit physical extraction and unresolved relative references.
4. AC-PX-02: carry the MOD data grammar and provenance through a closed Phoenix-specific observations provider; traverse every mandatory dependency transitively.
5. AC-PX-03: require owned Builder exports with independently known coordinates, UVs, normals, parent transforms and hinges before implementing a GEO decoder. Compare and re-admit only generated GLB bytes under existing Creator size/mesh/material limits.
6. AC-PX-04…09: preserve selected paint, arbitrary hinges, source/GLB/definition/compiler proof, Store versions, cancellation, restart, exact trial gates, native exports and numerical qualification. Keep previews and draft status separate from flyability.

## Reuse decision

Reuse the **SourceImporter inspection**, result/diagnostic schema, checked ZIP concepts, cancellation pattern, visual-hinge algebra and existing test conventions. Avoid reusing **ClearView params parser, AC3D decoder, raw-DEFLATE as zlib, `openrc_clearview` provenance namespace or its single-source Store assumption** without explicitly extending their contracts. Keep external aircraft packages and any unclear-licence test assets out of the Git repository.