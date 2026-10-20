# FW-35c — shared aircraft light control

2026-10-19. Current interface, configuration and adoption instructions: [aircraft lighting standard](../../../AIRCRAFT-LIGHTING.md). This record owns verification observations.

## Implementation

The previous airplane route fitted lights only during construction or an L press. It did not reevaluate fixed-time edits, and flowing worlds fitted the kit even in daylight. The helicopter had an independent solar fade. Both now consume one flight-local selection policy: automatic civil evening from 17:30, their existing morning/daylight rules, and explicit manual precedence until session reset. The authoritative clocks remain fixed TOD configuration and the field-world clock; no OS time is consulted.

Fixed-wing kit binding now declares navigation, strobe, landing and orientation groups. The P-51 retains its articulated anchors and downlocked landing-light gate. Timber's imported `light_red` and `light_green` emission uses private surface overrides, so OFF also disables its existing glow without hiding reflective lenses or changing the source GLB/materials. HUD changes invalidate the light indicator even when diagnostics are hidden. No physics, aircraft quantities, geometry, shaders or dependency versions changed.

## Verification

Godot **4.7.2-stable**, Windows, Compatibility, OpenGL 3.3, NVIDIA RTX 3090, driver 617.42. Native tests used isolated APPDATA. [Source/capture identities and results](verification.json).

| Check | Result | Evidence |
| --- | --- | --- |
| Shared policy and real flight routes | 151 checks, zero failures, headless | [Log](control-headless.log) |
| Same suite with rendered ON/OFF captures | 162 checks passed; no script/shader/renderer errors | [Native acceptance log](native-acceptance.log) |
| Existing GPU strip/sprite regression | 123 checks passed | [Summary](gpu-summary.json), [log](gpu.log) |
| Kit geometry, mode and crash mounting | 34 checks passed | [Log](night-kit.log) |
| P-51 anchors, rudder following and gear gate | 13 checks passed | [Log](p51-lights.log) |
| Helicopter optics, fade, rotor phase and mode isolation | 47 checks passed | [Log](helicopter-kit.log) |
| Existing world/field-light suite | 86 checks passed | [Log](world-field.log) |
| Paused time UI, persistence and Restart | Passed | [Log](test_ui_time_of_day_pause.gd.log) |
| Existing Help/input UI | Passed | [Log](test_ui_help.gd.log) |
| Project editor import | Completed without script/shader errors | [Log](import.log) |
| Shell partition harness | Five checks passed in WSL on a disposable LF copy | [Log](partitions-wsl.log) |

The main suite covers all five airplane visual families and the helicopter. It exercises manual ALL/NAV/OFF, physical-key repeat, controller actions, current HUD state, starting at 17:30, paused edits across that time, actual 240 Hz flight-clock progression through 17:30 with and without an override, fresh scenes, session resets, successful aircraft-data reload, Home aircraft changes, configurable thresholds, supported groups and imported emission isolation. The separate [native flow check](flow-native.log) also completed all six assertions without rendering errors.

The GPU regression checks that strips add light without dark blocks, disappear from the wrong side, remain visible at dusk, keep their pixel size under zoom/aspect changes, and stay behind opaque foreground geometry. No lamp shader changed. [Fleet ON/OFF comparison](fleet-on-off.png); full-resolution Timber [ON](turbo-lumber-evolution-on.png) / [OFF](turbo-lumber-evolution-off.png), and [helicopter](helicopter-on.png). All captures use the simulator renderer. The fixed-time flight views are paused; their synthetic FPS text is not a performance measurement.

Repeated unchanged policy samples measured below 1 microsecond per call on this host; this excludes the rest of presentation and rendering. Repeated updates retain one kit with unchanged child counts. This is bounded-work evidence, not an uncontended whole-frame or target-hardware performance qualification.

## Broader limitations and diagnostics

The combined native harness initially reported two 349524-byte texture leaks at renderer shutdown, after its 162 assertions passed: [diagnostic run](native-complete.log). A separate run of the **pre-change Home script** from `eddef175e` reproduced exactly two same-sized shutdown leaks when two previews were created and freed before rendering: [baseline log](native-home-baseline.log). The test now lets each native Home preview render before disposal. The final native acceptance run completed all 162 checks with no shutdown errors. No unrelated Home renderer repair is claimed.

`test_time_of_day_checkpoint.gd` reaches its P-51 coupled-shaft case and then accesses `physics` on an empty checkpoint: [current log](checkpoint-isolated.log). A probe using the **pre-change main.gd** from `eddef175e`, with current dependencies, also obtains an empty checkpoint at that point: [baseline probe](checkpoint-baseline.log). The complete checkpoint suite and complete application test suite are not claimed to pass. Earlier fixed-time restore assertions and the dedicated pause/Restart UI checks do not close that broader checkpoint failure.

The first attempt to run the Bash partition fixture with Windows Python encountered the checkout's CRLF and WSL environment transfer behavior. It passed under WSL with the runner copied to a disposable LF fixture; the working checkout's EOL rules were preserved. Existing unsupported-maple-wind and experimental-aircraft warnings remain visible in logs. Physical aircraft, pilot night-flight acceptance and low-end GPU qualification remain with their existing gates.
