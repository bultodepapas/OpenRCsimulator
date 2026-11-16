# AC-12 servo stage-time ablation

Owner: AC-12 / AC-CV-06. Preregistered on 2026-11-16 after the
[current-source audit](AC-12-audit-2026-11-16.md), before either experimental flight.
This is a private source-hashed experiment, not a production servo law or qualification.
Registration order is recorded in the retained agent-session chronology. Checked receipts
bind executable inputs and outputs, not an independently timestamped registration of this prose.

Question: how much does evaluating the existing slew law at RK stage time change the
C01 pitch and C15 roll tapes, while preserving their accepted servo endpoints? Use only
their retained full six-second 240 Hz `.orfl` baselines and exact compiled record bytes.
Their original complete replays already passed. Do not retrim, regenerate inputs, change
packages, modify wake evolution, adopt floors or unlock flight.

Prepare two private source copies from the original frozen audit snapshot. Their source
files differ only in one hold/ramp constant in `sim/flight_session.gd`. Both source hashes
must differ from the original solver; use the existing explicit candidate replay with
the original aircraft JSON and require `solver_changed=true`, reference backend, complete
ticks 0 through 1440 and 1441 rows. Retain all source/engine/input/output hashes.

Capture immutable start, target, rate, tick, start time, timestep and precomputed end servo
values at the tick hook. Only the coupled force evaluator may receive temporary stage aux.
For an interior stage use the existing rate-limit law at absolute stage time minus tick
start; at the endpoint use the precomputed endpoint bits. Never change accepted aux.
Clear scratch on accepted/rejected steps, reset and restore through the existing tick-fact
lifecycle. Setup/out-of-tick calls use the historical endpoint path.

Domain: explicit reference backend with no native helper, electric coupled shaft and dynamic
battery, empty normalized landing-gear data, no flaps, no soft hull contacts, no failure
runtime, calm weather and the original airborne tapes. This restriction is an experiment
guard, not a newly accepted Creator domain.

Before any ramp flight, the hold control must reproduce every original packed numeric row
using the existing replay disagreement comparator, including tick zero, loads, inputs,
body/aux/continuous/modes, air and mass. Also compare CSV bytes. Independently verify the
restored simulation checkpoint, aircraft model, mass/inertia/gravity, weather, field,
collision/lake and backend against the original. Reject input interventions and live kernel
events; input-log stop metadata is separate. A failure stops the comparison and remains
evidence; never silently substitute a looser control.

Check rising, falling, unchanged and early-arrival stage values at start/mid/end; endpoint
bits must match the original slew result. Verify activation at actual command edges and
scratch invalidation after restore and a deliberately rejected stage. Stage queries may
repeat/revisit times and cannot depend on call order. Bound observational diagnostics.

Only after both hold controls pass, run ramp on those identical logs. Preserve their CSVs
and reports. Compare post-step rows 1..1440 with the retained original 3840 Hz traces using
all seven existing metrics and the finer run's charge denominator. That is a comparison
against a numerical reference, not an exact solution, convergence proof or physical
validation. A later production change would need an explicit immutable generic context,
versioned law/checkpoint handling, native support or fail-closed reference selection, and
affected consumer tests before a new domain-wide campaign.

## Controlled comparison results

Both final checked jobs passed on ANGELA_AIR with the pinned executable SHA-256
`2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80`:
hold `a400e987d63f4fdca88e43f642d31efd` (47 checks) and ramp
`7e828f01eadf4e839bb6f58d6d671683` (45 checks), zero failures/errors/warnings.
The final hold reproduced every recorded packed numeric row and both 1440-row audit
telemetry files byte for byte. Both modes checked the actual reader session's full
initial simulation checkpoint, model and environment, all 1441 committed servo rows,
input interventions and live kernel events. Ramp activation was observed on the correct
axis at the original tick-120 command edge. Scratch invalidation after a rejected stage
and restore passed. Candidate reports are complete, mode `candidate`, `solver_changed=true`.

Actual frozen source inventories differ only in the hold/ramp constant. Session hashes:
`2618b6ca66fa8efbbb035f49ab39703f26e21d5070707d6e0a79fbbb48eb0de5` (hold) and
`e999ca0791f55c47a442eec6a291f487cb81c33258e88b5bf88cc5dcfa4dda20` (ramp).
Both use reader `b18830e5d2e111f23f8ab36e9f780d608a1d179d23701f87f25d0d3cb61dbebc`.
Their standard source-tree solver fingerprints are
`d1518527a4ab1d0ad9839a54b56d725591f63d23ef9fb7119ec0614ec807546c` (hold) and
`64d7c6721eb917ffae4aa3fc26f9f49d94230d8bfb8fa9994c9939c7aafa293a` (ramp).
Final input archives are `7edc7615894d2b768941abff77a0c4c1b4249bd6a39880674f275204afab441d`
and `daf4f6e90a626b039144347dd59030a782f6b27fe7fa35061831244230c07e8d` respectively.
All seven original output files per mode are hash-verified against the checked-log summary
digest and retained outside Git under the audit's private D: evidence root, in `servo-hold/`
and `servo-ramp/`. Full source archives, patches, preparation scripts, collection receipts,
frozen-source comparison and `servo-comparison.json` remain there. Preliminary controls
`bf3e7e11c1094664a8fbe7a637a35e81` and `6a944163350047bfb9e6276786999d7a` passed but were
superseded to add actual-session and direct-telemetry checks; their separate artifacts remain.

Maximum differences against the **original held-servo 3840 Hz numerical reference**:

| Metric | C01 hold 240 | C01 ramp 240 | C15 hold 240 | C15 ramp 240 |
| --- | --- | --- | --- | --- |
| Position m | 0.00551193 | 0.00041105 | 0.01687263 | 0.01185538 |
| Attitude degrees | 0.06288433 | 0.00463121 | 0.23810543 | 0.03051640 |
| Angular rate degrees/s | 0.79390412 | 0.05392025 | 6.26396622 | 0.43794352 |
| Airspeed m/s | 0.00400921 | 0.00029759 | 0.00326040 | 0.00127819 |
| Shaft rpm | 0.11672655 | 0.00901691 | 0.98394352 | 0.07736805 |
| Current A | 0.00064252 | 0.00004963 | 0.00611222 | 0.00048001 |
| Charge fraction | 1.512315e-5 | 4.691174e-7 | 6.785568e-5 | 3.232161e-5 |

The independent reducer uses the same physical metrics and finer-reference charge
denominator; its stable normalized quaternion chord-angle form was cross-checked against
all 20 original audit pairs. The 3840 Hz trajectory still contains sampled-law and numerical
error. These differences support stage-time servo evaluation as a substantial contributor
to the selected angular-rate discrepancy; they do not prove the candidate's order, its
remaining error, a complete causal decomposition, G05 or physical realism.

## Follow-up refinement preregistration

Before further candidate flights, fix C01/pitch_doublet and C15/roll_doublet at the audit's
unchanged sequence 240/480/960/960/1920/1920/3840 Hz, six seconds and common 240 Hz samples.
Reuse the final strict audit driver and its inherited, unchanged rule. Use the same private
ramp physics source; add only selecting research entrypoints and the tested measurement
driver. Record its mode explicitly in source context, require all usual identity/sample/
clock checks, repeats, complete exact replay of the candidate's own baseline, and preserve
all artifacts. This measures refinement of the same private candidate; it does not authorize
production integration or a new domain. A numerical failure remains a failure. No threshold,
floor, bound or extra case is selected after observing these follow-up flights.

## Follow-up results and integration limit

The two checked refinement jobs passed operationally on ANGELA_AIR:
`570765b4a50948c3835b424f1b810605` (C01) and `919b1128950f4409b4dcc41ef759ab4f` (C15),
zero errors/warnings. All 14 flights completed with valid clocks, initial/environment/input
comparability, 14 finite trace files and four byte-identical same-rate repeats. Both new
240 Hz baselines replayed exactly for all 1441 rows with `solver_changed=false` on their
own private candidate source. The reader's additional telemetry files equal those live
240 Hz traces byte for byte. All eight refinement pairs were independently recomputed.

| Cell | Original hold angular-rate estimate degrees/s | Ramp angular-rate estimate degrees/s | Ramp order from first three levels | Ramp inherited-rule result |
| --- | --- | --- | --- | --- |
| C01 / pitch_doublet | 0.84833901 | 0.00327695 | 2.155 | Fail: charge fraction |
| C15 / roll_doublet | 6.70185636 | 0.05678753 | 1.944 | Pass: all seven metrics |

The C01 charge differences are `4.606518391e-8` (240/480) and `4.426002919e-7`
(480/960), ratio `9.608130357`; the unchanged rule refuses them despite their small size
relative to the `0.002` tolerance. Its extrapolated-error sentinel remains `-1`.
Neither a new noise floor nor an absolute-error exception is adopted. Improving the body-rate
counterexample therefore **does not close G05**. The full 17-case domain was not tested for
this candidate, and the two-cell follow-up itself does not pass as a set.

The refinement archive is
`5b7258500acfc1b45f2d3eae1127391b8bb1ad21ded169a2293722ef0603ffc4`.
Its physics/sim/failure source hashes match the ramp comparison source exactly; only the
tested strict audit driver, its contract tests and research entrypoints differ. Candidate mode is explicitly
recorded as `ramp` in each source context. The complete outputs, input archives, extra
telemetry parity checks and independent metric receipts are retained in
`servo-ramp-refinement/` under the same private evidence root. The original audit and its
failed domain verdict remain unchanged. No scientific trace or third-party image enters Git.

Do not promote the private scratch patch directly into production. It deliberately lacks
a public versioned actuator selection and checkpoint contract. A future implementation
needs an explicit generic immutable joint-stage context, including before/after sampled
values and clock/input identity, with a boundary form for reset. The existing returned
`VehicleModel.stage_context` is an output to the substep policy, not that input contract;
framed-sampled-v1 must retain its existing meaning. This is an unimplemented proposal.

An optional explicit servo-integrator selector would need synchronized runtime contract,
generated schema, loader and versioned Creator opt-in. Absence must preserve old model/config
bytes and saved drafts. The selected law/protocol must be pinned in checkpoint and trace
identity; ordinary restore cannot silently reinterpret old arrays. Any candidate-only
migration must check the named law pair, units, layout and timestep and retain the original
physical frame. Native admission must refuse unsupported laws before recording, with
reference selection explicit. These changes need their own implementation/review and
affected kernel, replay, native, lifecycle and historical-draft tests. The present work
changes no production physics, stock goldens or ClearView flight/publication gate.
