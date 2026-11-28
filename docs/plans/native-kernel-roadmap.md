# Native kernel and optimization roadmap

Owner goal (2026-11-27/28): run the game's hot paths in the native kernel, robustly and as efficiently as possible,
batch by batch with measured returns, and keep optimizing whatever then costs most. This plan records what is native,
what each batch measured, where the time is after v0.4.0, and the remaining work ranked by return against effort.

Owner and scope:
- Prefix `NK`. Paths: `research/native-kernel/src/`, `app/sim/native_stage.gd`, the published-endpoint answers in
  `app/sim/flight_session.gd`, their consumers, and `docs/research/native-kernel/`.
- Rows from other tracks (F0–F6, VQ, DT-MAC, UI, AFC) keep their owners, IDs and acceptance gates. This plan ranks
  them against native work only.
- The [native kernel README](../../research/native-kernel/README.md) owns coverage, contracts and admission.
- Each batch's evidence README owns its figures.
- [Optimization priorities](optimization-priorities.md#frame-stalls-and-sustained-fps) owns the frame-cost
  attributions (F0–F6).
- [STACK](../STACK.md#native-backend-policy) owns the backend policy.

## Ground rules

- The GDScript reference remains the specification, the fallback and the replay backend
  ([decision](../DECISIONS.md#native-acceleration-keeps-the-reference-as-its-specification)).
- Each native answer has a hook that turns it off. A parity test compares the whole consumer output with the hook on,
  off and full-reference.
- `Simulation` keeps the commit, publication, checkpoint and rollback transaction
  ([AGENTS](../../AGENTS.md#native-development)).
- UI, menus, orchestration and the simulation transaction stay in GDScript by design. "Everything native" means every
  hot path whose measured return justifies it, not every line.

## Where the time is after v0.4.0

**Which hosts are CPU-limited.** The Windows workstation is CPU-limited in flight. ANGEL (M1) and PRIMIS (Intel UHD
630) are GPU-limited ([direct phase timing](../research/god-test/2026-11-24-flight-tick-cost.md#direct-phase-timing)).
- So CPU savings raise mean FPS only on CPU-limited hosts. Mean FPS on the M1 and the UHD 630 needs GPU work.
- CPU savings still shorten catch-up after a slow frame everywhere.
  - On 24 November, with a tick costing *c* = 1.0–1.9 ms, a delay of *d* ms grew to *d*/(1 − 0.24·*c*) through the
    extra ticks it caused: 1.3–1.45× on Windows, 1.45–1.85× on PRIMIS
    ([slow frames](../research/god-test/2026-11-24-flight-tick-cost.md#what-a-slow-frame-contains)).
  - Cheaper ticks shrink that factor: about 1.1× at *c* = 0.3 ms. That is arithmetic, not a measurement.

**Per tick (240 Hz).**
- 24 November, before NK-6: 1.01–1.28 ms per tick live on Windows, by the head-difference method.
- 27 November: live airborne Corsair ticks of 280–380 µs on the production field, observers 125–180 µs of them
  ([F1](optimization-priorities.md#frame-stalls-and-sustained-fps), per-observer timers).
- After NK-6u: live 1080p Corsair `Simulation.step` 250–255 µs, against 455–462 µs before NK-6a.
- Headless `Simulation.step`: 116 µs on the Corsair and P-51. The Corsair's tick was 150 µs with the production field's
  cost observations (NK-6u, NK-6v).
- The methods differ, so this plan claims no end-to-end ratio. Ranked item 1 measures one.

**Per frame (Windows).**
- 27 November, the F1 cell: `main.gd` 390–530 µs (`_render_pose` 132, `World.update` about 25 after the cloud fix,
  smoke 45, lens 23).
- Live, 28 November, the F5b cell, before NK-7j–7m: `_render_pose` 120–170 µs and `FlightAudio._process` 280–400 µs.
- Headless `_process`: 215–227 µs after NK-7f, and 172–224 µs on the ground after NK-7j.
- 25 November, jet, Compatibility, about 106 FPS: viewport render CPU 2.1 ms, GPU 1.4 ms
  ([per-frame scripts](../research/god-test/2026-11-24-flight-tick-cost.md#per-frame-script-cost-on-windows)).

**Stalls.**
- **Windows:** frames above 9 ms (931–2,118 per circuit) carry 3.5–4.2 ms of excess from the previous iteration's tail
  and non-tick time. Frames above 16.7 ms (4–44 per circuit) carry 9.6–10.1 ms. The GPU stays near 1.6 ms, which leaves
  presentation, driver work, deferred calls and OS scheduling.
- **PRIMIS:** isolated 45–88 ms stalls.
- **M1:** a disturbance every 500.00 ms with a per-cycle maximum excess of 12.6–13.9 ms.

**Inference from these figures, not a measurement.** The GDScript left on a Windows frame (27–28 November) is below
the render CPU of the 25 November Compatibility jet. Further native batches return tens of microseconds each, while
stalls, hull-contact ticks and GPU passes return milliseconds. The ranking below follows from that.

## What is native: measured returns

Figures are quoted on 2026-11-28 from each batch's README, which owns them and wins if they differ.

Unless a row says otherwise:
- conditions are Windows 11 x86_64, native backend, headless;
- units are µs;
- "live" means the 1080p app.

### Kernel and platforms

| Batch | Moved native | Measured |
| --- | --- | --- |
| [NK-3](../research/native-kernel/NK-3/README.md) | Linux x86_64 stage evaluator: aero, wheels, propeller, hull, joint stages, weather, helicopter | Linux i5-10500: median paired tick-cost ratio 2.11× over 30 pairs. Session runway idle 2,247.7 → 766.2 |
| [NK-4](../research/native-kernel/NK-4/README.md) | Windows build (MinGW-w64) | Debug editor, shared host: runway 2,064 → 766, trim 998 → 426, manoeuvre 878 → 311 |

### Simulation tick

| Batch | Moved native | Measured |
| --- | --- | --- |
| [NK-5a](../research/native-kernel/NK-5a/README.md) | Wing wake in the session pre-step | Corsair tick core 728 → 665 |
| [NK-5b](../research/native-kernel/NK-5b/README.md) | Liquid stage's source-off shaft rate for the substep preview | `substeps_joint` 78 → 14–25 |
| [NK-5c](../research/native-kernel/NK-5c/README.md) | Configuration guard fast paths | 47–75 → 37–59 (within the host's noise) |
| [NK-5g](../research/native-kernel/NK-5g/README.md) | Whole session pre-step | `_pre_step` 62–232 → 4–12. Whole tick −23 to −82 in flight, −107 to −204 rolling |
| [NK-5h](../research/native-kernel/NK-5h/README.md) | Guard plans: one engine comparison per root | `configuration_matches` ≈ 51–78 (estimated) → 26–39 |
| [NK-6a](../research/native-kernel/NK-6a/README.md) | Legacy joint tick: RK4, substeps, event locator | Live `Simulation.step` 303–462 → 204–356 (−23 to −33%) |
| [NK-6b](../research/native-kernel/NK-6b/README.md) | Glow step policy's firing fraction | Glow tick 911–1,081 → 584–628 |
| [NK-6c](../research/native-kernel/NK-6c/README.md) | Finite-pack electric policy | Pack tick 282–424 → 163–222 |
| [NK-6d](../research/native-kernel/NK-6d/README.md) | Glow resource step | Glow tick 541–615 → 393–486 |
| [NK-6e](../research/native-kernel/NK-6e/README.md) | Glow store checks; exact propeller-strike and probe reach bounds | Whole tick: glow −80 to −111, others −11 to −51 |
| [NK-6n](../research/native-kernel/NK-6n/README.md) | Steady glow tick accepted without `GlowFlight.finish` | Glow airborne tick 316–337 → 264–283 |
| [NK-6p](../research/native-kernel/NK-6p/README.md) | Frozen configuration; roots proved by identity | Guard plan 16–42 → 6–8 |
| [NK-6q](../research/native-kernel/NK-6q/README.md) | `Simulation.step` and session state checks | −4 to −7 in the mean (noise level) |
| [NK-6t](../research/native-kernel/NK-6t/README.md) | Liquid validity from the prepared stage; lazy contact sampler | Corsair and P-51 140–142 → 133–137. Glow within noise |
| [NK-6u](../research/native-kernel/NK-6u/README.md) | RK4 substep count inside the integrator | Corsair and P-51 135 → 116. Live Corsair 273–274 → 250–255 |

### Ground contact and hull

| Batch | Moved native | Measured |
| --- | --- | --- |
| [NK-5d](../research/native-kernel/NK-5d/README.md) | Proof that no scenery or lake contact is reachable | Contact resolution 69–146 → 14–75 |
| [NK-5e](../research/native-kernel/NK-5e/README.md) | Accepted-endpoint wheel compressions | Observer 32–68 → 4–7 in flight, 101–124 → 60–71 rolling |
| [NK-6f](../research/native-kernel/NK-6f/README.md) | Hull-scrape contact rows | Corsair touching 502 → 154 per observation |
| [NK-6g](../research/native-kernel/NK-6g/README.md) | Lake bank reach; guard reads published compressions | Runway whole tick −51 to −66 |
| [NK-6h](../research/native-kernel/NK-6h/README.md), [NK-6i](../research/native-kernel/NK-6i/README.md) | Quiet hull terminal for liquid and glow aircraft | Runway −76 to −83 (liquid), about −100 (glow). Airborne none |
| [NK-6j](../research/native-kernel/NK-6j/README.md) | Pre-tick guard's gear collapse | Corsair airborne −33 |
| [NK-6k](../research/native-kernel/NK-6k/README.md) | Propeller clear of ground and lake | `_check_prop_strike` 16–17 → 2–3. Runway −15 to −25 |
| [NK-6l](../research/native-kernel/NK-6l/README.md) | Session guard's empty hull contacts | Runway −16 to −26 |
| [NK-6v](../research/native-kernel/NK-6v/README.md) | Clear contact step in one call | −11 to −33 per airborne fuel tick; rolling breaks even. Live Corsair 268–269 → 254–260 |

### Statistics

| Batch | Moved native | Measured |
| --- | --- | --- |
| [NK-5f](../research/native-kernel/NK-5f/README.md) | Sampler reuses NK-5e's compressions (GDScript plumbing) | Rolling 125–218 → 70–116. Flight unchanged |
| [NK-5i](../research/native-kernel/NK-5i/README.md) | Endpoint facts in one call | Live observer 152–153 → 104–108 |
| [NK-9a](../research/native-kernel/NK-9a/README.md) | Detector speed window | `detector.observe` 18–19 → 7 |
| [NK-9b](../research/native-kernel/NK-9b/README.md) | Published sample | `sample(true)` 27–30 → 22–24 |

### Flight audio (per frame unless stated)

| Batch | Moved native | Measured |
| --- | --- | --- |
| [NK-6m](../research/native-kernel/NK-6m/README.md) | Glow voice per-sample synthesis (worker thread) | 25–27 → 9–11 ms of CPU per audio second |
| [NK-6o](../research/native-kernel/NK-6o/README.md) | Ground audio wheel rows | `snapshot_contacts` 260–309 → 142–163 on the ground |
| [NK-6r](../research/native-kernel/NK-6r/README.md) | Soundscape propagation delay | Live `heard_snapshot` 16–18.5 → 10.5–11.7 |
| [NK-6s](../research/native-kernel/NK-6s/README.md) | Glow engine vibration | 11.5–14.1 → 3.8–4.4 |
| [NK-7a](../research/native-kernel/NK-7a/README.md) | Soundscape laws | None by itself; its callers moved in NK-7b |
| [NK-7b](../research/native-kernel/NK-7b/README.md) | Soundscape core | 50–63 → 18–30 |
| [NK-7c](../research/native-kernel/NK-7c/README.md) | Recorded powertrain bank | 61–62 → 22–23 |
| [NK-7d](../research/native-kernel/NK-7d/README.md) | Accepted-tick ground audio | `FlightAudio._process` 385–395 → 316–319 |
| [NK-7e](../research/native-kernel/NK-7e/README.md) | Accepted-tick mechanical audio | `_process` 316–319 → 236–247 |
| [NK-7f](../research/native-kernel/NK-7f/README.md) | Airborne contact rows; source kinematics | `_process` 236–247 → 215–227 |
| [NK-7g](../research/native-kernel/NK-7g/README.md) | Glow audio keys in one call | `snapshot()` 84–86 → 75–76 |
| [NK-7i](../research/native-kernel/NK-7i/README.md) | Endpoint wind and air data | `snapshot()` 58–59 → 47–48 (P-51), 76–78 → 64–66 (glow) |
| [NK-7j](../research/native-kernel/NK-7j/README.md) | Loaded contact rows with region and material | `contact_snapshot()` 138–142 → 38–41. `_process` 273–323 → 172–224 on the ground |
| [NK-7k](../research/native-kernel/NK-7k/README.md) | Near-ground band rows; approach speeds | `snapshot_contacts()` 188–198 → 35–40. `approach_speeds()` 69–72 → 17–19 |
| [NK-7l](../research/native-kernel/NK-7l/README.md) | Glow voice whole-block render (worker) | 134 → 119 per 256-frame block, about 1.3 ms of CPU per audio second |
| [NK-7m](../research/native-kernel/NK-7m/README.md) | Shaft-load torques at the published endpoint | `snapshot()` 50 → 43 (P-51), 42 → 36 (electric), 68 → 65 (glow) |

### Rendering

| Batch | Moved native | Measured |
| --- | --- | --- |
| [NK-8a](../research/native-kernel/NK-8a/README.md) | Projected-shadow part walk | Live `ProjectedShadow.refresh` 77–79 → 22–24 |
| [NK-8b](../research/native-kernel/NK-8b/README.md) | Render terrain samples from the prepared ground | Live `receiving_ground` 48.5–48.7 → 12.2 |

### Supporting repairs in the same push

These are GDScript or engine-setting repairs. Each is recorded with its date in
[optimization priorities](optimization-priorities.md#frame-stalls-and-sustained-fps).
- **Per frame:**
  - Glow audio keys from the accepted state: 235–391 → 38–49 µs.
  - Glow shaft-load torques from the blade model: 55–57 → 9 µs.
  - Cloud transport validated once per frame: `World.update` 214 → about 25 µs.
  - Retraction poses only on change: 159 → 92 µs.
- **Per tick:**
  - Lens contact listener: 1–1.9 ms spikes → 7 µs.
  - Accident ledger samples gear support once per frame: about 0.36 ms of each rolling tick
    ([decision](../DECISIONS.md#the-accident-ledger-samples-gear-support-once-per-frame)).
  - Wheel support events built without re-validation: 18 → 4–6 µs per wheel.
- **Stalls removed:**
  - Pipeline cache writes deferred until no flight runs: 21–37 ms stalls gone.
  - Calibration verdict written on a worker: 133–147 ms frames gone.
  - Skyline on a worker: 0.72 s → 0.07 s of main-thread work.
- **Menus:** the Controls opening frame went 650–790 → 212–231 ms, and Settings 280–350 → 90–135 ms.

**Noise-level batches:**
- NK-5c, NK-6q and NK-6t (glow) measured within the host's run-to-run spread.
- NK-6h, NK-6i and NK-6j return nothing airborne; NK-6v returns nothing while rolling.

**Platforms:**
- Every NK-5a to NK-9b gain above was measured on Windows only. CI requalifies Linux and Windows on each push.
- Linux passed all nineteen installer gates locally at `d080ca630` (WSL, 2026-11-28).
- No NK-6/7/8 parity test has run on Linux or macOS.
- macOS packages ship the reference evaluator. The M1 native route is an experimental source-editor build of an
  earlier snapshot ([macOS ARM64](../../research/native-kernel/README.md#experimental-macos-arm64)).

## Remaining work ranked by return against effort

**Return** is main-thread time saved per second of flight. A per-tick saving counts × 240; a per-frame saving counts
× FPS (60 unless stated). 1 ms/s is 0.1% of the main thread. A felt stall ranks above an equal mean cost, and a cheap
measurement that may find one ranks above a small certain batch.

**Effort:**
- **S:** one consumer or one measurement, no new kernel entry point.
- **M:** a new kernel entry point with its parity test, mutation control, nineteen gates and installs in both trees;
  or a change in another owner's file.
- **L:** a new platform, package or engine-level change, or an owner prerequisite: hardware, Xcode or visual
  acceptance.

**Evidence marks:**
- Costs marked † come from the lead's probe on 28 November: Windows, headless, native backend, real timers
  (`Time.get_ticks_usec`) in a disposable instrumented copy. Raw logs were not retained.
- A figure after an arrow is an estimated saving until that batch's alternating A/B measures it.

| # | ID · owner | Work | Cost (source) → saving | Effort | Proof or blocker |
| --- | --- | --- | --- | --- | --- |
| 1 | NK-9c · F0/F2 | Phase-timed live Windows tour (jet, Corsair, glow Stik; 1080p, muted) with the native answer counters | No end-to-end Windows measurement since NK-6u; the slow-frame excess is unattributed. Enables every later claim | S | Every frame split by `frame_phases.gd`. Counters (`native_audio_row_answers`, `native_approach_answers`, `native_render_answers`) above zero, with no fallback reason |
| 2 | F1 · CR, sim | Re-measure touching ticks after NK-6f–6l. Then extend the ledger's hold from gear-support samples to persistent hull events, inside `app/economy/incident.gd` (new work); take one `mass_properties()` per accepted tick | F1 cell, 26 November, live Corsair, before NK-6f–6l: ledger about 600, session handler about 300, `mass_properties()` 110 µs per touching tick. A hold that pays the ledger once per 60 Hz frame saves at most 600 µs × 180 ticks ≈ 108 ms/s while a hull point touches | M | Its caller in `main.gd` is pinned by the companion manifest and stays unchanged. Ledger digests, crash audio, checkpoint and replay unchanged |
| 3 | F4 · DT-MAC | Profile the M1's 500 ms disturbance (`sample` or Instruments) | 12.6–13.9 ms maximum excess per cycle, twice a second, in flight, pause and menus | S after the prerequisite | Full Xcode on ANGEL (owner) |
| 4 | F3 · UI-34c | Save the first-flight hint preference off the flight frame | About 15 ms once, 10 s into a new player's first flight | S | `app_root.gd` is pinned by the companion manifest: renew its source and profile hash in the same push |
| 5 | F2 · VQ/PT | Repair the Windows slow-frame source that item 1 attributes | 3.5–4.2 ms excess in 931–2,118 frames per circuit | Unknown until attributed | A named source with a repeatable intervention |
| 6 | VQ · Apple C3, low-end L2 | Distance-gated ground detail; Simple versus Full ground | M1: ground ≈ 11 of 28.4 ms GPU. UHD 630: rough-field material 9.21 ms at Home. → ≤ 2.5 ms of GPU per frame on the M1 (plan estimate) | M | Owner visual acceptance. [Apple plan](apple-silicon-performance.md), [low-end plan](low-end-gpu-performance.md) |
| 7 | UI | Defer Controls' hidden tabs | Insertion about 100 ms and construction about 45 ms per open; largest frame 212–231 ms | S–M | First visit to each deferred tab, focus and device selection |
| 8 | F5 | Measure periodic work: statistics snapshot copies, incident `duplicate(true)`, controller storage at 2 Hz, performance text, overlay numbers | Unmeasured. The overlay refresh is about 340 µs per update, at an unrecorded cadence | S | No interval above 2 ms from these in a 10-minute flight |
| 9 | AFC | Re-measure companions at 1080p | About 52 ms frame p95 with three companions (older 720p test) | S | 0–3 companion attribution |
| 10 | F3 · VQ/CR | One pipeline warmup registry behind the loading screen, at live MSAA and viewport format | 105 background specializations 0.6 s after reveal; 7.2 MB VRAM growth; PRIMIS cold opening 6.7 s; fresh Windows first impact 47–766 ms | L | No allocation or pipeline-count change after reveal |
| 11 | NK-7n | Audio endpoint snapshot: mechanical snapshot, airborne clear test and the snapshot's remaining session reads in one call | † Endpoint observations 13–23 µs per frame (mechanical snapshot 11–15, clear test 6–8); `snapshot()` 36–65 µs. → about 20 µs, 1.2 ms/s | M | Parity on, off and full-reference; live counters |
| 12 | NK-6y | Liquid tick context and glow step plan from frozen-aircraft parts | † 15.6 and 16 µs per tick on those aircraft → about 10 µs, 2.4 ms/s | M | Parity with mutation control; replay identical |
| 13 | NK-6x | Contact step preparation from the stage's prepared configuration | † 8.7 µs per tick → about 6 µs, 1.4 ms/s | M | As above |
| 14 | F5b · aircraft, camera | Skip `apply_controls` when its inputs are unchanged; chase-camera springs | Live, F5b cell: 17–67 and about 40 µs per frame → up to 1–4 ms/s | M | The aircraft builder is SHA-pinned: hook at the render boundary, only if no other writer touches those nodes. Camera owners' rework |
| 15 | NK-7o | Glow voice hand-over telemetry from the glow keys | † 21 µs per frame on glow aircraft → about 15 µs, 0.9 ms/s | M | Byte-identical PCM |
| 16 | NK-5h-R2 · configuration owners | Freeze more guarded roots, so identity checks replace property watches | † Configuration and weather guards 9 + 5 µs per tick → up to about 10 µs, ≤ 2.4 ms/s | M | Owners' review. At the A/B noise floor, so accept only on an A/B above it |
| 17 | NK-P | NK-6/7/8 parity on Linux; then native macOS for the current source and package | No Linux parity run yet. macOS ships the reference evaluator. Before NK-5/6, NK-3 measured Linux's native stage evaluator at a median 2.11× cheaper tick. On the GPU-limited M1 this mostly shortens catch-up (inference) | S (Linux), L (macOS) | Linux parity suites in WSL; Mac source and package receipts on the M1 |
| 18 | F6 · gated | Simulation on its own thread | Only if F1 and F2 leave PRIMIS-class hosts below real time | L | Owner-reviewed contract |

**Not worth doing now:**
- **The glow voice's per-sample trigonometry.** It costs 119 µs per 256-frame block on the worker thread, not the
  frame, and byte-identical PCM rules out approximations.
- **Native batches below about 5 µs per tick.** They fall under the workstation's A/B noise floor: NK-6q measured −4
  to −7 in the mean, with single runs from −16 to +5.
- **Native ports of UI, orchestration, the simulation transaction or the GDScript reference.**

## What we learned

- **Answer only for the published endpoint.** Presentation readers may use a native answer only for the endpoint they
  read, under the publication's own conditions, and every refusal must reach the unchanged reference
  ([learning](../learnings/physics.md#native-answers-for-published-endpoints)).
- **Bytes and stamps both change hashes.** Receipts pin raw source bytes, and linkers stamp binaries, so line endings
  and PE timestamps both mislead ([learning](../learnings/runtime-and-delivery.md#clean-builds-and-desktop-evidence)).
- **Budget walks over aliased containers.** A plan that walks containers once per path explodes on aliased
  configurations; budget it and keep the alias-aware fallback
  ([learning](../learnings/physics.md#native-answers-for-published-endpoints)).
- **Exports can lack shader globals.** Exported builds can lack project shader globals that the editor registers
  ([learning](../learnings/models-and-rendering.md#rendering-and-visual-evidence)).
- **Time the real workload.** Synthetic estimates were wrong by 3×: NK-7l measured 15 µs per block, not the estimated
  50 ([learning](../learnings/physics.md#measure-the-complete-workload)).
- **Gains below the run-to-run spread are not gains.** Use alternating A/B rounds and medians. NK-5c, NK-6q and NK-6t
  sat inside the spread. An early native substep count was dropped as noise before NK-6u measured 135 → 116 µs.
- **Report each flight phase.** Hull and contact batches pay on the runway and nothing airborne (NK-6h–6j); NK-6v pays
  airborne and breaks even rolling.
- **CPU savings raise FPS only where the CPU limits.** On GPU-limited hosts they shorten catch-up spikes; mean FPS
  there needs GPU work.
