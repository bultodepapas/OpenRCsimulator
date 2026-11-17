# T15 — Dependency locality, packaging and compression

**Research date:** 2026-11-17. **Status:** proposal; no runtime measurements. [Twenty-investigation index](README.md).

**Question.** Can grouping the files actually consumed by a selected visual reduce its cold storage/decompression work without loading, duplicating or retaining the rest of the fleet? Packaging is an experiment on access locality; it is independent of T11's retention policy and T14's revision identity.

## Search and evidence

Actual queries on 2026-11-17: `site:docs.godotengine.org Godot 4 exporting PCK zip load_resource_pack replacement cache override resources`; `site:docs.godotengine.org godot asset dependency get_dependencies runtime resource PCK package compression`; `site:docs.godotengine.org Godot 4 resource importer texture compression VRAM compressed uncompressed lossless file size GPU memory`; `site:learn.microsoft.com DirectStorage Windows 11 API GPU decompression prerequisites`.

- [Godot 4.5 exporting packs](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_pcks.html) describes PCK/ZIP packs and runtime mounting. It does not promise that mounting a pack eagerly loads all its resources or that repacking alone accelerates reads.
- [Godot ResourceLoader](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html#class-resourceloader-method-get-dependencies) exposes resource dependencies; enumeration must be supplemented by observed builder/script loads and embedded assets to obtain OpenRC's actual closure.
- [Godot CompressedTexture2D 4.5](https://docs.godotengine.org/en/4.5/classes/class_compressedtexture2d.html) distinguishes file compression and GPU-resident compression. Quality and decode/upload costs differ by format.

Accessed 2026-11-17. These stable/4.5 pages do not establish 4.8-beta2 package performance. [Microsoft's DirectStorage API reference](https://learn.microsoft.com/en-us/windows/win32/dstorage/dstorage-portal) is Windows-specific; it is not a drop-in cross-platform Godot `ResourceLoader` feature or a substitute for the normal macOS/Compatibility path. No change to platform APIs is recommended by these sources.

## OpenRC seam and candidate

[HomePreviewResources](../../../../../app/ui/home_preview_resources.gd) reads a family manifest to select one stock GLB path. [AirplaneBuilder](../../../../../app/render/airplane.gd) then loads and validates its model registry, builder and selected appearance; for example, [MT8's builder](../../../../../app/vehicles/ground/mt8_model.gd) loads and instantiates its own GLB. Dependencies can include embedded geometry/textures, external resources, scripts, per-skin archives or materials, and shared assets. Source and generated assets have separate owners; vehicles need not share one GLB structure.

Instrument the existing release package first: capture resources actually read by a selected model, decompressed bytes, repeated/shared dependencies and offsets/read count where tools permit. Build a dependency inventory from export manifests and `get_dependencies()`, then reconcile it with dynamic builder and runtime traces. Group commonly requested visuals and version-matched dependencies where possible; preserve deliberately shared resources. Keep catalog/thumbnail metadata separately accessible, so opening or searching 100/1,000 records does not prepare the full fleet. Avoid one eagerly decompressed fleet bundle; many tiny packs may also harm locality. A pack being large on disk alone does not mean its entire contents are resident.

Compare stock export organization with a **small representative** family/appearance grouping through the existing Godot export/loader. Preserve virtual paths, dependency closure, manifest verification, copyright/source provenance, and current import/skin safety limits. Use deterministic generated manifests; do not hand-edit generated vehicle assets. Runtime imports may remain in their existing content-versioned owner; PCK/ZIP distribution is not a requirement imposed on users. Avoid overwriting mounted paths to simulate updates while old resources are live; T14 owns revision safety.

Compression choices are separate variables: keep source art unchanged; compare compatible imported texture/mesh forms and any tested container compression. Smaller package bytes can increase CPU decode, staging memory or first-draw latency; VRAM compression may lower residency but introduce artifacts and platform-specific formats. Do not infer GPU memory from compressed archive size. Include image quality, alpha, normals, color space and mipmaps in acceptance. A different DirectStorage integration would need its own Windows-specific engine, storage format and fallback work, so this experiment does not depend on it.

## Experiment and decision

A is the current packaged layout; B changes grouping only, holding asset bytes, quality, cache state, pins and request order constant. Test an explicitly documented compression variant separately so grouping and codec effects are distinguishable. On named target systems run fresh process/cold-storage conditions where controllable and warm repetitions, with single selections, revisits, skin changes and imported content. Record accessed/compressed/decompressed bytes, read count or seek proxies, CPU decode/transcode and validation, build/upload/first-draw times, total selection-to-correct-frame p50/p95/p99, package size, duplicated shared bytes and peak RSS/renderer counters. Qualify 1080p and both supported renderer paths as applicable; verify each exported package independently.

**Reject** B if complete cold or common-session benefit fails to exceed baseline variation, warm paths or package/update cost regress outside predeclared tolerance, dependencies or validity change, shared data is duplicated excessively, or the result depends on loading unrelated fleet assets. A locality change is not justified merely by fewer files or a smaller archive.

**Recommendation and step:** capture real closures in UI-VS-00; make locality a conditional packaging trial under UI-VS-09 with AS/VQ and delivery owners, and qualify shipped builds in UI-VS-12. Retain the existing layout if the experiment is inconclusive. No package or latency test was run for this note.
