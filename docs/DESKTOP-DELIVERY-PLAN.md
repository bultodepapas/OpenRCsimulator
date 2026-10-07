# Desktop Delivery Plan

2026-10-07 · Revision 3 · Step prefix: **DT-**.

**Status: DT-00, DT-00-R1 and DT-00-R2 research complete; the latest round adds 12 Godot/Apple Silicon investigations. Implementation is planned; no fullscreen, installer or performance improvement has shipped through this track.**

Owns this plan and `docs/research/desktop-delivery-investigations/`. Proposed implementation paths: `tools/desktop/`, `packaging/`, `research/desktop-delivery/`, `app/tests/test_desktop_*`. Shared changes to export scripts/presets, CI, project settings, first-launch documentation and product UI follow the ownership table below. Evidence: [initial audit](research/desktop-delivery-investigations/DT-00/README.md), [12 follow-up investigations and decision map](research/desktop-delivery-investigations/DT-00-R1/README.md).

Apple Silicon priority: [DT-00-R2 — twelve Mac investigations](research/desktop-delivery-investigations/DT-00-R2/README.md). Start with an M1-class physical baseline, then qualify newer M-series devices against the same contracts. ARM64 export, native execution and acceptable sustained flight are separate results.

## Outcome

A pilot downloads the appropriate desktop package, opens an identifiable application, reaches Home in fullscreen, connects a radio and flies. The app remembers confirmed preferences, recovers from display problems, stays responsive and maintains simulation time. Installation, updates and removal preserve personal settings and calibration.

This is a delivery plan separate from `ROADMAP.md`. It does not change physics priorities or close existing pilot/physics gates. Phases below are incremental releases, not a commitment to build everything at once.

## What exists and what is missing

| Observed in DT-00 | Missing proof or capability |
| --- | --- |
| Pinned Godot 4.7.2, Compatibility, 240 Hz physics; Windows/Linux/macOS presets | Native GUI execution on Windows/macOS in the inspected CI |
| ZIPs, checksums, build identity, exported Linux flight test, macOS bundle/version checks | Installer lifecycle, public signing/notarization, final downloaded-artifact acceptance |
| 1280×720 window configuration, Home, pause, language and aircraft persistence | First-run fullscreen, display preference application, DPI/monitor recovery |
| Versioned raw frame logger and substantial physics/visual evidence | Frozen desktop hardware matrix, current fullscreen performance and end-to-end latency |

See the [launch audit](research/desktop-delivery-investigations/DT-00/01-launch-display.md) and [distribution audit](research/desktop-delivery-investigations/DT-00/02-distribution.md). Existing source checks are retained. A successful cross-export does not certify that the application opens correctly on its target OS.

## Ownership and parallel work

| Area | Owner and coordination rule |
| --- | --- |
| Display preferences, mode controller, UI scale, shortcuts, translations and recovery UI | Menu track: **UI-07, UI-09a, UI-09b** in [MENU-PLAN](MENU-PLAN.md). DT supplies exported acceptance cases; implementation/status remains there. Agree one small patch at a time before shared writes |
| Fullscreen first-launch default | User-requested desktop behavior. Earlier UI research proposed windowed startup; carry this explicit change into UI-09b at its next coordinated revision |
| Export packaging, manifest, icons, installer scripts, native smoke harness | Desktop track; coordinate `app/export.sh`, `app/export_presets.cfg`, `app/get-*.sh`, `.github/workflows/ci.yml`, `app/project.godot` with their current maintainer |
| Build identity | UI-04 remains authoritative. Preserve preset names `Linux`, `Windows`, `macOS` and bundle ID `io.github.bultodepapas.openrcsimulator` |
| Frame logger, graphics knobs, capture/readability | Visual track: reuse VQ-01b and UI-09 integration. Desktop acceptance must not create a second preset system |
| Physics, input sampling, session lifecycle, native extensions | Physics/input owners. Preserve 64-bit state, 240 Hz, real-time checks and goldens; performance work does not authorize numerical changes |
| Shared indexes and lessons | Read `git status` immediately before additive edits; preserve concurrent content. This planning change leaves `ROADMAP.md` untouched |

DT rows that depend on UI/VQ describe **integration acceptance**, not duplicate implementations. Their status says whether the desktop package passes; the originating plan remains authoritative for its feature. Proposed paths are reservations, not permission to edit another track's files.

## Product decisions proposed for implementation

| Topic | Recommendation | Reason / reconsideration trigger |
| --- | --- | --- |
| Default launch | Ordinary non-exclusive fullscreen on first interactive launch; then last confirmed mode | Meets the requested experience; explicit windowed recovery overrides saved state |
| Display settings | Window/fullscreen and UI scale; Keep/Revert for subsequent changes | Avoid monitor-mode switching; validate mixed DPI, lost monitors and OS focus behavior |
| Windows delivery | Maintain portable ZIP; add per-user Setup EXE after portable acceptance | Lowest-friction comparison and rollback; installation adds shortcuts and uninstall |
| Windows installer | Inno Setup candidate; select and pin a tested version in DT-06 | MSIX deferred until Store/managed deployment is an actual requirement |
| macOS delivery | Universal `.app`; signed/notarized distribution with stapled evidence; optional drag-to-Applications DMG | No privileged PKG needed for this app; Mac host and Developer ID prerequisites are explicit |
| Linux delivery | Keep x86_64 archive, correct permissions and documented libraries; add desktop integration only if tested | AppImage/Flatpak deferred until a target distribution gap is demonstrated |
| Graphics | Keep Compatibility as baseline; measure MSAA and 3D scale; compare Mobile/Metal only through DT-11d | Current Mac path is OpenGL, not Metal; a renderer change needs visual, numerical and sustained-cost evidence |
| Updates | Manual download/reinstall initially, preserving `user://` state | An auto-updater adds signing, failure recovery and maintenance beyond the present need |

These proposals do not purchase certificates, publish builds or assert OS support. Tool versions, signing identity and minimum OS versions are selected from evidence in the corresponding phase. The [distribution report](research/desktop-delivery-investigations/DT-00/02-distribution.md) contains vendor sources and tradeoffs.

## Phase 0 — Freeze the delivery baseline

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| DT-00 | Audit current delivery and primary sources; register this track | Existing repository | Three sourced reports, engine version/help and source hashes | Done 2026-10-07 |
| DT-00-R1 | Challenge and refine the plan through 12 independent research questions | DT-00 | Primary-source reports, isolated production-module and Git probes, findings mapped to DT steps | Done 2026-10-07 |
| DT-00-R2 | Qualify the Godot/Apple Silicon design through 12 further investigations | DT-00-R1 | Primary sources, existing Mac artifact metadata, synthetic checker-contract probe; proposed Mac acceptance matrix | Done 2026-10-07 |
| DT-01 | Define supported/tested matrix and collect baseline | Coordinated clean candidate; access to target hosts | Named OS/build/CPU/GPU/driver/display/power profiles; package hashes; initial ten-launch/three-run samples with every result and failure; per-platform support tier explicit | Planned |
| DT-01a | Freeze the physical Apple Silicon floor and comparison hosts | DT-01; available Mac hardware | M1 Air-class 8 GB baseline, exact GPU/RAM/OS/power/display; lowest advertised OS and newer Mac rows; actual ARM64 process and backend recorded | Planned; hardware evidence pending |
| DT-02 | Add repeatable native package smoke harness and evidence schema | DT-01; CI maintainer | Final artifact outside repo: visible Home → Fly → Pause → Continue → End → Quit, host input/logs/timeouts; isolate user data; distinguish headless, virtual display, native architecture and translated execution | Planned |
| DT-02a | Run ARM64 source checks and downloaded-app smoke on macOS | DT-02; CI owner | Pinned Mac editor adapter; portable timeouts; runtime errors fail; final-app trace outside checkout; GUI capability assessed independently of headless success | Planned |
| DT-02b | Accept ARM64 numerical behavior | DT-02a; physics owner/H9 | Existing component budgets and exact discrete states pass across the frozen fleet; no re-recorded goldens or relaxed tolerances to hide architecture differences | Planned |

Start with the owner's actual Windows or Mac machine and the existing Linux target. Initial candidate coverage: Windows 11 x86_64; macOS Apple Silicon plus Intel if claimed supported; Linux x86_64 X11 and native Wayland if claimed supported. Engine support alone does not establish our minimum OS. Record version-specific failures rather than advertising “all Windows/macOS.”

Each platform records separate tiers: **exported/structurally checked → native CI launched → owner accepted on named hardware**. Native CI GUI availability needs a small spike; a hosted OS label does not guarantee a usable interactive desktop. Universal macOS slice inspection and Rosetta execution do not establish Intel-native acceptance. [Test strategy](research/desktop-delivery-investigations/DT-00-R1/08-native-test-strategy.md).

### Apple Silicon baseline

| Candidate | Purpose | Acceptance scope |
| --- | --- | --- |
| Physical M1 MacBook Air, 8 GB, exact GPU-core count recorded | Initial floor; fanless sustained load and memory pressure | AC and battery/default power; built-in Retina; declared 60 Hz flight profile; oldest advertised macOS tested |
| Newer physical M-series Mac, exact chip/RAM/OS recorded | Detect newer-OS/device differences | Same baseline cases; notched display/ProMotion if present; supported external monitor/dock configuration |
| ARM64 macOS CI runner | Repeat numerical and package regressions | Process architecture, source/artifact identity and available capabilities; not owner thermal/USB/display proof |

These are proposed qualification hosts, not measured minimum requirements. Godot 4.7 documentation and the inspected bundle declare **macOS 13 for Apple Silicon**; use that as the initial OS-floor candidate and test it before advertising support. The inspected ARM64 Mach-O has a lower load-command minimum, which must not override bundle/engine requirements. Keep Intel support a separate optional qualification. [Architecture/minimum OS](research/desktop-delivery-investigations/DT-00-R2/04-arm64-native-dependencies.md).

The current downloader/test shell assumes Linux; establish a pinned Mac adapter before promising native CI. Preserve source tests and final-package tests as separate layers. On Macs, isolate test accounts/user-data using macOS behavior, not assumed Linux XDG redirection. [CI qualification](research/desktop-delivery-investigations/DT-00-R2/10-native-ci-qualification.md), [ARM64 numerical contract](research/desktop-delivery-investigations/DT-00-R2/11-arm64-physics-numerics.md).

**Exit:** a reproducible baseline and a native smoke result for each intended pilot package, with remaining hardware gaps visible. Source/export failures are fixed before adding an installer.

## Phase 1 — Fullscreen with a reliable escape path

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| DT-03 | Agree display precedence and acceptance with UI-07/09; expose missing route tests | DT-02; menu owner | Table covers fresh launch, saved mode, engine CLI overrides and all automation routes; no duplicate preferences store | Planned |
| DT-03a | Establish recoverable settings and a writer policy | DT-03; UI-07; input owner for calibration | Stable user-data location, schema migration, interrupted/failed replacement, future schema intact and two-instance race test; display reset preserves calibration | Planned |
| DT-04 | Accept first-run fullscreen and recovery in exported apps | DT-03a; UI-09b coordinated slice | Home initially fullscreen; saved windowed mode survives restart; bounded transition/readback/fallback; F11/menu access; `--windowed --resolution 1280x720` recovers without changing calibration | Planned |
| DT-05 | Accept DPI, confirmation, display loss and focus | DT-04; UI-09a/b; session owner for focus | Matrix below; cancellation/15 s timeout/process interruption restore confirmed state; focus holds survive display transitions; radio never drives UI | Planned |
| DT-05a | Unify native shutdown and suspend/focus acceptance | DT-05; session/audio/menu owners | Window close/Alt+F4/Cmd+Q follow the same trace-save/error policy as Quit; sleep/wake and audio-device change preserve holds and leave no runaway sound/process | Planned |
| DT-05b | Verify installed-radio support claims | DT-04; UI-10a/10b/12 and input owner as needed | Recorded hardware/firmware/USB mode/axis map; arming, hotplug, focus, duplicate devices and upgrade persistence; narrow unsupported configurations explicitly | Planned |

Required behavior: fullscreen applies only to the interactive route; automation retains explicit dimensions and does not touch user preferences. First-run fullscreen opens directly without a mandatory settings wizard. Later display changes save only after Keep; timeout uses wall time while flight is paused. Mode-change focus events may pause but must not instantly undo a valid transition. Returning from another app does not resume flight by itself.

Treat a display change as requested → transitioning → effective/read back → confirmed or reverted. Bound transition time separately from the proposed 15 s confirmation period, which begins when the confirmation is usable. Keep the last confirmed configuration recoverable across process death; an interrupted first-run attempt must have a windowed recovery path. [Fullscreen transactions](research/desktop-delivery-investigations/DT-00-R1/04-fullscreen-transactions.md).

Freeze `user://` identity independently of install location. The [executed settings probe](research/desktop-delivery-investigations/DT-00-R1/10-settings-durability.md) reproduces stale-reader lost updates; choose one writable interactive instance or a tested conflict-aware writer. Temp-file replacement alone does not solve that race. Preserve future-schema refusal, isolate automated runs, and distinguish process-crash recovery from unproven power-loss guarantees.

UI scale and 3D render scale stay separate. Acceptance includes 720p/1080p/1440p/4K, 16:10/ultrawide, 200% UI scale, Windows fractional DPI, Mac Retina/external screen and Linux fractional Wayland scaling. Buttons remain reachable in English and Spanish. Reuse UI-09a's text/readability criteria and the visual team's camera/attitude checks; stretching must not silently alter the pilot-view contract.

Record logical window size, rendered pixel dimensions, effective UI scale and camera FOV/aspect separately to detect double scaling. Use the same aircraft pose/distance for readability comparisons; avoid counting a larger autozoomed airplane as an antialiasing improvement. The camera's 30 px target is constrained by its FOV limits, not guaranteed at every distance/resolution. [DPI/camera study](research/desktop-delivery-investigations/DT-00-R1/05-dpi-camera-readability.md).

The [native lifecycle audit](research/desktop-delivery-investigations/DT-00-R1/06-native-close-suspend-audio.md) identifies a close path that bypasses trace saving. DT-05a must expose save failure visibly with Retry/Discard/Cancel and preserve retryable data; merely forwarding native close to the current Quit method is insufficient. The [USB radio contract](research/desktop-delivery-investigations/DT-00-R1/12-radio-export-contract.md) supplies installed-device cases. Preserve the input owner's standalone diagnostic route when adding display arguments; its event timing is not physical input latency.

On macOS, fullscreen readback may reflect a cached requested state before AppKit finishes its Spaces transition. Require a usable visible window, stable layout and successful input in addition to mode readback. Validate Control-Command-F/green-button/menu behavior, Mission Control, external-display removal and notched screens; do not infer notch geometry from Godot's mobile-only safe-area API. Provide menu access that does not depend on Fn/F-key settings. [Mac window/input study](research/desktop-delivery-investigations/DT-00-R2/05-spaces-retina-input.md).

Mac radio acceptance distinguishes accessory authorization, OS USB enumeration, SDL identity and calibration; neither a charging cable nor an authorized hub proves controller input. CoreAudio recovery includes default-output switching, wired/Bluetooth output, sleep/wake and generator underruns; Dummy-driver checks cannot pass it. [Radio](research/desktop-delivery-investigations/DT-00-R2/08-macos-usb-radio-access.md), [audio](research/desktop-delivery-investigations/DT-00-R2/09-coreaudio-device-sleep-recovery.md).

**Exit:** the pilot opens and exits fullscreen, changes applications and disconnects a monitor without getting stuck or accidentally resuming flight. Missing native evidence prevents claiming that platform accepted.

## Phase 2 — Make the portable packages complete

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| DT-06 | Choose packaging tools and create source-controlled branding/metadata | DT-02; UI-04; maintainer | Exact tool versions/digests; native icon/title/version in Explorer, taskbar, Finder and Dock; preserve numeric version/full build identity distinction | Planned |
| DT-07 | Package manifest, licenses and portable layout | DT-06 | Fresh checkout produces declared files; required JSON/resources/libraries present; code, Godot and asset notices accessible offline; no tests, credentials or local reference material shipped | Planned |
| DT-08 | Harden release staging and final integrity checks | DT-07 | Unique staging directory per build; package set promoted only after validation; dirty candidates clearly identified and rejected for public release; final ZIP/DMG/installer hashes and manifest agree | Planned |
| DT-08a | Verify source provenance and promote exact final bytes | DT-08; CI maintainer | Clean tracked/untracked preflight, declared ignored inputs, engine/template/tool identities, final digests verified after download; tested/signed artifacts promoted without rebuilding | Planned |
| DT-08b | Retain Mac diagnostic and native-symbol identity | DT-08a; release owner | Executable/dependency UUID inventory, matching dSYM availability or explicit gap; bounded local logs/report; exact candidate identified in a failure rehearsal | Planned |

The current export script deletes the shared `dist/` directory: replace that behavior during DT-08 with isolated staging before parallel export work is permitted. Build scripts currently assume Linux tools and downloads; native jobs need small pinned platform adapters, not the assumption that the Bash pipeline runs unchanged on macOS/Windows.

`git describe --dirty` misses untracked files: use full porcelain status and an isolated candidate checkout, with generated/ignored inputs declared. Build identity, checksums, signatures and provenance each prove different properties. Preserve the existing build-once/artifact-download release graph, validate the exact file set after transfer, and serialize final promotion. Attestations are optional additional provenance after final transforms, not a prerequisite for the first fullscreen build. [Provenance investigation](research/desktop-delivery-investigations/DT-00-R1/07-release-provenance.md).

Verify the existing `embed_pck=true` layout with the selected Windows signing tool and a post-signing flight/pack check. Retain it if valid; consider a separate PCK only if a demonstrated tooling or update requirement warrants the layout change. A portable ZIP can contain either layout. Icons/version resources must be finalized before signatures. Hash final distributed artifacts after signing, notarization/stapling and packaging. [Windows/macOS findings](research/desktop-delivery-investigations/DT-00/02-distribution.md).

**Exit:** each portable artifact contains its declared runtime and attribution, starts outside the source checkout, identifies its build correctly and passes a repeat build from a clean checkout. Bit-for-bit reproducibility is a separate, unclaimed property until compared independently; signatures/timestamps can change bytes.

## Phase 3 — Installation and operating-system trust

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| DT-09a | Windows installer prototype | DT-07; pinned installer tool | Standard-user install without elevation, Start menu entry, optional desktop shortcut, Apps uninstall entry; spaces/non-ASCII paths; app runs without editor/runtime installation | Planned |
| DT-09b | Windows lifecycle and signed candidate | DT-03a/05a/08/09a; publisher identity/credential availability | Install → upgrade → repair/reinstall → uninstall → reinstall; preferences/calibration survive; changed EXE with equal numeric version replaces correctly; running-app replacement handled; EXE/installer/uninstaller signatures and timestamp verified; actual browser-download SmartScreen result recorded | Planned; signing prerequisite open |
| DT-09c | macOS signed universal app and DMG candidate | DT-08; Mac runner, Developer ID/notarization credentials | Both architecture slices verified; nested code signed before outer app; notarization accepted, ticket stapled/validated; downloaded DMG → Applications → Finder launch on clean account; Gatekeeper result including offline launch | Planned; signing prerequisite open |
| DT-09d | Linux portable and launch integration | DT-08; native target | Executable bits survive extraction, shared libraries checked, icon/desktop entry if offered, clean-account GUI smoke and user-data persistence | Planned |

Installer identity and data location remain stable across versions; installer files and user data have separate ownership. Uninstall retains calibration/settings by default. Any explicit “remove personal data” option must be clear and separately tested. Test failed/interrupted upgrade and refuse an unsafe downgrade schema rather than silently overwriting newer settings.

Define stable installer identity separately from prerelease build labels and numeric OS versions; test RC-to-RC ordering, same-version reinstall and downgrade. Ensure update/shutdown coordination preserves active traces rather than force-killing a running simulator. Configure Inno's compiler signing flow for both Setup and its embedded uninstaller after signing the game payload; verify all three outputs. [Windows lifecycle](research/desktop-delivery-investigations/DT-00-R1/01-windows-installer-lifecycle.md).

For macOS, maintain separate ZIP and DMG transformation recipes: sign nested code inside out, notarize the intended distribution container, staple supported targets, recreate ZIP after app stapling, then validate/hash final bytes. For Linux, publish a measured runtime-library/ABI and compositor contract; adding AppImage or Flatpak is conditional on an observed distribution gap. [macOS trust](research/desktop-delivery-investigations/DT-00-R1/02-macos-trust-pipeline.md), [Linux runtime](research/desktop-delivery-investigations/DT-00-R1/03-linux-runtime-contract.md).

DT-09c must separate structural validation from signing policy: `check_macos_export.py` currently accepts only ad-hoc flags, and the synthetic probe demonstrates that this is not cryptographic verification. Keep its slice/layout checks, add the intended distribution-signature policy and verify final trust natively. Inspect every bundled native dependency, preserve library validation unless a demonstrated requirement justifies an exception, and write no mutable data into the signed bundle. [Trust/dependency refinement](research/desktop-delivery-investigations/DT-00-R2/06-signing-quarantine-updates.md).

Public acceptance must not rely on removing quarantine or disabling system protections. Signing establishes publisher identity; it does not guarantee SmartScreen reputation or every enterprise policy will allow a build. Keep unsigned engineering artifacts clearly labeled if credentials are unavailable; packaging work can continue, while public-trust acceptance remains pending.

Signing credentials belong in the CI secret/keychain mechanism, never presets, archives or logs. Restrict signing to trusted release jobs; untrusted pull-request code must not receive signing credentials. Keep unsigned build validation separate so ordinary contributions can still be tested.

**Exit:** native installation/lifecycle evidence for each promoted target and verified final signatures. The owner chooses a public distribution channel once the concrete candidate and trust results exist; this is the DT-13 gate, not a prerequisite for research or prototyping.

## Phase 4 — Optimize measured desktop costs

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| DT-10 | Measure fullscreen, startup and live simulation costs | DT-01/05/08; VQ logger; physics workloads | Frozen package, real GPU, three 10 s warm-up + 60 s runs/case; raw p50/p95/p99/max; matched simulation/wall interval; no paused/scripted-flight throughput claims | Planned |
| DT-10a | Qualify metrics and comparison uncertainty | DT-10; visual/input owners | Label callback cadence versus presentation/latency; record quantile method/counts, every run and paired differences; add blocks when effects remain within run variation | Planned |
| DT-10b | Qualify sustained Apple Silicon performance and memory | DT-01a/02b/10a; visual/physics owners | Physical M1 8 GB soak with active graphics, raw tick/frame timing, memory pressure and AC/battery states; separate 60 Hz and optional ProMotion results; recover safely from sleep/occlusion | Planned |
| DT-11a | Fix the largest demonstrated startup/first-frame cost | DT-10; UI/visual owner | Paired cold/warm launch and Fly timings; draw/loading remains responsive; no loading completed early by omitting first draw or starting flight offscreen | Conditional on DT-10 |
| DT-11b | Reduce measured idle/minimized cost | DT-10; session/menu owner | Home/pause/minimized CPU/GPU comparison; confirmation clock works; restore/focus does not auto-resume or produce a catch-up jump | Conditional on DT-10 |
| DT-11c | Introduce only justified graphics options | DT-10; visual/UI owners | One option/change; recorded effective settings; paired cost improvement plus blinded aircraft readability; physics trajectory and input behavior unchanged | Conditional on DT-10 |
| DT-11d | Compare Compatibility/OpenGL with Mobile/Metal on Apple Silicon | DT-10b; visual owner; clean experimental candidate | Same scene/pose/pixels; actual driver logged; startup/shaders/alpha/depth/color/readability checked; sustained cost, memory and replay agreement; retain baseline unless migration evidence warrants a separate decision | Conditional on measured renderer need |

Targets originate in [DT-00 performance acceptance](research/desktop-delivery-investigations/DT-00/03-performance-acceptance.md), refined by [09 — Performance statistics](research/desktop-delivery-investigations/DT-00-R1/09-performance-statistics.md): initial goals include ≤3 s warm/≤5 s cold Home, ≤2 s Fly, **process-loop interval** p95 ≤18 ms/p99 ≤25 ms at 60 Hz and simulation/wall ratio 0.99–1.01. These are **proposed engineering budgets** to freeze on named hardware in DT-01, not current measured results. The existing logger cannot certify display presentation or input-to-photon latency; those need native timing/high-speed evidence. Physics and latency budgets stay with Phase H/Gate P and F6.

Ten launches and three runs are initial per-host screening samples, not a population reliability/p99 guarantee. Keep per-run raw data, actual interval counts, failures and paired before/after differences. Freeze the quantile method. Expand paired sampling when the effect remains near observed variation, or reject the optimization as unproven. Optional CPU/GPU instrumentation must be validated for Compatibility and its overhead disclosed.

For Mac evidence, extend the logger with actual rendering driver (not just rendering method), native process architecture, backing/rendered pixel sizes, full VSync mode and refresh/cap. Current MSAA enum 2 means 4×; a full 2560×1600 framebuffer has 4.44× the pixels of 1280×720 before MSAA. Compare MSAA/render-scale independently from UI scale and autozoom. Unified memory removes neither texture cost nor pressure on an 8 GB machine. [Renderer](research/desktop-delivery-investigations/DT-00-R2/01-renderer-metal-opengl.md), [Retina/memory](research/desktop-delivery-investigations/DT-00-R2/02-retina-fillrate-memory.md).

Start with a declared 60 Hz profile on the physical floor; do not advertise 120 Hz merely because a Mac has ProMotion. Record effective present cadence separately from callback intervals and assess input latency with its existing physical method. Keep 30-minute thermal evidence and session-cycle memory evidence; classify low-power/battery/occluded states separately. The current frame logger stops at 300 s and quits: DT-10b needs bounded continuous/host instrumentation before claiming a full-soak time series. Record Godot's existing `keep_screen_on` behavior and agree active-flight versus idle policy; do not add CPU-affinity hacks, disable App Nap globally or add wake assertions to hide a timing problem. [Pacing](research/desktop-delivery-investigations/DT-00-R2/03-promotion-frame-pacing.md), [sustained energy](research/desktop-delivery-investigations/DT-00-R2/07-apple-silicon-thermal-energy-soak.md).

Break startup into resource loading, procedural scene construction, aircraft trim/validation and first usable draw before choosing DT-11a. `load_threaded_get()` can still block; scene construction does not automatically become asynchronous. Compatibility gains nothing from the Forward+/Mobile shader baker; test bounded actual rendering of needed materials only if shader stalls are measured. Keep physics/audio held until flight is ready and support cancellation. [Startup study](research/desktop-delivery-investigations/DT-00-R1/11-startup-loading.md).

Retain an optimization only when the measured benefit exceeds run variation and it preserves readability, correctness and lifecycle behavior. The current 240 Hz/12-step catch-up arithmetic gives a 20 fps scheduling floor, not an acceptable pilot frame-rate target; keep the proposed 60 Hz target and measure real-time progression during stalls. Idle caps may differ only while simulation is held, with a verified restore path. High-refresh and VSync choices require native presentation/latency evidence.

**Exit:** agreed reference hardware meets the frozen budgets or a documented scope decision explains the miss. Physics speedups, renderer migration and auto quality adaptation are separate proposals requiring new evidence.

## Phase 5 — Release rehearsal and pilot acceptance

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| DT-12 | Rehearse the entire downloaded release | DT-05/05a/05b/08a/09/10a; Mac DT-01a/02a/02b/08b/10b; relevant DT-11 results | Clean-account native matrix below, same digests as promoted assets, complete suite on frozen commit, 30-minute soak and 50 Home/flight cycles, verified upgrade/data recovery | Planned |
| DT-13 | Gate DT: owner accepts desktop delivery per platform | DT-12 evidence | Owner receives candidate, concise comparison, open defects, trust results and rollback procedure; platform-specific decision recorded in DECISIONS | Open |

Gate DT is independent of Gate 2 and Gate P. An experimental flight model remains experimental even in a polished installer. Unavailable hardware, unsigned public candidates or blocked launch paths remain visible blockers for the affected platform, rather than passing through export success.

Mac release evidence must identify failure layers: trust/loader, Godot scripts, graphics/presentation, radio/audio and numerical simulation. Retain matching native symbols by UUID where available; explicitly record missing official-template symbols instead of substituting a rebuild. Provide a short local troubleshooting/report path. [Diagnostics](research/desktop-delivery-investigations/DT-00-R2/12-macos-diagnostics-symbols.md).

## Acceptance matrix and evidence contract

| Layer | Mandatory cases | Evidence |
| --- | --- | --- |
| Logic/CI | Route precedence; corrupt/future/read-only preferences; trial timeout/interruption; reset preserves calibration; final manifest/files | Automated results from isolated user-data paths; existing suite/pack checks |
| Native desktop | Fresh/default/saved/recovery launch; resize/DPI/multi-monitor; Alt+Tab/Cmd+Tab; minimize; sleep/wake; lost radio; window close/Alt+F4/Cmd+Q with active trace | OS/build, display/backend, steps, expected/actual behavior, logs and captures |
| Distribution | Browser download/quarantine; signatures; offline first use; install/upgrade/uninstall; paths with spaces/non-ASCII; read-only install directory | Final digest, signature/notarization logs, clean-account run and preserved settings |
| Performance | Startup, first flight, all offered aircraft, visual path, actual simulation, paused/minimized, 60 Hz and claimed higher refresh | Raw clocks plus hardware/candidate metadata; repeated runs and disclosed cache state |
| Pilot | Fullscreen, visible/focused controls, radio arming/reconnect, aircraft attitude recognition, sensible fan/power behavior | Owner session and observed problems; no substitution with headless checks |

Evidence for every implementation step goes under `docs/research/desktop-delivery-investigations/<DT-ID>/`, with commands, candidate commit/digests, environment, outcome and limitations. Store representative captures/reports in tracked evidence; larger artifact locations need stable release/CI references. Never link to ignored capture folders. Append the practical lesson to LEARNINGS and include proof in the step's commit message.

Research validation: DT-00 checked links/registration/engine CLI; DT-00-R1 additionally ran isolated copied-module and disposable-Git probes and static inspection of an existing Linux export. No full app suite, export, native display/radio or performance benchmark was run for these planning changes. The first implementation slice is **DT-01 → DT-02 → DT-03/03a/04**, delivering reliable fullscreen on an existing portable build before installer polish. DT-06–08 can proceed independently once native baseline work is established.

DT-00-R2 adds static Mac artifact inspection and an executed synthetic checker-contract probe on Linux. It claims no native Mac performance or launch result. Apple Silicon execution order is **DT-01a → DT-02a/02b → DT-04/05/05a/05b → DT-09c/10b → DT-12**; DT-08b accompanies packaging, and DT-11d remains optional. All research evidence is separate from implementation acceptance.
