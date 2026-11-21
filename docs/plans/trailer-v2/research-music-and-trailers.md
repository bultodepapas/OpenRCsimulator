# Trailer 2.0 — music and internet research

**Research checked 2026-11-21. Status: candidates and license documentation only.** No audio has been downloaded, auditioned end-to-end, mixed, synchronized, or uploaded. A composer-page description is not proof that the track will fit the current 150-second master, that its beat falls at a proposed cut, or that it is claim-free.

**R4 use:** this is retained source/candidate research. The [current screenplay](cinematic-script-r4.md) owns timing and sound placement; no track or software is selected by this audit.

## Musical brief
We want a game trailer with a punch in the first five seconds, recognizable actions across the whole fleet, an energetic rhythm for nitro trucks and FPV, a brief early contact accent, a precise quieter mechanism chapter, an airy Corsair orbit/lake payoff, and a memorable successful-play finish. Hybrid orchestral plus synth and percussion suits this, but don't let a nonstop climax drown out turbine, radial, electric motor and nitro engine voices.

The prior Every Input Matters v9.13 used one 90-second interval of Scott Buckley's **Uprising**. Preserve it as a musical reference and audio-level benchmark, not the default music for V2.

## Directly verified primary-source tracks

| Priority to audition | Track and source | Artist's description | Creative hypothesis | Source license |
|---|---|---|---|---|
| 1 | [Simulacra — Scott Buckley](https://www.scottbuckley.com.au/library/simulacra/) | High-energy hybrid orchestral action, arpeggiated synths, electric guitar, rhythmic strings and brass | Best first *candidate* for fleet montage, FPV, trucks and quick transitions; inspect whether it offers a quieter lake section | CC BY 4.0 with credit for commercial work |
| 2 | [Escape Velocity — Scott Buckley](https://www.scottbuckley.com.au/library/escape-velocity/) | High-energy, synth-driven epic orchestral track, emotional vocals | Modern game tone, possible musical lift for the night/scale reveals; vocals could mask engines | CC BY 4.0 with credit |
| 3 | [Pursuit — Scott Buckley](https://www.scottbuckley.com.au/library/pursuit/) | Fast drum-and-bass, brass and lead synth | Possible FPV / car racing rhythm; check whether it feels too continuous for the reflective lake chapter | CC BY 4.0 with credit |
| 4 | [Vanguard — Scott Buckley](https://www.scottbuckley.com.au/library/vanguard/) | Driving hybrid trailer music with slow build, break, melodic middle and thematic end | More traditional cinematic arc; potentially a strong alternate if first three are too hectic | CC BY 4.0 with credit |
| 5 | [Aphelion — Scott Buckley](https://www.scottbuckley.com.au/library/aphelion/) | 2026 epic, contemplative start, emotional energy with synth and orchestra | Alternative for beauty/lake reveal and large finale; may need a strong cold-open sound design | CC BY 4.0 with credit |
| Reference | [Uprising — Scott Buckley](https://www.scottbuckley.com.au/library/uprising/) | Orchestral slow build to heroic backend at 2:07 | Old film baseline; reuse only if new music fails A/B test | CC BY 4.0 with credit |

Scott Buckley's [licensing page](https://www.scottbuckley.com.au/licensing/) explicitly allows commercial projects when the prescribed attribution is given. For video platforms, use each track's exact credit, CC BY 4.0 license link and mention the music was edited. Rights or license status still need preserving for the selected final download; YouTube Content ID claims are possible if credit is missing.

## Additional licensed catalog strategies
- [Pixabay Content License](https://pixabay.com/service/license-summary/): commercial videos are generally allowed when the music is embedded in an original film, not distributed as a standalone song; attribution generally not mandatory. [Pixabay music FAQ](https://pixabay.com/service/faq/) specifically warns that some tracks are in Content ID and may get claims even with permitted use. Preserve original track URL, source file, certificate (if offered), download receipt and music use context.
- [Uppbeat commercial licenses](https://uppbeat.io/commercial-licenses): the current business plan covers certain online promotions/paid ads but not all broadcast, cinema or film uses. Read the [Business/Team license](https://uppbeat.io/uppbeat-business-team-license) for channels, terms and redistribution before purchasing. No Uppbeat song has yet been specifically shortlisted.
- Do not download major-label songs from YouTube/Spotify or assume streaming availability equals synchronization rights. Don't add any external audio to Git during this phase.

## Actual listening test and cue-sheet requirements
For each music file when future production begins: record original duration and audio hash; identify start transient, intro, changes every 4/8 bars, tempo by measurement, half-time/break, impact-friendly silence, strong climax and resolved ending; build two 150 s candidate test edits without forced tempo changes. Compare candidate cuts with and without effects. Score 1–5 after actual listening on opening hook, driving middle, lake breathing room, crisp sonic gap at crash, finale chord, natural 150 s segmentation and rights ease. **Current priority order is conceptual, not the result of an audio audition.**

For the selected music preserve composer, official link, downloadable file SHA-256, exact credit/license, date, final in/out timestamps, transforms, destination platforms, Content ID state and final acknowledgement. Make an audio-only listening session and a phone-speaker listening test; the old v9.13 required rotor -12.4dB correction because the rotor masked score.

## Internet trailer-craft research

**Steamworks [official trailer guidance](https://partner.steamgames.com/doc/store/trailer):** players want gameplay, especially in the first trailer. The early seconds should explain the game and clips must work muted. Steam's first trailer is used for a 6-second microtrailer. For upload, 16:9, 1920x1080, 30/60 fps H.264/AAC is a preferred format. This is guidance even when distributing outside Steam.

**Derek Lieu — [pacing](https://www.derek-lieu.com/blog/2020/11/16/how-to-think-about-pacing-in-a-trailer), [start here](https://www.derek-lieu.com/start-here) and [constructing timeline](https://www.derek-lieu.com/blog/2023/2/19/step-two-of-starting-a-game-trailer-timeline):** vary chunks rather than only cut speed, show what every short label claims, and build tension/release. The earlier OpenRC v8 lesson matches this: 267 words in 58 seconds were not legible.

**Godot [Movie Maker guide](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html):** offline movie writing gives stable fixed simulation steps even when rendering takes longer; it doesn't prove game performance in real time. See also [renderer differences](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) and [environment/SSR limits](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).

## Original OpenRC trailer lessons, directly sourced

See [v9.13 revision log](../../research/cinematic-trailer/revision-9-2026-10-29.md) and [V2 creative treatment](creative-treatment.md). The prior cut documented:
- dark, low-visibility RGB shots and nearly invisible aircraft;
- overused pond views and similar camera axes;
- a featureless storm cloud without a visible vehicle;
- same-plane skin montage improved by one continuous location/clock;
- scale-shot improvement after normal/giant/tiny were shown together with labels;
- tiny helicopter and too-long/too-many text overlays;
- loud rotor and jet audio relative to score;
- source footage on old Godot version requiring recapture.

## Sound design by vehicle
Use **actual in-game** audio where possible: Corsair radial, Mustang 120 cc gasoline prop; Extra .61 glow and baseline Stick .61 glow reference; Stick 6S and Bisonte electric motors; Vantage turbine; helicopter rotor; FPV quad motors; blimp; MONSTER CAR 2 nitro two-stroke, clutch and exhaust; tire slide/gravel; dirt/water impacts, thunder and short warning sound. Preserve unprocessed sound stems, avoid generic full-size V8 effects and do not claim all model sounds are physical measurements.

**Provisional first audition:** Simulacra versus Escape Velocity, with Vanguard as a less frantic control. This is a production recommendation, not evidence that either track was heard.
