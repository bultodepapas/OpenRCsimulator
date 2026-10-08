# G1b1 — Recorded propeller operating-range diagnostics

2026-10-08 · **Status: implemented and verified, offline scope complete.** G1b online counters, G1a matched operating-range measurements and physical propeller validation remain open. Owner: Codex propeller-range agent. No application or aircraft-data edits.

## Result

[Tool and reproduction](../../../../research/propulsion/range-audit/README.md). The auditor binds v3 trace metadata v2 to exact aircraft input bytes and reconstructs Ct/Cp lookup conditions using previous-state velocity with current auxiliary RPM. It rejects unsupported frames/timing, discontinuous or nonfinite rows and absent still-air acknowledgement. Per-table diagnostics separate extrapolation, reverse-flow clamping, stopped propellers, documented J gaps, source-region exclusions and unknown RPM coverage.

Six fixtures use the real session, recorder and propulsion model. The initial sample is excluded from counts. Ct and Cp have the same classification in these cases:

| Fixture | Flown queries | Active J range | Diagnostic |
| --- | ---: | --- | --- |
| Stik trimmed | 240 | 0.569085 | Inside table; source RPM coverage unknown |
| Stik 40 m/s dive, idle | 480 | 1.667145–2.812148 | All 480 exceed the last table knot, J=0.788 |
| Stik full power | 240 | 0.264112–0.402718 | 171 queries in the documented `0 < J < 0.373` gap |
| Stik stopped glide | 240 | undefined | All 240 stopped; no fictitious J=0 lookup |
| Extra trimmed | 240 | 0.578905 | Inside table; source coverage not supplied |
| P-51 trimmed | 240 | 0.639981 | Inside table; source coverage not supplied |

[Machine-readable verification](verification.json) records source/evidence hashes, all counts and the six traces. Reconstructed queries match 1,680 direct engine calls with maximum J difference `3.514e-11` from CSV rounding (acceptance `1e-8`). [Unit tests](unit.log): 20 pass. Three isolated mutations fail assertions: [RPM mistaken for revolutions/s](mutation-rpm-as-rps.log), [current velocity used for prior-state loads](mutation-wrong-state-timing.log), [gap endpoints incorrectly excluded](mutation-inclusive-gap.log). Existing [propulsion tests](test_propulsion.log) pass 16 checks; [metadata tests](test_trace_metadata.log) pass 171. [Flight log](flights.log) has no engine errors. No broad app-suite rerun was needed for this offline-only change.

Independent review caught a fixture defect before acceptance: assigning `session.commands.throttle` alone leaves synchronous `sim.step()` using old sampled inputs. Both powered fixtures now sample through `session._inputs()` before reset, and verification requires the commanded 0/1 throttle on every row plus constant target RPM. Fixture metadata explicitly describes the overrides. Earlier prototype traces were replaced with these corrected runs.

Final review found no blockers. Reverse-flow source coverage and contradictory gap/region declarations have explicit regressions. [Static lint](lint.json) reports zero errors and the same 12 pre-existing warnings; source/evidence hashes and local documentation links match at completion.

## Evidence limits and source provenance

The supplied [coverage manifest](../../../../research/propulsion/range-audit/stik-coverage.json) keeps the UIUC APC Sport 11×6 static campaign separate from its nominal 6,000 RPM tunnel run; the simulator uses a 12×6 Sport. The [static source](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_static_rd0488.txt) spans 1,752–6,259 RPM at J=0. The [tunnel source](https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_rd0495_6000.txt) spans J=0.373–0.788 without an RPM column. Both were fetched and byte-hashed on 2026-10-08; only factual ranges, URLs and hashes are retained. The static RPM extent does not establish dynamic-J support. No fictitious RPM tolerance is inferred from the tunnel filename.

This verifies classification of simulator lookup conditions, not propeller performance, physical-flight realism, or a four-quadrant model. A clear table flag is not evidence of validation. Source envelopes are exclusions, not confidence intervals. Still air and an unmodified loaded diameter/shaft/table configuration are required assumptions; v3 cannot prove them from trace columns alone. Rounded CSV values can change classification near a boundary. Internal RK-stage and shaft-engine torque queries are not counted; later G1b integration must instrument those explicitly if they are needed.

The review and source evidence support leaving propulsion coefficients unchanged. Obtain matched propeller/RPM data under G1a/VAL-7 before using these diagnostics to justify tuning.

Suggested commit message:

```text
G1b1: audit recorded Ct/Cp operating range with exact input identity

Proof: 20 unit/CLI tests, three rejected isolated mutations, 1,680
engine-query comparisons, six session flights and 187 existing checks.
Idle dive: 480/480 above-table; full-power: 171/240 in source J gap.
No force/data changes; online counters and physical validation stay open.
```
