# DT-MAC-04n4: Apple Silicon source-default evidence

**Date:** 2026-11-13–14 UTC. **Status:** guarded native physics adopted as the source-editor default on the qualified M1. The technical Home/replay checks passed headless with Dummy and scenery audio disabled. Audio-enabled shutdown, physical presentation and public distribution remain unqualified. The [implementation plan](../../../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md) owns those remaining product gates.

The measurements below used the Apple M1 MacBookAir10,1 with macOS 27.0.1 build `26A434` and the official native ARM64 Godot `4.8.beta2.official.cafc17a19`, SHA-256 `2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80`. The task workspace is `/Users/gius/OpenRC-m1-work/macos-native-default-20261113T125500Z`; raw M1 evidence paths below are relative to it. The earlier B3 source snapshot was `ba95b2329a11dd7733b25dbcffd8db7bd0cfe04e`; the later B4 qualification below uses a separate source identity. Individual receipts bind their own collection inputs.

## B3 domain-guard trial

The B3 trial retains live packed Variants and compares them with detached byte snapshots. Its tested dylib SHA-256 is `3eb18f46b35f89ac0f6589701fd7073220fdd4d6073a43702f552353233f35c6`; its native-source SHA-256 is `b9f499fbdba33c5a2380262093d4dac07499546ac4f3a4b1a8e158fe378fdad1`. On the stock context, preparation recorded 6,092 scenery proxies, 154,131 visited nodes, 1,078 packed leaves and 76,816 packed bytes. The M1 trial reported 72 passing mutation controls, including the tested packed aliases and resize cases. These controls exercise the guard, not the complete application or every possible mutation.

Five quiet, alternating microbenchmark pairs measured the isolated guard. Values are per-pair mean microseconds; the retained summary is `evidence/guard-ab03/summary.json` in the task workspace.

| Pair | Baseline µs | B3 µs |
| --- | ---: | ---: |
| 1 | 89.5733 | 19.205 |
| 2 | 89.7142 | 19.25333 |
| 3 | 89.83375 | 19.14417 |
| 4 | 90.42542 | 19.31125 |
| 5 | 89.59417 | 19.275 |

These numbers describe isolated guard cost on this host and context. They do not establish complete-session speedup, frame pacing, sustained performance or qualification of B3. An earlier B1 candidate passed its 17 numerical oracles, negative FPCR control, focused consumers and sanitizer checks; B1 is superseded, so those results are not B3 qualification. The [earlier implementation assessment](../DT-MAC-04n1/README.md) retains separate source10 and diagnostic-host limitations.

## B4 retained qualification

The full prepared application for B4 uses source commit `2f9ef1620cc35960be430ad445e13edac82ea69e`, after publication and companion metadata renewal. The installed ARM64 dylib SHA-256 is `45ca43bd48707990483a9b30203cec775867443a37406b7af591696312f4744b`; native-source SHA-256 remains `b9f499fbdba33c5a2380262093d4dac07499546ac4f3a4b1a8e158fe378fdad1`, and solver SHA-256 is `5e5b3c80f7e33d9a106b9c193bdf46b55f024e8136d69ee9e6d2b8ba076e6500`.

All 17 positive numerical oracles passed on the M1, with **1,323,114 of 1,323,114 comparisons identical**. The deliberately mutated evaluator produced 28,350 mismatches among 128,664 comparisons, and the FPCR control detected and restored its change. After installation, the actual stage, lifecycle and replay qualification hosts passed their native-success markers with `preloaded=false`. The oracle summary and drivers are in `evidence/candidate04-family-summary.json` and `evidence/candidate04-*-driver.log`; FPCR evidence is in `source/tmp/macos-default/fpcr-04/`. The locally retained build archive `tmp/macos-default/candidate04-build-retained.tar.gz` has SHA-256 `6f3b98e5d95f3ce58b241a2ebcf5730903f3d6a589da72c624f72547123838f7`.

UBSan and ASan each detected their deliberate positive control and passed the instrumented candidate's 72 real domain-guard checks. All five packed-alias resize controls observed an actual mutation, and the direct resize control changed the live array to 1,024 elements. These runs used a separately re-signed, non-hardened diagnostic Godot clone; the official host remained unchanged. Godot and the prebuilt bindings were not instrumented. The local summaries are `tmp/macos-default/diagnostic04-ubsan-domain-summary.json` and `tmp/macos-default/diagnostic04-asan-domain-summary.json`; sanitizer timing is not performance evidence.

The [November 13 publication receipt](../../release-readiness/PT1-CI-00/publication-rebind-2026-11-13.json) binds the 19-source-pin requalification and exact Windows/Linux captures to candidate `05e01598d2261cea86af3e2ec6024c88ed7530d1`, before the later companion rebind. It is not a whole-application capture of `2f9ef162...`; B4's prepared-app qualification above is the later, separately bound result.

### B4 headless callback screen

Each production-trim case completed five comparable reference/native pairs with throttle `0.5`, 2,400 warmup ticks and 14,400 sampled ticks at 240 Hz. The native measurements included the actual domain guard and the runs retained fingerprints and backend coverage. The probe uses explicit experimental native selection; it does not establish automatic marker admission. These are detached, headless measurements, with 10 and 60 seconds of simulated time per role rather than wall-clock flight durations.

| Aircraft and case | Median of five reference run means (µs/tick) | Median of five native run means (µs/tick) | Reduction of medians |
| --- | ---: | ---: | ---: |
| Jensen Ugly Stik, trim | 530.154 | 336.800 | 36.47% |
| Stik Electric 6S, finite pack, trim | 823.803 | 398.893 | 51.58% |
| Stik Glow 61FX, trim | 1,530.921 | 803.719 | 47.50% |

The stopwatch records elapsed time in the measured callbacks, not process CPU time. Fingerprinting, backend verification, additional guard checks and native-counter checks outside the stopwatch can perturb subsequent ticks. Reductions are ratios of the two role medians, not pooled tick statistics or an end-to-end workload saving. Four Jensen controls also completed three comparable pairs each: reference and native A/A, and observer-on/off for each backend. The local raw reductions and reports are `tmp/macos-default/cpu04/metrics.json`, `jensen.json`, `electric-pack.json`, `glow.json` and `control-*.json`. These results do not establish FPS, energy, live pacing, sustained behavior or product acceptance.

### B4 sustained technical circuit

All three alternating long pairs completed 30 measured wall minutes per role after 30 seconds of warmup, without competing tests on the M1. Each pair matched 71 complete 6,000-tick state/input windows and retained native coverage. The declared software pacing gates passed in all six runs: p95 at most 18 ms, p99 at most 25 ms and simulation/wall ratio within 0.99–1.01. The whole-run observed simulation/wall ratios were 0.99999845–1.00000136. These are uncapped Mobile/Metal technical circuits with the existing cloud-shadow-map option enabled for both roles, not owner pilot or physical presentation acceptance.

| Pair | Reference p95 / p99 (ms) | Native p95 / p99 (ms) | Reference process CPU (% of one core) | Native process CPU (% of one core) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 15.655 / 16.893 | 14.792 / 16.089 | 58.437 | 59.578 |
| 2 | 14.936 / 16.224 | 14.693 / 16.012 | 59.313 | 59.706 |
| 3 | 14.893 / 16.177 | 14.500 / 15.855 | 59.515 | 59.899 |

The medians of the three run p95s were 14.936 ms reference and 14.693 ms native, an observed 1.63% reduction. The medians of process CPU observations were 59.313% and 59.706% of one core: **no whole-process CPU saving was observed**. Process CPU includes all Godot threads and benchmark observation, unlike the callback stopwatch above. There is no whole-session observer-off control or confidence interval for this comparison. The worst recorded frame interval was 31.114 ms reference and 33.872 ms native; the smaller p95 does not imply every tail improved.

First/final-five-minute native p95s were 14.818/14.736, 14.561/14.617 and 14.263/14.429 ms. Those are disjoint wall-time windows, not independently tick-matched subcampaigns. Interior resource polls covered more than 99.45% of each requested five-minute window; omitted edges and clock uncertainty are retained. All six host attachments bracketed their selected intervals, recorded AC and Low Power off, and reported thermal `fair` without observed transitions. Memory pressure starts unknown and had no observed events; event coalescing/loss is unknown. These observations do not prove absence of thermal throttling or measure energy.

Sampled measured-window RSS peaks were 1,049.8–1,071.6 MiB reference and 1,066.1–1,202.7 MiB native. RSS fell during each run, with substantial run-to-run variation; it is not physical footprint, allocation rate or a leak test. No RAM-saving claim follows. GPU causality, bandwidth, watts/joules, battery benefit and physical 1080p presentation remain unmeasured.

The offline frame and long-resource reductions are `tmp/macos-default/frames04-metrics.json` and `resources04-long-metrics.json`. The reader's optional five-minute windows passed 17 focused tests; full default reductions of both historical examples remained byte-identical. The original 16 captures and their complete checked/resource/host hierarchy are retained in `tmp/macos-default/live04-raw-20261113T235200Z.tar.gz`, SHA-256 `86816ea9b9ead1154a9bf461f84dc9209ba0597fe8df816a9b1bf836eb9fac6b` (35,364,805 compressed bytes; 217,524,579 uncompressed bytes; 260 entries).

One original short reference resource capture (`live04-short-03`, capture `75c22120-d7d1-429b-82f5-8c17a25bd739`) stopped after 120 samples with `identity_status=reused`, `stop_reason=pid_reused` and partial coverage. Its frame comparison passed, but its process resources are unusable. The original receipt remains unchanged and excluded from resource comparisons. The replacement complete pair `live04-short-03r1` passed its frame comparison and both checked resource reductions. The selected five short and three long pairs therefore have 16 usable resource attachments. The selected archive is `tmp/macos-default/live04-selected-20261114.tar.gz`, SHA-256 `1fb99ef997676760e09498fe3fb33fe3cd4ff2f645b29801b9e8ba2faa141d20`. No identity check, physics, tape or tolerance was weakened.

### B4 adoption stopped; reader corrected

The private final adoption gate stopped before publishing a canonical marker. Its missing-receipt case selected reference but emitted a Godot JSON parse error. The reader now checks existence and a bounded byte count, validates UTF-8 before decoding, parses quietly and hashes the same bytes it parsed. Commit `a462cec93bc3d85702e19457655c8165f71f8b8f` passed 78 actual M1 admission-reader controls with zero failures or engine errors. No numerical behavior, golden flight or tolerance changed.

The admission file belongs to both the native mirrored-source roster and the solver fingerprint. B4 evidence remains bound to its original source; it is not relabeled as qualification of this correction. B5 therefore renewed companion tape parity, the native build/oracles, early installation fallbacks, fleet/live evidence and current-source CI. The canonical marker was still absent at the B4 stop.

## B5 corrected-source qualification

B5 freezes source `9386f5e532045ed618c992d2b9504e7206ccdf60`, native binary SHA-256 `b7852b6d9b8abfdd0edafb2ffd390e9d97e2666bc8cedb7b5ae8dca2451b2c25` and solver SHA-256 `880c90f727debd139689b6285563dcd85454953baf56fd22d8a941ba2ca6123b`. Both candidate and mutant were freshly built. All 17 positive oracles again passed **1,323,114 identical comparisons**; the numerical mutant produced the expected 28,350 mismatches, and the FPCR control passed. Installed stage, lifecycle, replay and domain-guard consumers passed. Receipts are `evidence/source-ready05.json`, `candidate05-complete.json` and `candidate05-family-summary.json`.

The early private, receipt-salted fixture passed all nine actual installation fallback cases, including missing/corrupt receipt, missing/tampered dylib, stale source and wrong slice. Its actual Main native recording and ordinary exact replay also passed. `evidence/early05-complete.json` explicitly marks this fixture-only evidence: its historical Jensen selection inputs do not qualify B5 fleet rows or activate the canonical app.

UBSan passed its positive control and candidate checks. The first ASan attempt detected its deliberate positive control, but Apple Clang then aborted with SIGABRT while compiling the candidate diagnostic; the empty compile log and two Clang crash reports are retained. ASan candidate tests did not run in that attempt, and no B5 performance campaign had started. Available disk was about 425 MiB afterward; the precise compiler root cause is unproven. The full B5 build was retained and every archived file checked before retiring cold compiler work. The required mutant workspace was restored and verified; only the candidate and mutant SCons Python environments remain retired. Headers, objects, static bindings, compile databases, both binaries, receipts and raw results remain. The failed attempt is not a sanitizer pass; the fresh retry below supplies that result.

The restored mutant workspace passed the original full installation verifier. The separately owned continuation retains the original two-step progress and failed ASan evidence by hash, revalidates UBSan's underlying artifacts, and uses a new ASan output directory. The fresh ASan attempt passed its positive control, numerical checks and domain-guard controls; performance collection then began. Neither receipt nor verifier was relaxed, and the official engine remained unchanged.

B5's fresh fleet completed all 11 shards and 1,428 fixed-wing rows in about 6,584 seconds. It again verified **1,382 guarded flights**, with 46 open rows and an aggregate **fail**. Exact row-key comparison found no loss of previously verified rows or new flight failures; the same 12 setup refusals remain outside admission. The historical campaign is used only for that regression comparison; every proposed B5 row has fresh B5 evidence. The result is `source/tmp/macos-default/fleet05/campaign.json`.

### B5 callback screen

All three production-trim cases completed five comparable alternating pairs at throttle `0.5`, with 2,400 warmup and 14,400 sampled ticks per role. The original seven campaign directories were retained and the existing reducers revalidated all 54 raw reports and logs, including the four three-pair A/A/observer controls. Every raw declares Apple M1, arm64 and eight logical CPUs; these characteristics do not uniquely identify a physical Mac.

| Case | Median reference run mean (µs/tick) | Median native run mean (µs/tick) | Reduction of medians |
| --- | ---: | ---: | ---: |
| Jensen, ideal supply | 527.182 | 337.168 | 36.04% |
| Electric 6S, finite pack | 824.019 | 400.062 | 51.45% |
| Glow 61FX | 1,531.932 | 806.474 | 47.36% |

The stopwatch measures callback elapsed time, including the actual native domain guard; it is not process CPU or FPS. The paired reduction ranges were 35.94–36.46%, 51.29–51.76% and 47.30–47.62%, respectively. Maximum A/A ratio deviations were 0.724% reference and 0.745% native. The observer control uses a different stopwatch: sample-loop wall time per tick. Its median observer-on/off deltas were +0.090 µs reference and +0.307 µs native, with ranges crossing zero; these controls do not quantify whole-session observer cost.

The complete archive is `tmp/macos-default/cpu05-retained.tar.gz`, SHA-256 `1d15fb75bc21de1d131c5c52a1065e1512b9a700fe6b4f88682caf291eeb3ea7` (115 files, 1,484,800 compressed bytes). The verified reduction is `tmp/macos-default/cpu05-metrics.json`, SHA-256 `babe584c2912911b19cccb08dc1a574db0b6f357f1e482c739d19a9caadf59a7`. This source screen does not establish Gate P's batch-tail statistic, physical display acceptance, energy or complete-product performance.

### B5 live collection and resource failures

The first four short live pairs passed both frame comparison and strict resource validation. In short pair 05, both checked engine runs exited successfully, but the native attachment (`6a9dba54-9182-46cb-a7cf-6b2f7c473dd1`) ended with `identity_status=process_exited`, partial coverage and `NoSuchProcess` errors for RSS/CPU in its final sample. The campaign stopped before comparing that pair or starting the long trials. The original `evidence/live05-short-05/` remains unchanged and excluded. The complete replacement `live05-short-05r1` passed comparison and both resource validations, giving five selected short pairs. No identity or coverage requirement was relaxed.

Long pair 01 completed 30 measured minutes per role, passed comparison and both resource validations, and remains valid evidence of its collector. In long pair 02, both engine runs completed successfully, but the reference sampler reported `pid_reused` after 725 samples, ending around second 734 of a 1,854-second process. Its partial attachment cannot establish full-run resources, and both roles of that pair remain excluded. No actual replacement-process identity or second creation-time value was retained, so the historical cause is unproven.

The [pinned psutil implementation](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/__init__.py) uses a clock-stable macOS identity for its original process object's liveness check; the [macOS backend](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/_psosx.py) separately adjusts the public epoch creation time for wall-clock changes. The sampler compares fresh public epoch values, which is an unsuitable stable-identity test. A separate, source-hashed collector uses original-object identity and owned-child checks before and after each poll. Its nine focused controls and actual owned-Python-child/host-helper smoke passed on this M1. Its derivation manifest SHA-256 is `888aae1072f75a3c2009deaa60e5b445c193736c7bfd0db78e2b9649387ac9f3`; the smoke receipt is `evidence/collector05r3-smoke/summary.json`. The canonical application, native binary, Git snapshot, oracle/fleet receipts and old raw captures remain unchanged. This measurement apparatus is not covered by the application's earlier CI. Its live pilot and replacement long pairs have separate receipts; no failed attachment is retroactively accepted or pooled across collector methods.

The new collector's 30-second-warmup/120-second live pilot passed both backends, frame comparison and strict resource validation. Its process CPU observations were 61.479% reference and 61.712% native of one core. The runner's whole-process observations were 0.125%/0.132% and the host helper's 0.0163%/0.0170%, respectively, across their wider intervals including warmup. Mean poll durations were 230.9/238.5 µs of wall time. These are separate measurements, not an observer-off estimate or proof of equal observer cost. The pilot is additional evidence, not one of the five selected short pairs; `evidence/collector05r3-pilot-comparison.json` retains its comparison with each original short pair without pooling CPU.

[CI run 43538072599](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43538072599) completed successfully for the exact B5 commit: 22 successful jobs and four conditional skips, with no failed or pending jobs. It includes native macOS ARM64, Linux and Windows, all eight unit partitions, integration, visual captures and exports. The completed live evidence follows below; export success does not qualify public signed distribution.

### B5 completed sustained circuit

The selected campaign completed five short pairs and three alternating long pairs. Each long role measured 1,800 wall seconds after 30 seconds of warmup, using normal 240 Hz automatic simulation and the same uncapped Mobile/Metal technical circuit. All eight pair comparisons and all 16 original checked resource attachments passed both on the M1 and in the independent retained-data reduction. Each long pair matched 71 complete 6,000-tick state/input hash windows. The declared software gates passed: p95 at most 18 ms, p99 at most 25 ms and simulation/wall within 0.99–1.01. Actual long simulation/wall ratios were 0.99999968–1.00000089.

| Pair | Collector | Reference p95 / p99 (ms) | Native p95 / p99 (ms) | Reference process CPU (% of one core) | Native process CPU (% of one core) |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Original | 13.730 / 15.174 | 13.979 / 15.401 | 62.042 | 61.210 |
| 2 replacement | r3 | 13.814 / 15.279 | 13.089 / 14.418 | 61.930 | 62.067 |
| 3 | r3 | 13.992 / 15.474 | 13.845 / 15.236 | 61.283 | 61.361 |

These are separate paired observations. Collector cohorts are not pooled, and there is no observer-off whole-session control or confidence interval. The r3 pairs show no whole-process CPU saving; the first pair's lower native CPU is not a general benefit. Frame tails did not improve uniformly. The worst selected long intervals were 23.711 ms reference and 21.191 ms native. These runs establish bounded technical pacing, not a stable FPS improvement or complete-product acceptance.

Descriptive native first/final-five-minute p95s were 13.912/14.019, 13.051/13.257 and 13.880/13.821 ms. All six resource attachments provided valid disjoint edge windows, with interior polls covering at least 99.424% of each requested five-minute interval; omitted edges and clock margins remain in the reductions. Host attachments bracketed their intervals, recorded AC and Low Power off, and observed thermal `fair` or `nominal`. Initially unknown pressure and unknown event loss remain explicit. These channels do not prove absence of throttling or measure energy.

Sampled long-window RSS peaks were 1,084.7–1,142.3 MiB reference and 1,197.8–1,274.9 MiB native. This is sampled RSS, not physical footprint or an allocation/leak test; no RAM-saving claim follows. Physical 1080p presentation, GPU causality, bandwidth, watts/joules and battery benefit remain unqualified.

The complete live transfer is `tmp/macos-default/live05r4-transfer.tar.gz`, SHA-256 `19faefde8f2774c10e94b869b0b2d9e175c83b10ff6837a2cfaa40987a463180`; its manifest SHA-256 is `b54eb34b79a8720dd652ebc3892d07db7d2fa7e0d11ba9f9ed7a7423abb00678`. All 495 files passed source and extraction validation, preserving 16 selected roles, four rejected roles and two additional pilot roles. The r4 retainer corrects an initial false rejection of labeled diagnostic directories; diagnostic reports and capture bytes were unchanged. The existing frame/resource readers reproduced the original accepted results. Their offline analysis is `tmp/macos-default/live05r4-analysis/analysis.json`, SHA-256 `6cde6382747daf5207d0ba270ebb24b44a48a15bc7b20e268ed413e72f5bc67d`. Compiler objects, diagnostic dylibs and external tool binaries are outside this live transfer; separate build retention and original M1 evidence remain authoritative for those artifacts.

### B5 Home and shutdown scope

The first final adoption attempt passed all nine installation fallbacks, normal native/reference controls, Main/native recording and ordinary exact replay. Its headless Home/Fly/restart/F5/Home/re-entry check observed native progression in all four flights, but failed its zero-leak shutdown assertion. The canonical marker was not published in that attempt. A separate verbose bridge-quit reproduction identified four retained audio objects: `AudioStreamMP3`, `AudioStreamWAV`, `AudioStreamPlaybackMP3` and `AudioStreamPlaybackWAV`. Calling the actual product `AppRoot.quit_app()` and waiting for the directly owned process still reported four retained objects, despite exit code zero and no crash; that nonverbose native run did not identify their classes. These failed results remain failures; ordinary audio-enabled shutdown is not qualified.

The separate existing-setting control used `OPENRC_SCENERY_AUDIO=off`, headless Godot and the Dummy audio driver, with no application arguments or backend override. The same four native transitions passed, and the product quit completed with exit zero, zero leaked objects and no crash. The exact control is `home05-audio-off-control.py`, SHA-256 `660dd9cb93b3c850b8b5f7f56501dd2a9d8923e00d0acf95ff1f12a572adcf26`; its original receipt is `evidence/home05-audio-off-control-prepublication/summary.json`. This closes only the declared technical Home/native check. It does not repair audio-enabled shutdown, establish audible or display acceptance, change the source, or disable the user's normal audio settings.

An initial attempted reference control supplied a backend CLI argument and correctly failed its initial Home assertion because any application argument selects the direct route. It is not same-route reference evidence. The subsequent no-argument missing-marker clone completed all four reference-fallback transitions with audio enabled and the same product-quit path. Its verbose exit report identified the same four classes, with exit zero and four retained objects. The source inventories differed only by the missing marker; the clone shared the promoted project's research profile name. This reproduces the issue with both evaluator backends in this headless configuration; it proves neither that the issue preceded B5 nor that the extension was never loaded.

### B5 adopted source route and final consumers

At **2026-11-14 10:11:51 UTC**, the reviewed continuation revalidated the original 14 checked installation/import/Main/replay results, all 16 selected resource attachments and the complete promotion corpus. It then published complete fsynced marker bytes by an exclusive hard link. No existing marker or failed receipt was overwritten. The first actual adoption receipt is `evidence/adopted05r2.json` (the retained filename does not make the failed r2 campaign complete), SHA-256 `0b770bd6936540cd714a7abf214110af425c4f9e14dfcf6b08dfac3573b1be9e`. It names the actual r4 adopter and its owner, preserves the prior failures, and explicitly limits the Home gate to headless/Dummy with `OPENRC_SCENERY_AUDIO=off`.

The canonical marker is `source/app/native/kernel/default-admission-macos.json`, SHA-256 `1dfdec16f93089d29c423c87772299075b17548baa2bca193040639452e5132d`. It admits only the 1,382 freshly verified guarded stock selections for the recorded M1/OS/engine/source tuple. Unsupported or changed selections retain reference during preparation; admitted flights keep their backend identity. No normal user audio setting was changed. This is source-editor physics adoption, not a public package or general Apple hardware qualification.

All three post-adoption consumers passed:

- The **actual canonical** `source/app` exercised Main's automatic native route without backend/experimental overrides, recorded five tick states and passed ordinary backend-pinned exact replay. `source/tmp/macos-default/canonical-default05/summary.json` has SHA-256 `da9ea72c879dfa61dbcf57041db9ae169cd44410e401942be372cbd1b7611ee0`.
- The verified prepared source project repeated Home/Fly/restart/F5/Home/re-entry with native progress in all four flights, exit zero, zero errors and zero leaked objects in the declared audio-off technical configuration. This is prepared-project Home evidence, not canonical-profile Home acceptance.
- A real automatic prepared-source Jensen flight recorded **2,590 ticks between its markers** over 10.796 wall seconds, including a small control pulse. The full 2,620-row tape passed native exact replay and a complete, marked reference candidate replay (`solver_changed=true`). The two exported CSVs were byte-identical for their recorded columns. This is not cross-solver bitwise equivalence of every internal state or physical validation. The real user-profile inventory remained unchanged at all checkpoints. `source/tmp/macos-default/source-flight-replay05/summary.json` has SHA-256 `78882539c60ca567e641e3a892a92b879a9ccfdc7a57e61ebed471c83edb43d4`.

The immutable `evidence/technical-{canonical,home,source-flight}05r4-{request,completion}.json` pairs bind each actual helper, command, child environment, source/adoption/marker/CI identities, logs and result hashes. All three declare the headless/Dummy scenery-audio-off scope; they do not qualify normal audio-enabled shutdown.

The independently verified post-adoption transfer is `tmp/macos-default/postadoption05r4-transfer.tar.gz`, SHA-256 `1d5511f8d52fe2a7d691f0502a84018410a651f62d1863629640a67b9ca6dc5e`; manifest SHA-256 `b0b7dd82489e774fd422cf614a0ab2d3eea2ff336cc308ce1c297d0443fb9ec1`. All **506 files** passed extraction and semantic validation, including installed native artifacts, invocation receipts, original failed controls, 16 resource rechecks, canonical replay and full flight/candidate evidence. Private profiles, project clones, build trees and caches were excluded; original M1 evidence remains intact.

Final teardown at 10:26 UTC verified the unchanged adopted marker and all three successful consumer receipts, found no task-owned Godot process, and stopped only the exact recorded keep-awake process identity. No persistent power setting changed. `evidence/finish05r4.json` and its local retained copy record that closure.

## Companion route

The [solver rebind receipt](../../ai-companions/AFC-02/rebinds/2026-11-13-192efadc-to-f60ac8ed.json) records identical CSV bytes for nine retained reference tapes using solver SHA-256 `f60ac8ed1339556c996e395a6167da3e502d56376310c44c7b3a13f56e8f2867`. This is bounded tape parity, not exact replay or physical validation.

The [behavior receipt](../../ai-companions/AFC-02/rebinds/2026-11-13-main-macos-route-behavior.json) records 16 completed checked import, stale-input, companion and Home tests. Its observed companion-enabled flight retained the reference backend, with three active, airborne companions and no reported companion faults or crashes. The observed player tick advanced from 47 to 60 without a flight fault; the owned debug session stopped gracefully with zero reported leaked objects. This is a short admission observation, not sustained flight or evidence of native companion acceleration.

The [final solver rebind](../../ai-companions/AFC-02/rebinds/2026-11-13-f60ac8ed-to-5e5b3c80.json) renews the profile from `f60ac8ed...` to B4's `5e5b3c80...`. All nine retained tapes produced identical CSV bytes, with 2,881 rows each, against the complete accepted application and current source. The companion-enabled automatic Mac route retains reference; this renewal does not qualify native companion acceleration.

The [B5 solver rebind](../../ai-companions/AFC-02/rebinds/2026-11-13-5e5b3c80-to-880c90f7.json) renews the profile after the quiet admission-reader correction. All nine tapes again produced identical CSV bytes, with 2,881 rows each, against the accepted application. These are bounded candidate-parity checks; companion-enabled automatic sessions retain reference.

## Pending

- B5 freshly verified 1,382 guarded stock fixed-wing rows; 46 remain open and the overall fleet verdict is **fail**. The manifest separately declares 14 non-applicable rotorcraft rows. Only the freshly verified, guarded rows may enter its marker.
- The open set contains 30 host-specific boundaries, four MoonRunner rows lacking current requalification, and 12 reset/setup refusals. Eight electric runway selections could not resolve their idle support pose; four MoonRunner ideal/hot-high trim or hand-launch selections could not trim at the requested throttle. Reference was not run for those 12 rows, so their failure sentinels prove neither numeric divergence nor matching reference refusal. No expectations or physics were changed to pass them.
- B5's guarded source-editor default, five selected short pairs, three long pairs, independent resource reductions and scoped canonical/Home/replay consumers are complete. Audio-enabled shutdown remains open with four retained audio objects in both evaluated backends' headless controls.
- Requested/window/render-target dimensions do not establish physical 1080p presentation. Broader Apple hardware, GPU causality, bandwidth, energy benefits and the complete-product Gate P statistic remain unqualified.
- Final signed package, distribution, quarantine, compatibility and recovery qualification. Source-editor evidence does not qualify a distributed package.
