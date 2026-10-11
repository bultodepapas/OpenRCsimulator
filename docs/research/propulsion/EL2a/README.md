# EL2a — Algebraic supply foundation

2026-10-10 · **Status: supply kernel verified; SOC integration and identified battery data remain open. Step prefix: EL.**

`app/physics/electric_supply.gd` evaluates a balanced aggregate pack with bounded piecewise-linear OCV(SOC), series resistance, capacity and explicitly pack-side auxiliary current. It is stateless and returns current, voltage, charge/energy rates and SOC derivative; it does not advance the flight or own a clock. The live electric demos still use fixed voltage.

For the positive-current branch:

`Im = [d*(OCV − Rpack*Iaux) − E] / [Rm + d²*Rpack]`

`Ipack = d*Im + Iaux`, `Vbus = OCV − Rpack*Ipack`, `dSOC/dt = −Ipack/(3600*Capacity_Ah)`.

Non-motoring branches draw no motor current; configured auxiliary draw remains when the source is disabled. Exact zero SOC uses an explicit exhausted-pack disconnection convention, including auxiliary loads. This is not a measured ESC/BMS cutoff or weakest-cell protection model. Infeasible/nonfinite buses fail instead of silently clipping voltage or SOC.

**93 checks pass**, covering the independent duty² solution, auxiliary-load sag, power accounting, charge versus energy rates, coast/exhaustion and invalid/overflow inputs. Run:

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_electric_supply.gd
```

Remaining EL2a work follows identified pack OCV/resistance/capacity/load data: loader branch, SOC/charge/energy continuous state, exhaustion-event integration, full rollback/replay and telemetry. RC polarization, thermal behavior and an Avian controller preset are not inferred from the synthetic algebra. [Plan and dependencies](../../../ELECTRIC-PROPULSION-PLAN.md#battery-and-esc-growth).
