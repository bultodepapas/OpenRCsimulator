# Native ground-vehicle evaluator

This optional GDExtension accelerates the experimental monster-truck evaluator. The GDScript implementation remains the reference and fallback. The extension does not change the aircraft catalog or aircraft dynamics, and its software parity is not physical validation of the estimated truck model.

## Contract and identity

`OpenRCGroundVehicleNative.evaluate(state, model, controls, road_batch, calculate_energy, adaptive_friction)` evaluates the same boundary as `VehicleDynamics._evaluate`. State is the existing 31-value `PackedFloat64Array`; model and controls are normalized dictionaries. The road callback receives one flat batch of north/east coordinates and returns the corresponding height, NED normal, friction and rolling values. The result uses the production evaluator's keys and packed-array types. Malformed inputs, invalid road samples and singular geometry return `{ok: false, error: ...}` without a partial result.

The numerical core stores simulation values as IEEE-754 `double`; it does not use Godot vector types as simulation state. Its identity is ABI `1`, backend version `openrc-ground-vehicle-native-evaluate-v1`, and solver version `openrc-ground-vehicle-dynamics-rk4-v2`. `backend_identity()` reads the current platform row from `build-receipt.json` and reports the backend, ABI/solver versions, and source, toolchain and binary SHA-256 values. A session freezes this identity and rejects a checkpoint or replay from another backend build.

## Pinned build tools

The [toolchain lock](toolchain-lock.json) pins Godot `4.7.2.stable.official.ed1daf0bf`, extension API `4.7`, godot-cpp `10.0.0-stable` at `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, SCons `4.10.1` (including the wheel hash), and Python `3.9+`.

| Host | Compiler and SDK | Flags |
| --- | --- | --- |
| Windows x86_64 | Visual Studio `18.9.12128.139`, MSVC `14.51.36231`, Windows SDK `10.0.26100.0` | `/fp:strict`, `/EHsc` |
| Linux x86_64 | Ubuntu 24.04, GCC `13.3.0` (`13.3.0-6ubuntu2~24.04.1`) | `-fno-fast-math`, `-ffp-contract=off`, `-fexceptions` |

The per-platform exception flag is appended after godot-cpp's base compiler flags; the Linux template disables exceptions, so `-fexceptions` is needed for the evaluator's guarded input and road-callback boundary. Each build uses Godot's float64 bindings and runs a load/float64 smoke check plus the native-versus-GDScript parity harness.

On Windows, open the x64 Native Tools prompt for the pinned Visual Studio and run:

```powershell
python -B research/rc-monster-truck/native/build.py --jobs 2
```

The build script uses `.tools/Godot_v4.7.2-stable_win64.exe` by default. Pass `--godot PATH` to use a different copy of the same pinned engine. The configured Linux app CI step targets an Ubuntu 24.04 x86_64 host with the locked GCC and runs:

```sh
python3 research/rc-monster-truck/native/build.py --jobs 2 --godot "$(app/get-godot.sh)"
```

For an isolated WSL qualification that does not touch the shared `.tools` cache, run `python3 -B research/rc-monster-truck/native/verify_linux.py --jobs 2` inside Ubuntu 24.04. It writes the `.so`, parity log and verification report under `tmp/rcv-native-linux/`; use `--source-root` or `--godot` if the checkout or pinned Linux Godot binary is elsewhere.

The configured CI upload retains only the named Linux library, platform receipt and parity log. It explicitly enables hidden-path inclusion because these generated files live under `.tools`; the [pinned upload action](https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/action.yml) otherwise excludes hidden paths by default.

Both build paths target x86_64 Windows/Linux only. macOS has no native artifact or descriptor entry and uses the GDScript reference backend. The Windows build and isolated WSL Ubuntu build have each passed GDExtension load/float64 smoke and 39/39 evaluator parity checks. Windows was built with the pinned MSVC/SDK; WSL qualification used Ubuntu 24.04, GCC 13.3.0 and the pinned Linux Godot binary. The Windows timing run used a debug Godot engine with a `template_release` extension, so evaluator timing from that run is a development probe, not exported-release performance evidence.

## Installing and exporting

Build outputs and their per-platform receipts live in the ignored `.tools/native-ground-vehicle/` cache by default. The checked-in project intentionally has no generated native binary. `--install-app` requires matching current-source Windows and Linux outputs plus `build-receipt.windows.json` and `build-receipt.linux.json` in that cache. It verifies each binary hash, refuses stale or missing platform records, then writes the two libraries, `openrc_ground_vehicle.gdextension`, aggregate `build-receipt.json`, and pinned godot-cpp license under `app/native/ground_vehicle/`. To install after staging both verified artifacts and receipts, run `python -B research/rc-monster-truck/native/build.py --jobs 2 --install-app` in the Windows Native Tools prompt. The Linux CI step only builds, loads/smokes and checks parity; a future package assembly job must collect its `.so` and receipt with the Windows DLL and receipt before invoking `--install-app`. The generated app directory is ignored by Git.

The descriptor selects the Windows DLL or Linux shared library, and Godot exports the library declared by its `.gdextension` entry. The Linux and Windows presets use `all_resources`, include the receipt JSON and license, and allow Godot's resource dependency export to carry the declared extension library. The macOS preset explicitly excludes `native/ground_vehicle/*`. At runtime, `VehicleDynamics` checks the receipt and binary SHA before loading; it searches the resource path and executable-relative native locations so a packaged library can load when Godot relocates it beside the executable. The Windows DLL currently depends only on `KERNEL32.dll`; it does not require an extra bundled runtime DLL. The native-enabled Windows RC-only release passed import, export, startup and backend-identified tick measurement; see the [dated evidence](../../../docs/research/rc-monster-truck/RCV-runtime/README.md#release-tick-cost). Its mean/p95 passed the 240 Hz interval, but its maximum ticks exceeded that interval and the 500 µs mean target remains open.

Godot's [4.7 `.gdextension` file documentation](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html) describes platform library selection, export and dependency placement. The runtime loader currently supports Windows and Linux. macOS and other architectures use the GDScript reference. The configured Linux CI step has not been run here; dual-platform CI artifact assembly, Linux release packaging and the full application release gate are not yet qualified.

## Parity scope

The harness compares evaluator accelerations, steering, suspension and tire forces, slips, contact flags, friction sweeps and energy for rest, driving, steering, braking, reverse, bumps, airborne/inverted states, non-flat road, malformed inputs, singular geometry and seeded valid states. This protects equation and data-contract parity. The integrated Windows tests additionally passed 47 dynamics and 85 Session/checkpoint/replay checks. These results do not establish tire calibration, realistic handling or target-machine frame pacing.
