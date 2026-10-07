# H4/H5 — Simulation-cost profile and measured hot-path work

2026-10-07 · **Status: profile-led GDScript work implemented; both target distributions and all 16 exact fingerprints recorded. Gate P reports a measured shortfall.** Main-line ROADMAP H4/H5 and Gate P.

## Method and target

The owner confirmed this Linux development host is the slowest supported target. It is an x86_64 KVM guest on an Intel Core i5-10500 at 3.10 GHz with 12 logical CPUs. Measurements use Godot 4.7.2-stable official build `ed1daf0bf001b61586d9930840f2f1394092c079`.

[`bench_regimes.gd`](../../../../app/tests/bench_regimes.gd) restores a real `FlightSession` for each aircraft and regime, runs 16 timed batches of 120 complete 240 Hz `sim.step()` ticks, and reports the median, nearest-rank p95, minimum and maximum batch-average cost. With 16 samples, this p95 is the largest sample. A separate 960-tick fingerprint hashes each float64 body state, auxiliary state and start-of-tick load in order; timing and fingerprint runs are independent. Component medians use seven batches of 1,200 calls after 100 warmups. These component figures locate cost; they are not substitutes for full-tick timing.

The workloads are trimmed flight; 15° angle-of-attack stall stress; a synthetic 22° high-rate spin-like load fixture (2.2 rad/s roll, 1.2 rad/s yaw, engine off; not handling evidence); and a level 2 m/s ground-contact fixture with 1 cm initial gear compression and engine off. Ground contact remains active through the 960-tick fixture for the Ugly Stik and P-51D. Extra 300S and Avanti S have no loaded landing-gear data, so their ground rows measure the no-gear/no-contact path and are not evidence of ground handling. The original baseline JSON retained the trimmed-start speed in its descriptive ground field; the actual fixture state was 2 m/s, confirmed by the matching 960-tick hashes from the revised harness.

## Before H4/H5 work

[`baseline.json`](baseline.json) records the 16 × 120 distributions and 960-tick hashes before the profile-led changes below. Values are median / nearest-rank p95 µs per physics tick:

| Aircraft | Trim | Stall | Spin-like | Ground |
| --- | ---: | ---: | ---: | ---: |
| Ugly Stik | 356.4 / 428.4 | 424.1 / 506.7 | 509.5 / 664.4 | 364.2 / 417.5 |
| Extra 300S | 359.7 / 461.2 | 444.1 / 507.0 | 543.3 / 702.9 | 486.5 / 531.0 |
| P-51D | 1125.1 / 1295.5 | 1276.5 / 1543.5 | 523.5 / 598.6 | 601.0 / 786.7 |
| Avanti S | 366.3 / 466.7 | 494.6 / 557.2 | 506.2 / 615.8 | 504.9 / 613.4 |

The baseline isolated P-51 `Dynamics.loads` at 261.3 µs/call in trim and 277.4 in stall; `Slipstream.loads` was 158.8 and 144.3 µs/call. Ground loads were below 1 µs/call in the air and 7.9 µs/call for the P-51's active gear fixture. This identified the P-51 powered tail-wash path, rather than ground contact, as the dominant cost.

## Changes and numerical proof

The P-51 slipstream path now shares the tail arm and `rates × arm` across washed/free loads, reuses each immersed piece's flow in force and moment calculation, and computes the shaft wash vector once per load call. The immersion calculation uses scalar terms in the same arithmetic order instead of temporary vector arrays and per-piece captured `Callable`s. Local aerodynamic loads similarly reuse the flow already computed for each station and tail. `local_flow_weight` uses scalar components, with its vector reference retained in `app/tests/aero_flow_reference.gd`.

The full-fleet interim probe completed all 16 fingerprints for 960 ticks without faults. Every hash exactly matched `baseline.json`. It also showed the P-51 `Dynamics.loads` profile at 175.6 µs/call trim and 217.6 stall, with `Slipstream.loads` at 93.0 and 92.8 µs/call. The shared-versus-legacy all-piece tail-pair comparison is byte-exact; on the pre-final-flow probe it measured 135.8 versus 103.6 µs/call in trim and 118.5 versus 88.1 in stall. These short diagnostic timings were gathered while other host activity was present; use them to locate work, not to accept Gate P.

The exactness evidence is:

- all 16 aircraft/regime 960-tick state/aux/load hashes match the pre-optimization baseline;
- `slipstream_pair_exact` and `slipstream_all_pairs_exact` pass for every benchmark fixture;
- `test_aero_flow.gd` passed 10,000 byte-exact scalar/vector reference comparisons across all four aircraft, including live CG and tail edits;
- the Godot project linter reports no parse errors and no new warnings (11 pre-existing path warnings).

No flattened data framework or `LoadContributor` abstraction was added. Static model dictionaries remain untouched during flight, preserving the checkpoint configuration identity.

## Final target runs and Gate P decision

After `app/test.sh` passed (66 headless programs) and the focused H11 rerun passed (72 checks), two sequential runs used the default 16 × 120 timing batches and 960-tick fingerprints. The owner's existing renderer remained active; no test engine ran concurrently. Each JSON file records the Godot build and CPU. [`source-manifest.json`](source-manifest.json) records the base commit, dirty-worktree flag, tracked physics/simulation diff hash and SHA-256 of every `app/physics/*.gd`, `app/sim/*.gd` and this benchmark harness.

Every aircraft/regime fingerprint completed 960 ticks without faults. All 16 hashes match the pre-optimization baseline and match across both target runs. Run 1 and run 2 median costs are close for the worst P-51 modes: trim 737.0/760.7, stall 877.7/897.7, spin-like 450.6/459.1 and ground 502.4/510.2 µs/tick. The 500 µs/tick budget is therefore missed in P-51 trim, stall and ground on both runs. P-51 spin medians are below the budget, but both p95 values exceed it. Other aircraft have medians below 500; the rows below show every case where either run's median or p95 exceeds 500. `p95` is nearest-rank over 16 batch averages, so it equals the maximum sample. The frame column is four physics ticks at 60 fps.

| Aircraft / regime | Median, run 1 / run 2 (µs/tick) | p95, run 1 / run 2 (µs/tick) | p95 frame cost, run 1 / run 2 (ms at 60 fps) |
| --- | ---: | ---: | ---: |
| Ugly Stik / stall | 325.7 / 347.1 | 367.0 / **505.2** | 1.468 / **2.021** |
| Ugly Stik / spin-like | 441.1 / 463.8 | **548.4 / 603.0** | **2.194 / 2.412** |
| Extra 300S / spin-like | 431.0 / 424.4 | **584.3** / 497.2 | **2.337** / 1.989 |
| Extra 300S / ground¹ | 402.1 / 436.9 | **554.5** / 479.7 | **2.218** / 1.919 |
| P-51D / trim | **737.0 / 760.7** | **949.5 / 966.5** | **3.798 / 3.866** |
| P-51D / stall | **877.7 / 897.7** | **1068.6 / 1021.0** | **4.274 / 4.084** |
| P-51D / spin-like | 450.6 / 459.1 | **526.0 / 576.6** | **2.104 / 2.306** |
| P-51D / ground | **502.4 / 510.2** | **658.6 / 619.2** | **2.634 / 2.477** |
| Avanti S / stall | 409.8 / 406.5 | **541.3 / 524.3** | **2.165 / 2.097** |
| Avanti S / spin-like | 417.9 / 465.2 | **516.1 / 526.8** | **2.064 / 2.107** |
| Avanti S / ground¹ | 414.4 / 410.2 | **539.0** / 474.5 | **2.156** / 1.898 |

¹ Extra and Avanti have no loaded landing gear. These are no-contact cost probes, not ground-handling evidence. The Ugly Stik and P-51 ground fixtures both retained gear contact through their 960-tick fingerprint run.

The initial-state P-51 component profile in the two target runs puts `Slipstream.loads` at 90.1/92.4 µs per call in trim and 85.8/98.3 in stall, compared with the baseline 158.8 and 144.3 µs/call. `Dynamics.loads` fell from 261.3/277.4 to 168.7–173.0/199.6–215.3 µs/call. These are component-probe medians, not averages of a 120-tick flight. `Simulation.step()` evaluates loads four times per successful tick (the starting load plus RK4 stages 2–4). Multiplying these initial-state component numbers by four gives a rough scale only: the 120-tick timing batch evolves, so it is not an exact attribution of the full batch. The ground evaluator was left alone: active Stik/P-51 contact profiles were 11.3–12.3 and 8.8–9.8 µs/call, respectively, and no measured ground subpath explained the larger whole-tick shortfall.

The optional three-piece wake/tail path is the first native-spike candidate; a bounded GDExtension entry point could batch wake, immersion and paired tail force/moment calculations while retaining the GDScript oracle. The observed P-51 stall median requires 378–398 µs/tick of savings to reach 500, so this first spike must be measured end-to-end and cannot be presumed sufficient. If it misses, re-profile the shared `Dynamics.loads` path before expanding native scope. No extension or migration is claimed here.

This closes the H4/H5 profiling and justified cheap-optimization work with an explicit negative Gate P result. Gate P remains open until the complete fleet meets the 500 µs/tick budget and any justified near-term reserve requirement. Reproduce both target files with:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/bench_regimes.gd -- \
  --samples=16 --ticks-per-sample=120 --fingerprint-ticks=960 \
  --output="$PWD/docs/research/simulation-state/H4-H5/target-run-1.json"
```

Run it a second time with `target-run-2.json`. The baseline and target JSON contain no third-party copied material; the repository is MIT-licensed. Empirical propwash references remain in the physics code and aircraft data.

Sources: [numerics/performance investigation](../../roadmap-investigations/01-numerics-architecture-performance.md), [Aero](../../../../app/physics/aero.gd), [Slipstream](../../../../app/physics/slipstream.gd), [Dynamics](../../../../app/physics/dynamics.gd), [Simulation](../../../../app/sim/simulation.gd), [benchmark harness](../../../../app/tests/bench_regimes.gd), [baseline](baseline.json), [run 1](target-run-1.json), [run 2](target-run-2.json), [source manifest](source-manifest.json).

Suggested commit messages:

- `H4: profile all aircraft and share slipstream work; preserve sixteen 960-tick fingerprints`
- `H5: reuse local airflow; prove 10000 exact cases and measured target distributions`
