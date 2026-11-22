#!/usr/bin/env python3
"""V2-FX-01: isolated zoom-through-text study on synthetic moving graphics.

This generates research material, not gameplay and not a master-film edit.
Only the letter mask transforms. A black cover uses alpha=255-glyph_coverage.
The full-resolution source continues at its original scale and 60 fps.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
import cinema_titles

W, H, FPS, FRAMES, SS = 1920, 1080, 60, 240, 4
ZOOM_START, ZOOM_END = 72, 191  # Last transform frame is fully revealed.
MARK = 'TEXT MASK STUDY · SYNTHETIC MOTION · NO GAME FOOTAGE'
SAMPLES = (36, 90, 126, 162, 191, 239)


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked(command):
    result = subprocess.run([str(v) for v in command], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-4000:])
    return result.stdout


def solid_square(mask):
    """Find an actually opaque interior square, avoiding counters and edges."""
    box = mask.getbbox()
    if box is None:
        raise ValueError('word has no visible glyphs')
    cropped = mask.crop(box)
    width, height = cropped.size
    pixels = cropped.tobytes()
    previous = [0] * (width + 1)
    best, right, bottom = 0, 0, 0
    for y in range(height):
        current = [0] * (width + 1)
        for x in range(width):
            if pixels[y * width + x] == 255:
                current[x + 1] = 1 + min(previous[x], previous[x + 1], current[x])
                if current[x + 1] > best:
                    best, right, bottom = current[x + 1], x + 1, y + 1
        previous = current
    if best < 4:
        raise ValueError('no safe opaque glyph interior for the zoom')
    return (box[0] + right - best / 2, box[1] + bottom - best / 2), best


class WindowMask:
    def __init__(self, word):
        if not isinstance(word, str) or not re.fullmatch(r'[A-Z ]{1,16}', word) or not word.strip():
            raise ValueError('word must contain 1–16 uppercase A–Z characters/spaces')
        font_path = cinema_titles.FONT_DIR / 'BarlowCondensed-SemiBold.ttf'
        face = ImageFont.truetype(str(font_path), 1024)
        bounds = face.getbbox(word)
        size = max(1, int(1024 * min(.80 * W / (bounds[2]-bounds[0]), .62 * H / (bounds[3]-bounds[1]))))
        face = ImageFont.truetype(str(font_path), size * SS)
        bounds = face.getbbox(word)
        x = (W * SS - (bounds[2]-bounds[0])) / 2 - bounds[0]
        y = (H * SS - (bounds[3]-bounds[1])) / 2 - bounds[1]
        self.source = Image.new('L', (W * SS, H * SS))
        ImageDraw.Draw(self.source).text((round(x),round(y)),word,font=face,fill=255)
        self.anchor, self.interior_square_px = solid_square(self.source.resize((W,H),Image.Resampling.LANCZOS))
        # Confirm the chosen point is inside original glyph ink, not resize ringing.
        ax, ay = (round(value * SS) for value in self.anchor)
        self.anchor_check_bounds = (ax - 2*SS, ay - 2*SS, ax + 2*SS, ay + 2*SS)
        if self.source.crop(self.anchor_check_bounds).getextrema() != (255,255):
            raise ValueError('zoom anchor is not strictly inside the source glyph')
        self.end_scale = max(W,H) / self.interior_square_px * 1.30
        # Check actual resampling, not a bounding-box prediction. Overscan as needed.
        for _ in range(8):
            if self.cover(ZOOM_END).getextrema() == (0,0):
                break
            self.end_scale *= 1.5
        else:
            raise ValueError('could not reach a completely transparent cover')

    def cover(self, frame):
        progress = smooth((frame - ZOOM_START) / (ZOOM_END - ZOOM_START))
        scale = math.exp(math.log(self.end_scale) * progress)
        ax, ay = self.anchor
        target_x = ax + (W/2 - ax) * progress
        target_y = ay + (H/2 - ay) * progress
        # Direct inverse sampling keeps allocation bounded even at a huge zoom.
        coefficients = (SS/scale, 0, SS*(ax-target_x/scale),
                        0, SS/scale, SS*(ay-target_y/scale))
        glyph = self.source.transform((W,H),Image.Transform.AFFINE,coefficients,
                                      resample=Image.Resampling.BICUBIC,fillcolor=0)
        if frame < 18:
            opacity = smooth(frame/17)
            glyph = glyph.point([round(v*opacity) for v in range(256)])
        return ImageOps.invert(glyph)


def pattern(frame, base):
    image=base.copy();draw=ImageDraw.Draw(image)
    # Abstract geometry makes motion obvious without suggesting a simulator scene.
    t=frame/FPS
    for index in range(-2,8):
        x=int(index*420+t*210)
        draw.polygon([(x,-60),(x+170,-60),(x-470,H+60),(x-640,H+60)],fill=(25,132,158))
    cx=int(1170+300*math.sin(t*1.3));cy=int(420+190*math.cos(t*1.1))
    draw.ellipse((cx-370,cy-370,cx+370,cy+370),outline=(241,176,78),width=55)
    draw.line((0,int(750-85*t),W,int(360-85*t)),fill=(121,206,207),width=18)
    return image


def render(out, word='FLY', ffmpeg='ffmpeg', ffprobe='ffprobe'):
    deps=cinema_titles.dependency_identity()
    mask=WindowMask(word)
    out=Path(out);out.mkdir(parents=True,exist_ok=False)
    movie=out/'text-window-study.mp4'
    base=Image.new('RGB',(W,H),(16,42,59));black=Image.new('RGB',(W,H))
    label_font=ImageFont.truetype(str(cinema_titles.FONT_DIR/'BarlowCondensed-Regular.ttf'),30)
    command=[ffmpeg,'-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24',
             '-video_size',f'{W}x{H}','-framerate',str(FPS),'-i','pipe:0','-an',
             '-frames:v',str(FRAMES),'-c:v','libx264','-threads','2','-preset','veryfast',
             '-crf','18','-pix_fmt','yuv420p','-video_track_timescale','60000','-movflags','+faststart',
             '-metadata','comment=Synthetic text-mask study; no game footage',str(movie)]
    samples={}; clear=[]
    process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    try:
        for frame in range(FRAMES):
            source=pattern(frame,base)
            alpha=mask.cover(frame)
            image=Image.composite(black,source,alpha)
            if frame >= ZOOM_END:
                if alpha.getextrema() != (0,0) or image.tobytes() != source.tobytes():
                    raise ValueError(f'frame {frame}: reveal changed source pixels or left a black edge')
                clear.append(frame)
            draw=ImageDraw.Draw(image)
            draw.text((96,1018),MARK,font=label_font,fill=(242,239,231),stroke_width=1,stroke_fill=(0,0,0))
            if frame in SAMPLES:
                samples[frame]=image.copy()
            process.stdin.write(image.tobytes())
        process.stdin.close()
        error=process.stderr.read().decode(errors='replace');code=process.wait()
        if code:raise RuntimeError(error[-4000:])
    except BaseException:
        if process.poll() is None:process.kill()
        process.wait()
        raise
    finally:
        if not process.stdin.closed:process.stdin.close()
        process.stderr.close()
    probe=json.loads(checked([ffprobe,'-v','error','-count_frames','-select_streams','v:0',
        '-show_entries','stream=width,height,avg_frame_rate,nb_read_frames:format=duration','-of','json',movie]))
    video=probe['streams'][0]
    if (video['width'],video['height'],video['avg_frame_rate'],video['nb_read_frames']) != (W,H,'60/1',str(FRAMES)):
        raise ValueError('study dimensions, rate or decoded frame count differ')
    checked([ffmpeg,'-hide_banner','-v','error','-xerror','-i',movie,'-f','null','-'])
    sheet=Image.new('RGB',(1440,612),(12,17,22));draw=ImageDraw.Draw(sheet)
    small=ImageFont.truetype(str(cinema_titles.FONT_DIR/'BarlowCondensed-Regular.ttf'),22)
    for index,frame in enumerate(SAMPLES):
        x,y=(index%3)*480,(index//3)*306
        sheet.paste(samples[frame].resize((480,270),Image.Resampling.LANCZOS),(x,y))
        draw.text((x+10,y+276),f'{frame/FPS:.2f} s · FRAME {frame}',font=small,fill=(242,239,231))
    contact=out/'text-window-contact.jpg';sheet.save(contact,quality=85,subsampling=0)
    summary={'kind':'isolated synthetic zoom-through-text study; no gameplay or master timeline change',
        'word':word,'fps':FPS,'frames':FRAMES,'duration_s':FRAMES/FPS,
        'phases':{'letter_windows_fade_in_from_black':[0,18],'readable_hold':[18,72],
                  'mask_zoom_including_clear_endpoint':[72,192],'full_picture_hold':[192,240]},
        'anchor_source_px':mask.anchor,'opaque_interior_square_px':mask.interior_square_px,
        'anchor_source_4x_check':{'bounds':mask.anchor_check_bounds,'coverage_min':255,'coverage_max':255},
        'end_scale':mask.end_scale,'supersampling':SS,'motion_blur':False,
        'clean_reveal_check':{'first_frame':ZOOM_END,'frames_checked':len(clear),
            'cover_alpha_max':0,'uncompressed_composite_equals_source':True,
            'scope':'Before study watermark and lossy H.264 encoding; every pixel compared.'},
        'generator_sha256':sha(__file__),'dependencies':deps,
        'ffmpeg':checked([ffmpeg,'-version']).splitlines()[0],'probe':probe,
        'outputs':{p.name:sha(p) for p in (movie,contact)}}
    (out/'study-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    return summary


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir',type=Path,required=True)
    parser.add_argument('--word',default='FLY')
    parser.add_argument('--ffmpeg',default='ffmpeg')
    parser.add_argument('--ffprobe',default='ffprobe')
    args=parser.parse_args()
    print(json.dumps(render(args.out_dir,args.word,args.ffmpeg,args.ffprobe),indent=2))
