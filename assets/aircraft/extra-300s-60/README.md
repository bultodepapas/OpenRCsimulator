# Great Planes Extra 300S .60 (GPMA0236): visual geometry v1, preview

`.60` is the kit size (64 in span, .61 nitro class). The model is a **visual preview** (EX-02): it has no physics data, the app does not offer it, and it does not fly.

Edit [geometry.json](geometry.json). Coordinates are metres, +X right, +Y up, −Z nose. The origin is the nominal CG station (4-1/8 in aft of the rib-2D leading edge) at spinner-axis height. The physics CG is set separately in EX-05. Every group records its evidence kind; measured values come from [the EX-01 metrology](../../../research/extra-300/ex01/metrology.json), and estimated ones (gear track, pant width, propeller, section corner rounding) say so.

From the repository root:

```bash
python3 assets/aircraft/extra-300s-60/compile_geometry.py           # writes app/aircraft/extra_300s_geometry.gd
python3 assets/aircraft/extra-300s-60/compile_geometry.py --check   # stale copy, structure, and 116 values vs metrology.json
python3 research/extra-300/ex01/measure.py --check                  # needs the local plan/manual PDFs in references/
research/extra-300/ex02/capture.sh                                  # needs xvfb-run; new directory under app/captures/
app/test.sh                                                         # includes aircraft/verify_extra.gd
```

The [native builder](../../../app/aircraft/extra_300s_model.gd) keeps the Stik interface: `build()` → `{root, propeller, hinges, gear}` with `airplane`, `propeller` and `*_hinge` nodes. The swept aileron hinge is carried by a static `aileron_frame_*` parent, so `render/airplane.gd::apply_surfaces()` works unchanged. The report is [extra-300-model-v1.md](../../../docs/research/extra-300-model-v1.md).

The plan PDFs, manual, photos and CAD stay in the ignored `references/extra-300/`. Measured coordinates, code and selected captures are in the repo. Geometry and colours are original work, not copies of plan artwork.
