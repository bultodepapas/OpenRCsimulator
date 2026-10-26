# Numerical correctness foundation — 2026-10-26

The explicit opt-in assembly/slip/work arithmetic contract completes the
original three-wheel rest tape without a solver refusal. This cohort does not
qualify drop accuracy, fleet data, launch admission or production performance.
[Report and identities](report.json) bind the selected receipts and exact sources.

The [original 10s receipt](rest/original-15-1/report.json) remains complete=true,
15 checks/1 failure: its normal-only moment observable omitted tangent/rolling
reaction. All 2400 ticks, speed/rate, energy and owner-budget checks pass.
Independent [6s](reaction/trace-6s.json) and [10s](reaction/trace-10s.json) full
reaction audits pass 45 checks each, using unchanged force/moment scales. Normal
and rolling pitch reactions cancel; total moment residuals are5.93e-7 and
5.55e-7Nm. Momentum closure is below1.64e-15Nms. Every accepted impulse in those
two 32-impulse audits has independently bounded nonpositive actual-state work.
Replacing only the incomplete observable yields a **derived corrected 15/0**
result from the frozen tape, rather than a rewritten successful runner receipt.

Maximum accounted drift is 1.33096e-9J over 10s, maximum positive tick work
1.76215e-12J, and maximum accepted numerical allowance3.25045e-14J within the
original 1e-11J tick allocation. Inputs use installed P51 hardware with synthetic
normal/aggregate data and frozen half-fuel properties. Raw residuals remain
visible; no physical cap, coefficient, state byte or quality tolerance changed.

The [main checked collection](main-checks/results.xml) has 9 passing invocations,
1550 checks: AR53, Strategy34, Slip19, Work24, QP659, Impulse314, Step167,
Accuracy84 and Electric196. The earlier wrong Accuracy completion marker is
[retained as rejected](rejected-checks/accuracy-wrong-marker/report.json).
[Production payload](production-target/manifest.json), frozen output fixtures
and [fixture transport](production-target/fixture-checkout.json) are separate
from the [original run source](analysis/live-identities.json). Source snapshots
retain exact captured LF/CRLF bytes. The initial raw Git comparison's EOL
mismatches are documented; reconstructed source hashes match the capture.

Local witness reuse reduced builds 162→51 on the retained tick, but profile times
are nested and affected by concurrent load. The full diagnostic run took
1741.875s wall time for 10 simulated seconds. This remains a performance blocker.
Uniform-grid gentle/hard drop work gates still refuse; the branch partition
proposal is [design evidence](analysis/branch-localization-design.md), not an
implemented runtime feature. Loaded lift/braking and240/480/960 qualification
remain open. No rendered application or full fleet benchmark ran here.

The retained subset can restore a new isolated physics project. The helper
verifies the supplied engine hash, relocates absolute imports, preserves the
captured physics settings, and omits unavailable UI/editor/translation assets.
It never overwrites an existing nonempty directory. A fresh import and6s
reaction replay passed45 checks with the **entire lossless trace byte-identical**
to the original (`d471b877a83c5113bafd6223734af1db6308597ed43de0c0f2cabab77bc50ab4`).
The earlier missing-UI import attempt is retained under `reproduction/rejected`.

```powershell
$Godot = 'C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta1_win64_console.exe'
python docs/research/ground-physics/GP-12/evidence/numerical-foundation/restore_snapshot.py --out tmp/gp12-foundation-repro --godot $Godot --mode reaction6
```

Use `--mode restore` to copy only. `--mode rest` intentionally reproduces the
original15/1 observable and exit1; it is a long diagnostic run. Import relocation
and project isolation are recorded in `restoration.json`; they are not claims
of byte-identical source or an application export. [Inventory](files.json) and
[cohort transport](transport.json) cover retained bytes. Prior cohorts are untouched.
