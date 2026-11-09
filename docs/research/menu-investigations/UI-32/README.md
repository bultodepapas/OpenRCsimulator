# UI-32 — preserve choices

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings AS-3, AS-4, AS-7 and F8. It follows the [redesign plan §11](../../../plans/menu-redesign.md#11-ui-30-audit-repairs). The rule it enforces: browsing never overwrites a saved choice as a side effect.

## Behaviour

| Finding | Change |
| --- | --- |
| AS-3 | Selecting the helicopter no longer rewrites the saved weather. Home and the Conditions dialog show it without turbulence (`app_root.weather_for_aircraft`), and the helicopter flight is launched without it. The saved airplane turbulence survives selection, Home rebuilds, helicopter flights and wind edits made while the helicopter is selected (`_weather_keeping_saved_turbulence`). |
| AS-4 | Battery mode and fuel fill are saved after a successful Fly. They survive End flight and an application restart. |
| AS-7 | Home keeps one start per vehicle class. The airplane start is the existing `start_choice`; the rotorcraft pad or hover start is new. Browsing the helicopter or a runway-less landscape only limits what is shown and launched; returning restores the remembered start. |
| F8 | Selecting an aircraft or landscape keeps Home's note (a failure debrief or a launch rejection). Only a failed save writes a note, and a later successful save clears only that note. |

**Preferences.** The new `[flight]` keys are additive and need no schema change, like `landscape`: `rotorcraft_start_choice` (`runway`/`airborne`), `battery_mode` (`ideal`/`pack`) and `fuel_fill` (one of `Preferences.FUEL_FILLS`; Home now reads that constant). Older files load with the defaults. Saving refuses invalid values.

## Proof

[`test_ui_preserved_choices.gd`](../../../../app/tests/test_ui_preserved_choices.gd) is new.
- Before the change it reported 7 failures, then stopped at a script error (the preference did not exist).
- After the change all 18 checks pass. They cover turbulence round trips, starts per class, landscape round trips, the note, and battery/fuel across End flight and an application restart.

Three [`test_ui_home.gd`](../../../../app/tests/test_ui_home.gd) checks encoded the lossy contract (saved weather equal to the stripped helicopter weather). They now assert the opposite: the display is stripped and the saved turbulence is kept.

Regression runs:

| Suite | Result |
| --- | --- |
| `test_ui_home` | 242 ok |
| `test_ui_aircraft` | 65 ok |
| `test_ui_battery_mode` | pass |
| `test_ui_home_start_layout` | pass |
| `test_ui_language` | 26 ok |
| `test_ui_weather` | pass |
| `test_landscapes` | pass |
| `test_ui_natural_random` | pass |
| `test_settings_ui` | pass |
| `test_ui_home_layout` | pass |

**Limits.** Only the Home route is covered. Direct technical routes still use defaults and never read preferences.

## Wind preset scope (UI-32-R1, 2026-11-06)

External audit **A11 R01** reproduced a wind preset replacing custom air at
1,500 m / 35 °C with reference air. Wind-only selections now replace wind,
gusts and turbulence while retaining the atmosphere source values, mode,
pending text and edit baselines. Invalid air remains visible and blocks Apply.
This includes spatial wind transitions and the altitude-dependent standard
column; untouched atmosphere values retain their source float64 precision.

The catalog explicitly marks **Hot and high**, **Cool dense air** and
**Standard dry ISA column** as composite presets. Their picker captions disclose
**Wind + Atmosphere**, using existing translations. They replace both domains,
including an unfinished atmosphere draft. The picker is labeled **Conditions**;
a combination that differs from every complete authored preset reopens as
**Custom**. CLI/scenario preset configurations and physics equations are unchanged.

The production regression drives actual popup selection, text entry and
Apply/Cancel controls. It covers every wind-only preset against custom and
standard-column air, pending mode/value changes, invalid text, legacy schema
preservation, spatial transitions, composite replacement and Home persistence.
Both atmosphere modes survive Apply, preference reload and reopening; Cancel
preserves the accepted in-memory configuration and exact preference-file bytes.
Persistence checks compare against the serialized input actually loaded by Home.

[Source identities and checked receipts](preset-scope-20261106/verification.json)
retain the identical regression before (**98 failures / 258 checks**) and after
(**258 passing checks**), with zero engine errors or warnings. The final focused
selection passes **664 checks across seven suites**:

| Suite | Passing checks |
| --- | ---: |
| `test_weather_preset_scope` | 258 |
| `test_ui_weather` | 67 |
| `test_ui_atmosphere` | 47 |
| `test_ui_spatial_weather` | 64 |
| `test_ui_preserved_choices` | 19 |
| `test_spatial_wind_contract` | 176 |
| `test_ui_weather_sliders` | 33 |

The [tested snapshot](preset-scope-20261106/tested-snapshot.patch) reconstructs on
`a9720f5a5ebb24dd37b3909c87f6741dae7a61f3`; the five integrated source/test/UID files
match its recorded hashes. Three retained texture import-metadata differences
belong only to the isolated test workspace. Earlier incomplete fixtures and
failed attempts remain in the receipts, including the corrected popup-window
input route, text replacement and persisted-value oracle. The CI unit roster
discovers the new test. Independent Good Enemy source review prompted the column
round-trip coverage and clearer composite scope.

Windows Godot `4.8.beta2.official.cafc17a19`, headless; the new regression uses a
1920×1080 logical viewport. This establishes software behavior, not native visual,
hardware, physical or release qualification. Required full CI remains pending.

## Audit preservation fixes (UI-32-R2, 2026-11-07)

A11 F03 and A21 §1 now share a staged visual transaction. Moon, sky, lighting and night options validate before publication; normal flights save one complete preference outcome. Direct flights and Natural Random remain temporary. Workshop inherits the complete night context and its originating save scope; return restores the retained world's Moon/date context. A24 §6 rotates frozen stars from their fixed build-time equatorial basis, without accumulating deltas.

UI2-02/03 separate save feedback from the display deadline and restore only the declared display-test keys on expiry. Other drafts remain editable and unsaved; explicit Revert/Close still discards the complete draft. A11 F06 reports language-save failure and a retryable/protected reason on the active Interface page. Its messages follow the selected language and do not consume the fixed action area at 200% text.

A11 F04 scrolls Help using the selected/remapped pad, with bounded repeat, release/device filtering and a route to Close. UI2-06 credits the keyboard hint only during visible, unpaused, advancing simulation time. WNEW-01 preserves independent upper wind, exact gust amplitudes on timing edits and the authored direction on intensity edits; equivalent display text does not replace full precision. WNEW-05 changes thermal-domain admission to the affine endpoint bound; the field law and sampling arithmetic remain unchanged.

The [checked evidence index](audit-20261107-checks.json) identifies the tested source and accepted scripts. Coverage includes rejected combined edits, injected preparation/commit refusal, normal/direct/Random/trial routes, protected/unwritable language saves, retry, both Help locales/scales, thermal boundary neighbors and lifetime sample parity. Native Windows Compatibility spot checks used actual 1920×1080 output at 100%/200%; screenshots remain under ignored `tmp/`. This is bounded rendered/software evidence, not physical-pad, screen-reader, macOS/Metal, full-CI or performance qualification. Recorder/controller evidence is in [UI-31](../UI-31/README.md); Workshop and statistics retain their own evidence homes.

## Field diagnostics, focus and radar (UI-32-R3, 2026-11-07)

A13 UI2-04 returns the invalid field's tab, identifier and code, reveals collapsed controls, and scrolls/focuses after layout. One localized explanation appears beside the input; the fixed action area names the field. Other drafts and raw Sky numeric text survive validation and blur. Corrected values clear the diagnostic. The integrated 604-check matrix covers all five invalid-origin tabs against Apply from all five tabs, empty/pasted/range values, cross-field and picker failures, eight locale catalogs, and English/Spanish at 100%/200%. Nine existing Conditions/Weather/Atmosphere/time/Sky consumers also pass. The atmosphere test preserves the existing first-Escape-ends-edit, second-Escape-closes contract.

UI2-07 connects future focus independently of initial tab visibility and checks effective focus, active surface, visibility and deliberate navigation at signal time. The shared observer covers repeated switches, silent autofocus, bounded subscriptions and recursive focus disable. UI2-08 shares existing translated cardinals, reserves glyph-dependent radar margins and invalidates both drawing layers on locale/font changes. Its 190 checks cover actual text scale from 11 to 22 logical pixels, live English/Spanish/German/Japanese, Japanese glyph fallback and changed font metrics. Heading/bearing arithmetic is unchanged.

Final native Windows Compatibility/RTX 3090 spot checks used actual 1920×1080 pixels: Conditions English/100% and Spanish/200%; radar English/Spanish/German/Japanese at both scales, including live locale changes through the production language setter. Focused inputs, inline explanations and action buttons remained visible; radar glyphs were centered and unclipped. Some static overlay titles retained their creation locale on live switches; that separate existing localization limitation is not repaired here. Captures remain ignored outside Git. The app stopped cleanly with zero leaked objects.

The [R3 evidence index](audit-20261107-r3-checks.json) retains 35 accepted checked invocations (33 runtime), 168 source hashes, native receipts, adverse/draft runs and ten capture hashes. The Windows weather-publication fixture was rebound only after an isolated baseline reproduced all four historical digests with a CRLF fuel registry; all 100 checkpoints matched LF after excluding only configuration, and complete LF baseline/candidate digests matched. No flight golden was re-recorded. The LSP collectors were inconclusive (no diagnostics/initialize timeout); checked imports, targeted parsing and affected runtime consumers passed. Required CI and physical/AT/device qualification remain open.

Native checkpoint layout evidence belongs to [NK-3-WNEW-02](../../native-kernel/NK-3/README.md#restored-ou-layout-nk-3-wnew-02-2026-11-07); audio geometry/cadence to [GP-19-N04/05](../../audio/AUD-15/validation.md#accepted-contact-corrections-gp-19-n0405-2026-11-07); the partial stopped-rotor correction and retained CSV/checkpoint tapes to [HELI-20-H01](../../helicopter/HELI-20/README.md#stopped-rotor-heading-memory-heli-20-h01-2026-11-07). Powered-but-blocked helicopter yaw remains open. Stock native numerical qualification, software replay and these visual spot checks do not establish new custom-weather domains, acoustics, physical realism, macOS/Metal or target performance.

## Launch recovery and saved-build diagnostics (UI-32-R4, 2026-11-07)

A14 F13 now keeps launch feedback beside the shared Fly action on every Home page. Helicopter preflight uses the session’s existing admission rule on AppRoot’s effective weather; runtime setup remains authoritative. Review Conditions returns focus after Cancel, and Apply restores a usable action when the opener disappears. Cancellation has its own translated outcome. Changing the relevant aircraft or conditions clears launch-owned failure feedback while preserving independent notices. Enlarged navigation joins the existing scroll when pinned status needs the room.

The dedicated regression passes 75 checks, including actual tree visibility, keyboard navigation, conditions correction, locale changes, saved airplane turbulence, root preflight before candidate creation, and Home/Random cancellation after candidate creation. Existing Home, nine-language layout, language-catalog and 56-check loading consumers pass. Two historical layout fixtures now use the same effective-weather resolver as the real selection path; their bounds and focus assertions are unchanged. All eight catalogs include the new Workshop, admission and mode-preview messages.

Independent review inspected eight final native Windows Compatibility/RTX 3090 captures at actual 1920×1080: English/Spanish, 100%/200%, Flight/Aircraft. A first 200% Flight capture exposed clipped Fly/utility actions; the final scroll adjustment and bounds regression resolve it. Review focus and native Cancel return were checked. The Aircraft detail card still extends below the viewport at 200%; this separate layout is not qualified by this correction. Workshop and helicopter evidence have their own homes below.

The [checked evidence index](audit-20261107-r4-checks.json) binds source bytes, accepted checks, rejected attempts, native prerequisite reports, retained inputs, companion CSV parity and ignored native captures. The combined candidate incorporates the parallel CI merge at `187182d3c`; its source was implemented in an isolated checkout while the main checkout had an unfinished merge. Full hosted CI, release/export, physical controllers, screen readers, macOS/Metal and participant usability remain separate gates.

After integration into `main`, a fresh Windows import and all four new suites pass there: 81 mode, 50 admission, 75 launch and 44 library checks, with no engine errors or warnings. The evidence index retains those integration receipts separately from the isolated Linux-native byte manifest.

## History and Garage integration (UI-32-R5, 2026-11-07)

The [R5 checked index](audit-20261107-r5-checks.json) binds this main-checkout batch on `8e26773de`: A14 F15/F16 and A21 §3/§4. The owning reports describe [statistics deletion/context](../../flight-statistics/UI-FS-08-R1/README.md#ui-fs-03-r1--deletion-commit-and-recovery-2026-11-07) and [Garage start/camera behavior](../../rc-monster-truck/RCV-runtime/README.md#staged-start-and-camera-feedback-rcv-2018-r1-2026-11-07). Six dedicated regressions pass 418 checks, affected existing consumers pass, and the final checked import has no engine diagnostics. The CI partition-discovery fixture passes all 14 tests under WSL; it does not run full CI.

Native Windows Compatibility/RTX 3090 review covers actual 1920×1080 Statistics in English/Spanish at 100%/200%, and Garage at 100%. A real Windows file lock exercises committed deletion with pending cleanup. Captures stay ignored; the index records their dimensions, hashes and limits. Early collapsed-column images and 1078-pixel-high attempts are excluded from 1080p acceptance. Existing mixed localization remains visible. No simulation/physics sources or golden flights changed; release, full required CI, physical devices, assistive technology, performance and participant validation remain separate gates.

## Recovery, drafts and practice scope (UI-32-R6, 2026-11-07)

This batch on `249dd41c1` implements [Garage checkpoint review](../../rc-monster-truck/RCV-runtime/README.md#checkpoint-review-rcv-20-r2-2026-11-07), [Companions draft preservation](../../ai-companions/AFC-05-R1/README.md#afc-05-r2--remove-preserves-the-draft-2026-11-07), and A18 §4's failure-practice scope/reminder (UI-36-R1). The three dedicated regressions pass **270 checks**: 93 Garage, 37 real-roster Companions and 140 practice UI checks. Existing consumers, the final import, language checks and 14 WSL partition-discovery tests pass. The [checked index](audit-20261107-r6-checks.json) binds actual source bytes, selected receipts, negative controls and native capture hashes, including the different versions used by earlier consumer checks.

The practice dialog explains reusable saved settings, stable Restart, immediate notices and excluded routes. Enabled practice stays beside ordinary Home Fly and follows locale/page changes; default-Off, rotorcraft and Garage hide it. The 61-check real Home/Pause route includes retained draw/seed/notices through Restart and changed settings on a new flight. Native 1080p English/Spanish review at 100%/200% confirms readable policy and fixed actions. At 200%, some page content requires scrolling; a real Up-key check reveals the selected airplane from Fly without hiding the reminder or launch action. This addresses a cognitive walkthrough, not participant comprehension or training efficacy.

Companions native checks remove genuinely admitted traffic at unchanged paused ticks, preserve drafts and show Cancel focus. Garage native English 100%/Spanish 200% checks cover refusal, verified setup, visible Close, effective lab values and matching restoration with unchanged saved bytes. Native review exposed the initial source-line-only reveal; the final layout and real-key regression correct it. Captures remain ignored outside Git. Whole-checkpoint inspection cost, complete localization, physical devices, assistive technology, full CI, release/platform, performance and physical-validation gates remain open. No simulation/physics sources, source pins or golden flights changed.

## Startup and calibration disclosure (UI-32-R7, 2026-11-08)

This batch on `ef4136720` implements A11 F07 and A18 §2/§3's supported controller guidance. Startup reads validated saved text size without loading the shell graph or writing preferences. Semantic, localized status and Skip controls retain the artwork and reduced-motion behavior. Held Skip input stays consumed until release and handoff; focus loss, disconnection and cleanup release ownership safely. Errors disable Skip and focus the assertive status, including an error set before deferred initial focus. The dedicated startup regression passes **182 checks**; branding assets remain unchanged and the trailer's footer-hiding contract is preserved.

Controller settings disclose the existing save point: Home calibration edits only the draft; in-flight **Save controller settings and calibrate** saves the profile and applies both device selections before calibration. Pause explains retained settings after cancellation and a refused start after a successful save. The new refusal notice retranslates live. Devices explains profile persistence versus session-only device choices. **Choose radio profile** navigates to the existing unknown/joystick type picker without editing or saving. Other observed types receive information without a new conversion path. The dedicated regression passes **85 checks**, including actual storage/role changes, refusals, cancellation and keyboard/pad focus at EN/ES 100%/200%. Review retained the inherited saved-Radio-profile/menu-admission issue in the [pending queue](../../../../external%20Audits/CONSOLIDATED-AUDITS.md); input policy is unchanged.

Native Windows Compatibility/RTX 3090 review uses actual 1920×1080 pixels. Production Intro seek captures cover EN/ES/JA at 100%/200%; a fresh isolated Japanese 200% error capture verifies the final early-error focus fix. These are presentation witnesses, not the complete real-startup loading/input matrix. Controller captures cover English 100% prerequisites, draft scope and save/cancel behavior, plus Spanish 200% flight guidance and cancellation. Native review exposed an off-screen explanation after focusing Calibrate; the final focus-scroll owner reveals the action and full explanation together when they fit. A fresh real-Tab capture and bounds assertion confirm both are visible. Explicit wheel input and unrelated focus remain preserved. Injected registry devices exercise software routes, not physical radios or gamepads; the native flight remains paused at tick zero.

The [checked index](audit-20261108-r7-checks.json) binds final source bytes, **267 dedicated checks**, affected consumers, earlier source versions, rejected candidates and ignored capture hashes. The language inventory passes with 11 new messages in all eight translated catalogs. WSL partition-discovery checks pass all 14 tests; they do not run required CI. All native app sessions exit with no crash or leaked objects. Screen-reader announcements, physical input, the full saved-preference native startup matrix, other platforms, full CI/release, performance and participant comprehension remain separate gates. No simulation/physics sources, accepted data, source pins or golden flights changed.

Merged verification at `18b13193b` preserves the parallel Home/render lifecycle work. A fresh import and eleven affected suites pass on that snapshot, including the 267 dedicated checks and Home rebuild/preview consumers. A fresh native 1920×1080 window on the now-4K display confirms the focused action, explanation and saved calibration outcome. Intervening 4K viewport images were downsampled and are excluded from 1080p acceptance. Earlier capture and consumer versions remain explicit in the index.

## Instrument help and launch summary (UI-32-R8, 2026-11-08)

A11 F08 gives all 28 Flight overlays switches wrapped purpose/limit text on focus and hover, plus localized accessibility descriptions. Constrained-height help becomes a focusable scroller; its hint uses existing localized key labels. Scrolling respects saved Accept, Back, Pause and navigation mappings, two-column navigation and manual scrolling. Changes still apply immediately; Done/Escape closes. **466 dedicated checks** include 107 real overflowing descriptions across nine locales at the 720p/200% fallback, primary 1080p cases, device filtering, live locale and rapid closure. The first candidate exposed a freed reveal coroutine; coalesced, object-bound frame callbacks resolve it without delaying closure.

A11 F09 retains graphical arrows while publishing a translated static-text name and value, with owned decorative children hidden. Physical-key labels retain the existing layout mapper and refresh on locale/application focus. **91 checks** cover directions, localization, injected layouts and Help. Native Windows UI Automation initially exposed four blank nodes despite passing internal name checks. The correction follows the pinned engine's Label contract: static-text content is a value. Final EN and live ES Help trees expose all four direction names once in their action rows. The separate background flight hint has its own four keys. An immediate earlier ES snapshot retained the previous English tree and is excluded. Tree text does not establish screen-reader speech or changed native keyboard layouts.

A18 §5's existing Aircraft/Practice Fly caption now includes aircraft, landscape and effective start from the current resolver, preserving remembered choices. **109 checks** cover EN/ES 100%/200%, notice/footer bounds, live locale, setup changes and actual AppRoot loading/cancellation handoffs for hand launch, an airborne airplane and helicopter hover. Flight/Garage/Random behavior is unchanged. The loading surface's generic helicopter Runway/Airborne wording and state/vehicle startup guidance remain in the queue; the candidate receives the correct start.

Verification used an isolated checkout on `8ebb252ac` while concurrent physics work changed main. Eight affected existing consumers pass. Native Windows Compatibility/RTX 3090 review uses actual **1920×1080** window and viewport pixels on the 4K monitor: all 28 descriptions at EN100/EN200/ES200, plus Home hand-launch and helicopter-hover captions. Descriptions and scoped actions fit; other page content may scroll. Live-language instrument captures retain some existing untranslated dialog chrome and do not qualify complete localization. Both native sessions exit without crashes or leaked objects. Captures remain ignored outside Git.

The [checked index](audit-20261108-r8-checks.json) binds source bytes, receipts, rejected attempts, native trees and capture hashes. Concurrent `174abfd02` includes the initial Home/instrument/catalog changes; all three final dedicated suites also pass on that main-tree integration: **666 checks**, zero engine errors/warnings. Independent Good Enemy review found no further blocker. Screen-reader listening, physical devices, required full CI/release, other platforms, performance and participant comprehension remain separate gates. This UI batch changes no simulation laws, accepted data or golden flights.

## Preview focus and loading identity (UI-32-R9, 2026-11-08)

A17 UI3-05 transfers focus only when the focused camera control is replaced: inline camera actions yield to Camera on collapse, and Camera yields to Front on expansion. Other focus, empty focus and a covering screen retain ownership. The dedicated regression passes **37 checks**, including real Workshop reflow, keyboard activation, synthetic mapped-pad navigation and screen-stack suspension. Native Windows Compatibility/RTX 3090 review starts at actual **1920×1080**; the secondary 1000×390/400 compatibility witnesses confirm Front→Camera→Front and subsequent Tab navigation. These short-window cases do not establish a 1080p defect.

A18's loading summary reuses Home's existing resolved, localized start label, including helicopter pad/hover. Natural Random retains its separately validated airplane airborne start. **45 checks** cover six aircraft/field/start combinations in English and Spanish, both helicopter candidate handoffs, and early/late Random cancellation. A cancellation consumer exposed an inherited hidden-Home focus warning; `reject_start` now focuses only an eligible visible action, preserving the briefing's return target. Native 1080p loading review confirms the X-Cell hover summary. No start, saved preference or flight input policy changes.

The [R9 evidence index](audit-20261108-r9-checks.json) retains source identities, checked receipts and ignored capture hashes. Existing flight-loading, loading-surface and screen-stack consumers pass. The separate `test_home_launch_conditions.gd` still has two inherited 200% Aircraft-page viewport failures, reproduced with the baseline Home script; those are not passes. Full CI/release, physical controllers, assistive technology, other platforms and participant comprehension remain open. No images are added to Git.

## Paused alert inspection (UI-32-R10, 2026-11-08)

A21 §5 adds **Review active alerts** to Pause when the flight has an overlay manager. The screen copies the manager's latest sampled, priority-ordered and category-filtered selection, including alerts beyond the visible cap. It identifies the copy as a non-updating sample and distinguishes a valid empty sample from unavailable flight data. Focusable rows contain the existing alert explanations; Close or Back returns to the Pause opener. The saved cap, alert policy and flight input are unchanged. Five messages were added to each translated catalog.

The dedicated regression passes **101 checks**, including cap one with STALL and LOW, hidden rail, category changes, reset, empty/unavailable states, unchanged settings and preference bytes, keyboard navigation, remapped selected-pad input and isolation of another device. Existing alert policy, warning settings and rail presentation pass **33, 89 and 41 checks**; Pause, screen stack and language pass **94, 38 and 104 checks**. All five modified/new GDScripts pass checked parsing. A final combined-tree run retained identical hashes for 26 relevant inputs before and after the dedicated test. Other controller changes and additional catalog messages landed after the earlier native run; individual consumer receipts describe their own run times rather than asserting a common source snapshot.

Native Windows Compatibility/RTX 3090 inspection used an actual **1920×1080** window and viewport. A synthetic, fixed paused sample with cap one displayed both alert explanations at English 100%/200% and live Spanish 200%; Down selected the second row and Escape returned focus. At 200%, Pause scrolled to show Return to Home and then Quit, with Resume visible. The debug session stopped without a reported crash or leaked objects; its launcher exit status was unavailable. The [checked evidence index](audit-20261108-alerts-checks.json) retains receipts, source and ignored capture hashes. This is bounded software and visual evidence, not a naturally observed simultaneous alert, physical-controller or screen-reader test, participant usability, full CI, release, other-platform or performance qualification. No images were added to Git.

## Frozen trial identity (UI-32-R11 / A21, 2026-11-09)

Pause identifies the frozen Workshop build as unsaved or as a saved name/revision.
An edited saved build names its unsaved candidate and saved ancestor. The trial
compares all persisted payload fields, including name/presentation, with the
editor's saved baseline; ancestry alone never means saved. Recovered copies stay
unsaved. Display context is detached and separate from physical, presentation,
trace and replay identities. Test fly neither saves nor certifies the build.
Nontrial Pause clears the trial display; there is no new Last flown indicator.

Native save/edit/Test fly revealed an inherited freed-opener failure during screen
suspension. The handoff now validates the opener before assigning it to a typed
Control, retaining the existing restoration guard. Integration checks free an
opener before launch and another during the trial, then return to the same editor.

[Checked evidence](audit-20261109-trial-checks.json) includes 58 trial assertions,
Workshop UI/integration, Pause, language coverage and Change aircraft consumers.
The 1080p EN/DE matrix covers 100%/200%, renamed/reverted content, two distinct
96-character names, translation changes and reachability of Resume/alerts.
German 200% can make the identity taller than its scroller; both ends remain
reachable, without a single-screen-fit claim.

Native Windows Compatibility/RTX 3090 inspection used actual **1920×1080** pixels,
English 100%/200% and German 200%. The real saved/edit/Test fly/Pause/return flow
passes after the opener correction. A separately injected maximum-name display
confirms wrapping and scrolling to the revision, Resume and alerts. The failed
initial run and corrected run are retained separately; the latter reported no
script error, crash or leaked objects, with launcher exit status unavailable.
Ignored capture hashes are in the evidence index; no images are added to Git.
Physical controllers, assistive technology, participant comprehension, other
platforms, full CI/release and performance qualification remain open.
