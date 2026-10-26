# Reddit launch discussion — comment transcript

[Reading guide and preliminary findings](README.md). This document preserves the retrieved discussion; quoted claims are participants’ statements, not verified project facts.

## Source and coverage

- Post: [I built a fully open-source RC flight simulator focused on hyper-realistic physics (alpha), please roast it!](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/).
- Requested comment: [19rjlwu08zdr8](#comment-19rjlwu08zdr8); the collection covers the whole post, not only that comment.
- Post author: u/bultodepapas; published 2026-10-17 19:06:31 UTC.
- Retrieved and assembled: 2026-10-26 15:43:58 UTC.
- Source: [Reddit JSON listing](https://www.reddit.com/r/RCPlanes/comments/1x8iee8.json?limit=500&depth=20&sort=old&raw_json=1), retrieved through the web reader; direct shell HTTP requests returned 403.
- Coverage: **169 unique comment records**, **50 top-level comments**, **119 replies**, **68 distinct author handles** (including OP). OP wrote **54** comments; other participants wrote **115**.
- Reddit reports **170** comments. The retrieved tree contains **169** and no `more` placeholders. The one-record discrepancy is unresolved: deletion, moderation or counting behavior are possible explanations, not established facts. This is the complete retrieved tree, not a claim that every comment ever posted is available.
- No retrieved body is `[deleted]` or `[removed]`; all non-root parent IDs resolve within this transcript. The requested comment is present.
- Order: depth-first discussion tree, using Reddit’s `sort=old` listing. Parent links and depth preserve reply structure; timestamps allow chronological analysis.
- Original languages, spelling, profanity, Markdown and linked media are retained in blockquotes. The web reader introduces some line wrapping; this is a text transcription, not a byte-identical raw HTTP archive. JSON escapes were decoded without translation or paraphrasing.
- Scores and edit timestamps are snapshot metadata and may change; scores are not a count of independent testers or validated findings.
- Media remain external links. No images or video files were downloaded into the repository; media contents have not been transcribed or analyzed.
- Recollection: request the linked JSON endpoint, recursively walk `t1` records in `replies.data.children`, resolve any `more` records, deduplicate by `name`, and compare the result with `num_comments`. Preserve parent IDs and explicitly report any discrepancy.

## Original post

Source: [u/bultodepapas on r/RCPlanes](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/).

> **Please roast it.** I genuinely want all the criticism: what feels wrong, what’s missing, what you actually want and need in a sim. That’s how this gets better.
>
> I’m an engineer, and I’ve spent a long time working on pure physics.
> I wanted an RC sim that’s built on real physics first, so I made one.
> It’s **100% open source and will always be free.** Copy it, fork it, break it.
>
> **What it has right now:**
>
> * Hyper-realistic flight physics: real flying, real landings, real feel
> * Wind, turbulence, weather, and time of day
> * Night flying with LEDs
> * Realistic materials and damage: props break, landing gear flexes, ground and grass friction
> * Planes (including jets, the classic Ugly Stick for learning, and the Timber), helicopters (some still in testing), and RC cars
> * A tornado scenario
> * Crash cost calculator (still in testing)
> * Works with an Xbox controller, your EdgeTX radio, sim USB dongles, or basically any joystick
>
> **What’s coming:**
>
> * More physics realism and better per-model flight feel
> * Next plane: the Sonicmodell Skyhunter
> * INAV integration
> * FPV racing drones
> * Boats and water physics
> * Better crash cost calculator
> * New scenarios
>
> **Heads up:** this is a very early alpha.
> Because of how deep the physics goes, there’s still a lot of polishing to do. New versions drop almost daily, so please keep updated to the latest one.
>
> Big thanks to **Sonicmodell, Hitec, and Savox** for their support, and to **OpenAI** (Codex) for backing open-source projects like this. We’re also working toward licensed models from well-known brands.I also saw other sim which is an excellent sim.
> If you’re the dev, you’re more than welcome to join this project and bring your ideas and criticism.
>
> [https://bultodepapas.github.io/OpenRCsimulator/](https://bultodepapas.github.io/OpenRCsimulator/)  
> [https://github.com/bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator)

## Discussion tree

- [u/fvpv · phcxh0v](#comment-phcxh0v)
  - [u/TitaniumKneecap · phcyzwn](#comment-phcyzwn)
  - [u/bultodepapas (OP) · phczogf](#comment-phczogf)
    - [u/GrParrot · phd47gg](#comment-phd47gg)
      - [u/bultodepapas (OP) · phd5o4l](#comment-phd5o4l)
        - [u/GrParrot · phdhrsz](#comment-phdhrsz)
          - [u/bultodepapas (OP) · phdkggq](#comment-phdkggq)
            - [u/MrGriffin77 · phgrbxf](#comment-phgrbxf)
  - [u/TheTerribleInvestor · phdimcy](#comment-phdimcy)
    - [u/bultodepapas (OP) · phdkzga](#comment-phdkzga)
    - [u/fvpv · phdyzfq](#comment-phdyzfq)
- [u/Njvaporent · phd3c28](#comment-phd3c28)
  - [u/bultodepapas (OP) · phd67jg](#comment-phd67jg)
    - [u/bultodepapas (OP) · phd698u](#comment-phd698u)
- [u/Brendon7358 · phd4i9t](#comment-phd4i9t)
  - [u/bultodepapas (OP) · phd640f](#comment-phd640f)
    - [u/New-Owl-6105 · phdnkfx](#comment-phdnkfx)
- [u/Professional_Will241 · phd5en6](#comment-phd5en6)
  - [u/bultodepapas (OP) · phd5wzf](#comment-phd5wzf)
    - [u/Professional_Will241 · phd6bbe](#comment-phd6bbe)
      - [u/bultodepapas (OP) · phd84ha](#comment-phd84ha)
      - [u/bbbbinion · phdb7gl](#comment-phdb7gl)
- [u/FederalProfessor7836 · phd5v2k](#comment-phd5v2k)
  - [u/bultodepapas (OP) · phd6omr](#comment-phd6omr)
    - [u/FederalProfessor7836 · phd8ci1](#comment-phd8ci1)
      - [u/bultodepapas (OP) · phd988z](#comment-phd988z)
      - [u/andarre · phd99eu](#comment-phd99eu)
      - [u/anaximander19 · phda1pl](#comment-phda1pl)
        - [u/bultodepapas (OP) · phdcapb](#comment-phdcapb)
        - [u/mastermalpass · phdkfr9](#comment-phdkfr9)
        - [u/coffeemonkeypants · pherbvk](#comment-pherbvk)
          - [u/anaximander19 · phge6wl](#comment-phge6wl)
    - [u/coldnebo · phi7uje](#comment-phi7uje)
  - [u/satori-t · phfxtj3](#comment-phfxtj3)
    - [u/FederalProfessor7836 · phhin1p](#comment-phhin1p)
- [u/pokerfas · phd65w3](#comment-phd65w3)
  - [u/FederalProfessor7836 · phd7a19](#comment-phd7a19)
  - [u/bultodepapas (OP) · phd7uxb](#comment-phd7uxb)
  - [u/New-Owl-6105 · phdmisz](#comment-phdmisz)
- [u/Adam627 · phd75pn](#comment-phd75pn)
  - [u/bultodepapas (OP) · phd7jgs](#comment-phd7jgs)
- [u/Mezyi · phd7isp](#comment-phd7isp)
  - [u/bultodepapas (OP) · phd8ffd](#comment-phd8ffd)
    - [u/PotentiallyHeavy · phddnf3](#comment-phddnf3)
      - [u/coffeemonkeypants · phervbn](#comment-phervbn)
  - [u/bbbbinion · phdbo1a](#comment-phdbo1a)
    - [u/bultodepapas (OP) · phdlfpy](#comment-phdlfpy)
  - [u/Erizial · phdlfxz](#comment-phdlfxz)
- [u/waffle_sheep · phdji1f](#comment-phdji1f)
  - [u/bultodepapas (OP) · phdlto8](#comment-phdlto8)
    - [u/waffle_sheep · phdofoe](#comment-phdofoe)
      - [u/bultodepapas (OP) · phdqc83](#comment-phdqc83)
        - [u/waffle_sheep · phdte0k](#comment-phdte0k)
          - [u/waffle_sheep · phdtx9z](#comment-phdtx9z)
      - [u/bultodepapas (OP) · phdqn95](#comment-phdqn95)
- [u/jhsantacruz63 · phdkhcy](#comment-phdkhcy)
  - [u/bultodepapas (OP) · phdlxc4](#comment-phdlxc4)
- [u/PotentiallyHeavy · phdlwn4](#comment-phdlwn4)
  - [u/bultodepapas (OP) · phdm7b4](#comment-phdm7b4)
    - [u/PotentiallyHeavy · phdpfpr](#comment-phdpfpr)
      - [u/bultodepapas (OP) · phdpv1q](#comment-phdpv1q)
      - [u/LupusTheCanine · phkf8p7](#comment-phkf8p7)
    - [u/PotentiallyHeavy · phe2ol3](#comment-phe2ol3)
      - [u/PotentiallyHeavy · phenubh](#comment-phenubh)
        - [u/bultodepapas (OP) · phewgi5](#comment-phewgi5)
          - [u/PotentiallyHeavy · phg0fnf](#comment-phg0fnf)
- [u/brainzhurtin · phdnffp](#comment-phdnffp)
  - [u/bultodepapas (OP) · phdpau3](#comment-phdpau3)
  - [u/bultodepapas (OP) · phdph6i](#comment-phdph6i)
    - [u/brainzhurtin · phe1v11](#comment-phe1v11)
      - [u/lukask04 · phhrbbr](#comment-phhrbbr)
        - [u/brainzhurtin · phiaijj](#comment-phiaijj)
  - [u/bbbbinion · phds52r](#comment-phds52r)
- [u/mastermalpass · phdo6kf](#comment-phdo6kf)
  - [u/bultodepapas (OP) · phdsisr](#comment-phdsisr)
    - [u/mastermalpass · phgvf83](#comment-phgvf83)
- [u/Accomplished-Bed115 · phdo7r8](#comment-phdo7r8)
  - [u/bultodepapas (OP) · phdq59z](#comment-phdq59z)
  - [u/bultodepapas (OP) · phdq7y1](#comment-phdq7y1)
    - [u/Accomplished-Bed115 · phftb68](#comment-phftb68)
- [u/justadiode · phdobys](#comment-phdobys)
  - [u/bultodepapas (OP) · phpjst1](#comment-phpjst1)
  - [u/bultodepapas (OP) · phpjyit](#comment-phpjyit)
    - [u/Joanzee · 19reby2v0rjoh](#comment-19reby2v0rjoh)
      - [u/bultodepapas (OP) · 19refxbw2bsro](#comment-19refxbw2bsro)
- [u/Oli4K · phdquq7](#comment-phdquq7)
  - [u/bultodepapas (OP) · phdrgs8](#comment-phdrgs8)
    - [u/Oli4K · phdtr17](#comment-phdtr17)
      - [u/Conscious-Clue3738 · phk7gzu](#comment-phk7gzu)
        - [u/Oli4K · phl0vdr](#comment-phl0vdr)
          - [u/Conscious-Clue3738 · phnhw1z](#comment-phnhw1z)
            - [u/Oli4K · phni8sl](#comment-phni8sl)
- [u/charlieb · phduope](#comment-phduope)
  - [u/bultodepapas (OP) · phewuuf](#comment-phewuuf)
  - [u/CumCereal08 · phkih9z](#comment-phkih9z)
    - [u/charlieb · phkxlol](#comment-phkxlol)
- [u/UpbeatBass6066 · phe35xw](#comment-phe35xw)
  - [u/UpbeatBass6066 · phe6uyv](#comment-phe6uyv)
  - [u/Houndmux · phnqyo3](#comment-phnqyo3)
    - [u/UpbeatBass6066 · phoo93o](#comment-phoo93o)
      - [u/Houndmux · php9jtb](#comment-php9jtb)
- [u/dbldwn02 · phegytf](#comment-phegytf)
  - [u/bultodepapas (OP) · phewweb](#comment-phewweb)
- [u/Phreedom1 · phei02k](#comment-phei02k)
  - [u/bultodepapas (OP) · phewxqd](#comment-phewxqd)
    - [u/Phreedom1 · phf0heq](#comment-phf0heq)
      - [u/bultodepapas (OP) · phf2if1](#comment-phf2if1)
- [u/Lagomorph9 · phek26y](#comment-phek26y)
- [u/gwenbeth · pher5ay](#comment-pher5ay)
  - [u/bultodepapas (OP) · phewz11](#comment-phewz11)
- [u/coffeemonkeypants · phes36u](#comment-phes36u)
  - [u/bultodepapas (OP) · phex17k](#comment-phex17k)
    - [u/coffeemonkeypants · phf2r84](#comment-phf2r84)
  - [u/Ti290 · phfuqlh](#comment-phfuqlh)
    - [u/coffeemonkeypants · phfysod](#comment-phfysod)
      - [u/Ti290 · phg323z](#comment-phg323z)
        - [u/coffeemonkeypants · phg3pmf](#comment-phg3pmf)
          - [u/Ti290 · 19rd1h8je3bs2](#comment-19rd1h8je3bs2)
            - [u/coffeemonkeypants · 19rd1nixkajc3](#comment-19rd1nixkajc3)
              - [u/Ti290 · 19rdf70csl4yt](#comment-19rdf70csl4yt)
                - [u/coffeemonkeypants · 19re7ll5vi0yo](#comment-19re7ll5vi0yo)
- [u/SamIAm_2020 · pheu933](#comment-pheu933)
  - [u/bultodepapas (OP) · pheuw9z](#comment-pheuw9z)
- [u/Key-Coffee-5376 · phev6pm](#comment-phev6pm)
- [u/Nico7rujillo · phey7nc](#comment-phey7nc)
- [u/89inerEcho · phfj1uu](#comment-phfj1uu)
  - [u/bultodepapas (OP) · phhbsqv](#comment-phhbsqv)
    - [u/89inerEcho · phlic90](#comment-phlic90)
- [u/Technos_Eng · phg2kxv](#comment-phg2kxv)
  - [u/bultodepapas (OP) · phhc8sv](#comment-phhc8sv)
- [u/retrorays · phg4jn8](#comment-phg4jn8)
  - [u/bultodepapas (OP) · phhc57u](#comment-phhc57u)
- [u/R-PlaneCrazy · phg538c](#comment-phg538c)
  - [u/bultodepapas (OP) · phhc366](#comment-phhc366)
- [u/ReserveLegitimate738 · phg5uh6](#comment-phg5uh6)
  - [u/bultodepapas (OP) · phhbon1](#comment-phhbon1)
    - [u/ReserveLegitimate738 · phi50rw](#comment-phi50rw)
      - [u/bultodepapas (OP) · phi8fyi](#comment-phi8fyi)
        - [u/ReserveLegitimate738 · phiib7m](#comment-phiib7m)
- [u/tomncd · phgcuuq](#comment-phgcuuq)
  - [u/Alexwarrior7 · phhk8lm](#comment-phhk8lm)
- [u/Nickelbag_Neil · phhzp7n](#comment-phhzp7n)
- [u/OUG54ps · phi06oh](#comment-phi06oh)
  - [u/bultodepapas (OP) · phi94kr](#comment-phi94kr)
    - [u/OUG54ps · phi9buu](#comment-phi9buu)
- [u/JakubDotPy · phi1hc7](#comment-phi1hc7)
  - [u/bultodepapas (OP) · phi8o6a](#comment-phi8o6a)
  - [u/bultodepapas (OP) · phi8rnr](#comment-phi8rnr)
- [u/East_Dust7967 · phiirnq](#comment-phiirnq)
- [u/reallifearcade · phj8c6j](#comment-phj8c6j)
  - [u/bultodepapas (OP) · phk3egb](#comment-phk3egb)
- [u/Fast-File6580 · phjthbc](#comment-phjthbc)
- [u/coffeemonkeypants · phl3c4y](#comment-phl3c4y)
- [u/plane__nerd · phm1s3y](#comment-phm1s3y)
- [u/imnotabotareyou · phmdt4b](#comment-phmdt4b)
- [u/mitch_feaster · phpottm](#comment-phpottm)
- [u/Travelingexec2000 · phqde5f](#comment-phqde5f)
  - [u/bultodepapas (OP) · phrfgox](#comment-phrfgox)
- [u/Past_Engineer2487 · phqeene](#comment-phqeene)
  - [u/bultodepapas (OP) · phrfx6u](#comment-phrfx6u)
- [u/Scary_Pop1244 · 19rf767gfvkh1](#comment-19rf767gfvkh1)
- [u/SnooBooks1032 · 19rhm45cp6543](#comment-19rhm45cp6543)
  - [u/bultodepapas (OP) · 19ri6roab95r8](#comment-19ri6roab95r8)
  - [u/bultodepapas (OP) · 19ri6skb8vzaa](#comment-19ri6skb8vzaa)
- [u/Carticiak96 · 19rjg49nlanvn](#comment-19rjg49nlanvn)
  - [u/bultodepapas (OP) · 19rjjwlq46h5x](#comment-19rjjwlq46h5x)
- [u/DryCryptographer1304 · 19rjlwas5d6qs](#comment-19rjlwas5d6qs)
- [u/DryCryptographer1304 · 19rjlwu08zdr8](#comment-19rjlwu08zdr8)
- [u/PoultryPants_ · 19rjoxaui7zaa](#comment-19rjoxaui7zaa)

## Comment transcript

<a id="comment-phcxh0v"></a>

### 001 · u/fvpv · phcxh0v

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phcxh0v/).
- Created: 2026-10-17 19:13:18 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 31.

> AI Slop.
>
>
> How exactly did **Sonicmodell, Hitec, and Savox** back this project? And how did OpenAI support it aside from you paying for a codex subscription? 

<a id="comment-phcyzwn"></a>

### 002 · u/TitaniumKneecap · phcyzwn

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phcyzwn/).
- Created: 2026-10-17 19:20:12 UTC; edited: not marked edited.
- Parent: [t1_phcxh0v](#comment-phcxh0v); depth: 1; score at retrieval: 0.

> XD

<a id="comment-phczogf"></a>

### 003 · u/bultodepapas (OP) · phczogf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phczogf/).
- Created: 2026-10-17 19:23:18 UTC; edited: not marked edited.
- Parent: [t1_phcxh0v](#comment-phcxh0v); depth: 1; score at retrieval: 12.

> Those brands don’t pay me.
> They simply gave me permission to use their names in the simulator. I’m also a maintainer and contributor to other significant open-source projects, and I’m happy to discuss the technical work behind this one.
> If you have specific questions or feedback about the simulator, I’m happy to hear them.

<a id="comment-phd47gg"></a>

### 004 · u/GrParrot · phd47gg

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd47gg/).
- Created: 2026-10-17 19:44:06 UTC; edited: not marked edited.
- Parent: [t1_phczogf](#comment-phczogf); depth: 2; score at retrieval: 7.

> To what extent did you use AI in this project? Personally I don’t much care as long as it doesn’t negatively impact the quality of the end product but I’m curious nonetheless

<a id="comment-phd5o4l"></a>

### 005 · u/bultodepapas (OP) · phd5o4l

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd5o4l/).
- Created: 2026-10-17 19:50:44 UTC; edited: not marked edited.
- Parent: [t1_phd47gg](#comment-phd47gg); depth: 3; score at retrieval: 2.

> Thanks for asking!The 3D models and Godot code are 100% AI-generated and personally direct and oversee all the physics work, staying closely involved in how the aircraft behave and feel.
> Making it feel like flying a real RC aircraft is the main goal of the simulator, so that’s where I focus my attention still in the very early stages, and there’s plenty to refine.
> agree with you that the quality of the end result matters, and specific feedback on how it flies is always welcome.

<a id="comment-phdhrsz"></a>

### 006 · u/GrParrot · phdhrsz

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdhrsz/).
- Created: 2026-10-17 20:47:06 UTC; edited: not marked edited.
- Parent: [t1_phd5o4l](#comment-phd5o4l); depth: 4; score at retrieval: -6.

> How can you claim it's "hyper-realistic" if the code is fully AI written? Did you do any experiments in real life to verify the physics model and claim that title?

<a id="comment-phdkggq"></a>

### 007 · u/bultodepapas (OP) · phdkggq

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdkggq/).
- Created: 2026-10-17 20:59:52 UTC; edited: not marked edited.
- Parent: [t1_phdhrsz](#comment-phdhrsz); depth: 5; score at retrieval: 16.

> the fact that AI wrote the code doesn’t, by itself, tell you whether the physics is accurate.
> The physics model is grounded in established mechanics and published research on aircraft, drones, and propellers code’s job is to implement those mathematical models numerically, and I personally direct and oversee that work. The comparisons I’m referring to are with published studies. Those provide a scientific foundation, but using established equations doesn’t automatically prove that every assumption or implementation detail is correct.
> That still needs verification and comparison with measured behavior.
>
> BUT your question about validation is fair.
> This is an early prototype with known limitations, so I should be clearer that “hyper-realistic” is the goal I’m working toward, rather than a level of accuracy I’ve already demonstrated across the simulator.
>
> THAT IS WHY I NEED YOU TO TEST THE SIM, and get your useful critics!!!

<a id="comment-phgrbxf"></a>

### 008 · u/MrGriffin77 · phgrbxf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phgrbxf/).
- Created: 2026-10-18 09:14:44 UTC; edited: not marked edited.
- Parent: [t1_phdkggq](#comment-phdkggq); depth: 6; score at retrieval: 3.

> I'm strongly against any use of generative AI, but I do really admire your honesty and openness about your use of AI in this project.
> Most others would just lie about it, as they would face backlash otherwise.
>
>
> And you're right, the use of AI does not automatically mean a lower quality product, as long as it's used carefully and with measure.
>
> I think you're doing great! Keep it up!

<a id="comment-phdimcy"></a>

### 009 · u/TheTerribleInvestor · phdimcy

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdimcy/).
- Created: 2026-10-17 20:51:06 UTC; edited: not marked edited.
- Parent: [t1_phcxh0v](#comment-phcxh0v); depth: 1; score at retrieval: 21.

> AI software isnt the worst thing in the world.
> There's not going to be a whole lot of companies who will put in the resources to make a RC plane simulator. If you have someone who is properly passionate about it it can bring something that is valuable for this small community.
>

<a id="comment-phdkzga"></a>

### 010 · u/bultodepapas (OP) · phdkzga

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdkzga/).
- Created: 2026-10-17 21:02:26 UTC; edited: not marked edited.
- Parent: [t1_phdimcy](#comment-phdimcy); depth: 2; score at retrieval: 3.

> thanks 

<a id="comment-phdyzfq"></a>

### 011 · u/fvpv · phdyzfq

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdyzfq/).
- Created: 2026-10-17 22:12:19 UTC; edited: not marked edited.
- Parent: [t1_phdimcy](#comment-phdimcy); depth: 2; score at retrieval: 0.

> I totally agree, I have a Claude code agent running pretty much all hours of the day working on my projects and correspondence with me.
> That doesn’t mean that this game doesn’t look sloppy though, and despite the OPs claims, the physics looked less than realistic.
>

<a id="comment-phd3c28"></a>

### 012 · u/Njvaporent · phd3c28

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd3c28/).
- Created: 2026-10-17 19:40:10 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 5.

> Hi, knee project! Any support for drones or FPV?

<a id="comment-phd67jg"></a>

### 013 · u/bultodepapas (OP) · phd67jg

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd67jg/).
- Created: 2026-10-17 19:53:13 UTC; edited: not marked edited.
- Parent: [t1_phd3c28](#comment-phd3c28); depth: 1; score at retrieval: 3.

> next steps is that directions, with Inav and Betafligh support, its kinda tricky 

<a id="comment-phd698u"></a>

### 014 · u/bultodepapas (OP) · phd698u

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd698u/).
- Created: 2026-10-17 19:53:26 UTC; edited: not marked edited.
- Parent: [t1_phd67jg](#comment-phd67jg); depth: 2; score at retrieval: 3.

> also Fpv nees better sceneries 

<a id="comment-phd4i9t"></a>

### 015 · u/Brendon7358 · phd4i9t

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd4i9t/).
- Created: 2026-10-17 19:45:31 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 9.

> No judgement, but what % of this is vibe coding?

<a id="comment-phd640f"></a>

### 016 · u/bultodepapas (OP) · phd640f

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd640f/).
- Created: 2026-10-17 19:52:46 UTC; edited: not marked edited.
- Parent: [t1_phd4i9t](#comment-phd4i9t); depth: 1; score at retrieval: 9.

> like 99.99999999% I know about physics and aerodynamics and I am over that 

<a id="comment-phdnkfx"></a>

### 017 · u/New-Owl-6105 · phdnkfx

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdnkfx/).
- Created: 2026-10-17 21:15:02 UTC; edited: not marked edited.
- Parent: [t1_phd640f](#comment-phd640f); depth: 2; score at retrieval: 2.

> Who downvoted an honest answer to 0?
>
>

<a id="comment-phd5en6"></a>

### 018 · u/Professional_Will241 · phd5en6

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd5en6/).
- Created: 2026-10-17 19:49:33 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> It’s got that AI vibe coded shine to it.
> Definitely Claude.

<a id="comment-phd5wzf"></a>

### 019 · u/bultodepapas (OP) · phd5wzf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd5wzf/).
- Created: 2026-10-17 19:51:53 UTC; edited: not marked edited.
- Parent: [t1_phd5en6](#comment-phd5en6); depth: 1; score at retrieval: 1.

> Claude is a beast for 3d modeling, codex is very good for math and physics 

<a id="comment-phd6bbe"></a>

### 020 · u/Professional_Will241 · phd6bbe

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd6bbe/).
- Created: 2026-10-17 19:53:42 UTC; edited: not marked edited.
- Parent: [t1_phd5wzf](#comment-phd5wzf); depth: 2; score at retrieval: -2.

> I’m sorry if I was misunderstood, but that was not a compliment.

<a id="comment-phd84ha"></a>

### 021 · u/bultodepapas (OP) · phd84ha

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd84ha/).
- Created: 2026-10-17 20:02:04 UTC; edited: not marked edited.
- Parent: [t1_phd6bbe](#comment-phd6bbe); depth: 3; score at retrieval: 8.

> oh im sorry I am too optimistic 

<a id="comment-phdb7gl"></a>

### 022 · u/bbbbinion · phdb7gl

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdb7gl/).
- Created: 2026-10-17 20:16:28 UTC; edited: not marked edited.
- Parent: [t1_phd6bbe](#comment-phd6bbe); depth: 3; score at retrieval: 6.

> This person made something for free and it honestly looks really awesome.
> And the entire community can improve upon it…
>
> You realize AI is being used for development of basically every single software you use these days right? Speaking of someone who was literally laid off by AI, some people’s knee-jerk reaction to ANYTHING touched by AI is hilarious to me.
> It’s already in everything you use and if you think you’re somehow taking a stand on /r/RCPlanes you’re just adorably delusional

<a id="comment-phd5v2k"></a>

### 023 · u/FederalProfessor7836 · phd5v2k

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd5v2k/).
- Created: 2026-10-17 19:51:38 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 20.

> Cue the armchair quarterbacks who have never written a line of code in their lives griping about “AI slop” and “vibe coding”.
> It’s how they cope with having not produced anything themselves. RIP, OP. 

<a id="comment-phd6omr"></a>

### 024 · u/bultodepapas (OP) · phd6omr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd6omr/).
- Created: 2026-10-17 19:55:25 UTC; edited: not marked edited.
- Parent: [t1_phd5v2k](#comment-phd5v2k); depth: 1; score at retrieval: 14.

> Still alive over here 😄 Appreciate the suppor my focus is on getting the physics right and building something useful for the RC community.
> It’s still early days, and there’s plenty to improve, so constructive feedback is always welcome.
> Happy to keep building and sharing the progress!!!!!!!!!!

<a id="comment-phd8ci1"></a>

### 025 · u/FederalProfessor7836 · phd8ci1

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd8ci1/).
- Created: 2026-10-17 20:03:07 UTC; edited: not marked edited.
- Parent: [t1_phd6omr](#comment-phd6omr); depth: 2; score at retrieval: 6.

> Don’t let them get you down.
> As a professional software engineer of 25 years, I know full well that anyone still employable in 2026 no longer writes code by hand. Kinda sad, but 100% reality.
> So to see these muppets crying about you giving away an open source labor of love, because you used Claude, just shows what bitter little n00bs they are.

<a id="comment-phd988z"></a>

### 026 · u/bultodepapas (OP) · phd988z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd988z/).
- Created: 2026-10-17 20:07:15 UTC; edited: not marked edited.
- Parent: [t1_phd8ci1](#comment-phd8ci1); depth: 3; score at retrieval: 3.

> Thanks, I really appreciate the encouragement, especially from someone with 25 years in the field!  I know but time would tell them the hard lesson, tech is a beast and don't stop or wait for anybody 

<a id="comment-phd99eu"></a>

### 027 · u/andarre · phd99eu

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd99eu/).
- Created: 2026-10-17 20:07:24 UTC; edited: not marked edited.
- Parent: [t1_phd8ci1](#comment-phd8ci1); depth: 3; score at retrieval: 2.

> They’re called Luddites.
> Just go to any RC field and look at their faces when they see a UAV fly past.

<a id="comment-phda1pl"></a>

### 028 · u/anaximander19 · phda1pl

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phda1pl/).
- Created: 2026-10-17 20:11:03 UTC; edited: not marked edited.
- Parent: [t1_phd8ci1](#comment-phd8ci1); depth: 3; score at retrieval: 6.

> Another professional software engineer here - there's a massive spectrum of AI-assisted coding techniques, and to me, "vibe coding" is where you tell the AI what you want but have no understanding of how the software works internally as you go, whereas it is entirely possible to understand the software enough to maintain quality *and* have AI write most of it.
> Perhaps not as high quality as a lovingly polished hand-written codebase, but let's face it, there was plenty of mediocre code out there before AI and a lot of it is in very successful commercial products.
> If there's a human in the loop and they can correctly explain the architecture and control flow that's taking place, then it's probably not total slop, and frankly you're ahead of several human-written applications that I've encountered in production.

<a id="comment-phdcapb"></a>

### 029 · u/bultodepapas (OP) · phdcapb

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdcapb/).
- Created: 2026-10-17 20:21:33 UTC; edited: not marked edited.
- Parent: [t1_phda1pl](#comment-phda1pl); depth: 4; score at retrieval: 4.

> Yeah, I think we’re on the same page.
> AI writing the code doesn’t remove my responsibility for what I’m building. I personally oversee the physics, and there’s still plenty to refine. I appreciate you taking the time to share your perspective. It’s good to have people here who are open to talking through the process and sharing thei experience.
> That’s the kind of community I’d love to see grow around the simulator.

<a id="comment-phdkfr9"></a>

### 030 · u/mastermalpass · phdkfr9

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdkfr9/).
- Created: 2026-10-17 20:59:46 UTC; edited: not marked edited.
- Parent: [t1_phda1pl](#comment-phda1pl); depth: 4; score at retrieval: 1.

> I jumped into Power Automate having never used it before, so CoPilot was pretty much holding my hand throughout most of the work in my earlier projects - especially where JSON expressions come into play.
> After so many months of setting up Power Automate projects, I do it all myself now. Very rarely might I chuck a huge block of JSON at CoPilot to help me find where I’ve misplaced a comma or bracket or something.
>
> Meanwhile in PowerBi, I’ve had little luck reverse-engineering the DAX that CoPilot’s given me… And for that I just say DAX is a terrible coding language.
> 😂

<a id="comment-pherbvk"></a>

### 031 · u/coffeemonkeypants · pherbvk

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/pherbvk/).
- Created: 2026-10-18 00:48:30 UTC; edited: not marked edited.
- Parent: [t1_phda1pl](#comment-phda1pl); depth: 4; score at retrieval: 3.

> I'll add to this.
> Been in tech for 30 years, partially as a developer, but mostly I run teams of technical people including devs. We can use Claude code and the like to do things incredibly fast and also quite well, especially if we're diligent about following a good process, engineering prompts well, and testing things properly. I'm also a stickler for removing the outward hallmarks of vibe coded nonsense, like the language it uses in UIs and things like that.
> Those get a very thorough human touch and the more documentation we write and use as instructions, the better it does. It's also personally allowed me to build two commercial projects in my free time, which I'd never have the bandwidth for in the past. I also like to remind people that it will never be 'worse' than it is right now. I truly hate AI for a lot of things it's used for, but quickly prototyping applications isn't one of them.
>

<a id="comment-phge6wl"></a>

### 032 · u/anaximander19 · phge6wl

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phge6wl/).
- Created: 2026-10-18 07:24:09 UTC; edited: not marked edited.
- Parent: [t1_pherbvk](#comment-pherbvk); depth: 5; score at retrieval: 2.

> I fully agree.
> I've written stuff with AI that never would have happened without, because the AI did it in days when I'd have taken months, and I didn't have months to spare. I tweak and change bits of the code where I disagree with the naming or the class structure or the specifics of an algorithm - and you're right, the tone of its UI wording often has a particular feel of being weirdly insincere that I'll often replace with my own words - but on the whole I don't touch most of its code.
> I'll eyeball it, I'll verify that the tests are legitimately testing something useful, I'll run the app and poke the edge cases, but most of the code is solid. I keep the discussion and prompts connected to the details enough that I can open the code and know where to look for things, so it's easier to spot when it's gone really off the rails because I know what to expect in the code before I look, having just talked about all the details.
> With the exception of minor stylistic preferences, a lot of the code is more or less what I'd have written myself - the AI just does it orders of magnitude faster.

<a id="comment-phi7uje"></a>

### 033 · u/coldnebo · phi7uje

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi7uje/).
- Created: 2026-10-18 14:48:57 UTC; edited: not marked edited.
- Parent: [t1_phd6omr](#comment-phd6omr); depth: 2; score at retrieval: 2.

> no worries, any project you can pull together is a lot of work AI or not.
> most here think writing the code is the hardest part, but install, test, maintenance and go-to-market are all significantly harder than writing code.
>
> I realize you have to sell it, but when I see “hyper-realistic physics”, my mind instantly goes “o rly?” but it wouldn’t be flightsim without long arguments about this. 
>
> I’ll take a look.
>

<a id="comment-phfxtj3"></a>

### 034 · u/satori-t · phfxtj3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phfxtj3/).
- Created: 2026-10-18 05:14:42 UTC; edited: not marked edited.
- Parent: [t1_phd5v2k](#comment-phd5v2k); depth: 1; score at retrieval: 2.

> 100% this.
> Anti-AI crusaders have quickly become bigger zealots than AI evangelists. Anything that has touched the evil tool must be called "slop".
> Has an experienced software engineer gone through every line and operation in the code with a finetooth comb? Doesn't matter, the evil tool was used so we must be enlightened and call it "slop".

<a id="comment-phhin1p"></a>

### 035 · u/FederalProfessor7836 · phhin1p

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhin1p/).
- Created: 2026-10-18 12:39:09 UTC; edited: 2026-10-18 12:43:22 UTC.
- Parent: [t1_phfxtj3](#comment-phfxtj3); depth: 2; score at retrieval: 1.

> And the reality is, nearly every piece of actively maintained software today is being built with AI assistance.
> Including Windows, macOS, and yes even Linux. Chrome. Spotify. Reddit 😂 We’re all already running AI built software and have been for some time. You are literally not employable as a software engineer today if you refuse to use these tools.
> Their little misdirected outrage amuses me.

<a id="comment-phd65w3"></a>

### 036 · u/pokerfas · phd65w3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd65w3/).
- Created: 2026-10-17 19:53:00 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 4.

> This actually looks pretty cool, but what sets it apart from Real Flight?

<a id="comment-phd7a19"></a>

### 037 · u/FederalProfessor7836 · phd7a19

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd7a19/).
- Created: 2026-10-17 19:58:10 UTC; edited: not marked edited.
- Parent: [t1_phd65w3](#comment-phd65w3); depth: 1; score at retrieval: 13.

> Uh, free and open source, for starters.
>

<a id="comment-phd7uxb"></a>

### 038 · u/bultodepapas (OP) · phd7uxb

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd7uxb/).
- Created: 2026-10-17 20:00:50 UTC; edited: not marked edited.
- Parent: [t1_phd65w3](#comment-phd65w3); depth: 1; score at retrieval: 8.

> Thanks! The main idea is to offer something completely free that the whole RC community can help shape n it’ll always stay free.
> Anyone can copy it, modify it, or build on it however they like. Community members and RC brands are all welcome to contribute It’s still in the early stages, and it’ll keep growing with new features and community input.
> For now, there’s also the damage calculator and a tornado (crazy I know) to play with, lol.

<a id="comment-phdmisz"></a>

### 039 · u/New-Owl-6105 · phdmisz

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdmisz/).
- Created: 2026-10-17 21:09:57 UTC; edited: 2026-10-17 23:53:30 UTC.
- Parent: [t1_phd65w3](#comment-phd65w3); depth: 1; score at retrieval: 1.

> Price would be an obvious thing.
> :)
>
> But the key things would be that this is still in "alpha."  That means it is still in early development.  Software in alpha is not complete. It will be missing features, could have compatibility issues, and It ***will*** be buggy and/or have stability issues. In general software in alpha is not ready for general use and is almost never released.
>
> However, in more recent years I've seen alpha software released more frequently. Sometimes it is to drum-up hype or find investors.
> But in open source projects and some indie games, the devs do it to get genuine feedback early in the development. It is often much easier to restructure an application and make significant changes early in development than it is later in development. This is because the stuff written in early development creates the foundation on which later parts of the program are built, Once the foundation is set, changes are harder, if not impossible to make.
> So alpha releases can let users give feedback on features and game mechanics that they like or don't like, as well as make requests for new features..... however they have to understand they are working with an unfinished product and it will have problems.
>
> Another thing is that this appears to be written by 1 person that is rapidly writing it with AI. Now as a software developer, I can tell you that AI written code does not automatically mean it is junk or slop.
> There are very few professional developers that do not use AI for code generation... it is too useful to not use. But a project that has only been around for a short time and only has one developer may continue to be developed and grow.... or the dev could become bored and abandon it.
> It is too early to tell.

<a id="comment-phd75pn"></a>

### 040 · u/Adam627 · phd75pn

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd75pn/).
- Created: 2026-10-17 19:57:36 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> Turbo Lumber Evolution lol love it.
>
> This looks like a really cool project, great work so far.
> I’m a software engineer so maybe I’ll take a stab at learning the Godot engine. Why did you choose it over unity or unreal?

<a id="comment-phd7jgs"></a>

### 041 · u/bultodepapas (OP) · phd7jgs

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd7jgs/).
- Created: 2026-10-17 19:59:24 UTC; edited: not marked edited.
- Parent: [t1_phd75pn](#comment-phd75pn); depth: 1; score at retrieval: 1.

> I am not a software engeener so it was easy to use in vscode lol.
> Men I love this to port to Unreal!!!! that would be a big step!!! help me 😄 )

<a id="comment-phd7isp"></a>

### 042 · u/Mezyi · phd7isp

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd7isp/).
- Created: 2026-10-17 19:59:19 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: -7.

> This is completely AI lol 

<a id="comment-phd8ffd"></a>

### 043 · u/bultodepapas (OP) · phd8ffd

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phd8ffd/).
- Created: 2026-10-17 20:03:30 UTC; edited: not marked edited.
- Parent: [t1_phd7isp](#comment-phd7isp); depth: 1; score at retrieval: 3.

> nooooo is like 99.9999999999999% ai

<a id="comment-phddnf3"></a>

### 044 · u/PotentiallyHeavy · phddnf3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phddnf3/).
- Created: 2026-10-17 20:27:47 UTC; edited: not marked edited.
- Parent: [t1_phd8ffd](#comment-phd8ffd); depth: 2; score at retrieval: 4.

> Anyone that complains that AI is used doesn't realize how many apps were built by smashing together stack overflow answers.
>

<a id="comment-phervbn"></a>

### 045 · u/coffeemonkeypants · phervbn

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phervbn/).
- Created: 2026-10-18 00:51:34 UTC; edited: not marked edited.
- Parent: [t1_phddnf3](#comment-phddnf3); depth: 3; score at retrieval: 2.

> Lol I feel this in my bones

<a id="comment-phdbo1a"></a>

### 046 · u/bbbbinion · phdbo1a

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdbo1a/).
- Created: 2026-10-17 20:18:37 UTC; edited: not marked edited.
- Parent: [t1_phd7isp](#comment-phd7isp); depth: 1; score at retrieval: 7.

> I currently play a shitty free sim on my phone and have to watch ads when I crash…
>
> This looks ten thousand times better…

<a id="comment-phdlfpy"></a>

### 047 · u/bultodepapas (OP) · phdlfpy

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdlfpy/).
- Created: 2026-10-17 21:04:39 UTC; edited: not marked edited.
- Parent: [t1_phdbo1a](#comment-phdbo1a); depth: 2; score at retrieval: 3.

> one of the future steps is mobile, and thanks for the support bro

<a id="comment-phdlfxz"></a>

### 048 · u/Erizial · phdlfxz

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdlfxz/).
- Created: 2026-10-17 21:04:41 UTC; edited: not marked edited.
- Parent: [t1_phd7isp](#comment-phd7isp); depth: 1; score at retrieval: 3.

> And its also free and open source.
> Build it better yourself.

<a id="comment-phdji1f"></a>

### 049 · u/waffle_sheep · phdji1f

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdji1f/).
- Created: 2026-10-17 20:55:15 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> How are the aerodynamic models and the dynamics handled? Are the planes represented by point masses or is it something more complex? Do the rotational equations of motion use Euler angles or quaternions or something else?

<a id="comment-phdlto8"></a>

### 050 · u/bultodepapas (OP) · phdlto8

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdlto8/).
- Created: 2026-10-17 21:06:33 UTC; edited: not marked edited.
- Parent: [t1_phdji1f](#comment-phdji1f); depth: 1; score at retrieval: 3.

> Each plane is a full 6-DOF rigid body with mass, CG and a full inertia tensor.
> Aerodynamics blend an empirical coefficient model near normal flight with local wing-strip and tail loads at larger angles, including stall and rotational airflow effects. Rotation uses body-axis angular rates and quaternion attitude, integrated with double-precision RK4 at 240 Hz.
> Aircraft-specific calibration and validation are still ongoing.

<a id="comment-phdofoe"></a>

### 051 · u/waffle_sheep · phdofoe

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdofoe/).
- Created: 2026-10-17 21:19:21 UTC; edited: not marked edited.
- Parent: [t1_phdlto8](#comment-phdlto8); depth: 2; score at retrieval: 1.

> Nice that’s pretty much exactly how the research grade flight simulation program I use is set up.
> I use AVL to get the aero/stability coefficients so custom planes can be modeled.
>
> Another question, what type of turbulence do you have implemented? I’ve been using turbulence generated from the Dryden and Von Karman spectra.
> I was using the standard 1D versions but have recently implemented a 3D flow field version

<a id="comment-phdqc83"></a>

### 052 · u/bultodepapas (OP) · phdqc83

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdqc83/).
- Created: 2026-10-17 21:28:43 UTC; edited: not marked edited.
- Parent: [t1_phdofoe](#comment-phdofoe); depth: 3; score at retrieval: 1.

> Mine currently uses temporal Ornstein–Uhlenbeck turbulence: three independent NED components with configurable RMS and correlation time, added to steady wind and smooth cosine gusts.
> It’s seeded for repeatable runs and spatially uniform; I haven’t implemented Dryden/Von Kármán spectra or a 3D turbulence field yet.
> How are you generating your 3D field?

<a id="comment-phdte0k"></a>

### 053 · u/waffle_sheep · phdte0k

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdte0k/).
- Created: 2026-10-17 21:43:47 UTC; edited: not marked edited.
- Parent: [t1_phdqc83](#comment-phdqc83); depth: 4; score at retrieval: 1.

> The 3d field is generated using a Fourier series of a lot of wave vectors, where the scale and distribution of the wave vectors are determined from the spectra.
> The main issue I faced setting that up was that the Von Karman spectra are defined as 1D, so they had to be converted to 3D, which I did by assuming an isotropic regime (high altitude, no atmosphere boundary layer) so the velocity power spectra could be converted to a single turbulent kinetic energy spectrum. Without isotropy the 1D to 3D conversion gets quite messy and I didn’t want to deal with that.
> For anisotropic turbulence (low altitude) I’ve been looking at using the Mann turbulence model, but haven’t gotten around to it yet

<a id="comment-phdtx9z"></a>

### 054 · u/waffle_sheep · phdtx9z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdtx9z/).
- Created: 2026-10-17 21:46:28 UTC; edited: not marked edited.
- Parent: [t1_phdte0k](#comment-phdte0k); depth: 5; score at retrieval: 1.

> Also, the flow field is mathematically incompressible, which is enforced by the coefficients in the Fourier series.
>

<a id="comment-phdqn95"></a>

### 055 · u/bultodepapas (OP) · phdqn95

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdqn95/).
- Created: 2026-10-17 21:30:15 UTC; edited: not marked edited.
- Parent: [t1_phdofoe](#comment-phdofoe); depth: 3; score at retrieval: 1.

> men you know a lot of aerdinamics, I love to have you in the team

<a id="comment-phdkhcy"></a>

### 056 · u/jhsantacruz63 · phdkhcy

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdkhcy/).
- Created: 2026-10-17 21:00:00 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 6.

> I downloaded it and will try it with my radio when I get home.
> Played around with keyboard controls a little and seems fun. My son is 4 and I want to start teaching him to fly so we will give this a try. I grew up flying Real Flight and have been flying rc's for 20+ years now so Ill pass on any notes I have.
>

<a id="comment-phdlxc4"></a>

### 057 · u/bultodepapas (OP) · phdlxc4

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdlxc4/).
- Created: 2026-10-17 21:07:03 UTC; edited: not marked edited.
- Parent: [t1_phdkhcy](#comment-phdkhcy); depth: 1; score at retrieval: 3.

> This made my day! Helping you share your love of RC flying with your son is exactly the kind of thing that motivates me to build this.
> I hope you two have a lot of fun with it Thank you for giving it a try.
> I’d love to hear how it feels with your radio, and with over 20 years of flying experience, your feedback would be a huge help as I keep improving it.

<a id="comment-phdlwn4"></a>

### 058 · u/PotentiallyHeavy · phdlwn4

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdlwn4/).
- Created: 2026-10-17 21:06:57 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 5.

> Alright, I'm in.
> I've got a few hours and plenty of tokens to burn.

<a id="comment-phdm7b4"></a>

### 059 · u/bultodepapas (OP) · phdm7b4

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdm7b4/).
- Created: 2026-10-17 21:08:24 UTC; edited: not marked edited.
- Parent: [t1_phdlwn4](#comment-phdlwn4); depth: 1; score at retrieval: 1.

> LETS GOOOOOO!!!!

<a id="comment-phdpfpr"></a>

### 060 · u/PotentiallyHeavy · phdpfpr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdpfpr/).
- Created: 2026-10-17 21:24:15 UTC; edited: not marked edited.
- Parent: [t1_phdm7b4](#comment-phdm7b4); depth: 2; score at retrieval: 2.

> I've had an idea bouncing around in my head for a year.
> I fly F3A precision aerobatics.
> There is a couple of projects called FlightCoach and FlightScore that record real-world performance using GPS and a flight controller for coaching and ultimately off board scoring of aerobatic manouvers.
> I've been looking for an RC sim to be able to bring this recorded data into to improve the accuracy of the flight characteristics , and be able to push a recorded flight path out of and back into FlightScore.

<a id="comment-phdpv1q"></a>

### 061 · u/bultodepapas (OP) · phdpv1q

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdpv1q/).
- Created: 2026-10-17 21:26:22 UTC; edited: not marked edited.
- Parent: [t1_phdpfpr](#comment-phdpfpr); depth: 3; score at retrieval: 1.

> brutal idea!!!! yea sure do it, do a branch, and I will keep and I on that! that sounds so useful for experts 

<a id="comment-phkf8p7"></a>

### 062 · u/LupusTheCanine · phkf8p7

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phkf8p7/).
- Created: 2026-10-18 20:31:01 UTC; edited: not marked edited.
- Parent: [t1_phdpfpr](#comment-phdpfpr); depth: 3; score at retrieval: 1.

> That process is called system identification.
> Ardupilot already supports recording suitable data.

<a id="comment-phe2ol3"></a>

### 063 · u/PotentiallyHeavy · phe2ol3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phe2ol3/).
- Created: 2026-10-17 22:31:52 UTC; edited: not marked edited.
- Parent: [t1_phdm7b4](#comment-phdm7b4); depth: 2; score at retrieval: 1.

> For an Alpha build, this thing is great.
> I've found an issue with the aileron reversal in post stall manouvers.
> I'm working on a fix in a feature branch now because it'll unlock a bunch of other things.
>
> Also found some issues with slightly buggy menu navigation when moving back and forth between the aircraft setup screen. I'll see if I can document what I think is going on.
>
> Nice relaxed trainer flying is a dream with this sim. The ugly stik flies wonderfully, I just spent 20 minutes flying lazy figure 8's watching the sun go down.
>
> EdgeTX integration worked perfect out of the box.
> It would be awesome to be able to map controls by selecting the in game target and then flicking the physical switch. 

<a id="comment-phenubh"></a>

### 064 · u/PotentiallyHeavy · phenubh

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phenubh/).
- Created: 2026-10-18 00:28:40 UTC; edited: not marked edited.
- Parent: [t1_phe2ol3](#comment-phe2ol3); depth: 3; score at retrieval: 1.

> I've got the post stall aileron reversal and the propwash systems worked out and doing testing/tuning on this aspect.
> Spins and snaps feel more realistic and comfortablenow, even if the stall transition is still really aggressive.
>
>
> The mechanics of the propwash and side forces still aren't right but I'll get it there.

<a id="comment-phewgi5"></a>

### 065 · u/bultodepapas (OP) · phewgi5

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phewgi5/).
- Created: 2026-10-18 01:18:15 UTC; edited: not marked edited.
- Parent: [t1_phenubh](#comment-phenubh); depth: 4; score at retrieval: 1.

> make the pull request!!! and thanks

<a id="comment-phg0fnf"></a>

### 066 · u/PotentiallyHeavy · phg0fnf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg0fnf/).
- Created: 2026-10-18 05:34:43 UTC; edited: not marked edited.
- Parent: [t1_phewgi5](#comment-phewgi5); depth: 5; score at retrieval: 2.

> PR submitted.
> Frame rate dropped quite a bit in my testing but that could be the tooling and debug I was also running at the time. 

<a id="comment-phdnffp"></a>

### 067 · u/brainzhurtin · phdnffp

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdnffp/).
- Created: 2026-10-17 21:14:21 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 16.

> Looks good.
>
> Where I'd spend time next:
>
> The grass, trees, sky, and water all look terrible.
>  The models themselves look great.  You should be able to go hyper realistic.  allow people to download packs
>
> Multi-player.  it'd be great to go multi player.
>
> VR compatible.  this is a must have for me, as it's the most realistic.
>
> Plane importer.  allow people to make their own planes and have a way to share them with others.
>
> map editor.  allow people to edit and share their own maps.
>
> Plane and map MCP.
>  "Hey claude, look up my local field I fly at on google maps and generate it in openRCsimulator"

<a id="comment-phdpau3"></a>

### 068 · u/bultodepapas (OP) · phdpau3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdpau3/).
- Created: 2026-10-17 21:23:35 UTC; edited: not marked edited.
- Parent: [t1_phdnffp](#comment-phdnffp); depth: 1; score at retrieval: 5.

> Thank you! This is exactly the kind of detailed feedback I need really appreciate you taking  time to check it out and put together these suggestions.
> I’ll add them to the roadmap and use feedback like this to help prioritize what comes next.
> It’s great to have the community helping shape the simulator!

<a id="comment-phdph6i"></a>

### 069 · u/bultodepapas (OP) · phdph6i

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdph6i/).
- Created: 2026-10-17 21:24:27 UTC; edited: not marked edited.
- Parent: [t1_phdnffp](#comment-phdnffp); depth: 1; score at retrieval: 2.

> and yeah claude can do that!!! but with a lot of credits, and a good skill, if you want and have credit I will add the skill for this.

<a id="comment-phe1v11"></a>

### 070 · u/brainzhurtin · phe1v11

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phe1v11/).
- Created: 2026-10-17 22:27:29 UTC; edited: not marked edited.
- Parent: [t1_phdph6i](#comment-phdph6i); depth: 2; score at retrieval: 5.

> I'm on a claude max plan.
>  I also run local LLMs which could also do it.  Yeah, I say add it

<a id="comment-phhrbbr"></a>

### 071 · u/lukask04 · phhrbbr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhrbbr/).
- Created: 2026-10-18 13:27:35 UTC; edited: not marked edited.
- Parent: [t1_phe1v11](#comment-phe1v11); depth: 3; score at retrieval: 1.

> Is it hard to do and implement? Can i for example create a local LLM that turns on the light when i say something like "it feels too dark in here"

<a id="comment-phiaijj"></a>

### 072 · u/brainzhurtin · phiaijj

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phiaijj/).
- Created: 2026-10-18 15:01:11 UTC; edited: 2026-10-18 15:06:17 UTC.
- Parent: [t1_phhrbbr](#comment-phhrbbr); depth: 4; score at retrieval: 2.

> Is it hard?  No.
>  Can you do that?  yes.  Although for that particular use case, there's probably better solutions, like Alexa or Google Home.
>
> If you are interested in running a local LLM, join /r/localLLM/ and start reading.  Local LLMs are free (minus computer price and electricity)
>
> To save you some time, Here's a primer for you.
>
> You'll need a decently powerful computer, usually with a large amount of memory.  You can get by, with degrading results with less memory.  The type of memory mostly matters.
>  You'd want video memory or unified memory.  The more memory and cores for the LLM to run, the faster it is, and also the "smarter" it is.
>
> Video memory is what you typically find in a video card.  Here you can get by with 8gb, be OK with 16GB, or do great with 96GBs or more.  You also want at least 32GBs of computer memory.  For example: I have a gaming desktop with an RTX 5080 16GB GPU, an 64GBs of ram.  Running this https://github.com/niko1221/strata it is VERY fast and accurate.
>
> Unified memory.
>  This is the type of memory you often find in modern Apple computers, nvidia dgx and rtx spark, etc.  Unified means it's both computer memory and graphics memory (hence unified). 
>
> Once you have your computer, now you need to choose which software (LLM) to run.  And that's more about how you are going to use it.  
>
> If you just want a chat bot that can talk to you, currently I'd suggest a variant of Qwen.
>  If you want a chat bot that can also write software, fix your network, install software, check for virus', etc, etc, etc, I'd still suggest Qwen, but you'd want an AI agent harness.  I use claude code cli for this.
>
> If you want to have something that you can create images, videos, music, etc, I'd suggest ComfyUI https://comfy.org/
>
> If you need help setting any of this up, the subreddits are all super helpful.
>  Or, simply go use the free frontier chats like ChatGPT, Google Gemini, Grok, etc, and ask them to walk you through what's best given your setup.
>
> If you don't want to run an LLM locally, there are very affordable options for the type of use I'd suspect you are looking to do.  Usually around $20/month would get you plenty of credits to do what you are looking to do.
>
> Me, I'm a tinkerer.  So I use this stuff all day, every day.
>  For example, in rc planes, I wanted to update my ELRS receivers, which I have around 25 planes.  I asked AI to write me a tool that I can just plug my planes in to my PC, and it'll read what version of ELRS is currently on the receiver, and push the current version, while also making sure all of the features in my receiver are all synced up.  It took AI about 10 minutes for it to create the software, and then it was just a matter of me plugging in each plane to my computer.  It made things so much nicer.
>  Another task I had AI do is, I took photos for my sons little league.  I asked AI to clean up the pictures an make them look like training cards.  20 minutes later everything looked professional.

<a id="comment-phds52r"></a>

### 073 · u/bbbbinion · phds52r

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phds52r/).
- Created: 2026-10-17 21:37:37 UTC; edited: not marked edited.
- Parent: [t1_phdnffp](#comment-phdnffp); depth: 1; score at retrieval: 5.

> That last part would be killer.
> I want to import my lake…then I don’t have to hop in the canoe when a crash…

<a id="comment-phdo6kf"></a>

### 074 · u/mastermalpass · phdo6kf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdo6kf/).
- Created: 2026-10-17 21:18:04 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Claude can do 3D models? Interesting… I still wouldn’t trust it to make them to my standards but then again, I don’t even trust Storebought planes.
> 😅
>
> What I’d like to see in a physics-focussed flight sim is realistic material and flow simulation. Have a look at Rise Of Flight and how planes in that game flex, bend, break and as long as they have enough wing in enough places, they still fly.
>
> I’m not asking for real-time voxel physics, but even RealFlight seems to do a rough impression of wind.
> Models bob up and down in a uniform fashion like they’re a box-kite and the shape of the airframe seems to make little difference. It’s simply “bigger plane = less bobbing”.
>
> Whereas in real life, I’ve had an FT MiniScout bobbing like crazy in the gusts due to its big undercambered airfoil, while my equivalent sized parkjet doesn’t bob at all, because its wings are ‘flat-plate’.
> The smaller and lighter Eachine minis vary too - the P-51 is very sensitive to changes in airspeed resulting in changes to lift (though this comes through as pitch, rather than this VTOL bobbing that RealFlight of the FT MiniScout shows), while it’s mostly stable on the roll axis.
> Conversely, the spitfire’s slimmer wing makes it more stable on the pitch axis, but a cross-gust is more likely to roll it over.
>
> That’s what I don’t see much of in RealFlight - different airframes displaying different characteristics when exposed to the same winds and banked at the same speed and angle.
> Nothing ever randomly snap-rolls in RealFlight, but I’ve seen it all the time in the real world.

<a id="comment-phdsisr"></a>

### 075 · u/bultodepapas (OP) · phdsisr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdsisr/).
- Created: 2026-10-17 21:39:30 UTC; edited: not marked edited.
- Parent: [t1_phdo6kf](#comment-phdo6kf); depth: 1; score at retrieval: 3.

> Yes, the 3D models are AI-generated too! And thanks for going into this much detail—the Mini Scout versus parkjet example is especially useful because it gives me a specific handling difference to investigate.
> That’s the direction I want to take the physics: different airframes responding differently to the same conditions, including their pitch and roll response. The current model includes each aircraft’s mass, center of gravity, and inertia, along with aerodynamic forces and stall behavior. Aircraft-specific calibration and validation are still ongoing.
>
> The structural flex and changes in handling after damage that you describe in Rise of Flight are interesting directions to explore too.
> I’m currently working with a rigid-body aircraft model, so those aspects would need additional work. If you try the simulator, I’d really appreciate feedback like the examples you’ve shared: which aircraft, roughly what conditions, and what response you expected versus what you experienced. That gives me something concrete to investigate and improve.
> Thanks for sharing your flying experience!

<a id="comment-phgvf83"></a>

### 076 · u/mastermalpass · phgvf83

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phgvf83/).
- Created: 2026-10-18 09:49:32 UTC; edited: not marked edited.
- Parent: [t1_phdsisr](#comment-phdsisr); depth: 2; score at retrieval: 1.

> I’ll give it a play.
> Something’s up with my Spektrum dongle, so it’ll be using an Xbox 360 controller, but I’m sure I can get a feel for its unique traits.

<a id="comment-phdo7r8"></a>

### 077 · u/Accomplished-Bed115 · phdo7r8

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdo7r8/).
- Created: 2026-10-17 21:18:14 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> Few questions 
> Will it run over Mac?
> Can I use my Spektrum dongle to fly it with my Tx?
> Can I load my own plane?
> How does it tune for particular planes’ mass and aerodynamics 
> Can it incorporate Ardupilot + user control simultaneously

<a id="comment-phdq59z"></a>

### 078 · u/bultodepapas (OP) · phdq59z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdq59z/).
- Created: 2026-10-17 21:27:47 UTC; edited: not marked edited.
- Parent: [t1_phdo7r8](#comment-phdo7r8); depth: 1; score at retrieval: 2.

> Thanks for the questions! I’d love for you to try your Spektrum dongle and let me know how it goes—I don’t have one to test myself Importing custom aircraft and adding autopilot integration, including ArduPilot, are on the roadmap.
> Here’s how the physics currently works: each aircraft is modeled as a full 6-DOF rigid body with mass, a center of gravity, and a full inertia tensor. The aerodynamics blend an empirical coefficient model near normal flight with local wing-strip and tail loads at larger angles, including stall and rotational airflow effects.
> Rotation uses body-axis angular rates and quaternion attitude, integrated with double-precision RK4 at 240 Hz.
>
> Aircraft-specific calibration and validation are still ongoing, and refining the physics remains a major focus. There’s still plenty to improve, so I appreciate you taking the time to check it out.
> Please keep the feedback coming as new updates roll out!

<a id="comment-phdq7y1"></a>

### 079 · u/bultodepapas (OP) · phdq7y1

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdq7y1/).
- Created: 2026-10-17 21:28:08 UTC; edited: not marked edited.
- Parent: [t1_phdo7r8](#comment-phdo7r8); depth: 1; score at retrieval: 3.

> and yes!!! full Mac support!!!

<a id="comment-phftb68"></a>

### 080 · u/Accomplished-Bed115 · phftb68

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phftb68/).
- Created: 2026-10-18 04:41:31 UTC; edited: not marked edited.
- Parent: [t1_phdq7y1](#comment-phdq7y1); depth: 2; score at retrieval: 1.

> Thanks, what about rest of the asks?

<a id="comment-phdobys"></a>

### 081 · u/justadiode · phdobys

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdobys/).
- Created: 2026-10-17 21:18:49 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 28.

> How is the "New model every week" commitment compatible with the sim being open source? Wouldn't a well polished custom model integration mechanism be more fitting for a (supposedly) open source sim?  
>   
> How comes the models' control surfaces (e.g.
> the rolling Extra) aren't moving? Wouldn't it make sense to render their movement, since their deflection angle is one of the input parameters into the physics engine?  
>   
> Why does the camera follow the model? Wouldn't it be more sensible for a flight sim to have first person and fixed point POVs?  
>   
> Why does the crash result in a despawn, not showing the praised complex damage model? I couldn't see any gear flexing.
>  
>   
> All in all, it looks kinda like a commercial product that counts on open source developers to get it to the point of being able to generate profit. But hey, if it is indeed an open source project, and as such a labour of love and passion, don't let us dishearten you and continue working on it.
> I'm sure this could then develop to become a great project.

<a id="comment-phpjst1"></a>

### 082 · u/bultodepapas (OP) · phpjst1

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phpjst1/).
- Created: 2026-10-19 15:12:00 UTC; edited: not marked edited.
- Parent: [t1_phdobys](#comment-phdobys); depth: 1; score at retrieval: 1.

> I’d love for you to [download the simulator](https://github.com/bultodepapas/OpenRCsimulator/releases) and give it a try! The video is a trailer, so it only gives a brief look at the experience.
> Spending some time flying in it will give you a better sense of how it handles and how the features work you’ve raised some thoughtful questions and your attention to detail could be really useful in spotting things that need improvement. Id be inerested to hear what feels right, what feels off, and what you’d change after trying it. It’s still early, and that kind of hands-on feedback would be a big help.
> Thanks again for taking the time to share your thoughts!

<a id="comment-phpjyit"></a>

### 083 · u/bultodepapas (OP) · phpjyit

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phpjyit/).
- Created: 2026-10-19 15:12:43 UTC; edited: not marked edited.
- Parent: [t1_phdobys](#comment-phdobys); depth: 1; score at retrieval: 0.

> Thanks for taking the time to write such detailed feedback, and for the encouragement! Let me answer the different points properly.
>
>
> **The weekly aircraft:** Adding a new model every week is a personal challenge I’ve set for myself. Over time, I hope people in the community will want to contribute aircraft and help keep that going. A proper custom-aircraft importer is also on the roadmap, and I agree it would make contributing much easier. 
>
> **Control surfaces:** The Extra already has articulated control surfaces in the current implementation.
> Their visible movement should reflect the simulated deflections, so if they appear stationary in that clip, I need to check that particular recording and build. You’re right that clearly showing the control inputs is valuable.
>
> **Camera views:** A fixed ground-pilot view is already available, along with chase, orbit, and close-up views. You can press **1** to select the pilot view, or use **C / Shift+C** to cycle through the views. An onboard FPV/cockpit view is still planned.
> The following camera is simply one of the available options.
>
> **Crashes and damage:** The current implementation supports persistent wreckage and debris, along with a report estimating component damage and repair or replacement costs. If the aircraft simply disappears in the footage, I need to check that specific case to explain what happened.
> The damage system is still experimental, and its estimates shouldn’t be confused with a fully validated simulation of structural failure.
>
> **Landing-gear flex:** Suspension compression is modeled, but the gear struts are still rigid visually. Showing the legs physically bend or deform is an area that needs further work.
>
> As for the project’s direction, the simulator is free and will remain free. People are welcome to copy, modify, and build on it.
> My hope is to grow a community of people who enjoy RC flying and want to help make the simulator better still an early project, and I can do a better job of showing the existing features and explaining their limitations.
> Your feedback helps with both, so thank you!

<a id="comment-19reby2v0rjoh"></a>

### 084 · u/Joanzee · 19reby2v0rjoh

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19reby2v0rjoh/).
- Created: 2026-10-20 18:55:55 UTC; edited: not marked edited.
- Parent: [t1_phpjyit](#comment-phpjyit); depth: 2; score at retrieval: 0.

> Using AI to generate your response is not installing confidence in me.

<a id="comment-19refxbw2bsro"></a>

### 085 · u/bultodepapas (OP) · 19refxbw2bsro

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19refxbw2bsro/).
- Created: 2026-10-20 20:25:08 UTC; edited: not marked edited.
- Parent: [t1_19reby2v0rjoh](#comment-19reby2v0rjoh); depth: 3; score at retrieval: 1.

> ok, I lost your confidence, I can live with that :) (work, family, open source ai project, open source maintainer, and 160 comments it is not easy my friend )

<a id="comment-phdquq7"></a>

### 086 · u/Oli4K · phdquq7

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdquq7/).
- Created: 2026-10-17 21:31:16 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> Can you eleborate on the flight dynamics model that you use? Does it use airfoil polars for lift and stall calculations? Have you used an existing model or created it from scratch? Any validation done on the FDM?

<a id="comment-phdrgs8"></a>

### 087 · u/bultodepapas (OP) · phdrgs8

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdrgs8/).
- Created: 2026-10-17 21:34:18 UTC; edited: not marked edited.
- Parent: [t1_phdquq7](#comment-phdquq7); depth: 1; score at retrieval: 3.

> It’s a custom implementation of standard 6-DOF rigid-body equations, using quaternions and RK4 at 240 Hz.
> Aerodynamics combine empirical stability/control coefficients with local wing-strip and tail forces. Lift and stall generally use analytical curves blending into flat-plate behavior; there’s also support for tabulated finite-wing polars, but these aren’t measured 2D airfoil polars.
>
> Verification includes known-answer tests, timestep convergence, regression flights and comparisons with published Ultra Stick flight modes.
> Those comparisons show discrepancies, and validation against measurements from the actual modeled aircraft is still pending. It’s an experimental FDM, with some borrowed or estimated coefficients.
> IF YOU HAVE ANY SUGGESTION I WILL LOVE TO HEAR IT.
>
>

<a id="comment-phdtr17"></a>

### 088 · u/Oli4K · phdtr17

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phdtr17/).
- Created: 2026-10-17 21:45:36 UTC; edited: not marked edited.
- Parent: [t1_phdrgs8](#comment-phdrgs8); depth: 2; score at retrieval: 4.

> No, just curiosity.
> I’ve been working on an RC soaring sim for the last 10 months and interested to hear how others tackle these issues. Started out with probably the same quaternion based logic, very similar to what CRRCsim used, and added a terrain based ridge lift generator and pretty standard turbulence models for realism. I’m using a wing slice stall model based on airfoil polars, or generic calculation if none are given for a model.
> It seems we’re working on very similar things.
>
> https://reddit.com/link/phdtr17/video/dkusomael3wh1/player

<a id="comment-phk7gzu"></a>

### 089 · u/Conscious-Clue3738 · phk7gzu

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phk7gzu/).
- Created: 2026-10-18 19:57:33 UTC; edited: not marked edited.
- Parent: [t1_phdtr17](#comment-phdtr17); depth: 3; score at retrieval: 2.

> Very cool, I've been thinking of making a soaring sim for a while also.
> But having a hard time finding the time to get started.  
> Where did you get info from on what CRRC sim used? is it documented somewhere or open source? 

<a id="comment-phl0vdr"></a>

### 090 · u/Oli4K · phl0vdr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phl0vdr/).
- Created: 2026-10-18 22:13:34 UTC; edited: not marked edited.
- Parent: [t1_phk7gzu](#comment-phk7gzu); depth: 4; score at retrieval: 1.

> It’s open source, and I analyzed the FDM before trying to port it and deciding to roll my own but based on the same aerodynamic mechanics and several quite standard models.
> It’s not cutting edge but good enough for a convincing soaring sim, I think.

<a id="comment-phnhw1z"></a>

### 091 · u/Conscious-Clue3738 · phnhw1z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phnhw1z/).
- Created: 2026-10-19 07:32:04 UTC; edited: not marked edited.
- Parent: [t1_phl0vdr](#comment-phl0vdr); depth: 5; score at retrieval: 1.

> Thanks much, thats good to know, I'll go checkout the code sometime.
>  
> Good luck with your project. Hope to see it live somewhere sometime.

<a id="comment-phni8sl"></a>

### 092 · u/Oli4K · phni8sl

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phni8sl/).
- Created: 2026-10-19 07:35:06 UTC; edited: not marked edited.
- Parent: [t1_phnhw1z](#comment-phnhw1z); depth: 6; score at retrieval: 2.

> Thank.
> I’ll post it here for sure when it progress allows!

<a id="comment-phduope"></a>

### 093 · u/charlieb · phduope

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phduope/).
- Created: 2026-10-17 21:50:20 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 2.

> I've recently seen mods for Minecraft and cyberpunks 2077 that allow you to fly drones through the games' environments.
> I wonder if you physics model could be ported over to those projects. I really want to fly a nano goblin through night city.
>

<a id="comment-phewuuf"></a>

### 094 · u/bultodepapas (OP) · phewuuf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phewuuf/).
- Created: 2026-10-18 01:20:29 UTC; edited: not marked edited.
- Parent: [t1_phduope](#comment-phduope); depth: 1; score at retrieval: 1.

> it would be easy but not open source probably 

<a id="comment-phkih9z"></a>

### 095 · u/CumCereal08 · phkih9z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phkih9z/).
- Created: 2026-10-18 20:45:27 UTC; edited: not marked edited.
- Parent: [t1_phduope](#comment-phduope); depth: 1; score at retrieval: 1.

> Oh my god first comment guy is still alive
>

<a id="comment-phkxlol"></a>

### 096 · u/charlieb · phkxlol

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phkxlol/).
- Created: 2026-10-18 21:57:08 UTC; edited: not marked edited.
- Parent: [t1_phkih9z](#comment-phkih9z); depth: 2; score at retrieval: 1.

> Did you hear differently? I'd like to think someone would let me know if I'd died.

<a id="comment-phe35xw"></a>

### 097 · u/UpbeatBass6066 · phe35xw

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phe35xw/).
- Created: 2026-10-17 22:34:30 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 34.

> I'm not surprised you are getting a nice simulator with "AI coding tools".
> I've been professionally coding systems for over 55 years now, and very skeptical of the outrageous Superintelligence claims by the Grifters, but writing 3D motion simulators based on a known game framework is a perfectly achievable task today. (Almost boilerplate). Agentic generative LLMs trained with existing code work great for such tasks.
>
> In fact games and simulators are so standardized that the "agents" are just simple coding of simple algorithmic pasterns and testing them.
>
> However, making the simulator physics model the real world of aerodynamics is not so simple. If you use research-standard models there will be effects you can't model - outside the range of validity of fluid dynamic approximations.
> Quadcopters, for example, are very unstable, as is wind-turbulence and shear.
> And then there is interaction between flying airframes.
> 55 years ago I modeled with computers of the day the motions and stresses on large sips in severe sea states, and also analyzed the same hull designs pulled in waves in the MIT Ship Model Towing Tank, comparing them with each other numerically. These were actual early supertanker designs.
>
> The math of the models were the best known at the time, including water-air interface models needed to generate "random sea states" under storm conditions.
>
> I mention this because you claim hyper-realistic physics. Well maybe for one craft in calm air... I would call what you mention actually "very approximate physics".
>
>
> And when you want to model a range of craft designs, well, the farther away from ideal, the more surprises, even if you do the modeling with a hyperfine grid size in CFD.
>
> So be a bit modest. You don't need hyper anything to be a good training system, and you don't need to impress folks who don't know what they are talking about. Learning is the hard issue you are tackling.
> Do that well.

<a id="comment-phe6uyv"></a>

### 098 · u/UpbeatBass6066 · phe6uyv

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phe6uyv/).
- Created: 2026-10-17 22:54:28 UTC; edited: not marked edited.
- Parent: [t1_phe35xw](#comment-phe35xw); depth: 1; score at retrieval: 8.

> I should add that I urge you to go for it.
> There's no "best simulator" in this space...

<a id="comment-phnqyo3"></a>

### 099 · u/Houndmux · phnqyo3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phnqyo3/).
- Created: 2026-10-19 08:50:09 UTC; edited: not marked edited.
- Parent: [t1_phe35xw](#comment-phe35xw); depth: 1; score at retrieval: 3.

> I agree.
> According to the docs, this simulator seems to follow a stability derivative based approach just like most other flight simulators. This is understandable because it is computationally inexpensive and produces acceptable results under normal flight conditions, but comes apart under high rotational rates or once the flow stalls significantly.
> More sophisticated methods like LLT or VLM on the other hand are much harder to implement in real-time on a PC if all relevant interaction effects for extreme maneuvers are to be covered.
> So "hyper realisic" really depends if you talk about sightseeing flights or aerobatics.
> Nowadays, every simulator claims to have "hyper/ultra/betterthanever realistic physics" and most users are satisfied when top speed and climb rates look correct and agility feels about right, so they just rely on the devs ensuring them how revolutionary their product is because it has "newtonian physics" (this ridiculous term was not used in this simulator however) or even "CFD" (nowhere near real-time capable).
> I'm not saying this isn't a good simulator, but it would be nice if these marketing hype terms about ultra realism weren't so overused these days.

<a id="comment-phoo93o"></a>

### 100 · u/UpbeatBass6066 · phoo93o

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phoo93o/).
- Created: 2026-10-19 12:43:48 UTC; edited: not marked edited.
- Parent: [t1_phnqyo3](#comment-phnqyo3); depth: 2; score at retrieval: 3.

> I like this hobby because IRL I'm an engineer/scientist who has worked on real-time control of very complex systems for decades, and I'm fascinated also by human-machine interaction and assisting human abilities to command them.
> FPV quadcopters (esp.
> tiny whoops) doing aerobatics are really not well modeled, though actually even 737 jets aren't either.
> So when I hear claims like precision physics or "video latency is crucial", it really bugs me.
> Especially when the writer claims they are an expert. Experts, real ones, generally know they don't know much at all about these kinds of things.
> (Do you know how a practiced human brain and eye can control a baseball bat to hit a home run? Or why this year's World Cup football design change utterly changed the flight of the ball?)
>

<a id="comment-php9jtb"></a>

### 101 · u/Houndmux · php9jtb

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/php9jtb/).
- Created: 2026-10-19 14:27:10 UTC; edited: not marked edited.
- Parent: [t1_phoo93o](#comment-phoo93o); depth: 3; score at retrieval: 2.

> Physicist who sold his soul to industry, hobby aerobatics pilot, and long-time amateur programmer here.
> I've been occasionally working on a flight sim aerodynamics code for years as a spare-time project, knowing full well that it's a never-ending story.
>
> Aerodynamics research on LLT/VLM methods has received quite a boost over the past few decades, mostly thanks to wind-turbine research, much of which is applicable to flight simulation as well.
> And whenever a new paper comes out, you think that finally something complete has become available, only to realize that they've merely cut off another head of the Hydra. Evil scientists certainly know how to keep themselves busy...
>
> I still haven't found an aerobatics simulator (non-RC) that models extreme maneuvers such as tumbles or spins even remotely correctly.
> So it bugs me when yet another sim claims to be hyper-realistic and people just buy into it, only to complain that the landing-light switch on some BigBusThing is half an inch too far to the left.
>
> But that's just me. Flight sim aerobatics are as much a niche within simulators as aerobatics are in real life.
> Still, one can keep dreaming...

<a id="comment-phegytf"></a>

### 102 · u/dbldwn02 · phegytf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phegytf/).
- Created: 2026-10-17 23:49:48 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Here's my roast.  I remember playing this exact same game on my windows 95 PC.  

<a id="comment-phewweb"></a>

### 103 · u/bultodepapas (OP) · phewweb

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phewweb/).
- Created: 2026-10-18 01:20:44 UTC; edited: not marked edited.
- Parent: [t1_phegytf](#comment-phegytf); depth: 1; score at retrieval: 2.

> trust in the process 

<a id="comment-phei02k"></a>

### 104 · u/Phreedom1 · phei02k

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phei02k/).
- Created: 2026-10-17 23:55:38 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> A clickable link would be nice, can't even copy and paste it.

<a id="comment-phewxqd"></a>

### 105 · u/bultodepapas (OP) · phewxqd

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phewxqd/).
- Created: 2026-10-18 01:20:57 UTC; edited: not marked edited.
- Parent: [t1_phei02k](#comment-phei02k); depth: 1; score at retrieval: 1.

> at the end my friend 

<a id="comment-phf0heq"></a>

### 106 · u/Phreedom1 · phf0heq

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phf0heq/).
- Created: 2026-10-18 01:41:36 UTC; edited: not marked edited.
- Parent: [t1_phewxqd](#comment-phewxqd); depth: 2; score at retrieval: 1.

> OK that is weird.
> When I first viewed this, the link was not clickable. Then when I saw your message I came back and it's now clickable for me. So if it wasn't edited I wonder why that would be. But anyway thanks for your comment because otherwise I probably wouldn't have remembered to come back and see.
>

<a id="comment-phf2if1"></a>

### 107 · u/bultodepapas (OP) · phf2if1

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phf2if1/).
- Created: 2026-10-18 01:53:29 UTC; edited: not marked edited.
- Parent: [t1_phf0heq](#comment-phf0heq); depth: 3; score at retrieval: 2.

> probably reddit bug for been vibe coded lol
>
>

<a id="comment-phek26y"></a>

### 108 · u/Lagomorph9 · phek26y

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phek26y/).
- Created: 2026-10-18 00:07:15 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 5.

> Reminds me a bit of an old program called FMS I used around 20 years ago.

<a id="comment-pher5ay"></a>

### 109 · u/gwenbeth · pher5ay

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/pher5ay/).
- Created: 2026-10-18 00:47:27 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Can we get thermals and wind together? and a high start?
>
> Also how are you determining the axial moments of inertia of the models?
>
>

<a id="comment-phewz11"></a>

### 110 · u/bultodepapas (OP) · phewz11

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phewz11/).
- Created: 2026-10-18 01:21:11 UTC; edited: not marked edited.
- Parent: [t1_pher5ay](#comment-pher5ay); depth: 1; score at retrieval: 1.

> sure in the pipeline for sure.

<a id="comment-phes36u"></a>

### 111 · u/coffeemonkeypants · phes36u

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phes36u/).
- Created: 2026-10-18 00:52:50 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 16.

> Good on you OP.
> I just bought and refunded real flight this week. It's honestly fucking terrible for what it costs. I'll give this a shot and maybe look at making a few PRs if I have time

<a id="comment-phex17k"></a>

### 112 · u/bultodepapas (OP) · phex17k

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phex17k/).
- Created: 2026-10-18 01:21:31 UTC; edited: not marked edited.
- Parent: [t1_phes36u](#comment-phes36u); depth: 1; score at retrieval: 3.

> all plane flight the same

<a id="comment-phf2r84"></a>

### 113 · u/coffeemonkeypants · phf2r84

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phf2r84/).
- Created: 2026-10-18 01:54:56 UTC; edited: not marked edited.
- Parent: [t1_phex17k](#comment-phex17k); depth: 2; score at retrieval: 4.

> It just feels incredibly outdated for the year 2026 and even something that should be straightforward, like setting up my radio was a pain in the butt.
>  Definitely something to think about for this app as well is a clean, easy way to add and calibrate popular radios using a wizard.
> I personally have a TX16s mk3, which is quite a popular radio and this should be very easy to build for.

<a id="comment-phfuqlh"></a>

### 114 · u/Ti290 · phfuqlh

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phfuqlh/).
- Created: 2026-10-18 04:51:45 UTC; edited: not marked edited.
- Parent: [t1_phes36u](#comment-phes36u); depth: 1; score at retrieval: 6.

> Yeah I did the same.
> Realfight was so bad, especially for helicopters. I use Heli-X now and it’s great. Heli focused but even the planes feel better than realflight. I also have a TX16s and it works wirelessly on Heli-X

<a id="comment-phfysod"></a>

### 115 · u/coffeemonkeypants · phfysod

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phfysod/).
- Created: 2026-10-18 05:22:10 UTC; edited: not marked edited.
- Parent: [t1_phfuqlh](#comment-phfuqlh); depth: 2; score at retrieval: 4.

> That's cool.
> How does it work wirelessly?

<a id="comment-phg323z"></a>

### 116 · u/Ti290 · phg323z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg323z/).
- Created: 2026-10-18 05:55:13 UTC; edited: not marked edited.
- Parent: [t1_phfysod](#comment-phfysod); depth: 3; score at retrieval: 3.

> It’s Bluetooth.
> You hit the sys button, click the expressLRS app, then scroll down and click BLE joystick. Then discover device on your computer’s Bluetooth. Has to be very close to your computer to initiate the connection and then still works from the other side of the room.
>

<a id="comment-phg3pmf"></a>

### 117 · u/coffeemonkeypants · phg3pmf

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg3pmf/).
- Created: 2026-10-18 06:00:29 UTC; edited: not marked edited.
- Parent: [t1_phg323z](#comment-phg323z); depth: 4; score at retrieval: 2.

> Oh dang.
> I don't think I ever realized this thing has bt. I got out of the hobby about 25 years ago (I was in college and had neither time nor money), and got back into it this year. I got this radio for just shy of $200. I am blown away at what I can do. This would have cost like 800 bucks back then.
>

<a id="comment-19rd1h8je3bs2"></a>

### 118 · u/Ti290 · 19rd1h8je3bs2

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rd1h8je3bs2/).
- Created: 2026-10-20 01:34:06 UTC; edited: not marked edited.
- Parent: [t1_phg3pmf](#comment-phg3pmf); depth: 5; score at retrieval: 1.

> Same, I hadn’t flown since 2002 until about 7 months ago and I’m blown away by how cheap the electronics are for what you get.
> I remember just a tail gyro was $300-500.
> Now a complete helicopter flight controller with 3 gyros, WiFi, telemetry, and a receiver is $100

<a id="comment-19rd1nixkajc3"></a>

### 119 · u/coffeemonkeypants · 19rd1nixkajc3

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rd1nixkajc3/).
- Created: 2026-10-20 01:38:01 UTC; edited: not marked edited.
- Parent: [t1_19rd1h8je3bs2](#comment-19rd1h8je3bs2); depth: 6; score at retrieval: 1.

> It's bonkers nuts, right? I mean I don't even remember there being gyros.
> Hell, our radios had crystals to change so you didn't interfere with other radios. Of course I also 3d printed a plane for something like 15 bucks worth of filament

<a id="comment-19rdf70csl4yt"></a>

### 120 · u/Ti290 · 19rdf70csl4yt

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rdf70csl4yt/).
- Created: 2026-10-20 06:41:37 UTC; edited: not marked edited.
- Parent: [t1_19rd1nixkajc3](#comment-19rd1nixkajc3); depth: 7; score at retrieval: 1.

> Oh yeah I remember using the frequency board and putting my AMA card in the slot for my channel! The planes have made some advancements, especially for beginners, but the helicopters now compared to back then are light years ahead.
> The power the electric ones have still blows my mind.

<a id="comment-19re7ll5vi0yo"></a>

### 121 · u/coffeemonkeypants · 19re7ll5vi0yo

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19re7ll5vi0yo/).
- Created: 2026-10-20 17:18:27 UTC; edited: not marked edited.
- Parent: [t1_19rdf70csl4yt](#comment-19rdf70csl4yt); depth: 8; score at retrieval: 1.

> Yeah, there's some people who fly them in an area by our flying field and they're like flying chainsaws.
>  Not my cup of coffee, but it's insane what they can do.

<a id="comment-pheu933"></a>

### 122 · u/SamIAm_2020 · pheu933

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/pheu933/).
- Created: 2026-10-18 01:05:21 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 4.

> No sailplanes?

<a id="comment-pheuw9z"></a>

### 123 · u/bultodepapas (OP) · pheuw9z

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/pheuw9z/).
- Created: 2026-10-18 01:09:08 UTC; edited: not marked edited.
- Parent: [t1_pheu933](#comment-pheu933); depth: 1; score at retrieval: 2.

> on the pipeline for sure!!!!

<a id="comment-phev6pm"></a>

### 124 · u/Key-Coffee-5376 · phev6pm

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phev6pm/).
- Created: 2026-10-18 01:10:51 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 0.

> Would be cool to be able to upload projects from flyout

<a id="comment-phey7nc"></a>

### 125 · u/Nico7rujillo · phey7nc

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phey7nc/).
- Created: 2026-10-18 01:28:22 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Ill def check this

<a id="comment-phfj1uu"></a>

### 126 · u/89inerEcho · phfj1uu

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phfj1uu/).
- Created: 2026-10-18 03:32:21 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Rockets please

<a id="comment-phhbsqv"></a>

### 127 · u/bultodepapas (OP) · phhbsqv

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhbsqv/).
- Created: 2026-10-18 11:56:09 UTC; edited: not marked edited.
- Parent: [t1_phfj1uu](#comment-phfj1uu); depth: 1; score at retrieval: 1.

> Rockets for the planes or rockets on the planes 

<a id="comment-phlic90"></a>

### 128 · u/89inerEcho · phlic90

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phlic90/).
- Created: 2026-10-18 23:45:21 UTC; edited: not marked edited.
- Parent: [t1_phhbsqv](#comment-phhbsqv); depth: 2; score at retrieval: 1.

> Both? Just want to simulate steerable rockets

<a id="comment-phg2kxv"></a>

### 129 · u/Technos_Eng · phg2kxv

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg2kxv/).
- Created: 2026-10-18 05:51:27 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> A camera from the ground would start to make it look realistic.
> All the best for the dev and let me know when you have something to test play.

<a id="comment-phhc8sv"></a>

### 130 · u/bultodepapas (OP) · phhc8sv

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhc8sv/).
- Created: 2026-10-18 11:59:09 UTC; edited: not marked edited.
- Parent: [t1_phg2kxv](#comment-phg2kxv); depth: 1; score at retrieval: 1.

> Lol it’s a trailer, download and download and play 

<a id="comment-phg4jn8"></a>

### 131 · u/retrorays · phg4jn8

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg4jn8/).
- Created: 2026-10-18 06:07:03 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> Roast ==> RC simulators were this good 20 years ago.
> Sure they cost $$ but i dont see anything new yet

<a id="comment-phhc57u"></a>

### 132 · u/bultodepapas (OP) · phhc57u

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhc57u/).
- Created: 2026-10-18 11:58:30 UTC; edited: not marked edited.
- Parent: [t1_phg4jn8](#comment-phg4jn8); depth: 1; score at retrieval: 1.

> Very useful 

<a id="comment-phg538c"></a>

### 133 · u/R-PlaneCrazy · phg538c

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg538c/).
- Created: 2026-10-18 06:11:14 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Why is it spanish

<a id="comment-phhc366"></a>

### 134 · u/bultodepapas (OP) · phhc366

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhc366/).
- Created: 2026-10-18 11:58:07 UTC; edited: not marked edited.
- Parent: [t1_phg538c](#comment-phg538c); depth: 1; score at retrieval: 2.

> Spanish and English 

<a id="comment-phg5uh6"></a>

### 135 · u/ReserveLegitimate738 · phg5uh6

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phg5uh6/).
- Created: 2026-10-18 06:17:10 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Is everything happening underwater or on the Moon maybe? Real life RC models don't behave like this.

<a id="comment-phhbon1"></a>

### 136 · u/bultodepapas (OP) · phhbon1

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhbon1/).
- Created: 2026-10-18 11:55:23 UTC; edited: not marked edited.
- Parent: [t1_phg5uh6](#comment-phg5uh6); depth: 1; score at retrieval: 2.

> Why? Can you explain your feelings 

<a id="comment-phi50rw"></a>

### 137 · u/ReserveLegitimate738 · phi50rw

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi50rw/).
- Created: 2026-10-18 14:35:48 UTC; edited: not marked edited.
- Parent: [t1_phhbon1](#comment-phhbon1); depth: 2; score at retrieval: 1.

> I absolutely love your initiative! Not negativity towards you or your project!
>
> What I was referring to is mostly how RC cars behave (starting 0:30 in your video).
> Just comparing to my personal experience being at a RC track in real life and youtube videos.
> In your videos it looks as if gravity is a bit lower than that of Earth's.

<a id="comment-phi8fyi"></a>

### 138 · u/bultodepapas (OP) · phi8fyi

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi8fyi/).
- Created: 2026-10-18 14:51:41 UTC; edited: not marked edited.
- Parent: [t1_phi50rw](#comment-phi50rw); depth: 3; score at retrieval: 1.

> its a trailer, at least test it yourself.

<a id="comment-phiib7m"></a>

### 139 · u/ReserveLegitimate738 · phiib7m

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phiib7m/).
- Created: 2026-10-18 15:36:20 UTC; edited: not marked edited.
- Parent: [t1_phi8fyi](#comment-phi8fyi); depth: 4; score at retrieval: 1.

> I would love to, looking forward to it! 

<a id="comment-phgcuuq"></a>

### 140 · u/tomncd · phgcuuq

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phgcuuq/).
- Created: 2026-10-18 07:13:13 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> On top of great physics, I am missing a sim where I can easily import a 360-photo of my favourites airfields to fly where I am used to fly.

<a id="comment-phhk8lm"></a>

### 141 · u/Alexwarrior7 · phhk8lm

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhk8lm/).
- Created: 2026-10-18 12:48:33 UTC; edited: not marked edited.
- Parent: [t1_phgcuuq](#comment-phgcuuq); depth: 1; score at retrieval: 2.

> This is a big one for me

<a id="comment-phhzp7n"></a>

### 142 · u/Nickelbag_Neil · phhzp7n

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phhzp7n/).
- Created: 2026-10-18 14:10:29 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Imo....not a single simulator is even close to the real thing! Not a one!

<a id="comment-phi06oh"></a>

### 143 · u/OUG54ps · phi06oh

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi06oh/).
- Created: 2026-10-18 14:12:49 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 2.

> can you pls make it work with the spectrum controller 🥺🙏

<a id="comment-phi94kr"></a>

### 144 · u/bultodepapas (OP) · phi94kr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi94kr/).
- Created: 2026-10-18 14:54:53 UTC; edited: not marked edited.
- Parent: [t1_phi06oh](#comment-phi06oh); depth: 1; score at retrieval: 1.

> I think is working, can you confirm that is not working, please, you as a spectrum helper is what I need

<a id="comment-phi9buu"></a>

### 145 · u/OUG54ps · phi9buu

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi9buu/).
- Created: 2026-10-18 14:55:49 UTC; edited: not marked edited.
- Parent: [t1_phi94kr](#comment-phi94kr); depth: 2; score at retrieval: 1.

> ye add me on discord @sp45GUO

<a id="comment-phi1hc7"></a>

### 146 · u/JakubDotPy · phi1hc7

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi1hc7/).
- Created: 2026-10-18 14:19:01 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 3.

> Doesn't look that realistic to me.
> The helicopter hover was too stable.

<a id="comment-phi8o6a"></a>

### 147 · u/bultodepapas (OP) · phi8o6a

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi8o6a/).
- Created: 2026-10-18 14:52:46 UTC; edited: not marked edited.
- Parent: [t1_phi1hc7](#comment-phi1hc7); depth: 1; score at retrieval: 1.

> did you downloaded? did you put wind? did you try the no gyro option? I love to see your feeling after you test it by yourself 

<a id="comment-phi8rnr"></a>

### 148 · u/bultodepapas (OP) · phi8rnr

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phi8rnr/).
- Created: 2026-10-18 14:53:13 UTC; edited: not marked edited.
- Parent: [t1_phi1hc7](#comment-phi1hc7); depth: 1; score at retrieval: 2.

> also the heli is in early development, heli physics are crazy 

<a id="comment-phiirnq"></a>

### 149 · u/East_Dust7967 · phiirnq

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phiirnq/).
- Created: 2026-10-18 15:38:20 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> looks great! dowloading it now.
> you can also try [narenana.com](http://narenana.com) for an RC sim, we can compare our approaches! 
>
>

<a id="comment-phj8c6j"></a>

### 150 · u/reallifearcade · phj8c6j

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phj8c6j/).
- Created: 2026-10-18 17:28:57 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 5.

> What I got in a quick try:
>
> Helicopter:  
>  \-> The trainer method = drone method, so no evaluation possible, feel as artificial as electronics governed drones (it lacks inertia)  
> \-> Cyclic method: you have some force calculations out of place by 90 degrees in a way that pitching up or down at low speed induces roll rotation.
> Something wrong in the physics
>
>   
> Planes:  
> \-> Low speed air dynamics is completely off, taildrops or transition from roll to spin do not work like the real life does, or are impossible to achieve.
>
>
>   
> Nice to see you using godot and it integrates well with AI.

<a id="comment-phk3egb"></a>

### 151 · u/bultodepapas (OP) · phk3egb

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phk3egb/).
- Created: 2026-10-18 19:40:06 UTC; edited: not marked edited.
- Parent: [t1_phj8c6j](#comment-phj8c6j); depth: 1; score at retrieval: 1.

> thanks for your feedback!!!

<a id="comment-phjthbc"></a>

### 152 · u/Fast-File6580 · phjthbc

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phjthbc/).
- Created: 2026-10-18 18:57:29 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Looks fantastic 👍

<a id="comment-phl3c4y"></a>

### 153 · u/coffeemonkeypants · phl3c4y

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phl3c4y/).
- Created: 2026-10-18 22:26:10 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Ok I just played this for about 5 minutes before I got annoyed and quit.
>  Here's a couple of quick thoughts - First, my controller (an RM Tx16s MkIII) doesn't get it's rudder recognized for some reason (ch4). So that's a problem.  I also think the controller setup screen needs an overhaul. It's very confusing.  We read left to right - don't have the axis to the right of the slider, or put them all on their own lines.
>  Setting up things like flaps - I'm configuring a 3 way switch and not an axis or button, but had to choose axis to get the setting to what I needed
>
> On to flying -   
> \- For the love of god, just let the flight start when I hit start flight. If my throttle is not at 0, that's on me.  
>
> \- If the damage report thing isn't ready for production, remove it.  Also make it an option to not have it at all in settings.
> It's a fun idea in theory, but I'm using this to practice and I don't really care if I crash pixels. The crash report notification also remains on the screen annoyingly
>
> \- Further, each time I crash and choose 'restart flight', it doesn't actually restart the flight. I'm stuck until I go to the menu and restart again.
>
> \- I'm flying the turbo timber, as that is what I actually have in real life.
> The flight model seems to porpoise a lot, and requires a lot of downward trim to fly level even at 1/3rd throttle.  For a sim, these planes should more or less fly level at half throttle
>
> \- Seems damn near impossible to land without 'crashing'.  Despite putting the plane down reasonably well, it still 'crashed'.  Work on the physics and tolerances here.  Real RC planes hit the ground and bounce at times.
> They don't have the exact same characteristics of their full scale counterparts
>
> \- Lastly - transparently, your website reeks so monumentally foully of Claude that it makes me want to throw up in my mouth a little bit.  "A project that's moving forward.  Without skipping any questions." What the fuck does this mean? You can cut about 80% of the fluffy shit from this site and just throw the features the sim has on there in plain language.
>
>
> I think this could be a really good piece of software, and I commend you for getting it this far.  Keep it up and I hope you get lots of contributions. 

<a id="comment-phm1s3y"></a>

### 154 · u/plane__nerd · phm1s3y

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phm1s3y/).
- Created: 2026-10-19 01:33:21 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> I think u should not pay when u crash but thats just me

<a id="comment-phmdt4b"></a>

### 155 · u/imnotabotareyou · phmdt4b

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phmdt4b/).
- Created: 2026-10-19 02:41:39 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Based

<a id="comment-phpottm"></a>

### 156 · u/mitch_feaster · phpottm

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phpottm/).
- Created: 2026-10-19 15:33:36 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 2.

> Wait this looks super fun

<a id="comment-phqde5f"></a>

### 157 · u/Travelingexec2000 · phqde5f

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phqde5f/).
- Created: 2026-10-19 17:16:45 UTC; edited: 2026-10-19 17:20:06 UTC.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 0.

> what makes it 'hyper realistic' .
> Easy to claim that, but what exactly are you implementing that is different?
>
> That heli looks anything but realistic. Have you flown a real heli? Unless it is on some major stabilization, you will never see it fly like that
>
> Maybe tone down the hyperbole till you have some evidence that it is materially better than exisiting sims.
> Your scenery is like RF from 4 generations ago

<a id="comment-phrfgox"></a>

### 158 · u/bultodepapas (OP) · phrfgox

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phrfgox/).
- Created: 2026-10-19 19:52:09 UTC; edited: not marked edited.
- Parent: [t1_phqde5f](#comment-phqde5f); depth: 1; score at retrieval: 1.

> Have you had a chance to download the simulator and try it yet? The video is a trailer, intended to give a quick visual introduction to the project.
> I’d encourage you to take a few flights yourself to get a fuller picture of the controls, flight behavior, and available settings.
>
> I’ve covered some of this in other comments, and the implementation and current limitations are documented on [GitHub](https://github.com/bultodepapas/OpenRCsimulator), but I’m happy to explain here too.
>
> The fixed-wing physics use a custom 6-DOF solver running at 240 Hz, with aircraft-specific mass, center of gravity and inertia, aerodynamic loads, stall behavior, and servo dynamics.
> I personally oversee the physics, and calibration and validation are ongoing. Those details describe the approach; how accurately it reproduces real aircraft behavior still needs testing.
>
> The helicopter is explicitly experimental and needs further work. Your observation about its movement is fair feedback to raise from the footage.
> I’d be interested in hearing which responses look wrong to you and what you would expect from a real helicopter in the same situation.
>
> I also agree that a claim like “hyper-realistic” needs evidence behind it. Realism is the goal, and the project still has work to do to demonstrate that.
> There’s room to improve the scenery too; this is still an early project.
>
> If you’re willing to [download it](https://github.com/bultodepapas/OpenRCsimulator/releases), your critical eye could be a real help. Knowing which aircraft you tried, what maneuvers you tested, and what felt off would give me something concrete to investigate and improve.
> I’d welcome that feedback.

<a id="comment-phqeene"></a>

### 159 · u/Past_Engineer2487 · phqeene

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phqeene/).
- Created: 2026-10-19 17:20:50 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 2.

> Nice sim! Also, you asked us to roast it…  
>
>
> https://preview.redd.it/m78f6whzjgwh1.jpeg?width=1672&format=pjpg&auto=webp&s=ec6fcac40aa06ddf331db1781ffc17e8caf557e6

<a id="comment-phrfx6u"></a>

### 160 · u/bultodepapas (OP) · phrfx6u

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/phrfx6u/).
- Created: 2026-10-19 19:54:04 UTC; edited: not marked edited.
- Parent: [t1_phqeene](#comment-phqeene); depth: 1; score at retrieval: 1.

> delicious

<a id="comment-19rf767gfvkh1"></a>

### 161 · u/Scary_Pop1244 · 19rf767gfvkh1

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rf767gfvkh1/).
- Created: 2026-10-21 06:36:00 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 0.

> Vibe coded, and i could tell that just from The text in the corner.
>
> Not hating

<a id="comment-19rhm45cp6543"></a>

### 162 · u/SnooBooks1032 · 19rhm45cp6543

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rhm45cp6543/).
- Created: 2026-10-22 15:05:16 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 2.

> This looks pretty cool and I'm kinda excited to give it a test shot!
>
> Slightly off the topic but I'm curious how detailed your models are/how much detail you aim for, and if you need any help with making some? I currently do blender modelling as a hobby more than anything and so if needed if be happy to help do some work for you for free, so long as I can use the models I make in a portfolio to show "hey look I made this shit for a game and it works".
>
> If this isn't something you're interested no stress, just thought could be worth asking haha 

<a id="comment-19ri6roab95r8"></a>

### 163 · u/bultodepapas (OP) · 19ri6roab95r8

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19ri6roab95r8/).
- Created: 2026-10-22 22:48:20 UTC; edited: not marked edited.
- Parent: [t1_19rhm45cp6543](#comment-19rhm45cp6543); depth: 1; score at retrieval: 1.

> bro you are my hero, i am currently spending 2 pro claude subscriptions only for blender, if you can help me to improve the models, are some details, that would be amazing.
> and OF COURSE I AM SUPER INTERESTING, thanks, DM please

<a id="comment-19ri6skb8vzaa"></a>

### 164 · u/bultodepapas (OP) · 19ri6skb8vzaa

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19ri6skb8vzaa/).
- Created: 2026-10-22 22:48:53 UTC; edited: not marked edited.
- Parent: [t1_19rhm45cp6543](#comment-19rhm45cp6543); depth: 1; score at retrieval: 1.

> i canno start chat with you so please you start the chat.

<a id="comment-19rjg49nlanvn"></a>

### 165 · u/Carticiak96 · 19rjg49nlanvn

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rjg49nlanvn/).
- Created: 2026-10-23 15:45:05 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 2.

> We need something with variable terrain for fixed wing flying.
> Mountain surfing. 

<a id="comment-19rjjwlq46h5x"></a>

### 166 · u/bultodepapas (OP) · 19rjjwlq46h5x

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rjjwlq46h5x/).
- Created: 2026-10-23 17:09:59 UTC; edited: not marked edited.
- Parent: [t1_19rjg49nlanvn](#comment-19rjg49nlanvn); depth: 1; score at retrieval: 1.

> ON THE ROADMAP, but create good scenaries is hard and not my speciality, baby someday an expert will join

<a id="comment-19rjlwas5d6qs"></a>

### 167 · u/DryCryptographer1304 · 19rjlwas5d6qs

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rjlwas5d6qs/).
- Created: 2026-10-23 17:54:38 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Meu Deus que maravilha cara e parabéns

<a id="comment-19rjlwu08zdr8"></a>

### 168 · u/DryCryptographer1304 · 19rjlwu08zdr8

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rjlwu08zdr8/).
- Created: 2026-10-23 17:54:58 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 1.

> Vai se mobile ou computador e qual que é o nome do jogo

<a id="comment-19rjoxaui7zaa"></a>

### 169 · u/PoultryPants_ · 19rjoxaui7zaa

- Source: [original comment](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/i_built_a_fully_opensource_rc_flight_simulator/19rjoxaui7zaa/).
- Created: 2026-10-23 19:02:31 UTC; edited: not marked edited.
- Parent: [Original post](#original-post); depth: 0; score at retrieval: 0.

> vibecoded ahh game and post
