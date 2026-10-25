# GDU-03: exact replay after the final source corrections

2026-10-25, native Windows, official 4.8-beta1. The existing FL-04 suite was
rerun against the final root source after the math-boundary and invalid-start
corrections: **3,247 checks pass**, with zero engine errors or warnings. The
checked collection also passes the existing evidence summarizer.

A newly recorded Ugly Stik flight then passed the actual flight-log CLI's
default-engine export and exact replay. Both reports contain 261 rows,
`complete=true` and `solver_changed=false`; their CSVs are byte-identical and
the existing comparison command reports no divergence. Neither command used
an engine override. The current raw flight-log solver fingerprint is
`08d8086faa1db1cd3370ec755c53e7b5b4f54adc0590b13326cafea4745bffd0`.
This raw-source fingerprint is distinct from the companion qualification's
canonical source hash.

[Verification](verification.json) retains the checked invocation, complete
export/replay/comparison reports and source/artifact hashes. Recordings and
logs remain under `D:/OpenRCsimulator-experiments/gdu03-final-replay/`.
This renews the [earlier launcher/replay evidence](../README.md) on the final
source; it does not change replay admission or establish cross-engine exact
replay, performance or physical validation.
