# EL2a-P2 — Bounded electric event localization

2026-10-11 · Step prefix: **EL** · **Status: integrated qualification in progress. Physical and Gate P acceptance remain open.**

This step follows the 12–14 ms battery-exhaustion spikes in [EL2a-P1](../EL2a-P1/README.md). It changes event localization, not the motor, battery, propeller, body/rotor, friction or RK4 laws. Baseline app revision: `5f85109ada405071864ee1c3c5c2a97ecaa4bc84`.

## Implementation

`event_bracket.gd` proposes a scaled secant offset inside a retained sign bracket. Scaling prevents overflow when endpoint residuals have very different magnitudes. A small interior gap handles an exact-zero upper value without repeatedly proposing the endpoint. If interpolation retains more than half the bracket, the next trial bisects it. The caller keeps the actual RK trial state; no state, charge, energy or rotor momentum is interpolated. [Sources and numerical rationale](sources.md).

Both event owners retain positive lower and nonpositive upper residuals. Battery acceptance requires a bracket no wider than `1e-12 s` and an upper charge residual no larger than `1e-10 C` in magnitude. Rotor acceptance requires the same bracket width and an upper residual no larger than `1e-7 RPM`, before its momentum-preserving projection. Both requirements apply at the final iteration too. A maximum of 128 root trials and a 60 s timestep domain bound the work; malformed trials, unrepresentable interior offsets or unattainable residuals fail. Normal runtime steps remain 1/240 s.

Battery `time_error_bound_s` is the **local offset bracket width**. An absolute timestamp additionally rounds when added to the float64 session clock; it does not promise 1 ps absolute accuracy at arbitrarily large times. The tests include a million-second clock to keep that distinction explicit. These local brackets apply to the computed RK trial map, not to exact physical event time or arbitrary hidden oscillatory crossings.

An event found just after battery disconnect can share its numerical boundary. The exhausted remainder now inserts such a rotor stop before the battery event and uses the battery timestamp when the recorded times differ by at most `TIME_TOL`. A resolvably later stop remains separate. This fixes a rounding-sensitive ordering case without leaking events from discarded trials.

Ordinary steps keep their arithmetic. Event endpoints can differ from the old bisection result within the declared tolerances: old crossing checkpoint bytes are not a preservation requirement. Replay under the same executable remains exact. Checkpoint/CSV schemas, aircraft input data and golden recordings are unchanged.

## Qualification

- New event tests: **2,945 checks** using independent constant and degree 2–4 time-polynomial integrals, wide scales, tiny residuals, upper-side projection, event order, deterministic replay and bounded refusal. Linear fixtures need at most **20 derivative calls**; nonlinear fixtures at most **155** in this corpus.
- Existing stop and battery-step tests: **37 + 63 checks**. The old stop test no longer requires nonzero bisection roundoff: an exact root needs no correction. Its momentum equality and one-projection checks remain.
- Five actual defects in disposable app copies: pure-bisection work regression, missing charge-residual contract, missing time bound, missing bisection safeguard and missing coincident ordering. A parse failure is never accepted as defect detection.
- Existing independent EL1d/EL2a analytic and SciPy DOP853 references are reused without changing their equations or tolerances. [Runner](../../../../research/propulsion/el2a-p2/verify_independent.py).
- Full-session timing, accepted event states and complete native replay checkpoints use the [event comparison tool](event-tool.md). Event-state tolerances are declared before measurement; no-event checkpoints must remain byte-identical.

This is software qualification on synthetic fixtures. Battery calibration, weakest-cell behavior, ESC low-voltage protection, physical glide/propeller drag and target rendered-frame acceptance remain outside this step.
