# GDU-03 native evaluator compatibility — 2026-10-25

Both x86_64 native ground-vehicle artifacts passed the locked builder's load/float64 smoke and all 733 native/GDScript evaluator checks on official Godot `4.8.beta1.official.4d10419ca`. Lake sampling returned 2,676 bit-exact scalar results at 669 coordinates on each host. These checks establish software compatibility; they do not establish physical calibration or performance acceptance.

The engine pin alone changed in the toolchain lock. Extension API `4.7`, godot-cpp `10.0.0-stable` at `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, SCons `4.10.1`, compiler versions, floating-point flags, ABI 1, evaluator v3 and solver v5 remain unchanged. Both receipts identify native source SHA-256 `6d4c5eabeb2f8565cf84d08fb6825ab5b1cacc47a7ebc26f215ac97b88ae1c2b`.

| Host | Result and artifact SHA-256 |
| --- | --- |
| Native Windows, MSVC `14.51.36231`, SDK `10.0.26100.0`, `/fp:strict`, `/EHsc` | Pass; `01b7803853a1f8b219bb4fbdd91ab33c0fde2b7aba1a7aa9d780951d854501bb` |
| WSL Ubuntu 24.04, GCC `13.3.0`, `-fno-fast-math`, `-ffp-contract=off`, `-fexceptions` | Pass; `08a4c6f7c05c5ef082099cd9158bd2b31814ca3bc4a7663a9ca770895141abcd` |

Windows ran the existing `research/rc-monster-truck/native/build.py --jobs 2 --godot .tools/Godot_v4.8-beta1_win64_console.exe` from the locked developer environment. SCons reused up-to-date objects; the resulting DLL equals the previous qualified DLL. The builder refreshed the receipt and loaded that DLL in the new engine. [Build log](windows-build.log), [parity log](windows-parity.log), [platform receipt](build-receipt.windows.json).

Linux used the existing isolated verifier with `--source-root /mnt/c/DEVELOPMENT/OpenRCsimulator --workspace /tmp/openrc-gdu03-native-r2 --out /mnt/c/DEVELOPMENT/OpenRCsimulator/tmp/gdu03-pins/native-linux-r2 --godot /mnt/c/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta1_linux.x86_64 --jobs 2`. It performed a fresh isolated compilation. The first attempt exposed a pre-existing missing snapshot input: the builder copies `physics/generalized_coordinates.gd`, but the verifier's sparse input list omitted it. Adding that existing required file fixed parity-project assembly. [Verifier report](linux-verification.json), [build log](linux-build.log), [platform receipt](build-receipt.linux.json). Absolute workspace paths can affect Linux binary hashes; the retained report binds this exact artifact to its source snapshot and receipt.

The verified Linux library and its builder-generated receipt retained inside the verifier report were staged beside the Windows artifact. `build.py --install-app` then verified both binary hashes and installed both platform rows, libraries, descriptor and godot-cpp license into the primary app. The [install log](windows-install.log) and [aggregate receipt](installed-build-receipt.json) record that integration. No receipt identity was manually changed.

The shared machine ran other correctness checks concurrently. Profile timings in raw logs are incidental and cannot establish a performance improvement. No rendered or GPU run was performed by this native qualification. Integrated application/export checks remain with the GDU-03 parent report; WSL establishes Linux behavior, while macOS keeps the reference backend.
