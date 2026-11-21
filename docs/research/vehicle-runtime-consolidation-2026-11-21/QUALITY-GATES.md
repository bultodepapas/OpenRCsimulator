# Verification, response, rollout and stop gates

**Status:** proposed implementation/qualification gates. No Godot test, flight replay, device campaign or CI was run for this documentation revision. Static document/data verification is recorded separately in [verification.json](verification.json). The [VRC plan](../../plans/vehicle-runtime-consolidation.md) owns open implementation steps; the [control contract](CONTROL-CONTRACT.md) defines the proposed interface obligations.

Use existing [tool selection](../../tools/README.md), [verification scope](../../tools/shared.md#verification-scope), [physics checks](../../tools/physics.md), [flight logs](../../FLIGHT-LOGGING.md) and [native admission](../../../research/native-kernel/README.md#normal-flight-backend-selection). These gates add specificity; they do not replace owning-track rules.

## Q0 Baseline and test admission

Before a migration, pin base and candidate source/dirty state, test source, engine version/hash, OS/architecture, actual backend/library, generated data/assets, field/weather, real catalog ID, profile/mapping and launch route. Identify expected fixtures and imports. A source checkout with missing dynamic resources is not an adequate substitute for the affected production activity.

The [prior controls audit](https://github.com/bultodepapas/OpenRCsimulator/blob/895dd4352c5191f1539a8b8f4df1996cd33eb86f/docs/research/game-controls-audit-2026-11-21/VERIFICATION.md) is historical Linux headless synthetic evidence: **22 of 27 programs passed; five failed/incomplete**. Its sources and tools are in that pinned commit, not present as executable audit scripts on this branch. Do not copy their adverse assertions unchanged and call a passing run a repair.

| Prior unqualified program | Treatment before relying on it |
| --- | --- |
| `test_controller_pause_recovery.gd` | Prior timeout/errors; provision required resources and investigate on the selected candidate. |
| `test_controller_recovery_focus.gd` | Prior timeout/errors; obtain decisive focused consumer evidence. |
| `test_controller_menu.gd` | Prior timeout/errors; qualify the actual screen/activity path. |
| `test_mr_controller_authority.gd` | Printed passing assertions but had engine errors; not a pass. Check complete clean execution. |
| `test_controller_car.gd` | Prior missing MT8 model; materialize required assets and rerun when ground is in scope. |

Keep failures, infrastructure problems and unavailable qualification separate. Do not assert every prior failure is caused only by missing assets. VRC-00 records all five GCA findings and each affected step's disposition. An unrelated baseline failure needs an explicit scope explanation; it cannot excuse a failing invariant in a touched path.

Tests use fresh isolated user/config/output paths. Serialize imports in one stable checkout and isolate process-global InputMap, device injection and focus state between cases, or use separate processes. Concurrent suites need separate checkouts and profiles and the [configured host/pool admission](../../../tools/testqueue/README.md). Do not bypass unavailable admission or submit duplicate jobs after uncertain status.

## Q1 Controls and transition contract

Select applicable IDs from [control-cases.json](control-cases.json) before implementation. Each row states owner, trigger/timeline, oracle, relevant seams, existing test starting points and `UNRUN` status. It is an executable specification **to implement and run**, not an assertion of existing coverage. Record actual fixture implementation and receipts when claiming completion.

Minimum coverage for an affected input/bridge route:

- Current versus stale activity/device/generation/profile authority at actual dispatch, including changes after status was displayed.
- Event versus poll evidence, held keys/buttons/axes, release/rebind/capture, independent pause holds and first accepted command. Verified gamepads retain first-valid-poll readiness; applicable radio LOW/OFF/center gates remain distinct.
- Admitted action → saved/active binding → real activity response; keep the existing keyboard/gamepad path and reject unsupported forms explicitly. Synthetic fakes alone do not establish the whole route.
- Failed activation/save and explicit recovery preserve the correct accepted state; known GCA paths have repaired oracles, not only reproducer success.
- Supported Home/direct/Workshop routes, same-radio menu centering where applicable and truthful unsupported/unknown status. Preserve existing guarded Fly/restart semantics.

For a pure status projection, test detachment, unknown fields, dynamic operation support and stale activity disposal; do not force the entire physical matrix. For shared input changes, expand to every affected family/route even if the first UI consumer is fixed-wing. State-machine sequence tests use declared seeds, bounded event/tick timelines, invariant assertions and a minimized failure trace; they supplement specific cases and cannot hide unvisited required transitions.

### Existing test starting points

Paths below are real executable scripts under `app/tests/` at the baseline. They do not imply every proposed case exists or passes.

| Boundary | Starting points | Additional decisive proof when moved |
| --- | --- | --- |
| Status/fixed-wing transition | `test_flight_session_staged.gd`, `test_flight_reset_transaction.gd`, `test_reset_publication.gd`, `test_restore_publication.gd` | Real consumer ordering; reject versus accepted fault; old writer/footer and held-key boundary. |
| Registry/profile/store | `test_controller_registry.gd`, `test_controller_profile.gd`, `test_controller_settings_save.gd`, `test_controller_audit_concurrency.gd` | Changed relevant profile/connection during intent; legacy GCA-04 and tiny-span GCA-05 repair witnesses. |
| Actions/temporal input | `test_rc_input.gd`, `test_controller_actions.gd`, `test_controller_edge_continuity.gd`, `test_controller_routing_audit.gd`, `test_aux_pause_retention.gd` | Real activity first-command chain; routing audit uses fake service/flight/session and is not sufficient alone. |
| Shaping | `test_controller_conditioning.gd`, `test_controller_rates.gd`, `test_controller_flap_mix_profile.gd` | Raw input→conditioning→session/tick, correct rate/expo/trim ownership; verified versus unverified fixtures. |
| Capture/menu | `test_controller_setup_safety.gd`, `test_controller_capture_scroll.gd`, `test_controller_menu.gd`, `test_e2e_input.gd` | Actual assigned control/release in screen context; text fields and native focus. E2E input is keyboard/main-scene coverage, not all devices. |
| Airship | `test_airship_session.gd`, `test_airship_activity.gd`, `test_controller_audit_vehicle_airship.gd`, `test_airship_flight_log.gd` | Low throttle plus centered yaw, armed input gate, menu ownership and transient profile retry. |
| Quad | `test_dr_multirotor_kernel.gd`, `test_controller_audit_vehicle_quad.gd`, `test_mr_controller_authority.gd` | Full admitted Pause dispatch, activity readiness/first tick, held fallback, race/tape policy. Input/plant checks do not prove shell dispatch. |
| Ground when in scope | `test_controller_ground.gd`, `test_controller_car.gd` | Neutral/armed, actual assets, interrupted export and explicit discard. |
| Flight/replay | `test_golden.gd`, `test_flight_log_inputs.gd` | Applicable retained complete tape and backend identity. `golden_flights.gd` is a helper, not a test launcher. |

### Checked verdict and completion

Use the canonical [checked-runner procedure](../../tools/shared.md#one-godot-script) or admitted pool. The pinned staged fixture example is:

```sh
python3 tools/godot/run_checked.py --timeout 90 \
  --require-text "FlightSession staged fixture: 12 checks, 0 failed" -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_flight_session_staged.gd
```

This command is **unrun here**. Recompute the expected terminal summary when intentionally changing the test. `--require-text` checks a literal substring, not an assertion-count grammar. Accept only the complete intended roster, positive expected count, zero failed assertions, successful process exit and no engine/script errors. Read the runner's `ok` and `reason`; `complete` means collection finished, not that the test passed. Retain and classify warnings under a declared policy; default runner behavior does not fail all warnings.

Examples at the pinned revision: `test_golden.gd` reports `4 golden flights, 0 failed`; the previous controls audit records routing `31 checks, 0 failures` and profile `91 checks, 0 failed`. These historical summaries are not new results or substitutes for selecting the current roster. Early exit, missing completion, timeout or errors remain FAIL/INCOMPLETE, even if a summary prints zero failed assertions.

## Q2 State, replay and lifetime

For unchanged laws/behavior, compare accepted commands, state arrays, event order, ticks, seeded state, checkpoint content and observer outputs under the contract's existing exactness/tolerance. Do not impose bitwise equivalence across unsupported platforms/backends. Golden maneuver tolerances are not byte-exact replay; `test_flight_log_inputs.gd`'s short synthetic tapes are not retained real-device flights.

Use this replay decision:

| Comparison | Required meaning |
| --- | --- |
| Original complete tape on original solver/backend/engine | Exact baseline replay, verified completeness and recorded identities. A recovered prefix is incomplete. |
| Candidate with unchanged supported identity | Exact mode only if all identity/admission checks genuinely match. |
| Structural change alters source fingerprint | Keep exact-mode refusal. Use compatible explicit candidate same-tape workflow for comparison; report `mode`, actual `solver_changed`, complete ticks and comparison result. Do not edit the old tape's identity. |
| Native behavior is affected | Current candidate mode selects reference; separately prove actual native selection/calls, parity, fault/rollback, ABI/library/source and package gates. |
| Servo checkpoint or other unsupported candidate domain | Candidate mode can refuse; do not bypass it. Obtain an owner-supported differential harness or leave that comparison blocked. |
| Device/profile/rates/expo path changes | A post-conditioning tape cannot retest it. Add input-path, live consumer and required physical/pilot evidence. |

The source fingerprint includes path and bytes of recursive `.gd` files in `app/sim`, `app/physics` and `app/failures`, plus `app/input/commands.gd` and `app/spec.gd` ([writer](../../../app/sim/flight_log.gd), [CLI](../../../app/tools/flight_log_cli.gd)). Thus a source move can change identity without changing dynamics. Candidate comparisons retain the same compatible initial state and command tape; separately record any intentional law/config change and do not call it an exact replay.

Select real catalog IDs/tapes covering the touched capabilities; record overlap and exclusions. Expand at integration/release where shared effects warrant it. Aircraft category names alone do not prove coverage. Helicopter, airship, quad and ground use their actual owned tape/checkpoint/recorder contracts, not assumed `.orfl` equivalence.

Moved fixed-wing transactions must distinguish refusal retaining old state/writer from an accepted observer fault that leaves a committed paused frame. Inject reentry and verify the owner-specified publication/footer and statistics-generation or noncredit outcome exactly once, as applicable; restore retains its noncredit branch. Airship and quad can notify recorders before a later reset refusal; characterize that behavior, and repair separately if a stronger guarantee is required. Do not silently change it in a refactor.

Lifecycle cases cover tentative detach/replacement cancellation, late load completion, repeated close, failed finalization/export, pending race results, explicit discard and correct worker retirement. Preserve existing recording/file format and source-to-artifact identity. Do not infer power-loss durability from process-level publication tests.

## Q3 Player flow and device qualification

Use the existing [controller hardware matrix](../../plans/controller-support.md#hardware-matrix), [physical procedure](../../plans/controller-support.md#physical-acceptance-procedure), [Controls UX](../../plans/controls-setup-ux.md) and owning family guides. Avoid a gratuitous device × model × OS × scene cross-product: cover changed seams with deterministic cases, then qualify the actual supported physical rows and release cohorts.

Run affected Home → Controls → test/save → launch → Pause/settings → recovery → Home flows through real UI, with explicit supported routes and exceptions. Native dialogs/text entry may retain keyboard/mouse exceptions. Verify EN/ES labels, focus/cancel, selected-device feedback, actionable errors and accessible control names at the applicable [display target](../../../AGENTS.md#display-resolution-priorities): normally 1080p first, native Retina pixels where that policy applies.

Physical source and exported-build evidence are separate. Preserve device/model/firmware/OS/transport/wrapper/profile/build identity, with unknown metadata marked unknown and identifiers redacted where appropriate. USB disconnect, Bluetooth sleep and transmitter-off while a receiver stays enumerated are distinct. Steady axes do not prove RF health. Missing hardware remains untested and limits published support claims.

The existing procedure calls for 30 seconds of idle observation, at least ten fault/reconnect cycles per primary path and at least 30 filmed transitions per qualified primary transport for response measurement. These are future obligations, not measurements made by this audit. Keyboard remapping, assistive-device breadth and formative pilot usability stay open with their existing owners unless separately delivered and qualified.

## Q4 Response and performance

Measure the changed input seam as well as complete workload cost. Record event/sample age, first accepted command/tick and first visible response; preserve order and freshness. Do not add an unexplained render-frame queue. Pin and record different baseline/candidate source identities with only the intended change varied; match engine/assets, profile, actual backend, display/FPS and workload on the same host, with an unchanged control scenario. Match input tapes where replayable; physical F6 and pilot work use their own repeated-transition protocols, not a claim of identical physical inputs.

Attribute a bottleneck before optimizing. Repeat paired alternated A/B runs and retain sample count, p50/p95/tails, uncertainty, allocations/retained memory and cold/warm state. Include the real vehicle/scene load; a microbenchmark is only local evidence. Callback counts are neither USB polls nor CPU time nor motion-to-photon latency. The prior 2 Hz store-lease and event-cache optimizations are already implemented; do not claim them again.

Use F6 for physical latency and separate first visible control response from aircraft motion/servo dynamics. No guessed absolute latency budget or speedup is introduced here. Stop for reproducible regression beyond declared measurement uncertainty, added buffering, invalid-sample masking, input-order drift or unexplained memory growth. Leave PT/VQ/NK measurement acceptance with those owners.

Lifecycle/soak checks follow their existing owners: the [global performance plan](../../plans/global-performance-visual-quality.md) and [desktop plan](../../DESKTOP-DELIVERY-PLAN.md) define different integration/release campaigns. Do not conflate a shorter local repetition with full delivery soak or infer that a finite run proves absence of leaks.

## Q5 Promotion and rollback

Before an implementation slice merges or is described as complete:

- [ ] Exact candidate, scope, owner, required cases and nonapplicable rows are recorded with reasons.
- [ ] Affected GCA defects are repaired before migrating their seam; unchanged unrelated findings remain visible.
- [ ] Actual consumer tests and required diagnostics/terminal summaries pass; no missing required fixture, unexplained error or incomplete case is hidden.
- [ ] Required CI is checked on the final tested source/merge identity. Focused local or static documentation checks are not full CI.
- [ ] Applicable replay, native, rendered, physical-device, pilot and exported-package evidence are separately labeled and attached.
- [ ] Structural work preserves schemas and user data; rollback is checked with the accepted profile/recording state, not only reverted code.
- [ ] No new authority, generic family switch, tick source, accidental controller handoff or masked fault has been introduced.
- [ ] Player/support wording names only qualified devices/routes/platforms and retains remaining limits.

A failed affected safety invariant stops that migration. An unrelated baseline failure requires an explicit bounded disposition, not a blanket waiver. A proposed or UNRUN case, historical adverse witness, missing device or interrupted soak cannot count as PASS. Optional extractions do not delay a separately complete controls repair.
