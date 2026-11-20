# Phoenix GEO feasibility protocol

Status: proposed experiments, 2026-11-18. No experiment below has been run in Phoenix Builder or PhoenixRC by this audit. No GEO offsets, complete grammar or decoder compatibility are established. The [parent plan](../phoenix-aircraft-import.md) owns AC-PX-03 status; the [implementation guide](implementation.md#7-geometry-conversion-and-the-unresolved-geo-gate) owns normalization and the Creator output contract. This document specifies how to obtain evidence before implementing a binary layout.

## 1. What the additional research actually supports

The reviewed sources provide useful workflow controls, not a complete GEO specification:

| Primary source / provenance | Useful evidence | Limit |
| --- | --- | --- |
| [Phoenix Builder user guide copy](https://www.scribd.com/document/739064752/UserGuide) | Describes local Test/Publish exports, separate mesh/material/physical editing, grouping/parenting and an auxiliary UV export for a scheme. | Mirror version/provenance is not verified. It does not establish every export's extractable members or the UV file's format. |
| [Creator's RC Universe posts, January–February 2015](https://www.rcuniverse.com/forum/rc-flight-simulator-software-138/11612102-phoenix-builder.html) | Reports initially invisible imported geometry, a rudder moving away from its fin, then successful OBJ import with Blender's Write Normals option. | Firsthand experience, not a universal setting requirement. The author had not yet tested that revised OBJ import in the simulator at the time of the normals report. |
| [SupermotoXL Eagle II author workflow](https://mail.supermotoxl.com/projects-articles/ready-to-drive-fly-models/dancing-wings-hobby-eagle-ii-phoenix-r-c-simulator.html) | Describes OBJ mesh import followed by functional control/attribute setup in Builder; identifies Builder v1.0.p and simulator 5.5 for that author's workflow. | Does not provide a verified original-source/GEO pair in this audit. Subjective flight similarity is not physical validation. |
| [Blender 3.2 OBJ import/export documentation](https://docs.blender.org/manual/en/3.2/addons/import_export/scene_obj.html) | That documented route does not carry parenting/transforms, and importing/splitting can change representation and vertex order. | Version-specific guidance, not a statement about every later Blender or Phoenix importer. Authoring hierarchy alone cannot prove the Builder hierarchy. |

These controls motivate normal/winding, hinge, transform and post-import-state measurements. Source access did not establish a complete GEO specification or a newly verified editable-source/export pair. That search outcome does not prove none exists. The linked [corpus catalog](../../research/aircraft-creator/phoenix-corpus-catalog-2026-11-17.md) remains useful for later lawful compatibility sampling; community download counts cannot substitute for known geometry truth.

Builder is a proposed developer investigation tool, not an end-user import dependency. Do not run downloaded installers, package code or malformed files as part of this documentation task. A later explicitly authorized operator uses an appropriate legitimately obtained installation and owned/permissioned fixtures. Preserve source and redistribution rights separately from technical results.

## 2. Capture four separate states

| State | Required record | What may be compared |
| --- | --- | --- |
| Authored source | Exact editable project and OBJ/dependencies, hashes, tool/export version/settings; independently specified vertices, corners, UVs, normals and materials | Source-space facts, including expected permutations or transforms |
| Builder after import | Actual imported objects, materials, grouping, transforms, Size, physical setup and hinges; settings/project identity and available numerical observations | Whether Builder retained, changed, omitted or recomputed authored data |
| Captured export | Exact Test/Publish route, complete package/member inventory, raw hashes and occurrence identities | Frozen wrapper and corresponding member differences; not guessed compressed offsets |
| Optional simulator observation | Separately authorized execution identity, selected aircraft/scheme, camera/lighting/control state and measured pose/render data | Corroborating exported behavior; no numerical equivalence or flight fidelity from a screenshot alone |

Do not silently treat the first and second state as equal. If import changes geometry and the change cannot be independently characterized, the source-to-export comparison is inconclusive. Record whatever minimum physical/model setup Builder actually requires; keep it constant and separate from the test geometry. A failed import is useful evidence but supplies no GEO layout.

Record the exact Builder executable/version identity, acquisition provenance, OS, locale, all relevant settings and project paths. The guide's local Test/Publish directories are workflow leads, not hardcoded product dependencies. Capture outputs before reusing a filename; preserve every replicate. An auxiliary UV file from Builder can cross-check its own outputs, but is not an independent oracle for that same encoder.

## 3. Original asymmetric source fixture

The following hand-authored OBJ is original test data: a tetrahedron and a separate marker triangle. It has seven position records, five triangle faces, fifteen face corners and bounds `(0,0,0)` to `(9,3,5)`. It is a **source oracle**, not a claim of successful Builder import or direct Creator admission.

```obj
v 0 0 0
v 2 0 0
v 0 3 0
v 0 0 5
v 7 0 0
v 9 0 0
v 7 1 0
vt 0 0
vt 1 0
vt 0 1
vt 0.25 0.25
vt 0.75 0.25
vt 0.25 0.75
vn 0 0 -1
vn 0 -1 0
vn -1 0 0
vn 0.7894736842105263 0.5263157894736842 0.3157894736842105
vn 0 0 1
o bodyA
f 1/1/1 3/2/1 2/3/1
f 1/1/2 2/2/2 4/3/2
f 1/1/3 4/2/3 3/3/3
f 2/1/4 3/2/4 4/3/4
o markerA
f 5/4/5 6/5/5 7/6/5
```

The first four face cross products are `(0,0,-6)`, `(0,-10,0)`, `(-15,0,0)` and `(15,10,6)`; the fourth unit normal is `(15,10,6)/19`. The marker cross product is `(0,0,2)`. Supplied decimal normal components approximate that exact rational and require a predeclared tolerance. Position records deliberately have different per-corner UV/normal associations. Do not lose those seams when comparing vertices.

No MTL is needed to describe this initial untextured source. Record the default material and any extra setup the actual Builder requires. Introduce a tiny original known texture and explicit material in the later material baseline, and freeze that baseline before changing its assignment. Do not guess image orientation from these UVs or import unsupported source features merely to make the fixture look plausible.

## 4. Control noise before interpreting bytes

First freeze a successful minimal workflow. Keep the same project/display/output names and paths while generating variants; copy the captured outputs into distinct experiment locations afterward. Renaming output files between A and B can contaminate a serialized-name comparison.

Obtain at least A1/A2/A3 baseline replicates, B1/B2/B3 repetitions of a single-concept change, and a return-to-baseline A4, plus a fresh-session A when available. Each B starts from the same verified A project. Interleave A/B where practical without changing other state. Three replicates are exploratory noise controls, not a statistical confidence guarantee.

Compare corresponding layers: full capture for identity, then independently checked package/member occurrences. Compression, metadata, revision fields, paths, padding, random values and reordering are possible explanations for differences, not asserted properties of GEO. A stability mask can suggest experiments; it cannot authorize ignoring unknown bytes or establish that unchanged bytes are geometry.

Keep a hypothesis ledger with exact input/output hashes, observed candidate byte ranges, proposed representation/stride/endianness, expected change and invariants, alternative explanations, actual observations and disposition. Freeze the hypothesis before viewing a held-out variant. Require at least two meaningful controlled deltas and a counter-change, then corroboration with different objects/values and a second independently authored workflow before broadening a profile. If the held-out answer changes the hypothesis, start a fresh held-out evaluation.

## 5. Sixteen controlled experiments

E00–E15 are proposed investigation rows, **not sixteen passed tests**. A row may require several separately controlled A/B pairs. Every pair records all changed tokens/settings and unchanged controls.

| ID | Deliberate change | Independent oracle / question |
| --- | --- | --- |
| E00 | Repeat export and reopen the unchanged project. | Source facts remain equal. Identify reproducible noise or uncontrolled state before proposing any field. |
| E01 | Change marker vertex 6 x from 9 to 9.5, with all other data/settings fixed. | Source max x becomes 9.5; marker normal stays +z and body corners stay identical. A *hypothetical* direct float32 little-endian position would change `00 00 10 41` to `00 00 18 41`; transformed/quantized storage predicts something else. Test additional axes/signs/values after freezing the hypothesis. |
| E02 | Change only marker's second UV from `(0.75,0.25)` to `(0.625,0.25)` after establishing a retained texture/UV baseline. | Only that source corner's u changes. Determine whether Builder retained it; inspect all output members and any auxiliary UV artifact. No inference of image origin from a matching float. |
| E03 | Change only one supplied normal; separately test normals omitted versus written in a pinned exporter. | Source normal changes while geometric face normal does not. Detect retention, recomputation or omission before asserting a GEO normal field. |
| E04 | Reverse the last two marker face corners, leaving supplied normal unchanged. | Winding changes and deliberately disagrees with the normal in one case. Distinguish oriented topology, recalculated normals and two-sided/culling behavior. |
| E05 | Permute two vertex declarations and remap every affected face reference. | All oriented corner tuples and surfaces remain equal. Index/record order or hashes may differ; test semantic correspondence without assuming original indices survive. |
| E06 | Change marker material assignment; in separate pairs vary one RGBA component or texture bytes under the same name. | Preserve object-to-material-to-image association and known pixels. Also test same pixels/different names. All changed MOD/GEO/image members count as observations; no presumed storage location. |
| E07 | Apply one Builder object translation, rotation, nonuniform scale or reflection on one axis. | Compute world points from captured settings and a known multiplication order. Determine baked vertices, node transform or omitted change. A source-baked transform is a separate control. |
| E08 | Change only model Size; separately change one typed physical dimension. | OBJ bounds remain fixed. Measure actual Builder/export effects to discriminate scale hypotheses. Do not apply Size/100 or a common unit multiplier by name alone. |
| E09 | Move one hinge endpoint; separately change object assignment or travel. | Known neutral geometry stays fixed. Correlate MOD/GEO/other members with exact endpoints/roles/poses; no GEO change does not imply there is no hinge. Establish direction/sign separately. |
| E10 | Duplicate one object, then change/translate only one occurrence; test equal names if admitted. | Keep distinct source occurrences. Distinguish shared edits, instances and independent copies; equal serialized bytes alone do not prove shared identity. |
| E11 | Create an actual Builder parent/child relation where supported; move only parent; compare equivalent baked world geometry. | Establish composition and world-point mapping. OBJ hierarchy is not presumed transported. If flattened/refused, qualify only that observed behavior. |
| E12 | Add one referenced vertex and known face; separately use face-only and position-only controls. | Hand-known corner/count changes challenge record/count/index hypotheses. Vertex splits, deduplication and reindexing need explained mappings. |
| E13 | Create larger original meshes across a candidate index/count threshold, after a concrete layout hypothesis. | All vertices are referenced and distinct. Predict representation and bounds on both sides, or explicitly refuse the unqualified range. Do not assume GEO has a conventional index buffer. |
| E14 | Reorder independent object/material declarations while preserving semantics. | Correct identity and visible associations survive where the source semantics permit. If order is significant, document that scope instead of sorting it away. |
| E15 | Export a selected owned scheme's texture and auxiliary UV data if available. | Compare independently known UV corners and selected texture hash; establish artifact encoding/coverage/origin first. Shared Builder output is corroboration, not independent encoder proof. |

Use the existing [numeric geometry and image fixtures](verification.md#51-independent-numeric-fixtures) for the separate GLB/converter layer. The OBJ above deliberately has different dimensions and purpose; do not substitute its constants for those existing acceptance oracles.

## 6. Promote hypotheses only through falsifiable predictions

A proposed GEO profile must define its discriminant, record recognition, length/count/range rules, scalar encoding, nesting/references, alignment/padding and exact end condition. Unknown bytes are unclassified until explained; an unknown record is not automatically optional. Explicitly evidenced shared ranges may be legitimate references, but unexplained overlap refuses the affected capability.

Test competing storage models: interleaved/separate buffers, byte order, float/integer/quantized values, zero/one-based indices, position versus corner attributes, and duplicated/split vertices. A field claim must predict values **and their association** across E01–E05 and E12/E13. One plausible float, object-name string or matching count is insufficient. Material/image references need their own E06/E15 closure evidence; hinge semantics need E09 independently of static geometry.

Bind objects to capture, selected member occurrence/hash and internal structural occurrence. If repeated names or shared bytes leave a reference ambiguous, withhold that binding. Keep a decoder's ability to retain distinct occurrences separate from a claim about the encoder's internal storage sharing.

```text
qualify_layout(hypothesis, controlled_training, withheld_inputs):
    require known authored facts and characterized Builder post-import changes
    require exact frozen outputs and corresponding admitted member identities
    freeze grammar, predictions, domain and numeric tolerances
    for unseen fixture in withheld_inputs:
        decoded = bounded_candidate_reader(fixture.member, frozen_hypothesis)
        expected = independent_source_and_post_import_oracle(fixture)
        compare exact object/reference/material identities and multiplicities
        compare oriented triangle-corner tuples, UV/normal seams and world points
        compare bounds plus predeclared numeric max/RMS tolerances
        if unexplained mismatch: reject hypothesis for that advertised domain
    require independently authored second workflow before generalizing
    return evidence for this narrow profile only
```

When topology order differs but the underlying source semantics permit it, compare an **oriented triangle-corner multiset** per independently associated object/material. Cyclic rotations are equivalent; reversed orientation is not. A multiset preserves duplicate faces; a set would hide them. Corner identity includes position, UV, normal and material context. Specify matching/tolerances before seeing decoded output, including what happens to repeated/near-equal corners. Exact discrete mismatches never become numeric tolerance successes.

Report every mismatch and maximum/RMS numerical errors. Bounds and a screenshot supplement those comparisons, not replace them. If Builder changes topology or materials, prove the transformation's scope independently before declaring equivalent output. A decoder round trip through its own encoder is not independent evidence.

## 7. Negative cases, output proof and stop conditions

After a candidate grammar exists, create tiny owned malformed inputs for truncated fields, inconsistent lengths/counts, integer overflow, invalid indices/references, cycles, unexplained overlap, unqualified record classes and data after the permitted end. Feed these only to the reviewed bounded candidate reader, **never to the vendor program**. Require typed deterministic refusal with a real tagged location or explicit unavailable phase, and independently bounded allocations/work/cancellation.

Encode proven source geometry into the exact Creator GLB subset; validate the exact emitted bytes with a pinned independent glTF validator and Creator admission. Recheck world poses, materials, UVs, normals and supported hinges against the source oracle after conversion. A well-formed GLB can still represent the wrong aircraft. Static conversion does not prove motion or physics.

Stop the affected investigation or capability when:

- The owned source/export pair, exact workflow or independently characterized post-import state is missing: retain package/definition evidence, mark GEO feasibility blocked.
- Repeated output is unexplained, a field rests on byte coincidence, or a held-out variant disproves a hypothesis: preserve evidence and revise the experiment; do not patch per-model offsets.
- Winding, units, object/material association, normal/UV behavior, hinge sign or transform order is unresolved: withhold that specific visual/motion mapping.
- A qualified grammar, bounded malformed-input campaign, independent output checks or held-out workflow is absent: make no general production-GEO claim.

Later corpus compatibility is a separate campaign over exact lawful captured samples. Physical authoring, numerical gates, exported-platform behavior and flight measurements remain independently owned requirements even after GEO correspondence succeeds.
