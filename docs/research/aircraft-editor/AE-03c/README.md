# AE-03c — Workshop draft recovery

**Evidence date:** 2026-10-19. This record covers the bounded recovery snapshot, its Workshop integration, and native dialog captures. Recovery is separate from the named build library: the snapshot holds the accepted recipe/profile and source pins apart from pending numeric, appearance, and smoke text. Restore is an explicit action that creates a detached, unsaved build; the ordinary validation and `Trial.freeze` path still decides whether it can be saved or flown. A stale or unavailable snapshot remains readable, cannot silently rebind selections, and is not automatically promoted or rewritten.

The interactive Home/Pause Workshop opts into the default `user://` recovery path. Tests and capture tools opt in only with isolated roots. A 750 ms one-shot debounce saves data-only state: accepted build, invalid or unapplied text buffers, page, name, and bounded preview camera state. It does not include the measurement dialog's unsent values or prior Undo history. **Restore as a new build**, **Later**, and **Discard recovered draft** remain explicit choices. Later keeps the original snapshot and prevents automatic replacement until it is restored or discarded.

## Verification

The focused backend test completed with **98 checks, 0 failures**. It covers first publication and update interruptions at each of the four injected write boundaries, reread/restart behavior, temporary-file non-promotion, current/backup retention, lock refusal, path collisions, and separation from named library data. Compare-and-swap coverage verifies exact-record digests, competing first writers, stale and matching updates, stale and matching discard, backup-selected updates, and digest-guarded discard of a bounded corrupt record. The earlier 80-check run is retained as history. The focused Workshop recovery UI test completed with **31 checks, 0 failures and no engine errors**, including launch blocking during review, Later, dirty-build guard cancellation, restore preserving invalid buffers, detached ancestry, unavailable-field refusal before mutation, two-editor stale-save handling, stale restore/discard refresh, and preservation of the original stored text after refusal.

The review pass found two restore-path hazards before the final run: canceling the dirty-build guard could leave Test fly disabled, and an unavailable saved selection could be discovered after restore began. Cancellation now restores the editor action/focus state, and restore preflights all saved editor fields before mutating the active draft. A stale restore now refreshes the captured digest before reopening review; a stale discard also refreshes and requires the user to review the replacement before discarding. The final UI checks cover these behaviors and verify that the refused snapshot remains unchanged.

The first two-editor UI attempt opened both recovery dialogs at once in one SceneTree. The fixture now models separate sessions with sequential dialogs; the final run passes 31 checks without engine errors. This was a test-harness sequencing issue, not a persistence failure.

The native capture helper opens the actual Workshop `ConfirmationDialog` in an isolated user-data root, saves the initial frame, then exercises Later, Restore, and Discard through their UI signals. It checks the raw `invalid` numeric buffer and `#BAD` color in the visible scroll area, verifies Later has initial focus, and measures the dialog and each enabled action against the viewport.

From the repository root, run it with the absolute path because the helper is outside `app/`:

```powershell
$exe = (Resolve-Path .tools/Godot_v4.7.2-stable_win64_console.exe).Path
$scriptPath = (Resolve-Path research/aircraft-editor/capture_recovery.gd).Path
$evidencePath = (Resolve-Path docs/research/aircraft-editor/AE-03c/evidence).Path
$arguments = @('--path','app','--rendering-method','gl_compatibility','--script',$scriptPath,'--',
    '--lang=en','--size=1920x1080',"--out=$evidencePath\recovery-en-1920x1080.png",
    "--evidence=$evidencePath\recovery-en-1920x1080.json")
$run = Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($run.ExitCode -ne 0) { throw "Capture failed with exit code $($run.ExitCode)." }
```

For Spanish 720p, change the language and size arguments to `--lang=es` and `--size=1280x720`, and use the matching Spanish PNG/JSON names.

| Capture | Viewport | Dialog rect (window coordinates) | Buttons (dialog coordinates, x/y/w/h) | Result |
| --- | ---: | ---: | --- | --- |
| [English capture](evidence/recovery-en-1920x1080.png) · [JSON](evidence/recovery-en-1920x1080.json) | 1920×1080 | 606/300/708/480 | Discard 12/423/298/49; Restore 318/423/285/49; Later 611/423/85/49 | All inside; Later focused; 0 failures |
| [Spanish capture](evidence/recovery-es-1280x720.png) · [JSON](evidence/recovery-es-1280x720.json) | 1280×720 | 131/120/1018/480 | Discard 12/423/387/49; Restore 407/423/450/49; Later 865/423/141/49 | All inside; Later focused; 0 failures |

Both captures used Godot 4.7.2, the GL Compatibility renderer, and an NVIDIA GeForce RTX 3090. The dialog was embedded in the viewport. The screenshot evidence is a UI/layout check; it makes no performance or flight-simulation claim. The Spanish action labels were checked against the expected translated strings. The invalid numeric and color buffers are visible at the bottom of the scrollable recovery summary.

The first Spanish capture exposed that the new recovery actions had not yet been translated. Those strings were added to [`app/i18n/es.po`](../../../../app/i18n/es.po); the final capture checks the exact translated title and action labels. The native helper restricts its disposable scratch root to one direct child of `user://` with the capture-specific prefix, and removes only that scratch tree after each run. The dialog summary now uses human-readable setting labels and omits empty appearance-buffer rows.

Logs: [98-check backend](evidence/backend-test.log), [historical 80-check backend](evidence/backend-test-80.log), [initial 18-check UI run](evidence/recovery-ui-initial-18.log), [historical 22-check UI run](evidence/recovery-ui-22.log), [final 31-check UI run](evidence/recovery-ui-test.log), [English capture run](evidence/recovery-en-1920x1080.log), and [Spanish capture run](evidence/recovery-es-1280x720.log). The initial UI log is retained as an earlier passing run. In the first test attempt, the test treated `Workshop.save_named_variant()` as returning a boolean even though it was `void`; the test was corrected to call it and inspect the resulting saved identity. This was a test-harness error, not a product failure.

## Persistence boundary

The implementation writes a bounded temporary snapshot, reads it back, rotates the prior committed record to a backup, then commits the new record. A lock is never reclaimed based on age. Injected failures exercise those code boundaries and verify restart selection, but they do **not** simulate process termination at the OS level or hardware/filesystem power loss. Godot documents `FileAccess.flush()` as writing its buffer and notes that it can help if the project crashes; the API reference does not state a power-loss durability guarantee. `DirAccess.rename_absolute()` is documented as a move/rename operation, with overwrite behavior when permitted; this evidence does not establish its atomicity across filesystems or platforms. See the [FileAccess reference](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html), [DirAccess reference](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html), and [Godot data-path guide](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html). No filesystem power-loss claim is made.

## Source identities

SHA-256 values below identify the exact source files used for the final checks and captures on 2026-10-19. They are evidence of the tested source state, not a signature or proof of physical durability.

| File | SHA-256 |
| --- | --- |
| [`app/workshop/draft_store.gd`](../../../../app/workshop/draft_store.gd) | `F4603FA608FE4916B089FEEB8395A4C15F8C96415302A7DE434D4115C1862CA2` |
| [`app/tests/test_workshop_drafts.gd`](../../../../app/tests/test_workshop_drafts.gd) | `5693F65642F707957447259C75825A1B2A494C5AF030F54AF38A1E47DB73051A` |
| [`app/ui/workshop.gd`](../../../../app/ui/workshop.gd) | `95DFAFE0DE0DC7C6F91490550BF6B743E1CE20D4B47CF440456E380A76C9F5B4` |
| [`app/app_root.gd`](../../../../app/app_root.gd) | `D7A01B46D48F96561EA31C1D540A833AE2DCDCB55D6988947C9A4FAB28B964BC` |
| [`app/i18n/es.po`](../../../../app/i18n/es.po) | `EE6C6B9FC3C30A1749AF82F423014A166423A93F0251428C136465CADDA6B92B` |
| [`app/tests/test_workshop_recovery_ui.gd`](../../../../app/tests/test_workshop_recovery_ui.gd) | `F9B932DE447725DAFEDC5CB8762EB56E81D015CEE15B13DC12909EDEC73BE078` |
| [`research/aircraft-editor/capture_recovery.gd`](../../../../research/aircraft-editor/capture_recovery.gd) | `C71A9348E143D36D4D8F8EBFF8CF65008F00368D62FFCCFE01F72E30C523C6D8` |
