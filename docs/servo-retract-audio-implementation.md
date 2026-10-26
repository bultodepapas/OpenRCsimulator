# Servo and retract audio — AUD-16

2026-10-25. Owner: audio. Parent: [audio guide](AUDIO-PLAN.md). Recording provenance and redistribution terms: [asset sources](audio-asset-sources.md).

## Contract and integration

Mechanical audio is a read-only presentation consumer. It does not change aircraft data, servo rates, flight commands, solver state, checkpoints or random numbers. Godot is the repository's pinned **4.8.beta1.official.4d10419ca**.

`app/audio/flight_audio.gd` observes every accepted `Simulation.stepped` endpoint after FlightSession's existing handler. It reads actual surface angles from `FlightSession.surface_angles_deg()`, the accepted flap fraction and maximum angle, and `gear_state()`. Simulation `dt()` supplies the clock. Render updates separately supply source/listener positions and the smoothed engine mask. A changed stick or gear target alone cannot produce motion audio.

There are three conventional logical actuator channels: aileron, elevator and rudder, plus a flap channel where the aircraft simulates flaps. The two ailerons and split elevator hinges share the existing logical state; they do not become independent simulated servos. Sources follow the centres of their authored control hinges, with the aircraft root as a fallback. This approximates servo installation positions; it does not claim hardware mount measurements. Retract sound uses one source at the airframe root for the coordinated mechanism.

The actual viewport `AudioListener3D`, when present, supplies listening position; otherwise the flight camera does. PiP remains non-listening under the camera system's existing contract. Camera cuts do not create artificial mechanical Doppler sweeps. Existing engine, rolling-wheel, impact and environmental audio continue through their established routes.

`mechanical_motion.gd` observes accepted deltas and transitions. `mechanical_audio.gd` owns bounded spatial players, recording playback and envelopes. `mechanical_profile.gd` validates the closed presentation configuration. Missing recording resources fail silent rather than substituting generated buzzing.

The observer builds one fresh normalized record per actuator and shares it between that result's state and motion views. Consumers must treat returned records as read-only. Neither input snapshots nor earlier observer states are mutated. Repeated accepted ticks refresh source positions and gear request metadata while preserving accepted travel and speed.

GP-19's `accepted-tick-mechanical-transitions-v1` captures start, reversal, stop and endpoint cues between render frames through the existing `MechanicalMotion` classifier. `MechanicalAudio.observe_accepted()` retains up to 64 ordered transitions, stamped with their accepted tick; overflow discards the oldest and increments diagnostics. Playback drains each retained batch once and refreshes spatial positions at render time. Its existing voice priority can still drop simultaneous transient cues. This presentation history owns no physical state, damage events or checkpoint fields. Direct presentation benches keep their legacy sampling mode unless they explicitly enable accepted observation.

Pause notifications discard pending transitions even if pause and resume both occur between frames. Manual stepping while paused records actual positions silently. Reset, tick gaps/rewinds, clock changes and invalid samples prime a fresh history; rejected physical ticks append no sample or cue. Detaching disconnects the session callbacks. Reattachment waits for child buses to rebuild, binds them before priming, then reconnects once. Reconfiguring replaces the old players, buses, channel bindings and subscriptions. A render-side rewind cannot erase valid movements already captured after the rewind.

## Configuration and Workshop

Workshop → **Mechanical audio** exposes exactly two servo profiles, **Standard Servo** and **High-Torque Servo**, servo level from 0–100%, and mechanical/electric or pneumatic retract sound. Retract selection is unavailable for fixed-gear aircraft. Existing game volume remains the overall volume control.

Presentation profile v4 adds this closed object:

```json
"mechanical_audio": {
  "servo_type": "high_torque",
  "servo_level": 0.75,
  "retract_type": "pneumatic"
}
```

Defaults are `standard`, `1.0`, and `electric`. These are sound-design choices, not a declaration that an aircraft's real hardware uses that mechanism. V1–v3 profiles remain readable without rewriting their data or identity; absent mechanical settings resolve to defaults. New settings participate in the presentation identity, independently of the physical trial identity. Undo/Redo, page reset, save revisions, portable bundles and draft recovery carry the same profile. Customized v1 smoke profiles retain their existing explicit migration requirement before promotion; an audio edit cannot reinterpret their smoke settings.

Finite numeric bounds and supported enum values are checked before a profile enters a variant. No asset path, script or source position can be supplied through a Workshop profile. Future servo profiles can be added to the closed registry and recording bank without adding vehicle-specific branches to the simulation kernel.

## Sound and mix decisions

Travel speed derives from angular displacement divided by accepted tick time. Motion duration gates recorded movement; speed changes the envelope and pitch. A 0.2 degree/second settling floor is independent of render sampling frequency. Starts, reversals and stops are separate from stationary state. No idle holding buzz is invented. The observer can carry an optional load field, but there is no load-to-sound mapping in this version: the flight model supplies no servo torque/current.

Electric retract playback uses motor/gear movement and endpoint cues. Pneumatic playback uses recorded valve/air textures and endpoint cues. The current gear law has an accepted deployment fraction and target with up/down endpoints; it has no air-pressure state, independently timed door state or lock sensor. Endpoint cues represent arrival at the model's accepted endpoint. There are no invented door events or pneumatic-pressure dynamics. Canopy, tailhook and wing-fold presentation animations are outside this initial logical actuator contract.

Engine masking uses accepted shaft RPM and installed engine family. Combustion idle receives a modest residual gain reduction; electric masking falls with shaft speed. This supplements the existing louder engine mix. Authored gain trims are not calibrated sound-pressure levels and cannot establish acoustic realism.

The bank contains 17 mono PCM16 cues, 429,074 decoded PCM bytes. Servo and electric textures use 44.1 kHz; air-only textures use 22.05 kHz. The two profiles use separate recorded servo sources, two onset/stop takes each, small deterministic gesture pitch/phase variation, and 35 ms attack / 85 ms release envelopes. The High-Torque profile uses a 0.82 pitch reference and a gentle 2 dB upper-shelf cut; those are authored treatments, not measured torque acoustics. The existing PCM loop wrap guard remains active; committed WAV imports disable QOA compression.

Spatial players feed the existing scene aggregate bus, outside the engine-only boost/filter chain. Manual gain is capped inside 2 m, follows inverse distance beyond it, fades from 39–60 m, and reaches zero at 60 m. Godot provides 3D panning without a second attenuation curve or mechanical Doppler. Outside audible range, render processing discards queued transients and bypasses detailed spatial playback; production accepted-tick capture continues. The legacy direct-snapshot mode primes silently on return. Pauses, stalled ticks, rewind, reset, detach and reconfiguration retire voices. The bank fails silent if a required resource is missing.

There are at most six pooled movement voices and two transient voices. Only moving audible channels start a loop. Gear locks take priority over gear onset, then servo onset and servo tails. Same-source reversals and interruptions fade the old transient over 20 ms before replacement; a canceled gear movement clears pending cues. Under simultaneous corrections, lower-priority transient cues may be dropped while movement beds remain active. This avoids multiplying every surface's start click.

A finished outgoing sample still reserves its slot for a pending cue. This fixes a reproduced race where a new servo onset could erase a queued gear lock between render updates. Movement voices stop when the pause/distance scene fade reaches silence, instead of consuming mixer voices until their separate release envelope settles. Stopped movement/event voices skip redundant player updates; attenuation envelopes share frame coefficients, and event positioning reuses normalized motion records instead of copying every actuator again.

## Verification

The GP-19 follow-up (2026-10-26) passes **317 selected checks**: accepted capture 58, existing playback 103, motion 36, configuration 24, ground audio 33, new real-session integration 35 and existing full-scene integration 28. The [retained cohort](research/ground-physics/GP-19/evidence/accepted-mechanics/README.md) includes source pins, checked logs, failed draft receipts and a bounded Dummy benchmark. Actual P-51 gestures return to their initial angle between renders while retaining all transitions; paired complete session checkpoints remain identical with audio attached. Reset, rewind, rejected ticks, paused stepping, reattachment and repeated configuration are covered. These checks establish this presentation slice, with native output, listening, whole-flight performance and accepted ground/slip/damage audio still open. Earlier AUD-16 native evidence below predates this tick-capture change.

Signal checks and deterministic state tests do not establish listening acceptance or physical sound calibration. Verification uses the pinned Windows Godot binary, Dummy for state tests and WASAPI for actual mixer captures. Results are summarized here; [verification evidence](research/audio/AUD-16/verification.json) retains measurements, source identities and failures, and [physics parity](research/audio/AUD-16/physics-parity.json) retains the paired checkpoints. The four focused suites total **191 passing checks**.

| Check | Result |
| --- | --- |
| Motion observer | 36 checks passed: actual deltas, speed, reversal, endpoint, pause, rewind, slow corrections at 30–240 Hz, snapshot ownership, repeated-tick position refresh and source replacement |
| Closed profile and migration | 24 checks passed: two types, finite level, v1–v3 identity, v4 JSON round trip, transfer |
| Recording/controller lifecycle | 103 checks passed: all four profile combinations, PCM assets, pooling, persistent loop playback, interrupted cues, priority, pending-cue cancellation on pause, reserved lock surviving sample completion, retiring/restarting silent mixer voices, culling and missing-resource fallback |
| Real-scene integration | 28 checks passed: frozen Workshop profile, P-51 accepted surface/flap/retract movement, gasoline/electric RPM masks and disabled sources, listener fallback, reset and cleanup |
| Existing regressions | Workshop presentation 85, transfer 22, store 141, bundle 28, trial 44, drafts 100, soundscape 168, powertrain 45 and ground audio 33 checks passed; Workshop UI suite also passed |
| Physics parity | Final isolated checkout: nine fixed-wing aircraft, 1,200 paired ticks each, identical full checkpoints with audio on/off, including pause and reset. Rotorcraft explicitly excluded |
| Export | Windows PCK mounted from an empty project: all 60 audio resources checked, including 17 actuator cues, manifest and CC BY attribution |
| 1080p Workshop | Inspected live through the debug bridge. Profile/level selection, fixed-gear restriction, Undo/Redo, save and Test fly verified; high-torque/65% reached the flight controller. Clean shutdown: no leaked objects |

The four-combination native bench has both passing and failing timing evidence. An earlier run captured about 49.3 s at 48 kHz with zero discarded frames and no clipping; controller update p95 was 217 microseconds (maximum 395), and peak was −25.14 dBFS. The later run captured only 47.904 s against 49.447 s of scripted wall time, despite reporting zero buffer discards. Its signal checker correctly fails the 120 ms timing bound. Do not treat zero capture discards alone as proof of uninterrupted native output. Both runs stayed within six movement/two event voices, reached digital silence in settled idle/pause/mute/far intervals, and restored bus count. Half-amplitude masking measured about 6 dB reduction; full travel exceeded small corrections. These are shared-host controller measurements, not audio-thread deadlines or whole-game frame-time qualification. A subsequent review found and fixed pending cues starting during a pause fade; the final controller regression explicitly awaits and verifies that sequence.

An initial 20 s actual gasoline flight capture had zero discarded frames, silent pause, and a −21.53 dBFS peak. The older gameplay checker did **not** pass: total adapter p95 was 722 microseconds against its 500 microsecond gate, and the P-51 chase camera stayed at least 10.48 m away against that checker's fixed 4 m bound. These results prompted the distant-source observation shortcut and separate mechanical timing instrumentation. Later gasoline/electric captures measured mechanical p95 of 296/325 microseconds and total adapter p95 of 1,017/1,670 microseconds. The electric run captured 18.741 s of a 20 s schedule; wall-indexed pause checking also failed. Whole-flight timing, native continuity and performance acceptance remain open. The native checkers now require finite positive wall time, source hashes and balanced pushed/recorded/flushed frame accounting. Missing timing can no longer bypass validation. Six Python fixture regressions cover valid reports, missing/nonfinite/nonpositive time, counter imbalance and invalid PCM flags. Mechanical capture now bulk-appends frames and defers per-sample analysis/encoding until capture has stopped, bounded to 60 seconds of retained PCM.

An initial Home render encountered an unrelated vegetation texture allocation/load failure. The inspected 1080p flight/Workshop used `--scenery=off`. Shared lighting edits temporarily caused parse/provenance failures during later full-scene checks; independent mechanical tests continued without altering those files.

### Optimization follow-up

The fixed Dummy benchmark uses 1,000 warmup calls and 10,000 measured calls per scenario, prebuilt snapshots, the installed recordings, and the same pinned engine. Timings cover `MechanicalAudio.update_sound()` only. Recorded before/after measurements are in microseconds per call:

| Scenario | Median before → after | p95 before → after |
| --- | ---: | ---: |
| Idle | 118 → 49 | 204 → 87 |
| Four moving servos plus retract | 240.5 → 196 | 385 → 245 |
| Paused | 116 → 73 | 186 → 93 |
| Distant | 22 → 16 | 29 → 20 |
| Repeated accepted tick (`dt=0`, observer refresh) | 148 → 82 | 285 → 140 |

All measured loops had zero Godot object-count growth and zero voice-pool growth, using at most five movement/two transient voices for these fixtures. Object counts do not measure temporary dictionary allocations. These are bounded host observations, not native mixer or rendered performance acceptance; other sessions were active on this shared machine. The lock-reservation and silent-voice regressions were each observed failing before their fixes and passing afterwards.

The corrected native follow-up passed the checked runner and current signal checker: **49.600 s PCM / 49.584306 s wall**, no overflow/truncation/unaccounted frames, −25.13 dBFS peak, controller p95 **181 microseconds** (maximum 421). It recorded 2,380,800 frames and explicitly flushed 2,048 inter-stage frames; all 2,382,848 pushed frames balance. All four profile combinations passed settled-silence, movement contrast and masking checks. The preceding follow-up passed signal/accounting but was rejected by the checked runner for querying an unattached capture effect's uninitialized buffer; that harness error was fixed and the rejected result remains in the evidence.

The follow-up live P-51 and electric Timber captures also had balanced frames, zero overflows, silent pauses and complete throttle/camera/reset sequences. Their PCM/wall durations were 20.000/20.013005 s and 20.010667/20.007377 s. Mechanical p95 was **198/122 microseconds**; whole-adapter p95 was **886/583 microseconds**. Both still fail the general checker's 500-microsecond whole-adapter budget and fixed 4 m camera gate. These results qualify the measured mechanical behavior and improved capture continuity for these runs; they do not close whole-flight performance or listening acceptance.

The final nine-aircraft parity check used a disposable checkout at `ac6fb9535` plus the final audio files, with the same native extension. Its presentation registry was regenerated inside that checkout. This avoided a concurrent lighting edit that invalidated the shared tree's presentation hash midway through the preceding run. All normalized audio sources match the shared tree; some untouched files have different byte hashes from Windows checkout line endings. Both the rejected shared-tree attempt and passing isolated result are retained in the evidence.

The stable-checkout live repeats again passed capture continuity and silent-pause checks, with mechanical p95 of 208/160 microseconds and total adapter p95 of 879/743 microseconds for gasoline/electric. The same two general-checker gates still fail. Other sessions resumed rendered tests, so file isolation did not establish a quiet host or target-hardware performance qualification. Temporary checkout files were removed after preserving the reports.

## Files and reproduction

- Runtime: `app/audio/mechanical_profile.gd`, `mechanical_motion.gd`, `mechanical_audio.gd`, and the existing `flight_audio.gd` adapter.
- Configuration: `app/workshop/presentation.gd`, `profile_transfer.gd`, `store.gd`, `bundle.gd`, `trial.gd`, `draft_store.gd`, and `app/ui/workshop.gd`.
- Recordings: `app/assets/audio/mechanical/`, retained permitted sources under `research/audio/AUD-16/recordings/`, and `tools/audio/import_mechanical.py`.
- Export: `app/export_presets.cfg` includes mechanical provenance and license notices alongside imported audio.
- Verification: `app/tests/test_mechanical_*.gd`, `tools/audio/mechanical_probe.gd`, `tools/audio/mechanical_benchmark.gd`, and mechanical telemetry in the existing gameplay/parity probes. `tools/audio/check_pack.gd` checks the actuator bank in exported resources.

Use the [audio tool guide](../tools/audio/README.md) and [checked Godot runner](tools/shared.md#one-godot-script). Do not regenerate flight goldens: this change introduces no intentional flight-physics change.

## Remaining limits

The named standard servo recordings establish source identity; a profile name alone does not establish torque/load equivalence. No identified, redistributable RC electric/pneumatic retract recording was found in the current search. The assembled retract cues use real recorded mechanisms and air, with source mismatches explicitly documented. Exact installed-device recordings, measured load curves, physical loudness calibration and human listening acceptance remain separate qualification work. The feature is implemented, but the requested premium fidelity and whole-flight performance bar is **not yet fully qualified**.
