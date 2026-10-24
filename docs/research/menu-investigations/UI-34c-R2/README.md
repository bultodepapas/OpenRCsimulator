# UI-34c-R2/R3/R4 — staged Home-to-flight preparation

2026-10-24. Source implementation and exploratory native verification. Owner: UI-34c / DT-11a. [Execution plan](../../../MENU-REDESIGN-PLAN.md#12-home-to-flight-loading-ui-34c-and-dt-11a); [preceding audit](../UI-34c-R1/README.md).

## Implemented behavior

AppRoot accepts one frozen aircraft/livery/landscape/start/fuel/battery/weather/lighting request. An opaque, translated loading screen owns input through ScreenStack. It reuses Home's theme, reports actual preparation stages, supports Cancel/Escape, and waits for a rendered frame before scene construction. Home's former extra frame delay is removed. There is no fabricated percentage or minimum display delay.

The candidate cannot process while incomplete. Main yields at validation, aircraft, world, instrumentation, contact, effects and audio boundaries. World and Field share their ordered construction helpers with the immediate builders. Field checks cancellation between ground, tree, cue, scenery, lake, vegetation and shadow chunks; partial detached trees are freed. The final flight draws while held before the loading surface is removed. Lost focus/controller readiness still opens Pause. Failure/cancellation restores the prior Home or Natural Random draft; quit waits for cancellation cleanup.

The existing preview broker owns selected imported-model requests across the handoff, including a pending preview. Its two-resource limit also accepts the synchronously loaded flight scene. The three-instance Home preview limit is unchanged. Mutable aircraft/world/session nodes are rebuilt and validated; no previous physics session is reused. Staged startup avoids the initial projected-shadow binding that the validated glow propeller setup would immediately replace.

Launch trim retains two exact argument tuples in an LRU cache. The aggregate serialized-key limit remains 1 MiB; exceeding the entry or byte bound evicts the least recently used tuple. Failures are never cached and do not evict successful entries. Unsafe values and oversized keys bypass retention. Results are deeply copied, and every launch still rebuilds and validates its model. This allows switching between two recent preparations without weakening setup/content invalidation.

Electric trim reuses the current equilibrium RPM for Jacobian probes that change only elevator, aileron or rudder. Alpha, duty and sideslip must match exactly; changed steady-point inputs still solve afresh. The final result also reuses the RPM its force evaluation already computed. Equations, convergence tolerances and iteration limits are unchanged.

Direct/headless/capture routes retain immediate construction without rendering waits. A test override that calls Main's now-awaitable world builder explicitly awaits it; with no checkpoint callback it still completes in the same frame. No physics parameters, authored geometry or golden recordings change.

## Rejected trials

1. Threaded `main.tscn` loading after the loading screen reduced the first observed maximum frame to 424 ms, but reproduced the **11 count-zero RefCounted shutdown warnings** from the [earlier rejected experiment](../../visual-quality-implementation/VQ-01c/loading/scene-warmup-2026-10-21/README.md). The warning also appeared in headless integration. This path is **not retained**.
2. Loading five script dependency groups sequentially did not remove the expensive remaining `main.gd` load and increased first-Fly time. This path is **not retained** either.

The adopted path loads the scene normally behind the acknowledged loading screen and keeps its PackedScene through the existing bounded broker. Background requests remain limited to imported models. First scene compilation is still a blocking stage; this implementation does not claim to eliminate it.

## Evidence and limits

Native Windows, Ryzen 9 5900X, RTX 3090 / NVIDIA 617.42, Godot 4.7.2 `ed1daf0bf`, Compatibility, 1920×1080. OS/import/driver caches and other host activity were uncontrolled. Other tracks edited the shared tree during work. These are source observations, not alternating frozen A/B pairs, an exported-package qualification, or a minimum-hardware guarantee.

The existing loading probe now waits for the transaction to finish, rather than accepting the first non-null candidate. It reports input-to-loading draw, accepted-to-ready time, phase spans, observed frame intervals and active/paused state separately. `phases[].work_usec` measures elapsed time between checkpoints excluding their explicit draw wait; it is not CPU profiling and can include asynchronous model waits. Field's `field_build_ms` separately excludes its checkpoint waits.

A 20-cycle native lifecycle run completed with all first flight draws active, exactly 869 nodes at each returned Home, zero orphan nodes, released tracked audio, and no shutdown leak warning. This run preceded the final removal of an extra feedback-frame wait and the two-entry trim change; it establishes the loading transaction's lifecycle at that point, not final feedback latency or a new 20-cycle cache soak. Its first scene span was 2.246 s; maximum warm loading frame was 340 ms. Remaining warm blocks include scenery generation and collision/contact preparation. Loading-frame p95 ≤33 ms, all chunks ≤100 ms, cold Fly ≤2 s and full DT-12 soak/package gates remain open.

Final native feedback samples, debug-bridge observations and checked test receipts are recorded in the accompanying evidence files. Captures remain under ignored `tmp/`; no images are added to the repository.

### Observed response and remaining blocks

The final five-cycle Stik source run acknowledged Fly in **91.8 ms on the first cycle and 17.9–28.0 ms on repeats**. Readiness was 4.91 s first and 2.32–2.46 s warm. All first flight draws were active. A separate debug-bridge run observed 9.6 ms feedback and 1.68 s warm readiness. These samples demonstrate drawn feedback; their variation does not establish the ≤2 s readiness gate.

Before electric RPM reuse, a Turbo Lumber pack launch took 25.78 s, of which 22.29 s was flight checking; an exact repeat took 2.13 s. In an isolated before/after `FlightSession.setup` capture with the same finite battery pack and 0.5 launch throttle, RPM reuse reduced setup from **22.069 s to 12.623 s (42.8%)**. Serialized start dictionaries were byte-identical: 784 bytes, SHA256 `105610a95322c2d1ef1e32e3ebfe2719c254a1ef90e1bd4ab581bfdad1b17d07`. This is one retained software parity case, not a physical validation or a general hardware speedup guarantee.

The final combined native electric run acknowledged Fly in **36.3/24.7 ms**, reached readiness in **16.38/1.78 s** and first active draw in **16.42/1.82 s** for first/repeated launch. It exited without engine errors or shutdown warnings. The remaining first flight-checking span was 12.96 s and scene preparation was 1.62 s. [Before](electric-before-2.json) and [after](electric-after-2.json) samples were separate exploratory runs with uncontrolled host/cache state, not alternating frozen pairs. [Final source hashes](electric-source-identities.json) were checked again after the run.

Cancellation is serviced at checkpoints. Scene compilation, scenery/contact construction and the remaining cold electric solve can still block between them. The visible stage remains on screen during these calls; continuous animation or immediate cancellation inside them is not claimed. Further work should split these measured blocks or establish a pure, cancellable worker for immutable preparation before adding more speculative preload.

### Verification receipts

- Loading transaction: 14 checks, including early/candidate cancellation, quit, rejected startup, duplicate Fly, held simulation and successful commit. Loading surface: 16 checks, including 1080p and 200% text.
- Preview resources: 15 checks; preview requests: 25. Shared World staging: 11; Field staging: 8; landscape runtime: 56. Natural Random: 30; Pause and session guards passed, including repeated return-to-Home flows.
- Electric reuse: 18; electric propulsion: 20; cruise trim: 22. Final two-entry cache: 47, including full-key invalidation, deep-copy isolation, LRU order, failure preservation and aggregate-byte eviction. Four golden flights passed without re-recording after the numeric optimization.
- The Python loading-probe fixture passed its success/failure/cleanup modes, including a detached Home with an incomplete candidate. An initial Natural Random fixture failed to parse because its override did not await the newly awaitable world builder; it was fixed and the 30-check retry passed. The failed and successful receipts are both retained.

The canonical companion tool replayed all nine retained tapes on both solver versions with byte-identical CSVs, then [renewed the solver qualification](../../ai-companions/AFC-02/rebinds/2026-10-24-eab5dcbc-to-83b06513.json) against committed solver source. Its nine Python consistency tests pass. The final profile test passes the solver-identity gate but **fails the separate controller-source pin**. [Hash evidence](companion-profile-status.json) confirms that the same pilot/profile mismatch already exists at accepted revision `a92a3192` and pre-change HEAD `8bbc27d9`. The loading repair does not change that pilot or weaken its guard; full companion profile admission remains blocked by this pre-existing issue.

[Checked runner receipts](checked-tests.json) retain commands, outcomes and log hashes; raw logs remain under ignored `tmp/`. This work did not run the full `app/test.sh` suite, exported-package checks or the complete DT-12 acceptance matrix. No golden recordings, aircraft parameters or authored geometry were changed.
