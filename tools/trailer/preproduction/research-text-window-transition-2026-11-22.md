# V2-FX-01 — Zoom-through-text transition

**Researched:** 22 November 2026.
**Status:** Researched effect with a rendered synthetic prototype; optional editorial treatment.
**Branch:** `docs/trailer-v2-preproduction-2026-11-21`.
**Current film authority:** [R6 shooting script](cinematic-script-r6.md), [shot plan](shot-plan-r6.json) and [title plan](title-plan-r6.json).

## Name and visual intention

The closest established name for the requested effect is **zoom-through-text transition**. Related search terms are **text mask reveal**, **video inside text**, **text matte reveal** and **knockout text**. The construction combines video-filled letters with an animated matte that grows until the picture fills the frame.

Wondershare's official [zoom-through-text guide](https://filmora.wondershare.com/customize-video/zoom-in-and-out-effect.html) uses the zoom-through terminology. Adobe's official [dynamic video title tutorial](https://www.adobe.com/us/learn/after-effects/web/dynamic-title-with-video-and-text) demonstrates video inside lettering using an alpha matte. Adobe's [track matte documentation](https://helpx.adobe.com/after-effects/using/track-mattes-and-traveling-mattes.html) explains the underlying compositing relationship. These sources establish the name and mechanism; the trailer timing and engineering choices below are our proposed treatment.

The audience sees black surrounding a large word. Moving footage appears only inside the letter strokes. The word grows toward the viewer, one stroke expands past all four edges, and the very same footage continues full-screen. A two-dimensional mask transform can create the impression of travelling through the word.

## How to build it in After Effects

1. Place the actual footage in a composition matching the delivery frame size and frame rate.
2. Add a black solid underneath.
3. Add a large, heavy text layer and use it as the footage layer's **Alpha Matte** source. Select normal alpha, with the picture visible inside the letter shapes.
4. Keep the footage's scale and timing continuous. Animate the text layer's scale and position.
5. Set the zoom destination inside a thick, filled stroke. Adjust the starting position so moving the anchor does not disturb the initial composition.
6. Hold the word long enough to read it, then enlarge the text with a deliberate acceleration and smooth finish.
7. Continue enlarging until the visible letter ink covers every corner. The underlying clip then continues without a cut or a restart.

The alpha-matte setup follows Adobe's documentation above. Anchor selection, timing and endpoint coverage are the proposed reveal design.

### The anchor matters

The centre of the word is not automatically a valid destination. The empty centre of an **O**, **P** or **R** remains black when the video is visible only in the strokes. Zooming toward that empty area can produce a black screen.

Choose the interior of a substantial stroke, away from its edge. Confirm the final result from the rendered mask; a text bounding box extending beyond the frame does not prove that the entire frame is clear.

### Keep the picture continuous

The mask and the picture have different jobs. The mask expands; the footage keeps playing at its established scale and frame rate. Enlarging a flattened composition would enlarge and crop the footage too. That is a different visual treatment and can introduce a visible jump when handing back to the original shot.

When a matte is used throughout the shot, there is no need for a transition cut at the endpoint: once it admits the whole frame, the original picture is already there.

## Proposed cinematic treatment for this trailer

Use this as one purposeful entrance into a flying sequence. **FLY** is the study word: short, immediately readable and with substantial strokes. It is a creative option, not a replacement already applied to the R6 copy.

Suggested fast version at 60 fps:

| Local frames, end exclusive | Duration | Direction |
| --- | --- | --- |
| 0–12 | 0.20 s | Begin black; reveal the moving picture inside the word. |
| 12–39 | 0.45 s | Hold the word; motion in the footage is already visible. |
| 39–87 | 0.80 s | Expand the matte through a filled stroke. |
| 87 onward | Remaining source shot | Continue the same full-screen footage and sound. |

This is a proposed 1.45-second treatment, not a changed master boundary. Its duration should be judged against the actual shot and musical phrase. A subtle rising sound can build through the expansion and resolve with the engine or musical accent when the picture becomes fully visible.

The opening jet shot is a candidate for an audition because its footage can continue underneath. Test whether the aircraft is recognisable through the letters and whether the opening still establishes flying quickly. Preserve the existing Corsair skin-orbit-to-lake continuity as its own visual moment. The import section needs its model/source labels continuously readable, so it is a poor first place to add a large obscuring mask.

For the visual design, start with the project's existing Barlow Condensed SemiBold, large letters, solid black outside the word and generous stroke width. Reassess the font against real footage: a busy or dark image can make the word hard to read. Delicate outlines, long multi-line copy and prolonged black holds work against this particular entrance.

## How it fits the current code tools

The existing [cinema title renderer](../cinema_titles.py) already provides verified Barlow assets and Pillow-based text rendering. [The assembler](../assemble.py) provides the FFmpeg composition path. A separate clean text-mask component can reuse those dependencies.

The following is an implementation specification, not a new assembler feature:

1. Render a clean glyph coverage mask, with 1 inside the ink and 0 outside. Exclude title shadows, settling motion and opacity effects from the raw mask.
2. Find an interior point in the actual filled glyph raster. Check its neighbourhood in that original raster, not solely in a resized preview.
3. Animate the mask's scale and position around that point. Sample directly into the fixed output frame rather than allocating an enormous enlarged bitmap.
4. Invert the glyph mask to obtain a black cover's alpha.
5. Composite the black cover over the original footage at the matching source frame.
6. At the fully open endpoint, require zero cover alpha at every output pixel. Keep the cover transparent for the remainder of the shot.
7. Preserve source duration, frame cadence and audio.

In normalised notation:

```text
M(t) = animated glyph coverage, in [0, 1]
A(t) = 1 - M(t)                  # black-cover alpha
output(t) = source(t) * M(t)     # with black outside the glyphs
```

For a black-first fade-in, use `M(t) = fade(t) * transformed_glyph(t)`. Fading the inverse cover from transparent to opaque instead would begin with the whole picture visible and then close its surroundings to black. Both are possible treatments, but they have different openings.

Use antialiasing or supersampling for stable letter edges. If motion blur is added, check the endpoint across all contributing subframes so a lingering edge does not create a dark flash. The final clear frame should equal the source before any study label, colour conversion or lossy encoding.

### Integration detail that needs care

The current assembler has overlay paths using `shortest=1`. Feeding a 1.45-second overlay into a longer source shot through such a path could shorten the result. A production implementation should provide a transparent cover through the complete shot, or explicitly configure and verify end-of-overlay behaviour. Check final picture and audio duration after composition.

The existing image `zoompan` treatment is not a substitute for this mask: it transforms the picture. The proposed effect transforms the lettering independently.

## Rendered study and verification

The retained [four-second MP4](review/text-window-2026-11-22/text-window-study.mp4) uses moving abstract graphics with a permanent **SYNTHETIC MOTION / NO GAME FOOTAGE** watermark. The [contact sheet](review/text-window-2026-11-22/text-window-contact.jpg) shows the progression. The [summary](review/text-window-2026-11-22/study-summary.json) records the generator, font/dependency and output identities.

| Local frames, end exclusive | Study phase |
| --- | --- |
| 0–18 | Letter windows fade in from black. |
| 18–72 | Readable word with moving graphics inside it. |
| 72–192 | Mask enlarges; frame 191 is already fully clear. |
| 192–240 | Full-picture continuation. |

This slower study makes the mechanism easy to inspect. The proposed trailer version above is shorter.

The actual output was probed at **1920 × 1080, 60 fps, 240 decoded frames, four seconds**, then fully decoded with FFmpeg `-xerror`. The generator checked **every pixel in frames 191–239**: the black cover had zero alpha and the uncompressed composite equalled the synthetic source before the watermark and H.264 encoding. The chosen anchor also passed a fully opaque neighbourhood check in the original 4× glyph raster. The contact sheet was visually inspected.

Independent source review identified and then confirmed corrections to the original-raster anchor check, black-first fade and strict decode. That review did not independently render the example.

The [generator](../text_window_study.py) is reproducible with the existing verified Barlow assets, Pillow, FFmpeg and ffprobe:

```sh
python3 tools/trailer/text_window_study.py \
  --word FLY \
  --out-dir tmp/trailer/text-window-study-01
```

Use a fresh output directory. The command accepts a study word of 1–16 uppercase A–Z characters/spaces; it produces synthetic footage and does not accept a game capture as an input.

The R6 script, numeric plans and master timing remain the current authorities. The study is isolated from the production assembler. A later footage audition must establish the actual aircraft's visibility and shot continuity.

## Useful references

- [Wondershare: zoom-through-text animation](https://filmora.wondershare.com/customize-video/zoom-in-and-out-effect.html) — naming and visual concept.
- [Adobe: create a dynamic title using video and text](https://www.adobe.com/us/learn/after-effects/web/dynamic-title-with-video-and-text) — official video-filled-text tutorial.
- [Adobe: track mattes and traveling mattes](https://helpx.adobe.com/after-effects/using/track-mattes-and-traveling-mattes.html) — alpha/luminance matte concepts and controls.
- [FFmpeg filter documentation](https://ffmpeg.org/ffmpeg-filters.html#overlay) — overlay frame synchronisation and end-of-file behaviour for a future implementation.

Search phrases: `zoom through text transition`, `video inside text alpha matte`, `text mask reveal`, `zoom through text After Effects`.
