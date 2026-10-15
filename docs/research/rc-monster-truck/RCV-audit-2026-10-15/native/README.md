# RC audit 2026-10-15 native build and lake parity

The native evaluator and lake-terrain helper were rebuilt from the frozen
solver-v5 sources with the pinned Godot 4.7.2 / godot-cpp 10.0.0 toolchain.
Both x86_64 builds passed the GDExtension load and float64 smoke check and all
733 evaluator parity checks. The shared source SHA-256 is
`6d4c5eabeb2f8565cf84d08fb6825ab5b1cacc47a7ebc26f215ac97b88ae1c2b`.

| Platform | Locked toolchain | Installed binary SHA-256 |
| --- | --- | --- |
| Windows x86_64 | MSVC 14.51.36231, Windows SDK 10.0.26100.0, `/fp:strict` | `01b7803853a1f8b219bb4fbdd91ab33c0fde2b7aba1a7aa9d780951d854501bb` |
| Linux x86_64 | Ubuntu 24.04, GCC 13.3.0, `-fno-fast-math`, `-ffp-contract=off` | `fd0be43f0afaa061ef27f8633b89d2f1496a47244246ff8bfb687d7677dca3c2` |

The Windows developer shell reported Visual Studio v18.10.4; the lock retains
its distribution label v18.9.12128.139. The builder verified the locked MSVC
toolset and Windows SDK versions shown above, and both are recorded in the
receipt.

Both receipts identify ABI 1, backend
`openrc-ground-vehicle-native-evaluate-v3`, and solver
`openrc-ground-vehicle-dynamics-rk4-v5`. The matched libraries were installed
under `app/native/ground_vehicle/` through `build.py --install-app`; the
copied [aggregate receipt](installed-build-receipt.json) matches both installed
binary hashes.

The lake/bathymetry parity check compared the native four-channel terrain
sample `[height_up, slope_north, slope_east, signed_shore_distance]` with the
shared GDScript terrain composition. It covered 669 coordinates: a 17 by 25
grid across the bank bounds, shoreline and bank vertices, edge midpoints and
small offsets on both sides of those edges, basin interior points, and an
off-lake point. All 2,676 scalar outputs were bit-exact on both platforms
(`max_abs_error=0`). The loaded bed profile includes the surface row and depth
interpolation rows `(inset_m, depth_m) = (0, 0), (5.5, 0.8), (20, 5)`; terrain
height and finite-difference slopes therefore exercise the bathymetry
composition. The harness also rejects a malformed bed profile, short or
non-finite dry samples, and non-finite coordinates.

The debug-Godot terrain microprofile over the same grid measured 0.15487 ms per
GDScript sample versus 0.01147 ms native on Linux, and 0.15319 ms versus
0.00978 ms on Windows. This is a bounded helper microprofile, not an integrated
vehicle tick measurement or physical validation.

Evidence files retain the complete Linux verifier report and build log, the
Windows build/install logs and parity output, and per-platform build receipts.
The root RC audit owns the integrated vehicle suite and trajectory comparison.
