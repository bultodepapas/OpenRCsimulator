# Reddit launch feedback — 2026-10-26

[Full post and comment transcript](comments.md) · [Original Reddit discussion](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/)

This snapshot preserves the first-public-release discussion for later analysis. It includes criticism, praise, questions, offers to contribute, side conversations and the author's replies. Original wording is quoted in the transcript; the observations below are preliminary interpretation.

## Coverage

| Item | Retrieved |
| --- | ---: |
| Unique comments | 169 |
| Top-level comments / replies | 50 / 119 |
| Distinct author handles, including OP | 68 |
| OP comments / other participants' comments | 54 / 115 |
| Reddit's advertised comment count | 170 |
| Unexpanded `more` placeholders | 0 |

**The one-comment discrepancy remains unresolved.** Every comment returned by the listing is preserved, but this cannot establish recovery of all comments ever posted. No retrieved comment has a deleted/removed body. See [source and coverage](comments.md#source-and-coverage) for acquisition, timestamp, ordering and transcription limits. The [specific comment supplied by the user](comments.md#comment-19rjlwu08zdr8) is included.

## Preliminary reading guide

These categories are navigation aids, not exhaustive coding or counts of independent reports. A comment can address several topics. Statements about physics, compatibility, completed fixes and contributor experience remain attributed claims; they have not been verified against the current application.

| Topic | What to inspect | Source comments |
| --- | --- | --- |
| First-session blockers | A TX16s MkIII tester reports unrecognized rudder/channel 4, confusing setup and three-position flap mapping, flight-start friction, a stuck restart and persistent crash notification. Another tester reports menu-navigation problems but successful EdgeTX setup. Preserve both outcomes. | [coffeemonkeypants](comments.md#comment-phl3c4y), [PotentiallyHeavy](comments.md#comment-phe2ol3), [calibration wizard request](comments.md#comment-phf2r84) |
| Aircraft handling and landing | Turbo Timber pitch oscillation, large down-trim requirement and overly sensitive crash detection; post-stall aileron reversal, abrupt stall transition and propwash issues. The same contributor praises relaxed Ugly Stik flight. | [Timber report](comments.md#comment-phl3c4y), [initial post-stall report](comments.md#comment-phe2ol3), [candidate progress](comments.md#comment-phenubh), [PR and possible frame-rate regression](comments.md#comment-phg0fnf) |
| Helicopter and low-speed behavior | A hands-on tester reports insufficient inertia in trainer mode, pitch/roll coupling in cyclic mode and difficult or impossible low-speed airplane maneuvers. Other users judge the helicopter's stability from footage. | [hands-on report](comments.md#comment-phj8c6j), [hover impression](comments.md#comment-phi1hc7), [trailer criticism](comments.md#comment-phqde5f) |
| Physical validation | Questions about polars, inertia, turbulence, aerodynamic methods and demonstrated validity; requests for differences between airframes in the same wind. Participants challenge the unqualified “hyper-realistic” claim. | [polars and validation](comments.md#comment-phdquq7), [inertia and soaring](comments.md#comment-pher5ay), [turbulence exchange](comments.md#comment-phdofoe), [airframe-dependent response](comments.md#comment-phdo6kf), [validity limits](comments.md#comment-phe35xw), [aerobatics discussion](comments.md#comment-phnqyo3) |
| Trust and presentation | Questions about brand support, AI use and generated replies; concerns about website language and a trailer that does not clearly show pilot view, control surfaces or damage. OP later distinguishes realism goals from demonstrated accuracy. | [support question](comments.md#comment-phcxh0v), [OP clarification](comments.md#comment-phczogf), [validation clarification](comments.md#comment-phdkggq), [trailer and openness](comments.md#comment-phdobys), [AI replies](comments.md#comment-19reby2v0rjoh), [website criticism](comments.md#comment-phl3c4y) |
| Scenery and extensibility | Aircraft import, map editing/sharing, downloadable scenery, 360-degree airfield photographs and variable terrain; also requests for VR, multiplayer and local-field generation. | [feature list](comments.md#comment-phdnffp), [360-photo import](comments.md#comment-phgcuuq), [support for photo import](comments.md#comment-phhk8lm), [mountain flying](comments.md#comment-19rjg49nlanvn), [Flyout import](comments.md#comment-phev6pm) |
| Platforms, controls and new activities | Mac and Spektrum questions; mobile availability, gliders, thermals/high-start, FPV/drones and autopilot integration. A request or OP reply does not establish compatibility or implementation. | [Mac/Spektrum/ArduPilot](comments.md#comment-phdo7r8), [Spektrum request](comments.md#comment-phi06oh), [mobile or computer question](comments.md#comment-19rjlwu08zdr8), [sailplanes](comments.md#comment-pheu933), [thermals](comments.md#comment-pher5ay), [FPV](comments.md#comment-phd3c28) |
| Collaboration and positive signals | Offers of code contributions and Blender modeling, FlightCoach/FlightScore integration, technical exchanges with other simulator developers, interest in teaching children and praise for accessible trainer flying. | [FlightCoach/FlightScore](comments.md#comment-phdpfpr), [Blender offer](comments.md#comment-19rhm45cp6543), [soaring developer](comments.md#comment-phdtr17), [other simulator developer](comments.md#comment-phiirnq), [teaching a child](comments.md#comment-phdkhcy), [trainer praise](comments.md#comment-phe2ol3) |

## Suggested next analysis

Start with reported hands-on blockers and handling problems, especially [coffeemonkeypants' detailed trial](comments.md#comment-phl3c4y), [reallifearcade's test](comments.md#comment-phj8c6j) and [PotentiallyHeavy's observations](comments.md#comment-phe2ol3). Split each into individual issues, preserving its comment ID, aircraft, controller, conditions and expected behavior. Record unspecified builds or settings as unknown. Reproduce against an identified build before assigning current defect status; this thread spans several days of a rapidly changing alpha.

Separate observed behavior, video impressions, feature requests, technical hypotheses, OP commitments and discussion about AI. Do not treat dissatisfaction with another simulator as a defect in OpenRC. Do not infer real-money charges from comments about the crash cost display. Treat contributor reports of a fix or PR as leads until their implementation and validation are checked.

Evaluate public wording alongside product findings: the thread contains both concrete engineering feedback and skepticism about broad realism claims. This reading suggests prioritizing a reliable first flight, reproducible handling evidence and clear descriptions of current capabilities before choosing additional features. That is an interpretation of the discussion, not a measured community ranking or a new project plan.

## Verification

All 169 retrieved bodies were checked against their generated Markdown blockquotes. Comment IDs and anchors are unique; every non-root parent resolves; the requested comment is present; top-level/reply and OP/non-OP counts reconcile. Original media URLs remain in the transcript, without local image copies. The collection records a historical discussion and does not alter runtime behavior or establish physical validation.
