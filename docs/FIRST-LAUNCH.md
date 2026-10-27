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

Home selects the aircraft, landscape, language, launch, weather and lighting. Menus support keyboard/mouse and an explicitly selected gamepad; a radio controls only flight. English is the default. The v0.1.8 download also offers Spanish; current source offers the additional languages listed in the [README](../README.md#current-features). Valid settings are remembered.

**Fly** starts the airplane directly when its controls are ready; no extra **Continue** is needed. Unready or unavailable controls open Pause for recovery.

Fresh settings select the Ugly Stik on the Club field runway: stopped near the threshold, landing gear down and throttle closed. Other airplanes with landing gear offer the same runway start. In current source, the gearless X8 offers a simulated hand launch instead; its release speed is an estimate, and the pilot must fly it after release ([details](research/skywalker-x8/X8-07/README.md)). **Start: in the air** is the other option: level flight at half throttle. Every airplane is trimmed the way a pilot trims a model, for level flight at 50% throttle, and the trim stays where it is until you move it ([why](research/flight-dynamics/power-climb-2026-10-19/README.md#d6e-r4-every-launch-trimmed-for-50--throttle)). Saved explicit choices take precedence, and Restart repeats the selected launch. Finite-glow aircraft, including the Extra, need **F7** to start; see the [engine guide](GLOW-ENGINES.md) and [flight options](#4-settings-and-flight-options).

An aircraft delivered with several paint schemes shows a **Paint** row at the top of the **Aircraft** page; the F4U Corsair offers thirteen in current source. Each click shows the next scheme on the backdrop, and every aircraft remembers its own. The scheme changes only the paint, never the flight model.

**Landscape** cycles between **Club field**, with its runway and scenery, and **Green paradise**, a flat grass surface without scenery objects or a lake. The backdrop updates immediately and the choice is remembered. To switch during a session, use **Pause → End flight → Home**, select the other landscape, then Fly. At Green, geared airplanes start airborne, the X8 offers hand launch or airborne starts, and the helicopter starts at hover. Natural Random requires Club field. RC-car courses are separate. [Landscape details and authoring](LANDSCAPES.md).

Home also offers two separate experimental activities, each with its own controls: [RC Helicopter Research Trainer](HELICOPTER.md) and [RC cars · Bisonte MT8 and MONSTER CAR 2](../research/rc-monster-truck/README.md).

**Esc** opens Pause; losing window focus also pauses. Continue resumes explicitly. Pause can restart, return to Home or quit. The direct CLI route has no Home to return to.

Current source records local fixed-wing flight statistics. Open **Home → Statistics · Pilot total**, **Aircraft → Aircraft statistics**, or **Pause → Statistics** for session/lifetime history and independent counter windows. The optional **Session statistics** flight overlay shows landings, crashes and restarts. Counter resets preserve history; history deletion is a separate confirmed action. See [Flight statistics](FLIGHT-STATISTICS.md) for counting rules, recovery and current limits.

| Key | Action |
| --- | --- |
| ← / → | Aileron / roll |
| ↓ / ↑ | Elevator / pitch; ↓ pulls the stick back |
| A / D | Rudder |
| W / S | Increase / decrease throttle |
| `[` / `]` | Aileron trim left / right |
| Page Up / Page Down | Elevator trim nose down / nose up, 0.1° per press |
| `,` / `.` | Rudder trim left / right, 0.5 % of the rudder throw per press (airplanes with a rudder) |
| Esc | Pause; cancel radio calibration |
| R | Restart flight |
| P | Resume after a radio failsafe |
| C · Shift+C | Next / previous view: pilot, chase, fly-by, orbit, close-up |
| 1 · 2 · 4 · 5 | Pilot · chase · fly-by · orbit view (2 again: 3D chase that leans with the model, for aerobatics; fly-by: a spectator ahead of the model, sun behind; orbit: drag with the right mouse button) |
| = · − · Backspace | Zoom in · out · reset (also the mouse wheel); in chase and orbit it moves the camera |
| Z | Toggle auto-zoom |
| V / L | Cycle ground-shadow aid / aircraft night lights |
| K · Enter | Start calibration · advance its step |
| F · Shift+F | Move equipped aircraft's flaps: next / previous |
| G / B | Toggle retractable gear / hold its wheel brakes |
| O | Fold or spread folding wings (F4U Corsair), on the ground and stopped; the throttle stays at idle until spread and locked |
| U · Y | Open or close the sliding canopy · lower or raise the tailhook (F4U Corsair); on the ground the hook rests on the runway |
| H | Toggle available smoke with keyboard controls |
| J · Enter | Assign the active radio's smoke AUX · advance its step |
| T | Start / save a flight trace |
| F10 / F11 | Start/stop flight log / mark a maneuver while recording |
| F3 | Toggle developer overlays |
| F2 | Cycle flight overlays: off / pilot / full / developer / player / all instruments / classic cockpit |
| F5 | Reload the aircraft data file |

Gear, brake, flap, smoke and glow shortcuts are limited to aircraft with those systems. Keys refer to physical QWERTY positions; in-game Help shows your keyboard's labels. At startup and on Home, a connected controller is selected automatically; with no devices, flight uses the keyboard. Controller settings can override that choice.

Keyboard, gamepad and configured joystick flights start in **sport** rates: full aileron travel, with the aircraft's normal elevator/rudder travel and keyboard expo. Gamepads apply their own deadzone/expo once; calibrated joysticks use the aircraft expo once. Profiles of type **Radio transmitter** keep their transmitter settings. **N**, the **left stick press (L3)** on a standard gamepad, or a remapped *Dual rates: normal / high* action switches between the selected high profile and normal low rates. The default pair is **sport ↔ normal**. `--rates=full` selects **full ↔ normal**, with maximum travel on every axis; `--rates=normal` retains the legacy low-start/full-high pair. The HUD shows the active profile. Near stall, full aileron can stall one wing: unload with the elevator and use normal rates when appropriate. [Handling evidence](research/aero-consistency/D11-R1/README.md).

In **Controls → Buttons**, remap *Dual rates: normal / high* to an unused joystick button or auxiliary axis, then Save. Unknown joysticks receive no guessed dual-rate button. Existing assignments and explicit Clear take priority over the gamepad default. Each press (or axis threshold crossing) toggles once; release before toggling again. A maintained switch position does not select a particular rate. The Control guide shows the actual assignment and active profile, including when a binding is missing. L3 retains its separate menu shortcut and helicopter trainer function. If your USB transmitter is unidentified, select **Radio transmitter · custom** so its own rates are preserved.

Vantage Jet keyboard pitch builds gradually over one second and returns promptly when released. Use short pulls and release as the flight path levels out. Holding Down still reaches the full normal elevator travel and can produce an accelerated stall, even at high speed. [Flight-response audit](research/avanti-realism/AV-17-R1/README.md).

Vantage Jet in **Normal** mode uses reduced gamepad elevator travel (±6° before trim) for short sticks. The revised wing polar gives a more gradual stall transition. Pull progressively and add power for a sustained climb; low energy or excessive angle of attack can still cause a stall. **Full** mode retains the maximum ±30° elevator travel and is very sensitive. RC radios retain their transmitter settings. [Gamepad flight correction](research/avanti-realism/AV-17-R2/README.md).

Its Normal gamepad rudder uses ±12° travel before trim and a brief progressive response (about 0.3 s to reach 95% of a held target or return). This softens the nose's swing when the stick centers; some aerodynamic return remains normal. The setting also reduces the coupled nosewheel steering command. Full mode and RC radios retain their existing rudder mapping. [Rudder-release evidence](research/avanti-realism/AV-17-R3/README.md).

Adjust elevator trim with **Page Up / Page Down** (Spanish keyboards: **RePág / AvPág**). Establish the desired speed and flight path with the sticks and throttle, then adjust trim to relieve the held elevator command. This is a fixed surface offset, not altitude hold; changes in power or speed may need another adjustment. The transmitter overlay shows the resulting trim. **R** restores the starting trim, unless trim practice keeps your trims (below). Trim keys are ignored while paused or replaying recorded inputs.

### Trim practice (current source)

**Home → Practice → Trim practice** starts airplanes naturally out of trim, as a newly built model is: it rolls, climbs, dives or turns with the sticks centred until you trim it out. Tick **Start with a naturally out-of-trim airplane** and choose the **intensity**: 0 % is perfectly trimmed, 100 % gives noticeable but realistic tendencies. Each airplane reacts with its own aerodynamics, so a sensitive aerobatic or jet model shows the same rigging error more than a stable trainer. The simulator never moves your trims.

- **First flight only:** the airplane starts out of trim on its first flight of the session. Your trims stay after crashes and restarts, and when you fly the same airplane again before quitting.
- **Every flight:** every new flight, restart or crash brings new tendencies, and the trims return to the starting trim. A radio keeps its own trims, so re-centre them yourself.

Trim with your radio's trim switches, the aileron/elevator/rudder trim keys above, or a gamepad's D-pad (aileron and elevator). Gamepad rudder trim has no default button; assign *Rudder trim left / right* under **Controls → Buttons**. Trim practice applies to Home airplane flights; Natural Random, helicopters and cars are unchanged. Technical routes accept `--out-of-trim=<0–100>`, `--out-of-trim-mode=first-flight|every-flight` and `--out-of-trim-seed=<n>`. [Model and evidence](research/radio-input/D6-TRIM-01/README.md).

### Controller settings (current source)

At startup and on Home, flight prefers a device with one matching saved profile, then a recognized radio, a mapped gamepad, or another joystick. Ties use the lowest current connection ID. Menus use the selected flight gamepad when eligible, otherwise the first eligible gamepad; radios and unconfigured joysticks never navigate menus. With no devices, flight uses **Keyboard** and menus use **Keyboard + mouse**. Recognized gamepads work with the Mode 2 preset without opening settings; unknown joysticks still need their axes configured before flight. A/Cross activates the focused menu button normally.

Open **Controller settings** from Home or Pause to override the automatic choices, then **Save**. This saves the profile and activates both controller choices together. A successful manual choice, including keyboard, remains in effect for this application run; unplugging that chosen device releases its role for automatic selection on Home. Selection waits while settings or another activity is open. A new connection never takes over an active flight. Keyboard and mouse remain available for menus.

Use the five sections: **Devices**, **Profile**, **Flight axes**, **Extra channels**, and **Buttons**. The selected devices, section navigation, validation messages and Save/Cancel stay visible while the section scrolls. Flight axes shows all four response previews alongside their settings. Buttons can filter **All**, **Flight**, **Camera**, **Auxiliary**, or **Menu** actions; filtering never changes assignments. D-pad/left stick and A/Cross operate the native controls. Switching sections or filters cancels an active remap and preserves the draft.

Choose **Mode 2** (left throttle/rudder, right roll/pitch), **Mode 1** (right throttle/roll, left pitch/rudder), or **absolute trigger throttle** for fixed-wing flight. Mode 1/2 throttle is incremental: pushing the throttle stick changes engine power; releasing it holds that power. The absolute trigger preset maps RT/R2 directly from idle to full power. It requires an independent analog trigger; use a stick-rate preset when a device exposes combined or digital triggers. Helicopter collective uses a stick-rate or calibrated radio profile, not the fixed-wing trigger preset.

If Save finds an invalid mapping, the affected fields are highlighted with explanations and the first error receives focus. Hidden action rows are revealed when needed. Fixing one error clears its markers while keeping other errors visible. A rejected remap or switch assignment keeps the previous assignment and identifies the conflicting controls.

Controller choices, mapping, inversion, gamepad deadzone/expo and action changes stay draft until **Save**. Switching profiles/devices keeps their drafts while this screen remains open. **Cancel** discards all edits; pending Home device detection can then update the automatic choice. Saving checks the selected activity and devices; a rejection keeps the draft open and restores the previous configuration. Profiles live in `user://controller_profiles.cfg`, with a transactional rollback copy. An unreadable store prevents flight-profile activation instead of silently using a factory mapping; successful rollback recovery also shows a notice. Legacy recovery copies a radio profile or restores a gamepad preset without deleting `rc_calibration.cfg`. Unknown devices require an explicitly configured profile; menu use additionally requires a saved gamepad profile with an unambiguous device association. Restarting the application restores automatic device selection and reuses matching profiles; connection IDs are never saved as device identities.

Choose automatic, Xbox, PlayStation, Nintendo or generic button prompts in the profile. A manual choice helps with emulated devices; it changes only labels and icons, never the bindings. The action list shows the actual remapped controls. Artwork is the free Kenney Input Prompts pack.

**JETI USB radios:** the app recognizes the DC/DS family from its complete USB identity plus a JETI name/descriptor, and offers a **JETI USB Mode 2** profile with absolute throttle. This starter uses the four axes supplied by JETI and leaves radio buttons unassigned. Existing saved profiles keep their calibration and assignments. In Profile, explicitly choose the **JETI Mode 2** preset or use **Use safe radio actions in draft** to remove inherited gamepad assignments from the draft, then Save. Cancel keeps the previous setup. A short family name identifies the radio; details/tooltips retain the backend name. Missing or contradictory identity data requires explicit configuration. Software support does not establish full model/firmware compatibility; see the [JETI evidence and remaining qualification](plans/jeti-support.md).

In Extra channels, choose **Switch positions** and two or three positions. Capture the actual Up, Middle (when installed) and Down buttons from the selected radio, or enter their observed indices. Add an optional physical name such as `Sa`; those configured positions then appear by name instead of gamepad glyphs. Changing a position to another button in the same group swaps them. Separate channels cannot share any group member. No Sa–Sj button map is assumed automatically.

A switch produces a maintained request, including a half-travel middle detent, rather than repeatedly toggling an action. After saving, pause/focus recovery or reconnection, deliberately return it to its zero/OFF position before using it; if already OFF, move away and back. Invert reverses the zero/full endpoints. Invalid or contradictory switch states disable that request until fresh OFF evidence is received. This equipment arming is separate from the radio's fresh low-throttle gate and explicit Continue.

Recognized gamepads with standard mapped axes become ready on the first valid live sample. There is no stick-wiggling, centering, button-release or timed arming step. Select **Continue** to resume an ordinary pause; moving a stick in Pause does not disable it. **Restart flight** resets the airplane and resumes immediately when controls are ready. An already armed radio remains ready under the same device/profile. Pause freezes incremental throttle and shows the value that Continue will use; a held throttle stick changes it only after resuming. Runway rate throttle starts at idle; airborne rate throttle uses the scenario power. Absolute-trigger throttle follows the current trigger value. Raw/nonstandard layouts still need configured channels and fresh input evidence. Radios retain their low-throttle arming requirement when selecting, reconnecting or recovering focus. Disconnects, uncertain continuity after suspension and profile changes pause and require explicit recovery; select **Keyboard** to return to keyboard flight.

Default buttons: **A/Cross** accept, **B/Circle** back, **Menu/Options** pause, **Y/Triangle** camera, right-stick click reset view, **X/Square** overlays, D-pad trims during flight, and held LB/L1 throttle cut for fixed-wing flight. D-pad/left stick navigate menus. Remaps are profile-specific. Ground driving keeps left-stick steering, RT drive, LT brake and B+RT reverse.

**Automatic aircraft controls:** on gamepad profiles, **A/Cross** cycles available flaps, **B/Circle** toggles retractable gear and **RB/R1** toggles available smoke. The P-51D and Vantage Jet receive flap and gear bindings; supported Stik, P-51D and stock Vantage Jet configurations receive the smoke binding. Automatic assignments use only free flight buttons, preserve explicit remaps and cleared actions, and yield to existing AUX assignments. A/Cross and B/Circle still mean Accept and Back in menus; release them before pressing again in flight. The Control guide shows this aircraft's equipment, actual binding, gear movement and smoke output. Unknown joysticks and RC radios keep their configured buttons; use **Remap** for their actual layout.

**Restart from the controller:** **View/Back** on Xbox or **Share/Create** on PlayStation restarts the selected flight, including from the accident report. Airplanes resume immediately when controls are ready; unready or unavailable controls keep Pause open for recovery. Helicopters retain explicit **Continue**. The flight controller owns this command even when another pad navigates menus. In Controller settings → Buttons → Flight, remap **Restart flight** to a button or an unused radio/joystick axis, then **Save**. An axis fires once when it crosses its threshold; return it toward OFF before restarting again. Settings/calibration cannot queue a restart from a held control. While an ordinary menu is open, use Pause's **Restart flight** action.

**Additional controls:** the action list also offers previous/direct pilot/chase/orbit cameras, zoom, auto zoom and lights. These remain unbound until assigned. Use **Clear** to free an existing assignment, then **Remap**, release the captured control and **Save**; Back and Pause must remain assigned. Disconnecting or changing the flight device cancels its pending capture. Primary flight axes cannot also trigger flight actions. The [helicopter defaults](HELICOPTER.md#historical-playable-reference-start-and-controls) assign arm, rotor hold, curve and trainer controls automatically, with the same saved remapping. [Cars](../research/rc-monster-truck/README.md#drive-and-experiment) use their own fixed driving scheme.

The **Extra channels** section maps smoke, flap requests and gear requests independently to an axis or a button. An axis uses calibrated OFF/ON endpoints; buttons can be maintained or toggle on each press. Available input slots are axes 0–9 and buttons 0–127, subject to what the device/backend actually exposes. Assign either an AUX source or semantic buttons to a function, not both. AUX channels cannot share a source or reuse a primary flight axis. After selection, pause/focus recovery or profile changes, return an AUX axis to OFF or release its button before use. Paused input cannot queue an AUX toggle. Vantage Jet flap positions are 0° retracted, 20° takeoff and 50° landing; **F** advances and **Shift+F** moves back. The radio AUX axis can request any intermediate position.

Review the effective action list after assigning AUX: an inherited flight button on the same source becomes Unbound. For a radio/joystick AUX on the inherited Pause button, Pause uses **Escape**; an explicitly remapped Pause is preserved and conflicts must be resolved before saving.

**Aircraft limits:** Vantage Jet has simulated retractable gear, including deployment, wheel contacts, drag and a retraction interlock while on its wheels. Fixed-gear aircraft cannot retract. Vantage Jet flaps move through the positions recommended in the [SebArt Avanti S 2.2m manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf): 0°, 20° takeoff and 50° landing. Its down-elevator mix scales with actual flap travel, to 8% of full elevator travel at 20° and 20% at 50°. The simulator shows requested and actual angle and an estimated overspeed advisory; it does not retract flaps automatically. Flap lift and drag behavior remains experimental. The P-51D also has simulated retractable taildragger gear and flaps at 0°, 15° takeoff and 45° landing, with an estimated 2.5-second flap travel time. Its aerodynamic calibration remains experimental. Other aircraft report flaps as unavailable. Stock Vantage Jet flights offer optional white tailpipe show smoke with H or smoke AUX; it follows the accepted turbine running state. This display does not simulate smoke-fluid consumption.

These are source features with automated checks, not a claim that every Xbox/PlayStation model or connection has been tested. [Implementation and remaining qualification](research/controller-support-2026-10-14/README.md#implementation-evidence).

### Radio setup

Connect in USB joystick mode with RF modules off. EdgeTX/OpenTX's Advanced joystick interface with at most eight axes is the starting configuration; mappings still depend on device, firmware and platform. The default channel order is AETR.

Before flying, open **Home → Controller settings**, select the radio, and choose **Calibrate selected radio**. If it appears as an unknown joystick, choose **Radio transmitter · custom** as its profile type first. Follow the steps with **Next** or **Enter**, choose **Use calibration**, then **Save** controller settings. This captures reduced hardware travel as well as reversed axes. The wizard changes only the draft; cancelling, losing focus or disconnecting leaves the previous draft intact. A connection change before Save requires recalibration. After saving, move throttle away from low and back to low to arm.

During a flight, **Pause → Controller settings → Calibrate selected radio**, or **K** outside menus, retains the flight wizard. Its calibration button saves and activates the chosen radio before starting; completion saves the calibration and leaves the flight paused. A separately selected menu gamepad can advance/cancel either wizard with A/B. Calibration is saved per radio; gamepads cannot enter this radio-only wizard. Unplugging pauses with idle throttle. Simulated-device tests do not certify your hardware.

On supported Stik, P-51D and stock Vantage Jet configurations, **J** opens a separate smoke-pump assignment: keep the control OFF, turn exactly one unused axis/button ON, then return it OFF, using Enter at each step. Buttons offer held-level or press-edge toggle. AETR axes cannot be assigned. The profile is saved per device; after assignment/reconnection, report OFF again before using smoke and rearm throttle before resuming. **H** controls the pump when no radio is connected. Ordinary engine exhaust is faint; the pump needs sufficient running RPM/throttle. Vantage Jet uses a separate requested show trail; Extra and electric aircraft have no stock RC exhaust effect. [Feature and limits](SMOKE.md).

## 4. Settings and flight options

The **Flight overlays** dialog has five sections: **Modern**, **Classic**, **Flight tools**, **Appearance** and **Other overlays**.
Preset and Units stay above the scrolling section, and Done stays below it. Use Appearance for widget size,
background, compact density, position lock and layout reset. Tabs support mouse and keyboard navigation; changing
a section does not change your flight layout. Developer overlays and transmitter options are under Other overlays.

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
**Birds** (Off, Few, Normal, Many) sets how many birds fly over the field: vultures and storks circling in
thermals, kites, swallows and evening swifts, chosen by time of day and weather. Normal follows Scene detail, Few
halves it, Many keeps full flocks at every level and Off sends them all away. The change applies at once, also from
the Pause menu: in flight the birds fly off or arrive over a minute or two. [Birds plan](plans/birds-sky-life.md).
Workshop's separate preview images do not use the main-view MSAA setting.
**Settings → Camera** sets the **First view** of flights from Home (pilot, chase, fly-by or orbit), the **Pilot field of view**
(30–70°, default 50°; about 30° shows the model at its real size on a 24–27-inch screen at arm's length), **Auto zoom**,
**Chase distance**, **Orbit sensitivity** and **Invert orbit up/down**. Changes apply at once, also from Pause; first view
waits for the next flight, and auto zoom and chase distance apply only when they change, so a view or zoom chosen in
flight with the keys stays. Command-line flights keep `--view` and `--autozoom`. Three pilot-view aids are off until
you try them: **Auto zoom** offers *Keeps looming* (the model still shrinks as it flies away) and *Gentle* beside the
default *Constant size*; **Keep the horizon in view** tilts the view down so the ground stays visible under a high
model; **Smooth overhead passes** stops the picture flipping when the model passes overhead (both share the **Pilot view
aids** picker); **Magnifier** adds a small window at the top that shows the model up close in the pilot view (Auto shows it
when the model gets small). [Camera plan](plans/camera-views.md).

From Home, **Graphics → Try High (restart)** starts a temporary experimental
Forward+ mode with ambient occlusion, soft sun shadows and sky reflections. Keep
display changes first. **Restart in Standard**, or close and launch normally, to
return to Standard. The restart action is unavailable during a flight or Workshop
session. [Trial scope, launch options and verified hardware](../tools/graphics/README.md).

Pause groups secondary actions under **Session options** and **Exit options**. Esc closes the top page or open group first; returning from Settings keeps the flight paused. Large text uses scrolling with focus following the selected action. The interactive UI scales automatically through native 4K without lowering 3D resolution. [Verification and remaining qualification](research/menu-investigations/UI-22-26-R1/README.md).

**Aircraft Workshop (Workbench).** Open it from Home or Pause to create experimental local builds, save revisions and test them from an airborne start. Adjustments depend on the aircraft's supported capabilities. [Workflow, current limits and development plan](AIRCRAFT-WORKSHOP.md).

Fresh Home preferences select Club field, gentle wind/gusts/turbulence, **Evening (time passing)**, scenery, birds, engine shadows and the live diagnostic marker. Saved choices take precedence. **Quick Flight** (`--quick-flight`) defaults to the Club field runway; add `--start=airborne` for airborne practice or `--landscape=green_paradise` for the flat grass landscape with an airborne start. Direct command-line flights ignore saved settings and use calm/reference weather and fixed daylight. Traces and captures retain their airborne reference start unless `--quick-flight` or `--start` is supplied.

**Flight overlays.** Home flights show data (speed, height, vertical speed, throttle, distance and time), transmitter sticks/trims, brief warnings, local wind and a **Control guide**. The guide opens by default with keyboard shortcuts or the selected controller's axes, remapped buttons and AUX assignments. Close overlays with ×; under Pause → **Flight overlays**, choose units, transmitter Mode 1/2 and JETI DS-24 II or Radiolink T16D artwork, or select presets with **F2** (cycle) and **F3** (developer). Choices save under `[hud]` in `settings.cfg`. Direct command-line flights keep legacy text unless `--hud=overlays`. [Plan](plans/flight-overlays.md).

**Player instruments.** Pause → Session options → Flight overlays → **Use player layout** enables four instruments: airspeed with recent trend, flight maximum and ground speed; height above terrain with climb/sink, pilot distance and flight time; battery estimate or finite fuel remaining; and wind speed, direction **from** which it blows (north up), and vertical air. The maximum uses 10 Hz samples and resets with the flight. Energy shows unavailable when the aircraft has no supported finite-energy reading. Drag each title to move it; × closes it. Individual switches reopen instruments, **Lock widget positions** prevents dragging, and **Reset widget positions** restores the four corners. Positions and visibility persist across launches; saved positions adapt to the viewport. Existing Pilot layouts remain unchanged.

Select **All instruments** to add **Fuel tank**, **Trims** and **Engine**, or enable them individually. Fuel shows accepted remaining percentage, mL and fuel mass in grams, with reserve warnings (including estimated reserves). Trims show signed aileron, elevator and rudder offsets as percentages of full travel, not degrees. Engine shows RPM, the simulation throttle command, and the aircraft's flight load in g. Unsupported readings remain unavailable. **Size** offers Small/Normal/Large; **Background** adjusts only the panel, preserving text opacity; **Compact instruments** reduces spacing and hides supplementary graphs while keeping values, warnings and trim bars. These choices save with the layout. At 720p, prefer compact instruments when showing all seven; arbitrary dragged layouts may overlap.

**Classic cockpit.** Select this preset in Flight overlays, or **Use cockpit layout**, for five optional round instruments: true airspeed, artificial horizon, altimeter, true heading and vertical speed. Individual switches allow mixing them with modern widgets. Drag the headers, close with ×, or use the shared size, background and position-lock options. Compact mode keeps the dials and numerical readout visible. The default 1080p layout raises the central horizon above bottom-centre notices. On narrow windows, show fewer dials or reposition them; custom layouts may overlap.

The horizon shows pitch and bank, including inverted flight. The altimeter reads height above the simulation datum, with a separate AGL readout; its long and short hands indicate hundreds and thousands of the selected unit. This is not a pressure altimeter. TAS is true airspeed, heading is true rather than magnetic, and the vario shows instantaneous vertical speed. A clipped needle is marked **Scale exceeded**, while its numerical value remains available. Missing telemetry suppresses the needle/horizon instead of implying zero.

When positions are unlocked, double-click a player widget's header to restore only that widget to its default position.
Hover an instrument's switch for its measurement description and missing-data behavior; the switch also reopens a closed widget.

**RC navigation.** In the Flight tools section, choose **Use RC navigation layout**, or enable its three widgets
individually. Pilot radar shows horizontal distance and aircraft position relative to the pilot, north up, with an
automatic range and recent position trail. Its centre is the pilot, not a recorded launch point. Wind & drift shows
ground track minus nose heading (positive to the right), plus heading-relative head/tailwind and wind blowing to
the left/right. Track is unavailable below 1 m/s. Cruise efficiency shows sampled electrical consumption per
ground distance in Wh/km or Wh/mi, power and a trend. It needs finite battery telemetry and at least two seconds
at 3 m/s or faster, using up to the last ten seconds. It measures consumption, not remaining range or return-home
reserve. Slow flight, missing readings, long sampling gaps and flight resets clear the estimate. Closing this
widget stops its sampling; reopening starts a fresh window. All three support dragging, ×, saved positions,
locking and shared size/background controls. Compact mode retains their navigation diagrams.

**Training instruments.** The Flight tools tab also offers **Use training layout** and three individual switches.
Maneuver meter shows signed body-axis load factor, bank, angle of attack, and sampled minimum/maximum load.
Its -4…+8 g arc clips with a **Scale exceeded** message while preserving the numerical value; it is not a
structural-limit warning. Glide monitor shows instantaneous vertical speed and a recent history. Its ground
glide ratio is horizontal ground speed divided by sink, shown only at >=3 m/s, <=5% throttle, <=20° bank and
more than 0.2 m/s descent. This is wind-dependent and is not aerodynamic L/D or an energy-compensated vario.
Flight summary shows simulation time since reset (including ground time), sampled maximum airspeed/AGL,
integrated ground-track distance and load extrema. Asterisked distance excludes missing or long sampling
intervals. Statistics continue while the widgets are closed and clear on flight reset. All three share the existing
drag, ×, lock, saved placement and appearance controls; compact mode keeps diagrams visible.

**Battery (experimental).** Turbo Lumber Evolution uses a finite pack by default; **More flight details → Battery** selects ideal constant voltage. The pack sags under load, recovers at idle, warms and triggers 50% ESC power at low cells (**LVC · land now**). The overlay shows voltage, cell readings, current, power, temperature, mAh used and remaining percentage estimated from mAh, not true charge. Direct routes also use the pack; add `--battery=ideal` for constant voltage. [Plan](plans/battery-realism.md).

**Weather** sets uniform wind, repeating gusts, seeded turbulence, field elevation, temperature, QNH and humidity. Apply validates and saves; Cancel/Esc keeps the prior settings. Wind direction is where it comes from; positive vertical gusts point up. Restart repeats the forcing. These are practice conditions, not measured club weather. [Wind](WIND-PLAN.md) · [Atmosphere](ATMOSPHERE-PLAN.md).

**Time of day** selects day/dawn/dusk/night or an evening that advances at 20× simulation time. Pause can set exact date, time and location with a UTC offset. Visual time does not affect weather or flight physics. Stars, moonlight and experimental aircraft lights support night practice; Club field also has field lamps and a campfire. Readability needs pilot testing. [Lighting](TIME-OF-DAY-PLAN.md).

Flight includes per-wheel spin/contact and approximate tree/prop collision proxies. Home and direct flights retain crash aftermath until **R** or Pause → Restart; `--crash-effects=off` restores timed recovery. Light wingtip, tail or belly touches continue the flight; hard impacts end it (`--soft-contacts=off` makes any airframe touch a crash). Scripted/capture routes keep their technical policy. Flyable structural damage is unimplemented; collision accuracy and takeoff/landing calibration remain open. [Ground model](research/ground-physics/GP-05/README.md) · [Crash scope](CRASH-DAMAGE-PLAN.md).

**Updates.** Exported builds check GitHub once a day while Home is open, sending the app version and OS name. A newer release shows a card; **Download** opens the release page and **Hide** silences that version. Updates are manual: replace the extracted app folder; user settings and calibration remain. Disable checks with `check=false` under `[updates]` in `settings.cfg` (`%APPDATA%\Godot\app_userdata\OpenRC Simulator\` on Windows, `~/Library/Application Support/Godot/app_userdata/OpenRC Simulator/` on macOS, or `~/.local/share/godot/app_userdata/OpenRC Simulator/` on Linux). Source-tree builds do not check.

The Extra, P-51, Vantage Jet and Turbo Lumber Evolution remain experimental. Vantage Jet starts with gear down on the runway; its optional airborne start uses gear and flaps up. Turbo Lumber Evolution uses fixed landing gear, flaps up and assists off. Its motor losses and borrowed propeller map still need matched hardware measurements. Synthetic electric development fixtures remain separate from the catalog.

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

Home flights leave the camera marker off by default. Enable it in Pause → Session options → Flight overlays → **Latency camera marker**. Its × closes it and saves that choice, including across pauses and later flights. Existing saved choices are preserved. Hidden markers stop sampling.

Use `-- --latency-patch` for a direct flight with a raw-input marker: axis 0 below zero is black, at/above zero is white; gray means inactive (pause, calibration, crash or disconnection). `--latency-axis=0..9` and `--latency-threshold=0.5` can select another crossing.

A centred axis at exactly zero is white with the default threshold. A steady white square is a threshold state, not a latency value or an error. Move the selected raw axis across the threshold to produce a black/white transition.

Film stick and screen together at 240 fps and use the [F6 protocol](research/radio-input/F6a/README.md#owner-camera-protocol-f6-still-pending). The marker does not calculate latency; physical acceptance remains open.
