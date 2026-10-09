# OpenRC Simulator: first launch

An alpha RC airplane simulator. Start with the Jensen Das Ugly Stik 60 and tell us how it feels compared with a real Stik. Extra 300S, P-51D and Avanti S are experimental flight models. Avanti uses a turbine and starts in the air with flaps and gear up. See the [aircraft table](../README.md#aircraft-hangar) for their status.

## 1. Download and check

From [Releases](https://github.com/bultodepapas/OpenRCsimulator/releases), download the ZIP for your computer. Choose the newest prerelease. `SHA256SUMS` lists each file's checksum. To check yours:

- **Linux:** `sha256sum -c SHA256SUMS --ignore-missing`
- **macOS:** `shasum -a 256 openrc-simulator-*.zip`, then compare with the matching entry in `SHA256SUMS`.
- **Windows (PowerShell):** `Get-FileHash .\openrc-simulator-*.zip`

## 2. First launch

The builds are not signed with a paid developer certificate, so each system warns the first time.

**macOS 15 Sequoia and later.** Right-click → Open no longer works.

1. Unzip and move **OpenRC Simulator.app** to Applications.
2. Double-click it. When macOS says it cannot be opened, click **Done**.
3. Open **System Settings → Privacy & Security** and scroll down. Click **Open Anyway** (it shows for about an hour after the blocked launch), enter your password and confirm.

After that it opens normally.

If macOS says the app "is damaged", run this once in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/OpenRC Simulator.app"
```

**Windows.** Unzip and run **OpenRC Simulator.exe**. If SmartScreen shows "Windows protected your PC", click **More info → Run anyway**. When *Smart App Control* is on, Windows blocks unsigned apps with no way to allow one app; you would need to turn Smart App Control off.

**Linux (x86_64).** Unzip, then run:

```sh
chmod +x openrc-simulator.x86_64
./openrc-simulator.x86_64
```

You need OpenGL 3.3 graphics.

## 3. Fly

Home lets you choose the aircraft and switch between English and Spanish. **Fly** starts in the air by default, trimmed for level flight (15 m/s for the Stik). In the current source build, the Stik also offers **Start: runway (experimental)**: click the start selector, or press Up from Fly and Enter, then Down and Enter to fly. The airplane starts at idle near the runway threshold. Fly remembers the choice; R, pause Restart and crash recovery use it again. Other aircraft start in the air.

Navigate menus with the keyboard or mouse; the radio controls only flight. **Esc** opens the pause menu with Continue, Restart flight, End flight and Quit. Losing window focus also pauses. The [runway flight card](research/menu-investigations/UI-06c/FLIGHT-CARD.md) describes the pending manual circuit trial. Direct CLI flights ignore the saved start choice.

| Control | Keyboard | Radio / gamepad |
| --- | --- | --- |
| Aileron, elevator | arrow keys | right stick (Mode 2) |
| Rudder | A / D | left stick, left–right |
| Throttle | W / S | left stick, up–down |
| Restart | R | |
| Pause menu | Esc | |
| Resume after a radio failsafe | P | |
| Camera: pilot / close-up | C | |
| Auto-zoom on / off | Z | |
| Ground shadow: sun / vertical / off | V | |
| Performance line on / off | F3 | |
| Record a flight trace | T | |
| Calibrate the radio | K, then Enter at each step (Esc cancels) | |

**A USB radio (EdgeTX/OpenTX) flies instead of the keyboard while it is connected.**

- **Recommended radio setup:** USB Joystick in *Advanced* mode, Interface = **Joystick**, at most 8 axes, RF modules off. On Linux, *Classic* mode makes the radio look like a gamepad.
- **Safety:** the engine stays at idle until you move the throttle stick to low. Unplugging the radio pauses the simulator with the engine at idle.
- **If the sticks are mapped wrong:** press **K** and follow the on-screen steps. The calibration is saved for that radio. After finishing, move the throttle away from low and back to low to arm; earlier calibration samples do not arm the engine.

Wheels can contact the ground for experimental landing and rollout. A hull strike or numerical fault freezes the scene for 1.5 s, showing the crash information, then the flight restarts.

## 4. What this build is (v0.1 alpha)

**It has:**

- full six-axis flight with prop torque and gyroscopic effects;
- stall at about 9 m/s and spins (recover with opposite rudder and the stick forward);
- servos, engine sound, a ground shadow and auto-zoom;
- Home, Help and pause menus in English and Spanish;
- a shared test field with sky, haze, clouds and three tree variants. Trees are visual only and have no collisions.

**It does not have yet:**

- validated takeoff/landing behavior or a guided circuit lesson (the Stik runway start is experimental; automated verification is not pilot acceptance);
- wind;
- validated engine response or recorded engine audio. RPM lag, P-51 shaft dynamics and Avanti turbine response are implemented but remain under evaluation.

## 5. Measure frame times (for the landscape work)

Builds from v0.1.0-rc2 on can write a frame-time report. Open a terminal in the folder with the app and run one of these:

- **Windows:** `"OpenRC Simulator.exe" -- --frametimes=frametimes.json --t=20`
- **Linux:** `./openrc-simulator.x86_64 -- --frametimes=frametimes.json --t=20`
- **macOS:** `"OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator" -- --frametimes=frametimes.json --t=20`

It flies for 21 seconds, writes `frametimes.json` and closes. Please send that file.

To measure beyond your screen's refresh rate, add `--disable-vsync` before the `--`.

## 6. Tell us

1. Fly three circuits, a loop, a roll, a stall and a spin recovery.
2. For roll, pitch, yaw and throttle, rate each one from **−2 (sluggish) to +2 (twitchy)** compared with a real Stik.
3. Note whether you can tell which way the airplane is facing at 100 m, with and without auto-zoom (Z).
4. Note how long the radio took to set up.
5. Note the numbers on the performance line (F3).

## 7. Record a controller diagnostic (F1)

In rc6 and later (or the current source tree), run from a terminal:

- **Windows:** `"OpenRC Simulator.exe" -- --input-report=input-report.json --t=20`
- **Linux:** `./openrc-simulator.x86_64 -- --input-report=input-report.json --t=20`
- **macOS:** `"OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator" -- --input-report=input-report.json --t=20`
- **Source:** `$(app/get-godot.sh) --path app -- --input-report=input-report.json --t=20`

Move every stick through its full range during those 20 seconds. The diagnostic collects controller events, writes the JSON report and closes; no flight starts and no settings or calibration change. The output folder must already exist. Without a path, `--input-report` prints JSON to the terminal; the default duration is 10 seconds.

The report lists all detected controllers, reconnects, observed axes and ranges. Unseen axes remain unknown. Its event spacing describes callbacks observed by Godot, not USB report timing or stick-to-screen latency. Include the radio firmware and USB mode separately when sharing the file; physical compatibility still needs a flight test.

## 8. Film stick-to-screen latency (F6a)

In rc6 and later, add `-- --latency-patch` to the executable command (source: `$(app/get-godot.sh) --path app -- --latency-patch`). This starts a normal flight with a black/white square. Move raw axis 0 first; black means below raw zero, white means at or above it. Gray means the measurement is inactive, including pause, calibration, crash or disconnection.

Optional `--latency-axis=0..9` and `--latency-threshold=0.5` select another raw axis or crossing. These values precede calibration and servo response. Film the stick and screen together at 240 fps; the marker itself does not record or calculate latency. Follow the [F6 camera protocol](research/radio-input/F6a/README.md#owner-camera-protocol-f6-still-pending) for at least 20 trials per display condition and retain the original footage. Physical F6 acceptance remains open.
