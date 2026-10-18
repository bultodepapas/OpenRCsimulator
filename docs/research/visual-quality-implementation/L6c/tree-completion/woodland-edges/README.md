# Woodland-edge habitat evidence

The default-field woodland-edge addition is a bounded decorative understory: four irregular edge patches use 48 source-derived shrub cards and 12 existing short-grass clumps. It adds 1,956 source triangles in five merged render batches. It creates no tree or sapling geometry and no collision objects. The builder applies only to the exact default field, scenery, and lake inputs; custom inputs skip the habitat.

## Composition review

R1's two straight, parallel shrub rows were rejected as garden-like. R2's continuous zigzag loops were rejected because the rendered patches read as hollow rings. Both folders remain diagnostic records: [R1 image](candidate-native/woodland-edge-east-north_close.png) and [R2 image](candidate-native-r2-review/woodland-edge-east-north_close.png).

R3's filled, asymmetric clusters were accepted for this bounded addition. They use the existing stylized atlas and are not photorealistic understory. The four close views below show each patch; the wide view provides field context. That wide view is low-contrast under the production atmosphere and is context evidence, not the basis for judging plant detail.

- [East north close](candidate-native-r3-final/woodland-edge-east-north_close.png)
- [East south close](candidate-native-r3-final/woodland-edge-east-south_close.png)
- [Northwest close](candidate-native-r3-final/woodland-edge-northwest_close.png)
- [Southwest close](candidate-native-r3-final/woodland-edge-southwest_close.png)
- [Field wide](candidate-native-r3-final/woodland_edges_field_wide.png)
- [Full capture report and source hashes](candidate-native-r3-final/report.json)

The final capture used Godot 4.7.2 Compatibility on an NVIDIA GeForce RTX 3090, at 1280×720 with 4× MSAA and production field surfaces, scenery, lake, atmosphere, and sun. `Field.build` took 1,806.965 ms in this run. All 60 emitted plant records had valid terrain samples. The report records the IDs, positions, asset IDs, sampled heights, PNG hashes, and source hashes. Its oak wind warning is from the existing source material's unsupported transparency mode; this habitat does not change tree wind behavior.

The capture fixture is retained at [woodland_capture.gd](woodland_capture.gd). R3 was visually reviewed after capture; the report's scope is a static visual fixture and does not claim a user-acceptance or flight-visibility result.

## Deterministic and runtime checks

- [Placement and mask check output](placement-check.txt): four patches and 1,956 source triangles.
- [Placement generator tests](placement-tests.txt): four tests pass, including source-derived triangle counts, full-layout clearance against masks, deterministic generation, and input-hash stability.
- [Godot habitat test](runtime-test.txt): 23 checks pass. It independently traverses emitted mesh surfaces and `MultiMesh` batches, verifies deterministic plant records and tiers, validates custom-input skips and read-only source inputs, and checks that no collision object is emitted.
- [Placement generator](../../../../../../tools/trees/place_woodland_edges.py), [placement tests](../../../../../../tools/trees/test_place_woodland_edges.py), [generated recipe](../../../../../../app/data/woodland_edges.json), and [runtime test](../../../../../../app/tests/test_woodland_edge_habitat.gd).

Final R3 world replay and unchanged sampled trim/runway evidence are in [the final world report](../world-final/README.md). The woodland geometry is decorative and does not alter the collision world.
