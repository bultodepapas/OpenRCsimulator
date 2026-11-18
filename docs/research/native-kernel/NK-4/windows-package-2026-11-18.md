# NK-4: first Windows release package with the native kernel (2026-11-18)

**Owner decision (2026-11-18):** "native kernel always". The native physics kernel ships and is used in Windows release packages too, not only Linux.

**Host:** this Windows 11 workstation (Ryzen 9 5900X), official Godot `4.8-beta2 (official)` and the official `windows_release_x86_64.exe` export template. The MinGW tool root is `D:/OpenRCsimulator-native/nk`; the unenrolled test-queue root is `U:\OpenRC\testqueue`.

## What changed

- **`app/sim/native_stage.gd`:** the release template path accepts Windows. `_load_package_library(platform)` checks the Windows receipt row, the packaged descriptor and the DLL.
- **`app/app_state/native_package.gd`:** a Windows x86_64 release template reads its own manifest, `res://native/kernel/package-windows.json`. The receipt row is `platforms.windows`, and the sidecar receipt is checked against the executable.
- **`app/addons/native_kernel/export_plugin.gd`:** a Windows branch embeds that manifest and the six diagnostics. The editor binding is platform-aware, and the end-of-export recheck uses the export's own platform.
- **`research/native-kernel/package.py`:** new `prepare-windows` and `finalize-windows` commands. A pre-existing defect is also fixed: `solver_identity()` had omitted `input/commands.gd` and `spec.gd`, which `flight_log.gd` has hashed since 2026-11-16. Every package export, Linux included, would have refused on that mismatch.
- **`research/native-kernel/test_default_route.py`:** now works on Windows (DLL name, APPDATA). It can write beside the executable's volume, so private package copies are hard links rather than 2 GB copies.
- **Tests:**
  - `test_native_stage.gd` gains Windows manifest cases, 104 checks.
  - `research/native-kernel/test_package_windows.py` (7 tests) checks loader descriptor parity, LF-only writing, separate manifests and the solver-identity source list.

Because `native_package.gd` and `native_stage.gd` are part of the kernel identity, the Windows DLL was rebuilt and requalified before packaging. The mutant was rebuilt too. All 19 gates ran: 18 bit-identical, and the negative control diverged as required. The DLL was then installed.

## Package

| Item | SHA-256 / value |
| --- | --- |
| Exported `OpenRC Simulator.exe` (embedded pack, 2.16 GB) | `ceba2497…4578204` |
| Template `windows_release_x86_64.exe` | `afb68595…2b86aeede` |
| Qualified editor `Godot_v4.8-beta2_win64.exe` | `9d735a72…8faccf2` |
| `native/kernel/openrc_native_kernel.dll` | `5c64d4e7…dd1b4d7f` |
| Embedded `package-windows.json` | `2c399155…5da9a343a` |

## Qualification on the exported executable

These are the same five modes and markers as the Linux gate in `app/export.sh`, run through `tools/godot/run_checked.py` with a private `APPDATA`:

| Mode | Result |
| --- | --- |
| `stage` | 103 checks, 0 failed; `NK3_NATIVE_STAGE_NATIVE verdict=pass` |
| `lifecycle` | `NK3_NATIVE_SESSION` 343 checks, 0 failures |
| `replay` | `NK3_NATIVE_REPLAY` 209 checks, 0 failures |
| `helicopter` | 399 checks, 0 failures, native exercised |
| `helicopter-radio` | 80 checks, 0 failed |

Every run reported `NATIVE_QUALIFICATION preloaded=false` and `verdict=pass`. Capturing standard output from the GUI-subsystem executable worked.

`test_default_route.py --release-executable` then printed **`NK3_DEFAULT_ROUTE verdict=pass`**:

- an ordinary flight selects native;
- explicit reference works;
- helicopter native and its lake fallback work;
- the package falls back safely with the binary missing, a corrupt descriptor, a corrupt DLL, a malformed receipt or a wrong executable hash;
- invalid backends and malformed qualifications are refused before flight.

The main risk was that the DLL is qualified against the editor while the release template is a different binary. On this host the template runs the kernel identically to the reference.

## Not yet done

- The CI release path: upload the Windows DLL, receipt and evidence from `native-kernel-windows`, then run `prepare-windows` and `finalize-windows` in `app/export.sh`.
- A windows-2025 package-gate job that runs the steps above on the cross-exported executable and gates `release`.
- Adding the Windows payload to `tools/release/manifest.py`.

Until then, published Windows ZIPs still ship without the kernel. Raw logs stayed outside the repository (`U:/OpenRC/winpkg-3-evidence`).
