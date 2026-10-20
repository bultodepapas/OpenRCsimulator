# AS-13 accepted contact observations

**Date:** 2026-10-13. **Scope:** a common contact observation and checkpoint boundary for the existing aircraft. Physical laws, numerical operation order and calibration remain unchanged. The [aircraft contract](../../../AIRCRAFT_CONTRACT.md#contact-observations-and-checkpoints) defines the public API; the [active plan](../../../plans/aircraft-standardization.md) retains the remaining identity/section and capability gates.

## Delivered

- `AircraftContactEvents` normalizes hull, gear-limit, scenery, lake and single-propeller observations into plain versioned records. Measurements remain float64. Unknown references, duplicate contacts, nonfinite data, incomplete strikes and unresolved/contradictory scenery responses are rejected.
- `FlightSession` retains only the latest accepted tick's events, ongoing hull IDs and the flight's strike latch. Hull entry/persistence/exit is explicit; terminal hull decisions replace that point's observation. `contact_events_changed` notifies readers after accepted commit and for decisions between integration steps, so a strike cannot disappear unnoticed at the next step.
- Swept collision filtering stages crash/scenery/lake presentation and publishes it after `Simulation` accepts the full step. Rejected filters and failed continuous-state projections cannot publish phantom impacts or damage. Water engine-stop modes remain inside the simulation transaction.
- Checkpoints retain their existing physics version and add a strict, separately versioned contact state. Old checkpoints seed existing contacts without inventing historical events. Malformed new records fail before mutation. Failed reloads restore accepted observations and broken-propeller state. Transient crash/wreck presentation is still cleared on checkpoint replay, as before.
- The conformance runner includes the new event/session suites and existing collision, damage, lake and crash tests. A reusable contact probe compares complete per-tick physical state/load fingerprints through seven ground/scenery/water fixtures.

## Verification

Native Windows, Godot `4.7.2.stable.official.ed1daf0bf`. This was a shared working tree with concurrent physical/model/editor work. The before/after copies isolate only `sim/flight_session.gd` and the new `sim/aircraft_contact_events.gd`; [parity report](parity.json) records source SHA-256 values and exact comparison results. No golden flight was rerecorded.

| Check | Evidence |
| --- | --- |
| Event data contract | 45 checks: lifecycle, owned arrays, available kinematics, support/probe references, swept timing, strict strikes, duplicate/unknown/nonfinite mutations and unresolved response rejection |
| Session integration | 63 checks: tick-zero/touching reset, ongoing/ended contacts, exact event replay, atomic invalid restore, accepted observer order, rejected filters, final projection failure, failed reload, propeller latch/notification, water engine rollback and foreign environment rejection |
| Fleet parity | Seven configurations × soft/terminal policy: all 14 complete-state/load trajectories and checkpoint replays match exactly. [Before](baseline-fleet.json), [after](candidate-fleet.json) |
| Contact parity | Seven fixtures match exactly: legacy/soft wingtip brushes, nose impact, Avanti belly slide, nonterminal/terminal scenery and water entry. [Before](baseline-contacts.json), [after](candidate-contacts.json) |

The current focused-suite commands and logs are retained in [integration verification](integration/verification.json). The final notification changes and contact probe were checked separately in [final reruns](final-reruns.json), including the 63-check session suite. [Delivery identity](delivery.json) records the tested sources and final disposition. The first authoring run found an obsolete Timber r1 visual diameter expectation (`0.280642 m`) after the concurrent r2 source moved to a measured radius of `0.14032 m`; the expectation now uses r2's `0.28064 m` diameter. The [original failure](models-python-before.log) and [passing rerun](models-python-rerun.log) are retained. No physical propeller parameter was changed for that correction.

This continuation does not claim a complete `app/test.sh` run, new package/visual acceptance, target-machine performance qualification or physical validation. The whole-app parse attempt was stopped during redundant broad checks in the busy shared tree; changed runtime scripts compile and run in the focused suites. Previous package and full-parse evidence remains dated under [AS-06–14](../AS-06-14/README.md).

## Reproduce

```text
python research/aircraft-standardization/conformance.py --godot <pinned-godot> --out <output>
```

Use `--baseline <fleet.json>` and `--contact-baseline <contacts.json>` only with the same platform/engine and matching physical sources. `--parse-all` and `--package` retain their broader checks. Run the contact probe alone with:

```text
<pinned-godot> --headless --path app --audio-driver Dummy --script <repo>/research/aircraft-standardization/contact_probe.gd -- <contacts.json>
```

Current hull IDs remain ordered compatibility IDs, not durable authoring identities. Mapping probes to detachable visual sections, the common Blender builder's explicit gear-pivot bindings and a second distinct Blender delivery remain open. This change does not enable flaps, multiple propulsion installations or new contact response laws.
