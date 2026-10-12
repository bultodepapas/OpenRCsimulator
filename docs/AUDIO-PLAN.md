# Immersive audio: current implementation and limits

2026-10-12 · Revision 4 · Step prefix: **AUD-**

**Status:** AUD-01–05 are delivered. The new soundscape passed software qualification and stereo-speaker acceptance. Dedicated mixer-thread timing and target-platform qualification remain open limits.

**Owns:** app/audio, app/assets/audio/soundscape, tools/audio and the soundscape/wildlife tests. Simulation, aircraft data, UI, scenery and world rendering remain with their owners. The only active audio workstream is this integration.

## Current implementation

The soundscape reads simulation and view state without writing to the flight model, shared random state or trace. Aircraft audio remains the foreground cue; wind and wildlife sit behind it. Dynamic gains, filters, pause/restart and camera transitions are bounded. Legacy engine sound remains available with --soundscape=legacy.

The source library contains original generated PCM with per-asset provenance. The current build has 29 soundscape sources; the procedural wildlife layer varies birds and adds distant dogs, nocturnal owls and crickets. No external recordings were required for the qualified release.

| Step | Result and evidence |
| --- | --- |
| AUD-01 | Source, license, API and integration audit: [sources](research/audio/AUD-01/sources.md), [integration audit](research/audio/AUD-01/integration-audit.md). |
| AUD-02 | Fourteen original PCM assets, generator and export checks: [asset record](research/audio/AUD-02/assets.md). |
| AUD-03 | Read-only dynamic mix, spatial environment and aircraft audio; 76 focused checks and five exact simulation pairs: [implementation](research/audio/AUD-03/README.md). |
| AUD-04 | Native gameplay captures and stereo-speaker review: [evidence](research/audio/AUD-04/README.md). Dedicated mixer timing was not qualified. |
| AUD-05 | Wildlife variation and export qualification: [evidence](research/audio/AUD-05/README.md). Speaker feedback and the frozen regression suite are recorded there. |

## Remaining qualification

The host-side update p95 and dedicated mixer-thread budget are not established for target hardware. Windows listening and WASAPI captures do not qualify Linux/macOS devices or the owner's full radio setup. Keep those statements separate from the passed software and stereo-speaker checks.

Useful contracts and source details are in the AUD-01–05 evidence. The older G3b research remains historical evidence; it does not replace the current AUD qualification.
