"""TRA-06/07: reproducible frame-based edit of captured OpenRC footage.

Uses existing Pillow for English motion-graphic plates and FFmpeg for editing.
No generated gameplay, optical-flow interpolation or solver modifications.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import tempfile
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

import crystal_titles
import cinema_titles
import title_plan
import shot_plan

HERE = Path(__file__).resolve().parent
FONT = HERE / "assets/fonts/BarlowCondensed-SemiBold.ttf"
REGULAR = HERE / "assets/fonts/BarlowCondensed-Regular.ttf"
W, H, FPS = 1920, 1080, 60


def run(args, **kw):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True, **kw)
    if result.returncode:
        raise RuntimeError(result.stderr[-6000:])
    return result


def font(size, regular=False):
    return ImageFont.truetype(str(REGULAR if regular else FONT), size)


def tracked(draw, xy, text, size, spacing, color, regular=False):
    x, y = xy
    f = font(size, regular)
    for letter in text:
        draw.text((x, y), letter, font=f, fill=color)
        x += draw.textlength(letter, font=f) + spacing
    return x


def plate(path, label="", subtitle="", title="", cinematic=False, brand=False, title_xy=(88, 795), gradient=True, compact=False, crystal=False, cinematic_label="CINEMATIC FORMATION SEQUENCE"):
    accent = crystal_titles.FOCUS + (255,) if crystal else (255, 178, 91, 255)
    ink = (6, 14, 8, 165) if crystal else (4, 12, 20, 155)
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    if gradient and (label or title) and not compact:
        for y in range(750, H):
            a = int(155 * ((y - 750) / (H - 750)) ** 1.35)
            d.line((0, y, W, y), fill=(3, 9, 15, a))
    if label and compact:
        f = font(29)
        width = d.textlength(label, font=f)
        x = W - 96 - width
        d.rounded_rectangle((x - 22, 956, W - 76, 1009), radius=4, fill=ink,
                            outline=crystal_titles.FOCUS + (90,) if crystal else None)
        d.rectangle((x - 20, 966, x - 17, 998), fill=accent)
        d.text((x, 963), label, font=f, fill=crystal_titles.PRIMARY_TEXT + (255,) if crystal else (235, 242, 247, 255))
    elif label:
        d.rectangle((88, 897, 92, 956), fill=(255, 170, 77, 255))
        d.text((111, 887), label, font=font(43), fill=(245, 246, 248, 255))
        if subtitle:
            tracked(d, (113, 941), subtitle, 23, 2.6, (200, 215, 226, 255), True)
    if title:
        d.text(tuple(title_xy), title, font=font(74), fill=(250, 250, 250, 255),
               stroke_width=1 if gradient else 2, stroke_fill=(4, 12, 20, 170))
    if cinematic:
        cy = 963 if compact else 72
        caption_font = font(23, True)
        label_width = sum(d.textlength(letter, font=caption_font) + 1.3 for letter in cinematic_label)
        d.rectangle((78, cy - 4, max(510, int(92 + label_width + 14)), cy + 39), fill=ink, outline=crystal_titles.FOCUS + (110,) if crystal else None)
        tracked(d, (92, cy), cinematic_label, 23, 1.3,
                crystal_titles.CRYSTAL + (255,) if crystal else (243, 247, 252, 255), True)
    if brand:
        brand_x = 1640 if cinematic else 88
        d.text((brand_x, 72), "OpenRC", font=font(38), fill=(255, 255, 255, 240))
        tracked(d, (brand_x + 1, 119), "SIMULATOR", 20, 4, (230, 239, 247, 230), True)
    im.save(path)


def feature_plate(path, cue):
    """Render a transparent, bounded feature title; motion lives in the edit.

    Typography stays in the upper negative space. The background is a feathered
    local scrim, not a full-frame grade, so native models and report UI stay clear.
    Return measured text bounds for export inspection.
    """
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    x, y = cue.get("xy", [96, 88])
    size = cue.get("size", 82)
    lines = cue["headline"]
    assert 1 <= len(lines) <= 2
    kicker = cue.get("kicker", "")
    detail = cue.get("detail", "")
    f = font(size)
    rows = []
    if kicker:
        rows.append((kicker, (x + 53, y + 2), font(25, True), (212, 224, 233, 255)))
    title_y = y + 42
    for i, line in enumerate(lines):
        rows.append((line, (x, title_y + i * (size - 2)), f,
                     (255, 183, 99, 255) if i == len(lines) - 1 else (248, 250, 252, 255)))
    if detail:
        rows.append((detail, (x + 2, title_y + len(lines) * (size - 2) + 18), font(31, True), (234, 241, 247, 255)))
    bounds = [d.textbbox(pos, text, font=face, stroke_width=1) for text, pos, face, color in rows]
    assert all(72 <= b[0] and b[2] <= W - 72 and 64 <= b[1] and b[3] <= 450 for b in bounds), bounds
    right = max(b[2] for b in bounds)
    bottom = max(b[3] for b in bounds)
    # Small-resolution mask is smoothly resampled once instead of painting a
    # costly per-pixel HD gradient. Text remains native-resolution vector type.
    mask = Image.new("L", (W // 4, H // 4))
    pixels = mask.load()
    for py in range(min(H // 4, (bottom + 160) // 4)):
        yy = py * 4
        fy = math.exp(-((yy - (y + bottom) / 2) / 200) ** 2)
        fy *= min(1.0, max(0.0, (bottom + 160 - yy) / 100))
        for px in range(min(W // 4, (right + 360) // 4)):
            xx = px * 4
            fx = math.exp(-((xx - (x + right) / 2) / (right - x + 190)) ** 2)
            fx *= min(1.0, max(0.0, (right + 360 - xx) / 160))
            pixels[px, py] = int(115 * fx * fy)
    scrim = Image.new("RGBA", (W, H), (3, 9, 16, 0))
    scrim.putalpha(mask.resize((W, H), Image.Resampling.BICUBIC))
    im.alpha_composite(scrim)
    d = ImageDraw.Draw(im)
    if kicker:
        d.line((x, y + 19, x + 33, y + 19), fill=(255, 183, 99, 255), width=3)
    for text, pos, face, color in rows:
        d.text(pos, text, font=face, fill=color, stroke_width=1, stroke_fill=(3, 9, 16, 80))
    im.save(path)
    return {"text_bounds": bounds, "safe_area": [72, 64, W - 72, 450], "scrim_bottom": bottom + 160}


def end_card(path, detail=""):
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            light = math.exp(-(((x - 1430) / 950) ** 2 + ((y - 390) / 650) ** 2))
            px[x, y] = (int(5 + 6 * light), int(11 + 13 * light), int(19 + 19 * light))
    d = ImageDraw.Draw(im)
    tracked(d, (150, 176), "OPEN SOURCE RC SIMULATION", 25, 4, (151, 176, 194), True)
    d.text((144, 274), "OpenRC", font=font(192), fill=(244, 247, 250))
    tracked(d, (153, 490), "SIMULATOR", 49, 14, (214, 226, 236), True)
    d.rectangle((153, 598, 285, 602), fill=(255, 170, 77))
    d.text((150, 648), "EVERY INPUT MATTERS.", font=font(59), fill=(249, 250, 252))
    if detail:
        tracked(d, (153, 734), detail, 27, 3, (214, 226, 236), True)
    d.text((153, 776), "bultodepapas.github.io/OpenRCsimulator", font=font(32, True), fill=(173, 199, 217))
    tracked(d, (1590, 94), "BETA PREVIEW", 24, 2, (173, 199, 217), True)
    d.text((153, 986), "Music: Uprising by Scott Buckley · CC BY 4.0 · scottbuckley.com.au", font=font(24, True), fill=(143, 164, 182))
    im.save(path)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def frame_sequence_identity(pattern, start_frame, frames):
    """Hash the exact numbered source frames, not the name of a capture report."""
    value = str(pattern)
    matches = list(re.finditer(r'%(?:0[1-9][0-9]*)?d', value))
    if len(matches) != 1 or value.count('%') != 1:
        raise ValueError('frame source must contain exactly one %d or %0Nd number pattern')
    if type(start_frame) is not int or start_frame < 0:
        raise ValueError('frame source start_frame must be a nonnegative integer')
    digest = hashlib.sha256()
    for number in range(start_frame, start_frame + frames):
        path = Path(value % number)
        digest.update(f'{number}:{sha(path)}\n'.encode('ascii'))
    return digest.hexdigest()


def editor_identity(style, ffmpeg):
    """Cache inputs include rasterization, licensed assets and encoder identity."""
    return {'assemble_sha256':sha(__file__), 'crystal_sha256':sha(crystal_titles.__file__),
            'cinema_sha256':sha(cinema_titles.__file__), 'title_plan_tool_sha256':sha(title_plan.__file__),
            'style':style, 'title_dependencies':cinema_titles.dependency_identity(),
            'ffmpeg':run([ffmpeg, '-version']).stdout}


def cinema_context(spec, resolve, prepare_only):
    """Bind editorial timing before opening any sources or creating output files."""
    if spec.get('style') != 'cinema':
        return None
    if not spec.get('title_plan') or not spec.get('shot_plan'):
        raise ValueError('cinema style requires title_plan and shot_plan paths')
    plan_path = resolve(spec['shot_plan'])
    plan, plan_digest = shot_plan.read_snapshot(plan_path)
    # Use the repository sources and their pinned hashes, never trust a media
    # manifest to redefine the stock vehicle/skin bindings.
    shot_plan.validate(plan, HERE.parents[1])
    if plan.get('revision') not in ('R6', 'R7'):
        raise ValueError('cinema style requires an R6 or R7 shot plan')
    actual = [(s['id'], s['frames']) for s in spec['shots']]
    expected = [(s['id'], s['out_frame']-s['in_frame']) for s in plan['shots']]
    if actual != expected:
        raise ValueError('cinema media shot order and lengths must match the selected shot plan')
    for shot in spec['shots']:
        if shot.get('graphics') or shot.get('features'):
            raise ValueError('cinema titles come only from the global title plan')
        if shot.get('fade_in_frames') or shot.get('fade_out_frames'):
            raise ValueError('cinema uses hard picture cuts; animate titles in the global title plan')
        if shot['id'] == 'R4-45' and shot.get('kind') != 'end_card':
            raise ValueError('R4-45 must use kind=end_card to avoid inherited legacy card text')
        if shot['id'] != 'R4-45' and shot.get('kind') == 'end_card':
            raise ValueError('only R4-45 can use kind=end_card')
    titles_path = resolve(spec['title_plan'])
    loaded = title_plan.load(titles_path, publication=not prepare_only,
                             trial_basis=spec.get('trial_basis'), shot_plan=plan)
    if not prepare_only:
        for key in ('title', 'metadata_comment', 'video_description', 'output_filename'):
            if not isinstance(spec.get(key), str) or not spec[key].strip():
                raise ValueError(f'cinema publication requires explicit {key}; legacy defaults are not used')
    return {**loaded, 'title_plan_sha256':loaded['source_sha256'], 'shot_plan_sha256':plan_digest}


def cinema_end_card_base(path):
    """Text-free editorial background; all wording comes from the title plan."""
    ramp = Image.new('RGB', (1, H))
    pixels = ramp.load()
    for y in range(H):
        lift = round(4 * (1 - abs(2*y/(H-1)-1)))
        pixels[0,y] = (10+lift, 13+lift, 17+lift)
    ramp.resize((W,H)).save(path)


def render_graphics_only(manifest_path, work):
    """Legacy graphics remain available, but a cinema manifest gets R6 copy."""
    work.mkdir(parents=True,exist_ok=True)
    spec = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path else {}
    if spec.get('style') != 'cinema':
        end_card(work/'end-card.png',spec.get('end_card_detail',''))
        return
    if not spec.get('title_plan'):
        raise ValueError('cinema graphics require title_plan')
    path = Path(spec['title_plan'])
    if not path.is_absolute(): path = (manifest_path.parent/path).resolve()
    loaded = title_plan.load(path)
    base = work/'cinema-end-card-base.png'
    cinema_end_card_base(base)
    with Image.open(base) as image:
        frame = image.convert('RGBA')
    for cue in loaded['cues']:
        if cue['in_frame'] <= 8700 < cue['out_frame']:
            frame.alpha_composite(cinema_titles.CinemaCue(cue).frame(8700))
    frame.convert('RGB').save(work/'cinema-end-card.png')


def valid_cached_clip(cache, target, audio_out, fingerprint):
    """An interrupted or replaced encode cannot inherit an old cache receipt."""
    try:
        receipt = json.loads(cache.read_text(encoding='utf-8'))
        return (receipt.get('fingerprint') == fingerprint
                and receipt.get('video_sha256') == sha(target)
                and receipt.get('audio_sha256') == sha(audio_out))
    except (OSError, ValueError, AttributeError):
        return False


def check_encoded_clip(path, ffprobe, frames):
    data = json.loads(run([ffprobe,'-v','error','-select_streams','v:0',
        '-show_entries','stream=width,height,avg_frame_rate,nb_frames','-of','json',path]).stdout)
    streams = data.get('streams',[])
    if len(streams) != 1:
        raise ValueError(f'encoded clip has no unique video stream: {path}')
    value = streams[0]
    if (value.get('width'),value.get('height'),value.get('avg_frame_rate'),str(value.get('nb_frames'))) != (W,H,'60/1',str(frames)):
        raise ValueError(f'encoded clip does not contain the requested 1080p60 frames: {value}')


def assemble(manifest_path, ffmpeg, ffprobe, out, work, prepare_only=False):
    spec = json.loads(manifest_path.read_text(encoding="utf-8"))
    def media_path(value):
        path = Path(value)
        return path if path.is_absolute() else (manifest_path.parent / path).resolve()

    spec["music"] = str(media_path(spec["music"]))
    shots = spec["shots"]
    for shot in shots:
        for key in ("source", "audio"):
            if shot.get(key):
                shot[key] = str(media_path(shot[key]))
    assert spec.get("fps", FPS) == FPS
    assert shots and all(isinstance(s["frames"], int) and s["frames"] > 0 for s in shots)
    total_frames = sum(s["frames"] for s in shots)
    total_duration = total_frames / FPS
    cinema = cinema_context(spec, media_path, prepare_only)
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    if cinema:
        cinema_end_card_base(work / 'cinema-end-card-base.png')
    else:
        end_card(work / "end-card.png", spec.get("end_card_detail", ""))
    source_rows = []
    video_clips, audio_clips = [], []
    timeline = 0
    editor = editor_identity(spec.get('style',''), ffmpeg)
    for index, shot in enumerate(shots):
        name = shot["id"]
        frames = shot["frames"]
        duration = frames / FPS
        target = work / f"{index:02}-{name}.mp4"
        audio_out = work / f"{index:02}-{name}.wav"
        kind = shot.get("kind", "video")
        if cinema and kind == 'end_card':
            source = work / 'cinema-end-card-base.png'
            kind = 'image'
        else:
            source = Path(shot["source"]) if name != "end-card" else work / "end-card.png"
        if prepare_only and kind != "frames" and not source.exists():
            print(f"AWAITING_SOURCE {name}", flush=True)
            timeline += frames
            continue
        try:
            source_hash = sha(source) if kind != "frames" else frame_sequence_identity(source, shot.get('start_frame',0), frames)
            audio_hash = sha(shot["audio"]) if shot.get("audio") else None
        except FileNotFoundError:
            if not prepare_only:
                raise
            print(f'AWAITING_SOURCE {name}', flush=True)
            timeline += frames
            continue
        fingerprint = hashlib.sha256(json.dumps({'shot':shot,'source':source_hash,'audio':audio_hash,
            'editor':editor,'timeline_start_frame':timeline,'cinema':cinema},sort_keys=True).encode()).hexdigest()
        cache = work / f"{index:02}-{name}.cache.json"
        if valid_cached_clip(cache, target, audio_out, fingerprint):
            video_clips.append(target)
            audio_clips.append(audio_out)
            source_rows.append({**shot, "timeline_start_frame":timeline, "encoded_sha256":sha(target), "source_sha256":source_hash})
            timeline += frames
            print(f"EDIT_SHOT_CACHED {name}: {frames} frames", flush=True)
            continue
        # Invalidate before overwriting either encoded output. A failed attempt
        # cannot leave the previous fingerprint authorizing mixed/partial files.
        cache.unlink(missing_ok=True)
        input_args = []
        if kind == "frames":
            input_args = ["-framerate", FPS, "-start_number", shot.get("start_frame", 0), "-i", source]
        elif kind == "image":
            input_args = ["-loop", "1", "-framerate", FPS, "-i", source]
        else:
            assert source.exists(), source
            input_args = ["-ss", shot.get("start", 0), "-i", source]
        vf = "fps=60,scale=1920:1080:flags=lanczos,setsar=1,setpts=PTS-STARTPTS"
        if kind == "image" and shot.get("zoom"):
            # TRA-10: slow eased push-in on the interface value that matters; supersampled to avoid stair-stepping.
            (cx, cy), z = shot["zoom"]["center"], float(shot["zoom"]["to"])
            ease = f"(3*pow(on/{frames},2)-2*pow(on/{frames},3))"
            vf = (f"scale=3840:2160:flags=lanczos,zoompan=z='1+{z - 1}*{ease}':"
                  f"x='max(0,min(iw-iw/zoom,{2 * cx}-iw/zoom/2))':y='max(0,min(ih-ih/zoom,{2 * cy}-ih/zoom/2))':"
                  f"d=1:s=1920x1080:fps=60,setsar=1,setpts=PTS-STARTPTS")
        if shot.get("remove_empty_ui_marker", False):
            # Hidden overlays leave a 20x16 empty panel at (8,8) in this build.
            # Remove only that non-informative panel, never gameplay/report data.
            vf += ",delogo=x=6:y=6:w=24:h=20:show=0"
        if isinstance(shot.get("grade"), str):
            vf += "," + shot["grade"]  # TRA-10: an explicit per-shot grade, e.g. the cool night look
        elif shot.get("grade", True):
            vf += ",eq=contrast=1.035:brightness=-0.012:saturation=1.025:gamma=0.985"
        overlay = shot.get("graphics", {})
        cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "warning", *input_args]
        filters = [f"[0:v]{vf}[base]"]
        current = "base"
        input_index = 1
        cinema_sequence_root = None
        crystal = spec.get("style") == "crystal"
        if cinema and any(c['in_frame'] < timeline + frames and c['out_frame'] > timeline for c in cinema['cues']):
            # Reserve a fresh sequence even after an interrupted render. Sample
            # the master clock so a held source label cannot blink at each cut.
            cinema_sequence_root = Path(tempfile.mkdtemp(prefix=f'{index:02}-cinema-', dir=work))
            sequence = cinema_sequence_root / 'rgba'
            try:
                cinema_titles.render_sequence(sequence, cinema['cues'], timeline, frames)
            except BaseException:
                shutil.rmtree(cinema_sequence_root)
                raise
            cmd += ['-framerate', FPS, '-start_number', 0, '-i', sequence / '%05d.png']
            filters += [f'[{current}][{input_index}:v]overlay=0:0:shortest=1:alpha=straight[cinema]']
            current = 'cinema'
            input_index += 1
        if overlay:
            graphic = work / f"{index:02}-graphics.png"
            plate(graphic, **overlay, crystal=crystal)
            cmd += ["-loop", "1", "-framerate", FPS, "-i", graphic]
            show = float(shot.get("graphics_until", duration))
            fade_start = max(0.2, show - 0.35)
            # A formation disclosure must be present for the whole staged shot.
            anim = "format=rgba" if overlay.get("cinematic") else f"format=rgba,fade=t=in:st=0.10:d=0.25:alpha=1,fade=t=out:st={fade_start}:d=0.35:alpha=1"
            filters += [f"[{input_index}:v]{anim}[plate]", f"[{current}][plate]overlay=shortest=1[labels]"]
            current = "labels"
            input_index += 1
        for cue_index, cue in enumerate(shot.get("features", [])):
            if crystal:
                # TRA-09: per-frame crystal titles carry their own entrance, landing glow and exit.
                sequence = work / f"{index:02}-crystal-{cue_index}"
                crystal_titles.render_cue(sequence, cue, frames, duration, bool(cue.get("lower", False)))
                cmd += ["-framerate", FPS, "-i", sequence / "%05d.png"]
                next_label = f"featured{cue_index}"
                filters += [f"[{current}][{input_index}:v]overlay=0:0:shortest=1[{next_label}]"]
                current = next_label
                input_index += 1
                continue
            graphic = work / f"{index:02}-feature-{cue_index}.png"
            feature_plate(graphic, cue)
            cmd += ["-loop", "1", "-framerate", FPS, "-i", graphic]
            start, end = float(cue.get("start", 0)), float(cue.get("end", duration))
            fade_in, fade_out = .25, .25
            anim = "format=rgba"
            if start >= 0:
                anim += f",fade=t=in:st={start}:d={fade_in}:alpha=1"
            if end <= duration:
                anim += f",fade=t=out:st={max(0, end-fade_out)}:d={fade_out}:alpha=1"
            # Negative start carries a title continuously across adjacent cuts.
            shift = f"18*pow(1-clip((t-({start}))/{fade_in},0,1),3)"
            next_label = f"featured{cue_index}"
            filters += [f"[{input_index}:v]{anim}[feature{cue_index}]",
                        f"[{current}][feature{cue_index}]overlay=x='{shift}':y=0:shortest=1[{next_label}]"]
            current = next_label
            input_index += 1
        fades = []
        if shot.get("fade_in_frames", 0):
            fades.append(f"fade=t=in:st=0:d={shot['fade_in_frames']/FPS}")
        if shot.get("fade_out_frames", 0):
            fade_frames = shot["fade_out_frames"]
            assert 1 < fade_frames < frames
            # The last encoded frame reaches black, not one frame after EOF.
            fades.append(f"fade=t=out:st={(frames-fade_frames)/FPS}:d={(fade_frames-1)/FPS}")
        if fades:
            filters.append(f"[{current}]{','.join(fades)}[transition]")
            current = "transition"
        cmd += ["-filter_complex", ";".join(filters), "-map", f"[{current}]"]
        cmd += ["-an", "-frames:v", frames, "-c:v", "libx264", "-threads", "6", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", "-r", FPS, "-video_track_timescale", 60000, target]
        try:
            run(cmd)
        finally:
            if cinema_sequence_root is not None:
                shutil.rmtree(cinema_sequence_root)
        check_encoded_clip(target,ffprobe,frames)
        video_clips.append(target)
        audio_out = work / f"{index:02}-{name}.wav"
        audio = shot.get("audio")
        if audio:
            run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-ss", shot.get("audio_start", shot.get("start", 0)), "-i", audio,
                 "-af", f"atrim=duration={duration},asetpts=PTS-STARTPTS,volume={shot.get('audio_gain', 1)},afade=t=in:d=0.025,afade=t=out:st={max(0,duration-0.035)}:d=0.035,apad=whole_dur={duration}",
                 "-t", duration, "-ar", 48000, "-ac", 2, "-c:a", "pcm_s24le", audio_out])
        else:
            run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", duration, "-c:a", "pcm_s24le", audio_out])
        audio_clips.append(audio_out)
        source_rows.append({**shot, "timeline_start_frame": timeline, "encoded_sha256": sha(target),
                            "source_sha256": source_hash})
        cache.write_text(json.dumps({'fingerprint':fingerprint,'video_sha256':sha(target),
                                     'audio_sha256':sha(audio_out)}),encoding='utf-8')
        timeline += frames
        print(f"EDIT_SHOT_OK {name}: {frames} frames", flush=True)
    if prepare_only:
        return
    for filename, paths in [("picture-list.txt", video_clips), ("sound-list.txt", audio_clips)]:
        (work / filename).write_text("".join("file '" + x.resolve().as_posix().replace("'", "'\\''") + "'\n" for x in paths), encoding="utf-8")
    picture = work / "picture.mp4"
    game = work / "game-audio.wav"
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", 0, "-i", work / "picture-list.txt", "-c", "copy", picture])
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", 0, "-i", work / "sound-list.txt", "-c:a", "pcm_s24le", game])
    mixed = work / "mix.wav"
    mix_settings = spec.get("mix", {})
    game_gain = float(mix_settings.get("game_gain", 1.0))
    music_gain = float(mix_settings.get("music_gain", 0.72))
    assert 0 < music_gain <= 2 and 0 <= game_gain <= 2
    # Keep the score continuous. Shot order must never inherit time-coded ducks
    # from an older edit; prominence is explicit in the portable manifest.
    mix_filter = (f"[0:a]volume={game_gain}[g];[1:a]volume={music_gain}[m];"
                  "[g][m]amix=inputs=2:normalize=0:duration=longest,"
                  f"alimiter=limit=0.89:level=false:latency=true,atrim=duration={total_duration}[a]")
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", game, "-i", spec["music"],
         "-filter_complex", mix_filter,
         "-map", "[a]", "-ar", 48000, "-c:a", "pcm_s24le", mixed])
    # Two-pass loudness normalization on the full mixed program.
    measure = run([ffmpeg, "-hide_banner", "-i", mixed, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"])
    raw = measure.stderr[measure.stderr.rfind("{"):]
    # FFmpeg can append progress statistics after the filter's JSON object.
    loud = json.JSONDecoder().raw_decode(raw)[0]
    normalizer = ("loudnorm=I=-14:TP=-1.5:LRA=11:linear=true:"
                  f"measured_I={loud['input_i']}:measured_TP={loud['input_tp']}:measured_LRA={loud['input_lra']}:"
                  f"measured_thresh={loud['input_thresh']}:offset={loud['target_offset']}")
    final = out / spec.get("output_filename", f"OpenRC-Every-Input-Matters-{total_duration:g}s-1080p60.mp4")
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", picture, "-i", mixed, "-map", "0:v:0", "-map", "1:a:0",
         "-c:v", "copy", "-af", normalizer, "-ar", 48000, "-c:a", "aac", "-b:a", "320k", "-t", total_duration, "-movflags", "+faststart",
         "-metadata", "title=" + spec.get("title", "OpenRC Simulator — Every Input Matters"), "-metadata", "comment=" + spec.get("metadata_comment", "Actual simulator captures and labeled cinematic formation. Music: Uprising by Scott Buckley, CC BY 4.0."), final])
    probe = json.loads(run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", final]).stdout)
    v = next(s for s in probe["streams"] if s["codec_type"] == "video")
    assert (v["width"], v["height"], v["r_frame_rate"], int(v["nb_frames"])) == (1920, 1080, "60/1", total_frames), v
    assert abs(float(probe["format"]["duration"]) - total_duration) < .05
    run([ffmpeg, "-hide_banner", "-v", "error", "-i", final, "-f", "null", "-"])
    decoded_measure = run([ffmpeg, "-hide_banner", "-i", final, "-vn", "-af", "loudnorm=I=-14:TP=-1:LRA=11:print_format=json", "-f", "null", "-"])
    decoded_loud = json.JSONDecoder().raw_decode(decoded_measure.stderr[decoded_measure.stderr.rfind("{"):])[0]
    assert float(decoded_loud["input_tp"]) <= -1.0, decoded_loud
    (out / "render-manifest.json").write_text(json.dumps({"shots": source_rows, 'editor':editor, 'cinema':cinema, "mix":{"game_gain":game_gain,"music_gain":music_gain,"music_sha256":sha(spec["music"]),"music_ducks":False}, "loudness_first_pass": loud, "decoded_aac_loudness": decoded_loud, "probe": probe, "sha256": sha(final)}, indent=2), encoding="utf-8")
    (out / "VIDEO-DESCRIPTION.txt").write_text(spec.get("video_description") or (
        "OpenRC Simulator — Every Input Matters\n\n"
        "An open-source RC simulator. Development footage with current aircraft, helicopter and RC cars. "
        "The simultaneous four-aircraft sequence is labeled cinematic choreography using the original game models; it does not demonstrate multiplayer.\n\n"
        "Project: https://bultodepapas.github.io/OpenRCsimulator/\n\n"
        "'Uprising' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au\n"
        "https://www.scottbuckley.com.au/library/uprising/\n"
        "https://creativecommons.org/licenses/by/4.0/\n"
        "Music edited for length and mixed with simulator audio.\n"),
        encoding="utf-8")
    print(str(final), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--ffmpeg", type=Path)
    parser.add_argument("--ffprobe", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--work", type=Path, default=Path("tmp/trailer/edit"))
    parser.add_argument("--graphics-only", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if args.graphics_only:
        render_graphics_only(args.manifest,args.work)
    else:
        assemble(args.manifest, args.ffmpeg, args.ffprobe, args.out, args.work, args.prepare_only)
