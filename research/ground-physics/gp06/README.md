# GP-06 landing-gear audit tools

2026-10-19 · Reproduces the [GP-06 fleet landing-gear audit](../../../docs/research/ground-physics/GP-06/README.md). Pinned Godot from `app/get-godot.sh`, Python 3 standard library; no display. Write outputs to a fresh directory outside the repository.

| Tool | What it measures |
| --- | --- |
| `geometry_dump.gd` + `geometry_audit.py` | Static gear design metrics from the production loader: rest attitude, load shares, sag, damping ratio on the real static share, heave frequency, main-gear angle to the CG, nose-over deceleration, overturn angle, rest hull and propeller clearances, tail-strike pitch and wingtip-strike bank. |
| `reserve_drop.gd` | Report of the former 14 CFR 23.725/23.727 free drops (7 ft/s limit, 1.2× reserve, lift 2/3 W through the CG) for every geared catalog airplane. The drop itself lives in `app/tests/test_gear_reserve_energy.gd`, which asserts the reserve case. |
| `landing_envelope.gd` | Controlled touchdowns on the real `FlightSession` (aero, idle propulsion, wheel profiles, field surfaces, collapse/hull/prop-strike checks) across sink rates and attitudes, with a minimal attitude-holding pilot. Reports collapse, scrapes, bounce height and count, peak load factor and first-bounce restitution. |

From the repository root:

```sh
G=$(app/get-godot.sh); OUT=/tmp/gp06-$(date +%s); mkdir -p "$OUT"
"$G" --headless --path app --script "$PWD/research/ground-physics/gp06/geometry_dump.gd" -- --out="$OUT/geometry_dump.json"
python3 research/ground-physics/gp06/geometry_audit.py "$OUT/geometry_dump.json" --json "$OUT/geometry_audit.json"
"$G" --headless --path app --script "$PWD/research/ground-physics/gp06/reserve_drop.gd" -- --out="$OUT/reserve_drop.json"
"$G" --headless --path app --script "$PWD/research/ground-physics/gp06/landing_envelope.gd" -- --out="$OUT/landing_envelope.json" \
  jensen_ugly_stik_60 gp_extra_300s_60 p51d_mustang_120 sebart_avanti_s_a200 turbo_lumber_evolution
```

`landing_envelope.gd` options: `--terminal` (scripted D9d policy: any hull touch ends the flight), `--no-pilot` (trimmed controls held fixed). The envelope run takes about 15 minutes for the five aircraft on the shared VM.

The regression checks run in `app/test.sh`: `app/tests/test_gear_visual_contacts.gd` (rendered wheel bottom equals the physics contact through the manifest datum, 0.5 mm) and `app/tests/test_gear_reserve_energy.gd` (no gear collapse in the reserve drop).

Limits: the probe pilot, start height, speeds (1.15/1.4 Vs from the envelope CL_max) and reserve-drop attitudes are authored probe choices. The FAR rules are a full-size certification convention borrowed for RC models. None of these outputs is a physical RC measurement.
