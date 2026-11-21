# Control boundary contract for VRC migrations

**Status:** proposed acceptance obligations, not a newly implemented API or a certification of current controls. Runtime baseline `57abea025f62b20233ca281d58d2acbee4ab8b8e`; review [scope and findings](EXTERNAL-AUDIT.md). The [VRC plan](../../plans/vehicle-runtime-consolidation.md) owns implementation status; [controller support](../../plans/controller-support.md) owns existing input policy, and [Controls UX](../../plans/controls-setup-ux.md) owns its remaining user experience work.

The first slice is one fixed-wing status/pause/resume consumer. Later requirements apply only when their seam is changed or a qualification claim depends on them. They do not authorize a common reset/restore/exit framework.

## 1. One owner for each decision

| Decision | Authority to retain | Bridge responsibility |
| --- | --- | --- |
| Connected device, role, connection generation | [Registry](../../../app/input/controller_registry.gd) and current selection owner | Resolve the current owner; reject a mismatched expected identity. A numeric device handle alone is insufficient. |
| Profile, eligibility, mapping and storage | [Controller service](../../../app/input/controller_service.gd), [profile](../../../app/input/controller_profile.gd), store/legacy owners | Preserve managed and direct resolution routes. Recheck relevant mapping/action identity after change; do not make a new profile cache. |
| Input event, poll, normalization and edge memory | [RcInput](../../../app/input/rc_input.gd), action/menu and family adapters | Keep event evidence distinct from a polled sample; preserve shaping and edge rules. |
| Player intent, screen/focus/capture and menu holds | [AppRoot](../../../app/app_root.gd), screen stack and actual activity | Forward through the full current call chain, in order; do not infer safety from a previously enabled button. |
| Family readiness and resume | Existing shell/activity entry point **plus** its session chain | Fixed-wing Continue includes AppRoot/screen-stack checks; airship/quad include their activity checks. Never bypass them by calling a session alone. |
| Accepted tick, physical state, checkpoint and observer transaction | Family session, [Simulation](../../../app/sim/simulation.gd) and existing model | Observe detached outcomes. No extra sampling inside solver stages or new tick source. |

Direct flight, standalone tools and external-driver cases may intentionally operate without `ControllerService`. Preserve the supported route and its different profile/input admission; do not require a singleton merely to share a helper. The route inventory must name Home/direct/Workshop combinations actually offered at the implementation revision.

## 2. Status is a projection; intent is a request

A minimal projection identifies its activity and reports what the owner knows: preparation/running/paused/fault state; active hold reasons; available operations; current input readiness and recovery action; and actual backend/identity when available. These are views of existing owners, not new mutable lifecycle state. Distinguish **unsupported**, **temporarily refused**, **unknown**, and **ready**. Missing data never defaults to ready.

Static features can be immutable for a specific model identity. Operational availability changes with the profile, equipment, external driver and current session. In particular, simulator-rate availability is not equivalent to a static airplane capability. Refresh it from the owner; a stale snapshot cannot authorize an action.

Detach nested arrays/dictionaries/resources that carry mutable state. A caller mutating a snapshot must not change the session, input reader, profile or another view. Avoid expensive full-state copies at every input event; choose the smallest view and profile its cost if it enters a hot path.

The intent's captured activity/role/generation/profile context is diagnostic or an expected-identity check. At dispatch, the current authority validates the actual selection, relevant mapping, capture/focus and family readiness. A relevant change between display and dispatch invalidates stale permission. If processing yields, queues or awaits, revalidate after that boundary. Reuse current identity/fingerprint mechanisms where sufficient; no universal revision service is prescribed.

Results must reflect the owner operation: unsupported, refusal, acceptance, or accepted-with-fault if a physical commit has occurred. Do not fabricate a common rollback promise. Do not retry a non-idempotent transition after an ambiguous result; first reconcile the actual owner state. Async work has an owner and cancellation/completion path; late results cannot act on a replaced activity.

**Cases:** C01–C04, C27–C30 in [the acceptance matrix](CONTROL-ACCEPTANCE.md).

## 3. Temporal input semantics

For each changed seam, trace the **actual event and poll order, conditioning, admission, first accepted command/tick and visible response**, marking absent stages where they do not apply. Routes need not share one canonical pipeline. Identify source, connection generation, relevant profile/mapping and event-versus-poll origin. Ordinary unverified polls cannot manufacture radio LOW or post-focus/reconnect center/OFF evidence. Preserve the explicitly trusted same-generation verification-challenge seed in [radio menu input](../../../app/ui/radio_menu_input.gd); it is a separate validated path. Stationary input or absent events alone do not establish disconnection.

Preserve these distinct contracts:

- **Verified gamepad:** the first valid trusted poll may establish readiness; no universal neutral dwell, motion gesture or button-release requirement may be added by the bridge. Raw/unverified fixtures are not evidence for changing that policy.
- **Radio:** current connection/mapping evidence and the existing LOW, OFF and verified-menu center requirements remain authoritative. A held ON value before selection/reconnect/focus recovery does not become a new press. Reduced, reversed and offset learned-axis ranges retain hysteresis.
- **Ordinary hold:** where the family already polls rate throttle during a hold, preserve its nonintegrating path. Virtual rate throttle does not drift while the menu is open. Do not infer that all input accumulators roll back with a failed physical tick; characterize the actual sampling and fault boundary.
- **AUX:** an unarmed bound channel is no command, not an instruction to retract gear/flaps. Preserve latched targets and the separately owned smoke-off policy. Fresh OFF rearms according to the current action semantics.
- **Keyboard:** consuming a UI event does not suppress global physical-key polling. Retain the [per-axis held-key mask](../../../app/ui/held_keys.gd): Down held while selecting Continue cannot become immediate pitch until released; an independent axis remains independent. Positional radio sticks are not masked by this keyboard rule.
- **Capture/text:** retain supported keyboard capture and selected-device capture; a foreign controller cannot bind. Consume the matching release, cancel on connection loss and restore focus/draft state. Typing a remapped Back chord in a text field must not navigate; deliberate Escape retains its documented recovery behavior.

For the same verified radio used for flight and menus, current roll/pitch **center** evidence gates applicable launch/Continue/restart even if the player clicks with the mouse or uses the keyboard. Radio-menu command OFF/rearming separately gates those radio command actions; do not add it as an extra mouse/keyboard resume predicate. Other role combinations follow their existing policy.

**Cases:** C05–C10, C18–C20, C34, C40.

## 4. Preserve family-specific controls

| Context | Required distinction |
| --- | --- |
| Fixed-wing Home Fly / restart | Existing guarded launch/restart may already contain explicit pilot intent and resume when ready. Do not add a second Continue; preserve all owner checks and held-key ordering. Recovery after lost continuity is a separate route. |
| Fixed-wing shaping | Mapping/calibration, selected transmitter-versus-simulator shaping, airplane normal/sport rates, flap mixing and trims keep their order. Preview agrees with the stage it actually displays; it must not claim to show final trim/actuator dynamics if it does not. |
| Helicopter | Collective, arm/hold/cut dominance, trainer/curve and rotor readiness stay with HELI. A generic throttle boolean cannot replace them. |
| Airship | [Activity](../../../app/vehicles/airship/airship_scene.gd) samples armed input before [session resume](../../../app/sim/airship/session.gd). Require low throttle and centered yaw. Default zero arguments are not proof of live readiness. |
| Quad | [Activity](../../../app/vehicles/multirotor/multirotor_scene.gd) owns binding/generation/profile retry/readiness before [session resume](../../../app/sim/multirotor/session.gd). The input frame is pre-expo; FC shaping is separate. Same-source ordinary hold preserves frozen rate throttle; source/focus recovery has its own reset/disarm policy. |
| Quad fallback | Preserve existing automatic replacement selection while held and invalidated arm continuity. Identifying the new source before Continue remains open GCA-G3 acceptance, not a claim about qualified current UI. Selection is not automatic flight resumption. Paused stored motor state and first resumed tick are different observations. |
| Ground | Neutral plus armed, pause holds, damage/course/backend and recording/export conditions remain distinct. |

For configurable bindings, test assignment/validation, persistence or activation, actual dispatch and resulting command/state; add OFF/press/release only where the action uses those semantics. Fixed controls retain their direct route. Test lack of authority from an unselected device and an old generation. An assignment presented as supported for the active activity must have a consumer or be refused/disabled with an explanation. Shared profiles may retain valid bindings for other families; do not delete them merely because this activity cannot use them. Schema acceptance alone cannot establish working Pause.

**Cases:** C10–C12, C15–C19, C24, C33–C34.

## 5. Persistence and numerical input admission

A successful Save acknowledges the published update under the documented storage contract and reports the actual activation result. Managed V2 save/apply retains its transactional rollback. Direct fixed-wing/helicopter legacy calibration can activate in memory before saving and report `NOT saved` if publication fails; preserve and test that distinction rather than promising universal rollback. Managed V2 refuses unreadable stores, and legacy writers must not overwrite unreadable files. The direct legacy reader can return an empty profile for absent or unreadable input; stronger discrimination needs a separately owned repair. Process-level acknowledgement does not prove crash/power-loss durability. A transient managed resolver refusal must not become an inferred unconfigured default.

All five GCA findings have separate baseline and repair obligations. The [original remediation](https://github.com/bultodepapas/OpenRCsimulator/blob/895dd4352c5191f1539a8b8f4df1996cd33eb86f/docs/research/game-controls-audit-2026-11-21/REMEDIATION.md) supplies their detailed scope:

- GCA-03 retries an unresolved **uncached** airship profile at an explicit recovery boundary. Releasing contention alone never resumes. Repeated busy/corrupt/ambiguous results stay held; a late result for changed ownership cannot activate.
- GCA-04 covers legacy calibration read/modify/write, including calibration versus smoke updates. It is separate from the already repaired V2 concurrency issue. Test same/different-device competing writers, old reader/new writer, acknowledged updates, interruption and explicit contention. Atomic rename alone is not a power-loss guarantee.
- GCA-05 requires a justified admitted range contract: declared endpoints produce correct finite commands or activation refuses with a useful field error. Test below/at/above the boundary for absolute and each signed side, offset center, inversion, save/reload and legacy import. Keep files recoverable; ordinary wizard acceptance is not proof for external profiles.

Do not change profile schema, handedness, mapping defaults or calibration meaning inside a structural extraction. Persisted user overrides must survive restart and rollback. Planned keyboard remapping and assistive-device support are not implemented merely because a generic action API exists.

**Cases:** C12–C15, C20–C23.

## 6. Recovery, lifetime and interruption

Preserve all current holds. Removing a menu hold does not clear a controller-loss, calibration, fault or other independent hold. The player must see the remaining reason and an available next action. For a refused airship profile the current workaround is Home → Controls → relaunch; do not promise a Controls button in the airship HUD unless a separately tested change adds it.

For moved scheduling/recovery paths, investigate GCA-G1 with a deterministic clock at the **real first post-gap tick**. Record whether detection precedes any accepted command. A source-only watchdog review is insufficient, and a processing gap is not the same as HID event silence. Any changed hold/recovery policy is an explicit family-owned behavior change. Native sleep, a main-thread engine hang and RF loss require separate evidence; a GDScript timeout cannot prove recovery while the main thread is blocked.

Detach and retire only owned listeners/resources. Temporary detach during replacement is not final disposal: failed or cancelled replacement must respect the existing surviving activity and recorder policy. Observe worker completion without joining a live loader that needs main-thread work. Repeated close/cancel or callback reentry must not double-publish, double-advance, close a new session or erase pending recordings/results.

For fixed-wing transaction migrations, a refused candidate preserves the old accepted flight/writer and publishes nothing; a postcommit observer fault leaves the committed new frame paused with its correct old-flight footer. For airship and quad, record reset/refusal/recording behavior before proposing any stronger guarantee. Treat a new preservation guarantee as a separate repair with an injected failure witness.

**Cases:** C03–C04, C17, C25–C29, C37.

## 7. Evidence and player quality

Every case has an explicit oracle, owner, touched-seam applicability and execution status. Existing suites are starting points. Fakes characterize a layer; at least one affected real owner/consumer chain must prove the migrated interaction. A proposed case or a passing adverse-baseline reproducer is not a repaired pass. Use [quality gates](QUALITY-GATES.md) for identity, checked-runner and replay rules.

Correctness precedes optimization. A cached/shared sample must preserve observation age, event order, generation, invalid sample handling, button release and the first accepted command; it must not insert an unexplained frame queue. Keep global-input capture and radio event evidence independent of sampling reuse.

Physical timing and pilot feel use the existing [F6 procedure](../../plans/controller-support.md#physical-acceptance-procedure). Retain actual OS, device model/firmware, transport, wrapper, package, profile and display/FPS identity; mark unknown metadata unknown. Software timestamps, callbacks and synthetic polling do not measure USB frequency or motion-to-photon latency. Pilot usability, accessibility and physical aircraft handling remain different judgments.

At the player boundary, confirm truthful selected-device/status feedback, recoverable errors, EN/ES labels, keyboard/controller focus and absence of accidental flight commands during setup. Existing usability targets stay with Controls UX/controller owners. No full support claim is made for unavailable devices, arbitrary remaps, OS dialogs or an untested package.

**Cases:** C30–C40. The resulting evidence qualifies only the executed scope.
