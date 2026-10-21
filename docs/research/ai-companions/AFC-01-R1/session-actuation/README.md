# AFC-01-R1 session actuation parity

The focused session test compares the external tick adapter with the ordinary session path for Avanti gear, brakes, and flaps, including actual AUX movement, optional-field persistence, atomic rejection, and one runway-start tick. Its shared tick assertion compares byte-exact simulation arrays, continuous state, modes, commands, and raw controls. The Stik unsupported packet check now requires separate gear, flap, and brake rejection reasons while preserving the staged valid packet.

The current source passed 65 checks with 0 failures. The pre-reason-coverage 65-check run and source are retained under [pre-reason-coverage-65](checks/pre-reason-coverage-65/run_checked-report.json) and [its source copy](sources/pre-reason-coverage-65/test_companions_session.gd), alongside the earlier pre-tick-comparison run under [prior-65](checks/prior-65/run_checked-report.json). This is software-level session-seam evidence; it does not qualify failure behavior, contact behavior, or physical flight performance.

See [verification details](verification.json), the [tested source](sources/test_companions_session.gd), and the [current runner report](checks/current-65/run_checked-report.json) and [engine log](checks/current-65/engine.log). The earlier session baseline is recorded in [AFC-00-06](../../AFC-00-06/README.md).
