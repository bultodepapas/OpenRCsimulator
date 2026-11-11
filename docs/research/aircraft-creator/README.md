# Aircraft Creator evidence

Dated evidence for the [Aircraft Creator plan](../../plans/aircraft-creator.md) (prefix AC). The plan owns steps and gates; this index owns probes, commands and results. Everything here is software evidence from one development machine. It establishes neither target-hardware performance nor physical realism.

| Record | Content |
| --- | --- |
| [Revision 6 specification](2026-11-07-creator-specification-rev6.md) | External source specification, 2026-11-07, written against `997e2127` and never run against the application. Kept unchanged as the detailed reference for record, storage and UI contracts. The plan supersedes it where they differ. Its companion pack and historical probe receipts (H01, H02) were never in this repository. |
| [Estimated trainer package](estimated-trainer-package.md) | Derivation, borrowed values, domain and software checks of the first airframe and power packages (AC-05, AC-06). |

## Engine probes (2026-11-10)

Pinned engine `4.8.beta2.official.cafc17a19`, Windows x86_64 console build, headless, run as scratch scripts outside the repository. They decide mechanisms in the plan; each still needs its platform qualification where noted.

| Question | Observation | Consequence |
| --- | --- | --- |
| Bounded inflate without native code? | `StreamPeerGZIP.start_decompression(true, 65536)` inflates a zlib stream incrementally: 8 MiB of zeros round-trips exactly; with a 64 KiB bound the reader stopped after 130,608 output bytes having consumed 143 input bytes. A truncated stream yields fewer bytes without an error; bytes after the stream end are not consumed. `finish()` logs an engine error when decompressing and is not called. | AC-03 bounds PNG `IDAT` expansion in GDScript: exact expected size, stop at the first excess byte, refuse trailing data. No native utility. |
| Same with `decompress_dynamic`? | Bounded, but it logs an engine error whenever the bound is exceeded. | Not used: a hostile file must not be able to fill the log. |
| Exclusive file lock from GDScript? | A second `FileAccess.open(path, WRITE)` on a file already open for writing succeeds. | `FileAccess` cannot be the writer lock. |
| OS-owned process lock without native code? | Two processes: the first `TCPServer.listen(port, "127.0.0.1")` returns `OK`; the second gets error 22 (`ERR_ALREADY_IN_USE`) while the first lives. | AC-13 uses a loopback listener as the single-writer lock: released by the OS on exit, never stolen by age or PID. Windows only so far; Linux and macOS are qualified in AC-13. An unavailable lock makes the Creator read-only. |
| Exact-byte JSON writer? | `JSON.stringify(data, "", true, true)` sorts keys and prints full precision (`0.3333333333333333`, `1e-07`, `9007199254740991`). | Writer `openrc-json-bytes-v1` (AC-01). |
| Partial numeric parse? | `"1.5abc".to_float()` is `1.5`; `"1e400".to_float()` is `inf`. | Every reader validates the token grammar itself and checks finiteness. |
| Empty SHA-256 update? | `HashingContext.update` refuses an empty buffer. | The helper skips the update for empty input. |

## Source seams (2026-11-10)

Read-only inventory of the current tree (`7bff7849`), used to place the Creator without new kernel branches.

- **Loader.** `AircraftData.load_file` reads, hashes and parses the same bytes, then applies wheel profiles. The Creator's `record_loader.gd` does the same for bytes already in memory using the loader's public functions, so `aircraft_data.gd` keeps its bytes: that file is pinned by the solver identity and by `tools/godot/fixed_brake_legacy.py`. No bundled record is conventional and gearless; the closest coherent donor is `synthetic_stik_electric_4s_battery.json`.
- **Session.** `FlightSession.setup(path, expected_id, frozen_data)` flies an in-memory model when `frozen_data` carries `input_identity.format` and a matching `model.id`. Hand launch needs an airplane without landing gear and a runway field.
- **Main.** A frozen trial already enters through `workshop_trial`. A non-catalog aircraft additionally meets the catalog gate and battery-mode gate in `_prepare_flight` and the bundled-model build in `_build_world`. `AirplaneBuilder.datum` returns zero for an unknown ID, which is correct for a runtime model whose origin is the leading-edge datum by construction.
- **Root.** `_start_workshop_trial` freezes, qualifies, keeps the previous world until the new flight passes startup, and restores the same editor on return. The airship family is dispatched there by predicate; the Creator follows that pattern.
- **Workshop UI.** One `workshop` screen identity; the Creator is composed inside it, so trial start and return reuse the existing ownership.
- **Untrusted input already in the tree.** `CustomSkin` checks ZIP structure and a PNG header by hand but verifies no chunk CRC and does not bound `IDAT` expansion; `GLTFDocument` is used only by offline tools, never on runtime bytes.

## Software checks

Run with the checked runner, which fails on a non-zero exit and on any engine error or warning line:

```sh
python tools/godot/run_checked.py --label <name> --timeout 240 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/<test>.gd
```

Second run of 2026-11-11, working tree based on `1a96d7481` (uncommitted changes of the same day), Windows 11 x86_64, engine `4.8.beta2.official.cafc17a19`, headless, reference GDScript evaluator. Every test generates its fixtures in code; no binary or image fixture is committed. Tests that open a Creator library use a temporary folder under `user://` and remove it.

| Step | Test | Result |
| --- | --- | --- |
| AC-01 | `test_creator_bytes.gd` — writer vectors, exact-byte round trip, bit-exact floats over 8,000 sampled doubles, lexical integer tokens, control characters, bounded slow-number path, refusals | 0 failures |
| AC-02 | `test_creator_stl.gd` — binary/ASCII grammar, detection, limits, hostile numbers, degenerate facets | 262 checks, 0 failures |
| AC-03 | `test_creator_png.gd` — CRC, chunk order, bounded inflate, exact scanline size, expansion bomb, window differential, passive metadata | 207 checks, 0 failures |
| AC-04 | `test_creator_glb.gd` — container, strict JSON, cyclic and shared-child graphs, accessors, materials, images, ceilings, engine acceptance of the admitted subset | 356 checks, 0 failures |
| AC-07, AC-08 | `test_creator_import.gd` — capture once, content decides the format, placement known answers for 24 axis pairs, fresh preview nodes, STL and GLB | 0 failures |
| AC-05, AC-06 | `test_creator_compiler.gd` — byte-identical output, loader acceptance, `RecordLoader` equals `load_file`, mass and inertia known answers, fin equalities, dihedral, domain refusals | 196 checks, 0 failures |
| AC-06 | `test_creator_flight.gd` — trim, 20 s hands-off, control signs, spiral response to dihedral, hand launch, 240/480/960 Hz refinement | 56 checks, 0 failures |
| AC-09, AC-10 | `test_creator_trial.gd` — typed fields, provenance of starting values, domain bounds, snapshot and hostile-snapshot restore, freeze, verify against edited copies (model, placement, parts, paint, scale, added keys, relabelled identity), Airborne and Hand-launch checks | 0 failures |
| AC-13 | `test_creator_store.gd` — drafts, backup slots, versions, archive, compare-and-swap, quota, a kill at every transaction stage, tampered and forged pointers, indexes and records, two instances, two real processes on one lock | 509 checks, 0 failures |
| AC-15, AC-17 | `test_creator_visual.gd` — parts list, binding refusals, suggested axis and sign, posing known answers, propeller pivot and blur, flight-visual contract, solid paint, no shared resources, no orphan nodes | 223 checks, 0 failures |
| AC-10 | `test_creator_ui.gd` — eight steps, 1920×1080 and 1280×720 layout, worker import with stale-result discard, picking, invalid text, Test fly payload | 201 checks, 0 failures |
| AC-13…AC-17 | `test_creator_persistence_ui.gd` — bind the GLB fixture's parts, paint, save, conflict, publish versions 1–3, reopen with the same fingerprint and compiled bytes, automatic backup and recovery, archive, view-only second wizard, three-way leave guard, damaged entry | 95 checks, 0 failures |
| AC-10 | `test_creator_language.gd` — Spanish crawl of every step; step, field, library, part and paint messages present in all eight catalogs | 0 failures |
| AC-11, AC-17 | `test_creator_flow.gd` — real root and Main: both starts, refused runway and forged requests, edited trial refused by Main, a GLB flown with bound ailerons, elevator, rudder and propeller and solid paint, the wizard journey, return to the same document, the leave guard through the host, no recovery offer after a discard | 0 failures |

Regression checks of the shared files touched (`app/main.gd`, `app/app_root.gd`, `app/ui/workshop.gd`, catalogs), same run: `test_workshop_ui.gd`, `test_workshop_integration.gd`, `test_workshop_document_flow.gd`, `test_workshop_recovery_ui.gd`, `test_airship_workshop_flow.gd`, `test_ui_quit.gd`, `test_workshop_sizes.gd`, `test_workshop_trial.gd`, `test_workshop_starts.gd`, `test_aircraft_data.gd`, `test_custom_skin.gd` and `test_ui_language.gd` pass. `app/test.sh`, the visual suite and required CI were not run; these focused checks do not replace them.

Measured on this machine, not asserted in tests: a 200,000-facet binary STL reads in about 0.23 s and a 50,000-facet ASCII STL in about 0.75 s; the worst hostile 32 MiB ASCII file is refused in about 5 s; admission runs on a worker thread. An automatic backup costs about 30 ms plus 3 ms per MiB of model on the main thread (130 ms for a 32 MiB model), two seconds after the last edit. The wizard was viewed rendered at 1920×1080: weight and review steps, the moving-parts panel with the GLB fixture bound, solid paint, the library and the leave question. Other sizes were only laid out headless. No exported build, Linux or macOS run exists yet.

### Engine facts found on the way (2026-11-11)

- **Text to float is not exact.** `String.to_float()` on the pinned engine returned a double up to 717 units in the last place away from the one `JSON.stringify(..., full_precision)` had written, and zero for values below about 1e-292 (220,000 sampled doubles). `bytes.gd` therefore reads a number by searching for the double whose own spelling is the token. The engine's `JSON` reader uses the same conversion; a document snapshot stores floats as IEEE hex for the same reason.
- **The JSON writer emits bytes its own strict reader refuses**: U+0001–U+0007 and U+000E–U+001F raw, and U+000B as `\v`. The record writer refuses such text, and the wizard document drops control characters at entry.
- **`GLTFState.get_scene_node` returns freed objects** for mesh nodes; the part map walks `GLTFState.get_nodes()` and cross-checks it against the file.

## Independent review (2026-11-11)

A read-only Good Enemy review attacked the trust boundary, identity, physics honesty, integration and plan claims with scratch probes outside the repository. It found no blocker. Findings and their closure:

| Finding (reproduced by the reviewer) | Closure |
| --- | --- |
| A PNG whose zlib header declares a 256-byte window around longer back-references passed admission, then failed inside the engine PNG decoder and its JPEG fallback, with the texture silently missing. | The inflater refuses a stream whose declared window is smaller than its content (the engine inflater ignores the declared window; PNG decoders enforce it). Every embedded image is also decoded once at admission, and a decode failure refuses the model. Fixture added. |
| A frozen trial copy with an edited model or an emptied placement still verified; Main did not verify; the candidate docstring overstated its guarantee. | `freeze` loads the flying model from the exact bytes; `verify` reloads and compares the model, the placement and the trial id; Main verifies before skipping a catalog gate and refuses an edited trial. Docstring reworded: it is an ownership convention, not a security boundary. Fixtures added. |
| Starting values taken from the model's extent and the reference trainer were recorded as `manual`, player-entered. | The definition carries optional per-field evidence; unconfirmed starting values compile as `estimated` with a source that says so, and become `manual` only when the player types them. |
| The package domain did not bound control travel, servo time or thrust angles, although the borrowed derivatives are linear per radian (60° throws reached 58° angle of attack). | Domain bounds added for the three travels, servo time, both thrust angles and the starting charge. |
| A GLB without a default `scene` was admitted and made the importer log a warning on every build. | Refused with export advice. |
| `tEXt`, `tIME` and `bKGD`, which common editors write, were refused. | Admitted as bounded passive metadata; expandable metadata stays refused. |
| Flight metadata reported the source hash as a model-manifest hash; Pause did not name the aircraft under test. | Separate key for the source identity; Pause shows the unsaved aircraft's name. |

Items it left open are carried in [Open items](#open-items).

## Second independent review (2026-11-11)

A second read-only Good Enemy review attacked the store, the process lock, the record reader, parts and paint, the frozen trial and the document snapshot with 20 scratch probes. Findings (all reproduced by the reviewer) and their closure:

| Finding | Closure |
| --- | --- |
| A stored pointer, index or record whose `format` was a number, list or flag raised a script error inside the schema check, which then passed as valid: a writer committed on top of a malformed index. | The format member is type-checked before it is compared, at all four sites. Fixtures for five non-text spellings of pointer, index and record. |
| The record writer could emit control characters its reader refuses, so one pasted control character made a draft and its backup unsaveable with an error the player cannot act on. | The writer refuses such text with its field path; the document drops control characters when text is typed or restored. |
| Damage to an object of the newest change, at any later time, rolled the whole library back one generation and set the current pointer aside, with a message saying the change "did not finish". | The newest-change deep check is removed: a pointer only moves after its objects are installed and read back, so that damage is always later damage. It is now confined to its own entry like any other; the previous pointer is used only when the pointer or index itself fails. |
| `verify` did not cover everything Main reads from a trial (`scale`, `presentation_profile`, `presentation_identity`), and the `qualification` and `experimental` labels could be edited with a recomputed trial id. | A Creator trial has a closed key set and unit scale; both labels are checked against their only valid values. `definition_sha256` is documented as an unauthenticated label. |
| Binding numbers were integers in memory and floats after a store round trip, so reopening looked like an edit. | The document keeps whole numbers as integers however they were spelled. |
| A hostile snapshot restored a field showing one number while holding another, and accepted any 36-character identity. | Typed text is kept only when it is the text of the stored value or is recorded as invalid; the identity must be a lowercase version 4 UUID. |
| A record of 91,000 subnormal number tokens took 37 s to decode. | The exact search starts next to its answer, and a record needing it for more than 4,096 tokens is refused. |
| Store roots ending in a dot or named like a Windows device made the engine log errors. | Refused. |

Held under attack: bit-exact float round trip (19,000 doubles including subnormals and the largest finite values), junctions as the root or an object folder, a fully damaged root opened as writer (no file changed), three simultaneous processes over eight rounds (exactly one writer each), a foreign listener on the first lock port, index and draft fields of every wrong type, tampered bindings, appearance, placement and bytes.

Not reached by that review: a kill at an arbitrary instruction beyond the store's fault stages, the lock on Linux or macOS, hand-made GLB variants for the part map, `check_start`, the wizard UI.

## Open items

- **Numerical gate (AC-12, G05).** The [campaign](AC-12-numerical-campaign.md) ran and the gate is not passed. Behaviour after a large upset is explained in the [package derivation](estimated-trainer-package.md#behaviour-after-a-large-upset-ac-12-2026-11-11): propeller reaction torque, gyroscopic precession and a near-neutral spiral mode, not a solver artefact; wing dihedral is now an input. The package stays `experimental`.
- **Library growth (AC-13).** Every change writes a new index object and nothing is reclaimed, so the 4 GiB quota is a lifetime budget; the 2 MiB index fills at about 17 versions per aircraft with 512 aircraft and 512 drafts, far below the declared 1,000 versions; backup slots have no count limit; the "library cannot list any more entries" message then suggests saving a new version, which also grows the index. Compaction of superseded indexes and backups, and limits that agree with each other, are open.
- **Durability (AC-13, G03).** Interrupted-process only. Power loss is not claimed: GDScript cannot flush a directory. Windows NTFS only; Linux, macOS and exported builds open.
- **Loopback lock (AC-13).** Qualified on Windows with real processes. A halted instance keeps the lock until it is closed.
- **Automatic backup cost.** The store hashes the model bytes on every backup, on the main thread (see the measurement above).
- **Moving parts (AC-17).** A part turns about its own node origin; a non-uniformly scaled parent shears it. No rendered review; a real crash with bound parts was not flown. Control names inside binding messages are inserted untranslated.
- **Paint (AC-15).** Solid paint makes transparent surfaces opaque.
- **Hand-launch gate (AC-09).** The three-second hands-off check decides only whether the throw is offered. It is not a handling assessment.
- **Engine log on corrupt deflate data.** A stream that is well formed up to a corrupt block still makes the engine log one error while it is refused.
- **Real exporter corpus (G02).** No corpus of real STL, GLB and PNG exports has been run; the chunk and extension allow-lists may refuse common files.
- **Parser differential as a class.** Building the mesh from the preflight's own validated accessors instead of calling the engine importer would remove it; an STL-only first release is the conservative alternative. Decide before G02.
