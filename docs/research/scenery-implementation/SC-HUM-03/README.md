# SC-HUM-03 — Field people follow the aircraft with their heads

Status: **implemented, software-verified, 2026-10-24.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md).

## What changed

The 13 LU-21 people turn their heads toward the player's aircraft. Pilots on the flight line stay coupled to it. Spectators, veranda visitors and pits members hold still until it leaves a seeded dead zone, then follow it. Heads return to rest when the aircraft is behind them or out of a seeded range. No asset was regenerated, and draw calls, triangles and textures are unchanged.

| Part | File |
| --- | --- |
| Head state per person: fixed 1/120 s steps of simulation time, critically damped follower with a rate limit, coupled or step-and-hold mode, yaw/pitch limits, rear gate, range, anticipation lead, seeded variation | [people_gaze.gd](../../../../app/scenery/people_gaze.gd) |
| Neck pivot and weight band derived from each posed mesh (eye proxy height, cranium centroid); role per placement zone; per-person metadata | [population.gd](../../../../app/scenery/population.gd) |
| Rotate head and neck vertices by angle × weight around the pivot, normals included; yaw in `INSTANCE_CUSTOM.w`, pitch in instance `COLOR.a` | [population_person.gdshader](../../../../app/scenery/population_person.gdshader) |
| Zone passed to the population batch | [scenery.gd](../../../../app/scenery/scenery.gd) |
| Model built with the field unless scenery quality is `low`; `advance_people` per simulation tick, `update_people` per frame | [field.gd](../../../../app/render/field.gd), [main.gd](../../../../app/main.gd) `_advance_windsock`, [world.gd](../../../../app/render/world/world.gd) `update` |

Render-only: the model reads the aircraft position from the simulation tick and writes only MultiMesh instance data. Scripted routes do not connect the tick consumer, and nothing is written before the first tick, so Home, scripted captures and golden flights keep zero head angles; the shader leaves every vertex with zero angle or zero weight untouched, so their geometry is exact. The Low Scene detail level, which Automatic selects for software renderers, keeps people static.

## Verification

| Check | Result |
| --- | --- |
| `tests/test_field_people_gaze.gd`, headless | PASS. Head mask on the real poses: eyes, eyebrows and hair turn rigidly; shoes and transmitter never move; body below the neck band is fixed; ≤6 % of clothing vertices (the collar) move. Pilot settles within 1° and tracks a crossing aircraft within 6°; rate limit holds; step-and-hold, rear gate, clamp, range, determinism, desynchronisation (>3° between two spectators), 60 Hz vs 240 Hz updates (<0.5°), pause (repeated timestamps) and backward-time reset. Default scenery roles: 2 pilots, 5 pits, 6 spectators |
| Same test, native under Xvfb + llvmpipe | PASS, including MultiMesh read-back of yaw and pitch on all 7 pilot parts |
| Existing regressions, headless | `test_landscape_population_assets`, `test_field_population_collection` (54/0), `test_landscape_population`, `test_scenery_build`, `test_field_projected_shadows` (59/0): all pass |
| Parse check of every changed script | pass |
| Rendered poses (scratch capture, 1920×1080, llvmpipe) | ±60° yaw, +35° and −15° pitch on standing, sitting and pilot poses; neck, collar and shoulders stay intact |
| Running app via the [debug bridge](../../../../tools/debug/README.md) (`OPENRC_SCENERY_QUALITY=high`, airborne Ugly Stik, 1920×1080) | Pilot heads rose 20–25° toward the aircraft at 30 m and swept from +19° to −50° as it crossed east; a 1080p close-up shows the head turned toward the aircraft with no mesh damage |
| CPU cost, 13 people, VM CPU | First version 21 µs per simulation tick (0.08 ms per 60 Hz frame). After the struct-of-arrays rewrite (2026-10-24) a 14 s scenario with companions, roster changes and a crash measures 16–17 µs per tick against 33–35 µs before, with a **bit-identical** SHA-256 over every head angle of every tick (`f8bc1763…`). The per-frame write only runs when angles change |

### Independent review (2026-10-24)

A read-only reviewer with no shared context found no blockers and four minor issues, all repaired the same day:

| Finding | Repair | Test |
| --- | --- | --- |
| The crash glance advanced behind the pause menu | Crash clock stops while the session has holds, as the crash director's aftermath does | Code path in `main.gd` (live check pending) |
| A restart with companions moved targets hundreds of metres in one tick, read as ~1,300 m/s; the pilot held rest for ~0.3 s and overshot ~6° | Moves faster than 200 m/s restart the target without velocity | `a teleported target restarts without a velocity spike` |
| No hysteresis at the rear gate or range limit: a hovering target swept a pilot's head between −5° and 67° | Latched behind/out-of-range flags with exit thresholds (gate − 60 % of the margin, 90 % of the range) | `no head sweeps while the target hovers at the rear gate` |
| "Scripted captures unchanged" was inaccurate: `configure()` wrote seeded rest angles and the shader was not bit-exact at zero | No writes before the first tick; the shader skips zero-angle instances and zero-weight vertices | Claim corrected above |

Also adopted: non-finite times are ignored instead of freezing the model; the people's culling box grows 0.15 m for the turning head; a CPU mirror of the shader rotation (`Population.head_rotate`) checks the yaw/pitch signs on the real eyes of all three poses; a person with a non-zero heading is tested. Not adopted: heads look at the crash point (as the crash camera does), not at the tumbling wreck body. The scenario fingerprint changed with these intentional fixes (`b491828c…`) and repeats across runs; cost 18 µs per tick.

Captures were reviewed but not committed (repository image rule). Reproduce them with `capture_heads`-style scratch scripts or the debug bridge commands above.

## Limits

- No crash glance yet; the shared field-event signal (plan §4.2) is still open.
- Only the player aircraft is a target; companion pilots are SC-HUM-04.
- The VM numbers are not performance qualification. Frame cost on the owner's GPU, and the owner's judgement of amplitude and lag, are still required (SC-HUM-09).
- Human-factors constants are estimates within the survey ranges (H1–H3, H10), not measurements of club spectators.
- The current shirts carry the MakeHuman logo; replacing clothing is SC-HUM-07.
