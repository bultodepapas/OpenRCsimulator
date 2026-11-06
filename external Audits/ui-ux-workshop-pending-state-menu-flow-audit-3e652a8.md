I continued the code and menu-flow audit and found **five additional issues**. The most important is in Workshop: **Undo can silently erase an unapplied lighting edit, and Redo does not recover it**. The other findings affect explicit discard, selected-page indicators, cancellation, and focus during resizing.

This pass is frozen at [commit `3e652a8`](https://github.com/bultodepapas/OpenRCsimulator/commit/3e652a879ab8e928fc7d0b23d8303ac5724c3be6). I checked the current [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/external%20Audits/CONSOLIDATED-AUDITS.md), including A1–A12, and reconciled these findings against the previous UI review. The ledger now records the earlier **New profile identity** issue as repaired; I have not counted it again.

The complete 12-page report contains reproduction steps, source references, proposed repairs, and acceptance criteria:

[OpenRC_Menu_Flow_Audit_3e652a8_2026-11-06.pdf](https://chatgpt.com/library?file_id=libfile_a8a9aa52a068819196ee933ba8bd731b&account_id=personal)

The accompanying evidence includes the focused probes, checked logs, exact source identities, Godot research, and running-application transcript:

[OpenRC_Menu_Flow_Evidence_3e652a8_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_34c63e1383148191995363cf331639c1&account_id=personal)

## Prioritized findings

| ID | Priority | Finding | Player impact |
|---|---|---|---|
| **UI3-01** | **P1** | Undo and completed recovery omit pending Lighting zone state | An unapplied edit disappears without a clear decision from the player |
| **UI3-02** | **P2** | Discard and load retains outgoing Smoke text | A successfully loaded build remains dirty, with Save/Test fly disabled |
| **UI3-03** | **P2** | Rejected navigation changes the selected tab or dropdown | The interface identifies the wrong page; selecting the intended destination again can do nothing |
| **UI3-04** | **P2** | An invalid first color edit leaves Cancel disabled | The interface tells the player to cancel while disabling the visible cancellation action |
| **UI3-05** | **P3** | Preview controls lose focus during very short-window reflow | Keyboard navigation stops until the player uses a recovery route |

There is also a **qualified Companions finding** described below. Its UI behavior was reproduced with a declared status fixture because the normal enabled-companion launch was blocked by the current solver-profile pin.

## 1. Undo silently loses a pending Lighting edit

**This is the first issue I would fix.**

I reproduced the following sequence in the running application:

1. Choose **Custom** Lighting.
2. Open **Flight setup** and change Power multiplier from **1.00 to 1.10**.
3. Return to **Lighting → Customize zones**.
4. Change Landing lamp brightness from **1.00 to 0.42**, without pressing **Apply zone**.
5. Press **Undo**, then **Redo**.

The resulting state was:

| State | Power multiplier | Zone brightness shown | Lighting edit pending |
|---|---:|---:|---|
| Before Undo | 1.10 | 0.42 | Yes |
| After Undo | 1.00 | 1.00 | No |
| After Redo | 1.10 | 1.00 | No |

Undo correctly reverses the power change, but it also discards the unrelated, unapplied brightness proposal. The status reports that the previous recipe was restored, and Save/Test fly become available again. **Redo restores the power change but leaves the lighting proposal lost.**

The accepted saved build was not corrupted. The failure concerns the pending value the player was still editing.

### Why it happens

Workshop history stores the accepted recipe and presentation. Restoring history reconfigures the presentation panels, while `_sync_presentation()` attempts to preserve their pending editor state.

However, Lighting’s `get_editor_state()` stores the selected zone, disclosure state, color text, and sequence state **without storing the complete pending zone or effects drafts**. Reconfiguration clears those drafts, so the restoration cannot reconstruct the proposed brightness. This is visible in [Lighting’s state serialization](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop_lighting.gd#L394-L478), [presentation synchronization](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop.gd#L3035-L3053), and [history restoration](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop.gd#L3140-L3152).

### The same omission affects recovery

A separate probe waited beyond the actual recovery debounce, verified that a completed snapshot existed, recreated the editor, and selected **Restore**. The accepted Custom lighting profile returned, but the pending **0.42** value did not.

That was a completed-snapshot restoration test, not an operating-system crash test. The effects-draft omission is confirmed in source; I did not separately reproduce an effects-edit loss.

This differs from the previous recovery finding: here, **the recovery file exists, but its editor-state payload is incomplete**.

### Recommended repair

Preserve the complete pending Lighting state across unrelated history changes and recovery, including its validation and pending flags. If a history transition would invalidate that pending state, require an explicit Apply or Cancel decision before proceeding.

The essential acceptance test should use the real controls and check four things separately: accepted values, pending values, dirty status, and Save/Test fly availability. Checking only the accepted profile misses this failure.

## 2. “Discard changes” can leave the discarded field behind

This route also reproduced in the running application:

**Save build → change Power → Smoke → enter `#BAD` without applying → Library → Load the saved build → Discard changes**

The saved build loads successfully:

- Its saved identity and revision are restored.
- Power returns to the saved **1.00** value.
- The status confirms that the saved build loaded.

But the outgoing **`#BAD` Smoke field remains**. Workshop still considers the editor dirty, and **Save build** and **Test fly** remain disabled.

The component witness additionally verified that the accepted presentation and disk record still matched the selected saved build. The lingering problem is the transient editor buffer.

### Why it happens

[`_load_variant_snapshot()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop.gd#L1257-L1320) clears pending numeric fields before replacing the accepted recipe and presentation. It does not clear the outgoing presentation buffers.

The subsequent synchronization deliberately preserves pending presentation fields during ordinary editing. That useful preservation behavior is also being applied to a successful build replacement, causing the discarded Smoke text to return. The relevant preservation logic is in [`_sync_presentation()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop.gd#L3035-L3053).

### Recommended repair

Give successful build replacement an explicit synchronization policy:

- Validate the selected target.
- Commit the replacement.
- Clear every outgoing pending presentation buffer.
- Configure the editor from the loaded target.
- Synchronize identity, dirty status, and available actions before displaying success.

A canceled or failed load must preserve the complete outgoing draft.

**UI3-01 and UI3-02 need complementary rules:** preserve pending state during ordinary editing; clear outgoing state when an authorized replacement actually commits. A blanket “clear all buffers on refresh” fix would make the Undo problem worse.

For the player, successful loading should produce one coherent result: the selected build is present, its identity is correct, and its actions reflect that build’s actual validity.

## 3. Rejected navigation selects the wrong page—and can suppress the retry

With an invalid pending Lighting edit, attempting to open **Flight setup** correctly keeps Lighting visible and returns focus to the problematic field.

However, the navigation indicator changes anyway:

- In the desktop layout, **Flight setup appears selected** while Lighting remains visible.
- In the compact layout, the dropdown displays **Flight setup** while the active page is still Lighting.

The desktop case was reproduced with a synthetic Space key at the primary **1920×1080** layout.

I then checked the compact popup path in the running application and found an additional consequence. After resolving the pending edit with the real Cancel button, selecting **Flight setup again did nothing**. Selecting **Smoke**, then **Flight setup**, worked.

### Why it happens

Workshop’s [`_set_page()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop.gd#L2400-L2423) returns early when Lighting has a pending edit. That return happens before the normal synchronization of the tab buttons and page selector.

I verified the preceding control behavior in the pinned Godot beta source:

- [`BaseButton`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/gui/base_button.cpp#L251-L275) changes its toggle/group state before invoking the pressed callback.
- [`OptionButton`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/gui/option_button.cpp#L442-L469) changes its current item and displayed text before emitting `item_selected`.

The dropdown therefore believes Flight setup is already selected. With reselect disabled by default, choosing that same item again can produce no new navigation callback. Godot’s API documents that reselect behavior. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/classes/class_optionbutton.html?utm_source=chatgpt.com)

### Recommended repair

Make `_active_page` authoritative and use one helper to synchronize **both** navigation presentations after accepted or refused navigation.

On refusal:

1. Restore the dropdown to the actual active page.
2. Restore every tab’s selected state.
3. Keep the existing pending-field focus and scroll handling.

When using `set_pressed_no_signal()`, synchronize every button in the group: Godot documents that this method does not automatically unpress the other group members. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/classes/class_basebutton.html?utm_source=chatgpt.com)

Changing `allow_reselect` alone would leave the wrong page indicator visible. The acceptance criterion should be stronger: **after resolving the pending edit, one selection of the intended destination must open it immediately.**

## 4. Invalid input leaves the visible Cancel button disabled

This is a separate failure from the selected-page mismatch.

Starting from a clean Lighting zone, replace `#FFFFFF` directly with `#BAD`, without first making another valid zone edit.

The editor then behaves inconsistently:

- It recognizes a pending edit.
- It blocks Save/Test fly.
- It refuses to leave the page and tells the player to apply or cancel.
- **Apply zone is disabled**, appropriately.
- **Cancel is also disabled**, inappropriately.

The running application and an independent component probe both confirmed this.

### Why it happens

The invalid-text branch in [`_on_zone_hex_changed()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop_lighting.gd#L856-L871) marks raw text as pending, displays the error, and emits validity. It then returns before [`_refresh_zone_pending()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop_lighting.gd#L1031-L1038) updates the zone-specific pending flag and enables Cancel.

The page guard and the action buttons are therefore describing different states.

### Recommended repair

Use one consistent relationship:

> **Pending input enables Cancel. Validity determines whether Apply is enabled.**

Refresh the pending and action state on every text change, including empty, partial, and invalid text. Keep the player’s invalid text visible until it is corrected or canceled.

There are recovery paths today. The checked component confirmed that the header Back button cancels the field, and that two Escape presses recover it when the LineEdit is in editing mode. Correcting the text also makes the zone actions available. Those paths prevent a permanent lock, but they do not make the disabled Cancel button understandable.

The existing [Lighting test](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/tests/test_workshop_lighting.gd#L107-L114) cancels through a method call. A regression test needs to activate the **visible Cancel control**, because that is the boundary that failed.

## 5. Preview reflow can remove keyboard focus

This is a lower-priority compatibility issue, bounded to a very short window.

The checked route was **Home → Workshop → Preview**, at 100% text:

- Focus the inline **Front** camera action.
- Resize from **1000×1080** to **1000×390**.
- The inline camera controls are replaced by a **Camera** menu.
- Focus becomes null; Down and Tab do not recover it.

The reverse transition also fails: focus Camera, increase the height to **400 px**, and the restored inline controls have no focus.

The visibility swap occurs in [`workshop_preview.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop_preview.gd#L887-L907). The parent’s [layout reconciliation](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/workshop.gd#L595-L643) does not cover that later child-control replacement. Godot’s navigation guidance explicitly notes that hiding a control can cause it to lose focus. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html?utm_source=chatgpt.com)

The repair should transfer focus only when the focused control is being replaced: to Camera when collapsing, and to an appropriate inline action when expanding. It should preserve unrelated focus and avoid continuously calling `grab_focus()`.

**I would schedule this after the primary 1080p defects.** This witness occurred at a 390–400 px-high window and does not establish a 1080p visual defect.

## Qualified finding: Remove companions now resets unrelated pending settings

The source contains another incomplete preservation path.

[`_refresh_companions_dialog_status()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/app_root.gd#L2604-L2629) preserves only enabled, count, seed, and save-as-default before reconfiguring the dialog. The dialog’s [`configure()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/ui/companions_dialog.gd#L56-L85) also overwrites volume, label visibility, and label distance.

The controlled UI reproduction produced:

| Unapplied setting | Before Remove now | After Remove now |
|---|---:|---:|
| Engine volume | 35% | 100% |
| Show labels | On | Off |
| Label distance | 600 m | 250 m |

**Evidence boundary:** the normal enabled-companion launch was refused because the current companion profile did not match the normalized solver sources. I did not rebind it. I used a real solo-flight Pause dialog with an explicit active-count display fixture to expose Remove now. No actual companion aircraft was present or removed.

The resulting refresh behavior is confirmed, but the complete active-companion player journey still needs verification with an admitted profile.

The clean repair is to **separate status refresh from draft initialization**. Removing traffic should update traffic counts, status, and action availability while preserving the player’s unapplied settings.

## What this means for the next implementation pass

The common problem is the relationship between three kinds of state:

| State | Examples | Required behavior |
|---|---|---|
| **Accepted build data** | Recipe, presentation profile, saved revision | Changes through an explicit accepted operation |
| **Pending edits** | Invalid text, unapplied zone values, effects proposals | Remain available until applied, canceled, or deliberately discarded |
| **Navigation state** | Active page, selected tab, focus, scroll | Always agrees with the screen and controls the player can currently use |

The first implementation pass should establish those rules around the existing Workshop code. It does not require a new UI framework.

I recommend this order:

1. **Repair pending Lighting preservation and recovery completeness.**
2. **Clear outgoing buffers only when a validated build replacement commits.**
3. **Synchronize selected-page indicators after refused navigation.**
4. **Keep explicit Cancel usable for every pending invalid edit.**
5. **Repair the short-window preview focus transfer.**
6. **Verify the Companions refresh fix in an admitted active session.**

Five focused reproduction probes completed with zero engine errors or warnings while asserting the documented behavior. The existing recovery UI check passed 75 checks, and the corrected existing Lighting run reported zero failures. Their success does not cover the newly identified control and state boundaries.

I also excluded a potential statistics-dialog finding after checking the exact Godot implementation: the synthetic reentry test bypassed the engine’s [exclusive-child window-close guard](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/main/window.cpp#L964-L970). It remains documented as diagnostic evidence rather than a demonstrated player-facing defect.

**No production files were changed.** This pass establishes code and interaction-state failures through headless testing; native visual polish, physical-controller behavior, screen-reader output, and GPU performance still require their corresponding acceptance checks.