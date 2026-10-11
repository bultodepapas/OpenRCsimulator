# E5b — Nose-over contact mechanics

2026-10-09 · **Status: software verification on Linux; real soft-ground and pilot validation remain open.** Owning step: [ROADMAP E5b](../../../../ROADMAP.md). [Reproduction tools](../../../../research/ground-contact/e5b/README.md).

The existing force law needs no change to produce nose-down motion under sufficiently large ground drag. E5b adds regression checks and corrects the roadmap's conflation of a **tail-up pitch-moment threshold** with **first tail lift from three-point support**. No runtime physics, aircraft data, field data or product start mode changes.

## Oracle and events

For a symmetric main pair, let `d` be the horizontal distance from the CG forward to the main contacts and `h` their vertical distance below the CG. Combined normal force `N` and backward drag `D` give nose-up pitch moment `M = N*d − D*h`. Gravity acts through the CG. With no other pitching moment, zero moment requires `D/N = d/h`. This is a dimensionless **effective drag/normal ratio**, not necessarily the lateral tyre coefficient or friction deceleration divided by gravity during a transient.

The independent trigonometric oracle rotates the loaded body-frame contact vector `[x,y,z]` at pitch `θ`: `d = x*cos(θ) + z*sin(θ)` and `h = z*cos(θ) − x*sin(θ)`. In the symmetric test poses, `θ = 0` means a level body with the tail already clear; the geometric three-point pitch is `atan2(z_main − z_tail, x_main − x_tail)`.

| Model-derived quantity | Extra 300S .60 | P-51D 1/4 |
| --- | ---: | ---: |
| Tail-up main arm d (m) | 0.0902001 | 0.1527627 |
| Tail-up main arm h (m) | 0.2444800 | 0.4393540 |
| Tail-up pitch-moment threshold d/h | 0.3689468 | 0.3476986 |
| Geometric three-point pitch (degrees) | 10.862 | 13.892 |
| Three-point rigid tail-lift threshold d/h | 0.6035673 | 0.6510193 |
| Simulated tail separation, 256× stiffness, 3840 Hz, slow ramp | 0.6034310 | 0.6509180 |
| Separation error relative to rigid threshold | −0.0226% | −0.0156% |

All values are **derived from provisional model inputs**, not measurements of real aircraft. [Full numeric report](verification/full.json) and [input hashes](verification/verification.json) identify the source data. For compliant fixed-point contacts, `h` is the actual force arm, including penetration below the nominal plane. It differs from CG height above that plane; replacing it with nominal height would change the oracle. E6a owns wheel-circle geometry.

## Fixtures and proof

- **Tail already up:** mains carry weight, the tail is clear and rolling speed is 3 m/s. Static evaluated forces obey `M = N(d − Crr*h)` below, at and above the threshold; ±2% samples have opposite moment signs. Independent bisection locates zero moment. A separate case requests large resistance with a friction-circle cap below the threshold and confirms it cannot create a nose-down moment.
- **First tail lift:** start on all three wheels, settle for 1.5 s and ramp the test copy's rolling coefficient at 0.05/s or 0.025/s. A horizontal tow through the CG cancels horizontal ground force without adding torque, maintaining resolved rolling speed. Aero and engine forces are absent. Scale stiffness by 64 or 256, damping by its square root and onset/sag inversely; run at 1920/3840 Hz. All eight tail-separation trials meet the ±2% rigid oracle. Increasing stiffness moves the threshold closer; doubling tick rate and halving ramp rate each change it by less than 0.1% of the oracle. Tail force is zero by the sampled geometric separation; the report brackets separation between adjacent ticks.
- **Synthetic resistance patch:** ordinary production gear, 3 m/s, no tow, no aero/engine. Mains start 60 mm before a rectangular patch. Two multipliers request `Crr = 0.8*d/h` and `1.3*d/h`; the corresponding factors are 7.379/11.991 for Extra and 9.272/15.067 for P-51. These are **authored test stimuli**, within the supported surface-factor bounds, not calibrated turf. Both direct force probes and 150 ms trajectories exercise lookup at the wheels. At 240/480/960 Hz, the higher-drag patch reverses the initial nose-up motion and ends with negative pitch rate; the lower-drag case continues nose-up. Tails remain clear and gear does not collapse. Adjacent-rate final pitch differences stay below 0.1° (worst 0.0481°); the abrupt boundary does not show monotonic convergence. This verifies onset, not a completed overturn or crash response.

The first patch assertion incorrectly required the attitude itself to become nose-down within 150 ms. Its [retained failed run](initial-patch.log) shows negative pitch rate while attitude remains slightly nose-up. The final checks require the motion to reverse and pitch to fall from its peak, matching the event being tested; no aircraft coefficient or observation duration was tuned.

The [focused verification](verification/verification.json) contains **125 passing assertions** (including report output), a **95-assertion fresh-clone quick control**, and four intentionally rejected defects: a shortened pitch-force arm, uncapped longitudinal drag, ignored patch resistance and surface lookup at the CG. Defects live only in a disposable clone. The runner requires the intended assertion to fail and rejects engine errors or incomplete reports; a runtime error cannot count as fault detection. The clone uses the recorded current input overlay, so uncommitted inputs are not silently replaced by HEAD.

The [full existing app suite](app-tests.log.gz) passes all **154 sections**, including 125 GDScript test programs, E5a, goldens, aircraft contracts and trace/frame-rate checks, with zero engine errors. After adding E5b to `app/test.sh`, its exact appended command block [passes separately](app-hook.log); the entire suite was not repeated for that registration. [Validation](validation.json) records both runs and confirms that only `test.sh` changed among 617 tracked app files. New-script lint has zero errors/warnings; app lint retains twelve existing warnings. The full suite also emits eight ObjectDB leak warnings in existing input/menu tests, alongside normal aircraft-provenance warnings; this is not a warning-free application claim.

## Limits and next evidence

The ramp deliberately stiffens test copies beyond production values and uses a tow. It is a rigid-limit numerical experiment, not a simulated field coast-down or a proposed aircraft configuration. The patch has no soil deformation, rut, obstacle, wheel digging or terrain-height change. Neither fixture runs the full flight/crash session or establishes prop-strike timing, a full overturn, damage severity or pilot recovery. Existing crash-session tests remain separate.

Whether real grass or a soft spot supplies these effective drag ratios is unknown. Physical acceptance needs configuration-matched CG/contact geometry, wheel and surface condition, drag/coast-down observations and recorded pitch/control history. Keep that evidence separate from these force-law checks.

Ready-to-paste commit message:

```text
E5b: verify taildragger nose-over thresholds and synthetic patch response

Proof: independent contact-moment oracle, refined three-point tail separation,
240/480/960 Hz patch response, fresh-clone control and four rejected isolated
force/surface defects; full existing app suite and the new E5b hook pass.
Runtime physics and aircraft data are unchanged.
Tail-up moment reversal is distinct from first tail lift; physical acceptance remains open.
```
