# E0b7 — field-observation preparation

2026-10-09 · **Status: Linux tooling verified; physical field checks remain open.** Owns `research/propwash/e0b7/`. No app, aircraft-data, coefficient or golden-flight changes.

E0b7 asks for nose-wheel unloading, taxi blip and takeoff swing with configuration, throttle/RPM, uncertainty and independent held-out cases. No physical observations were supplied. This step prepares the work that can be completed on Linux: an [observation reducer](../../../../research/propwash/e0b7/README.md), an explicitly [synthetic input](../../../../research/propwash/e0b7/example.synthetic.json), a [field card](FIELD-CARD.md) and regression checks registered in `research/test-tools.sh`.

The reducer retains every annotated sample and its provenance, summarizes endpoint changes and sampled extrema, and uses declared absolute error bounds. It keeps measured load distinct from visible tire clearance. Original-file hashes are verified for measured campaigns; calibration/held-out leakage through trial identity or shared source bytes is rejected. Coverage remains visible for incomplete campaigns. It fits no coefficients and always leaves physical acceptance false.

## Proof

| Check | Result and retained evidence |
| --- | --- |
| Focused reducer/CLI checks | [19 tests pass](tests.log): known-answer changes/bounds, heading branch crossing, transient extrema, clearance/load ambiguity, retained inputs, partial coverage, measured provenance, malformed data, overflow, output preservation and direct/symlink/hard-link alias protection. Fake original bytes test provenance plumbing only. |
| Deliberate faults in disposable copies | [Four mutations rejected](mutations.json): subtracting bounds, ignoring clearance error, permitting split leakage and skipping original-file hashes. The unmodified copied control passes. |
| Integrated offline suite | [214 tests in 12 programs pass](offline-tools.log), including the new E0b7 suite and existing measurement/reducer harnesses. |
| Fresh checkout | A new local clone of HEAD plus only the E0b7 tool files and suite registration passes [the same 214 tests](clean-checkout.log). The synthetic report reproduces byte-for-byte, without local caches or untracked dependencies. |
| Source identity | [Validation manifest](validation.json) records commit, tool/input hashes, platform, counts and log hashes. Tracked `app/` inputs have no changes. |

The [synthetic report](example-result.json) contains six invented runs, covering three maneuvers in both partitions. Nose load changes by −4 ± 0.2 N; nose clearance changes by 0.010 ± 0.004 m, with only the final sample's clearance interval entirely positive. Unwrapped heading 179° → 183° changes by +4 ± 0.4°. These are absolute-bound algebra checks, not measured uncertainties, aircraft performance or a model fit. Identical invented responses across the two partitions do not constitute independent physical validation.

Reproduce from the repository root:

```sh
python3 -B research/propwash/e0b7/test_reduce.py
python3 -B research/propwash/e0b7/check_mutations.py
python3 -B research/propwash/e0b7/reduce.py research/propwash/e0b7/example.synthetic.json --output /tmp/e0b7-report.json
research/test-tools.sh
```

The application was not modified, so this step uses offline regressions rather than claiming another full Godot regression run. No runtime or rendering behavior is inferred from these tests.

## Interpretation and remaining work

An annotated positive clearance can support separation at that frame; it cannot supply normal force or first-liftoff time. Heading change and lateral displacement also contain effects of steering, wind, ground contact, restraint, CG and thrust line. The reducer preserves this evidence without assigning it uniquely to propwash. Bound addition is conservative with shared errors and assumes the supplied bounds cover acquisition/annotation error; it does not assign a probability or model unsampled motion.

Collect original observations using the field card, retaining incomplete attempts and independent reserved trials. Match the real configuration, controls, initial state, reference points and timing before comparing a simulator candidate. Any inferred coefficients must be recorded as fitted/derived with identifiability limits and uncertainty, then assessed against fresh held-out cases. Production Stik wash remains disabled; enabled-path cost, deliberate enablement and any golden changes remain explicit follow-up work. This tooling does not close E0b7 or PT2 physical acceptance.

Ready-to-paste commit message:

```text
E0b7: prepare field-observation reduction and collection card

Proof: 19 focused tests, four rejected isolated mutations and 214 offline
tests pass; fresh checkout reproduces the report bytes. Retain bounds,
original hashes and calibration/held-out partitions. Physical checks,
fitting and Stik wash enablement remain open; app inputs unchanged.
```
