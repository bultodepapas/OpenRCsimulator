# Independent stage-local rotor factor review

Supported. The only runtime diff selects assembled.factor when the validated
hold-index set is empty. It introduces no global cache, prepared authority,
resource identity or inter-stage reuse.

_assemble already constructs/factors the current full matrix and rejects its
invalid SPD domain. With no holds, _solve_holds copied every matrix/RHS entry in
the same order and called the same factor_body_local/solve_body_local routines.
Reusing that current factor therefore removes duplicate construction only.
No mutation or callback intervenes between assembly and solve. The new zero
hold-torque array matches the old zero-filled array. Ledger, stage factor,
capacity/refusal envelopes and the nonempty-hold path remain unchanged.

Baseline e58d107a and candidate fa52e266 match the root manifest and current-main
base. The full diff contains only this branch. Existing root parity/standalone,
rotor, legacy and actual Stage/drop receipts were inspected; the rejected first
hold-key fixture remains excluded. The benchmark is a local method diagnostic,
not a whole-tick or native performance result.

Seven additional independent strict checks cover the supported zero-rotor and
maximum64-rotor no-hold edges, complete return bytes, operand immutability and
the body-only Euler acceleration from an independent inertia-inverse equation.
All pass. No further source changes requested.

Root production-location checks and exact-byte fixture transport remain needed
when promoting the standalone test/rotor_stage_factor.bin fixture. No app edits
were made by this reviewer.
