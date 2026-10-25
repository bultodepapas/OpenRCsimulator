# Servo and retract audio — AUD-16

2026-10-25. Owner: audio. Parent: [audio guide](AUDIO-PLAN.md). Recording provenance and redistribution terms: [asset sources](audio-asset-sources.md).

## Contract and integration

Mechanical audio is a read-only presentation consumer. It does not change aircraft data, servo rates, flight commands, solver state, checkpoints or random numbers. Godot is the repository's pinned **4.8.beta1.official.4d10419ca**.

`app/audio/flight_audio.gd` reads accepted surface angles from `FlightSession.surface_angles_deg()`, the accepted flap fraction and maximum angle, and `gear_state()`. It supplies elapsed simulation ticks, actual angles/deployment, source positions, pause state, listener position and a smoothed engine masking gain. A changed stick or gear target alone cannot produce motion audio.

There are three conventional logical actuator channels: aileron, elevator and rudder, plus a flap channel where the aircraft simulates flaps. The two ailerons and split elevator hinges share the existing logical state; they do not become independent simulated servos. Sources follow the centres of their authored control hinges, with the aircraft root as a fallback. This approximates servo installation positions; it does not claim hardware mount measurements. Retract sound uses one source at the airframe root for the coordinated mechanism.

The actual viewport `AudioListener3D`, when present, supplies listening position; otherwise the flight camera does. PiP remains non-listening under the camera system's existing contract. Camera cuts do not create artificial mechanical Doppler sweeps. Existing engine, rolling-wheel, impact and environmental audio continue through their established routes.

`mechanical_motion.gd` observes accepted deltas and transitions. `mechanical_audio.gd` owns bounded spatial players, recording playback and envelopes. `mechanical_profile.gd` validates the closed presentation configuration. Missing recording resources fail silent rather than substituting generated buzzing.

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

Travel speed derives from angular displacement divided by accepted tick time. Motion duration gates recorded movement; speed changes the envelope and pitch. Starts, reversals and stops are separate from stationary state. No idle holding buzz is invented. The observer can carry an optional load field, but there is no load-to-sound mapping in this version: the flight model supplies no servo torque/current.

Electric retract playback uses motor/gear movement and endpoint cues. Pneumatic playback uses recorded valve/air textures and endpoint cues. The current gear law has an accepted deployment fraction and target with up/down endpoints; it has no air-pressure state, independently timed door state or lock sensor. Endpoint cues represent arrival at the model's accepted endpoint. There are no invented door events or pneumatic-pressure dynamics. Canopy, tailhook and wing-fold presentation animations are outside this initial logical actuator contract.

Engine masking uses accepted shaft RPM and installed engine family. Combustion idle receives a modest residual gain reduction; electric masking falls with shaft speed. This supplements the existing louder engine mix. Authored gain trims are not calibrated sound-pressure levels and cannot establish acoustic realism.

The bank contains 17 mono PCM16 cues, 429,074 decoded PCM bytes. Servo and electric textures use 44.1 kHz; air-only textures use 22.05 kHz. The two profiles use separate recorded servo sources, two onset/stop takes each, small deterministic gesture pitch/phase variation, and 35 ms attack / 85 ms release envelopes. The High-Torque profile uses a 0.82 pitch reference and a gentle 2 dB upper-shelf cut; those are authored treatments, not measured torque acoustics. The existing PCM loop wrap guard remains active; committed WAV imports disable QOA compression.

Spatial players feed the existing scene aggregate bus, outside the engine-only boost/filter chain. Manual gain is capped inside 2 m, follows inverse distance beyond it, fades from 39–60 m, and reaches zero at 60 m. Godot provides 3D panning without a second attenuation curve or mechanical Doppler. Outside audible range, the controller bypasses detailed motion observation and primes silently on return. Pauses, stalled ticks, rewind, reset, detach and reconfiguration retire voices. The bank fails silent if a required resource is missing.

There are at most six pooled movement voices and two transient voices. Only moving audible channels start a loop. Gear locks take priority over gear onset, then servo onset and servo tails. Same-source reversals and interruptions fade the old transient over 20 ms before replacement; a canceled gear movement clears pending cues. Under simultaneous corrections, lower-priority transient cues may be dropped while movement beds remain active. This avoids multiplying every surface's start click.

## Verification

Signal checks and deterministic state tests do not establish listening acceptance or physical sound calibration. Verification uses the pinned Windows Godot binary, Dummy for state tests and WASAPI for actual mixer captures. Results are summarized here; native and parity measurements are retained in `docs/research/audio/AUD-16/`.

| Check | Result |
| --- | --- |
| Motion observer | 20 checks passed: actual deltas, speed, reversal, endpoint, pause and rewind |
| Closed profile and migration | 24 checks passed: two types, finite level, v1–v3 identity, v4 JSON round trip, transfer |
| Recording/controller lifecycle | 89 checks passed: all four profile combinations, PCM assets, pooling, persistent loop playback, interrupted cues, priority, culling and missing-resource fallback |
| Real-scene integration | 26 checks passed: frozen Workshop profile, P-51 accepted surface/flap/retract movement, gasoline/electric RPM masks, listener fallback, reset and cleanup |
| Existing regressions | Workshop presentation 85, transfer 22, store 141, bundle 28, trial 44, drafts 100, soundscape 168, powertrain 45 and ground audio 33 checks passed; Workshop UI suite also passed |
| Physics parity | Nine fixed-wing aircraft: 1,200 paired ticks each, identical full checkpoints with audio on/off, including pause and reset. Rotorcraft explicitly excluded |
| Export | Windows PCK mounted from an empty project: all 60 audio resources checked, including 17 actuator cues, manifest and CC BY attribution |
| 1080p Workshop | Inspected live through the debug bridge. Profile/level selection, fixed-gear restriction, Undo/Redo, save and Test fly verified; high-torque/65% reached the flight controller. Clean shutdown: no leaked objects |

The four-combination native bench captured about 49.3 s at 48 kHz with zero discarded frames and no clipping. The final run's controller update p95 was 217 microseconds (maximum 395); measured peak was −25.14 dBFS. Playback stayed within six movement/two event voices, and bus count returned to baseline. These are shared-host controller measurements, not audio-thread deadlines or whole-game frame-time qualification.

An initial 20 s actual gasoline flight capture had zero discarded frames, silent pause, and a −21.53 dBFS peak. The older gameplay checker did **not** pass: total adapter p95 was 722 microseconds against its 500 microsecond gate, and the P-51 chase camera stayed at least 10.48 m away against that checker's fixed 4 m bound. These results prompted the distant-source observation shortcut and separate mechanical timing instrumentation; they do not establish overall performance acceptance. Subsequent captures and any outstanding integration limits are recorded with the evidence.

An initial Home render encountered an unrelated vegetation texture allocation/load failure. The inspected 1080p flight/Workshop used `--scenery=off`. Shared lighting edits temporarily caused parse/provenance failures during later full-scene checks; independent mechanical tests continued without altering those files.

## Files and reproduction

- Runtime: `app/audio/mechanical_profile.gd`, `mechanical_motion.gd`, `mechanical_audio.gd`, and the existing `flight_audio.gd` adapter.
- Configuration: `app/workshop/presentation.gd`, `profile_transfer.gd`, `store.gd`, `bundle.gd`, `trial.gd`, `draft_store.gd`, and `app/ui/workshop.gd`.
- Recordings: `app/assets/audio/mechanical/`, retained permitted sources under `research/audio/AUD-16/recordings/`, and `tools/audio/import_mechanical.py`.
- Export: `app/export_presets.cfg` includes mechanical provenance and license notices alongside imported audio.
- Verification: `app/tests/test_mechanical_*.gd`, `tools/audio/mechanical_probe.gd`, and mechanical telemetry in the existing gameplay/parity probes. `tools/audio/check_pack.gd` checks the actuator bank in exported resources.

Use the [audio tool guide](../tools/audio/README.md) and [checked Godot runner](tools/shared.md#one-godot-script). Do not regenerate flight goldens: this change introduces no intentional flight-physics change.

## Remaining limits

The named standard servo recordings establish source identity; a profile name alone does not establish torque/load equivalence. No identified, redistributable RC electric/pneumatic retract recording was found in the current search. The assembled retract cues use real recorded mechanisms and air, with source mismatches explicitly documented. Exact installed-device recordings, measured load curves, physical loudness calibration and human listening acceptance remain separate qualification work.
