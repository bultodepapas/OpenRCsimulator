# Changelog — Turbo Timber Evolution game build

## r2 — 2026-10-13 (delivery specification revision 2)

### Kept from r1 (unchanged bytes of r1 are not touched; r1 lives in its own folder)
- All 14 pivot nodes: names, parents and rest transforms copied from `r1/export/aircraft.glb`
  (verified ≤ 0.1 mm / 0.01°, in fact identical). Local +X hinge axes, positive directions and authored ranges.
- Root `TurboTimberEvolution` at D0 with identity transform; the 10 material names.

### Changed
- **`airframe` removed and split** into sibling section meshes under the root: `fuselage_core`, `wing_left_fixed`,
  `wing_right_fixed`, `stabilizer_fixed`, `fin_fixed`, `cowl`, `canopy_glass` (r1 had them merged).
- **Crash sections**: string extra `openrc_section` on every mesh and moving pivot (root and `thrust_frame` untagged).
- **Cowl joint cut** at Blender y = +0.157 m (nose panel, fillet, stripes and exhaust plates split there).
- **Closure faces** at wing roots, cowl joint, stabilizer and fin: split off, plain foam colour, 0.2 mm inset.
- **Source geometry**: exterior solids from master v15 (closed foam shells, no hatch seam), fuselage/tail/wing
  markings from master v17 (thin skins; wing and tail markings trimmed to the skin outside the substrate),
  propeller rotor from v17 (10-size bell, corrected backplate). Interior structure and electronics of v16/v17 are
  excluded (`export-map.json`).
- **Markings as base colour** on wings and tail (spec: base colour preferred over decal shells): the foam part is split in
  CAD by its markings and each piece keeps its colour (no shells). Fuselage/cowl stripes stay thin single-sided shells,
  lifted 0.12 mm × priority and seated ≥ 0.1 mm above the foam.
- **Budget**: 42,519 triangles (r1 64,291) with deviation-bounded decimation (≤ 0.25 mm, colour borders locked);
  49 surfaces (r1 39: the section split adds primitives); backface culling on all materials.
- **Demo**: `control_demo` now moves one control at a time (r1 spun the wheels/propeller during the control
  blocks); flaps demonstrated at 0 / 20.7 / 36.6 / 40°.
- **Extras added**: `sim_range_deg_approx` on ailerons/elevator/rudder, `sim_flap_steps_deg` on flaps.
- **Metadata**: `sections` list; per articulation mesh members, section, authored and simulator ranges with sources,
  clearance envelope; mass ledger relabelled non-flight placeholder, manual reference 2.190 kg selected.
- **Verification**: new structural validator (`valida_glb.py`, pure Python) + Blender verifier (`verifica_r2.py`)
  with re-import consistency, sign and clearance sweeps, section separability, closures, z-fighting, demo timing,
  master-vs-game silhouettes; negative tests on disposable broken copies (`pruebas_negativas.py`).

### Measured differences (not rescaled)
- Span 1.5455 m (r1 1.5479 m): r2 uses the master v15 wingtip (r1 used v12).
- Length 1.1155 m (r1 1.1166 m): v17 spinner (−0.8 mm) and the rudder trailing edge is now the foam edge (r1 measured
  the marking shell).
- Main gear: the master v17 suspension pin sits 0.18 mm lower than the r1 pivot (z −90.526 vs −90.347 mm,
  CAD frame); the r1 pivot is kept as required, the difference is below any visible effect.
- Clearance reported (not clamped): flaps clear to 39° (wing contact at 40°); main suspension clear to 6°
  (wire link meets its foam bracket from 7°).

### Not changed / not supported
- CAD rebuild from the package is unsupported (master BREP caches not shipped); the tessellation output is shipped.
- No floats, no slats, no ground attitude, no textures, no cameras or lights.

## r1
First delivery (see `../r1/`).
