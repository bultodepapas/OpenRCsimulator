# Night-lighting asset intake

FW-67 builds selected, redistributable runtime derivatives from immutable downloads under `assets/landscape/night-lighting/source/`. Read the source [ledger](../../assets/landscape/night-lighting/README.md) and the [current field-world guide](../../docs/FIELD-WORLD-PLAN.md#night-field-and-campfire) and [FW-66 research](../../docs/research/field-world/FW-66/README.md) before changing selection or conversion settings.

Run from the repository root:

```powershell
python tools/night-lighting/build.py
python tools/night-lighting/build.py --check
```

The build verifies every source file it uses against the SHA-256 and byte counts in `assets/landscape/night-lighting/PROVENANCE.json`, then writes only selected output to `app/assets/landscape/night-lighting/`. `--check` regenerates the same bytes in memory and fails on any missing or changed output. Pillow is pinned in [requirements.txt](requirements.txt); the conversion script otherwise uses the Python standard library.

The floodlight derivative keeps the left downloaded housing, lens, heat-sink ribs, bezel and adjustable arm. It bakes the housing-center pivot and source transforms, points the optical axis along local `-Z`, batches the body to one matte surface and retains one separate non-emissive lens surface. The sensor, second head and shared wall plate are omitted. `asset-manifest.json` records the source hash, output hash, scale convention, bounds, surface count and exact lens-center offset in metres. The runtime head remains at its GLB metre scale; the field-light fixture scale is owned by the renderer.

The Kenney `campfire-pit.glb` and its palette are copied byte-for-byte with the required relative texture path. Runtime presents this base at 3.6× on the helper's visual child (about 1 m across and 0.39 m high); the campfire root stays parent-positioned at ground level. The Mikodrak archive is not shipped. Its 80 unmodified 81×123 RGBA frames are packed in source order into an 8×10 atlas with 32 px transparent gutters; the atlas recipe and each frame rectangle are recorded in the manifest. The runtime uses a spatial shader to cap flame albedo against `Environment.tonemap_exposure`; ember material is unshaded albedo without emission, and the local OmniLight has its own exposure cap. No downloaded code executes. Smoke is omitted pending side-view quality review; wind currently gives an instantaneous presentation lean, with no wind history stored for checkpoint replay. The downloaded author notes and CC0 license evidence are retained beside the runtime assets.

The script has no network behavior and does not execute downloaded content. To select or replace a source, update the provenance record first, review the license evidence, then adjust the conversion and expected geometry metadata deliberately.
