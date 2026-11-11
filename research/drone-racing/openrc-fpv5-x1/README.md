# openrc-fpv5 x1: experimental product candidate (DR-10/11/13)

`derive.py` turns `sources.json` into the strict `openrc-multirotor v1` document
`app/data/multirotors/openrc-fpv5-x1.json`, read by `app/physics/multirotor_data.gd`.

The build is family `openrc-fpv5`, variant `openrc-fpv5-f50-2150-f5146-6s-x1`: an F50 2150 KV motor, a T-Motor
F5146 prop (5.1 in = 129.54 mm), a 6S 1300 mAh pack and the 205.32 mm square-X hub geometry of the downloaded OpenRacer frame (DR-29). `x1` is the estimate
revision. Its status is `experimental-estimates`. It is **not** a measured or validated aircraft. It stays separate
from the lab fixture `Plant.research_quad()` and any published research-aircraft reproduction (decision D-DR-C,
[FPV/01](../../../FPV/01_FPV_MASTER_PLAN.md)).

## Provenance classes

Each output quantity is `{value, unit, kind, source}`. `kind` is the provenance class, and `source` begins with it:

| Class | Meaning here |
| --- | --- |
| `manufacturer-reported` | The F50/F5146 static rows, KV designation and prop diameter ([FPV/03 §6](../../../FPV/03_FLIGHT_DYNAMICS_AND_RESEARCH.md)). They are vendor numbers, not measurements by this project. |
| `derived` | Computed by `derive.py` from named inputs: k_T/k_Q fit, R, Kv in rad/s/V, mass/CG/inertia, CG-relative hubs, feet, hull and camera, contact constants and pack OCV. |
| `estimated` | Engineering estimate, with the reasoning stated in `sources.json`. This covers geometry, the mass inventory, the battery, the controller starting gains, contacts and camera. |
| `borrowed` | Taken from the lab fixture `Plant.research_quad()`: rotor inertia, rotor drag, airframe drag areas and the idle/max command. |

## Method

- `k_T` and `k_Q` use least squares through the origin against Ω² over both manufacturer rows. The displayed
  torque half-step (±0.005 N·m) gives about ±2.8 % on `k_Q`. Fit residuals and leave-one-out residuals are recorded
  in `provenance.derived_diagnostics`.
- `R = (V − Ω/Kv)/I` is taken at the 100 % row and assumes full bridge duty. It lumps motor, ESC and wiring loss.
  The no-load current (1.0 A) is estimated.
- The mass inventory is defined from the hub-plane centre (FRD). Mass, CG and the locked-rotor inertia about the CG
  are computed with the parallel-axis theorem. Each prop component carries the borrowed rotor spin inertia once
  (`rotor_id`). Motors are point masses, so the bell is not counted twice.
- Hover solves the four rotor thrusts from force and moment balance. Static maximum thrust uses the motor torque
  balance at the full-charge open-circuit voltage, without pack sag.
- Contacts: the feet are 22 mm below the hub plane. Total stiffness is `m·g/0.004 m`, and heave damping ratio is 0.6.
  The rest height is computed at static sag.

The loader recomputes mass, CG, inertia, clearance, k_T and hover. It refuses a document whose recorded diagnostics
differ by more than 1e-9 relative.

## Commands (repository root)

```
python research/drone-racing/openrc-fpv5-x1/derive.py            # write the candidate
python research/drone-racing/openrc-fpv5-x1/derive.py --check    # regenerate in memory, compare, never write
python research/drone-racing/openrc-fpv5-x1/derive.py --out PATH # write elsewhere
```

Output is deterministic: sorted keys, `repr` floats, LF line endings and UTF-8. The `sources.json` hash and the
`--check` comparison normalize CRLF to LF, so an `autocrlf` checkout gives the same result. Never hand-edit the
generated JSON. Change `sources.json` or `derive.py` and regenerate it.

## Limits

- None of these values has been measured. The static rows come from one vendor page without instrumentation or
  uncertainty data. The page bytes and hash have not been captured yet.
- The F5146 page recommends motors below 2100 KV, which conflicts with the 2150 KV tested pairing. This is unresolved.
- The frame geometry and component masses are typical-class estimates. Downloaded-frame intake (DR-29) is still open.
- Rotor inertia, drag areas and rotor drag are borrowed from a different (lab) aircraft.
- The static law above 3669.6 rad/s (the 100 % row) is extrapolated. Transient, braking, forward-flow, propwash and
  pack polarization behavior are not identified.
- Controller gains are starting values for the controller owner to requalify. They are not tuned results.
