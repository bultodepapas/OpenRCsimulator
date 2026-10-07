# E0b1 — Ideal propeller wake verification

2026-10-07 · **Status: analytic verification complete; Stik wash remains disabled.** Main-line ROADMAP M2 E0b1.

The pure `Slipstream.wake()` already exists and is called by the production P-51 load path. This step adds an independent conservation-law test; it does not change the runtime model, aircraft data or goldens. The next step is E0b2: locate the Stik hub and washed tail pieces from its geometry.

## Reference and scope

For a uniformly loaded ideal actuator disc in forward flow, thrust equals mass flow times velocity gain. Bernoulli on either side of the disc gives `T/A = rho/2 * (V_far² - u²)`. These are the test oracles, rather than a copied implementation of `wake()`. Derivation: [NASA Glenn, Propeller Thrust](https://www.grc.nasa.gov/www/k-12/airplane/propth.html) (accessed 2026-10-07; US government educational reference, linked and paraphrased; no assets copied).

Continuity gives `A * (u + w) = pi * r_far² * V_far`, where `w = (V_far - u)/2`. At rest, `V_far = sqrt(2T/rho A)`, `r_far = R/sqrt(2)` and `q_far = T/A`. Substituting the definitions of Ct and J gives `q_far/q_inf = 1 + 8Ct/(pi J²)` for positive u. At zero airspeed the test uses absolute pressure, never divides by q_inf.

The test-only `wash_factor = [2, 2]` selects the ideal far wake. This is a mathematical reference, not a proposed Stik tail multiplier. The current P-51 decay/swirl configuration is untouched. Domain: positive density and diameter, nonnegative axial inflow and thrust. Reverse-flow fade, braking propellers, wash transport, actual coverage and tail-load calibration belong to later E0b steps. With zero thrust and zero inflow, wake radius has no physical meaning; only finite outputs and zero induced flow are required.

## Results

[`test_propeller_wake.gd`](../../../../app/tests/test_propeller_wake.gd) checks:

- Static speed, contraction, pressure and disc/far-speed relation; unchanged inputs and byte-identical repeated output.
- Momentum, pressure jump, volume-flow continuity, Ct/J ratio and contraction bounds over 144 cases: rho 0.8/1.225 kg/m³; D 0.15/0.3048/0.66 m; u 0/0.01/1/5/15/40 m/s; T 0.01/3/41.25/320 N. Tolerance: `1e-12 * max(1, abs(expected))` for analytic identities, in each quantity's SI units.
- Zero thrust at rest and in forward flow; rotation of shaft and velocity together, with crossflow, to detect use of body-x velocity or total speed instead of axial projection.
- The roadmap landmarks using the current Stik propulsion table and its level-flight drag polar. These are derived predictions, not independent measurements.

| Operating point | Thrust (N) | Ideal q_far/q_inf |
| --- | ---: | ---: |
| 5 m/s, fixed maximum static rpm | 38.36603 | 35.33847 |
| 15 m/s, fixed maximum static rpm | 32.59434 | 4.24141 |
| 15 m/s, thrust equals level-flight polar drag | 3.01268 | 1.29960 |

The rounded roadmap bands (35.3 ± 0.1 and 1.30 ± 0.01) are historical regression landmarks, distinct from the tight conservation checks. The 15 m/s level point estimates lift = weight and polar drag; it is not a powered six-degree-of-freedom trim. It must not be presented as a universal cruise wash factor. See the [propeller knowledge base](../../roadmap-investigations/03-propeller-propwash.md) for the borrowed propeller data and unmeasured decay/coverage limits.

## Reproduce

```bash
$(app/get-godot.sh) --headless --path app --script res://tests/test_propeller_wake.gd
python3 docs/research/propwash/E0b1/check_mutations.py
app/test.sh
```

The test is picked up automatically by `app/test.sh`. [`check_mutations.py`](check_mutations.py) creates a temporary minimal project, verifies its baseline, changes only the copy, rejects five distinct defects through failed assertions, and verifies restoration. It never mutates the shared app.

## Verification evidence

- [Analytic checks](checks.log): 19 checks pass, including the 144-case grid.
- [Mutations](mutations.log): missing pressure-jump factor 2, doubled induction, removed contraction, body-x projection and ignored wash factor are all rejected; the restored baseline passes.
- [Full suites](suite-summary.log): baseline 104 sections and final 105 sections both exit 0, with no engine errors; all goldens pass and the real app reaches identical states at 30/60/144 fps.
- Skill lint: zero errors before/after; the same 12 existing warnings.
- [Cost and trajectory record](cost.json): all 16 four-second trajectory fingerprints match between two sequential measurements (four aircraft × trim/stall/spin/ground). Tracked `app/physics`, `app/sim` and aircraft data are byte-identical to the recorded baseline commit.

### Cost

Median µs per complete 240 Hz tick, 3 batches of 120 ticks per fixture. Both measurements use identical runtime code; the full test suite ran concurrently. These record current cost, not an optimization or a Gate P decision. Timing variation cannot be attributed to E0b1, which adds no runtime work.

| Aircraft / fixture | First measurement | Second measurement |
| --- | ---: | ---: |
| Ugly Stik / ground | 282.5 | 281.4 |
| Ugly Stik / spin | 278.2 | 297.7 |
| Ugly Stik / stall | 290.8 | 258.7 |
| Ugly Stik / trim | 229.7 | 256.6 |
| Extra 300S / ground | 250.3 | 240.8 |
| Extra 300S / spin | 288.6 | 265.0 |
| Extra 300S / stall | 261.7 | 291.5 |
| Extra 300S / trim | 220.2 | 260.9 |
| P-51D / ground | 327.8 | 396.5 |
| P-51D / spin | 251.3 | 283.2 |
| P-51D / stall | 494.8 | 481.8 |
| P-51D / trim | 502.2 | 485.3 |
| Avanti S / ground | 239.4 | 261.4 |
| Avanti S / spin | 278.9 | 257.6 |
| Avanti S / stall | 305.2 | 276.1 |
| Avanti S / trim | 262.1 | 281.6 |

Reproduce the measurement twice with the command recorded in `cost.json`. Preserve host/load conditions when comparing performance. P-51 trim still borders the 500 µs budget on this shared host; Gate P remains open.
