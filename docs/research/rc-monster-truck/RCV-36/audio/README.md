# RCV-36 Nitro audio evidence

The Nitro-specific procedural voice produces a two-stroke exhaust cadence from accepted RPM, throttle and fuel-flow telemetry. Signed clutch slip and torque drive the mechanical layer; tire skid requires wheel contact and tire slip. The voice gates all output when the engine is stopped or the tank is empty, and freezes its oscillator while paused. The bounded generator target is 50 ms in a 150 ms ring, with render requests capped at 4,096 frames.

The harmonic weights and layer levels are authored for presentation. This evidence validates the code path and PCM limits, not real-world acoustic accuracy. No third-party sample is included; the existing generic combustion WAV was inspected and not reused.

| Artifact | Result |
| --- | --- |
| `nitro_audio_test.log` | Godot 4.7.2 headless; 23 checks passed, 0 failed |
| `nitro_engine_preview.wav` | 4.0 seconds, 22,050 Hz, stereo, 16-bit PCM; peak 0.272766, RMS 0.091649 |
| `receipt.json` | Source, test-log, and preview SHA-256 values |

Run the focused suite from the repository root with:

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_rcv_nitro_audio.gd
```

See the [audio source assessment](../../../../../research/rc-monster-truck/rcv36/audio/assessment.md) for existing-asset selection and the presentation model.
