# EL2a-E1 — electric runway startup and flight envelope

**Status:** software qualified (2026-10-11). Synthetic software evidence;
physical validation and Gate P remain open.

[Verification manifest](verification.json) records final source/artifact hashes,
commands and completion counts. [Ready-to-use commit message](commit-message.txt).

## Runtime correction

The generic `FlightSession.reset_on_runway()` helper previously asked every
propulsion kind for a positive steady idle RPM. An enabled electric source at
zero duty has a stopped rotor; its positive-RPM equilibrium search is correctly
unbracketed. Passing that NaN into the ground-pose solver refused the start.

The helper now seeds electric RPM at exactly zero. The combustion branch is
unchanged. Launch metadata explicitly describes the electric source as enabled,
with zero duty and the rotor at rest. The ground solver, coupled rotor/body
dynamics, battery law, aircraft data and existing golden flights are unchanged.

This corrects the generic simulation/test helper. The selected runway-start
menu route remains Stik-only; it does not promote the synthetic electric
fixtures into the catalog or enable electric runway starts from Home.

## Startup evidence

The [original reproduction](startup/README.md) compares baseline rejection,
baseline manually seeded zero RPM, and the corrected public helper on Windows
and Linux. Candidate startup agrees with the manually seeded baseline on both
platforms. These are synthetic model outputs, not measured hardware values.

`test_electric_runway.gd` exercises both 4S/6S configurations, fixed-bus and
dynamic-battery variants, and both runway directions: 177 checks. It requires
exact rotor rest, three loaded wheels, a stationary parked pose, analytic
auxiliary-only charge/heat/energy, powered startup current, byte-exact replay
through a fresh owner, empty-pack refusal, replenishment on restart, unchanged
airborne restart, and complete state restoration after an invalid runway pose.

The disposable qualification runner requires a clean import, the exact positive
completion count and clean engine logs. It rejects two executable defects:
restoring the old combustion idle search and inventing an electric idle of
1 RPM. Original source bytes are restored before the final positive rerun.
Both platforms pass 177 checks, both defect controls and the restored rerun.
Reports and engine logs: [Windows](runway-windows/report.json),
[Linux](runway-linux/report.json).

## Maneuver qualification

The maneuver runner uses existing synthetic battery datasets and the real
session/crash detector. Each planned duration is fixed before stepping; pauses,
faults, crashes, missing ticks, nonfinite samples and incomplete CSVs fail.
The independent trace checker retains EL2's electrical and energy equations
and tolerances, adding exact sample continuity and variable tick rates.

Landing exploration found the inherited pilot's original 94 m/6 m approach
touched the 4S model approximately 0.132 m before the runway threshold, with a
minimum longitudinal wheel margin of −0.136 m. Lateral margin remained above
5.27 m; halving the timestep reproduced the longitudinal miss. The final
scenario moves the approach starting position 2 m farther along the runway
for both packs and both rates. No aircraft or control-law parameter is fitted
to conceal that result.

[Original approach metrics](original-landing-metrics.json) are explicitly
labelled exploratory summaries and carry their local CSV fingerprints.

The final matrix has twelve cases per platform: two packs, three maneuvers and
two rates (240/480 Hz). Each platform checks 106,572 CSV rows. The profiles are:

| Maneuver | Duration | Pilot and positive outcome |
| --- | --- | --- |
| Takeoff | 8 s | Stopped rotor at the threshold; full throttle, neutral surfaces; liftoff before the runway end, heading error <15° throughout the roll and liftoff confirmation, wheel paths ≥0.5 m inside lateral runway edges, terminal wheel-clear dwell ≥0.5 s |
| Stall/recovery | 20 s | Start at 150 m and 1.4 estimated one-g stall speeds; power-off accelerated pull-up until positive alpha reaches model `a2`; unload for 0.75 s, then powered recovery; recover within 10 s, lose <80 m, remain above 35 m, and finish with ≥1 s stable flight |
| Landing | 46 s | Existing 12 m/s, 6 m approach pilot, with the declared +2 m start shift; every wheel path stays ≥0.5 m inside the runway after first touchdown, every contact sink <1.2 m/s; stop and hold ≥2 s, <2 mm drift and <0.02 m/s terminal speed |

"Stable" recovery means speed ≥1.2 estimated one-g stall speeds, absolute alpha
<8°, bank <20° and climb between −5 and +8 m/s. This is an accelerated-stall
excursion/recovery test, not a measurement of one-g stall speed. Acceptance
bands are software regression limits, not physical aircraft specifications.

Representative 240 Hz results (Windows; Linux agrees to roundoff):

| Measurement | 4S | 6S |
| --- | ---: | ---: |
| Liftoff time / distance | 3.588 s / 35.270 m | 4.288 s / 43.883 m |
| Liftoff speed | 19.475 m/s | 19.157 m/s |
| Peak stall alpha | 18.346° | 18.312° |
| Recovery latency / altitude loss | 3.313 s / 21.875 m | 3.321 s / 20.097 m |
| Touchdown beyond threshold | 1.868 m | 2.737 m |
| Maximum contact sink | 0.445 m/s | 0.451 m/s |
| Minimum wheel/runway margin | 1.864 m | 2.733 m |
| Stop time from approach start | 20.896 s | 20.958 s |

The largest 240→480 Hz differences are 2.084 ms in liftoff/recovery/stop timing,
0.040 m in liftoff distance, 0.006° in peak stall alpha and 0.011 m in recovery
altitude loss. The largest energy-ledger residual is 9.85e-5 J against the
unchanged 2e-3 J limit. Two resolutions establish the declared consistency
bands; they do not establish an asymptotic convergence order.
The smallest lateral wheel margin through the takeoff roll and liftoff
confirmation is 2.132 m, above the declared 0.5 m floor.

Final reports: [Windows matrix](envelope-windows/report.json),
[Linux matrix](envelope-linux/report.json). They include every criterion,
refinement difference/limit, CSV SHA-256, source/fixture hashes and electrical
residuals. Engine logs are retained beside each report.

## Regression and delivery

The isolated `app/test.sh` run completed 180 GDScript test suites and 72 Python
cases, plus the existing model/trace/golden/FPS/contact gates, without engine
errors. The new 177-check runway suite is part of that run. The final E5b gate
completed all 125 checks. [Full log](full-suite.log).

The offline tool suite also passes, including twelve new trace-verifier tests
with truncated/duplicate/mistimed/nonfinite/configuration/electrical corruption
controls and electrically self-consistent but incorrect runway initial states.
[Offline log](offline-tools.log). The tests are registered in
`research/test-tools.sh`; no old golden was re-recorded.

The baseline clone was `38847b4`; only the two runtime hunks and the new runway
test were overlaid for the full app run. All 388 copied app `.gd`/`.json` and
`project.godot` files match the delivered app after line-ending normalization.
The shared workspace's separate consolidation process committed part of the
research during execution; this task did not stage or create a commit.

## Reproduce and interpret

Commands and scripts: [tool README](../../../../research/propulsion/el2a-e1/README.md).
Use fresh output directories and the pinned Godot executable. Do not run
mutations against the shared app. Evidence records source/fixture hashes;
raw CSVs are generated by the runner.

This work verifies a synthetic 4S/6S operating envelope. It establishes no
measured Timber conversion, physical takeoff distance, real stall speed,
endurance, ESC low-voltage cutoff, windmilling or reverse-torque behavior.
The current unilateral rotor model's unsupported reverse-breakaway case still
fails explicitly. The existing 500 µs performance gate remains unchanged.

## References

- [Godot physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html):
  fixed physics cadence and `_physics_process`. This repository integrates its
  own float64 state; engine cadence alone does not prove deterministic replay.
- [Godot SceneTree](https://docs.godotengine.org/en/stable/classes/class_scenetree.html):
  script exit status. The runner additionally rejects engine errors and checks
  positive completion counts because exit zero alone is insufficient.
- [EL2a](../EL2a/README.md), [EL2a-P2](../EL2a-P2/README.md):
  unchanged battery accounting, stop/exhaustion events and numerical limits.
