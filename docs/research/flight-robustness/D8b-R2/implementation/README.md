# D8b-R2 experimental implementation

2026-10-11 · **Status: software verification passed, including the full app suite. No production polar selected or physical acceptance claimed.**

[Owning plan, revision 3](../../../../UGLY-STIK-PULLUP-PLAN.md) · [Original diagnosis](../README.md) · [18 investigations](../research-index.md) · [Matrix and provenance](matrix/README.md)

## Delivered behavior

The optional `aero.wing_polar` branch replaces the estimated lift-blend transition with explicit positive/negative tables. The existing aircraft files do not enable it. Normal launches therefore retain the original flight behavior; the reported default-aircraft departure is **not yet a validated, released repair**.

The branch uses 64-bit scalars and packed arrays throughout. Each table supplies angle magnitude, lift magnitude, profile drag and attached fraction, with units/evidence kind/source. The loader rejects unknown keys, missing provenance, nonfinite or unordered samples, invalid coefficient ranges and unsupported endpoint slopes. A companion schema checks structure; cross-row and physical joins remain runtime checks.

Interior derivatives use the weighted harmonic PCHIP rule; endpoint derivatives instead match the existing attached and flat-plate laws, with an additional monotonicity constraint. This is an explicit endpoint-constrained implementation, not a call to SciPy or an identical copy of its endpoint scheme. Its interpolation reference is the [SciPy PCHIP documentation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.interpolate.PchipInterpolator.html); the [method review](polar-method.md) discusses the separate aerodynamic evidence requirements.

Tables describe a **finite-wing strip reference at geometric incidence**, not a measured two-dimensional section polar. The attached induced-map correction is retained in proportion to attached fraction. The same evaluation feeds strip loads and tail downwash. Beyond ±90°, the existing periodic plate continuation applies. No rate clamp, extra damping, automatic rudder, throw reduction, artificial symmetry or gyro removal is used.

Production changes are confined to [polar evaluation](../../../../../app/physics/wing_polar.gd), [data loading](../../../../../app/physics/aircraft_data.gd), [aerodynamic integration and optional strip diagnostics](../../../../../app/physics/aero.gd), [trace identity](../../../../../app/sim/flight_session.gd) and the [experimental launch route](../../../../../app/main.gd). Golden files and default aircraft JSON are unchanged.

## Experimental flight

From the repository root in PowerShell:

```powershell
$polarPath = (Resolve-Path research/flight-robustness/d8b-r2/candidates/intermediate.json).Path
.\.tools\Godot_v4.7.2-stable_win64_console.exe --path app -- --experimental-aircraft-data="$polarPath"
```

`intermediate` is a reproducible sensitivity fixture, not a preferred calibration. `steep` and `retained` are alternatives. The CLI requires an absolute JSON path and accepts only the default Ugly Stik with changes confined to `aero.wing_polar`. Invalid input, another aircraft, electric/scripted routes, changed reference data or a failed trim/start return an error without silently falling back. Input bytes are fingerprinted across validation and loading. The HUD and trace metadata identify the experimental polar. F5 reload is disabled for this route; restart the application to change its input file. Normal session reset/replay uses the loaded model identity.

Use Down arrow for positive elevator. For comparison, launch without the experimental argument. Engine power, entry speed, trim and command history must match before comparing the observed departure.

## Measured simulator response

These are **synthetic simulator results**, not measurements of a real Jensen Ugly Stik. The constructed families have no evidence-backed uncertainty interval. Their differing 25° lift retention factors (0.5, 0.7, 0.9) are sensitivity settings only.

The [static screen](candidate-screen.json) evaluates actual summed aircraft loads at 25 m/s, neutral surfaces, zero body rates; its derivative perturbs roll rate by ±1e-5 rad/s. The angle scan spans −90° to +90° at 0.1° spacing. Values below are sampled extrema, not analytic global bounds.

| Model | Minimum / maximum total CL | Largest positive dMx/dp, N·m/(rad/s) |
| --- | ---: | ---: |
| Legacy | −0.8073 / 1.1051 | 11.1207 |
| Steep synthetic | −0.9474 / 1.1604 | 4.5537 |
| Intermediate synthetic | −0.9500 / 1.1632 | 2.3072 |
| Retained synthetic | −0.9775 / 1.1818 | 0.5458 |

The complete [flight matrix](matrix/README.md) contains 17 scenarios for each of the baseline and three candidates, plus two higher-rate flights: **70 complete finite runs**. For the 25 m/s abrupt positive pull over 5 s, baseline peak absolute roll rate is 6.5536 rad/s (375.5°/s), versus 0.1602 rad/s (9.18°/s) for each candidate; maximum cross-track displacement is 38.57 m versus 7.15 m. The original diagnosis observed 4 s, so its displacement must not be compared directly to these 5 s values.

All three candidates share the curve region seen in this maneuver's recorded tick-boundary strip samples: maximum geometric lookup incidence is 13.7751°, below the first changed interpolation interval (14–25°). The 14° tangent stays zero for all three tables. The diagnostics do not separately record internal RK4 stages. These identical results are **one shared-region observation**, not three independent validations of the post-stall choices. Moreover, total CL peaks changed materially. Removing the large roll alone does not select a physically correct replacement.

The intermediate 480/960 Hz runs each match 1,201 timestamps against 240 Hz. Maximum airspeed differences are 0.0109/0.0163 m/s and alpha differences 0.000840/0.001263 rad. This is sampled-command timestep sensitivity, not proof of RK4 convergence order. No timestep increase is shipped.

The cost screen times 1,200 evolving ticks per repetition, after warmup, including three recorded repetitions. Observed legacy means are 285–333 µs/tick; candidate means span 321–435 µs/tick. Shared-host timing and different evolved trajectories preclude an isolated overhead estimate or target-machine performance acceptance.

## Verification

| Evidence | Result and scope |
| --- | --- |
| [Mass/control contracts](mass-controls.md) | 41 checks: full tensor, coupling, provenance and all eight keyboard keys |
| [Polar tests](../../../../../app/tests/test_wing_polar.gd) | 111 checks: exact attached loads, both branches/joins, bounded interpolation, reverse flow, same downwash law, actual strip-load sum, passive power and malformed input |
| [Session tests](../../../../../app/tests/test_wing_polar_session.gd) | 8 checks: exact replay, model identity, transactional invalid reload, reflected loads and finite spin/recovery with a synthetic fixture |
| [CLI tests](../../../../../app/tests/test_pullup_cli.py) | 3 test methods / 13 launches: valid trace byte identity and rejected route/data combinations |
| [Mutation evidence](polar-mutation.json) | Unmodified control passes; forced negative profile drag and ignored empty provenance are rejected by named checks |
| Candidate generation | All three committed JSON fixtures pass the loader and freshness check; all three pass the companion JSON schema |
| Schema regression | Existing 1,863 schema/loader cases, 142 valid inputs and 20 runtime-only cases pass (4 test methods) |
| [Matrix](matrix/README.md) | Complete/finite checks, matched-time comparisons and retained gzip/raw hashes verified; two full traces retained per 17-case run, all summaries and generated hashes retained |
| Full app regression | **Pass:** `app/test.sh`, 177 GDScript test files plus CLI, model, trace, golden, FPS and ground checks; [log](app-test.log), [exit 0](app-test.exit-code), [source/evidence identities](verification.json) |

The full suite ran in an isolated Linux/WSL clone with a frozen overlay. [Snapshot comparison](suite-snapshot.json) records the later status-label correction, its native CLI recheck and equivalent schema-number spelling; physics code is identical. [Native directed log](native-directed.log) and [native CLI log](native-cli.log) cover the final Windows source.

The spin test's rate thresholds are software regression bounds for its synthetic fixture. They are not independently measured handling bands. The physical-key adapter test uses injected Godot events; neither it nor the research raw-input schedule establishes physical keyboard/OS latency.

Reproduce directed tests with the pinned Godot binary and the full integration run with `bash app/test.sh` on Linux/WSL. The full script includes candidate freshness and CLI tests, in addition to every `test_*.gd` script. To regenerate candidate JSON intentionally:

```powershell
$generator = (Resolve-Path research/flight-robustness/d8b-r2/make_candidates.gd).Path
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$generator"
# Append: -- --check   to check freshness without writing.
```

The [matrix README](matrix/README.md) supplies complete run/comparison commands. Original diagnosis and matrix captures retain their historical source hashes; later integration hashes must not be substituted for those run identities.

## Still required for a production repair

1. Identify a defensible Jensen/reference-build polar and control/mass bounds, including the falling lift branch, drag, Reynolds number and coefficient basis. Current synthetic families cannot supply that evidence.
2. Compare actual-load lift limits, roll growth, recovery and held-out maneuvers; perform fixed-input strip refinement and target-machine timing. Identify any transient-state model only if evidence requires it.
3. Complete pilot-flown loops, reduced-throw/hold variations and owner keyboard handling acceptance on identified builds. Then select data, document intended trajectory changes and deliberately update goldens if necessary.

Gate 2 stays open. The implemented path makes that final selection observable, reproducible and testable without presenting invented coefficients as aircraft measurements.
