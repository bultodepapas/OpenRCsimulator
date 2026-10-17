"""TRA-06/07: reproducible frame-based edit of captured OpenRC footage.

Uses existing Pillow for English motion-graphic plates and FFmpeg for editing.
No generated gameplay, optical-flow interpolation or solver modifications.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

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


def plate(path, label="", subtitle="", title="", cinematic=False, brand=False, title_xy=(88, 795), gradient=True):
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    if gradient and (label or title):
        for y in range(750, H):
            a = int(155 * ((y - 750) / (H - 750)) ** 1.35)
            d.line((0, y, W, y), fill=(3, 9, 15, a))
    if label:
        d.rectangle((88, 897, 92, 956), fill=(255, 170, 77, 255))
        d.text((111, 887), label, font=font(43), fill=(245, 246, 248, 255))
        if subtitle:
            tracked(d, (113, 941), subtitle, 23, 2.6, (200, 215, 226, 255), True)
    if title:
        d.text(tuple(title_xy), title, font=font(74), fill=(250, 250, 250, 255),
               stroke_width=1 if gradient else 2, stroke_fill=(4, 12, 20, 170))
    if cinematic:
        d.rectangle((78, 68, 510, 111), fill=(4, 12, 20, 160))
        tracked(d, (92, 72), "CINEMATIC FORMATION SEQUENCE", 23, 1.3, (243, 247, 252, 255), True)
    if brand:
        d.text((88, 72), "OpenRC", font=font(38), fill=(255, 255, 255, 240))
        tracked(d, (89, 119), "SIMULATOR", 20, 4, (230, 239, 247, 230), True)
    im.save(path)


def end_card(path):
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
    d.text((153, 776), "bultodepapas.github.io/OpenRCsimulator", font=font(32, True), fill=(173, 199, 217))
    tracked(d, (1590, 94), "EARLY ALPHA", 24, 2, (173, 199, 217), True)
    d.text((153, 986), "Music: Uprising by Scott Buckley · CC BY 4.0 · scottbuckley.com.au", font=font(24, True), fill=(143, 164, 182))
    im.save(path)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


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
    assert sum(s["frames"] for s in shots) == 3600
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    end_card(work / "end-card.png")
    source_rows = []
    video_clips, audio_clips = [], []
    timeline = 0
    editor_hash = sha(__file__)
    for index, shot in enumerate(shots):
        name = shot["id"]
        frames = shot["frames"]
        duration = frames / FPS
        target = work / f"{index:02}-{name}.mp4"
        audio_out = work / f"{index:02}-{name}.wav"
        source = Path(shot["source"]) if name != "end-card" else work / "end-card.png"
        kind = shot.get("kind", "video")
        if prepare_only and kind != "frames" and not source.exists():
            print(f"AWAITING_SOURCE {name}", flush=True)
            timeline += frames
            continue
        source_hash = sha(source) if kind != "frames" else "individual frame hashes in capture manifest"
        fingerprint = hashlib.sha256(json.dumps({"shot":shot,"source":source_hash,"editor":editor_hash},sort_keys=True).encode()).hexdigest()
        cache = work / f"{index:02}-{name}.cache.json"
        if cache.exists() and target.exists() and audio_out.exists() and json.loads(cache.read_text())["fingerprint"] == fingerprint:
            video_clips.append(target)
            audio_clips.append(audio_out)
            source_rows.append({**shot, "timeline_start_frame":timeline, "encoded_sha256":sha(target), "source_sha256":source_hash})
            timeline += frames
            print(f"EDIT_SHOT_CACHED {name}: {frames} frames", flush=True)
            continue
        input_args = []
        if kind == "frames":
            input_args = ["-framerate", FPS, "-start_number", shot.get("start_frame", 0), "-i", source]
        elif kind == "image":
            input_args = ["-loop", "1", "-framerate", FPS, "-i", source]
        else:
            assert source.exists(), source
            input_args = ["-ss", shot.get("start", 0), "-i", source]
        vf = "fps=60,scale=1920:1080:flags=lanczos,setsar=1,setpts=PTS-STARTPTS"
        if shot.get("remove_empty_ui_marker", False):
            # Hidden overlays leave a 20x16 empty panel at (8,8) in this build.
            # Remove only that non-informative panel, never gameplay/report data.
            vf += ",delogo=x=6:y=6:w=24:h=20:show=0"
        if shot.get("grade", True):
            vf += ",eq=contrast=1.035:brightness=-0.012:saturation=1.025:gamma=0.985"
        overlay = shot.get("graphics", {})
        cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "warning", *input_args]
        if overlay:
            graphic = work / f"{index:02}-graphics.png"
            plate(graphic, **overlay)
            cmd += ["-loop", "1", "-framerate", FPS, "-i", graphic]
            show = float(shot.get("graphics_until", duration))
            fade_start = max(0.2, show - 0.35)
            # A formation disclosure must be present for the whole staged shot.
            anim = "format=rgba" if overlay.get("cinematic") else f"format=rgba,fade=t=in:st=0.10:d=0.25:alpha=1,fade=t=out:st={fade_start}:d=0.35:alpha=1"
            cmd += ["-filter_complex", f"[0:v]{vf}[base];[1:v]{anim}[plate];[base][plate]overlay=shortest=1[v]", "-map", "[v]"]
        else:
            cmd += ["-vf", vf]
        cmd += ["-an", "-frames:v", frames, "-c:v", "libx264", "-threads", "6", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", "-r", FPS, "-video_track_timescale", 60000, target]
        run(cmd)
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
        cache.write_text(json.dumps({"fingerprint":fingerprint}),encoding="utf-8")
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
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", game, "-i", spec["music"],
         "-filter_complex", "[0:a]volume=1.0[g];[1:a]volume='0.72*if(lt(t,1),0.5,if(between(t,18,23),0.7,if(between(t,44,48),0.45,1)))':eval=frame[m];[g][m]amix=inputs=2:normalize=0:duration=longest,alimiter=limit=0.89:level=false:latency=true,atrim=duration=60[a]",
         "-map", "[a]", "-ar", 48000, "-c:a", "pcm_s24le", mixed])
    # Two-pass loudness normalization on the full mixed program.
    measure = run([ffmpeg, "-hide_banner", "-i", mixed, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"])
    raw = measure.stderr[measure.stderr.rfind("{"):]
    loud = json.loads(raw)
    normalizer = ("loudnorm=I=-14:TP=-1.5:LRA=11:linear=true:"
                  f"measured_I={loud['input_i']}:measured_TP={loud['input_tp']}:measured_LRA={loud['input_lra']}:"
                  f"measured_thresh={loud['input_thresh']}:offset={loud['target_offset']}")
    final = out / "OpenRC-Every-Input-Matters-60s-1080p60.mp4"
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", picture, "-i", mixed, "-map", "0:v:0", "-map", "1:a:0",
         "-c:v", "copy", "-af", normalizer, "-ar", 48000, "-c:a", "aac", "-b:a", "320k", "-t", 60, "-movflags", "+faststart",
         "-metadata", "title=OpenRC Simulator — Every Input Matters", "-metadata", "comment=Actual simulator captures and labeled cinematic formation. Music: Uprising by Scott Buckley, CC BY 4.0.", final])
    probe = json.loads(run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", final]).stdout)
    v = next(s for s in probe["streams"] if s["codec_type"] == "video")
    assert (v["width"], v["height"], v["r_frame_rate"], int(v["nb_frames"])) == (1920, 1080, "60/1", 3600), v
    assert abs(float(probe["format"]["duration"]) - 60) < .05
    run([ffmpeg, "-hide_banner", "-v", "error", "-i", final, "-f", "null", "-"])
    decoded_measure = run([ffmpeg, "-hide_banner", "-i", final, "-vn", "-af", "loudnorm=I=-14:TP=-1:LRA=11:print_format=json", "-f", "null", "-"])
    decoded_loud = json.loads(decoded_measure.stderr[decoded_measure.stderr.rfind("{"):])
    assert float(decoded_loud["input_tp"]) <= -1.0, decoded_loud
    (out / "render-manifest.json").write_text(json.dumps({"shots": source_rows, "loudness_first_pass": loud, "decoded_aac_loudness": decoded_loud, "probe": probe, "sha256": sha(final)}, indent=2), encoding="utf-8")
    (out / "VIDEO-DESCRIPTION.txt").write_text(
        "OpenRC Simulator — Every Input Matters\n\n"
        "An open-source RC simulator. Development footage with current aircraft, helicopter and RC cars. "
        "The simultaneous four-aircraft finale is labeled cinematic choreography using the original game models; it does not demonstrate multiplayer.\n\n"
        "Project: https://bultodepapas.github.io/OpenRCsimulator/\n\n"
        "'Uprising' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au\n"
        "https://www.scottbuckley.com.au/library/uprising/\n"
        "https://creativecommons.org/licenses/by/4.0/\n"
        "Music edited for length and mixed with simulator audio.\n",
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
        args.work.mkdir(parents=True, exist_ok=True)
        end_card(args.work / "end-card.png")
    else:
        assemble(args.manifest, args.ffmpeg, args.ffprobe, args.out, args.work, args.prepare_only)
