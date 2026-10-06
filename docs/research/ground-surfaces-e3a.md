# E3a — Field surfaces under the wheels (2026-10-06)

First sub-step of [ROADMAP](../../ROADMAP.md) E3 (runway start). [E2](ground-friction-e2.md) gave the tyres
dry-pavement values and found that idle thrust out-pulls rolling resistance. Our runway is not pavement: the
landscape plan draws it as a mown grass strip (LANDSCAPE-PLAN L9c), and its field rectangles were meant to "feed
both the ground shader and later ground physics". E3a makes the wheels roll on those surfaces.

## Model

- `app/data/ground/surface_friction.json` (format `openrc-surfaces v1`, every value `{value, unit, kind, source}`):
  per surface type a `friction_factor` (× the gear's μ) and a `rolling_factor` (× the gear's C_rr). The aircraft's
  coefficients stay "tyre on dry pavement", as in JSBSim/FlightGear.
- `app/physics/ground_surfaces.gd` loads and validates the table and builds a flat lookup from the field's validated
  rectangles (read through `data/field_loader.gd`, whose files are not touched). Precedence: runway over mown over
  rough, whatever the field's order. Beyond every rectangle the ground is rough.
- `ground_contact.gd` looks up the surface under **each wheel** (not the CG) in every RK4 stage
  (`surface_at`). An empty table means pavement everywhere, so E1/E2 tests and aircraft without a field are unchanged.
- `FlightSession.set_field(field)`: `main.gd` passes the loaded field. Invalid surface data refuses the flight, like
  invalid aircraft data. The trace header names the field.

| Surface | μ factor | Rolling factor | Stik μ / C_rr | Source |
| --- | --- | --- | --- | --- |
| runway (mown strip) | 0.8 | 2.5 | 0.64 / 0.10 | FlightGear `grass_rwy` (friction 0.8, rolling 0.05 over asphalt's 0.02) — borrowed |
| mown | 0.7 | 5 | 0.56 / 0.20 | FlightGear `Grass/Airport/Greenspace` (0.7, 0.1) — borrowed |
| rough | 0.7 | 7.5 | 0.56 / 0.30 | FlightGear `Grassland` (0.7, 0.1, bumpier) — friction borrowed; rolling ×1.5 for a 76 mm wheel in uncut grass, **estimated** |

**Rolling creep.** The rolling law is linear below a creep speed, now 0.01 m/s (E2 had 0.05), growing as 0.1·C_rr
above C_rr 0.1. Its low-speed rate is then at most g/0.1 = 98 /s on any surface (λ·dt 0.41 at 240 Hz). The cost of a pure
velocity law: a steady push F < C_rr·N is not held but creeps at 0.1·F/(m·g) once C_rr ≥ 0.1 (0.9 cm/s at idle).
True stiction needs per-wheel state and is planned for E3b, where the airplane must wait at idle before takeoff.

## Proof (`app/tests/test_ground_surfaces.gd`, 28 checks)

- Table: values loaded; six refusals (format, missing type, friction factor > 1, unit `%`, unknown type, empty source).
- Lookup on the real field from its own rectangles: runway centre, threshold and edge are runway; 1 cm past the end
  or side is rough; the pilot station and 30 km out are rough. A nested runway/mown/rough field listed in the worst
  order resolves by precedence.
- Hand-computed (N = 100 N, C_rr 0.04, μ 0.8): runway drag −10 N, runway skid −64 N, rough drag −30 N, rough at 1.5
  cm/s −15 N (creep scaling), no table −4 N (E2). CG on the runway with the wheel 0.2 m past its end → rough drag.
- Friction power ≤ 0 over 2000 random states across surface edges (max −0.67 W).
- Coast-down from 3 m/s (bare body): runway 0.979 m/s² vs 0.981 (C_rr·2.5·g), rough 2.933 vs 2.942.
- Real session, idle, 10 s: without a field the Stik rolls 21.1 m (3.78 m/s, the E2 finding). On the mown runway it
  holds (10 cm, 0.92 cm/s: the creep). Same on the rough. A missing table refuses the flight.
- `check_trimmed_flight.py` (app trace in `test.sh`) now fails if an aircraft with gear flies without the field's
  surfaces.
- Mutations on a scratch copy, all caught: precedence reversed (5 failures), friction factor ignored (1), surface
  looked up at the CG (1), creep not scaled (1), `main.gd` not calling `set_field` (app trace check).
- `--trace --t=3` rows byte-identical (SHA-256 `7d2f8a4c…`). E1/E2 tests unchanged (22, 26).

## Not proven / limits

- **No validation.** All factors are borrowed from full-size simulation data or estimated. The decisive real
  measurement is cheap: a coast-down and an idle test of a real Stik on the owner's grass runway.
- The idle balance on the runway is thin (2.6 N thrust vs 2.8 N drag): a 10 % change in either flips it.
- Surfaces are flat rectangles with sharp edges. No bumpiness (FlightGear has it), no wet grass, no rolling-
  resistance rise with speed.
- Creep at 0.9 cm/s until E3b adds stiction.

## Reproduce

```bash
$(app/get-godot.sh) --headless --path app --script res://tests/test_ground_surfaces.gd
```

Sources: FlightGear fgdata (GPL), `Materials/default/global.xml` (`grass_rwy`, `dirt_rwy`), `global-summer.xml`
(`Grass`, `Grassland`), `Materials/base/materials-base.xml` (`Asphalt`) and `Docs/README.materials`,
gitlab.com/flightgear/fgdata, branch `next`, read 2026-10-06. Only numbers are used, no data files copied.
