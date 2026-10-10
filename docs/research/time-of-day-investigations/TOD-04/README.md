# TOD-04 — Shadows and existing field materials

Status: implemented; focused and rendered checks pass, 2026-10-10. Parent: [time-of-day plan](../../../TIME-OF-DAY-PLAN.md).

Aircraft projected shadows multiply existing opacity by available sunlight and a smooth low-angle fade. With no direct Sun, the physical shadow is hidden. The existing bounded projection remains; it is an approximation near the horizon. The explicitly selected vertical height aid retains its separate semantics. Capture diagnostics use the same bounded projection direction and guard horizon division and report an unavailable solar shadow rather than an infinite location. A stable alternate up vector handles a zenith Sun.

`FieldBuilder.build(field, lighting)` passes the selected snapshot to ground/grass and the optional scenery hook. Scenery builds directional shadow batches using that Sun, weights their opacity, and omits them at night. Contact cues use black unshaded tint for astronomical lighting: the legacy grey tint could brighten a dark surface. Legacy contact cues retain their original appearance. Scenery remains opt-in. Selection is static, so no field reconstruction occurs while flying.

Aircraft geometry, hinges, generated materials and physical data remain unchanged. The fleet's noon/night captures and real field tests are in [TOD-07](../TOD-07/README.md). This is not an implementation of dynamic scenery shadows, field lamps or night-equipped aircraft.
