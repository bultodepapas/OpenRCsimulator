# DT-MAC-02 — Windows preparation for native Mac testing

2026-10-28. Implementation on Windows with three Terra 6.1 Max specialists:
native acquisition/compatibility, renderer/reconstruction, and capture/reducers.
The [Apple Silicon plan](../../../plans/apple-silicon-performance.md) owns status
and remaining acceptance. The [preceding research](../DT-MAC-00-R2/README.md) owns
the dated primary references and pinned-engine audit.

## Implemented preparation

| Delivery | Implementation | Evidence boundary |
| --- | --- | --- |
| DT-MAC-02a: native editor | `app/get-godot.sh` downloads the exact official 4.8-beta1 ARM64 archive, verifies SHA-512, preserves the app bundle, checks Mach-O architecture/version and verifies a complete cached-file manifest | Official archive downloaded and inspected on Windows; mocked Darwin/cache/failure paths run on Windows/WSL. Actual Mac launch, signature/trust behavior and import remain pending |
| DT-MAC-02a: templates/preflight | Darwin `shasum` support, Python 3.11 prerequisite/override for the existing beta-template correction, bounded serial-filtered host/GPU/display/tool/engine inventory with unique JSON receipts | Fixture validation only. Forced ARM64 `--version` status is distinct from normal app execution. System display dimensions are not drawable pixels. Linux export/NK gates remain intact |
| DT-MAC-02b: long capture | Opt-in `openrc-frametimes v3` chunk stream, bounded memory/file/duration/frame counts, sequence/hash/completion/failure receipts, interruption handling, synchronous write timing; v2 short reports retained | Synthetic 30-minute 60/120 Hz streams and real short Windows headless captures. No 30-minute native flight, observer-cost acceptance, power or thermal evidence |
| DT-MAC-02b: readers/identity | Existing native summary and frame diagnosis validate streams. Diagnostics include OS/architecture, method/driver, VSync/FPS cap, explicit timing/viewport scope and unknown command backend | Missing presentation/GPU observations stay unverified. Existing v2-only incident/Perfetto routes are not v3-qualified |
| DT-MAC-05a: isolated experiments | Preparation helper copies/hashes app sources, assigns a UUID user-data identity, isolates import cache, disables startup multi-bounce and links sibling assets. Launcher validates method/driver pairs and records requested/effective identity | Windows fixtures and headless identity checks. Shared linked assets must remain frozen. Compatibility/Mobile/Forward+ native parity, pixel dimensions and performance untested |
| DT-MAC-07a–c: guarded MetalFX | Five opt-in Spatial/Temporal choices, runtime method/driver/RD/enum/feature/scale checks, provider-specific AA/sharpening, localized UI, explicit unknown execution and Native recovery | Injected capability fixtures do not execute MetalFX. Temporal requires Forward+ and falls back on history discontinuity without verified reset acknowledgement. Native motion, reset, resize, leaks and actual scaler-pass evidence remain open |

The shipped renderer default, engine pin and simulation physics are unchanged by
this preparation. It does not implement a Metal 4 command driver or frame
interpolation. Those require a separately reviewed engine integration and native
evidence; the current pin uses its MTL3 implementation. No renderer or quality
preset was promoted on the basis of Windows tests.

## Operating instructions

Use these authoritative guides instead of copying stale commands from this report:

- [Native Apple Silicon setup and preflight](../../../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a).
- [Isolated renderer and MetalFX trials](../../../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac).
- [Frame collection and reduction](../../../../research/performance/README.md).
- [First M1 session and acceptance matrix](../../../plans/apple-silicon-performance.md#10-first-test-session-on-the-available-m1).

Use new single-writer output directories. The raw v3 sidecar is part of the report;
retain both files and their hashes. Interrupted/capped prefixes are diagnostic
evidence, never successful sustained runs. `--scripted` is a rendering fixture;
headless captures do not establish active native graphics performance. The direct
technical route does not exercise Home preference loading or packaged launch.

Start with Compatibility at 1920×1080 on the actual M1 Air/8 GB. Record OS, power,
display, engine and source identities; run exact local replay and normal
Home/Fly/Workshop checks. Then compare prepared Mobile/Metal and Forward+/Metal
copies with fixed effects/workload. Only evaluate MetalFX after the native
bottleneck and moving-aircraft readability checks justify it. Higher resolutions
follow 1080p; 720p remains the last compatibility target.

## Windows verification

Focused checks passed against the official Windows 4.8-beta1 engine and Python
fixtures; native Mac qualification is not implied:

| Check | Result / scope |
| --- | --- |
| Editor getter | 10 fixtures on Windows Git Bash and WSL; existing Windows/Linux cache paths and shell syntax checked |
| Template/preflight/correction | 40 tests per platform; Windows skips FIFO and four native export cases, WSL skips the four export cases |
| Research launcher/profile | 20 Python tests, including actual Windows headless identity; 78 profile assertions |
| Research preparation | 13 fixtures including identity, path/copy validation, retained partial failure and atomic receipt publication |
| Stream collector | 110 Godot assertions including 30-minute-equivalent 60/120 Hz streams, bounds, malformed metrics and interruption |
| Summary/diagnosis | 71 Python tests including legacy reports, long streams, missing/corrupt/oversized input and completion checks |
| Real capture | Legacy and v3 short captures, frame-cap rejection and external-owner interruption tested with the actual headless Main; counts/final results retained below |
| Reconstruction/preferences | MetalFX policy, shared reconstruction, display preferences, diagnostics, history and Settings focused checks; final results retained below |

The shared tree advanced through externally created commits during this work;
the specialists did not commit or revert other workstreams. A detached test snapshot
was frozen from base `1fc7258e6e3f0d8bdbff88da365167f11912b3dd`, working HEAD
`3bfc7d65320320ceaaa8f174b0c977b618e1a6be` plus dirty changes. Its binary patch
SHA-256 is `cc5ca10f80ea6215f4600ba00cd4dc7ae1dbe7f51c5b34c539330a19bce9eb77`.
Later review fixes receive focused checks separately; this is not an assertion
that the changing shared checkout is one immutable release candidate.

The first full-suite attempt exited during fresh import of the existing
`f4u_corsair.glb`, process status `4294967295`, without a script error diagnostic.
The cause was not established. Existing scene import caches were copied into the
snapshot and revalidated by Godot before the second attempt. This second run is
warm-cache software verification, not a successful cold-import qualification.
Final suite outcome and outstanding failures are recorded here after completion.

Local raw check output is under ignored `tmp/dt-mac-prep/`; it is not a release
artifact or a durable substitute for the required native campaign. No screenshots
were added by this task. Existing unrelated trailer/media work was preserved.
