# LU-21 staged collision validation

Scope: `.tools/lu16-stage/app`, after support-surface changes. Native render timing had ended before the solo headless benchmark. No runtime source outside the staged collision files was edited.

The requested `test_scenery_collision.gd` and `test_crash_checkpoint.gd` names are not present in this stage. The closest staged checks were run: `test_landscape_collision.gd` for scenery collision, `test_crash_snapshot.gd` for crash snapshot/checkpoint handling, plus both general and landscape checkpoint tests.

| Check | Result |
| --- | ---: |
| `test_landscape_collision_support.gd` | 24 checks, 0 failures |
| `test_landscape_collision.gd` | 51 checks, 0 failures |
| `test_landscape_collision_coverage.gd` | 54 checks, 0 failures |
| `test_crash_snapshot.gd` | 42 checks, 0 failures |
| `test_checkpoint.gd` | 90 checks, 0 failures |
| `test_landscape_checkpoint.gd` | 18 checks, 0 failures |

All six processes exited 0. The checkpoint and crash-snapshot tests printed the existing aircraft inertia diagnostic (`Jyy = 0.3871 kg·m2`, 2.11× the scaled UltraStick25e value); it did not fail either check.

## Production query benchmark

Raw command and full output are in [`benchmark_landscape_collision.log`](benchmark_landscape_collision.log). Godot 4.7.2, 240 Hz physics, 80 m/s, 8-point real crash hull, 20 warmups and 200 measured calls per method and case. The production world contained 3,877 proxies and 1,039 bins; world construction took 154.025 ms. Identity: `481b7b5dc048ef33dab7c4c6bcd261236a7143903f81c9af33e0930fdc4b5f13`.

The independent baseline oracle and candidate selected identical first-hit IDs in every measured case: `none` in empty air, `vehicle:cars:00:car_hatch:2` near the car, and `tree:shade-tree:shade-trees:00:crown:2` near the tree.

| Rate | Case / displacement | Baseline first hit p50/p95/p99/max | Candidate first hit p50/p95/p99/max | Candidate full contacts p50/p95/p99/max |
| ---: | --- | --- | --- | --- |
| 120 Hz | Empty / 0.667 m | 25/29/35/47 µs | 25/29/36/39 µs | 24/28/32/36 µs |
| 120 Hz | Car / 0.667 m | 406/501/545/597 µs | 290/349/410/422 µs | 289/352/390/407 µs |
| 120 Hz | Tree / 0.667 m | 460/475/481/487 µs | 322/333/344/475 µs | 319/331/365/375 µs |
| 240 Hz | Empty / 0.333 m | 13/26/30/62 µs | 13/27/28/57 µs | 13/26/28/35 µs |
| 240 Hz | Car / 0.333 m | 461/481/499/513 µs | 323/335/342/443 µs | 320/333/342/372 µs |
| 240 Hz | Tree / 0.333 m | 358/461/488/656 µs | 250/321/349/383 µs | 252/317/352/408 µs |

Empty-air queries remain below 100 µs. Near-obstacle candidate queries do not meet the 100 µs target: first-hit p95 is 321–349 µs at 240 Hz, and full-contact p95 is 317–333 µs.

Raw per-check outputs and exact commands are in the matching `test_*.log` files in this folder.
