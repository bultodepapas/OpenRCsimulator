# Trailer tooling survey

2026-10-30 · TRA-10 · Owner request: which video libraries, tools and agent skills would improve the trailer.

There were 33 web searches, and three licenses were checked at the primary source. Most pricing and quality claims come from third-party pages, so check them again before buying or adopting anything.

## Baseline

Godot Movie Maker captures the real session at a fixed 60 fps. The edit uses three tools:

- `crystal_titles.py`: Pillow titles in the UI palette, with tracked tags.
- `assemble.py`: FFmpeg cuts on a measured beat grid, with two-pass loudnorm to −14 LUFS.
- Delivery: H.264 CRF 16 at 1080p60.

Any new tool must beat this and keep the footage honest:

- Captured, not generated.
- Redistributable.
- Pinned.

## Worth adopting (ranked)

| # | Tool | License / cost | Use here |
| --- | --- | --- | --- |
| 1 | [Sonniss GDC bundles](https://sonniss.com/gameaudiogdc) (or [99Sounds cinematic](https://99sounds.org/cinematic-sound-effects/)) | Sonniss: royalty-free, commercial, no attribution, no AI training. 99Sounds: check the terms. | A trailer SFX layer: sub-boom at the heroic entry, whooshes on passes, a soft hit when a title lands. The mix is now music plus game audio only. Read the bundle's license file first. |
| 2 | 240 fps Movie Maker capture plus a 4-frame blend (FFmpeg `tmix=frames=4`, keep every 4th frame) | Free | Real motion blur from rendered frames, as Godot's [Movie Maker article](https://godotengine.org/article/movie-maker-mode-arrives-in-godot-4) suggests. It is not optical-flow interpolation. The sim already runs at 240 Hz. Cost: 4× render time and disk. Pilot on `jet-pass` first. |
| 3 | Native 1440p or 4K Movie Maker capture | Free | Serves the secondary resolution targets ([AGENTS.md](../../../AGENTS.md#display-resolution-priorities)). Larger uploads get YouTube's higher-bitrate tiers ([upload settings](https://support.google.com/youtube/answer/1722171)). Check disk space before rendering. |
| 4 | [beat_this](https://arxiv.org/pdf/2407.21658), madmom or librosa | Open source | Check the hand-measured 0.66848 s grid, and find downbeats and accents for SFX hits. |
| 5 | [Phantom Camera](https://github.com/ramokz/phantom-camera) | MIT, Godot 4.4+ | Cinemachine-style Camera3D for future shots: path, framed dead zone, group framing, tweened handoffs. The directors already script cameras, so adopt it only for new camera-heavy shots, in the trailer runtime and not in `app/`. |
| 6 | [OpenTimelineIO](https://github.com/PixarAnimationStudios/OpenTimelineIO) | Apache 2.0 | Export `timeline.json` so the owner can open the cut in Kdenlive or Resolve, which both import OTIO. Known issue: track order is inverted. |
| 7 | [PySceneDetect](https://github.com/Breakthrough/PySceneDetect) | BSD | Regression check: detected cuts must equal the timeline's cut frames, with no flash frames. |

## Not adopted, and why

- **[Remotion](https://www.remotion.dev/docs/license/faq)** is source-available: free for individuals, non-profits and companies of up to 3 employees. It has an [official agent skill](https://www.remotion.dev/docs/ai/skills) (`npx skills add remotion-dev/skills`). It would replace working Pillow titles with React and headless Chrome, and it needs a company license if the project grows.
  - If titles ever move to HTML, prefer **[HyperFrames](https://github.com/heygen-com/hyperframes)** (Apache 2.0, HTML/GSAP, Claude Code plugin `hyperframes@hyperframes`). Its alpha-overlay output is unverified.
- **ElevenLabs and TTS:** the trailer has no voiceover by design. ElevenLabs' free tier is non-commercial. For a future narrated explainer, use Kokoro-82M (Apache 2.0). F5-TTS and XTTS weights are non-commercial.
- **[Manim](https://docs.manim.community/)** (MIT) suits a separate physics-explainer video, not the trailer.
- **The following add no value:**
  - **MoviePy 2:** slower than direct FFmpeg.
  - **FFmpeg MCP servers:** they only run shell commands.
  - **Third-party video skills:** they are FFmpeg prompt wrappers.
  - **Resolve scripting:** external scripting is Studio-only.
  - **Blender VSE:** no advantage over the FFmpeg edit.
- **LUT packs** (Q-DDL CC BY 4.0, FreeVisuals) are marginal. Per-shot grades already exist.
- **Film grain** costs encoder bits on YouTube.
- **Anthropic** publishes no official video skill. The local Blender skills (camera-cinematography, compositing, rendering) apply only to Blender-rendered shots.

## Craft notes

- **[Steamworks](https://partner.steamgames.com/doc/store/trailer):** the first trailer should be primarily gameplay.
  - The microtrailer is six 1-second clips from it.
  - A trailer may get under 10 s, sometimes muted.
  - The current cut opens on a labeled cinematic formation (0–6 s). A Steam variant could open on gameplay.
  - Titles already carry the meaning without sound.
- **Practitioner guides:** a hook in about 5 s, logos at the end, and cuts that shorten toward the climax. These are conventions, not measured standards.
