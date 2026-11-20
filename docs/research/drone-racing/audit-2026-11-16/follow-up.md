# FPV audit follow-up: evidence and repair options

**Date:** 2026-11-16. **Production source:** `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`; experiments were run from the published audit checkout `35c20367027ed7306dca58997ce11f3c9a9cce2f`, with unchanged production files. This extends the original 18-finding audit with **A19, a P2 controller-generation defect**, bringing the [current register](README.md) to **19 findings: 2 P1, 12 P2 and 5 P3**. The [active drone plan](../../../plans/drone-racing.md#16-audit-remediation-programme-2026-11-16) owns implementation order and closure gates.

The follow-up strengthens A03, A07 and A10, adds a Start/AUX case to the A02/A05 ownership problem, and compares repair mechanisms. **Eight selected checked runs passed: 60 observation/comparison assertions, two geometric/composed-tick witnesses and 15 bounded pad-start trials, with zero engine errors or warnings.** These categories are distinct; the witness/trial counts are not additional unit-test assertions. The probes observe current behavior; successful diagnostic checks are not desired-behavior regressions. No production fix, native controller acceptance or physical validation is claimed.

## 1. Source drift and execution scope

Remote main advanced to `6dfe1b9179af408f6b765b91ca164e626570db9f` through two ClearView-related commits. The audited multirotor physics/data/input, race/session/activity, AppRoot and UI-input files and the owning drone plan are unchanged. Other shared files, including translations and Creator code, did change. This is a source-drift comparison, not complete requalification of that newer main. The experiments deliberately use the stable audit checkout.

The engine is the repository-pinned **Godot 4.8.beta2.official.cafc17a19**, Linux x86_64, headless with Dummy audio and separate disposable profiles. The existing 25-suite/1,120-check baseline remains [dated evidence](evidence/verification.json); it was not needlessly rerun for documentation and diagnostic additions. The local checked runner was used because the test pool had no host configuration. [follow-up.json](evidence/follow-up.json) records per-run completion, diagnostics, source/log hashes and portable observations. Raw runner metadata is excluded.

## 2. Stronger observations

### A03: ordinary pause through the real activity

[scene_pause.gd](experiments/scene_pause.gd) constructs the real activity with a synthetic selected radio and a valid level Arm AUX profile. It prepares the supported research air start at 20 m AGL, arms with fresh OFF then ON evidence, opens the actual menu and uses its Continue handler. The source generation and Arm switch remain unchanged. The first accepted resumed tick nevertheless contains a ready input with Arm OFF, disarms the motor and records that substituted OFF in the tape. **12 observation checks passed.**

This closes the earlier gap between the input/plant witness and the actual activity path. It does not establish physical-radio behavior or an ordinary pad-start airborne trajectory. The shared fresh-OFF rule remains legitimate: while paused, AUX polling is disabled/reset, so a proposed fix that simply waits for a valid AUX request before enabling Continue would deadlock. See [RCInput](../../../../app/input/rc_input.gd), [quad input](../../../../app/input/multirotor_input.gd) and [activity](../../../../app/vehicles/multirotor/multirotor_scene.gd).

### A02/A05 extension: Start ignores effective Pause ownership

[start_aux_scene.gd](experiments/start_aux_scene.gd) tests Arm and Flight mode separately. Each accepted profile remaps Pause to P and assigns its AUX channel to Start. The real scene adopts the profile; a selected-device release establishes fresh OFF; a foreign-device press has no effect. A selected Start press creates the valid AUX request in the input handler and then opens Pause in the scene's unhandled-input handler. **14 checks passed.**

The experiment explicitly calls those handlers in input-phase order. Native GUI event dispatch is not exercised, and no accepted armed physics tick is claimed for this press: Pause occurs before one. The result is an additional binding-ownership case, not evidence that Start arms while paused and not an extra count added to the original 18 findings. The runtime shortcut is visible in [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd); effective binding validation lives in [controller_actions.gd](../../../../app/input/controller_actions.gd).

### A19: a second matching pad invalidates the active verifier without a hold

[duplicate_pad_scene.gd](experiments/duplicate_pad_scene.gd) uses the real ControllerService, its hotplug/refresh path, real registry and real quad activity. Device observations, OS-focus/SDL confirmation and input are synthetic; the initial arm is an injected keyboard action. A different-family arrival is a positive control: the original selected gamepad remains ready and armed. Adding a second same-family gamepad keeps the original selected and connected, but ambiguity advances its registry generation. The quad sync compares only numeric ID and retains its old generation-bound verifier. The next real activity tick accepts an unready input and disarms, while the activity keeps running without opening a recovery menu. Removing the second pad leaves the verifier stale. **12 checks passed.**

The real service's verifier also rejects the old generation before its OS checks. Source review of [ControllerService](../../../../app/input/controller_service.gd), [registry](../../../../app/input/controller_registry.gd), [AppRoot](../../../../app/app_root.gd) and [activity](../../../../app/vehicles/multirotor/multirotor_scene.gd) finds no intervening rebind/hold on this ambiguity-only path: it emits devices-changed, retains flight selection, and automatic defaults are disabled while the activity is active. This is a scene/service software reproduction with injected device observations, not native hotplug timing or a flown motor cut. P2 matches A03's lifecycle severity. A preliminary registry-only 11-check probe passed but is excluded from totals in favor of this stronger service-integrated run.

**Repair direction:** distinguish changed matching evidence for an uninterrupted handle from actual disconnect/replacement. Either reverify the same physical authority and preserve its allowed mapping/continuity, or hold and explain recovery before accepting the next physics tick. Do not blindly preserve an old generation or silently feed unready input into an armed flight. Cover addition/removal, different-family controls, serial-qualified devices, actual identity change and same-handle reuse.

### Additional constructed ordering, not another confirmed finding

[same_handle_reselect.gd](experiments/same_handle_reselect.gd) uses the real registry and scene with two synthetic raw-radio profiles having opposite roll inversion. It changes a serial on the same numeric handle and explicitly reselects that handle synchronously before deferred selection callbacks execute. The registry correctly clears the original selection and advances its generation, but the scene's ID-only sync keeps the old mapping/source generation and accepts a ready armed input with the old roll sign. **10 observation checks passed.**

Ordinary human/UI reachability of that precise ordering is unproven, and the profile resolver is synthetic. It is retained as a boundary regression candidate for the A19/DR-14 repair, not counted as A20. Identity replacement normally clears selection; the existence of a generation change alone is not proof that all uninterrupted connections must lose authority.

### A07: endpoint miss on the shipped RC ramp

[rc_ramp_disc.gd](experiments/rc_ramp_disc.gd) uses the shipped quad, default field and default RC track. It constructs a stationary accepted pose at north 39.0 m, east -5.1 m, yaw 0, with every rotor hub at least 5 mm above its sampled terrain and shafts at 1,000 rad/s. A rotor-rim witness penetrates the terrain by **0.028290129 m**, while the production `crash_reason` is empty. At the witness the east slope is approximately **0.554871**. Track source SHA-256 is `31ee093d4fc968d8bfb083a7ee89315030373ce886f87195b78115000e680e29`.

This extends the original analytic-plane counterexample to shipped composed terrain. It is still a constructed endpoint, not a flown collision or a measurement of physical rotor contact. Finite rim samples establish this observed hit; absence of a sampled hit could not establish clearance. See [controlled plant](../../../../app/physics/multirotor/controlled_plant.gd) and [RC track](../../../../app/physics/ground_vehicle/airfield_track.gd).

### A10: finish-before-crash through a real wrapped physics tick

[wrapped_collision_tick.gd](experiments/wrapped_collision_tick.gd) initializes a valid final-lap checkpoint, with a disarmed moving vehicle, then calls the real session tick. It traverses RK4, plant endpoint, race wrapper and director. The initial proxy clearance is **0.168541212 m**, above the body radius **0.167950351 m**. A point on the accepted chord before the finish-plane crossing has clearance **0.167934928 m**, already within the proxy. The accepted crossing fraction is **0.400269664**, with inferred mean acceleration **12.5040 m/s²**, within the rules' declared chord envelope.

The committed event order is `race_gate, race_lap, race_finish, crash`; the result is valid and FINISHED, while the crash is stamped at tick 1201's endpoint. Thus the defect survives the composed physics path, not only a director fixture. The checkpoint is deliberately initialized; this does **not** prove that a legal flown race tape can reach it. See [race model](../../../../app/sim/race/race_model.gd), [director](../../../../app/sim/race/race_director.gd), [gate crossing](../../../../app/sim/race/gate_crossing.gd) and [session](../../../../app/sim/multirotor/session.gd).

### A06: bounded pad-start search narrows the claim

[pad_start_regen.gd](experiments/pad_start_regen.gd) performs **15 stock-data session trajectories**, all from a fully charged ordinary field pad, without editing a frame. It arms, applies throttle 0.2, 0.5 or 1.0 for 1, 4, 12, 36 or 96 ticks, then chops to zero for 60 ticks. All **1,377 ticks** were accepted. Eleven trajectories show negative endpoint pack current and increasing accepted charge; the lowest observed current is **-19.092436 A**, and the largest one-tick charge increase is **0.084764365 C**. **None exceeds the initial 4,680 C capacity.**

Regenerative current itself is intentional in the existing damped law and is not a new defect. These bounded results establish normal pad-start regenerative operation, but do not establish pad-start over-capacity. The supported research-air-start over-capacity witness in the original audit remains valid. Neither result is exhaustive. The electrical equations and the existing coasting/braking comparison are in [controlled_plant.gd](../../../../app/physics/multirotor/controlled_plant.gd) and [test_mr_controlled_plant.gd](../../../../app/tests/test_mr_controlled_plant.gd).

### A13: a recoverable publication pattern already exists

[persistence_options.gd](experiments/persistence_options.gd) observes that, on the pinned Linux build and the same local filesystem, direct rename replaces an existing regular file and the tested missing-source rename failure retains it. Explicitly deleting the target before that failure loses it. The probe then uses the existing PreferencesFile publish seam to inject destination removal followed by publication failure. The helper reports failure, restores the exact previous bytes, releases its lock and successfully handles a later save. **12 checks passed.**

This is concrete reuse evidence for [preferences_file.gd](../../../../app/app_state/preferences_file.gd), not a claim that its ConfigFile API can directly store a race book or that rollback survives every interruption. [statistics/store.gd](../../../../app/statistics/store.gd) provides another relevant pattern: independently validated alternating generations.

## 3. Platform facts that change the storage plan

The exact official engine source was inspected at **cafc17a192acf67903910a68aeb3c076c0907a4b**:

| Source | Observed implementation | Consequence |
| --- | --- | --- |
| [Windows DirAccess](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/windows/dir_access_windows.cpp), `DirAccessWindows::rename` | For an ordinary different-path replacement, an existing destination is removed before `MoveFileW`. | Removing OpenRC's own pre-delete does not by itself repair Windows replacement failure. This is source inspection, not a Windows execution. |
| [Unix DirAccess](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/unix/dir_access_unix.cpp), `DirAccessUnix::rename` | Calls native rename; cross-device fallback copies and removes. | Keep staging on the same filesystem and qualify actual platform behavior. A generic rename call is not a universal atomic transaction. |
| [Unix FileAccess](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/unix/file_access_unix.cpp), `FileAccessUnix::flush` | Uses `fflush`, with no `fsync` in that method. | Successful flush/readback is not proof of survival through sudden power loss. |

The [official DirAccess documentation](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html#class-diraccess-method-rename) describes destination overwrite, not a cross-platform atomicity or durability guarantee. A repair should promise **recoverable replacement under a specified failure model** unless a stronger native primitive and recovery protocol have actually been qualified.

## 4. Alternatives and selected planning direction

### Controls: repair the managed boundary before redesigning the shared API

The [controller service](../../../../app/input/controller_service.gd) deliberately returns an explicit default for a healthy new known gamepad and an empty result on refusal. [Airship's selected-controller path](../../../../app/vehicles/airship/airship_scene.gd) already prevents an empty managed result from activating RcInput's standalone default. Apply that refusal contract to the quad first, retaining a connected but unready selected device and useful setup diagnostics. A typed resolution result is a useful later shared-interface improvement, but is not necessary to close A01. Silently switching to keyboard is not a repair.

For A02, reserve every physical member of configured known AUX bindings against inherited quad shortcuts, with explicit Arm precedence and synchronized held/edge state. The ownership map must include only actions the quad actually dispatches: the generic inherited LB throttle-cut action is not active in this activity. Blindly treating the entire shared action map as occupied would break ordinary default LB arming. Route Pause/Start through the same effective ownership policy and derive help from that result. Preserve separate flight and UI device roles.

For A03, prefer a scene/adapter **ordinary-hold continuity contract**. Capture the verified handle, connection generation, effective mapping and last valid arm intent atomically at pause entry; observe relevant changes without queuing toggles; recheck before the first resumed tick. A genuine OFF, OFF→ON sequence, profile/source/focus uncertainty or lost verification invalidates powered continuity. Recovery must be explicit. Keeping the last ON indefinitely would hide a real switch change. A smaller containment option keeps the scene frozen and offers a clearly explained pad restart, but does not fully satisfy ordinary powered-resume behavior. Changing the nine-value pilot frame to carry tri-state validity is a larger versioned alternative, not an incidental patch.

### Persistence: authoritative attempts and an idempotent book

The [activity's result callback](../../../../app/vehicles/multirotor/multirotor_scene.gd) currently updates the record book even when the attempt file failed to save. Retrying by blindly applying the result again can double-count. Conversely, a successful attempt write followed by a failed book write needs reconciliation. The latter failure combination is a source-inferred consistency gap, not an injected crash demonstrated here.

Select a stable publication UUID outside the pure physics transition; retain it and its canonical payload on retry. Same ID/same payload is idempotent success; same ID/different payload is a visible conflict. A name collision must never overwrite another result. If UUID generation fails after the terminal tick, retain the terminal payload and expose retry; do not lose it merely because it has no publication ID yet. Use a properly scoped exclusive writer/recovery lock or a qualified atomic no-replace primitive; check-exists-then-rename alone has a race. Preserve a legacy-book baseline and define a bounded, idempotent post-migration projection. The new authoritative payload must retain course/rules/medal facts needed to reconstruct the same projection; historical files do not necessarily contain them.

The minimum release provides Retry saves and guards every graceful departure or restore that would destroy the last pending copy. A permanent storage failure must offer staying in the activity, retrying, or a specific informed discard showing the pending count; cancel preserves every pending payload, and only that explicit discard permits loss. This fixes graceful-session recovery, not process-crash survival. A durable queue is a separate phase with a verified acknowledgement boundary and startup reconciliation; it cannot save a result when its own first write fails. Keep external publication ownership separate from rewindable physics. Deterministic verification replay must not publish; a deliberately resumed live branch needs an explicit publication identity policy. Preserve unknown/future and malformed legacy bytes, and define migration for the partial entries accepted by an existing test rather than inventing missing historical counters.

### Physics: choose a coherent law, then qualify its consequences

For A06, the smallest coherent experimental baseline is the existing **one-quadrant, non-regenerative** law, with explicit refusal of unsupported signed-regeneration configurations on raw and prepared paths and a charge-domain check. Regenerate the shipped estimated data through its source pipeline. This is a proposed behavior change: the existing synthetic throttle-chop test shows much weaker early roll authority when coasting. Preserve baseline logs and qualify candidate response before adopting it. If the candidate cannot meet the declared maneuver envelope, keep the gate open and implement a complete braking law; do not restore unbounded regeneration merely to recover a passing feel test.

Two alternatives remain: dynamic non-regenerative braking with an explicit loss/switching mechanism, or bounded regeneration with charge acceptance, voltage/current limits and a destination for excess energy. Retaining negative motor torque while clipping negative pack current breaks energy accounting. Test stage bus balance and integrated chemical/terminal/pack-loss/shaft work, including full/near-full boundaries, mixed motor power flow, disarm/depletion and step refinement. None identifies the real ESC's braking behavior.

For A08, keep the independent maximum-power bound as a negative oracle, then solve the **loaded shared-bus equilibrium**. For each required hover thrust, derive shaft speed and positive current using the actual regularized friction law; define `Ai = wi/Kv + Rm*Ii`, `P = sum(Ai*Ii)` and `B = Voc - Rp*Iaux`. Candidate bus voltages satisfy `V² - B*V + Rp*P = 0`. Check a numerically stable root, positive voltage, every duty/speed bound and residuals against the plant. Explicitly choose the high-voltage operating branch or evaluate both; handle zero resistance and near-double-root uncertainty. The current low-charge screening point is the first OCV knot strictly above 0.1 SOC, **0.2 for shipped data**, not 10%. This establishes a frozen-SOC, quasi-steady mechanical/electrical hover operating point. Positive pack draw still reduces charge; neither full-state equilibrium nor sustained hover follows. Real-FC hover with throttle/torque limits is a separate acceptance check.

For A07, a planar slope has an exact disc oracle. With NED center `c`, unit disc normal `a`, radius `r` and `l = (dh/dn, dh/de, 1)`, maximum penetration is `c_down + h(c_n,c_e) + r*norm(l - a*(a dot l))`. This does not certify curved terrain: an interior crest can miss every rim sample. Reuse bounded witness/clearance ideas from [rotor_disc_terrain.gd](../../../../app/physics/rotorcraft/rotor_disc_terrain.gd), with a new adapter that bounds the **whole composed terrain**, including the RC overlay. The existing helper does not accept that overlay; the RC upper bound alone does not necessarily bound the quad's memoized tangent approximation. Custom ramp widths can approach zero under current admission. Define exact collision geometry, a valid approximation bound, or refusal of unsupported geometry before claiming clearance. Review the CG-only 0.6 m early-out. An unresolved bound is not an observed crash.

For A09, share normalized physical invariants between raw and prepared admission, while retaining raw-only provenance/inventory checks. Validate passivity, inertia, geometry, powertrain/pack/contact domains, derived data and loaded hover as appropriate. Refusal must preserve the accepted frame, tape, recorder and identity. Version physics/collision compatibility deliberately: the flight log's solver hash alone does not prevent restoration of an older session checkpoint with an unchanged model/session identity.

### Scoring: conservative uncertainty before an event locator

For A10, select a versioned conservative local-practice rule: a terminal with unresolved time within the tick suppresses that tick's crossings. Cover crash and depletion. It may invalidate a physically earlier finish when the actual terminal was later; make that consequence explicit. A future locator can accept a finish only when certified crossing and terminal intervals prove its precedence. Endpoint timestamps or unqualified interpolation cannot establish that ordering. Pair rule changes with course/result identity and legacy-record policy. A15 should hash canonical terrain-resolved collision frames; A14 should capture the pre-reset terminal tick and a consistent reset reason without weakening reset transactionality.

## 5. Reproduction and interpretation

Use the imported audit checkout, pinned engine, a fresh profile per probe and the repository checked runner. Example from the repository root:

```sh
FPV_GODOT="$(app/get-godot.sh)"
FPV_EXPERIMENTS="$PWD/docs/research/drone-racing/audit-2026-11-16/experiments"
XDG_DATA_HOME="$PWD/tmp/fpv-followup-repro/scene-pause" \
python3 tools/godot/run_checked.py --label fpv-followup-scene-pause --timeout 180 \
  --require-text 'scene pause repro: 12 checks, 0 failed' -- \
  "$FPV_GODOT" --headless --path app --audio-driver Dummy \
  --script "$FPV_EXPERIMENTS/scene_pause.gd"
```

The [manifest](evidence/follow-up.json) supplies each script and completion marker. The ramp and pad probes are bounded searches: inspect their reported observation, not merely exit zero. After a production repair, convert each applicable diagnostic into a desired-behavior regression; a baseline probe that expects the defect should then stop observing it.

Native Windows/macOS replacement behavior, physical radio/gamepad transitions, native 1080p event/UI behavior and performance, full required CI, long endurance, selected-build measurements and a legally flown A10 collision tape remain separate evidence gaps. No calendar estimate or fidelity promotion follows from these source reviews and headless experiments.
