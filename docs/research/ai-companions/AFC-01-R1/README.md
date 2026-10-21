# AFC-01-R1: external session parity

Two focused increments extend the controllerless session checks without changing
runtime or physics code:

- [Equipment and runway start](session-actuation/README.md): 65 checks pass,
  including Avanti gear/brake/flap commands, actual actuator movement, omitted
  optional fields, atomic rejection, and the first Stik runway-start tick.
- [Failure onset and rollback](session-failures/verification.json): 24 checks
  pass through a real, seeded 20-second roll-jam onset. Ordinary and external
  sessions match every pre-onset physical/control frame, the accepted onset and
  an opposing demand with a jammed servo. An injected rejected onset publishes
  no failure event; explicit restore/resume recovers the exact accepted boundary.

Both use Godot 4.7.2 at 240 Hz and retain source identities and checked-runner
logs. The failure test's first attempt exposed two incorrect test assumptions:
restore deliberately pauses, and faulted kernels refuse checkpoint production.
Its failed source/log remains retained; the corrected fixture explicitly resumes
and compares committed fields directly. No runtime repair was needed.

These are software seam checks, not physical flight qualification. Nonterminal
contact/prop-strike parity, other failure types and broader start-mode coverage
remain open. The existing 10,000-tick manager comparison and earlier 42-check
session result remain historical evidence, not additional assertions in these runs.
