# UI-34c / DT-11a: cold trim preparation

2026-10-24. Continuation of [R2](../UI-34c-R2/README.md). The [execution plan](../../../MENU-REDESIGN-PLAN.md#12-home-to-flight-loading-ui-34c-and-dt-11a) owns remaining work. This slice reduces repeated electric-source work and moves cold cruise trim onto a private numeric worker. It does not change aircraft data, solver tolerances, integration laws or golden recordings.

## Scope and source

The frozen baseline is `6b4bd9e3b27b87697152b5f856a3b7c59aa24f5a`. Candidate development and measurements used an isolated worktree; unrelated shared-tree work was excluded. Native measurements use the same Godot 4.7.2 Compatibility renderer, Ryzen 9 5900X, RTX 3090 and NVIDIA 617.42 driver. Fresh processes do not imply cold OS, import or shader caches.

A diagnostic profiler run identified repeated `PackEcm.initial_block` and full telemetry construction inside electric torque residuals. That run crossed an unrelated shared-tree translation merge and is attribution only, not accepted timing evidence. Subsequent baseline/candidate comparisons use the frozen worktrees.

## Changes and ownership

`Propulsion.steady_operating_point` now prepares the rested pack block once per equilibrium search. Residual and tolerance probes use the existing compact evaluation; the voltage reference still uses the full result. Every root search owns its context. No persistent pack-state cache or cross-aircraft reference is introduced.

The staged session route validates and prepares the aircraft on the main thread, then asks the existing exact launch-trim cache for a hit or a cold-job reservation. The worker receives serialized, independently decoded plain data and calls only `CruiseTrim.solve_level_at_throttle`. Scene creation, validation, cache lookup/publication and session commit stay on the main thread. The ordinary synchronous setup route remains available for direct launches, traces and tests.

Only one worker reservation can exist per cache. Unsafe, oversized, busy or unavailable-thread requests preserve the synchronous fallback. Successful exact tuples retain the existing two-entry / aggregate 1 MiB key bounds; failures and cancelled worker results are not published. Clearing the cache invalidates stale publication. No live `FlightSession`, `VehicleModel`, `Resource` or callback crosses the worker boundary.

Cancellation is polled between main-thread frames. The loading screen can acknowledge it while trim is running, but cleanup waits for the numeric job to finish and join. The solver itself is not interrupted. Quit uses the same drain path. Remaining indivisible scene/world calls still defer cancellation until their next checkpoint.

A native indeterminate activity bar accompanies the stage text without inventing a percentage. Reduced motion omits that animation. It can animate while the numeric job runs; it cannot hide an indivisible main-thread stall.

The transitive numeric closure was inspected through CruiseTrim, Trim, Dynamics, Aero, Propulsion, Slipstream, Air and math helpers. No reachable scene access, file loading or shared mutable cache was found; preloaded scripts and constant tables are read-only. This follows Godot's [thread-safety boundary](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) and [join requirement](https://docs.godotengine.org/en/stable/classes/class_thread.html). Thread safety checks remain enabled.

## Numerical parity

The isolated Turbo Lumber pack setup fell from **11,654.101 ms to 4,956.700 ms** in single headless captures, a 57.5% reduction. Both complete start results contain 784 identical bytes, SHA-256 `105610a95322c2d1ef1e32e3ebfe2719c254a1ef90e1bd4ab581bfdad1b17d07`. These are mechanism checks, not a native-loading speedup estimate.

Four valid root fixtures spanning duty, inflow, density and initial SOC, plus four failure fixtures, also retain identical result bytes. [Root parity manifest](root-parity.json) records each result identity. The permanent differential test checks prepared/full output equality, compact consumed fields, independent contexts and failure behavior without assuming cross-platform bitwise hashes.

## Native loading and recovery

[Five alternating pairs](native-summary.json) used the existing `research/performance/loading_probe.gd`, each fresh process performing one cold and one repeated Home/Fly transition. Both worktrees used `--resolution 1920x1080 --fullscreen`; every retained viewport is exactly 1920×1080. [Source identities](source-identities.json) identify candidate `b0054b5e8` and baseline `6b4bd9e3`.

| Scene readiness | Baseline median | Candidate median |
| --- | ---: | ---: |
| First electric Fly | 15.811 s | 8.561 s |
| Repeated electric Fly | 1.634 s | 1.706 s |

First-load median fell **45.9%**. The repeated route stays near 1.7 s; these five samples do not establish a warm-route speedup. Candidate first-load samples ranged 8.122–10.521 s. Acknowledgement after acceptance took 8.6–20.3 ms across its ten transitions. Cold handoff-frame p95 ranged 19.9–32.5 ms, but the longest frame remained **1.70–2.67 s**, dominated by cold scene preparation. Warm p95 remained 218–246 ms, so the overall cadence and chunk gates are still open. More frames during the numeric job reduce the cold percentile; that does not erase the remaining long stalls.

Baseline pair 1 and candidate pair 4 lost focus and had paused first draws. Their scene-readiness measurements are retained, but are **not interactive-ready evidence**. Pairs 2, 3 and 5 have active first draws on both sides. Focus guards were not bypassed. Earlier windowed exploratory runs produced 1920×1061 viewports and are excluded from this primary-resolution set.

The [20-cycle Stik run](native-stik20.json) completed with 869 Home nodes every cycle, zero orphan nodes, no paused first draws and clean audio teardown. First readiness was 3.762 s; the median of the 19 repeated transitions was 1.790 s. This is a node-lifecycle check, not a RAM/VRAM or DT-12 soak qualification.

The native debug bridge exercised the Spanish loading surface at 1920×1080. A 46-frame window during the cold worker measured mean 16.67 ms, p95 17.18 ms and maximum 17.24 ms, with no hitches. The candidate Sim stayed at tick zero and outside the active tree. Cancel changed the text to “Cancelando…” while the worker was still alive, drained it, restored Home/focus and retained no trim entry. A second cold launch accepted Quit while the worker was alive and exited after drain. The [lifecycle receipt](debug-lifecycle.json) records zero orphan nodes after cancel and zero reported ObjectDB leaks or crashes at exit. A full-size screenshot was inspected under ignored `tmp/`; no image is retained in Git.

After these measurements, a controller-cut null guard was added for the earlier loading interval before a candidate session exists. The native cancellation/quit checks and repeated loading transaction suite include this guard; it does not alter the timed numeric or scene construction path.

## Verification

- Electric equilibrium preparation: 22 checks; electric propulsion 20; pack ECM 84; supply 95; compact motor 13; electric trim reuse 18; cruise trim 22.
- Async cache: 24 checks, including private input isolation, one reservation, invalidation, raw-result parity, failed solve preservation and unsafe-input fallback. Staged session: 12 checks, including independently cold sync/staged output parity, raw cache parity, validation failures and continued frames during cancellation drain.
- Exact launch cache: 47; loading surface: 16; loading transaction: 14; session guards: 32; all four unchanged golden flights pass. Natural Random numerical flight checks: 576.

[Checked-run receipts](checked-tests.json) retain commands, outcomes and log hashes. The initial seeded baseline import reported stale import metadata; its retry passed before measurement. No failed import or exploratory profile is used as accepted performance evidence.

The canonical companion rebind replayed all nine retained tapes on both solver versions with byte-identical CSVs and [renewed the solver pin](../../ai-companions/AFC-02/rebinds/2026-10-24-83b06513-to-6a5373ca.json). Its nine Python consistency tests pass. The profile gate accepts the new solver identity but still fails the **pre-existing controller-source pin mismatch** documented in [R2](../UI-34c-R2/README.md#verification-receipts). The pilot was not changed or re-pinned; full companion admission remains unresolved.

## Remaining gates

Scene script compilation, scenery construction and contact setup remain main-thread work. The target of Fly within two seconds, loading p95 at most 33 ms and no chunk over 100 ms remains open. Idle prefetch needs immediate-Fly and selection-dwell comparisons, cancellation/ownership proof and total launch-to-flight measurements before adoption. The rejected threaded scene preload is not restored.

Source tests and native samples do not establish release-package, minimum-hardware, DT-12 soak or physical qualification. The full `app/test.sh` suite is not part of this slice's evidence.
