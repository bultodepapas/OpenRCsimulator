# AFC-09 R1: C5e takeoff, circuit, landing, and vacate evidence

Five of the eight C5e cases passed all 22 existing gates. Three failed: west headwind exceeded the approach TAS ceiling by 0.0343 m/s, and both south-crosswind sorties timed out during physical runway vacate. All eight selected sorties produced ORFLs; all eight exact replays completed with `solver_changed=false` on the same solver identity. The full case records, report/ORFL/replay hashes, and source identities are in [verification.json](verification.json).

| Direction | Weather and seed | Existing gates | Physical result |
| --- | --- | ---: | --- |
| East | Calm | 22/22 pass | Vacated in 5.892 s |
| East | Headwind, 20261015 | 22/22 pass | Vacated in 6.108 s |
| East | North crosswind 0.5 m/s, 20261025 | 22/22 pass | Vacated in 5.933 s |
| East | South crosswind 0.5 m/s, 20261027 | 20/22 pass | North-side taxi timed out at 45 s |
| West | Calm | 22/22 pass | Vacated in 5.588 s |
| West | Headwind, 20261039 | 21/22 pass | Vacated; gate TAS 12.5343 m/s, 0.0343 above 12.5 m/s |
| West | North crosswind 0.5 m/s, 20261044 | 22/22 pass | Vacated in 5.633 s |
| West | South crosswind 0.5 m/s, 20261051 | 20/22 pass | North-side taxi timed out at 45 s |

The first east-headwind attempt has a `checks=0` session-setup failure and no ORFL. It is retained in the evidence record, excluded from the eight selected cases, and replaced by the successful `-r1` run above. There were no setup failures in the selected matrix.

C5e remains exploratory. C5f changed only the final-join TAS feedback gain from 0.16 to 0.20, with fixed bias still zero. In the paired west-headwind seed, it reached the same predicted gate location with measured TAS 12.3304 m/s versus C5e's 12.5343 m/s, below the unchanged 12.5 m/s ceiling. This one-case feedback result does not qualify the approach envelope. The 22 existing gates remain unchanged. The reporting-only entry-readiness classifier now has 99 passing boundary and malformed-input checks; it does not steer or initiate a go-around.

The south-crosswind ORFLs show loss of taxi speed after the landing gear crossed the runway end and the rolling factor changed from 2.5 on the strip to 7.5 on rough grass. Eastbound nose/main-right/main-left crossing times were +1.5917/+1.7833/+2.0208 s from taxi start; westbound nose/main-left/main-right times were +1.7625/+1.9167/+2.3000 s. At nose crossing, speeds were 1.2988/1.3891 m/s, throttle commands 0.1103/0.1011, rudder-servo commands −0.5311/+0.5689, and RPM 3853/3766. Both cases later crawled near 0.03 m/s with throttle near 0.24 and RPM near 4780. The terrain transition and speed loss are observed in sequence, but these runs do not isolate the transition as the sole cause. The detailed measurements and touchdown-to-stop distances are in [verification.json](verification.json).

The historical 22-gate vacate check is weaker than full-airframe clearance: it marks the runway clear after all three gear points remain north of the runway edge by 0.5 m for 0.25 s. That flag is sticky and would not reset on re-entry; the final check does not require hull clearance. The separate hash-bound reconstruction of all eight exact replays found no wheel-clear re-entry in these cases, but none of the six physically completed exits ever cleared every accepted crash-hull point. At the best point, the least-forward gear or hull point remained 0.493–0.546 m south of the edge+0.5 m plane. The two south-crosswind timeouts remained 5.055–5.844 m short and exceeded the candidate side-corridor bounds. All six completed paths spent 60 ticks with gear clear and hull not clear. The CSV records geometric wheel-down state but not per-wheel support force or stiction. See [verification.json](verification.json) for case metrics, touchdown snapshots, analysis source identity, and the full report hash.

The research candidate taxi state requires gear and hull clearance, all three gear points down, and a nonnegative side-corridor margin for a continuous 0.25 s. It resets dwell on any violation, keeps the side-corridor check live through the exit endpoint, rechecks current clearance and wheel-down state at completion, and refuses completion after any recorded error. Its focused state test passes 21 checks; this is unit evidence only, not a new physical taxi qualification.

The 50-sortie campaign, incursion/abort cases, runtime integration, and physical pilot validation remain open. No arrival shift or aircraft/physics retune is qualified by this evidence. These are software simulation results, not physical aircraft qualification.

Raw reports, ORFLs, and exact-replay CSVs remain under `D:\OpenRCsimulator-AFC-work\evidence\sorties`; their SHA-256 identities are retained in [verification.json](verification.json).
