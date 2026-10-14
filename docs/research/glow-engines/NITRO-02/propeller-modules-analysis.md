# Propeller normal force, P-factor and wake for glow installations: analysis

2026-10-14. Desk analysis requested with the NITRO improvements. No runtime change was made. Line references are to the tree of that date.

## Where the refusal happens

`physics/glow/installation.gd` `prepare_value()` refuses `propulsion.propeller.normal_force`, `pfactor_moment` and `slipstream`. It is the only refusal:

- the module registry allows all three for `glow_prop`;
- the loader parses them, and each needs `thrust_angles`, which the glow Stiks already declare as `[0, 0]`;
- `test_glow_installation.gd` `_test_unsupported_modules` covers the refusal.

The NITRO plan requires these modules to use "the same stage loads and profile", which rules out borrowing the legacy tables.

## Normal force and P-factor: feasible

- **The tables fit the surrogate exactly.** Both laws (`propulsion.gd` `normal_force` and `pfactor_moment`) need only the axis, diameter, rpm, hub velocity, density and C_N(J), C_M(J). The annular surrogate has no induced inflow and no Reynolds dependence, so T = ρn²D⁴·Ct(J) and Q = ρn²D⁵·Cq(J) hold exactly, and J-indexed tables scale correctly.
- **Tables can be derived from the installation itself** by an azimuth-resolved pass over the same annuli. For the 55AX 12×7: C_N = 0.0012 / 0.0025 / 0.0041 / 0.0063 and C_M = 0.0020 / 0.0038 / 0.0053 / 0.0065 at J = 0.1 / 0.2 / 0.3 / 0.4.
- **The effect is small.** At 15 m/s, 10° and 10,000 rpm it gives about 0.21 N and 0.083 N·m of left yaw, roughly 1.5 % of rudder authority. This agrees with [03-propeller-propwash](../../roadmap-investigations/03-propeller-propwash.md) (0.30 N and 0.11 N·m).
- **Energy.** The normal force is passive (N·v_c ≤ 0). The P-factor's power has no fixed sign and is not paid by the shaft. The hub-power closure check in `test_glow_hub_inflow.gd` must therefore be split into separate terms.
- **Open contract issue, windmilling.** The coefficients change sign at J ≈ 1.5 (2T) and J ≈ 1.0 (4T). An idle glide sits near J ≈ 1.7. The shared table contract ([0, 1] range, floor 0) cannot represent negative values; the P-51 uses the same contract.
- **Omitted terms.** A stopped propeller's fin force and the near-static jet normal force are omitted, as they are for the P-51.

## Slipstream and wake: not consistent as written

1. `Slipstream.loads` re-evaluates the propeller at the datum velocity. That is a second, unprepared evaluation per stage, outside the hub-inflow law.
2. `reverse_weight` reads the legacy `ct_table` that the glow aircraft still carry, not the surrogate.
3. The glow state layout has no slots for wash-transport states, so only a quasi-static wake would fit without a new checkpoint format.
4. `slipstream.hub` is never checked against `thrust_line_offset`.
5. Swirl comes from torque as a declared heuristic. Its energy is not in the glow work ledger.
6. The borrowed oracle derivatives may already contain power-on wash, so adding a wake could double count it.

## Plan

**A. Normal force and P-factor** (about 3–4 days, low risk):

1. Generate surrogate-consistent tables in `build_installations.py`.
2. Owner decision: truncate the domain, or extend the shared table contract to negative values.
3. Lift the two refusals and keep `slipstream` refused.
4. Bump `GlowFlight.LAW`.
5. Extend the installation, stage-reuse, hub-inflow, propulsion-scalar and module tests, and add a sign test.
6. Re-record the NITRO flight evidence.

**B. Slipstream** is blocked on owner data and decisions:

- the E0b7 field card (nose-wheel unloading, taxi blip, takeoff swing);
- the wash and swirl factors;
- Gate P cost acceptance: active wash costs 598–838 µs per tick against a 500 µs budget.

Its software part:

- pass same-stage thrust, torque and hub velocity into `Slipstream`, keeping the P-51 byte-exact;
- take the static Ct from the surrogate;
- validate the hub position;
- quasi-static only.
