# R11 Lake Geometry Bake Failure Diagnosis

The focused `test_lake_geometry_bake.gd` run on the Windows source copy reproduced the reported two failures: `18 lake geometry bake checks, 2 failed` (see [windows-existing-test.txt](windows-existing-test.txt)). The probe in [lake_bake_probe.gd](lake_bake_probe.gd) identifies two independent causes. It did not edit app code, generated resources, or generator outputs.

The source-stamp assertion fails on one source only. The resource metadata contains `ground_terrain.gd = 9373dfc3…`, but its current LF-normalized source is `1c650cf1…`; the hashes for `lake_terrain.gd`, `lake_surface.gd`, and `math3d.gd` match. Consequently the digest of current source hashes is `6335af7d…`, while both the baked metadata and `generated_geometry_stamp.gd` carry `f53435ab…`. The `baked_sources` digest matches the stamp, but it no longer matches the current source tree. `test_lake_geometry_bake.gd:63–77` correctly detects this stale generated provenance. `tools/ground/bake_lake_geometry.gd:52–64` shows that the four code files, LF-normalized, feed the resource metadata and generated stamp. The default field JSON is not in that source list, so the helicopter-pad field data cannot explain this assertion.

The array-corruption failure is a test-target mismatch. The probe reports `basin_input_key_matches=false` and `water_input_key_matches=true`. `test_lake_geometry_bake.gd:136–139` empties `basin_arrays`, but `lake_terrain.gd:220–226` intentionally skips validation for a mesh whose input key does not match, allowing partial reuse of the matching water mesh. The probe confirms that this call returns true, while emptying `water_arrays` returns false. This is consistent with the existing partial-reuse assertion at `test_lake_geometry_bake.gd:164–167`; the corrupted basin is not a matched array in this fixture.

The test's fresh procedural basin and water builds both remain byte-identical to the saved arrays. The key mismatch still makes the basin ineligible for cache reuse, so the live build follows the procedural path for that component. This evidence establishes stale source provenance and an inapplicable corruption fixture; it does not establish a geometry-content mismatch.

The current default field includes `helicopter-pad-surface` (`data/fields/default.json:90–91`), but that same field content is present in the retained R00 baseline. The probe proves the resulting basin input key does not match this resource, but it does not isolate which field/surface tuple differs from the key baked into the resource. It would be inaccurate to attribute the source-hash failure to the pad or to call the pad a new change here.

The bake and stamp have now been regenerated through the source pipeline in an isolated physical app copy. The refreshed basin key matches current inputs; the generated basin and water arrays are byte-identical to the old arrays. This makes the existing basin-corruption assertion applicable without changing the test. See the [isolated regeneration receipt](isolated/README.md) for output hashes, source identity, commands, and the passing 18-check run. Live generated outputs were still untouched at the time of this isolated verification.

## Reproduction

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/physics-audit-r11-final-scenarios-04/verified-app --audio-driver Dummy --script res://tests/test_lake_geometry_bake.gd
```

The separate diagnostic command was:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/physics-audit-r11-final-scenarios-04/verified-app --audio-driver Dummy --script docs/research/physics-audit-2026-10-14/remediation/R11/lake-bake-diagnostic/lake_bake_probe.gd
```

The probe exited 0 and reported: current source digest `6335af7d8f0692a55e61def680e74dd233917f3117c65971421368dc8b41ae6`; baked/stamp digest `f53435abcf470385d79d3f800d7b46ecf3424067aa295afa628591392fafd03a`; basin key mismatch; water key match; `baked_matches_unmodified=true`; `baked_matches_with_empty_basin_arrays=true`; and `baked_matches_with_empty_water_arrays=false`.

The frozen Linux candidate and Windows source copy have the same file contents for the test, lake source files, generated stamp/resource, and relevant field JSON after stripping CR line endings. The only platform-copy differences in these GDScript files are line endings. Hashes below are SHA-256 of the raw Windows copy unless a value is labeled LF-normalized.

| Artifact | SHA-256 |
| --- | --- |
| `test_lake_geometry_bake.gd` raw Windows copy | `C93630F2C46E73B16CE6221AE841FDCC4A3C3376A40EF6ABA89DB64583034249` |
| `lake_terrain.gd` raw Windows copy | `B7467250CF9BA32BC59456AA851351B2C6930E18DA5F1472EF89652E4CB996A8` |
| `ground_terrain.gd` | `1C650CF179C7CCDCA62DFD4B908E34DBC7ADFE66700753CA6648AF36BF5F2358` |
| `lake_surface.gd` | `DD9E3C3690EB2A71AD0928AEE206D0FEDCC4399A4B6CC41B542C1282E06A04A1` |
| `math3d.gd` raw Windows copy | `DDA830CF7F85668B558E328368DEC173CD2AF75F6438B4506432409B7A92D80B` |
| `generated_geometry_stamp.gd` | `F1683C340F3807C653917B18E66C40A37A62CD033518548B62680AF746198F9C` |
| `default_geometry.res` | `50102097F9AAF329637F1DBCA1211A5428AAC593BF1B25EFDCD291BE77E2FF6D` |
| `default.json` raw Windows copy | `A4908850C54F183E8D479623384AE249E2024A893B3FB8288030FD69EB20069D` |
| `lake_bake_probe.gd` | recorded after the probe run |
