# Moon textures: credit and licence

Credit: **NASA's Scientific Visualization Studio**. CGI Moon Kit, SVS ID 4720, <https://svs.gsfc.nasa.gov/4720>.
Visualizer Ernie Wright (USRA); scientist Noah Petro (NASA/GSFC). Data: LRO LROC WAC colour mosaic (Arizona State
University) and LRO LOLA elevation.

NASA media terms (<https://www.nasa.gov/nasa-brand-center/images-and-media/>): NASA material is generally not subject to copyright in the United States;
NASA must be acknowledged as the source; use must not state or imply NASA endorsement. No NASA insignia or logotype
is used. SVS notes that the maps are "optimized for aesthetics, not science".

These files are reference-derived generated outputs. Do not edit them; rebuild them with
`"$(app/tests/visual-env.sh)" tools/world/moon_texture.py` (`--check` verifies them). Sources and hashes:
`assets/sky/moon/PROVENANCE.json`.

| File | Made from | SHA-256 |
| --- | --- | --- |
| `moon_albedo_2k.jpg` | `source/lroc_color_2k.jpg` (sha256 `f7130a1822681fa7512d7dcfd40db8c10b9ba4f06777910348698260ed7a2170`), copied byte for byte | `f7130a1822681fa7512d7dcfd40db8c10b9ba4f06777910348698260ed7a2170` |
| `moon_normal_1k.png` | `source/ldem_4_uint.tif` (sha256 `e6668bec27fc9b8fbb02d198c7ddfb08eedeeb790167b494f95e6b34201da05e`), local east/north/up normals | `2777b027249ed3e8905d8d80b294e4094189f496094b24d5e9fc71197d8f7b0d` |

Mapping (both textures): equirectangular, u = (east longitude + 180°) / 360°, v = (90° − latitude) / 180°; the left
edge is 180° W, the centre 0°, north at the top. The normal map is linear data: n = 2·rgb − 1 in the local (east, north,
up) frame on the 1737.4 km sphere; relief ×1, faded to up poleward of 86–88°.
Pipeline `fw-moon-04-v1`.
