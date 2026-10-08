# E0b6p — Share propulsion work within an RK stage

2026-10-07 · **Status: comparison complete; this candidate is not adopted. E0b6p's budget remains open.**

## Result and decision

Sharing the existing thrust/torque result is numerically safe in the tested cases, but this optional-argument implementation does not establish a repeatable whole-tick gain. Keep production interfaces unchanged. The reproducible candidate and regression harness are retained for future work; no force equation, quadrature, aircraft parameter, golden flight or native production dependency changed.

The [candidate patch](native-run2/candidate.patch) computes thrust/torque once in each Dynamics evaluation when a running propeller has wake data. Propulsion and wake consume that same read-only result. Standalone calls retain their original calculation. Stopped, turbine and reverse-cutoff branches remain separate; the native binding still receives exactly two values. No cross-stage or cross-tick cache is introduced.

## Measurements

Both native runs use the unchanged decoder-optimized library, Godot 4.7.2 and the shared Linux i5-10500 host. These are workload measurements, not quiet-target or Gate P acceptance. Nine alternating pairs measure 24-tick batches after warm-up; fifteen pairs measure 64 changing-input Dynamics calls. Comparisons and trajectory hashing are outside the timed regions. Source and binary hashes, raw paired samples and complete summaries are retained in [run 1](native-run1/evidence.json) and [run 2](native-run2/evidence.json).

Positive savings mean the candidate was faster. Paired medians are not differences between independent medians.

| Smooth wake, swirl 0.4 | Direct saving, run 1 / 2 (µs/call) | Whole-tick saving, run 1 / 2 (µs/tick) | Candidate whole tick, run 1 / 2 (µs) |
| --- | ---: | ---: | ---: |
| Forward | −1.67 / 5.94 | −5.67 / 32.21 | 619.8 / 648.8 |
| Stall | −2.61 / 2.94 | −3.08 / 33.62 | 739.8 / 687.3 |
| Static | 2.11 / 3.80 | 11.12 / 25.33 | 587.5 / 871.4 |
| Powered spin | 1.94 / 5.38 | 21.79 / 29.88 | 748.6 / 732.2 |
| Reverse fade | 0.06 / 7.19 | 39.33 / 26.92 | 550.9 / 530.4 |
| Reverse cutoff | −0.94 / −2.86 | −29.96 / −10.38 | 554.2 / 387.9 |

Active smooth-wake medians remain **530–871 µs/tick**, above the 500 µs target. Reverse cutoff already avoided the duplicate calculation, so it pays the added plumbing without saving that work; both runs show slower paired medians there. Unaffected fleet cases also show substantial timing spread. P-51 trim paired savings change from −1.0 to +34.3 µs, and stall from −11.2 to +62.3 µs. These results do not support a general fleet speedup.

The [GDScript run](gdscript/evidence.json) independently verifies the production backend. Its enabled swirling medians remain 5.19–6.04 ms/tick. Removing a few redundant table lookups cannot resolve that workload. It is one GDScript timing run, not repeated performance acceptance.

## Correctness and mechanism

Each of the three retained runs passes:

- **1,216 byte-exact six-load comparisons** across 19 cases with changing velocity, rates, RPM, density, wind and transported speeds. The roster includes four aircraft, stopped propulsion, tilted legacy P-51 wake, both swirl factors, reverse fade/cutoff and axial transport. A finite downwash state is supplied only for models declaring that tail law.
- **30 flights × 241 boundaries** (initial plus 240 ticks) with exact body, auxiliary, continuous and load arrays, finite values, expected shapes and trajectory SHA-256 hashes. Sixteen fleet cases cover trim, stall, stopped spin and ground. Twelve smooth cases retain powered spin and full initial RPM; the last two cover axial transport and stopped residual decay. These are numerical/performance fixtures, not a flight-handling or calibration claim.
- [Six mechanism cases](native-run2/mechanism.json): powered smooth and legacy wake reduce thrust/torque calls from **8 to 4 per tick**. No-wash propeller remains 4, turbine 0, and stopped/no-residual 0. Stopped residual remains **8 total**: four wake-load calls plus four unchanged transport-derivative calls. The candidate's two counters separate those paths. Transport work is not implicitly shared across callbacks.
- [Two source mutations](native-run2/mutations.json) fail by assertions: restoring duplicate propulsion work is caught even though loads stay equal; changing thrust is caught by force/state comparisons. No deliberately broken app files are left in the worktree.

The second native profile records 39,020 baseline and 38,180 candidate kernel calls, with **zero refusals**. Legacy routing is expected for P-51; the count difference includes setup/trim calls through the baseline Dynamics used by both flight constructors. Both timed paths use the same native binary. [Profile and route counters](native-run2/profile.json).

[Validation](validation.json) also records four rejected report mutations, zero lint errors with the same 12 existing warnings, and a successful reproduction from a fresh `git clone --no-hardlinks --dissociate` plus the new harness. The native binary was supplied explicitly; no ignored app directory was required. The working-tree baseline [full application suite](suite-summary.log) exited 0 during concurrent landscape work; it is not an isolated acceptance result for that other track. This step makes no production app edits.

## Next bounded work

The previous attribution measured native model decoding at roughly 13–14 µs/call. The next useful experiment is a **prepared native model representation**, with explicit rebuild on model change and malformed-input/refusal tests, before considering any runtime cache. Keep stage velocity, controls, RPM, density, downwash and transported wash fresh on every call. Measure the complete adapter and fleet again; neither component savings nor this rejected candidate close Gate P. Independent E0b7 field calibration and the Stik circuit prerequisites remain open.

## Reproduce and provenance

[Runner and commands](../../../../../research/propwash/e0b6p/stage-sharing/README.md). Each report preserves its executed source hashes; [validation.json](validation.json) records the final harness hashes and rechecks older reports with the hardened comparator. The first native/GDScript profiles predate the added route-counter report; their numerical and timing checks are unchanged. The retained library SHA-256 is `e0febacfff4552e6df7ce24fb1d51bca6c389450c94f63987c7409b637d47f36`, matching the [decoder retained build](../decoder/retained/evidence.json).

Sources are the repository's Dynamics, propulsion, slipstream and wash-transport implementations, the existing provenanced aircraft/experimental fixtures, and the [previous cost attribution](../attribution/README.md). No new aerodynamic source or fitted coefficient is introduced. Project-owned code and evidence use the repository MIT license. Same-binary byte equality verifies this refactor; it does not establish cross-platform determinism or physical validity.

Commit message: `E0b6p: measure stage-local propulsion sharing; prove 1,216 exact loads and 30 exact flights; retain candidate outside production`
