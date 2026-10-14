# AS-09/10: common Blender construction

2026-10-13. This continuation moves Timber r2 from an aircraft-specific constructor to the shared `imported_model.gd` builder. Model manifest v2 supplies explicit rotor frames, gear pivots, geometry references and per-instance material adjustments. Procedural model manifests remain v1. The physical aircraft format, equations, calibration, GLB and generated geometry are unchanged.

The [aircraft contract](../../../../AIRCRAFT_CONTRACT.md#model-and-package-contract) owns authoring instructions. The [active plan](../../../plans/aircraft-standardization.md) retains the remaining gates.

## Compatibility proof

The baseline uses `app/aircraft/timber_model.gd` from revision `4e8755d5`, SHA-256 `a36e1251da54d6b0af9f37eb741ef1dc480452e600dde666168af7f07d120675`. Its original source was captured before editing, then loaded directly by the pose probe. The comparison includes neutral, conventional full travel, full flaps, rotor spin, wheel spin with steering, and combined poses.

Each state contains 47 tree nodes and two cowl material overrides. The final [pose comparison](pose-parity-summary.json) checks node names, parents, classes, local and root-relative transforms, nested glTF section tags, and material settings. JSON integer/float spellings compare numerically. No path normalization is applied to the accepted result. Both transform comparisons have maximum absolute difference **0.0**, within the declared 1e-6 tolerance. [Baseline](pose-baseline.json), [candidate](pose-candidate.json).

The source binding retains the legacy `wheel_tail_spin` and `wheel_tail_spin_mount` names. The Timber inspector facade retains the shared generated geometry constant by identity for its older metrology tools; the generic loader returns an equivalent geometry snapshot. The black/red cowl offsets remain 0.8 mm and use independent material instances. Wreck duplication preserves the constructed tree and authored sections.

## Verification

- [Common source/package conformance](conformance/verification.json): generator/schema checks, LF/CRLF checkout checks, module/model/Workshop checks, catalog-discovered source preflight and exported Windows PCK preflight. Both preflights cover seven physical configurations and five visual families; package checks use the pack without `--path app`.
- [Imported builder](imported-builder.log): 68 checks, including independent instances, reset, immutable shared materials, wreck duplication, renamed nodes, a synthetic two-hinge elevator, absent rotor marker, all six signed frame axes, missing/duplicate nodes, malformed references and invalid mechanical transforms. Rejected scene ownership is released.
- [Timber metrology and crossing checks](timber-checks.json): 452 model checks and 19 surface-crossing checks pass. The full distance-gap scan exceeded its initial 180-second bound; the final crossing-only run does not claim new minimum-gap or suspension-clearance measurements.
- [Model manifest](conformance/aircraft_model_manifest.log): 53 checks. [Fleet surface/render contract](conformance/aircraft_render_contract.log): 291 checks. Generated sources and Workshop pins were regenerated through their source pipelines.

The first integration run exposed an outdated test that treated model version 2 as unknown, a changed tail-wheel wrapper label, and the inspector's constant-identity expectation. These were corrected and the relevant suites rerun. Final source identities and command results are recorded in [delivery.json](delivery.json). No golden flights were re-recorded. This slice changes no flight state, forces or physical data; concurrent rotorcraft changes are listed separately in the delivery record and were preserved.

## Reproduce

Use the pinned Godot 4.7.2 build. From the repository root:

```text
python research/aircraft-standardization/build_models.py --check
python research/aircraft-editor/build_descriptors.py --check
python research/aircraft-standardization/conformance.py --godot <godot> --out <new-evidence-directory> --models-only --package
<godot> --headless --path app --script res://aircraft/verify_timber.gd
<godot> --headless --path app --script res://aircraft/verify_timber_clearance.gd -- crossings-only
<godot> --headless --path app --script research/aircraft-standardization/imported_pose_probe.gd -- --out=<candidate.json> --baseline=<pose-baseline.json>
```

Pass absolute paths for the external pose script and its output/baseline when required by the platform. The probe also accepts `--builder-source=<legacy-timber-model.gd>` to reproduce a baseline from the recorded revision. On Windows, wait for the native executable through Python `subprocess.run`; do not assume launching the GUI executable from PowerShell waits for its exit.

## Remaining gates

The renamed/split fixtures are software tests, not a second Blender delivery. AS-18 still requires a genuinely distinct authored asset. Durable physical inventory/contact IDs and probe-to-detachable-section references remain separate work. Flaps here remain visual-only; new mixing, propulsion topologies and contact laws still need their physical consumers and evidence.

Existing procedural aircraft keep their builders. Official current Workshop descriptors pin the regenerated manifests. Frozen variants retain their exact historical presentation hashes and reject changed dependencies; this delivery does not silently migrate saved trials or claim historical package replay.
