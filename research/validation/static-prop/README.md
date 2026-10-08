# VAL-7a — Static propeller measurement reduction

**Status:** offline tool verified with synthetic inputs. Real thrust/RPM/torque measurements and throttle-step lag remain VAL-7. Python 3 standard library only; no simulator or aircraft-data writes. [Evidence](../../../docs/research/validation/VAL-7a/README.md).

From the repository root:

```sh
python3 research/validation/static-prop/test_reduce.py
python3 research/validation/static-prop/reduce.py research/validation/static-prop/example.synthetic.json
```

The CLI prints a deterministic JSON report to stdout. Invalid input exits 1 and prints no report. Output includes the parsed input, exact input-byte and reducer SHA-256 hashes, derived values, standard uncertainties and signed input contributions. Preserve the original input alongside the report; parsed JSON does not retain byte formatting.

## Prepare a measurement

The [example](example.synthetic.json) contains **invented data**, not Stik observations or suggested uncertainty estimates. Replace every reading and source before reporting a physical campaign.

1. Identify the exact propeller manufacturer/model, diameter/pitch, engine, fuel, installation, instrument calibration and raw records in `configuration`. Different propellers and RPM ranges cannot be treated as interchangeable data.
2. Record matched readings from one stabilized operating point. Enter RPM from an identified tachometer or other independently checked measurement; this tool does not infer RPM from throttle, audio harmonics or engine specifications.
3. Confirm negligible ambient axial inflow and document stand alignment, flow clearance, fixture effects and remaining limitations. `static_conditions_confirmed: true` is a declaration, not a measured wind or stability check. A test with appreciable inflow is outside this static reducer.
4. Supply **net axial thrust in N** after rig tare/alignment corrections. A kg-reading scale is not a force in N; convert with documented gravity and uncertainty first. Supply density in `kg/m^3` with its measured or derived source and uncertainty; no default atmosphere is assumed.
5. Supply optional **net propeller shaft torque in N*m**, positive for torque driving the propeller, after relevant rig/friction corrections. Set `torque: null` when unavailable. Do not substitute engine rated power, electrical input power or ideal-disc power for a shaft-torque measurement.
6. Use separate runs for distinct stable conditions or repetitions. Record timing, averaging, corrections and raw-reading identifiers in `notes` and each quantity's `source`. Preserve transients separately; no lag fit is performed here.

## Input contract

Unknown fields, duplicate JSON keys/IDs, nonfinite values and numeric booleans/strings are refused.

| Field | Meaning |
| --- | --- |
| `format` | `openrc-static-prop v1` |
| `evidence` | `synthetic` or `measured`; synthetic quantities are refused in a measured campaign |
| `configuration` | Nonempty configuration and raw-record description |
| `static_conditions_confirmed` | Boolean `true`; only set after assessing the stated static assumptions |
| `runs` | Nonempty array of unique `id`, `notes`, `thrust`, `rpm`, `diameter`, `density`, `torque`; `torque` must be explicitly `null` or a quantity |
| Quantity | `{value, unit, u, kind, source}`; finite positive `value`, finite nonnegative standard uncertainty `u`; `kind` is `measured`, `estimated`, `derived`, `manual` or `synthetic`; nonempty `source` |
| Units | `thrust`: `N`; `rpm`: `rpm`; `diameter`: `m`; `density`: `kg/m^3`; `torque`: `N*m` |

The tool covers powered static operation with positive thrust, RPM and, when supplied, torque. Stopped, reverse-thrust and windmilling cases are outside its scope. In a measured campaign, thrust, RPM and any torque must be `measured` or `derived` from identified measurements/corrections; catalogue (`manual`) or `estimated` operating readings are refused. Density and diameter may still carry explicitly estimated inputs. Evidence labels and measurement-derived sources are declarations, not independent authenticity checks. Derived outputs always have `kind: derived`.

`u` is one-standard-deviation uncertainty in the input's unit, not a tolerance, resolution or 95% interval. Record how it was obtained. A rectangular bound ±a gives `u=a/sqrt(3)` under that distributional assumption. A standard error from repeated samples requires independence; closely spaced sensor readings may be correlated. Zero `u` excludes an error term; it does not mean unknown uncertainty.

Inputs are assumed independent within a run. Correlations between different instruments, shared calibration biases and between-run errors are not modeled. Do not interpret comparison of two reported uncertainties as an independent significance test when the runs share instruments. Large relative errors can invalidate first-order propagation.

## Equations and interpretation

Let `n = rpm/60` in revolutions/s and `A = pi*D²/4`:

| Output | Equation | Meaning |
| --- | --- | --- |
| `ct` | `T/(rho*n²*D⁴)` | Static thrust coefficient |
| `shaft_power` | `2*pi*n*Q` | Mechanical power delivered to the propeller shaft |
| `cp` | `P/(rho*n³*D⁵)` | Static power coefficient |
| `ideal_static_disc_power` | `sqrt(T³/(2*rho*A))` | Ideal open-flow actuator-disc power, excluding swirl/profile/tip/nonuniform losses |
| `static_figure_of_merit` | `ideal_static_disc_power/shaft_power` | Static ideal-disc comparison, **not propulsive efficiency** |

Without torque, shaft power, Cp and figure of merit remain `null`. Ideal-disc power is a theoretical lower bound under its assumptions; it is never substituted for actual shaft power. Propulsive efficiency uses `T*V/P`, which is zero at static airspeed for positive shaft power.

Uncertainty follows the original measurements directly: for a product `f = c*product(x_i**a_i)`, each signed contribution is `a_i*f*u(x_i)/x_i`, and `u(f)` is their root-sum-square. This retains reuse of density/diameter when forming figure of merit; treating derived Ct and Cp as independent would count their shared errors incorrectly.

A nominal figure of merit above one produces a diagnostic, not a clamp or failed CLI. Investigate the measurements, corrections and ideal open-flow assumptions. Fixture interference, recirculation or ground/wall proximity can undermine this comparison. Output uncertainty reaching the nominal value also produces a diagnostic. Neither diagnostic is a physical acceptance gate, and absence of diagnostics does not certify the rig.

Method references: [UIUC Propeller Database](https://m-selig.web.engr.illinois.edu/props/propDB.html), [MIT propeller performance notes](https://web.mit.edu/16.unified/www/SPRING/thermodynamics/notes/node86.html), and [NIST uncertainty propagation](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty). Full sources and scope are in the [evidence report](../../../docs/research/validation/VAL-7a/README.md).
