# UI-30 — menu system audit at 1080p and above

2026-10-20, source `9a55ea7a`. This is a visual and functional audit of Home, the aircraft catalog, Settings, Controls, Conditions, Help, Practice, Workshop entry, Pause, in-flight menu states, the helicopter route and the RC garage. It covers 1920×1080 through 5120×1440. It builds on [UI-29-R3](../UI-29-R3/README.md); current code supersedes this snapshot. The repair steps live in the [active redesign plan](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs).

## 1. Verdict

The shell is technically sound. Its scaling, input isolation, pause freeze and focus restoration all work at every resolution tested. The menus look coherent, and Home shows the aircraft well.

The remaining problems are in **flows and in using the space**, not in the visual style:

- **Space.** Dense content is squeezed into a 320-pixel rail or a 720p-sized dialog while most of the screen stays empty. The catalog, flight details and Flight conditions all scroll at 1080p and 4K.
- **Interaction.** Rows that look identical cycle a value, open a dialog or rebuild the scene. Several user choices are silently overwritten.
- **Aircraft switching.** Changing aircraft mid-flight takes six steps through a collapsed group, and Pause never says which aircraft is flying.
- **Recovery dead ends.** One Critical and several High findings leave the user frozen or pointed at a hidden control: radio calibration, controller recovery and Workshop trials.
- **Two UI systems.** The flight overlays, accident report, garage dashboard and several dialogs sit outside the shared screen stack, theme and text scale.

| Severity | Meaning | Count |
| --- | --- | ---: |
| Critical | A supported task cannot be completed or the user is stuck without visible recovery | 1 |
| High | A core flow is confusing, lossy or much longer than needed, or a stated accessibility gate is missed | 7 |
| Medium | An inconsistency or extra step with a workaround | 33 |
| Low | Polish | 21 |

No redesign is proposed. The Home composition, theme tokens, canvas policy and screen stack stay. The fixes are bounded flow, layout and consistency repairs.

## 2. Method and coverage

**Captures.** [`audit.gd`](audit.gd) drives the production `app_root.tscn` with isolated preferences and real key events (`tests/ui_driver.gd`). It is one process per case, under Xvfb at the stated screen size. Each capture records:

- logical canvas, focus owner and visible-control rectangles;
- a count of unscrolled controls outside the viewport;
- per-case timings.

It also measures simulation ticks while paused. [`metrics.json`](metrics.json) summarizes every capture.

| Physical pixels | Aspect | Logical canvas | Language, text | Set |
| --- | --- | --- | --- | --- |
| 1920×1080 | 16:9 | 1920×1080 | EN 100% | Full: all screens, Pause branches, restart, catalog sweep, helicopter, garage |
| 1920×1080 | 16:9 | 1920×1080 | ES 100%, EN 150% | Core |
| 1920×1080 | 16:9 | 1920×1080 | EN, first run | First-flight route |
| 1920×1200 | 16:10 | 1920×1200 | EN 100% | Core |
| 2560×1440 | 16:9 | 1920×1080 | EN 100% | Core |
| 3840×2160 | 16:9 | 1920×1080 | EN 100% | Core |
| 2560×1080 | 21:9 | 2560×1080 | EN 100% | Core |
| 3440×1440 | 21:9 | 2580×1080 | EN 100% | Core |
| 5120×1440 | 32:9 | 3840×1080 | EN 100% | Core |

"Core" means Home and its four pages, Settings, Help, Controls, Conditions, Workshop, flight, Pause, the expanded groups, Settings/Help/Controls over Pause, and End flight.

**Limits:**

- **Renderer.** This VM has no GPU, so rendering is Mesa llvmpipe.
  - The 3D backdrop renders at `scaling_3d_scale = 0.5`; the interface renders at native resolution.
  - The 1080p Home/Settings/Help/Controls/Conditions reference frames used full 3D scale.
  - No timing here is a performance result.
- **Window.** Xvfb has no window manager, so the "fullscreen" cases use an undecorated window that covers the whole screen. The window size and the logical canvas match a fullscreen run.
- **Cross-check.** The UI-29-R3 Windows/RTX 3090 4K captures provide native GPU evidence for the same layouts.
- **Not covered:**
  - Physical radios and gamepads, Windows DPI and human users were not available.
  - The accident report card was assessed from code only, not from a staged crash.

**Code review.** Three delegated read-only reviews covered pause logic, selection/switching and theme/scaling/chrome. A direct review covered Home, Settings, Help and the capture results, and re-checked every Critical and High claim. Claims marked **[V]** were checked in the current source; **[I]** are inferences that need a runtime check. File references are `app/`-relative `path:line` at `9a55ea7a`.

**Regression state.** `test_ui_home.gd` (242 checks), `test_ui_pause.gd` (73) and `test_ui_screen_stack.gd` (38) pass headless on the audited source.

## 3. Scorecard

| Area | State | Summary |
| --- | --- | --- |
| Scaling and resolution | Good | One 1920×1080 logical canvas. 1440p and 4K are pixel-proportional copies of 1080p (rail mean difference 1.5–2/255 after downsampling). No control falls outside the viewport in any case. Wider aspects add scene, not text width. |
| Home composition | Good / Fair | Grounded aircraft, readable field, one primary action, Fly focused on arrival. The brand cluster and summary rows are untidy, and the details live in a scrolling rail. |
| Space use for dense content | Weak | Catalog, details and Flight conditions scroll inside small containers while 60–75% of the screen is decorative. |
| Interaction model | Weak | Identical-looking rows cycle, open a dialog or rebuild the world. Pause groups flatten into an 11-item list. |
| Aircraft selection and switching | Fair / Weak | Fast single-step selection and a correct preview race model. But the entries carry no information, there is no switch from Pause, and saved settings are lost. |
| Pause and in-flight states | Fair | The freeze is correct (0 ticks while paused, including under nested screens). Recovery states have dead ends, and Pause shows no identity. |
| Consistency (chrome, terms, theme) | Fair | Shared tokens and focus outline. Four close/commit patterns, four tab styles, untranslated or ad-hoc surfaces, and five names for "conditions". |
| Accessibility | Fair | Contrast tokens pass, and reduced motion and opaque panels exist. In-flight text is 11–17 logical px and ignores text size; disabled states rely on text colour alone. |

## 4. Findings

Each row gives the evidence, the impact and the smallest fix. Plan step IDs refer to [§11 of the redesign plan](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs).

### 4.1 Screen space and scaling

Matrix results. Across all 176 geometry-tracked captures in [metrics.json](metrics.json), zero controls fell outside the viewport.

| Canvas (physical → logical) | Result |
| --- | --- |
| 1920×1080 → 1920×1080 | Reference. Default Home, Settings and Pause have no scrollbar, except Home with the helicopter selected (SP-7). Catalog, details and dialogs scroll (SP-1–3). |
| 1920×1200 → 1920×1200 | Same layout; the extra height becomes a gap above FLY. The catalog still scrolls. |
| 2560×1440, 3840×2160 → 1920×1080 | Proportional copies of 1080p (rail mean difference 1.5–2/255 after downsampling); text is crisp. [4K Home](captures/en-3840x2160-100-home.webp) |
| 2560×1080 → 2560×1080; 3440×1440 → 2580×1080 | More scene; the rail and dialogs keep their size. [21:9 Home](captures/en-3440x1440-100-home.webp) |
| 5120×1440 → 3840×1080 | No defects; menus sit at the screen edges (SP-5). |
| 1920×1080 ES | Pause rows wrap to two lines; landscape names are untranslated and a Conditions tab is hidden (AL-5). |
| 1920×1080 EN 150% text | Pause fits; Home and the catalog scroll early (SP-8); flight overlays do not scale (SP-4). |


| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| SP-1 | High | The Aircraft page is a list inside the 320 px rail at every resolution. At 1080p and 4K, 4½ of 9 entries are visible and the list scrolls, with the last row clipped under FLY. Each entry spends two lines on name + status. Width to the right is unused. [1080p](captures/en-1920x1080-100-aircraft.webp), [4K](captures/en-3840x2160-100-aircraft.webp). `ui/home.gd:419-459` [V] | Comparing aircraft means scrolling a narrow column. The fleet will grow. | At logical ≥1500×850, show the catalog as a wide panel: rows with name, one-line summary and status chip, plus a selected-aircraft card. Keep the preview visible. Compact layout keeps the rail list. UI-34. |
| SP-2 | Medium | "More flight details" expands inside the rail and scrolls under the pinned FLY; only one line of the details is visible. [1080p](captures/en-1920x1080-100-home-details.webp) [V] | Specifications and limitations are effectively hidden. | Show the details as a card in the scene area (anchored to the preview), not inside the rail. UI-34. |
| SP-3 | Medium | Dialogs are sized for 720p and scroll at 1080p+. Flight conditions is 960×634 logical: its sixth slider row is cut while about 40% of the screen height is unused. Settings is 800 wide with a mostly empty body; Controls 1160; Help 1200. [Conditions](captures/en-1920x1080-100-weather.webp), [Settings](captures/en-1920x1080-100-settings-display.webp) [V] | Avoidable scrolling, inconsistent sizes, wasted space at 1080p+. | Two or three modal width classes and height-to-content up to ~88% of logical height, from a shared modal shell. UI-35. |
| SP-4 | High | In-flight text bypasses the shell's text scale and compact factor (owner: HUD/CR/RCV) [V]: overlays 13/14/20 px (`render/overlays/overlay_frame.gd:11-13`), diagnostics and input panel 13 px, HUD 17 px (`render/hud.gd:13`), garage 14–28 px. The captured control guide is 11–13 logical px, with key labels at 12 px. The accident report clamps text scale to 0.8–1.5 (`ui/accident_report.gd:986-990`). [Flight](captures/en-1920x1080-100-flight-hud.webp) | 11–14 px essential text at 1080p is below the plan's ~18 px target; 150–200% text never reaches flight. | Route these sizes through `UiTheme` with the full text scale; keep overlay geometry bounded. UI-37 with HUD. |
| SP-5 | Low | Ultrawide works without defects: at 3440×1440 (logical 2580) and 5120×1440 (logical 3840) the extra width becomes scene, and the aircraft stays framed. At 32:9, however, the Home rail, the Pause sidebar and the Language/Settings header sit at the extreme left and right edges, about 3,700 logical px apart, while dialogs stay centred at 720p size. [3440 Home](captures/en-3440x1440-100-home.webp), [5120 Home](captures/en-5120x1440-100-home.webp), [5120 Pause](captures/en-5120x1440-100-pause.webp) | On a 49-inch 32:9 monitor, menus sit in peripheral vision; head movement is needed between the rail and the header. | Optional centred UI safe area (for example 2560 logical wide) for canvases wider than 21:9; the scene still fills the screen. UI-35. |
| SP-6 | Low | `--vehicle` and direct-flight routes return before `UiScale.apply` (`app_root.gd:171-195`) [V], so technical captures show half-size HUDs at 4K. | Misleading evidence only. | Apply the canvas policy on every route. UI-37. |
| SP-7 | Medium | With the helicopter selected, the **default Flight page scrolls** at 1080p (`HomeContentScroll` scrollbar visible); 1440p and 4K share that 1920×1080 canvas. The three-line name card ("RC Helicopter Research Trainer") pushes the summary under FLY, breaking the plan's no-scroll gate for Home. When the catalog scrolls, its rows are cut mid-text directly under the navigation, with no fade. [Helicopter Home](captures/en-1920x1080-100-home-heli.webp), [catalog](captures/en-1920x1080-100-aircraft-p51d-mustang-120.webp) | Home's key summary is hidden for one of nine aircraft; the clipped rows look broken. | Use the catalog short name on the card (AS-9); fade the edges of the scroll viewport; add a Home-fit test per catalog entry. UI-34. |
| SP-8 | Medium | At 150% text on 1080p the rail widens to its large-text width (`min(48% of the width, 500)` logical px, `ui/home.gd:806`), but the Flight page still scrolls after Landscape and Conditions: Time of day, input and details sit below FLY. The catalog shows about 1½ entries. In flight, the overlays stay at 11–14 px while the archived-report button grows with the text setting (SP-4, VC-6). Pause fits. *Corrected 2026-10-20: the first version said the rail keeps its width; a half-scale contact sheet was misread.* [150% Home](captures/en-1920x1080-150-home.webp), [150% catalog](captures/en-1920x1080-150-aircraft.webp), [150% flight](captures/en-1920x1080-150-flight-hud.webp) | Players who need larger text lose Home's summary first, although the screen has room beyond the rail. | At large text, move the details and catalog information into a card in the scene area (SP-1, SP-2) and use the paired conditions row before scrolling. UI-34. |

### 4.2 Visual hierarchy and consistency

| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| VC-1 | Medium | There is no shared modal frame (`ui/screen.gd` gives dim/centre/fade only) [V], so close and commit differ by screen. Close sits in the header for Settings, Help and Controls; Cancel/Apply in the footer for Conditions, Time and Failures; Back is last in Natural Random's button stack; Workshop says "Back to Pause". Controls shows both Close and Cancel for the same action (`ui/controller_setup.gd:222,715`); Settings shows Close + Revert + Keep changes; Conditions' Apply is not a primary button (`ui/weather_dialog.gd:299-304`). [Controls](captures/en-1920x1080-100-controls.webp) | Users relearn each dialog; Close sometimes means Cancel. | One modal shell: title left, one dismiss control, actions bottom-right with the primary last. UI-35. |
| VC-2 | Medium | Tabs come in four styles: Settings text tabs, Controls boxed buttons, Conditions `TabBar`, Workshop small boxed tabs. Titles run 28–38 px, and three are in capitals (PAUSED, FAILURES · NEXT FLIGHT, ACCIDENT REPORT) while the rest use sentence case. Four panel styles and seven dim values. [V] | The shell looks assembled rather than designed as one system. | Shared tab, title and panel variations in `ui_theme.gd`. UI-35. |
| VC-3 | Medium | Unthemed control states: slider focus, CheckBox/CheckButton icons, SpinBox, ScrollBar and native dialogs fall back to Godot defaults (`ui/ui_theme.gd:192-231`) [V]. That gives three toggle looks. The slider knob's red centre uses the colour reserved for errors (`ui/slider_grabber.svg`). | Focus visibility and state language are inconsistent; plan §5 requires these states. | Theme the missing states and remove Weather's slider overrides (`ui/weather_dialog.gd:913-940`). UI-35. |
| VC-4 | Medium | Pause disclosure groups have no chevron or indentation. Expanded Session options flattens into an 11-item list, with Settings after Flight overlays and a next-flight item inside a current-session group. [Expanded](captures/en-1920x1080-100-pause-session.webp) | Hierarchy is lost and items are hard to find. | Indented sub-items with chevrons; order the menu as current session · next flight · application. UI-33. |
| VC-5 | Medium | Error text uses four colours (ERROR token, two raw oranges, plain body text in Conditions), and the Controls status shows errors by colour alone. [V] | Errors are missed, especially in Conditions. | One error label variation with an icon or prefix. UI-35. |
| VC-6 | Medium | Any earlier crash archive makes every new flight show a 52 px **primary-styled** "View archived accident report" button at bottom centre (`main.gd:775-777`, `ui/accident_report.gd:349-354,383-385`) [V]. Both it and the first-flight hint are anchored bottom-centre, so it covers part of the hint's key row. [Flight](captures/en-1920x1080-100-flight-hud.webp), [first flight](captures/en-1920x1080-100-firstrun-after-fly.webp) | The flight's most prominent control belongs to an old session, sits next to the runway view and hides onboarding. | Quiet style in a corner, and only after a crash in this session (or from Pause). UI-37 with CR. |
| VC-7 | Medium | The helicopter flight draws a monospace developer text block: model identity, the key list and the arming instructions as one debug paragraph (`render/hud.gd:13`, `helicopter_main.gd:172`). It has none of the airplane's overlay panels (flight data, wind, transmitter, control guide), and Pause still shows "Next flight failures: Off". [Helicopter flight](captures/en-1920x1080-100-heli-flight.webp), [Pause](captures/en-1920x1080-100-heli-pause.webp) [V] | The two aircraft classes feel like different products; the arming steps read as debug output. | Use the overlay framework for rotorcraft with an arming-steps warning panel (HELI/HUD own the content). UI-37. |
| VC-8 | Low | The brand cluster wraps "development build" into two lines beside the ALPHA badge at every size. [Home](captures/en-1920x1080-100-home.webp) | Visual noise at the top of Home. | Keep the small ALPHA badge; move the build identity to Help/About. UI-33. |
| VC-9 | Low | Disabled buttons differ from enabled ones only by text colour (background contrast 1.04:1, `ui/ui_theme.gd:13-16`) [V]. Keep changes and Revert look the same whether or not there is anything to keep. | Unclear state. | Disabled background and edge tokens. UI-35. |
| VC-10 | Low | Workshop preview toolbar text is about 11–12 px; the Workshop title is 28 px against 38 elsewhere. [Workshop over Pause](captures/en-1920x1080-100-pause-session-workshop.webp) | Small targets and inconsistent hierarchy. | Shared title and small-button variations (AE owns layout). UI-35. |

### 4.3 Home structure and navigation

| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| HN-1 | High | Summary rows look identical but behave differently, and none shows an arrow or chevron (`ui/home.gd:195-202,301-344`) [V]. **Start**, **Time of day** and **Language** cycle a value; **Weather** opens a dialog; **Landscape** cycles, saves and rebuilds the backdrop, and on Green Paradise it also forces airborne starts. [Home](captures/en-1920x1080-100-home.webp) | Users cannot predict a click. A stray click on Landscape rebuilds the world and can silently change the start method. | One row pattern: label, value, and an explicit affordance. ‹ › for cyclers; › with "opens" semantics for dialogs. Landscape changes show their consequence ("airborne start only"). UI-33. |
| HN-2 | Medium | Workshop sits in the page navigation, but it opens a full-screen editor, not a page (`ui/home.gd:233-238`) [V]. RC garage is a page whose primary action replaces FLY, yet the backdrop keeps showing the selected airplane. [Garage](captures/en-1920x1080-100-garage.webp) | The navigation model is mixed; the garage looks like an airplane screen. | Separate the "pages" from the "open editor" action (divider and → glyph). Show the garage's own vehicle, or a neutral pits shot, when that page is selected. UI-33. |
| HN-3 | Medium | FLY stays visible on the Aircraft and Practice pages. On Practice it flies the prepared flight, not a practice activity, while Natural Random's briefing has its own FLY. [Practice](captures/en-1920x1080-100-practice.webp) | Two different "FLY" meanings one screen apart. | Label the pinned action with its object ("Fly Ugly Stick"), or hide it on Practice. UI-33. |
| HN-7 | Medium | Fly disables itself and emits `fly_requested` in the same frame (`ui/home.gd:1354-1359`). The flight world is then built synchronously, with no "preparing flight" state (`app_root.gd:511`) [V]. Fly → first flight frame took 26–59 s under software rendering; the native time has not been measured. End flight → Home rebuilds the same way. | **[I]** Without a rendered acknowledgement, the press can look ignored and invite repeated input. | Render a lightweight "Preparing flight · aircraft · field" state first, then build on the next frame. Measure Fly→first-frame natively as a tracked metric. UI-34. |
| HN-4 | Low | Home Quit is next to Help, in the same quiet style, and closes the application immediately (`app_root.gd:1729-1736`) [V]. | Accidental exit and reload. | Separate the quit control (gap or group); confirm only when it costs work, matching the Pause exit. UI-33. |
| HN-5 | Low | Language appears twice: a header cycler ("Language: English") and a Settings dropdown ("Interface language"). | Two names, two behaviours. | Keep both, but use one label and make the header open the Interface page or a small popup. UI-33. |
| HN-6 | Low | Practice leaves about 400 px of the rail empty between its content and FLY; Natural Random and Failure practice render as centred plain text with no button affordance. [Practice](captures/en-1920x1080-100-practice.webp) | Looks unfinished; the actions are hard to identify. | Row variation with a description line. UI-33. |

### 4.4 Aircraft selection and switching

The selection model itself is good: Home opens on Flight with Fly focused (one step to fly the saved aircraft), the latest request wins, and no stale-preview race was found (`ui/home_scene.gd:200-235`, `app_root.gd:453-455`) [V].

| Flow | Steps now [V] | Target |
| --- | ---: | ---: |
| Fly the saved aircraft from start | 1 | 1 |
| Fly another aircraft from Home | 3 (Aircraft → entry → Fly), or 2–5 with arrows | 2–3 |
| Switch aircraft after a flight | 3 | 3 |
| Switch aircraft **mid-flight** | 6 (Esc → Exit options → End flight → Aircraft → entry → Fly) | 3 (Esc → Change aircraft → entry/Fly) |
| Fly a saved Workshop variant from Home | 6 (Workshop → Library → dropdown ×2 → Load → Test fly) | 3–4 |

| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| AS-1 | High | Pause has no aircraft change and no aircraft/field identity (`ui/pause_menu.gd:103-119`) [V]. End flight sits in the collapsed Exit options. | The most common mid-session change is the longest path. | Top-level **Change aircraft** in Pause: run the existing End-flight trace transaction, then open Home on the Aircraft page with the current entry focused. Add "Aircraft · field" to the Pause header. UI-34. |
| AS-2 | High | Entries show only name + capability. The summary and limitations are tooltip-only (`ui/home.gd:630-632`), contradicting the page text "limitations are shown on each entry" (`:427`). "Ugly Stick" and "Ugly Stick · MAX-61FX" look the same. [V] | Keyboard and gamepad users cannot read the differences. Choosing the right variant is guesswork. | One summary line per entry (class · span · power), a status chip, and the selected entry's note under the list. UI-34. |
| AS-3 | High | Selecting the helicopter clears the saved turbulence and saves it (`app_root.gd:270-275,428-440`). Returning to an airplane does not restore it. Previous from the default Stik wraps straight to the helicopter. [V] | One click silently destroys a user setting. | Keep airplane weather in preferences; strip turbulence only for rotorcraft display/launch. UI-32. |
| AS-4 | Medium | Battery mode and fuel fill live only in the Home instance (`ui/home.gd:72-77`). They are not saved, and they reset after every End flight and every application start. [V] | Repeated setup; launches differ from what the user set. | Persist per aircraft in preferences (schema-compatible, additive). UI-32. |
| AS-5 | Medium | Loading and failed preview states show only on the Flight card (`ui/home.gd:296-300,973-975`). On the Aircraft page the new entry highlights while the old model stays for up to ~1.6 s, or permanently on failure. [V] | Selection and preview disagree. | Show the same state text on the Aircraft page. UI-34. |
| AS-6 | Medium | There are two unsynchronised pickers: the Home catalog (9 entries with status) and the Workshop library (8 airplanes, saved builds). Saved builds never appear in the Home catalog. With the helicopter selected, Workshop and Natural Random are disabled, although Workshop has its own picker and Natural Random picks its own five airplanes (`ui/home.gd:958-962,1008-1012`; `scenarios/scenario_config.gd:16-22`). The reasons are tooltip-only. [V] | Dead ends, and no route from catalog to variant. | Enable both independent of the selection; list favourite saved builds under their base aircraft in the catalog ("Fly build" → existing trial route). UI-34. |
| AS-11 | Medium | The Natural Random briefing names the drawn aircraft (here "P-51D Mustang 1/4"), but the backdrop keeps showing Home's selection (Ugly Stick). The random route never requests a preview (`app_root.gd:940-1016`) [V]. [Briefing](captures/en-1920x1080-100-natural_random.webp) | The screen contradicts itself at the moment the user decides to fly. | Request the drawn aircraft's preview on briefing and reroll; restore Home's selection on Back. UI-34. |
| AS-7 | Low | Browsing rewrites the start choice: helicopter → runway, Green → airborne, saved immediately (`app_root.gd:431-437`), despite the comment "remembered only on a successful Fly" (`:458`). [V] | The airplane start the user chose is lost after browsing. | Store the start per vehicle class; resolve the effective start at launch. UI-32. |
| AS-8 | Low | Every selection parses and validates the aircraft JSON three times without a cache. Home is rebuilt after each flight, which drops the preview caches (`ui/home_preview_resources.gd:93-95`). [V] | Avoidable stalls on selection and after each flight. | Cache runway and fuel capability per ID; keep the preview broker across Home rebuilds. UI-34 with UI-05. |
| AS-9 | Low | Compact short names are hard-coded per ID in UI code (`ui/home.gd:644-649`). The helicopter appears as both "X-Cell .60 Trainer" and "RC Helicopter Research Trainer". [V] | The catalog does not own its names. | `short_name` in catalog entries. UI-34. |
| AS-10 | Low | Latent: a blocked (Preview only) aircraft disables FLY with no reason next to it (`ui/home.gd:652-660,946-948`). No current entry triggers it. [V] | Future dead end. | Reason line under FLY. UI-34. |

### 4.5 Pause and in-flight states

Verified behaviour to keep:

- Opening Pause stops simulation ticks: 0 ticks advanced over 1 s, and none while Settings, Controls or Help are open over Pause. Audio, smoke, wind, clouds and the clock freeze with simulation time.
- Held keys are masked on resume, and Enter does not leak into flight.
- Escape collapses an open group before it resumes.
- Trace-save failure recovery works.

Sources: `ui/screen_stack.gd:88-96`, `sim/flight_session.gd:924-929`, `app_root.gd:1743` [V]; audit log.

| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| PS-1 | **Critical** (radio) | Calibration is started from Controller settings ("Calibrate selected radio") or K. It closes all menus and runs in flight, but its prompts render only in the developer Diagnostics panel (`main.gd:1126-1130`), which the default Pilot overlay preset hides (`render/overlays/overlay_settings.gd:21`). No overlay shows calibration [V]. After the final keyboard Enter (`main.gd:1458`), the flight stays frozen with no menu; the result text sits in `pause_reason` (`sim/flight_session.gd:889-901`) [V]. Not reproduced with hardware. | Radio users cannot see what to do, and then face a frozen screen. | Show the calibration step as a modal Screen card (title, step, live axes, Esc cancel). Reopen Pause with the result when it finishes, from any input path. UI-31 with D6-GP. |
| PS-2 | High | When the controller is lost or not armed, Pause says "open Controller settings" (`ui/pause_menu.gd:384-388`), but that button is inside the collapsed Session options (`:146-148`). Continue only repeats the message (`app_root.gd:1658-1660`). [V] | The recovery path is hidden at the moment it is needed. | When not ready, show Controller settings as a top-level action under the status, and focus it. UI-31. |
| PS-3 | Medium | A Workshop trial attaches the controller but never runs the launch step that Home flights use (`app_root.gd:1274` vs `657`) [V]. **[I]** With a selected controller, the trial starts frozen with no menu. | A trial appears to hang; Esc recovers. | Call the same launch step after trial creation. UI-31. |
| PS-4 | Medium | Continue closes Pause before it checks other holds (`app_root.gd:1661-1662`). If smoke AUX assignment (layer 20, outside the stack) holds the session, the flight stays frozen with no menu. [V] | A frozen state with no explanation. | Check `can_resume` before popping; put smoke AUX on the screen stack. UI-31. |
| PS-5 | Medium | The Pause status block always shows "Next flight failures: Off", including for helicopter, trial and direct routes where it does not apply (`ui/pause_menu.gd:271-292`). It shows no aircraft, field, flight time or conditions. [Pause](captures/en-1920x1080-100-pause.webp) [V] | Irrelevant information takes the space reserved for identity. | Session identity line; failure summary only where failures apply. UI-33. |
| PS-6 | Medium | Wind/Conditions cannot be edited from Pause. Sky and lighting applies now and also saves for later flights (`app_root.gd:1381-1444`). [V] | Changing wind means End flight → Home → Weather → Fly (4+ steps). Two semantics sit side by side. | Conditions in Pause, staged and labelled "applies on Restart". Keep sky immediate and say so. UI-36 with M5-W. |
| PS-7 | Medium | Helicopter divergence: R calls `session.reset()` directly (`helicopter_main.gd:412`), bypassing the shared restart. The crash status says "R: restart" while Pause swallows R. P pauses with no menu (`:413-416`). [V] | Inconsistent recovery between vehicles. | Restart signal plus shared path; vehicle-neutral status text. UI-31 with HELI. |
| PS-8 | Medium | The garage is a third menu style (`vehicles/ground/ground_dashboard.gd`) [V]. It opens paused on a right-hand dashboard (Pause sits on the left). The dashboard has about 16 equal-weight centred buttons, with key hints inside the labels ("Recover · R", "Headlights on · L"). Its body scrolls with the last row cut, and the HUD uses shadowed text. It has no Settings, Help or Quit; its strings are hard-coded EN/ES outside `tr()`; it sits outside the screen stack; and Return to Home has no trace guard. [Garage](captures/en-1920x1080-100-garage-drive.webp) | Car users cannot change volume, language or quit. Spanish users get mixed copy. The activity looks like a different product. | Shared `PauseMenu` frame with a garage-specific options group, `tr()` and the same exit group. Vehicle tools go in grouped sections. UI-37 with RCV. |
| PS-9 | Medium | The accident report is not a Screen; it has its own scaling and no route Home (Esc → Exit options → End flight) (`ui/accident_report.gd:294-306`) [V]. | A three-step exit after a crash. | Add "Return to Home" to the card; mount it as a Screen. UI-37 with CR. |
| PS-10 | Low | The flight-log label is on CanvasLayer 25, above every menu (`main.gd:1958-1959`), and is not hidden with the overlays (`main.gd:1571-1583`) [V]. | Debug text over Pause and dialogs. | Hide it with the overlays or move it below layer 9. UI-31. |
| PS-11 | Low | A Restart whose trace save fails has no recovery dialog. The helicopter failure note prefix is not recognised (`ui/trace_recovery.gd:21-22`). [V] | A recording can be lost silently. | Same save check on Restart; one prefix. UI-31. |
| PS-12 | Low | Only `APP_FOCUS_OUT` pauses (`app_root.gd:1092-1095`); about 250 ms of flight continues after Alt+Tab on X11 ([research 24](../24-pausa-foco-entrada.md)). Closing the window, then choosing Stay after a failed save, resumes flight without Continue. [V] | Small unintended flight time. | Also handle window focus-out; return to Pause after Stay. UI-31. |

### 4.6 Settings, Controls, Conditions and Help

| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| SC-1 | Medium | Settings mixes transaction models: language saves immediately, other options preview with Keep/Revert, and Close also reverts ("Preview · Close to undo"). That is three exits for one draft. [Interface](captures/en-1920x1080-100-settings-interface.webp) [V] | Users cannot tell what is kept. | One model: Back keeps nothing unconfirmed and says so; Keep changes is the only commit; the display safety timer is unchanged. Treat language like the other options, or move it out of the draft. UI-36. |
| SC-2 | Medium | Display offers only Window mode and Text size. There is no 3D resolution scale, quality preset, frame cap/VSync, monitor or field of view, which matter at 1440p/4K. | High-resolution players cannot trade quality for frame rate. | Expose existing renderer settings only (DT/VQ/CAM own them); no placeholder controls. UI-36. |
| SC-3 | Medium | Controls is in three places with two names: the Home footer "Controls", the Settings › Interface link "Controls" and the Pause Session option "Controller settings". | Hard to find, and the names drift. | One name ("Controls"); Settings gets a Controls category that opens the same screen. UI-33/36. |
| SC-4 | Medium | Help is a flat key list that mixes player and developer keys (F5 reload data, F2/F3 developer overlays, F10/F11 flight log) with aircraft-specific keys (Stik smoke). The headings "WHILE FLYING" and "FLY" are nearly the same, and multi-line rows misalign their key caps. [Help](captures/en-1920x1080-100-help.webp) | The first-flight information is buried. | Sections: First flight · Controls · Radio setup · Developer (collapsed) · About; aircraft-specific keys only for the selected aircraft. UI-36. |
| SC-5 | Medium | Escape behaves differently: Conditions handles Escape before the focused field and discards the whole draft mid-typing (`ui/weather_dialog.gd:131`); Settings and Controls discard drafts on Escape without asking; Failures opens with Apply focused (`ui/failures_menu.gd:165`). [V] | Lost edits and accidental commits. | Escape order: field → popup → confirm discard if dirty → close. Initial focus on the first editable control. UI-35. |
| SC-6 | Low | Flight conditions always opens on preset "Custom", even when the weather equals the default "Gentle breeze" preset (`ui/weather_dialog.gd:307,454,499`) [V]. | First-time users believe they changed something. | Select the matching preset on open. UI-36. |
| SC-7 | Low | Units differ in one session: Home and Conditions use m/s, while the English HUD defaults to mph/ft ("auto by language"). Units can only be changed in Flight overlays. [Flight](captures/en-1920x1080-100-flight-hud.webp) | The same wind reads "1.5 m/s" and "4 mph". | One Units setting in Settings › Interface, used by menus and overlays. UI-36 with HUD. |
| SC-8 | Low | In Flight conditions the Wind preset selector and the wind intro ("Uniform wind and repeating gusts…") sit above every tab, including Atmosphere, Time of day and Sky & clouds. The Time tab exposes engineering terms ("Lighting model: Legacy daylight", "Time preset: Custom"). Every tab body scrolls inside about 330 px. [Tabs](captures/en-1920x1080-100-weather-tab3.webp) [V] | The page reads as wind-only; time/sky choices look technical. | Move the preset and intro into the Wind tab; player-facing names for lighting modes. UI-36 with TOD. |
| SC-9 | Low | The first flight shows the key guidance twice: the Control guide overlay (top-left, 11–13 px) and the first-flight hint card (bottom-centre). [First flight](captures/en-1920x1080-100-firstrun-after-fly.webp) [V] | A busy first frame; neither copy is readable at a glance. | One onboarding surface on the first flight: the hint, with larger key caps; the Control guide opens on request. UI-36 with HUD. |

### 4.7 Accessibility and language

| ID | Sev | Finding and evidence | Impact | Recommendation |
| --- | --- | --- | --- | --- |
| AL-1 | Medium | Terminology drifts for the same concepts; see the table below. [V] | Formative task "find Controls / change conditions" fails on naming. | One EN/ES glossary applied in one pass (Resume, Restart, Return to Home, Quit to desktop, Conditions, Controls, Workshop). UI-33. |
| AL-2 | Medium | The theme refresh reaches only `Screen` nodes (`app_root.gd:749-752`). The accident report, overlays, hint, smoke AUX and Workshop native dialogs keep a stale theme after text-size/opaque changes made over Pause. Overlay labels are translated once and never refreshed (`render/overlays/overlay_frame.gd:77`). [V] | Partial updates after a settings change in flight. | A refresh group for every themed surface; live `tr()` for overlays. UI-37. |
| AL-3 | Medium | Opaque panels does not reach the rail fade (0.92), overlays (0.84), the accident report or dims. [V] | The accessibility option is partial. | Route these opacities through the token. UI-35. |
| AL-4 | Low | Default focus follows four patterns (first field, primary, Close, Library); Settings and Help open on Close. [V] | Gamepad users start in unexpected places. | First category or first editable control; primary only on decision screens. UI-35. |
| AL-5 | Low | Spanish at 1080p: landscape names bypass `tr()` and have no `es.po` entry, so Home reads "Paisaje: Club field" (`ui/home.gd:1002`). Flight conditions' five tabs no longer fit, so "Cielo y nubes" hides behind tab-scroll arrows at 100% text. [ES Home](captures/es-1920x1080-100-home.webp), [ES Conditions](captures/es-1920x1080-100-weather.webp) [V] | Mixed-language Home; a hidden tab. | Translate catalog display names; size the Conditions dialog for the longest locale (SP-3). UI-33/35. |

Terminology:

| Concept | Current labels | Proposed EN · ES |
| --- | --- | --- |
| Resume flight | Continue; Resume trial | Resume · Continuar |
| Leave flight | End flight; Return to Home (garage); Back to Home / Back to Pause (Workshop) | Return to Home · Volver al inicio |
| Close app | Quit (Home, Pause, field error) | Quit to desktop · Salir al escritorio |
| Weather/time | Weather; Flight conditions; Sky and lighting; Time of day; Sky & clouds | Conditions · Condiciones (tabs keep Wind, Turbulence, Atmosphere, Time, Sky) |
| Input setup | Controls; Controller settings; Configuración del control | Controls · Controles |
| Editor | Workshop; Aircraft Workshop; Taller de aviones | Workshop · Taller |
| Help | Help; Help & About | Help · Ayuda |

### 4.8 Architectural causes

These explain why the inconsistencies keep recurring. They are not separate user-facing defects.

| ID | Cause | Effect |
| --- | --- | --- |
| AR-1 | `Screen` provides dim/centre/fade but no frame (title, close, scrolling body, action row). `Kind.SIDEBAR` and `Kind.MODAL` behave identically; `TOAST` is unused (`ui/screen.gd:10`). | VC-1/2, SP-3, SC-5 |
| AR-2 | `app_root.gd` keeps nine bespoke open guards and seven near-identical `close_*` functions, and writes already-translated text into self-translating buttons (`:1124`), which go stale after a language change. | AL-1, PS-4 |
| AR-3 | Six surfaces live outside the screen stack: accident report, smoke AUX, trace recovery, field error, Workshop native dialogs and the garage dashboard. | PS-4/8/9/10, AL-2 |
| AR-4 | Theme refresh is limited to `Screen` nodes; in-flight surfaces size their own fonts. | SP-4, AL-2 |

## 5. Strengths to preserve

- **Canvas policy.** 1440p and 4K reproduce the 1080p composition exactly; text is crisp at 4K, and no case placed a control outside the viewport ([4K Home](captures/en-3840x2160-100-home.webp)).
- **Home.** Selected aircraft parked on the field, one primary action, Fly focused on arrival and after each flight, and selection by explicit press only.
- **Pause.** The real frozen pilot view, a dominant Continue, collapse-before-resume Escape, frozen ticks under nested screens, and the trace-save recovery dialog.
- **Shared screen stack.** Named holds, top-only input, focus restoration, and logical/physical Escape.
- **Tests.** The regression suite uses real input events (242/73/38 checks on the audited source).

## 6. Reproduction

From the repository root, with Xvfb and the pinned Godot (`app/get-godot.sh`):

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" "$(app/get-godot.sh)" --path app --rendering-driver opengl3 \
  --audio-driver Dummy --script "$PWD/docs/research/menu-investigations/UI-30/audit.gd" -- \
  --size=1920x1080 --lang=en --text=1.0 --set=core --out="$PWD/tmp/ui30"
```

Arguments:

- `--set`:
  - `core` — Home pages, dialogs, flight and Pause branches;
  - `full` — all of the following;
  - `homerest` — remaining Home dialogs;
  - `flightfull` — every Pause child, restart, End flight;
  - `switching` — catalog sweep, helicopter, garage;
  - `firstrun` — first-flight hint.
- `--size` must match the Xvfb screen size.
- `--scale3d` sets the 3D backdrop scale; it defaults to 0.5 for software rendering. Use 1.0 on a GPU host.

Outputs are PNGs plus per-set geometry and timing JSON. Under llvmpipe each capture takes about 20–40 s at half 3D scale, and each case starts with 1–2 minutes of world loading. [`captures/`](captures/) holds a lossy WebP (quality 82) selection; [metrics.json](metrics.json) lists every capture, committed or not, with its canvas, focus, scrollbars and smallest font.

Other committed frames: [en-2560x1440 home](captures/en-2560x1440-100-home.webp), [en-2560x1080 home](captures/en-2560x1080-100-home.webp), [en-1920x1200 home](captures/en-1920x1200-100-home.webp), [en-1920x1200 aircraft](captures/en-1920x1200-100-aircraft.webp), [en-3840x2160 pause](captures/en-3840x2160-100-pause.webp), [en-3840x2160 weather](captures/en-3840x2160-100-weather.webp), [es-1920x1080 pause-session](captures/es-1920x1080-100-pause-session.webp), [es-1920x1080 settings-display](captures/es-1920x1080-100-settings-display.webp), [en-1920x1080 pause-exit](captures/en-1920x1080-100-pause-exit.webp), [en-1920x1080 pause-session-failures](captures/en-1920x1080-100-pause-session-failures.webp), [en-1920x1080 pause-session-overlays](captures/en-1920x1080-100-pause-session-overlays.webp), [en-1920x1080 pause-session-timeofday](captures/en-1920x1080-100-pause-session-timeofday.webp), [en-1920x1080 home-after-flight](captures/en-1920x1080-100-home-after-flight.webp), [en-1920x1080 150% pause-session](captures/en-1920x1080-150-pause-session.webp).
