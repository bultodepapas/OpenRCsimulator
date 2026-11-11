# AC-12 numerical-domain campaign: step refinement of the estimated trainer package

**Dated research record.** Step AC-12, gate G05 of the [Aircraft Creator plan](../../plans/aircraft-creator.md). Driver: [`research/aircraft-creator/ac12/`](../../../research/aircraft-creator/ac12/README.md). Package and derivation: [estimated trainer package](estimated-trainer-package.md).

This record has two parts. The **preregistration** was written on 2026-11-11 before any campaign flight was run and is not edited afterwards. The **results** are appended below it with their date.

Software verification of the integration step only. It says how far the 240 Hz production step is from a refined step for this estimated model. It says nothing about whether the model flies like a real airplane.

## Preregistration (2026-11-11, written before the runs)

### Question

For which part of the package domain does one flight at the 240 Hz production step agree with the same flight at 480 Hz and 960 Hz within the tolerances below?

### What was already known

- The template's 4 s pitch/roll/yaw pulse manoeuvre differs by 5.4 mm, 0.011° and 0.002 m/s between 240 and 480 Hz, and by half of that between 480 and 960 Hz (`test_creator_flight.gd`, AC-06). Convergence is first order.
- First order is expected: the kernel integrates with RK4, but servos, the downwash lag and the sampled rotor momentum advance once per tick and are held through the stages.
- No other case, tape or metric of this campaign had been flown at more than one step size. The cases were only compiled and listed (`campaign.gd --list`), which flies nothing.

### Configuration

- Working tree based on `7bff78490` with the uncommitted Aircraft Creator sources, including the wing-dihedral input added the same day. Source identities (SHA-256, first 16 hex digits): airframe package `00cd592b2e53bd06`, power package `8037b63011d68999`, `packages.gd` `0a2d1d246164d876`, `compiler.gd` `8c6989eb72174ce7`, `definition.gd` `4acf2e6a6fbc546b`, `campaign.gd` `0ab6246a6152e28c`, `variants.gd` `be780aa316d9a179`. Each result row carries the SHA-256 of the compiled record it flew.
- Engine `4.8.beta2.official.cafc17a19`, Windows x86_64 console build, headless, reference GDScript evaluator, `FlightSession` unchanged.
- Step sizes: 240 Hz (production), 480 Hz, 960 Hz. The tick is changed as `test_creator_flight.gd` does: `Engine.physics_ticks_per_second` is set before the session is created. No other solver path.

### Initial state

The session's own trimmed airborne start (`START_AIRBORNE`): level flight at the record's `start.level_speed`, 30 m above the origin, calm standard air, the battery at the definition's starting charge, shaft at its trimmed speed, servos at the trimmed surface positions. The hand launch is not part of this campaign: it adds a ground-contact gate and is covered by AC-09.

### Input tapes

Stick values are fractions of full travel **added to the trimmed inputs**; throttle is absolute. Every edge is a multiple of 0.25 s, so the three step sizes switch at identical instants. Each tape is one separate 6 s flight.

| Tape | Input |
| --- | --- |
| `pitch_doublet` | pitch +0.3 from 0.5 s to 1.0 s, −0.3 from 1.0 s to 1.5 s, then trim |
| `roll_doublet` | roll +0.3 from 0.5 s to 1.0 s, −0.3 from 1.0 s to 1.5 s, then trim |
| `rudder_kick` | yaw +0.5 from 0.5 s to 1.0 s, then trim |
| `throttle_step` | throttle 1.0 from 0.5 s to 3.0 s, then the trim throttle |

### Cases

All cases compile through the unchanged compiler and are inside the package domain. Geometry variants come from `variants.gd`: lengths scaled from the template, the package's own airframe mass proposal, and a balance reached by moving the battery (then nose or tail ballast if needed). "Margin" is the static margin.

| ID | Kind | Construction |
| --- | --- | --- |
| C01 | template | `Definition.template()` |
| C02 | interior | taper 0.8, dihedral 3°, margin 0.18, throws 15/15/20°, servo 0.2 s |
| C03 | edge | margin 0.085 (bound 0.08) |
| C04 | edge | margin 0.295 (bound 0.30) |
| C05 | edge | aspect ratio 4 at the template's wing area |
| C06 | edge | aspect ratio 7 at the template's wing area |
| C07 | edge | span 2.2 m, all lengths scaled |
| C08 | edge | span 1.0 m, all lengths scaled: thrust/weight 1.98 (bound 2) |
| C09 | edge | taper 0.6 |
| C10 | edge | dihedral 0° |
| C11 | edge | dihedral 8° |
| C12 | edge | lightest build: structure items lightened to thrust/weight 1.97, wing loading 3.14 kg/m² (bound 3) |
| C13 | edge | heavy: payload at the centre of mass to wing loading 7.9 kg/m² (bound 8) |
| C14 | stiff A | C12 with the fastest servos (0.05 s) and the largest throws (30/30/35°) |
| C15 | stiff B | span 0.9 m (bound), aspect ratio 4.5, margin 0.29, thrust/weight 1.97, wing loading 7.86 kg/m², servo 0.05 s, throws 30/30/35° |
| C16 | adverse | aspect ratio 7, taper 0.6, dihedral 0°, margin 0.085, throws 30/30/35°, servo 0.5 s |
| C17 | adverse | aspect ratio 4, wing loading 7.9 kg/m², margin 0.295, dihedral 8°, thrust angles 5° down and 5° right, starting charge 0.2 |

C14 is the stiff candidate the plan asks for: light, the highest thrust/weight, the shortest servo time and the largest throws the domain admits. C15 adds the smallest and fastest airframe the bounds admit together: at 0.9 m span the wing-loading and thrust/weight bounds leave only aspect ratios below 4.66 with the one power package.

Not covered and therefore not qualified by this campaign: tail aspect ratios and tail volumes at their bounds, fin aspect ratio bounds, the hub position bound, negative thrust angles, hand launch, wind and turbulence, stalled and spinning flight, flights longer than 6 s.

### Metrics

Samples are taken at the common 240 Hz instants (every tick at 240 Hz, every second at 480 Hz, every fourth at 960 Hz). For each pair of runs a metric is the **largest difference over all 1440 samples**:

| Metric | Definition |
| --- | --- |
| Position | norm of the difference of the NED positions, m |
| Attitude | rotation angle between the two attitudes, degrees |
| Body rates | norm of the difference of p, q, r, degrees/s |
| Airspeed | difference of the true airspeed, m/s |
| Rotor speed | difference of the shaft speed, rpm |
| Battery current | difference of the pack current, A |
| Charge | difference of the charge consumed at 6 s, as a fraction of the charge consumed |

### Verdict rule

With E₁ = |240 Hz − 480 Hz| and E₂ = |480 Hz − 960 Hz|:

- ratio r = E₂/E₁ and observed order p = −log₂ r are reported for every metric;
- **convergence**: r ≤ 0.75 is required (first order gives 0.5, fourth order 0.0625). A difference below the noise floor (1e-7 m, 1e-7°, 1e-6°/s, 1e-8 m/s, 1e-5 rpm, 1e-7 A, 1e-10 charge fraction) counts as converged without a ratio;
- **estimated 240 Hz error** against the refined limit: E₁/(1 − r), the sum of the geometric series of successive differences (2·E₁ at first order);
- a metric passes when it converges and its estimated 240 Hz error is within the tolerance; a tape passes when all three runs complete without a fault and every metric passes; a case passes when its four tapes pass.

### Tolerances and their reasons

The production step has a known timing granularity: a command sampled once per tick and held acts on average half a tick late, 2.1 ms at 240 Hz. Tolerances are set at the size of that effect or of a few such ticks, well below what a pilot or the estimate itself can resolve, and were fixed before the runs.

| Metric | Tolerance | Reason |
| --- | --- | --- |
| Position | 0.10 m | 5 ms of flight at 20 m/s; below the 10–20 ms latency of an RC link and 0.1 % of the path flown in 6 s |
| Attitude | 0.5° | 2.1 ms at a brisk 200°/s is 0.4°; below what a pilot resolves by eye at flying distance |
| Body rates | 2°/s | 1 % of a 200°/s manoeuvre rate |
| Airspeed | 0.05 m/s | 0.4 % of the template's level speed |
| Rotor speed | 20 rpm | 0.2 % of a 9000 rpm full-throttle shaft |
| Battery current | 0.2 A | 0.5 % of a 40 A full-throttle draw |
| Charge | 0.2 % | of the charge consumed in the flight |

### What a failure does

A failing case is reported as failing. The tolerances are not widened. If a failure can be tied to a domain bound, that bound is narrowed in the package data with its reason and a test, so the failing corner is no longer admitted. The `experimental` label is not changed by this campaign: that decision belongs to the project owner.

## Results (2026-11-11)

**Gate G05 is not passed.** Under the frozen rule 8 of the 17 preregistered cases pass (56 of their 68 tapes). No bound was narrowed, no tolerance was changed, and the package stays `experimental`.

Runs: 96 tapes × 3 step sizes = 288 flights (68 preregistered tapes, 28 follow-up tapes), all completed without a solver fault. Sources as preregistered (same identities for both packages, `packages.gd`, `compiler.gd`, `definition.gd`, `variants.gd`); `campaign.gd` gained the follow-up cases after the preregistered runs (`20acca0973e6c728`), the C cases unchanged. Raw outputs (`campaign-*.json`, logs) are kept outside the repository and can be regenerated with the [driver](../../../research/aircraft-creator/ac12/README.md).

### Preregistered cases

| Verdict | Cases |
| --- | --- |
| Pass (4 of 4 tapes) | C01, C03, C06, C07, C10, C11, C12, C13 |
| Fail | C02, C04, C05, C08, C09, C14, C15, C16, C17 |

Failing tapes, with E₁ = \|240 − 480 Hz\| and E₂ = \|480 − 960 Hz\|:

| Case and tape | Metric | E₁ | E₂ | Why it fails |
| --- | --- | --- | --- | --- |
| C02 `roll_doublet` | position | 1.49 mm | 1.75 mm | ratio 1.18 |
| C02 `throttle_step` | rotor speed | 0.0012 rpm | 0.0011 rpm | ratio 0.93 |
| C04 `roll_doublet` | charge | 2.7e-8 | 3.0e-8 | ratio 1.10 |
| C04 `throttle_step` | rotor speed | 0.0017 rpm | 0.0013 rpm | ratio 0.80 |
| C05 `throttle_step` | charge | 4.4e-9 | 1.3e-8 | ratio 3.0 |
| C09 `throttle_step` | charge | 5.7e-9 | 1.2e-8 | ratio 2.1 |
| C16 `throttle_step` | charge | 6.6e-9 | 1.0e-8 | ratio 1.6 |
| C08 `roll_doublet` | body rates | 1.24°/s | 0.63°/s | estimated error 2.5°/s > 2°/s |
| C14 `roll_doublet` | body rates | 1.67°/s | 0.85°/s | 3.4°/s > 2°/s |
| C15 `pitch_doublet` | body rates | 1.46°/s | 0.73°/s | 2.9°/s > 2°/s |
| C15 `roll_doublet` | body rates | 3.33°/s | 1.68°/s | 6.7°/s > 2°/s |
| C17 `roll_doublet` | body rates | 1.10°/s | 0.56°/s | 2.2°/s > 2°/s |

The failures are of two kinds.

- **Differences that do not shrink with the step, at very small size** (first seven rows). They are three to seven orders of magnitude below their tolerances (position 1.5 mm against 0.10 m, rotor speed 0.002 rpm against 20 rpm, charge 1e-8 against 2e-3) but above the preregistered noise floors, so the convergence rule applies and fails them. The floors were set without a measurement of the step-independent scatter of these metrics. The cause of the floor was not investigated.
- **Body-rate error above tolerance, converging at first order** (last five rows; ratio 0.50 in each). These are real 240 Hz step errors: 2.2 to 6.7°/s in the roll doublet of the smallest, lightest or fastest-servo corners, and 2.9°/s in the pitch doublet of C15. First order is the expected rate (commands and servos advance once per tick). In the same tapes attitude stays within 0.25° (tolerance 0.5°) and position within 0.073 m (tolerance 0.10 m).

Largest estimated 240 Hz error of every converging metric over all 96 tapes: position 0.073 m, attitude 0.25°, body rates 6.7°/s, airspeed 0.0076 m/s, rotor speed 1.1 rpm, current 0.0066 A, charge 0.034 %. Only body rates exceed their tolerance.

### Follow-up cases (added after the preregistered runs; exploratory)

They use the same rule, tapes and tolerances, but they were chosen after seeing the results above and carry no preregistration weight.

| ID | Construction | Verdict |
| --- | --- | --- |
| X01 | C12 with the fastest servos (0.05 s), template throws | Fail: roll-doublet body rates 2.3°/s; one non-shrinking charge difference (6e-6) |
| X02 | C12 with the largest throws (30/30/35°), template servos (0.14 s) | Pass |
| N01 | span 1.2 m, all lengths scaled | Pass |
| N02 | C17 at wing loading 7.0 kg/m² | Fail: roll-doublet body rates 2.07°/s; one non-shrinking charge difference |
| N03 | lightest build, servo 0.10 s, throws 25/25/35° | Fail: roll-doublet body rates 2.06°/s; non-shrinking charge differences |
| N04 | span 1.2 m, aspect ratio 4.5, lightest build, margin 0.29, servo 0.10 s, throws 25/25/35° | Fail: roll-doublet body rates 2.9°/s; non-shrinking charge differences |
| N05 | template at wing loading 7.0 kg/m² | Fail: one non-shrinking current difference (9e-6 A) |

X01 against X02 ties the body-rate error of the light build to the servo time, not to the throws. The narrowed corners tried (span ≥ 1.2 m, wing loading ≤ 7.0 kg/m², servo time ≥ 0.10 s, throws ≤ 25/25/35°) do not pass together, so no narrowing is supported by this evidence and none was made.

### What this does and does not establish

- Established: for the cases flown, a 240 Hz flight of this estimated model stays within 0.25° and 0.073 m of its refined-step limit over 6 s; angular rates during abrupt commands differ by up to 6.7°/s in the stiffest corner.
- Not established: G05. The preregistered question ("for which part of the domain…") has no answer yet, because the rule fails cases on differences far below its own tolerances and no tested narrowing clears the body-rate failures.
- Not covered: everything listed as not covered in the preregistration; any physical validation.

### Next step (needs a new preregistration; this one is not edited)

1. Measure the step-independent scatter of each metric (for example 960 against 1920 Hz, and repeat runs) and state noise floors from that measurement.
2. Decide, with the project owner, whether the peak body-rate difference at command edges stays a gate metric with a 2°/s tolerance, or whether the package domain should exclude the fast-servo, light corners that exceed it.
