# Product shell and menus

Status: current shell and UI-00…06 delivery checked 2026-10-12. Owner: menu track; prefix UI-. The shared-screen refactor UI-20/21 is delivered; active UI-22…29 work lives in [MENU-REDESIGN-PLAN](MENU-REDESIGN-PLAN.md). Pilot, accessibility and display acceptance remain open.

Owns `app/app_root.*`, `app/ui/`, `app/app_state/`, `app/i18n/`, build-info export integration and UI tests. Coordinate simulation holds/recording with physics, world construction with rendering, weather with M5-W/ATM, lighting with TOD/FW and display settings with DT.

## Implemented behavior

- No user arguments opens Home; arguments after `--` select direct flight. `--input-report` is standalone diagnostics. Direct routes use English and do not read/write player preferences.
- Home offers Fly, aircraft selection, Stik start selection, Weather, Time of day, Language, Help and Quit. The still 3D backdrop uses the selected model and current field/world modules. There is one field, with no implemented field/scenario picker.
- The catalog resolves aircraft/data/model identity; previews refuse Fly. All four current entries have flight data; Extra, P-51 and Avanti are experimental. Aircraft parameters stay outside the catalog.
- New preferences select Stik/runway, gentle practice weather, passing evening and a live diagnostic marker. Explicit saved choices remain valid; runway is restricted to the Stik. The engine shadows and audio defaults are applied by their presentation owners.
- Esc or focus loss opens Pause. Continue, Restart, End flight, Quit, Help and time-of-day editing use the shared navigation lifecycle. Direct flights omit End flight. Weather is edited on Home; paused weather editing remains proposed.
- Named session holds freeze flight while a blocking screen is open. Menus isolate joystick actions and swallow flight shortcuts. Held keys must be released before they can fly again. Resume cannot bypass a menu, invalid start or crash.
- End/Quit saves an active trace. A save failure is visible; a second explicit request discards it. Returning to Home frees the old flight, camera, audio and session.
- Help, Home and the first-flight hint share `controls_reference.gd`. Physical keyboard positions drive flight; displayed labels follow the keyboard layout where the platform supplies them.
- English is the source/default language; `app/i18n/es.po` supplies Spanish. Dynamic strings rebuild on locale change.

Player instructions and controls: [FIRST-LAUNCH](FIRST-LAUNCH.md). Developer commands: [TOOLS](TOOLS.md).

## Architecture and saved state

`app_root.gd` owns the route, accepted preferences, Home backdrop and current flight. `ScreenStack` owns screen membership, top-screen activation, layered input isolation, named holds and focus restoration. `Screen` supplies shared modal/sidebar behavior; `Widgets` creates common controls. Existing CanvasLayer wrappers and public test views remain stable. [UI-21 implementation and parity](research/menu-investigations/UI-21/README.md).

`user://settings.cfg` is a validated ConfigFile. Schema 4 is the highest supported settings version; saves use the lowest compatible schema for the selected weather/lighting profile, while also retaining the diagnostic-marker preference. Legacy schemas remain readable. Unreadable files are retained as `.bad`; newer schemas are read where valid and never overwritten. Language, aircraft, launch, weather and lighting persist through the interactive route. Radio calibration has its own file. A refused launch returns to Home with its reason; it does not save a successful launch choice.

Runway selection belongs to `FlightSession`, so R, Pause Restart and crash reset reconstruct the same equilibrium. Trace metadata distinguishes selected launch from the recording-start snapshot; restoring a physics-only checkpoint clears inherited launch claims. Direct technical flights retain their explicit/default start policy.

The build-info plugin writes `build_info.json` into exports without changing the source tree. The full identity uses Git description/commit/dirty state; platform version fields use numeric `config/version`. The plugin itself is excluded from packs. [Build/export contract](TOOLS.md#release-sequence).

## Delivery evidence

| Step | Delivered result | Evidence |
| --- | --- | --- |
| UI-00/01 | Home/direct entry, radio isolation and localization | [UI tests](../app/tests/test_ui_home.gd), [language](../app/tests/test_ui_language.gd), [input](../app/tests/test_ui_input.gd) |
| UI-02/03 | Pause/focus holds, End/Quit, trace-save policy and lifecycle | [Pause regression](../app/tests/test_ui_pause.gd) |
| UI-04/05 | Shared controls/help/hint, build identity, aircraft selection | [Controls](../app/tests/test_controls_reference.gd), [Help](../app/tests/test_ui_help.gd), [aircraft](../app/tests/test_ui_aircraft.gd) |
| UI-06a/b/c | Persistent experimental Stik runway start and export proof | [Session](research/menu-investigations/UI-06a/README.md), [Home](research/menu-investigations/UI-06b/README.md), [package trial](research/menu-investigations/UI-06c/README.md) |
| UI-06a-R1 / c-R1 | Checkpoint launch-attribution repair and refreshed package proof | [Repair](research/menu-investigations/UI-06a-R1/README.md), [export](research/menu-investigations/UI-06c-R1/README.md) |
| UI-06d | Current interactive defaults, existing options enabled without physics tuning | [Default profile evidence](research/menu-investigations/UI-06d/README.md) |
| UI-20/21 | Shell audit and shared-screen refactor with unchanged visual/flight results | [Audit](research/menu-investigations/UI-20/README.md), [implementation](research/menu-investigations/UI-21/README.md) |

Original research and executed engine probes: [menu investigations](research/menu-investigations/README.md). They are dated evidence; current code supersedes their older catalog, pause and layout descriptions.

## Remaining work and acceptance

UI-22…29 own theme, scaling/display, Settings, Home/Hangar, pause/conditions polish, HUD, motion and delivery proof. UI-07/08/09 are superseded by that [active redesign plan](MENU-REDESIGN-PLAN.md).

UI-10/12 radio setup/device selection, UI-15 key remapping, further UI-06 scenario selection and UI-14 model inspection are not delivered by the current shell. A general settings screen, fullscreen default, menu gamepad navigation and screen-reader acceptance are not implemented.

Use real input events in UI regressions, check the exported Home route as well as technical flight, and inspect EN/ES captures. Headless checks establish lifecycle/input behavior; native focus/fullscreen, screen readers, radio setup, monitor readability and target-GPU costs need separate acceptance. The [manual runway flight card](research/menu-investigations/UI-06c/FLIGHT-CARD.md) remains the PT2 pilot trial.
