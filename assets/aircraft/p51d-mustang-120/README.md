# P-51D Mustang 1/4 scale, 120 cc class: visual geometry v1, experimental

`120` is the engine class (121 cc DA-120 / DLE-120). The model is **experimental** (P51-02/05): a first visual model and a first physics estimate, selectable on Home; not flight-tested against any real airplane.

Edit [source.json](source.json) (full-size P-51D dimensions in metres plus the kit values), then run the two compilers. Coordinates are metres, +X right, +Y up, −Z nose; z = 0 at the wing root leading edge on the centreline, y = 0 on the spinner axis. Every group records its evidence kind: the overall dimensions are published P-51D figures, the tail comes from the Virginia Tech configuration study, the airfoil from the UIUC ordinates, the fuselage/scoop/canopy sections are read by eye from the public-domain AN 01-60-3 three-view (`references/p51-mustang/`, gitignored), and the kit values (span 2.82 m, DA-120, 4-blade 26x12, CG 27 % MAC, throws) are estimates documented in [the research](../../../docs/research/p51-family-research.md).

From the repository root:

```bash
python3 assets/aircraft/p51d-mustang-120/build_geometry.py            # source.json -> geometry.json (scale 1/4)
python3 assets/aircraft/p51d-mustang-120/build_geometry.py --check    # stale geometry.json
python3 assets/aircraft/p51d-mustang-120/compile_geometry.py          # writes app/aircraft/p51d_geometry.gd
python3 assets/aircraft/p51d-mustang-120/compile_geometry.py --check  # stale copy and structure checks
python3 research/p51/p51-05/derive_physics.py                         # writes app/data/aircraft/p51d_mustang_120.json + derivation.md
python3 research/p51/p51-05/derive_physics.py --check                 # stale physics data or report
xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://aircraft/inspect_p51.gd -- --output-dir=/tmp/p51 --suite=inspection   # renders
app/test.sh                                                           # includes aircraft/verify_p51.gd and tests/test_p51_handling.gd
```

The [native builder](../../../app/aircraft/p51d_model.gd) keeps the Stik/Extra interface: `build()` → `{root, propeller, hinges, gear}` with `airplane`, `propeller` and `*_hinge` nodes. The wing node carries the +1° incidence, `wing_frame_<side>` the ±5° dihedral and `aileron_frame_<side>` the swept hinge line, so `render/airplane.gd::apply_surfaces()` works unchanged. Flaps are drawn fixed. The landing gear is drawn down (retracts are not simulated). Finish: an original generic natural-metal look (red spinner and nose band, olive anti-glare panel, yellow tips and rudder); no unit markings or copied artwork.

Plan and status: [docs/P51-PLAN.md](../../../docs/P51-PLAN.md).
