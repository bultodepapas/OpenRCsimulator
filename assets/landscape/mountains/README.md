# Club mountain sources (LU-16-R1/R2)

2026-10-20. Downloaded elevation data, not a surveyed simulator field.

`chingaza.hgt.gz` retains a lossless crop of the public Mapzen Terrain Tiles
`N04W074.hgt.gz` tile, covering 4.42–4.72° N and 73.96–73.70° W in the Colombian
Eastern Cordillera. Data attribution: **SRTM data courtesy of the U.S. Geological
Survey; Mapzen Terrain Tiles**.

- [Dataset and anonymous download access](https://registry.opendata.aws/terrain-tiles/)
- [Exact upstream tile](https://s3.amazonaws.com/elevation-tiles-prod/skadi/N04/N04W074.hgt.gz)
- [Provider attribution and SRTM public-domain terms](https://github.com/tilezen/joerd/blob/master/docs/attribution.md#srtm)

The source is 937 columns × 1,081 rows of big-endian signed int16 elevations in
metres; rows run north to south. No void samples occur in this crop.

| Artifact | SHA-256 |
| --- | --- |
| Downloaded tile archive | `2471314dae35ad938cb53092ff4bc9cd2929beab4dcd5a2bad4973e65e7eccab` |
| Retained crop archive | `cbf79ada80352fba6bebc1c98788b3bca2289886ca1e7d694318eff9b456364d` |
| Uncompressed crop | `d639fc35d79a5117cd8a9474941278fe8b306dc1463dc1e1938092eb607d2222` |

[`import_mountains.py`](../../../tools/terrain/import_mountains.py) rotates and
resizes this crop into a 13 × 7 km visual backdrop north of Club field. It subtracts
1,850 m, scales positive relief by 0.70, tapers the borders, applies a 5 × 5 source
sample filter and reduces the mesh to 193 × 73 vertices. These are artistic
transforms, not preservation of geographic position, scale or flight terrain.
The same crop supplies a 513 × 193 object-space normal/local-cavity texture.
`bake_mountain_habitat.py` uses slope, broad concavity and relative altitude to
bake a matching RGB rock/sheltered-vegetation/upland mask. This is an artistic
classification, not surveyed vegetation or hydrology.

Two unchanged 1K JPG photographs by Rob Tuytel / Poly Haven supply surface
variation: [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) and
[Aerial Rocks 01](https://polyhaven.com/a/aerial_rocks_01), both CC0-1.0.
Exact URLs, hashes and import transformations ship in
[sources.json](../../../app/assets/landscape/mountains/sources.json).
Godot imports compressed mipmaps; world-space texture footprints are artistic
125 m and 180 m, not the photographed assets' original physical footprints.

Regenerate offline:

```sh
python tools/terrain/import_mountains.py
python tools/terrain/import_mountains.py --check
python tools/terrain/bake_mountain_habitat.py
python tools/terrain/bake_mountain_habitat.py --check
```

`--download-source` recreates the retained crop from the pinned tile; it refuses
changed upstream bytes. The 93,377-byte profile, 306,313-byte relief PNG,
181,840-byte habitat PNG and two photographs enter the app. Original elevation
data stays outside `app/`. Packaged attribution lives in
[`UPGRADE_CREDITS.md`](../../../app/assets/landscape/UPGRADE_CREDITS.md).
