# EL2a — Powered exhaustion through the flight session

2026-10-11 · **Status: eight synthetic event cases and exact observation/control parity pass; event timing remains a performance concern. Step prefix: EL.**

This complements the auxiliary-only analytic event oracle with depletion while the motor draws positive current. Each 4S/6S fixture starts from a native trimmed checkpoint, commands duty 1 and substitutes a small remaining charge: 0.20 C for 4S, 0.12 C for 6S. Energy/heat accumulators start at zero for this local experiment. The checkpoint is valid, but this is an artificial near-empty boundary, not a measured discharge history. The session's consumed-charge field still refers to its configured 95% initial charge; the event-local energy budget starts at the substituted charge.

The actual near-empty pre-event points draw 50.239/27.339 A at the motor and 50.439/27.489 A at the pack. `loaded_trim_point` and `pre_event_point` are separate observations in the evidence. Each real session advances to the same 50 ms endpoint at 120/240/480/960 Hz. All accepted states remain finite, charge reaches exactly zero, all pack loads disconnect, energy and heat are positive, and the rotor continues coasting. Each run records exactly one exhaustion event.

The independent chemical budget is the exact integral of the fixture's two-knot linear OCV curve:

`Wchem = Vmin Q0 + (Vmax − Vmin) Q0²/(2 Capacity_C)`.

`Wchem − Eterminal − Hpack` stays within 4.48e−10 J against a 1e−7 J bound. Event times are approximately 3.980718 ms (4S) and 4.397640 ms (6S); the numerical root brackets are below 1e−12 s and charge residuals below 1e−10 C. These brackets bound root localization within the numerical trajectory, not physical time uncertainty.

Against the 960 Hz endpoint, the 120 Hz cases differ by at most 2.17e−6 RPM, 2.16e−7 rad/s in body rates, 1.87e−8 m/s in body velocity and 2.77e−10 J in energy/heat. These are refinement diagnostics across a switched boundary; 960 Hz is not an exact whole-aircraft oracle. [States, chemistry and refinement](powered-evidence.json)

## Observation control

The runner creates fresh copies of the app without `.godot` or captures. One copy is unmodified; the other applies the [small observation patch](../../../../research/propulsion/el2/powered/instrument-flight-session.patch), which times the existing callback and copies its returned event list. It returns the original state. Both copies run the same probe from identical checkpoint blobs. All eight complete 1,436-byte endpoint checkpoints match byte for byte; the only differing app source is the patched session script. [Parity and checkpoint hashes](powered-parity.json), [source/tool hashes](powered-source.json)

The report records the whole exhaustion tick in both copies and the event callback in the observed copy. These timings were collected while other checks ran and are diagnostic; they expose a tens-of-milliseconds event spike that ordinary warmed batches do not exercise. They do not close the 500 µs/tick performance gate. See the [whole-tick cost record](README.md#performance).

Reproduce from the repository root (the default creates a new temporary output directory):

```sh
python3 research/propulsion/el2/powered/reproduce_and_compare.py --godot "$(app/get-godot.sh)"
```

The runner refuses nonempty explicit output directories, bounds subprocess time, rejects Godot errors, checks complete native-byte parity and then runs the independent chemistry verifier. It never patches the live app. This evidence does not establish real-pack LVC, brownout, temperature, endurance or aircraft calibration.
