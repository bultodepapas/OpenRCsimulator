# GDU-03: aircraft-flow test selects the interactive route

2026-10-25, official 4.8-beta1, Windows x86-64. The full unit partition found
that `test_ui_aircraft_flow.gd` expected a deferred flight build while using the
headless default. `AppRoot` deliberately constructs direct/headless flights in
the same frame; its interactive loading route is a separate, existing option.
The button already displayed the expected text, but `app.flight == null` failed.

The test now explicitly enables `flight_loading_enabled`, as the existing
`test_flight_loading.gd` does. It retains the preconstruction assertion and also
requires the loading screen. A bounded wait then requires completed startup,
the `ready` result and removal of that screen. This replaces the stale assumption
that construction always finishes after exactly two frames. Product code is
unchanged by this correction.

The corrected test passes all 20 assertions at a 1920×1080 headless canvas, with
zero engine errors or warnings. This checks route and layout state, not rendered
pixels. The original failure remains in the frozen suite's
`tmp/gdu03-shard3-r2/checks/godot-7_smcm2j/`; the successful checked invocation
and source identity are retained in [verification.json](verification.json).
