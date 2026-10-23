# F4U-12: verification of the F4U Corsair 1/4.5

Run 2026-10-23 for the [F4U plan](../../../F4U-PLAN.md) on Windows 11 with the official Godot 4.7.2, headless. This is software verification of the experimental catalog aircraft. It is not physical validation, which is F4U-14.

## Summary

| Check | Result | Evidence |
| --- | --- | --- |
| [verify_f4u.gd](../../../../app/aircraft/verify_f4u.gd): asset, registry, control signs, flaps, clearance envelope, gear, oleo, presentation, contacts, crash release | 28/28. The clearance-envelope check fails, as it should, on a 40° rudder mutated in a disposable copy | [verify_f4u.log](checks/verify_f4u.log) |
| Clearance sweep | The author's g1.3 sweep is all clear: BVH triangle intersections at 5° steps (not continuous collision detection) over ailerons ±25°, flaps 0–50°, elevator ±25° and rudder ±35°. The rig's hinge ranges are those envelopes; the full throws (13.5°, 11.2°, 25.9°) and the 30° flap limit lie inside them. The gear-door audit finds no contact over retraction frames 0–100 in steps of 5 | [clearance.json](../../../../assets/source-deliveries/f4u-corsair-g1-3/f4u_corsair/g1_3/previews/clearance.json), [door-audit.json](../../../../assets/source-deliveries/f4u-corsair-g1-3/f4u_corsair/g1_3/previews/door-audit.json) |
| Handling probe ([F4U-07 probe.gd](../../../../research/f4u-corsair/F4U-07/probe.gd)): loader, trims, flare authority, top speed, flight modes | 22/22 before and after the [incidence correction](../F4U-07/README.md#method-corrections-found-while-deriving) | [probe.log](checks/probe.log) (before), [F4U-07](../F4U-07/README.md#verification-2026-10-23-windows-godot-472) (after) |
| Generators | Six Corsair generators and five shared builders current; `test_models.py` 17 OK | [generators.log](checks/generators.log), [shared-generators.log](checks/shared-generators.log) |
| Catalog suites after the throw correction | 13 suites, 0 failures: rates, catalog, UI, Workshop descriptor and experiments, render contract, trace metadata, crash energy, economy, powertrain audio, retractable gear, flight log, night kit | [suites/](checks/suites/) |
| Flight-test card `ft-card-v5` | 34/40 valid, exit 0, no script errors, on the current data (earlier runs 29/40 and 33/40, see below) | [ft/run3-incidence/](ft/run3-incidence/summary.md) |
| Software baseline `.orfl` | 2,400 ticks; exact replay `complete: true`, `solver_changed: false`; export and replay CSVs byte-identical | [baseline](#software-baseline) |
| Ground handling against the CARF manual | Tail-up landing consistent; full stick at full power gives a stalled, wing-dropping lift-off; nose-over not reproduced | [below](#ground-handling) |
| Retracts, flaps and smoke in the production flight scene | 15/15 | [below](#retracts-flaps-and-smoke) |

## Flight-test card

Every run used `research/flight-test/run.py --aircraft f4u-corsair-250 --jobs 4`.

| Run | Tree | Data SHA-256 (file) | Valid |
| --- | --- | --- | --- |
| [run1-throws-at-max](ft/run1-throws-at-max/summary.md) | `16b82bcb`, clean | `cee5e2ef…` | 29/40 |
| [run2](ft/run2/summary.md) | `c0fe45fd`; only another track's camera files dirty | `4780a4a4…` | 33/40 |
| [run3-incidence](ft/run3-incidence/summary.md), current | `11bd41d3` with this step's data and other tracks' uncommitted startup and shader edits ([run.json](ft/run3-incidence/run.json)) | `69816c7e…` | 34/40 |
| [run3-same-tree-pre-incidence](ft/run3-same-tree-pre-incidence/summary.md) | The same tree, via `--app` on a disposable copy holding the pre-incidence data | `a76daa38…` | 33/40 |

**Throw correction (run 1 → 2).** The card flies the data's full throws, the `full` rate profile. The first run showed a full-aileron roll of only 55°/s at the start speed. The cause: F4U-07 had put CARF's single recommended set into `max_throw`, so radios and the card had no travel beyond it, and keyboard and gamepad flew 80 % of it. Now CARF's set is the normal rate and the full throw is that set ÷ the median low/high ratio of three Corsair manuals ([F4U-07](../F4U-07/README.md#method-corrections-found-while-deriving), [LEARNINGS](../../../LEARNINGS.md)). The second run rolls at 72°/s (pb/2V 0.076). The inverted pass, the full-rudder knife-edge, the split-S and the cross-controlled stall became valid. [compare.md](ft/compare.md) lists 571 changes. The 1-g power-off stall (14.99 → 14.85 m/s), top speed (62.5 → 62.6 m/s), best climb (16.8 m/s), glide ratio and modes are unchanged or move under 1 %.

Two stall metrics moved through the card pilot, not the wing. The 45° turning stall went from 0.93 to 1.34 Vs√n and the inverted stall from 1.37 to 2.00 Vs. Both are `elevator limit (mush)` breaks: the elevator held at its stop for 1 s near the stall start, at speeds above the 1-g stall. The card's stall loops work in stick units, so more throw per stick raises their gain. Read these two numbers as the card's answers for this airframe, not stall speeds.

**Incidence correction (run 2 → 3).** Run 3 flies the wing at the F4U-1 handbook's +2° incidence instead of the R59 visual master's 0.5° ([F4U-07](../F4U-07/README.md#method-corrections-found-while-deriving)). It also carries the [TR 586 recheck](../F4U-07/tr586-recheck-2026-10-23/README.md) (CL_max −0.03 %) and [GP-02-R1](../../ground-physics/GP-02/rolling-2026-10-23/README.md)'s rolling law. Between runs 2 and 3, other tracks also changed the solver (D10-R3-R1 forward-flow body side force, GP-02-R1, mass-inventory and kernel guards). The same-tree run with the pre-incidence data reproduces run 2: 33/40 with the same invalid set, and only seven values move by more than 1 %. The incidence correction alone therefore accounts for the run 2 → 3 differences ([compare-incidence-same-tree.md](ft/compare-incidence-same-tree.md); [compare-run2-run3.md](ft/compare-run2-run3.md) lists all 640 changes). The main ones:

- The inverted spin becomes an inverted spiral that recovers, so `spin_inverted` is valid.
- Idle glide ratio 9.5 → 10.3.
- Spiral halves in 16 s instead of 27 s; hands-off heading change 12° → 8°.
- Four-point roll over-rotation 22.5° → 14.8°.
- Inverted flight needs more down elevator: −0.317 instead of −0.108 stick on the inverted pass.
- Stall start 14.6° → 13.4° body angle; the 1-g stall is 14.79 m/s (14.85 before).

### Results (run 3)

| Quantity | Corsair | P-51 1/4 ([FT-05](../../flight-test/FT-05/README.md)) |
| --- | --- | --- |
| Power-off stall, wing drop | 14.79 m/s, left | 15.63 m/s, left |
| Maximum level speed | 62.1 m/s | 58.2 m/s |
| Best full-throttle climb | 16.9 m/s | 16.9 m/s |
| Full-aileron roll at start speed | 72°/s | 138°/s |
| Loop height / time | 100 m / 6.5 s | 105 m / 6.7 s |
| Upright spin: time per turn / recovery turns | 1.38 s / 1.05 | 1.33 s / 0.94 |
| Lift-off speed / ground roll (card's tail-up take-off) | 20.4 m/s (1.38 Vs) / 29 m | 21.4 m/s / 35 m |
| Landing: touchdown speed / attitude / rollout | 18.5 m/s / 5.2° / 122 m | 19.4 m/s / 5.8° / 171 m |
| Hands-off 30 s: heading / height change | 8° / 0.3 m | 109° / −9.3 m |
| Phugoid at start speed: period / ζ; spiral | 12.4 s / 0.22; halves in 16 s | 10.8 s / 0.19; halves in 66 s |

The card rolls on the full throw: pb/2V 0.076. At CARF's normal-rate throw it is 0.062 ([F4U-07](../F4U-07/README.md#results-provisional)), near the full-size 0.064 (NACA RM A7C05). The P-51's 138°/s is pb/2V 0.136. The card's maximum level speed comes from its own Vmax search; the F4U-07 probe's full-throttle trim gives 53.5 m/s.

### Invalid tests in run 3

| Test | What happened | Reading |
| --- | --- | --- |
| `knife_edge` | Full throttle, both ways: bank held at 92°, sinking 0.84 m/s (right) and 0.53 m/s (left) with rudder to spare; the card accepts 0.5 m/s or a saturated rudder | The card's height loop. With full top rudder the airplane climbs 12 m/s at about 45° pitch while slowing from 50 to about 30 m/s: the Corsair declares the fuselage side-force law (D10-R3), the P-51 file does not |
| `inverted_speeds` | Start speed (23 m/s): rolled back to 147°, sinking 11 m/s at −0.83 stick and α −10°; 0.6 and 0.8 Vmax are held | The slowest inverted pass lies beyond the down-elevator authority, as with the Timber in FT-05. The stabilizer setting is the F4U-4's against an assumed reference line |
| `inverted_turn` | Left: climbing 2.5 m/s at 134.5° bank; the right turn is held | The card's height loop |
| `outside_loop` | Completed (−4.32 g, 153 m) with 23.5° of sideslip and a 38° heading change: a rolling departure | The pitch–yaw–roll coupling below |
| `snap_roll` | Right: 348°/s peak, stops 156° late and exits at 63° bank. Left: autorotation ends after 4.5° | Right: the card pilot. Left: the airplane's answer |
| `stall_turn` | No up-line in all four cases. The full-throttle pull from 50 m/s rolls right at about 0.15 rad/s, reaching about 100° of bank by 2.8 s, so the nose never reaches 80° of elevation | Nose-up pitch yaws the nose right through the propeller: 0.047 kg·m² of propeller, hub and crank (2.4 × the P-51's) at about 4,900 rpm gives 12–19 N·m at 0.5–0.8 rad/s. The 2.5° right thrust adds about 3 N·m. The resulting sideslip acts on the gull wing's dihedral term. The card's pull holds α and damps the roll rate but does not hold the bank |

None of these is a script error. The coupling behind the stall turn and outside loop follows the declared inertia and dihedral data. Whether a real CARF Corsair needs that much aileron in a full-power pull is F4U-14 evidence.

## Ground handling

[ground_handling.gd](../../../../research/f4u-corsair/F4U-12/ground_handling.gd) tests the CARF manual's notes ([source.json](../../../../assets/aircraft/f4u-corsair-250/source.json) `handling`) from the qualified runway start. Throttle comes up over 1 s, the elevator stick is held fully back, and the rudder and steerable tail wheel hold the heading. Result: [ground-handling.json](checks/ground-handling.json).

| Case | Tail wheel leaves | Lift-off | Least pitch |
| --- | --- | --- | --- |
| 50 % power, normal-rate elevator (CARF's 20 mm) | 2.78 s, 12.3 m/s | 3.06 s, 14.2 m/s | 13.6° |
| Full power, normal-rate elevator | 2.60 s, 12.3 m/s | 2.84 s, 14.1 m/s | 13.8° |
| Full power, full elevator throw | 2.76 s, 13.5 m/s | none: right wingtip strike at 17.6 m/s | 12.7° |
| Full power on the brakes, normal-rate elevator | 2.45 s, 10.4 m/s | 2.94 s, 14.0 m/s | 13.2° |

These runs use the current data, with the handbook's +2° wing incidence. Before the incidence correction all four cases lifted off three-point at 13.9 m/s, the tail leaving 0.05–0.24 s before the mains.

- **Tail-up landing, consistent.** The three-point attitude is 15.25°, beyond the 13.4° stall start: a three-point touchdown needs a stalled wing, which matches the manual's "challenging" three-point landing. The card lands tail-up, touching down at 5.2°.
- **Full power with the stick held fully back: a stalled lift-off.** With the full 11.2° of up elevator the Corsair leaves the ground on a stalled wing, drops the right wing and strikes the tip (`probe_wing_right_te`). This is the classic warbird torque-roll take-off, and the reason the manual asks for half power. With CARF's normal-rate elevator it lifts off at 14.1 m/s.
- **Full-power nose-over, not reproduced.** The manual warns that "at full power the low-rate elevator cannot hold the tail down and the model may nose over". In the model, the attitude stays within 2.6° of the three-point attitude, and the tail wheel leaves 0.24–0.5 s before the mains; the airplane does not nose over. At 15°, the thrust's vertical component carries up to 34 % of the weight (static thrust 28.0 kgf).
  - In a free roll, the thrust (0.531 m above the main contacts) is largely balanced by the airplane's own acceleration acting at the CG (0.43 m above them). A quasi-static estimate puts tail lift at low speed at about 1.7 times the weight in thrust; this model has T/W 1.30.
  - The estimated 2.0 N·m brakes resist with about 42 N against roughly 275 N of static thrust, so they cannot hold a run-up.
  - Grass drag, a different main-gear position or CG height, or stronger brakes could explain the difference. Each needs evidence (F4U-14) before any data change.
- **Not checked:** the manual's flap warning (30° maximum because large flaps weaken low-speed elevator response).

## Retracts, flaps and smoke

[systems_check.gd](../../../../research/f4u-corsair/F4U-12/systems_check.gd) runs `main.tscn` with the Corsair, starting airborne at 150 m on the keyboard input path. It requests the gear and flaps through the same session calls as the G and F keys, and switches on the smoke as the H key does. Run 2026-10-23 on Windows with the official Godot 4.7.2 (Compatibility renderer, 1920×1080): 15/15 ([systems.json](checks/systems.json)).

| System | Result |
| --- | --- |
| Retracts | Down and locked in 4.0 s and up in 4.0 s (data: 4.0 s each way); the rendered main wheel travels 0.347 m and returns to its stowed pose within 0.1 mm; retraction is accepted in flight |
| Flaps | 30° in 2.4 s (data: 2.5 s); the rendered hinge reaches 30.00°. At the same flight state, full flap adds 201 N of lift and 9.5 N of drag and a 21 N·m nose-down moment |
| Smoke | The stock profile has two emitters at the exhaust: show smoke (672 particles) and engine exhaust (60). With the smoke key on and the engine running, both emit |

A connected gamepad owns the throttle and the smoke: the H key works only without a radio or gamepad, and with one connected, smoke follows the AUX assigned with J. From above, the lowered flaps look light grey. They carry the wing's own material and texel colour (`paint_wing`, `#11243d`, roughness 0.36): the tilted semi-gloss surface reflects the bright horizon. With the same material made fully matte in the same frame, they render dark blue like the wing. Screenshots were reviewed but not kept.

## Software baseline

[record_baseline.gd](../../../../research/f4u-corsair/F4U-12/record_baseline.gd) records a bounded 10 s tape from the catalog airborne start, each input added to the start's trim and marked: aileron right and reversal, an elevator doublet, a rudder pulse, then a full-throttle step. It is not piloted; it fixes a tick and input tape for future candidate comparisons under the [flight logging workflow](../../../FLIGHT-LOGGING.md).

| File | Content |
| --- | --- |
| [baseline.orfl](baseline.orfl) | 2,400 ticks at 240 Hz, markers at ticks 240, 360, 720, 1200 and 1680 |
| [baseline-exact.json](baseline-exact.json) | Exact replay: `complete: true`, `solver_changed: false`, solver `1d06d516…` (commit `11bd41d3`), aircraft input `69816c7e…` (current data) |
| [baseline.csv](baseline.csv), [baseline-summary.json](baseline-summary.json) | Export (SHA-256 `33214fff…`, equal to the replay's CSV) and its summary |
| [exact-comparison.json](exact-comparison.json) | Export against replay: zero difference in every channel |
| [candidate-gp02r1.json](candidate-gp02r1.json), [candidate-gp02r1-comparison.json](candidate-gp02r1-comparison.json) | History: the first tape (data `4780a4a4…`, solver `3f148883…`) as an open-loop candidate after [GP-02-R1](../../ground-physics/GP-02/rolling-2026-10-23/README.md) changed the solver to `6d0169f7…`: exact replay is refused as it should be, and the candidate's CSV is byte-identical over 2,401 rows, since the airborne tape never touches the ground |

Commands, from the repository root, with `GODOT` set:

```sh
godot --headless --path app --audio-driver Dummy --script <repo>/research/f4u-corsair/F4U-12/record_baseline.gd -- --out=<new .orfl>
python3 tools/flight_log/flight_log.py replay <new .orfl> --out <new directory>
```

The tape was re-recorded on 2026-10-23 after the [incidence correction](../F4U-07/README.md#method-corrections-found-while-deriving). Its trim elevator input fell from 0.279 to 0.072, and the first tape replayed on the new data climbed 19 m in 10 s (trim mismatch, not handling); the first tape stays in git history. A physics or solver change makes `solver_changed` true. From then on, the tape gives candidate comparisons, not exact equivalence. The piloted baseline stays with F4U-14.

## Limits

These are model predictions with a scripted pilot in calm air. The card's results depend on its pilot ([rules](../../../../research/flight-test/README.md#pilot-rules)). The CARF handling notes are qualitative. Nothing here measures a real Corsair.
