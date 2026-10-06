# 06 — Radio input, control shaping, servos and end-to-end latency

**Status:** research knowledge base, 2026-10-06. **Serves:** ROADMAP M1 D6d (owner flies with the radio; open trim question), D6c (servo model), M3 F3 (replug/focus), F4 (compatibility table), F5 (setup screen); MENU-PLAN UI-10a/10b/12 (radio wizard, device choice); future flight aids (gyro "receiver"). **Read with:** [ROADMAP](../../../ROADMAP.md) M1/M3, [RESEARCH.md: RC input is an end-to-end pipeline](../../../RESEARCH.md#rc-input-is-an-end-to-end-pipeline), [plan review #3](../../../RESEARCH.md#plan-review-3-radio-input-full-envelope-flight-release-and-measured-flight-modes), [MENU-PLAN](../../MENU-PLAN.md), menu investigations [02](../menu-investigations/02-input-focus-radio-isolation.md), [05](../menu-investigations/05-radio-onboarding.md), [12](../menu-investigations/12-identidad-joypads-sdl3.md), [24](../menu-investigations/24-pausa-foco-entrada.md).

## Summary

1. **EdgeTX USB joystick sends channel outputs after limits, not sticks:** Classic = 8 axes × 11 bit (`channelOutputs + 1024`, clipped to 0…2047), 24 buttons, HID *Game Pad*, VID:PID `1209:4F54`, `bInterval` 1 ms. Expo, rates, mixes, trims and endpoints are already applied; beyond ±100 % is clipped.
2. **The radio reports once per mixer run:** 1 ms with both RF modules off, otherwise at the RF module's period (default 4 ms). "RF off" is a latency setting.
3. **Godot 4.7.2 samples joysticks once per rendered frame** (`process_events → joypad_sdl->process_events → Main::iteration`). At 60 fps the four 240 Hz ticks share one sample: a 60 Hz sample-and-hold (+8.3 ms mean), similar to a receiver's 50 Hz servo frame.
4. **Estimated stick-to-photon:** ≈ 42 ms at 60 Hz VSync, 59–75 ms if the driver queues 1–2 frames, 22–29 ms at 144 Hz. A real sport plane needs ≈ 15–40 ms from stick to servo command. **Target: ≤ 50 ms median, ≤ 70 ms p95 at 60 Hz, measured (F6) before any optimisation.**
5. **Convention:** with a radio, the sim is **receiver + servos + linkages**; the radio does expo, rates, mixes and trims. The sim shapes only keyboard and gamepad. `max_throw` = mechanical throw at ±100 % output.
6. **D6d trim question — answer:** keep the solved trim but make it a per-aircraft **linkage trim** (subtrim/clevis), solved once at a stated reference cruise, applied after every input device; radio trims start centred. Reason (measured): the Stik needs **+26 % elevator** at 15 m/s, beyond EdgeTX's default ±25 % trim range.
7. **Axes read 0 until moved** ([#105676](https://github.com/godotengine/godot/issues/105676) open, reproduced on 4.8-dev with a RadioMaster Pocket, 2026-08-25). Keep arming; re-arm after any axis clear.
8. **Windows disconnect hang [#121539](https://github.com/godotengine/godot/issues/121539) is fixed only in 4.8** (SDL 3.4.16, PR #120373, closed 2026-09-14).
9. **Servos:** today's slew limit has no small-signal delay (a 5 % correction takes 7 ms); a measured hobby servo behaves like τ ≈ 0.075 s. Next level (L2): deadband + first-order lag + slew; no extra transport delay, because the sim's own input/display latency (≈ 42 ms) already exceeds a real link's (≈ 15–40 ms). Hinge-moment load (L3) matters above ≈ 30 m/s and for giant scale. See [Servo model](#4-servo-model).
10. **Identity:** the SDL3 GUID embeds the firmware version, so keep investigation 12's three levels (index / exact key / family `vid:pid|raw_name`).
11. **Flight aids** fit as an optional "gyro receiver" stage between command and servos (rate damping, envelope, self-level, panic), as AS3X/SAFE, Futaba and FrSky receivers do; see [Flight aids](#7-flight-aids-gyro-receiver).
12. **USB carries no failsafe:** a frozen but connected device (BLE out of range) cannot be detected from axis values.

## Where the code stands

| Item | Fact (2026-10-06) | File |
| --- | --- | --- |
| Device choice | First pad at start or first connected; radio flies instead of the keyboard while connected; no explicit selection (UI-12) | [flight_session.gd](../../../app/sim/flight_session.gd) L102–121 |
| Reader | Pure state machine; polls 10 axes with `Input.get_joy_axis` once per physics tick into float64; `_input` forwards `InputEventJoypadMotion` only to mark axes as *seen* | [rc_input.gd](../../../app/input/rc_input.gd) |
| Profiles | `radio` (unshaped, AETR Classic default, elevator inverted), `gamepad` (deadzone 0.08 rescaled, expo 0.3 as `(1−e)x + e·x³`, rate throttle 0.5/s); radio detection by name list | rc_input.gd |
| Arming | Throttle idle until the throttle axis was seen ≤ 5 %; gamepads armed at once (rate throttle starts at 0) | rc_input.gd `poll` |
| Failsafe | Unplug → idle, sticks centred, trims kept, pause with reason; resume is explicit | flight_session.gd `_failsafe` |
| Calibration | Wizard (rest → throttle → aileron → elevator → rudder), per-side endpoints, inversion from first deflection; saved per `guid|vid:pid|name` (MD5 section) in `user://rc_calibration.cfg`, validated on load | [rc_calibration.gd](../../../app/input/rc_calibration.gd) |
| Keyboard | Bang-bang keys → virtual stick rate-limited at `Spec.CONTROLS.rate`, self-centring; throttle by rate | [keyboard.gd](../../../app/input/keyboard.gd), [commands.gd](../../../app/input/commands.gd) |
| Trims | Solved at the start condition (Stik at 15 m/s: roll +0.021, pitch +0.263, yaw +0.026, throttle 0.284; trace 2026-10-06), added to the sticks in command units, clamped ±1 | flight_session.gd `flown_commands` |
| Servos | `aux` states; slew-rate only, `servo_full_throw_time` 0.14 s (Stik, Extra; estimated) / 0.18 s (P-51), same for every surface; advanced once per tick in `_pre_step`, held over RK4 stages | flight_session.gd `_pre_step`, `app/data/aircraft/*.json` |
| Tick order | `FlightSession` (parent) runs `_physics_process` before its child `Simulation`, so inputs read in a tick act in the same tick (no extra tick of delay) | flight_session.gd L97, simulation.gd L182 |
| Godot input settings | `Input.use_accumulated_input = false` (main.gd L112); joypad events removed from `ui_*` (UI-01b); pause on `APPLICATION_FOCUS_OUT` | main.gd, [ui_input.gd](../../../app/ui/ui_input.gd), simulation.gd L111 |
| Render | Interpolates between the last two ticks with `Engine.get_physics_interpolation_fraction()` (shows the state up to one tick old) | main.gd L296 |

**Missing:** explicit device selection and multi-device handling; a live raw→mapped monitor (F5/UI-10b); radio-side setup guidance per brand; channels beyond 4 (flaps, gear, rates switch, trainer, "panic" button); servo delay, deadband and load; hinge moments; trim keys for keyboard; latency measurement; flight aids; any detection of a frozen device; tests of axis values with 11-bit quantisation and off-centre rest (EdgeTX [#4881](https://github.com/EdgeTX/edgetx/issues/4881)).

## Theory and models

### 1. The input chain, stage by stage

```
stick pot/hall → ADC + filter → EdgeTX mixer (inputs: weight/expo/curve, trims; mixes; outputs: subtrim, limits, invert)
  → channelOutputs (±1024 = ±100 %) → USB HID report (11 bit) every mixer run → OS HID driver → SDL3 (thread on Windows)
  → SDL event queue → Godot joypad_sdl.process_events (once per OS loop) → Input._joy_axis (float32)
  → FlightSession._physics_process: get_joy_axis ×10 → calibration (piecewise linear) → [device shaping] → + linkage trim
  → servo model (aux, once per tick) → surface deflection → aero → RK4 → render interpolation → GPU → swap/VSync → panel
```

**EdgeTX (source read, `main`, GPLv2) [S1]–[S9]:**
- [`usb_joystick.cpp`](https://github.com/EdgeTX/edgetx/blob/main/radio/src/usb_joystick.cpp): Classic = *Game Pad* (0x05), 24 buttons, 8 axes as 16-bit fields 0…2047, value `limit(0, channelOutputs + 1024, 2047)`. Advanced builds the descriptor at run time (Joystick 0x04 / Gamepad 0x05 / MultiAxis 0x08), axes 0…2048, optional circular cutout.
- `mixer_task.cpp` calls `usbJoystickUpdate()` after each mixer run; `mixer_scheduler.h`: default period 4000 µs, joystick 1000 µs; an active internal or external module's period wins. HID `bInterval = 1`.
- Resolution 2/2047 ≈ 0.001 of range (0.02° of a 20° throw). Godot maps SDL int16 to float32 (`joypad_sdl.cpp` L229).
- Linux merges Advanced *sim Thr* + *Slider* (and *sim Rud* + *Dial*) into one evdev axis; Advanced is absent on monochrome radios with < 1 MB flash [S9]. Which Windows backend SDL uses for EdgeTX is **unverified**.

**Godot (source read, 4.7.2-stable) [S37]–[S39]:**
- `OS_LinuxBSD::run()`: `DisplayServer::process_events(); joypad_sdl->process_events(); Main::iteration();` (same pattern on other desktops, investigation 12); `SDL_HINT_JOYSTICK_THREAD=1`.
- With `use_accumulated_input = false`, each event updates `_joy_axis` at once. Agile flushing is "implemented only on Android". Either way SDL is polled once per OS loop: **no setting gives more than one joystick sample per rendered frame.**
- `Main::iteration` runs the frame's physics ticks back to back (cap `max_physics_steps_per_frame` = 12).
- Focus: before 4.7 focus loss always cleared `_joy_axis`; since PR #115119 (4.7) only if `ignore_joypad_on_unfocused_application = true` (default false; diff read).
- `swapchain_image_count` and `frame_queue_size` are RenderingDevice-only, **not** Compatibility; there the driver sets queue depth (unverified). `max_fps` with VSync + VRR: cap at `r − r²/3600`.

### 2. Latency model

Total mean latency, stick crossing a threshold → photons changing mid-screen:

`L = L_radio + L_usb + L_poll + L_tick + L_interp + L_render + L_queue + L_scan + L_panel`

| Term | Model | 60 Hz VSync | 144 Hz | Kind |
| --- | --- | --- | --- | --- |
| L_radio | ADC + mixer: ½ period + compute | ≈ 1 ms (1 ms period, RF off); ≈ 2–3 ms at 4 ms | same | derived from EdgeTX source |
| L_usb | ½ bInterval | 0.5 ms | 0.5 | derived |
| L_poll | wait for the next OS-loop poll: ½ frame | 8.3 | 3.5 | derived (Godot source) |
| L_tick | physics runs right after the poll, same frame | ≈ 0 | ≈ 0 | derived |
| L_interp | render shows state ≤ 1 tick old: ½·(1/240) | 2.1 | 2.1 | derived (main.gd) |
| L_render | CPU+GPU, then wait for VSync: 1 frame (double buffering) | 16.7 | 6.9 | estimated |
| L_queue | driver-queued frames (OpenGL: 0–2, unverified) | 0–33 | 0–14 | estimated |
| L_scan | top-to-bottom scanout to mid-screen: ½ frame | 8.3 | 3.5 | derived |
| L_panel | monitor processing + pixel response | 0–20 on a good monitor, ≥ 63 on a slow TV [S34] | same | measured (external) |
| **Sum** (panel 5 ms) | | **≈ 42 / 59 / 75 ms** (0/1/2 queued) | **≈ 22 / 29 ms** | derived (sum of the rows) |

A pilot feels phase lag at the pilot–aircraft crossover: a pure delay τ costs φ = ω·τ; at ω = 3–6 rad/s, 20 ms → 3.4–6.9°, 40 ms → 6.9–13.8°, 60 ms → 10.3–20.6°, 100 ms → 17–34° (derived).

**Do not count the link delay twice.** In reality the pilot sees the airplane instantly and the delay sits in the RF link and receiver (≈ 15–40 ms, below). In the sim the input and display chain already costs ≈ 42 ms. Rule: modelled transport delay = `max(0, real link delay − measured sim latency)`, which is **0** whenever the sim's latency exceeds ≈ 25–40 ms. So L2 models servo dynamics (lag, deadband, slew); the receiver-frame hold stays in the data, off by default.

**Real airplane chain** (stick → servo command). Each periodic stage adds ½ period on average, one period at worst.

| Stage | Value | Kind | Source |
| --- | --- | --- | --- |
| EdgeTX/OpenTX mixer with RF on | period 4 ms default (0.85–50 ms); OpenTX gimbal → module 5.6 ms mean | source; measured | [S1], [S20] |
| ELRS packet interval 50/150/250/500 Hz; F1000 | 20 / 6.7 / 4 / 2 ms; 1 ms | manual | [S21] |
| Crossfire 150 Hz CRSF; FrSky R9M-Lite SBUS (gimbal → RX frame) | 13.9 (8.4–19.6); 14.1 (7.5–20.2) ms | measured | [S20] |
| FrSky XJT → XSR SBUS / FPort; Taranis X9D; FlySky FS-i6S | 19.8 / 15.1; 23.0; 15.1 ms mean | measured | [S22], [S24] |
| Futaba FASSTest 12/18 ch frame; Spektrum DSMX frame | 6.3 / 15 ms; 11 or 22 ms | manual | [S26], [S27] |
| Receiver servo pulse frame: analog / digital high speed | 20 ms (+10 mean) / 3 ms | manual | [S30], [S13] |

So a 2.4 GHz sport setup: **≈ 15–40 ms** stick → servo command (derived), then servo travel (0.1–0.2 s/60° no-load).

**Tolerated delay** (full-size and HCI references, none RC-specific): FAA Part 60 full-flight-simulator transport delay ≤ 300 ms (Level A/B), ≤ 150 ms (C/D) [S28]; NASA TM-110150: 150 ms transports, 100 ms high-performance aircraft [S29]; MIL-F-8785C equivalent delay 0.10 s Level 1 [S31]; pointing/steering degrade from ≈ 16 ms [S32]; display lag "great" 21–41 ms, "bad" ≥ 63 ms [S34]; key-to-screen on modern PCs 50–200 ms [S35]. RC flying (roll rates 150–200°/s) is a high-performance task, so ≤ 100 ms total is a ceiling, not a target. No RC simulator vendor publishes a latency figure (none found).

**Measurement (F6):** phone at 240 fps (4.17 ms/frame) filming stick and screen; a "latency patch" square in the app toggles on the first tick that sees the axis cross 50 %; ≥ 20 trials, median and p95 (method of [S35]). For sub-ms timing: an Arduino-class USB HID joystick toggling an axis plus a photodiode on the patch (OpenLDAT/OSLTT style [S36]). Linux `evtest` timestamps give the radio's report interval. Godot has no input timestamps ([S56]), so in-app timers cover only poll → tick → frame submit.

### 3. Control shaping: where rates, expo, mixes and trims live

**EdgeTX order** [S5][S7]: *Inputs* (weight = rate, offset, expo/curve, trim, switch → dual rates) → *Mixes* → *Outputs* (subtrim, limits, invert). USB carries the Outputs.

**EdgeTX expo** (`mixer.cpp` `expou`, GPLv2: reuse the formula, not the code), x ∈ [0, 1], k = expo/100:
`f(x) = k·x³ + (1 − k)·x`, odd; negative k mirrors: `f(x) = 1 − f₊(1 − x, |k|)`. Slope at centre 1 − k; k 0.3 → f(0.25/0.5/0.75) = 0.18/0.39/0.65. (The integer code maps k via `calc100to256`; an `EXTENDED_EXPO` build strengthens k > 80 %.) Our gamepad expo already uses this formula.

**Typical sport settings** (practice, estimated): low rate 60–75 % with 20–35 % expo, high rate 100 % with 30–50 %. Throttle cut on a switch. Differential, flaperon, elevon and V-tail are radio mixes; the sim needs separate channels only for aircraft that have those surfaces.

**Two conventions in commercial sims:** *sim = computer radio* (SeligSIM: "do not create any mixes, expo, dual rates" on the transmitter; edit them in the sim; "Use Your Own Programming" as the alternative [S50]); *sim = receiver* (fly the field model's programming). **Recommendation:** with a radio, **sim = receiver + servos + linkages**; setup text: clone the field model, USB joystick, RF off, keep rates/expo/trims. Keyboard and gamepad get a labelled *input profile* (expo, rates, trim keys), never applied to a radio.

**Trims (D6d).** Today's solved trim is the surface offset for hands-off flight at the start condition. In real life it ends up in the clevis or subtrim after the maiden flight, and transmitter trims are re-centred.

| Option | Radio pilot experience | Risk |
| --- | --- | --- |
| A. Keep (added to sticks, re-solved per start) | Hands-off; radio trims add on top | "Linkage" changes with scenario; a runway start (M2) has no trimmed condition |
| B. Zero with a radio (or C: keyboard only) | Must hold +26 % up elevator at 15 m/s, beyond default ±25 % trim | Feels like a badly rigged airplane |
| **D. Linkage trim (recommended)** | `controls.linkage_trim` (`kind: derived`, "trim solver at V_ref"), applied after the device for every device, constant across scenarios | Needs V_ref per aircraft; at other speeds the pilot trims with the radio, as in reality |

Side finding: real airplanes are rigged so cruise needs little trim; +26 % at 15 m/s suggests V_ref is slow for a Stik or Cm0/incidence differ from the real airplane: a data point for D8b/D10.

### 4. Servo model

**Datasheets** (manual; speed is no-load and torque is stall, the two ends of a torque–speed line [S10][S12]):

| Servo | Type | s/60° @4.8/6.0 V | kg·cm @4.8/6.0 V | Deadband | Source |
| --- | --- | --- | --- | --- | --- |
| Hitec HS-311 / Futaba S3003 | analog | 0.19 / 0.15; 0.23 / 0.19 | 3.0 / 3.7; 3.2 / 4.1 | 5 µs; — | [S10], [S11] |
| Hitec HS-425BB / HS-645MG | analog | 0.21 / 0.16; 0.24 / 0.20 | 3.3 / 4.1; 7.7 / 9.6 | 8 µs | [S10] |
| Hitec HS-5645MG | digital | 0.23 / 0.18 | 10.3 / 12.1 | 4 µs (search result) | [S10] |
| Savox SC-1258TG / SB-2271SG | digital | 0.10 / 0.08; 0.085 / 0.065 | 9.6 / 12; 15 / 20 | 12-bit, 333 Hz | [S13] |
| Hitec HS-7955TG (giant) | digital | 0.19 / 0.15 | 18 / 24 | 1 µs (0.080°/µs) | [S12] |

Pulse 1500 µs centre, ±100 % ≈ 1100–1900 µs [S27][S30]. A 5 µs deadband on an S3003 (0.1125°/µs) ≈ 0.56° at the servo, ≈ 0.25° at the surface (derived).

**Identified dynamics (measured):** HD-1810MG small-amplitude sweep → first order τ = 0.075 s plus 5 µs deadband [S14]; Align DS610 (20 ms frame), ±5° steps → settles in ≈ 0.12 s, and under rotor load the bench model over-predicted position by 22 % (saturation) [S15]. **Simulator practice:** ArduPilot SITL defaults to 0.14 s/60° as a 1-pole low-pass, optionally delay → slew → 2-pole filter [S16, GPLv3, read only]; JSBSim `<actuator>`: lag → rate limit → deadband → hysteresis → bias → delay → clip, `lag` = C in C/(s+C) [S17, LGPL]; PX4 Gazebo rc_cessna: a joint P-controller [S18]; OpenFlightSim UltraStick25e: 0.020 s delay (RESEARCH.md).

**Gap in L1 (today):** a slew limit has no small-signal delay: 5 % of throw completes in 7 ms, 10 % in 14 ms, while a real servo answers small inputs with τ ≈ 0.075 s plus up to one 20 ms frame. Pilots judge feel on small corrections, so L1 is too fast exactly there. D10's "servo time: no effect" applies only to linear modes, which exclude the actuator.

**Hinge moments:** `H = q·S_f·c_f·C_h`, `C_h = C_hα·α + C_hδ·δ`; servo torque `T = H·dδ/dθ` (virtual work; 20° of surface per 45° of servo → 0.44). Plain unbalanced flaps (t/c 0.12): C_hδ −0.70 … −0.94/rad theoretical × 0.80–0.91 real-airfoil factor, C_hα −0.32 … −0.72/rad (Roskam figures digitised in FAST-GA [S19]); working range C_hδ −0.5 … −0.9, C_hα −0.2 … −0.5 (estimated). At δ = 20°, C_hδ −0.7 (derived; geometry estimated):

| Surface | V | H | Servo-side (×0.44) | Load vs servo |
| --- | --- | --- | --- | --- |
| Stik aileron 0.06 × 0.5 m | 15 / 35 m/s | 0.62 / 3.36 kg·cm | 0.27 / 1.48 | 9 % / 49 % of 3 kg·cm |
| Stik elevator 0.08 × 0.6 m | 15 / 35 m/s | 1.32 / 7.18 kg·cm | 0.58 / 3.16 | 19 % / > 100 %: **blowback above ≈ 34 m/s** |
| P-51 aileron 0.10 × 0.6 m | 45 m/s | 18.5 kg·cm | 8.2 | 41 % of 20, 27 % of 30 kg·cm |

So load slows a Stik's servos by ≈ 10–30 % in normal flight; blowback needs large deflections in dives. **Linkage:** `δ = asin((r_s/r_h)·sin θ)` is within 0.5° of the four-bar for typical arms; a 20° raked arm gives −22°/+15° differential (own geometry). Throws are data in degrees, so kinematics matter only for differential and load.

| Level | Model | Matters for |
| --- | --- | --- |
| L0 | Surface = command | Tests |
| L1 (today) | Slew limit, one full-throw time | Large fast moves |
| **L2 (next)** | Deadband → first-order lag τ → slew at datasheet speed × arm travel; receiver-frame hold (20 / 11 / 3 ms) in data, off unless F6 shows the sim faster than a real link | Small corrections, flare, analog vs digital |
| L3 | L2 + load: `ω = ω₀·max(0, 1 − T_load/T_stall)`, hold at blowback; optional hysteresis | Dives, giant scale, weak servos |
| L4 | Second-order loop with current limit, pushrod flex | Research only |

Numerics: all in `pre_step` once per tick; first order exact as `x += (1 − e^(−dt/τ))(u − x)`; the optional 20 ms frame hold (4.8 ticks) as a tick-phase accumulator whose phase is seeded and recorded, or goldens stop replaying bit-exactly.

### 5. Safety, failsafe and identity

- **Failures:** unplug (detected; Godot zeroes axes), focus loss (detected; axes kept by default in 4.7), hitch (> 12 ticks per frame = 50 ms: sim time slows), frozen-but-enumerated device (undetectable: SDL emits only changes), wrong profile (only the pilot sees it).
- **Arming invariant:** never apply a throttle not *seen* since the last axis reset; re-arm after unplug, profile change, calibration, and focus return if axes were cleared. A menu pause keeps arming (investigation 02).
- **Identity:** EdgeTX radios share `1209:4F54`, manufacturer "OpenTX", serial `00000000001B` on most boards: two identical radios are indistinguishable → ask (investigation 12).
- **Multiple devices:** the device chosen in setup flies; others are ignored; if it disappears → failsafe, never a silent fallback (investigation 20).
- **Trainer / buddy box (future):** EdgeTX trainer runs over jack (PPM), Bluetooth, serial, SBUS/CPPM, Multi or CRSF; the master takes over per stick with Off/Add/Replace and a *Trainer* function [S51]. If both radios are linked by EdgeTX itself the sim needs nothing; otherwise **two USB devices**, the instructor's switch channel (or a key) hands over with Replace semantics and an audible cue.

### 6. Radio and adapter landscape

| Path | How it appears | Ch. | Notes | Source |
| --- | --- | --- | --- | --- |
| EdgeTX USB (RadioMaster, Jumper, FrSky on EdgeTX, BetaFPV, Flysky PL18…) | `1209:4F54`, "<Maker> <Model> Joystick" | 8 + 24 btn | Classic → SDL gamepad on Linux (throttle 0…1 trigger, Ch7/8 lost; inference) → recommend Advanced/Joystick | [S2], inv. 12 |
| OpenTX 2.2 USB | 8 axes, 24 buttons, 8-bit per manual | 8 | Linux `jscal` may add a centre deadband | [S57] |
| FrSky Ethos USB | **unverified** | ? | Ask the owner | — |
| Spektrum NX6/8/10 | USB Setting → *Game Controller*, RF off | 8 | | [S50] (search result) |
| Spektrum WS1000/WS2000 | DSMX receiver → USB gamepad | 8–9 | Adds the 11/22 ms frame | [S54], [S55] |
| Futaba | Trainer-port PPM → USB cable; WSC-1 wireless; T16IZ USB | 6–8 | PPM ≈ 20 ms frame; cable quality varies | [S54] |
| RX2SIM | Any brand's receiver → USB | 8 | | [S54] |
| ELRS BLE joystick | TX ≥ 2.0, Lua *BLE Joystick*; "ExpressLRS Joystick", 8 axes | 8 | ≈ 3 m range; reset bug fixed in 3.5.1 | [S52] (search result) |
| CRSF → USB (RP2040 + ELRS receiver) | DIY HID joystick | 16 | Real RF link in the loop | [S53] |
| Gamepad | SDL gamepad | 2 sticks + triggers | Rate throttle | Godot |

### 7. Flight aids (gyro receiver)

**What real products do** (manuals; algorithms not public):

| System | Modes and behaviour | Numbers | Source |
| --- | --- | --- | --- |
| Spektrum AS3X/AS3X+ | Rate (damping, default); Heading (holds attitude after release, no self-level) | Gain 0–100 % × sensitivity 0.25…4; **Priority** 0–200: gain → 0 at stick fraction 100/P (AS3000 default 160) | [S40][S41] |
| Spektrum SAFE | Envelope (limits, keeps attitude); Self-level (stick = attitude, optional throttle → pitch); Panic button (level from any attitude) | Limits user-set, **no published defaults** | [S40][S42] |
| Futaba GYA460 / GYA553, T16IZ | Beginner (≈ ±80° scaled by dual rate, auto-level); Normal (rate) / AVCS (heading hold) on one signed gain channel | Gain in 5 % steps | [S43] |
| FrSky SR10/S8R | Stabilization, Auto-level, Hover, Knife-edge | Per-mode gains, angle offsets | [S44] |
| Hobbyeagle A3 Pro V2 | Normal, Lock, Angle, Level, Hover | Max angle ±30/**±60 default**/±90° | [S45] |
| INAV / ArduPlane (GPLv3) | ANGLE/HORIZON; FBWA/TRAINING/ACRO | Bank 45°; ArduPlane pitch +20/−25°, roll τ 0.5 s, gains scaled by `SCALING_SPEED`/EAS (15 m/s) | [S46][S47] |

RealFlight Trainer Edition advertises "electronic assistance like SAFE, AS3X" on its trainers [S48]; PicaSim has time scale, slow motion, pause/rewind and an AI pilot (PolyForm Noncommercial: read only) [S49].

**Proposed control laws** (proposal, not a vendor algorithm). Per axis, stick s ∈ [−1, 1], body rate ω, command to servos u:
- Priority attenuation: `a = clamp(1 − |s|·P/100, 0, 1)`.
- Airspeed schedule: `σ = clamp(V_ref/V, σ_min, σ_max)`, `K_eff = K·σ²` (surface authority ∝ q ∝ V²).
- Rate damping (AS3X/Normal): `u = s − a·K_eff·ω` (or `u = s + a·K_eff·(s·ω_max − ω)`).
- Heading hold (AVCS/Lock): add `a·K_I·σ²·∫(ω_cmd − ω)dt`, bleed while |s| > deadband, clamp (anti-windup).
- Self-level (Beginner/ANGLE): `φ_cmd = s_roll·φ_max`, `θ_cmd = s_pitch·θ_max (+ k_thr·(thr − 0.5))`; `ω_cmd = (angle_cmd − angle)/τ` through the Euler→body-rate transform, then the rate law.
- Envelope (Intermediate): rate mode plus a soft wall `ω_cmd −= K_env·max(0, |φ| − φ_max + m)·sign φ` (same for θ).
- Panic: ignore sticks; if |φ| > 90° roll the shortest way upright at ω_max, then φ_cmd 0, θ_cmd +5…10° (assumption); throttle stays with the pilot.

Architecture: a `gyro_receiver` stage between `flown_commands()` and the servo `aux` (it reads the *simulated* gyro = body rates and attitude, i.e. perfect sensors; noise and IMU lag later). It runs once per tick in `pre_step` (state: integrators), its gains live in an optional aircraft-data block `receiver.gyro`, off by default, with modes selectable from a radio channel (signed gain channel like Spektrum/Futaba) or a key. Beginner extras that are not physics: time scale 0.5–1.0, pause/rewind to the last safe state, wind off.

## Implementation options and trade-offs

| Topic | Options | Recommendation |
| --- | --- | --- |
| Input sampling | (a) `get_joy_axis` once per tick (today: simple, deterministic, frame-rate hold); (b) threaded GDExtension (SDL3, zlib; or HIDAPI, licence to check) with timestamped samples aligned to each tick (true 240 Hz; C++ per OS; a second SDL instance may contend for the device) | **(a)**; (b) only if F6 shows sampling > 25 % of total |
| Per-event `_input` | Every SDL event goes through the scene tree (accumulation off): up to ≈ 60 events/frame with 4 axes moving at 1 kHz | Measure (F3b); stop forwarding once armed |
| Shaping with a radio | Sim = receiver (one truth) vs sim = computer radio (double shaping risk) | **Receiver**; computer radio for keyboard/gamepad only |
| Trims | Per-start trim vs linkage trim | **Linkage trim** |
| Servo | L1 slew / **L2 deadband + lag + slew** / L3 load / L4 loop | L2 next, L3 for giant scale and dives |
| Flight aids | Gyro receiver component, off by default | M5 |
| Latency | Measure first (camera, ±4 ms) | **F6 before any optimisation** |

## Godot / GDScript notes

- **Determinism:** input enters only through `sim.inputs` once per tick and goldens record per-tick inputs; any future reader must still deliver exactly one value per tick.
- **float64:** reader and calibration use `PackedFloat64Array`; Godot's float32 `_joy_axis` loses nothing on 11-bit data.
- **Settings:** keep `use_accumulated_input = false`; keep `ignore_joypad_on_unfocused_application = false` (true clears axes on focus loss → re-arm); never use `SDL_GAMECONTROLLER_IGNORE_DEVICES` (hides the radio).
- **Latency knobs in Compatibility:** VSync on/off and `Engine.max_fps` only.
- **Hot-plug:** Linux needs udev for reliable hot-plug [S39].
- **Version watch:** 4.8 = SDL 3.4.16 (#121539 fix); open PR #118606 would swap Godot's mapping database for SDL's (changes which devices are "gamepads"); #105676 open.
- **Tests:** fake device id 15; never `get_joy_guid` on a fake id; a recorded raw-axis CSV can drive the reader headless.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | Use here |
| --- | --- | --- | --- | --- |
| EdgeTX source | HID descriptor, mixer period, expo, trim ranges | GPLv2 | [EdgeTX](https://github.com/EdgeTX/edgetx) | Cite; reimplement formulas only |
| SDL3 / HIDAPI | Joystick backend / raw HID reports | zlib / GitHub reports no SPDX id (multi-licence per its README, unverified) | [SDL3](https://wiki.libsdl.org/SDL3/CategoryJoystick), [HIDAPI](https://github.com/libusb/hidapi) | Only for X-INPUT-1 |
| Godot-TimeStampInput | GDExtension capturing input events with earliest timestamps | MIT | [GitHub](https://github.com/h4yase/Godot-TimeStampInput) | Read for X-INPUT-1 / F6 (not vetted) |
| JSBSim FGActuator | Lag, rate limit, deadband, hysteresis, delay, clip | LGPL | [S17] | Pattern for L2 |
| CRSFJoystick | RP2040 + ELRS receiver → USB HID | GPL-3.0 | [S53] | Hardware test fixture only (no code reuse) |
| OSLTT / OpenLDAT | Photodiode latency testers | see repos | [S36] | Optional precise F6 |
| `evtest`, Windows `joy.cpl` | Raw events with timestamps; controller panel | OS tools | — | F1/F4 rows |
| OpenFlightSim UltraStick25e | Servo delay 0.020 s | see repo | RESEARCH.md | Reference for the optional frame hold |

## Parameters and data

Servo datasheets, link stages and gyro limits are in the tables above; this table keeps the numbers a data file or test would use.

| Quantity | Value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| EdgeTX Classic axes / resolution / buttons | 8 / 11 bit / 24 | — | source | [S2] |
| EdgeTX report interval RF off / on | 1 / module period (default 4) | ms | source | [S1][S4] |
| EdgeTX trim range standard / extended | ±25 % / ±100 % | of channel | source | [S6] |
| Sport rates / expo (low; high) | 60–75 % / 20–35 %; 100 % / 30–50 % | % | estimated | practice |
| Stik solved trims at 15 m/s (roll, pitch, yaw, throttle) | +0.021, +0.263, +0.026, 0.284 | command | measured (our trace) | `--trace` 2026-10-06 |
| Analog sport servo @6 V (HS-311 class) | 0.15 / 3.7 | s/60°, kg·cm | manual | [S10] |
| Servo deadband analog / digital / giant digital | 5–8 / ≈ 4 / 1 | µs | manual | [S10][S12] |
| Receiver frame analog PWM / DSMX / digital HS | 20 / 11–22 / 3 | ms | manual | [S30][S27][S13] |
| Servo small-signal τ (HD-1810MG) | 0.075 | s | measured | [S14] |
| Arm travel for full throw / full-throw time today | ≈ 45° / 0.14 (P-51 0.18) | deg / s | estimated | aircraft JSON |
| Plain-flap C_hδ / C_hα | −0.5 … −0.9 / −0.2 … −0.5 | 1/rad | borrowed | [S19] |
| Stik elevator blowback speed (3 kg·cm, δ 20°) | ≈ 34 | m/s | derived | H formula, §4 |
| Real stick → servo command (2.4 GHz) | ≈ 15–40 | ms | derived | [S20]–[S27] |
| Sim stick → photon, 60 Hz (0/1/2 queued frames) | 42 / 59 / 75 | ms | derived | §2 |
| Target at 60 Hz | ≤ 50 median, ≤ 70 p95 | ms | estimated | this doc |

## Validation

**Verification (known answers, headless):**
1. Reader: 11-bit quantised ramps through calibration reproduce the stick within one LSB; an off-centre rest (raw 1024 ± 3, EdgeTX #4881) calibrates to 0.
2. Expo: `f(0.5, 0.3) = 0.3875`, `f(1, k) = 1`, slope 1 − k at 0, odd symmetry, mirror identity for negative k.
3. Linkage trim: identical at any start speed; hands-off at V_ref holds as today.
4. Servo L2/L3: step reaches 63 % at τ; the optional frame hold delays by the expected ticks; inputs inside the deadband never move the servo; at `T_load = T_stall` speed is 0 and the hold angle equals the analytic blowback angle.
5. Latency patch toggles in the same tick as the injected axis event (0 extra ticks).
6. The 30/60/144 fps hash test stays identical after every input change.

**Independent validation:** F6 camera measurement vs the budget (a gap > 20 ms reveals a hidden queue: driver, compositor, TV mode); D6d/F4 rows per OS (axes, gamepad vs joystick, `evtest` report interval, GUID before/after a firmware update); a bench video of the owner's own servo (no load and with a weight on the horn) vs its datasheet; Gate 2 axis ratings with L1 vs L2 servos (blind A/B if possible).

**Mutations that must fail:** remove arming (exists); shape a radio profile; add trim twice (stick + linkage); drop the L2 lag (instant small steps); update the latency patch in `_process` instead of the tick.

## Pitfalls and risks

1. **Double shaping** (radio + sim expo or trims) misread as physics. *Mitigation:* radio profiles never shaped (test); linkage trim separate; monitor shows raw vs mapped.
2. **RF module on:** reports at the RF period, plus emissions. *Mitigation:* warn when the measured event spacing > 2 ms.
3. **Classic mode on Linux → SDL gamepad** (throttle as trigger, Ch7/8 lost). *Mitigation:* `1209:4F54` + `is_joy_known` → "use Advanced → Joystick".
4. **Axes 0 until moved** (#105676) and **focus setting flipped to true** later. *Mitigation:* arming; re-arm on every axis clear; a test pins the setting.
5. **Windows disconnect hang** in 4.7.2. *Mitigation:* document; re-test on 4.8.
6. **Frozen device** keeps the last stick. *Mitigation:* document; later an optional heartbeat (a radio logical switch toggling a button at 1 Hz).
7. **Per-event `_input` cost.** *Mitigation:* F3b.
8. **GUID changes with firmware** → calibration silently missed. *Mitigation:* family match with confirmation (UI-10b).
9. **OpenGL driver queue** adds 1–2 frames our timers cannot see. *Mitigation:* F6; `max_fps`/VSync options in preferences (UI-07) if they help.
10. **Wrong yardstick for servos:** linear modes exclude actuators (D10 "no effect"). *Mitigation:* judge servo levels by time responses and pilot A/B.
11. **Aids contaminating goldens.** *Mitigation:* separate component, off by default, own goldens.

## Proposed roadmap steps

IDs: F3–F5 keep their ROADMAP meaning; flight aids M5-AIDS-n; the optional reader X-INPUT-n. Ordered basic → advanced.

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| F1 | **Input report:** `-- --input-report` lists each device (index, GUID, `raw_name`, VID:PID as integers, `is_joy_known`, axes moved, min/max, mean event spacing = report interval) | Fake-device headless test; the owner's D6d run yields one F4 row per OS | D6a |
| F2 | **Linkage trim:** `controls.linkage_trim` solved at a stated V_ref (generated, `derived`), applied after every device, constant across scenarios; keyboard trim keys | A 20 m/s start keeps the V_ref trim; hands-off at V_ref holds; double-trim mutation fails | D4, owner decision |
| F3 | **Replug and focus** (existing): exact key, else family with confirmation; re-arm after every axis clear; pin `ignore_joypad_on_unfocused_application`; #121539 on 4.8 | Scripted unplug/replug/focus log: never non-idle throttle before re-arm; owner log on Windows 4.8 | F1, UI-10a |
| F3b | **`_input` cost:** µs/frame with 4 axes changing at 1 kHz; stop forwarding once armed | Before/after µs per frame; e2e radio tests unchanged | D6a |
| F4 | **Compatibility table** (existing) incl. report interval and GUID across a firmware update | One row per tested device | F1 |
| F5 | **Setup screen** (existing, = UI-10b/12): device pick; raw → calibrated → surface monitor; Classic-on-Linux and RF-on warnings; setup text "clone your field model, RF off" | Owner sets up a new radio without editing files; fake-device tests for both warnings | F1, F3, UI-10a |
| F6 | **Measured latency:** latency-patch mode + 240 fps camera protocol (≥ 20 trials) at VSync on/off and `max_fps` cap on the owner's machines | Measured median/p95 table vs the budget; headless same-tick check | D7, F1 |
| F7 | **Servo data schema**, no behaviour change: per-surface `{speed_s_per_60deg, voltage_V, stall_torque_kgcm, deadband_us, frame_ms, arm_deg_full_throw}`; full-throw time derived | `--trace` bytes and goldens identical; loader rejects a missing unit/kind | D6c |
| F8 | **Servo L2:** deadband, first-order lag, slew; optional frame hold (recorded tick phase) off by default | Analytic step tests; fps hash identical; goldens re-recorded deliberately; owner A/B at a Gate | F7, F6 |
| F9 | **Servo L3:** hinge moments (labelled estimates), torque–speed derating, blowback | Hold angle = analytic; Stik at 15 m/s changes < 30 %; dive > 34 m/s shows elevator blowback; µs/tick reported | F8, E0a |
| F10 | **Keyboard/gamepad shaping:** EdgeTX expo, rates key; never on radios | Formula tests; "shape a radio" mutation fails | F5 |
| F11 | **Extra channels** (rates switch, flaps, panic, trainer) in the profile | e2e: a button toggles the rate; menus unaffected | F5, UI-01b |
| M5-AIDS-1 | Gyro receiver: rate damping with priority and airspeed schedule, off by default | Gust roll rate decays ≥ 2× faster; no-aid goldens identical | F8 |
| M5-AIDS-2 | Envelope and self-level | Full stick holds φ_max ± 2°; centred stick levels within a stated time | AIDS-1 |
| M5-AIDS-3 | Panic | ≥ 99 % of 100 random attitudes recover above 10 m | AIDS-2 |
| M5-AIDS-4 | Trainer with two devices (Replace semantics) | e2e with two fake devices: handover in one tick, arming per device | F3, F11 |
| X-INPUT-1 | Threaded GDExtension reader with tick-aligned samples (conditional) | F6 re-measured: gain ≥ predicted ½ frame; replay unchanged | F6 shows sampling > 25 % |

## Decisions to take now

1. **Shaping convention:** radio = full transmitter; sim = receiver + servos + linkages; sim shaping only for keyboard/gamepad. *Recommended now*, because F5's screen layout and the data meaning of `max_throw` depend on it.
2. **Trims:** adopt *linkage trim* (option D): data field per aircraft, solved at a stated V_ref, applied after the device for all devices; radio trims centred. Decide before M2's runway start (E-steps), which has no trimmed start condition.
3. **Latency target and measurement before optimisation:** ≤ 50 ms median / ≤ 70 ms p95 at 60 Hz stick-to-photon (estimated target; revise after F6). No GDExtension reader unless F6 shows input sampling > 25 % of the total. No modelled RF/receiver transport delay while the measured sim latency exceeds a real link's (rule in §2).
4. **Servo data schema now, physics later:** extend `controls` with per-surface servo entries `{speed_s_per_60deg, voltage, torque, deadband_us, frame_ms, arm_deg_full_throw}` (all `{value, unit, kind, source}`), so L2/L3 add no schema break; keep `servo_full_throw_time` derived from them.
5. **Device identity and selection rules** (investigation 12/20) are the contract for F5/UI-12: family match only with confirmation; never another device silently.
6. **Flight aids as an optional "receiver" component** between radio command and servos, with its own data block; no aid ever enabled by default.

## Sources

1. [S1] EdgeTX, `radio/src/mixer_scheduler.h` / `mixer_scheduler.cpp`, main 2026. https://github.com/EdgeTX/edgetx/blob/main/radio/src/mixer_scheduler.h (fetched)
2. [S2] EdgeTX, `radio/src/usb_joystick.cpp`, main 2026. https://github.com/EdgeTX/edgetx/blob/main/radio/src/usb_joystick.cpp (fetched)
3. [S3] EdgeTX, `radio/src/tasks/mixer_task.cpp`. https://github.com/EdgeTX/edgetx/blob/main/radio/src/tasks/mixer_task.cpp (fetched)
4. [S4] EdgeTX, `usbd_hid_joystick.c` (bInterval 1 ms). https://github.com/EdgeTX/edgetx/blob/main/radio/src/targets/common/arm/stm32/usbd_hid_joystick.c (fetched)
5. [S5] EdgeTX, `radio/src/mixer.cpp` (`expou`, `expo`, trims). https://github.com/EdgeTX/edgetx/blob/main/radio/src/mixer.cpp (fetched)
6. [S6] EdgeTX, `radio/src/myeeprom.h` (`TRIM_MAX 128`, `TRIM_EXTENDED_MAX 512`). https://github.com/EdgeTX/edgetx/blob/main/radio/src/myeeprom.h (fetched)
7. [S7] EdgeTX manual, USB Joystick (Classic/Advanced, 1000 Hz with RF off). https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick (fetched)
8. [S8] EdgeTX manual v2.11, Joystick mapping information for game developers. https://manual.edgetx.org/v2.11/edgetx-how-to/joystick-mapping-information-for-game-developers (fetched)
9. [S9] EdgeTX manual, Configure advanced joystick. https://manual.edgetx.org/edgetx-how-to/configure-advanced-joystick-with-edgetx (fetched)
10. [S10] Hitec RCD, product pages HS-311, HS-322HD, HS-425BB, HS-645MG, HS-5645MG. https://hitecrcd.com/search/product_home/HS-425BB (fetched; others same path)
11. [S11] Servodatabase / retailers, Futaba S3003, S3004, S9001. https://servodatabase.com/servo/futaba/s3004 (search result only)
12. [S12] ServoCity, Hitec HS-7955TG. https://www.servocity.com/hs-7955tg-servo/ (fetched)
13. [S13] Lindinger, Savox SC-1258TG and SB-2271SG listings. https://lindinger.at/en/RC-ELECTRONICS/Servos-Accessories/Servos-Digital-Low-Voltage/SAVOEX-SC-1258TG-6V-12KG-0.08s-DIGITAL-SERVO/9795331 (fetched)
14. [S14] Afman et al., 2016, servo identification (first order τ 0.075 s). https://arxiv.org/pdf/1611.07650 (fetched)
15. [S15] Gladysz & Wang, IFAC 2014, servo modelling for a helicopter rotor. https://skoge.folk.ntnu.no/prost/proceedings/ifac2014/media/files/1137.pdf (fetched)
16. [S16] ArduPilot, `libraries/SITL/ServoModel.cpp` (GPLv3). https://github.com/ArduPilot/ardupilot/blob/master/libraries/SITL/ServoModel.cpp (fetched)
17. [S17] JSBSim, `FGActuator.cpp/.h` and class docs (LGPL). https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGActuator.html (fetched)
18. [S18] PX4, Gazebo `rc_cessna/model.sdf`. https://github.com/PX4/PX4-gazebo-models/blob/main/models/rc_cessna/model.sdf (fetched)
19. [S19] FAST-GA, digitised Roskam hinge-moment figures and `hinge_moments_elevator.py` (GPLv3); Ames & Sears, NACA TR-721, 1941. https://github.com/supaero-aircraft-design/FAST-GA ; https://ntrs.nasa.gov/api/citations/19930091799/downloads/19930091799.pdf (fetched; TR-721 OCR poor)
20. [S20] O. Liang, R9M-Lite vs Crossfire latency testing. https://oscarliang.com/r9m-lite-crossfire-latency-testing/ (fetched)
21. [S21] ExpressLRS docs, Signal health / Lua how-to (packet intervals). https://www.expresslrs.org/info/signal-health/ (fetched)
22. [S22] O. Liang, FPort latency testing. https://oscarliang.com/fport-latency-testing/ (fetched)
23. [S23] O. Liang, Improve radio control latency. https://oscarliang.com/improve-radio-control-latency (fetched)
24. [S24] Hackaday, Quantifying latency in cheap RC transmitters, 2018. https://hackaday.com/2018/02/26/quantifying-latency-in-cheap-rc-transmitters/ (fetched)
25. [S25] RC Tech / RunRyder radio benchmark results, 2013. https://www.rctech.net/forum/radio-electronics/991213-radio-benchmark-program-results-2.html (search result only)
26. [S26] Futaba R7018SB listing (FASSTest/FASST frame times). https://www.karkkainen.com/verkkokauppa/futaba-fpr7018sb-vastaanotin-2-x-akku (fetched)
27. [S27] Betaflight wiki, Spektrum and RC smoothing (11/22 ms); Spektrum Remote Receiver Interfacing manual. https://betaflight.com/docs/wiki/guides/archive/Spektrum-and-RC-Smoothing-Filter ; https://www.astramodel.cz/manualy/S/spektrum_SPM_Remote_Receiver_Interfacing-Manual-EN.pdf (fetched)
28. [S28] FAA, 14 CFR Part 60 final rule, 73 FR 26478, 2008. https://www.govinfo.gov/content/pkg/FR-2008-05-09/pdf/08-1183.pdf (fetched)
29. [S29] Smith, Chung, Martinez, NASA TM-110150, 1995 (simulator transport delay). https://ntrs.nasa.gov/api/citations/19950023033/downloads/19950023033.pdf (fetched)
30. [S30] Hitec, Servo manual (pulse 0.9–2.1 ms, 50 Hz). https://neurophysics.ucsd.edu/Manuals/Hitec/Servomanual.pdf (fetched)
31. [S31] Grantham, 1987, time-delay criteria for large transports. https://ntrs.nasa.gov/citations/19870007416 (abstract fetched)
32. [S32] Friston et al., 2015, latency and pointing/steering, IEEE TVCG. https://doi.org/10.1109/tvcg.2015.2446467 (abstract fetched)
33. [S33] NVIDIA, Reflex low-latency platform. https://www.nvidia.com/en-gb/geforce/news/reflex-low-latency-platform (fetched)
34. [S34] DisplayLag.com, Testing method. https://displaylag.com/testing-method/ (fetched)
35. [S35] D. Luu, Computer latency 1977–2017 (240/1000 fps camera). https://danluu.com/input-lag/ (fetched)
36. [S36] Dossena & Trentini, OpenLDAT, J. SID 2022, https://doi.org/10.1002/jsid.1104 (abstract fetched); OSLTT, https://github.com/OSRTT/OSLTT (RESEARCH.md)
37. [S37] Godot 4.7.2-stable source: `platform/linuxbsd/os_linuxbsd.cpp`, `main/main.cpp`, `core/input/input.cpp`, `drivers/sdl/joypad_sdl.cpp`, `doc/classes/ProjectSettings.xml`, `doc/classes/Input.xml`. https://github.com/godotengine/godot/tree/4.7.2-stable (fetched)
38. [S38] Godot issues/PRs #121539, #105676, #122817, #106218, #115119, #120373, #118606, #82080. https://github.com/godotengine/godot/issues/121539 (fetched via GitHub API)
39. [S39] Godot docs, Jitter, stutter and input lag; Controllers, gamepads and joysticks (4.7). https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html ; https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html (fetched)
40. [S40] Spektrum AR631+ manual SPM-1031 (AS3X+, SAFE, Panic). https://astramodel.cz/manualy/S/SPM-1031_MANUAL_EN.pdf (fetched)
41. [S41] Spektrum AS3000 manual (gain sign, Priority). https://www.astramodel.cz/manualy/spektrum/SPMAS3000-Manual-EN.pdf (fetched)
42. [S42] Flightengr, Modify SAFE settings on an AR636. https://www.rcportal.sk/public/files/1523390270-modify-safe-settings-on-an-ar636-safe-select-receiver.pdf (fetched)
43. [S43] Futaba GYA460 manual; T16IZ Super manual. https://lindinger.at/media/74/a1/07/1601769331/9720260_EN_Manual.pdf (fetched)
44. [S44] FrSky TW R10 / TW SR10 manual. https://www.gator-rc.com/cdn/shop/files/TW_R10_TW_SR10_Manual_1.pdf (fetched)
45. [S45] Hobbyeagle A3 Pro V2 manual v1.1. https://cdn.shopify.com/s/files/1/1052/4162/files/A3ProV2_User_Manual_v1.1.pdf (fetched)
46. [S46] INAV `docs/Settings.md` (GPLv3). https://raw.githubusercontent.com/iNavFlight/inav/master/docs/Settings.md (fetched)
47. [S47] ArduPilot Plane flight modes and source (GPLv3). https://ardupilot.org/plane/docs/flight-modes.html (fetched)
48. [S48] Steam, RealFlight Trainer Edition (app 1314820), RealFlight Evolution (2069310), UMX Conscendo add-on (2759380). https://store.steampowered.com/app/1314820 (fetched via API)
49. [S49] PicaSim repository (PolyForm Noncommercial). https://github.com/Rowlhouse/PicaSim (fetched)
50. [S50] SeligSIM manual, Editing the transmitter; Spektrum NX10/DX8 guides. https://www.seligsim.com/manual/edit_transmitter.html (fetched); https://www.seligsim.com/manual/controllers/howto-spektrum-nx10.html (search result only)
51. [S51] EdgeTX manual, Trainer (model setup). https://manual.edgetx.org/color-radios/model-settings/model-setup/trainer (fetched)
52. [S52] O. Liang, How to use ExpressLRS Bluetooth joystick. https://oscarliang.com/expresslrs-bluetooth-joystick/ (search result only)
53. [S53] M. Neiderhauser, CRSFJoystick (RP2040). https://github.com/mikeneiderhauser/CRSFJoystick (fetched)
54. [S54] CGM, neXt compatible input devices. https://www.cgm-online.com/rc-flight-simulator/next-input-devices_e.html (fetched)
55. [S55] Spektrum WS2000 product page. https://www.realflight.com/product/spektrum-ws2000-wireless-simulator-usb-dongle/SPMWS2000.html (search result only)
56. [S56] Godot proposal #552, Add OS time to InputEvent. https://github.com/godotengine/godot-proposals/issues/552 (fetched via GitHub API)
57. [S57] OpenTX 2.2 manual, Radio as joystick (8-bit, jscal deadband) — via RESEARCH.md. https://doc.open-tx.org/manual-for-opentx-2-2/advanced-features/radio_joystick (RESEARCH.md)
