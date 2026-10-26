# Trace and recording consumer scope

Highest active legacy Trace before this slice is v16. Fixed brake output is an
outer v17 with fixed_brake_base_trace_format naming the original underlying
layout; existing unbraked/retractable output bytes and versions are unchanged.
The new column is cmd_wheel_brake, with no synthetic gear columns or auxiliary
gear pair. Named input_layout and the conditional law/index identify its role.

* app/tools/flight_log_cli.gd: ORFL reader/export/replay has explicit fixed-brake
  input roles under fixed-gear-shared-wheel-brake-input-v1 (already installed).
  It is independent of legacy Trace format versions. Candidate ORFL row replay
  is checked with the detached Session owner; this draft's runtime source pins
  are separate from Log.solver_identity(), which reads installed source paths.
* tools/flight_log/flight_log.py: generic ORFL-export CSV inspector accepts named
  optional cmd_wheel_brake. Its required ORFL CSV columns differ from legacy
  Trace columns; it is not presented as a v17 physical validator.
* trace_role_contract.py: focused test helper for generic v17 inspection only;
  validates identity, named roles, base format, columns, finite bounded command
  samples and chronology. Explicit physics_validation_available=false. No force
  equations or command projection. Hostile role/base cases are required.
* app/tests/check_trimmed_flight.py, check_wind_trace.py,
  check_atmosphere_trace.py, flap_trace_contract.py, mass_trace_contract.py:
  their physical validators retain their existing versions/equations and refuse
  v17. No nonzero brake column is stripped to pretend a prior oracle qualifies
  braking. Support would require an explicit equation/contract extension.
* Dated research landing/propulsion/range/glow trace checkers retain exact
  v3/v7/v8/v14 version gates. They are deliberately not retrofitted.

This is bounded new-role inspection and input/transaction verification, not a
new trace validation platform or stock braking qualification. Stock wheel
profile bytes are frozen. The six canonical ORFL files remain immutable and
candidate comparisons explicitly report solver_changed=true.
