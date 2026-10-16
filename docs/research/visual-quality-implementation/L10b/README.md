# L10b — pilot station

## L10b-R1 — renewed materials and fitted joinery (2026-10-16)

The current station uses light satin-finished timber, a dark petrol powder-coated frame, stainless fasteners, post caps and inset anchor plates. Bevelled edges catch light at close range. A textured concrete slab and low ribbed entrance strip complete the rear-open footprint. The original width, depth, height, pilot position and grass exclusion are retained.

Downloaded **ambientCG Wood050, Concrete034 and Metal032** maps supply grain, surface relief and roughness; all are CC0. [Asset provenance](../../../../app/assets/landscape/pilot-station/PROVENANCE.json) records source links, archive/file hashes and source dimensions. Textures are unmodified JPGs with lossless imports, mipmaps and anisotropic filtering. The stain, coating, normal strength and fitting dimensions are artistic choices. The material uses model-space mapping, with grain following each side's boards. No transparent surfaces or extra shadow pass are introduced.

The native Windows Godot 4.7.2 compatibility render contributes **one draw / 6,124 triangles**, within the revised 8,000-triangle ceiling. Four close-detail views were inspected. Five scenery-on ablation poses pass: visible geometry stays within projected bounds, no cue pixels clip white, and both actual pilot threshold views have **zero changed pixels**. Focused suites pass **279 checks** (39 geometry/grass, 163 data, 20 contact-shadow, 57 projected-shadow). The application entry script also parses. This is visual/engineering verification, not target-device timing or a replacement for human Gate L review.

[Verification and source hashes](detail-2026-10-16/verification.json) · [Before](detail-2026-10-16/before/front.png) · [Rear entrance](detail-2026-10-16/after/rear.png) · [Joinery](detail-2026-10-16/after/joint.png) · [Floor](detail-2026-10-16/after/floor.png).

![Renewed pilot station](detail-2026-10-16/after/front.png)

Detail captures use `tools/ground/capture_pilot_station_detail.gd -- --out=<empty-directory>` with the native OpenGL renderer. The existing flight-cue checker below verifies visibility and draw budgets.

## Original implementation evidence (2026-10-08)

**Status (2026-10-08): engineering verification passed; human Gate L remains open.** One bounded [L10](../../../LANDSCAPE-PLAN.md) flight cue; broader safety-line fencing remains pending.

## Scope and provenance

The default pilot now stands inside a low three-sided station, open to the south/rear. Its 1.5 m east-west width, 1.2 m north-south depth and 0.75 m height are estimated visual dimensions, informed by the club examples in [field-layout research](../../scenery-investigations/03-rc-field-layout-references.md#markings-and-pads). They are not a safety standard or a claim of physical protection. The concrete pad, galvanized frame, four orange slats per side and colours are original procedural artwork. No downloaded asset or dependency is added.

The station follows the existing pilot datum; neither the pilot camera nor the runway moves. `pilot_station.gd` emits one opaque mesh, with no processing, collision or shadow pass. All fittings remain inside the specified footprint; the rear has no crossing rail. Near grass excludes the pad plus the existing full-clump margin. Surface friction, contacts and flight physics do not consume this visual cue.

The optional field-data array accepts at most one windsock and one station. Position, dimensions and provenance are validated before building. The station must match the flat-ground pilot location, remain below eye height, fit on rough ground and clear runway/mown surfaces. Fields without cues preserve their prior normalized shape. See [data contract](data-contract.md).

## Verification

The focused checks pass: 36 station geometry/grass checks, 161 station-data checks, 119 windsock-data checks, 16 windsock mesh checks and 161 legacy loader checks. Existing field integration, surfaces and near-grass suites also pass. Geometry readbacks cover footprint/height across supported dimensions, open rear and closed sides, finite vertices/normals, deterministic builds and the single-draw budget. On/off captures cover front, rear, raised overview and both runway thresholds from the actual pilot eye; default repeats and scenery-on runs share the same frozen clock. The pilot-view check requires exact pixel equality and rejects a pixel-difference control (one modified image pixel, not a rendered occluder). Visible views must change inside projected mesh bounds; an invisible-feature control must fail.

All 30 station captures and 18 windsock regression captures pass from a clean clone plus the explicit [landscape overlay](evidence/snapshot.json). The station contributes **one draw and 230 triangles** in visible views. Both threshold views remain byte-identical with it on/off, including optional scenery. The pad excludes **49 clumps**, leaving 4,794, and repeat images/counters are exact. No clipped whites appear on the cue.

The [three-second flight comparison](evidence/trace-comparison.json) has 721 identical numeric samples before/after; only the creation timestamp differs. The [Linux PCK check](evidence/pack-check.log) loads the station, windsock, grass and trees from an empty project root. Static lint reports no errors and the same 12 pre-existing warnings. The full `app/capture.sh` pipeline was not rerun; both flight-cue modes were exercised directly. Native Windows/macOS execution is not claimed.

All headless checks completed in the isolated snapshot, including golden flights, flight/model contracts and 30/60/144 fps state equality. The initial `app/test.sh` run exited 124 when the landing maneuver exceeded 60 seconds without an assertion failure. A continuation repeated that test with a 180-second limit and ran every remaining original assertion, exiting 0; prior checks had passed. The repository runner was unchanged. Concurrent uncommitted physics changes were excluded. [Initial log](evidence/app-test-initial.log) · [Continuation log](evidence/app-test-resumed.log) · [Exact continuation script](evidence/resume-checks.sh) · [Verification scope](evidence/verification.json).

Evidence: [station capture summary](evidence/station-summary.json), [windsock regression summary](evidence/windsock-summary.json), [station geometry checks](evidence/test_pilot_station.log), [data checks](evidence/test_pilot_station_data.log). Three representative images are retained; all six manifests and source hashes are in `evidence/`.

![Pilot station, open at the rear](station.png)

[With the optional club scenery](scenery.png) · [Pilot looking at the left runway threshold](pilot-left.png)

The pilot-view assertion applies to the default field, these camera poses and 50-degree vertical FOV. It does not replace the owner's Gate L playtest or target-GPU timing.

## Reproduce

```bash
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_pilot_station_data.gd
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_pilot_station.gd
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py \
  --cue pilot_station --app app --godot "$(app/get-godot.sh)" --out /tmp/l10b-review
```

The shared flight-cue checker retains its L10a filename for existing callers; omitting `--cue` still checks the windsock. `app/capture.sh` invokes both cue modes and records their completion reports. The grass exclusion remains active in both sides of the station mesh ablation, so that comparison isolates the station geometry.
