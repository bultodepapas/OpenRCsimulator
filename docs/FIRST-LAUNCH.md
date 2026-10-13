# OpenRC Simulator: first launch

Status: rc8 player guide, checked 2026-10-12. [rc8 release notes](releases/v0.1.0-rc8.md) describe the download; [flight setup](#current-source) explains its defaults and features. Aircraft remain under evaluation; start with the [Ugly Stik](UGLY-STIK-PLAN.md).

## 1. Download and check

Download a platform ZIP and `SHA256SUMS` from [rc8](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8). Extract the ZIP before launching. Compare the archive's SHA-256 with its matching entry:

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

Home selects the aircraft, language, launch, weather and lighting. Menus use keyboard or mouse; a radio controls only flight. English is the default, Spanish is available, and valid settings are remembered.

In **rc8**, new preferences select the Stik at idle near the runway threshold, gentle wind and passing evening. Select **Airborne**, **Calm** and **Day** for trimmed airborne practice. Other flight-capable catalog aircraft start airborne. Saved choices take precedence; Restart uses the selected launch. Details are [below](#current-source).

**Esc** opens Pause; losing window focus also pauses. Continue resumes explicitly. Pause can restart, return to Home or quit. The direct CLI route has no Home to return to.

| Key | Action |
| --- | --- |
| ← / → | Aileron / roll |
| ↓ / ↑ | Elevator / pitch; ↓ pulls the stick back |
| A / D | Rudder |
| W / S | Increase / decrease throttle |
| Esc | Pause; cancel radio calibration |
| R | Restart flight |
| P | Resume after a radio failsafe |
| C | Pilot view / close-up |
| Z | Toggle auto-zoom |
| V | Ground-shadow aid: sun / vertical / off |
| K · Enter | Start calibration · advance its step |
| T | Start / save a flight trace |
| F3 | Toggle performance numbers |
| F5 | Reload the aircraft data file |

Letters refer to physical QWERTY positions; in-game Help shows your keyboard's labels. A connected USB radio/gamepad replaces the keyboard flight sticks.

Keyboard and gamepad sticks use the aircraft's normal-flight dual rates and expo where its manual states them (Extra, P-51, Avanti; the status line shows `rates: normal`); a radio keeps its own rates. The direct route's `--rates=full` flies the maximum throws, as the Ugly Stik always does.

### Radio setup

Connect in USB joystick mode with RF modules off. EdgeTX/OpenTX's Advanced joystick interface with at most eight axes is the starting configuration; mappings still depend on device, firmware and platform. The default channel order is AETR.

Move throttle to low to arm. If channels or directions are wrong, press **K**, follow the on-screen steps with **Enter**, then move throttle away from low and back to low to rearm. Calibration is saved per radio. Unplugging pauses with idle throttle. Simulated-device tests do not certify your hardware.

## Current source

New Home preferences select the Stik runway launch, gentle wind/gusts/turbulence, **Evening (time passing)**, scenery, birds, engine shadows and the live diagnostic marker. Existing explicit choices take precedence. Choose **Airborne**, **Calm** and **Day** for the earlier practice setup. Direct command-line flights ignore saved settings and default to airborne, calm/reference weather and fixed daylight.

**Weather** edits spatially uniform wind, repeating gusts, seeded temporal turbulence, field elevation, temperature, QNH and humidity. Apply validates and saves; Cancel/Esc keeps the previous settings. Wind direction is where it comes from; positive vertical gusts point upward. Restart repeats the configured forcing. These are authored practice conditions, not measured weather at a club. [Wind](WIND-PLAN.md) · [Atmosphere](ATMOSPHERE-PLAN.md).

**Time of day** selects fixed day/dawn/dusk/night or passing evening. Evening advances visual time at 20× simulation time. Pause also offers exact time/date/location editing with an explicit UTC offset. Visual time does not change weather or flight physics. Stars, moonlight, field lamps and an experimental aircraft light kit support night practice; readability still needs pilot testing. [Lighting](TIME-OF-DAY-PLAN.md).

Current source includes per-wheel spin/contact and approximate static tree/prop collision proxies. Ordinary Home and direct flights enable crash effects and retain the aftermath until **R** or Pause → Restart. `--crash-effects=off` restores timed recovery; scripted/capture routes keep their technical policy. Deformation, damage severity and collision proxies are engineering approximations. Flyable structural damage, surveyed collision terrain and calibrated takeoff/landing behavior are not implemented or accepted. [Ground model](research/ground-physics/GP-05/README.md) · [Crash scope](CRASH-DAMAGE-PLAN.md).

**Updates.** While Home is open, an exported build asks GitHub once a day whether a newer release is published: one anonymous HTTPS request to `api.github.com` carrying only the app version and the OS name. A newer version shows a small card at the top right. **Download** opens the release page in your browser, where the three ZIPs, `SHA256SUMS` and the release notes are; **Hide** silences that version until a newer one exists. Updating is manual: download the ZIP for your platform and replace the extracted folder; settings and calibration live in your user data folder and are kept. To turn the check off, set `check=false` under `[updates]` in `settings.cfg` (Windows `%APPDATA%\Godot\app_userdata\OpenRC Simulator\`, macOS `~/Library/Application Support/Godot/app_userdata/OpenRC Simulator/`, Linux `~/.local/share/godot/app_userdata/OpenRC Simulator/`). Builds run from the source tree do not check.

The Extra, P-51 and Avanti remain experimental. Avanti starts airborne with gear and flaps up. Electric development fixtures are not selectable catalog aircraft. Turbo Lumber Evolution is a selectable visual preview; Fly is unavailable until its flight data and propulsion are integrated.

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

The report records observed controllers, reconnects, axes and ranges. Unseen axes remain unknown. Event spacing measures Godot callbacks, not USB timing or stick-to-screen latency. Include firmware and USB mode separately. [Diagnostic contract](TOOLS.md#radio-diagnostics).

## 8. Film stick-to-screen latency (F6a)

Use `-- --latency-patch` for a direct flight with a raw-input marker: axis 0 below zero is black, at/above zero is white; gray means inactive (pause, calibration, crash or disconnection). `--latency-axis=0..9` and `--latency-threshold=0.5` can select another crossing.

Film stick and screen together at 240 fps and use the [F6 protocol](research/radio-input/F6a/README.md#owner-camera-protocol-f6-still-pending). The marker does not calculate latency; physical acceptance remains open.
