# TT-00 — external Timber package assessment

2026-10-08 · **Status: complete as a static research/audit step.** No application integration or evaluated Blender export was performed.

Owning plan: [Turbo Timber Evolution integration](../../../TIMBER-INTEGRATION-PLAN.md). Supporting reports: [primary sources](sources.md), [code seams](code-audit.md). Machine-readable evidence: [source inventory](inventory.json), [Blender DNA audit](blend-audit.json).

## Scope and result

Inspected the user-supplied `Timber turbo evolution/` package without modifying or moving it. Read the actual catalog, renderer, flight session, loader, controls, trace and export seams. Researched manufacturer manuals/product revisions and official Godot import documentation. The source changed during initial inspection; the final evidence identifies exact bytes by SHA-256 rather than treating the `v12` filename as immutable.

The accepted audit snapshot contains 118 files and 139,757,658 bytes: 112 binary STLs, a Blender scene, a STEP, its ZIP duplicate, the scene sidecar and two Python scripts. All 112 STL names match the sidecar's material map; all declared hinge members exist. Every triangle vertex is finite; 26 triangles have exactly zero area. No manifold, self-intersection or mechanical-clearance claim follows from these checks.

| Measurement | Result | Interpretation |
| --- | --- | --- |
| Binary STL triangles | 1,134,030 | Full incoming tessellation, not a runtime budget |
| Both springs | 765,356 triangles (67.49%) | First simplification target |
| Both slat supports | 103,736 triangles | Second small-part target |
| STL global bounds, source units | X −283.461…832.700; Y −774.047…774.047; Z −255.994…178.000 | Millimetres inferred from manifest/geometry; establish formal frame in TT-02 |
| Blender blocks | 171 objects; 130 meshes; 20 materials; 7 cameras; 2 lights; 2 actions | Aircraft plus rig and studio content |
| Blender mesh faces | 1,432,290 | Stored faces, including helpers/studio; not evaluated exported triangles |
| Object relationships | 26 objects with drivers; 10 with constraints; none with modifiers | Static pointer presence only; does not evaluate the driver expressions |
| Scene units | metric, scale length 1 | Blender translation values are already metre-sized |
| Root stored transform | position [0, 0, 0.253613]; Euler [0, 0.171404, 0] rad | A presentation pose must not become the simulator's neutral flight pose |
| ZIP content | One STEP, hash equal to supplied standalone STEP | Duplicate delivery format, not another geometry revision |

The Blender source header is `BLENDER17-01v0502` inside Zstandard compression. Official Blender Python DNA readers were used externally; they read the file as data and did not execute its drivers. The only stored image datablock is `Render Result`; absence of image textures does not prove material export fidelity. The embedded 128×128 thumbnail was a generic cube and was not usable aircraft evidence.

The sidecar is valuable but incomplete: it has geometry/rig controls, not the repository's evidence-bearing flight-data schema. The source Blender rig has more complete parentage than the sidecar hinge-member lists. `Eje_motor` includes fixed mounts as well as the propeller, so an adapter must split fixed and rotating children. Full slat and float geometry was not identified by object/part names; evaluated visual inspection must settle their presence.

The added `tren_aterrizaje_v12.py` describes a photo-based parametric gear model. `auditoria_tren.py` needs missing caches and mechanical-analysis data and uses assumed geometric acceptance limits. Neither supplies real spring/damper or tire measurements. They were read, not executed.

## Reproduce the inventory

From repository root, with the original package available:

```bash
python3 research/timber/tt00/audit_sources.py \
  'Timber turbo evolution' /tmp/timber-inventory.json
cmp /tmp/timber-inventory.json docs/research/timber-integration/TT-00/inventory.json
```

The source folder remains an untracked external handoff. A clone containing only the audit cannot rerun source measurements without that package. The saved hashes, measurements and metadata remain reviewable without it. Do not overwrite the baseline when new source bytes arrive; record a new step/revision and compare the manifests.

## Reproduce the static Blender inspection

No Blender executable was installed. This probe uses official Blender reader code at commit `5998795aa64a99892895e784945f7dc763aeaa05`, `zstandard==0.25.0` and Python 3.12. It needs network access for the reader and Python package; they remain in `/tmp`, outside project dependencies. Reader hashes are embedded in the report.

```bash
mkdir -p /tmp/timber-dna-reader
curl --fail --location --silent \
  https://raw.githubusercontent.com/blender/blender/5998795aa64a99892895e784945f7dc763aeaa05/tools/modules/blendfile.py \
  --output /tmp/timber-dna-reader/blendfile.py
curl --fail --location --silent \
  https://raw.githubusercontent.com/blender/blender/5998795aa64a99892895e784945f7dc763aeaa05/scripts/modules/_blendfile_header.py \
  --output /tmp/timber-dna-reader/_blendfile_header.py
python3 -m pip install --target /tmp/timber-dna-reader/deps zstandard==0.25.0
PYTHONPATH=/tmp/timber-dna-reader/deps python3 research/timber/tt00/audit_blend.py \
  'Timber turbo evolution/turbo_timber_evolution_v12.blend' \
  /tmp/timber-dna-reader/blendfile.py /tmp/timber-blend-audit.json
cmp /tmp/timber-blend-audit.json docs/research/timber-integration/TT-00/blend-audit.json
```

This checks stored datablocks, parent links, transforms and mesh counts. It does **not** evaluate constraints/drivers, detect every external dependency, render materials, validate UVs or export a GLB. TT-01/03 must run a real compatible Blender and Godot import round-trip.

## Validation and limits

- Both audits rerun deterministically against the captured source snapshot; exact JSON comparisons passed.
- ZIP CRC/read and STEP content hash comparison passed.
- Local Markdown link targets and plan step IDs checked; both Python scripts compile.
- No app code, data, assets, ROADMAP or other aircraft plan was changed. Only additive entries were made to the documentation registries, with one reusable rig-import lesson added to the existing models/rendering guide.
- `app/test.sh` was not run: this delivery contains documentation and offline read-only audit scripts, not a gameplay change. No runtime, export, performance or flight acceptance is claimed.

## Sources and rights

Manufacturer/Godot links and field-specific references are in [sources.md](sources.md). [Blender's official reader](https://github.com/blender/blender/blob/5998795aa64a99892895e784945f7dc763aeaa05/tools/modules/blendfile.py) and [header parser](https://github.com/blender/blender/blob/5998795aa64a99892895e784945f7dc763aeaa05/scripts/modules/_blendfile_header.py) carry GPL-2.0-or-later headers; they were fetched for inspection and are not vendored into the simulator. [Blender 5.0 file-format changes](https://developer.blender.org/docs/release_notes/5.0/core/) explain why old file-header assumptions are unsafe.

The incoming aircraft source contains no explicit license/provenance file. Record author and redistribution terms in TT-01 before shipping those assets. Manufacturer documentation is used as attributed technical reference; no manual, photos or marketing artwork were copied into the repository.
