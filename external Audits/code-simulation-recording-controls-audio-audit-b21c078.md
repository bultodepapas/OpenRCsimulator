## Audit result

I audited **`main` at commit `b21c0789649b856217d82faa112c190d34389a21`** and found **five new defects supported by focused runtime reproductions**:

- Two ways to lose manual CSV recordings.
- Held controller switches becoming eligible to trigger again after Controls-menu transitions.
- Fixed-wing audio evaluating ground contact without the enabled RC circuit.
- Deferred audio observation incorrectly extending airborne time and generating a false touchdown cue.

The first three deserve the earliest fixes. The two audio defects have narrower presentation impact. **I did not establish a new crash, memory leak, GPU bottleneck, or confirmed regression from a previously repaired implementation.**

I read [`external Audits/CONSOLIDATED-AUDITS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/external%20Audits/CONSOLIDATED-AUDITS.md) before reviewing the implementation, then cross-checked candidates against the completed-work ledger, relevant original audits, GitHub issues, PR reviews, and recent history. The existing mathematical and performance backlog remains important, but I have kept it separate from new discoveries.

### Deliverables

- [**Complete audit report**](https://chatgpt.com/space/page_a837fc1e69288191af414d4270f9b32e) — detailed findings, source locations, coverage, mathematical analysis, and implementation plan.
- [**OpenRC_Audit_Evidence_b21c078.zip**](https://chatgpt.com/library?file_id=libfile_fde3_f-3188360a88fc8191addf8ece3903fea9_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) — four reproduction scripts, original checked-runner logs and receipts, source/engine identities, hashes, and reproduction instructions.

The report text was read back and verified; its Page layout was not visually previewed. **No repository source was changed.**

---

## 1. Prioritized new findings

Here, **P2** means a significant functional or data-preservation failure under the stated conditions. **P3** means incorrect presentation with narrower practical impact.

| ID | Priority | New finding | Practical impact | Evidence |
|---|---|---|---|---|
| **N01** | **P2** | Automatic CSV filenames collide within one UTC second | A successfully saved trace is overwritten while both saves report success | Reproduced with both production recorders |
| **N02** | **P2** | Starting another recording clears a failed save’s retained data | Unsaved flight rows disappear without an explicit discard decision | Reproduced with both production recorders |
| **N03** | **P2** | Controls transitions erase held-switch latches | A still-ON axis can request an unintended restart or change control rates | 16 checked production-router/UI-component assertions |
| **N04** | **P3** | Fixed-wing audio omits circuit terrain | Physically loaded wheels are reported airborne to audio, suppressing contact cues | Physical and audio contact results disagree in a controlled pose |
| **N05** | **P3** | Audio cadence credits time before liftoff | A short hop generates an extra touchdown event and starts its debounce | Production cadence/classifier witness with a longer-hop control |

**“New” means absent from the prior material checked—not necessarily introduced by the latest commit.** None of these is classified as a confirmed regression.

## 2. Actual engine, platforms, and architecture

The project is more specialized than a conventional Godot physics game. Recommendations must respect its custom simulation and replay contracts.

| Area | Verified configuration |
|---|---|
| Application | OpenRC Simulator **0.2.0** |
| Engine | Official **Godot 4.8-beta2**, exact executable version **`4.8.beta2.official.cafc17a19`** |
| Default renderer | **Compatibility / `gl_compatibility`**, with **4× 3D MSAA** |
| Apple Silicon | `arm64` selects **Mobile/Metal**, with renderer recovery; Intel/Rosetta retain Compatibility |
| Higher graphics profile | Product High uses **Forward+** |
| Simulation | Custom **float64**, fixed **240 Hz**, RK4; maximum **12 catch-up ticks per frame** |
| Flight backend | Application requests the in-house **NK-3 C++ evaluator**; reference GDScript remains available |
| RC-car backend | Optional native evaluator on Linux/Windows; macOS uses the reference path |
| Shipping platforms | Windows x86-64, Linux x86-64, macOS universal desktop ZIPs |
| Display priorities | 1080p is the project’s primary acceptance target; the configured default viewport is 1280×720 |

These are grounded in the pinned [project settings](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/project.godot), [engine getter](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/get-godot.sh), [architecture](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/STACK.md), and [export presets](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/export_presets.cfg).

Each vehicle session installs a `VehicleModel` into the shared `Simulation` kernel. The kernel owns tick validation, integration, accepted-state publication, checkpoints, and rollback. Vehicle adapters own equations, controls, and environmental preparation. **Godot rigid-body nodes do not solve the flight dynamics.**

The base rigid-body state has 13 float64 values, with NED world coordinates, FRD body coordinates, and a quaternion mapping body to NED. Additional fuel, motor, battery, wheel, and rotor states extend that layout. Rendering consumes detached converted state. This separation is valuable, but it requires every observer to preserve the geometry and timing meaning of the state it consumes. [Kernel and contracts](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/vehicle_model.gd).

### Vehicle coverage

The reviewed catalog contains **ten fixed-wing entries and one playable helicopter entry**:

| Family | Models and boundaries reviewed |
|---|---|
| Reference trainer | Ugly Stick: propulsion, trim, controls, contact, session and trace ownership |
| Glow trainers | MAX-61FX, MAX-55AX, FS-64V variants: installation, fuel-feed and event/state boundaries |
| Aerobatic aircraft | Extra 300S: finite glow installation, mass properties and moment conventions |
| Warbirds | P-51D and Corsair: fuel, flaps, retracts, collisions, starts and resets |
| Turbine | Vantage Jet / Avanti S: turbine/fuel and startup refusal/cleanup |
| Electric | Turbo Lumber and MoonRunner X99: motor/supply, finite battery, control mixing and gear/no-gear paths |
| Helicopter | X-Cell reference physics with HX-700 visual surrogate: rotor, drive, inflow, skids, electronics and reset/checkpoint seams |
| RC ground | Bisonte MT8 electric and MONSTER CAR 2 nitro: arming, tires/brakes, water/damage, service, recovery, checkpoints and recording |
| Research groundwork | Laboratory HX-700 model and multirotor components; neither is a separate playable catalog activity |

Only the original Stik has the catalog’s `FLYABLE` label; the other aircraft are `EXPERIMENTAL`. Those labels do not imply completed physical calibration. [Aircraft catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_state/aircraft_catalog.gd#L23-L147), [ground catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/vehicles/ground/vehicle_catalog.gd).

## 3. New findings in detail

### N01 — Automatic trace filenames can overwrite a successful save

**Priority: P2. Applies to fixed-wing and helicopter manual CSV recording.**

**Affected code**

- `Recorder.stop()` in [`app/sim/recorder.gd:35–43`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/recorder.gd#L35-L43).
- Helicopter `stop()` in [`app/sim/rotorcraft_recorder.gd:65–79`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/rotorcraft_recorder.gd#L65-L79).
- The writers in [`trace.gd:1693–1706`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/trace.gd#L1693-L1706) and [`rotorcraft_recorder.gd:25–32`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/rotorcraft_recorder.gd#L25-L32).

The default filename is derived from `Time.get_datetime_string_from_system(true)`. That string has whole-second precision. The resulting file is opened with `FileAccess.WRITE`, which truncates an existing file. Official Godot documentation confirms both semantics; the pinned engine source agrees. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_time.html?utm_source=chatgpt.com)

**Reproduction**

Stop a recording, then quickly start and stop another before the filename’s UTC second changes. Both saves select the same path.

The production-recorder witness produced:

| Recorder | First successful save | After second successful save |
|---|---:|---:|
| Fixed-wing | 121 rows, 48,744 bytes | 1 row, 696 bytes |
| Helicopter | 121 rows, 26,065 bytes | 1 row, 712 bytes |

In each case, the path was identical, the file hash changed, and **both calls returned success**.

The 121 rows came from a synthetic simulation fixture. A longer recording could also be lost if both default paths are generated in the same second; no long flight was tested. The manual T handlers follow this recorder sequence. This concerns CSV telemetry, not the separate `.orfl` format.

**Correction**

Centralize automatic filename allocation and use a **no-clobber save protocol**:

1. Reserve a unique destination using a session/generation identity.
2. Write and flush a complete staged file.
3. Publish it without replacing an existing automatic save.
4. Retain the trace and report failure if publication fails.

Adding milliseconds alone does not establish a complete collision policy. An unprotected `exists()` check followed by WRITE also leaves a race. Preserve intentional explicit-path/CLI overwrite behavior separately.

**Regression verification**

Force equal timestamps and existing destinations. Assert distinct output paths, complete content, unchanged prior hashes, and truthful return codes. Cover both recorders, clock rollback, publication failure, concurrent writers, and the actual T-key flow.

### N02 — Starting a new recording destroys a failed save’s retained rows

**Priority: P2. Applies to both manual recorders.**

The fixed-wing [`start()`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/recorder.gd#L24-L32) increments the generation and immediately calls `trace.clear()`. The [helicopter implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/rotorcraft_recorder.gd#L57-L79) behaves similarly.

Meanwhile, `stop()` sets `recording=false` before attempting the save. The normal T handler chooses start or stop using that flag.

**Reproduction**

The test placed a regular file at `user://traces` inside an isolated profile, causing the production default save path to fail:

- `stop()` returned error 12.
- The recorder stopped but retained **121 rows**.
- The next `start()` advanced the generation and left **one new initial row**.
- No discard operation was called.

The save error itself is exposed in the recorder note. The defect is the subsequent destructive transition.

The longer route—exit save failure → Stay → Resume → T—is supported by the call chain, but I did not execute that complete dialog sequence. Recovery tracks the current generation and removes stale pending entries, so it cannot recover data already cleared by `start()`. [`trace_recovery.gd:130–135`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/ui/trace_recovery.gd#L130-L135).

**Why this is separate from prior work**

The previous departure-coordinator repairs govern leaving a flight and handling pending decisions. This finding concerns **starting another recording afterward**. The existing generation test checks stale-decision isolation after replacement; it does not establish consent to destroy the preceding unsaved generation.

It is also independent of N01: one overwrites a saved file after success; the other clears unsaved memory after failure.

**Correction**

Represent recording ownership explicitly—for example, idle, recording, saved, and unsaved/failed generation states.

A new start should either:

- Wait for successful save or explicit discard of the old generation; or
- Preserve the old generation independently while recording another.

Reuse the shared recovery flow and retain stale-callback generation guards. Do not infer ownership from a human-readable status string.

**Regression verification**

Test both aircraft paths through failure → T and exit failure → Stay → Resume → T. Compare old row bytes through repeated failures, retry, dismissal, explicit discard, restart, and delayed callbacks. Only successful persistence or explicit discard should release the old generation.

### N03 — Controls transitions allow a held switch to trigger again

**Priority: P2. Potential unintended restart request or rate change.**

The routers deliberately observe the flight controller while another device operates menus. Their comments explicitly require an OFF transition before a held switch may trigger again.

However:

- [`open_controls()`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L1566-L1599) calls `_clear_controller_actions(false)`.
- The helper [always clears restart edges](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L1657-L1671), despite preserving rate edges when passed `false`.
- Successful Controls Save calls `_controller_ui_changed()`, clearing **both** latches.

**Reproduction**

Use a mapped analog switch with threshold `0.65` and a separate menu pad:

1. While paused, observe the flight switch at `0.80`.
2. Open Controls.
3. Close Controls and Pause.
4. Receive `0.81` while the switch remains ON.

The restart router sees an empty previous latch and issues a new restart request.

For rates, observe ON under Controls, save an unchanged valid profile, close menus, then receive another ON sample. The rate action toggles.

The test exercised real AppRoot routing, ScreenStack and ControllerSetup, with synthetic devices, mocked persistence, and a stub flight. **Sixteen assertions passed.** An ordinary Pause-only control preserved the latch; a genuine OFF → ON transition triggered once. [Router implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/app_root.gd#L1765-L1800).

**Conditions and impact**

A fresh above-threshold event must arrive **after** menus close. An event while Controls remains open can repopulate the latch. A device that emits no further event does not trigger this witness.

The test counted restart requests, not a completed physical reset. Production routes the request through its recording-aware restart transaction, which can reset the flight when its guards succeed. Rate changes apply to configured joystick/gamepad profiles and rate-capable aircraft; radio profiles use transmitter rates.

**Correction**

Preserve latch history for unchanged flight-device bindings. When a binding, device identity, or connection generation changes, require a fresh OFF observation before arming the new assignment. Blindly retaining stale mappings would be an incomplete fix.

**Regression verification**

Cover Save and Cancel, unchanged and changed mappings, positive/negative axes, separate flight/menu devices, reconnects, focus changes, and event timing around menu closure. Verify both the rate consumer and the real guarded restart path.

### N04 — Fixed-wing audio evaluates contact without the RC circuit

**Priority: P3. Contact feedback disagrees with physical support.**

[`ground_audio_model.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio_model.gd#L39-L95) calls `Ground.evaluate`, `Wheels.frame`, and fallback `Ground.loads` with field and lake context, but omits the circuit overlay. Its [far-ground shortcut](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio_model.gd#L126-L143) also omits circuit height.

The physical session does pass the circuit to contact evaluation.

**Production conditions**

A non-scripted Club-field fixed-wing flight with the circuit enabled. This can be explicit ON, or Auto resolving ON under the qualifying dedicated-GPU/detail configuration. It is not universally enabled by default. [Option resolution](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/scenery/rc_track_option.gd).

**Reproduction**

The component fixture disabled simulation processing and directly assigned the stock Stik tabletop pose at NED `[39, -4, -0.755]`:

| Quantity | Physical composed geometry | Audio observation |
|---|---:|---:|
| Circuit height | Approximately 0.51444 m | Omitted |
| Wheel compression | 0.011918, 0.012819, 0.014576 m | Approximately −0.50 m |
| Normal loads | 6.674, 7.178, 6.414 N | 0, 0, 0 N |

Removing the circuit made the elevated pose legitimately unloaded; lowering it to flat terrain restored loaded audio observations.

This is a controlled geometry comparison, not a flown landing or equilibrium claim. Since rolling and touchdown cues require loaded/grounded observations, the discrepancy can suppress them.

**Correction**

Pass the same validated circuit context through every audio contact query and the conservative observation bound. Keep geometry resolution separate from material fallback policy.

Do not indiscriminately reuse `last_loads`: an RK stage force and an accepted-endpoint contact observation can represent different instants.

**Regression verification**

Test tabletop, ramp, edge, ordinary field, disabled circuit, lake combinations, reset/rewind, and actual approach histories. Verify geometry identity and emitted audio events.

The previous **A6 F3** fix addressed statistics on composed terrain. It did not fix this separate audio consumer.

### N05 — Deferred audio observation counts time before liftoff

**Priority: P3. False touchdown cue and incorrect debounce.**

The scheduling logic in [`flight_audio.gd:146–159`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/flight_audio.gd#L146-L159) may defer observations while the last observed wheels are grounded. When the next endpoint is airborne, [`GroundAudio`](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio.gd#L68-L105) passes the entire elapsed interval into the [motion classifier](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/audio/ground_audio_motion.gd#L6-L47).

That backdates liftoff.

**Reproduction and calculation**

At 240 Hz:

- Grounded through ticks 0–3.
- Airborne on ticks 4–34.
- Loaded again on tick 35, with sufficient approach speed.

Per-tick observation credits:

\[
31/240 = 0.12917\ \text{s},
\]

below the `0.14 s` touchdown threshold.

With observation at a four-tick render boundary, the first airborne endpoint receives four ticks instead of one. Credited duration becomes:

\[
34/240 = 0.14167\ \text{s}.
\]

The production classifier therefore queues **zero** touchdown events in the per-tick case and **one** with default sampled cadence. A longer-hop control queues one under both.

The test uses production classes with a synthetic contact sequence and outer near-ground gate. It does not establish occurrence frequency or audible output in real flights. The extra event also starts the `0.65 s` debounce, potentially masking a subsequent legitimate cue.

**Correction**

Preserve the first unloaded tick through a qualified per-tick transition observation, or explicitly represent uncertain onset and apply a conservative policy. Reducing the sample interval alone does not recover the true transition time.

**Regression verification**

Shift hops just below and above the threshold across render phases at 30/60/144 FPS and cadence settings 0–4. Include stationary ground, sustained flight, ordinary touchdown, pause and reset. An exact transition receipt should match the tick oracle; an uncertainty-based implementation should satisfy declared bounds and document false-positive versus missed-cue behavior.

## 4. Existing issues that remain more important than cosmetic optimization

These are **previously documented issues**, not new findings from this audit.

| Earlier issue | Assessment and required action |
|---|---|
| **A6 F6 — coupled tire/brake dissipation** | Still pending. Force limits do not guarantee passive behavior. Fix before further handling calibration. |
| **CF-05 — raised-track first-contact admission** | Clear endpoints can conceal an interior crossing. More bisection cannot repair a crossing never admitted. |
| **CF-06 / E300-01 / CF-01 — moment conventions** | Resolve flap-flow projection and moment origins before tuning pitch/yaw behavior. |
| **H01 — grounded helicopter yaw reference** | Current source suppresses the integral while manual heading reference can still advance. |
| **H02/A20 — low-RPM rotor-law domain** | The blend/domain qualification remains open. |
| **WNEW-02 — native turbulence restore** | Preparation still reads the old live auxiliary index before the restored index is committed. Actual native continuation needs dedicated verification. |
| **WNEW-03/WNEW-04 — helicopter discontinuities** | Prior tail-wake and sideflow witnesses remain relevant; standalone results do not automatically prove a full-session upset. |
| **A11/A13/A14/A17/A21 — UI and persistence** | Existing lighting ownership, rollback, draft, navigation and error-visibility issues remain separate work. |
| **A24 / RCV-41 — performance** | Repeated observer work and identity I/O were already documented; historical timings are not current measurements from this review. |

The authoritative status reference remains the [consolidated audit ledger](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/external%20Audits/CONSOLIDATED-AUDITS.md).

I also checked repairs rather than assuming old reports still applied. Current source contains the glow multi-substep admission guard and representable-reserve handling. The companion identity helper matched **174 current source files** to the qualified profile, so the earlier companion-admission mismatch is not a current finding. Historical Home-calibration complaints also do not describe the current source route.

One concern remains **unpromoted**: explicit `gdscript_reference` helicopter reset can notify observers before candidate refusal, unlike the rollback-wrapped native-request route. I found the asymmetry, but no ordinary supported stock restart demonstrating the failing boundary. It should receive a targeted refusal test, not be reported as a confirmed player failure. [Reset implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/app/sim/helicopter_flight_session.gd#L405-L519).

## 5. Mathematical and performance priorities

### Enforce local passivity in contact solving

For each nonelastic tire and brake without an explicit energy store, enforce:

\[
\mathbf F_{t,i}\cdot\mathbf s_i \le 0,
\qquad
Q_{b,i}\omega_{\mathrm{rel},i}\le 0.
\]

Here, \(\mathbf s_i\) is actual contact slip including body, suspension and wheel motion; \(Q_{b,i}\) is signed brake torque on the wheel; and \(\omega_{\mathrm{rel},i}\) is wheel spin relative to the body.

Checking only the total power sum is weaker: one element’s negative work can conceal another’s positive work. Preserve static zero-slip reactions and account explicitly for any physical energy store introduced.

A coupled impulse or constrained optimization formulation may address A6 F6, but it must preserve force limits, reversal, load loss, rollback and native/reference agreement. Independent scalar clipping is not sufficient evidence of correctness.

### Separate event admission from root accuracy

For CF-05, equal-sign endpoints do not prove an interval has no contact crossing. The algorithm needs conservative interval admission and selection of the earliest supported event before accurate root localization.

Increasing global tick frequency or root iterations can consume substantial CPU while leaving that logical error intact.

### Preserve endpoint meaning when sharing observer work

A promising architectural improvement is a single immutable contact observation carrying:

- Accepted tick.
- Environment and geometry identity.
- Endpoint contact/load information.
- Transition timing or explicit uncertainty.

Statistics and audio could consume that consistently. N04 and N05 provide correctness tests for such a change. A cached RK-stage result is not automatically an equivalent endpoint observation.

### CPU, GPU and memory conclusions

I did **not** run a target-hardware timing campaign, so there is no defensible new “X% faster” or FPS claim.

At 240 Hz, each outer tick has approximately **4.167 ms** of real time; a 60 FPS frame normally contains four ticks. The project’s 500 µs physics target is an acceptance budget, not a guarantee. Its 12-step catch-up limit deliberately leads to slowdown below approximately 20 rendered FPS. That documented behavior is not a newly discovered hang. [Timing and budget policy](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/STACK.md).

For CPU work, measure current backend-identity checks, repeated contact observations, and configuration preparation before changing them. Preserve cache invalidation and fault semantics. For memory, distinguish retained replay history from bounded caches and truly abandoned objects.

For GPU work, use the existing [graphics/debug tooling](https://github.com/bultodepapas/OpenRCsimulator/blob/b21c0789649b856217d82faa112c190d34389a21/docs/tools/graphics.md) on target hardware at actual 1080p pixels. Hold camera, aircraft, landscape, weather, renderer and reconstruction constant; then isolate shadows, transparent overdraw, reflections, geometry submission and post-processing. Shader length alone does not identify a bottleneck.

## 6. Executed checks and limits

| Check | Result |
|---|---|
| Full resource import | Completed; no checked errors, eight OBJ/PBR ambient warnings |
| RC vehicle session | **162 checks, 0 failed** |
| RC nitro session | **28 checks, 0 failed** |
| Environment lifetime | **34 checks, 0 failed**, including eight retirement cycles |
| Startup/failed-launch cleanup | **29 checks, 0 failed** |
| Controller latch witness | **16 checks, 0 failed** |
| Recorder witnesses | Both overwrite cases and both failed-save replacement cases reproduced |
| Audio witnesses | Circuit mismatch and cadence mismatch reproduced, with controls |
| Companion identity | Qualified profile matches 174 current source files |

The RC session test explicitly skipped its native backend-switch guard because the native extension was not staged locally. Local execution used Linux headless/Dummy; it does not qualify physical controllers, native graphics, GPU memory or real-aircraft behavior.

At **2026-11-07 01:53:04 UTC**, the same-commit GitHub run showed **17 of 19 checks successful**, including all eight unit shards, both RC native production jobs, NK-3 Linux qualification, and release builds. Integration and visual jobs were still running. [Workflow run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42322395902).

## 7. Practical improvement plan

| Order | Work | Acceptance criterion |
|---|---|---|
| **1** | Fix recording preservation and automatic save allocation | Neither successful nor failed generations can disappear without the intended save/discard policy |
| **2** | Preserve controller latch continuity | An unchanged held input cannot retrigger after Controls; changed bindings require OFF before ON |
| **3** | Close existing simulation correctness gates | Contact passivity, raised-track admission, moment conventions, rotor domains and native restore have accepted-session evidence |
| **4** | Align audio geometry and timing | Circuit/lake combinations and frame-phase tests produce consistent contact cues |
| **5** | Optimize measured hot paths | Same-workload p50/p95/p99 and allocation/RSS evidence, with replay and rollback preserved |
| **6** | Complete platform qualification | Same-commit CI, packaged desktop smoke tests, physical controllers, target renderers and repeated session transitions |

My recommendation is to make the recording and controller corrections first, in small independent changes, then address the existing physical-correctness gates before retuning handling. The audit produced concrete new failures without treating previously documented problems, deliberate research limitations, or unmeasured rendering costs as fresh discoveries.