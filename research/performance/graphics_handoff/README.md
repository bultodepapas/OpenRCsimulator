# DRS contract reference for the graphics handoff

The separate [ray-query and sunlight-energy fixture reference](rt_fixture_README.md) now provides offline M4 geometry/lighting cases. This page remains the DRS specimen's home; neither reference is a measurement collector or a production feature.

2026-11-15 · A small executable design specimen for [M2](../../../docs/research/graphics-performance-2026-11-15/05-integrated-implementation-plan.md), following the [timing/DRS design](../../../docs/research/graphics-performance-2026-11-15/09-timing-and-drs-design.md). This is original standard-library Python code outside `app/`. It neither changes the simulator nor collects measurements. It needs Python 3.10 or newer; it has no package dependencies, GPU, engine, settings, network, file-writing or physics integration.

## Run the contract checks

From the repository root, including a fresh complete checkout:

```sh
python3 -B -m unittest discover -s research/performance/graphics_handoff -p 'test_drs_reference.py' -v
```

The suite has 38 tests plus table-driven negative cases. It checks independently specified integer examples, a default-policy transition trace, stale and duplicate samples, bounded storage, CPU/pacing admission, floor/ceiling, hysteresis, and proposal/acknowledgement/retirement. It does not qualify Godot or any GPU. The [execution playbook](../../../docs/research/graphics-performance-2026-11-15/11-test-and-execution-playbook.md) names the existing application, native, optical and export checks that remain necessary. Results and exact file hashes belong in the [handoff receipt](../../../docs/research/graphics-performance-2026-11-15/evidence/handoff-validation.json).

## What the code makes concrete

| Contract | Reference behavior |
| --- | --- |
| Single scalar to integer pixels | `nominal_extent` models the accepted scalar path inspected in Godot `cafc17a19`: float32 scalar/product, positive truncation to integer. This is nominal source arithmetic, not actual allocation or dispatch evidence. |
| Legal range | `legal_ladder` intersects at most 32 candidate scalars with explicit per-axis floor/ceiling/alignment. It never rounds width and height independently, invents a legal size or silently widens the range. An empty range is rejected; one legal extent is static. |
| User choice | Construction requires the highest rung to equal the already observed fixed scalar **and** integer extent. Equal pixels do not permit raising the user's scalar. Provider/quality selection remains external. |
| Samples | A new completed ID, coherent generation and input extent, positive finite duration, and known same-clock recording time are required. Equal durations on different IDs remain distinct. A duplicate cannot refresh its original age even if its payload is rewritten. |
| Bounded policy | The reference uses non-overlapping windows with at least 120 accepted unique samples spanning 2 seconds. Three bounded counters include **every** accepted frame; no time thinning or sample array is needed. The nearest-rank p90 threshold decisions are exact for those samples. These are control predicates, not reported benchmark percentiles. |
| Adaptation | The starting proposal in report 02 is made explicit: high p90 above 90% of the real-frame budget for two windows, at least 5 seconds between changes before one-rung reduction; low p90 below 75% for at least 10 seconds and a 10-second dwell before one-rung recovery. A single spike cannot create two high windows. |
| Apply transaction | A proposal does not change `confirmed`. The qualified adapter applies through the existing reconstruction owner and returns the exact opaque `Change` object with a newer generation and observed extent. An integer request ID alone is not authority. Foreign/copied tokens are ignored, successful observation is accepted, and matched failure/timeout returns an immediate fixed-restoration decision. |
| Retirement | Invalid or unavailable feedback and blocking transitions request fixed restoration and permanently retire this controller instance. Old samples and callbacks cannot revive it. After the owner confirms safe fixed state, it may create a fresh instance with the new generation. CPU/pacing ineligibility clears evidence and holds the acknowledged level. |

The scalar arithmetic source is [the exact pinned viewport configuration](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp#L136-L310); that function also has mode/renderer/fallback branches this nominal arithmetic helper does not model. The official [RenderingServer timing contract](https://docs.godotengine.org/en/latest/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu) describes scope and cap/power-state caveats. The [detailed design](../../../docs/research/graphics-performance-2026-11-15/09-timing-and-drs-design.md#3-timing-identity-what-the-pinned-engine-actually-exposes) explains why a polled number or a separately queried RD frame counter cannot manufacture the coherent sample required here. A method name in latest documentation is not a verification of the project's engine pin.

For `N` accepted values, the nearest-rank p90 index is `k = ceil(0.9 × N)`, computed exactly as `(9*N + 9) // 10`. If `A` counts values strictly above the high threshold, p90 is above that threshold exactly when `N - A < k`. If `L` counts values strictly below the low threshold, p90 is below that threshold exactly when `L >= k`. This uses constant storage and avoids the periodic-cost alias found during review: selecting every second frame could hide alternating 2/4 ms costs at 240 Hz. Both phases now have a regression test. A pathological window above one million samples retires safely; it does not grow a retained data buffer.

## Deliberate limits and adapter preconditions

This is a partial executable contract, not a second rendering implementation. `gpu_limited=True` represents **prior, current-enough proof** of pixel-sensitive GPU pressure with contemporaneous CPU/physics/pacing exclusions. It is not computed from FPS. The adapter must reject the wrong provider, output size, measured scope, unsupported mode, incomplete auxiliary-work coverage and invalid actual execution **before** supplying a sample. Those fields are not all present in this small `Sample` dataclass. A correct controller cannot rescue an adapter that invents completion identity, age, scope or observed extent.

`recorded_ms` must be the monotonic CPU time associated with the same submitted/measured work, in the same clock domain as `now_ms`; it is not the current poll time or an uncalibrated GPU timestamp. The specimen assumes one ordered completed-sample stream for its viewport/configuration epoch. The integration must qualify that association and all native synchronization. It does not use `frame_post_draw` as GPU completion or convert generated presents into real render samples.

The 100 ms age bound, 250 ms gap bound and 1,000 ms apply timeout are explicit **untuned experiment parameters**. The non-overlapping window partition is one bounded interpretation of the earlier rolling-window proposal, chosen here to avoid counting overlapping windows as independent sustained evidence. It needs a documented native decision before becoming production behavior. Test-only `FAST` parameters compress time for edge cases; the separate default trace checks the uncompressed starting proposal. Neither parameter set promises a smooth or optimal control response.

`confirmed` means the last accepted reference state. After retirement it is historical, not a live renderer query. `restore_fixed=True` is a request to the existing reconstruction/settings owner, not proof that restoration happened. The adapter must cancel or drain pending native work, observe the effective fixed provider/scale, preserve saved MSAA and requests, and create a new epoch. Explicit user Off, resize, renderer change and settings Keep/Revert remain owner operations in report 09. There is no per-frame preference write, native API wrapper, telemetry schema, new capture tool or graphics setting here.

Timeouts are cooperative in this pure model. The integration owner must schedule a monotonic deadline independently of draw/sample arrival, and call the policy's pending-timeout path even if no GPU callback arrives (`step(None, deadline, gpu_limited=...)` is the reference event). A matching late acknowledgement also retires immediately. A constant of 1,000 ms does not create a timer, safely cancel GPU work or restore a viewport by itself.

## First implementation use and disposal

Use these cases as acceptance examples when implementing the production policy under VQ-07d/PT after M0/M1 admission. Keep the exact Godot policy and real consumer tests in `app/tests/`, using the existing checked runner and test queue. Port the cases and independently check production behavior; a Python reference agreeing with another copy of itself is insufficient. Once equivalent production tests cover these decisions, consolidate the useful examples and remove the disposable duplicate reference instead of maintaining two policy engines.

Do not expand this directory into a profiler, a report schema framework or a second benchmark suite. These offline research examples were requested for the engineering handoff; they are **not an M0 measurement executable, capture path or extra native qualification gate**. The five-day M0 repair limit and one-day later attribution review in [05](../../../docs/research/graphics-performance-2026-11-15/05-integrated-implementation-plan.md) still apply. Using existing tools for required native qualification remains necessary and separate from building instrumentation.
