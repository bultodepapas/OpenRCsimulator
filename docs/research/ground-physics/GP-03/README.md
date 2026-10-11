# GP-03 profile and trace integration

Status: focused software verification complete; physical acceptance remains open. Recorded 2026-10-11 with Godot `4.7.2.stable.official.ed1daf0bf` on Windows.

The integrated reader accepts wheel-state metadata schema v6 only when its wheel model, contiguous contact-order state layout, finite rim speeds, profile identity and appended continuous tail validate. Legacy traces without wheel state retain their prior schema and layout checks. This keeps older no-wheel aircraft readable while preventing a v6 trace from being mistaken for a legacy trace or silently losing wheel state.

The focused runs passed: atmosphere flight 140 checks, wind flight 51, wind trace 29; weather CLI 7 tests, atmosphere CLI 6 and shaft CLI 10. Full outputs are in the adjacent `*-flight.log` and `*-cli.log` files. The profile inventory is `profiles.json`. Exact SHA-256 values for tested draft sources and evidence are in [codehashmanifest.json](codehashmanifest.json).

Wheel-tail compatibility rechecks also passed on the isolated GP draft with pinned Godot `4.7.2.stable.official.ed1daf0bf` under WSL/Linux: session guards 32 checks, coupled shaft 43, electric battery session 103, and wash transport 38; each had 0 failures. The logs are [session guards](test_session_guards.log), [coupled shaft](test_shaft_coupled.log), [electric battery session](test_electric_battery_session.log), and [wash transport](test_wash_transport.log). These cover joint-path fault rollback, original RPM/battery/wash prefix indexing, and wheel-only continuous state on file-backed aircraft without transport wash.

Reproduction from the repository root in PowerShell:

```powershell
$Godot = (Resolve-Path .tools\Godot_v4.7.2-stable_win64_console.exe).Path
foreach ($Test in 'test_atmosphere_flight.gd','test_wind_flight.gd','test_wind_trace.gd') {
  & $Godot --headless --audio-driver Dummy --path .tools\gp-work\app --script "res://tests/$Test"
}
$env:OPENRC_TEST_GODOT = $Godot
python .tools\gp-work\app\tests\test_weather_cli.py
python .tools\gp-work\app\tests\test_atmosphere_cli.py
python .tools\gp-work\app\tests\test_shaft_cli.py
```

The tested sources were an isolated in-progress copy at `.tools/gp-work/app`; the manifest identifies that snapshot. These checks cover reader contracts, state continuity, trace and checkpoint behavior, and deterministic software execution. They do not validate tire or grass parameters against a physical aircraft, nor establish real rollout, braking, or taxi behavior.

The final integrated catalog inventory is [profiles-integrated.json](profiles-integrated.json), including the concurrent v2 aircraft inputs and the per-aircraft rolling reference radius. Post-merge tests and exact baseline parity are recorded in [GP-05](../GP-05/README.md).

## Integrated visual gear check

The native-app probe builds the Stik, Extra 300S and P-51D with their real model builders and sessions, then checks contact-order mapping, supported wheel-pivot compression, spin direction, steering limits and heading, finite simulation state, and observer teardown. It passed all 39 checks after 48 spin/steer ticks per aircraft. Per-wheel compression moved each matching wheel pivot exactly along its expected local up axis; maximum support compression was 19.2–21.7 mm. Re-run with pinned Godot using `& $Godot --headless --audio-driver Dummy --path app --script research/ground-physics/visual_gear_probe.gd` from PowerShell. The output is [visual-gear-probe.log](visual-gear-probe.log), and the probe itself is [visual_gear_probe.gd](../../../../research/ground-physics/visual_gear_probe.gd).

Compatibility-renderer captures show each aircraft in a near-ground close-up: [Stik](visual-gear-stik.png), [Extra 300S](visual-gear-extra.png), and [P-51D](visual-gear-p51.png). Each has an adjacent JSON capture record; the run output is [visual-gear-capture.log](visual-gear-capture.log). The [visual evidence manifest](visual-gear-manifest.json) pins the integrated source and capture hashes.

The numeric probe found a 5.0 mm rest wheel-center/contact-plus-radius offset on all Stik wheels; the Extra and P-51D residuals were about 1 μm. Steering-heading dot products were 0.9999958–0.9999998 on the lightly rough field, reflecting the renderer's vertical steering pivot versus physics terrain-normal projection. The screenshots prove visual construction and near-ground composition, not exact tire-ground contact; the P-51D's overhead close-up partly hides its wheels. The observer articulates wheel pivots while gear legs remain rigid, and does not displace the ground mesh. These are visual approximations, separate from the physical contact checks.
