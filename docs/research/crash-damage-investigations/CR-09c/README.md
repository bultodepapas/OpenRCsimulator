# CR-09c / TT-13c — Real-part breakup for Blender-imported models

2026-10-13 · **Status:** implemented. The Timber section map awaits owner overlay review. **Serves:** [crash realism plan](../../../plans/crash-realism.md), [Timber plan](../../../TIMBER-INTEGRATION-PLAN.md) TT-13 (crash integration). Built on a read-only review of the r1 asset (probes kept in the session scratchpad, summarised below).

## The problem

The Timber (r1, the first Blender import) flies as one merged `airframe` mesh: 9 material surfaces, 36,691 triangles. The author's exporter joins its 43 CAD parts (`r1/source/scripts/exporta_juego.py`). Only nodes are breakable by name, so the wreck found just the propeller, elevator, rudder and wheels. Since CR-09b, a C3 wing-tip hit on a model without wing sections released **nothing**.

## For any imported model (CR-09c, crash track)

1. **Explicit sections from Blender.** [wreck.gd](../../../../app/render/crash/wreck.gd) `_section_of()` resolves a node's crash section in this order:
   - glTF extras `openrc_section`: a Blender custom property, exported with `export_extras=True` (the Timber exporter already sets this);
   - meta `crash_section`, set by a builder or the splitter;
   - the existing name rules.

   Valid values are `wing_left`, `wing_right`, `wing_center`, `engine`, `propeller`, `horizontal_tail`, `vertical_tail`, `gear`, `canopy` and `core`. A `core` node stays with the body but its tagged children can still break away. An unknown value is warned and ignored. **A new Blender model gets real-part breakup by setting one custom property per object**, and the flying model needs no code.
2. **Merged meshes.** [section_splitter.gd](../../../../app/render/crash/section_splitter.gd) replaces any twin `MeshInstance3D` that carries `meta("crash_section_map")` with one child mesh per section.
   - It uses whole triangles of the original surfaces, keeping materials, normals, tangents and UVs; nothing is cut, dropped or duplicated.
   - Only the wreck's hidden twin changes. The flying model is untouched.
   - A map that does not match the mesh is rejected before any change, with a warning, and the mesh stays whole.
3. **Never nothing.** Release sets keep only sections the model has; an empty C3 set falls back to the legacy wings-and-tails set (CR-09c1).

## The Timber (TT-13c, Timber pipeline)

[make_crash_sections.gd](../../../../research/timber/tt13/make_crash_sections.gd) runs headless on the Godot-imported asset:

1. It welds each surface into shells (107 whole CAD shells).
2. It classifies each shell's centroid by rules measured in `TimberGeometry.DATA` (TT-02):
   - **canopy:** glass;
   - **wing halves:** outboard of `fuselage_half_width_at_wing` inside the wing chord band ±5 cm;
   - **fin / stab:** within 5 cm of the centreline and above the fin root → fin; outboard → stab;
   - **engine:** forward of half the cowl-front station;
   - **core:** everything else.
3. It writes the generated [timber_crash_sections.gd](../../../../app/aircraft/timber_crash_sections.gd): 41 runs, 1.8 KB, tied to the GLB SHA-256, with `--check`.

[timber_model.gd](../../../../app/aircraft/timber_model.gd) `_tag_crash_sections()` is meta only. It attaches the map when the GLB hash matches, and names the aileron and flap pivots with their wing and the gear pivots as gear.

| Section | Triangles | Shells |
| --- | ---: | ---: |
| wing_left | 10,353 | 30 |
| wing_right | 10,322 | 30 |
| horizontal_tail | 2,940 | 14 |
| vertical_tail | 1,602 | 7 |
| engine | 3,760 | 6 |
| canopy | 632 | 4 |
| core | 7,082 | 16 |
| **total** | **36,691** | **107** |

**Overlay review** ([top](timber_sections_top.png), [side](timber_sections_side.png), [front](timber_sections_front.png); rendered by [capture_sections.gd](../../../../research/timber/tt13/capture_sections.gd) under xvfb/llvmpipe):

- Both wing halves are clean, with their ailerons and flaps.
- The stab and the fin/rudder are separate; the glazing is canopy; the gear legs and wheels are gear; the propeller is separate.

**Known limit.** The cowl skin was welded into the fuselage shell by the author's `remove_doubles`, so only the forward cowl details form `engine`, and the cowl stays with the body. This is r2 request: per-section objects with `openrc_section` and a separate cowl.

## Evidence

- [test_crash_sections.gd](../../../../app/tests/test_crash_sections.gd): **33 checks**.
  - **Synthetic merged mesh:** sections become groups, the flying model is unchanged, triangles are conserved, there is one surface per material, the region is correct, UVs are kept, the result is deterministic, and a bad map is rejected with nothing changed.
  - **Resolution:** extras, meta on a hinge, a `core` parent with a tagged child, an unknown value.
  - **No-wing fallback regression.**
  - **Real Timber:** 8 real sections; the left wing carries aileron and flap; all 36,691 triangles are in the twin's sections; the flying model keeps its merged airframe. A C3 left-tip hit releases exactly `wing_left`.
- **Unchanged checks:** `verify_timber` (296), `test_timber_data`, `test_crash_wreck` (163), `test_crash_breakup` (27), `test_aircraft_catalog` (43), `test_crash_integration` (95), and `make_crash_sections.gd --check`.
- [Mutations](../../../../research/crash-damage/cr-09c/mutations.log): **9/9 killed** — sections the model lacks kept in release sets, extras ignored, `core` stopping the search, splitter never run, last run dropped, validation skipped, materials lost, hinges untagged, map not attached. The first run let the no-wing case survive, so the regression check was added.

## Limits and next steps

- Wreck collision stays one box per section; real meshes improve the picture, not the contact shape.
- The splitter runs once per flight load on the twin; its cost on the target machine is part of CR-22c.
- **r2 (author):** split the `airframe` role into per-section objects with `openrc_section` (and a separate cowl); then delete the generated map. Per-section objects raise the flying model's surface count (about 56 against the provisional ≤ 40), so either measure in TT-13 or keep a merged flight mesh alongside.
