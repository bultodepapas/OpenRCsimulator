# GDU-03: field shadow-world integration check

2026-10-25, official Godot 4.8-beta1, headless/Dummy audio. The existing field
integration test now passes all 39 checks with zero engine errors or warnings.
Only `app/tests/test_field_integration.gd` changed; production rendering and
simulation code are unchanged. Root and the frozen full-suite test file match
exact bytes after the overlay.

The original helper classified every flight `SubViewport` as a shadow mask.
The CAM-18 magnifier intentionally shares the gameplay world, so its existing
viewport failed that classification. A diagnostic copy of the existing test,
with the original assertions intact, reports both:

- `ProjectedShadow/Silhouette256`: owns its world, distinct from gameplay, with
  one camera, one environment and one mask mesh.
- `MagnifierLayer/Magnifier`: shares the gameplay world, with its inset camera.

The fix enumerates actual `ProjectedShadow` owners and checks each owner's
viewport. It still rejects missing viewports, missing or shared worlds,
`own_world_3d == false`, unexpected children, or anything other than exactly
one camera/environment/mask mesh. It still requires at least one shadow owner.
This resolves a feature/test scope mismatch without changing the shadow-world
contract or forcing the magnifier into a separate world.

A disposable copy of the fixed integration test substitutes the real
shared-world inset for the helper's local shadow viewport. The unchanged
isolation assertion rejects it: exactly one failed check, 38 passing checks,
process exit 1 and zero engine errors/warnings. An earlier attempt to toggle
an already-live viewport's world also triggered a headless scenario-null engine
error; that rejected forensic receipt is retained and excluded from this clean
negative-control claim.

[Verification](verification.json) retains commands, test/log hashes, the
diagnostic world identities and all four focused receipts. Raw scripts and
logs stay at `D:/OpenRCsimulator-experiments/gdu03-field-shadow-audit/`.
The lead owns the full shard rerun; this focused result does not establish
whole-suite, native visual or package qualification.
