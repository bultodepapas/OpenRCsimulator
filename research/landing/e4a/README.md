# E4a — Experimental full-circuit replay

**Status:** verified offline regression fixture; E4/PT2 physical and release acceptance remain open. One eastbound, 240 Hz, calm-air, wash-off Ugly Stik circuit. [Evidence](../../../docs/research/ground-contact/E4a/README.md).

```sh
python3 research/landing/e4a/verify.py --out /tmp/e4a-proof
```

Choose a new output directory. The verifier replays the **saved** [native tape](circuit.tape.gz), detects two ground-physics changes and ten tape corruptions, then runs the existing checkpoint, replay-policy and airborne-golden tests. It checks engine errors as well as exits, isolates user settings and refuses evidence if source files change during the run. A frozen checkout is recommended while other developers work. No runtime files or existing golden recordings are changed.

## What is recorded

The unmodified [E3c2a driver](../e3c2a/circuit_driver.gd) flies its closed-loop pilot once. The recorder observes `Simulation.stepped`: tick k's inputs are the exact controls used to produce state k, downstream of session trims and upstream of sampled servo/engine/contact dynamics. Replay feeds these values directly and never invokes the controller to compensate for changed physics.

`reset_on_runway()` emits two tick-zero events. The final event replaces the initial checkpoint and clears the earlier capture. The native checkpoint retains its exact model/surface fingerprint. State, previous pose, RPM, servos, wheel anchors, downwash, engine mode, inputs and loads are sampled every 60 ticks, with the final boundary always included. This fixture has no continuous wash state; nonempty continuous state is refused rather than assigned an invented tolerance.

The native `openrc-circuit-tape v1` Variant payload is gzip-compressed for storage. It preserves packed float64 arrays and integer modes; it is read with object construction disabled. It is an offline Godot fixture, not a user save format, a substitute for the active `openrc-golden v1` reader, or a version-independent exchange format. Input count, every checkpoint tick, dimensions, finite values, command bounds and binary anchor modes are checked before restoration.

The [reference field](field.reference.json) is an exact copy of `app/data/fields/default.json` at the recorded baseline. Its digest and the aircraft's exact JSON digest are retained in the tape. The wrapper passes this field explicitly so later presentation-only field edits do not invalidate the ground environment. The model/surface fingerprint must still pass the production restore path; changed aircraft JSON is refused. Source hashes in the proof identify code beyond the build's incomplete untracked-file dirty flag.

## Acceptance

A fresh session restores the authentic tick-zero checkpoint and disables live input. Each recorded input advances exactly one `sim.step()`, followed by the real session's crash detection. Every tick must complete with no crash, pause or fault. Tick zero, clock, command and mode equality are explicit; sampled body/previous/auxiliary values use the **current read-only H9 policy**, not tolerances stored in the tape. Wheel-anchor mode flags are exact. Complete sampled bytes, including loads, are additionally compared as a same-platform diagnostic; H9 has no load tolerance, so force-byte equality is not a cross-platform acceptance requirement.

The full baseline contains 28,861 steps over 120.25417 s and 483 sampled boundaries. The current Linux baseline matches every sampled byte. Other platforms and long-trajectory numerical sensitivity remain unverified; this fixture is not added to the default CI gate yet.

After successful baseline restoration, separate in-memory sensitivity probes multiply rolling resistance by 1.1 or every anchor stiffness by 2. No initial fingerprint is bypassed or edited. Each must exceed an existing H9 state tolerance: observed first sampled failures are tick 300 and tick 60 respectively. The perturbed runs stop at that evidence; they do not claim a complete mutated landing or isolated causal separation between rolling and static breakaway limits.

Disposable tape mutations cover a missing command, nonfinite command, missing final sample, wrong checkpoint tick, changed expected position/servo, altered initial state, a fractional anchor mode and malformed policy/platform metadata. They must fail for the expected reason; an unrelated engine error does not count as detection. The stored policy must match the current descriptor; the engine version must match the pinned recording. These checks validate metadata consistency, not authorship. The stored `flight` report is informational apart from completion/tick count; actual route acceptance belongs to E3c2a and the bounded checks made during recording, not a trust claim about editable report fields.

## Deliberate rerecording

```sh
python3 research/landing/e4a/verify.py --out /tmp/e4a-candidate --record
```

This writes a **candidate** under the new output directory and verifies it. It never replaces the tracked baseline automatically. Review changed trajectories and provenance before copying a deliberate new recording into the repository. The E3c2a controller is model-specific, estimated test infrastructure; its successful circuit and this replay establish regression behavior, not real-aircraft handling fidelity. Rendered circuit acceptance, propwash calibration, independent measurements and PT2 remain open.
