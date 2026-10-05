# OpenRC Simulator: first launch

A test build of an RC airplane simulator: a Das Ugly Stik 60 with a .61 glow engine. The airplane starts in the air, already trimmed for level flight at 15 m/s. Please fly it and tell us how it feels compared with a real Stik.

## 1. Download and check

From the release page, download the zip for your computer. `SHA256SUMS` lists each file's checksum. To check yours:

- **Linux or macOS:** `sha256sum -c SHA256SUMS --ignore-missing`
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

| Control | Keyboard | Radio / gamepad |
| --- | --- | --- |
| Aileron, elevator | arrow keys | right stick (Mode 2) |
| Rudder | A / D | left stick, left–right |
| Throttle | W / S | left stick, up–down |
| Restart | R | |
| Resume after a pause | P | |
| Camera: pilot / close-up | C | |
| Auto-zoom on / off | Z | |
| Performance line on / off | F3 | |
| Record a flight trace | T | |
| Calibrate the radio | K, then Enter at each step (Esc cancels) | |

**A USB radio (EdgeTX/OpenTX) flies instead of the keyboard while it is connected.**

- **Recommended radio setup:** USB Joystick in *Advanced* mode, Interface = **Joystick**, at most 8 axes, RF modules off. On Linux, *Classic* mode makes the radio look like a gamepad.
- **Safety:** the engine stays at idle until you move the throttle stick to low. Unplugging the radio pauses the simulator with the engine at idle.
- **If the sticks are mapped wrong:** press **K** and follow the on-screen steps. The calibration is saved for that radio.

A crash freezes the scene for 1.5 s, showing the impact speed, then the flight restarts.

## 4. What this build is (v0.1 alpha)

**It has:**

- full six-axis flight with prop torque and gyroscopic effects;
- stall at about 9 m/s and spins (recover with opposite rudder and the stick forward);
- servos, engine sound, a ground shadow and auto-zoom.

**It does not have yet:**

- takeoff or landing (it starts in the air);
- wind;
- menus;
- real engine response or engine sound recordings.

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
