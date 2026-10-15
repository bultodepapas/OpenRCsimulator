# R11: complete-session timestep refinement

2026-10-14. [Raw runs and comparisons](results.json), [execution log](probe.log), [source and harness identity](identity.json), [reproduction probe](../../../../../../research/physics-audit-2026-10-14/remediation/time_refinement.gd).

The Stik and Jet each complete three seconds at 120, 240, 480 and 960 Hz: eight fault-free runs, with byte-identical initial body, auxiliary, continuous and command arrays across grids. Commands are held at trim except for simultaneous increments `[roll=0.15,pitch=0.10,yaw=0.20]` during `[0.5,1.0)` seconds. These boundaries align exactly on every grid; throttle is held. States are compared at common 30 Hz observations. The source identity remains unchanged throughout.

Maximum differences from the 960 Hz run:

| Aircraft | Rate (Hz) | Position norm (m) | Velocity norm (m/s) | Angular-rate norm (rad/s) | Attitude angle (rad) |
|---|---:|---:|---:|---:|---:|
| Stik | 120 | 0.0182360 | 0.00781649 | 0.0145892 | 0.00197508 |
| Stik | 240 | 0.00852051 | 0.00338075 | 0.00716585 | 0.000913045 |
| Stik | 480 | 0.00283553 | 0.00114787 | 0.00241339 | 0.000307170 |
| Jet | 120 | 0.0494676 | 0.0274160 | 0.0379097 | 0.00395775 |
| Jet | 240 | 0.0203747 | 0.0127113 | 0.0163599 | 0.00173048 |
| Jet | 480 | 0.00656318 | 0.00434107 | 0.00549240 | 0.000581367 |

The differences decrease as the step shrinks. Ratios of successive 240/480 versus 480/960 differences are approximately 1.93–2.11, consistent with first-order convergence of this complete sampled-control/session experiment. RK4 body integration alone does not make the once-per-tick actuator and auxiliary updates fourth-order accurate. The 960 Hz run is a numerical reference, not physical truth; these measurements do not supply an aircraft handling acceptance tolerance or validate untested events, contacts, stalls or weather conditions.

Attitude distance uses sign-aligned unit quaternions and `4*atan2(norm(q-q_ref),norm(q+q_ref))`, avoiding cancellation in small-angle `acos` comparisons. This run precedes the R05B Glow-only contact extension; its retained source is the R11 `final-scenarios-03` solver.
