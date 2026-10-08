# VAL-8a — reproducible ground-run video measurements

2026-10-07 · **Status: tooling complete and verified; physical measurements remain open.**

## Scope and result

The circuit needs independent takeoff/landing observations. The available physics tasks already had active owners, so this step adds a bounded offline measurement tool under [`research/validation/ground-video/`](../../../../research/validation/ground-video/README.md). It changes no runtime, aircraft data, flight expectations or CI. Roll/stall/glide video cards and dashboard integration remain VAL-8.

The reducer accepts original capture-frame event CSVs and a campaign describing the aircraft, environment, survey and capture clock. It calculates interval time, signed displacement, net runway distance and mean along-runway ground speed. First-order standard uncertainties include per-event frame/position correlation and shared clock/length calibration. Named signed contributions retain covariance when intervals reuse an endpoint. Reports carry exact input/reducer hashes; measured campaigns additionally require the declared clip hash to match supplied video bytes. Publication is atomic and refuses input aliases.

The invented example gives **5 s, 30 m and 6 m/s**, with standard uncertainties **0.0058034951 s, 0.0734846923 m and 0.0162634560 m/s**. These are analytic fixture values, not aircraft performance. See [full result and input hashes](example-result.json).

## Verification

- **22 tests pass:** analytic values and covariance, rational FPS, origin invariance, reversed travel/correlation, zero/perfectly correlated errors, overflow/underflow, strict malformed-input rejection, measured-file identity, deterministic reports, output protection and CLI failure behavior. [Log](tests.log).
- **25,000 seeded samples:** empirical standard deviations agree with the correlated first-order model within the predeclared 2.5% sampling tolerance. Included in the 22 tests.
- **Five isolated mutations rejected by the intended assertions:** inclusive frame counting, lost clock uncertainty, lost survey-scale uncertainty, ignored within-event correlation and lost shared-event identity. The complete positive-control suite passes first. [Results](mutations.json).
- Independent Luna Max review found a warning gap when frame-pick and clock uncertainty separately stayed below 10% but jointly exceeded it. The reducer now checks combined duration uncertainty; a regression reproduces the 8% + 8% case.
- **Full `app/test.sh` passes:** 132 sections, including 104 GDScript test programs, four real-app trimmed traces and identical 30/60/144 FPS hashes for ordinary, wash-transport and swirl flights. Tested the unmodified app at `a6c1e4d4a0c90c4f6160566ffc60075450341d62` in an isolated clone with separate XDG settings and pinned Godot 4.7.2. Concurrent runtime work is excluded from this baseline. [Full log](app-test.log), [source identity and proof inventory](verification.json).

Reproduce the focused suite, mutation experiment and example with the three commands in the [tool README](../../../../research/validation/ground-video/README.md). Run `app/test.sh` for the separate simulator regression baseline. Mutations run only on temporary copies. Python standard library only; no dependency upgrades.

## Interpretation and next evidence

Capture FPS is distinct from playback FPS. Net along-runway displacement is path length only for straight motion without reversal; its mean speed cannot establish airspeed or instantaneous liftoff/touchdown speed. Use surveyed positions or a calibrated ground-plane mapping, and the same aircraft reference point at each endpoint. Camera perspective, event definitions, cadence and input authenticity remain operator responsibilities. The tool hashes but does not decode video. General cross-event survey/image correlations are unsupported and must not be declared independent without justification.

All uncertainties are k=1 local linearizations, not confidence/acceptance bands. The 10% warnings are diagnostic choices; they do not certify smaller uncertainties. No real clip or aircraft measurement was available. Next: collect an identified Stik run, preserve its original clip/survey/annotations, then compare a matching simulated run using the same event definitions and reference point.

Sources: [NIST TN 1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty), first-order covariance law; [Tracker video documentation](https://opensourcephysics.github.io/tracker-website/help/videos.html), frame timing and video analysis. Equations and fixtures are original derivations/code under the repository MIT license. No third-party video/assets are redistributed.

Ready-to-paste commit message:

```text
VAL-8a: add ground-video reduction with correlated uncertainty

Proof: 22 tests, 25,000-sample uncertainty check, five isolated mutations;
full app/test.sh on the identified isolated baseline (see evidence report).
Physical flight measurements and VAL-8 acceptance remain open.
```
