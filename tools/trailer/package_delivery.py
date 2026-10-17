"""Retain the editable sources and make a visual inspection sheet for the finished film."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont


def run(*args):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True, text=True).stdout.strip()


def sha(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def package(out, work, ffmpeg):
    root = Path(__file__).resolve().parents[2]
    film = out / 'OpenRC-Every-Input-Matters-60s-1080p60.mp4'
    assert film.exists()
    spec = json.loads((out / 'timeline.json').read_text(encoding='utf-8'))
    assert spec['status'] == 'accepted production edit'
    shutil.copytree(root / 'tools/trailer', out / 'editor', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2(work / 'game-audio.wav', out / 'sources/game-audio.wav')
    shutil.copy2(work / 'end-card.png', out / 'end-card.png')
    run(ffmpeg, '-y', '-v', 'error', '-ss', '2.5', '-i', film, '-frames:v', 1, out / 'poster.png')
    review = out / 'evidence/visual-review'
    review.mkdir(parents=True, exist_ok=True)
    sheet = Image.new('RGB', (1920, 5 * 306), '#08111c')
    draw = ImageDraw.Draw(sheet)
    face = ImageFont.truetype(str(root / 'tools/trailer/assets/fonts/BarlowCondensed-Regular.ttf'), 24)
    frame = 0
    for index, shot in enumerate(spec['shots']):
        t = (frame + shot['frames'] / 2) / 60
        image_path = review / f'{index:02}-{shot["id"]}.png'
        run(ffmpeg, '-y', '-v', 'error', '-ss', t, '-i', film, '-frames:v', 1, image_path)
        tile = Image.open(image_path).convert('RGB').resize((480, 270), Image.Resampling.LANCZOS)
        x, y = index % 4 * 480, index // 4 * 306
        sheet.paste(tile, (x, y))
        draw.text((x + 10, y + 273), f'{frame / 60:05.2f}s  {shot["id"]}', fill='white', font=face)
        frame += shot['frames']
    sheet.save(out / 'contact-sheet.jpg', quality=93)
    identities = {'repository':str(root), 'head_at_handoff':run('git', '-C', root, 'rev-parse', 'HEAD'),
                  'trees':{}, 'source_files':{}, 'editor_sha256':{},
                  'scope':'No application/physics changes. Live working-tree capture; tree identities retained, not an exact-replay qualification.'}
    for path in ['app', 'assets', 'research']:
        identities['trees'][path] = run('git', '-C', root, 'rev-parse', f'HEAD:{path}')
    for path in sorted((out / 'sources').glob('*')):
        if path.is_file():
            identities['source_files'][path.name] = {'bytes':path.stat().st_size,'sha256':sha(path)}
    for path in sorted((out / 'editor').rglob('*')):
        if path.is_file():
            identities['editor_sha256'][path.relative_to(out / 'editor').as_posix()] = sha(path)
    (out / 'evidence/source-identities.json').write_text(json.dumps(identities,indent=2),encoding='utf-8')
    print(f'PACKAGED {film}\nSHA256 {sha(film)}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--ffmpeg',type=Path,required=True)
    args = parser.parse_args()
    package(args.out,args.work,args.ffmpeg)
