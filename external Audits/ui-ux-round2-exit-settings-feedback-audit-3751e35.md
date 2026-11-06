## Review completed

**I identified eight additional UI/UX findings and one focused loading-performance candidate.** The most serious issue is in the garage exit flow: a recording export can fail, the interface can say the recording is retained in memory, and the application can still reach its quit request.

The strongest improvements are about making the interface’s promises reliable: whether changes are saved, what a timeout will undo, which field is invalid, and whether canceling an exit preserves recovery. These behaviors need to be dependable for the game to feel polished.

I reviewed **`bultodepapas/OpenRCsimulator` at commit `3751e35e1cccf574c4446d21273a4d5ecaf80ddf`**, using its pinned **Godot 4.8 beta 2** build.

The complete **19-page report** includes source links, reproduction details, proposed fixes, acceptance criteria, and the Godot research:

[OpenRC_UI_UX_Incremental_Audit_2026-11-06.pdf](https://chatgpt.com/library?file_id=libfile_ecc3ed98349081919be12251b22d5db7&account_id=personal)

The evidence archive contains probes, logs, source hashes, reconstruction instructions, and the prior-audit comparison:

[OpenRC_UI_UX_Evidence_2026-11-06(1).zip](https://chatgpt.com/library?file_id=libfile_14a46b6f606081919632d7722957cd31&account_id=personal)

### How I handled previous audits

I started with an earlier copy of `external Audits/CONSOLIDATED-AUDITS.md`, then reconciled the frozen revision’s expanded **A1–A9** ledger before finalizing. I also checked the **62-item UI-30 audit**, subsequent menu investigations, active design plans, and the previous dedicated UI review. The report records the two ledger versions explicitly.

Consequently, I have not counted previously reported profile overwrites, controller-recovery focus loss, Help scrolling, remapped Back-key editing problems, Natural Random Moon preference leakage, startup scaling, hover-only help, or the existing Home-to-Fly loading work as new discoveries. Their earlier status remains attributed to the original records. [Consolidated ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/external%20Audits/CONSOLIDATED-AUDITS.md) · [UI-30 audit](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/docs/research/menu-investigations/UI-30/README.md) · [Menu redesign status](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/docs/plans/menu-redesign.md)

## Prioritized findings

The IDs below belong to this report; I have not added them to your project tracker.

| Priority | ID | Finding | Evidence |
|---|---|---|---|
| **P1** | UI2-01 | Garage recording export failure does not stop the application’s quit path | Production handlers tested together; final quit intercepted |
| **P2** | UI2-02 | Display countdown overwrites the failed-save message on the next frame | Component and current headless application |
| **P2** | UI2-03 | Display-test expiry discards unrelated sound and accessibility drafts | Component and actual settings controls |
| **P2** | UI2-04 | Conditions reports an error for the visible tab instead of the invalid field | Component and actual dialog controls |
| **P2** | UI2-05 | Workshop removes recovery before the quit transaction commits | Early deletion reproduced; later canceled-exit consequence established by source inspection |
| **P3** | UI2-06 | Keyboard onboarding expires while hidden during controller use | Production hint component |
| **P3** | UI2-07 | Controls on initially hidden overlay tabs miss focus-sound subscriptions | Production components; cue requests measured |
| **P3** | UI2-08 | Pilot radar bypasses existing cardinal-direction translations | Source inspection |
| **Investigate** | OBS-01 | Natural Random clears its busy state before a frame can display it | Scheduling established from source; duration unmeasured |

P1 protects recoverable player work. P2 addresses confusing or unreliable workflows. P3 addresses consistency, discoverability, and feedback.

---

## 1. Garage recording failure can still be followed by application quit

**This is the first issue I would fix.**

When a window-close request reaches the garage, `GroundScene` attempts to finish the recording. If export fails, it retains the pending recording and reopens the garage with a recovery message.

However, `AppRoot` independently handles the same close request and starts its own quit transaction. Its recorder enumeration includes `flight` and `_workshop_previous_flight`, but excludes `ground_vehicle`. The ground handler’s decision to stay open therefore does not stop the root transaction. [Ground recording failure](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/vehicles/ground/ground_scene.gd#L839-L854) · [Ground close handler](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/vehicles/ground/ground_scene.gd#L926-L928) · [Root recorder enumeration](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L3159-L3185)

### What the controlled reproduction showed

With an active synthetic recording and an injected export failure:

- Recording stopped once.
- Export was attempted once and failed.
- The recording remained pending.
- The garage reopened.
- **The root still reached its final quit request.**

A ground-only control correctly blocked quitting. Testing the production handlers together exposed the failure. I intercepted the final quit rather than terminating the process, so this demonstrates an unsafe exit path—not an observed loss of a real player’s recording.

### Recommended correction

Make **one root exit coordinator** responsible for deciding when the process may terminate. Ground recording should participate in the same save, retry, stay, and explicit discard decisions as other recordings.

A useful recovery message would be:

> Recording could not be saved. It is still available in this session.

Actions should clearly express the consequence: **Retry save**, **Stay in garage**, and **Discard and quit**.

Test active recordings, already-pending exports, repeated close requests, successful retries, Stay, and explicit discard. The acceptance rule is simple: **a failed participant prevents the final quit until the player resolves it**.

This is distinct from UI-30’s earlier garage Return-to-Home guard. The new trigger is the competing ownership of a window-close request.

## 2. Failed-save feedback disappears during a display test

The Settings screen has two independent facts to communicate:

1. Whether the draft was saved.
2. How much time remains in a display test.

Currently, both compete for the same status field.

`keep_changes()` sets a save error when the preference store refuses the write. On the next processing cycle, `_process()` replaces that error with the display-test countdown. The draft remains unsaved. [Failed Keep path](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/settings_screen.gd#L946-L957) · [Countdown update](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/settings_screen.gd#L122-L140)

In the component and current-app checks, an injected non-writable store produced:

> Could not save settings (error 10).

The next processing cycle replaced it with:

> Keep the display test within 15 seconds.

The player can reasonably interpret this as an unresponsive Keep button. If the timer expires, the subsequent rollback makes the behavior even harder to understand.

### Recommended correction

Use **separate persistent save feedback and display-test activity**.

For example:

> Settings could not be saved. Your changes are not saved yet.

Below that, retain the independent countdown:

> Display test ends in 12 seconds.

A successful retry should clear the error. A passive countdown update should not. Preserve the safety deadline, and make any expiry message explain both the restored display and the remaining unsaved work.

Regression coverage should check the message immediately after failure, after one frame, after several countdown ticks, on successful retry, and at expiry. The existing test checks the retained deadline and saved values; it does not establish that the error survives another frame.

This concerns the **display-preference store**. The previous review’s hidden language-save failure over Pause remains a separate finding with a different cause.

## 3. Display timeout discards unrelated pending settings

This is a particularly frustrating interaction because the player loses work outside the category being tested.

I reproduced the following through the actual Settings controls:

1. Set **Game volume** to `0.4`.
2. Enable **Opaque panels**.
3. Start a **Borderless fullscreen** test.
4. Let the 15-second deadline expire.

The draft’s window mode returned to `windowed`, but `master_volume` also returned to `1.0` and `opaque_panels` returned to `false`. The entire draft then equaled the saved configuration.

The cause is direct: expiry calls the general `_revert()` method, which replaces the whole draft with `_saved`. The timed display fields and the full settings transaction share a rollback operation with different scopes. [Timed-field list](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/settings_screen.gd#L741-L752) · [Whole-draft rollback](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/settings_screen.gd#L960-L968)

### Recommended correction

Keep three states distinct:

- **Saved preferences**
- **Current draft**
- **Known-good display-test baseline**

When a display test expires, restore only the explicitly defined test fields. Preserve unrelated pending edits, reapply the combined draft, and retain the dirty indicator.

For a draft \(D\), rollback baseline \(B\), and trial-key set \(T\), the intended rule is:

\[
D'_k =
\begin{cases}
B_k, & k \in T \\
D_k, & k \notin T
\end{cases}
\]

Then determine whether changes remain pending by comparing \(D'\) with the saved configuration.

The resulting message should say:

> Display settings restored. Your other changes are still unsaved.

Keep **Revert all** as an explicit action. Test edits made both before and during the countdown, repeated display changes, failed Keep attempts, expiry, and deliberate full-form reversion.

This is an overbroad rollback within the existing settings transaction. Previously saved preferences were not corrupted, and the headless test does not establish native operating-system window behavior.

## 4. Conditions can direct the player to the wrong invalid setting

The validation correctly prevents an invalid save, but its explanation can identify the wrong problem.

I entered invalid text in the wind-speed field, switched to **Time of day**, and selected Apply. The dialog stayed on Time of day and reported:

> Check the time, date, UTC offset and location. Apply will not save invalid lighting.

The invalid wind text remained, and accepted wind stayed at `1.5 m/s`.

`_on_apply()` validates fields across tabs, while `_show_error()` chooses its message from the **currently selected tab**. The presentation context is being used as the validation context. [Cross-tab validation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/weather_dialog.gd#L735-L770) · [Error selection](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/weather_dialog.gd#L880-L885)

### Recommended correction

Have validation return a structured result containing the owning tab, field identifier, error code, and localized explanation.

On failure:

- Reveal the owning tab.
- Scroll the invalid field into view.
- Focus it after layout settles.
- Show an explanation beside the field.
- Preserve valid edits elsewhere.

For the reproduced case, the message can be specific:

> Wind speed: enter a number from 0 to 15 m/s.

Changing time, date, or location cannot repair Apply while the invalid wind value remains. The interface should lead the player directly to the field that can resolve the problem.

A focused regression matrix should cover invalid input originating on each tab while Apply is pressed from each of the five tabs. Include empty text, pasted text, and out-of-range numbers. These are proposed checks; the reproduced case was specifically invalid wind followed by Apply from Time of day.

UI-30’s error-color work does not cover this incorrect diagnosis.

## 5. Workshop deletes recovery before the exit has committed

Workshop recovery currently ends too early in a multi-stage exit.

The component check created a dirty draft and a completed recovery snapshot, opened the Quit guard, and directly invoked `_navigation_finish()`, the handler wired to Discard changes. It did **not** activate the Discard button.

The handler deleted the snapshot and stopped its recovery timer before invoking the next navigation stage. One second later, the draft was still dirty in memory, but no recovery snapshot existed. [Navigation handler](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/workshop.gd#L2559-L2563) · [Recovery deletion](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/workshop.gd#L3420-L3435)

### Where the inference begins

The root exit flow can subsequently encounter a trace-save failure and offer **Stay**. That path cancels quitting, but its source does not rearm Workshop recovery. The full trace-failure → Stay sequence was not executed in this review. [Root failure and cancellation paths](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L3220-L3347)

The risk is therefore precise: **a still-usable dirty draft can lose its recovery protection after an aborted exit**. The draft is not immediately erased by Stay; the vulnerability is a later unexpected shutdown before another edit schedules recovery.

### Recommended correction

Separate permission to discard from the final commitment of the transition.

Delete recovery only when the global transition commits. If another participant blocks or cancels the exit, preserve or refresh recovery for the live draft.

Your aircraft-editor plan already requires delayed discard. This finding is a concrete counterexample to that requirement, rather than a new feature proposal. [Existing requirement](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/docs/plans/aircraft-editor.md#L416)

The decisive integration test is: dirty draft → recovery snapshot → Quit → Discard → trace save fails → Stay. Both the draft and its recovery protection should remain usable.

## 6. Keyboard onboarding expires while the hint is hidden

The first-flight hint hides when a controller is connected or controller-lost state is active. Its elapsed-flight counter nevertheless advances whenever the session is unpaused.

In the component check, hidden controller-owned time completed the hint and emitted `done`. Switching to keyboard afterward left the hint invisible. The root completion handler marks the hint as seen and persists that preference. [Hint visibility and timing](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/first_flight_hint.gd#L94-L104) · [Completion persistence](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L1884-L1886)

For someone who starts with a controller and later tries the keyboard, the game can record a tutorial as completed without ever displaying it.

### Recommended correction

Count **visible, relevant exposure**:

- The hint is visible.
- Its intended input mode is active.
- The session is advancing.

Preserve the remaining time when the controller takes over or the session pauses. If separate controller guidance is introduced later, track completion per input family.

Test controller-first → keyboard, switching back and forth, pause/resume, controller loss/recovery, explicit dismissal, and preference reload after valid completion.

This is a specific timing defect in existing onboarding. The broader first-run tutorial work already belongs to the earlier menu plan. The test used a synthetic session and shortened duration; physical-controller behavior and the real preference write were not exercised.

## 7. Initially hidden overlay tabs miss focus sounds

The Overlays dialog temporarily sets controls on inactive pages to `FOCUS_NONE`, then restores their focus mode when the page becomes active.

`MenuAudio` observes the surface once and connects `focus_entered` only for controls that are focusable at that moment. Controls can already be marked observed through other signal connections, preventing a later observation from adding the omitted focus subscription. [Hidden-page focus handling](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/overlays_dialog.gd#L332-L400) · [Audio observation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/menu_audio.gd#L282-L299)

The reproduction showed that the initially active Modern-page control requested a focus cue. After switching to Classic, its control became focusable and acquired focus, but requested no additional cue.

### Recommended correction

Subscribe to future focus for eligible interactive controls independently of their initial visibility. At signal time, retain the existing checks for active surface, visibility, and deliberate navigation.

This keeps sound policy in the shared observer and avoids individual tabs implementing their own audio behavior.

Acceptance should require one cue for a deliberate eligible keyboard/controller focus movement, none for silent autofocus, and no duplicate callbacks after repeated tab switches.

This was a measurement of **cue requests** with Dummy audio and synthetic navigation. Audible output and physical devices remain separate checks.

## 8. Pilot radar uses untranslated cardinal labels

The Pilot radar draws literal `N`, `E`, `S`, and `W`, while the Weather compass translates the equivalent labels.

The application already contains translations such as Spanish west `O`, German east `O`, and Japanese cardinal glyphs. As a result, the two instruments can use different language conventions even when created fresh in the same locale. [Radar literals](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/render/overlays/navigation_instrument.gd#L165-L169) · [Translated Weather compass](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/render/overlays/player_instrument.gd#L703-L706)

### Recommended correction

Apply the established cardinal-translation policy to both instruments. Reuse the existing strings; introduce a shared provider if further instruments duplicate the mapping.

Keep the heading and bearing calculations unchanged. Invalidate the cached label face when locale or font state changes.

Compare both instruments in English, Spanish, German, and Japanese, including initial language, live changes, glyph fallback, centering, and increased text size.

This is a source-confirmed consistency issue. I did not observe a rendered clipping problem or a player navigational error. It is also distinct from the earlier finding about stale localization after changing language.

---

## Loading and responsiveness: Natural Random needs a targeted measurement

There is one additional preparation interval worth investigating.

Opening Natural Random or selecting **Another flight** sets the screen busy, generates a scenario, prepares a candidate `FlightSession`, calls synchronous `setup()` and `reset()`, and clears busy before returning successfully. There is no frame yield between those operations.

Consequently, the successful path cannot display its temporary **Preparing flight** state between those writes. Any substantial synchronous work also delays further input handling. [Briefing preparation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L1783-L1871) · [Busy-state presentation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/natural_random_screen.gd#L228-L233)

**The scheduling problem is established; its perceptible duration is not.** I have not assigned a measured stall time or claimed an FPS improvement.

Measure the time from accepted input to visible acknowledgement, generation completion, session preparation, and ready state. Capture the longest frame across several aircraft and seeds, with cold and warm runs.

If preparation is material, render acknowledgement before it and break eligible work into bounded units under the existing job owner. Yielding once permits a frame; it does not make the following computation asynchronous.

For repeated rerolls, use request generations so an older result cannot replace the latest requested flight. Any cached preparation needs an exact validity key covering aircraft/configuration, environment, seed, and relevant model/schema revisions.

This concerns **briefing entry and reroll**. Home-to-Fly already has loading ownership, staging, cancellation, and first-frame work in the existing UI-34c track.

## Godot research and its practical implications

I used official Godot guidance and checked relevant contracts against the exact beta source at `cafc17a192acf67903910a68aeb3c076c0907a4b`. The official release announcement identifies that build. Broader 4.7 tutorials were used as guidance; rolling `latest` documentation was not treated as a frozen beta-2 contract. [Godot Engine](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/?utm_source=chatgpt.com)

The following engine details materially affect these fixes:

| Godot behavior | Application to OpenRC |
|---|---|
| Hidden controls can lose focus; complex interfaces benefit from explicit neighbors and deferred initial focus | Reveal and focus the actual invalid Conditions field after layout. Preserve opener/fallback behavior through the existing screen stack. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html?utm_source=chatgpt.com) |
| `_input` precedes GUI processing in the documented input flow | Keep gameplay input isolation in the established route/hold owner. A GUI control consuming an event cannot undo gameplay already performed earlier. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html?utm_source=chatgpt.com) |
| Containers control child layout | Add error rows and persistent status using minimum sizes, wrapping, and size flags. Manual child offsets are fragile during relayout. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html?utm_source=chatgpt.com) |
| Theme resources propagate through the UI hierarchy | Extend `UiTheme` for new feedback states and spacing. Avoid creating separate visual conventions in Settings, Conditions, and recovery dialogs. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_skinning.html?utm_source=chatgpt.com) |
| Calling `load_threaded_get()` before loading finishes blocks the caller | Poll status across frames and collect only when ready. Resource loading, scene construction, and simulation preparation need separate timing. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html?utm_source=chatgpt.com) |
| Node-bound tweens have defined lifetime and pause behavior | Bind transitions to the screen lifecycle, stop superseded motion, and deliberately choose pause behavior for pause-menu animation. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/classes/class_tween.html?utm_source=chatgpt.com) |
| Accessible names/descriptions and screen-reader traversal require deliberate configuration | Preserve semantics for new error controls and validate announcements on a native target. Metadata, visible focus, and actual screen-reader output are separate checks. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html?utm_source=chatgpt.com) |

One loading detail deserves particular care: the exact beta retains references for repeated threaded requests, and result collection releases those references. Logical cancellation should suppress obsolete publication while safely collecting submitted work at terminal completion. Simply abandoning results indefinitely is not a complete lifecycle policy. [Exact request accounting](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/resource_loader.cpp#L700-L721) · [Exact result collection](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/resource_loader.cpp#L932-L995)

## What AAA-quality acceptance should require

The project already has shared type roles, colors, control states, scaling, and screen ownership. Those are useful foundations for a coherent interface. The new fixes should extend them. [Shared theme](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/ui_theme.gd) · [UI scaling](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/ui_scale.gd) · [Screen stack](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/screen_stack.gd)

I would use the following acceptance criteria for the fixes and existing visual work. These are not additional observed defects.

**Presentation at the intended size.** Qualify 1920×1080 first, then larger displays and ultrawide. Exercise supported text scaling, including 150% and 200%, and retain 720p/short-window fallback coverage. Error text must wrap without hiding the action row. Godot’s design resolution, actual window size, stretch mode, and user scale are distinct concerns and should be tested together. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html?utm_source=chatgpt.com)

**Readable states over real scenery.** Measure important normal-size text against its least favorable visible background, including bright scenery behind translucent panels. A useful standard-text target is **4.5:1**, consistent with Microsoft’s game-accessibility guidance. The existence of opaque panels is valuable, but the rendered combinations still need measurement. [Microsoft Learn](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/102?utm_source=chatgpt.com)

**Complete interaction states.** Capture normal, hover, focus, selected, pressed, and disabled appearances. Focus outlines must remain visible after scaling and clipping. A selected value, displayed label, accessible name, and explanatory text should agree after every change.

**Predictable recovery.** Every failed action should answer three questions: what happened, whether the player’s work still exists, and what action resolves the problem. Save errors should persist long enough to act on. Display countdowns should remain visible without overwhelming assistive announcements.

**Deliberate navigation.** Exercise mouse, keyboard, and a supported physical controller through nested dialogs, text editing, repeated Back, cancellation, and reopening. Returning to a screen should restore a visible, usable focus target and an understandable location.

**Responsive motion.** Respect reduced motion, handle interrupted transitions, and avoid delaying input acknowledgement for decorative animation. Loading percentages should correspond to measurable work; otherwise use truthful stage names and indeterminate feedback.

## Recommended implementation order

I would organize the work into five focused changes:

1. **Unify exit readiness and commitment.** Add the garage recorder to the root transaction and defer Workshop recovery deletion until commitment.
2. **Repair Settings state and feedback.** Separate save outcome from the display countdown, and scope automatic rollback to the declared trial fields.
3. **Make validation identify its field.** Use one structured result to drive Conditions error text, tab selection, scrolling, and focus.
4. **Finish feedback consistency.** Correct hint exposure timing, dynamic focus-audio subscriptions, and radar localization.
5. **Measure Natural Random preparation.** Optimize only after identifying material delay, preserving identical validated scenarios and correct cancellation.

This order addresses the greatest player cost first: potentially losing recoverable work, then losing pending configuration effort, then being sent to the wrong place, followed by interaction polish.

## What was verified

Seven final component witnesses completed successfully with **zero recorded engine errors or warnings**. Their success means the reproductions completed their assertions; it does not mean the defects are fixed.

The current headless application separately reproduced the three Settings/Conditions issues and completed:

**Home → Fly → Pause → Restart flight → Return to Home**

Focus returned to **Fly**. The application was then shut down cleanly. The evidence also records the reference-physics fallback used in that environment.

Native visual rendering, physical controllers, audible output, screen readers, and target-hardware loading cadence remain unverified. I therefore have not invented new typography, alignment, contrast, or clipping failures from source alone, nor claimed a native AAA presentation pass.

**My first implementation priority is UI2-01, followed by the paired Settings fixes UI2-02 and UI2-03.** Those changes would immediately make the interface more trustworthy at precisely the moments when players are most likely to become confused or lose work.