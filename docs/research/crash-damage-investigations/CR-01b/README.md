# CR-01b — Hull-plane crossing reconstruction

2026-10-08 · **Status: implemented, verified and integrated; remaining CR-01 presentation/labels stay open.** Bounded continuation of [CR-01a](../CR-01a/README.md) under [CR-01](../../../CRASH-DAMAGE-PLAN.md). [Reproduction tools](../../../../research/crash-damage/cr-01b/).

## Contract

After the existing hull detector triggers, the snapshot optionally reconstructs the earliest hull-point crossing of flat ground along the previous-to-current pose interpolation. It uses the existing renderer's position lerp and shortest-path quaternion nlerp, in float64. This is an interpolation estimate, not the integrated trajectory, continuous collision detection or a physical impulse solver. An enter-and-exit event with every point clear at the detected tick still does not trigger the existing detector.

`impact.crossing` is separate from `impact.detected_state` and its tick-boundary point/velocity. When available it holds the fraction within the interval, hull index, CG position, quaternion and contact point; `method` identifies `position-lerp-shortest-nlerp-v1`. No velocity at crossing is inferred. The selected crossing index can differ from the first penetrating index at the detected tick. Contacts within `1e-12` of a tick fraction keep hull data order. At exactly 180° endpoint separation (`quaternion dot = 0`), the helper preserves the renderer's endpoint-sign convention; the endpoints alone do not distinguish the two equally short rotation paths. Arrays are owned copies; consumers follow the snapshot's read-only convention.

An omitted previous state leaves `crossing=null`. A supplied but invalid/nonfinite state, malformed hull, pre-existing hull contact, numerically unresolved tangent/stationary root, overflowing reconstruction or failed plane residual returns `available=false` with a reason and empty pose arrays. A clear interval reports `no_crossing`. Numeric zero fields in an unavailable result are not measurements. Gear-limit snapshots retain no crossing estimate.

The helper deliberately refuses the whole estimate if any point is ambiguous, even if another has a known root. It also refuses stationary-inflection roots inside the roundoff band. These conservative unknowns avoid inventing contact ordering; they may hide an otherwise recoverable estimate. Refining them is unnecessary for the current diagnostic boundary.

## Derivation and numerical checks

Write the unnormalized, sign-corrected interpolated quaternion as `q(f)=a+f b`. Its squared norm `N(f)` is quadratic and stays positive between valid normalized endpoints on the shortest path. For body point `r`, the NED-down numerator of its rotated offset is

```text
H(q,r) = 2(xz-wy) rx + 2(yz+wx) ry + (w²-x²-y²+z²) rz.
P(f)   = (z0 + f (z1-z0)) N(f) + H(a+f b,r).
```

Thus point-down is `P(f)/N(f)`, and ground crossings are roots of a cubic. The helper partitions `[0,1]` at derivative roots, then bisects negative-to-nonnegative intervals. This detects a tip that enters and leaves the ground while its two endpoint depths are negative; endpoint-depth interpolation and a fixed sample grid can miss that event.

Coefficients are scaled before solving. A stable quadratic evaluation finds the derivative roots; near-zero critical values use an explicit unknown policy (`128` binary64 eps in normalized coefficient units). Bisection is bounded to 60 iterations. The final pose is rebuilt using the actual interpolation operations and checked against the ground plane with relative residual `1e-10` and a 1 m scale floor. This is a numerical residual check, not a claim of physical location accuracy. Nonfinite scale is rejected.

The definition is derived from repository [quaternion rotation](../../../../app/physics/math3d.gd) and [pose interpolation](../../../../app/sim/simulation.gd). A 180° roll fixture has an analytical entering root at `f=1/3` for a lateral tip and a later root `f=3/4` for a negative-Z point. The latter's endpoint-depth chord would incorrectly give `f=0.9`. One hundred seeded mixed-attitude cases compare against direct evaluation of the existing interpolation, independently of the polynomial expansion.

## Verification

- [40 focused checks](focused-tests.log) pass, including the 100 mixed-attitude comparisons, rotating enter/exit, three-root cubics, sign equivalence, ties, invalid input, scale/overflow and actual-session wiring. The [42 existing snapshot checks](snapshot-tests.log) also pass.
- [Four semantic mutations](mutations.json) fail with the unmodified control passing: omitted critical intervals, omitted shortest-path sign, reversed pitch cross-term and omitted tie tolerance.
- [All four complete three-second numeric traces](comparison.json) are byte-identical to baseline (721 samples each). Snapshot-plus-crossing median batch costs are Stik 201.6 µs, Extra 289.4 µs, P-51 271.3 µs and Avanti 227.4 µs. Ordinary flight follows the same operations.
- [Lint counts](lint-counts.json): zero errors and the same 12 pre-existing warnings. [Exact source manifest](verification.json).

The first unmodified suite run [hit exit 124](app-tests-timeout.log) in `test_landing_maneuver.gd` at the 60 s process deadline during concurrent suites, with no failed assertion. The unchanged [baseline landing test](baseline-landing.log) passes all 28 checks in 75.51 s (74.98 s user CPU), also exceeding that deadline on this host. The [full isolated rerun](app-tests.log) passes all **138 sections** with a [validation-only timeout wrapper](timeout-wrapper.sh) raising 60 s process deadlines to 180 s; all source files, test cases and numerical assertions remain unchanged. The shared integration passes [40 crossing checks](integrated-crossing.log) and [42 existing snapshot checks](integrated-snapshot.log); lint remains at zero errors and the same 12 warnings. The full run includes goldens, fleet model contracts, real-app trace checks and 30/60/144 FPS hashes. Existing test-exit ObjectDB cleanup warnings remain (listed in the manifest and also present in CR-01a baseline evidence); the focused crash tests emit none. No engine errors occurred. The candidate is isolated from concurrent work; its baseline is commit `0a496184ab0c583d6c67dd211ad076d9ca01ae62` plus the already verified CR-01a files recorded in the manifest (those exact overlay bytes are now committed in `b0f9e08`). Independent Luna Max review checked the polynomial, ordering, numerical safeguards and conservative unknown policy.

Run from the repository root:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_hull_crossing.gd
app/test.sh
python3 research/crash-damage/cr-01b/mutations.py --godot "$(app/get-godot.sh)" \
  --candidate /path/to/candidate-clone --output /tmp/cr01b-mutations.json
python3 research/crash-damage/cr-01b/compare.py --godot "$(app/get-godot.sh)" \
  --baseline /path/to/baseline-clone --candidate /path/to/candidate-clone \
  --output /tmp/cr01b-comparison.json
```

To reproduce the shared-host deadline adjustment without changing the repository runner:

```sh
mkdir -p /tmp/cr01b-deadline-bin
install -m 755 docs/research/crash-damage-investigations/CR-01b/timeout-wrapper.sh /tmp/cr01b-deadline-bin/timeout
PATH="/tmp/cr01b-deadline-bin:$PATH" app/test.sh
```

The mutation tool modifies only a temporary copy and requires assertion failures, rejecting parse/runtime errors as evidence. The comparison imports both projects, isolates runtime settings and checks complete three-second numeric traces. Its timing batches measure evolving trimmed/stalled ticks and snapshot construction (baseline without crossing; candidate with a resolved crossing). Shared-host batch averages are observations, not per-tick percentiles or target-hardware acceptance.

## Remaining CR-01 work

The renderer does not yet consume this pose. Reference-aircraft component labels, crossing-time kinematics and rendered crossing-pose acceptance remain open in CR-01. Detector decisions, forces, integration, aircraft data, ordinary-flight operations, crash freeze/reset, UI and trace/checkpoint schemas are unchanged.

Ready-to-paste commit message:

```text
CR-01b: reconstruct hull crossing along the existing pose interpolation

Proof: 40 crossing checks plus 42 snapshot checks pass after integration;
four semantic mutations fail and all four 3 s numeric traces are unchanged.
Full isolated app/test.sh passes 138 sections with a 180 s harness deadline;
unchanged baseline landing takes 75.51 s and exceeds the default 60 s.
Crash-only snapshot/reconstruction medians 202–289 us on the shared host.
Renderer handoff and component labels remain open in CR-01.
```
