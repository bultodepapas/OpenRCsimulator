# EL2a-P2 — Bounded electric event localization

2026-10-11 · Step prefix: **EL** · **Status: complete — software qualification and measured event-cost reduction. Physical and Gate P acceptance remain open.**

This step follows the 12–14 ms battery-exhaustion spikes in [EL2a-P1](../EL2a-P1/README.md). It changes event localization, not the motor, battery, propeller, body/rotor, friction or RK4 laws. Baseline app revision: `5f85109ada405071864ee1c3c5c2a97ecaa4bc84`.

## Implementation

`event_bracket.gd` proposes a scaled secant offset inside a retained sign bracket. Scaling prevents overflow when endpoint residuals have very different magnitudes. A small interior gap handles an exact-zero upper value without repeatedly proposing the endpoint. If interpolation retains more than half the bracket, the next trial bisects it. The caller keeps the actual RK trial state; no state, charge, energy or rotor momentum is interpolated. [Sources and numerical rationale](sources.md).

Both event owners retain positive lower and nonpositive upper residuals. Battery acceptance requires a bracket no wider than `1e-12 s` and an upper charge residual no larger than `1e-10 C` in magnitude. Rotor acceptance requires the same bracket width and an upper residual no larger than `1e-7 RPM`, before its momentum-preserving projection. Both requirements apply at the final iteration too. A maximum of 128 root trials and a 60 s timestep domain bound the work; malformed trials, unrepresentable interior offsets or unattainable residuals fail. Normal runtime steps remain 1/240 s.

Battery `time_error_bound_s` is the **local offset bracket width**. An absolute timestamp additionally rounds when added to the float64 session clock; it does not promise 1 ps absolute accuracy at arbitrarily large times. The tests include a million-second clock to keep that distinction explicit. A positive sub-clock-ULP exhausted remainder is still integrated locally; rejecting it solely because its absolute timestamp rounds to the same float would spuriously fail the whole tick. These local brackets apply to the computed RK trial map, not to exact physical event time or arbitrary hidden oscillatory crossings.

An event found just after battery disconnect can share its numerical boundary. The exhausted remainder now inserts such a rotor stop before the battery event and uses the battery timestamp when the recorded times differ by at most `TIME_TOL`. A resolvably later stop remains separate. This fixes a rounding-sensitive ordering case without leaking events from discarded trials.

Ordinary steps keep their arithmetic. Event endpoints can differ from the old bisection result within the declared tolerances: old crossing checkpoint bytes are not a preservation requirement. Replay under the same executable remains exact. Checkpoint/CSV schemas, aircraft input data and golden recordings are unchanged.

## Qualification

- New event tests: **2,946 checks** using independent constant and degree 2–4 time-polynomial integrals, wide scales, tiny residuals, upper-side projection, event order, deterministic replay and bounded refusal. Linear fixtures need at most **20 derivative calls**; nonlinear fixtures at most **155** in this corpus.
- Existing stop and battery-step tests: **37 + 63 checks**. The old stop test no longer requires nonzero bisection roundoff: an exact root needs no correction. Its momentum equality and one-projection checks remain.
- Five actual defects in disposable app copies: pure-bisection work regression, missing charge-residual contract, missing time bound, missing bisection safeguard and missing coincident ordering. A parse failure is never accepted as defect detection.
- Existing independent EL1d/EL2a analytic and SciPy DOP853 references are reused without changing their equations or tolerances. [Runner](../../../../research/propulsion/el2a-p2/verify_independent.py).
- Full-session timing, accepted event states and complete native replay checkpoints use the [event comparison tool](event-tool.md). Event-state tolerances are declared before measurement; no-event checkpoints must remain byte-identical.

This is software qualification on synthetic fixtures. Battery calibration, weakest-cell behavior, ESC low-voltage protection, physical glide/propeller drag and target rendered-frame acceptance remain outside this step.

## Performance

AMD Ryzen 9 5900X (12 cores / 24 logical CPUs), WSL2 Linux, pinned Godot 4.7.2 official. Six paired rounds alternate AB/BA order. No other qualification suite ran during measurement. Values are medians of **individual accepted event-containing simulation ticks**, not whole-flight batches.

| Event fixture | Baseline (µs) | Candidate (µs) | Reduction |
| --- | ---: | ---: | ---: |
| Battery exhaustion, coast, 4S | 13,727.5 | 1,440.0 | 89.5% |
| Battery exhaustion, coast, 6S | 13,560.5 | 1,509.0 | 88.9% |
| Battery exhaustion, powered, 4S | 13,208.0 | 4,394.5 | 66.7% |
| Battery exhaustion, powered, 6S | 14,104.0 | 4,162.5 | 70.5% |
| Fixed-voltage rotor stop | 10,499.0 | 2,363.0 | 77.5% |

[Raw samples and comparison](performance/comparison.json) · [source manifest](performance/source-manifest.json). All six cases retain exact seed/end checkpoint bytes across repeats of each implementation. The no-event battery control also matches across implementations. Event types and containing ticks match. The largest observed cross-version body-component difference is `3.012e-12`, rotor difference `6.831e-9 RPM`, terminal-energy difference `3.221e-10 J`, and pack-heat difference `3.917e-11 J`; remaining-charge endpoints match exactly. These are far below the predeclared component tolerances, without claiming identical crossing-root bits.

This reduces the measured spikes; it does **not** close the 500 µs physics budget. The powered 4S median still exceeds the 4,166.7 µs period of 240 Hz, and its six samples span 4,328–6,023 µs. Six samples do not establish a worst-case ceiling, target-machine performance or rendered-frame smoothness. Remeasure on the original target before Gate P acceptance.

## Retained evidence

- [Windows localization and five injected defects](localization-windows/report.json); [Linux equivalent](localization-linux/report.json). Both pass all 3,046 positive checks and identify each actual defect without accepting engine errors as a detection.
- [Independent analytic/SciPy reference report](independent.json), with original verifier equations and tolerances.
- [Eight-flight parity](fresh-flight-parity.json): eight complete 30-second, 7,201-row traces match byte-for-byte after excluding only their wall-clock creation header. Complete flight/checkpoint results and ten refinement endpoints match. Each snapshot independently passes 48 corruption controls: [baseline](flights-baseline/verified.json), [candidate](flights-candidate/verified.json).
- Complete `app/test.sh` passes for both snapshots: [baseline, 178 GDScript test programs](baseline-app.log) and [candidate, 179](candidate-app.log), plus every integration, golden-flight, model, trace, FPS and ground-contact gate in the script. Both logs contain zero engine-error lines. Nonfatal ObjectDB exit warnings remain in the broader suite (11 in the baseline, 8 in the candidate).
- [Offline tool suite](offline-tools.log): 230 tests, including eight event-report validator tests.
- [Verification manifest](verification.json): completion counts, commands, process results and evidence hashes.

[Source audit](source-audit.json) confirms 446 live source/data files match the measured snapshot after CRLF normalization; the five changed runtime/test files match raw bytes across measurement and Windows/Linux qualification. Generated UID/cache artifacts are excluded from this content audit.

[Reproduction commands](../../../../research/propulsion/el2a-p2/README.md). Complete trace CSVs can be regenerated; their normalized SHA-256 hashes are retained in the parity report. Runtime captures and imported caches are not required inputs.
