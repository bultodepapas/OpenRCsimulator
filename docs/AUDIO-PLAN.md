# Immersive audio: current implementation and limits

2026-10-20 · Revision 6 · Step prefix: **AUD-**

**Status:** AUD-01–05 are delivered. The new soundscape passed software qualification and stereo-speaker acceptance. Dedicated mixer-thread timing and target-platform qualification remain open limits. **Active plan:** [audio realism](plans/audio-realism.md) (AUD-06…13: glitches, engine voices, turbine).

**Owns:** app/audio, app/assets/audio/soundscape, tools/audio and the soundscape/wildlife tests. Simulation, aircraft data, UI, scenery and world rendering remain with their owners. The only active audio workstream is this integration.

## Current implementation

The soundscape reads simulation and view state without writing to the flight model, shared random state or trace. Aircraft audio remains the foreground cue; wind and wildlife sit behind it. Dynamic gains, filters, pause/restart and camera transitions are bounded. Legacy engine sound remains available with --soundscape=legacy.

The source library contains 30 original generated PCM sources and three edited CC0 recording loops with per-asset provenance. Since AUD-14, the wind layers use a real wind-in-trees recording, and fields with a windsock add one quiet spatial fabric source. Wind level and direction read the accepted weather sample; fabric position and inflation read the rendered sock. The fabric envelope fades with the scene mix, responds to wind above 1.2 m/s, and has a 55 m hearing limit. The 14 existing voices remain; a field can add at most one fabric player. The procedural wildlife layer varies birds and adds distant dogs, nocturnal owls and crickets.

AUD-15 adds installed powertrain profiles and licensed recording banks in `app/assets/audio/powertrains/`. Gasoline has two RPM bands, electric has a brushless recording, and the helicopter route now follows accepted rotor speed, including coast with the drive held. The turbine bank is a downloaded CC0 designed sound. Glow engines retain their separate phase-aware two-stroke/four-stroke voices with revised power-dependent levels. The bank uses adjacent equal-power crossfades, smooth pitch/gain changes, guarded PCM loops, and a bounded inverse-distance law. Engine emitters follow the installed thrust line; the helicopter emitter follows its main hub. Only the selected bank is loaded.

These are authored audio profiles, not recordings of every installed engine: the electric source is a quadcopter, the rotor source is a small toy helicopter, RPM references are estimates, and the turbine source is synthetic. Exact glow recordings, isolated starter/shutdown recordings, and acoustic calibration remain open. Starts and stops follow accepted RPM/running state; audio does not invent a shaft run-down after physics stops. [Source identities and limitations](research/audio/AUD-15/sources.md).

Landing-gear audio reads accepted gear contacts and surface type. Rolling and touchdown events have separate envelopes and bounded players. Loaded moving wheels create rolling sound; airborne and stationary gear do not. Lower engine power exposes the quieter ground layer. Spawn, reset and pause prime the contact observer without inventing a landing. [Ground assets and contact contract](research/audio/AUD-15/landing-gear.md), [verification](research/audio/AUD-15/validation.md).

| Step | Result and evidence |
| --- | --- |
| AUD-01 | Source, license, API and integration audit: [sources](research/audio/AUD-01/sources.md), [integration audit](research/audio/AUD-01/integration-audit.md). |
| AUD-02 | Fourteen original PCM assets, generator and export checks: [asset record](research/audio/AUD-02/assets.md). |
| AUD-03 | Read-only dynamic mix, spatial environment and aircraft audio; 76 focused checks and five exact simulation pairs: [implementation](research/audio/AUD-03/README.md). |
| AUD-04 | Native gameplay captures and stereo-speaker review: [evidence](research/audio/AUD-04/README.md). Dedicated mixer timing was not qualified. |
| AUD-05 | Wildlife variation and export qualification: [evidence](research/audio/AUD-05/README.md). Speaker feedback and the frozen regression suite are recorded there. |
| AUD-06/07/10a | Linux Movie Maker bench; loop-wrap clicks, start pop, stuck limiter, Doppler camera-cut chirp and near-field clamp fixed; two-layer directional turbine voice: [evidence](research/audio/AUD-06/README.md), [plan](plans/audio-realism.md). Owner listening pending. |
| AUD-14 | Downloaded CC0 wind and light fabric recordings, reproducible editing pipeline, long PCM loops, weather-driven wind and spatial windsock sound: [sources, changes and verification](research/audio/AUD-14/README.md). Speaker listening and acoustic calibration remain open. |

## Remaining qualification

The host-side update p95 and dedicated mixer-thread budget are not established for target hardware. Windows listening and WASAPI captures do not qualify Linux/macOS devices or the owner's full radio setup. Keep those statements separate from the passed software and stereo-speaker checks.

Useful contracts and source details are in the AUD-01–05 evidence. The older G3b research remains historical evidence; it does not replace the current AUD qualification.
