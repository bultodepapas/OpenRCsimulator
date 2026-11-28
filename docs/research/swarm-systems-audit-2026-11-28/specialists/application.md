# Application and user-data review

Source commit `8d4169f8febfd7d78a028eaa817414217a54f24b`. These cases concern data displayed or edited by the pilot. Neither changes flight state, the replay law, numerical precision or the 240 Hz clock.

## APP-1 · A second FPV session can replace a faster personal best

**P2, requires two overlapping race-book readers sharing one user directory.** Enter the FPV course in two simulator instances. Finish the same course in 60 s in A, then in 75 s in B. The book reloaded after B shows 75 s and one finish. A third instance opening the book will display that slower record. If B flies a different course, its save removes A's course from the current book. Both individual attempt files survive.

The course information pane calls the first-load-only `_load_records()` at `app/vehicles/multirotor/multirotor_scene.gd:1574–1579,1597–1606`. The terminal signal at line 272 schedules the handler that folds the result into that scene's cached dictionary and saves the complete book at lines 1485–1495. The previous-copy and read-back checks in `app/vehicles/multirotor/race_records.gd:86–117` verify the supplied bytes. They cannot detect an earlier finish missing from a valid snapshot. `RaceRecords.apply()` computes counts and minimum times from the supplied book at lines 181–191,195–226.

The checked Godot 4.8-beta2 probe uses two actual FPV scene objects in one process, the real terminal-result callback, independent real session outboxes and actual files. It supplies synthetic terminal results and calls the HUD's initial read directly. It models the ordering of two desktop sessions without launching UI windows or flying timed laps. Every write occurred sequentially. [Probe](../../../../research/swarm-systems-audit-2026-11-28/probes/race_book_two_windows.gd) · [Console receipt](../../../../research/swarm-systems-audit-2026-11-28/evidence/race-book.log)

| When B first loaded the book | Courses flown | Current book after both finishes | Attempt files |
| --- | --- | --- | ---: |
| Before A finished | Same | 75 s best, 1 finish | 2 |
| After A finished | Same | 60 s best, 2 finishes | 2 |
| Before A finished | Different | 1 course, A's entry absent | 2 |
| After A finished | Different | 2 courses, A's entry present | 2 |

**Repair and acceptance.** Commit a terminal-result delta against the latest readable book under a shared writer lease, including the read, apply, backup and replacement. Refresh the scene's summary from the committed result. If retries or reconstruction from the attempt files are supported, use their stable publication IDs to keep one contribution per attempt. Reloading just before an unlocked write still permits two writers to read the same previous value. Test both reader orders above, truly overlapping writers, retry of the same publication ID and backup recovery. Preserve the existing course limit and the scoring rules for cancelled and aborted attempts. Per-attempt filename collisions (race audit A12), interrupted replacement (A13) and malformed entries (A16) have different triggers. The previous copy may retain an earlier record until another save rotates it.

## APP-2 · Switching profiles makes an unsaved duplicate unreachable

**P3, single Controls window.** Duplicate an existing controller profile, customize the copy and switch to the original before saving. The picker offers the original and **New profile**. Neither item returns to the copy. Saving the original leaves Controls open with an instruction to select the other unsaved profile. The copy still exists in memory, and explicitly discarding all drafts removes it. The saved original remains on disk.

The Duplicate button binds to `_duplicate_profile()` at `app/ui/controller_setup.gd:1010–1012`. The handler creates a fresh UUID and calls `_set_draft_profile()` at lines 2913–2927, which uses a `profile:<uuid>` context at lines 2556–2561. Ordinary switching remembers the actual draft under that context at lines 2530–2544. The picker builds its entries from the saved profile list at lines 2590–2604. Its New entry selects the device's separate draft context at lines 2607–2619. The other dirty draft is found at lines 400–407, reaching the instruction to select it at lines 4255–4258. The dialog's explicit Discard closes Controls at lines 509–519.

The checked Godot 4.8-beta2 run used the actual Controls widget and ConfigFile store with one synthetic gamepad observation. The probe visited every picker entry. It found only “New profile” and “Training · Gamepad”. The edited name and roll-axis 9 remained in the internal draft. Saving the original emitted zero close signals and left the screen dirty. Explicit discard closed it, and reopening storage found only the original with its original name and roll assignment. In the immediate-save control, the duplicate reloaded under a new ID with the edited name and axis 9. [Console receipt](../../../../research/swarm-systems-audit-2026-11-28/evidence/controller-draft.log)

**Repair and acceptance.** Give each unsaved duplicate a selectable entry with its own UUID until Save or Discard, and preserve edits when switching away. Exercise this sequence with pending name and channel edits, two unsaved duplicates, an existing device's New draft and an immediate-save control. Verify that saving the selected copy produces a separate durable profile, that the original is intact and that a genuine remaining dirty draft is reachable through the action suggested by the UI. Existing `app/tests/test_controller_profile_creation.gd:85–102,123–133` covers switching a New draft and saving Duplicate immediately. Its tests do not switch away from an unsaved duplicate. [Probe](../../../../research/swarm-systems-audit-2026-11-28/probes/controller_duplicate_draft.gd)
