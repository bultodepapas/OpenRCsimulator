---
name: export-checklist
description: Pre-export quality-control checklist and recommended export settings by destination (YouTube, vertical short-form, festival, archive). Use when the user is about to render or deliver a video, asks which codec, bitrate, resolution or loudness to use, or wants to avoid common delivery mistakes.
license: MIT
metadata:
  author: Benjamin Leleu
  version: "1.0.0"
---

# Export Checklist

Catch the mistakes that cost a re-render: wrong frame rate, clipped audio, burned-in captions in the danger zone, unlicensed music.

## Inputs to collect

Ask only what is missing:

1. **Destination(s)**: YouTube / streaming, vertical short-form (TikTok, Reels, Shorts), festival or screening, client delivery, archive
2. **Project specs**: resolution, frame rate, color space, whether captions are burned in
3. **Editing tool**: Premiere Pro, DaVinci Resolve, After Effects, other (to name the right export menu)

## Process

1. Run the **universal QC pass** (below) on whatever the user can confirm.
2. Recommend **per-destination settings** from the table, adapted to their project.
3. Flag the **top three risks** for this specific delivery.
4. Remind them to **verify against the platform's current published specs**, since platform requirements change.

## Universal QC pass

- **Picture**: no dropped frames, no black flashes at cuts, no stray frames at head/tail, no leftover offline media or placeholders
- **Frame rate and resolution**: match the project; never "convert" frame rate casually, it creates judder
- **Color**: confirm the working color space and the delivery space; check a still on a second display; watch for crushed blacks and clipped whites
- **Audio**: no clipping, consistent dialogue level, music not masking speech, no pops at cuts, stereo not accidentally mono (or the reverse)
- **Loudness**: streaming platforms commonly normalize around -14 LUFS integrated; keep true peak safely below 0 dBTP (around -1 dBTP is a common safe target)
- **Text and captions**: spelling checked, readable at phone size, kept inside the platform's UI-safe margins (leave generous margins at top and bottom for vertical)
- **Rights**: every music track, font, stock clip and logo has a license or permission; automated copyright systems can mute or block uploads

## Starting-point settings (verify against the destination's current guidance)

| Destination | Container / codec | Resolution & fps | Notes |
|-------------|-------------------|------------------|-------|
| YouTube / streaming | MP4, H.264 (or H.265/AV1 if supported) | Native project resolution, native fps | High bitrate source gives the platform better re-encodes; export at project resolution, do not upscale |
| Vertical short-form | MP4, H.264, AAC audio | 1080x1920, 24-60 fps (match footage) | One master usually serves Shorts, Reels and TikTok; design for the most restrictive UI overlay (right-edge buttons, large bottom area, Reels typically the biggest), keep text and faces in the upper-middle of frame; check each platform's current max length; strong first 1-2 seconds; avoid excessive sharpening |
| Festival / screening | ProRes 422 HQ or the festival's stated spec | Project resolution and fps | Follow the festival's delivery sheet exactly; ask for it |
| Client review | MP4, H.264, moderate bitrate | 1080p | Burn a timecode only if requested |
| Archive / master | ProRes 422 HQ/4444 or DNxHR, plus project files | Original | Keep project, media list and a plain-text notes file |

## Output format

1. **Destination summary**: one line per destination with the recommended preset
2. **QC checklist**: only the items relevant to this delivery, as a tick list
3. **Top 3 risks**: specific to the project
4. **Export menu hints** for the user's tool (e.g. Premiere: Export Settings, match sequence settings; Resolve: Deliver page, render settings)

## Rules

- Never claim a platform's requirements are fixed; they change. Say "verify against current specs".
- If information is missing, give the safest default and say it is a default.
- Do not recommend upscaling or frame-rate conversion unless the user needs it.
