# Twenty GitHub repositories: universal FPV code survey

**Date:** 2026-11-22. **Status:** targeted static source review complete; OpenRC runtime implementation and interoperability qualification pending. **OpenRC input:** planning branch `plan/universal-fpv-gimbal-2026-11-22`, plan commit `48549e4f2e7fc560a57a5a62df438f1ae4709035`, unchanged runtime baseline `7940a4081e10994f34c858c4acac3d7a1a271464`. The [universal FPV plan](../../plans/universal-fpv.md) owns execution; the [OpenRC audit](2026-11-22-audit.md) owns the internal reuse inventory.

## Selection and method

The search followed unresolved implementation questions: multi-protocol logs and replay; firmware OSD semantics and editors; gimbal/protocol contracts; simulator frames and FPV presentation. Five repositories were selected in each group. **Kite means [b14ckyy/Kite-GC](https://github.com/b14ckyy/Kite-GC)**, which matches the user's description of an INAV/ArduPilot-capable ground station and log viewer.

For each repository, the review resolved an inspected commit, examined at least two relevant implementation/definition files and followed a concrete source-to-consumer or control path. Relevant tests were read where useful. The exact paths and symbols below make the scope reproducible; this is not a whole-repository audit. License files and relevant source notices were inspected, independently of GitHub's license label. No upstream code or tests were executed, built or installed; no upstream source, fonts, assets or dependencies were added to OpenRC.

The commits are separately pinned research snapshots, not a tested set of compatible releases. In particular, the INAV maintenance branch and Configurator master need an admitted reference pair before fidelity claims. GitHub's `stronnag/bbl2kml` is archived and announces migration to Codeberg; it is retained as a narrowly useful historical sensor-replay reference. AirSim's GitHub metadata reported **not archived** when checked; its old reputation is not evidence of its current archive flag.

Shared lineage matters: ArduPilot OSD credits Betaflight/INAV and INAV Configurator font work; OpenIPC's MSP implementation credits fpv-wtf and has closely related parser code; MAVSDK/pymavlink consume the same MAVLink ecosystem. Similar behavior in these projects is not automatically independent corroboration.

## Repository inventory

The full commit and implementation links appear in each detailed finding.

| ID | Repository | Selection question | Inspected commit |
| --- | --- | --- | --- |
| R01 | [b14ckyy/Kite-GC](https://github.com/b14ckyy/Kite-GC) | Can live telemetry, several log formats, replay and FPV share a semantic model? | `142fe50cf0` |
| R02 | [ArduPilot/UAVLogViewer](https://github.com/ArduPilot/UAVLogViewer) | How are parsers, attitude sources, events and 3D replay separated? | `01f9d510b7` |
| R03 | [ArduPilot/WebTools](https://github.com/ArduPilot/WebTools) | How are configurable widgets synchronized with recorded video? | `50d1e84cf4` |
| R04 | [betaflight/blackbox-log-viewer](https://github.com/betaflight/blackbox-log-viewer) | How are corrupt logs, sparse state, seeking and video offsets handled? | `e179902df4` |
| R05 | [stronnag/bbl2kml](https://github.com/stronnag/bbl2kml) | What does feeding recorded sensors into INAV SITL actually establish? | `ab5bdb66b5` |
| R06 | [iNavFlight/inav](https://github.com/iNavFlight/inav) | What do INAV elements, layouts, fonts and horizon inputs mean in code? | `ce4d347b58` |
| R07 | [iNavFlight/inav-configurator](https://github.com/iNavFlight/inav-configurator) | How are layout encodings, previews and writes managed? | `95504dcea1` |
| R08 | [ArduPilot/ardupilot](https://github.com/ArduPilot/ardupilot) | What are the actual OSD measurement and gimbal target semantics? | `5a89ce5d6d` |
| R09 | [mavlink/qgroundcontrol](https://github.com/mavlink/qgroundcontrol) | How are telemetry facts, gimbal frames and control ownership represented? | `2af411ce0d` |
| R10 | [ArduPilot/MissionPlanner](https://github.com/ArduPilot/MissionPlanner) | How does a real editor group and write ArduPilot OSD parameters? | `41298695e9` |
| R11 | [mavlink/mavlink](https://github.com/mavlink/mavlink) | What are the authoritative field, sentinel, identity and gimbal definitions? | `b864fb4d6d` |
| R12 | [mavlink/MAVSDK](https://github.com/mavlink/MAVSDK) | What survives when those definitions become a convenient client API? | `0537d8c543` |
| R13 | [ArduPilot/pymavlink](https://github.com/ArduPilot/pymavlink) | How do live, tlog, DataFlash, parser recovery and source clocks differ? | `4fd5b57831` |
| R14 | [fpv-wtf/msp-osd](https://github.com/fpv-wtf/msp-osd) | How are ordered DisplayPort writes rendered into completed character screens? | `ef9d906cf4` |
| R15 | [OpenIPC/msposd](https://github.com/OpenIPC/msposd) | Which grid, font and transport assumptions vary between OSD consumers? | `642faae831` |
| R16 | [ArduPilot/ardupilot_gazebo](https://github.com/ArduPilot/ardupilot_gazebo) | How are physical frames, mounted cameras and an external simulator connected? | `f116b03552` |
| R17 | [PX4/PX4-Autopilot](https://github.com/PX4/PX4-Autopilot) | How are gimbal modes, source ownership, limits and simulator clocks implemented? | `288b114841` |
| R18 | [microsoft/AirSim](https://github.com/microsoft/AirSim) | How are reusable vehicle cameras, settings and engine frame boundaries organized? | `1ca93f6f77` |
| R19 | [FlightGear/flightgear](https://github.com/FlightGear/flightgear) | How are authored onboard viewpoints and one active view managed? | `807e406dd3` |
| R20 | [OpenHD/QOpenHD](https://github.com/OpenHD/QOpenHD) | How do an FPV video rectangle, movable widgets and FC telemetry meet? | `76bd7dae11` |

## Integration decisions

These are OpenRC design inferences from the code below. They refine the existing **9 phases / 38 subphases**; they do not import another application's architecture wholesale.

Source/clock, log/video and protocol cases apply only to the corresponding admitted feature. Local telemetry retains per-measurement validity even when several values arrive in one stream; optional external/log integrations add no first-release dependency.

| Decision | Evidence | Plan packets and required proof |
| --- | --- | --- |
| Preserve nullable, instance-keyed telemetry end to end; retain raw/source meaning where needed. | R01, R08–R13, R20 | 01a, 03a–c, 08b: two batteries/estimators, zero versus absent, per-stream freshness and source changes. |
| Carry explicit airspeed kind and altitude datum. | R06, R08, R11 | 03b, 05c: TAS/EAS/IAS distinction, admitted conversion or declared deviation, AGL/home/MSL separation. |
| Keep simulation, source, receive, log and video clocks distinct. | R01, R03–R05, R13 | 03c, 06c, 08b: widen-before-scale, wrap/reboot/reorder, pause, seek, offset/gap/uncertainty. |
| Prove frame composition with independent asymmetric/noncommuting poses. | R02, R06, R08, R16–R19 | 01a/b, 02b/e, 04b: known axes/positions, structural datum, quaternion sign, inversion and invalid orientation. |
| Separate request, ACK, observed ownership and achieved gimbal pose. | R08–R12, R17 | 04a–d, 08c: per-axis frame/limit, multi-device identity, simultaneous release, timeout and ownership change. |
| Version profile, element encoding, grid and glyph assets separately. | R06–R08, R10, R14/R15 | 05a–d, 08c: qualified reference pair, unsupported bits/assets, lossless round trip or explicit refusal. |
| Preview full element footprints and preserve dirty state on failure. | R03, R07, R10, R20 | 05d, 06a: overlap, right/bottom edges, signed/large/localized text and partial/failed saves. |
| Project through the achieved camera and actual displayed image rectangle. | R01, R03, R06, R08, R18/R20 | 02e, 05e: letterbox/insets/resize/zero-size, body instrument versus optical cue. |
| Treat DisplayPort as incremental screen state with a completion boundary. | R14/R15 | 08c: split/concatenated packets, clear/write/draw, glyph pages, interrupted frame and bounded capacity. |
| Isolate decoders and indexes from physics; restore sparse state on seek. | R01–R04, R13 | 06c, 08b: immutable originals, decoder identity, cancellation/generation, home/config/mode transitions and explicit gaps. |
| Keep optional network/decode/video work outside accepted-tick observers. | R01/R03, R05, R16/R17 | 01d, 04d, 08a: blocked consumer, queue saturation and observer failure cannot delay accepted physics. |
| Use source tests as design evidence, then build independent OpenRC fixtures. | R01/R02, R06–R09, R12/R13, R16–R19 | 00c/d, 07b: exact fixture/version identity, known expected values and actual assertions; no inherited test-pass claims. |

## Detailed code findings

### R01 — b14ckyy/Kite-GC
Commit: `142fe50cf0ecef338daa438e64b49e487161ee80` (master); not archived at inspection. [License](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/LICENSE): GPL v3 text; inspected source headers specify GPL-3.0-or-later. This is the user's “Kite” match. Its pinned README describes a 2.0 beta, whereas the search index still described older release work; the commit is the source identity.

**Code inspected:** [TelemetryRecord](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src-tauri/src/flightlog/types.rs), [toTelemetryData](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src/lib/adapters/telemetryAdapter.ts), [PlaybackController](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src/lib/controllers/playbackController.ts), [hires cache](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src-tauri/src/flightlog/hires.rs), [video replay](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src/lib/controllers/videoReplay.ts), [FPV HUD](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src/lib/components/FpvHud.svelte). Also inspected the native/legacy decoder comparison fixture.

**Observed:** a common optional-field telemetry record feeds one replay mapper; battery/GPS instances and source-specific mode data are retained. A low-rate track timeline and a disposable full-rate instrument cache are separate. A virtual playback time drives both playback and video synchronization; flight changes serialize video open/close, and gaps are covered while the next picture is prepared. The HUD separates a conformal horizon from a compact instrument cluster and derives focal length from FOV.

**Adapt:** shared semantic samples for live/replay; retain originals and decoder identity; derive bounded disposable indexes/caches; use generation-aware cancellation and explicit gaps; compute projection from the actual video rectangle. Map to 01a, 03a–03c, 05e, 06c and optional 08a/08b.

**Reject/counterexamples:** the replay mapper replaces many missing readings with zero, guesses RSSI scale from magnitude, infers armed status from the presence of a mode, and falls back from yaw to course. These are unsuitable for OpenRC's validity contract. The record comments acknowledge mixed raw GPS-fix scales and target altitude without its frame. The HUD uses a fixed 16:9 viewBox and assumes a sufficiently wide panel; do not copy it as universal optics. Reuse the architecture, independently implement stronger identity/availability/frame semantics.

**Verification limit:** the [native/legacy comparison test](https://github.com/b14ckyy/Kite-GC/blob/142fe50cf0ecef338daa438e64b49e487161ee80/src-tauri/src/flightlog/inav/compare_test.rs) is opt-in/ignored and depends on external logs/decoder; it was read, not run. No claim about all supported import formats or visual correctness is established here.

### R02 — ArduPilot/UAVLogViewer
Commit: `01f9d510b7df31687819a6c87415161041d73ae6` (master); not archived. [GPL v3 license](https://github.com/ArduPilot/UAVLogViewer/blob/01f9d510b7df31687819a6c87415161041d73ae6/LICENSE).

**Code inspected:** [parser.worker.js](https://github.com/ArduPilot/UAVLogViewer/blob/01f9d510b7df31687819a6c87415161041d73ae6/src/tools/parsers/parser.worker.js), [dataflashDataExtractor.js](https://github.com/ArduPilot/UAVLogViewer/blob/01f9d510b7df31687819a6c87415161041d73ae6/src/tools/dataflashDataExtractor.js), [CesiumViewer.vue](https://github.com/ArduPilot/UAVLogViewer/blob/01f9d510b7df31687819a6c87415161041d73ae6/src/components/CesiumViewer.vue), [ParamSeeker](https://github.com/ArduPilot/UAVLogViewer/blob/01f9d510b7df31687819a6c87415161041d73ae6/src/tools/paramseeker.js), [log test](https://github.com/ArduPilot/UAVLogViewer/blob/01f9d510b7df31687819a6c87415161041d73ae6/test/unit/specs/dataflashlogs.spec.js).

**Observed:** a worker selects a parser and loads a useful initial message subset; additional types are requested lazily. The extractor discovers Euler/quaternion attitude sources and estimator instances, separately extracts modes/events, and the viewer builds sampled orientations on log time. ParamSeeker attempts reconstruction of parameter state when scrubbing.

**Adapt:** worker/decode isolation, source-and-instance selection, lazy channel loading, and parameter/home/mode timelines for optional telemetry inspection. Camera replay must reconstruct the configuration effective at a seek point. Use source instances rather than whichever attitude packet last arrived. Map to 03a/03c, 06c, 08a/08b.

**Limits:** its quaternion-to-scene path includes a coordinate-system TODO, explicit sign/rotation offsets and NaN pitch substitution; it is not an oracle for OpenRC frames. The inspected log test references a parser path absent from this pinned tree and an extractor name different from the inspected implementation; do not claim the test currently passes. Replay trajectories do not prove dynamics or exact physical replay.

### R03 — ArduPilot/WebTools
Commit: `50d1e84cf4da57adb0bb7a9e29be128b14eded70` (main); not archived. [GPL v3 license](https://github.com/ArduPilot/WebTools/blob/50d1e84cf4da57adb0bb7a9e29be128b14eded70/LICENSE).

**Code inspected:** [VideoOverlay.js](https://github.com/ArduPilot/WebTools/blob/50d1e84cf4da57adb0bb7a9e29be128b14eded70/VideoOverlay/VideoOverlay.js), [TelemetryDashboard.js](https://github.com/ArduPilot/WebTools/blob/50d1e84cf4da57adb0bb7a9e29be128b14eded70/TelemetryDashboard/TelemetryDashboard.js), [WidgetBase](https://github.com/ArduPilot/WebTools/blob/50d1e84cf4da57adb0bb7a9e29be128b14eded70/TelemetryDashboard/Widgets/Base_Class.js).

**Observed:** the overlay matches its container to the actual video's dimensions, maps video time to log time using an explicit offset, waits for widgets at each export frame, then composites. Grid/layout export carries a tool/version header. Widget configuration uses validated form content and dirty/saved state.

**Adapt:** a shared displayed-image rectangle, a declared presentation clock, versioned layout envelopes and visible dirty state. A future recorded-video comparator should sample every element at the same presentation timestamp and preserve the offset/timebase in its sidecar. Map to 02e, 05a/05d/05e, 06c.

**Limits:** HTML screenshot/compositing and asynchronous export work belong outside the live 240Hz presentation observer. `Promise.allSettled` is not itself proof that every widget succeeded; OpenRC should handle/report failed samples. Offset-only synchronization does not prove long-recording clock-drift alignment. No generic custom-HTML plugin system is required for the initial FPV feature.

### R04 — betaflight/blackbox-log-viewer
Commit: `e179902df4e38f24d4b61f114bf856a196c995be` (master); not archived. [GPL v3 license](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/LICENSE).

**Code inspected:** [flightlog_parser.js](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/flightlog_parser.js), [flightlog_index.js](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/flightlog_index.js), [video_handler.js](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/video_handler.js), [playback store](https://github.com/betaflight/blackbox-log-viewer/blob/e179902df4e38f24d4b61f114bf856a196c995be/src/stores/playback.js).

**Observed:** header-driven firmware/field decoding, explicit frame validation/corruption statistics and stream resynchronization. Its seek index stores IMU, slow-message, GPS-home and GPS state at selected I-frames so sparse state can be restored without rereading the entire log. Video conversion explicitly includes the log origin and seconds-to-microseconds scale.

**Adapt:** bounded indexed seek checkpoints including sparse configuration/events; preserve gaps and corruption counts; store log origin, units and video offset explicitly. Use independent known fixtures for seek forward/backward, mid-log home change, corrupt/truncated frames and resume events. Map to 03c, 06c, 08b.

**Limits:** gyro-derived estimated attitude is not the simulator's accepted physical attitude. Firmware name recognition alone does not qualify every INAV log version. Preserve decoder/version identity, original bytes and the distinction between reconstructed telemetry, presentation replay and exact physical replay. Reuse concepts, not an entire browser graphing stack.

### R05 — stronnag/bbl2kml
Commit: `ab5bdb66b5af94dc33d09b817e0c07e2ff313bcd` (master); GitHub repository archived and README announces migration to Codeberg. [GPL v2 license](https://github.com/stronnag/bbl2kml/blob/ab5bdb66b5af94dc33d09b817e0c07e2ff313bcd/LICENSE). Included as a specifically relevant historical reference, not a maintained dependency recommendation.

**Code inspected:** [file_reader.go](https://github.com/stronnag/bbl2kml/blob/ab5bdb66b5af94dc33d09b817e0c07e2ff313bcd/pkg/sitlgen/file_reader.go), [sitlgen.go](https://github.com/stronnag/bbl2kml/blob/ab5bdb66b5af94dc33d09b817e0c07e2ff313bcd/pkg/sitlgen/sitlgen.go), [generic_telem.go](https://github.com/stronnag/bbl2kml/blob/ab5bdb66b5af94dc33d09b817e0c07e2ff313bcd/pkg/sitlgen/generic_telem.go).

**Observed:** log samples are converted into `SimData`, paced from recorded timestamp deltas, and encoded as X-Plane-style RREF sensor fields for INAV SITL. The bridge separately maps RC channels, modes and failsafe state; the sender retransmits its last sample after a timeout. Accelerometer normalization and pitch-sign conversion are explicit.

**Adapt/defer:** a recorded-message/sensor fixture can exercise optional telemetry and OSD integration repeatedly. Keep parser, normalized sample, transport encoding and command/control adapters separate. Map to 08a/08b and replay acceptance in 06c.

**Reject/limits:** wall-clock sleeps, float32 source conversion and repeated old samples are not OpenRC's authoritative timing/freshness model. Predetermined recorded sensor trajectories cannot establish closed-loop control, lockstep, rollback or physical correctness. Live observer mode must never inherit the arming/RC command path; the optional firmware owner must explicitly admit any controlling mode.



### R06 — iNavFlight/inav
Commit: `ce4d347b58c4e53afea140594bd3beb112602ac4` (`maintenance-10.x`). [License](https://github.com/iNavFlight/inav/blob/ce4d347b58c4e53afea140594bd3beb112602ac4/LICENSE): GPL v3 text; inspected OSD source states v3 or later.

**Trace:** [osd.h](https://github.com/iNavFlight/inav/blob/ce4d347b58c4e53afea140594bd3beb112602ac4/src/main/io/osd.h) defines element IDs, per-layout storage and packed positions; [osd.c](https://github.com/iNavFlight/inav/blob/ce4d347b58c4e53afea140594bd3beb112602ac4/src/main/io/osd.c) decodes visibility/position in `osdDrawSingleElement`, schedules draws and validates font metadata. The normal coordinate encoding uses six bits per axis, while SD/DJI compatibility has a distinct five-bit form. Relative and MSL altitude are separate calculations. Its attitude horizon uses vehicle roll/pitch with optional fixed camera uptilt.

**Adapt:** profile/element/encoding/glyph version identity; explicit altitude provenance; bounded formatting and draw policy. **Counterexample:** fixed uptilt does not provide arbitrary gimbal projection, and one coordinate encoding cannot represent every output backend. Versioned parameter-group registration does not prove a migration algorithm.

**Proof to add:** use the existing [centi-number tests](https://github.com/iNavFlight/inav/blob/ce4d347b58c4e53afea140594bd3beb112602ac4/src/test/unit/osd_unittest.cc) as examples of positive/negative width cases; independently test the OpenRC profile, assets and achieved-camera projection. **Packets:** 03b/c, 05a/b/d/e, optional 08b/c.

### R07 — iNavFlight/inav-configurator
Commit: `95504dcea167685e2f9adb08f5f17d6ff1a7462f` (master). [License](https://github.com/iNavFlight/inav-configurator/blob/95504dcea167685e2f9adb08f5f17d6ff1a7462f/LICENSE): GPL v3 text.

**Trace:** [tabs/osd.js](https://github.com/iNavFlight/inav-configurator/blob/95504dcea167685e2f9adb08f5f17d6ff1a7462f/tabs/osd.js) obtains layout/item counts, reads layouts and writes individual layout/item/position values; preview detects overlap and adjusts horizontal overflow. [js/msp.js](https://github.com/iNavFlight/inav-configurator/blob/95504dcea167685e2f9adb08f5f17d6ff1a7462f/js/msp.js) refuses dependent writes after source parsing failed. [Recovery tests](https://github.com/iNavFlight/inav-configurator/blob/95504dcea167685e2f9adb08f5f17d6ff1a7462f/tests/msp-parse-failure-recovery.test.mjs) exercise refusal without success callbacks.

**Adapt:** capability-driven editor population, overlap/extent preview, valid-source prerequisites and visible write failure. **Counterexamples:** the position packer rebuilds X/Y/visibility rather than retaining every documented bit; the bad-font-header path creates a rejected promise without immediately returning. An asynchronous retry failure may reach a resolved callback with false, unlike an immediate refusal. Completion alone is not successful persistence.

**Proof to add:** supported-version round trip, unsupported-bit preservation/refusal, malformed font rejection, positive save acknowledgement and retained dirty state. The firmware and configurator pins are research points, not a qualified release pair. **Packets:** 05a/b/d, optional 08b/c.

### R08 — ArduPilot/ardupilot
Commit: `5a89ce5d6d4839d9fc0f561a3671ab09d6a95539` (master). [License](https://github.com/ArduPilot/ardupilot/blob/5a89ce5d6d4839d9fc0f561a3671ab09d6a95539/COPYING.txt): GPL v3 text; inspected OSD notices specify v3 or later.

**Trace:** [AP_OSD_Setting.cpp](https://github.com/ArduPilot/ardupilot/blob/5a89ce5d6d4839d9fc0f561a3671ab09d6a95539/libraries/AP_OSD/AP_OSD_Setting.cpp) provides enabled/X/Y settings. [AP_OSD_Screen.cpp](https://github.com/ArduPilot/ardupilot/blob/5a89ce5d6d4839d9fc0f561a3671ab09d6a95539/libraries/AP_OSD/AP_OSD_Screen.cpp) draws home-relative altitude, vehicle-attitude horizon and AHRS **EAS**, displaying a placeholder when the latter is unavailable. [AP_Mount_Backend.cpp](https://github.com/ArduPilot/ardupilot/blob/5a89ce5d6d4839d9fc0f561a3671ab09d6a95539/libraries/AP_Mount/AP_Mount_Backend.cpp) separates angle/rate targets and body/earth locks, limits joint targets and clears rates on failsafe/timeout.

**Adapt:** precise measurement semantics, explicit target type/frame, current capabilities and rate-stop policy. **Counterexamples:** OpenRC TAS is not automatically EAS; its body-attitude OSD is not an optical gimbal horizon. Firmware loop rates/timeouts do not define OpenRC timing. The source acknowledges Betaflight/INAV OSD and font lineage.

**Proof to add:** [gimbal-estimator tests](https://github.com/ArduPilot/ardupilot/blob/5a89ce5d6d4839d9fc0f561a3671ab09d6a95539/libraries/SITL/tests/test_mavlink_gimbal_estimator.cpp) provide particularly useful independent-stream freshness, zero/NaN quaternion, encoder-composition and contradictory-frame cases. Read, not run. **Packets:** 03b/c, 04a–d, 05c/e, optional 08c.

### R09 — mavlink/qgroundcontrol
Commit: `2af411ce0de35c42ce0b06182e95a31bd7bd8745` (master). [License notice](https://github.com/mavlink/qgroundcontrol/blob/2af411ce0de35c42ce0b06182e95a31bd7bd8745/.github/COPYING.md) describes Apache 2.0/GPL v3 alternatives and dependency conditions; GitHub's single Apache label is incomplete.

**Trace:** [VehicleFactGroup.cc](https://github.com/mavlink/qgroundcontrol/blob/2af411ce0de35c42ce0b06182e95a31bd7bd8745/src/Vehicle/FactGroups/VehicleFactGroup.cc) dispatches telemetry, checks attitude source and maintains separate altitude facts. [GimbalController.cc](https://github.com/mavlink/qgroundcontrol/blob/2af411ce0de35c42ce0b06182e95a31bd7bd8745/src/Gimbal/GimbalController.cc) pairs manager/device identity, reads reported control ownership and converts frame-qualified yaw; explicit zero delta is valid. [Delta-yaw tests](https://github.com/mavlink/qgroundcontrol/blob/2af411ce0de35c42ce0b06182e95a31bd7bd8745/test/Gimbal/GimbalControllerDeltaYawTest.cc) cover availability changes, wrap and reference frames.

**Adapt:** typed facts, instance identity, valid-zero treatment and control-state transitions. **Counterexamples:** VFR HUD handling maps several NaNs to zero. `_tryGetGimbalControl` can request ownership and return before new status confirms it. A source comment explains why simultaneous axis stops require care around duplicate-command suppression.

**Proof to add:** unavailable versus true zero, independent status freshness, source identity, simultaneous release, disconnect and request/ACK/status/achieved-pose distinctions. **Packets:** 03c, 04b/c, optional 08a–c.

### R10 — ArduPilot/MissionPlanner
Commit: `41298695e9ef34f0e78eb5ee630b5550958d1cc6` (master). [License](https://github.com/ArduPilot/MissionPlanner/blob/41298695e9ef34f0e78eb5ee630b5550958d1cc6/COPYING.txt): GPL v3 text; individual components/assets require their own provenance.

**Trace:** [ConfigFactory.cs](https://github.com/ArduPilot/MissionPlanner/blob/41298695e9ef34f0e78eb5ee630b5550958d1cc6/ExtLibs/OSDConfigurator/ConfigFactory.cs) groups named enabled/X/Y triples; [OSDItem.cs](https://github.com/ArduPilot/MissionPlanner/blob/41298695e9ef34f0e78eb5ee630b5550958d1cc6/ExtLibs/OSDConfigurator/Models/OSDItem.cs) exposes them. [Visualizer.cs](https://github.com/ArduPilot/MissionPlanner/blob/41298695e9ef34f0e78eb5ee630b5550958d1cc6/ExtLibs/OSDConfigurator/GUI/Visualizer.cs) maps coordinates and indicates screen regions. [ConfigOSD.cs](https://github.com/ArduPilot/MissionPlanner/blob/41298695e9ef34f0e78eb5ee630b5550958d1cc6/GCSViews/ConfigurationView/ConfigOSD.cs) writes changed parameters individually.

**Adapt:** named per-screen configuration and an honest grid preview. **Counterexamples:** coordinate conversion clamps negative values but not the positive screen edges; per-parameter writes can partially succeed. This does not establish atomic local persistence or full element bounds.

**Proof to add:** incomplete settings, both edges, full footprints, partial failure, dirty-state retention and supported-schema round trips. [OSD tuning tests](https://github.com/ArduPilot/MissionPlanner/blob/41298695e9ef34f0e78eb5ee630b5550958d1cc6/MissionPlannerTests/Utilities/OsdTuningSlotProviderTests.cs) cover parameter identifiers, not these editor journeys. **Packets:** 05a/c/d, 06a; optional external configuration stays with 08.

### R11 — mavlink/mavlink
Commit: `b864fb4d6da1ca9edf41ca23669e9a1b5543329c`. [COPYING](https://github.com/mavlink/mavlink/blob/b864fb4d6da1ca9edf41ca23669e9a1b5543329c/COPYING) describes generator terms and a generated-output exception; do not infer every file's terms from the repository label.

**Trace:** [common.xml](https://github.com/mavlink/mavlink/blob/b864fb4d6da1ca9edf41ca23669e9a1b5543329c/message_definitions/v1.0/common.xml) defines gimbal frames/capabilities, angle/rate and ownership messages, units, altitude meanings and per-field invalid values. Battery base and extension cells use different absence rules; an array entry may represent pack voltage. [minimal.xml](https://github.com/mavlink/mavlink/blob/b864fb4d6da1ca9edf41ca23669e9a1b5543329c/message_definitions/v1.0/minimal.xml) defines heartbeat component/autopilot identity. [ardupilotmega.xml](https://github.com/mavlink/mavlink/blob/b864fb4d6da1ca9edf41ca23669e9a1b5543329c/message_definitions/v1.0/ardupilotmega.xml) supplies the dialect context.

**Adapt:** explicit versioned mapping tables before scaling; system/component/instance identity; separate unknown, unset and valid zero. A gimbal frame/ownership flag is a protocol state, not proof of physical stabilization.

**Proof to add:** field-specific sentinel, identity, capability and malformed/contradictory flag fixtures against an admitted dialect. **Limit:** definitions alone demonstrate no firmware/device interoperability; actual producers/consumers must be qualified separately. **Packets:** 01a, 03b/c, 04b and optional 08a–c.

### R12 — mavlink/MAVSDK
Commit: `0537d8c5436fe04a36f27ef1ca840da648fd61c5`. [License](https://github.com/mavlink/MAVSDK/blob/0537d8c5436fe04a36f27ef1ca840da648fd61c5/LICENSE.md): BSD 3-clause.

**Trace:** [gimbal_impl.cpp](https://github.com/mavlink/MAVSDK/blob/0537d8c5436fe04a36f27ef1ca840da648fd61c5/cpp/src/mavsdk/plugins/gimbal/gimbal_impl.cpp) discovers manager/device information and derives ownership from status. [gimbal_device_matching.cpp](https://github.com/mavlink/MAVSDK/blob/0537d8c5436fe04a36f27ef1ca840da648fd61c5/cpp/src/mavsdk/plugins/gimbal/gimbal_device_matching.cpp) distinguishes a separate device component from a device sharing the manager; [tests](https://github.com/mavlink/MAVSDK/blob/0537d8c5436fe04a36f27ef1ca840da648fd61c5/cpp/src/mavsdk/plugins/gimbal/gimbal_device_matching_test.cpp) encode that distinction. [telemetry_impl.cpp](https://github.com/mavlink/MAVSDK/blob/0537d8c5436fe04a36f27ef1ca840da648fd61c5/cpp/src/mavsdk/plugins/telemetry/telemetry_impl.cpp) converts raw telemetry.

**Adapt/defer:** use discovery and matching as design references; decide on a dependency only in the optional protocol track. **Counterexamples:** convenient converted values can lose sentinel meaning; the battery consumer's extension processing does not itself enforce every prerequisite in the inspected definition. A frame branch accepts conflicting yaw flags with a preferred interpretation, and control support is not symmetric for primary/secondary users.

**Proof to add:** repeated IDs across links/managers, absent capability information, unsupported ownership, per-field sentinels, explicit widening before clock arithmetic, and independent wire/payload robustness cases. The [fuzzer](https://github.com/mavlink/MAVSDK/blob/0537d8c5436fe04a36f27ef1ca840da648fd61c5/cpp/src/fuzz_tests/mavlink_fuzzer.cpp) constructs valid-checksum traffic, which does not replace corrupt-wire tests. **Packets:** optional 08b/c.

### R13 — ArduPilot/pymavlink
Commit: `4fd5b57831b047ea6f77469994be7d898505870e`. [COPYING](https://github.com/ArduPilot/pymavlink/blob/4fd5b57831b047ea6f77469994be7d898505870e/COPYING) describes generator/output terms; the inspected `mavutil.py` header states LGPL v3 or later.

**Trace:** [mavutil.py](https://github.com/ArduPilot/pymavlink/blob/4fd5b57831b047ea6f77469994be7d898505870e/mavutil.py) filters likely-vehicle heartbeats, maintains source state and distinguishes received/log time. [DFReader.py](https://github.com/ArduPilot/pymavlink/blob/4fd5b57831b047ea6f77469994be7d898505870e/DFReader.py) implements several DataFlash clock models and rewind behavior. [mavgen_python.py](https://github.com/ArduPilot/pymavlink/blob/4fd5b57831b047ea6f77469994be7d898505870e/generator/mavgen_python.py) contains partial-input parsing, invalid-data recovery and configured validation paths. [Signing-state tests](https://github.com/ArduPilot/pymavlink/blob/4fd5b57831b047ea6f77469994be7d898505870e/tests/test_signing_state.py) check that invalid/replayed input does not advance trusted state.

**Adapt:** separate raw source time, received time, imported timeline and trust state; retain original data and parser/version identity. **Counterexamples:** selecting the first likely vehicle is not sufficient user selection on a shared link; fallback/interpolated log time is not an observed timestamp. Unknown-message and validation-bypass behavior must not silently become OpenRC's policy.

**Proof to add:** partial/concatenated/corrupt traffic, valid recovery, unknown dialect/message, identity change, independent signing/boot clocks, wrap/reboot/reorder and rewind. **Packets:** 03c, 06c, optional 08a/b. Dependency adoption remains deferred.

### R14 — fpv-wtf/msp-osd
Commit: `ef9d906cf43ac939799ef04287b19bfbd1bd968f`. [License](https://github.com/fpv-wtf/msp-osd/blob/ef9d906cf43ac939799ef04287b19bfbd1bd968f/LICENSE): GPL v3 text; font assets need separate provenance.

**Trace:** [msp.c](https://github.com/fpv-wtf/msp-osd/blob/ef9d906cf43ac939799ef04287b19bfbd1bd968f/jni/msp/msp.c) parses MSP v1. [msp_displayport.c](https://github.com/fpv-wtf/msp-osd/blob/ef9d906cf43ac939799ef04287b19bfbd1bd968f/jni/msp/msp_displayport.c) dispatches clear, positioned strings, options and draw completion; string attributes select glyph pages. [msp_displayport_mux.c](https://github.com/fpv-wtf/msp-osd/blob/ef9d906cf43ac939799ef04287b19bfbd1bd968f/jni/msp_displayport_mux.c) buffers/commits screen state, while [the renderer](https://github.com/fpv-wtf/msp-osd/blob/ef9d906cf43ac939799ef04287b19bfbd1bd968f/jni/osd_dji_overlay_udp.c) clips to its selected grid.

**Adapt:** bounded character staging, explicit draw completion, source-specific grids and glyph-page identity. **Reject direct copying:** the string scanner lacks the actual payload-length argument, and the mux append checks do not establish capacity for the whole next append. Missing-page fallback can produce a plausible but wrong glyph.

**Proof to add:** truncated subcommands, unterminated strings within payload bounds, exact capacity and one byte over, unknown/missing pages, split frames and disconnect before completion. Static counterexamples are not a reproduced vulnerability claim. **Packets:** 05a and optional 08c; this hardware renderer is not the definition of either firmware profile.

### R15 — OpenIPC/msposd
Commit: `642faae831e3325767004b78e1cd1bd6d82aec33`. [License](https://github.com/OpenIPC/msposd/blob/642faae831e3325767004b78e1cd1bd6d82aec33/LICENSE): GPL v3 text.

**Trace:** [msp.c](https://github.com/OpenIPC/msposd/blob/642faae831e3325767004b78e1cd1bd6d82aec33/osd/msp/msp.c) and [msp_displayport.c](https://github.com/OpenIPC/msposd/blob/642faae831e3325767004b78e1cd1bd6d82aec33/osd/msp/msp_displayport.c) provide related MSP/DisplayPort parsing; [osd.c](https://github.com/OpenIPC/msposd/blob/642faae831e3325767004b78e1cd1bd6d82aec33/osd.c) clips writes, copies completed maps and applies local grid/font policy. It can flush transport data before draw completion and its options handler does not apply every suggested mode.

**Adapt:** test variation across consumers and keep transport chunks independent from screen transactions. **Counterexamples:** a consumer's locally selected grid is not universal protocol truth; incremental screens need not begin with clear, and one packet need not contain a complete screen. The string/append boundary concerns resemble R14's shared parser lineage, so the two implementations are one family of evidence.

**Proof to add:** incremental update without clear, clear/write/draw split across chunks, mode change, dropped/interrupted update, bounded glyph/image dimensions and capacity checks. Preserve a declared last completed frame with stale state if the next frame cannot be admitted. **Packets:** 05a and optional 08c; no renderer/parser port proposed.

### R16 — ArduPilot/ardupilot_gazebo
Commit: `f116b03552d05c8d0b0bed5ed67033a1183121d1` (main). [License](https://github.com/ArduPilot/ardupilot_gazebo/blob/f116b03552d05c8d0b0bed5ed67033a1183121d1/LICENSE.md): LGPL v3 text.

**Trace:** [ArduPilotPlugin.cc](https://github.com/ArduPilot/ardupilot_gazebo/blob/f116b03552d05c8d0b0bed5ed67033a1183121d1/src/ArduPilotPlugin.cc) distinguishes world/body/model transforms and exchanges simulator state with the controller; [gimbal model](https://github.com/ArduPilot/ardupilot_gazebo/blob/f116b03552d05c8d0b0bed5ed67033a1183121d1/models/gimbal_small_3d/model.sdf) authors a joint-chain camera. [GstCameraPlugin.cc](https://github.com/ArduPilot/ardupilot_gazebo/blob/f116b03552d05c8d0b0bed5ed67033a1183121d1/src/GstCameraPlugin.cc) uses a bounded leaky video queue.

**Adapt:** explicitly authored mount transforms/axes and a latency policy for optional visual frames. **Counterexamples:** source comments question an inverse under nontrivial yaw; default symmetric transforms can conceal mistakes. Blocking lockstep controller receives belong to an admitted firmware simulator, outside OpenRC's presentation observer. Dropping obsolete video frames does not authorize dropping accepted ticks, gimbal commands or events.

**Proof to add:** asymmetric translated mounts and independently known noncommuting rotations, plus blocked-consumer/queue-overflow invariance. The [test gimbal scene](https://github.com/ArduPilot/ardupilot_gazebo/blob/f116b03552d05c8d0b0bed5ed67033a1183121d1/tests/worlds/test_gimbal.sdf) is a scene fixture and contains a yaw-joint reference inconsistent with its selected two-axis model; no runtime failure was tested. **Packets:** 01a/b/d, 02e, 04a/d, optional 08a.

### R17 — PX4/PX4-Autopilot
Commit: `288b114841caf27816bb25846dc7dbc1f1e5ad23` (main). [License](https://github.com/PX4/PX4-Autopilot/blob/288b114841caf27816bb25846dc7dbc1f1e5ad23/LICENSE): BSD 3-clause.

**Trace:** [gimbal/common.h](https://github.com/PX4/PX4-Autopilot/blob/288b114841caf27816bb25846dc7dbc1f1e5ad23/src/modules/gimbal/common.h) declares per-axis follow/rate/world-lock semantics; [input_mavlink.cpp](https://github.com/PX4/PX4-Autopilot/blob/288b114841caf27816bb25846dc7dbc1f1e5ad23/src/modules/gimbal/input_mavlink.cpp) checks primary source identity. [output.cpp](https://github.com/PX4/PX4-Autopilot/blob/288b114841caf27816bb25846dc7dbc1f1e5ad23/src/modules/gimbal/output.cpp) expires rates and clamps travel. [SimulatorMavlink.cpp](https://github.com/PX4/PX4-Autopilot/blob/288b114841caf27816bb25846dc7dbc1f1e5ad23/src/modules/simulation/simulator_mavlink/SimulatorMavlink.cpp) ties simulator-clock advancement to the appropriate sensor path.

**Adapt:** source arbitration, axis capability, asymmetric limits and rate expiry. **Reject direct math/timing:** Euler-component compensation and an update-loop delta do not establish continuous arbitrary-orientation optics; external autopilot lockstep does not replace OpenRC accepted-tick presentation.

**Proof to add:** mode changes, inversion, ±180° crossing, asymmetric limits and source loss. [MatrixAttitudeTest](https://github.com/PX4/PX4-Autopilot/blob/288b114841caf27816bb25846dc7dbc1f1e5ad23/src/lib/matrix/test/MatrixAttitudeTest.cpp) contains useful noncommuting rotation/inverse assertions; those tests were not run and do not qualify the whole gimbal. **Packets:** 04a–d; optional 08a/b.

### R18 — microsoft/AirSim
Commit: `1ca93f6f77e4e8a39b2b241c1fe2764da4d7dd41` (main); GitHub metadata reported not archived. [Root license](https://github.com/microsoft/AirSim/blob/1ca93f6f77e4e8a39b2b241c1fe2764da4d7dd41/LICENSE) contains MIT text despite metadata `NOASSERTION`.

**Trace:** [NedTransform.cpp](https://github.com/microsoft/AirSim/blob/1ca93f6f77e4e8a39b2b241c1fe2764da4d7dd41/Unreal/Plugins/AirSim/Source/NedTransform.cpp) distinguishes local/global positions, velocity, scale and orientation. [AirSimSettings.hpp](https://github.com/microsoft/AirSim/blob/1ca93f6f77e4e8a39b2b241c1fe2764da4d7dd41/AirLib/include/common/AirSimSettings.hpp) supports camera overrides from shared defaults. [PIPCamera.cpp](https://github.com/microsoft/AirSim/blob/1ca93f6f77e4e8a39b2b241c1fe2764da4d7dd41/Unreal/Plugins/AirSim/Source/PIPCamera.cpp) uses target dimensions for projection and performs its stabilization in actor Tick.

**Adapt:** one frame boundary, hierarchical mount/camera settings and actual render-target geometry. **Counterexample:** that stabilization blends Euler components without the requested joint/rate dynamics; Unreal conversions are not Godot conversions. [QuaternionTest.hpp](https://github.com/microsoft/AirSim/blob/1ca93f6f77e4e8a39b2b241c1fe2764da4d7dd41/AirLibUnitTests/QuaternionTest.hpp) does not provide an executed asserted gimbal acceptance test: the invoked rotation-order routine lacks assertions and another routine is disabled.

**Proof to add:** coordinate/unit/datum fixtures, per-vehicle override resolution, aspect changes and accepted-tick gimbal continuity. **Packets:** 01a, 02b/e, 04b/d. No engine or simulation-stack dependency proposed.

### R19 — FlightGear/flightgear
Commit: `807e406dd3bceca816942490a999970e157dbcfa` (`next`). [License](https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/LICENSE.md): GPL v2 text; inspected view-source notice states v2 or later.

**Trace:** [view.cxx](https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/src/Viewer/view.cxx), particularly `View::createFromProperties` and `recalcLookFrom`, separates authored position, orientation, FOV and near plane and combines them with the model pose. [viewmgr.cxx](https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/src/Viewer/viewmgr.cxx) applies the current view to the camera. [CameraGroup.cxx](https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/src/Viewer/CameraGroup.cxx) keeps GUI projection distinct.

**Adapt:** data-defined onboard views and one active owner; keep structural mount data separate from world pose. **Limits:** the source retains aircraft-specific assumptions and sign conventions; its larger multi-camera system exceeds this task's initial scope.

**Proof to add:** atomic valid/invalid mount switch, no stale subscribers, one final camera write, independent mount/FOV/frame cases. [View tests](https://github.com/FlightGear/flightgear/blob/807e406dd3bceca816942490a999970e157dbcfa/test_suite/unit_tests/general/test_Views.cxx) assert named-view switching, while an invalid-index assertion is compiled out; source existence does not prove failed-switch behavior. **Packets:** 01d, 02a/b/d/e, 05e, 06a.

### R20 — OpenHD/QOpenHD
Commit: `76bd7dae112ba63880d70ae0811a113cb5828fab` (`2.7-evo`). [License](https://github.com/OpenHD/QOpenHD/blob/76bd7dae112ba63880d70ae0811a113cb5828fab/LICENSE) includes GPL v3 text plus an additional credits restriction; GitHub reports `NOASSERTION`. Record those actual terms rather than calling it unmodified GPL-3.0.

**Trace:** [video_ratio_helper.hpp](https://github.com/OpenHD/QOpenHD/blob/76bd7dae112ba63880d70ae0811a113cb5828fab/app/videostreaming/vscommon/video_ratio_helper.hpp) fits and centers video; [BaseWidget.qml](https://github.com/OpenHD/QOpenHD/blob/76bd7dae112ba63880d70ae0811a113cb5828fab/qml/ui/widgets/BaseWidget.qml) retains widget alignment. [fcmavlinksystem.cpp](https://github.com/OpenHD/QOpenHD/blob/76bd7dae112ba63880d70ae0811a113cb5828fab/app/telemetry/models/fcmavlinksystem.cpp) exposes FC telemetry; [horizonladder.cpp](https://github.com/OpenHD/QOpenHD/blob/76bd7dae112ba63880d70ae0811a113cb5828fab/app/osd/horizonladder.cpp) draws rounded, linearly spaced attitude marks.

**Adapt independently:** explicit image-rectangle/layout mapping and movable widgets. **Counterexamples:** unknown heading is mapped to zero; zero latitude/longitude is treated as missing for home-distance calculation. Valid equator/meridian locations therefore motivate independent availability flags. The aircraft-attitude ladder is not a camera-world projection.

**Proof to add:** zero dimensions, resize/letterbox geometry, legitimate zero coordinates, missing home, stale heading and banked-body/stabilized-camera cases. No relevant automated test surfaced in the inspected app/QML subtrees; a repository-wide absence is not claimed. **Packets:** 02e, 03b/c, 05d/e, optional 08b.

## Evidence limits and implementation order

The review found reusable contracts and counterexamples, not a ready-made universal FPV subsystem to transplant. Selected source tests suggest useful expectations, but none was executed here. No upstream build, firmware pair, device, wire transport, video alignment, on-screen fidelity, pilot behavior or target-hardware performance has been qualified.

The lead checked the important adopted claims against original pinned code, including INAV coordinate packing, ArduPilot EAS and estimator freshness tests, QGC yaw conversion, MAVLink battery sentinels, MAVSDK device matching, DisplayPort dispatch, Gazebo transform comments and AirSim stabilization. OpenRC's existing runtime remains the source for integration ownership. The remaining criteria are explicit in the plan.

Retain the execution order: **00c/00d → 01a/01b**, then shared extraction, universal fixed FPV, common telemetry, gimbals, profile/editor work and integrated fleet/platform qualification. Optional log/video tools and live protocols follow their admission gates. A full GCS, a new database, a browser UI, an external physics engine and hardware-specific OSD code are not required dependencies.

Any later code/font reuse must retain file-specific terms and provenance. This change carries original analysis and links only. Historical implementations remain references; references do not create runtime dependencies.
