# Decision brief — the Ugly Stik oracle's borrowed coefficients

2026-10-07 · **Status: awaiting the owner.** Prepared by the main line after D11d, E0a2a/b and D11f. Record the choice in DECISIONS.md.

## Situation

Below α ≈ 8° the simulator flies a whole-airplane "oracle" whose coefficients are borrowed from the UltraStick 25e (OpenFlightSim). Above it, flight uses the local strip model built from the Stik's own geometry. D11d, E0a2 and D11f made the local model consistent and verified it against independent references:

| Quantity | Local model (Stik physics) | Stik-consistent reference | Borrowed oracle (25e) | Local ÷ oracle |
| --- | ---: | ---: | ---: | ---: |
| Clp | −0.50 | VLM −0.40 to −0.47 (coarse 3 strips) | −0.4496 | ×1.12 (accepted) |
| CLα | 4.58 | (matched by construction) | 4.58 | ×1.00 (accepted) |
| Cmq + Cmα̇ | −10.93 | geometry −11.07 | −13.57 | ×0.81 |
| Cnr | −0.127 to −0.134 | −0.132 (fin from the data's own Cnβ + wing profile) | −0.1833 | ×0.72 |
| Drag polar | per-strip k·(cl − 0.23)² | induced k_i ≈ 0.064 (e ≈ 1.0) | k 0.0815 about CL 0.23 | not decomposable for the Stik |

The rate derivatives show the largest blend inconsistencies, where the airplane changes damping as it crosses about 8–12° (slow flight, the approach), and they come from borrowed numbers, not from the model.

## Options

1. **Keep the borrowed 25e values.** No work. The Stik keeps a pitch- and yaw-damping change across the blend (≈ 20–30%), and the drag polar stays non-physical per strip.
2. **Replace them with Stik geometry-derived values (recommended).** Derive Clp, Cmq (with Cmα̇), Cnr and an induced/profile drag split from the Stik's geometry: the in-repo references above, optionally cross-checked with AVL (D11c). Label every value `derived` with its method. The oracle then agrees with the local model through the blend, and explicit per-strip induced drag can replace the per-strip polar term. Validation stays open (VAL).
3. **Measure first.** Short-period, roll and dutch-roll identification on the real Stik (VAL-5/6, the owner's field kit) supplies Cmq, Clp and Cnr; keep the borrowed values until then.

Options 2 and 3 combine well: 2 now (consistent, labelled derived), 3 when flight data exist, with the measured values kept as held-out validation rather than fitted in.

## Consequence of each

- **Option 1:** handling changes as the plane crosses the blend; known and documented.
- **Option 2:** one DATA step changes the oracle (re-recorded goldens and modes). D11b acceptance closes against the Stik's own numbers.
- **Option 3:** a field-kit session first; until then, option 1 behaviour.
