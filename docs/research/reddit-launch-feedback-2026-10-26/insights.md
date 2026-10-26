# Launch feedback: product insights and future opportunities

Analysis date: 2026-10-26. Corpus: [archived post and 169 comments](comments.md), captured at 15:43:58 UTC. Quantitative evidence: [complete coding, recurrence and scores](coding.md). Implementation comparison: [current capabilities](current-capabilities.md). This is a dated product investigation, not an implementation plan or a change to track priorities.

The strongest opportunity is to make OpenRC a dependable place to practice with a familiar radio, aircraft and flying field. The thread supports improving the first-flight loop and demonstrating handling quality before expanding vehicle breadth. Aircraft import and familiar-field creation are the clearest repeated extensibility requests. VR and multiplayer merit discovery, but their apparent vote strength comes from one bundled wishlist.

## How to interpret the evidence

The analysis considers all 169 records, including 54 OP replies for context. Community statistics use **115 comments from 67 distinct non-OP handles**. Each of those comments was manually classified by topic, explicit request, type and stated exposure; all records have a row in the [coding ledger](coding.md#complete-coding-ledger). Technical exchanges about another simulator, trailer impressions and actual OpenRC trials remain distinct.

Recurrence means distinct handles, not repeated replies. A person can appear in several themes, and handles are not verified independent people. Topic discussion does not establish agreement, demand or a defect. Scores are the archived **net score**, not upvotes, unique voters, purchases or willingness to contribute. Comment age, visibility, nesting and vote fuzzing are uncontrolled; scores cannot be normalized into a reliable market ranking. No theme score is used as a product-priority formula.

Six comments by four handles explicitly describe using/testing OpenRC. Three of those handles report concrete problems; one reports an initial keyboard trial and interest in teaching a child. This is a conservative textual classification, not the total number of users who tried the simulator. Most reports lack a build identifier, complete setup and reproduction tape. The archive contains 169 records while Reddit advertised 170; the missing record and unexamined linked media limit completeness.

Manual labels are interpretation, not an objective sentiment measurement. A separate qualitative reading checked the main conclusions, but this is not a formal inter-rater reliability study. The reproducible counts depend on the retained annotation choices; [analyze.py](../../../research/reddit-launch-feedback/analyze.py) checks source coverage and regenerates [coding.md](coding.md).

## What recurs

| Topic discussed | Distinct handles / 67 | Comments | Interpretation |
| --- | ---: | ---: | --- |
| AI use/development | 21 | 30 | Large conversation volume; contains defense, criticism and neutral questions. Not a feature backlog. |
| Public wording/presentation/discoverability | 19 | 22 | People struggle to understand or trust what is being shown and claimed. Includes language and download-link questions. |
| Handling, physical methods and validation questions | 17 | 27 | Strong interest in flight behavior, but mixes actual trials, footage and discussions of other projects. |
| Credibility, evidence and realism claims | 13 | 17 | Includes validity, endorsement, openness and transparency concerns; not 13 independent bug reports. |
| Contribution offers and technical exchanges | 11 | 19 | Useful recruitment leads; not 11 committed contributors. |
| Free/open-source value and differentiation | 10 | 13 | A meaningful reason to try the project; not proof of better flight behavior. |
| Aircraft/field authoring | 7 | 8 | A repeated desire to bring personal equipment and locations into the simulator. |
| Scenery/local fields/terrain | 7 | 8 | Both appearance and familiarity matter; those are different engineering problems. |
| Radios/calibration/mapping | 6 | 10 | Includes competitor discussion. Direct setup requests and an actual trial provide the strongest product evidence. |

There is also explicit encouragement or positive interest from **22 handles across 26 comments**. These overlap with criticism; they are not a positive-sentiment percentage. Preserve the praise alongside the problems: the thread is not a uniform rejection of the project.

The narrower explicit-request ledger is more useful for feature selection:

| Request family | Distinct requesters | Archived source scores | Reading |
| --- | ---: | --- | --- |
| Custom aircraft import/integration | 4 | +16, +3, +28, 0 | Broadly repeated; includes a Flyout-specific request. |
| Familiar-field/lake creation or import | 4 | +16, +5, +3, +2 | Shared outcome with several proposed methods. |
| Specifically 360° photo import | 2 | +3, +2 | Subset of familiar-field demand; do not add it as two extra people. |
| Easier radio setup / move-to-bind | 2 | +1, +4, +1 | Three comments, two authors; combines direct experience and a competitor-inspired proposal. |
| Spektrum compatibility | 2 | +3, +2 | Compatibility questions, not two verified failures. |
| Ground-pilot view | 2 | +28, +1 | Current source already has it; investigate demonstration/discoverability. |
| FPV/first-person | 2 | +5, +28 | Separate from drone physics and from VR. |
| Sailplanes / thermals and high-start | 2 | +1, +4 | Repeated niche with adjacent technical expertise. |
| Optional/unobtrusive crash-cost workflow | 2 | +1, +1 | Low visibility, direct relevance to uninterrupted practice. |
| Visible structural flex/damaged flight | 2 | +1, +28 | Distinguish animation, damage consequences and validated structural physics. |
| VR / multiplayer | 1 each | Same +16 comment | One author's multi-feature bundle; not 16 independent requests for each. |

Every membership and the remaining single-author asks are linked in [explicit feature signals](coding.md#explicit-feature-and-compatibility-signals). Broader families are deliberately labeled as such: asking about desktop/mobile availability is weaker than committing to use a mobile port.

## What the votes actually highlight

| Comment | Net score | Constructive interpretation |
| --- | ---: | --- |
| [UpbeatBass6066](comments.md#comment-phe35xw) | +34 | The most-visible response asks for modest modeling claims and useful training. It does not dismiss AI-assisted development. |
| [fvpv](comments.md#comment-phcxh0v) | +31 | AI criticism is bundled with a concrete question about what brand/OpenAI support means. Specify the relationship accurately. |
| [justadiode](comments.md#comment-phdobys) | +28 | Extensibility, visible controls, camera choice and damage demonstration are bundled with openness concerns. A polished explanation and importer workflow address different parts of this comment. |
| [TheTerribleInvestor](comments.md#comment-phdimcy) | +21 | AI can still produce something valuable for a neglected niche. |
| [FederalProfessor7836](comments.md#comment-phd5v2k) | +20 | Defense of the author against AI backlash; no requested feature. |
| [brainzhurtin](comments.md#comment-phdnffp) | +16 | Rich wishlist: scenery, VR, multiplayer, aircraft/map creation and MCP. Cannot allocate the score among those items. |
| [coffeemonkeypants, before trying](comments.md#comment-phes36u) | +16 | Willingness to try an alternative after refunding RealFlight. |
| [FederalProfessor7836 on differentiation](comments.md#comment-phd7a19) | +13 | Free and open source are already a recognizable reason to care. |
| [coffeemonkeypants, after trying](comments.md#comment-phl3c4y) | +1 | Specific first-session abandonment, radio, restart, crash and Timber problems. Lower score does not make this low priority. |

The [−6 validation question](comments.md#comment-phdhrsz) still raises a legitimate evidence requirement. Conversely, a high score on an encouraging or anti-AI comment does not establish physical accuracy or a feature mandate. Use votes to identify messages that resonated, specificity to design investigations, and reproduced impact to prioritize fixes.

## Twelve constructive insights

### 1. Convert initial interest into a successful first flight

One user's trajectory is unusually informative. [coffeemonkeypants first offers interest and possible PRs](comments.md#comment-phes36u), [asks for easy radio calibration](comments.md#comment-phf2r84), then [reports quitting after about five minutes](comments.md#comment-phl3c4y). The last message describes several interacting barriers, not one missing feature. It still ends with encouragement.

**Opportunity:** a coherent “ready to fly” flow: identify the radio, confirm four primary controls visually, bind flaps/gear as physical controls, explain any launch lockout at the point of action, and guarantee an obvious reset. Existing calibration and AUX capture should be improved and qualified rather than duplicated. A three-detent physical switch may arrive as an axis; the interface should not make the pilot diagnose that representation.

**Evidence to seek:** a build-identified TX16s MkIII session recording raw channels, mapping and the reported rudder failure; a clean-profile test in which a pilot reaches flight and restarts after a crash without help. Measure time to first controlled flight, setup failures and restart success. Set targets after a baseline. Do not remove throttle-start safeguards solely because one frustrated user requests it; explain the state and test an appropriate practice workflow.

### 2. Make repeated practice a first-class experience

[The crash report interrupts practice](comments.md#comment-phl3c4y), and [another person interprets the crash cost as paying](comments.md#comment-phm1s3y). The problem spans interruption, restart reliability and meaning. Current incident costs are estimates, not a wallet debit. The code has a report-off launch option but the source review found no ordinary settings control; the failure-notification toggle controls a different feature.

**Opportunity:** an optional practice presentation preset: immediate reliable restart, unobtrusive or hidden cost cards, and detailed reports available on demand. Label prices as estimated repair costs, with no actual charge. This does not require disabling the underlying contact/damage physics or creating a new economy. Check crash → restart → control → crash repeatedly, including notification cleanup and focus restoration.

### 3. Publish a useful validity envelope instead of a global realism adjective

The [highest-scoring critique](comments.md#comment-phe35xw), [questions about polars](comments.md#comment-phdquq7), and [discussion of extreme aerobatics](comments.md#comment-phnqyo3) ask what the model can demonstrate. The OP's [own clarification](comments.md#comment-phdkggq) already distinguishes a goal from established accuracy.

**Opportunity:** concise per-aircraft evidence cards: what was measured, which maneuvers are supported by comparison, which inputs were estimated, known departures, experimental modes and relevant build. Link existing research rather than inventing a new certification scale. Avoid “realistic: 95%” without a meaningful measurement.

**Evidence to seek:** independent measurements with uncertainty, not merely passing unit tests or tuned traces. A reproducible limitation can build more confidence than a broad superlative. This is also a communication improvement with much lower scope than replacing the aerodynamic method.

### 4. Focus physics investigations on distinct failure cases

The actionable cases are specific: [Timber pitch/trim and landing thresholds](comments.md#comment-phl3c4y), [post-stall reversal and transition](comments.md#comment-phe2ol3), [remaining propwash/side-force behavior](comments.md#comment-phenubh), and [helicopter cyclic coupling/inertia plus low-speed airplane maneuvers](comments.md#comment-phj8c6j). Trailer-based [RC-car gravity impressions](comments.md#comment-phi50rw) belong to a different vehicle and evidence class.

**Opportunity:** a small pilot test pack with repeatable setup, maneuver and reporting instructions. Preserve a baseline flight, exact replay and one candidate as required by [flight logging](../../FLIGHT-LOGGING.md). Compare normal trainer behavior, stall entry/recovery, trim and survivable landing contact separately. For helicopters, record stabilization mode explicitly before interpreting hover behavior.

Do not promise universal “half-throttle level flight” or tune gravity to a trailer impression. Those are user expectations to investigate against aircraft configuration, not validated physical targets. Preserve the positive [Ugly Stik and EdgeTX experience](comments.md#comment-phe2ol3) as a regression scenario while repairing other cases.

### 5. “My radio, my plane, my field” is a coherent future direction

Four authors ask for aircraft import/integration, while four ask for familiar fields; radio questions recur too. This combination suggests personal relevance as a product direction. It does not prove that every requester wants the entire package.

**Opportunity:** make existing variant sharing easy to discover, then define one validated custom-aircraft package workflow. Current Workshop bundles modify registered aircraft; they cannot import an arbitrary new airframe. Treat geometry, aerodynamic data, controls, units, provenance and version compatibility as separate acceptance concerns under [the aircraft contract](../../AIRCRAFT_CONTRACT.md). A mesh import alone cannot deliver a trustworthy airplane.

Start with one contributor-produced package that installs in a clean checkout and fails clearly when invalid. The thread supports extensibility more strongly than a commitment to author a new aircraft every week. Flyout compatibility is one explicit format request; determine interchange feasibility before promising it.

### 6. Familiar scenery may deliver more value than uniformly expensive scenery

[A lake](comments.md#comment-phds52r), [360° field photos](comments.md#comment-phgcuuq), [an independent endorsement](comments.md#comment-phhk8lm), [local-field generation](comments.md#comment-phdnffp) and [mountain surfing](comments.md#comment-19rjg49nlanvn) share a desire for meaningful places. They do not all require the same world technology.

**Opportunity:** investigate a narrow panoramic-field workflow for stationary pilot practice, separately from navigable 3D terrain for mountain flying/FPV. Panorama projection requires scale, pilot position and ground/collision decisions; a photograph is not terrain or obstacle geometry. Do not imply it can support every camera mode. For 3D fields, extend the existing field/landscape contracts and reuse suitable free content and tools instead of building another general terrain editor.

Compare one representative field at **1080p first**, with legible aircraft and measured frame times. Higher resolutions follow; 720p cannot qualify the product target. Do not require an LLM subscription for ordinary field import: MCP generation is one person's preferred method, not the shared requirement.

### 7. Demonstration and discoverability can resolve some apparent feature gaps

Two authors ask for ground-pilot view, yet [current source already defaults to pilot view](current-capabilities.md). The trailer also prompts questions about surfaces, wreckage and gear flex. Runtime behavior, footage and claims must be checked separately.

**Opportunity:** a short uncut demonstration of the actual training flow: radio input, pilot view, control-surface response, takeoff, landing, accident and restart. Name the build and stabilization mode. Show how to find the existing view; do not add another camera implementation to solve an explanation problem. Onboard FPV remains a distinct missing view in the inspected source.

The [Spanish-language question](comments.md#comment-phg538c), [mobile/name question](comments.md#comment-19rjlwu08zdr8), and [download-link exchange](comments.md#comment-phei02k) are small but direct onboarding clues. They justify clear language/platform/download labels, not a conclusion that ports or translation are absent.

### 8. AI debate is heterogeneous; answer the concrete trust concern

AI discussion involves 21 handles and 30 comments. [An AI opponent praises honesty](comments.md#comment-phgrbxf); [an AI user criticizes presentation/physics](comments.md#comment-phdyzfq); [generated replies reduce confidence for another person](comments.md#comment-19reby2v0rjoh). Treating all skepticism as hostility to AI would miss useful product signals.

**Opportunity:** short, specific, personally accountable replies and plain public copy. Explain whether brand support means permission, hardware, funding or another relationship, consistent with the [OP clarification](comments.md#comment-phczogf). Distinguish implementation, demonstration and validation. The proposal is not to hide AI usage or litigate general software-industry claims.

The website is changing concurrently, so the archived wording critique is historical; this analysis does not claim that exact text remains live. No messages or website changes were made for this investigation.

### 9. Give contributors small completed outcomes

[PotentiallyHeavy offers time](comments.md#comment-phdlwn4), then reports flying, candidate fixes and a [submitted PR with a possible performance cost](comments.md#comment-phg0fnf). [SnooBooks1032 offers Blender modeling with portfolio permission](comments.md#comment-19rhm45cp6543). Other developers exchange aerodynamic methods. These are different contribution paths.

**Opportunity:** concise contribution briefs with one aircraft/maneuver or asset boundary, a reproducible baseline, acceptance evidence, required source files and attribution/permission terms. Keep tester, artist and physics-contributor entry points distinct. Confirm the reported PR and its evidence before describing the fix as merged or validated. A voluntary offer is not an assigned deliverable.

The conversion target should be an accepted, reproducible contribution, not more promotional attention. Reuse the existing [subagent/contribution boundaries](../../SUBAGENTS.md) and asset contracts where applicable rather than opening an unbounded community platform project.

### 10. Real-flight interchange is a small-demand, high-learning opportunity

[FlightCoach/FlightScore interchange](comments.md#comment-phdpfpr) comes from one F3A pilot (+2); [another participant names system identification and ArduPilot logging](comments.md#comment-phkf8p7). This is not broad demonstrated demand, but it aligns unusually well with the project's need for independent validation.

**Opportunity:** a bounded interchange feasibility study using one freely available sample with permission and a defined export/import contract. Existing ORFL/CSV tooling supplies the simulator side. Check units, coordinate frames, time synchronization, sampling, telemetry quality and input availability. A GPS path alone does not identify all aerodynamic parameters, and matched trajectories are not proof of a unique physical model. FlightCoach/FlightScore formats and external capabilities still need primary-source research before implementation.

A useful first deliverable is an honest overlay/report of a real and simulated maneuver, with uncertainty and missing inputs, not a promise of automatic airframe calibration or live integration.

### 11. Keep low-frequency expansion ideas visible without letting them dominate

VR and multiplayer each have one explicit requester in the same +16 comment. Mobile is a platform question from one person; rockets come from one person in two messages. Soaring has two explicit requesters plus adjacent technical discussions. FPV view and drone physics are separate asks.

**Opportunity:** retain a discovery queue with the use case, requester and current capability boundary. Investigate soaring as a coherent optional track—aircraft, launch, lift field and handling evidence—not as “add a glider mesh.” Treat VR, networking, mobile and new vehicle types as separate cost/validation decisions. This thread alone cannot justify their implementation order or justify migrating to another engine.

Use demand from repeat users and a small feasibility result before widening the roadmap. The [current-capability map](current-capabilities.md) prevents confusing a thermal preset, mobile graphics profile or autopilot component label with an accepted product feature.

### 12. Make feedback produce an answer the tester can verify

Some OP replies explain limitations well; others mainly say to download the simulator or note that the video is a trailer. [One asker explicitly follows up on unanswered questions](comments.md#comment-phftb68). A trailer observation may be incomplete while still revealing a presentation problem.

**Opportunity:** use a short issue-response pattern: acknowledge the specific observation; say what is known; request only missing build/device/aircraft/mode information; provide the next check or disposition. For a fixed issue, publish the build and reproduction outcome. For a feature request, distinguish existing functionality, planned work and an uncommitted idea.

Keep both negative and positive follow-up outcomes. This would help turn the contributor and returning-user trajectories into a repeatable feedback loop. It is a recommendation, not evidence that a particular reply caused someone to leave.

## Recommended sequence and acceptance evidence

This is a proposed order based on blocker severity, specificity, recurrence and fit with the shared simulation kernel. Effort labels are relative judgments, not engineering estimates or deadlines. Existing owning tracks retain implementation authority.

| Sequence | Small reviewable outcome | Owning tracks | Effort / uncertainty | Evidence required before declaring success |
| --- | --- | --- | --- | --- |
| First | Reproduce TX16s input and crash/restart flow on an identified build; repair confirmed failures | Input/controller, UI, crash | Medium; hardware/build uncertainty | Saved mapping, observed channel sequence, successful first flight and repeated restart; actual target radio qualification |
| First | Expose unobtrusive practice/report preference and clarify estimated costs | UI, crash/economy | Small–medium; product wording and state lifecycle | User can hide/reopen reports; preference persists; crash/restart still works; no accidental conflation with failure notifications |
| First | Replace unsupported global claims with precise descriptions; demonstrate current pilot workflow | Public presentation, aircraft/physics evidence | Small for copy/demo; validation itself is larger | Every claim links to current capability or named evidence; build-identified uncut demonstration at 1080p |
| Next | Investigate Timber trim/landing, stall behavior and helicopter modes as separate cases | Aircraft owners, physics/ground, HELI | Medium–large; independent measurements missing | Baseline exact replay, matched candidate tape, per-case report and independent physical comparison where realism is claimed |
| Next | Make existing variant sharing discoverable; define one new-aircraft contribution/import slice | Workshop, aircraft standardization | Medium–large; contract breadth | Clear variant/new-airframe distinction; valid package loads; invalid data cannot fly; fresh-install contribution walkthrough |
| Next | Compare panoramic field practice with one authored 3D field workflow | Landscape, camera, graphics | Medium–large; mode and collision constraints | Real user import task, explicit supported views, valid ground scale, measured 1080p performance |
| Bounded research | One FlightCoach/FlightScore interchange feasibility report | Flight logging, validation | Medium; format/sample/input uncertainty | Licensed sample, documented transforms, timestamps and uncertainty; no claim of automatic calibration |
| Later discovery | Soaring, FPV, VR, multiplayer, mobile and other vehicles | Their existing owners and kernel contracts | Different large scopes; sparse demand | Separate use case, repeat-user evidence, feasible prototype and each feature's own acceptance gates |

Do not create an arbitrary weighted score that converts +34 on a multi-topic comment into a numerical mandate. The immediate decision is to validate first-session reliability and targeted handling, while developing a credible route toward personal aircraft and fields. Revisit this ordering after build-identified trials and another cohort of users; the current thread is an early, self-selected sample.
