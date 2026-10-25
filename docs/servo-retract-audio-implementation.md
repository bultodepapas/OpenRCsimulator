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

Travel speed derives from angular displacement divided by accepted tick time. Motion duration gates recorded movement; speed changes the envelope and pitch. Starts, reversals and stops are separate from stationary state. No idle holding buzz is invented. Optional load information can be consumed by the audio contract, but the current flight adapter supplies none because servo torque/current is not modeled.

Electric retract playback uses motor/gear movement and endpoint cues. Pneumatic playback uses recorded valve/air textures and endpoint cues. The current gear law has an accepted deployment fraction and target with up/down endpoints; it has no air-pressure state, independently timed door state or lock sensor. Endpoint cues represent arrival at the model's accepted endpoint. There are no invented door events or pneumatic-pressure dynamics. Canopy, tailhook and wing-fold presentation animations are outside this initial logical actuator contract.

Engine masking uses accepted shaft RPM and installed engine family. Combustion idle receives a modest residual gain reduction; electric masking falls with shaft speed. This supplements the existing louder engine mix. Authored gain trims are not calibrated sound-pressure levels and cannot establish acoustic realism.

## Verification

Verification results are recorded below after integration. Signal checks and deterministic state tests do not establish listening acceptance or physical sound calibration.

## Files and reproduction

- Runtime: `app/audio/mechanical_profile.gd`, `mechanical_motion.gd`, `mechanical_audio.gd`, and the existing `flight_audio.gd` adapter.
- Configuration: `app/workshop/presentation.gd`, `profile_transfer.gd`, `store.gd`, `bundle.gd`, `trial.gd`, `draft_store.gd`, and `app/ui/workshop.gd`.
- Recordings: `app/assets/audio/mechanical/`, retained permitted sources under `research/audio/AUD-16/recordings/`, and `tools/audio/import_mechanical.py`.
- Export: `app/export_presets.cfg` includes mechanical provenance and license notices alongside imported audio.

Use the [audio tool guide](../tools/audio/README.md) and [checked Godot runner](tools/shared.md#one-godot-script). Do not regenerate flight goldens: this change introduces no intentional flight-physics change.

## Remaining limits

The named standard servo recordings establish source identity; a profile name alone does not establish torque/load equivalence. No identified, redistributable RC electric/pneumatic retract recording was found in the current search. The assembled retract cues use real recorded mechanisms and air, with source mismatches explicitly documented. Exact installed-device recordings, measured load curves, physical loudness calibration and human listening acceptance remain separate qualification work.
