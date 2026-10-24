# OpenRC Simulator: first launch

Status: current-source player guide, checked 2026-10-20. [v0.1.8](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.8) is the latest stable software release for this early-alpha simulator. Aircraft models and experimental activities still require independent physical and pilot validation; automated checks do not establish flight accuracy. See the [v0.1.8 release notes](releases/v0.1.8.md). Current-source features may differ from the v0.1.8 package. Start with the [Ugly Stik](UGLY-STIK-PLAN.md).

## 1. Download and check

Download the latest stable release, [v0.1.8](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.8). Download a platform ZIP and `SHA256SUMS` from that release. Extract the ZIP before launching. Compare the archive's SHA-256 with its matching entry:

- Linux: `sha256sum -c SHA256SUMS --ignore-missing`
- macOS: `shasum -a 256 openrc-simulator-*.zip`
- Windows PowerShell: `Get-FileHash .\openrc-simulator-*.zip -Algorithm SHA256`

## 2. First launch

| Platform | Launch |
| --- | --- |
| Windows x86_64 | Run `OpenRC Simulator.exe` from the extracted folder |
| macOS Apple Silicon / Intel | Move `OpenRC Simulator.app` to Applications and open it |
| Linux x86_64 | Run `chmod +x openrc-simulator.x86_64`, then `./openrc-simulator.x86_64`; requires OpenGL 3.3 graphics |

These test builds have no trusted developer signing/notarization. If macOS refuses an unidentified developer, Apple's [opening-app guidance](https://support.apple.com/en-us/102445) explains the Privacy & Security override. Windows may show a reputation warning; platform policy can prevent launch. Native-platform and graphics acceptance remain separate from package checks.

## 3. Fly

Home selects the aircraft, landscape, language, launch, weather and lighting. Menus support keyboard/mouse and an explicitly selected gamepad; a radio controls only flight. English is the default, Spanish is available, and valid settings are remembered.

**Fly** starts the airplane directly when its controls are ready; no extra **Continue** is needed. Unready or unavailable controls open Pause for recovery.

Fresh settings select the Ugly Stik on the Club field runway. Every flight-capable catalog airplane supports this default there: stopped near the threshold, landing gear down and throttle closed. Changing airplanes keeps the runway selection. **Start: in the air** is the other option: level flight at half throttle. Every airplane is trimmed the way a pilot trims a model, for level flight at 50% throttle, whether it starts in the air or climbs out from the runway: below half it descends, above half it climbs, and the trim stays where it is until you move it ([why](research/flight-dynamics/power-climb-2026-10-19/README.md#d6e-r4-every-launch-trimmed-for-50--throttle)). Saved explicit choices take precedence, and Restart repeats the selected launch. Finite-glow aircraft, including the Extra, need **F7** to start; see the [engine guide](GLOW-ENGINES.md) and [flight options](#4-settings-and-flight-options).

An aircraft delivered with several paint schemes shows a **Paint** row at the top of the **Aircraft** page; the F4U Corsair offers five. Each click shows the next scheme on the backdrop, and every aircraft remembers its own. The scheme changes only the paint, never the flight model.

**Landscape** cycles between **Club field**, with its runway and scenery, and **Green paradise**, a flat grass surface without scenery objects or a lake. The backdrop updates immediately and the choice is remembered. To switch during a session, use **Pause → End flight → Home**, select the other landscape, then Fly. Green uses airborne airplane starts and helicopter hover; Natural Random requires Club field. RC-car courses are separate. [Landscape details and authoring](LANDSCAPES.md).

Home also offers two separate experimental activities, each with its own controls: [RC Helicopter Research Trainer](HELICOPTER.md) and [RC cars · Bisonte MT8 and MONSTER CAR 2](../research/rc-monster-truck/README.md).

**Esc** opens Pause; losing window focus also pauses. Continue resumes explicitly. Pause can restart, return to Home or quit. The direct CLI route has no Home to return to.

| Key | Action |
| --- | --- |
| ← / → | Aileron / roll |
| ↓ / ↑ | Elevator / pitch; ↓ pulls the stick back |
| A / D | Rudder |
| W / S | Increase / decrease throttle |
| `[` / `]` | Aileron trim left / right |
| Page Up / Page Down | Elevator trim nose down / nose up, 0.1° per press |
| Esc | Pause; cancel radio calibration |
| R | Restart flight |
| P | Resume after a radio failsafe |
| C · Shift+C | Next / previous view: pilot, chase, orbit, close-up |
| 1 · 2 · 5 | Pilot · chase · orbit view (orbit: drag with the right mouse button) |
| = · − · Backspace | Zoom in · out · reset (also the mouse wheel); in chase and orbit it moves the camera |
| Z | Toggle auto-zoom |
| V / L | Cycle ground-shadow aid / aircraft night lights |
| K · Enter | Start calibration · advance its step |
| F · Shift+F | Move equipped aircraft's flaps: next / previous |
| G / B | Toggle retractable gear / hold its wheel brakes |
| O | Fold or spread folding wings (F4U Corsair), on the ground and stopped; the throttle stays at idle until spread and locked |
| H | Toggle available smoke with keyboard controls |
| J · Enter | Assign the active radio's smoke AUX · advance its step |
| T | Start / save a flight trace |
| F10 / F11 | Start/stop flight log / mark a maneuver while recording |
| F3 | Toggle developer overlays |
| F2 | Cycle flight overlays: off / pilot / full / developer |
| F5 | Reload the aircraft data file |

Gear, brake, flap, smoke and glow shortcuts are limited to aircraft with those systems. Keys refer to physical QWERTY positions; in-game Help shows your keyboard's labels. At startup and on Home, a connected controller is selected automatically; with no devices, flight uses the keyboard. Controller settings can override that choice.

Keyboard sticks use aircraft normal rates/expo where specified. Gamepads apply their own scalar deadzone/expo once, followed by aircraft travel rates and trims; radios keep their own rates and curves. The direct route's `--rates=full` flies maximum throws. **N** (or the optional gamepad action *Rates: normal / full*) switches between the two in flight.

Ventage Jet keyboard pitch builds gradually over one second and returns promptly when released. Use short pulls and release as the flight path levels out. Holding Down still reaches the full normal elevator travel and can produce an accelerated stall, even at high speed. [Flight-response audit](research/avanti-realism/AV-17-R1/README.md).

Ventage Jet in **Normal** mode uses reduced gamepad elevator travel (±6° before trim) for short sticks. The revised wing polar gives a more gradual stall transition. Pull progressively and add power for a sustained climb; low energy or excessive angle of attack can still cause a stall. **Full** mode retains the maximum ±30° elevator travel and is very sensitive. RC radios retain their transmitter settings. [Gamepad flight correction](research/avanti-realism/AV-17-R2/README.md).

Its Normal gamepad rudder uses ±12° travel before trim and a brief progressive response (about 0.3 s to reach 95% of a held target or return). This softens the nose's swing when the stick centers; some aerodynamic return remains normal. The setting also reduces the coupled nosewheel steering command. Full mode and RC radios retain their existing rudder mapping. [Rudder-release evidence](research/avanti-realism/AV-17-R3/README.md).

Adjust elevator trim with **Page Up / Page Down** (Spanish keyboards: **RePág / AvPág**). Establish the desired speed and flight path with the sticks and throttle, then adjust trim to relieve the held elevator command. This is a fixed surface offset, not altitude hold; changes in power or speed may need another adjustment. The transmitter overlay shows the resulting trim. **R** restores the starting trim. Trim keys are ignored while paused or replaying recorded inputs.

### Controller settings (current source)

At startup and on Home, flight prefers a device with one matching saved profile, then a recognized radio, a mapped gamepad, or another joystick. Ties use the lowest current connection ID. Menus use the selected flight gamepad when eligible, otherwise the first eligible gamepad; radios and unconfigured joysticks never navigate menus. With no devices, flight uses **Keyboard** and menus use **Keyboard + mouse**. Recognized gamepads work with the Mode 2 preset without opening settings; unknown joysticks still need their axes configured before flight. A/Cross activates the focused menu button normally.

Open **Controller settings** from Home or Pause to override the automatic choices, then **Save**. This saves the profile and activates both controller choices together. A successful manual choice, including keyboard, remains in effect for this application run; unplugging that chosen device releases its role for automatic selection on Home. Selection waits while settings or another activity is open. A new connection never takes over an active flight. Keyboard and mouse remain available for menus.

Use the five sections: **Devices**, **Profile**, **Flight axes**, **Extra channels**, and **Buttons**. The selected devices, section navigation, validation messages and Save/Cancel stay visible while the section scrolls. Flight axes shows all four response previews alongside their settings. Buttons can filter **All**, **Flight**, **Camera**, **Auxiliary**, or **Menu** actions; filtering never changes assignments. D-pad/left stick and A/Cross operate the native controls. Switching sections or filters cancels an active remap and preserves the draft.

Choose **Mode 2** (left throttle/rudder, right roll/pitch), **Mode 1** (right throttle/roll, left pitch/rudder), or **absolute trigger throttle** for fixed-wing flight. Mode 1/2 throttle is incremental: pushing the throttle stick changes engine power; releasing it holds that power. The absolute trigger preset maps RT/R2 directly from idle to full power. It requires an independent analog trigger; use a stick-rate preset when a device exposes combined or digital triggers. Helicopter collective uses a stick-rate or calibrated radio profile, not the fixed-wing trigger preset.

Controller choices, mapping, inversion, gamepad deadzone/expo and action changes stay draft until **Save**. Switching profiles/devices keeps their drafts while this screen remains open. **Cancel** discards all edits; pending Home device detection can then update the automatic choice. Saving checks the selected activity and devices; a rejection keeps the draft open and restores the previous configuration. Profiles live in `user://controller_profiles.cfg`, with a transactional rollback copy. An unreadable store prevents flight-profile activation instead of silently using a factory mapping; successful rollback recovery also shows a notice. Legacy recovery copies a radio profile or restores a gamepad preset without deleting `rc_calibration.cfg`. Unknown devices require an explicitly configured profile; menu use additionally requires a saved gamepad profile with an unambiguous device association. Restarting the application restores automatic device selection and reuses matching profiles; connection IDs are never saved as device identities.

Choose automatic, Xbox, PlayStation, Nintendo or generic button prompts in the profile. A manual choice helps with emulated devices; it changes only labels and icons, never the bindings. The action list shows the actual remapped controls. Artwork is the free Kenney Input Prompts pack.

**JETI USB radios:** the app recognizes the DC/DS family from its complete USB identity plus a JETI name/descriptor, and offers a **JETI USB Mode 2** profile with absolute throttle. This starter uses the four axes supplied by JETI and leaves radio buttons unassigned. Existing saved profiles keep their calibration and assignments. In Profile, explicitly choose the **JETI Mode 2** preset or use **Use safe radio actions in draft** to remove inherited gamepad assignments from the draft, then Save. Cancel keeps the previous setup. A short family name identifies the radio; details/tooltips retain the backend name. Missing or contradictory identity data requires explicit configuration. Software support does not establish full model/firmware compatibility; see the [JETI evidence and remaining qualification](plans/jeti-support.md).

In Extra channels, choose **Switch positions** and two or three positions. Capture the actual Up, Middle (when installed) and Down buttons from the selected radio, or enter their observed indices. Add an optional physical name such as `Sa`; those configured positions then appear by name instead of gamepad glyphs. Changing a position to another button in the same group swaps them. Separate channels cannot share any group member. No Sa–Sj button map is assumed automatically.

A switch produces a maintained request, including a half-travel middle detent, rather than repeatedly toggling an action. After saving, pause/focus recovery or reconnection, deliberately return it to its zero/OFF position before using it; if already OFF, move away and back. Invert reverses the zero/full endpoints. Invalid or contradictory switch states disable that request until fresh OFF evidence is received. This equipment arming is separate from the radio's fresh low-throttle gate and explicit Continue.

Recognized gamepads with standard mapped axes become ready on the first valid live sample. There is no stick-wiggling, centering, button-release or timed arming step. Select **Continue** to resume an ordinary pause; moving a stick in Pause does not disable it. **Restart flight** resets the airplane and resumes immediately when controls are ready. An already armed radio remains ready under the same device/profile. Pause freezes incremental throttle and shows the value that Continue will use; a held throttle stick changes it only after resuming. Runway rate throttle starts at idle; airborne rate throttle uses the scenario power. Absolute-trigger throttle follows the current trigger value. Raw/nonstandard layouts still need configured channels and fresh input evidence. Radios retain their low-throttle arming requirement when selecting, reconnecting or recovering focus. Disconnects, uncertain continuity after suspension and profile changes pause and require explicit recovery; select **Keyboard** to return to keyboard flight.

Default buttons: **A/Cross** accept, **B/Circle** back, **Menu/Options** pause, **Y/Triangle** camera, right-stick click reset view, **X/Square** overlays, D-pad trims during flight, and held LB/L1 throttle cut for fixed-wing flight. D-pad/left stick navigate menus. Remaps are profile-specific. Ground driving keeps left-stick steering, RT drive, LT brake and B+RT reverse.

**Automatic aircraft controls:** on gamepad profiles, **A/Cross** cycles available flaps, **B/Circle** toggles retractable gear and **RB/R1** toggles available smoke. The P-51D and Ventage Jet receive flap and gear bindings; supported Stik, P-51D and stock Ventage Jet configurations receive the smoke binding. Automatic assignments use only free flight buttons, preserve explicit remaps and cleared actions, and yield to existing AUX assignments. A/Cross and B/Circle still mean Accept and Back in menus; release them before pressing again in flight. The Control guide shows this aircraft's equipment, actual binding, gear movement and smoke output. Unknown joysticks and RC radios keep their configured buttons; use **Remap** for their actual layout.

**Restart from the controller:** **View/Back** on Xbox or **Share/Create** on PlayStation restarts the selected flight, including from the accident report. Airplanes resume immediately when controls are ready; unready or unavailable controls keep Pause open for recovery. Helicopters retain explicit **Continue**. The flight controller owns this command even when another pad navigates menus. In Controller settings → Buttons → Flight, remap **Restart flight** to a button or an unused radio/joystick axis, then **Save**. An axis fires once when it crosses its threshold; return it toward OFF before restarting again. Settings/calibration cannot queue a restart from a held control. While an ordinary menu is open, use Pause's **Restart flight** action.

**Additional controls:** the action list also offers previous/direct pilot/chase/orbit cameras, zoom, auto zoom and lights. These remain unbound until assigned. Use **Clear** to free an existing assignment, then **Remap**, release the captured control and **Save**; Back and Pause must remain assigned. Disconnecting or changing the flight device cancels its pending capture. Primary flight axes cannot also trigger flight actions. The [helicopter defaults](HELICOPTER.md#historical-playable-reference-start-and-controls) assign arm, rotor hold, curve and trainer controls automatically, with the same saved remapping. [Cars](../research/rc-monster-truck/README.md#drive-and-experiment) use their own fixed driving scheme.

The **Extra channels** section maps smoke, flap requests and gear requests independently to an axis or a button. An axis uses calibrated OFF/ON endpoints; buttons can be maintained or toggle on each press. Available input slots are axes 0–9 and buttons 0–127, subject to what the device/backend actually exposes. Assign either an AUX source or semantic buttons to a function, not both. AUX channels cannot share a source or reuse a primary flight axis. After selection, pause/focus recovery or profile changes, return an AUX axis to OFF or release its button before use. Paused input cannot queue an AUX toggle. Ventage Jet flap positions are 0° retracted, 20° takeoff and 50° landing; **F** advances and **Shift+F** moves back. The radio AUX axis can request any intermediate position.

Review the effective action list after assigning AUX: an inherited flight button on the same source becomes Unbound. For a radio/joystick AUX on the inherited Pause button, Pause uses **Escape**; an explicitly remapped Pause is preserved and conflicts must be resolved before saving.

**Aircraft limits:** Ventage Jet has simulated retractable gear, including deployment, wheel contacts, drag and a retraction interlock while on its wheels. Fixed-gear aircraft cannot retract. Ventage Jet flaps move through the positions recommended in the [SebArt Avanti S 2.2m manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf): 0°, 20° takeoff and 50° landing. Its down-elevator mix scales with actual flap travel, to 8% of full elevator travel at 20° and 20% at 50°. The simulator shows requested and actual angle and an estimated overspeed advisory; it does not retract flaps automatically. Flap lift and drag behavior remains experimental. The P-51D also has simulated retractable taildragger gear and flaps at 0°, 15° takeoff and 45° landing, with an estimated 2.5-second flap travel time. Its aerodynamic calibration remains experimental. Other aircraft report flaps as unavailable. Stock Ventage Jet flights offer optional white tailpipe show smoke with H or smoke AUX; it follows the accepted turbine running state. This display does not simulate smoke-fluid consumption.

These are source features with automated checks, not a claim that every Xbox/PlayStation model or connection has been tested. [Implementation and remaining qualification](research/controller-support-2026-10-14/README.md#implementation-evidence).

### Radio setup

Connect in USB joystick mode with RF modules off. EdgeTX/OpenTX's Advanced joystick interface with at most eight axes is the starting configuration; mappings still depend on device, firmware and platform. The default channel order is AETR.

Select the radio in Controller settings and Save, then move throttle to low to arm. If channels or directions are wrong, use **Calibrate selected radio** from Pause → Controller settings, or **K** outside menus. The calibration button saves and activates the chosen radio before opening its wizard. Follow the steps with **Enter**, then move throttle away from low and back to low to rearm. A separately selected menu gamepad can advance/cancel the wizard with A/B. Calibration is saved per radio; gamepads cannot enter this radio-only wizard. Unplugging pauses with idle throttle. Simulated-device tests do not certify your hardware.

On supported Stik, P-51D and stock Ventage Jet configurations, **J** opens a separate smoke-pump assignment: keep the control OFF, turn exactly one unused axis/button ON, then return it OFF, using Enter at each step. Buttons offer held-level or press-edge toggle. AETR axes cannot be assigned. The profile is saved per device; after assignment/reconnection, report OFF again before using smoke and rearm throttle before resuming. **H** controls the pump when no radio is connected. Ordinary engine exhaust is faint; the pump needs sufficient running RPM/throttle. Ventage Jet uses a separate requested show trail; Extra and electric aircraft have no stock RC exhaust effect. [Feature and limits](SMOKE.md).

## 4. Settings and flight options

**Settings.** Home pins Fly and utility actions; scroll for Workshop, practice and RC cars. Settings (Home or Pause) covers windowed/borderless display, themed text size, opaque panels, reduced motion, language, sound, Controls and Help/About. Game and menu-cue volume preview live. Display previews revert after 15 seconds unless kept; Back discards unkept display changes, while language saves immediately. Preferences are separate from aircraft and controller profiles.

Current source adds **Settings → Graphics**: unlimited or 30/60/90/120/144/165/240 FPS,
VSync on/off and main-view MSAA off/2×/4×/8×. **Display → Window resolution** offers
720p through 4K, including 16:10 and ultrawide sizes, fitted to the available desktop.
Automatic preserves the window size at the start of a settings transaction;
borderless fullscreen uses the desktop resolution. Graphics changes preview immediately
and share the 15-second Keep/Revert recovery. Restore graphics defaults returns to
unlimited FPS, VSync on and 4× MSAA. These controls do not change flight physics.
VSync's effective state is displayed because the driver/compositor may override it.
**Scene detail** (Automatic, Low, Medium, High, Extreme) sets trees, props and model detail
from the next flight: Low and Medium draw all field trees as cards with fewer props, High
draws the trees in front of the pilot in 3D, and Extreme every nearby field tree. Automatic
(default) picks Low, Medium or High from your GPU at each launch; its tooltip names the GPU. Tree
collision is the same at every level. [Presets and measured cost](research/visual-quality-implementation/VQ-06b-scene-detail/README.md).
Workshop's separate preview images do not use the main-view MSAA setting.

From Home, **Graphics → Try High (restart)** starts a temporary experimental
Forward+ mode with ambient occlusion, soft sun shadows and sky reflections. Keep
display changes first. **Restart in Standard**, or close and launch normally, to
return to Standard. The restart action is unavailable during a flight or Workshop
session. [Trial scope, launch options and verified hardware](../tools/graphics/README.md).

Pause groups secondary actions under **Session options** and **Exit options**. Esc closes the top page or open group first; returning from Settings keeps the flight paused. Large text uses scrolling with focus following the selected action. The interactive UI scales automatically through native 4K without lowering 3D resolution. [Verification and remaining qualification](research/menu-investigations/UI-22-26-R1/README.md).

**Aircraft Workshop (Workbench).** Open it from Home or Pause to create experimental local builds, save revisions and test them from an airborne start. Adjustments depend on the aircraft's supported capabilities. [Workflow, current limits and development plan](AIRCRAFT-WORKSHOP.md).

Fresh Home preferences select Club field, gentle wind/gusts/turbulence, **Evening (time passing)**, scenery, birds, engine shadows and the live diagnostic marker. Saved choices take precedence. **Quick Flight** (`--quick-flight`) defaults to the Club field runway; add `--start=airborne` for airborne practice or `--landscape=green_paradise` for the flat grass landscape with an airborne start. Direct command-line flights ignore saved settings and use calm/reference weather and fixed daylight. Traces and captures retain their airborne reference start unless `--quick-flight` or `--start` is supplied.

**Flight overlays.** Home flights show data (speed, height, vertical speed, throttle, distance and time), transmitter sticks/trims, brief warnings, local wind and a **Control guide**. The guide opens by default with keyboard shortcuts or the selected controller's axes, remapped buttons and AUX assignments. Close overlays with ×; under Pause → **Flight overlays**, choose units, transmitter Mode 1/2 and JETI DS-24 II or Radiolink T16D artwork, or select presets with **F2** (cycle) and **F3** (developer). Choices save under `[hud]` in `settings.cfg`. Direct command-line flights keep legacy text unless `--hud=overlays`. [Plan](plans/flight-overlays.md).

**Battery (experimental).** Turbo Lumber Evolution uses a finite pack by default; **More flight details → Battery** selects ideal constant voltage. The pack sags under load, recovers at idle, warms and triggers 50% ESC power at low cells (**LVC · land now**). The overlay shows voltage, cell readings, current, power, temperature, mAh used and remaining percentage estimated from mAh, not true charge. Direct routes also use the pack; add `--battery=ideal` for constant voltage. [Plan](plans/battery-realism.md).

**Weather** sets uniform wind, repeating gusts, seeded turbulence, field elevation, temperature, QNH and humidity. Apply validates and saves; Cancel/Esc keeps the prior settings. Wind direction is where it comes from; positive vertical gusts point up. Restart repeats the forcing. These are practice conditions, not measured club weather. [Wind](WIND-PLAN.md) · [Atmosphere](ATMOSPHERE-PLAN.md).

**Time of day** selects day/dawn/dusk/night or an evening that advances at 20× simulation time. Pause can set exact date, time and location with a UTC offset. Visual time does not affect weather or flight physics. Stars, moonlight and experimental aircraft lights support night practice; Club field also has field lamps and a campfire. Readability needs pilot testing. [Lighting](TIME-OF-DAY-PLAN.md).

Flight includes per-wheel spin/contact and approximate tree/prop collision proxies. Home and direct flights retain crash aftermath until **R** or Pause → Restart; `--crash-effects=off` restores timed recovery. Light wingtip, tail or belly touches continue the flight; hard impacts end it (`--soft-contacts=off` makes any airframe touch a crash). Scripted/capture routes keep their technical policy. Flyable structural damage is unimplemented; collision accuracy and takeoff/landing calibration remain open. [Ground model](research/ground-physics/GP-05/README.md) · [Crash scope](CRASH-DAMAGE-PLAN.md).

**Updates.** Exported builds check GitHub once a day while Home is open, sending the app version and OS name. A newer release shows a card; **Download** opens the release page and **Hide** silences that version. Updates are manual: replace the extracted app folder; user settings and calibration remain. Disable checks with `check=false` under `[updates]` in `settings.cfg` (`%APPDATA%\Godot\app_userdata\OpenRC Simulator\` on Windows, `~/Library/Application Support/Godot/app_userdata/OpenRC Simulator/` on macOS, or `~/.local/share/godot/app_userdata/OpenRC Simulator/` on Linux). Source-tree builds do not check.

The Extra, P-51, Ventage Jet and Turbo Lumber Evolution remain experimental. Ventage Jet starts with gear down on the runway; its optional airborne start uses gear and flaps up. Turbo Lumber Evolution uses fixed landing gear, flaps up and assists off. Its motor losses and borrowed propeller map still need matched hardware measurements. Synthetic electric development fixtures remain separate from the catalog.

## 5. Measure frame times (for the landscape work)

Run from the extracted application's folder:

- PowerShell: `& '.\OpenRC Simulator.exe' -- --frametimes=frametimes.json --t=20`
- Linux: `./openrc-simulator.x86_64 -- --frametimes=frametimes.json --t=20`
- macOS: `"OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator" -- --frametimes=frametimes.json --t=20`

The app warms up for one second, records 20 seconds, writes the report and exits. Add `--disable-vsync` before `--` to measure beyond the display refresh cap. Include hardware, resolution and build identity when sharing results.

## 6. Tell us

Report build, aircraft, controller, operating system, maneuver, commanded input and expected/observed response. Identify any real RC model used for comparison. A **T** trace helps reproduce handling; visibility feedback benefits from distance, screenshot, resolution and auto-zoom state. [Pilot feedback](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=pilot_feedback.md).

## 7. Record a controller diagnostic (F1)

Replace the frame-time option above with `--input-report=input-report.json --t=20`. Move each stick through its full range. This standalone diagnostic writes a report and exits without starting flight or changing settings/calibration. The output folder must exist. With no output path, `--input-report` prints JSON; the default duration is 10 seconds.

The current source report records observed controllers, reconnects, axes/ranges, bounded button transitions and advertised capabilities. Press and release the buttons as well as moving the sticks. Unseen controls remain unknown. Event spacing measures Godot callbacks, not USB timing or stick-to-screen latency. Include firmware and USB/Bluetooth mode separately. [Diagnostic contract](TOOLS.md#radio-diagnostics).

## 8. Film stick-to-screen latency (F6a)

Use `-- --latency-patch` for a direct flight with a raw-input marker: axis 0 below zero is black, at/above zero is white; gray means inactive (pause, calibration, crash or disconnection). `--latency-axis=0..9` and `--latency-threshold=0.5` can select another crossing.

Film stick and screen together at 240 fps and use the [F6 protocol](research/radio-input/F6a/README.md#owner-camera-protocol-f6-still-pending). The marker does not calculate latency; physical acceptance remains open.
