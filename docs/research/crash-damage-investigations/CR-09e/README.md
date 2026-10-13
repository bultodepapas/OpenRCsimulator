# CR-09e/f · physical parts, broken structure and bare wood (Ugly Stik first)

2026-10-13, at the owner's request ("improve how it breaks apart … inside should be balsa wood, more parts: ailerons…"). The work is software- and render-reviewed on llvmpipe; owner review on the target host is still open.

## What was wrong

A C4 nose-in of the Stik (15 m/s forward, 7 m/s down, grass; [before](before-c4-overview.png)) produced the following:

- Intact factory parts with clean cuts: both wing halves, the tail, the engine and the propeller.
- An untouched fuselage.
- The main and nose gear flying off as one rigid V on a single box.

Real built-up sport models snap behind the wing, splinter at their breaks, show bare balsa, and shed control surfaces and wheels.

## What changed

| Step | Change | Where |
| --- | --- | --- |
| CR-09e | **Parts by contact:** same-kind members whose boxes touch (2 cm) form one body, and the rest become separate bodies (main strap with its wheels, nose leg, tail skid). Each part takes its kind's weight by box volume, so mass is not doubled, and a C2 releases only the part nearest the contact. | `render/crash/wreck.gd` `_connected_members`, group `key`, `_key_share` |
| CR-09e | **Tail boom:** a new `tail_boom` kind. The Stik's fuselage section map splits the wreck twin at the first station aft of the wing trailing edge (z = 0.317 m); the flying mesh never changes. A C3 tail hit releases the boom. | `ugly_stik_model.gd` `FUSELAGE_BREAK_STATION`, `wreck.gd` release rules |
| CR-09e | **Builder meshes in section maps:** `section_splitter.gd` accepts non-indexed meshes, using the sequential index, which is exact for SurfaceTool output. | `_triangle_index` |
| CR-09e | **Hidden fracture detail:** `meta crash_reveal = kind` keeps a node invisible until that section breaks away; reset hides it again. The Stik ships end grain and seeded balsa splinters with torn film on both sides of the fuselage break, and spar, leading-edge and trailing-sheet stubs at each wing root, at the plan-traced chord stations. | `wreck.gd` `_reveal`, `aircraft/ugly_stik_fracture.gd` |
| CR-09f | **More parts:** new explicit-only kinds `aileron_left/right`, `elevator`, `rudder` and `wheel`, nested inside their parent section. The Stik marks its hinge pivots and wheel pivots; other aircraft keep their earlier, coarser breakup. | `_collect_nested_explicit` |
| CR-09f | **Attached parts ride along:** under `CARRIERS`, a released section carries the parts fixed to it whether or not they were struck — the boom carries stab, fin and both hinged surfaces; stab → elevator; fin → rudder; wing half → aileron; leg → wheel when their boxes touch. Masses add up. C4 destroys every joint. C2 hits on an aileron, elevator or rudder tear off only that surface. | `_carry_attached`, `_release_kinds_for` |
| CR-09f | **Bare wood inside:** a balsa lining runs the whole fuselage, shrunk by each wall's sheet (1/4 in sides, 1/8 in top, 3/32 in bottom), as its own mesh so the skin stays the solid that clearance tools probe. The wing root caps are balsa root ribs. Torn CA hinge strips (1 in, seeded side, ragged edge) appear on the hinge line of every surface that tears off. | `ugly_stik_model.gd`, `ugly_stik_fracture.gd` |

## Evidence

- [After, C4 overview](after-c4-overview.png): both ailerons, the elevator, rudder, fin and stab, the boom, the three wheels, the gear strap, engine and propeller come off separately, and both fuselage ends show wood.
- [C4 fuselage break](after-c4-fuselage-break.png): balsa lining, end grain and splinters on both pieces, with pushrods pulled out of the front piece.
- [C4 wing root](after-c4-wing-root.png): balsa root rib, spar stubs and torn film.
- [C3 tail hit](after-c3-tail-hit.png): the boom snaps and rotates away with stab, fin and surfaces as one body.
- [Hashes](SHA256SUMS). Bench: [`research/crash-damage/cr-09e/crash_bench.gd`](../../../../research/crash-damage/cr-09e/crash_bench.gd).

Tests:

- `app/tests/test_crash_fracture.gd`, 24/0, on the real Stik:
  - hidden detail in flight, and the flying fuselage stays one mesh with a lining that splits with it;
  - balsa root rib; three gear parts and three wheels; weight shares sum to 1;
  - C3 tail carries four parts; C3 wing carries its aileron; C2 gear releases only the nose leg with its wheel; C2 aileron releases only that aileron, with its hinges shown;
  - C4 frees and reveals everything, and reset hides it.
- `test_crash_breakup.gd` 30/0, updated to the new contract: expected sets include the parts riding along.
- `test_crash_wreck` 219/0, `masses` 27/0, `integration` 133/0, `sections` 33/0, `pose` 149/0, `snapshot` 42/0, `ladder` 41/0, `effects` 60/0, `wreck_surface` 10/0, `proportional` 49/0.
- `verify_model` 915/0; render contract, propeller blur, projected shadows and gear flex pass.
- Mutations on a disposable copy, 8/8 detected by `test_crash_fracture` (failures out of 24): no part clustering 3, no reveal 4, no carriers 3, C2 releasing every same-kind part 2, no nested sections 6, hinged surfaces not named 5, root rib painted 1, splitter requiring an index 1. The test fetches sections through `_first()`, so a missing section fails its checks instead of aborting the run.
- `test_crash_energy` keeps its 2 failures from the new glow data files (`stik_glow_*`), the same as on `HEAD` before this work.

## Limits

- Break stations, splinter lengths, film tears and hinge counts are seeded presentation estimates, not a fracture model. The boom always breaks at one station.
- A detached aileron's leading edge still shows the dark hinge-gap finish rather than bare wood.
- Wreck bodies still collide as boxes; CR-09d3 convex shapes remain the next physics step.
- Other aircraft gain the generic behaviour (part clustering, carriers, reveal), but only once their pipelines name the new sections.
