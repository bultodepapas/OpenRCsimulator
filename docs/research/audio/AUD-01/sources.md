# AUD-01 — Sound sources, licensing, and native Godot audio

2026-10-11 · **Status: source and API research complete.** Shipped original sources and gameplay acceptance are documented in [AUD-02](../AUD-02/assets.md) and [AUD-04](../AUD-04/README.md); the third-party candidates below remain unshipped and unauditioned.

This audit records item-level license evidence and viable source candidates for [AUDIO-PLAN](../../../AUDIO-PLAN.md). It does not change the separate G3b engine-audio work. A sound being free to download does not establish its reuse license: preserve each item's own license page and provenance.

## Ambience candidates

| Asset and direct download | Source, content, and license evidence | Assessment |
| --- | --- | --- |
| [park_ambience_wind.wav](https://opengameart.org/sites/default/files/park_ambience_wind.wav) | [OpenGameArt item page](https://opengameart.org/content/park-ambiences), uploader **Thimras**; the item is marked **CC0**. The page describes a 48 kHz, 24-bit recording in an open field with stronger wind, made in a public park in Adelaide. | Best starting bed for field wind. WAV is 74 MB; trim and encode a game-ready derivative after listening. The description does not promise an isolated wind stem or a seamless loop. |
| [park_ambience_birds.wav](https://opengameart.org/sites/default/files/park_ambience_birds.wav) | Same [item page](https://opengameart.org/content/park-ambiences), uploader **Thimras**, marked **CC0**. The page describes a 48 kHz recording close to a copse, with birds chattering before rain. | Good foliage-and-birds source candidate. WAV is 86.2 MB. It is a mixed field recording, so use it as source material or a quiet bed only after listening; it cannot independently follow bird timing and wind strength. |

Both direct download endpoints returned HTTP 200 on 2026-10-11. The item page links the [CC0 1.0 deed](https://creativecommons.org/publicdomain/zero/1.0/). CC0 permits copying, modification, redistribution, and commercial use without attribution; retain **Thimras / “Park ambiences” / OpenGameArt** in project provenance as a courtesy. Neither file has been auditioned here, and no loop seam or in-game mix is accepted yet.

## RC motor recording

[“1 radio control plane taking off.wav” by rcEyeSoar](https://freesound.org/people/rcEyeSoar/sounds/176968/) is a 15.915-second, 2.7 MB, 44.1 kHz, 16-bit stereo recording described as a **120 cc radio-control plane taking off**. Its own Freesound page marks it **Creative Commons 0**. The file's download control requires a Freesound sign-in. The same creator's [“rc plane fly-by.wav”](https://freesound.org/people/rcEyeSoar/sounds/176972/) is another item-level CC0 recording (22.889 seconds, 3.9 MB) described as radio-control gas-engine noise.

These are combustion-engine references, not electric or turbine sources. Their fixed takeoff/fly-by timing and pitch make them poor substitutes for the live aircraft emitter; the plan also rules out unrelated fly-by one-shots. Keep them for acoustic study or derived source work, and have the flown aircraft produce any spatial pass. Record the author and item URL even though CC0 does not require attribution.

## Godot 4.7 and production tools

Godot 4.7 natively imports WAV, Ogg Vorbis, and MP3. Its audio-import guide recommends Ogg Vorbis for long sounds, supports loop and loop-offset settings for Ogg/MP3, and documents the file-size versus playback-CPU tradeoff. The 74–86 MB WAV ambience originals should be edited and reduced before shipping; measure actual voice and decode costs against the plan's 8 MiB source budget.

`AudioStreamPlayer3D` supplies distance attenuation, directionality, Doppler and distance filtering. `AudioStreamRandomizer` is an available weighted-variation option. AUD-03 uses native 3D players, a private deterministic scheduler, explicit two-endpoint Doppler and `AudioEffectHardLimiter`; it retains G3b's generator only in legacy mode. No middleware is required. [Implementation](../AUD-03/README.md).

[Audacity](https://www.audacityteam.org/) is a free, open-source editor for auditioning, trimming, fading/crossfading loop points, and exporting compressed sources. Godot imports the resulting common audio formats directly; no runtime audio library is needed.

| Tool / library | Verified license and distribution requirement | Used here |
| --- | --- | --- |
| [Godot](https://godotengine.org/license/) | MIT; retain engine copyright/license when redistributing the engine, plus its bundled third-party notices | Existing pinned 4.7.2 runtime |
| [NumPy](https://github.com/numpy/numpy/blob/main/LICENSE.txt) | BSD 3-Clause; source/binary redistribution retains copyright, conditions and disclaimer; no endorsement | Offline generator/checker only, pinned 2.4.6; not bundled in the game |
| [Audacity](https://github.com/audacity/audacity/blob/master/LICENSE.txt) | GPLv3 for the application; redistributing the application has GPL obligations | Optional editor, neither installed nor bundled by this work |

The generated WAVs contain original synthesized material, not copied library code or downloaded recordings. They ship with the repository's MIT notice in their own folder; preserve that notice when redistributing these assets. The export filters include the notice and manifest. [Godot's audio import guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_audio_samples.html) and [AudioStreamWAV](https://docs.godotengine.org/en/4.7/classes/class_audiostreamwav.html) distinguish compressed data bytes from sample-frame loop positions; explicit PCM import and export checks now enforce that contract.

## Evidence and provenance

- Primary item pages above show each asset's description, author, and license. The Freesound pages are item-specific: do not infer that every Freesound upload is CC0.
- Direct OpenGameArt WAV links and the Commons Ogg candidate were checked with HTTP `HEAD` on 2026-10-11. This establishes reachable download endpoints, not successful import, perceptual quality, or a clean loop.
- For AUD-02, keep the source URL, title, author, item-level license, retrieval date, source hash, and edit/encode settings beside each derivative. Preserve an attribution file even for CC0 sources.

## References

- Godot 4.7: [Importing audio samples](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_audio_samples.html), [AudioStreamPlayer3D](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer3d.html), [AudioStreamRandomizer](https://docs.godotengine.org/en/4.7/classes/class_audiostreamrandomizer.html), [audio buses](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html), and [AudioStreamGenerator](https://docs.godotengine.org/en/4.7/classes/class_audiostreamgenerator.html).
- Creative Commons: [CC0 1.0 deed](https://creativecommons.org/publicdomain/zero/1.0/) and [legal code](https://creativecommons.org/publicdomain/zero/1.0/legalcode).
- Optional small public-domain fallback: [“20090610 0 ambience.ogg” on Wikimedia Commons](https://commons.wikimedia.org/wiki/File:20090610_0_ambience.ogg), 2:03, 3.31 MB, with a direct [Ogg download](https://upload.wikimedia.org/wikipedia/commons/0/0a/20090610_0_ambience.ogg). The file page records an author dedication to the public domain, wind/trees/birds/crows, and the recorder's note that the capture is noisy; treat it as a listening candidate, not a quality-approved source.
