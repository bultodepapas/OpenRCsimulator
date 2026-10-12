# RC smoke: engine exhaust and auxiliary pump

2026-10-12 · Revision 3 · Step prefix: **SM-**

**Status:** research and implementation plan only. No smoke system is integrated in the app. SM-00 is the first step and must resolve Compatibility particle behavior before runtime integration.

**Owns:** future smoke rendering and auxiliary input work after the model, UI and M5 wind interfaces are agreed. Research stays in [rc-exhaust-smoke](research/rc-exhaust-smoke.md) and [smoke investigations](research/smoke-investigations/README.md).

## Intended behavior

The initial visual feature is a light exhaust trace from the glow engine. A separate auxiliary radio control starts a denser white aerobatic smoke stream. Turning the pump off stops new particles; smoke already in the air fades naturally. Smoke is presentation only and cannot alter flight physics or traces.

## Technical constraints from research

- Probe Godot 4.7.2 GPUParticles3D with the Compatibility renderer before adding dependencies or a custom particle history.
- At 30 fps and 40 m/s the emitter moves about 1.33 m each frame. A prior isolated probe showed gaps for small quads. SM-00 must compare point births with native emission distributed along the travelled segment; ordinary visual interpolation is not proof of a continuous trail.
- Verify pause, restart, deterministic seeds, transparency order and particle aging while the emitter is fully off camera. A correct visibility AABB alone does not prove off-screen processing.
- Keep the auxiliary assignment separate from AETR, preserve it through radio recalibration and profile changes, and test it with the fake radio before a real-radio review.
- The future wind response must use the shared M5 service for old and new particles. Do not invent a second wind clock.
- Keep the smoke mask small and reproducible first. Add depth fading or a custom birth shader only if a rendered probe shows the native material is insufficient.

The recorded emitter tests and off-camera processing questions are in [investigation 02](research/smoke-investigations/02-clock-captures.md), [moving-emitter results](research/smoke-investigations/03-moving-emitter.md), [radio AUX](research/smoke-investigations/07-aux-radio.md), [pump behavior](research/smoke-investigations/08-pump-behavior.md), and [wind advection](research/smoke-investigations/09-wind-advection.md). The full tool/API/license survey remains in the [investigation index](research/smoke-investigations/README.md).

## Small steps and proof

| Step | Work | Status / proof required |
| --- | --- | --- |
| SM-00 | Scratch Compatibility probe: moved emitter, timing, pause/reset, off-camera aging, transparency and seed behavior. | Not started. Record the exact engine/backend and a rendered result before choosing the implementation. |
| SM-01 | Add a validated exhaust anchor to the aircraft model interface. | Not started. Verify the mouth position and direction across supported attitudes. |
| SM-02 | Integrate the subtle engine exhaust tied to engine RPM. | Not started. Test idle, cruise, full power, glide, pause and reset in Home and flight. |
| SM-03/04 | Add pump state, then map it to an assigned AUX axis/button. | Not started. Pump off stops births; fake-radio tests cover assignment, reversal, reconnect and persistence. |
| SM-05/06 | Add reproducible trail captures and tune appearance/intersections. | Not started. Equal tick/seed repeats; airplane/smoke masks remain separate; keep the simplest material that passes. |
| SM-07/08 | Measure culling, memory, release performance, provenance and clean export. | Not started. Include off-screen processing and repeated reset checks on supported platforms. |
| SM-09 | Add wind or other extensions only when separately justified. | Later work; depends on M5 wind and new evidence. |

SM-02 is the first useful exhaust-only delivery. The full requested pump and real AUX experience is not complete until SM-08. Every future step needs its own proof; do not report a probe as an integrated flight feature.
