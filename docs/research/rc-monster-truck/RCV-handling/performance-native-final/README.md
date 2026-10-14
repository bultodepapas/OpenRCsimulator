# Final native handling verification

Evidence collected 2026-10-14 for the final cap-128 handling solver snapshot. The Linux and Windows builds share native source SHA-256 `e2ae0a5ffebc8d81636302d66238348035ee92bf51d2f40965db7053bb251541`; both report solver `openrc-ground-vehicle-dynamics-rk4-v3`, native evaluator `openrc-ground-vehicle-native-evaluate-v2`, and ABI 1. Each platform passed the corrected 50-check native/GDScript parity harness and the float64 extension load smoke check.

The solver version and native evaluator version are separate identities: the first names the float64 RK4 dynamics behavior, while the second names the GDExtension evaluation backend. These files record the final v3/v2 pair. They do not describe earlier solver-v2 or native-evaluator-v1 builds.

| Platform | Host and toolchain | Godot | Native binary SHA-256 | Parity profile |
|---|---|---|---|---|
| Windows x86_64 | MSVC 14.51.36231, SDK 10.0.26100.0 | 4.7.2 stable | `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c` | GDScript 1.7468 ms; native 0.3270 ms; 5.34×; 50 iterations |
| Ubuntu 24.04 / WSL x86_64 | g++ 13.3.0; `-fno-fast-math -ffp-contract=off` | 4.7.2 stable | `444738e96a8578298a0b0741907884f644413681e7b932b7368905eafef1ef66` | GDScript 2.2049 ms; native 0.2652 ms; 8.31×; 50 iterations |

The profile numbers are short evaluator comparisons in the parity harness. They are platform-specific and do not measure a complete vehicle tick, a driving session or user-perceived frame rate.

`linux-verification.json` records the isolated sparse-archive build, exact working-file overlays, lock/toolchain identity, native source and binary hashes, smoke result, parity result and build output. `linux-build.log` retains the compiler and Godot output. `linux-build-receipt.json`, `windows-build-receipt.json` and `windows-parity.log` retain the corresponding native identities and Windows parity output. The Linux working-input snapshot hash is `4bc2305329cba71b17c7d36e9b267f77b50ab633aa052255aa9524baea9dee93`; its overlay hashes matched the snapshot, and its receipt source hash matches the Windows build.

The related Track sampler scalar-allocation study is in [performance-track-scalar-r2](../performance-track-scalar-r2.md). It records independent exact-output checks and paired Track-only timing; those measurements do not establish whole-session or release performance.
