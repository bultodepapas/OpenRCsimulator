# E4b — Adjacent-float sensitivity through the full circuit

2026-10-08 · **Status: measurement complete; platform and physical acceptance remain open.** Owner: Codex circuit-sensitivity agent. Scope: [offline E4b tools](../../../../research/landing/e4b/README.md), disposable app copies and this evidence. No shared runtime, solver, aircraft-data, controller or replay-policy changes.

## Result

The frozen [E4a](../E4a/README.md) circuit completes under joint one-adjacent-float perturbations of `sin_` and `atan2_` toward both positive and negative infinity. Each run covers **28,861 ticks / 120.25417 s**, with **483 sampled boundaries**, runway start, takeoff, circuit, touchdown, rollout and anchored stop.

Both directions retain all selected H7 branch decisions and every tick's engine/anchor modes. No sampled component exceeds its unchanged H9 tolerance. Worst budget usage is **4.00791e-5 of tolerance (0.00401%)**, in the lagged downwash coefficient. This leaves about **24,951× margin** in this experiment; it is not a bound on other platforms or trajectories.

| Component | Maximum absolute error, upward | Maximum absolute error, downward | H9 absolute tolerance |
| --- | ---: | ---: | ---: |
| Position (m) | 7.12852e-12 | 1.01732e-11 | 1e-6 |
| Velocity (m/s) | 2.14051e-13 | 2.28928e-13 | 1e-6 |
| Quaternion component | 2.05391e-14 | 2.08722e-14 | 1e-9 |
| Angular rate (rad/s) | 9.62529e-14 | 1.11318e-13 | 1e-6 |
| Anchor coordinates (m) | 7.13918e-12 | 1.01856e-11 | 1e-6 |
| Downwash lift coefficient | 3.70814e-14 | 4.00791e-14 | 1e-9 |
| RPM / servo command | 0 / 0 | 0 / 0 | 1e-5 / 1e-9 |

Body rows include both current and previous state; peaks are over saved sample boundaries, not all intervening states. [verification.json](verification.json) retains the peak tick, state block and index for each component. Anchor flags are checked exactly, separately from coordinate errors. Numerical force tolerance is not introduced.

## Proof

- Raw and instrumented baseline trajectories match **bit for bit on every tick**, including previous state, loads and auxiliary/discrete state. Both match all 483 E4a saved samples. This checks that branch observation does not change the flight.
- The deliberate H7 aerodynamic early-return mutation changes selected branch sequences on **25,636 ticks**, first at tick **1**, while the complete trajectory remains bit-identical. Numeric tolerances alone would miss this execution-path change; branch evidence detects it.
- Python checks actual wrapper result bits against `math.nextafter` for positive, negative and zero outputs in both directions. Model derivation and checkpoint authentication run before perturbation is enabled.
- [Comparator controls](test_probe.log): 11 checks pass, including a known 1 m / 1e6-tolerance error, first exceeded tick, exact sample count, fractional anchor mode, NaN previous state and infinite loads.
- Existing [H8 checkpoint tests](test_checkpoint.log): 90 pass; [H9 policy tests](test_replay_policy.log): 50 pass; [four airborne goldens](test_golden.log): pass on the same isolated app baseline.
- [Static lint](lint.json): three new GDScripts, no errors or warnings. Actual Godot execution also parses their inherited E4a and app dependencies. Existing aircraft-inertia evidence warnings remain visible; no engine errors occurred.
- [Source identity](source-identity.json) records the isolated committed app snapshot and exact research/fixture/engine hashes. App and research copies are checked against those hashes before execution. Final runs use isolated settings and disposable instrumentation; the source app remains unchanged. Independent Luna Max review confirmed the replay boundary/observer method and identified the copy-provenance race that this check closes.

Full compact reports retain every selected decision and mode tick: [raw](raw.json.gz), [instrumented baseline](baseline.json.gz), [upward](up.json.gz), [downward](down.json.gz), [branch control](branch-control.json.gz). Corresponding `.log` files record engine completion. The tool documentation explains branch-table interning and exact reproduction.

## Interpretation and next step

The long takeoff–landing trajectory passes the same tolerance/1000 sensitivity margin used by the short-airborne H7 experiment, without relaxing tolerances or changing physics. Ground transitions did not amplify these two perturbations into a branch change in this fixture.

Keep E4a as an offline regression until identified Windows/macOS/Linux runs establish actual platform behavior. H7 observes local-flow/stall saturation, global/local aero selection, gear reach, wheel compression/normal load and propulsion type/stopped branches. It does not instrument every anchor, surface-edge or crash conditional; exact anchor/mode timelines and crash guards add bounded coverage, not universal branch equivalence. These runs perturb two wrappers jointly by one adjacent float; they do not bound other functions, larger library errors, compiler behavior, unstable maneuvers or other aircraft.

No full app suite or physics-cost benchmark was rerun: production sources are unchanged and the instrumented timing is not representative. Complete real-session replays and focused H8/H9 integration provide the relevant proof. E4/PT2 release acceptance, the owner's circuit/readability review, independent ground/flight measurements and calibrated propwash remain open.

Ready-to-paste commit message:

```text
E4b: measure full-circuit adjacent-float sensitivity offline

Proof: five 28,861-tick runs; joint sin/atan2 up/down errors consume at
most 0.00401% of H9 tolerance with unchanged selected branches/modes.
Instrumentation is bit-exact every tick; deliberate branch change is
detected on 25,636 ticks despite identical state. Eleven comparator
controls, H8 90/H9 50 checks and four airborne goldens pass.
No runtime/data/tolerance changes; platform and physical gates remain open.
```
