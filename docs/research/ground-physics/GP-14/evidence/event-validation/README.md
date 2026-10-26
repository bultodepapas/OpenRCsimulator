# GP-14 event primitive validation

2026-10-26. `FlightEvent.valid` now checks selector primitive types before equality
comparisons. Malformed booleans, numbers, arrays and objects are refused without
GDScript invalid-operand errors. Valid generated events and physical behavior are
unchanged.

The [baseline reproduction](checks/baseline/report.json) printed 135 checks and
zero failed assertions but raised engine errors; the checked runner correctly
failed it. The [corrected main suite](checks/main/report.json) passes all **135
checks**, including 47 new malformed-selector cases, with zero diagnostics. The
[33-check real-session suite](checks/session/report.json) also passes, retaining
gear-up accident deduplication, ongoing motion and exact observer noninterference.

[Manifest](manifest.json) pins 13 selected artifacts. This small source snapshot
is not a complete application dependency freeze or a replacement for the earlier
[shared-events cohort](../shared-events/README.md).
