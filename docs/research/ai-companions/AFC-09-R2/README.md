# AFC-09 R2 — Full-footprint runway-exit gate qualification

This research-only run rechecked the eight fixed C5e sorties with a stricter physical exit gate. The historical result remains **5/8 passes of the original 22 gates**; R2's full-clear gate passes **5/8**, and **4/8** pass both sets. R2 does not change the pilot, taxi commands, simulation physics, aircraft data, or production app.

The historical C5e pilot uses a final-join TAS feedback gain of 0.16 and fixed bias 0.0. The gate-only driver retains the same flight and taxi command path. It requires all three landing-gear points and all accepted crash-hull points to stay north of the runway edge by more than 0.5 m, all wheels to remain down, the entire gear-and-hull footprint to stay within the runway's east/west end bounds, and a resettable 0.25 s clear dwell. Completion rechecks those predicates and requires at least 2 s since taxi exit began. A side-corridor violation rejects immediately; the measured negative margins below are retained without tolerance adjustment. Wheel `all_anchors` stiction is report-only and is not substituted for wheel support.

| Case (weather, seed) | R1 original 22 gates / entry TAS | R2 full-clear gate | Entry readiness | Harness checks | Combined sortie acceptance | Common CSV prefix |
|---|---|---|---|---:|---|---:|
| East calm, 0 | Pass / 12.2741 m/s | Pass; 16.958 s; min end margin +1.1055 m | Ready | 26/0 | Yes | 30,664 × 62 |
| East headwind, 20261015 | Pass / 11.7811 m/s | Pass; 16.208 s; +38.9163 m | Ready | 26/0 | Yes | 33,206 × 70 |
| East north crosswind 0.5 m/s, 20261025 | Pass / 12.2843 m/s | Reject; −0.00018549 m side-corridor margin | Ready | 26/0 | No | 30,591 × 70 |
| East south crosswind 0.5 m/s, 20261027 | Fail: physical taxi timeout / 12.2449 m/s | Reject; −0.00150277 m side-corridor margin | Ready | 26/0 | No | 29,628 × 70 |
| West calm, 0 | Pass / 12.2735 m/s | Pass; 17.163 s; +1.2811 m | Ready | 26/0 | Yes | 30,583 × 62 |
| West headwind, 20261039 | Fail: approach TAS 12.5343 > 12.5 m/s / 12.5343 m/s | Pass; 16.371 s; +35.2469 m | Not ready: airspeed | 26/1 | No | 29,777 × 70 |
| West north crosswind 0.5 m/s, 20261044 | Pass / 12.2767 m/s | Pass; 18.946 s; +0.9925 m | Ready | 26/0 | Yes | 30,680 × 70 |
| West south crosswind 0.5 m/s, 20261051 | Fail: physical taxi timeout / 12.3079 m/s | Reject; −0.00219429 m side-corridor margin | Ready | 26/0 | No | 29,906 × 70 |

“Combined sortie acceptance” means the case passed the historical R1 22 gates **and** the R2 full-clear gate. The west-headwind case clears the new exit gate but remains unacceptable because it exceeds the existing approach TAS limit by 0.0342797 m/s. The east north-crosswind case was an R1 pass but fails the stricter end-corridor predicate by 0.185 mm. The two south-crosswind taxi timeouts remain historical failures; R2 additionally records their earlier side-corridor violations. No case is relabeled retroactively in R1.

Clear times are measured from the start of taxi after the existing two-second supported-rollout dwell and end when the new 0.25-second full-clear dwell first qualifies. All eight R2 runner receipts completed with zero engine/setup errors; the sole test-process failure is the west-headwind approach-TAS assertion, not a setup failure.

Harness counts report assertion-suite results, not sortie acceptance. For the three R2 corridor rejections, 26/0 means the harness verified the expected incomplete result and rejection reason. West headwind is 26/1 because the unchanged approach TAS assertion fails, even though the full-clear driver itself completes. The approach-readiness classifier is report-only in this experiment.

Every candidate ORFL completed an exact replay with `solver_changed=false` (8/8). Each candidate numeric flight CSV matched the retained R1 baseline exactly across every column through `min(baseline_final_tick, candidate_final_tick)`: 8/8 comparisons, 0 mismatched cells, 245,035 common-prefix rows total. Prefix lengths are per-case in the table; the verification JSON records both final ticks, the compared columns, exact replay reports, CSVs, ORFLs, runner receipts, byte counts, and SHA-256 values. This proves common-prefix command/state invariance for the gate-only candidate; the different suffixes and stop points are gate outcomes, not full-run equivalence.

The state helper passed 21/21 focused checks when loaded from the gate-only driver and 21/21 with the existing taxi-candidate default. These checks validate state transitions and boundary behavior, not physical taxi qualification. The eight-case matrix does not close the 50-sortie campaign, the 10 incursion/abort/go-around tests, or runtime integration.

Source identities used for the matrix:

- [Gate-only driver](../../../../research/ai-companions/sorties/external_sortie_driver_candidate_clearance.gd): `658212374fe2cd0b887169f9c1db87aaed60a41a2c4c280239f38d5f569ca4bd`.
- Historical driver: `b8902dee829422974d9020781e7bd629c4d30145147aecc6b3c5f2f246fc8b6d`.
- C5e pilot: `ab03aa2ff54061e0a4110ccedacfac4369c8491fcafe1411637fd9caedb08395`.
- Aircraft authoring input: `5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007`.
- Solver: `21c675a567d7a28a07c2e417fd12581ea7346cf2423cb9d839f1de4f24af46c3`.
- Test harness: `59092afeaf47bff0d2bc59fec31aa9f0f2431104cf231f417575f71709126a62`.

The frozen, separately imported Godot mirror was `D:/OpenRCsimulator-AFC-work/evidence/avoidance/AFC-04-R4/mirror/app`; raw R2 evidence is under `D:/OpenRCsimulator-AFC-work/evidence/sorties/research/AFC09-clearance-gate-R2/`. The per-run source identities and raw artifact hashes are in [verification.json](verification.json). The preceding historical results and the original wheel-only, sticky-clearance limitation remain in [AFC-09 R1](../AFC-09-R1/README.md) and its [verification receipt](../AFC-09-R1/verification.json).
