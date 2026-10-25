# GP-08 integrated regression receipts

2026-10-25: **15 selected scripts, 841 checks, zero failed checks**. The existing
[collection summarizer](results.xml) verified all 15 checked invocations passed
with complete, consistent raw logs and reports. Selection takes the latest
successful receipt per unique script across the two integration batches;
duplicate earlier runs are not added to the total.

| Script | Checks | Retained receipt |
| --- | ---: | --- |
| `test_ground_accidents.gd` | 55 | [report](test_ground_accidents/report.json), [log](test_ground_accidents/engine.log) |
| `test_ground_accident_session.gd` | 29 | [report](test_ground_accident_session/report.json), [log](test_ground_accident_session/engine.log) |
| `test_wheel_coupling.gd` | 84 | [report](test_wheel_coupling/report.json), [log](test_wheel_coupling/engine.log) |
| `test_flight_statistics_detector.gd` | 67 | [report](test_flight_statistics_detector/report.json), [log](test_flight_statistics_detector/engine.log) |
| `test_flight_statistics_lifecycle.gd` | 51 | [report](test_flight_statistics_lifecycle/report.json), [log](test_flight_statistics_lifecycle/engine.log) |
| `test_flight_statistics_resets.gd` | 48 | [report](test_flight_statistics_resets/report.json), [log](test_flight_statistics_resets/engine.log) |
| `test_flight_statistics_store.gd` | 49 | [report](test_flight_statistics_store/report.json), [log](test_flight_statistics_store/engine.log) |
| `test_flight_statistics_writer.gd` | 18 | [report](test_flight_statistics_writer/report.json), [log](test_flight_statistics_writer/engine.log) |
| `test_aircraft_contact_session.gd` | 63 | [report](test_aircraft_contact_session/report.json), [log](test_aircraft_contact_session/engine.log) |
| `test_ground_contact.gd` | 23 | [report](test_ground_contact/report.json), [log](test_ground_contact/engine.log) |
| `test_soft_contacts.gd` | 36 | [report](test_soft_contacts/report.json), [log](test_soft_contacts/engine.log) |
| `test_retractable_gear_ground.gd` | 26 | [report](test_retractable_gear_ground/report.json), [log](test_retractable_gear_ground/engine.log) |
| `test_checkpoint.gd` | 92 | [report](test_checkpoint/report.json), [log](test_checkpoint/engine.log) |
| `test_checkpoint_integrity.gd` | 149 | [report](test_checkpoint_integrity/report.json), [log](test_checkpoint_integrity/engine.log) |
| `test_wheel_session.gd` | 51 | [report](test_wheel_session/report.json), [log](test_wheel_session/engine.log) |

The [aggregate report](report.json) identifies each original receipt, timestamp,
completion count and log hash, and hashes the final seven GP runtime files plus
all 15 test scripts. Main source base:
`9f12c79e1490c4c72895d450910d9c916743d7b9`, with the recorded working-tree changes.
Engine: official Windows Godot `4.8.beta1.official.4d10419ca`, headless, executable
SHA-256 `90a914f1815b31fec4959be7867b2b491a61a02b1e3cb1e251653c58b7ff855f`.
Source hashes were sampled after the final selected runs. Receipts span several
batches and do not embed per-run source hashes; this is not an atomic full-suite
snapshot. Original absolute command paths remain historical run provenance.

Final GP-14 checks cover live accepted gear-up sliding without simulation
mutation, rejected intervals, reset/restore fencing, fixed-gear exemption after
an accepted contact tick, persistence and same-incident escalation. The immutable
writer snapshot check verifies that escalation replaces a copied crash record.
The detector uses the service's activity UUID namespace; the live reset check
verifies its configured namespace follows the activity. Pure checks reject
inconsistent v2 accident-group snapshots atomically. Lifecycle checks retain the
accepted aircraft configuration hash through reloads.

The main working tree also contained concurrent aerodynamic/wind and mechanical
audio changes and their tests. Those tracks are disclosed in the aggregate
report's dirty paths and are not qualified by this collection. The earlier
[candidate replay](../candidate/README.md) used its separately hashed isolated
source. Final main `statistics/detector.gd` and `statistics/service.gd` differ
from that candidate; do not attribute its numerical replay proof to those later
statistics changes.

To repeat a selected check, use the repository's
[checked runner](../../../../../tools/shared.md#one-godot-script), the matching
engine and a fresh output directory. To revalidate these retained receipts:

```powershell
python tools/godot/summarize.py docs/research/ground-physics/GP-08/evidence/integration --junit tmp/gp08-integrated-recheck.xml
```

This is selected headless software regression evidence. No full suite,
independent physical validation, performance benchmark, rendered application or
1920×1080 qualification is claimed.

## Evidence checkout preservation

The repository attributes preserve raw GP-08 evidence and GP-09/14 checked
receipts without newline conversion. A disposable Git fixture was committed and
fresh-cloned with `core.autocrlf=true`: all **116 retained files** matched their
original SHA-256, and the cloned integrated collection still verified **15/15**
passed invocations. [Checkout receipt](checkout.json) records every compared
path/hash and the attributes identity. This checks evidence portability, not a
fresh-clone application build; the receipt itself was written after comparison.
