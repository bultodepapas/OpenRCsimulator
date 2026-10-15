# R05-B1: live Glow mass at contacts

2026-10-14. Implemented software slice of [R05-B](R05-B-dynamic-mass-integration-boundary.md). Existing finite-fuel Glow installations now use current mass, CG and inertia for hull compliance, hull impact thresholds, scenery impulses and lake incident energy. This does not implement Jet fuel, a general open-system vehicle law or event-substep continuation.

## Corrected inconsistency and convention

Glow's airborne derivative already used its current fuel inventory, but contact preparation and swept collision response used the initial wet mass/tensor and treated fixed-datum arms as CG arms. Burning fuel therefore changed airborne acceleration without consistently changing contact mobility or impact energy.

The body origin `O` remains the initial wet CG. Geometry uses `r_O`; the current CG is `c` from `O`, and `r_C=r_O-c`. For a stationary contact normal transformed to body axes:

```text
beta = 1/m + (r_C × n)ᵀ I_C⁻¹ (r_C × n)
effective_mass = 1/beta
J = -(1+e) * normal_closing_velocity / beta * n
delta_omega = I_C⁻¹ (r_C × J)
delta_v_O = J/m - delta_omega × c
K = 0.5*m*|v_O + omega × c|² + 0.5*omegaᵀ I_C omega
```

Point velocity remains `v_O + omega × r_O`. Continuous contact moments stay about `O`; Glow's existing derivative translates them to current CG once. Geometry never recenters. The shared physical-tensor validator checks the inertia and the supplied inverse's consistency. Invalid samples return an explicit failure, separate from valid no-hit/empty-force results.

Hull geometry is prepared once; near the ground, coefficients use the stage's mass snapshot and reuse its inverse. Tensor validation happens once per coefficient loop. An airborne reach rejection avoids coefficient work. The terminal hull rule retains its previous-endpoint velocity convention and samples previous-endpoint mass accordingly.

Swept scenery/lake contacts interpolate fuel at the same fraction as the existing interpolated body state. The selected event retains that exact mass-properties dictionary; impulse response does not resample it at the endpoint. Scenery geometry ordering remains based on contact fraction, stable obstacle ID and probe index. Lake threshold classification samples mass before deciding whether a candidate is terminal.

## Transaction and compatibility

`Simulation.post_step_joint` supplies detached body and continuous endpoints to the contact filter, before auxiliary projection and commit. It cannot replace the integrated continuous tail. Only one legacy or joint filter may be selected. FlightSession buffers contacts, crashes and scenery damage until `stepped`; a later projection failure clears the buffers and restores the accepted body, resource, auxiliary and mode state.

Glow checkpoints, configuration hashes and trace metadata identify `fixed-datum-live-mass-contact-linear-fuel-v1`. Missing or different markers are refused without altering the current flight. The propulsion law and continuous layout remain unchanged. Non-Glow sessions retain the original contact API and refuse an unexpected Glow marker. Wet reference metadata is explicitly labeled; `glow_state().mass_properties` supplies live values. Fresh reset/trim/runway initialization still uses the configured full tank, so its existing wet properties agree with its actual initial fill.

## Evidence

[Source identities and scenario summary](glow-contact-20261014/identity.json) retain old/new recordings, CSV and exact replay reports, plus complete solver-source archives. The [fixture](../../../../../research/physics-audit-2026-10-14/remediation/r05b/contact_recording.gd) uses the actual catalog Glow hull, 25% remaining fuel, an 8 m/s lamp approach, source cut and a spinning propeller. Initial body/internal/command arrays are identical between laws. Both scenarios use the same 60 post-conditioning commands; all four final recordings replay **61/61 rows**, `complete=true`, `solver_changed=false`, against their own retained solver.

| Contact probe | Old effective mass (kg) | Corrected effective mass (kg) | Old normal energy (J) | Corrected normal energy (J) |
|---|---:|---:|---:|---:|
| Foremost hull point | 2.62289908 | 2.53289908 | 84.1209742 | 81.2345163 |
| Rightmost wing point | 0.561907652 | 0.552823793 | 18.0210616 | 17.7297312 |

Both contacts occur at the same interior fraction before and after the change. The [wingtip comparison](glow-contact-20261014/wingtip-comparison-02.json) reaches maximum component differences of 0.0180104 m position, 0.122401 m/s velocity and 0.0506554 rad/s angular rate over 0.25 s; attitude separation reaches 0.00833440 rad. These are consequences of the corrected model, not measured error reductions.

The independent [6×6 generalized-mass oracle](../../../../../research/physics-audit-2026-10-14/remediation/r05b/fixed_datum_impulse_oracle.py) checks 56 scalar identities, including anisotropic inertia and moving-surface work, with maximum direct-versus-matrix impulse error below 2.3e-16 ([retained output](glow-contact-20261014/fixed-datum-oracle.json)). Production GDScript tests separately cover 34 dynamic-contact checks, 12 quaternion/Simulation transaction checks and 15 real Glow session checks. The last test injects a nonfinite final projection after an interior-fraction impact: no candidate event, damage or tick escapes, then retry reproduces the same fraction and sampled properties.

The [focused isolated batch](glow-contact-20261014/focused02/verification.json) passes 20 physics/replay suites. Its water presentation test fails because that copy lacks imported resources and parent authoring sources; that failed attempt is retained. The [integrated native rerun](glow-contact-20261014/integrated-native/verification.json) passes all three new suites and the water checkpoint test with the real resource context. The full canonical Linux gate remains owned by [R11](../R11/README.md).

## Remaining limits

Crash presentation is not fully connected to live mass. The current `CrashDirector._start` reads `sim.mass/inertia`, which remain wet references, for generic impact severity and wreck mass. Its scenery branch receives the sampled effective-mass scalar but still supplies wet total mass to severity; lake-bank presentation recomputes the scalar from wet values. Declared fuel metadata also does not consume Glow's live fuel state. Water aftermath and soft-touch effects do not perform an additional mass calculation. These are presentation/damage-estimate consumers, not a second force path, and they remain open in the [R05-B handoff plan](R05-B-dynamic-mass-integration-boundary.md#remaining-crash-presentation-handoff). The live crash files have concurrent CR-track changes; this slice does not overwrite them or claim that boundary is complete.

The existing nonterminal response accepts the body at the interpolated impact plus impulse while the continuous resource tail completes the full tick. It does not integrate the post-impact remainder, and linear fuel interpolation is not an event-integrated resource solution. R05-B/R07's joint event continuation remains open.

The impulse uses the current **locked-rotor** inertia and preserves relative RPM, matching the inherited contact convention. The rigid-body energy identity does not establish the response of a freely spinning shaft. That requires a coupled impulse solve with carrier block `I_C-I_r*a*aᵀ`, `delta_Omega_relative=-a·delta_omega`, shaft state projection and full-system energy checks. Terminal water impacts provide incident diagnostics; they do not implement buoyancy or a moving-water impulse response.

Glow retains its declared uniform-tank, co-moving-efflux law. No slosh, exhaust thrust, new fuel-flow geometry, partial-fill start UI, helicopter resource dynamics or ground-vehicle mass matrix is inferred. The tests establish implementation consistency, not physical validation of the contact constants or aircraft.
