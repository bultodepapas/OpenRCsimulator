# GP-19: ground and mechanism audio

2026-10-26. Implemented slice: servo/flap/retract transitions captured at accepted physics endpoints and consumed by the existing bounded playback controller. Current behavior and limits are owned by the [mechanical audio guide](../../../servo-retract-audio-implementation.md); the [317-check cohort](evidence/accepted-mechanics/README.md) retains numerical/software evidence.

The shared classifier, recordings, Workshop sound profiles and six movement/two transient voice limits remain the owners. This observer supplies no force, physical mechanism, failure or checkpoint state. It preserves brief completed/reversed motion between renders, handles pause/reset/rewind and retained Workshop rigs, and explicitly bounds queued history.

GP-19b also connects fixed-wing contact snapshots to the existing GP-10 solid-support material provider. Turf and long grass now use grass rolling instead of usage-derived pavement/gravel; unavailable material has an explicit playback fallback. The [91-check material cohort](evidence/material-routing/README.md) verifies real-session checkpoint preservation, routing, stale provenance and existing audio behavior. The historical helicopter usage helper remains unchanged.

GP-19 remains open for accepted wheel/slip/work observations, suspension and scraping/damage layers, native output, listening, combined budgets and whole-flight performance. Ground audio still samples contacts on render updates. No new recording or acoustic calibration is claimed.
