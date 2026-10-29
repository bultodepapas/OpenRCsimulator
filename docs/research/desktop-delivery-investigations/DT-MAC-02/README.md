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
| Template/preflight/correction | Initial combined getter/template/preflight/correction run: 40 tests per platform. Final rerun after shared template-cache hardening: 46 tests per platform, successful with five Windows skips (FIFO and four native export cases) and four WSL skips (native export cases) |
| Research launcher/profile | 21 Python tests, including actual Windows headless identity; 78 profile assertions |
| Research preparation | 13 fixtures including identity, path/copy validation, retained partial failure and atomic receipt publication |
| Stream collector | 112 Godot assertions including 30-minute-equivalent 60/120 Hz streams, bounds, malformed metrics, interruption and late report-path collision |
| Summary/diagnosis | 74 Python tests including legacy reports, long streams, missing/corrupt/oversized input, completion checks and explicit CLI soak-duration gates |
| Real capture | Seven actual headless Main cases: legacy and v3 short captures, frame-cap rejection, external-owner interruption and preservation of a late-created report sentinel |
| Reconstruction/preferences | MetalFX policy 51, shared reconstruction 118, display preferences 160, diagnostics 26, reconstruction history 16, FSR history 11, camera history 25, advanced graphics 146; Settings 1080p/200% and nine-language checks passed |

The shared tree advanced through externally created commits during this work;
the specialists did not commit or revert other workstreams. A detached test snapshot
was frozen from base `1fc7258e6e3f0d8bdbff88da365167f11912b3dd`, working HEAD
`3bfc7d65320320ceaaa8f174b0c977b618e1a6be` plus dirty changes. Its binary patch
SHA-256 is `cc5ca10f80ea6215f4600ba00cd4dc7ae1dbe7f51c5b34c539330a19bce9eb77`.
That first snapshot captured an in-progress UI review edit, and its warm-cache run
correctly rejected a type-inference error. After the specialists finished, the
snapshot was refreshed with their final files at 23:00 UTC: patch SHA-256
`1f481522f13e281324a28667ee2492158c504aadd44f946664074ff9786615b9`, same base and
working HEAD. The final per-file manifest is retained with local check output.
This is not an assertion that the changing shared checkout is one immutable
release candidate.

A later focused shared-tree check covered concurrent FSR runtime-failure changes:
reconstruction (118), MetalFX policy (51), FSR history (16), and advanced graphics
Settings (146) all passed. Reconstruction source stayed unchanged during the run,
SHA-256 `7ccf7d4bddfbfa2f6a236f73fc2ccf983ea8347e7de71f53771d7acae9615efd`.
This supplements the frozen snapshot rather than silently changing its identity.

The reducer subsequently gained optional `--minimum-warmup-s` and
`--minimum-sample-s` gates. Defaults remain 10/60 seconds and the three-run minimum
is unchanged; the Mac procedure explicitly requests 30/1800 seconds and three
independent soaks. CLI tests prove that valid short captures are rejected by that
soak policy without invalidating their collection. This is a separately verified
offline-tool change; the running integration snapshot was not mutated.

The first full-suite attempt exited during fresh import of the existing
`f4u_corsair.glb`, process status `4294967295`, without a script error diagnostic.
The cause was not established. Existing scene import caches were copied into the
snapshot and revalidated by Godot before the second attempt. This second run is
warm-cache software verification, not a successful cold-import qualification.
Final partition outcomes and outstanding failures are recorded below.

The refreshed suite next detected byte-pinned customization sources changed by
the disposable worktree's `core.autocrlf=true` checkout. Twelve presentation files
differed only by CRLF/LF; the live checkout's customization freshness check passed.
The snapshot was synchronized to the exact working-tree bytes (6,792 text/source
files checked, 2,800 copied), without changing the generated registry. Its
freshness check then passed. Final broad verification uses the existing
`integration` partition and four `units` shards, each with a separate user-data
directory; this changes test scheduling, not assertion or acceptance rules.

The complete **integration partition passed**. Its checked collection contains
**1,578 successful invocations**, including **1,538 script-parse checks**, with
zero rejected/invalid reports. The existing report summarizer verified the logs
and emitted JUnit. The suite also completed its Python-driven trace/CLI checks,
negative controls, model contracts, finite frame reports, numerical sensitivity,
and fixed-step/hash comparisons at 30/60/144 FPS. The retained integration log's
SHA-256 is `d8bf7c85e331f2a5f2478b5f8960c8723cb74b30974f9f947927d485d56aaf3e`.
These are Windows software results, not Mac, graphics-performance or physical
validation.

The broad unit run is complete under the existing stop-on-first-failure policy:

| Partition | Checked invocations, including import | Result |
| --- | --- | --- |
| Unit 0/4 | 217 | All passed; 216 selected unit scripts |
| Unit 1/4 | 54 | 53 passed, one failed; stopped at engine audio |
| Unit 2/4 | 62 | 61 passed, one failed; stopped at the fixed-brake reference check |
| Unit 3/4 | 216 | All passed; 215 selected unit scripts |

Across the four partitions, 545 of the frozen snapshot's 861 unit scripts were
attempted: 543 passed and two failed; 316 later scripts in the failed partitions
were not run. The existing named pending-physics policies in `app/test.sh` were
preserved. The checked-report summarizer validated each collection and wrote
JUnit output locally. This is **not a full-suite pass**.

The two failures are outside the edited graphics and capture paths:

- `test_engine_audio.gd`: 146 checks, three device-aware queue-target failures.
  A separate run with fresh user data reproduced two failures of the same assertion
  (exit 1, 60.547 s, not a timeout). Relevant audio source/config and all 370
  baseline-tracked simulation/physics/aircraft files match `c953c8c` after line-ending
  normalization, with the same pinned engine; a pristine baseline was not executed
  and the cause is not established. No audio or physics change was made.
- `test_fixed_gear_brake_input.gd`: 257 checks, two exact frozen-reference failures
  for `sebart-avanti-s-a200-p100rx` (checkpoint/metadata and CSV). The physics path
  was not changed and no golden data was re-recorded. The frozen Windows source
  pin is `3ebd08c2869207e869c3c127da6f0db7be1409a32ab0903b17d3211d0b2807b1`;
  the snapshot aircraft file is `048305d4000829fbcf4b1854bd0a89e506b7b01a6ed4a64f1c758519716dbbbd`.
  Historical commit `b1c6d9806`, before this Mac work, changed its description
  from `Ventage Jet` to `Vantage Jet`; parsed JSON is otherwise identical.
  Aircraft identity hashes include the description and feed checkpoint/trace
  metadata, explaining a provenance difference without establishing changed
  physics. The separate three-tick exact continuation check passed. The combined
  failing assertion does not separate checkpoint and metadata digests, so this
  is not a complete field-by-field runtime attribution. The acceptance failure
  remains open for the reference owner; it is not waived or physical validation.

Local raw check output is under ignored `tmp/dt-mac-prep/`; it is not a release
artifact or a durable substitute for the required native campaign. No screenshots
were added by this task. Existing unrelated trailer/media work was preserved.
