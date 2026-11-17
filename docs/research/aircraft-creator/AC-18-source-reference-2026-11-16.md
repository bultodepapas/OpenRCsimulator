# AC-18 exact published source resolution

**Date:** 2026-11-16; updated 2026-11-17. **Status:** SourceRef and selection-state contracts implemented; Home, preference
integration, published-flight admission and exported-target gates remain open.
This is a dependency of [AC-18](../../plans/aircraft-creator.md), not completion of
the [ClearView import journey](../../plans/clearview-aircraft-import.md).

## Contract

`openrc-creator-source v1` is a closed record containing a lowercase v4 aircraft
UUID, positive integer revision and exact revision-record SHA-256. It carries no
path, library root, latest selector or flight permission. The byte reader preserves
the integer token and refuses fractional/exponent revision spellings.

`SourceResolver.resolve(application_library_root, reference)` opens a fresh
read-only Store and requires that exact record in the current accepted index.
Archived history remains resolvable. Missing/corrupt current pointers are refused
even when Store could recover the same record through `previous.json`; existing
interactive Store recovery is unchanged. There is no latest or orphan lookup.

The resolver re-admits captured source bytes, validates placement, bindings and
paint, and reloads the exact stored aircraft bytes. V2 revision records rejoin a
restored document through the existing compiled-publication receipt. Historical
Store v1 definitions/snapshots remain opaque and receive `legacy-unbound`
provenance; no compilation or retrospective receipt is invented. A Store v1
record is distinct from an aircraft v1 raw record.

The result is a detached, non-flight `Resolved` owner. Its `source_ref()`, bytes,
model and presentation getters return copies, including nested packed arrays.
Public diagnostics are deeply separated from captured source notes. Sealing and
receipts are trusted-process conventions, not authentication. Recognized
ClearView sources remain unavailable while their independent gates are open.

## Evidence and limits

Snapshot `3728fb4f3f564a76a75dab47d4ca4c3a`, request
`b30a915d00314306a7ab4860b80d28e8`, passed **230 checks** on ANGELA_AIR with the
pinned official Godot 4.8-beta2 engine and zero checked errors/warnings. Coverage
includes A1 after A2/archive/reopen, exact hashes, unindexed objects, opaque
legacy records, indexed v2 snapshot/name/source/presentation mismatches, missing
and corrupted dependencies, current-pointer recovery refusal, ClearView refusal,
and copy/diagnostic isolation. Each deliberate mutation uses its own disposable
library. Source files and native-generated UIDs were integrated with hashes in
the external `main-source-ref-integration-20261116.json` receipt.

The service fixture includes matching runtime data registries. Earlier fixtures
with incomplete code or runtime data failed and remain retained. The full
consumer fixture, including unsaved-trial rejection, passed **231 checks** on
Windows (`cecc2d730a964601880bde6365d86769`, snapshot
`4ec0fd2fa1d8424c9a79b03c27fb32cf`) with zero checked errors/warnings.
Its macOS run remains queued on ANGEL; it is not covered by the earlier Mac
service pass. Linux, Home, renderer and packaged filesystem qualification are
not established here.

A separate, unintegrated preferences prototype uses an explicit selection-change
intent and compares recovered current/before/after values under the existing
settings lock. Its 86 transaction assertions passed on ANGELA_AIR
(`9a2bf003ff6849888ce58378dbe907cd`) and Linux
(`4458127acdab4d1192062945307016c5`, batch
`creator-selection-linux-20261116`). It preserves incidental saves, rejects
stale/absent selections, verifies rollback and malformed-backup refusal, and
requires the exact weather witness in proposed schema 8. Reader/writer, Home
unknown-state handling and flight consumers still need coordinated integration.
The standalone asynchronous owner is described below. Older writers can be prevented from overwriting
schema 8; their runtime stock behavior cannot be changed by this importer.

## Selection and asynchronous state

`creator_selection.gd` defines a closed exact-reference/start choice and a
before/after change intent. Its settings transition compares the recovered
current selection under the existing lock; it never grants an incidental save
permission to clear or replace the choice. Declaring proposed schema 8 here
does not enable a production writer or change current player settings.

`creator_selection_state.gd` separates the current UI choice from the last
acknowledged persisted choice. Source callbacks carry the exact in-process owner,
generation and SourceRef; stale callbacks, callbacks from a rebuilt owner and
duplicate completions are refused. Start-only changes retain source resolution.
Explicit stock selection invalidates it. Failed/conflicting saves preserve the
current UI choice; a fresh locked read may update only the disk expectation.
Source-ready is preview data and carries no flight permission.

The state module passed 43 Windows assertions in snapshot
`5fdd521d9e6d4dc1b38256977d32b5be` (`7ce5e90e37c9418a9d88a19feac6c765`).
The shared authoring fixture then removed an unrelated flight-test preload.
Snapshot `c0e45b650f1c448490b4a7853f8a72e2`, manifest
`f03ab9901c0a62f36ae487417ad9f9831f8e912ba970168b265b6020a2ef510b`,
passed 43 state, 62 published-trial and 86 transaction checks on ANGELA_AIR
(`4aca3635b6744567a4a977f6c3185ee7`, `0808075cbad74665bafe2e14b68d3bf0`,
`6a12d31ccb2249a0a62f9c9008d37bca`), with complete evidence, confirmed cleanup
and zero checked errors/warnings. Only the selection/state prerequisites, shared
fixture and state test are integrated. The writer remains a prototype; Home,
preference restoration, rendered review and published-flight gates remain open.
The external `main-selection-state-integration-20261117.json` receipt binds the
integrated bytes and native-generated UIDs. The adapted fixture also passed its
43 state and 62 published-trial assertions on Windows, with zero checked
errors/warnings (`601e5d21a583486b91e0404d5d9d90a4`,
`c388612cd5e845a2a4052328ff30a2e6`). Earlier Windows and Mac checks remain retained.

## Prepared saved revisions

`published_trial.gd` prepares a distinct `creator_published` payload from the
resolved owner. It reloads the exact raw v2 bytes and rejoins every model,
source, name and presentation field to that owner. The identity carries canonical
SourceRef JSON text and its SHA so generic log JSON readers cannot coerce the
revision token. Verification reconstructs the entire expected payload, including
owner/source object identity, and refuses cross-pairs even after public hashes
are recomputed. Historical Store v1/raw-v2 records keep their exact bytes and
`legacy-unbound` description; raw aircraft v1 remains research-only.

Snapshot `f2f0c95e113b4a138ba4a01aab244b5d`, request
`7c5012b6e2d44b6c993e809f68d62809`, passed 62 native ANGELA_AIR assertions with
zero checked diagnostics, including A/B cross-pairs, closed payloads, copy
isolation, integer-reference serialization, v1 refusal, and continued frozen
verification after the current library pointer disappears. Independent source
review found no concrete defect within this consistency scope. The two source/test
files and their native-generated UIDs were integrated with the external
`main-published-trial-integration-20261116.json` receipt.

Preparation remains separate from flight admission. `check_start` deliberately
returns unavailable, and Main/Home do not yet consume this payload. Numerical,
package-domain, actual live environment/contact, restart/replay and target gates
remain required before enabling that route.

## Actual flight configuration boundary

Source inspection identifies `green_paradise` as a selectable field with an
empty collision inventory, no lake and no RC track. This is not native launch
evidence. Home's Calm choice preserves the previous atmosphere, so Reference
air must also be explicit. Home has no soft-contact control; passing
`--soft-contacts=off` enters AppRoot's direct technical flight route and cannot
qualify the normal Home/Creator flow.

Keep contact configuration separate from SourceRef and frozen source hashes.
The existing per-flight request flows from Aircraft Creator's `trial_requested`
signal through AppRoot to `Main._new_flight_setup`. A visible, validated Creator
flight option belongs in that request and must be applied immediately after
creating `FlightSession`, before synchronous or staged setup. Main's later
contact assignment must preserve the same effective choice. Stock retains its
existing default. Persisting a new option requires a deliberately versioned
preference/transition change; the implemented schema-8 source selection is closed.

Before admission, inspect the actual installed collision world, lake, RC track,
field, weather and soft-contact setting. `weather_configuration()` is required:
the electric checkpoint canonicalizes calm/reference weather and does not
preserve every original weather setting. ORFL records the actual contexts when
recording starts, but is not an unconditional launch receipt. Preserve the
ClearView trial, package numerical and published-start refusals until these
runtime gates and their native evidence are complete.

## Remaining preference integration boundary

The private schema-8 reader/writer must ship together with Home/Root guards and
explicit stock/activity selection intents. The current production Root does
not consume active or unknown Creator selections or unknown exact weather;
copying only that reader would silently expose the remembered stock choice.
The prototype also preserves unreadable preferences instead of the previous
automatic `.bad` recovery, requiring an explicit recovery flow and deliberate
updates to the affected language-preference tests. These consumers remain
unintegrated.

Review found that the prototype writer's locked current-file check still
accepted nonpositive or coercible noninteger schemas that its reader refused.
The correction rejects those existing-file markers before selection CAS,
including stale writers, while retaining the separate absent-file path.
Snapshot `dfb69050d9d5464cbc1b69dacf93be6c` passed 98 native Windows transaction
checks (`db237cc9b0814aeea2b2e9afe008b31f`) with zero engine diagnostics, complete
evidence and confirmed cleanup. Six new malformed-marker fixtures retain
their exact original bytes and create no acknowledged previous copy. This is
prototype verification, not production schema-8/Home acceptance.

## Saved Home prototype checks

The bounded Windows Home fixture uses the ordinary empty-user-argument route
at a 1920×1080 window size, low scene detail, and disabled scenery, landscape
upgrade and enhanced grass. It is a functional/layout check, not a rendered
1080p, default-scenery or performance qualification.

Request `d838ffc98e124219ab02e86a7e4a8100` completed 291 assertions without an
assertion failure, but the checked run failed with 17 engine errors. Three
vegetation resources were absent from the reduced fixture; eight render
transform errors came from fitting navigation lights to a Creator visual with
no authored light hardware. That result does not qualify Home integration.

The next private candidate declares empty light hardware and material-name
bindings on Creator visuals, skips inferred fitting, preserves artist emission,
and explicitly refuses a requested hardware profile when none is available.
Its regression covers night/day/re-show, emission named `light_red`, finite
transforms, and unchanged default stock fitting. Native verification remains
pending. This capability boundary does not repair the generic one-sided
geometry fitter for other callers.

The next Windows run (`a363bd912dfd48ef8079e4e45d7577af`) completed 306 assertions
with no transform or missing-resource errors, but still failed: two stock
customization checks correctly rejected stale presentation-source pins. The
official `build_customization.py --root <candidate>` pipeline then regenerated
the seven-family registry and both overlays; `--check` passes for each private
source. No hash validator was weakened and no generated registry was hand-edited.

Frozen functional manifest
`1148b22ffa07e8b86f268dfdfc8ad18740441ff1f9cf7ce05ec75aa63ffc6a5b`
also includes an actual saved-Home noon/midnight/noon/midnight cycle, preview
reuse, unchanged source selection, no geometry-worker work for absent hardware,
and finite world transforms. It is queued for native Mac checks; Windows and
rendered 1080p acceptance remain pending. Previously saved customization
profiles retain their old source pins; regeneration is not an implicit migration.
