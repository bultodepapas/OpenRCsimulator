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
