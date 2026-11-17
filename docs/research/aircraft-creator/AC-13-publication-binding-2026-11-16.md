# AC-13: versioned Creator publication binding

2026-11-16. Owner: AC-13 / AC-CV persistence dependency. This records a bounded
publication/editor slice; it does not close numerical, Home or export gates.

Creator definition/document v4 publications use `openrc-creator-aircraft v2`.
`CompiledPublication.capture` synchronously captures one base Authoring document,
its accepted compiled candidate, admitted source, snapshot and validated
presentation. The frozen owner returns detached copies. The flat legacy writer
refuses v4/servo markers on either carrier or raw data. Both writers use the same
existing CAS, quota, object installation and root-pointer transaction.

The closed `openrc-creator-compile-binding v1` receipt contains profile
`openrc-creator-v4-servo-compiler-v1`, canonical definition SHA-256 and exact raw
SHA-256. It records the association checked by the trusted in-process capture
path. It is not a signature, source authentication or protection against trusted
GDScript fabricating an owner or coordinated rewriting of store history.

Reading validates the stored receipt, blobs, definition, UUID and law without
recompiling or replacing historical physical bytes. Before editor adoption,
the restored document must also match the source, snapshot, name and presentation.
Invalid presentation fails before replacing the current document. Opaque stored
JSON converts integers to floats; comparison preserves exact binary64 values
without an epsilon, while refusing boolean/numeric coercion and unsafe integers.
The snapshot's previous published revision legitimately differs from the new
record revision. Draft and recovery routes retain their independent behavior.

The direct Save aircraft handler now checks UI-owned invalid buffers as well as
document compilation, so bypassing a disabled button cannot save the last valid
value while invalid wingspan, datum or inventory text remains visible.

## Native evidence

- Snapshot `0e43fdb6b0484cee80eec23b1a643664`: 94 binding/store assertions passed
  on Windows (`6eaf6e3223164731974f1e3dd86ef8db`) and Apple Silicon
  (`9cc08ff5d59f4bf6a0b25c92dc44c827`). These include same-UUID/same-law mixed
  revisions, flat-writer/read refusals, CAS, detached captures and pre/post-commit
  interrupted-save recovery. Six assertions compare actual v1 Store preimage
  preparation and fixed-time bytes; that duplicate implementation remains only
  in frozen external evidence. The production test keeps the other 88 checks.
- Snapshot `24b2a87fd32847cc98546fd0667b6072`: 28 editor checks passed on Windows
  (`eaa10ebebf2547b0bd425f8dacb95b7e`) and Apple Silicon
  (`cd981557e038441fa2f10cc9bfb0515a`). They cover valid reopening, cross-pairs,
  both legacy/new-law mismatch directions, source/presentation refusals, preserved
  current edits, direct publication, v4 drafts and recovery. A 1920×1080 headless
  viewport establishes these UI behavior checks, not rendered qualification.

Stable reference snapshot `136cfe7949d44173922d756527d5abc0` then passed the
existing Creator persistence journey (95 checks,
`7e08a24f4f9b46539e862895ea6cc427`), ClearView UI gate/race journey (68,
`c6b3ec3f20e7483e9657f6769c85c66a`), production binding test (88,
`daf6be7f80d84281a6d15fe69d5f802d`) and new editor journey (28,
`af363183fb4b43b8ad91f84d3901c587`) on Windows, with zero checked diagnostics.
The first expanded regression fixture contained optional native descriptors
without their Windows libraries and failed during import; that frozen failure
remains separate. The corrected fixture explicitly excludes native-extension
discovery with `native/.gdignore` and qualifies the GDScript reference path only.
The production native-extension setup was not changed.

The complete existing Store regression additionally passed 509 assertions,
including all interrupted transaction stages and two real headless peer processes,
on Windows (`6c200ab16d844bd48d89b9d5e9a0ec10`) and Apple Silicon
(`25d2d0522438407e8861515edad4b836`). MCP batch
`creator-store-v2-native-20261116` retained frozen snapshot
`745a537bd7e541cf920f87e79d9cee53`; both checked outcomes are complete with zero
errors/warnings. Linux and packaged filesystem qualification remain separate.

The implementation and native-generated UIDs were integrated with before/after
hashes in the external `main-publication-integration-20261116/integration.json`
receipt. A subsequent Store comment correction documents the v1/v2 distinction;
it changes no behavior. Native extension, full-application, Linux, exported-build,
Home and target-rendering qualification remain open. Recognized ClearView
sources still refuse capture/publication while their flight gates are open.
