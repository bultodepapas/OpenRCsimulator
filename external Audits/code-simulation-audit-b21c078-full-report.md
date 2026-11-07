# OpenRC Simulator code and simulation audit

Five new defects are confirmed by focused runtime witnesses: two CSV recording data-loss paths, controller switches retriggering after Controls transitions, missing circuit contacts in fixed-wing audio, and a frame-dependent false touchdown cue. Three are P2 functional/data-preservation issues; two are P3 presentation issues. No new crash, memory leak, GPU bottleneck, or regression from a previously repaired implementation was established.

The first repair batch should protect recordings and held-controller state. The next simulation batch should address the existing contact-energy, raised-track event, and helicopter-law backlog before further handling calibration. Those physics issues are already documented and are not counted as new discoveries here.

# Reviewed revision and evidence

Repository: [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator). Branch snapshot: **main**, commit **b21c0789649b856217d82faa112c190d34389a21**, authored 2026-11-07 01:08:15 UTC. Audit date: 2026-11-07 UTC. [Reviewed commit](https://github.com/bultodepapas/OpenRCsimulator/commit/b21c0789649b856217d82faa112c190d34389a21).

The review began with [external Audits/CONSOLIDATED-AUDITS.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/external%20Audits/CONSOLIDATED-AUDITS.md), followed by its completed-work ledger and relevant original reports. New candidates were also compared with GitHub issues, merged PRs, PR 8 inline reviews, recent commits, and current-source repairs. No repository source, issues, PRs, or settings were changed. Audit probes and test profiles were separate from the checkout.

This is a repository-wide architectural and integration review with selective deep code tracing and focused execution. It is not a proof of every source line or a physical qualification of every vehicle. Runtime evidence came from the pinned Linux x86-64 engine, headless display and Dummy audio; no physical transmitter, target GPU, native Metal, acoustic listening, or Windows/macOS runtime was exercised locally.

# Actual platform and architecture

| Aspect | Verified implementation |
| --- | --- |
| Application | OpenRC Simulator 0.2.0; startup scene `res://ui/startup.tscn` hands off to the application shell |
| Engine | Official **Godot 4.8-beta2**, exact executable version **4.8.beta2.official.cafc17a19**; installer verifies its pinned SHA-512 |
| Default rendering | Compatibility, `gl_compatibility`; 4× 3D MSAA |
| Apple Silicon | `arm64` selects Mobile/Metal with renderer recovery; Intel/Rosetta retain Compatibility |
| Higher rendering profile | Product High uses Forward+; renderer, reconstruction and platform guards have separate qualification |
| Resolution | Configured viewport 1280×720; project acceptance policy prioritizes 1920×1080, then higher resolutions, then 720p |
| Physics | Custom float64 rigid-body kernel, fixed 240 Hz, RK4; maximum 12 physics catch-up steps per frame; jitter fix 0 |
| Native evaluation | In-house NK-3 C++ aircraft evaluator requested by the application; GDScript reference remains available and is the low-level tool/session default |
| RC cars | Optional native evaluator on Linux/Windows; macOS reference path |
| Exports | Windows x86-64, Linux x86-64 and macOS universal desktop ZIPs; no shipped mobile/web activity |
| Toolchain | Both native locks pin godot-cpp 10.0.0-stable at `507ed9d...`, SCons 4.10.1 and the 4.7 extension API; strict floating-point compiler settings are deliberate |

Sources: [project settings](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/project.godot), [engine getter](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/get-godot.sh), [architecture](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/STACK.md), [export presets](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/export_presets.cfg), [NK-3 lock](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/research/native-kernel/toolchain-lock.json), [RC native lock](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/research/rc-monster-truck/native/toolchain-lock.json).

Each fixed-wing, helicopter and ground session installs one `VehicleModel` into `Simulation`. The kernel owns tick validation, integration, accepted-state publication, checkpoint identity and rollback. Vehicle adapters own their equations, control interpretation and environment preparation. Godot rigid-body nodes do not solve the flight dynamics.

The base state has 13 float64 values. Position is north/east/down, body vectors are forward/right/down, and attitude maps body to NED. Additional motor, battery, fuel, wheel or rotor states are appended in explicitly identified layouts. Rendering consumes detached converted state. Consequently, reducing visual update frequency must not change the physical trajectory or reinterpret the duration of discrete events. The two audio findings expose different violations of that observer boundary. [VehicleModel contract](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/vehicle_model.gd), [kernel](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/simulation.gd), [frame conversion](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/render/frames.gd).

## Vehicle coverage

| Implemented path | Catalog models and reviewed boundaries |
| --- | --- |
| Fixed-wing reference | Ugly Stick; legacy propulsion path, trim, controls, ground contact and trace/session ownership |
| Glow variants | Ugly Stick MAX-61FX, MAX-55AX and FS-64V; two-/four-stroke installation, fuel-feed and event/state boundaries |
| Aerobatic fixed-wing | Extra 300S; finite glow installation, mass/reference-frame and force/moment concerns |
| Warbirds | P-51D Mustang and F4U Corsair; fuel, inertia/CG, flap/gear state, collisions and start/reset integration |
| Turbine | Vantage Jet, internally the Sebart Avanti S/P100-RX installation; turbine/fuel and startup refusal/cleanup |
| Electric | Turbo Lumber Evolution and MoonRunner X99; motor/supply, finite pack versus ideal supply, elevons/flaps and no-gear support |
| Playable helicopter | X-Cell .60 Research Trainer physics with HX-700 visual surrogate; rotor/drive/inflow/skids, controller electronics and reset/checkpoint seams |
| RC ground | Bisonte MT8 electric and MONSTER CAR 2 nitro; body/wheel integration, input arming, brakes, water/damage, service/recovery, checkpoints and recording |
| Research-only rotorcraft | HX-700 electric/body-rate laboratory model and multirotor rotor/powertrain/airframe groundwork; neither is a separate playable catalog activity |

There are ten fixed-wing catalog entries and one playable helicopter entry. Only the original Stik carries the catalog's FLYABLE label; the others are EXPERIMENTAL. That label is a software/product status, not a claim of completed physical validation. Treating the laboratory HX-700 model or multirotor groundwork as shipping aircraft would produce inappropriate recommendations. [Aircraft catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_state/aircraft_catalog.gd#L23-L147), [ground catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/vehicles/ground/vehicle_catalog.gd), [helicopter admission](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/helicopter_flight_session.gd#L259-L267).

## Player flows and shared infrastructure

The traced paths include startup → Home → aircraft/landscape selection → preparation → flight; Pause → Controls/Settings → Continue or guarded Restart; Workshop draft/history/trial/return; recording → save failure/recovery → subsequent actions; and car Garage → neutral arming → drive → service/recover → checkpoint/restore. Shared checks covered statistics ownership, failure-plan setup/restore, companion source admission, weather configuration, audio contact observation, resource retirement and package/backend identity.

Club and Green paradise are separate landscape entries. Direct command-line flight has its own argument resolution and intentionally does not read Home preferences. These are relevant distinctions when reproducing a menu-only state defect. [Architecture and routing](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/STACK.md), [landscape catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/landscapes/catalog.gd).

# Prioritized new findings

P2 means a significant functional or data-preservation failure under the stated conditions. P3 means incorrect presentation with narrower practical impact. All five are new findings relative to the checked audit material; none is labeled a confirmed regression.

| ID | Priority | Finding | Practical impact | Evidence |
| --- | --- | --- | --- | --- |
| N01 | P2 | Automatic CSV names collide within one UTC second | A successfully saved trace is permanently replaced while both saves report success | Both production recorders reproduced |
| N02 | P2 | Starting another recording discards a failed save | Retained unsaved rows disappear without an explicit discard decision | Both production recorders reproduced |
| N03 | P2 | Controls transitions clear held-switch latches | An ON axis sample can request an unintended restart or toggle rates | 16 checked router/UI-component assertions |
| N04 | P3 | Fixed-wing audio omits the RC circuit overlay | Physically loaded wheels are classified as airborne by audio; landing/rolling cues can be suppressed | Production geometry and audio snapshot disagreement |
| N05 | P3 | Deferred audio observation backdates liftoff | A short hop receives an extra touchdown event and starts the debounce | Exact production classifier/cadence witness |

## N01 Automatic CSV trace filenames overwrite prior saves

**Locations.** `Recorder.stop()`, [recorder.gd:35–43](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/recorder.gd#L35-L43); helicopter `stop()`, [rotorcraft_recorder.gd:65–79](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/rotorcraft_recorder.gd#L65-L79); file writes in [trace.gd:1693–1706](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/trace.gd#L1693-L1706) and [rotorcraft_recorder.gd:25–32](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/rotorcraft_recorder.gd#L25-L32). The manual T handlers are [main.gd:2092–2096](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/main.gd#L2092-L2096) and [helicopter_main.gd:515–517](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/helicopter_main.gd#L515-L517).

The default filenames use `Time.get_datetime_string_from_system(true)`, whose string has whole-second precision. Both writers open the resulting path with `FileAccess.WRITE`. Godot defines this mode to clear an existing file before writing; the exact pinned engine's [FileAccess.xml:653–655](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/FileAccess.xml#L653-L655) confirms the behavior. [Official Time documentation](https://docs.godotengine.org/en/latest/classes/class_time.html#class-time-method-get-datetime-string-from-system).

**Reproduction.** Stop one manual recording, then start and stop another before the UTC second changes. Two successful default `stop()` calls produce the same path. In the compact synthetic fixture:

| Recorder | First successful file | After the second successful save |
| --- | --- | --- |
| Fixed-wing | 121 rows, 48,744 bytes | 1 row, 696 bytes; same path, different SHA-256 |
| Helicopter | 121 rows, 26,065 bytes | 1 row, 712 bytes; same path, different SHA-256 |

Both calls returned OK. A longer trace could also be at risk if both default paths are generated in the same second; no long flight was tested. A system clock returning to an already-used timestamp is another source-derived collision condition. The existing failed-save flow cannot intervene because the overwrite reports success. This concerns manual CSV telemetry, not the separate F10 `.orfl` recording format.

**Correction.** Centralize automatic save-path allocation. Use a unique session/generation identifier plus a no-clobber reservation/publication protocol, then stage, flush and publish the complete content without replacing an existing automatic save. More timestamp digits alone are not a complete cross-process policy; neither is an unprotected `exists()` followed by WRITE. Keep any deliberate explicit-path/CLI overwrite behavior separate.

**Verification.** Inject a fixed clock and force two stops to request the same stem. Assert distinct saved paths, complete expected content, unchanged prior hashes and truthful return codes. Repeat for both recorders, pre-existing files, clock rollback, publication failure and concurrent writers. Exercise the real T-key route after the component test.

## N02 A new recording erases the retained failed generation

**Locations.** Fixed-wing `start()` clears the trace at [recorder.gd:24–32](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/recorder.gd#L24-L32), while `stop()` first makes `recording=false`. Helicopter has the same ownership pattern at [rotorcraft_recorder.gd:57–79](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/rotorcraft_recorder.gd#L57-L79). The normal T handlers decide start versus stop using only `recording`. Recovery identifies pending work by recorder generation and prunes stale entries at [trace_recovery.gd:130–135](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/ui/trace_recovery.gd#L130-L135).

**Reproduction.** Let a recording save fail; the probe placed a regular file at `user://traces` in an isolated profile so directory creation failed. Each recorder returned error 12, retained 121 rows and became stopped. The next `start()` incremented the generation and left only the new initial row. No discard API was called.

The keyboard source takes precisely that start branch after a failed stop. The longer exit failure → Stay → Resume → T sequence is source-traced, not a separately executed dialog test. The error itself is shown in the recorder note; the defect is the subsequent destructive transition. The trial-return recovery promise explicitly preserves data for Retry or Discard, but that ownership does not guard `start()`. [Trial-return contract](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/plans/aircraft-editor.md#L418), [recovery state](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/ui/trace_recovery.gd#L23-L54).

This is distinct from N01: N01 destroys an already saved file after reported success; N02 destroys the sole retained in-memory generation after a reported failure. It also differs from the repaired departure-coordinator work. The existing generation test protects against stale decisions after a generation changes; it does not establish consent to destroy the previous rows.

**Correction.** Give the recorder explicit saved/unsaved generation state. Reject or defer a new start until the previous unsaved generation is saved or explicitly discarded, or retain multiple independent immutable generations. Route the decision through the shared recovery flow. Preserve generation guards for delayed callbacks; do not derive ownership from a human-readable note.

**Verification.** For fixed-wing and helicopter, test save failure → new T; exit failure → Stay → Resume → new T; repeated save failures; retry success; explicit discard; and stale callbacks after a new accepted generation. Compare the old row bytes throughout. Failure, dismissal or unrelated menu activity must not authorize clearing them.

## N03 Controls transitions rearm a switch that never returned OFF

**Locations.** [app_root.gd:1566–1599](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L1566-L1599), [1657–1671](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L1657-L1671), and [1765–1800](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L1765-L1800). Successful profile save emits the callback from [controller_setup.gd:2401–2444](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/ui/controller_setup.gd#L2401-L2444). Restart follows the normal guarded transaction at [app_root.gd:2963–2974](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L2963-L2974).

The restart and rate routers deliberately observe the flight device while another device navigates menus. This prevents a held switch from firing when flying resumes. However, `open_controls()` calls `_clear_controller_actions(false)`: false preserves rates but the helper still unconditionally clears restart edges. A successful Controls Save calls `_controller_ui_changed()`, which clears both.

**Reproduction.** Use a mapped analog switch with threshold 0.65 and a separate menu pad. While paused, observe 0.80 ON. Open Controls, close Controls and Pause, then deliver 0.81 while the switch remains ON. The empty restart latch turns that sample into a new request. Separately, observe the rate switch ON under Controls, save an unchanged valid profile, close menus, then deliver another ON sample: the rate action toggles.

The checked test used real AppRoot routing, ScreenStack and ControllerSetup with synthetic devices, mocked successful persistence and a fake flight that counted dispatched actions. Sixteen assertions passed with zero engine errors/warnings. Ordinary Pause-only handling suppressed the same held sample; OFF → ON triggered exactly once.

The timing condition matters: a sample received while Controls remains open can repopulate the latch. A motionless device that emits no new event does not trigger this witness. The restart request can lead to a reset when the normal departure guards succeed; the test did not complete a physical reset. Rate changes apply to a configured joystick/gamepad and a rate-capable aircraft; radio profiles intentionally use transmitter rates. [Rate consumer](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/flight_session.gd#L3905-L3917).

**Correction.** Preserve edge history when the flight device and relevant binding are unchanged. When binding, device identity or connection generation changes, enter an explicit require-OFF state before arming the new assignment. Do not simply retain stale mappings or clear every latch on any UI update.

**Verification.** Extend the controller test around Save and Cancel, both actions, positive/negative axes, unchanged/changed mappings, separate flight/menu devices, disconnect/reconnect, and focus changes. Shift the final ON event before and after menu closure. Verify the real guarded restart path with and without a pending recording. Existing nested-Controls rate tests do not exercise Save or restart-latch clearing. [Existing test](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/tests/test_controller_rates.gd#L185-L204).

## N04 Audio reconstructs contact against a different ground surface

**Locations.** [ground_audio_model.gd:39–95](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio_model.gd#L39-L95) and its far-ground shortcut at [126–143](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio_model.gd#L126-L143). Physics receives the circuit through [flight_session.gd:4416–4425](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/flight_session.gd#L4416-L4425). Production enabling is at [main.gd:702–704](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/main.gd#L702-L704) and [rc_track_option.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/scenery/rc_track_option.gd).

The audio adapter supplies field and lake to `Ground.evaluate`, `Wheels.frame` and legacy `Ground.loads`, but omits the circuit overlay. Its height bound omits it too. The physical and audio systems therefore evaluate different support surfaces for the same body pose.

**Reproduction.** The production route is a non-scripted Club-field fixed-wing flight with the circuit enabled. The option is explicitly ON or resolves ON from Auto with the qualifying dedicated-GPU/detail configuration; it is not universally on. The component fixture disabled simulation processing and directly assigned the stock Stik tabletop pose at NED `[39, -4, -0.755]`; it did not obtain this pose by flying or stepping the integrator:

| Quantity | Physical composed geometry | Audio observation |
| --- | --- | --- |
| Circuit height | Approximately 0.51444 m | Omitted |
| Wheel compression | 0.011918, 0.012819, 0.014576 m | Approximately −0.50 m |
| Normal loads | 6.674, 7.178, 6.414 N | 0, 0, 0 N |

Removing the track makes that elevated pose genuinely clear of the field; lowering to flat terrain restores loaded audio rows. This establishes the geometry mismatch. The staged pose is not claimed to be static equilibrium or a completed landing. Because rolling and impact logic require loaded/grounded rows, cues can be suppressed during real circuit contact. [Audio consumption](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio.gd#L282-L323).

**Correction.** Pass the same validated circuit context to all audio contact queries and their conservative observation bound. Prefer one explicit composed-support contract for physics and read-only observers. Do not substitute `last_loads` indiscriminately: an integrator-stage force and an accepted-endpoint contact snapshot need not represent the same instant.

**Verification.** Tabletop, ramp, edge, off-track field, circuit disabled, lake combinations, restart/rewind and actual approach/landing histories. Assert both geometry identity and audio event behavior. Reuse the prior A6 F3 geometry as a regression fixture while adding this different consumer.

**Related optional improvement.** The environment intentionally falls back to unsupported material geometry whenever an overlay exists, even outside its coverage. A checked off-track runway sample selected hard audio with the circuit and grass without it despite identical loaded forces. Resolve unambiguously off-track field materials only after validating the coverage rule; retain explicit fallback where circuit material support is unqualified. This deliberate conservative policy is not a sixth defect.

## N05 Frame cadence counts grounded time as airborne

**Locations.** Observation scheduling at [flight_audio.gd:146–159](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/flight_audio.gd#L146-L159), accumulated interval at [ground_audio.gd:68–105](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio.gd#L68-L105), classifier at [ground_audio_motion.gd:6–47](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio_motion.gd#L6-L47).

When the last observation has all wheels grounded, the presentation cadence may defer the next contact observation. If its next endpoint is airborne, the classifier credits the entire skipped interval as airborne. Later near-ground observations become per-tick, but the initial overcount remains.

**Reproduction and math.** At 240 Hz, keep a synthetic near-ground wheel grounded through ticks 0–3, airborne on 4–34, and loaded at 35 with sufficient approach speed. With per-tick observation, airborne time is 31/240 = 0.12917 seconds, below the 0.14-second cue threshold. With one observation per four-tick render frame, the first unloaded observation credits four ticks rather than one. Total credited time becomes 34/240 = 0.14167 seconds, crossing the threshold.

The production GroundAudio, Motion and Cadence classes queue zero impact events under per-tick observation and one under default frame cadence. A longer hop queues one under both policies. The driver supplies synthetic near-ground gating; it is not a full FlightAudio flight or an acoustic recording. The extra event also starts the 0.65-second debounce, which can hide a subsequent legitimate cue.

**Correction.** Preserve the first unloaded tick using a qualified per-tick transition observation, or explicitly handle an uncertain transition conservatively. Render scheduling may consume the event later; it must not invent its start time. A shorter deferral interval reduces error but does not make the onset exact.

**Verification.** Shift hops just below and above 0.14 seconds across render phases at 30/60/144 FPS and cadence settings 0–4. Check stationary ground, sustained flight, normal touchdown, pause/resume and reset. With a per-tick transition receipt, assert exact parity with the tick oracle. With a deliberately uncertain onset, assert correct bounds and the declared conservative cue policy, including false-positive and missed-cue tradeoffs. Keep these decisions outside physical integration.

# Cross-check against previous audits

The following work remains separate from the five new findings.

| Earlier item | Current disposition and practical consequence |
| --- | --- |
| A6 F6 coupled tire/brake dissipation | Still pending in the consolidated ledger. Force magnitude limits alone do not prevent the coupled solver from doing positive work. Correctness gate before handling calibration. |
| A12 CF-05 raised-track first contact | Still pending: clear interval endpoints can hide an interior crossing. More root bisection cannot repair a candidate never admitted. |
| A12 CF-06 and E300-01/CF-01 moment conventions | Existing flap-flow projection and CG/reference-point issues. Resolve the equations before tuning pitch or yaw damping. |
| A15 H01 grounded helicopter yaw | Source still suppresses the integral while allowing manual heading reference to advance; consistent with the prior finding. |
| A15 H02/A20 low-RPM rotor law | Existing blend/domain gap remains an acceptance issue; no new startup/pole reproduction was claimed here. |
| A22 WNEW-02 native turbulence restore | Current preparation still reads the old live auxiliary index before the restored index is committed. Native continuation remains a dedicated verification requirement. |
| A22 WNEW-03/WNEW-04 | Existing tail-wake and pure-sideflow discontinuities; prior standalone results are not automatically full-session upset evidence. |
| A11/A13/A14/A17/A21 menu and persistence backlog | Existing lighting ownership, display rollback, draft/navigation, error-visibility and trial issues remain listed; not rediscovered as new. |
| A24 and RCV-41 performance observations | Repeated contact/statistics work, source identity checks and shader opportunities are already documented. Historical measurements were not presented as measurements of this audit. |
| A6 F1/F4/A4 | Current source contains the glow multi-substep refusal, next-representable reserve handling and committed firing-counter logic. These were not relabeled as open discoveries. |
| A6 F3 statistics on composed terrain | Delivered fix applies to statistics; N04 is a separate audio consumer still omitting that terrain. |
| A14 F14/UI2 departure coordination | Delivered work remains present. N02 is the subsequent new-recording transition, not a claim that the whole departure repair regressed. |
| Earlier companion-admission mismatch | Not current at this snapshot: the production identity helper matches all 174 sources to the current qualified fingerprint. |
| GitHub issues 3 and 5 | Historical controller field-validation/Home calibration complaints are not current source proof; current code implements the corresponding routes. |

Primary cross-reference: [consolidated ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/external%20Audits/CONSOLIDATED-AUDITS.md), [completed work](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/external%20Audits/COMPLETED-AUDIT-WORK.md), [PR 8 reviews](https://github.com/bultodepapas/OpenRCsimulator/pull/8/files), [issue 3](https://github.com/bultodepapas/OpenRCsimulator/issues/3), [issue 5](https://github.com/bultodepapas/OpenRCsimulator/issues/5).

Recent history was relevant to interpretation. The companion qualification refresh postdates the earlier failed-admission observation. PR 7's control-surface integration did not mean all proposed aerodynamic laws or retuned goldens from PR 1 were adopted. The reviewed head adds stricter native CI evidence requirements; it does not itself certify every runtime platform. [PR 7](https://github.com/bultodepapas/OpenRCsimulator/pull/7), [head commit](https://github.com/bultodepapas/OpenRCsimulator/commit/b21c0789649b856217d82faa112c190d34389a21).

## Issues requiring further verification

The explicit `gdscript_reference` helicopter reset path emits `resetting` and clears flyable readiness before candidate validation can refuse. Its production observer stops recording. The native-request path has a rollback wrapper, including when it falls back to reference. This asymmetry merits an injected-refusal test, but no ordinary supported stock restart that reaches the failing boundary was identified. It is not a sixth confirmed player bug. [Reset paths](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/helicopter_flight_session.gd#L405-L519), [observer](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/helicopter_main.gd#L310-L314).

The raw RK-stage quaternion passed to helicopter Euler-heading electronics can move the familiar vertical-attitude heading flip slightly before the physical vertical crossing. Physical rotations use a normalized attitude. This refines the already documented HELI-15b limitation rather than establishing a new defect or flown upset. Correcting normalization alone would not remove Euler heading's vertical singularity. [Flight dynamics](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/physics/rotorcraft/flight_dynamics.gd#L149-L169), [electronics](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/physics/rotorcraft/electronics.gd#L158-L160), [existing limitation](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/plans/helicopter.md#L810).

# Mathematical and performance improvement strategy

## Preserve physical invariants

For each modeled nonelastic tire and brake without an explicit energy store, enforce its own passivity inequality:

```math
\mathbf F_{t,i}\cdot\mathbf s_i\leq0,\qquad Q_{b,i}\omega_{\mathrm{rel},i}\leq0.
```

Here `s_i` is actual contact slip including body, suspension and wheel motion; `Q_b,i` is signed brake torque on the wheel; and `omega_rel,i` is wheel spin relative to the body. A nonpositive total power sum is a useful diagnostic but can hide positive work in one tire behind another tire or brake. Preserve static zero-slip and zero-relative-spin reactions. If a physical energy store is introduced, include its energy change explicitly.

A6 F6 requires a coupled dissipative solution while retaining those local passivity conditions, static reactions and force limits. An impulse or constrained optimization formulation can enforce the principle, but its feasibility, cost, load-loss/reversal behavior and backend parity must be tested. Do not repair a bad coupled solution by clipping unrelated scalar components and assume the energy inequality follows.

For events, equal-sign endpoints do not prove there is no crossing between them. CF-05 needs conservative interval admission and the earliest supported event, followed by accurate root localization. Increasing global tick frequency or iteration count is not a substitute for an interval that was skipped entirely.

For aerodynamic moment repairs, write down the origin explicitly: translating a resultant from point A to B adds the arm cross force with the correct sign. Keep free section couples separate. For moving fuel mass, preserve the existing fixed-datum/body and mass-inventory ownership rather than injecting a second CG correction in the rendering or session layer.

For discontinuities, preserve each previous witness and sweep both sides of the boundary. Use 240/480/960 Hz comparisons for selected crossing cases, accepted-session continuation and native/reference agreement. A finite output is not by itself a physically valid output. Any deliberate law change needs explicit compatibility/version treatment and reviewed baseline changes.

## CPU and memory

There was no target-host timing campaign, so this report makes no new milliseconds-per-frame or FPS improvement claim. The checked test durations are harness wall time, not physics benchmarks.

At 240 Hz, each outer tick has 1/240 = 4.1667 ms of real time. A 60 FPS frame normally contains four ticks. The project's 500 microsecond physics target is an acceptance budget, not a guarantee; twelve catch-up steps imply simulation slowdown below approximately 20 rendered FPS. That behavior is documented and should not be mistaken for a newly found hang. [Timing settings](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/project.godot#L47-L56), [budget policy](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/STACK.md).

The highest-value CPU investigation is at duplicated boundary work: source/backend identity checks, endpoint contact diagnostics reused by observers, and settings/environment preparation. RCV-41 already documents per-tick identity I/O and bounded caching; A24 already documents observer work discarded after restore. Establish current p50/p95/p99 costs on the actual backend before modifying those guards. Preserve invalidation identity and fault/rollback behavior.

A useful design direction is one immutable, accepted-tick contact observation carrying tick, environment identity, geometry identity and load/transition data. Statistics and audio could consume it consistently. Construction must remain read-only and endpoint-correct; a cached stage evaluation is not automatically equivalent. N04 and N05 provide correctness tests for that refactoring before performance claims.

Car control-tape growth is deliberate exact-replay history, not automatically a leak. Memory tests should separate bounded caches, intentionally retained history and objects that should be released. Eight repeated environment retirement cycles and startup cleanup passed in the headless checks; these do not measure native radiance-texture or GPU memory.

## GPU and loading

No new GPU bottleneck was established. Do not reduce shadows, trees, transparency, lake quality or reconstruction quality on the basis of shader length or draw-call intuition alone. Use the existing debug bridge to capture CPU/GPU attribution on a target display at actual 1080p pixels, then above 1080p, with fixed aircraft, landscape, weather, camera, renderer and reconstruction.

Run one-variable ablations for geometry/draw submission, shadows, transparent overdraw, reflection passes and post-processing. Measure cold launch separately from steady flight and repeat transitions to expose resource growth. Preserve the readability and landing cues that matter for RC training. Native Metal/MetalFX, Forward+ and Compatibility must be qualified separately; headless Dummy results establish none of them. [Graphics tools](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/tools/graphics.md), [debug bridge](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/tools/debug/README.md).

# Executed verification

All final listed receipts passed the checked runner. It inspects engine/script errors as well as exit status and retains raw logs.

| Check | Observed result | Limit |
| --- | --- | --- |
| Full app resource import | Complete, no checked errors; eight OBJ/PBR ambient warnings | Import success, not rendered acceptance |
| RC vehicle session | 162 checks, 0 failed | Native backend-switch subcheck explicitly skipped because native library was not staged |
| RC nitro session | 28 checks, 0 failed | Local reference path |
| World environment lifetime | 34 checks, 0 failed across eight retirement cycles | Headless ownership/signals; no native GPU memory claim |
| Main startup cleanup | 29 checks, 0 failed | Headless valid/refused startup and Home rollback; native request fell back to reference |
| Controller latch witness | 16 checks, 0 failed | Real router/Controls, synthetic devices, stub flight/persistence |
| Recorder-loss witness | Both collision cases and both failed-save replacement cases reproduced | Production recorders with synthetic simulation signals |
| Track audio witness | Loaded physical contacts versus zero audio force reproduced; controls passed | Staged geometry; no flown landing/listening |
| Cadence audio witness | Short-hop mismatch and longer-hop control reproduced | Production classes with synthetic contact sequence |
| Companion identity helper | Current profile matches 174 source files | Identity match, not a fleet flight |

An initial startup cleanup attempt lacked authoring files omitted by the sparse checkout. Fetching the exact pinned files made the test pass; the incomplete-checkout failure is excluded from findings. Early isolated audio copies similarly lacked preload assets; only completed checked receipts support the audio findings.

At **2026-11-07 01:53:04 UTC**, all eight unit shards, both RC native production jobs, native build jobs, NK-3 Linux qualification, release builds and supporting jobs had passed: **17 of 19 checks successful**, with integration and visual jobs still running. These are observed hosted CI statuses, not locally rerun native results. [Same-commit workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42322395902).

# Practical implementation plan

| Order | Work | Exit criteria |
| --- | --- | --- |
| 1 | Protect both manual recorders and centralize automatic path allocation | N01/N02 witnesses become preservation tests; two saves cannot clobber, failed generations survive until saved/discarded; real T and exit/Stay paths pass |
| 2 | Repair controller latch continuity | Unchanged ON inputs never trigger after Controls/Save; changed bindings require OFF before ON; real guarded restart/rate tests pass |
| 3 | Close the existing simulation correctness gates | Coupled contact energy, raised-track first contact, moment origins/projections, helicopter domains and native weather restore each have accepted-session evidence and reviewed law/version treatment |
| 4 | Align audio with physical geometry and accepted transition timing | N04/N05 witnesses pass for track/lake combinations and frame phases; native listening confirms cue behavior |
| 5 | Measure and optimize current hot paths | Same workload/backend/environment before/after, p50/p95/p99 plus allocations/RSS, exact replay/rollback preserved; no unsupported FPS claim |
| 6 | Complete desktop qualification | Same-commit CI completes; packaged Windows/Linux/macOS smoke, physical controllers, target 1080p renderers, repeated session transitions and export-source identity verified |

The repair sequence should be implemented as small changes with independently retained witnesses. Avoid combining aerodynamic retuning, engine upgrades, renderer changes and persistence fixes into one baseline update. The five new findings are actionable now; the existing mathematical backlog deserves dedicated correction and qualification rather than being counted again as fresh audit output.
