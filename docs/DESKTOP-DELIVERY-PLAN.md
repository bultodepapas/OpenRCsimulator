# Desktop delivery plan

2026-10-12 · Revision 4 · Step prefix: **DT-**.

**Status:** DT-00, DT-00-R1 and DT-00-R2 research is complete. DT-01–DT-12 remain planned or conditional; the owner acceptance gate DT-13 is open. No fullscreen, installer, public signing/notarization or native Windows/macOS acceptance has shipped through this track.

Research records remain in [DT-00](research/desktop-delivery-investigations/DT-00/README.md), [DT-00-R1](research/desktop-delivery-investigations/DT-00-R1/README.md) and [DT-00-R2](research/desktop-delivery-investigations/DT-00-R2/README.md). The latter reports inspect Godot/macOS artifacts and synthetic checker behavior; they do not establish native Mac launch or performance.

## Current delivery

Godot 4.7.2 is pinned, Compatibility is the renderer, physics runs at 240 Hz, and `app/project.godot` sets a 1280×720 viewport. Presets export Linux x86_64, Windows x86_64 and a universal macOS app from the Ubuntu CI job. `app/export.sh` embeds the PCK, creates ZIPs and `SHA256SUMS`, checks the exported Linux binary with a trimmed-flight trace, checks field data in each pack, checks macOS slices for an ad-hoc signature, and checks Windows/macOS numeric version metadata.

CI itself runs on Ubuntu; its cross-exports do not prove that Windows or macOS launches. The macOS export is ad-hoc signed and not notarized. There is no installer lifecycle test, final downloaded-artifact run, fullscreen/display recovery acceptance, frozen native hardware matrix or sustained desktop performance result. `app/export.sh` also removes the shared `dist/` directory before building; DT-08 must replace that with isolated staging.

Display preferences and recovery belong to [MENU-PLAN](MENU-PLAN.md) (UI-07/09); build identity remains UI-04. DT records desktop-package acceptance and coordinates changes to shared export, preset and CI files with their maintainers. Export success alone is not platform support.

## Accepted step register

| ID | Deliverable and minimum proof | Status |
| --- | --- | --- |
| DT-00 | Audit delivery, engine and primary sources; register the track. | Done — 2026-10-07 |
| DT-00-R1 | Challenge the plan with twelve focused implementation and release investigations. | Done — 2026-10-07 |
| DT-00-R2 | Investigate Godot/macOS and Apple Silicon packaging, native CI, numerics and performance. | Done — 2026-10-07 |
| DT-01 | Freeze each claimed OS/build/hardware/display profile; record package hashes and launch/performance baselines. | Planned |
| DT-01a | Measure an M1-class 8 GB Mac floor and comparison hosts; record chip, OS, power, display and actual process architecture. | Planned — hardware evidence pending |
| DT-02 | Build a repeatable native smoke harness against the final package and isolated user data. | Planned |
| DT-02a | Run source checks and downloaded-app smoke on a pinned macOS ARM64 host; keep GUI and headless results distinct. | Planned |
| DT-02b | Check ARM64 numerical budgets and discrete outcomes without re-recording goldens or relaxing tolerances. | Planned |
| DT-03 | Agree display precedence with UI; test fresh, saved, CLI and automation routes without duplicate preferences. | Planned |
| DT-03a | Test settings schema, failed/interrupted writes, future versions, concurrent writers and calibration preservation. | Planned |
| DT-04 | Accept first-run fullscreen, saved windowed mode and `--windowed --resolution 1280x720` recovery in exported apps. | Planned |
| DT-05 | Accept DPI, resizing, display loss and focus; test Keep/Revert with a usable 15 s wall-clock timeout and no automatic flight resume. | Planned |
| DT-05a | Test close/quit, suspend/wake and audio-device changes; trace-save failure must offer Retry/Discard/Cancel. | Planned |
| DT-05b | Record installed-radio hardware, firmware, USB mode and supported arming/reconnect behavior per platform. | Planned |
| DT-06 | Pin packaging tools and source-controlled application branding/metadata. | Planned |
| DT-07 | Declare portable package contents and offline licenses; verify clean-checkout output excludes tests and local material. | Planned |
| DT-08 | Use per-build staging and validate final package set, manifest and hashes before promotion. | Planned |
| DT-08a | Record clean source/tool/template provenance and promote the exact tested bytes without rebuilding. | Planned |
| DT-08b | Record macOS executable/dependency UUIDs, available matching symbols and a local diagnostic path. | Planned |
| DT-09a | Prototype a no-elevation Windows install; verify Start-menu entry, optional shortcut, uninstall registration and paths with spaces/non-ASCII. | Planned |
| DT-09b | Test Windows install/upgrade/repair/uninstall and preference preservation; verify app/installer/uninstaller signatures and browser-download trust result. | Planned — signing prerequisite open |
| DT-09c | Sign nested code, notarize/staple a universal macOS app/DMG and verify downloaded online/offline launch on a clean account. | Planned — signing prerequisite open |
| DT-09d | Accept Linux extraction permissions, runtime libraries and any offered desktop integration on a native target. | Planned |
| DT-10 | Measure startup, fullscreen and active simulation on frozen packages and named hardware; warm up 10 s and record 60 s per case. | Planned |
| DT-10a | Define timing semantics, sample counts, quantiles, paired comparisons and uncertainty before optimization. | Planned |
| DT-10b | Soak an M1-class 8 GB Mac at the declared 60 Hz profile; record 30 min of timing, memory, AC/battery state and sleep/occlusion recovery. | Planned — hardware evidence pending |
| DT-11a | Fix the largest measured startup/first-frame cost without hiding loading or starting flight early. | Conditional on DT-10 |
| DT-11b | Reduce measured idle/minimized cost while preserving focus and simulation timing. | Conditional on DT-10 |
| DT-11c | Add a graphics option only when paired performance and blinded readability evidence support it. | Conditional on DT-10 |
| DT-11d | Compare Compatibility and Mobile/Metal only if measurements show a renderer need; preserve the baseline absent evidence. | Conditional on DT-10b |
| DT-12 | Rehearse the downloaded release on clean accounts using promoted hashes, the frozen suite, soak and repeated launch/flight cycles. | Planned |
| DT-13 | Record the owner's platform-by-platform delivery decision, defects, trust results and rollback path. | Open — delivery gate |

## Acceptance and evidence

DT-01 records separate tiers: exported/structurally checked, native CI launched, and owner accepted on named hardware. Apple Silicon ARM64 export, native execution and sustained acceptable flight are separate claims. Intel macOS is a separate claim if it is offered. A hosted runner label or Rosetta run is not native owner acceptance.

DT-10 budgets are proposals to freeze against DT-01 hardware, not current results: Home ≤3 s warm/≤5 s cold, Fly ≤2 s, process-loop interval p95 ≤18 ms/p99 ≤25 ms at 60 Hz, and simulation/wall ratio 0.99–1.01. The current logger does not measure presentation or input-to-photon latency. DT-10b needs evidence beyond its current 300 s capture limit. Performance work must preserve flight numerics and readability.

DT-12 includes final digest identity, clean-account launch and distribution checks, platform logs, a 30-minute soak and 50 Home/flight cycles. Evidence for each step stays under `docs/research/desktop-delivery-investigations/<DT-ID>/` and records commit, artifact hashes, OS/hardware, commands, results and limits. Never infer a native pass from an export or headless test.

The detailed sources and acceptance studies remain available: [native-test strategy](research/desktop-delivery-investigations/DT-00-R1/08-native-test-strategy.md), [fullscreen transactions](research/desktop-delivery-investigations/DT-00-R1/04-fullscreen-transactions.md), [release provenance](research/desktop-delivery-investigations/DT-00-R1/07-release-provenance.md), [Mac trust pipeline](research/desktop-delivery-investigations/DT-00-R1/02-macos-trust-pipeline.md), [Apple Silicon performance](research/desktop-delivery-investigations/DT-00-R2/07-apple-silicon-thermal-energy-soak.md), and [Mac diagnostics](research/desktop-delivery-investigations/DT-00-R2/12-macos-diagnostics-symbols.md). Signing tools, OS support floors and release channels are selected only from evidence in the relevant accepted steps.
