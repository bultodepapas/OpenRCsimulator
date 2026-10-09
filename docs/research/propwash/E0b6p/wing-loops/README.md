# E0b6p — Wing-loop invariant experiment

2026-10-09 · **Status: experiment complete; combined candidate not adopted. E0b6p and Gate P remain open.**

The [aero/simulation profile](../dynamics-cost/README.md) selected a small GDScript optimization: move invariant dictionary reads out of the wing-lift loop and compute an induced-map row offset once per strip. The candidate preserves numerical outputs, but these Linux measurements do not establish a reliable whole-flight improvement. Production remains unchanged.

## Change and decision

The [candidate patch](prepared1/candidate.patch) changes only `Aero.wing_lift_coefficient` and the map loop in `_local_loads`. It caches per-call aileron values, incidence-array presence and coefficients, and replaces repeated integer row multiplication with `row_start`. There is no cache across calls, no coefficient tuning, and no change to floating-point expressions, strip count or summation order.

**Do not adopt the combined change.** The wing-lift helper improves in all three runs, but the local-load helper does not. Whole-flight results are mixed across aircraft and wake cases, including repeated slower static-swirl samples. These results justify separating the two transformations, not assuming that fewer source-level operations make every path faster.

Next bounded experiment: isolate the dictionary-read hoisting in `wing_lift_coefficient`, leaving both induced-map loops unchanged. Compare it with the same frozen baseline and fixtures before considering adoption. The present experiment does not predict that variant's performance or close the whole-tick budget.

## Measurements

Godot 4.7.2, shared Linux i5-10500 host. Runs were sequential: two with independent baseline/candidate prepared-wake adapters, then one with the GDScript backend. Prepared run 2 stages the app from a fresh clone at `4b92dd0`; all three runs use the same 617 application inputs. Source code, generated scripts, the prepared binary and build inputs are hashed and checked for changes.

The manufactured sweep times 1,024 calls per sample, one warmup pair and nine measured alternating pairs. Positive paired saving means the candidate is faster. These are medians of paired differences, so they need not equal the difference between two separately computed medians.

| Helper | Prepared run 1 saving (µs/call) | Prepared run 2 | GDScript run |
| --- | ---: | ---: | ---: |
| Wing-lift coefficient | +0.797 | +1.483 | +0.735 |
| Local surface loads | −0.077 | −0.231 | −1.985 |

The helper code is GDScript in all three runs; “prepared” describes the subsequent whole-flight wake backend, not native execution of the aero helper. Half the manufactured requests use the coupled map and half use the fallback, with incidence absent/present. The local-load measurements do not isolate a VM-level cause for the observed cost.

Whole-flight samples use 24 evolving ticks, one warmup pair and nine measured alternating pairs. Positive paired medians occur in **14/30, 17/30 and 19/30** cases respectively; this count is descriptive, not a statistical acceptance rule.

| Selected flight | Prepared run 1 saving (µs/tick) | Prepared run 2 | GDScript run |
| --- | ---: | ---: | ---: |
| Stik trim | +19.54 | +13.58 | −3.96 |
| Stik stall | +12.67 | +8.50 | +3.00 |
| Extra trim | −5.75 | −4.17 | −0.25 |
| Avanti stall | −21.04 | +6.83 | −58.12 |
| Smooth forward, swirl 0.4 | −4.58 | −0.12 | −25.83 |
| Smooth stall, swirl 0.4 | −8.21 | +2.46 | +53.71 |
| Smooth static, swirl 0.4 | −21.00 | −24.54 | −2.62 |
| Smooth spin, swirl 0.4 | +19.42 | +11.04 | +32.33 |

All cases, raw timing pairs, medians and hashes are retained in [prepared run 1](prepared1/evidence.json), [prepared run 2](prepared2/evidence.json) and [GDScript run](gd1/evidence.json). The underlying `profile.json` and `verify.json` files in each folder are the original engine reports. Shared-host variance and the prepared adapters' symmetric route counters limit interpretation. No individual-tick percentile, target-budget acceptance or portable speedup is claimed.

## Verification

Each run passes:

- **1,024 manufactured requests, 5,120 comparisons and 25,600 scalar values**, checked for finite values and exact original float64 bytes. Four aircraft × coupled/uncoupled maps × incidence absent/present × 64 state/control settings exercise wing lift, local loads and blended loads, with instantaneous/held downwash where supported.
- **1,216 direct load comparisons and 30 exact flight trajectories**, each with the initial boundary plus 240 steps: **7,230 boundaries**. Coverage includes all four aircraft in trim/stall/spin/ground states; twelve smooth-wake cases; axial transport; and stopped residual wash. State, auxiliary, continuous and load buffers are compared and hashed. Comparisons are within each backend; they are not a claim of bit identity between native and GDScript wake implementations.
- Two deliberately wrong candidates are rejected after complete sweeps: shifting the induced-map column causes **258 failed comparisons**, and reversing the cached left-aileron sign causes **1,016**. The runner requires assertion failures and differing hashes, rejects engine errors as proof, and restores the candidate afterward.
- Prepared runs reject **ten corrupted reports** each; the GDScript run rejects **seven**. These cover missing coverage, changed hashes, nonfinite timing, changed workload and, for prepared runs, setup fallback/refusal and missing route details. Each prepared adapter has 49 explicit preparations; measured setup/refusal counts are zero, and active smooth cases must dispatch prepared calls in both paths.

The two prepared runs also have identical baseline trajectory hashes. All retained reports can be reduced again with the checked-in runner.

The unmodified production app passes **`app/test.sh`: 153 sections, including 125 test scripts**, model contracts, goldens, live traces and frame-rate independence. The candidate was not installed into production, so this suite result is not presented as a full candidate-app run. [Validation and artifact hashes](validation.json) and the [compressed full-suite log](baseline-app-tests.log.gz) retain the proof. Source lint reports zero errors and the same 12 existing warnings; the GDScript disposable probe adds one guarded optional native-path warning inherited from the reused probe. Engine execution reports no script errors.

## Reproduction and limits

[Runner, commands and baseline override](../../../../../research/propwash/e0b6p/wing-loops/README.md). `candidate.py` generates the reviewable change; the runner stages both dependency paths, compares them in the same process and never edits the source app. Candidate and source hashes are retained in every report. Aircraft data, goldens and production code remain unchanged.

The finite synthetic sweeps and replay checks prove equivalence for their coverage, not real-airframe calibration. The host timings do not qualify native Windows/macOS execution, production model lifecycle ownership or player rendering. Stik propwash remains off, and pilot/airframe acceptance remains open.

Ready-to-paste commit message: `E0b6p: test wing-loop hoisting without adoption; proof: three exact 30-flight runs, 25,600-scalar sweeps, two rejected aero mutations and 153 app checks`
