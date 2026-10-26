# Comment coding and descriptive statistics

Generated from [annotations.tsv](../../../research/reddit-launch-feedback/annotations.tsv) and the [archived transcript](comments.md) by [analyze.py](../../../research/reddit-launch-feedback/analyze.py). See [interpretation and limits](insights.md).

Regenerate: `python3 research/reddit-launch-feedback/analyze.py`; verify without writing: append `--check`.

## Scope and denominators

- 169 comment records; 54 OP replies retained as context but excluded from community statistics.
- 115 community comments by 67 distinct handles. Handles are not verified unique humans or independent samples.
- Multi-label manual coding: discussion is not necessarily a request, support, complaint or hands-on test.
- Scores are archived net scores. They are not upvote counts, unique supporters or feature votes. No scores are refreshed here.
- Theme score sums overlap when a comment has several tags; never add rows or treat these sums as priority scores.
- Feature rows count explicit requests/questions/endorsements. Follow-ups by the same handle do not add a requester. Request families and subsets overlap.

## Topic recurrence (community only)

| Topic | Comments | Handles / 67 | % of handles | Sum of comment scores | Median | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Explicit encouragement or positive interest (`SUPPORT`) | 26 | 22 | 32.8% | 133 | 2 | 21 |
| AI use and development process (`AI`) | 30 | 21 | 31.3% | 153 | 2 | 34 |
| Public wording, presentation and discoverability (`COMMUNICATION`) | 22 | 19 | 28.4% | 115 | 1 | 34 |
| Handling, physical methods and validation questions (`PHYSICS`) | 27 | 17 | 25.4% | 107 | 1 | 34 |
| Credibility, evidence and realism claims (`CREDIBILITY`) | 17 | 13 | 19.4% | 110 | 2 | 34 |
| Offers, contributions and technical exchanges (`COLLABORATION`) | 19 | 11 | 16.4% | 63 | 2 | 16 |
| Free/open source and competitor differentiation (`VALUE`) | 13 | 10 | 14.9% | 95 | 6 | 21 |
| Soaring, drones, autopilots and other activities (`ACTIVITIES`) | 8 | 7 | 10.4% | 19 | 2 | 5 |
| Aircraft/field import, creation and sharing (`AUTHORING`) | 8 | 7 | 10.4% | 62 | 4 | 28 |
| Jokes and tangential non-product conversation (`OFF_TOPIC`) | 10 | 7 | 10.4% | 11 | 1 | 2 |
| Scenery quality, local fields and terrain (`SCENERY`) | 8 | 7 | 10.4% | 35 | 2.5 | 16 |
| Radios, calibration and mapping (`CONTROLS`) | 10 | 6 | 9.0% | 26 | 2.5 | 6 |
| Training, menus, starts, resets and crash workflow (`PRACTICE`) | 6 | 5 | 7.5% | 45 | 1.5 | 34 |
| Platforms, VR, multiplayer and language availability (`PLATFORMS`) | 4 | 4 | 6.0% | 21 | 2 | 16 |
| Ground-pilot and onboard/FPV views (`CAMERAS`) | 3 | 3 | 4.5% | 34 | 5 | 28 |
| Runtime performance observations (`PERFORMANCE`) | 1 | 1 | 1.5% | 2 | 2 | 2 |

## Explicit feature and compatibility signals

Scores below belong to whole comments, often containing several requests. The peak score must not be interpreted as votes for the named feature. This table deliberately does not sum feature scores.

| Family | Distinct handles | Comments | Peak whole-comment score | All source comments |
| --- | ---: | ---: | ---: | --- |
| Custom aircraft import/integration, including Flyout | 4 | 4 | +28 | [phdnffp](comments.md#comment-phdnffp), [phdo7r8](comments.md#comment-phdo7r8), [phdobys](comments.md#comment-phdobys), [phev6pm](comments.md#comment-phev6pm) |
| Create/import/share a familiar field or lake | 4 | 4 | +16 | [phdnffp](comments.md#comment-phdnffp), [phds52r](comments.md#comment-phds52r), [phgcuuq](comments.md#comment-phgcuuq), [phhk8lm](comments.md#comment-phhk8lm) |
| Optional/unobtrusive crash costs and practice workflow | 2 | 2 | +1 | [phl3c4y](comments.md#comment-phl3c4y), [phm1s3y](comments.md#comment-phm1s3y) |
| FPV/first-person view or support | 2 | 2 | +28 | [phd3c28](comments.md#comment-phd3c28), [phdobys](comments.md#comment-phdobys) |
| Ground-pilot camera | 2 | 2 | +28 | [phdobys](comments.md#comment-phdobys), [phg2kxv](comments.md#comment-phg2kxv) |
| Specifically import a 360-degree airfield photograph | 2 | 2 | +3 | [phgcuuq](comments.md#comment-phgcuuq), [phhk8lm](comments.md#comment-phhk8lm) |
| Easier radio setup or move-to-bind mapping | 2 | 3 | +4 | [phe2ol3](comments.md#comment-phe2ol3), [phf2r84](comments.md#comment-phf2r84), [phl3c4y](comments.md#comment-phl3c4y) |
| Sailplanes or thermals/high-start soaring | 2 | 2 | +4 | [pher5ay](comments.md#comment-pher5ay), [pheu933](comments.md#comment-pheu933) |
| Spektrum compatibility question/request | 2 | 2 | +3 | [phdo7r8](comments.md#comment-phdo7r8), [phi06oh](comments.md#comment-phi06oh) |
| Visible flex/deformation or continued damaged flight | 2 | 2 | +28 | [phdo6kf](comments.md#comment-phdo6kf), [phdobys](comments.md#comment-phdobys) |
| ArduPilot and simultaneous manual control | 1 | 1 | +3 | [phdo7r8](comments.md#comment-phdo7r8) |
| Drone support | 1 | 1 | +5 | [phd3c28](comments.md#comment-phd3c28) |
| Port aircraft physics into other game worlds | 1 | 1 | +2 | [phduope](comments.md#comment-phduope) |
| AI/MCP-assisted field creation | 1 | 2 | +16 | [phdnffp](comments.md#comment-phdnffp), [phe1v11](comments.md#comment-phe1v11) |
| FlightCoach/FlightScore real-flight interchange | 1 | 1 | +2 | [phdpfpr](comments.md#comment-phdpfpr) |
| Language availability/discoverability | 1 | 1 | +1 | [phg538c](comments.md#comment-phg538c) |
| Mac availability | 1 | 1 | +3 | [phdo7r8](comments.md#comment-phdo7r8) |
| Mobile/desktop availability clarification | 1 | 1 | +1 | [19rjlwu08zdr8](comments.md#comment-19rjlwu08zdr8) |
| Multiplayer | 1 | 1 | +16 | [phdnffp](comments.md#comment-phdnffp) |
| Steerable rockets | 1 | 2 | +1 | [phfj1uu](comments.md#comment-phfj1uu), [phlic90](comments.md#comment-phlic90) |
| Downloadable scenery packs | 1 | 1 | +16 | [phdnffp](comments.md#comment-phdnffp) |
| Variable terrain and mountain surfing | 1 | 1 | +2 | [19rjg49nlanvn](comments.md#comment-19rjg49nlanvn) |
| VR support | 1 | 1 | +16 | [phdnffp](comments.md#comment-phdnffp) |

## Highest-scoring community comments

| Comment | Author | Net score | Coding note |
| --- | --- | ---: | --- |
| [phe35xw](comments.md#comment-phe35xw) | UpbeatBass6066 | +34 | Urges modest validity claims and training utility; self-described engineering experience. |
| [phcxh0v](comments.md#comment-phcxh0v) | fvpv | +31 | AI dismissal combined with a concrete question about endorsements. |
| [phdobys](comments.md#comment-phdobys) | justadiode | +28 | Questions importer, visible controls, camera, despawn and flex; suspects commercialization while encouraging work. |
| [phdimcy](comments.md#comment-phdimcy) | TheTerribleInvestor | +21 | Defends potential community value of AI-assisted niche software. |
| [phd5v2k](comments.md#comment-phd5v2k) | FederalProfessor7836 | +20 | Defense against AI criticism; no feature request. |
| [phdnffp](comments.md#comment-phdnffp) | brainzhurtin | +16 | Multi-feature wishlist with scenery criticism and model praise; score cannot be split among features. |
| [phes36u](comments.md#comment-phes36u) | coffeemonkeypants | +16 | Refunded RealFlight; intends OpenRC trial and possible contributions. |
| [phd7a19](comments.md#comment-phd7a19) | FederalProfessor7836 | +13 | Names free and open source as differentiators. |
| [phd4i9t](comments.md#comment-phd4i9t) | Brendon7358 | +9 | Neutral question about proportion of vibe coding. |
| [phe6uyv](comments.md#comment-phe6uyv) | UpbeatBass6066 | +8 | Same critic explicitly encourages continuing the project. |
| [phd47gg](comments.md#comment-phd47gg) | GrParrot | +7 | Asks extent of AI use; quality matters more than provenance. |
| [phdbo1a](comments.md#comment-phdbo1a) | bbbbinion | +7 | Likes alternative to ad-supported mobile sim; does not explicitly request a mobile port. |
| [phd8ci1](comments.md#comment-phd8ci1) | FederalProfessor7836 | +6 | Further AI defense by same author. |
| [phda1pl](comments.md#comment-phda1pl) | anaximander19 | +6 | Distinguishes supervised AI development from uncomprehending generation. |
| [phdb7gl](comments.md#comment-phdb7gl) | bbbbinion | +6 | Supports free community-improvable project and defends AI use. |

## Explicit OpenRC usage reports

6 comments by 4 handles explicitly describe using/testing OpenRC. This is a conservative textual classification, not proof that other authors did not use it or that these reports were reproduced.

| Comment | Author | Net score | Observation |
| --- | --- | ---: | --- |
| [phdkhcy](comments.md#comment-phdkhcy) | jhsantacruz63 | +6 | Played with keyboard; plans to teach child and later test radio. |
| [phe2ol3](comments.md#comment-phe2ol3) | PotentiallyHeavy | +1 | Post-stall reversal and menu issues; praises trainer flight and EdgeTX; requests move-to-bind mapping. |
| [phenubh](comments.md#comment-phenubh) | PotentiallyHeavy | +1 | Reports candidate progress and remaining stall/propwash issues; not a second tester. |
| [phg0fnf](comments.md#comment-phg0fnf) | PotentiallyHeavy | +2 | PR submission and possible frame-rate cost; tooling confound explicitly noted. |
| [phj8c6j](comments.md#comment-phj8c6j) | reallifearcade | +5 | Reports helicopter inertia/cyclic coupling and airplane low-speed problems after quick trial. |
| [phl3c4y](comments.md#comment-phl3c4y) | coffeemonkeypants | +1 | Left after five minutes; input/start/restart/damage/Timber/landing/copy issues with encouragement. |

## Complete coding ledger

Every archived record appears once below. OP replies remain available through their source links. `unknown` means the comment does not establish exposure; `other_product` includes real-world experience and discussion of another product. `website` does not establish simulator use. Theme and request definitions are in the generator; individual inclusion judgments are in the annotation file.

| Comment | Author | Score | Kind / exposure | Themes | Explicit requests | Interpretation |
| --- | --- | ---: | --- | --- | --- | --- |
| [phcxh0v](comments.md#comment-phcxh0v) | fvpv | +31 | meta / unknown | AI, CREDIBILITY, COMMUNICATION | — | AI dismissal combined with a concrete question about endorsements. |
| [phcyzwn](comments.md#comment-phcyzwn) | TitaniumKneecap | +0 | offtopic / unknown | OFF_TOPIC | — | Reaction only; no product request. |
| [phczogf](comments.md#comment-phczogf) | bultodepapas (OP) | +12 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd47gg](comments.md#comment-phd47gg) | GrParrot | +7 | question / unknown | AI | — | Asks extent of AI use; quality matters more than provenance. |
| [phd5o4l](comments.md#comment-phd5o4l) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdhrsz](comments.md#comment-phdhrsz) | GrParrot | -6 | question / unknown | AI, CREDIBILITY | — | Requests experimental validation of realism claims. |
| [phdkggq](comments.md#comment-phdkggq) | bultodepapas (OP) | +16 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phgrbxf](comments.md#comment-phgrbxf) | MrGriffin77 | +3 | support / unknown | AI, CREDIBILITY, SUPPORT | — | AI opponent appreciates transparency and allows careful use. |
| [phdimcy](comments.md#comment-phdimcy) | TheTerribleInvestor | +21 | meta / unknown | AI, VALUE, SUPPORT | — | Defends potential community value of AI-assisted niche software. |
| [phdkzga](comments.md#comment-phdkzga) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdyzfq](comments.md#comment-phdyzfq) | fvpv | +0 | impression / video | AI, CREDIBILITY, PHYSICS, COMMUNICATION | — | Uses AI personally but criticizes perceived sloppiness and physics. |
| [phd3c28](comments.md#comment-phd3c28) | Njvaporent | +5 | request / unknown | ACTIVITIES, CAMERAS | fpv, drones | Asks about drone or FPV support. |
| [phd67jg](comments.md#comment-phd67jg) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd698u](comments.md#comment-phd698u) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd4i9t](comments.md#comment-phd4i9t) | Brendon7358 | +9 | question / unknown | AI | — | Neutral question about proportion of vibe coding. |
| [phd640f](comments.md#comment-phd640f) | bultodepapas (OP) | +9 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdnkfx](comments.md#comment-phdnkfx) | New-Owl-6105 | +2 | meta / unknown | AI, CREDIBILITY | — | Defends an honest OP answer in the AI discussion. |
| [phd5en6](comments.md#comment-phd5en6) | Professional_Will241 | +1 | impression / unknown | AI, COMMUNICATION | — | Attributes appearance to Claude. |
| [phd5wzf](comments.md#comment-phd5wzf) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd6bbe](comments.md#comment-phd6bbe) | Professional_Will241 | -2 | meta / unknown | AI | — | Clarifies preceding AI remark was criticism; same author. |
| [phd84ha](comments.md#comment-phd84ha) | bultodepapas (OP) | +8 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdb7gl](comments.md#comment-phdb7gl) | bbbbinion | +6 | meta / unknown | AI, VALUE, SUPPORT | — | Supports free community-improvable project and defends AI use. |
| [phd5v2k](comments.md#comment-phd5v2k) | FederalProfessor7836 | +20 | meta / unknown | AI, SUPPORT | — | Defense against AI criticism; no feature request. |
| [phd6omr](comments.md#comment-phd6omr) | bultodepapas (OP) | +14 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd8ci1](comments.md#comment-phd8ci1) | FederalProfessor7836 | +6 | meta / unknown | AI, VALUE | — | Further AI defense by same author. |
| [phd988z](comments.md#comment-phd988z) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd99eu](comments.md#comment-phd99eu) | andarre | +2 | meta / unknown | AI | — | AI-discussion retort; not an OpenRC UAV request. |
| [phda1pl](comments.md#comment-phda1pl) | anaximander19 | +6 | meta / unknown | AI | — | Distinguishes supervised AI development from uncomprehending generation. |
| [phdcapb](comments.md#comment-phdcapb) | bultodepapas (OP) | +4 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdkfr9](comments.md#comment-phdkfr9) | mastermalpass | +1 | meta / other_product | AI | — | Personal AI-tool experience outside OpenRC. |
| [pherbvk](comments.md#comment-pherbvk) | coffeemonkeypants | +3 | meta / unknown | AI, COMMUNICATION | — | Emphasizes process and human editing of AI-style product language. |
| [phge6wl](comments.md#comment-phge6wl) | anaximander19 | +2 | meta / unknown | AI, COMMUNICATION | — | Supports AI development with review and editing; same author as phda1pl. |
| [phi7uje](comments.md#comment-phi7uje) | coldnebo | +2 | meta / unknown | CREDIBILITY, COMMUNICATION, SUPPORT | — | Skeptical of hyper-realistic marketing; intends to try. |
| [phfxtj3](comments.md#comment-phfxtj3) | satori-t | +2 | meta / unknown | AI | — | Criticizes categorical opposition to AI. |
| [phhin1p](comments.md#comment-phhin1p) | FederalProfessor7836 | +1 | meta / unknown | AI | — | General AI-adoption claims; no product evidence. |
| [phd65w3](comments.md#comment-phd65w3) | pokerfas | +4 | question / unknown | VALUE, SUPPORT | — | Asks differentiation from RealFlight. |
| [phd7a19](comments.md#comment-phd7a19) | FederalProfessor7836 | +13 | meta / unknown | VALUE | — | Names free and open source as differentiators. |
| [phd7uxb](comments.md#comment-phd7uxb) | bultodepapas (OP) | +8 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdmisz](comments.md#comment-phdmisz) | New-Owl-6105 | +1 | meta / unknown | VALUE, AI, CREDIBILITY | — | Explains alpha limitations and uncertain project longevity. |
| [phd75pn](comments.md#comment-phd75pn) | Adam627 | +3 | offer / unknown | COLLABORATION, SUPPORT | — | Tentative developer offer and engine-choice question; not an Unreal migration demand. |
| [phd7jgs](comments.md#comment-phd7jgs) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phd7isp](comments.md#comment-phd7isp) | Mezyi | -7 | meta / unknown | AI | — | AI attribution without a concrete product issue. |
| [phd8ffd](comments.md#comment-phd8ffd) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phddnf3](comments.md#comment-phddnf3) | PotentiallyHeavy | +4 | meta / unknown | AI | — | Defends AI against software-assembly analogy. |
| [phervbn](comments.md#comment-phervbn) | coffeemonkeypants | +2 | meta / unknown | AI | — | Agrees with preceding analogy; no new demand. |
| [phdbo1a](comments.md#comment-phdbo1a) | bbbbinion | +7 | comparison / other_product | VALUE, SUPPORT | — | Likes alternative to ad-supported mobile sim; does not explicitly request a mobile port. |
| [phdlfpy](comments.md#comment-phdlfpy) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdlfxz](comments.md#comment-phdlfxz) | Erizial | +3 | meta / unknown | VALUE, AI | — | Defends free/open-source project against AI criticism. |
| [phdji1f](comments.md#comment-phdji1f) | waffle_sheep | +3 | question / unknown | PHYSICS | — | Asks about rigid-body and rotational representation. |
| [phdlto8](comments.md#comment-phdlto8) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdofoe](comments.md#comment-phdofoe) | waffle_sheep | +1 | technical / other_product | PHYSICS, COLLABORATION | — | Shares AVL approach and asks turbulence details; not a direct custom-import request. |
| [phdqc83](comments.md#comment-phdqc83) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdte0k](comments.md#comment-phdte0k) | waffle_sheep | +1 | technical / other_product | PHYSICS, COLLABORATION | — | Describes spectral 3D turbulence construction in own work. |
| [phdtx9z](comments.md#comment-phdtx9z) | waffle_sheep | +1 | technical / other_product | PHYSICS | — | Adds incompressibility detail; same contributor. |
| [phdqn95](comments.md#comment-phdqn95) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdkhcy](comments.md#comment-phdkhcy) | jhsantacruz63 | +6 | experience / firsthand | PRACTICE, SUPPORT | — | Played with keyboard; plans to teach child and later test radio. |
| [phdlxc4](comments.md#comment-phdlxc4) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdlwn4](comments.md#comment-phdlwn4) | PotentiallyHeavy | +5 | offer / unknown | COLLABORATION, SUPPORT | — | Offers time and tokens; later provides actual contribution reports. |
| [phdm7b4](comments.md#comment-phdm7b4) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdpfpr](comments.md#comment-phdpfpr) | PotentiallyHeavy | +2 | request / unknown | COLLABORATION, PHYSICS, PRACTICE | flightcoach | Proposes real-flight import/export with FlightCoach and FlightScore. |
| [phdpv1q](comments.md#comment-phdpv1q) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phkf8p7](comments.md#comment-phkf8p7) | LupusTheCanine | +1 | technical / other_product | PHYSICS, COLLABORATION | — | Suggests ArduPilot logging for system identification; not a separate FlightScore request. |
| [phe2ol3](comments.md#comment-phe2ol3) | PotentiallyHeavy | +1 | experience / firsthand | PHYSICS, PRACTICE, CONTROLS, COLLABORATION, SUPPORT | radio_setup | Post-stall reversal and menu issues; praises trainer flight and EdgeTX; requests move-to-bind mapping. |
| [phenubh](comments.md#comment-phenubh) | PotentiallyHeavy | +1 | experience / firsthand | PHYSICS, COLLABORATION | — | Reports candidate progress and remaining stall/propwash issues; not a second tester. |
| [phewgi5](comments.md#comment-phewgi5) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phg0fnf](comments.md#comment-phg0fnf) | PotentiallyHeavy | +2 | experience / firsthand | PERFORMANCE, COLLABORATION | — | PR submission and possible frame-rate cost; tooling confound explicitly noted. |
| [phdnffp](comments.md#comment-phdnffp) | brainzhurtin | +16 | request / unknown | SCENERY, AUTHORING, PLATFORMS, COLLABORATION, SUPPORT | aircraft_import, local_fields, vr, multiplayer, scenery_packs, field_mcp | Multi-feature wishlist with scenery criticism and model praise; score cannot be split among features. |
| [phdpau3](comments.md#comment-phdpau3) | bultodepapas (OP) | +5 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdph6i](comments.md#comment-phdph6i) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phe1v11](comments.md#comment-phe1v11) | brainzhurtin | +5 | request / unknown | AUTHORING, SCENERY | field_mcp | Same author confirms interest in field-generation skill. |
| [phhrbbr](comments.md#comment-phhrbbr) | lukask04 | +1 | question / other_product | OFF_TOPIC | — | Asks about local LLM home automation. |
| [phiaijj](comments.md#comment-phiaijj) | brainzhurtin | +2 | technical / other_product | OFF_TOPIC | — | Local LLM tutorial and personal automation anecdotes; not new simulator requirements. |
| [phds52r](comments.md#comment-phds52r) | bbbbinion | +5 | request / unknown | SCENERY, AUTHORING | local_fields | Wants to import own lake; does not explicitly request a boat simulator. |
| [phdo6kf](comments.md#comment-phdo6kf) | mastermalpass | +1 | request / other_product | PHYSICS, AI | structural_damage | Wants airframe-specific gust response and continued flight after deformation; competitor and real-flight comparisons. |
| [phdsisr](comments.md#comment-phdsisr) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phgvf83](comments.md#comment-phgvf83) | mastermalpass | +1 | context / other_product | CONTROLS | — | Own Spektrum dongle problem before trying OpenRC; not an OpenRC defect report. |
| [phdo7r8](comments.md#comment-phdo7r8) | Accomplished-Bed115 | +3 | request / unknown | PLATFORMS, CONTROLS, AUTHORING, PHYSICS, ACTIVITIES | mac, spektrum, aircraft_import, autopilot | Asks about Mac, radio dongle, aircraft import/tuning and mixed manual/ArduPilot control. |
| [phdq59z](comments.md#comment-phdq59z) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdq7y1](comments.md#comment-phdq7y1) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phftb68](comments.md#comment-phftb68) | Accomplished-Bed115 | +1 | followup / unknown | COMMUNICATION | — | Asks OP to answer remaining questions; do not count as another independent requester. |
| [phdobys](comments.md#comment-phdobys) | justadiode | +28 | request / video | AUTHORING, CAMERAS, PHYSICS, CREDIBILITY, COMMUNICATION | aircraft_import, ground_view, fpv, structural_damage | Questions importer, visible controls, camera, despawn and flex; suspects commercialization while encouraging work. |
| [phpjst1](comments.md#comment-phpjst1) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phpjyit](comments.md#comment-phpjyit) | bultodepapas (OP) | +0 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [19reby2v0rjoh](comments.md#comment-19reby2v0rjoh) | Joanzee | +0 | meta / unknown | AI, COMMUNICATION, CREDIBILITY | — | Generated reply reduces confidence. |
| [19refxbw2bsro](comments.md#comment-19refxbw2bsro) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdquq7](comments.md#comment-phdquq7) | Oli4K | +3 | question / unknown | PHYSICS, CREDIBILITY | — | Asks about polars, provenance and validation. |
| [phdrgs8](comments.md#comment-phdrgs8) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phdtr17](comments.md#comment-phdtr17) | Oli4K | +4 | technical / other_product | PHYSICS, COLLABORATION | — | Describes own soaring simulator; not a direct request for OpenRC gliders. |
| [phk7gzu](comments.md#comment-phk7gzu) | Conscious-Clue3738 | +2 | question / other_product | PHYSICS, COLLABORATION | — | Asks another developer about CRRCsim sources. |
| [phl0vdr](comments.md#comment-phl0vdr) | Oli4K | +1 | technical / other_product | PHYSICS, COLLABORATION | — | Explains CRRCsim-derived approach in own work. |
| [phnhw1z](comments.md#comment-phnhw1z) | Conscious-Clue3738 | +1 | support / other_product | COLLABORATION | — | Encourages other soaring developer. |
| [phni8sl](comments.md#comment-phni8sl) | Oli4K | +2 | context / other_product | COLLABORATION | — | Other developer plans to share own project. |
| [phduope](comments.md#comment-phduope) | charlieb | +2 | request / other_product | ACTIVITIES, SCENERY | external_games | Wants RC physics in existing game worlds; not a multiplayer request. |
| [phewuuf](comments.md#comment-phewuuf) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phkih9z](comments.md#comment-phkih9z) | CumCereal08 | +1 | offtopic / unknown | OFF_TOPIC | — | Conversation about commenter identity. |
| [phkxlol](comments.md#comment-phkxlol) | charlieb | +1 | offtopic / unknown | OFF_TOPIC | — | Reply to identity joke. |
| [phe35xw](comments.md#comment-phe35xw) | UpbeatBass6066 | +34 | technical / unknown | AI, CREDIBILITY, PHYSICS, PRACTICE, COMMUNICATION | — | Urges modest validity claims and training utility; self-described engineering experience. |
| [phe6uyv](comments.md#comment-phe6uyv) | UpbeatBass6066 | +8 | support / unknown | SUPPORT | — | Same critic explicitly encourages continuing the project. |
| [phnqyo3](comments.md#comment-phnqyo3) | Houndmux | +3 | technical / unknown | PHYSICS, CREDIBILITY, COMMUNICATION | — | Discusses model limits and criticizes hyper-realism marketing. |
| [phoo93o](comments.md#comment-phoo93o) | UpbeatBass6066 | +3 | technical / unknown | PHYSICS, CREDIBILITY | — | Same critic expands on modeling uncertainty. |
| [php9jtb](comments.md#comment-php9jtb) | Houndmux | +2 | technical / other_product | PHYSICS, CREDIBILITY | — | Aerobatics enthusiast describes limits across simulators and LLT/VLM research. |
| [phegytf](comments.md#comment-phegytf) | dbldwn02 | +1 | impression / video | COMMUNICATION | — | Windows 95 comparison without specific reproducible issue. |
| [phewweb](comments.md#comment-phewweb) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phei02k](comments.md#comment-phei02k) | Phreedom1 | +1 | experience / website | COMMUNICATION | — | Reports non-clickable download link. |
| [phewxqd](comments.md#comment-phewxqd) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phf0heq](comments.md#comment-phf0heq) | Phreedom1 | +1 | experience / website | COMMUNICATION | — | Same user reports link now works; cause unknown. |
| [phf2if1](comments.md#comment-phf2if1) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phek26y](comments.md#comment-phek26y) | Lagomorph9 | +5 | comparison / unknown | VALUE | — | FMS nostalgia; not necessarily criticism or feature demand. |
| [pher5ay](comments.md#comment-pher5ay) | gwenbeth | +1 | request / unknown | ACTIVITIES, PHYSICS | soaring | Requests combined thermals/wind and high-start; asks inertia derivation. |
| [phewz11](comments.md#comment-phewz11) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phes36u](comments.md#comment-phes36u) | coffeemonkeypants | +16 | offer / other_product | VALUE, COLLABORATION, SUPPORT | — | Refunded RealFlight; intends OpenRC trial and possible contributions. |
| [phex17k](comments.md#comment-phex17k) | bultodepapas (OP) | +3 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phf2r84](comments.md#comment-phf2r84) | coffeemonkeypants | +4 | request / other_product | CONTROLS, VALUE | radio_setup | Requests easy calibration wizard based on competitor friction; later submits OpenRC trial. |
| [phfuqlh](comments.md#comment-phfuqlh) | Ti290 | +6 | comparison / other_product | CONTROLS, VALUE | — | Reports Heli-X and wireless TX16s success; not an OpenRC test. |
| [phfysod](comments.md#comment-phfysod) | coffeemonkeypants | +4 | question / other_product | CONTROLS | — | Asks how wireless operation works in competitor discussion. |
| [phg323z](comments.md#comment-phg323z) | Ti290 | +3 | technical / other_product | CONTROLS | — | Explains ELRS BLE joystick procedure; no OpenRC qualification. |
| [phg3pmf](comments.md#comment-phg3pmf) | coffeemonkeypants | +2 | context / other_product | OFF_TOPIC | — | Returning hobbyist discusses modern radio price/features. |
| [19rd1h8je3bs2](comments.md#comment-19rd1h8je3bs2) | Ti290 | +1 | context / other_product | OFF_TOPIC | — | RC electronics price nostalgia. |
| [19rd1nixkajc3](comments.md#comment-19rd1nixkajc3) | coffeemonkeypants | +1 | context / other_product | OFF_TOPIC | — | Radio crystals and printed-airplane nostalgia. |
| [19rdf70csl4yt](comments.md#comment-19rdf70csl4yt) | Ti290 | +1 | context / other_product | OFF_TOPIC | — | Modern helicopter hardware discussion. |
| [19re7ll5vi0yo](comments.md#comment-19re7ll5vi0yo) | coffeemonkeypants | +1 | context / other_product | OFF_TOPIC | — | Comments on observed helicopter performance outside simulator. |
| [pheu933](comments.md#comment-pheu933) | SamIAm_2020 | +4 | request / unknown | ACTIVITIES | soaring | Explicit sailplane request. |
| [pheuw9z](comments.md#comment-pheuw9z) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phev6pm](comments.md#comment-phev6pm) | Key-Coffee-5376 | +0 | request / unknown | AUTHORING | aircraft_import | Requests importing Flyout projects. |
| [phey7nc](comments.md#comment-phey7nc) | Nico7rujillo | +1 | support / unknown | SUPPORT | — | Intends to try; no completed test claimed. |
| [phfj1uu](comments.md#comment-phfj1uu) | 89inerEcho | +1 | request / unknown | ACTIVITIES | rockets | Requests rockets. |
| [phhbsqv](comments.md#comment-phhbsqv) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phlic90](comments.md#comment-phlic90) | 89inerEcho | +1 | request / unknown | ACTIVITIES | rockets | Same user clarifies steerable rockets; count one requester. |
| [phg2kxv](comments.md#comment-phg2kxv) | Technos_Eng | +1 | request / video | CAMERAS, COMMUNICATION, SUPPORT | ground_view | Requests ground camera from viewing trailer; availability unclear to viewer. |
| [phhc8sv](comments.md#comment-phhc8sv) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phg4jn8](comments.md#comment-phg4jn8) | retrorays | +3 | impression / video | VALUE, COMMUNICATION | — | Questions differentiation versus older paid simulators. |
| [phhc57u](comments.md#comment-phhc57u) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phg538c](comments.md#comment-phg538c) | R-PlaneCrazy | +1 | question / unknown | COMMUNICATION, PLATFORMS | language | Asks why Spanish; potential language discoverability gap. |
| [phhc366](comments.md#comment-phhc366) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phg5uh6](comments.md#comment-phg5uh6) | ReserveLegitimate738 | +1 | impression / video | PHYSICS | — | General low-gravity impression; later clarified as RC car footage. |
| [phhbon1](comments.md#comment-phhbon1) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phi50rw](comments.md#comment-phi50rw) | ReserveLegitimate738 | +1 | impression / video | PHYSICS, SUPPORT | — | Clarifies car footage at 0:30; not an aircraft flight-test report. |
| [phi8fyi](comments.md#comment-phi8fyi) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phiib7m](comments.md#comment-phiib7m) | ReserveLegitimate738 | +1 | support / unknown | SUPPORT | — | Intends future trial; no completed test. |
| [phgcuuq](comments.md#comment-phgcuuq) | tomncd | +3 | request / unknown | SCENERY, AUTHORING | local_fields, panorama | Explicit 360-photo import of familiar airfields. |
| [phhk8lm](comments.md#comment-phhk8lm) | Alexwarrior7 | +2 | request / unknown | SCENERY, AUTHORING | local_fields, panorama | Distinct author endorses parent panorama request. |
| [phhzp7n](comments.md#comment-phhzp7n) | Nickelbag_Neil | +1 | meta / unknown | CREDIBILITY | — | General skepticism about all simulators; not a specific OpenRC bug. |
| [phi06oh](comments.md#comment-phi06oh) | OUG54ps | +2 | request / unknown | CONTROLS | spektrum | Requests Spektrum compatibility without identifying failure or tested build. |
| [phi94kr](comments.md#comment-phi94kr) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phi9buu](comments.md#comment-phi9buu) | OUG54ps | +1 | offer / unknown | CONTROLS, COLLABORATION | — | Offers contact for follow-up; not independent evidence of a radio bug. |
| [phi1hc7](comments.md#comment-phi1hc7) | JakubDotPy | +3 | impression / video | PHYSICS, CREDIBILITY | — | Helicopter hover looks too stable; not a hands-on report. |
| [phi8o6a](comments.md#comment-phi8o6a) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phi8rnr](comments.md#comment-phi8rnr) | bultodepapas (OP) | +2 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phiirnq](comments.md#comment-phiirnq) | East_Dust7967 | +1 | offer / unknown | COLLABORATION, SUPPORT | — | Other sim developer suggests comparing approaches; downloading not completed testing. |
| [phj8c6j](comments.md#comment-phj8c6j) | reallifearcade | +5 | experience / firsthand | PHYSICS | — | Reports helicopter inertia/cyclic coupling and airplane low-speed problems after quick trial. |
| [phk3egb](comments.md#comment-phk3egb) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phjthbc](comments.md#comment-phjthbc) | Fast-File6580 | +1 | support / unknown | SUPPORT | — | General visual praise. |
| [phl3c4y](comments.md#comment-phl3c4y) | coffeemonkeypants | +1 | experience / firsthand | CONTROLS, PRACTICE, PHYSICS, COMMUNICATION, SUPPORT | radio_setup, crash_optional | Left after five minutes; input/start/restart/damage/Timber/landing/copy issues with encouragement. |
| [phm1s3y](comments.md#comment-phm1s3y) | plane__nerd | +1 | request / unknown | PRACTICE | crash_optional | Objects to paying on crash; cannot infer actual money charged. |
| [phmdt4b](comments.md#comment-phmdt4b) | imnotabotareyou | +1 | support / unknown | SUPPORT | — | Brief positive reaction. |
| [phpottm](comments.md#comment-phpottm) | mitch_feaster | +2 | support / unknown | SUPPORT | — | Looks fun; no usage claim. |
| [phqde5f](comments.md#comment-phqde5f) | Travelingexec2000 | +0 | impression / video | CREDIBILITY, PHYSICS, SCENERY, COMMUNICATION | — | Challenges realism claim and helicopter footage; criticizes scenery. |
| [phrfgox](comments.md#comment-phrfgox) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [phqeene](comments.md#comment-phqeene) | Past_Engineer2487 | +2 | support / unknown | SUPPORT | — | Positive text and linked roast image; image content not analyzed. |
| [phrfx6u](comments.md#comment-phrfx6u) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [19rf767gfvkh1](comments.md#comment-19rf767gfvkh1) | Scary_Pop1244 | +0 | impression / video | AI, COMMUNICATION | — | Attributes overlay text style to AI; explicitly says not hating. |
| [19rhm45cp6543](comments.md#comment-19rhm45cp6543) | SnooBooks1032 | +2 | offer / unknown | COLLABORATION, SUPPORT | — | Offers Blender work with portfolio-use condition; not unconditional asset transfer. |
| [19ri6roab95r8](comments.md#comment-19ri6roab95r8) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [19ri6skb8vzaa](comments.md#comment-19ri6skb8vzaa) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [19rjg49nlanvn](comments.md#comment-19rjg49nlanvn) | Carticiak96 | +2 | request / unknown | SCENERY, ACTIVITIES | terrain | Requests variable terrain and mountain surfing. |
| [19rjjwlq46h5x](comments.md#comment-19rjjwlq46h5x) | bultodepapas (OP) | +1 | op_context / not_coded | — | — | OP response/context; excluded from community recurrence and score tables. |
| [19rjlwas5d6qs](comments.md#comment-19rjlwas5d6qs) | DryCryptographer1304 | +1 | support / unknown | SUPPORT | — | Portuguese congratulations. |
| [19rjlwu08zdr8](comments.md#comment-19rjlwu08zdr8) | DryCryptographer1304 | +1 | question / unknown | PLATFORMS, COMMUNICATION | mobile | Asks desktop/mobile availability and game name. |
| [19rjoxaui7zaa](comments.md#comment-19rjoxaui7zaa) | PoultryPants_ | +0 | meta / unknown | AI, COMMUNICATION | — | AI dismissal aimed at game and post. |

## Input identities

Hashes identify this collection and coding pass, not the live Reddit page.

- `docs/research/reddit-launch-feedback-2026-10-26/comments.md`: SHA-256 `6d9864da05a89fd1b41fe99d59274e8b79a2c1d9745c93dbe5a98e58eec78b9a`.
- `research/reddit-launch-feedback/annotations.tsv`: SHA-256 `dee9272f25ade36bf8a39543479d560b58993d460b711fc71f7c55f97acf25fa`.
