# AFC-12 R2: continuous static trajectory clearance

2026-10-20, Godot 4.7.2, Windows. The production tree contains the independently
tested [`static_trajectory.gd`](../../../../app/ai/companions/static_trajectory.gd)
helper. Runtime maneuver selection does not use it yet. A clear result certifies
the supplied geometric polyline and error allowance, not a controller's ability
to fly it.

Configuration validates the actual collision inventory, aircraft contact model,
terrain surfaces, lake identity and pilot station. The caller must supply the
same model and environment installed in the aircraft session. A failed
configuration invalidates queries. Empty scenery requires explicit opt-in and
still retains terrain and pilot protection. The result identity includes the
normalized geometry, aircraft radius, surface data, lake and world identity.

The checker encloses all hull/gear probes and the propeller disc with a sphere,
then expands obstacles by that radius, caller-supplied path error, a 2 m margin
and 1 micrometre numerical padding. Slab clipping checks every continuous
segment. People, the pilot station, shelters and pavilions retain 30 m horizontal
exclusions at every altitude. Terrain and wave upper bounds retain a 20 m
airborne clearance. These conservative rules can reject flyable paths; runway
operations and low passes require their own qualified policies.

The existing scenery spatial index is rebuilt from validated enclosing bounds;
incoming bins are never trusted. Oversized inventories or query bounds fall
back to all proxies. Limits are 10,000 proxies and 129 points. Error allowance
must bound interpolation, tracking and prediction error over the whole path;
zero describes only the supplied polyline.

The integrated check passes **40 checks, zero errors or warnings**:

```powershell
python tools/godot/run_checked.py --warnings-as-errors --timeout 90 --require-text "static trajectory: 40 checks, 0 failed" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_companions_trajectory.gd
```

Coverage includes fast between-point crossings, tangency, parallel and stationary
segments, geometric near misses, error inflation, protected footprints, terrain
and water, malformed contexts, oversized-index fallbacks and invalidation. An
independent sampled-point oracle found 58 intersections across 600 seeded
segments with zero omissions. A second oracle exercises complete assessments
across 250 paths and 12 generated obstacles. Sampling is a supplementary oracle,
not a proof of every continuous intersection.

A follow-up differential oracle compares the rebuilt spatial index against an
all-proxy scan at positive and negative 32 m cell boundaries. Across 360 paths
and 36 sparse boxes it finds 96 blocked paths, 264 clear paths with successful
index pruning, and zero result/proxy-identity mismatches. The existing oversized
inventory and query cases also exercise the conservative fallback. Original
38-check receipts remain preserved alongside this source-bound follow-up.

Both 33-point and 129-point nominal circuit paths clear the current full field
(6,092 proxies, world identity in the retained log) with a 0.5 m geometric
interpolation allowance. This allowance is not a qualified controller error
bound. The maximum-work fixture completes all 1,280,000 slab checks and preserves
the correct clear result. Independent review found no concrete geometric false
negative for correctly bound input context. No timings, supported population,
flight containment or physical realism are established here. Runtime binding,
controller uncertainty and isolated target-host cost qualification remain open.

[Verification receipt](verification.json) preserves source hashes and the check
sequence. The full-world snapshot is identified by the integrated run's log;
the scenery owner continues to change the shared tree independently.
