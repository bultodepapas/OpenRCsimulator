# AFC-09 R1: C5e takeoff, circuit, landing, and vacate evidence

Five of the eight C5e cases passed all 22 existing gates. Three cases failed: west headwind exceeded the approach TAS ceiling by 0.0343 m/s, and both south-crosswind cases stalled during the physical runway vacate. All eight selected sorties produced ORFLs; all eight exact replays completed with `solver_changed=false` on the same solver identity. The full case records, report/ORFL/replay hashes, and source identities are in [verification.json](verification.json).

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

C5e remains exploratory. C5f changed only the final-join TAS feedback gain from 0.16 to 0.20 and passed one west-headwind case; that single-case retune against the 0.0343 m/s miss does not qualify the approach envelope. The 22 existing gates remain unchanged. A reporting-only entry-readiness classifier and unit-boundary tests are being prepared; no go-around behavior is claimed or accepted.

The south-crosswind ORFLs show actual rudder-servo commands near ±0.53/±0.57. By 3 s, ground speed had fallen to 0.075/0.165 m/s despite 0.232/0.223 throttle and 4569/4481 RPM; at 5 s it remained near 0.02–0.03 m/s with throttle around 0.237 and RPM around 4780. In the passing west north-crosswind case, speed was 1.714 m/s by 3 s with 0.099 yaw command/servo, 0.069 throttle, and 3427 RPM. The failed south-profile traces have about +0.5 m/s northward wind while the passing north-profile trace has about −0.5 m/s. These observations do not establish a wind-specific cause; they point to a low-speed, high-steering ground-control interaction for a controlled sweep. The model has tricycle gear: the main wheels are fixed and the nose wheel is rudder-linked with an estimated 20° limit.

Next, retain C5e flight controls and sweep one bounded, wind-independent ground-speed policy across both south-crosswind failures, the passing north-crosswind case, and calm. Record speed, throttle, RPM, commanded and actual rudder, nose-wheel steering, all-wheel/contact support, contact events, and the full-airframe footprint throughout exit. The 50-sortie campaign, incursion/abort cases, runtime integration, and physical pilot validation remain open. These are software simulation results, not physical aircraft qualification.

Raw reports, ORFLs, and exact-replay CSVs remain under `D:\OpenRCsimulator-AFC-work\evidence\sorties`; their SHA-256 identities are retained in [verification.json](verification.json).
