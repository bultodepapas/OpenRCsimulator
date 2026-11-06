I continued the player-journey review, and the strongest new finding is **a Workshop trial can quietly change an unrelated saved setting**. I also followed three garage journeys through leaving, returning, restoring, and changing options, plus a source-based review of the new warning display.

The earlier walkthrough is preserved. This continuation adds a **12-page report** and its supporting evidence:

- [OpenRC_Player_Journeys_Interruptions_Recovery_2026-11-06.pdf](https://chatgpt.com/library?file_id=libfile_7affe66a0bd881918df4a363759b6094&account_id=personal)
- [OpenRC_Player_Journeys_Interruptions_Recovery_Evidence_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_6f916099b9f081919949ab833aa64a39&account_id=personal)

I reviewed commit [`d0b672b`](https://github.com/bultodepapas/OpenRCsimulator/commit/d0b672b09663226ff8b8ac4f43eae8643c77a8c4), cross-checking the [current A1–A14 consolidated audit](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/external%20Audits/CONSOLIDATED-AUDITS.md) and the previous journeys.

The first-person thoughts below are **imagined player expectations**. The confirmed observations come from application state, saved files, and code. The application checks used the project’s debug bridge, synthetic control activation, and an inspected 1920×1080 logical viewport. They establish behavior; native appearance and physical controller handling still need their own evaluation.

## 1. “I changed the sky. Why did my saved campfire turn off?”

**Priority: first. Confirmed in the application and settings file.**

Imagine someone preparing an evening flying session. They enable the campfire, enter Workshop to try an aircraft build, and adjust the sky during its test flight.

Their intention is straightforward:

> I am testing the aircraft in the conditions I chose. Changing the sky should preserve the other settings I already saved.

I exercised this route:

**Home → Conditions → Campfire on → Apply → Workshop → runway trial → Pause → Sky and lighting → Clear blue → Apply → Return to Workshop.**

The resulting state was:

| Point in the journey | Saved campfire setting | Trial campfire setting |
|---|---|---|
| Before entering the trial | On | — |
| Trial starts | On | **Off** |
| Apply the sky change | **Off** | Off |
| Return to Workshop | **Still off** | Trial has ended |

The before-and-after settings files confirm that `campfire=true` became `campfire=false`. The sky changed as requested; the campfire change came along with it. I did not execute a separate application relaunch, so the precise persistence claim is that **the saved file changed and remained changed after returning**.

### Why this happens

The trial setup copies the field, weather, time, and sky, but omits the night-options bundle. The new flight therefore receives its default campfire and field-light settings.

The Pause dialog then reads those trial defaults. When Apply saves the dialog’s values, it also writes those untouched night options into the normal preferences.

The relevant paths are the [trial construction in `app_root.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/app_root.gd#L2135), the [flight defaults in `main.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/main.gd#L116), and the [paused lighting Apply handler](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/app_root.gd#L2387).

### What I would change

**Give the trial a complete, explicit presentation context.** Include sky, lighting, field-light activation, campfire, and the policy governing whether edits become saved defaults.

That improves two things at once:

- The trial starts in the conditions the player expects.
- An unrelated option cannot enter a save operation merely because a new scene supplied its default.

The interface should also state the scope of Apply. If trials are intended to be temporary, suitable wording would be:

> **Applies to this trial.**

A separate action could offer:

> **Use as my flight defaults.**

If ordinary trials intentionally update normal defaults, explain that before Apply and preserve every untouched option.

I would avoid a blanket “restore all preferences when leaving Workshop” fix. A player might deliberately change another setting during the trial; restoring an old snapshot could erase that legitimate change.

**What already works:** the exercised route returned to Workshop with the runway choice displayed and focus on Test fly. Source and existing integration-test code separately support retaining the editor and interrupted flight, although those broader restoration cases were not rerun here. The [editor plan already calls for actual inherited conditions and preservation of the draft](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/plans/aircraft-editor.md#L400).

---

## 2. “I saved my experiment. Why won’t Restore work?”

**Priority: next. Confirmed refusal, file preservation, and a successful recovery path.**

Now imagine an interested simulation player experimenting with the RC car:

> I reduced gravity, saved the state, went back to Home, and reopened the same car. If the save needs another setup, tell me which setup.

I followed this sequence:

1. Open **Bisonte MT8**.
2. Select **Physics lab**.
3. Set **Gravity to 0.50** and apply the experiment.
4. Select **Save state**.
5. Return to Home.
6. Reopen Bisonte MT8 and select **Restore**.

Restore set the message to:

> “State does not match this vehicle and course.”

The car and field were the same. The missing part of the explanation was the **experiment setup**.

I then reapplied Gravity 0.50, leaving the other experiment controls at the same values, and selected Restore again. It succeeded. The saved file had remained byte-for-byte unchanged after the earlier refusal.

There was a second revealing case: **before saving anything**, Restore produced the same mismatch message for an empty slot.

### What the player is being asked to remember

Applying an experiment changes the vehicle’s model identity. Returning Home destroys the active ground scene, and reopening the car starts its default setup. Restore correctly requires a compatible model, course, vehicle, and solver.

The problem is the explanation and recovery route. The current message does not identify the experiment mismatch, and it does not distinguish that situation from having no save at all.

See the [garage save/restore handling](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/vehicles/ground/ground_scene.gd#L742) and [checkpoint compatibility checks](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/ground_vehicle/session.gd#L829).

### A clearer recovery experience

These outcomes deserve different messages and actions:

| Situation | Useful explanation | Next action |
|---|---|---|
| No saved run | “No saved run for this vehicle yet.” | Continue driving or save |
| Saved experiment differs | “This saved run uses Gravity 0.50.” | **Review saved setup** |
| Saved run cannot be read | “The saved run could not be read.” | Show available recovery options and details |
| Compatible saved run | Identify the run being restored | **Restore run** |

After validating the saved metadata, the interface could show the car, course, and experiment settings in terms the player recognizes. Where supported, **Apply setup and restore** would make the recovery concrete.

The existing compatibility checks should remain. They protected the run correctly, and the matching setup restored successfully. This is an opportunity to make that protection understandable and actionable.

For the Physics lab, I would also favor outcome-focused feedback such as:

> **Gravity 0.50 applied. Run restarted.**

Technical identity details can remain available in Details.

This work belongs to the existing RCV checkpoint and laboratory workflow, which the [RC vehicle plan already tracks](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/plans/rc-monster-truck.md#L396).

---

## 3. “I was choosing where to go. Did that restart my run?”

**Priority: next. The reset is confirmed; whether players anticipate it needs observation.**

Imagine someone opening the garage after driving and browsing the available circuit starts.

> I want to try the rollers. Before replacing my current run, show me what selecting that location will do.

The location option currently commits the reset as soon as a selection is accepted.

In the short application check:

- The run had advanced to tick **14**.
- Its in-memory control tape contained **56 values**.
- Selecting **Circuit · Rollers** immediately changed the tick to **0**, cleared that tape, and moved the car to the new start.
- The garage remained paused.

This was a brief logical-state check, not a long driving trial or a telemetry-recording test.

The [selection handler](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/vehicles/ground/ground_scene.gd#L210) finalizes recording, then calls `session.reset()`. The [successful session reset](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/ground_vehicle/session.gd#L253) also replaces the current run’s other transient state.

### Make the consequence part of the action

I would use:

**Start location:** Circuit · Rollers  
**Action:** Restart at Circuit · Rollers  
**Consequence:** Ends the current run.

Accepting an option would select a pending destination. The explicit restart action would commit it.

This does not need a confirmation dialog every time. An untouched initial run can retain a fast path. Once meaningful state exists, the player should be able to browse another location and press Back without replacing the current run.

There is a clean Godot implementation boundary here: `OptionButton.item_selected` can update the pending value, while a separate button performs the reset. The selection signal itself does not require the application to reset anything. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_optionbutton.html?utm_source=chatgpt.com)

The existing circuit guidance and recording-finalization behavior are useful. This finding concerns the consequence of accepting the option; it does not reopen the previously reported garage quit/recording issue.

---

## 4. “Did the camera button do anything?”

**Priority: polish after the state and recovery issues.**

Imagine choosing a driving view before releasing the car:

> I want to compare the views while paused. Tell me what I selected and when it takes effect.

In the garage, the Camera button changes the selected camera mode. However, the [camera implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/vehicles/ground/ground_camera.gd#L32) deliberately uses the garage’s orbit composition for the chase, pilot, and orbit selections while the menu is open.

I confirmed that two successive selections changed the mode to 1 and then 2 while producing **the same paused camera transform**. The button still read **Camera · C**.

Circuit overview was a useful counterexample: it selected a different mode and produced a different camera transform.

### The player needs a selected value

A paused garage composition can be intentional. The interface still needs to tell the player what the button selected.

For example:

> **Driving camera: Pilot stand**  
> Used when you select Drive.

Or, where the composition permits it, preview the selected driving camera while paused.

I would keep **Circuit overview** as a clearly named separate view. Its return behavior also needs precise wording: the current [handler toggles overview back to Chase](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/vehicles/ground/ground_scene.gd#L706). Offering “Return to previous camera” would require preserving that previous choice.

This is a small change with a clear purpose: **every camera action should leave a readable indication of what the player selected**.

The actual framing, visual transition, and controller experience still need native evaluation.

---

## 5. “I can see another alert exists. How do I read it?”

**Priority: a focused design improvement to evaluate after the state issues. Source-based in this pass.**

The new warning rail has several good foundations: priority ordering, removal of redundant reminders, a configurable limit, and an overflow count.

The next journey is about understanding that overflow.

> There is “+1 MORE ALERTS.” I want to know what that other condition is.

Consider a source-supported case with the visible limit set to one and both STALL and LOW selected. The policy keeps both codes, displays the higher-priority one, and gives the overflow summary the highest omitted severity.

However, the [overflow summary](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/render/overlays/warnings_bar.gd#L137) is an inert panel with labels. It has no direct expansion action or focus target that reveals the omitted names.

There is an existing workaround: **Pause → Flight overlays → Alerts** lets the player increase the limit from one to three or five, with an overlay preview. Other instruments may also expose some underlying conditions. The issue is specifically the absence of a direct way to inspect the rail’s additional selected alerts.

### Give the count an understandable action

A possible addition is:

> **Review active alerts (2)**

That could open a deliberately paused, focusable view containing the selected alerts and their explanations.

It should:

- Preserve the player’s saved display limit.
- Retain the current priority and category policy.
- Clearly describe whether the list represents the paused snapshot or updates while open.
- Return predictably to Pause or flight.
- Avoid unexpectedly taking control of flight input.

Godot’s focus guidance matters here: hidden controls can lose focus, and UI navigation actions should remain separate from gameplay actions. The existing screen-stack and selected-menu-device handling are the appropriate places to integrate this interaction. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_navigation.html?utm_source=chatgpt.com)

The [current HUD plan explicitly intends the cap, overflow, and whole-rail close behavior](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/docs/plans/flight-overlays.md#L51). I am keeping this as an inspection opportunity within that design, not counting those intentional behaviors as new defects.

A related wording refinement would be **Hide warning panel** for the persistent whole-panel close action. That describes its scope more clearly than a generic dismissal.

---

## Two further Workshop details worth preserving in the review

### A detour from Natural Random should have an explicit settings scope

The source shows that a normal Natural Random launch sets `remember_lighting_selection=false`, while a separately constructed Workshop trial defaults it to true and does not inherit that flag.

That creates another route through which trial sky and lighting edits can reach ordinary defaults. Returning restores the original Random flight and world, but does not roll back those preference changes.

This is **source analysis**, and it belongs under the existing A11 F03 isolation concern. It is a distinct non-Moon trial route, not another count of the earlier Moon finding. The relevant comparison is between [normal launch policy](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/app_root.gd#L970) and [Workshop trial construction](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/app_root.gd#L2135).

My preferred behavior is for a trial entered from a temporary Random session to inherit that temporary scope, with an explicit action if the player wants to adopt its conditions as defaults.

### “Which version of my build am I testing?”

Workshop already provides build identity and saved/unsaved state, and [Test fly freezes the current draft](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/ui/workshop.gd#L1973).

During the trial, however, [Pause identifies the base aircraft and field](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/app_root.gd#L2964), without naming the build or its saved/draft identity.

A small cue could help:

> **Testing unsaved changes to Weekend Trainer**

or:

> **Testing saved revision 4**

If you later add a “Last flown draft” indicator, compare the actual relevant build contents. Launching a trial should never automatically mean “passed,” and Test fly should never imply that the build was saved.

This is an orientation improvement, not evidence that the wrong build currently flies.

## What these journeys suggest for the next implementation pass

The repeated need is to make three states understandable:

| State | What the player needs to know |
|---|---|
| **Pending choice** | What will change if I commit? |
| **Active session** | What is in effect right now? |
| **Saved setup** | What can I return to later? |

That distinction should appear both in the code and in the interface. Godot’s `ConfigFile` also distinguishes in-memory changes from writing them to disk, and `save()` returns a result that must determine the success feedback. For the Workshop bug, the wrong untouched value reaches that save operation before feedback becomes relevant. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_configfile.html?utm_source=chatgpt.com)

The practical order I recommend is:

1. **Fix complete Workshop condition inheritance and define trial save scope.**
2. **Give garage Restore distinct outcomes and a route to the required saved setup.**
3. **Make changing a start location an explicit restart decision.**
4. **Add truthful selected-camera feedback.**
5. **Evaluate direct inspection of additional alerts through the existing Pause flow.**

For the next player evaluation, I would ask someone to recover an experiment, browse a start location without restarting, and identify which build and conditions they are testing—without explaining the implementation first. That would test whether the interface carries enough context for someone to leave a task and resume it, consistent with established guidance on designing for interruptions. [NN/G](https://www.nngroup.com/articles/designing-for-waits-and-interruptions/?utm_source=chatgpt.com)

The evidence package retains all **85 bridge commands**, including the initial runtime/setup failures and their resolution. The source checkout remained unchanged, and the app stopped without a forced termination or reported leaked objects. The most valuable immediate change is the Workshop fix: it would make a routine experiment preserve the player’s saved choices, exactly where the current journey breaks that expectation.