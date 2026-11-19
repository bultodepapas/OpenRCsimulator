# Experimental EdgeTX native observation host

This is an experimental, headless observation host for a separately built
EdgeTX T18-H7 simulator library. It is not a flight controller or a Godot bridge.
It does not implement telemetry or prove that any named model loaded.

The host source is original and is intended under the existing OpenRC MIT
grant. The selected EdgeTX interface and runtime have GPLv2 terms. An assembled
host and runtime must be assessed for GPLv2 obligations before distribution;
the process boundary is not an automatic exception, and no MIT-only status is
claimed for that combination. This tool redistributes no EdgeTX binaries or
upstream source. Review the exact runtime, Qt and other dependency licenses,
notices and corresponding-source arrangements before any release.

## Build prerequisites

Use the exact EdgeTX checkout at commit
`0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99`, a compatible Qt 6 build with
Core and SerialPort development files, and SDL2 development files. Use the
SDL-enabled upstream simulator build: the pinned no-SDL build omits a volume
function still referenced by the wrapper. The CMake configuration checks hashes of
the four upstream headers directly used by this host. It does not establish the
full checkout or runtime binary's provenance, and the C++/Qt ABI still needs to
match the library. The host uses its own Qt meta-object code and dynamically
resolves the upstream factory; it does not link the EdgeTX plugin at build time.

```sh
cmake -S /absolute/path/to/OpenRCsimulator/tools/radio_runtime \
  -B /absolute/path/to/OpenRCsimulator/tmp/radio-runtime/build \
  -DEDGETX_SOURCE_DIR=/absolute/path/to/edgetx_2_12_5 \
  -DCMAKE_PREFIX_PATH=/absolute/path/to/qt
cmake --build /absolute/path/to/OpenRCsimulator/tmp/radio-runtime/build
```

Building the EdgeTX simulator itself is a separate operation. Its native
configuration requires additional Qt modules and other dependencies. Use the
pinned upstream build instructions and record the complete build identity.
For a locally extracted SDL2 SDK, also supply its `SDL2_DIR` CMake package path
and any platform-specific include directory required by that SDK.

## Run

Make **private copies** of both SD contents and radio/model settings before
running. The firmware may create, modify, rename or delete files in these
directories. The host checks that the supplied paths exist, are absolute and
resolve to ASCII paths; it cannot prove that they are copies. It deliberately
requires both paths so an empty path cannot fall back to the current directory
or an earlier settings path. It disables splash, calibration and startup checks.
Like Companion, it initializes SDL before firmware startup. This observation
host forces SDL's silent `dummy` audio driver, records initialization, and calls
`SDL_Quit` after simulator shutdown. Audible output is not qualified.

Supply a trusted library path and a fresh output path whose parent exists. The
host hashes the library, checks its reported factory and instance names, and
creates the output directory exclusively. It does not overwrite existing
output files. Library loading resolves all symbols immediately, rejecting an
incomplete runtime before starting the simulator. Provide an independently recorded expected SHA-256 when available;
matching a hash alone does not establish source provenance. The hash and load
are separate operations and do not protect against concurrent file replacement.

```sh
./tmp/radio-runtime/build/openrc-edgetx-smoke \
  --plugin /absolute/path/libedgetx-t18h7-simulator.so \
  --sd-copy /absolute/path/private-sd \
  --settings-copy /absolute/path/private-settings \
  --output /absolute/path/new-observation \
  --duration-ms 5000 \
  --expected-plugin-sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

The example hash is a placeholder. Omit that argument until the actual expected
hash is independently known. The output is a JSON receipt and, if a non-null
frame arrives, one `latest.rgb565` file containing exactly 480 × 272 pixels,
960 bytes per row, in native-endian RGB565. The host keeps only the latest frame,
caps recorded channel events and errors, and records aggregate counts. The
receipt includes monotonic host-relative observation times, plugin and frame
hashes, Qt/OS details, heartbeat and channel observations.

The LCD copy-before-acknowledgment sequence follows pinned Companion. Upstream
shares the framebuffer pointer and refresh flag between firmware and Qt code;
this host does not independently establish cross-thread memory synchronization.
A captured frame is a best-effort observation, not proof of coherent or fresh
framebuffer publication. The receipt leaves LCD coherence unverified as well
as channel-snapshot coherence and freshness.

`--sweep-stick 0`, `1`, `2` or `3` optionally sends −1024, 0 and +1024 during
the run. It is training-only: a stick number is a physical input index, not a
verified channel mapping. A usable test needs an independently prepared,
calibrated, same-version fixture with known output expectations. A blank SD
can show an initialization warning; seeing a frame, a heartbeat or changing
channels does not prove that a named model loaded. The receipt explicitly
leaves model identity, telemetry and flight admission unverified.

Keep the process log alongside the receipt. Its error counts cover host errors
and the upstream `runtimeError` signal; they do not classify every firmware log
line. Missing SD themes/widgets can be logged while the basic observation passes.

The duration is limited to 1.5–30 seconds. A separate hard watchdog exits after
the requested duration plus ten seconds if firmware startup, shutdown or the
event loop blocks. A watchdog exit is abrupt and may leave no complete receipt.
A completed observation exits `0` only when the receipt's basic observations
are met, `1` for an incomplete observation, and `2` for host-validated invalid
values or an output write error. Qt command-line syntax errors (unknown options
or missing option values) exit `1` before a receipt is created; `--help` exits
`0`. The hard watchdog exits `124`.
These checks are a plumbing smoke test, not a test of timing, coherence,
telemetry, model semantics or safety.

The [2026-11-19 Linux experiment](../../docs/research/radio-input/D6-RADIO-01/README.md)
built the pinned SDL-enabled library, captured its LCD and observed one raw input
sweep on two separate process starts/stops. It used generated default settings
and an empty SD directory. A complete SD asset set, independently prepared model,
configured telemetry, timing/coherence, native packaging and device qualification
remain open. No upstream source, SDK or binary is redistributed by this tool.
