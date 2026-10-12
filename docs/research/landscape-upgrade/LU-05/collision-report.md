# LU-05 — Landscape collision and response

Date: **2026-10-11** · Step: **LU-05** · **Status: implemented; focused and integrated checks pass; nearby-query performance target remains open.**

## Result

The float64 flight session now detects swept aircraft-hull contacts against a frozen inventory built from normalized field, scenery, and light data. Stable proxy IDs and a SHA-256 world identity make obstacle selection repeatable and prevent checkpoint restore against a different layout. The simulation remains authoritative; render-space nodes and Godot rigid-body contacts are not used to decide flight impacts.

`app/scenery/collision_world.gd` composes scalar proxies and a 32 m grid. `app/scenery/collision_setup.gd` supplies the normalized, scenery-quality-filtered inputs. `app/sim/scenery_collision.gd` sweeps the aircraft's float64 `crash_hull` points, and `app/sim/flight_session.gd` connects the query through `Simulation.post_step`, so direct simulation steps receive the same decision. The normal no-world path retains its prior state behavior.

The inventory contains a trunk and crown envelope for all 1,680 field trees; seeded shade-tree envelopes; metric boxes for buildings, vehicles, and every current fleet aircraft; separate posts and roof for the open pit shelter; six Avanti-cradle supports; flood/stake lamps; and nearby tangible equipment, fences, hedges, people, animals, and landmarks. Catalog/model dimensions are converted to world N/E/down scalar bounds. The Avanti proxy uses the shared parked-base-height helper. The shelter has no enclosing solid box, so its open volume remains clear.

The installed default inventory built **3,867 proxies in 950 coarse bins** in **149 ms** in the measured native run. Trees use `Treeline.identity()` dimensions; their cards do not provide a physical trunk mesh, so trunk and crown bounds are gameplay estimates. Other catalog bounds likewise describe collision envelopes, not triangle-accurate render meshes.

## Contact and response rules

The detector tests swept points against oriented boxes and vertical capsules. It subdivides shortest-path attitude motion using a 2-degree average-angle target. Because normalized linear interpolation (nlerp) advances nonuniformly at large rotations, each segment expands its narrow-phase proxy by the sagitta computed from that segment's actual endpoint quaternion angle: `R × (1 − cos(Δθ/2))`, where `R` is the global farthest hull-probe radius. A sweep returns the earliest event per obstacle, sorted by time of impact, stable obstacle ID, and hull-probe index. Tests cover a thin-pole pass-through whose endpoints are clear, an attitude arc the unexpanded chord misses, and a 180-degree nlerp central segment where the old average-angle bound misses the arc witness.

Events carry `trigger="scenery"`, contact pose/state, tick fraction, point and velocity, NED normal, obstacle ID/kind/part, response class, normal approach speed, effective mass, and `½ × m_eff × v_n²`. This is an incident normal-energy estimate only; it does not establish structural strength or failure.

Responses use normal speed rather than total airspeed. Hard buildings, vehicles, trunks, shelter parts, and other hard proxies are terminal and enter the existing crash presentation. The provisional gameplay rules for softer classes are:

| Response class | Restitution | Terminal at normal speed | Current behavior |
| --- | ---: | ---: | --- |
| `soft_foliage_impulse` | 0.35 | 22 m/s | Below threshold, bounded dissipative impulse; at/above, terminal |
| `frangible_impulse` | 0.20 | 12 m/s | Below threshold, bounded dissipative impulse; at/above, terminal |
| `light_airframe_impulse` | 0.25 | 14 m/s | Below threshold, bounded dissipative impulse; at/above, terminal |
| `hard_terminal` | 0.00 | Always | Terminal crash |

The impulse uses the aircraft's mass and inertia at the contact arm, checks before/after kinetic energy, falls back to a perfectly inelastic impulse if roundoff would add energy, and adds 1 cm of geometric separation to avoid replaying a stationary touch. These coefficients and thresholds are provisional, uncalibrated estimates. A low-speed lamp or parked-aircraft contact changes aircraft motion but does not yet break the static scenery mesh or persist damage. Foliage is a bounded impulse response, not branch bending, lodging, or an aerodynamically calibrated drag model.

Terminal events retain the first-contact pose for crash presentation. Nonterminal responses are committed before state emission and trace recording. Checkpoint configuration includes the world identity; collision-enabled checkpoints use version 7 while legacy no-world checkpoints keep their existing version family. Reset clears the transient event and retains the installed world. A world cannot be changed after the session advances.

## Verification and measured cost

Native Godot 4.7.2 checks on 2026-10-11:

- `test_landscape_collision.gd`: **51 checks, 0 failures**. Covers inventory, trees, fleet, lamps, open shelter, building/car boxes, high-speed continuous crossing, response classes, energy loss, grazing hits, per-segment nlerp rotation padding, and stable ties. In a staging-only mutation back to the old 2-degree average padding, the large-rotation witness check fails as expected.
- `test_landscape_collision_session.gd`: **25 checks, 0 failures**. Covers nonfatal post-step state and trace, contact-pose crash, checkpoint identity/mismatch, reset, direct-step behavior, and no-world parity.
- `test_landscape_collision_world.gd`: production normalized field/scenery/lights build; **0 failures**. Lead integration also reports its native flight/wreck/pause/reset run at **56/56 checks** with no engine errors.
- All seven owned GDScript files passed native `--check-only`; `python app/tests/check_transcendentals.py` passed.

The production-world query benchmark warms each path for 20 calls and measures 200 full real-hull calls. The car/tree sweeps span 16 m in one query (1,920 m/s), an intentionally severe continuous-collision stress case. This native host run measured:

| Path | Full `contacts()` p95 | `first_hit()` p95 |
| --- | ---: | ---: |
| Empty air | 25 μs | — |
| Near car | 1,280 μs | 1,054 μs |
| Near tree | 850 μs | 795 μs |

The 100 μs p95 target is met in empty air and **missed in nearby-object sweeps**. `first_hit()` currently calls the full sorted-contact query, so it is not an early-out optimization; its measurements are included to show the actual session path. These measurements are host-specific and the 16 m/tick cases are stress paths, not flight-performance acceptance. The one-time default-world build was 149 ms. A dedicated broadphase/narrow-phase profiling pass remains appropriate before calling the query budget qualified.

## Limits

Collision coverage is the supplied discrete `crash_hull` probe set, not a continuous swept aircraft mesh; gaps between its points remain possible. Static proxies do not follow moving scenery or rotor/blade motion. Distant visual ridges remain non-colliding until a matching terrain sampler exists. Low-speed frangible hits do not currently damage their visual prop, and no persistent obstacle damage is serialized. Human contacts are soft and do not depict injury. Proxy dimensions, restitutions, and terminal-speed cutoffs have no independent impact calibration; the reported energy and outcome class are gameplay estimates, not validated structural conclusions.

Research basis and prior constraints: [LU-00 collision audit](../LU-00/collision-audit.md) and [Crash and Damage Plan](../../../CRASH-DAMAGE-PLAN.md).
