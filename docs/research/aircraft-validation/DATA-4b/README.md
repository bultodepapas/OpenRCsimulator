# DATA-4b — numeric boundaries and optional aircraft features

**Status:** completed, 2026-10-07. Scope: offline contract tests and one runtime diagnostic; no force-law or aircraft-data changes.

## Change

The additional corpus specifies limits independently of the schema, using the production loader's contract. It covers control throws, servo time, start speed, propulsion scalars and table ordinates, thrust offsets/angles, shaft friction, steering, breakaway factor, downwash and smooth-wake settings. Each range has two accepted endpoints and two refused outside values. The outside gap is 1e-6 of the range: deliberately larger than decimal-parser rounding, not a claim about adjacent-float behavior.

All 32 shaft/axis/normal-force/P-factor/slipstream presence combinations are checked. Shaft-free controls replace negative Cp samples with zero so they isolate axis dependencies; a separate negative case retains signed Cp without a shaft. Eight turbine ram/tilt combinations and transport/swirl controls exercise optional branches. Cross-field counterexamples remain schema-valid and runtime-invalid, including equal/reversed fade, differential throw, shaft power, throttle-map endpoint and nonzero mean wing incidence.

The throttle endpoint case lowers the final RPM by 2 while retaining strict table ordering. Setting it to zero would violate both rules and could hide a missing endpoint check; each negative fixture should isolate its intended invariant.

The incidence case exposed a real diagnostic failure: `_surfaces()` rejected the data but formatted its error with unsupported `%.2e`, emitting a Godot engine error and leaving the placeholder in the message. `%s` prints the numeric mean cleanly. Acceptance and flight calculations are unchanged. [Before](repro-before.log), [after](repro-after.log).

Eight in-memory schema mutations are now part of the existing CI contract command: three prior type/unit/width checks plus removed lower/upper limits, an inclusive limit made exclusive, a removed axis dependency and a removed zero-swirl restriction. Positive controls detect excessive restriction as well as permissive schemas.

## Evidence

- **1,691 schema/loader cases pass**, including **222 new cases**, **136 valid controls** and **11 runtime-only counterexamples**. The new cases cover 42 numeric ranges (168 endpoint/outside checks). [Case outcomes and input hashes](agreement.json), [contract log](contract.log).
- **Eight schema mutations detected**, including rejection of a valid lower endpoint by an overstrict schema. They run in `test_contract.py`, already called by CI. [Mutation evidence](mutations.json).
- The original incidence diagnostic emits an engine error; the corrected path returns a numeric diagnostic without engine errors. Both runs reject the same input. The complete corpus fails on the original diagnostic. The focused case also passes in the [shared workspace](repro-integrated.log); full-suite evidence excludes other contributors' changes.
- Godot project lint reports **zero errors and the same 12 warnings** before/after. **Full `app/test.sh` passes (137 sections)** in an isolated checkout of `b0f9e0887803869a42bef2a58723bd215648cbe1` plus this change, with separate XDG settings. Goldens, four finite trimmed starts and 30/60/144 FPS flight/wake/swirl fingerprints pass. [Full log](app-test.log), [snapshot hashes and verification](verification.json).

## Reproduce and limits

Follow the pinned environment and commands in the [tool README](../../../../research/aircraft-data/schema/README.md), then run `app/test.sh`. The incidence reproduction is the case `DATA-4b:runtime-only:incidence-nonzero-mean`; reverting the diagnostic line makes the contract command fail on the engine log even though the loader returns `ok=false`.

This is software verification, not flight-model calibration. Coupled geometry/envelope bounds, contact-stability thresholds and the complete optional-field state space remain outside this bounded corpus. DATA-4 stays open. No benchmark claim is made: the production change only executes when rejecting an invalid input.

Sources: [production loader](../../../../app/physics/aircraft_data.gd), [schema](../../../../app/data/schema/openrc-aircraft-v1.schema.json), [independent fixtures](../../../../research/aircraft-data/schema/boundary_cases.py), the four aircraft JSON files and the E0b3b smooth-wake fixture. These are repository sources under its MIT license; no new external data or dependencies were added.

Ready-to-paste commit message:

```text
DATA-4b: cover aircraft boundaries and fix incidence rejection diagnostic

Proof: 1,691 schema/loader cases, eight schema mutations, zero lint errors,
and all 137 isolated app/test.sh sections pass. Flight goldens unchanged.
```
