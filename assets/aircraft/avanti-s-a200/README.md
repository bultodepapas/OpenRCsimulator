# Sebart Avanti S (A200, 2.0 m span): visual geometry, preview

A **visual preview only** (AV-03): it is not flyable, has no physics data and no turbine propulsion yet. The shape is the AV-02 maquette, revision `a200-av02-contours-03`, unchanged. Only the span (2.00 m), length (2.22 m), JetCat P100-RX envelope and control throws are manufacturer nominal values; every section, chord, thickness, hinge and installation position is an `estimated_visual_blockout` (see `evidence` in [geometry.json](geometry.json)). Panels are thin solids, not airfoils.

Coordinates are metres, +X right, +Y up, −Z nose. z = 0 is the wing root leading edge beside the fuselage, projected onto the symmetry plane; y = 0 is the estimated wing mid-plane at the root (not a measured CG height).

From the repository root:

```bash
python3 assets/aircraft/avanti-s-a200/compile_geometry.py           # writes app/aircraft/avanti_s_geometry.gd
python3 assets/aircraft/avanti-s-a200/compile_geometry.py --check   # fails if the generated copy is stale
$(app/get-godot.sh) --headless --path app --script res://aircraft/verify_avanti.gd
```

[avanti_s_model.gd](../../../app/aircraft/avanti_s_model.gd) `build()` returns `{root, propeller, hinges, gear, has_propeller, data, ...}`: root `airplane`, an empty invisible `propeller` marker, `gear = {}`, `has_propeller = false`, and seven hinges (`flap_*`, `aileron_*`, `elevator_*`, `rudder`), each `{node, axis, rest, ...}`. `apply_surfaces(airplane, Commands.surface_deflections_deg(...))` poses ailerons, both elevators and rudder; `set_flaps(airplane, deg)` is the hook for a future flap step. Materials are shared between builds.

Limits: no aerodynamic or mass data, no swept-volume clearance check, approximate contours, no livery. Edit [geometry.json](geometry.json) (keep `revision` and `VISUAL_REVISION` in step) and regenerate; the AV-02 study it comes from is [research/avanti-s/av02/](../../../research/avanti-s/av02/), the plan is [docs/AVANTI-S-PLAN.md](../../../docs/AVANTI-S-PLAN.md).
