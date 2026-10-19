# P51-18 integration and cost

2026-10-12 · **Status: verification complete with baseline failures and target-performance gap recorded.** [Audit](../README.md) · [Plan](../../../P51-PLAN.md)

## Qualification

| Check | Result and evidence |
| --- | --- |
| Native Godot 4.7.2 focused checks | P-51 handling 15, envelope 15, ground 12 checks pass. Data/schema, propulsion, runway policy, all four model contracts and P-51 clearances pass. [Original results](native-focused/results.json). Catalog initially lacked imported texture resources; [import](native-import.log) and [36-check rerun](native-catalog-after-import.log) pass without engine errors. The runner now imports first. |
| Flight/ground matrix | 34 airborne + 5 ground cases × baseline/candidate × 240/480 Hz = 156 executions, all complete/finite/fault-free. [Airborne results](airborne-results.md), [ground and lifecycle results](ground-results.md). Four stricter ground reruns add 20 executions and reproduce the original JSON exactly. |
| Incomplete-ground negative control | [Injected finite-crash report](negative-ground.json) has `numerics_ok=true`, `cases_completed=false`, `completed=false`; process exits 1 as required. [Log](negative-ground.log). The injection changes only the research test's outcome after a normal case, never production state or source. |
| Fresh LF Linux suite | `app/test.sh` attempted, stopped at atmosphere-flight failure. Continuation covers every remaining unit script and downstream block. Of 208 unit scripts, 206 pass; 27/27 later integration groups pass. [226 execution records](linux-suite/results.json) include one aggregate attempt, 198 continued unit scripts and 27 integration groups. This is **not an uninterrupted green suite**. |
| Baseline attribution | Both failed scripts reproduce on unchanged P-51 baseline inputs: extreme-density Ugly Stik reset/trim (`test_atmosphere_flight.gd`, plus a dictionary access error) and time-of-day/scenery opt-in assertion (`test_time_of_day_render_update.gd`). [Direct baseline replays](baseline-triage/triage.md). No full baseline suite is claimed. |
| Compatibility and shared consumers | Before the first failure, resource import, every-app-script parse, float64/math/shader guards and offline configuration/asset checks pass. Continued coverage includes shared atmosphere/wind/propulsion/shaft/ground/crash/replay/trace/input/UI checks, golden flights, all four actual app trimmed traces, and 30/60/144 fps independence. No golden file was changed. |
| Final provenance/CI delta | [Nine final checks](final-checks/results.json) pass: P51 generator freshness, independent inventory oracle, `bash -n app/test.sh`, parameter register, known migrations, migration tests, Godot aircraft data/contract/catalog. The Linux clone received the reviewed final files only after its full suite finished; [LF hashes](final-checks/lf-source-hashes.json) identify that final subset. This separately checks the added inventory CI hook and source-text correction. |
| Final identity | [Identity bridge](final-identity.json) confirms one source-string change from the frozen flight candidate; no numerical/type/shape change outside inventory from baseline. Final tool hashes include the hardened harness and negative control. |

The frozen baseline/candidate source manifests exclude ongoing landscape, documentation and radio work. Their tests do not qualify those concurrent edits. The current P-51 physics JSON and fixture are the reviewed final versions; no parallel work was reverted or committed by this pass.

## Performance observations

Native Windows, pinned Godot 4.7.2 official, AMD Ryzen 9 5900X (12 cores / 24 logical processors). Measurements share a developer workstation, not a controlled target-hardware lab. The initial [baseline](baseline-benchmark.log) / [candidate](candidate-benchmark.log) samples suggested trim +5.56% but stalled −10.5%, so they were insufficient to attribute a regression.

After qualification processes finished, [alternating runs](performance/results.json) executed baseline → candidate → candidate → baseline. Each reported number is the best of three 2,400-tick trials. The table compares the arithmetic mean of the two reported best values, not all-trial averages or confidence intervals.

| Regime, µs per `Simulation.step()` | Baseline best values | Candidate best values | Mean change |
| --- | --- | --- | ---: |
| Trimmed flight | 592.1, 589.6 | 599.2, 617.4 | +2.95% |
| Start at 15° angle of attack | 606.1, 591.9 | 623.1, 604.6 | +2.48% |
| Idle on ground | 980.62, 1023.02 | 940.81, 967.92 | −4.74% |

The stalled benchmark starts at 15° and evolves; it does not hold that state throughout. Ground uses the audited three-contact idle fixture for ten seconds and checks final finite state, time and contact count. Fixture construction, metric reduction, session `_physics_process()` and rendering are excluded from the timed `Simulation.step()` loop, consistently with the existing physics benchmark. Raw ground trial values are retained; they range 980.62–1078.44 µs baseline and 940.81–1086.08 µs candidate. Component timings are retained in the adjacent logs.

No repeatable >5% degradation appeared in this bounded repetition. This data-only change adds no per-tick production operation; the tensor is derived at load time. The result is **not** proof of a speedup, and host variation prevents stronger performance claims. Both baseline and candidate exceed the existing 500 µs target, even for trimmed flight. Slowest-target-hardware and rendered frame-time acceptance remain open; do not report the cost gate as passed.

## Review disposition

P51-15…18 audit, bounded implementation and verification are complete. Physical acceptance remains experimental: hardware inertia/CG, installed propulsion, rigging/control response, stall/spin behavior and real-radio pilot feel lack matched-build measurements. A landing rebound makes contact-only path length rate-sensitive; the gross rollout displacement and event metrics are reported separately. Neither these numerical checks nor the inertia correction validate the entire RC aircraft.
