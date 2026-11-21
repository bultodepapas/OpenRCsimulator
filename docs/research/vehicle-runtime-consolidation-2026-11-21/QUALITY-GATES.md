# Verification, performance, rollout and stop gates

**Status:** planned test strategy only; none of the commands below was executed for this planning branch. Baseline source `57abea025f62b20233ca281d58d2acbee4ab8b8e`. Follow [TOOLS](../../TOOLS.md), [tool verification scope](../../tools/shared.md#verification-scope), [physics checks](../../tools/physics.md), [FLIGHT-LOGGING](../../FLIGHT-LOGGING.md) and [AGENTS](../../../AGENTS.md). Run from repository root with the pinned `app/get-godot.sh` engine and checked runner.

## A. Characterization before any extraction (VRC-00/01)

- Capture exact `git status`/SHA, engine hash/version, source/data/catalog hashes, OS, native/reference selection, field, vehicle, weather, controller route, replay law/format and generated resource identities. Separate current upstream failures from change-caused failures.
- Capture a baseline complete fixed-wing `.orfl` for a representative conventional electric, glow, turbine, retractable, flap and elevon model. Use available canonical fixtures where possible; no physical-accuracy claim. Require `complete=true` and expected `solver_changed=false` for exact same-backend replay. Keep input tape/ticks identical for candidate. Distinguish post-conditioning command replay from actual device shaping.
- For helicopter, airship, quad and ground use their **actual owned** checkpoint/tape/session tests; `.orfl` equivalence is not assumed.
- Add contract tests for accepted/refused lifecycle requests, one-shot listener publication, duplicate/dropped event negatives, loss/reconnect generation, focus and crash. Cover saved settings and native fallback, including no live scene mutation from a detached snapshot.
- GCA-01…03 are known audit findings; report their unchanged witnesses as a separate defect bucket, not as a pass or a regression introduced by the refactor.

## B. Focused checks by PR

| Scope | Example checked tests already present at baseline | Additional witness |
| --- | --- | --- |
| Aircraft schema/registry (AS coordination) | `test_aircraft_contract.gd`, `test_aircraft_modules.gd` | Unknown capability refused, all offered variants and Workshop/flight agreement |
| Fixed-wing transition/session | `test_flight_session_staged.gd`, `golden_flights.gd`, `test_flight_log_inputs.gd` | Refused reload retains state/recording; accepted start observer count and exact replay |
| Control routing | `test_controller_pause_recovery.gd`, `test_controller_routing_audit.gd`, `test_e2e_input.gd` | Keyboard/radio/gamepad, stale generation, OFF-before-ON, no action accepted but ignored |
| Airship | `test_airship_session.gd`, `test_airship_flight_log.gd`, `test_airship_activity.gd` | Yaw/throttle centered resume, stale native menu mapping and profile retry witness |
| Quad | `test_dr_multirotor_kernel.gd`, `test_controller_audit_vehicle_quad.gd` | FC sample once/tick, pause binding, race results and outbox, tape cap |
| Ground (later opt-in) | `test_controller_ground.gd`, `test_controller_car.gd` | Neutral+armed, interrupted export, damage and course identity |
| Native selection and shared transaction | `test_golden.gd` and the exact applicable native/reference parity suite in the current physics guide | Qualified source/ABI/back-end, atomically committed state and fault rollback |
| UI/camera/HUD | Applicable current menu, HUD, render and controller prompts suites | 1080p visible behavior, no duplicate listeners and correct scene/resource lifetime |

**Run an individual Godot test with the checked runner**, for example (replace with the exact selected file and resolved engine):

```sh
python3 tools/godot/run_checked.py --timeout 90 -- "$(app/get-godot.sh)" \
  --headless --path app --audio-driver Dummy --script res://tests/test_flight_session_staged.gd
```

The runner validates messages as well as exit code. This is a *recommended command*, **not a recorded pass**. Recheck test names and imports at implementation revision; match the repository's required CI before merge. Some prior controls audits encountered missing assets in sparse checkout; qualify only with required assets and log failures without recategorizing them as source defects.

## C. Numerical and identity gate

- For a structural-only change, require byte-equal accepted state, input, event ordering, tick count and checkpoint identity where the current contract guarantees it. Do not re-record goldens to hide drift.
- Replay the original complete `.orfl` on the matching backend/source with identical tick/input tape. Compare candidate with fixed start/field/weather/law/source. Mark `solver_changed` and `complete` from outputs, not assumptions; a recovered prefix does not certify equivalence.
- If native callback preparation or event order changes, use explicit fault/rollback tests, negative controls, and the current native guide’s reference/ABI/package gates. A reference fallback is not native parity.
- For changed controller conditioning, a post-conditioning replay cannot test raw HID/profile/calibration; add actual input-path unit/integration and physical-route qualification.

## D. Performance gate (VRC-09; no promised savings)

Before selecting optimization, profile *real* representative flight workload and source/host/backend across warm/cold launches and air/ground/hover/idle regimes. Track wall-time per accepted tick, p50/p95/p99 where stable, allocations/retained memory, scene-load stalls, and 1080p frame pacing separately. Select one dominant attributed cost, one candidate, one unchanged negative/control scenario.

Use paired alternated A/B runs on the same host with equivalent assets and controller tape, and compare full-session results. Publish raw samples, sample size, variability and confidence/limits. Never add historical NK-2a or renderer speedups to forecast VRC benefits. Stop/revert if behavior drifts, memory grows materially, a new dependency creates frame-blocking loads, or target hardware does not reproduce improvement. Performance approvals remain with PT/VQ/NK owners.

## E. Merge checklist for each independently reviewable PR

- [ ] Current base and owner coordination recorded; changed paths limited to one contract or concern.
- [ ] No new vehicle-type conditional branch in `Simulation`; unchanged precision and 240 Hz clock.
- [ ] New shared code has **at least two real supported consumers** or isolates a demonstrated risk/test seam.
- [ ] Before/after acceptance, refusal, interruption, restart, checkpoint, listener and resource lifetime checked.
- [ ] Affected tests and broad tests required by impact passed with raw receipts; CI failures classified, not concealed.
- [ ] Source/version/backend identities and exact replay recorded when trajectory/tick input may be touched.
- [ ] Headless synthetic vs native UI/device/pilot vs exported-package results separately labeled.
- [ ] Docs/track registry and relevant authoritative plans updated without duplicating status.
- [ ] Source tree clean after committing owned paths; no generated artifacts or rewritten baselines without documented reason.

**Release/blocker policy:** a source-only plan is not CI evidence. Failure of an unrelated baseline test requires explicit disposition, not silent acceptance. An unexplained physics/checkpoint drift, new control action gap, or missing required test is a stop, not an excuse for a broad rewrite.
