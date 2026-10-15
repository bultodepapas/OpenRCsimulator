# Desktop delivery plan

2026-10-15 · Revision 22 · Step prefix: **DT-**.

**Status:** DT-00, DT-00-R1 and DT-00-R2 research is complete. DT-01–DT-12 remain open; initial DT-10/10a measurements and a narrow DT-11a lake geometry reuse repair are recorded through VQ-01c; cold loading and package qualification remain open. The owner acceptance gate DT-13 is open. No fullscreen, installer, public signing/notarization or native Windows/macOS acceptance has shipped through this track.

Research records remain in [DT-00](research/desktop-delivery-investigations/DT-00/README.md), [DT-00-R1](research/desktop-delivery-investigations/DT-00-R1/README.md) and [DT-00-R2](research/desktop-delivery-investigations/DT-00-R2/README.md). The latter reports inspect Godot/macOS artifacts and synthetic checker behavior; they do not establish native Mac launch or performance.

Latest DT-11a evidence: [horizon construction](research/visual-quality-implementation/VQ-01c/loading/horizon-build/README.md). Five native runs preserve complete mesh output; construction median is 68.721→55.027 ms. This does not measure full Home/Fly loading or FPS. A combined native horizon/atmosphere regression test reports four texture shutdown errors on reference and candidate; isolation remains open. [Earlier shadow blur](research/visual-quality-implementation/VQ-01c/loading/shadow-blur/README.md) and [grass-mask loading attempts](research/visual-quality-implementation/VQ-01c/loading/grass-masks/README.md) remain separate evidence. Current-package qualification, cold-load non-regression, loading budgets and production shutdown/soak remain open.

## Current delivery

DT-11a follow-up (2026-10-15): [fallback shadow pixel reuse](research/visual-quality-implementation/VQ-01c/loading/shadow-mask-cache/README.md) retains one 85.3 KiB CPU mip chain while keeping each image/texture independent. Repeated carrier construction measures 16.266→0.853 ms; the first call still generates the mask and complete Home/Fly loading remains unqualified.

DT-11a follow-up (2026-10-15): [batch population shadow transforms](research/visual-quality-implementation/VQ-01c/loading/population-shadow/README.md) preserves exact geometry and reduces repeated three-cell collection from 29.990 to 27.708 ms. Field regressions pass headless/native; a P-51 contract failure and Home shutdown warning in wider checks remain separately recorded. Full loading and lifecycle qualification stay open.

DT-11a follow-up (2026-10-15): [helicopter canopy intersection rejection](research/visual-quality-implementation/VQ-01c/loading/heli-canopy/README.md) preserves contour/kit geometry and reduces measured kit construction from 1.753 to 0.494 s. Headless lights/rotor/crash/Home-cache checks pass. The native night-light test reproduces two texture shutdown errors on reference and candidate; full loading and lifecycle qualification remain open.

DT-11a continuation (2026-10-15): [reuse canopy cuts across four profiles](research/visual-quality-implementation/VQ-01c/loading/heli-canopy/README.md#follow-up-reuse-cuts-for-four-profiles) reduces kit construction from 465.734 to 127.429 ms against the already optimized collector. Sixty real output pairs and 1,280 synthetic pairs agree exactly; six permanent contour checks are added. The existing native texture shutdown diagnostic remains open.

DT-11a continuation (2026-10-15): [native fixed-wing light transforms](research/visual-quality-implementation/VQ-01c/loading/night-kit/transforms/README.md) reduce measured geometry extraction by 15–49% across five families, with 300 exact native geometry/kit pairs. Full-kit median reductions are 1.755–18.277 ms on a shared host; loading qualification stays open. Corrected standalone night-kit initialization passes 30 checks headless/native without shader warnings.

DT-11a continuation (2026-10-15): [shared upper/lower wing cuts](research/visual-quality-implementation/VQ-01c/loading/night-kit/wing-slices/README.md) preserve complete kit output in 300 native fleet pairs and reduce kit construction by 25–33% in the paired campaign. Three permanent shared-data checks are added; field/night-kit/Home-cache regressions pass. Full loading, isolated timing and package qualification remain open.

DT-11a continuation (2026-10-15): [bounded fuselage light station scans](research/visual-quality-implementation/VQ-01c/loading/night-kit/belly-stations/README.md) preserve 300 native contour/kit pairs and reduce measured complete-kit construction by 15–23%. Four endpoint/range regressions are added; field and headless/native night-kit tests pass cleanly. Home cache assertions pass but four audio ObjectDB shutdown leaks reproduce with reference and candidate. Lifecycle, full loading and package qualification remain open.

DT-11a continuation (2026-10-15): [bounded wing light station scans](research/visual-quality-implementation/VQ-01c/loading/night-kit/wing-stations/README.md) preserve 300 native skin/kit pairs and reduce measured two-skin construction by 15–28%. Three permanent endpoint/order checks pass; native night-kit checks are clean. Extra's small complete-kit difference is mixed across processes and does not qualify a reliable gain. Home retains the four-object audio shutdown diagnostic. Full loading, lifecycle and isolated package qualification remain open.

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
| DT-10 | Measure startup, fullscreen and active simulation on frozen packages and named hardware; warm up 10 s and record 60 s per case. | Initial [VQ-01c Windows source observations](research/visual-quality-implementation/VQ-01c/README.md); pacing fails and two samples paused. [Home/Fly loading and DT-11a results](research/visual-quality-implementation/VQ-01c/loading/README.md) now exist; cold/first-Fly budgets, frozen packages/display and native acceptance remain open. |
| DT-10a | Define timing semantics, sample counts, quantiles, paired comparisons and uncertainty before optimization. | VQ-01c tools distinguish CPU callback samples, native active-flight eligibility and pacing. Observer cost remains unresolved above host variation; no performance acceptance. |
| DT-10b | Soak an M1-class 8 GB Mac at the declared 60 Hz profile; record 30 min of timing, memory, AC/battery state and sleep/occlusion recovery. | Planned — hardware evidence pending |
| DT-11a | Fix the largest measured startup/first-frame cost without hiding loading or starting flight early. | [Lake reuse/bake](research/visual-quality-implementation/VQ-01c/loading/README.md) and [exact grain precomputation](research/visual-quality-implementation/VQ-01c/loading/grain/README.md) implemented. Grain campaign Home median 10.747→8.809 s; first Fly mixed. Clean Windows export, full field-pack smoke and extracted ZIP headless flight pass. Cold/first-Fly budgets, leaks/soak and native qualification remain open. |
| DT-11b | Reduce measured idle/minimized cost while preserving focus and simulation timing. | Conditional on DT-10 |
| DT-11c | Add a graphics option only when paired performance and blinded readability evidence support it. | Conditional on DT-10 |
| DT-11d | Compare Compatibility and Mobile/Metal only if measurements show a renderer need; preserve the baseline absent evidence. | Conditional on DT-10b |
| DT-12 | Rehearse the downloaded release on clean accounts using promoted hashes, the frozen suite, soak and repeated launch/flight cycles. | Preliminary [50-cycle packaged diagnostic](research/visual-quality-implementation/VQ-01c/loading/audio/README.md): stable Home node count, observed audio released, no exit warnings; one paused first draw. Promoted release/clean accounts, uninterrupted interactive coverage and 30-minute soak remain open. |
| DT-13 | Record the owner's platform-by-platform delivery decision, defects, trust results and rollback path. | Open — delivery gate |

## Acceptance and evidence

DT-01 records separate tiers: exported/structurally checked, native CI launched, and owner accepted on named hardware. Apple Silicon ARM64 export, native execution and sustained acceptable flight are separate claims. Intel macOS is a separate claim if it is offered. A hosted runner label or Rosetta run is not native owner acceptance.

DT-10 budgets are proposals to freeze against DT-01 hardware, not current results: Home ≤3 s warm/≤5 s cold, Fly ≤2 s, process-loop interval p95 ≤18 ms/p99 ≤25 ms at 60 Hz, and simulation/wall ratio 0.99–1.01. The current logger does not measure presentation or input-to-photon latency. DT-10b needs evidence beyond its current 300 s capture limit. Performance work must preserve flight numerics and readability.

DT-12 includes final digest identity, clean-account launch and distribution checks, platform logs, a 30-minute soak and 50 Home/flight cycles. Evidence for each step stays under `docs/research/desktop-delivery-investigations/<DT-ID>/` and records commit, artifact hashes, OS/hardware, commands, results and limits. Never infer a native pass from an export or headless test.

The detailed sources and acceptance studies remain available: [native-test strategy](research/desktop-delivery-investigations/DT-00-R1/08-native-test-strategy.md), [fullscreen transactions](research/desktop-delivery-investigations/DT-00-R1/04-fullscreen-transactions.md), [release provenance](research/desktop-delivery-investigations/DT-00-R1/07-release-provenance.md), [Mac trust pipeline](research/desktop-delivery-investigations/DT-00-R1/02-macos-trust-pipeline.md), [Apple Silicon performance](research/desktop-delivery-investigations/DT-00-R2/07-apple-silicon-thermal-energy-soak.md), and [Mac diagnostics](research/desktop-delivery-investigations/DT-00-R2/12-macos-diagnostics-symbols.md). Signing tools, OS support floors and release channels are selected only from evidence in the relevant accepted steps.
