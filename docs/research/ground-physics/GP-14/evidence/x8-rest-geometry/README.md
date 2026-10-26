# X8 lower-hull rest geometry audit

2026-10-26. Read-only qualification of the existing generated crash hull through
`AircraftData.ground_support`, using its authored LE coordinates and derived CG.
The generator's `--check` reports both aircraft records current. Ideal-bus and
6S-pack records have identical complete hull and inventory objects. No aircraft,
force, damage or statistics resource changed.

The selected stable facet with the largest CG margin contains `probe_belly`,
`probe_engine` and `probe_elevon_left_te`. Static shares are approximately
0.667447, 0.329773 and 0.002781; the CG polygon margin is only 2.445 mm. The normal
implies roll -0.05609146 rad and pitch 0.04892090 rad, with CG height 43.596 mm.
The retained JSON includes all 28 exact hull coordinates, CG, normal and result.

This is a rigid support-facet diagnostic, not a compliant equilibrium, time-domain
landing, propeller-clearance analysis or physical measurement. It does not prove
that this facet is the only attainable rest state. In particular, it supplies no
reason to call motor-mount or elevon contact an intended benign landing support.
The authoring extension must resolve the accepted support geometry/roles and
validate compliant continuation before granting stock X8 belly-landing credit.
Do not invent a benign rest pose or silently exclude existing collision points.

`geometry.gd` is the original checked probe; run through `tools/godot/run_checked.py`
with the root app and pinned Godot build. `source-identities.json` pins selected
original inputs rather than copying a complete project. The current optional
intended-hull-support contract and flight/damage rules remain unchanged.
