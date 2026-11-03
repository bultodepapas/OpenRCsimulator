# GDU-12 application suite evidence

The initial beta2 headless run completed unit shards 0–3 before a stale guard in
`test_landscape_population_assets.gd` was corrected. Their rosters, compact
console excerpts and audits remain in `rosters/`, `console/` and `shards/` as
pre-fix evidence. Shard 4 was [interrupted](interrupted-shard-4/summary.json)
and is not a completed shard. Full checked-run collections, console logs and
JUnit files remain under `D:/OpenRCsimulator-experiments/gdu-beta2/final-units/`.

A fresh post-fix suite is being collected from a common frozen source: eight
unit shards and a separate integration run with the parse complement. The old
receipts are excluded because each is bound to the pre-fix roster digest.
The [source comparison](post-fix/source-comparison.md) records the newer Windows
checkout, line-ending differences and the four explicit EOL-rule exceptions.
After that snapshot, the root mechanical-audio test received a
[test-only teardown assertion](post-fix/mechanical-audio-final/README.md). Targeted
Windows and Linux checks cover the changed test; the frozen suite receipts keep
their original source and roster identities.

The checked-run summarizer validates each run's report, diagnostics and log
hash. Its JUnit `skipped` count does not count conditional skips printed inside
a successful Godot script, so those lines are retained separately. Native
extensions were not staged in the initial pre-fix RAM fixture. The separate
ext4 fixture has Linux aircraft and ground native libraries staged; actual
native execution is established only by the corresponding checked branch, not
installation alone. Corresponding [native headless](../native-headless/) and
[native rendering](../native-rendering/) checks provide separate evidence for
some conditional skips. Physical-device and physical-model qualification are
not established by these software receipts.

For a shard's `checked_collection_sha256`, sort the checked-run directory names
by their UTF-8 names and concatenate, for each directory, its UTF-8 name, one
NUL byte, the 32 raw bytes of the report SHA-256 and the 32 raw bytes of its
engine-log SHA-256. The resulting SHA-256 binds the full raw collection without
duplicating every startup log here. Individual raw JUnit and console hashes are
recorded separately.

The [first integration attempt](failed-integration/summary.json) exited 1 when
its H7 scratch copy exhausted disk space. Its 688-script partial parse receipt is
retained only as failed-attempt context; it is not part of the final roster set.
The run also reported that `references/battery-energy` was absent, so its input
hash check was skipped. A fresh integration run is required to finish the gate.
