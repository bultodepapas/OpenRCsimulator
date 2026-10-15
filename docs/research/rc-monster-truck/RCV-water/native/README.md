# Native water-terrain parity evidence — 2026-10-14

The native extension adds the optional `sample_lake_terrain` helper for the
RCV airfield road sampler. It receives a normalized lake dictionary, finite
north/east coordinates, and a three-value dry microrelief sample. It returns
`[height_up_m, slope_north, slope_east, signed_shore_distance_m]`; malformed
inputs return an empty `PackedFloat64Array` so the caller can use the shared
GDScript sampler.

The helper ports the validated lake composition and center signed shoreline
distance using float64 geometry. It preserves polygon-edge, bank/shore
precedence, bed-profile interpolation, and the existing ±0.025 m finite
differences. It uses an outer bank AABB fast path and does not quantize or cache
terrain. Existing evaluation remains backend v3 / solver v4 / ABI 1.

Both pinned x86_64 builds passed the GDExtension load/float64 smoke and all 733
native parity checks on Godot 4.7.2. The terrain grid compared 669 points
(2,676 scalar outputs) across the bounded lake, shoreline and bank vertices and
edges, edge offsets, basin interior, and off-lake samples. Every output was
bit-exact against `GroundTerrain.sample_validated` plus
`LakeSurface.shore_distance_validated` (`max_abs_error=0`). Invalid lake shape,
short base input, and non-finite base data fail closed.

| Platform | Toolchain | Lake path, debug Godot |
| --- | --- | --- |
| Linux x86_64 | g++ 13.3.0; `-fno-fast-math`, `-ffp-contract=off` | GDScript 0.11781 ms/sample; native 0.009302 ms/sample; 12.66x |
| Windows x86_64 | MSVC 14.51.36231, SDK 10.0.26100.0; `/fp:strict` | GDScript 0.19264 ms/sample; native 0.01421 ms/sample; 13.56x |

This microprofile times terrain composition and the shoreline metadata scan
over the parity points; it is not an end-to-end tick measurement. The parent
track owns the full 3,600-tick entry comparison.

The installed receipts identify backend `openrc-ground-vehicle-native-evaluate-v3`,
solver `openrc-ground-vehicle-dynamics-rk4-v4`, and ABI 1. The shared source
SHA-256 is
`7b064e5dca1fc8333d958c073c2dac11eecc96a95b4095117d38be93ae672695`.
`native/build.py --install-app` staged both receipt-matched libraries under
`app/native/ground_vehicle/`.

The adjacent parity logs retain engine output and per-platform build identity;
`build-receipt-2026-10-14.json` records compiler and binary hashes. This
evidence establishes implementation parity and build packaging, not physical
validation of the water-force model.
