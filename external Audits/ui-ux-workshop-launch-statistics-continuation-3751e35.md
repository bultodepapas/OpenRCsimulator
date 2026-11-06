## Continued review: seven additional findings

I continued against **`main` at commit `3751e35`**, rechecked `external Audits/CONSOLIDATED-AUDITS.md`, and concentrated on areas that add evidence beyond the first report: **Workshop editing, saved builds, aircraft launch failures, combined exit recovery, and flight statistics**. The new findings are numbered **F10–F16** so they remain distinct from F01–F09. [Reviewed baseline](https://github.com/bultodepapas/OpenRCsimulator/tree/3751e35e1cccf574c4446d21273a4d5ecaf80ddf) · [Consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/external%20Audits/CONSOLIDATED-AUDITS.md)

**The highest-priority new problem is that a Workshop preset can silently discard measured component data.** Several other findings share a broader usability problem: the interface presents a state—“Saved,” an empty library, an available Fly action, or unchanged history—that does not accurately describe the operation underneath it.

### Deliverables

- **[OpenRC_UI_UX_Audit_Continuation_2026-11-06.pdf](https://chatgpt.com/library?file_id=libfile_d721f3461b488191a7c40509477bde06&account_id=personal)** — 17 pages covering the seven findings, suggested player-facing messages, implementation guidance, acceptance checks, 36 project references, and 14 official Godot documentation references.
- **[OpenRC_UI_UX_Continuation_Evidence_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_5ddcca51a2ec81919aedd72b6e1db580&account_id=personal)** — focused reproduction scripts, six checked component runs, the full-app command transcript, diagnostic logs, source identities, and reconstruction instructions.

The production checkout remains unchanged; these are review findings and concrete repair recommendations.

## Priority register

| ID | Priority | Finding | Player impact |
|---|---|---|---|
| **F10** | **P1** | Workshop presets discard measurements and clear invalid pending input | The build can change beyond what the player intended |
| **F11** | **P2** | Valid imported names are truncated, marked Saved, and later persisted shortened | An unrelated edit can unintentionally rename a build |
| **F12** | **P2** | Unreadable saved builds can appear to be an empty library | Players receive no explanation for apparently missing work |
| **F13** | **P2** | A rejected helicopter launch returns to Aircraft with its explanation hidden | Fly appears available again, but the player cannot see how to proceed |
| **F14** | **P2** | Trace and statistics recovery lose ownership of the complete exit operation | Dialogs conflict, and an explicit Discard decision is forgotten |
| **F15** | **P2** | A committed statistics deletion leaves stale rows, counts, and actions | The live screen contradicts the operation’s durable result |
| **F16** | **P2** | Flight history omits scenario and failure-practice context | Players cannot reliably interpret or compare recorded flights |

Here, **P1** means an early repair because important player-authored inputs can change silently. **P2** means a demonstrated functional or feedback problem with a narrower trigger or a recovery path.

---

## F10 — Workshop presets can silently remove measured component data

### What I verified

Workshop’s **Starting preset** operation constructs a recipe from `Compiler.defaults()` and copies the preset’s factors into it. It does not retain `mass_edits`. The responsible operation is in [Workshop’s preset handler](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/workshop.gd#L1626), with measured-recipe handling in the [Workshop compiler](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/workshop/compiler.gd#L73).

In the focused component reproduction:

1. I supplied a clearly synthetic measured component value.
2. Selecting **More power** removed the measured entries.
3. A positive control combined those same measurements with the preset’s power and control factors and compiled successfully.
4. Undo restored the measurements.

That compatibility check matters: removing the measurements was not required to apply this particular preset.

The same operation also clears unresolved numeric input. Invalid weight text correctly remained visible and blocked **Test fly**, including after the field lost focus. Selecting **More power** then replaced that text with `1.0`, cleared its pending/error state, and re-enabled Test fly. The accepted recipe history does not preserve that rejected raw text.

### Why this matters

A player choosing a power adjustment should be able to predict its scope. Silently removing measurements or resolving invalid text on their behalf breaks the relationship between the build they are reviewing and the build they will test.

This is especially important in a simulator, where measured inputs are meaningful evidence. The issue is independently actionable even though the broader “preset overwrites unrelated state” pattern resembles the earlier Wind/Atmosphere finding. The [aircraft-editor plan already requires scoped preset changes](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/docs/plans/aircraft-editor.md#L404); this reproduction identifies a concrete implementation gap.

### Recommended repair

Apply each preset as a **declared patch to the current recipe**:

- Preserve measurements when the resulting combination is compatible.
- Explain dependencies before a preset removes or invalidates measurements.
- Require the player to correct or explicitly cancel unresolved input.
- Record the accepted preset change as one Undo operation.

For a preset that changes fields in a set \(K\), the useful invariant is:

\[
x'_i=x_i\qquad\text{for every field }i\notin K
\]

Any necessary exception should be explained before acceptance.

Godot’s `Dictionary.duplicate(true)` can help create a detached working copy of nested arrays and dictionaries, but resources remain shared; the implementation still needs deliberate ownership of any resource objects. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_dictionary.html?utm_source=chatgpt.com)

**Suggested feedback:** “More power applied. Measured component masses retained.”

**Acceptance:** compatible presets preserve measurements; incompatible combinations prompt or safely refuse; invalid text remains visible and blocking until explicitly resolved; Save and Test fly consume exactly the reviewed values.

---

## F11 — A valid imported name can be shortened and still appear Saved

### What I verified

The stored-build and portable-bundle formats accept names up to **96 characters**, while Workshop’s name field uses a **64-character** limit. These boundaries are defined separately in the [editor](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/workshop.gd#L737), [store](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/workshop/store.gd#L1377), and [portable bundle validation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/workshop/bundle.gd#L351).

The reproduction exported and imported a valid **80-character name** into a separate local record. Opening it in Workshop:

- Reduced the displayed name to 64 characters.
- Established that shortened value as the clean baseline.
- Reported the build as **Saved**, without an unsaved change.
- Persisted the shortened name in revision 2 when only the power setting was changed and saved.

The original record and earlier immutable revision remained intact. The defect is an unintended rename during a later save.

Godot documents `LineEdit.max_length` as a truncation limit. It also specifies that assigning `LineEdit.text` does not emit `text_changed`. Loading data into a constrained widget therefore needs explicit validation; the widget’s resulting value cannot automatically be treated as the original saved identity. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_lineedit.html?utm_source=chatgpt.com)

### Recommended repair

Use **one name-length contract** throughout import, storage, editing, navigation guards, and draft recovery.

Supporting the existing 96-character format end to end is the least surprising direction. A long name can scroll inside its field or be visually abbreviated in a card while retaining the complete underlying string.

There are separate 64-character boundaries in the guard dialog and recovery editor state, so changing only the main name field would leave the workflow inconsistent.

**Acceptance:** import and open names of 64, 65, 80, and 96 characters; change an unrelated parameter; save, reload, recover, and export. The accepted name must remain identical throughout. Keep explicit rejection above the supported format limit.

---

## F12 — An unreadable build can masquerade as an empty library

### What I verified

`Store.list_variants()` omits builds whose load fails. Workshop interprets an empty returned array as evidence that the player has no saved builds. See [store enumeration](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/workshop/store.gd#L111) and [Workshop’s library refresh](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/workshop.gd#L1087).

In an isolated fixture, I created one saved, nonfavorite build and deliberately malformed its manifest, with no usable backup:

- Direct loading returned an error.
- The build still existed on disk.
- Enumeration returned an empty array.
- Workshop enabled the message: **“No saved builds yet. Save the current build to add it here.”**

The component test inspected the real empty-state label after the refresh routine; it did not visually render the library dialog.

### Why this matters

The message tells the player that their work never existed. It gives them no reason to retry, inspect a damaged entry, or seek a recoverable version.

The current return shape loses information that the interface needs. An empty array can mean “nothing saved” or “nothing could be read,” and those require different screens.

### Recommended repair

Return both **usable build summaries and read diagnostics**, then represent distinct states:

| State | Appropriate presentation |
|---|---|
| Successful scan, no builds | “No saved builds yet” |
| Filter excludes all builds | “No builds match this filter” |
| Some entries cannot be read | Healthy builds plus named unavailable entries |
| Entire location cannot be read | A load failure with Retry and Details |

Godot exposes directory-open errors through `DirAccess`; preserving that information through the store/UI boundary is essential to choosing the correct state. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_diraccess.html?utm_source=chatgpt.com)

**Suggested feedback:** “1 saved build could not be opened. Your files were kept.”

**Acceptance:** genuinely empty library, one damaged record, mixed healthy/damaged records, valid backup recovery, invalid backups, root access failure, and Favorites filtering. Healthy builds should remain usable, and unreadable originals should remain untouched.

---

## F13 — A helicopter launch failure can return to Aircraft with no visible explanation

### What I verified in the full application

The ordinary player path is:

**Conditions → Atmosphere → Standard atmosphere by altitude → Apply → Aircraft → X-Cell .60 Trainer → Fly.**

The helicopter correctly refuses this unsupported atmosphere model. The UI then returns to the Aircraft page and re-enables Fly, but places the rejection message inside **`FlightPage/HomeNotice`**, whose parent page is hidden.

The application state confirmed:

- No flight was created.
- Aircraft remained the visible page.
- Fly was enabled again.
- The notice contained the failure explanation.
- `note_label.is_visible_in_tree()` was **false**.

Selecting the Flight page revealed the same message. The cause is the combination of [Home’s page-specific notice](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/home.gd#L413), [launch rejection handling](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/home.gd#L1467), and the [authoritative helicopter restriction](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/sim/helicopter_flight_session.gd#L345).

I reproduced the rejection through both nonstaged and staged launch paths, including a staged check at a verified **1920 × 1080 logical viewport**. Switching to **Reference air** provided the positive control: staged loading reached ready with a flyable helicopter and no startup error.

### Recommended repair

Move launch status into a **persistent region beside the shared Fly action**, outside individual Home pages.

Also preflight the accepted aircraft/field/conditions combination where feasible. Runtime validation should remain authoritative, but a known incompatibility can be explained before expensive preparation begins.

**Suggested feedback:**

> This helicopter cannot use Standard atmosphere by altitude. Choose Reference air or Custom field conditions.

Provide **Review Conditions** as the immediate recovery action. Preserve the player’s airplane weather configuration rather than silently resetting it.

### What makes this feel polished

A failed action should return the player to an understandable state: their choices remain intact, the reason is visible where they acted, and one nearby control resolves the problem.

**Acceptance:** launch from Flight and Aircraft; verify supported and unsupported conditions; distinguish cancellation from failure; check meaningful focus and translated copy. Tests must assert **visibility in the tree**, not merely that an error label contains text.

---

## F14 — Trace and statistics recovery do not own the complete exit operation

### What I verified in the full application

I used the actual recorder and statistics store with filesystem conflicts confined to a disposable profile. Both writes failed through their production paths.

The resulting sequence was:

1. **Return to Home** opened **Trace not saved**.
2. **Discard trace and continue** advanced to the statistics-save decision.
3. Godot logged an exclusive-window conflict during the transition.
4. **Cancel** on the statistics decision retained the flight.
5. Choosing **Return to Home** again reoffered the trace that had already been explicitly discarded.

The statistics dialog remained reachable through the headless bridge. This evidence establishes the modal conflict and forgotten decision; it does not establish a universal native-window lockout.

The source explains both results. [`_finish_exit_request()`](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L3315) forgets the completed trace decision and clears the exit owner before calling an operation whose statistics write can still fail. The [trace action handler](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L3288) also queues the old dialog for deletion and immediately advances.

### A related ownership problem

A separate comparison invoked the production close handler synthetically:

- One close attempt followed by Cancel resumed the previously running flight.
- Two close requests while the statistics decision was pending replaced the dialog, produced the exclusive-window conflict, and left the session paused with no active hold or screen after Cancel.
- Escape recovered the Pause screen.

Actual desktop OS close delivery remains untested; the evidence is a controlled invocation of the real handler.

### Recommended repair

Keep **one exit coordinator alive until the destination is actually committed or the departure is cancelled**.

That coordinator should retain:

- The intended destination.
- The current recording’s resolved Save/Discard decision.
- The pending statistics decision.
- The relevant pause state and holds.
- Ownership of the current modal.

Repeated requests should join the pending operation instead of creating another owner. An explicit Discard must remain resolved for that recording; a newly started recording must receive a new decision.

Godot’s `queue_free()` is deferred, and exclusive child windows block their parent’s input. The current dialog must relinquish its exclusive ownership before its successor is presented. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_node.html?utm_source=chatgpt.com)

**Suggested feedback:** “Your flight is still open. Statistics could not be saved.”

Use explicit actions such as **Retry**, **Return to flight**, and **Leave without saving**.

**Acceptance:** trace Retry or Discard followed by statistics failure; statistics Retry, Cancel, and Leave; repeated close requests; an already-paused flight; and a new recording after cancellation. Require one decision owner, no modal conflict, and an intentional resumable or visibly paused state.

This adds coverage for the combined transaction. It does not repeat the already repaired Restart trace guard or earlier Stay/focus policy work.

---

## F15 — A committed history deletion can leave the old rows and counts visible

### What I verified

Statistics deletion has a durable commitment point. Once the deletion record is committed, reopening the store must complete that deletion.

Using the existing interruption hook, I checked a pre-commit control and two post-commit failures against the actual store, service, screen, and reset dialog.

After each tested post-commit failure:

- The screen still showed the deleted flight and **Completed = 1** after Cancel.
- An already cached aircraft query still returned one flight.
- A newly requested all-aircraft query also returned one flight.
- The delete action remained enabled.
- The screen said management was available even though `service.can_manage()` returned false.
- Reopening the actual store correctly recovered the committed deletion and returned zero flights.

The pre-commit control correctly retained the record after reopening.

The responsible boundary is between [store deletion](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/statistics/store.gd#L274), [service state publication](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/statistics/service.gd#L570), and [dialog failure handling](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/statistics_reset_dialog.gd#L133).

These were headless component observations with programmatic confirmation/cancellation and injected transaction-stage failures.

### Recommended repair

Replace the undifferentiated failure result with outcomes that reflect the operation’s state:

- **Refused before commitment:** history is unchanged.
- **Committed, cleanup pending:** deletion is recorded, but recovery work remains.
- **Completed:** publish the verified remaining history.

After commitment, publish a verified survivor snapshot and invalidate affected queries, or clearly mark results unavailable until forward recovery is safe. Update action availability at the same time.

**Suggested feedback after commitment:** “Deletion recorded. Cleanup is incomplete; history is temporarily unavailable.”

**Suggested feedback before commitment:** “Deletion could not be completed. Your history is unchanged.”

Those messages must be selected from established store state.

**Acceptance:** the open screen, summary counters, cached and uncached queries, and relevant HUD consumers must agree with the durable result—or explicitly say that results are temporarily unavailable.

---

## F16 — History omits the context needed to interpret a flight

### What the source and component check show

The production writer stores scenario and failure configuration inside **`record.metadata`**. History rendering instead reads **`record.scenario`** at the top level, while the statistics schema rejects that top-level field.

That means the renderer’s scenario branch cannot display the valid nested production data. There is also no equivalent presentation of failure-practice context. See the [metadata producer](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L2284), [history renderer](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/statistics_screen.gd#L653), and [statistics schema](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/statistics/schema.gd#L28).

A statistics-schema-valid synthetic record with minimized nested scenario and failure metadata displayed its aircraft, outcome, landing counts, airspeed, and timestamps, but neither context. The nested fixtures were not validated as complete launch configurations, and this was not a flown Natural Random session.

### The producer also needs correction

Rendering the existing nested field alone would be incomplete.

Natural Random launches use a default failure configuration, but `_attach_statistics()` records saved `preferences.failure_config` rather than the accepted scene’s effective configuration. A future label could therefore describe the player’s saved preference instead of the settings actually used for that flight. The relevant launch choice is in [AppRoot’s Natural Random setup](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/app_root.gd#L861).

### Recommended repair

Create one schema-aware record-to-view adapter and capture the **effective accepted configuration** when the flight is admitted.

Useful presentation would include:

- **Natural Random** or the appropriate scenario context.
- **Failure practice enabled**, where established.
- Expanded details for the seed and accepted practice settings.
- Actual recorded failure events, separately from whether practice was enabled.
- Exact airborne duration in expanded details.

The same 42-second fixture was presented only as **`<1 min`**, despite the existing plan requesting seconds in detailed views. This is a smaller extension of the history-detail gap, not another major finding. [Flight-statistics presentation requirements](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/docs/plans/flight-statistics.md#L59)

Older records with missing or unreliable context should remain qualified as unknown.

**Acceptance:** ordinary and Natural Random sessions; practice enabled/disabled; saved preferences deliberately different from the effective flight configuration; legacy records; translated tags; and a real store round-trip before inspecting the rendered details.

---

## Additional presentation improvements

These are deliberately outside the seven functional findings because their evidence is narrower.

### Give custom paint cards a recognizable identity

Built-in paint choices can provide thumbnails; custom choices currently provide IDs and labels without thumbnails. The actual gallery component produced two identically labelled cards with no thumbnail textures when given distinct custom-shaped IDs with the same allowed label. [Custom choice generation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/aircraft/custom_skin.gd#L113) · [Gallery construction](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/livery_picker.gd#L58)

Provide a cached preview or intentional fallback swatch, preserve a clear selected state, and expose a stable distinguishing detail. Do not assume labels are unique.

The remaining acceptance case is to import two real same-label packages and compare them using mouse, keyboard, and controller.

### Explain when previously installed paint becomes unavailable

Source inspection shows that a skin incompatible with a changed model identity can disappear from the choices, with the saved selection resolving to stock. The archive remains, but the explanation is missing.

Keep an unavailable entry and explain the fallback. Preserve the explicitly supported legacy compatibility exception. This upgrade scenario was not executed during the continuation. [Paint compatibility and fallback](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/render/airplane.gd#L195)

### Localize the part of an import error that helps the player act

`SkinTools` translates the introductory failure text but appends raw English validation reasons. Use stable error codes with localized explanations for wrong aircraft, incompatible revision, invalid package, and a full inventory. [Import result presentation](https://github.com/bultodepapas/OpenRCsimulator/blob/3751e35e1cccf574c4446d21273a4d5ecaf80ddf/app/ui/skin_tools.gd#L99)

A named in-game paint-management flow would also reduce friction at the 32-paint limit. A documented manual removal procedure already exists; the improvement is making that recovery practical inside the game.

---

## How these repairs should improve the interface

### Keep feedback beside the action that caused it

The shared Fly action should own its visible launch status. Workshop’s save status should reflect the complete stored identity. Library and History screens should preserve a meaningful result after a dialog closes.

Use the existing theme and Container-based layout for these additions, with wrapping explanations and one dominant recovery action. Godot’s Containers and theme system support consistent resizing and inherited styling, which is preferable to adding another set of individually positioned notices. [docs.godotengine.org](https://docs.godotengine.org/en/latest/tutorials/ui/gui_containers.html?utm_source=chatgpt.com)

### Make the same meaning available through focus

A reason for an unavailable action should be visible and available through keyboard/controller focus and accessible properties. Mouse-only tooltips are insufficient for these recovery paths.

Godot’s navigation guidance specifically warns that automatic focus-neighbor selection can be unsuitable for complex interfaces and that hidden controls lose focus. Initial and return focus should therefore target meaningful visible controls after each transition. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_navigation.html?utm_source=chatgpt.com)

### Keep responsive feedback independent of expensive previews

For custom-paint previews, show names, selection, and availability immediately, then populate previews through a bounded cache. Include aircraft/model identity and skin identity in the cache key, and discard stale results when the selection changes.

Godot’s background-loading and thread-safety guidance supports separating resource preparation from live scene-tree work. It does not establish a speedup for this project without measurement. This continuation produced no new GPU benchmark or frame-time claim; the existing loading-performance work remains a separate acceptance task. [docs.godotengine.org](https://docs.godotengine.org/en/latest/tutorials/io/background_loading.html?utm_source=chatgpt.com)

## Recommended implementation order

| Order | Work | Completion criterion |
|---|---|---|
| **1** | **F10 + F11:** preserve authored inputs and names | Presets and unrelated saves cannot silently alter other accepted data |
| **2** | **F13:** make launch rejection visible and actionable | Every launch entry point shows the reason and a direct correction path |
| **3** | **F14:** retain one owner for departure | Recovery decisions survive later failures; dialogs and pause state remain coherent |
| **4** | **F12 + F15:** reconcile displayed results with storage outcomes | Empty, unreadable, committed, and unavailable states are accurately distinguished |
| **5** | **F16 + paint improvements:** improve interpretation and selection | History explains the session, and paint choices are recognizable |

The six retained component runs completed with their required markers and zero engine errors or warnings. The full-app run deliberately preserves the reproduced modal diagnostics and helicopter refusals. Native visual quality, physical input, assistive technology, and OS window-manager behavior still require their own acceptance checks; the headless evidence establishes application state and node visibility.

**The strongest next step is to make every action’s scope and outcome dependable:** preserve what the player entered, explain why an operation stopped, and keep the next useful action where they are already looking. The existing theme, screen stack, compiler, and checked tools provide a practical foundation for those repairs.