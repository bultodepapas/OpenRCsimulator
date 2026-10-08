# VAL-8b — Complete-roll timing without overclaiming body rate

2026-10-08 · **Status: implemented and verified with synthetic observations.** Scope: new offline Python tool and documentation. Physical observations and simulator comparison remain VAL-8.

## Change

The [validation investigation](../../roadmap-investigations/08-validation-flight-testing.md) identifies roll response as a real-aircraft evidence gap. The [new reducer](../../../../research/validation/roll-video/README.md) accepts annotated original video frames and cumulative signed complete-turn counts, with explicit capture cadence, uncertainty and provenance. It emits duration, mean period, signed turn frequency and mean completed-roll rate. It preserves shared event/clock uncertainty contributions and refuses ambiguous declarations, malformed inputs, inconsistent intervals and mismatched clip hashes. Invalid CLI runs preserve existing reports and original inputs.

The research guide's historical `p = 360*N/duration` wording was too strong. Full-turn timing averages an observed phase cycle. Without additional attitude/kinematic assumptions it is not body-axis `p`; it cannot identify a roll-decay pole. This tool does not reconstruct attitude from pixels or fit aircraft coefficients. Real count/sign/phase and capture cadence are operator assessments; a hash verifies byte identity only. Separate runtime code, data and active replay/ground-start work are untouched.

## Verification

The invented 240 fps fixture has two 600-frame turns: **2.5 s/turn, 0.4 turn/s, 144 deg/s**, and 5 s total. Shared event cancellation and common clock error are checked analytically. Tests cover opposite direction, rational cadence, frame/count origins, incomplete/invalid evidence, reversals, finite-output refusal, exact input hashes, deterministic CLI output, original-clip mismatch, output aliases and failed-report preservation. A seeded 20,000-trial timing experiment checks standard uncertainty and cross-interval covariance. No physical data or fitted reference is included.

Five source mutations run only on temporary copies: inclusive frame counts, lost direction, wrong shared-event sign, omitted clock error and bypassed clip identity. Each must fail its intended assertion; the unmodified copied control must pass. [Verification manifest](verification.json): **23 tests, 20,000 seeded trials and five rejected mutations**, repeated in a fresh git clone with only the owned tool files overlaid. The CLI output is byte-identical across the working tree and fresh clone. [Tests](tests.log) · [Mutation assertions](mutations.json) · [Fresh-clone tests](fresh-clone-tests.log) · [Fresh-clone mutations](fresh-clone-mutations.json) · [Synthetic report](example-result.json). The two-turn fixture reports standard uncertainty 0.1671406593 deg/s for its 144 deg/s mean rate; these invented uncertainties are not measurement recommendations.

A Luna Max subagent independently reviewed the formulas, parser and measurement definition. No mathematical blocker was found; its requests to distinguish pure calculations from provenance-bearing CLI reports and to define viewpoint ambiguity within the same-phase declaration are incorporated. The initial exact-equality assertion on `144*0.001` was corrected to a tight numerical tolerance; production arithmetic was unchanged.

## Sources and limits

- [NIST TN 1297, Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty): first-order sensitivity/covariance propagation and standard uncertainty. Signed contribution identities in this tool follow directly by differentiation of the timing equations.
- [Kinovea, Measuring time](https://www.kinovea.org/help/en/measurement/time.html): original capture cadence must be distinguished from playback cadence for slow-motion clips.

Sources consulted 2026-10-08; linked, not redistributed. Count/sign errors and perspective ambiguity are not Gaussian timing noise. Variable cadence, unmodeled correlated phase-pick bias and uncertain complete-turn counts remain unsupported. Timing alone cannot close aircraft roll-response acceptance or establish control derivatives. No full Godot rerun is claimed: this task changes only offline code and documentation.

Ready-to-paste commit message:

```text
VAL-8b: reduce complete-roll video timing with shared uncertainty

Proof: 23 analytic/contract/CLI tests, 20,000 seeded trials and five
rejected source mutations; fresh-clone tests and byte-identical output.
Correct the research guide: cycle-average roll timing is not body p
or roll damping. Runtime/data unchanged; physical VAL-8 remains open.
```
