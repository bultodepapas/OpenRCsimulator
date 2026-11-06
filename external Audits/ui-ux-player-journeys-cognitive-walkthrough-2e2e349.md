I continued by walking through **seven plausible player journeys**, including the moments when someone changes their mind, overlooks an instruction, switches aircraft, or expects Restart to use a setting they just changed.

The clearest improvement is to **show the consequence of an action before the player commits to it**: what will launch, what will be saved, what Cancel can undo, and what Restart will repeat. Several of your menus already handle the underlying behavior well; the next step is making that behavior easier to predict.

[OpenRC_Player_Journeys_2026-11-06.pdf](https://chatgpt.com/library?file_id=libfile_2f8b3f3c00e88191b8a0e57183ce7e88&account_id=personal)

The complete 13-page walkthrough includes the seven journeys, proposed wording, implementation priorities, acceptance tasks, and references to the reviewed code.

[OpenRC_Player_Journeys_Evidence_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_e5a55e0d27388191a007381edcc26d72&account_id=personal)

The supporting evidence contains the application transcript, logs, final test-profile settings, source identities, and reproduction guidance.

## How I approached this pass

I reviewed revision **`2e2e3492e67d`**, reread the updated [consolidated audit](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/external%20Audits/CONSOLIDATED-AUDITS.md), and checked the earlier findings and current menu plans. Existing concerns remain attached to their previous owners.

This is a **cognitive walkthrough**: imagine a player’s goal, follow the available actions, and ask whether the interface makes the next step and its result understandable. That is an established inspection method, separate from a study with real participants. The thoughts below are explicitly imagined—not player quotations or measured reactions. [NN/G](https://www.nngroup.com/articles/cognitive-walkthroughs/?utm_source=chatgpt.com)

I also exercised selected routes in the complete application: Help and Controls detours, failure-practice settings and Restart, changing aircraft, starting the 61FX engine, and browsing Natural Random. Those checks used the headless application with a verified logical **1920 × 1080** viewport. They establish application state and navigation behavior; visual polish and physical-controller usability still need native evaluation.

---

## 1. The curious beginner: “I chose an aircraft. Why isn’t it moving?”

**Journey:** Home → Aircraft → Ugly Stick · 61FX → Flight → runway start → Fly.

Imagine a player who is new to your simulator but curious enough to choose the experimental 61FX variant. They see an aircraft, a runway start, and a prominent Fly action. Once in the flight, they look for the basic controls.

Their possible thought is:

> “The instructions say throttle. I increased it. Is my keyboard working, or am I missing a step?”

### What the implementation actually does

The finite-glow 61FX deliberately begins a runway flight with its engine stopped. Throttle and starting the engine are separate operations. The compact airplane hint covers arrows, throttle, and Pause; the separate starter appears in the longer shortcut information.

I exercised the ordinary route: the 61FX began stopped, and **Resume → F7 → Pause** left the engine running. That supports the startup requirement without establishing that a real player would miss it. See the [engine-start handling](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/sim/flight_session.gd#L383) and [shared control-reference content](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/controls_reference.gd#L20).

There is already useful guidance: **Help and the default Control guide include F7**. The opportunity is to bring the relevant instruction closer to the moment it is needed.

### Recommended experience

Use a short cue that reflects the actual aircraft and state:

| Moment | Suggested presentation |
|---|---|
| Before Fly, for this runway configuration | **Engine begins stopped. Press F7 after the flight starts.** |
| In flight, while the engine is stopped | **Engine stopped · F7: starter** |
| After a successful request | **Engine running** |
| When a request is refused | Explain the actual blocking condition, where the implementation can provide it. |

The preflight message predicts the initial state. The in-flight message describes the current state. That distinction prevents a stale instruction from appearing after the player has already started the engine.

F7 is currently a **fixed physical-key handler**. The displayed key should use your existing key-label machinery; a gamepad starter binding would be separate work. The current dispatch is in [main.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/main.gd#L2012).

**Why this improves the experience:** it answers the immediate question without sending the player through a long list of unrelated commands. It also preserves the deliberate engine-start mechanic.

**Prior-work relationship:** this is a specific finite-glow example for the existing contextual-help and onboarding work in UI-30/UI-36, rather than another broad tutorial finding.

---

## 2. The RC enthusiast: “My transmitter is detected. Where is calibration?”

**Journey:** Home → Controls → Devices → select transmitter → look for calibration.

Imagine someone who knows RC aircraft well but has never used your interface. They connect a transmitter and perhaps a separate gamepad for menus.

Their possible thought is:

> “The simulator sees my transmitter. The next thing I expect to do is calibrate it.”

### Where the journey becomes less obvious

For an unfamiliar device that initially appears as a joystick, the player may need to:

1. Select the device for flight.
2. Open **Profile**.
3. Choose **Radio transmitter · custom**.
4. Return to **Devices**.
5. Start calibration.

The calibration action becomes available for a connected radio draft. The prerequisite is explained in Profile and in the first-launch documentation, but it is not presented beside the place where the player initially looks for calibration. This is a source-grounded discoverability opportunity; I did not attach a physical transmitter for this pass. See [controller_setup.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/controller_setup.gd#L279), [calibration visibility](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L1584), and the [documented setup route](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/docs/FIRST-LAUNCH.md#L141).

### Recommended experience

For an unconfigured flight device, add a small contextual instruction:

> **Using an RC transmitter?**  
> Choose a Radio transmitter profile, then calibrate.

A direct action such as **Choose radio profile** would make the dependency discoverable without automatically guessing what unfamiliar hardware is.

There is another expectation worth addressing: **Save does not give the profile and the current device selections the same lifetime.** The profile persists, while explicit flight/menu device-role selections are maintained for the current app session; startup selects devices automatically again. That policy is intentional and documented. See [controller_service.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/input/controller_service.gd#L354) and [FIRST-LAUNCH.md](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/docs/FIRST-LAUNCH.md#L99).

A successful-save message could explain both outcomes:

> **Profile saved.**  
> Device selections apply for this app session. Devices are selected automatically when the app starts again.

**What to preserve:** the separate Flight and Menu roles, keyboard/mouse fallback, and explicit identification of unfamiliar hardware are useful foundations.

**Prior-work relationship:** this is about exposing an existing prerequisite and persistence policy. It does not reopen the earlier profile-identity or controller-recovery-focus defects.

---

## 3. The player who changes their mind: “I cancelled calibration. Why did my settings change?”

**Journey:** Pause → Session options → Controls → edit a mapping → Calibrate selected radio → cancel calibration.

This is the most important controller-related journey in this pass because it concerns the meaning of **Cancel**.

The player’s possible expectation is:

> “I have not pressed Save. Calibration is another setup step. If I cancel it, I should still have my previous controller settings.”

### What actually happens

During a live flight, the calibration button first calls:

```gdscript
setup._save_profile(false)
```

That commits the Controls draft and selected device roles before the calibration wizard starts. Cancelling the wizard leaves those newly accepted settings in place.

The behavior is documented, and the save is checked before proceeding. The uncertainty comes from the button’s wording and from applying the Home calibration model to the Pause route. Home calibration remains a draft until Save; the in-flight route has an earlier commitment point. See [app_root.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L1549) and the [in-flight calibration instructions](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/docs/FIRST-LAUNCH.md#L145).

### Recommended experience

Make the committing action explicit:

> **Save controller settings and calibrate**

Immediately beside it:

> Calibration starts after these settings are saved. Cancelling calibration keeps the saved settings.

After cancellation:

> **Calibration cancelled. Your saved controller settings are still active.**

This gives “previous profile” a clear meaning. The player should not need to reconstruct which version of the profile was considered “previous” when the wizard began.

I would start with the caption and explanation rather than automatically adding another confirmation dialog. The action can remain efficient if its consequence is visible beforehand.

**Why this improves the experience:** it aligns the player’s understanding with the actual transaction boundary. That matters particularly when a profile edit changes how an aircraft responds.

**Acceptance task:** edit one mapping and the two device roles, begin calibration, and cancel. Before the player presses the calibration action, ask what they expect to remain. The interface should make the eventual result predictable.

**Prior-work relationship:** the save-before-calibrate mechanism is known. The contribution here is a clearer explanation of that behavior, not a claim that the mechanism was newly discovered or accidentally introduced.

---

## 4. The casual practice session: “I only wanted failures for one flight”

**Journey:** Practice → Failure practice → 100% → Apply → Flight → Fly → Pause → set failures to 0% → Restart.

This produced the strongest new wording issue in the walkthrough.

The dialog currently says:

> “Probability and failure type apply to the next flight only…”

A plausible interpretation is:

> “I am enabling one practice flight. After that, normal flying returns.”

But the preference is deliberately reusable until changed. The implementation saves it and reads it for subsequent ordinary airplane flights. The failure-mode plan explicitly supports that behavior. See the [dialog wording](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/failures_menu.gd#L89), [save path](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L2657), and [owning plan](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/docs/plans/failure-mode.md#L97).

### Two uncertainties combine

First, the failure summary is on **Practice**. When the player returns to **Flight**, that summary is hidden. The setting can still affect the upcoming flight, but its reminder is on another page. The relevant placement and page logic are in [home.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/home.gd#L601).

Second, **Restart preserves the current resolved failure draw**. Changing future settings to zero does not replace the current exercise when Restart is pressed. This is useful for repeatable practice, but “next flight” can easily be interpreted as including a restart.

I exercised that sequence. The current episode remained the same after setting the future probability to zero and restarting. A later new airplane flight had failures disabled. No failure activated during the ground-only check.

### Make the three choices understandable

| Action after changing failure settings | Result |
|---|---|
| **Resume** | Continue the current flight and its existing failure draw. |
| **Restart flight** | Restart the current resolved draw, including a draw with no failure. |
| **Return Home → Fly** | Start a new ordinary airplane flight using the saved settings. |

The restart implementation is in [app_root.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L2922).

### Recommended wording and visibility

Replace the one-off implication with a truthful lifetime statement:

> **Failure settings apply to new ordinary airplane flights until you change them.**  
> Restart repeats the current failure setup. Start a new flight from Home to use changed settings.

Keep two qualifications close to the relevant controls:

- **Notification changes apply to the current flight immediately.**
- **Natural Random does not use these saved failure settings; helicopters are excluded from this modifier.**

Those distinctions follow the [effective configuration selection](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L861) and current Apply behavior.

Beside Fly, show a compact reminder when the modifier is enabled:

> **Failure practice: 100% · Review**

That reminder should describe the chosen practice configuration without revealing a failure that is intended to remain undisclosed.

**Why this improves the experience:** players can deliberately leave practice mode, understand repeatability, and recognize an active modifier before launching.

**Prior-work relationship:** this is new copy-level evidence about an intentionally persistent setting. It is separate from the previously reported history-context and onboarding issues.

---

## 5. The returning pilot: “Let me try another aircraft”

**Journey:** Pause → Change aircraft → MoonRunner X99 → Fly.

This route has a good existing shortcut: **Change aircraft** runs the end-flight transaction and opens the catalog with the current aircraft focused. I exercised that behavior.

Now imagine the player has been using runway starts. They select MoonRunner and assume the next flight will begin in broadly the same way.

Their possible thought is:

> “I changed the aircraft. Will this still start on the runway?”

### What changes behind that selection

With a remembered runway preference, selecting the gearless MoonRunner resolves the effective start to **Hand launch**.

On the Aircraft page, the visible caption names the next aircraft, while the Start row belongs to the hidden Flight page. The loading screen does show the resolved start after Fly and provides Cancel. The opportunity is to make that information available at the earlier decision point. See [effective-start resolution](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/home.gd#L1278), [the Fly caption](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/home.gd#L806), and [loading configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L889).

### Recommended experience

Expand the existing caption into a compact review of the effective setup:

> **Next flight**  
> MoonRunner X99 · Club field · Hand launch  
> **Change start**

When practice modifiers are active, include their short summary in the same decision area.

This does not need a mandatory confirmation screen. The player should be able to glance at the result and immediately press Fly.

The important implementation rule is that the summary must use the **same resolved values** used by loading and session creation. Another independent copy of the aircraft/field/start compatibility rules would create opportunities for disagreement.

**Why this improves the experience:** aircraft selection becomes a transparent configuration change. Players can see its consequences without making a second trip through the menus.

**Prior-work relationship:** this extends UI-34’s setup and launch work and the existing remembered-start rules. The observed MoonRunner configuration was valid; this is a visibility opportunity.

---

## 6. The airplane pilot trying a helicopter: “The controls I just learned are different now”

**Journey:** complete airplane tips → return Home → choose X-Cell → choose pad start → Fly.

A player who has learned the airplane controls may reasonably expect a short introduction when trying a substantially different vehicle.

Their possible thought is:

> “W controlled throttle before. What must I do before this rotor starts?”

### What the source shows

The first-flight hint has vehicle-specific content, but completion is stored through one shared `first_flight_hint_seen` preference. Completing the airplane hint can therefore suppress the dedicated helicopter hint on a later first helicopter flight.

This is a source-only journey in this pass. The helicopter already has meaningful guidance: its HUD provides a disarmed startup instruction, and Help explains the pad-start sequence. See [hint construction and launch handling](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L1116), [helicopter HUD instructions](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/helicopter_main.gd#L279), and [contextual Help](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/help_screen.gd#L162).

### Recommended experience

Track useful tip exposure by **vehicle class**, coordinated with the existing work on input family and actual visible exposure.

For a disarmed pad start, the short instruction must include the prerequisites:

> Center cyclic/yaw and set zero pitch. Press B to arm, H to release hold, then wait for governed RPM before raising collective.

That sequence should appear only in the appropriate state. A hover start initializes differently.

Also provide **Show flight tips** as an on-demand action. Returning players should be able to recover the current vehicle’s short instructions without resetting unrelated preferences.

**Why this improves the experience:** the interface recognizes that knowing one aircraft class does not automatically teach another. It reuses the content you already have.

**Prior-work relationship:** combine this vehicle-class dimension with UI-36/HELI onboarding and A13’s existing hint-exposure work. It should not become a parallel tutorial system or another duplicate onboarding ticket.

---

## 7. The explorer: “I want to look around without losing my setup”

**Journey:** Help → Back → Controls → Cancel → Natural Random → Another flight → Back → Settings.

This journey revealed several behaviors worth preserving.

In the exercised routes:

- Leaving Help restored focus to **Help**.
- Cancelling Controls restored focus to **Controls**.
- **Change aircraft** opened the current catalog entry.
- Browsing and rerolling Natural Random, then choosing Back, preserved the Home aircraft/start choice and restored focus to **Natural Random**.

These are valuable patterns. They let someone explore while keeping their place. The shared navigation behavior is owned by [Screen](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/screen.gd#L88) and [ScreenStack](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/screen_stack.gd#L71).

### The remaining uncertainty is scope

As players move between screens, several different models coexist:

| Interaction | Scope the interface needs to explain |
|---|---|
| Presentation preview | A draft with Keep/Revert behavior. |
| Language selection | An immediate save. |
| Home radio calibration | A draft until Controls is saved. |
| In-flight radio calibration | Controls settings are committed before the wizard. |
| Ordinary paused Sky and lighting | Apply affects the flight and attempts to save defaults for later flights. |

The Settings and Sky rows were source-traced in this pass. Their owners are [settings_screen.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/settings_screen.gd#L459), [time_of_day_dialog.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/ui/time_of_day_dialog.gd#L62), and the [ordinary-flight lighting save path](https://github.com/bultodepapas/OpenRCsimulator/blob/2e2e3492e67d30635cc4e727025581e2848cdf2e/app/app_root.gd#L2433).

A player should not have to infer which model is active.

For ordinary Sky and lighting, a scope statement could say:

> **Applies to this flight and saves as the default for later flights.**

The result should then distinguish:

> **Applied and saved.**

from:

> **Applied to this flight. Settings could not be saved.**

That preserves the difference between a successful live change and a failed persistent write.

**Prior-work relationship:** the ordinary Sky scope concern and several Settings recovery issues are already documented. Here they illustrate the player’s journey; they are not being counted again.

---

## What I would improve first

| Order | Change | Player benefit |
|---|---|---|
| **1** | Correct failure-setting lifetime and Restart wording; show active practice near Fly. | Players can predict whether the next action continues, repeats, or starts a new exercise. |
| **2** | Rename the in-flight calibration action to disclose the save. | Cancelling the wizard no longer creates uncertainty about controller settings. |
| **3** | Show aircraft, field, and effective start beside Fly. | Players can review the result of aircraft selection before launching. |
| **4** | Make short startup guidance depend on vehicle and state. | The required action appears at the moment it becomes useful. |
| **5** | Explain unknown-radio prerequisites and device-selection lifetime. | Setup becomes discoverable without requiring the external guide. |

This sequence prioritizes consequential decisions and changes in player intent. Much of it can be delivered through precise wording and small additions to existing components.

## How I would implement the polish in Godot

**Reuse your current screen and theme infrastructure.** `home.gd`, the shared screen stack, and `ui_theme.gd` already provide the appropriate homes for these changes. A shared launch-summary component should refresh from accepted selection/configuration changes, rather than recreating compatibility rules or rebuilding the menu every frame.

For layout, use your existing `Container` structure and wrapping behavior. Godot’s containers control their children’s positioning, so manually adjusting managed child offsets is a fragile way to accommodate longer summaries or translated text. Qualify the result at 1080p first, following the repository’s priorities. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_containers.html?utm_source=chatgpt.com)

For navigation, preserve opener focus and a valid fallback when conditional controls disappear. Godot explicitly notes that hiding a focused control can remove focus and that automatic neighbor selection can be unreliable in complex layouts. Your new summaries should remain non-interactive unless they offer an actual action such as **Review** or **Change start**. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_navigation.html?utm_source=chatgpt.com)

For presentation, use consistent typography, spacing, and state styling from the shared theme. Active practice needs visible text as well as any color treatment. Focus should remain distinguishable from selected and pressed states; Godot’s theme documentation describes focus styling as an overlay on the underlying control appearance. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_skinning.html?utm_source=chatgpt.com)

For transitions, keep the existing loading and cancellation ownership. Show the actual stage being performed, and measure whether feedback is rendered during the wait. Godot’s threaded resource retrieval can still block when the requested resource has not finished, so a loading label alone does not establish responsiveness. The synchronous Natural Random preparation concern is already covered by A13 and should stay with that work. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/io/background_loading.html?utm_source=chatgpt.com)

## How to validate these imagined journeys

The next useful evaluation is to give people goals without teaching them the route:

- “Choose the 61FX and get ready to take off.”
- “Use this transmitter for flight and this gamepad for menus.”
- “Change one mapping, begin calibration, then change your mind.”
- “Try failure practice, then start a normal new flight.”
- “Switch from a runway airplane to MoonRunner.”
- “Try the helicopter after your airplane flight.”
- “Browse a random flight, then return to your original setup.”

Before a consequential action, ask: **“What do you expect this to change, and what do you expect to stay?”** Record where that prediction differs from the actual result. That will tell you which of these hypotheses causes real friction.

The source remains unchanged. The delivered report provides the review and proposed experience; the evidence package preserves what was actually exercised. The most useful next design outcome is a player who can look at **Fly, Save, Cancel, Restart, or Back** and correctly predict both the immediate result and what will remain afterward.