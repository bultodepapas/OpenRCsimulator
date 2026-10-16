# Lake Bake Regeneration Receipt

The two generated outputs were produced in a full physical copy of `app` at
`tmp/physics-audit-r11-lake-bake-generator-copy-20261014/app`, with the unchanged
repository generator copied to the matching temporary `tools/ground` path. The copied
generator inputs used the same bytes as the live sources. Their four LF-normalized
source hashes also match the immutable Linux candidate
`/home/bulto/openrc-r11-b09-r05b-20261014-03/app`:

| Source | LF-normalized SHA-256 |
| --- | --- |
| `physics/ground_terrain.gd` | `1c650cf179c7ccdca62dfd4b908e34dbc7adfe66700753ca6648af36bf5f2358` |
| `render/lake/lake_terrain.gd` | `8e042fef3ee14b848ae096c8be27b2e75c6cc1a66cf744e3ae552e708bd81f65` |
| `physics/lake_surface.gd` | `dd9e3c3690eb2a71ad0928aee206d0fedcc4399a4b6cc41b542c1282e06a04a1` |
| `physics/math3d.gd` | `3fb2c705d38f0e27d58ac79981d7e57ac7952b6c755fcb0998b44c43a03528e1` |

The production-path generator command, output, and exit code are retained in the
temporary copy's `generator-command.txt`, `generator-output.txt`, and
`generator-exit-code.txt`. It completed with exit code 0 and emitted these reviewable
artifacts:

| Output | SHA-256 | Bytes |
| --- | --- | ---: |
| `pipeline-default_geometry.res` | `1be6cdbf85fd7761a2f5d1bcfc9766da1babd2bbde6dee01b7319bc67c788e35` | 739231 |
| `pipeline-generated_geometry_stamp.gd` | `3f6177bca34b1bc77de4d2c69dbc6f0329ca73a257381dabb27070ec0a66f1c2` | 173 |

The old production bytes are preserved in the parent directory as
`before_default_geometry.res` (SHA-256 `50102097f9aaf329637f1dbca1211a5428aac593bf1b25efdcd291be77e2ff6d`)
and `before_generated_geometry_stamp.gd` (SHA-256
`f1683c340f3807c653917b18e66c40a37a62cd033518548b62680af746198f9c`).

`array-identity.txt` compares the old and regenerated resource metadata: both basin
and water arrays are byte-identical to the old arrays (digests `5861457b…` and
`666a839d…`). The water key is unchanged. The basin input key is refreshed to the
current field/surface inputs, which makes both array-corruption cases matched and
therefore rejectable. `regenerated-probe.txt` records current source digest and
stamp `6335af7d8f0692a55e61def680e74dd233917f3117c65971421368dc8b41ae6`, matching
keys, and `false` for `baked_matches` after corrupting either matched array.

The exact copied-app generator `--check` passed (`generator-check.txt`). The complete
focused test passed: `18 lake geometry bake checks, 0 failed`
(`test-lake-geometry-bake.txt`). No test, runtime, source, or live generated output
was changed during this isolated validation.

An additional `--out` resource is retained as `default_geometry.res` for reference.
Its raw file hash differs from the production-path output, so the production-path
pair above is the artifact pair used for integration.

After review, those exact artifacts were copied into
`app/assets/landscape/lake/default_geometry.res` and
`app/render/lake/generated_geometry_stamp.gd`. The live files have the same SHA-256
and byte sizes as the isolated pair above. The live production generator check passed
(`../live-generator-check.txt`), followed by the complete focused test with 18 checks
and 0 failures (`../live-test-lake-geometry-bake.txt`). Exact commands:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/bake_lake_geometry.gd" -- --check
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_lake_geometry_bake.gd
```

The only live app paths changed for this regeneration are those two generated
outputs; no generator, runtime, or test source was edited.

## Release-source refresh — 2026-10-16

At `b85392bc`, the LF-normalized `ground_terrain.gd` hash had changed to `42e9f30e155c8b710dbc3f0219da5b7ba72776fe5123132752a8f13dee260a90`. The other three generator source hashes and both input keys were unchanged; the [source probe](../release-20261016/before-probe-absolute.stdout.log) identifies the stale stamp.

The unchanged production generator ran in an isolated checkout with official Windows Godot `4.7.2.stable.official.ed1daf0bf`. It normalizes CRLF before hashing. The regenerated source digest is `b124686058bfa6e7263cea1c9af2e9e73781474c29134b2b8ee63b5bba7a7019`. [Array comparison](../release-20261016/compare.stdout.log) confirms that both basin/water arrays and input keys are byte-identical to the committed resource. The [generator](../release-20261016/generator.stdout.log), [generator check](../release-20261016/generator-check.log) and [18-check focused test](../release-20261016/focused-test.log) passed. Only the two generated outputs were integrated; no simulation law, geometry, generator or assertion changed.

WSL entered read-only mode after its host disk filled, so this refresh has Windows evidence and comparison against the committed arrays, not a fresh Linux regeneration. The full release suite remains required.
