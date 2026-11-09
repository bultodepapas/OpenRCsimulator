# TT-21-R1 — preserve Lumber LODs through visual repair

2026-11-09. Implements the first second-pass recommendation in
[`TRIANGULOS.MD`](../../../../../external%20Audits/TRIANGULOS.MD), checked against
`8fb825a96dbc39fbbf99c1056ba643c9cde49b5d`. Existing tree/backlight work in the
shared checkout is outside this change. The imported r2 GLB is unchanged.

## Repair and compatibility

The paint-seam repair rebuilt every surface without the imported LOD dictionaries.
Unmodified surfaces now retain their primitive, arrays, format, names, materials
and LOD distance/index data. Cold builds and cache hits use the same template.
The cache fingerprint includes surface formats and sorted LOD distances/indices;
its eight-entry capacity is unchanged. Templates retain no instance/material references.
Split or normal-smoothed surfaces retain the existing full-detail fallback: their
new vertex indices cannot safely use the original LOD buffers. The source shadow
mesh is not attached across a changed surface layout.
Retaining LODs adds index buffers; it does not establish a resident-memory saving.

Custom paint still uses the distributed Timber kit identity
`1cfbbec926b1589005a35769d957edcd3e67e7edfe690278aefd2b5f627540e6`.
`CustomSkin` recognizes exactly that family/kit identity paired with the reviewed
new full procedural identity
`45bd45bff9cd6617839d24b8ab84200f5edb6de82c226939df7bb2c3b280bf69`.
The existing manifest/source proofs remain required. A later source or model change
does not match this pair and must be reviewed again; wrong-family/hash rejection
is retained. `procedural_skin.gd`, the distributed kit ZIP and archive format are unchanged.

The owning kit registry's prepared-source fingerprint is now
`3ac6b122d7c6cf9c9014c03515644f55d9d67a27ff56c8faa198e397e4a5c045`,
reproduced in two independent checked exports with pinned Godot 4.8 beta 2 on Windows.
The pre-repair helper exported `465d4168ed0856d763fe10c5fc9d2ea448392a239bf62ae38637636cd94e08e7`
on the same engine, already different from the old `2b192c…` generation pin.
Only the generation fingerprint changed; the paint compatibility identity did not.
The existing kit passed its archive checks; a new Blender kit was not generated.

## Native 1080p evidence

Windows, Godot `4.8.beta2.official.cafc17a19`, Compatibility/OpenGL3,
RTX 3090, NVIDIA driver 617.42. The existing Timber inspector ran with matched
fixed cameras, lighting, controls and source data. A preserved pre-change helper
provided the baseline. Images and source-specific manifests remain under ignored
`tmp/triangle-lod-20261109/`; no review images were added to Git.

| 50 m pose | Raw primitives before | After | Draw calls before/after |
| --- | ---: | ---: | ---: |
| Level crossing | 29,465 | 24,827 | 143 / 143 |
| Roll −60° | 29,465 | 24,827 | 143 / 143 |
| Roll +60° | 29,465 | 24,827 | 143 / 143 |
| Nose toward pilot | 29,459 | 24,821 | 143 / 143 |

Stock and custom-painted aircraft produced the same counts: 4,638 fewer raw
submitted primitives, approximately 15.7%, in each isolated view. These are engine
submission counters, not source geometry, GPU time or whole-flight FPS. The inspector
now retains the raw counters beside each capture for future comparisons.

Matched pixel comparisons cover eight close and eight 50 m views, including full
control deflection and banked poses. Close views changed at most 58 RGB pixels and
one foreground/silhouette pixel; 50 m views changed at most 21 RGB pixels and two
foreground/silhouette pixels. Eight additional close-view comparisons with automatic
LOD disabled were pixel-identical. This control separates intended LOD selection
from base geometry/finish changes. Static image inspection found no broken outline
or paint placement; moving pilot readability and whole-flight hardware acceptance
remain open. Metrics are in `pixel-comparison.json` beside the raw captures.

## Verification

Checked Godot runs passed:

- Procedural paint: 3,458 checks, including base/LOD attribute and geometry mapping.
- Existing Timber-format custom skin through `Airplane.build`: 89 checks.
- Custom-skin admission and rejection: 47 checks.
- Timber visual isolation: 164 checks, including source triangles, articulation,
  factory lights and Wreck bounds.
- Detail textures and paint material strength: 23 checks.

The kit archive tests passed (two tests), and the nine-language guide is current.
All 16 native capture processes and both candidate prepared-scene exports passed
the checked runner. The complete application/CI suite was not run for this bounded
rendering change. No flight equations, physics data, triangle ceilings or golden
flights changed.

Use the [existing inspector](../../../../../assets/aircraft/turbo-lumber-evolution/README.md#verification-and-review)
and [skin tooling](../../../../../tools/skins/README.md) for reproduction; the checked
logs, frozen helper and generated GLBs are under `tmp/triangle-lod-20261109/`.
