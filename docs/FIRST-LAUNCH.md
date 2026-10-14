# OpenRC Simulator: first launch

Status: v0.1.1 player guide, checked 2026-10-14. [v0.1.1 release notes](releases/v0.1.1.md) describe the download; [flight setup](#current-source) explains its defaults and features. Aircraft remain under evaluation; start with the [Ugly Stik](UGLY-STIK-PLAN.md).

## 1. Download and check

Download a platform ZIP and `SHA256SUMS` from [v0.1.1](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.1). Extract the ZIP before launching. Compare the archive's SHA-256 with its matching entry:

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

Home selects the aircraft, language, launch, weather and lighting. The rc8 package uses keyboard/mouse menus. Current source also supports an explicitly selected gamepad; a radio controls only flight. English is the default, Spanish is available, and valid settings are remembered.

Fresh settings select the Ugly Stik at idle near the runway threshold. Other flight-capable catalog aircraft start airborne. Saved choices take precedence; Restart repeats the selected launch. Select **Airborne**, **Calm** and **Day** for trimmed airborne practice. See [defaults and features](#current-source).

Home also offers two separate experimental activities, each with its own controls: [RC Helicopter Research Trainer](HELICOPTER.md) and [RC cars · Bisonte MT8](../research/rc-monster-truck/README.md).

**Esc** opens Pause; losing window focus also pauses. Continue resumes explicitly. Pause can restart, return to Home or quit. The direct CLI route has no Home to return to.

| Key | Action |
| --- | --- |
| ← / → | Aileron / roll |
| ↓ / ↑ | Elevator / pitch; ↓ pulls the stick back |
| A / D | Rudder |
| W / S | Increase / decrease throttle |
| Page Up / Page Down | Elevator trim nose down / nose up, 0.1° per press |
| Esc | Pause; cancel radio calibration |
| R | Restart flight |
| P | Resume after a radio failsafe |
| C · Shift+C | Next / previous view: pilot, chase, orbit, close-up |
| 1 · 2 · 5 | Pilot · chase · orbit view (orbit: drag with the right mouse button) |
| = · − · Backspace | Zoom in · out · reset (also the mouse wheel); in chase and orbit it moves the camera |
| Z | Toggle auto-zoom |
| V | Ground-shadow aid: sun / vertical / off |
| K · Enter | Start calibration · advance its step |
| H | Toggle the Stik smoke pump with keyboard controls |
| J · Enter | Assign the active radio's smoke AUX · advance its step |
| T | Start / save a flight trace |
| F3 | Toggle developer overlays |
| F2 | Cycle flight overlays: off / pilot / full / developer |
| F5 | Reload the aircraft data file |

Letters refer to physical QWERTY positions; in-game Help shows your keyboard's labels. In current source, choose a controller explicitly in Controller settings; merely plugging one in does not replace keyboard flight sticks.

Keyboard sticks use aircraft normal rates/expo where specified. Gamepads apply their own scalar deadzone/expo once, followed by aircraft travel rates and trims; radios keep their own rates and curves. The direct route's `--rates=full` flies maximum throws.

Adjust elevator trim with **Page Up / Page Down** (Spanish keyboards: **RePág / AvPág**). Establish the desired speed and flight path with the sticks and throttle, then adjust trim to relieve the held elevator command. This is a fixed surface offset, not altitude hold; changes in power or speed may need another adjustment. The transmitter overlay shows the resulting trim. **R** restores the starting trim. Trim keys are ignored while paused or replaying recorded inputs.

### Controller settings (current source)

Open **Controller settings** from Home or Pause. With no menu controller selected, **A / Cross** on a recognized gamepad claims menu navigation and opens settings. Choose the flight controller and optional separate menu gamepad, then **Apply device selection**. Keyboard and mouse remain available. A new connection never takes over a flight.

Choose **Mode 2** (left throttle/rudder, right roll/pitch), **Mode 1** (right throttle/roll, left pitch/rudder), or **absolute trigger throttle** for fixed-wing flight. Mode 1/2 throttle is incremental: pushing the throttle stick changes engine power; releasing it holds that power. The absolute trigger preset maps RT/R2 directly from idle to full power. It requires an independent analog trigger; use a stick-rate preset when a device exposes combined or digital triggers. Helicopter collective uses a stick-rate or calibrated radio profile, not the fixed-wing trigger preset.

Mapping, inversion, gamepad deadzone/expo and action changes stay draft until **Save**. **Cancel** discards profile edits; an already applied device selection remains applied. Profiles live in `user://controller_profiles.cfg`, with a rollback copy. Legacy recovery copies a radio profile or restores a gamepad preset without deleting `rc_calibration.cfg`. Unknown devices require an explicitly configured profile; menu use additionally requires a saved gamepad profile with an unambiguous device association. Reconfirm role selection after restarting the application.

Choose automatic, Xbox, PlayStation, Nintendo or generic button prompts in the profile. A manual choice helps with emulated devices; it changes only labels and icons, never the bindings. The action list shows the actual remapped controls. Artwork is the free Kenney Input Prompts pack.

On first selection, profile replacement or gamepad focus recovery, move every mapped flight control once, release sticks/triggers/buttons, and wait for neutral. Then choose **Continue**. Runway rate throttle starts at idle; airborne rate throttle uses the declared scenario power on explicit resume. Pause shows the throttle or collective value before continuing. Menus and ordinary focus loss freeze current rate throttle. Disconnects, uncertain continuity after suspension and profile changes pause and require explicit recovery; select **No flight controller** to deliberately return to keyboard flight.

Default buttons: **A/Cross** accept, **B/Circle** back, **Menu/Options** pause, **Y/Triangle** camera, right-stick click reset view, **X/Square** overlays, D-pad trims during flight, and held LB/L1 throttle cut for fixed-wing flight. D-pad/left stick navigate menus. Remaps are profile-specific. Ground driving keeps left-stick steering, RT drive, LT brake and B+RT reverse.

These are source features with automated checks, not a claim that every Xbox/PlayStation model or connection has been tested. [Implementation and remaining qualification](research/controller-support-2026-10-14/README.md#implementation-evidence).

### Radio setup

Connect in USB joystick mode with RF modules off. EdgeTX/OpenTX's Advanced joystick interface with at most eight axes is the starting configuration; mappings still depend on device, firmware and platform. The default channel order is AETR.

Select the radio in Controller settings, then move throttle to low to arm. If channels or directions are wrong, use **Calibrate selected radio** from Pause → Controller settings, or **K** outside menus. Follow the steps with **Enter**, then move throttle away from low and back to low to rearm. A separately selected menu gamepad can advance/cancel the wizard with A/B. Calibration is saved per radio; gamepads cannot enter this radio-only wizard. Unplugging pauses with idle throttle. Simulated-device tests do not certify your hardware.

On the Stik, **J** opens a separate smoke-pump assignment: keep the control OFF, turn exactly one unused axis/button ON, then return it OFF, using Enter at each step. Buttons offer held-level or press-edge toggle. AETR axes cannot be assigned. The profile is saved per device; after assignment/reconnection, report OFF again before using smoke and rearm throttle before resuming. **H** controls the pump when no radio is connected. Ordinary glow exhaust is faint; the pump needs sufficient running RPM/throttle. Other aircraft currently have no configured smoke installation. [Feature and limits](SMOKE-PLAN.md).

## Current source

Fresh Home preferences also select gentle wind/gusts/turbulence, **Evening (time passing)**, scenery, birds, engine shadows and the live diagnostic marker. Saved choices take precedence. Direct command-line flights ignore saved settings and default to airborne, calm/reference weather and fixed daylight.

**Flight overlays.** Home flights show separate overlays instead of the diagnostic text: flight data (airspeed, ground speed, height above ground, vertical speed, throttle, distance from you, flight time), the transmitter's sticks and trims, short warnings (radio safe, failsafe, stall, sinking low, too far, battery) and the wind seen from where you stand. Telemetry and the developer diagnostics are optional. Close any overlay with its ×, press **F2** to cycle presets, **F3** for the developer overlays, or choose overlays, units (km/h, mph or m/s; by language by default) and transmitter Mode 1/2 under Pause → **Flight overlays**. The choice is saved under `[hud]` in `settings.cfg`. Direct command-line flights keep the legacy text unless `--hud=overlays`. [Plan](plans/flight-overlays.md).

**Weather** edits spatially uniform wind, repeating gusts, seeded temporal turbulence, field elevation, temperature, QNH and humidity. Apply validates and saves; Cancel/Esc keeps the previous settings. Wind direction is where it comes from; positive vertical gusts point upward. Restart repeats the configured forcing. These are authored practice conditions, not measured weather at a club. [Wind](WIND-PLAN.md) · [Atmosphere](ATMOSPHERE-PLAN.md).

**Time of day** selects fixed day/dawn/dusk/night or passing evening. Evening advances visual time at 20× simulation time. Pause also offers exact time/date/location editing with an explicit UTC offset. Visual time does not change weather or flight physics. Stars, moonlight, field lamps and an experimental aircraft light kit support night practice; readability still needs pilot testing. [Lighting](TIME-OF-DAY-PLAN.md).

Flight includes per-wheel spin/contact and approximate static tree/prop collision proxies. Ordinary Home and direct flights enable crash effects and retain the aftermath until **R** or Pause → Restart. `--crash-effects=off` restores timed recovery; scripted/capture routes keep their technical policy. A light wingtip, tail or belly touch continues the flight; only a hard impact ends it (`--soft-contacts=off` restores "any airframe contact is a crash"). Deformation, damage severity and collision proxies are engineering approximations. Flyable structural damage, surveyed collision terrain and calibrated takeoff/landing behavior are not implemented or accepted. [Ground model](research/ground-physics/GP-05/README.md) · [Crash scope](CRASH-DAMAGE-PLAN.md).

**Updates.** While Home is open, an exported build asks GitHub once a day whether a newer release is published: one anonymous HTTPS request to `api.github.com` carrying only the app version and the OS name. A newer version shows a small card at the top right. **Download** opens the release page in your browser, where the three ZIPs, `SHA256SUMS` and the release notes are; **Hide** silences that version until a newer one exists. Updating is manual: download the ZIP for your platform and replace the extracted folder; settings and calibration live in your user data folder and are kept. To turn the check off, set `check=false` under `[updates]` in `settings.cfg` (Windows `%APPDATA%\Godot\app_userdata\OpenRC Simulator\`, macOS `~/Library/Application Support/Godot/app_userdata/OpenRC Simulator/`, Linux `~/.local/share/godot/app_userdata/OpenRC Simulator/`). Builds run from the source tree do not check.

The Extra, P-51, Ventage Jet and Turbo Lumber Evolution remain experimental. Ventage Jet starts airborne with gear and flaps up. Turbo Lumber Evolution flies with fixed wheels, flaps up, assists off and a prescribed 4S bus; battery depletion is not modeled. Its motor losses and borrowed propeller map need matched hardware measurements. Synthetic electric development fixtures remain separate from the catalog.

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
