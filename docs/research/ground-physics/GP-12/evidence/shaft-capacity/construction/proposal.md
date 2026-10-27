# GP-12 stable shaft capture in integrated capacity

Next dependency after the shared capacity operator, not stock activation.

The existing Electric producer appends finite internal shaft friction after
currently loaded wheel rows. The new capacity packet retains unloaded wheel
rows, so the old ordinal cannot be reused. Source.electric_fixed_voltage derives
constant bearing capacity as Kt * no_load_current_a; this is an independent
torque bound, never a tire normal-load coefficient.

Proposed contract: optional sample.interval_capture = {rotor_index, row_id}.
Both fields have exact types. A nonempty old sample.capture requires the new
mapping for the integrated law; an orphan mapping is refused. Resolve the stable
row_id against the validated packet, then use existing Impulse._capture_mapping
to prove the row is exactly +e_sigma with zero bias and its own scalar group.
Require row_contact_indices=-1 and independent_rates equal the source's existing
finite bearing rate in the legacy capture row. Both mappings name the same
declared nonnegative rotor. Pin the semantic mapping through all predictor and
actual evaluations, including before/after half kicks. Resolve the local ordinal
only at the shared impulse call. Old laws keep their old path and complete bytes.

Electric gets an explicit opt-in capacity wrapper around its existing evaluator,
not a second source force or solver. Wheel context must be prepared by the
existing sealed Traction context for the exact installed mechanics and flat
provider. Append one stable, model-bound internal shaft row to that packet, with
normal factors zero and independent bearing rate. Preserve the legacy sample
rows; only the new operator consumes the packet and interval_capture. The
trusted owner still binds held controls/source/configuration and interval domain.

Checks before promotion: real electric fixed-voltage producer in airborne,
loaded, unloading and brake-command cases; unchanged wheel packet coordinates
and source stage; stable shaft identity as legacy ordinals change; finite shared
capture and startup/stop with work and momentum accounting; malformed/orphan,
wrong rotor/row/rate/group and midstage identity mutations refuse atomically;
existing old-law output oracle remains exact. Use existing physical raw error
gate and source-domain certificate. No relaxed errors to accept a source stop.

Finite battery remains refused until event localization integrates charge-zero
and shaft boundaries into this same operator. Do not wrap ElectricBatteryStep
or ElectricStop as a second contact integrator. ESC supervision stays once per
accepted outer tick.
