# AE-03a — named-library save interruptions

**2026-10-19 · Save-boundary and handled-failure staging slices delivered; AE-03 remains partial.** The unchanged public `Store.save_variant` delegates to a private transaction seam with an optional local checkpoint callable. There is no global failpoint, player setting or saved-record/schema change. The original save-boundary baseline is retained below; the later cleanup slice has its own logs and source identities.

The new `test_workshop_store_interruptions.gd` exercises the actual save path with the current Jensen Ugly Stik source and generated bindings. Its default mode returns an explicit failure at each boundary and rereads the resulting filesystem prefix. Optional `--process-cuts` runs a separate writer, records the reached boundary, then kills that writer before stack unwinding. The reader checks the on-disk prefix after the writer exits. Every case uses a unique direct child of `user://` with the `workshop_store_cuts_` prefix; the player library is never selected.

## Save-boundary baseline

| Scenario | Cuts | Boundaries |
| --- | ---: | --- |
| First publication | 10 | Staging/revisions directories; revision temporary write/readback/rename; manifest temporary write/readback/rename; before/after UUID publication |
| First update | 8 | Revisions directory; revision temporary write/readback/rename; manifest temporary write/readback; current-to-backup rename; manifest commit |
| Update with an existing backup | 9 | First-update boundaries plus prior-backup removal |
| Update after backup recovery | 8 | Common revision/manifest boundaries; invalid-primary removal; manifest commit while preserving the valid backup |

The default matrix passed **35 cases, 796 checks, 0 failures**. Native Windows abrupt-writer termination passed **35 cases, 1,076 checks, 0 failures**. The [process log](checks/native-process-cuts.log) and [default log](checks/workshop/test_workshop_store_interruptions.log) retain the final results.

The matrix checks these outcomes:

- A first save is invisible until directory publication. An update exposes the previous committed build until the new manifest commits. The loaded record contains the complete expected recipe, authored paint/visual seed and source/compiler/dependency pins.
- Listing/loading does not change any prefix bytes or promote temporary files, staging directories or orphan revision files. Previously written immutable revisions retain their exact bytes.
- An update retry creates a revision beyond existing files in the published UUID and rereads exactly. It never overwrites an orphan candidate revision; stale retries refuse. A first-save retry starts at revision 1 in a new staging directory and ignores the earlier uncommitted staging directory.
- Abrupt termination leaves the exclusive reservation in place. Reads remain available, overwrite/delete refuse, and Save a copy succeeds without changing the reserved build. The fixture removes its orphan reservation only after its sole writer has exited; production never steals it automatically.

The baseline storage suite passed **141 checks** before adding the seam. The final run passed **all 25 Workshop suites** and the three presentation companion suites (`test_aircraft_customization`, `test_smoke_profiles`, `test_presentation_sources`), with no engine errors. Model, descriptor and customization generator checks passed for five visual families/eight descriptors; customization and checkout tests each passed eight cases. Native editor import and [all 1,110 GDScript parse checks](checks/parse-all.log) passed. The parse sweep used the same `--check-only --script res://...` command as `app/test.sh`, with four independent native processes. Logs are retained under [checks](checks/); the [verification receipt](verification.json) identifies the tested storage source bytes and log hashes. These are software/storage checks, not full-app, current-fleet flight, physics or performance acceptance. Unrelated concurrent track edits may postdate individual checks.

An initial harness run failed four complete-payload assertions because its paint fixture omitted the required `pattern` and `accent` fields; its [console output](checks/initial-fixture-output.txt) is retained as a transcription. The fixture now supplies both and asserts that the bound profile validates with nonempty paint before saving. No storage-recovery failure was found in that attempt. Windows termination is checked using the reached-boundary marker, writer return status and retained reservation rather than a nonzero exit code alone: Godot's [Windows kill implementation](https://github.com/godotengine/godot/blob/4.7-stable/platform/windows/os_windows.cpp#L1490) calls `TerminateProcess` with exit status zero.

## Ordinary-failure staging cleanup

Handled first-save failures now discard their own known staging files before releasing the UUID reservation. A scope guard retains that reservation through cleanup and is released immediately after successful publication. It never scans or reclaims earlier stages, published UUIDs, trash generations or orphan locks. Abrupt termination does not unwind the guard and still leaves its staging and reservation intact.

Cleanup verifies the normalized store/staging paths and matching live reservation, then preflights the entire layout before deleting any file. It accepts at most eight child entries across the stage and its single `revisions` directory: `manifest.json`, revision `00000001.json`, and their UUID-named temporary files. Unknown files (including hidden entries), other revisions, nested directories, links or excess entries retain all bytes with a diagnostic. Removal is nonrecursive and rechecks path/link guards. A filesystem removal error retains the remaining data for a later retry; it cannot redirect cleanup to the committed build. Godot documents [`DirAccess.is_link`](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html#class-diraccess-method-is-link) for symbolic links, directory junctions and other reparse points.

| Check | Result | Evidence |
| --- | --- | --- |
| Focused staging suite, including actual Windows open-file removal refusal/retry | 157 checks, 0 failed | [Final focused run](staging/checks/staging-io.log); [earlier 151-check draft](staging/checks/staging-draft.log) |
| Handled save-boundary matrix with explicit staging assertions | 35 cases, 806 checks, 0 failed | [Default run](staging/checks/workshop/test_workshop_store_interruptions.log) |
| Abrupt native Windows writer termination | 35 cases, 1,086 checks, 0 failed | [Process run](staging/checks/native-process-cuts.log) |

The focused suite covers complete/partial known layouts, the eight-entry boundary and refusal beyond it, every link location from store ancestor to revisions, absent/busy/mismatched reservations, wrong roots and published-path refusal. Injected revision/manifest readback corruption exercises the actual save error path. An unexpected-file case deliberately emits the retained-data warning and verifies every byte survives; older unrelated stages remain untouched. A held Windows file handle exercises a real removal error, followed by successful cleanup after release. The additional six checks were added after the original 151-check run; that original log is retained.

A read-only second review found no concrete issues in the cleanup, reservation lifetime or initial safety tests. This was code review, not an additional test execution. The [cleanup verification receipt](staging/verification.json) records the final source hashes and run scope separately from the original baseline receipt.

## Reproduce

Import the matching Godot build first, as described in [TOOLS](../../../TOOLS.md#developer-setup). From the repository root:

```powershell
$GodotWindows = (Resolve-Path .tools/Godot_v4.7.2-stable_win64_console.exe).Path
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_workshop_store_interruptions.gd
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_workshop_store_interruptions.gd -- --process-cuts
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_workshop_staging.gd
```

The default test is discovered by `app/test.sh`. The separate process-cut run can exceed its ordinary unit timeout. Run the other Workshop, presentation and generation checks using the [Workshop commands](../../../TOOLS.md#aircraft-workshop). Inspect engine errors as well as exit status.

## Remaining qualification

This record covers completed filesystem-operation boundaries and bounded, live-owned cleanup on native Windows with Godot **4.7.2 stable `ed1daf0bf`**. It does not interrupt an operation halfway through a write/rename, simulate power loss, establish directory durability, qualify another OS/filesystem, or reclaim orphan/crash stages. Corrupt-record and delete/restore behavior also retain their existing focused tests; this matrix does not simulate abrupt termination during delete/restore. Draft-recovery storage is a separate [AE-03c](../AE-03c/README.md) contract. The [active AE plan](../../../plans/aircraft-editor.md#56-implementation-packages-and-order) owns the remaining work.
