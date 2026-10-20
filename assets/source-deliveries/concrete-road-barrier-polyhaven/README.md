# Poly Haven Concrete Road Barrier source

Source: [Concrete Road Barrier](https://polyhaven.com/a/concrete_road_barrier) by Amal Kumar, published by Poly Haven under [CC0](https://polyhaven.com/license). The source package was downloaded on 2026-10-20 from Poly Haven's official API. [`source-manifest.json`](source-manifest.json) records each exact official URL, API MD5 and downloaded SHA-256.

The source Blender file contains six author-provided LODs. The runtime [LOD2 GLB](../../../app/assets/landscape/track-barrier/concrete-road-barrier-lod2.glb) uses the supplier's 2,359-vertex, 4,722-triangle LOD2 mesh and original UVs. It embeds the official 1K diffuse, OpenGL normal and ARM JPG maps from the supplied glTF material; no new mesh was modelled or decimated. Rebuild it with [`export_track_barrier_lod.py`](../../../tools/landscape/export_track_barrier_lod.py) in Blender 5.2.2 LTS.

The exported local Y-up mesh measures 1.54446 m along X, 0.83163 m high and 0.63661 m deep. The application scales it into each authored track barrier footprint. These are visual dimensions; the collision envelopes remain defined by the track data.
