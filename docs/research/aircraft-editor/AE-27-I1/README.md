# AE-27-I1 — Internal attachment contract and Stik wheel study

**Date:** 2026-11-19, America/Bogota (raw runner timestamps use 2026-11-20 UTC).
**Branch:** `plan/workshop-aircraft-attachments-2026-11-19`.
**Baseline:** GitHub `main` at `e0a733937e255bacfe95ff09db0fb3838697239f`; planning/research
head `9f20493631aa3013fbf28341bc9bcc9704fe48fd`.
**Integrated upstream:** `d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`, following the first merge
of `b69ac2d54871b0d798af7c61ac62d8f17e6abd3d`. Both merged without conflicts. The combined
updates include ClearView importer/guide work and shared rendering, physics, telemetry and
ClearView motion changes. They leave the stock Stik builder and presentation v4 contract unchanged.
The resource import and all five focused suites below were rerun after the final merge.

This is an internal implementation increment of the [attachment plan](../../../plans/workshop-aircraft-attachments.md).
It advances AE-27-00b and AE-27-01a preparation. It does **not** complete either step or expose a
Parts selector. The existing presentation v4, generated model/customization/descriptor pins and
physical recipe remain unchanged. The [twenty investigations](../AE-27-R1/README.md) remain the
design research; they are not asset qualification evidence.

## Implemented boundaries

| Owner | Implemented behavior |
| --- | --- |
| [Selection contract](../../../../app/workshop/attachment_selection.gd) | A closed internal v1 document contains the catalogue digest and four explicit slot/option IDs. `original()` is a deliberate constructor; `{}` or missing slots do not become defaults. Unknown, stale, malformed and wrong-slot options fail with structured diagnostics and no accepted selection. |
| Trusted resolution | Compatibility comes from owned registration metadata, never from the document. The single `stik_twin_groove_v1` study is registered only for `jensen-das-ugly-stik-60` at explicit scale `1.0`, always `preview_only`. No support is inferred for another Stik installation, Extra, an alias or an imported airplane. |
| [Native wheel study](../../../../app/render/attachments/stik_wheel_preview.gd) | Stages all three replacement meshes on the existing wheel handles before publishing. Keeps the pivot/node objects, transforms, steering/flex handles and crash metadata. Copies the three hardware surfaces and builds one alternate tire surface per wheel. |
| Restore and failures | Original invokes no mesh/material setters. Repeated apply/restore reuses the staged meshes. Restore returns the exact original Mesh resources while retaining subsequent paint overrides. Missing/reparented handles, another owner's mesh replacement, intervening override changes and unsupported scale refuse before publication. |
| Ownership limit | The study requires an unchanged, exclusively owned `Airplane.build()` result with immutable source meshes/materials. It detects the documented reference/scale changes, not arbitrary in-place mutations by another owner. It refuses mutation while the model is in a SceneTree; attaching a prepared model remains caller-controlled and is not flight admission. |

`resolve(document, verified_aircraft_id, explicit_scale)` returns compatibility metadata, **not**
flight authorization. The current Workshop, save store, bundle import and launchers do not call the
new modules. The existing presentation validator refuses the new field until the coordinated
migration is implemented. The catalogue digest pins registration metadata only; it is not an asset,
factory, model-manifest or exported presentation proof.

The resolved Original status retains the accepted baseline's meaning; it does not establish that an
unregistered aircraft or arbitrary installation can fly. The future caller must verify the base,
source pins, physical compilation and actual start qualification separately. Duplicate JSON keys
also require the future strict JSON I/O boundary; an already-parsed Dictionary cannot recover them.

## Native geometry decision

The first study uses two circumferential grooves inside the existing tire envelope. This establishes
replacement and recovery before the Small/Large/XL presets introduce a ground-support discrepancy.
It is a modest visual experiment, not a bush-wheel performance package.

| Property | Main wheels | Nose wheel |
| --- | --- | --- |
| Nominal tire diameter | 76.2 mm | 69.85 mm |
| Nominal tire width | 24 mm | 22 mm |
| Groove centers | ±7% of tire width along the axle | Same rule |
| Each groove | 1 mm wide, 0.4 mm deep | Same dimensions |
| Radial sampling | 40 segments, retained from the stock lathe | Same |
| Added tire triangles | 480 per wheel | 480 |

The crown between the grooves retains the stock centerline support. Hubs, sidewall rings, bolt heads
and axle artwork are copied from the accepted source mesh; they are not enlarged with the tire.
Each replacement surface owns a copied material; existing per-instance vehicle-paint overrides
remain on the original mesh nodes. The factory reuses the native lathe helper without editing the
proved equipment builder or changing its dependency closure.

The first implementation's decoded-array copy failed six exact hardware comparisons: the engine
repacked normal/tangent channels. The final factory preserves the encoded hardware surfaces and
their indices using the existing [stored-surface pattern](../../../../app/scenery/imported_vegetation.gd).
Tests require both the stored payload and decoded channel bytes to match the source exactly; the
failure was not resolved by widening a tolerance. `_surfaces` is a pinned-engine storage interface,
so missing/incompatible surface data refuses staging and engine changes require requalification.
It is not a general importer API. Dynamic region updates were also avoided because the repository's
[earlier probe](../../timber-integration/TT-21/motion/README.md) found stale CPU-side copies/bounds.

These dimensions are the internal study's design and measured-test targets. They do not qualify
visibility, rendered fit, collision behavior, terrain support or flight. Headless triangle-buffer
measurements and pose comparisons do not replace native visual acceptance.

## Verification

Executed locally on Linux with the repository's checked Godot runner and the exact verified
`4.8.beta2.official.cafc17a19` engine. The shared test-pool configuration was absent on this
unenrolled workspace, so these are standalone checked runs. The project resource import, including
the incremental import after merging `main`, completed successfully.

| Focused suite | Checks | Failures |
| --- | ---: | ---: |
| `test_attachment_selection.gd` | 121 | 0 |
| `test_stik_wheel_preview.gd` | 121 | 0 |
| `test_workshop_presentation.gd` | 92 | 0 |
| `test_presentation_sources.gd` | 233 | 0 |
| `test_gear_flex.gd` | 27 | 0 |
| **Total** | **594** | **0** |

All five final suite reports have zero engine errors and warnings. [Verification metadata](verification.json)
pins the delivered sources, engine, raw logs and checked-runner reports. The new code was parsed
before entering `app/`; subsequent edits were checked by the actual test loads. All five suites
were rerun after the hardware-buffer repair and the final upstream merge. The receipts below
therefore describe the same delivered implementation and integrated source revision.

Measured tire-buffer radii were 0.038100000 m for the mains and 0.034925003 m for the nose;
lowest local vertices were −0.038100000 m and −0.034924999 m respectively. Widths were 0.024000000 m
and 0.022000000 m. Each alternate tire has 1,280 triangles, 480 more than stock; the complete set adds
1,440 triangles and no mesh nodes. These are mesh measurements, not frame-time or memory budgets.

The repeat test performs eight apply/restore cycles using the same staged resources. It does not
complete C5's twenty-cycle preview/close/performance campaign. Full app CI, exported packages,
native rendered fit/accessibility, complete Workshop persistence/trial flow, physical same-input
parity, damage/shadow/observer qualification and target-platform performance are still pending.

Reproduce after `app/get-godot.sh` and a completed checked import, from the repository root:

```sh
python3 tools/godot/run_checked.py --label ae27-selection --timeout 90 \
  --require-text 'Attachment selection: 121 checks, 0 failed' -- \
  .tools/Godot_v4.8-beta2_linux.x86_64 --headless --path app --audio-driver Dummy \
  --script res://tests/test_attachment_selection.gd
python3 tools/godot/run_checked.py --label ae27-wheel --timeout 90 \
  --require-text 'Stik wheel preview: 121 checks, 0 failed' -- \
  .tools/Godot_v4.8-beta2_linux.x86_64 --headless --path app --audio-driver Dummy \
  --script res://tests/test_stik_wheel_preview.gd
```

The new tracked tests are:

- [Selection tests](../../../../app/tests/test_attachment_selection.gd): closed shape, explicit Original,
  canonical round trip, malformed/unknown/stale IDs, compatibility and scale, defensive metadata
  copies, and the unchanged presentation/physical-recipe boundary.
- [Wheel study tests](../../../../app/tests/test_stik_wheel_preview.gd): actual manifest-bound builds,
  measured tire radius/width/lowest vertices and groove/crown geometry, unchanged hardware arrays,
  material isolation, rest/steering/compression/attitude envelopes, atomic failure, stale scale,
  repeated resource reuse, paint-preserving restore and live-scene refusal/recovery.

Two independent source reviews identified and resolved the missing-scale default, existing base-ID
grammar, digest precision, stale root/wheel scale, Original setter side effects and active-material
test coverage. Those reviews were read-only; they do not substitute for executed tests.

## Next integration increment

1. Coordinate the presentation/binding/proof versions and regenerate **all** affected companions,
   overlays and the export package together. Include airship, transfer, rebind, audio-edit promotion
   and stock/empty predicates. Preserve historical records and truthful stale-profile behavior.
2. Add attachment bindings and factory/source proof through the owning generators. Bind this internal
   selection contract to the verified aircraft/model/installation context; do not publish its metadata
   digest as a substitute for those proofs.
3. Wire the one-set preview/document/history/save/recovery flow. Handle apply errors, bounds,
   Original/Draft, paint/lights/decals, thumbnail cache and dependent observers. Separate visual
   preparation for **both thumbnails and bundle import** from strict flight freezing.
4. Enforce trusted eligibility at Workshop and CLI launch before physical start qualification. Run
   physical parity with the same source/package, solver/build revision, engine and execution
   conditions, plus the complete trial/return journey, including refusal paths. Matching trial IDs
   alone do not establish equivalence across the upstream solver changes.
5. Review actual native rendered fit, active materials, shadows, wreck/reset and cleanup. Only then
   decide whether this option can be promoted from preview-only and expose the public selector.
6. Add one bounded larger wheel set after that first complete flow. Keep an exaggerated size
   preview-only when support/clearance does not fit; do not adjust physics to conceal the mismatch.

Physical wheels, propulsion changes and functional floats remain in phases 5–7 of the plan.
