# RCV-42 — Road-batch transport optimization

2026-10-15. MONSTER CAR 2 uses **3.7% less whole-session CPU time per tick** in the paired workload below. The native road adapter now validates samples without creating a success Dictionary for each point, reserves the six-channel float64 output once, and writes it directly. The shared validator preserves the original errors, normal-length arithmetic and acceptance thresholds. Physics equations, contact locations, 240 Hz stepping and the native binary are unchanged.

## Exploration and selection

The [baseline profile](baseline.json) and preceding [RCV-41 evidence](../RCV-41/README.md) identified road sampling and integration as the next costs. This phase explored four transport variants and a different snapshot strategy before integration:

- **Preallocation alone:** inconsistent across repeated batches. Fewer allocations did not establish a standalone speedup.
- **Shared error-only validation with preallocation:** selected. Successful validation returns an empty String, avoiding the `{ok, surface}` wrapper inside the native batch loop. The ordinary single-sample API retains its original result Dictionary. Checking three finite normal components directly and retaining the same `M.sqrt_(x*x + y*y + z*z)` order removes small helper calls.
- **Shared validation with append:** also faster than the baseline, with similar component timings to the selected version. The evidence does not attribute an independent benefit to preallocation.
- **Selected-field road snapshots:** rejected. Explicit GDScript field selection and recursive detachment were approximately 3.9–4.3 times slower than Godot's full `duplicate(true)` in the [copy probe](snapshot-exploration.json). Four real dry/wall/wet samples and malformed nested fixtures passed 14 projection/ownership comparisons. Production keeps its existing deep copies and local exact-coordinate cache.

The batch still validates the entire initial coordinate buffer and rechecks each pair and Callable immediately before invocation: callbacks can mutate the shared buffer or invalidate their target. Failure returns an empty output buffer, never partial samples. No sample is quantized, deferred or retained across evaluations.

## Measured outcome

Godot 4.7.2 official Windows debug runtime, Ryzen 9 5900X, native body evaluator, headless source project, audio disabled. [Paired measurements](paired.json) use three rounds of 60 warmup plus 960 measured ticks with launch, steering, braking and coast inputs. Baseline and candidate alternate first execution each tick. The baseline uses a retained pre-RCV-42 body evaluator and Nitro bridge while both Sessions retain the same current artifact identity checks. State/telemetry comparisons occur outside timing.

| CPU measurement | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Whole session, median of round means | 5.686 ms/tick | 5.473 ms/tick | 3.7% |
| Whole session, median of round p95s | 7.045 ms/tick | 6.801 ms/tick | 3.5% |
| Validation/packing, median of five 6,000-batch means | 54.956 µs/14 samples | 38.042 µs/14 samples | 30.8% |

Whole-session round reductions are **3.7%, 4.1% and 2.7%**. An earlier [draft comparison](paired-draft.json) showed 2.7%, 2.4% and 3.1%, also with exact trajectories. The final [component run](batch.json) measures a cheap callback returning an existing Dictionary to isolate adapter cost; it is not the full terrain-query cost. Earlier `batch-exploration`, `batch-preserved-guards` and `batch-variants` reports retain the development experiments. Final `batch.json`, `paired.json` and their [measurement receipt](measurement-receipt.json) are authoritative for the accepted implementation.

The [candidate profile](candidate.json) still performs **70 road calls per tick**. Its nested road-sampling timer is included in integration/telemetry, so those buckets must not be added together. Separate instrumented profiles are diagnostic; paired production timings determine the claimed gain. Shared-host load affects absolute values, which also explains the faster absolute draft run.

At 5.473 ms/tick the measured mean still exceeds the **4.167 ms interval at 240 Hz**. The stricter 500 µs track gate also remains open. These measurements do not establish rendered FPS, GPU cost, wet/obstacle worst-case cost, release-package performance or physical realism.

## Verification and identities

- **6,216 exact component comparisons** cover the three variants against the retained original: empty and malformed batches, wrong callback result types, missing fields, malformed/non-finite normals, both sides of the unit tolerance, invalid friction/rolling values and 2,000 seeded finite samples. Serialized outputs preserve float64 bytes and error dictionaries.
- **55 permanent road-batch checks** passed before and after integration. They verify channel/coordinate order, runtime negative zero, immediate failure with no partial buffer, reused mutable Dictionary/normal results, and a callback changing the next coordinate to NaN. The test is included automatically by `app/test.sh`'s `test_*.gd` discovery.
- **3,060 paired ticks** preserve state and telemetry bytes, control/event tapes and checkpoint identities within each round. Independent baseline/candidate profiles pass checkpoint restoration, official replay and full-trajectory replay. The common trajectory digest remains `d2c255aee62148ea79908da716d1c1c6279b20b22e5b1a88bc9e261597908eb8`.
- All **nine focused suites** pass: **407 numbered checks** plus the aggregate airfield-course suite. They cover road transport, both vehicle sessions, Nitro dynamics/service, body native/reference behavior and backend switching, airfield sampling, damage replay and obstacle contacts. [Logs, exits and source/test hashes](checks/verification.json) contain no engine/script/shader errors. The full repository, rendering and export suites were not run.

`solver_changed=true` and `course_changed=true` describe implementation-source identities: the Nitro composite and course manifest include the body adapter source. The equations, native binary and Session source are unchanged. Historical source-pinned checkpoints/recordings remain incompatible under the existing guards; exact numerical comparisons do not waive identity checks. [summary.json](summary.json) validates current sources, receipts, replay and evidence hashes before reducing the measurements.

## Reproduce

From the repository root, run Godot processes sequentially:

```powershell
python research/rc-monster-truck/monster-car-2/rcv42/measure.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out docs/research/rc-monster-truck/RCV-42
python research/rc-monster-truck/monster-car-2/rcv42/verify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out docs/research/rc-monster-truck/RCV-42/checks
python research/rc-monster-truck/monster-car-2/rcv42/summarize.py
```

[`rcv42/`](../../../../research/rc-monster-truck/monster-car-2/rcv42/) retains the baseline evaluator, bridge, component variants, projection probe and runners. `measure.py` records process exits and checks source stability; `summarize.py` rejects stale hashes. The profile schedule/wrapper is reused from `rcv41/` without the old identity baseline overrides. The operating home is the [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md).

Godot documents [PackedFloat64Array](https://docs.godotengine.org/en/4.7/classes/class_packedfloat64array.html) reference semantics and explicit duplication, and [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate) deep-copy behavior. Consulted 2026-10-15; mutation probes establish the behavior exercised here.
