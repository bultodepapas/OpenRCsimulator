# VQ-02a — read-only texture inventory foundation

2026-10-14. Inventory delivered; import/material qualification remains open.
See the [tool contract](../../../../research/performance/README.md) and
[machine-readable inventory](texture-inventory.json).

The current scan reports 126 import sidecars: 54 texture imports and 72 other imports.
PNG/JPEG headers were inspected for 52 textures; two SVG sources are outside that
header parser. It records 39 shader/include files, 16 sampler declarations, eight
resource-string/material references and 11 GLBs. Three embedded images in one GLB
remain explicitly **UNINSPECTED** at the payload level.

No automatic review candidate was raised by these bounded checks. This does not
establish correct color space, compression, pixel quality, runtime material bindings,
VRAM residency or complete asset provenance. GDScript-created materials are not resolved;
files with multiple shader assignments keep unknown context rather than borrowing the
first shader's hints. Missing `source_color` means unspecified, not a detected defect.

Ten inventory tests pass, including image header failures, unhinted samplers, ambiguous
material contexts, missing sources, bounded GLB metadata and deterministic output. No
imports, source assets or generated aircraft were changed. Review runtime consumers,
embedded image payloads and moving views after VQ-01c/d before correcting a specific
import or adopting a material change. [VQ-01c](../VQ-01c/README.md) records the shared
verification, engine/source identity and remaining acceptance gaps.
