# AV-17-R4 native/reference parity check

Verdict: **pass** for the sampled states and short paired trajectories below. This is a research-oracle comparison on Linux x86_64 under WSL2, not an installation, production backend-selection, full-fleet, performance, Windows, or physical-validation result.

On 2026-11-10, `research/native-kernel/build.py --jobs 4` reused the up-to-date cached native binary and refreshed its temporary receipt. No app installation was performed. The checked run was:

```sh
python3 research/native-kernel/run.py --script liquid_stage_oracle.gd --states 500 --option ticks=64 --timeout 1800
```

The existing oracle loaded the temporary native extension, sampled 500 states for each of seven weather cases on each of three liquid-fuel aircraft, and ran runway, airborne spatial-weather, and fuel-exhaustion paired trajectories for each aircraft. It made 64,136 comparison records, all identical; there were zero recorded mismatches or harness failures. The comparator self-test passed. The checked Godot process exited 0, its required pass marker was present, it completed without recognized engine errors, and `run_valid` was true. The engine log contains repeated aircraft-data notices that the experimental tabulated wing polar needs provenance and aircraft-specific post-stall validation review.

For the Avanti specifically, the seven cases contained 3,500 sampled stages: 2,285 met the harness's finite-output criteria and 1,215 did not. Each weather case included 125 gear-up, 250 partial-gear, 125 gear-down, and 100 source-off inputs. The three 64-tick Avanti trajectories all completed without divergence and respectively made 256, 256, and 275 native stage calls, with 64 native context calls each. The exhaustion trajectory observed its expected fuel-exhaustion event. Trajectory tapes include the initial state, yielding 585 matching tape comparisons across all nine trajectories.

The oracle compares the recorded stage values and serialized context bit-for-bit. Spatial preview sampler object identities are excluded from serialized context comparison; their validity and sampled values are checked separately. It checks native ownership and stage/context calls on each trajectory tick. This scope does not prove parity for untested states or longer trajectories.

Identity:

- Repository HEAD: `3699b237a417413f3942736bbfa2bb229a2d6125`, with the candidate aircraft data and generator dirty in the shared working tree.
- Aircraft data SHA-256, before and after the oracle: `77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9`.
- Generator SHA-256, observed before and after: `e3d874bb71cfa603c7deb1cd2d39f5fd55374cd6f56e16b3fa3f28a4b7c8c025`. The oracle consumes the generated data, not the generator.
- Liquid-stage harness SHA-256: `7ad3b7747b92131f92bb3fd2919c173dd7534615a668f9efa722b208f5b3132a`.
- Native source-roster digest from the build receipt: `a278b5b451f71056a96e8ce2f404304440cc3cabbeb4eac1a219ecd99fdde798`.
- Native library SHA-256, before and after: `ea5631517fdb5f6af8c7af4d347bc798f981e0b6fbec997e32635eb0f11a36f7`; ABI 2.
- Godot 4.8-beta2 official Linux executable SHA-256, before and after: `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.
- Environment: Ubuntu WSL2, Linux `6.18.58.1-microsoft-standard-WSL2`, x86_64; locked GCC `13.3.0`; seed `20261027`.

The copied [result](liquid-stage-results.json) retains the full source, harness, engine and binary identities, all case counts, trajectory counters, and the embedded checked-run record. Its SHA-256 is `e19ae6e35666536e9200a8f0aa20fd9708485aaacd3887496a1979a5e32e9410`. Also retained: [checked report](checked-report.json), [engine log](engine.log), [build receipt](build-receipt.json), and [build log](build.log). The original run files remain in `tmp/native-kernel/`.
