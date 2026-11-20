# VQ-01c / A33: keep the departing world's resources while Home rebuilds

2026-11-18 · Windows 11, Ryzen 9 5900X, RTX 3090, official Godot `4.8.beta2.official`, Compatibility at 1920×1080 windowed. Source: `main` at `39fa2746a` plus the uncommitted change described here.

## Problem

End flight frees the flight and then rebuilds Home in stages. Godot's `ResourceLoader` cache only keeps resources that are still referenced. Once the flight is gone, Home reloaded every imported model, texture and parked-aircraft mesh from disk. The parked Stik and Avanti meshes alone take 33–36 ms each to load.

Home → Fly did not pay this cost, because the departing Home is retained until the flight is ready.

## Change

[`world_resource_hold.gd`](../../../../../../app/render/world/world_resource_hold.gd) collects the departing activity's disk-backed meshes, materials and textures, without its nodes or generated resources. `app_root.gd` holds that list from End flight, or End ground vehicle, until `_finish_home_build`. Home then reuses the cached objects.

## Results

### Headless field rebuild

Default field, median of 5 builds:

| Variant | Time |
| --- | --- |
| Previous field freed | 1000 ms |
| Resources held | 742 ms |

Collecting the 378 held resources takes 3.6 ms. A first reflection-based collector cost 82 ms and was replaced.

### Native End flight → Home

[`load_ab.py`](load_ab.py) ran the repaired [`loading_probe.gd`](../../../../../../research/performance/loading_probe.gd). It used three interleaved pairs, three cycles each, with Stik airborne. In the baseline, only the collection line was replaced. [Reports](reports/).

| Median of 9 cycles | Baseline | Hold |
| --- | --- | --- |
| End flight → staged Home first draw | 2580 ms (2414–3773) | **1678 ms** (1555–2106) |
| Following Home → Fly first draw | 2824 ms | 2389 ms |

Every Hold cycle was faster than every baseline cycle. Viewport 1920×1080 in all runs. Orphan nodes were 13 in both variants. All six engine logs had zero errors and zero leak reports.

## Probe repair

UI-28-R5b made the return to Home staged, which broke `loading_probe.gd`. The probe still required Home one frame after End flight, so every run failed with "End flight failed to restore Home", in both variants.

The probe now waits, with a 60 s limit, until Home is installed. It records `return_staged`. `return_first_draw_usec` now includes the staged build.

## Limits

- One host and one aircraft.
- Peak memory during the return now includes the flight's resources that Home does not reuse, such as a different aircraft model, until Home finishes. Home → Fly already keeps two complete worlds.
- No Linux, macOS or weak-GPU rows.
- This is loading evidence. Frame pacing is not covered.
