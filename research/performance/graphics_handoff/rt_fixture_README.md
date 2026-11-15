# Offline ray-query and sunlight-energy fixture reference

2026-11-15 · Executable preparation for existing M4 / RT-01–06 in the [graphics audit](../../../docs/research/graphics-performance-2026-11-15/15-ray-tracing-fixture-handoff.md). This small Python reference and its hand-specified cases are outside `app/`. They need Python 3.10+ and the standard library only. They have no Godot, GPU, network, measurement collection, settings, physics or production integration. The native implementation is a separate [work order](../../../docs/research/graphics-performance-2026-11-15/ray-tracing/03-vulkan-fixture-work-order.md), with newly identified pinned-engine prerequisites.

## Run the actual offline checks

From the repository root:

```sh
python3 -B -m unittest discover -s research/performance/graphics_handoff -p 'test_rt_fixture_reference.py' -v
```

The suite contains **26 test methods**, including table-driven cases. [rt_fixture_cases.json](rt_fixture_cases.json) contains **14 geometric cases** and **five ideal light-energy cases**, with expected values recorded independently of the evaluator. [rt_fixture_reference.py](rt_fixture_reference.py) evaluates them; [test_rt_fixture_reference.py](test_rt_fixture_reference.py) also checks rejected inputs, mask/ID bounds, data ownership and ambiguity. This command executes no graphics API. The DRS reference remains a [separate specimen](README.md) and is not rerun by this command.

## The exact domain

Geometry is opaque, two-sided triangles in render-space metres, Y-up. Every vertex, transform coefficient, ray component and interval endpoint is explicitly converted to finite binary32. Geometry calculations then use Python's standard-library `Fraction` for exact rational plane intersections, affine transforms, barycentrics and closest ordering over those rounded inputs. Returned numeric fields are float64 approximations. The implementation is deliberately small and slow compared with a renderer; it is a correctness reference for this finite corpus, not a replacement for a free production ray-tracing library or a GPU precision model.

`transform_rows` means three **mathematical** local-to-world rows, each with three linear coefficients and translation. It is not a declaration that those JSON bytes can be copied directly into Godot's `Basis`, a push block or a Vulkan structure. The native adapter must use the verified RD constructor/ABI and keep object-space geometry separate from instance transforms.

For an exact input ray, `P(t) = origin + t × direction`. The reference does not normalize direction. `t` is that parameter; `distance_m = t × length(direction)` is reported separately. Instance masks and ray `cull_mask` are eight-bit integers; `instance_custom_index` is the supplied 24-bit application index. Primitive index is the triangle's position within its single geometry. These are distinct from a TLAS array index or geometry index. Fixture custom IDs are unique by design, although uniqueness is not asserted as a universal Vulkan requirement. A miss has no meaningful hit distance or identity; the JSON uses explicit `null` fields.

Vulkan traversal has no candidate-order guarantee, and its [closest-hit rules](https://docs.vulkan.org/spec/latest/chapters/raytraversal.html) allow equality at the current maximum to be retained or dropped. The native closest-hit diagnostic must complete traversal without `TerminateOnFirstHit`; a later binary visibility optimization can assert hit/miss only. Exact endpoints, triangle edges/vertices, coplanar rays and equal nearest hits are outside this fixture's strict GPU acceptance domain. The reference raises `AmbiguousFixture` when it encounters them rather than inventing a unique portable result. This is a deliberately conservative domain exclusion, not a claim that every edge operation is unspecified by Vulkan.

The original float64-only draft misclassified small, non-axis-aligned exact endpoint, edge and tie cases. Independent review supplied dyadic counterexamples, which are retained as regression tests. Exact rational arithmetic fixes those **ideal geometric classifications** without widening a global epsilon or shifting a hit into a miss. It still does not establish the GPU's arithmetic error bound. Native comparisons must predeclare an appropriate float32 tolerance for the bounded interior corpus and inspect validation errors; do not require general bit equality or use these tests to qualify arbitrary production meshes.

## Independent answers that catch integration mistakes

| Case | Hand-specified answer and purpose |
| --- | --- |
| Raised identity triangle | Local `(0,0,0)/(2,0,0)/(0,0,2)`, translated to y=2. Ray from `(0.5,0,0.5)` upward hits at t=2 m, custom ID 7, primitive 0, barycentrics `(0.5,0.25,0.25)`. Side/away rays miss. |
| Affine near/far instances | Rotation, nonuniform scale and translation produce near t=6 m/custom 66051 and far t=10 m/custom 73. Far is listed first; reversing order preserves the nearest answer. Masking out near selects far. |
| Non-unit direction | The same near intersection with direction `(0,2,0)` gives t=3 and distance 6 m. Normalizing it without adjusting the parameter changes the answer incorrectly. |
| Tilted triangle | A nonzero local y coordinate makes the transform's y scale observable: correct t=6.75 m; ignoring that scale gives 6.25 m. A flat y=0 mesh alone could not catch that error. |
| Changed transform / interval | Moving near aside exposes far; intervals entirely before/between surfaces miss; an interval past near still finds far. This is expected-data preparation, not proof that an engine updates a TLAS. |
| Small nearby blocker | A receiver-origin offset of 1/4096 m misses the receiver but preserves a distinct blocker at y=1/512 m, t=7/4096 m. An excessive offset erases it. This is a bounded case, not a universal self-intersection cure. |

The expected values are not regenerated from the reference during tests. The native adapter should consume the same case inputs and compare its witness independently. Its initial compact witness can omit barycentrics; do not claim fields were checked that it did not produce. The exact work order explains GPU buffer fields and sentinel handling.

## Lighting contract and its limits

The ideal linear fixture separates ambient, emission, already-treated other lights, unshadowed Sun diffuse and unshadowed Sun specular. It defines:

```text
effective_visibility = 1 - opacity * (1 - raw_visibility) * (1 - fade_to_lit)
sun_factor = effective_visibility * cloud_transmission
total = ambient + emission + other_lights
      + sun_diffuse * sun_factor + sun_specular * sun_factor
```

`fade_to_lit` is an already evaluated blend weight, not distance. Inputs are finite nonnegative linear radiance; HDR values above one are valid. Factors lie in `[0,1]`. `other_lights` already includes the second directional light's existing cloud/visibility policy and is preserved. The input Sun terms exclude old raster visibility. The JSON's `previous_raster_visibility` is context for the **future native replacement test**; this pure evaluator intentionally does not consume it. Its passing tests cannot prove that an actual shader replaced rather than multiplied the raster term.

The five recorded cases use binary-exact values. Fully blocked Sun with full opacity/no fade leaves `(0.40625, 0.25, 0.21875)` from ambient/emission/other light. Unblocked Sun produces `(0.6875, 0.4375, 0.40625)`. Raw zero with opacity 0.5 and fade-to-lit 0.5 gives effective visibility 0.75 and total `(0.6171875, 0.390625, 0.359375)`. Component checks preserve direct specular and prevent accidental repeated cloud attenuation; they are stronger than checking total darkness alone.

The exact Godot pin reconstructs a packed eight-bit shadow factor, applies shadow opacity and calls its blur policy before `light_compute`. This reference does **not** implement that quantization, BRDF, exposure, tonemapping, MSAA or post-processing. Select the actual replacement seam and native image tolerance before expecting matching pixels. Keep raw visibility, linear component checks and final-image/readability checks as different evidence.

## Use, review and retirement

Use this finite corpus during the first engine/ABI witness and selected-sun fixture. Port the relevant independent answers into the smallest existing native harness when the real adapter exists; keep existing checked-runner and test-queue ownership. A source-checked recipe, passing Python tests, shader compilation and one GPU hit are different claims. Normal-flight coverage, temporal lifetime, lighting, pilot readability, cost and package qualification remain open.

Do not add collectors, telemetry, an automated benchmark service or a second scene system here. This is research preparation within the requested handoff, not another M0 instrument or mandatory delay before a product correction. M0 remains five engineering days total; M4 retains its two-day feasibility and two-week useful opaque-fixture checkpoint. Once production/native tests cover these independent cases, consolidate them into that owner and retire the duplicate reference. Actual local checks and deliberate-regression evidence are recorded in the [fixture receipt](../../../docs/research/graphics-performance-2026-11-15/evidence/rt-fixture-validation.json).
