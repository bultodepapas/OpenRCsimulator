#!/usr/bin/env python3
"""Build a repeatable pilot/inspection review kit from the accepted circuit trace."""
import argparse
import html
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from prepare import ROOT, EVIDENCE, prepare, sha256
from checks import check_kit

HERE = Path(__file__).resolve().parent


def checked(command, log, env, timeout=240):
    result = subprocess.run(list(map(str, command)), env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=timeout)
    log.write_text(result.stdout)
    if result.returncode or any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for line in result.stdout.splitlines()):
        raise RuntimeError(f'process failed or reported engine error: {log}')


def parameters():
    pilot = json.loads((ROOT/'app/data/fields/default.json').read_text())['pilot']
    pilot = {k: v['value'] for k, v in pilot.items() if isinstance(v, dict)}
    eye = [pilot['east'], pilot['eye_height']-pilot['down'], -pilot['north']]
    throws = json.loads((ROOT/'app/data/aircraft/jensen_ugly_stik_60.json').read_text())['controls']['max_throw']
    return eye, {k: v['value'] for k, v in throws.items()}


def report_html(out, manifest, proof):
    cards = []
    records = json.loads((out/'first/captures.json').read_text())['frames']
    for frame in manifest['frames']:
        pictures = []
        for record in records:
            if record['id'] != frame['id']:
                continue
            view = record['view']
            metric = next(r for r in proof['images'] if r['id'] == frame['id'] and r['view'] == view)
            pictures.append(f'<figure><a href="first/{record["png"]}"><img src="first/{record["png"]}" alt="{html.escape(frame["id"])} {view}"></a><figcaption>{view.title()} · FOV {record["fov_deg"]:.1f}° · {metric["changed_pixels"]:,} airplane pixels</figcaption></figure>')
        cards.append(f'<section><h2>{html.escape(frame["id"].replace("_", " ").title())}</h2><p>Tick {frame["tick"]} · {frame["time_s"]:.4f} s · CG height {-frame["state"][2]:.2f} m</p><div class="pair">{"".join(pictures)}</div></section>')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>E3c2b circuit review</title>
<style>body{background:#17202a;color:#eee;font:16px system-ui;margin:2rem auto;max-width:1400px;padding:0 1rem}h1,h2{font-weight:550}.pair{display:grid;grid-template-columns:1fr 1fr;gap:1rem}figure{margin:0}img{width:100%;display:block}figcaption{padding:.4rem 0;color:#bacbd8}section{margin:2rem 0}a{color:#9bceff}@media(max-width:750px){.pair{grid-template-columns:1fr}}</style>
<h1>Experimental circuit · recorded-state review</h1><p>Ugly Stik, calm air, propwash off. Twelve recorded stages, shown through the production renderer. Pilot views use the normal fixed eye and auto-zoom; inspection views follow the aircraft.</p>
<p>These are stills from a verified trajectory, not a new simulation replay or a continuous video. The renderer uses the current field and model. Software rendering does not establish human readability, obstacle clearance, physical realism or target-GPU performance.</p>
<p>The airplane-on/off mask keeps the shadow fixed. Pixel counts establish visible rendered content only. Each image repeats exactly in two isolated captures.</p>
<p><a href="manifest.json">Source poses and trace identity</a> · <a href="proof.json">Verification</a> · <a href="source-identity.json">Renderer source identity</a></p>'''
    (out/'index.html').write_text(page+'\n'.join(cards)+'</html>\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='new output directory')
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--trace', type=Path, default=EVIDENCE/'circuit.csv.gz')
    parser.add_argument('--report', type=Path, default=EVIDENCE/'report.json')
    args = parser.parse_args()
    # Validate the source before creating a deliverable or launching a renderer.
    manifest = prepare(args.trace, args.report)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    manifest_path = out/'manifest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2, allow_nan=False)+'\n')
    sources = [ROOT/p for p in subprocess.check_output(['git', '-C', ROOT, 'ls-files', 'app'], text=True).splitlines()]
    sources += list(HERE.glob('*.py')) + list(HERE.glob('*.gd'))
    sources += [ROOT/'research/landing/e3c2a/check_trace.py']
    identity = {str(p.relative_to(ROOT)): sha256(p) for p in sources if p.is_file()}
    (out/'source-identity.json').write_text(json.dumps(identity, indent=2)+'\n')
    godot = args.godot or Path(subprocess.check_output([ROOT/'app/get-godot.sh'], text=True).strip())
    with tempfile.TemporaryDirectory(prefix='openrc-circuit-capture-') as temporary:
        env = os.environ.copy()
        env.update(LIBGL_ALWAYS_SOFTWARE='1', LP_NUM_THREADS='1', OPENRC_SCENERY='off',
                   OPENRC_SCENERY_AUDIO='off', OPENRC_SCENERY_BIRDS='off')
        for name in ('DATA', 'CONFIG', 'CACHE'):
            env[f'XDG_{name}_HOME'] = temporary+'/'+name
        checked([godot, '--headless', '--path', ROOT/'app', '--import'], out/'import.log', env)
        checked([godot, '--headless', '--path', ROOT/'app', '--check-only', '--script', HERE/'capture.gd'], out/'parse.log', env)
        for run in ('first', 'second'):
            checked(['xvfb-run', '-a', godot, '--path', ROOT/'app', '--audio-driver', 'Dummy',
                     '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3',
                     '--resolution', '960x540', '--script', HERE/'capture.gd', '--',
                     f'--manifest={manifest_path}', f'--out={out/run}'], out/f'{run}.log', env)
    proof = check_kit(manifest_path, out/'first', out/'second', *parameters())
    if any(sha256(ROOT/path) != digest for path, digest in identity.items()):
        raise RuntimeError('source changed during capture; repeat from an isolated snapshot')
    (out/'proof.json').write_text(json.dumps(proof, indent=2)+'\n')
    report_html(out, manifest, proof)
    print(f'PASS: {proof["captures"]} pose/camera pairs, exact repeated images: {out/"index.html"}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
