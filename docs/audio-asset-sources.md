# Mechanical audio sources — AUD-16

Research and rights check: **2026-10-25**. Implementation: [servo/retract audio](servo-retract-audio-implementation.md). This is the provenance home for the mechanical bank, not the existing engine/environment banks; those remain linked from [AUDIO-PLAN](AUDIO-PLAN.md).

## Selected source material

LaSonothèque's individual pages identify the servo, movement, recordist and recording conditions. They designate the files CC0 and explicitly permit editing, commercial use and redistribution. These are original mono 48 kHz, 24-bit WAV/BWF recordings by **Joseph Sardin**, recorded with a SoundDevices MixPre-3 and Neumann KM184. They are not synthetic servo tones.

| Recording | Original page | Original WAV | SHA-256 |
| --- | --- | --- | --- |
| Futaba S3003, 90°; 0.459792 s | [2910](https://lasonotheque.org/servomoteur-1-90-2-s2910.html) | [2910.wav](https://lasonotheque.org/UPLOAD/bwf-fr/2910.wav) | `0bae7f973d0aae87bf01ad252878950b8b36ab17da60aff53c55c7dbe51d1a4a` |
| Futaba S3003, 180°; 0.690875 s | [2911](https://lasonotheque.org/servomoteur-1-180-1-s2911.html) | [2911.wav](https://lasonotheque.org/UPLOAD/bwf-fr/2911.wav) | `e7f48be365dfa28191824396fecec4245d91d06b45d82ede939ff7fff91cd366` |
| T2M TS-315, 90°; 0.427854 s | [2920](https://lasonotheque.org/servomoteur-2-90-2-s2920.html) | [2920.wav](https://lasonotheque.org/UPLOAD/bwf-fr/2920.wav) | `4939980e094faf197aa675c57d1c6536c2aa18708fdda63979dedb6f61f9de51` |
| T2M TS-315, 180°; 0.764479 s | [2921](https://lasonotheque.org/servomoteur-2-180-1-s2921.html) | [2921.wav](https://lasonotheque.org/UPLOAD/bwf-fr/2921.wav) | `6e6af155055bd46effaaef02e058c2bbdac5bf52c02475476bedd4668eeb2282` |

License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Suggested courtesy credit: “Servo recordings by Joseph Sardin / LaSonothèque, CC0; edited for OpenRC Simulator.”

The Futaba is a standard analog airplane servo according to its [manufacturer page](https://futabausa.com/product/s3003/). LaSonothèque describes the TS-315 as a large servo. **Its torque rating and recording load are not established.** The High-Torque Servo setting is an authored acoustic profile based on that separate larger-servo recording, not a claim that a measured high-torque installation was recorded. The original TS-315 recording is spectrally brighter than the S3003 when analyzed at 44.1 kHz; the deeper profile uses documented authored treatment. Spectral measurements do not replace audition or establish torque.

| Additional recorded layer | Page, author and license | Acquisition and source-fit limit |
| --- | --- | --- |
| `release_air_pffft.wav` | [reg7783, sound 131302](https://freesound.org/people/reg7783/sounds/131302/), CC0 1.0 | [Official HQ MP3 preview](https://cdn.freesound.org/previews/131/131302_2394357-hq.mp3), SHA-256 `56ba199e5b6e90bc2d671b41af1e150f91e2db635315a6026299f1c2d0c9d5c6`. Recorded pneumatic nail-gun disconnect; an air-release layer, not an RC cylinder recording. |
| `Garage Air Compressor Releasing Pressure` | [j_soundeffects, sound 847748](https://freesound.org/people/j_soundeffects/sounds/847748/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | [Official HQ MP3 preview](https://cdn.freesound.org/previews/847/847748_14030247-hq.mp3), SHA-256 `130c6497038ed3b1d04607c88e69a9c114b2e65b241035fbe48a1dd3efacda58`. Zoom H1 recording of a garage compressor pressure valve; sustained air/valve texture, not an RC retract cycle. |

Freesound's original WAV downloads required login; retained files are the official full-length HQ previews, with that lossy source identity preserved. Required attribution for derivatives of sound 847748: **“Garage Air Compressor Releasing Pressure” by j_soundeffects, Freesound sound 847748, CC BY 4.0; trimmed, downmixed, filtered, normalized and loop-edited for OpenRC Simulator.** Link the sound page and license above; no endorsement is implied.

The runtime `app/assets/audio/mechanical/manifest.json` maps each derived file to its actual source, edit segment, processing and hashes. `LICENSE.txt` travels with exported audio. The importer retains the approved originals under `research/audio/AUD-16/recordings/` and reproduces the derived bank offline. Only used source material belongs in that retained bank; acquisition comparisons remain research observations.

## Comparisons and rejected candidates

Thirteen recordings were acquired for evaluation: seven original named-servo WAVs and six official licensed previews. Selection was based on provenance, recording isolation, waveform/spectrum and processing suitability. **No human listening session was performed during this research.**

| Candidate | Evidence / decision |
| --- | --- |
| Hitec HS-55, 90° and 180° | Joseph Sardin, CC0 original recordings: [2940](https://lasonotheque.org/servomoteur-4-90-2-s2940.html), [2942](https://lasonotheque.org/servomoteur-4-180-2-s2942.html). Small-servo alternatives; the initial bank uses S3003 for Standard. |
| Multiplex MS-X4, 180° | Joseph Sardin, [2932](https://lasonotheque.org/servomoteur-3-180-2-s2932.html), CC0 original. Medium-servo alternative; no torque/load qualification. |
| RC car steering servo | [plingativator / Gabriel Koenig, 188917](https://freesound.org/people/plingativator/sounds/188917/), CC BY 4.0. Explicit RC provenance but unidentified hardware, compressed preview and longer mixed movements; superseded by identified CC0 originals. |
| Generic servo sweeps | [Burningmonkey 322021](https://freesound.org/people/Burningmonkey/sounds/322021/), [derjuli 824121](https://freesound.org/people/derjuli/sounds/824121/), [vacuumfan7072 264592](https://freesound.org/people/vacuumfan7072/sounds/264592/), all CC0. No named RC hardware or torque identity; superseded. |
| “Landing Gear” | [77Pacer 425273](https://freesound.org/people/77Pacer/sounds/425273/), CC0, 11.025 kHz custom audio for Aces High II. Physical source provenance unclear; rejected. |
| Airliner gear | [Ramstar757 763119](https://freesound.org/people/Ramstar757/sounds/763119/), CC0; [Boeing 757 gear swing](https://commons.wikimedia.org/wiki/File:757_Gear_Swing.ogg), Peter K. Sheerin, CC BY-SA 4.0. Full-size hydraulic systems mismatch the intended RC equipment; not copied. |
| Designed compressor loop | [kkenny101 861613](https://freesound.org/people/kkenny101/sounds/861613/), explicitly synthetic. Rejected in favor of recordings. |
| Sonniss Odyssey | [Official collection](https://sonniss.com/sound-effects/odyssey-collection-starter/) and [tracklist](https://cdn.sonniss.com/storage/2025/02/The-Odyssey-Collection-STARTER-Sound-Effects-Library.pdf) list an RC-car servo. Paid, and the [license](https://sonniss.com/license/) does not permit raw-library redistribution to unlicensed users; not purchased/copied. |
| Pixabay / commercial sound libraries | [Pixabay terms](https://pixabay.com/service/terms/) restrict standalone redistribution. A game-use license alone is insufficient for an open repository containing source assets. No such asset was copied. |

Searches covered Freesound, LaSonothèque, OpenGameArt, Internet Archive, Wikimedia, commercial catalogs, RC communities, manufacturers and operating videos. Queries included servo, RC servo, RC retract, electric retract, landing gear, MG996R, MG995, S3003, HS-645MG and Savox. The latter exact-model searches did not yield an authenticated, redistributable high-torque recording. Internet Archive/OpenGameArt searches yielded no suitable RC-specific asset with clear source rights. This is a dated search outcome, not proof that no such recording exists.

[Aerofly's servo-sound discussion](https://www.aerofly.com/community/forum/index.php?pageNo=2&user-post-list%2F42623-jparia%2F=) is a useful community reference for movement mapping; its referenced bundled `electric02.wav` has no public redistribution permission. RC demonstrations and installation videos were reference-only. No video audio was extracted, and no third party was contacted for permission.

## Hardware research and interpretation

- [Futaba S3003](https://futabausa.com/product/s3003/), [S9177SV](https://futabausa.com/product/s9177sv/), [TowerPro MG996R](https://towerpro.com.tw/product/mg996R/) and [Hitec HS-645MG](https://hitecrcd.co.jp/material/spec_sheet/servo/32645.pdf) distinguish hardware classes. Torque rating alone does not determine audible pitch; voltage, drive, gearing, load and mounting matter.
- Futaba's [servo parameter guidance](https://futabausa.com/futaba-rc-tech/wireless-setting-of-servo-parameters/) connects deadband/hold settings with correction activity and current draw. The simulator has no measured servo-load telemetry, so it does not invent holding buzz or infer torque from aerodynamic load.
- [Robart electric instructions](https://cdn.shopify.com/s/files/1/0339/0713/files/Electric_Instructions_Rev1_-_Robart.pdf) describe stopping the drive at travel limits/obstruction and supply-dependent speed. Motor sound follows travel and stops after interruption/completion.
- [Robart pneumatic instructions](https://cdn.shopify.com/s/files/1/0339/0713/files/188VR_Rev_6-13__kit_Instructions.pdf) and [manufacturer FAQ](https://robart.com/pages/faqs-robart-manufacturing) describe a servo-operated valve, tank and cylinders. Tank charging does not justify a compressor loop during each gear cycle.

No authenticated RC retract recording was obtained. Electric travel and endpoint cues are adaptations of actual servo mechanisms; pneumatic cues combine recorded air and mechanism textures. A recorded servo stop used as an endpoint cue is explicitly an authored proxy, **not a measured gear-lock sound**. Exact retract hardware fidelity, loaded high-torque recordings and listening acceptance remain open.
