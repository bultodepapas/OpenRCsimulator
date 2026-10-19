# OpenRC Simulator: first launch

Status: current-source player guide, checked 2026-10-19. [v0.1.3](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.3) is the latest stable software release for this early-alpha simulator. Aircraft models and experimental activities still require independent physical and pilot validation; automated checks do not establish flight accuracy. See the [v0.1.3 release notes](releases/v0.1.3.md). Current-source features may differ from the v0.1.3 package. Start with the [Ugly Stik](UGLY-STIK-PLAN.md).

## 1. Download and check

Download the latest stable release, [v0.1.3](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.3). Download a platform ZIP and `SHA256SUMS` from that release. Extract the ZIP before launching. Compare the archive's SHA-256 with its matching entry:

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

Home selects the aircraft, language, launch, weather and lighting. Menus support keyboard/mouse and an explicitly selected gamepad; a radio controls only flight. English is the default, Spanish is available, and valid settings are remembered.

Fresh settings select the Ugly Stik on the runway. Every flight-capable catalog airplane supports this default: stopped near the threshold, landing gear down and throttle closed. Changing airplanes keeps the runway selection. **Start: in the air** is the next option for trimmed airborne practice; saved explicit choices take precedence, and Restart repeats the selected launch. Glow-engine Stik variants need **F7** to start; see the [engine guide](GLOW-ENGINES.md) and [flight options](#4-settings-and-flight-options).

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
| H | Toggle the Stik smoke pump with keyboard controls |
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

Recognized gamepads with standard mapped axes become ready on the first valid live sample. There is no stick-wiggling, centering, button-release or timed arming step. Select **Continue** to resume; moving a stick in Pause does not disable it. **Restart flight** resets the aircraft and confirms the restart. Pause freezes incremental throttle and shows the value that Continue will use; a held throttle stick changes it only after resuming. Runway rate throttle starts at idle; airborne rate throttle uses the scenario power. Absolute-trigger throttle follows the current trigger value. Raw/nonstandard layouts still need configured channels and fresh input evidence. Radios retain their low-throttle arming requirement. Disconnects, uncertain continuity after suspension and profile changes pause and require explicit recovery; select **Keyboard** to return to keyboard flight.

Default buttons: **A/Cross** accept, **B/Circle** back, **Menu/Options** pause, **Y/Triangle** camera, right-stick click reset view, **X/Square** overlays, D-pad trims during flight, and held LB/L1 throttle cut for fixed-wing flight. D-pad/left stick navigate menus. Remaps are profile-specific. Ground driving keeps left-stick steering, RT drive, LT brake and B+RT reverse.

**Automatic aircraft controls:** on gamepad profiles, **A/Cross** cycles available flaps, **B/Circle** toggles retractable gear and **RB/R1** toggles an installed smoke pump. The P-51D and Ventage Jet receive flap and gear bindings; the Stik receives the smoke binding. Automatic assignments use only free flight buttons, preserve explicit remaps and cleared actions, and yield to existing AUX assignments. A/Cross and B/Circle still mean Accept and Back in menus; release them before pressing again in flight. The Control guide shows this aircraft's equipment, actual binding, gear movement and smoke output. Unknown joysticks and RC radios keep their configured buttons; use **Remap** for their actual layout.

**Restart from the controller:** **View/Back** on Xbox or **Share/Create** on PlayStation restarts the selected flight, including from the accident report, then opens Pause for explicit **Continue**. The flight controller owns this command even when another pad navigates menus. In Controller settings → Buttons → Flight, remap **Restart flight** to a button or an unused radio/joystick axis, then **Save**. An axis fires once when it crosses its threshold; return it toward OFF before restarting again. Settings/calibration cannot queue a restart from a held control. While an ordinary menu is open, use Pause's **Restart flight** action.

**Additional controls:** the action list also offers previous/direct pilot/chase/orbit cameras, zoom, auto zoom and lights. These remain unbound until assigned. Use **Clear** to free an existing assignment, then **Remap**, release the captured control and **Save**; Back and Pause must remain assigned. Disconnecting or changing the flight device cancels its pending capture. Primary flight axes cannot also trigger flight actions. The [helicopter defaults](HELICOPTER.md#historical-playable-reference-start-and-controls) assign arm, rotor hold, curve and trainer controls automatically, with the same saved remapping. [Cars](../research/rc-monster-truck/README.md#drive-and-experiment) use their own fixed driving scheme.

The **Extra channels** section maps smoke, flap requests and gear requests independently to an axis or a button. An axis uses calibrated OFF/ON endpoints; buttons can be maintained or toggle on each press. Available input slots are axes 0–9 and buttons 0–127, subject to what the device/backend actually exposes. Assign either an AUX source or semantic buttons to a function, not both. AUX channels cannot share a source or reuse a primary flight axis. After selection, pause/focus recovery or profile changes, return an AUX axis to OFF or release its button before use. Paused input cannot queue an AUX toggle. Ventage Jet flap positions are 0° retracted, 20° takeoff and 50° landing; **F** advances and **Shift+F** moves back. The radio AUX axis can request any intermediate position.

Review the effective action list after assigning AUX: an inherited flight button on the same source becomes Unbound. For a radio/joystick AUX on the inherited Pause button, Pause uses **Escape**; an explicitly remapped Pause is preserved and conflicts must be resolved before saving.

**Aircraft limits:** Ventage Jet has simulated retractable gear, including deployment, wheel contacts, drag and a retraction interlock while on its wheels. Fixed-gear aircraft cannot retract. Ventage Jet flaps move through the positions recommended in the [SebArt Avanti S 2.2m manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf): 0°, 20° takeoff and 50° landing. Its down-elevator mix scales with actual flap travel, to 8% of full elevator travel at 20° and 20% at 50°. The simulator shows requested and actual angle and an estimated overspeed advisory; it does not retract flaps automatically. Flap lift and drag behavior remains experimental. The P-51D also has simulated retractable taildragger gear and flaps at 0°, 15° takeoff and 45° landing, with an estimated 2.5-second flap travel time. Its aerodynamic calibration remains experimental. Other aircraft report flaps as unavailable. The jet has no implemented smoke emitter/pump; the guide reports it as unavailable. An inventory description mentioning smoke hardware does not enable that function.

These are source features with automated checks, not a claim that every Xbox/PlayStation model or connection has been tested. [Implementation and remaining qualification](research/controller-support-2026-10-14/README.md#implementation-evidence).

### Radio setup

Connect in USB joystick mode with RF modules off. EdgeTX/OpenTX's Advanced joystick interface with at most eight axes is the starting configuration; mappings still depend on device, firmware and platform. The default channel order is AETR.

Select the radio in Controller settings and Save, then move throttle to low to arm. If channels or directions are wrong, use **Calibrate selected radio** from Pause → Controller settings, or **K** outside menus. The calibration button saves and activates the chosen radio before opening its wizard. Follow the steps with **Enter**, then move throttle away from low and back to low to rearm. A separately selected menu gamepad can advance/cancel the wizard with A/B. Calibration is saved per radio; gamepads cannot enter this radio-only wizard. Unplugging pauses with idle throttle. Simulated-device tests do not certify your hardware.

On the Stik, **J** opens a separate smoke-pump assignment: keep the control OFF, turn exactly one unused axis/button ON, then return it OFF, using Enter at each step. Buttons offer held-level or press-edge toggle. AETR axes cannot be assigned. The profile is saved per device; after assignment/reconnection, report OFF again before using smoke and rearm throttle before resuming. **H** controls the pump when no radio is connected. Ordinary glow exhaust is faint; the pump needs sufficient running RPM/throttle. Other aircraft currently have no configured smoke installation. [Feature and limits](SMOKE-PLAN.md).

## 4. Settings and flight options

**Settings.** Home pins Fly and utility actions; scroll for Workshop, practice and RC cars. Settings (Home or Pause) covers windowed/borderless display, themed text size, opaque panels, reduced motion, language, sound, Controls and Help/About. Game and menu-cue volume preview live. Display previews revert after 15 seconds unless kept; Back discards unkept display changes, while language saves immediately. Preferences are separate from aircraft and controller profiles.

Pause groups secondary actions under **Session options** and **Exit options**. Esc closes the top page or open group first; returning from Settings keeps the flight paused. Large text uses scrolling with focus following the selected action. The interactive UI scales automatically through native 4K without lowering 3D resolution. [Verification and remaining qualification](research/menu-investigations/UI-22-26-R1/README.md).

**Aircraft Workshop (Workbench).** Open it from Home or Pause to create experimental local builds, save revisions and test them from an airborne start. Adjustments depend on the aircraft's supported capabilities. [Workflow, current limits and development plan](AIRCRAFT-WORKSHOP.md).

Fresh Home preferences select gentle wind/gusts/turbulence, **Evening (time passing)**, scenery, birds, engine shadows and the live diagnostic marker. Saved choices take precedence. **Quick Flight** (`--quick-flight`) defaults to the runway; add `--start=airborne` for airborne practice. Direct command-line flights ignore saved settings and use calm/reference weather and fixed daylight. Traces and captures retain their airborne reference start unless `--quick-flight` or `--start` is supplied.

**Flight overlays.** Home flights show data (speed, height, vertical speed, throttle, distance and time), transmitter sticks/trims, brief warnings, local wind and a **Control guide**. The guide opens by default with keyboard shortcuts or the selected controller's axes, remapped buttons and AUX assignments. Close overlays with ×; under Pause → **Flight overlays**, choose units and transmitter Mode 1/2, or select presets with **F2** (cycle) and **F3** (developer). Choices save under `[hud]` in `settings.cfg`. Direct command-line flights keep legacy text unless `--hud=overlays`. [Plan](plans/flight-overlays.md).

**Battery (experimental).** Turbo Lumber Evolution uses a finite pack by default; **More flight details → Battery** selects ideal constant voltage. The pack sags under load, recovers at idle, warms and triggers 50% ESC power at low cells (**LVC · land now**). The overlay shows voltage, cell readings, current, power, temperature, mAh used and remaining percentage estimated from mAh, not true charge. Direct routes also use the pack; add `--battery=ideal` for constant voltage. [Plan](plans/battery-realism.md).

**Weather** sets uniform wind, repeating gusts, seeded turbulence, field elevation, temperature, QNH and humidity. Apply validates and saves; Cancel/Esc keeps the prior settings. Wind direction is where it comes from; positive vertical gusts point up. Restart repeats the forcing. These are practice conditions, not measured club weather. [Wind](WIND-PLAN.md) · [Atmosphere](ATMOSPHERE-PLAN.md).

**Time of day** selects day/dawn/dusk/night or an evening that advances at 20× simulation time. Pause can set exact date, time and location with a UTC offset. Visual time does not affect weather or flight physics. Stars, moonlight, field lamps and experimental aircraft lights support night practice; readability needs pilot testing. [Lighting](TIME-OF-DAY-PLAN.md).

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
