# AFC-04 R4: production avoidance migration

The source-bound production wrapper passes its retained circuit matrix and the
six nominal moving-encounter cases in both calm and gentle-practice weather.
This qualifies the recorded migration scope only. Static maneuver containment,
prediction-error bounds, infeasible-encounter recovery, multi-seed endurance and
performance remain open.

The [verification receipt](data/verification.json) binds controller
`363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed` to its unchanged
circuit base `1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`.
These runs use the frozen 133-source normalized solver identity
`1526c98431a7dee5206eb992e10f40e436a7ef80d173e8c1dbfe6f1ad8f33b7e`, not subsequent
shared physics changes. Raw source and replay identities are recorded separately.

## Results

The 148-check, 120-second circuit matrix covers one, two and three Stiks in calm
and gentle weather, with a deterministic repeat. Every aircraft completes 28,800
ticks without refusal, fault or crash. Maximum radial error is 4.05 m; minimum
player and peer separation are 122.31 m and 121.74 m. The matrix uses field
surfaces and a stationary pilot reference; the moving survey separately loads
the full retained scenery collision and lake contexts.

| Seed / encounter | Calm minimum player distance (m) | Gentle minimum player distance (m) |
| --- | ---: | ---: |
| 20261020 / head-on | 61.090 | 60.971 |
| 20261020 / crossing left | 65.433 | 65.615 |
| 20261020 / crossing right | 41.338 | 49.205 |
| 20261021 / head-on | 60.781 | 61.395 |
| 20261021 / crossing left | 58.465 | 58.090 |
| 20261021 / crossing right | 65.767 | 65.808 |

Each survey case completes 60 seconds / 14,400 ticks. All twelve nominal routes
meet the unchanged 30 m player-separation gate, without controller refusal,
simulation fault or crash. Minimum AI AGL is 34.09 m in calm and 34.12 m in gentle
weather. The deliberately conflicting parallel two-threat fixture starts inside
the clearance limits and still fails them: player/peer minima are 29.00/9.00 m
in calm and 29.00/8.21 m in gentle weather. It is retained separately, not counted
as a passing nominal route. See the [calm](data/encounter-calm-report.json) and
[gentle](data/encounter-gentle-report.json) reports.

Two additional 20-second calm crossing recordings match the retained R3 weather,
probe and geometry. All six ORFL streams replay exactly: 4,801 rows each,
`complete=true`, `solver_changed=false`. The same-weather R3/R4 comparison aligns
804 trajectory rows. Exact replay establishes reproduction of each recording;
it does not establish equality between the two controller versions.

## Intentional terrain-floor difference

The production wrapper raises an active avoidance target to local terrain plus
35 m when necessary. Even this field's small terrain offsets affect commands:
the initial target is approximately 35.002191 m instead of R3's 35.0 m. Raw
`initial_target_height_matches_nominal=false` flags remain in the reports. They
describe that deliberate target change; no separation or AGL gate was relaxed.

The [matched survey comparison](data/r3-r4-route-delta-summary.json) measures
target-height increases up to 6.958 mm in calm and 6.772 mm in gentle weather.
Resulting horizontal sample differences reach 4.425/2.199 mm north/east in calm
and 5.968/3.288 mm in gentle weather. These are real trajectory differences,
consistent with the added floor. No blanket R2/R3 command or trajectory
equivalence is claimed. A target floor is not a guaranteed flight-path clearance.

## Limits and reproduction

The receipt indexes exact commands, checked-runner diagnostics, source manifests,
recordings, replay reports and comparisons. Large artifacts remain on the D:
evidence volume at the recorded paths and hashes. Initial missing-import failures
are retained separately; the final D mirror has its own imported cache and exact
aircraft-authoring inputs. Test elapsed times are development diagnostics.

The controller's 3 m prediction uncertainty remains an engineering allowance,
not a measured bound. The admitted scope remains airborne Stik circuits at Club
field with one to three experimental companions. No runway behavior, higher
population, arbitrary-player avoidance guarantee or physical validation follows
from these results.
