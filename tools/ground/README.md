# Ground surface capture

Run the L9c Compatibility-renderer review with:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_surfaces.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l9c-surfaces
```

The checker captures the production `FieldBuilder`, `Atmosphere`, and `ShaderClock` at fixed time zero. It covers 100 m and 300 m runway zooms (10° vertical FOV), 100 m and 300 m oblique runway views, the threshold, and a raised overview. Each pose has surface-on/off captures at zero and half-pixel camera-plane shifts. The raised planes must be consolidated into the rough ground material, whose surface arrays and bounds are checked against field data.

The 100 m runway edge score uses the camera-projected runway polygon, intersects its inside edge with pixels changed by the surface-on/off ablation, and compares median on-surface luma with the adjacent rough-ground band. It must exceed 5% Weber contrast. The shimmer score is RMS change in the surface-only residual divided by its RMS signal; it includes the expected response to camera translation. The checker records both oblique views against a scratch raw-square-wave mutation, but does not claim that the comparison proves shimmer closure. Stripe-filter acceptance remains open. A separate disabled-surface mutation must trigger the no-effect gate. Mutation copies are imported before capture and kept isolated from the live project.

Default and custom priority captures repeat in separate processes; every PNG hash and draw, primitive, and object counter must match. The custom fixture reverses runway/mown input order, draws both kinds, and compares runway pixels with the default field to check priority. `summary.json` records metrics, renderer and Godot versions, source hashes, exact capture arguments, and the deterministic render environment. Output directories must be new or empty.

The L9c-R1 stripe reference check separates expected camera motion from sampling error:

```bash
"$(app/tests/visual-env.sh)" tools/ground/test_stripes.py
"$(app/tests/visual-env.sh)" tools/ground/check_stripes.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l9c-stripes
```

It subtracts `stripe_amp=0` images, compares native output with an independent raw-wave reference rendered at 16× resolution, and subtracts the reference's expected half-pixel motion. The improvement at 100/300 m must exceed twice the measured 8×/16× reference disagreement. A nearby threshold view must retain its stripe detail. Independent native repeats must match exactly; both a raw-wave control and a no-stripes control must fail acceptance.

Only a 640×64 sub-frustum of each original camera is rendered (up to 10240×1024 at 16×). The camera translation remains measured in base-resolution pixels; projected geometry is checked across resolutions. The measurement mask is a fixed one-metre runway inset, independent of image colour. The high-resolution PNGs are decoded to linear RGB before box averaging. This is a bounded engineering regression check, not proof of reference convergence or perceptual shimmer closure. See [method and evidence](../../docs/research/visual-quality-implementation/L9c-R1/README.md). Both ground checks run from `app/capture.sh` and appear in its final manifest.

L10a flight-cue captures use the same pinned rendering environment:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l10a-windsock
```

Three production-field views isolate the calm windsock with visibility on/off at shader time zero. Default captures repeat exactly; a third run exercises optional scenery. Pixel changes must stay within projected cue bounds, whites must not clip, and the cue must add two draws and fewer than 2,000 triangles. The checker rejects an invisible-feature control. [L10a evidence and scope](../../docs/research/visual-quality-implementation/L10a/README.md).

L10b reuses the flight-cue harness for the pilot station:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py --cue pilot_station --app app --godot "$(app/get-godot.sh)" --out /tmp/l10b-station
```

Front, rear and raised views require a visible one-draw cue below 400 triangles. Both runway-threshold views use the field's actual pilot eye and require identical on/off pixels. A modified-pixel control tests that equality guard; it does not render an occluder. Default repeat and scenery-on runs produce 30 images. Both cue modes run in `app/capture.sh`. [L10b evidence and limits](../../docs/research/visual-quality-implementation/L10b/README.md).
