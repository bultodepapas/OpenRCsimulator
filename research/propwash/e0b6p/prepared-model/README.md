# E0b6p — Prepared native model experiment

2026-10-08 · **Status: research-only candidate; production integration and Gate P remain open.**

The candidate decodes an aircraft model once into an owned C++ value. Each load call still receives fresh state, velocity, controls, thrust/torque, density, fade, held wing lift and transported wake speeds. Decoder and kernel arithmetic come from the existing native probe; static and dynamic kernel validation remain enabled. This experiment does not include the earlier stage-sharing candidate.

```sh
python3 research/propwash/e0b6p/prepared-model/build.py --jobs 2
python3 research/propwash/e0b6p/prepared-model/run.py \
  --godot "$(app/get-godot.sh)" --output /tmp/prepared-model-run1
```

The builder uses the repository's locked native toolchain and serializes prepared-model builds. It captures source bytes before generation, checks them after compilation, and publishes a hashed library/manifest. The runner checks every manifest source, including the generated candidate, and the library before copying the app into a disposable project. Use distinct output directories. `--project /path/to/stable/app` selects the source app; `--verify-only` omits timing; `--keep-work` retains the staged project. No production app files are written.

## Lifecycle contract

- `prepare_model(model)` invalidates the old snapshot first. A valid model returns a positive generation; invalid input returns zero and leaves no active model. Generation exhaustion refuses without wrapping.
- `loads_prepared(..., generation, ...)` requires the current generation on that same backend instance. Invalid/stale calls return an empty packed array; the research adapter surfaces refusal as six NaNs for the existing simulation guard.
- `invalidate_model()` clears the snapshot without resetting the generation counter. Tokens are local to their instance; they are not globally unique handles.
- The snapshot owns all decoded values and arrays. Later edits to the caller's dictionary cannot modify it. **Callers must explicitly prepare after every model edit**, including nested edits. The adapter detects dictionary replacement and a smooth/legacy route change, but does not detect arbitrary in-place coefficient edits.
- `begin_setup()` is an explicit stateless setup mode used for trim/fixture construction. The harness prepares after setup and before timed calls/ticks. Failure in prepared mode never selects stateless smooth loads as a fallback. This harness lifecycle is not production reload/checkpoint wiring.

The runner reuses the strict stage-sharing profile roster/comparator: 1,216 changing-input Dynamics calls and 30 flights with initial plus 240 tick boundaries, compared byte for byte. Timing alternates baseline/prepared paths within one process. Preparation, fixture setup and comparisons are outside timing. Lifecycle, adapter, field-contract and GDScript-oracle checks run before timing; deliberate adapter defects and malformed-report probes must be rejected.

[Retained results and limitations](../../../../docs/research/propwash/E0b6p/prepared-model/README.md). Code and evidence use the repository MIT license. No new aerodynamic coefficient, production native dependency or schema is introduced.
