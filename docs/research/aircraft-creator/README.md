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

Run of 2026-11-11 on the working tree based on `7bff7849` (uncommitted), Windows 11 x86_64, engine `4.8.beta2.official.cafc17a19`, headless, reference GDScript evaluator. Every test generates its fixtures in code; no binary or image fixture is committed.

| Step | Test | Result |
| --- | --- | --- |
| AC-01 | `test_creator_bytes.gd` — writer vectors, exact-byte round trip, lexical integer tokens, refusals | 0 failures |
| AC-02 | `test_creator_stl.gd` — binary/ASCII grammar, detection, limits, hostile numbers, degenerate facets | 262 checks, 0 failures |
| AC-03 | `test_creator_png.gd` — CRC, chunk order, bounded inflate, exact scanline size, expansion bomb, window differential, passive metadata | 207 checks, 0 failures |
| AC-04 | `test_creator_glb.gd` — container, strict JSON, cyclic and shared-child graphs, accessors, materials, images, ceilings, engine acceptance of the admitted subset | 356 checks, 0 failures |
| AC-07, AC-08 | `test_creator_import.gd` — capture once, content decides the format, placement known answers for 24 axis pairs, fresh preview nodes, STL and GLB | 0 failures |
| AC-05, AC-06 | `test_creator_compiler.gd` — byte-identical output, loader acceptance, `RecordLoader` equals `load_file`, mass and inertia known answers, fin equalities, domain refusals | 155 checks, 0 failures |
| AC-06 | `test_creator_flight.gd` — trim, 20 s hands-off, control signs, hand launch, 240/480/960 Hz refinement | 45 checks, 0 failures |
| AC-09, AC-10 | `test_creator_trial.gd` — typed fields, provenance of starting values, domain bounds, freeze, verify against edited copies, Airborne and Hand-launch checks | 0 failures |
| AC-10 | `test_creator_ui.gd` — eight steps, 1920×1080 and 1280×720 layout, worker import with stale-result discard, picking, invalid text, Test fly payload | 199 checks, 0 failures |
| AC-10 | `test_creator_language.gd` — Spanish crawl of every step, messages present in all eight catalogs | 0 failures |
| AC-11 | `test_creator_flow.gd` — real root and Main: both starts, refused runway and forged requests, edited trial refused by Main, the wizard journey, return to the same document, guarded discard | 0 failures |

Regression checks of the shared files touched (`app/main.gd`, `app/app_root.gd`, `app/ui/workshop.gd`, catalogs), same run: `test_workshop_ui.gd`, `test_workshop_integration.gd`, `test_airship_workshop_flow.gd`, `test_ui_quit.gd`, `test_workshop_sizes.gd`, `test_workshop_trial.gd`, `test_workshop_starts.gd`, `test_aircraft_data.gd`, `test_custom_skin.gd` and `test_ui_language.gd` pass. `app/test.sh`, the visual suite and required CI were not run; these focused checks do not replace them.

Measured on this machine, not asserted in tests: a 200,000-facet binary STL reads in about 0.23 s and a 50,000-facet ASCII STL in about 0.75 s; the worst hostile 32 MiB ASCII file is refused in about 5 s; admission runs on a worker thread. The wizard was viewed rendered at 1920×1080 (weight and review steps). No exported build, Linux or macOS run exists yet.

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

Left open, with their owning step:

- **Handling after a large upset (AC-12, physics owner).** Hands-off at trim the template holds 20 s within 0.13 m. After a one-second full-aft pull, or hands-off at full throttle, most in-domain variants roll past 80° of bank within 10 s and do not return to trim within 12 s. The reviewer could not tell propeller torque and a spiral mode with little dihedral effect from a model artefact. The package borrows the donor's roll derivatives and has no dihedral input. This is unresolved and is why the package stays `experimental`.
- **Hand-launch gate (AC-09).** The three-second hands-off check decides only whether the throw is offered. It is not a handling assessment.
- **Engine log on corrupt deflate data.** A stream that is well formed up to a corrupt block still makes the engine log one error while it is refused.
- **`StrictJSON` logs** an engine warning on a number token such as `1e999` and on invalid UTF-8. The GLB preflight pre-scans to avoid it; durable Creator records (AC-13) must do the same or the shared scanner must change with its owner.
- **Real exporter corpus (G02).** No corpus of real STL, GLB and PNG exports has been run; the chunk and extension allow-lists may refuse common files.
- **Loopback lock (AC-13).** Probed on Windows only; a port collision would make the Creator read-only until it is diagnosed.
- **Parser differential as a class.** Building the mesh from the preflight's own validated accessors instead of calling the engine importer would remove it; an STL-only first release is the conservative alternative. Decide before G02.
