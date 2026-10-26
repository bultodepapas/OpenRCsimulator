# GP-14 X8 landing-support audit

2026-10-26. Read-only runtime audit; the only application edit is
`app/tests/test_flight_statistics_detector.gd`. No support role or physical law was added.

`app/data/aircraft/skywalker_x8.json` and
`app/data/aircraft/battery/skywalker_x8_6s_pack.json` author `gear: locked_up`,
no `landing_gear` or `ground`, and 28 stable crash-hull IDs. `probe_belly_front`
and `probe_belly` have belly crash labels; wing-bottom probes also exist. These
are geometric/contact labels, not intended landing roles. The source pipeline is
`research/skywalker-x8/X8-06/derive_physics.py`; generated aircraft JSON must not
be edited directly. `app/tests/test_x8_flying_wing.gd::_hull` proves a synthetic
3 m/s contact survives its estimated EPO thresholds, not successful landing credit.

`app/physics/aircraft_contact_contract.gd::describe` exposes 28 hull probes and
zero wheel support points. `app/statistics/profiles.gd::resolve` correctly returns
`landing_available: false`, `reason: unreviewed_aircraft_profile`, empty support
maps and no derived rest height. `app/sim/flight_session.gd::accident_observation`
correctly excludes an aircraft without wheel bindings from gear-up accidents.
Its intended-support flag remains false; `app/statistics/fixed_wing_adapter.gd`
therefore marks hull contact incident. Enabling successful belly landing needs
an explicit role contract and propagation; a guessed wheel profile cannot do it.

The detector test now retains explicit coverage for all nine known wheel-equipped
catalog aircraft and their two-main/three-stop geometry gates. A separate named X8
case checks both stock power variants, absent installed wheels/roles, unavailable
landing credit, empty maps and all 28 exact authored/bound hull IDs. Future unknown
catalog aircraft fail until explicitly reviewed. Existing changed-geometry rejection
remains. This replaces three invalid fleet-wide wheel assumptions with explicit
coverage assertions; it does not qualify belly landings.

Draft parsed outside `app/`; draft and promoted suite each passed **111/111**.
Main receipt: `tmp/gp14-x8-checks/main/godot-lxa57g5p/report.json`
(complete=true, ok=true, exit 0, no diagnostics).
Test SHA-256: `fc83209a7f15c1eb90c3f5503f02bc28a9012e884b9701c838cc7737d15fd7d2`.

Proposed next scope, pending root agreement: an optional source-authored intended
hull-support capability, referencing existing hull IDs/geometry and selected soft
hull law, with provenance, qualifying support/stop rules and reviewed rest envelope.
Mixed intended/incidental contacts must not become globally exempt. Extend the
source validator/generator, contact description and observer before granting credit.
Do not add a second integrator or duplicate physical geometry.
