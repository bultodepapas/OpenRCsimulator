# RCV-36 Nitro audio assessment

Date: 2026-10-15

The repository already contains `app/assets/audio/soundscape/motor_combustion.wav`, an MIT-licensed original procedural 100 Hz firing cycle. Its manifest records SHA-256 `bdec71c124bd227ed201fe3935202f23e21116e27d81c18c545533c4254b8392` and a 4x playback pitch factor. It is a generic repeating tone; it has no RPM, fuel, clutch, or tire-contact events, so the Nitro voice does not reuse it. No third-party recording was imported.

The new voice uses the local procedural glow voice's two-stroke cadence as a foundation: one exhaust event per crank revolution, with an authored harmonic envelope. The Nitro-specific renderer leaves out the aircraft propeller and uses accepted Nitro telemetry for throttle/fuel-flow level, engine RPM and running/fuel gating, signed clutch slip/torque, and grounded tire slip. The clutch partials are individually omitted above Nyquist. All partial weights and layer gains remain presentation estimates, not acoustic measurements.

`app/tests/test_rcv_nitro_audio.gd` verifies cadence, load response, startup/stall/fuel silence, pause/resume continuity, clutch and grounded-skid telemetry gates, finite/clipped output, 45,000 RPM partial safety, and generator bounds. The retained test and WAV evidence are in [RCV-36 audio evidence](../../../../docs/research/rc-monster-truck/RCV-36/audio/README.md).
