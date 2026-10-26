# GP-19b — fixed-wing rolling audio follows authored material

2026-10-26. `GroundAudioModel.snapshot_contacts()` now samples the existing
`Environment.sample_support()` provider at each actual legacy wheel contact.
Maintained turf, mown grass and long grass select the installed grass recording;
declared pavement/asphalt/concrete select hard rolling, and declared gravel selects
gravel. The land-use rectangle name does not choose the material. No recording,
force, friction, geometry or aircraft data changed.

Contact snapshots retain material identity, region identity, resolution status and
an explicit audio-fallback flag. Unknown/unavailable materials use the existing
hard-roll recording as a playback fallback, without claiming pavement. A changed
raw surface table cannot keep stale material provenance. Unsupported roads and
unmeasured lake-bed material cannot borrow grass from the underlying field.
The old usage-only helper remains for unmigrated presentation callers, including
helicopter skid audio; the fixed-wing path no longer uses it.

The actual Session baseline reproduces turf being classified as hard surface.
The production checks pass **91 checks with zero engine diagnostics**: 23 material
cases, 33 existing ground audio cases and 35 accepted FlightAudio adapter cases.
The material fixture checks exact full-Session checkpoint preservation. These
are headless/Dummy software checks; listening, mixer timing and complete flight
performance remain unqualified. Accepted wheel/slip/work event capture and damage
layers remain open GP-19 work.

All checked receipts are retained. Two discarded draft runs failed: the first
called the timestep method as a property; the second assumed an origin spawn in
its fixture. Both are corrected in the passing draft/production runs. The failed
draft logs are diagnostic history, not exact source-replay cohorts. `manifest.json`
hashes the baseline source/probe, selected current sources/data and every receipt;
it does not claim a complete application snapshot.
