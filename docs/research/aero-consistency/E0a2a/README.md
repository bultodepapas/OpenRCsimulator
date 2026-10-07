# E0a2a — Horizontal tail downwash split

2026-10-07 · **Status: implemented and verified (first slice of E0a2). Pitch damping ×0.28 → ×0.64 of the oracle; downwash lag (E0a2b) and pitch acceptance remain open.** Main-line ROADMAP M2 E0a2.

## Problem

The local horizontal tail had an *effective* lift slope of 1.75/rad = a_t·η·(1 − dε/dα), and it applied that slope to everything:
- to the free stream, where the downwash reduction belongs;
- to the pitch-rate flow q·l_t/V and to the elevator, where it does not, because downwash follows the wing's lift.

The elevator's `control_effectiveness` 1.174 (= Cmde/Cma, "including omitted downwash") compensated by hand. Results:
- pitch damping in the local regime was ×0.28 of the oracle (D11b);
- the tail's angle, and so its stall and its separation drag, was overstated: local drag ran 20% above the oracle across the blend;
- the tail triggered the blend from α ≈ 6°, earlier than the wing.

## Model

Optional data `aero.surfaces.horizontal.downwash_gradient` (Stik: 0.457, `derived`, the knowledge base's VLM value at the tail; the elliptic estimate is 0.50). With it, the loader derives the free tail law from the existing consistency data and the D11d wing map:

| Derived value | Formula | Stik |
| --- | --- | --- |
| free slope a_t·η | lift_slope / (1 − dε/dα) | 3.223/rad (a Helmbold tail of AR 3.27, η 0.9, gives 3.17) |
| elevator flap effectiveness τ | control_effectiveness·(1 − dε/dα) | 0.637 |
| downwash per wing CL, k_ε | (dε/dα) / CLα_wing | 0.1083 rad |
| free incidence | (1 − dε/dα)·incidence + k_ε·CL_wing0 | 0.0309 rad |

`Aero._local_loads` sets the tail angle to (flow angle at the tail, including q·l_t) − k_ε·CL_wing + τ·δe + i_free. CL_wing is the strips' actual mean section lift coefficient, so **downwash collapses when the wing stalls**, and the tail then sees more angle: the stall break. `local_flow_weight` uses the linear attached form for its blend decision.

By construction, static tail lift is unchanged: CLα, Cmα, Cmde and CL0 equal the former law and the oracle. Downwash with a propeller slipstream (the P-51's opt-in path) is refused until it is modelled. Other aircraft have no gradient and keep the former law.

**Elevator.** τ 0.637 against thin-airfoil flap theory for the Stik's 20%-chord elevator (from the model team's tail outlines) of 0.545: the borrowed 25e Cmde appears to overstate the Stik's small elevator by about 17%. This is a data finding for VAL (measure elevator authority); not fitted here.

## Proof

- **Tail tests:** [`test_tail_downwash.gd`](../../../../app/tests/test_tail_downwash.gd), 8 checks.
  - With no rates, lift is identical to the former law to 6.5e-16 (α −2…6°, elevator ±0.05 rad). The pitching moment differs at most 1.6%, through the tail drag's arm only.
  - Local drag is now closer to the oracle (α 8°: 4.36 against 4.17 N, former 4.71; α 10°: 5.29 against 5.16 N, former 5.79).
  - The tail's pitch-rate moment grows ×1.78; the lift part alone is 1/(1 − dε/dα) = 1.84, and tail drag and lift tilt account for the rest.
  - τ is plausible.
  - At α 14° (wing partly stalled), the tail angle recovered from its own lift, 10.01°, equals α − k_ε·CL_wing + i_free, and is 1.2° above what linear downwash would leave.
- **D11b:** **Cmq ×0.28 → ×0.64**; CLα ×1.000; Clp ×1.098; Cnr ×0.715 → ×0.748 only because the blend now starts later (D11f). The blend now starts at α ≈ 8° (wing-triggered), as the attached limit intends.
- **Flight modes:** 10 m/s short period ζ 0.47 → **0.52** (0.90 → 0.99 Hz). D11d's 0.45 floor exception is removed; 15/25 m/s are bit-identical.
- **Goldens (deliberate):** with the gradient fields removed all four replay at 1e-15 m; with them roll_15, pull_throttle and rudder_doublet move 0.04–0.23 m and glide_15 is unchanged. All four were re-recorded.
- **Frozen oracles:** the H4/H12 frozen oracles compare against the pre-E0a2 tail law and stay byte-exact.
- **Mutation checks** on scratch copies, all caught: linear downwash in the loads (the α 14° check), an elevator not rescaled (4 checks), no free slope (4 checks).
- **Other tracks:** the P-51, Extra and Avanti handling and envelope tests, spin and envelope all pass. Full `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (100 sections). [Summary](suite-summary.log).

## Why Cmq stays at ×0.64 and what E0a2b must do

The theoretical Stik tail pitch damping is −2·a_t·η·V_H·(l_t/c) = −2 · 3.22 · 0.486 · 2.36 = **−7.4**; the wing adds about −0.4. The borrowed oracle Cmq −13.57 comes from the UltraStick 25e: a different geometry, and a model without Cmα̇, so its single number stands in for both. The downwash lag Cmα̇ = −7.4 · dε/dα ≈ **−3.4**, giving Cmq + Cmα̇ ≈ −11.2, or 0.83× the oracle.

A quasi-static loads function cannot produce α̇ effects. E0a2b adds the lag as a sampled H8 state: the tail sees the wing's CL from l_t/V earlier. Its acceptance should compare like with like: short-period damping (local versus oracle) or Cmq + Cmα̇ against the oracle, not the static ∂Cm/∂q.

## Limits

dε/dα is a VLM estimate; η and the 20% elevator chord come from geometry, not measurement. The downwash is applied as an angle at the tail's pressure centre (no spanwise variation, no ground effect). The cost is about four float operations per local evaluation and was not separately measured.
