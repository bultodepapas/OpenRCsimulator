# E0a2b — Downwash lag as sampled state

2026-10-07 · **Status: implemented and verified. The local model's pitch damping now matches the Stik's own geometry (Cmq + Cmα̇ −10.93 vs −11.07); it is ×0.81 of the borrowed oracle, a data question (see below).** Main-line ROADMAP M2 E0a2b; completes the E0a2 model.

## Model

The tail's downwash follows the wing's lift late, because the wake needs τ = l/V to reach the tail. Here l = 0.765 m from the wing's quarter chord to the tail's pressure centre (`downwash_lag_length`, derived by the loader), so τ = 51 ms at 15 m/s.

The session holds the lagged wing CL as one sampled aux entry after the anchors. That is the H8 pattern used for engine rpm:
- `_pre_step` advances it once per tick from the committed state by the exact first-order lag, `CL + (lag − CL)·exp(−dt·V/l)`;
- it is held through the RK stages, so loads stay pure;
- it starts settled at reset and at the runway start, and is carried by checkpoints and rollback.

`Aero.wing_lift_coefficient` uses exactly the strip law of `_local_loads`. `Dynamics.loads` and `Aero.loads` take the lag as an optional argument: NaN means quasi-static, which is what trim, flight-mode linearisation and the runway solve correctly use at their steady states. Only models with a downwash gradient and an envelope carry the lag (the Stik today). H9 golden replay classifies the entry as `downwash` (1e-9).

## Proof

[`test_downwash_lag.gd`](../../../../app/tests/test_downwash_lag.gd), 12 checks:

- **Layout:** the Stik carries one entry; the Extra, P-51 and Avanti carry none. Reset starts it exactly at the start state's wing CL.
- **Identity:** a lag equal to the instantaneous CL reproduces the quasi-static local loads byte for byte (2000 states including stall, rates and controls).
- **Real path:** `FlightSession._loads` feeds the lag to the tail. With the lag displaced at α 11°, the pitching moment is −2.95 against −2.40 N·m quasi-static.
- **Step response:** exact (24 ticks, error 1e-16).
- **Cmα̇** from a forced plunge oscillation (α oscillates, q = 0, reduced frequency 0.02) through the real `_pre_step` and local loads:

  | | 240 Hz | 480 Hz |
  | --- | ---: | ---: |
  | Measured | −3.424 | −3.495 |
  | Error to theory | 3.7% | 1.8% |

  - The theory is the delay theory (∂Cm/∂tail angle)·(dε/dα)·(l/V)·(2V/c) = −3.593, times the first-order lag's exact quadrature factor 1/(1 + (ωτ)²) = −3.557.
  - The 3.7% bias is the half-tick shorter effective delay of a per-tick update (τ − dt/2). The error halves with the tick (first order).
- **Effective pitch damping** in the local regime: Cmq −7.48 + Cmα̇ = **−10.93**, against the geometry estimate −11.07 (within 1.3%).
- **Checkpoint:** restore mid-pull and a 200-tick replay are byte-identical, lag included.
- **Mutation checks** on scratch copies, all caught: a lag without airspeed (4 checks), a lag not fed through the session's loads (the real-path check), an unsettled start.
- **Goldens (deliberate):** with only the lag length removed (back to E0a2a), all four replay exactly. With it, roll_15, pull_throttle and rudder_doublet move 0.4 mm to 3.6 cm; glide_15's trajectory is identical and only its aux rows gain the entry. All four were re-recorded.
- **Unchanged:** D11b's static derivatives, the flight modes (quasi-static linearisation), takeoff roll and the handling tests of every aircraft.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (102 sections). [Summary](suite-summary.log). The suite also found that a pure-oracle model (no envelope, `test_envelope`'s linear variant) must not carry the lag; fixed.

## The remaining gap is in the data, not the model

| Pitch damping (per q̂) | Value |
| --- | ---: |
| Stik tail, free slope (−2·a_t·η·V_H·l_t/c) + wing | −7.48 |
| + downwash lag Cmα̇ | −3.42 |
| **Local model, effective** | **−10.93** |
| Geometry estimate | −11.07 |
| Borrowed oracle Cmq (OpenFlightSim UltraStick 25e) | −13.57 |

The borrowed value belongs to another airplane's tail volume and arm, and it lumps Cmα̇ into one number. The Stik's own geometry gives −11.1. D11b therefore keeps its static Cmq pin (×0.64), and like-with-like acceptance is against the geometry here. Closing the last ×0.81 means choosing the oracle's Cmq source: keep the borrowed 25e value, or replace it with the Stik's geometry-derived value (DATA, with D11c/AVL as optional support), or measure it (VAL short-period identification). That is an owner/DATA decision; nothing was fitted.

## Limits

First-order lag instead of a pure delay (they agree to first order in ωτ; at ωτ 0.1, the 1/(1 + (ωτ)²) factor is 1%). The input is held per tick (bias −dt/(2τ), 4% at 240 Hz and 15 m/s). Downwash is uniform over the tail and has no ground effect.
