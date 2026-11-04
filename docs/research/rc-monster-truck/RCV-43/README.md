# RCV-43 — RC car circuit on the airplane field

2026-11-03. Airplane flights on the club field can show the RC car circuit and fly with its physics. The setting is **Settings > Display > RC circuit**: Automatic (default), On or Off. One decision per flight feeds the rendered dirt, the wheels' terrain and the collision world, so the circuit is never visible without its physics or the reverse.

## Design

- **Wheels.** `physics/ground_vehicle/airfield_track.gd` `composed()` adds the circuit to the field terrain sample. The aircraft wheel laws (`ground_wheels.gd`, `ground_contact.gd`) and the car course (`airfield_course.gd`) use the same arithmetic. On the dirt, tyre friction and rolling factors blend toward the circuit's `mu`/`rolling` by coverage, like the car course.
- **Hull.** Raised dirt at least 5 cm high (ramps, rollers, banked turns) is solid ground for crash-hull points. `flight_session.gd` `_rc_track_hit()` bisects the exact float64 surface along the scenery sweep interpolation and competes with flat-ground, lake and scenery hits by sweep fraction. Legacy ties keep their winners. The 3.5 cm pad stays with the flat-datum hull laws, so a hull point can sink at most 3.5 cm into pad dirt.
- **Obstacles.** The 5 walls, 3 tyre stacks, 4 signs, 2 timing posts, 2 tape spans and the timing cabinet join the collision world as 17 boxes (`AirfieldTrack.dressing()`). Walls are the course's exact boxes; the other boxes use measured source bounds. Tyres and tape use `frangible_impulse`; the rest use `hard_terminal`.
- **Identity.** The circuit identity enters the configuration hash, flight metadata, checkpoints (restores refuse a mismatch) and the flight-log header (`rc_track`, only when present). AI companions copy it from the player. The research native stage refuses a session with the circuit. With the circuit off, every contact path keeps its exact legacy arithmetic.
- **Scope.** Menu-launched airplane flights on the club field only. Traces, captures, tests and scripted runs never read the preference; `--rc_track=on|off|auto` (or `OPENRC_RC_TRACK`) requests it explicitly. Helicopters, the car activity and custom fields never receive it.
- **Automatic.** On for a dedicated GPU (Scene detail's adapter heuristic) at High or Extreme scene detail. Off for integrated, entry, mobile, software, unknown or absent GPUs and for lower scene detail.
- **Menu home.** The Graphics page has 7 px left at the 1920×1080 reference canvas. Sharing its Scene detail row wraps that label (page 719 px against a 700 px body), so the row lives on the Display page (372 px).

## Render optimization

The car activity keeps its tested 0.10 m layout. The flight build (`render/rc_track_field.gd`, `airfield_track_view.gd` profile `flight`) changes the following:

| Item | Car activity before | Flight build |
| --- | ---: | ---: |
| Dirt build, first flight | 2,428 ms (0.10 m grid, course sampler) | 416 ms (0.20 m grid, lean sampler) |
| Dirt build, later flights | 2,428 ms | 3.4 ms (mesh cache by circuit, surface and lake identity) |
| Dirt triangles | 142,920 | 35,080 |
| Dirt vertex buffer | 141,363 (unused rows at the origin) | covered vertices only; bounds stay on the circuit |
| Start grid and arrows | 13 draws | 2 merged paint meshes |
| Tyres | 8 mesh instances | 1 MultiMesh |
| Fine hardware and labels | always drawn, shadowed | culled beyond 30 m and 45 m, no shadows; props beyond 450 m |

Both profiles now keep the importer's LODs on the fitted concrete barriers and share identical furniture materials. A 0.20 m grid bounds the chord error on the 0.48 m tabletop to about 1.5 cm; the wheels still roll on the exact surface. Grass, imported near grass and runway-meadow plants are masked off the lane and the inner 60 % of its shoulder (28 polygons).

Measurements: Godot 4.8 beta2 headless (dummy renderer), Windows, this workstation. They establish CPU build cost and geometry counts only, not GPU frame time.

## Verification

- [`test_rc_track_flight.gd`](../../../../app/tests/test_rc_track_flight.gd): 60 checks. Checked areas:
  - The aircraft terrain equals the car course height and coverage exactly on a 141 × 177 grid.
  - Wheel compression and loads follow the bank.
  - Session identity, checkpoint refusal and restore.
  - The hull crossing on the tabletop deck, both direct and through the post-tick resolver.
  - The 17 proxies.
  - Every rendered dressing node matches its collision record.
  - The flight render budget and cache.
  - The Automatic rules.
- **Regression.** 151 of 152 related suites pass, including the golden flights. The suites cover ground, wheel and contact; landscape collision; lake; flight log; checkpoints; the RCV car activity; and the field build. The one failure is `test_companions_profiles.gd`: its profile pins the physics/sim source identity, which changed (90fb5ae1 → 880d1911).
- **Companion behaviour.** The nine retained companion tapes replay byte-identical CSVs (2,881 rows each) on HEAD's whole `app/` tree and on this change. The method is `rebind.py`'s `replay()` and CSV comparison with a whole-tree baseline. `rebind.py` itself cannot compile its baseline here: the accepted solver directories lack the new `AirfieldTrack` API that scenery and render code call. After this change is committed, the profile, `qualification.json` and a receipt still need re-pinning. Separately, `rebind.py` now copies `tools/release/macos_reference_receipt.py`, which `tools/flight_log/flight_log.py` loads at import; without it every baseline replay failed.
- **Native app, 1920×1080.** Windows, NVIDIA GeForce RTX 3090, `gl_compatibility`, `--rc_track=on --start=runway`, camera at the pilot's eye looking north at the circuit, flight paused.
  - Hiding the circuit node: 164 → 222 draw calls, 336,262 → 397,101 primitives (shadow passes included), 841 → 899 objects.
  - Frame time: 2.26 → 2.25 ms mean, p95 2.79 → 2.75 ms. The difference is within the noise of the 7,200-frame window.
  - The app exited cleanly with no leaked objects. The research native stage logged its refusal and the reference stage ran. That backend has no Windows binary, so nothing changes on Windows; Linux falls back to the reference stage while the circuit is on.

## Open

- One high-end GPU only. The scene budget (`tools/scenery/scene_budget.json`) has not been re-measured with the circuit, and integrated GPUs are unmeasured; Automatic stays off there.
- No flight-feel or physical validation of aircraft on dirt; the circuit's friction values are the car course's estimates.
- Hull contact with raised dirt is terminal (no sliding over it); belly slides over the 3.5 cm pad use the flat datum.
