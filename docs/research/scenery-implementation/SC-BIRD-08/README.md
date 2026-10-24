# SC-BIRD-08 · Director, arrivals and departures, storks and swifts

2026-10-24 · Evidence for the second slice of the [birds plan](../../../plans/birds-sky-life.md), after [SC-BIRD-01…05](../SC-BIRD-01-05/README.md). Software evidence on the Linux VM's llvmpipe; not target-hardware performance and not the owner's Gate SC judgement.

## What changed

| Part | Where | Notes |
| --- | --- | --- |
| Director | [bird_director.gd](../../../../app/scenery/birds/bird_director.gd) | Share of each species out from the **true** solar elevation (`solar.elevation_deg`; snapshots clamp `sun_elevation_deg` ≥ 0.05° for the sky), morning or afternoon (solar hour angle), the rendered weather's cloud cover (`Atmosphere.cloud_state_snapshot()`; thermal soarers fade above `clouds_max`) and the scene-detail tier (low 0.5, balanced 0.75, high 1.0 [est]). Wildlife's day curve is kept, so the birds that call are the birds that fly |
| One topology per group | [bird_planform.gd](../../../../app/scenery/birds/bird_planform.gd) | Species of a MultiMesh share the group's finger slots and a three-triangle tail; each species' shape and rig weights sit in `CUSTOM0..3` (verified to reach `vertex()` in Compatibility). A bird draws only its own 35 (soaring) or 21 (small) triangles, instead of every species' triangles of the earlier atlas |
| Arrivals and departures | [birds.gd](../../../../app/scenery/birds.gd), [birds_runtime.gd](../../../../app/scenery/birds/birds_runtime.gd), [sky_birds.gdshader](../../../../app/scenery/birds/sky_birds.gdshader) | When its species stops flying a bird leaves over its departure time on `sim_clock` (vultures and storks glide 600 m away in 75 s, kites 400 m in 60 s, swallows 300 m low in 40 s, swifts climb 350 m in 150 s), and arrives the same way; a bird on its way turns round where it is; a start a moment ahead or after a rewind waits instead of finishing. A sun jump over 2° between commits, or an animation that would exceed the budget, snaps. Birds away are not drawn (`visible_instance_count`); the runtime node settles finished transitions (none replays at the 1024 s wrap) and re-runs the director when flowing time moves the sun or the weather changes the cloud cover |
| New species | [birds.json](../../../../app/data/scenery/birds/birds.json) | **White stork** in the vultures' thermal (mixed kettle): 6 birds, 5.5 turns of 1024/75 s at r 18/20/23 m, climb 0.92 m/s, glide 14.9 m/s (Weinzierl 2016 Table 1: 20.3 m, 13.65 s, 0.92 m/s); wingbeat 3.14 Hz measured. **Common swift** screaming party over the club in the evening (sun −1…8° and afternoon): 12 birds at about 19–29 m, 8–11 m/s (Hedrick 2018: 9.7 ± 1.4 m/s) |

## Checks

| Check | Result |
| --- | --- |
| [test_birds.gd](../../../../app/tests/test_birds.gd) | 309 checks pass, among them: real time-of-day snapshots (night and dawn: none; noon: vultures, storks, kites, swallows, no swifts; evening at sun 4.8°: swifts and swallows, no vultures; morning at the same sun: no swifts); overcast noon: no vultures or storks; low detail: half; transitions continuous (largest step < 0.8 % of the way per 0.1 s, turning round included), easing in from any fraction of a second and at the clock wrap, settled to flying or away; a noon-to-evening jump snaps within the budget; the runtime follows a flow-state sun; low detail draws about half the birds; **drawn primitives ≤ 1,000 at every sun elevation, morning and afternoon, clouds 0/0.7/0.95, with birds still on their way from ±1° of sun (worst 805)**; every bird stays out of the flight box and 30 m from the pilot on its circuit and along its way out; shared topology and per-species shapes in CUSTOM0..3; per-species colour, gait, departure and rig uniforms hold their data |
| [check_birds.py](../../../../tools/scenery/check_birds.py) at 1920×1080, noon and 17:48 | 14 views, earliest and latest flying bird of each flock: all drawn 1.9–4.9 px from the CPU prediction. Noon: 17 soaring + 10 small birds drawn; evening (sun 4.8°): 1 kite + 21 small. Mean bird colour at noon: storks (229, 233, 234), vultures (96–119), kites (81–95), swallows dark. Repeats and second processes byte-identical |
| [lifecycle_check.py](../../../../tools/godot/lifecycle_check.py) `--scenario flight --cycles 4`, birds on | Passed: no node, orphan, object or resource growth over Home → flight → Home; no shutdown leak warnings |
| Regressions | `test_time_of_day_scenery_update`, `test_scenery_build`, `test_landscape_scenery_grass_mask` pass; GDScript warnings clean in the bird scripts |

Reproduce: `"$(app/tests/visual-env.sh)" tools/scenery/check_birds.py --app app --godot "$(app/get-godot.sh)" --out tmp/<new>` (about 8 min) and the unit test command in its header.

## Independent review

A second read-only review (Good Enemy role) confirmed the half-float exactness of every state over 400,000 random cases, the turn-round symmetry, the still-clock settle, the buffer reorder and the culling boxes, and found these defects, fixed before this record:

| Finding | Fix | Check |
| --- | --- | --- |
| A start rounded up to 0.25 s ahead read as `mod(clock - start, 1024)` ≈ 1024 s, so about half of all transitions popped | Clock difference wrapped to ±512 s and clamped at 0 (CPU and shader) | Starts at 100.2, 100.3, 100.8, 511.6 and 1023.8 s ease in |
| A time-of-day jump (paused edit, restore) animated every bird at once: 1,057 primitives | Snap when the sun moves > 2° or the animation exceeds the budget | Noon → evening jump test |
| Snapshot `cloud_coverage` is a fixed constant; the rendered cover never reached the director | Read `Atmosphere.cloud_state_snapshot()`; the runtime follows its changes | Overcast test with the cover override |
| Flowing time updates `Atmosphere.state` without committing lighting, so swifts kept flying into the night | Runtime re-runs the director when the flow sun moves 0.1° | Flow-state test |
| A restore commits lighting before the clock: transitions started at the pre-restore clock | Covered by the wrapped difference (waits) and the jump snap | — |
| Tests: "none vanishes" counted drawn slots; loose continuity bound; low detail checked shares only | Departure share read per bird; bound 0.008; drawn counts compared | — |
| No limit on departure speed or birds per group | ≤ 30 m/s; ≤ 32 birds per group | Mutations |

## Efficiency round

Measured before changing anything, then one change at a time ([bench_birds.gd](../../../../tools/scenery/bench_birds.gd): the bird layer alone at 1920×1080, 20 copies, pilot-eye camera, best of 3–4 alternating rounds; llvmpipe on the shared VM, so it ranks versions on this machine only).

| Change | Before → after | Evidence |
| --- | --- | --- |
| Indexed group mesh: corners identical in every attribute (all species' shapes, weights, shade) share a vertex | 105 → 69 vertex-shader runs per soaring bird, 63 → 25 per small bird | Test: every corner keeps each species' attributes |
| One track evaluation per vertex instead of five: analytic heading on the tangent-continuous segment; bank from the lateral acceleration averaged with the same ±0.8 s triangle kernel, integrated exactly over the segments (no trigonometry) | 5 lookups + 5 positions → 2 lookups, a ≤ 8-segment walk, 1 position | Tests: bank exact (`atan(v²κ/g)`) inside arcs, roll continuous across joints, the float32 shader copy within 0.00005 m/s² of the float64 reference |
| Segment lookup by motif repeat (every repeat lasts period / repeats): search ≤ 7 segments instead of up to 25 | Swallow circuit 25 → ≤ 5 iterations | Shader tables test over 0–2048 s |
| GPU, combined (same process, old shader `be42c196` and de-indexed mesh vs current) | **1,090–1,096 → 578–675 µs per layer copy** (−38…−47 %; the spread follows the machine's load) | Bench rounds above |
| Exact track bounds (segment ends and the arc points where the heading crosses a multiple of 90°) instead of sampling every 0.25 s | Data validation and compile ≈ 45 → ≈ 5 ms; `Birds.build` ≈ 50 → 11–15 ms (headless, loaded machine) | Test: exact bounds hold every 0.05 s sample and are within 0.1 m of it |

Behaviour change, deliberate: the bank is now the true lateral acceleration. The old second difference of positions shortens it on tight turns by the chord factor 2(1 − cos θ)/θ² (swift 6 m turn: 42.6° instead of 45.2°). Positions are unchanged: the 1080p capture still draws every bird 1.9–4.9 px from the CPU prediction (14 views). `MIN_SEGMENT_S` is now 0.25 s and a motif has at most 16 segments, so the shader's fixed loops hold.

Unchanged and already cheap: `apply_lighting` ≈ 80 µs per commit, the runtime's `poll()` ≈ 4 µs per frame, `test_birds.gd` ≈ 3–4 s (309 checks).

## Measured renderer facts

- **MultiMesh custom data is a truncated half float in Compatibility.** A probe read back 1000.3 as 1000.0, 100.3 as 100.25 and 1.6 as 1.5996. Every custom value is therefore exact in a half float: time offsets in whole half-seconds, hashes in 1/1024 steps, `track + 8 · species`, and states (1500 flying, 2000 away, 0…1023.5 leaving since, −1024…−0.5 arriving since). Recorded in [LEARNINGS](../../../learnings/models-and-rendering.md).
- Mesh `CUSTOM0..3` attributes (RGBA float) and `inverse(mat3(MODEL_MATRIX))` work in the Compatibility vertex shader (native opengl3; the web export is not checked).

## Correction to SC-BIRD-01…05

The first slice's colour tables never reached the shader: `(pair[0] as PackedVector4Array).append()` appended to a temporary copy, so `color_top`, `color_under` and `color_tip` were zero and every bird rendered black, tinted only by fog. Its record's "two-tone underside / species colour" claim was therefore wrong. Fixed here, with a test that reads the uniforms back; the GDScript lesson is in [LEARNINGS](../../../learnings/runtime-and-delivery.md). The underside now takes the sun on the wing's upper surface at 0.6 of its colour [est], so a white stork reads white with black flight feathers from below.

## Observations and limits

- An exit warning "4 ObjectDB instances were leaked" appeared in 3 of about 26 headless 3 s flights with birds and in none of 19 without; six `--verbose` runs and the lifecycle check were clean, so the objects are not identified and the cause is not attributed.
- Not checked: the web export, Windows, target hardware, the owner's look; storks' black secondaries are only partly dark (the shade ramp is shared by all species).
- Seasons (D9), rain and storms (no weather input reaches the scenery), kettle drift with the mean wind and the exclusion cone (SC-BIRD-09) remain open.
