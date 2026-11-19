# Native EdgeTX observation experiment — D6-RADIO-01

Date: **2026-11-19 (America/Bogota)**. Status: **local Linux build and bounded
LCD/input/channel observation passed; full runtime integration gate remains open**.
The [active plan](../../../plans/radio-display-edgetx.md) owns the complete gate;
[code-reuse and license research](../D6-RADIO-00/code-reuse-licensing-2026-11-19.md)
owns the proposed release boundary.

## What is implemented

The original [observation host](../../../../tools/radio_runtime/README.md) uses
the pinned upstream `SimulatorInterface` and dynamically loads the separately
built T18-H7 simulator library. It runs the Qt event loop, supplies explicit
private SD/settings paths, copies and acknowledges LCD frames, records channel
notifications and heartbeats, and stops/destroys the simulator before unloading
the library. Its optional three-position raw-stick sweep is for observations.

The host keeps one latest frame and bounded event/error records. It writes a
JSON receipt and an RGB565 framebuffer into a new output directory. A hard
watchdog bounds a blocked start, event loop or stop; forced exit can leave no
complete receipt. Header hashes, reported target names and an optional expected
plugin hash guard the selected experiment; they do not prove an arbitrary
binary's source provenance or make untrusted native libraries safe to load.

No EdgeTX source, SDK, native binary or SD asset bundle is copied into OpenRC.
The adapter source is original. The real firmware remains a separately built
component using its existing license. This tool is not a Godot transport, a
configuration editor or a flight-input provider.

## Build identity

| Item | Observed identity |
| --- | --- |
| EdgeTX | v2.12.5, commit `0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99` |
| Target | `PCB=T18H7`, `edgetx-t18h7`, native `libsimulator`, Debug |
| Source state | Tracked checkout clean; recursive submodules at their pinned commits |
| Platform/compiler | Linux x86-64; Debian GCC 14.2.0; CMake 4.4.5 |
| Qt / SDL | Qt 6.9.3 with ICU 73; SDL2 2.32.4, initialized with the silent dummy audio driver |
| Final plugin | 58,327,648 bytes; SHA-256 `e055a9724d12c8dc69850a47925c4f932640924211fcc654e519cc96409a10fa` |
| Relocations | `ldd -r`: no missing libraries or unresolved symbols; `registerSimu` exported |
| Packaging | Absolute local Qt/SDL RUNPATHs; this is **not a portable package** |

The [build receipt](build-receipt.json) records dependency revisions and archive
hashes. Qt archives and missing development packages were extracted locally;
the system installation and upstream source were not modified. The upstream
datacopy generator needed Clang 19 headers and Python bindings. Its `CPATH` was
limited to that generator; leaving those headers in GCC's environment broke
compilation. The main C/C++ build ran with that generator-specific path unset.

Upstream native configuration fetched a moving `rs-dfu` latest-release archive
and linuxdeploy continuous packaging helpers. Their observed identities are
recorded, but a pinned EdgeTX commit alone does **not** make this build hermetic.
The presence of a configure tool is not evidence that it is linked into the
simulator. A reproducible packaging recipe must pin or isolate these downloads.
The final successful build reused the existing native cache and objects from
the iterative setup; a clean-build reproduction was not performed.

### Recorded build sequence

This normalizes the successful commands for the recorded Linux environment.
It assumes the exact source/submodules and dependency layouts in the receipt
already exist; it is not an installer or a clean-build verification recipe.
`EDGETX_GENERATORS` holds Jinja2/Pillow/asciitree, and `deps/python` holds the
recorded clang/lz4 packages. `deps/lib/libclang.so` resolves the matching system
libclang 19. The generator's discovery warning did not prevent that loader path;
the generator completed with no AST diagnostics and produced 439 lines.

```sh
EDGETX_SRC=/absolute/path/to/edgetx_2_12_5
EDGETX_BUILD=/absolute/path/to/edgetx_native_build
EDGETX_QT=/absolute/path/to/edgetx_qt
EDGETX_GENERATORS=/absolute/path/to/edgetx_generators
EDGETX_CMAKE=/absolute/path/to/cmake
EDGETX_EXTRA="$EDGETX_BUILD/deps"

CMAKE_PREFIX_PATH="$EDGETX_QT" PYTHONPATH="$EDGETX_GENERATORS" \
  "$EDGETX_CMAKE" -S "$EDGETX_SRC" -B "$EDGETX_BUILD" \
  -DPCB=T18H7 -DCMAKE_BUILD_TYPE=Debug \
  -DOPENGL_INCLUDE_DIR="$EDGETX_EXTRA/root/usr/include" \
  -DOPENGL_gl_LIBRARY=/lib/x86_64-linux-gnu/libGL.so.1

LD_LIBRARY_PATH="$EDGETX_QT/lib" CMAKE_PREFIX_PATH="$EDGETX_QT" \
  PYTHONPATH="$EDGETX_GENERATORS" \
  "$EDGETX_CMAKE" --build "$EDGETX_BUILD" --target native-configure --parallel 4

LD_LIBRARY_PATH="$EDGETX_QT/lib" \
  CMAKE_PREFIX_PATH="$EDGETX_QT:$EDGETX_EXTRA/root/usr" \
  PYTHONPATH="$EDGETX_EXTRA/python:$EDGETX_GENERATORS" \
  "$EDGETX_CMAKE" -S "$EDGETX_SRC" -B "$EDGETX_BUILD/native" \
  -DSDL2_DIR="$EDGETX_EXTRA/root/usr/lib/x86_64-linux-gnu/cmake/SDL2"

LD_LIBRARY_PATH="$EDGETX_EXTRA/lib:$EDGETX_QT/lib" \
  CPATH="$EDGETX_EXTRA/root/usr/lib/llvm-19/lib/clang/19/include" \
  PYTHONPATH="$EDGETX_EXTRA/python:$EDGETX_GENERATORS" \
  "$EDGETX_CMAKE" --build "$EDGETX_BUILD/native" --target datacopy --parallel 4

env -u CPATH \
  LD_LIBRARY_PATH="$EDGETX_EXTRA/lib:$EDGETX_EXTRA/root/usr/lib/x86_64-linux-gnu:$EDGETX_QT/lib" \
  CPLUS_INCLUDE_PATH="$EDGETX_EXTRA/root/usr/include/x86_64-linux-gnu" \
  PYTHONPATH="$EDGETX_EXTRA/python:$EDGETX_GENERATORS" \
  "$EDGETX_CMAKE" --build "$EDGETX_BUILD/native" --target libsimulator --parallel 4
```

The direct SDL configuration relies on the native cache produced by
`native-configure`, including its upstream native toolchain and target flags.
Supplying `CMAKE_PREFIX_PATH` in the environment of `native-configure` mattered;
the top-level cache did not forward it in this run.

## Actual runtime results

The initial empty-settings run created default YAML files and displayed a real
EdgeTX **storage warning**. That was useful bootstrap evidence, not a model
loading or normal-screen pass. Two subsequent runs each received a new private
copy of the generated settings and an empty SD directory. Firmware logs identify
`MODEL01`; the captured LCD shows the EdgeTX main-view shell, with SD theme and
widget assets absent. It is not a fully populated radio screen.

| Observation | First SDL run | Separate-process repeat |
| --- | --- | --- |
| Requested observation | 5 seconds | 5 seconds |
| Process / basic receipt verdict | Exit 0 / passed | Exit 0 / passed |
| Started and stopped signals | Both received | Both received |
| LCD | 2 frames, 480 × 272, RGB565, 261,120 bytes | Same geometry; 2 frames |
| Heartbeats | 5 | 5 |
| Channel notifications | 35 | 35 |
| Raw input sweep | Stick index 0: −1024, 0, +1024 | Same requested sequence |
| Observed output change | Zero-based channel 0 reached −1024 and +1024, with an intermediate zero | Same range and intermediate zero |
| SDL audio initialization | Successful, dummy driver | Successful, dummy driver |
| Host errors / upstream runtimeError signals | 0 / 0 | 0 / 0 |

[First runtime receipt](runtime-first.json), [repeat receipt](runtime-repeat.json)
and [host checks/source hashes](checks.json) preserve the actual observations.
Published receipts replace only the scratch-workspace path prefix with
`<workspace>` and record the original receipt hash. They do not contain the
firmware binary or framebuffer image.

The firmware separately logged missing WIDGETS/THEMES directories and a failed
bitmap load. Zero `runtimeError` signals therefore does not mean a warning-free
boot. The basic receipt means the listed plumbing observations occurred; it does
not establish complete SD content, a calibrated model, model semantics or
telemetry. The repeats are **two processes**, not an in-process restart test.

The input/output observations establish one response through this generated
default configuration. They do not assign the channel to an OpenRC logical
axis, prove a general channel map, or measure useful latency/freshness bounds.

## Findings that changed the implementation

1. **Reject incomplete libraries at load time.** The first upstream build without
   SDL produced a shared library but omitted `simuSetVolumeGain(int)`. A simple
   `ldd` and a limited first boot did not expose that path; `ldd -r` did. The host
   now requests `QLibrary::ResolveAllSymbolsHint`. The incomplete library is
   rejected before startup, and the selected build uses upstream's SDL path.
2. **Initialize the audio subsystem explicitly.** Companion initializes SDL
   before starting the simulator. The host now follows that lifetime, forces
   the dummy driver and quits SDL after simulator destruction/unload. This
   establishes initialization and cleanup, not audible-output quality.
3. **Follow the LCD acknowledgment contract without overstating it.** Copying
   before `lcdFlushed()` matches Companion. Upstream's refresh flag and buffer
   pointer cross threads without an independently qualified synchronization
   contract. The receipt leaves LCD coherence and channel freshness unverified.
4. **Keep lifecycle callbacks shallow.** Upstream emits started/stopped under a
   non-recursive mutex. Those callbacks record state; they do not call back into
   start/stop/isRunning. Owner-thread cleanup happens after callback return.
5. **Treat disk data as mutable training data.** Even these short runs write
   radio/model YAML. The host requires explicit paths and refuses to overwrite
   an existing output directory. A supplied wrong binary hash is rejected
   before output creation. Callers must provide copies; a path check cannot
   prove that a directory is a copy.

These points are grounded in the actual runs and the pinned
[simulator interface][interface], [wrapper][wrapper], [SDL audio implementation][audio],
[no-audio implementation][no-audio], [Companion simulator startup][startup] and
[LCD handoff][lcd]. Independent review covered the lifecycle, signal and SDL
changes; it did not replace the execution checks.

## Reuse and release consequences

The result supports continuing with the upstream firmware core and a small
adapter. Rewriting the menus, mixing rules and storage interpreter would still
duplicate work. The next useful code is the bounded Godot transport and an
enlarged view, after a complete copied-model and telemetry experiment establishes
what the adapter must carry.

The adapter's original source grant does not make an assembled EdgeTX host and
runtime MIT-only. The earlier GPL scope, dependency notices and corresponding
source questions remain release work. SDL2 adds a dependency under the
[official zlib license][sdl-license]; preserve its applicable notices and
provenance. Qt modules, transitive libraries, fonts, themes, SD scripts and
package tooling still require the selected distribution inventory. No separate
permission was requested from maintainers, no license was changed and no native
binary was published with this source increment.

## Remaining D6-RADIO-01 gate

Prepare an independently reviewed, calibrated T18-H7 fixture with a complete,
version-matched SD asset set and explicit expected channels. Then verify copied
model selection and menu interaction, configured/discovered telemetry displayed
with correct units and stale behavior, and the intended same-process lifecycle.
Measure channel freshness and qualify the memory/transport contract separately
before virtual-flight admission. Windows/macOS packages, actual radios and RF
behavior retain independent evidence requirements.

[interface]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/simulatorinterface.h
[wrapper]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/opentxsimulator.cpp
[audio]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/simuaudio.cpp
[no-audio]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/no_audio.cpp
[startup]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulator.cpp
[lcd]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/simulcd.cpp
[sdl-license]: https://www.libsdl.org/license.php
