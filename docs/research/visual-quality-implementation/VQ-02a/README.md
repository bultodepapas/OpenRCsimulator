# VQ-02a — texture inventory and remaining qualification

2026-10-14. Read-only static and bounded runtime inventory delivered.
Import/material corrections remain gated by VQ-01c/d. No production assets, import
settings, materials, physics or goldens changed in this slice.
Commands and tool scope live in the [tool contract](../../../../research/performance/README.md#runtime-texture-inventory-vq-02a).
The first correction, [VQ-02a-R1 roof map mipmaps](roof-mipmaps/README.md) (2026-10-21), is recorded separately.

## Source and evidence

The expanded audit uses tracked source commit
`5f7f4ad529940743bdc16e3d9691243a8a1c6cd8`, archived with `git archive ... app assets`.
It excludes dirty/untracked work, including the concurrent Avanti integration.
The static scan uses a pristine extraction. Runtime uses a separate extraction
imported by Windows Godot **4.7.2 ed1daf0bf**, then Compatibility on the
**NVIDIA GeForce RTX 3090, driver 610.88**, Dummy audio.

[Verification and hashes](coverage/verification.json) identify the source archive,
engine, tools and reports. Import normalized 172 existing sidecars and generated
45 files outside the import cache in the disposable snapshot; all changed tracked
inputs were sidecars. This is recorded separately from the pristine static audit.
No import ran against the shared working tree.

The [original foundation inventory](texture-inventory.json) remains historical:
54 texture imports, 11 GLBs and three embedded images counted but uninspected.
The new snapshot has additional tracked assets; its larger counts are not a
performance regression or a before/after import comparison.

## Results

The [expanded static inventory](coverage/static-inventory.json) contains:

- 172 sidecars: 100 texture imports and 72 other imports.
- 52 parsed PNG/JPEG sources and 48 unsupported SVG headers; no missing sources.
- 12 GLBs; **25 embedded PNG/JPEG headers inspected and payloads hashed**:
  22 in the Avanti asset and three in HX-700.
- 52 external image references explicitly uninspected as GLB payloads; the tool
  does not fetch URIs. Standalone import records remain a separate view.
- 39 shader/include files, 16 sampler declarations and eight resource references.

Exact core glTF references record base-color/emissive sRGB roles, linear normal
data, G roughness, B metallic and R occlusion. Alpha remains linear. No conflicting
role reuse or automatic review candidate was found in this snapshot. This does
not qualify encoded pixels, extensions, image profiles, provenance or runtime use.

The [native runtime inventory](coverage/runtime-final.json) records assigned
resources, including hidden/overridden assignments, not effective GPU draws:

| Off-tree case | Nodes | Materials | Texture resources |
| --- | ---: | ---: | ---: |
| Default fixed-day world | 268 | 129 | 36 |
| Stik | 168 | 45 | 3 |
| Extra | 50 | 15 | 0 |
| P-51 | 151 | 28 | 0 |
| Avanti | 45 | 5 | 0 |
| Timber | 47 | 12 | 0 |

Of 39 case-local texture resources, **33 returned images** with format, mip count,
byte size and hash. Six ViewportTextures were deliberately not read back. Four
ImageTextures have no resource path, demonstrating coverage beyond import sidecars.
Zero assigned textures does not mean missing materials: these family builders can
use procedural geometry, vertex colors and material parameters. In particular,
the frozen Avanti builder does not yet consume the embedded maps in the tracked
GLB; the concurrent integration is outside this evidence.

CPU image byte sizes are not resident VRAM. Resource IDs and consumers can be
followed through each case's `resource_links`; no cross-case residency total is
claimed. The world uses resolved scenery high/on and landscape upgrade on. Audio
and birds are configured on, but nodes stay off-tree and do not process.
Persistent campfire/flame-atlas and club-lighting assignments are included even
with the campfire effect disabled. The largest single CPU readback is 22,369,620
bytes; the probe has no per-image allocation cap. Its commit label is supplied by
the caller; the separate archive/import hashes establish this run's source identity.

## Verification and limits

[All 18 Python tests pass](coverage/static-tests.log), including malformed chunks,
buffer ranges, bounded streaming, unsupported/URI images, role reuse and
determinism. The [native fixture passes](coverage/runtime-fixture.log): shared
textures/materials, MultiMesh, overrides/overlay/next pass, shader defaults, mip
byte sizes, repeated scans and unchanged assignments. Repeated static and native
reports are byte-identical; hashes are retained in the verification record.
Existing-output and headless guards return 2 without overwriting/creating reports.

The [full native process log](coverage/runtime-final.log) retains **two GL texture
teardown errors, 349,524 bytes each**, after the success marker. Waiting two process
frames after releasing local builder references does not remove them. Inventory
generation exits zero, but clean shutdown is **not qualified**; this probe has not
attributed those warnings to production or the observer. It is not a timing,
resident-memory, leak-repair or lifecycle acceptance result.

Remaining coverage: Home/UI, aircraft night kits, conditional weather, flight-only effects,
rotorcraft/ground vehicles, sampler arrays/global textures, deep containers,
unsupported source formats, external GLB image resolution and pixel/provenance
qualification. Continue targeted consumer review against a frozen VQ-01c/d source
before selecting a correction; retain baseline appearance unless a paired moving
comparison supports the change.

## API evidence

The pinned fixture confirms that `Shader.get_shader_uniform_list()` hides uniforms
with default textures. The observer queries RenderingServer's parameter list and
resolves Shader defaults explicitly. The behavior is also visible in the
[engine implementation](https://github.com/godotengine/godot/blob/master/scene/resources/shader.cpp).
This prevents an apparently empty shader inventory from silently losing a binding.

Channel meanings follow the
[glTF 2.0 material specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials).
Readback scope follows the
[Godot Image API](https://docs.godotengine.org/en/stable/classes/class_image.html)
and [Shader default-texture API](https://docs.godotengine.org/en/stable/classes/class_shader.html).
These references describe contracts; the retained pinned-engine runs establish
what this audit exercised.
