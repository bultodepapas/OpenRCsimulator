# Great Planes Extra 300S .60 (GPMA0236): visual geometry v1, preview

`.60` is the kit size (64 in span, .61 nitro class). The model is **flyable (experimental)**: its flight data `app/data/aircraft/gp_extra_300s_60.json` is GENERATED from this geometry by `research/extra-300/ex05/derive_physics.py` (owned by the physics/catalog line).

Edit [geometry.json](geometry.json). Coordinates are metres, +X right, +Y up, −Z nose. The origin is the nominal CG station (4-1/8 in aft of the rib-2D leading edge) at spinner-axis height. The physics CG is set separately in EX-05. Every group records its evidence kind; measured values come from [the EX-01 metrology](../../../research/extra-300/ex01/metrology.json), and estimated ones (gear track, pant width, propeller, section corner rounding) say so.

From the repository root:

```bash
python3 assets/aircraft/extra-300s-60/compile_geometry.py           # writes app/aircraft/extra_300s_geometry.gd
python3 assets/aircraft/extra-300s-60/compile_geometry.py --check   # stale copy, structure, and 197 values vs metrology.json
python3 assets/aircraft/extra-300s-60/compile_appearance.py         # writes app/aircraft/extra_300s_appearance.gd (--check in CI)
python3 research/extra-300/ex01/measure.py --check                  # needs the local plan/manual PDFs in references/
research/extra-300/ex02/capture.sh                                  # needs xvfb-run: 85 renders + review/ (metrics, sheets, local plan overlays)
python3 research/extra-300/ex05/derive_physics.py                   # REQUIRED after changing wing.*, tail.*, gear axles/track/wheels,
                                                                    # spinner, firewall_z, cowl_rear_z, propeller.z, canopy.top or fuselage_stations (CI runs --check)
app/test.sh                                                         # includes aircraft/verify_extra.gd
```

The [native builder](../../../app/aircraft/extra_300s_model.gd) keeps the Stik interface: `build()` → `{root, propeller, hinges, gear}` with `airplane`, `propeller` and `*_hinge` nodes. The swept aileron hinge is carried by a static `aileron_frame_*` parent, so `render/airplane.gd::apply_surfaces()` works unchanged. The report is [extra-300-model-v1.md](../../../docs/research/extra-300-model-v1.md).

The plan PDFs, manual, photos and CAD stay in the ignored `references/extra-300/`. Measured coordinates, code and selected captures are in the repo. Geometry and colours are original work, not copies of plan artwork.

**Finish (EX-10a).** [appearance.json](appearance.json) holds the red/white/blue scheme adapted from the owner's photo (top, sides) and the .40 underside photo: colours, bands, stars and stripes in metres or chord fractions, labelled as an artistic estimate. [extra_300s_finish.gd](../../../app/aircraft/extra_300s_finish.gd) draws it with one shared shader per part from model-space UVs written by the builder. The upper surface reads red/white, the lower one blue/white; `review.py` measures that from the ground. Results: [visual review](../../../docs/research/extra-300-visual-review-v1.md).

**Articulation, propeller, pilot (EX-04).** Elevator and rudder hinge edges carry a 45° V-bevel, like the ailerons. [extra_clearance.gd](../../../app/aircraft/extra_clearance.gd) checks every moving surface against its neighbours at the manual throws and at 45°. The propeller is a twisted 12×8 stand-in. The pilot comes from the plan's figure and sits under a tinted transparent canopy (`appearance.json` → `canopy.alpha`; 1.0 = opaque fallback).
