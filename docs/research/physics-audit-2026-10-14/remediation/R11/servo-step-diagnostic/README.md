# R11 Servo-Step Test Fixture

The Avanti servo-observation test failed before a simulation tick began. After `FlightSession.setup`, a retractable-gear aircraft has six simulation inputs: roll, pitch, yaw, throttle, gear command, and wheel-brake demand. The test replaced that initialized array with four values. `Simulation.step()` checks the array length at [simulation.gd:189](../../../../../../app/sim/simulation.gd#L189), rejects it at line 191, and emits `before_step` only after validation at line 193. The recorded diagnostic therefore isolates an input-shape error; it does not exercise the servo response or any changed physics law.

The native reproduction used Godot 4.7.2 on the retained Windows source copy `tmp/physics-audit-r11-final-scenarios-04/verified-app`. Its original test, simulation, and Avanti data hashes match the frozen Linux R11 candidate. Its `flight_session.gd` differs from that candidate only by adding `p51d-mustang-120` to `RUNWAY_AIRCRAFT_IDS`; the Avanti setup, input sizing, and input layout are unchanged. The diagnostic uses the original four-value command and records the exact fault and rollback state in [before-native-windows.txt](before-native-windows.txt).

The Avanti reproduction reported `input_size=6`, command length 4, fault `step rejected: input or auxiliary state is nonfinite or malformed`, tick 0, and zero `before_step` signals. State, previous state, auxiliary state, continuous state, modes, and loads stayed byte-identical; fail-safe restored the original six-element input array. Setup had passed `is_flyable()` before the attempted step; the report's `flyable=false` is the post-fault state.

The fixture now duplicates `flight.sim.inputs` and overwrites only indices 0–3 in [test_control_surface_observation.gd:36](../../../../../../app/tests/test_control_surface_observation.gd#L36). This retains the gear and brake slots for aircraft that have them. The same test then passed all 50 existing checks across the catalog's flyable aircraft; see [after-focused-test.txt](after-focused-test.txt). No assertion count, threshold, runtime behavior, aircraft data, or golden recording changed.

The ready-to-apply fixture diff is preserved in [test-fixture.patch](test-fixture.patch).

The R00 baseline already has the same test fixture (test SHA-256 `B616F8C611F978DEAEA911B5B76C4890085488CE43DB9A18F860F1BE457D9D51`), the same six-slot retractable-gear input protocol, and a `Simulation.step()` length guard before `before_step` (baseline simulation lines 172–176; baseline `flight_session.gd` lines 996 and 2101–2106). Its Avanti data also contains the retractable-gear section. The same pre-step rejection therefore predates the R05B/AV17/H4/H7 changes; the R00 test itself was not rerun for this repair.

## Reproduction and verification

Original failure diagnostic:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/physics-audit-r11-final-scenarios-04/verified-app --audio-driver Dummy --script research/physics-audit-2026-10-14/remediation/r11_servo_step_diagnostic.gd
```

Focused post-fix test:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_control_surface_observation.gd
```

The first command exited 0 after reproducing the expected invalid-input rejection and exact rollback. The second exited 0 with `Control surface observation: 50 checks, 0 failed`.

## Identities

| Artifact | SHA-256 |
| --- | --- |
| Test before fix / frozen candidate | `B616F8C611F978DEAEA911B5B76C4890085488CE43DB9A18F860F1BE457D9D51` |
| Test after fix | `CC79E175C84CF7B4489BC4BF9895D1FA44C177C32721A285AC6C8F4606B0F26E` |
| Diagnostic script | `E7C37C79D5662AA220888C6E33BD171A8BE8B6395B8D532C8FC6E1D5F9858CA9` |
| Current simulation source | `545ED43EA3C1BBBFA505E9EB9BAC1021CDEE32CC7503F83F58931568A45D0AC9` |
| Current flight-session source | `6AB22B03A16B9A5783931254BCF407C97D6E2A09EDEB45A3974C09C2EC199F43` |
| Current Avanti aircraft data | `68D3FD42B28E30BF1DC210B838D945D517F062506749AF14F995A5A5F39A83B6` |
| R00 baseline simulation source | `B57F836BA757CC25ACD3B724B0BD40BE2D20BCC92C1837D8D557566ADB2E2A41` |
| R00 baseline flight-session source | `D23145D1C726752F730EE83988EEACB4FE101B996A8E5608B05B53207B77C5D0` |
| R00 baseline Avanti aircraft data | `74043C9BC1DE35DE066BC65B971E85F5E099173F2D9CCCEC065C6988ABBB6B9D` |

The frozen Linux candidate independently reported hashes `b616f8c6…` for the original test, `545ed43e…` for `simulation.gd`, `df45d4bd…` for `flight_session.gd`, and `68d3fd42…` for Avanti data. The sole source-copy difference described above is outside the tested input path.
