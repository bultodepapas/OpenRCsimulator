## Review completed

**The highest-priority improvements are to preserve player choices, maintain usable focus after controller recovery, and make saving behavior truthful.** I found concrete failures in all three areas.

The project already has a substantial UI foundation: a shared theme, centralized screen management, display-change rollback, staged loading, and background flight preparation. The most valuable next step is to make the behavior at the boundaries of those systems consistently dependable. The relevant foundations are in [the screen stack](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/screen_stack.gd), [the theme](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/ui_theme.gd), and [the loading surface](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/flight_loading.gd).

### Deliverables

- [OpenRC_UI_UX_Audit_2026-11-06.pdf](https://chatgpt.com/library?file_id=libfile_31a747c503f4819196fd799d26818ada&account_id=personal) — the complete 18-page review, including priorities, implementation references, recommended repairs, prior-audit cross-checks, and acceptance criteria.
- [OpenRC_UI_UX_Evidence_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_b58414f6afe08191a27290d6aeab1023&account_id=personal) — reproduction fixtures, logs, settings-file differences, source identities, replay instructions, and a machine-readable findings register.

### Baseline and evidence

I read [`external Audits/CONSOLIDATED-AUDITS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/external%20Audits/CONSOLIDATED-AUDITS.md) before reviewing the implementation. I also cross-checked [UI-30](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/docs/research/menu-investigations/UI-30/README.md), the subsequent menu delivery plan, and current PR review comments.

The reviewed baseline is:

- **Repository:** `bultodepapas/OpenRCsimulator`
- **Branch:** `codex/m1-native-validation-20261106`
- **Commit:** [`e72d878b6b4a89209dfe1a992ba119921dcdd34c`](https://github.com/bultodepapas/OpenRCsimulator/tree/e72d878b6b4a89209dfe1a992ba119921dcdd34c)
- **Engine:** `4.8.beta2.official.cafc17a19`, matching the project’s pinned engine. Godot’s official announcement identifies that beta2 snapshot and engine commit. [Godot Engine](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/?utm_source=chatgpt.com)

I distinguish **actual-application reproductions**, **component reproductions**, and **source-level findings** below. A native graphical window was unavailable in this environment, so I do not claim fresh native visual validation, physical-controller testing, screen-reader testing, or renderer benchmarks. The retained native screenshots were inspected as historical design context. Production source was not modified.

## Priorities

The review contains **nine new findings** and **one additional reproduced case within an already documented design concern**.

| ID | Priority | Finding | Evidence |
|---|---|---|---|
| F01 | P1 | “New profile” can overwrite an existing controller profile | Production-component reproduction |
| F02 | P1 | Successful controller recovery can leave Pause without focus | Component reproduction; both timing orders |
| F03 | P1 | Moon edits cross session boundaries and fail on a direct-flight route | Actual application; two routes |
| R01 | P1 | A wind-only preset resets custom atmosphere settings | New reproduction in a previously identified area |
| F04 | P2 | Help cannot be scrolled with the selected gamepad | Component reproduction at 100% and 200% text |
| F05 | P2 | A remapped Back key intercepts ordinary text editing | Verbatim production router in a component host |
| F06 | P2 | A language-save failure from Pause has no visible failure message | Actual application with a protected settings fixture |
| F07 | P2 | Startup ignores saved text size and lacks semantic status/action controls | Source evidence |
| F08 | P2 | Instrument explanations depend on mouse hover | Source evidence |
| F09 | P3 | Graphical arrow keycaps lack application-provided text equivalents | Source evidence |

**P1** means configuration integrity or continuity of control should be corrected before a wider polished release. **P2** is a material usability or accessibility failure for an affected route or input method. **P3** is a bounded quality improvement.

## 1. Protect the player’s configuration

### F01 — “New profile” can update the existing profile instead of creating one

The controller profile selector includes a selectable **New profile** entry with ID `-1`. However, `_on_profile_selected()` only changes the draft for an existing profile index.

Consequently, the selector can display **New profile** while `_draft_profile` still contains the previously selected profile’s identity. Saving passes that identity to the store, which replaces an existing entry with the same ID. The responsible code is in [`controller_setup.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/controller_setup.gd#L1408) and [`controller_profile_store.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/input/controller_profile_store.gd#L44).

**What the reproduction showed:** after selecting New profile, changing its name, and saving, the store still contained one profile with the original ID and the new name.

This interaction deserves particularly careful treatment. Controller configuration can represent substantial player effort, and “New” creates a clear expectation that the previous configuration will survive.

**Recommended change:** make profile creation an explicit state transition. Selecting New profile should create a fresh draft with a new ID and a sensible starting configuration. Alternatively, make that entry a disabled placeholder and provide an explicit **Create profile** action. Keep **Create**, **Duplicate**, and **Update** behavior distinct.

**Acceptance:** start with one saved profile, create another, change a mapping, save, and reload. Both profiles must remain, with different IDs and the original data unchanged. Include Cancel, duplicate names, and switching between profiles.

This is separate from the already tracked unsaved-draft confirmation work.

### F03 — Moon changes bypass the intended session/default boundary

This is the strongest cross-screen settings defect I found.

Natural Random sets `remember_lighting_selection = false`. The later sky, lighting, and night-option persistence paths honor that flag. Moon changes do not: `_on_time_of_day_applied()` calls `_apply_moon_config()` unconditionally, and that helper writes to normal preferences.

The relevant paths are [`_apply_moon_config()`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/app_root.gd#L781) and [the paused editor’s Apply handler](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/app_root.gd#L2393).

I reproduced two consequences in the actual headless application:

| Route | Observed result |
|---|---|
| Natural Random → Pause → Sky and lighting → No moon → Apply | The normal settings file changed from `moon = "real"` to `moon = "off"`, while `remember_lighting_selection` remained `false`. Reloading preferences returned `"off"`. |
| Direct `--quick-flight` → Sky and lighting → No moon → Apply | The code attempted to save a preference dictionary containing only Moon configuration and logged a missing-`language` script error. The editor closed and the flight remained paused. |

The direct route deliberately starts without loading normal preferences. The failing access is in [`Preferences.save_to()`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/app_state/preferences.gd#L276). This was an observed **script error**, not an application crash. The isolated sentinel preferences file remained unchanged.

The Natural Random behavior conflicts with its [documented normal-preference isolation](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/docs/plans/natural-random-flight.md#L88).

**Recommended change:** stage Moon with the rest of the lighting edit, validate the combined draft, then commit it through the same route-aware owner. All fields should share the same persistence decision and a single reported save outcome.

There is also a source-level robustness concern: Moon is committed before the later sky/night/lighting operations finish. A later refusal could leave a partial edit. I did not reproduce a player-triggered failed-sky transaction, so that remains a code-ordering risk rather than another confirmed runtime finding.

**Acceptance:** save normal Moon A, change to B in Natural Random, restart and end the scenario, and verify that the normal preference remains A. Repeat on a direct flight with a sentinel settings file; require no preference access, no script error, and a usable paused session. A rejected combined edit must not partially commit Moon.

### R01 — A wind-only preset silently replaces the atmosphere

The WeatherDialog reproduction started with custom atmosphere at **1,500 m and 35 °C**. Selecting **Steady breeze** and applying produced reference atmosphere at **0 m and 15 °C**, along with the intended **3 m/s wind**.

The cause is concrete: [`_on_preset_selected()`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/weather_dialog.gd#L572) passes the complete preset to `_set_fields()`, which replaces the base configuration and reconstructs the atmosphere controls.

**Prior-audit boundary:** UI-30 SC-8 reports preset placement and wording. The separate [sky/cloud plan already requires unrelated tabs to be preserved](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/docs/plans/sky-clouds-weather.md#L129). I am adding a specific reproduced failure and regression case to that known requirement.

**Recommended change:** make preset scope explicit and merge only the fields that the chosen preset owns.

There is an important implementation detail: the [preset catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/physics/wind_config.gd#L185) intentionally includes **Hot and high**, **Cool dense air**, and **Standard dry ISA column**. Those composite choices should retain their authored atmosphere and disclose their broader effect. Stripping atmosphere from every preset would introduce a different defect.

**Acceptance:** wind-only presets preserve both custom and standard-column air through Apply and reload; Cancel preserves the original draft; composite atmosphere presets apply exactly the broader change they disclose.

## 2. Keep menus controllable through every transition

### F02 — Successful controller recovery can remove the return-focus target

Pause exposes a recovery action while the flight controller is unavailable. Opening Controls captures that action as the focus-return target.

After a successful recovery, Pause’s refresh can hide the action. [`Screen.close()`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/screen.gd#L81) restores focus only if the old opener is still visible, and the stack supplies no fallback. If the action hides after focus is restored, focus is lost at that later moment instead. The visibility change occurs in [`pause_menu.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/pause_menu.gd#L414).

Both timings were reproduced with the production Pause, Screen, ScreenStack, and input components. Afterward, D-pad Down, Accept, keyboard Down, and Tab did not reacquire focus.

The earlier recovery work made the action visible and tested opening/cancelling it while the device remained lost. This finding concerns **successful recovery followed by the opener disappearing**.

**Recommended change:** establish a shared focus invariant:

> When a menu is active and keyboard/gamepad navigation is in use, there must be a valid focus target on that active surface.

Restore the original opener when it is still valid. Otherwise, select the screen’s explicit fallback. Also repair focus when a later refresh hides the currently focused control. **Resume** is a sensible Pause fallback, but focusing it must never resume the flight automatically or steal a newer valid focus.

Godot explicitly documents that hidden controls can lose focus and that deliberate focus acquisition and navigation paths are necessary. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_navigation.html?utm_source=chatgpt.com)

**Acceptance:** perform the real recovery flow with a separate menu pad, selecting Keyboard or a replacement flight controller. Test both refresh timings. The flight stays paused, a visible enabled action has focus, and navigation continues.

### F04 — Help is not fully readable with the selected gamepad

Help’s scroll container can receive focus, but its custom scrolling handler rejects events that are not `InputEventKey`. The text body has no focusable content that would advance `follow_focus`. See [`help_screen.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/help_screen.gd#L147).

The component checks used a 1920 × 1080 viewport:

| Text size | Available scroll distance | Selected-pad result | Keyboard positive control |
|---|---:|---|---|
| 100% | 349 px | Repeated navigation left scrolling at zero | End reached the bottom |
| 200% | 2,833 px | Same failure | End reached the bottom |

A player can enter Help with the gamepad and reach its reading region, yet cannot read the remaining material through that input method.

**Recommended change:** handle selected/remapped menu scrolling while the reading region has focus, or expose explicitly navigable scroll controls. Preserve a direct route to Close and Back. Reuse the existing device filtering so RC radio axes do not begin moving menus.

**Acceptance:** read every section with only the selected controller at 100% and 200% text, including English and Spanish. Test held-repeat, limits, reopening, and closing. Keep keyboard Home/End/Page Up/Page Down and mouse-wheel behavior intact.

This is distinct from the previous Help content-organization work and keyboard-scroll tests.

### F05 — Mapping Back to Backspace can turn deletion into cancellation

The action configuration accepts keyboard events for menu Back. AppRoot processes those mappings in `_input`, before the focused text widget receives its GUI input.

The reconstructed component test used the **verbatim production router**, actual `LineEdit`, and production action validation:

- Default binding: Backspace changed `123` to `12`.
- Back mapped to Backspace: the same event cancelled the modal.
- The production validator accepted that mapping.

The dispatch is in [`app_root.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/app_root.gd#L1691), with accepted bindings in [`controller_actions.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/input/controller_actions.gd#L334). Godot’s documented event order explains why the early handler wins over text editing. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/inputs/inputevent.html?utm_source=chatgpt.com)

The actual Conditions screen has editable fields and connects close requests to cancellation. However, the full saved-profile-to-Conditions route was not executed in this reproduction; the verified result establishes the input-order mechanism.

**Recommended change:** give editable controls their opportunity to consume ordinary keyboard editing before routing remaining menu shortcuts, or add an explicit focused-editor guard. Preserve popup handling, binding capture, intentional Escape/Back behavior, and recovery.

**Acceptance:** use the actual saved profile with Backspace and a printable-key mapping. Typing/deleting must edit the field without closing the draft. Then verify menu Back after editing, modifiers, capture mode, and a real controller Back event.

UI-30 SC-5 already tracks Escape ordering and dirty drafts. This is an additional editing-key conflict to resolve within that work.

## 3. Make settings outcomes explicit

### F06 — Language changes from Pause can fail to save without explaining that failure

The Settings page promises **“Language is saved immediately.”** AppRoot changes the live locale and attempts to save, but sends the visible error only to Home. During flight, Home is absent.

The relevant code is [`set_language()`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/app_root.gd#L616) and [the Settings language row](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/settings_screen.gd#L459).

I reproduced this in the paused application using a newer-schema fixture loaded through the production preferences loader:

- The loader returned `writable = false`.
- Selecting Español changed the live locale to `es`.
- Settings retained the translated immediate-save promise and generic preview status.
- No save-failure message appeared.
- The file remained byte-for-byte unchanged.
- Reloading it still returned `en`.

The protected fixture was installed during the isolated run; I did not relaunch the whole app to establish that fixture.

**Recommended change:** return the persistence outcome to the active screen. Represent “accepted,” “applied for this session,” and “saved” separately. A suitable failure message is:

> Language changed for this session. Your settings could not be saved.

Add a useful reason and Retry when retry is possible. Display the message in the newly selected language. Preserve the existing protection against overwriting newer settings files.

Godot’s `ConfigFile` distinguishes in-memory changes from explicit saving and returns an error from save operations. That distinction should remain visible all the way to the player. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_configfile.html?utm_source=chatgpt.com)

**Acceptance:** exercise both a protected file and an unwritable destination. The active language changes, the active screen explains that saving failed, and the original file survives. A successful later save clears the stale error.

This is a specific missing-error path, not a re-report of the broader mixed-transaction model.

## 4. Close the new accessibility gaps

These three findings are supported by source inspection. Actual assistive-technology output still needs testing.

### F07 — Startup does not honor saved text size

Startup reads language and reduced motion, but does not restore the saved display `ui_scale`. BrandIntro draws its status and Skip prompt using viewport-fit font sizes rather than the player’s text-size preference. Those strings are also custom-drawn rather than represented by semantic status and action controls.

See [`startup.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/startup.gd#L206) and [`brand_intro.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/brand_intro.gd#L94).

**Recommended change:** retain the branded artwork, but use lightweight semantic controls for status and Skip. Read the validated saved text scale without pulling the heavy application dependency graph into startup.

The existing skip inputs and reduced-motion behavior should remain. In particular, the input that skips the intro must not also activate Fly after handoff.

**Acceptance:** native launches at saved 100% and 200% text, English/Spanish and a CJK locale, reduced motion on/off, meaningful loading/error announcements, and keyboard/gamepad Skip.

### F08 — Instrument explanations are available through mouse hover

The overlay dialog contains useful descriptions, including interpretation and availability conditions for newer instruments. It assigns them to checkbox tooltips, without a corresponding visible focus-help region. See [`overlays_dialog.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/overlays_dialog.gd#L43).

A sighted keyboard/gamepad user can reach and toggle an instrument without seeing the explanation available to a mouse user. Godot documents the standard tooltip around the pointer resting over a control. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_control.html?utm_source=chatgpt.com)

**Recommended change:** provide a wrapped description area that follows focus and hover. Include what the instrument measures and when its values are meaningful. Reuse the localized explanation as an accessibility description where appropriate.

**Acceptance:** discover each instrument’s purpose and limitations without moving a mouse, including at 200% text.

The earlier aircraft-catalog tooltip finding concerns another surface; this is the instrument-selector case.

### F09 — Arrow key graphics need text equivalents

Help’s arrow keycaps draw directional triangles in a custom Control without providing their directional meaning as text or an accessibility name. The project already has localized arrow-key names that could supply it.

See [`key_cap.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/key_cap.gd#L12) and [`key_labels.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/key_labels.gd#L10).

**Recommended change:** preserve the vector graphics and provide localized semantic names, or expose each action row as one coherent instruction—for example, “Roll left: Left arrow.” Avoid duplicate announcements.

**Acceptance:** inspect the accessibility tree and listen to the four directions with their actions. Check translated labels and changed keyboard layouts.

Godot’s accessibility guidance specifically recommends meaningful names/descriptions and testing with actual target-platform screen readers such as NVDA, VoiceOver, and Orca. A debug snapshot alone does not establish a usable reading experience. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/creating_applications.html?utm_source=chatgpt.com)

## 5. Visual presentation, loading, and transitions

### Preserve and finish the existing visual direction

The retained Home and Workshop captures show a coherent graphite/lime treatment, a recognizable primary action, and a useful separation between navigation, preview, and editing. Their provenance is documented in [the media capture records](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/docs/media/readme-gameplay.json). They predate the reviewed build, so they support design context rather than current-build visual conclusions.

For the next native sign-off, I would inspect the complete state set of each important control:

| State or condition | What needs to be clear |
|---|---|
| Focus and selection together | The player can distinguish the current value/category from the action their next input will operate |
| Hover and pressed | The control responds immediately without moving its label or destabilizing layout |
| Disabled | The unavailable action remains understandable; the reason is discoverable where needed |
| Pending, applied, saved, or failed | The visible message matches the actual configuration state |
| 200% text and long translations | Labels, explanations, and actions remain reachable and correctly grouped |
| Bright/dark scenery and opaque mode | Text and focus remain legible against the real backdrop |

These are acceptance checks, not a claim that every state is currently broken. Broad typography, modal-shell consistency, overlay scaling, and theme-refresh work already exist in the prior audit and should retain their current owners.

Use the project’s documented **1080p primary target**, larger resolutions next, and 720p fallback. Continue using containers, sizing flags, and theme variations for responsive structure; avoid fixes that depend on one language’s text width. Godot’s layout and theming documentation supports that approach. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/ui/gui_containers.html?utm_source=chatgpt.com)

### Loading already has substantial implementation

The current code provides loading stages, cancellation, first-frame checkpoints, and Home-side preparation. Relevant owners include [`flight_loading.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/flight_loading.gd), [`flight_scene_load.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/flight_scene_load.gd), and [`home_flight_preparation.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/e72d878b6b4a89209dfe1a992ba119921dcdd34c/app/ui/home_flight_preparation.gd).

The important remaining evaluation is whether feedback remains responsive through the expensive phases on native hardware. Measure separately:

- Input-to-visible-feedback latency.
- The longest uninterrupted main-thread segment.
- Time to a genuinely rendered ready frame.
- Cancellation acknowledgement and completion.
- Cold versus warm loading conditions.

Resource loading, scene construction, world preparation, and drawing the first usable frame are different milestones. Godot warns that `load_threaded_get()` can still block when called before loading completes. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/io/background_loading.html?utm_source=chatgpt.com)

The project’s dedicated worker has documented history behind it. I would retain that design until an alternative demonstrates equivalent lifetime, cancellation, and pinned-engine behavior. Moving arbitrary active scene-tree work onto a worker is also inappropriate; Godot’s thread-safety rules require more selective ownership. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html?utm_source=chatgpt.com)

### Preserve transition ownership

Startup already uses an owned Tween and temporarily disables the new application’s processing during handoff. Extend that arrangement carefully when adding semantic Skip/status controls.

Godot’s node-bound Tween lifetime is useful here: binding ties animation lifetime to its owner, including termination when that owner is freed. Preserve that ownership and the input-consumption boundary across the transition. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_tween.html?utm_source=chatgpt.com)

### One bounded performance opportunity: frozen intro redraws

In `brand_intro.gd`, `seek()` stops playback, but `_process()` continues refreshing shader parameters and requesting redraws.

When reduced motion or handoff freezes the intro, processing could stop until a relevant change invalidates it. **That requires an explicit `status_text` setter or signal**: simply stopping processing would otherwise leave loading or failure messages stale.

Godot caches custom drawing until redraw is requested, making event-driven invalidation a concrete optimization mechanism. No CPU, GPU, frame-time, or battery improvement was measured here, so this remains a low-priority profiling candidate. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/2d/custom_drawing_in_2d.html?utm_source=chatgpt.com)

## 6. Recommended implementation sequence

| Sequence | Work | Required result |
|---|---|---|
| **1. Preserve choices** | F01, F03, R01 | New profiles have new identities; session edits respect persistence scope; wind-only presets preserve atmosphere |
| **2. Preserve control** | F02, F04, F05 | Dynamic changes leave valid focus; Help is fully readable; editing keys remain editing keys |
| **3. Explain outcomes and meaning** | F06–F09 | Saving failures are visible; startup honors accessibility preferences; descriptions and symbols work across input methods |
| **4. Complete native acceptance** | Existing visual/loading gates plus these repairs | Corrected behavior is demonstrated with real devices, native rendering, large text, translations, and screen readers |

The regression checks should verify **the player-visible result and the stored data separately**. An updated picker is not proof that the correct profile was saved. A successful bridge command is not proof that the engine logged no error. Restoring a screen is not proof that it has a usable focus target.

For release acceptance, the decisive journey is: launch with saved accessibility preferences, configure a controller, change conditions without disturbing unrelated choices, read Help with that controller, start a flight with responsive feedback, recover input while paused, edit session options without changing normal defaults, and restart or exit with an accurate understanding of what was saved.