# Every Input Matters — delivered trailer

2026-10-17 · TRA-01…07 · Local film delivered; publication was not requested.

Latest edit: [revision 6](revision-6-2026-10-17.md) removes the abrupt reset before the logo and ends at 58 seconds. Feature titles, native ramp jump, formation opening, continuous score, twilight Lumber and two Extra rolls are retained. This report retains the first delivery's capture and export evidence.

The [production plan](../../plans/cinematic-trailer.md) and [16-topic research ledger](2026-10-17.md)
led to a complete **60-second English trailer** with eight distinct vehicles, real flying/driving,
weather, controls, a priced native incident and a labeled four-aircraft finale.

## Delivery and measured output

Durable folder: `C:/DEVELOPMENT/OpenRCsimulator-exports/trailer-2026-10-17/`.

| Item | Accepted result |
| --- | --- |
| Film | `OpenRC-Every-Input-Matters-60s-1080p60.mp4` |
| Duration / frames | 60.000 seconds; 3,600 frames; constant 60 fps |
| Picture / sound | Native 1920×1080, H.264; AAC stereo, 48 kHz |
| File size | 250,844,422 bytes |
| SHA-256 | `66e32950c082cf33a6c430bca91af67c00fbc28725c638c21fe6a45c470b2d19` |
| Decoded AAC loudness | −13.96 LUFS integrated; −1.48 dBTP; 4.30 LU loudness range |
| Technical checks | Full video/audio decode; exact duration, dimensions, rate and frame count; Python editor compilation |
| Visual checks | Seventeen midpoint frames/contact sheet; full-size impact/report/restart/lightning/formation samples; native capture manifests |
| Remaining review | Listening balance/musical joins, full-motion small-screen review and existing Turbo Lumber asset release notice |

The export includes README, timeline, render manifest, description/credits, poster, contact sheet,
original/derived sources, editor snapshot, evidence and licenses. The poster is a final-video frame.
Original MJPEG/PCM takes and lossless derived sources remain separate from the H.264 delivery.
See [trailer tools](../../../tools/trailer/README.md) for rebuilding and the compact
[delivery manifest](delivery-2026-10-17.json) for final identity. Large media lives outside Git.

## Accepted timeline

| Film time | Subject / actual result | Frames |
| --- | --- | ---: |
| 00–04 | Ventage Jet pass; turbine opening | 240 |
| 04–08 | Jensen Das Ugly Stik 60 bank with native smoke | 240 |
| 08–12 | Extra 300S .60 completes a normal-speed roll, followed by a banked exit | 240 |
| 12–15 | P-51D Mustang 1/4 banked pass | 180 |
| 15–18 | Turbo Lumber Evolution electric pass | 180 |
| 18–23 | RC Helicopter Research Trainer hover, yaw and forward transition | 300 |
| 23–27 | Bisonte MT8 grounded steering/acceleration | 240 |
| 27–31 | MONSTER CAR 2 grounded steering/acceleration | 240 |
| 31–34 | Native electrical-storm tower and cloud-to-ground lightning | 180 |
| 34–38 | Stik responding to configured physical wind/gusts | 240 |
| 38–42 | Native flight/control UI; `TAKE CONTROL.` | 240 |
| 42–43.45 | Actual Stik approach; `MISTAKES COST.` | 87 |
| 43.45–44.5 | Impact and wreck visible before the native report appears | 63 |
| 44.5–48 | Native provisional accident estimate, including a 0.55-second editorial still hold | 210 |
| 48–50 | Result of native Restart action | 120 |
| 50–57 | Four-plane authored formation and fan-out, labeled throughout | 420 |
| 57–60 | OpenRC end card; `EVERY INPUT MATTERS.` | 180 |

The original storyboard's Stik takeoff, Mustang gear transition, Turbo landing and truck jump were
not accepted shots and are not claimed. Three additional Stik engine configurations share one
visual family; eleven configurations are not advertised as eleven designs. The Extra take records
about 410.47° unwrapped roll by its banked exit and minimum altitude about 32.8 m. The helicopter
reaches about 2.34 m/s forward speed. Flight commands enter the actual simulation; helicopter/car
drivers use normal keyboard events. No flown maneuver is sped up or interpolated.

The minute contains 47 seconds of simulation-origin flight/driving and UI (including the 0.55-second
report hold), three seconds of native storm presentation, seven seconds of staged formation and
three seconds of titles. It is not represented as sixty seconds of interactive gameplay.

## Native incident and weather

Accepted take: `stik-propstrike-v4-visible-impact`. Propeller ground contact occurs at tick 345,
approximately 11,129 rpm, followed by terminal nose-gear travel-limit impact at tick 350.
The confirmed propeller replacement subtotal is **US$5.39**; `total_minor` is null and `complete`
is false. The native headline **US$5.39–US$1,331** is explicitly provisional, with whole-aircraft
replacement as the upper limit and inspection pending. No price was invented or substituted.
Report catalog hash: `79bc366ea4386a1775f73017d8107be1df807ebe183f7889916164c66a8436c8`.

Only presentation visibility changed: the report CanvasLayer stays hidden until 60 post-impact
frames, then native details expand. Native Restart is accepted at +240, with 120 post-restart frames.
Source ranges are [3,90), [90,153), [153,330) and [330,450); the 177-frame report segment receives
a 33-frame still extension. Original incident: `evidence/incident.json`, identity
`2026-10-17T14:51:55-7501021`.

Storm visuals use seed 1001, event `548234009:0`; its bolt appears at source frame 118, about
32.92 seconds into the film. Thunder comes from a closer recording of the same event, where its
native voice starts at simulation time 2.408333 seconds. The wide camera's arrival would be
33.876 seconds, outside that take. This closer microphone perspective is an editorial sound choice,
not the wide camera's physical travel time. The tail bridges into a separate wind shot: base wind
4 m/s from 130°, gust 5 m/s, upward component 1.5 m/s, duration 2 s, period 6 s, delay 0.5 s.

## Formation, capture and code

Four production Stik render actors share the field with native smoke/propeller presentation.
Their authored paths have no simulation session or interacting vehicle physics. All four remain
visible in 420 frames: minimum center separation 6.169267 m, maximum model radius 1.032725 m,
minimum screen margin 108.01 px. Persistent `CINEMATIC FORMATION SEQUENCE` labeling prevents a
multiplayer claim. The first four seconds hold the wide formation, followed by a three-second fan-out.

Godot 4.7.2 stable, Compatibility/OpenGL, captures at 60 fps with 240 Hz ordinary flight simulation
and synchronized 48 kHz PCM. An isolated startup project sets 1920×1080 before Movie Maker starts.
Its directories are junctions to the working tree, not a frozen checkout. Startup offsets are three
frames for fixed-wing takes, nine for the helicopter and eight for each truck. Original media and
input/state records are retained.

Python/Pillow 12.3.0 and FFmpeg/ffprobe 9.0.2 provide frame trims, titles, restrained grading,
audio envelopes, loudness normalization and encoding. Capture tools author cameras and the staged
formation. Selected HUD-free shots remove only an empty top-left UI panel; controls and cost
qualifications remain native. The trailer track changed no application physics, model geometry,
economics or prices.

Concurrent work changed application source during filming. `evidence/source-identities.json`
records handoff tree identities, **not one frozen revision for every take**. App tree observed at
handoff: `6299d43140cb98187ba91b4f853173cfb30eae21`. Original captures, incident/config identities
and the editor snapshot explain the delivered cut. No `.orfl` exact-replay qualification or
physical-validation claim is made.

## Music, licenses and remaining review

Music: **Uprising — Scott Buckley**, acquired from the [creator's page](https://www.scottbuckley.com.au/library/uprising/)
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), edited to the minute and mixed
with simulator sound. Attribution is retained in the end card and `VIDEO-DESCRIPTION.txt`:

> 'Uprising' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au

Source URL, hashes, modifications and license evidence are retained. Barlow Condensed retains its
SIL Open Font License. No paid stock, third-party trailer footage, generative-video output, new
aircraft asset or newly installed video skill was used.

Audio was measured, **not auditioned**: this environment could not provide listening input.
Musical joins and subjective vehicle/music balance remain a listening-review gate. Visual review
uses sampled full-size and contact-sheet frames; it does not establish complete real-time phone
playback review.

The existing `app/assets/aircraft/turbo-lumber-evolution/LICENSE.txt` says redistribution terms
are not set and the package is for internal evaluation. Its notice and other project asset notices
are copied into `licenses/`. Local delivery does not change those terms or establish public-release
clearance. Resolve that notice and complete listening review before publication. No upload,
purchase or publication was performed.
