#!/usr/bin/env python3
"""Compare two engine capture suites with matching cameras, poses and lighting."""
import argparse
import html
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from make_detail_gallery import relative_href, validate_manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path, help='Before manifest.json')
    parser.add_argument('after', type=Path, help='After manifest.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    before, _ = validate_manifest(args.before)
    after, _ = validate_manifest(args.after)
    old = {c['file']: c for c in before['captures']}
    if set(old) != {c['file'] for c in after['captures']}:
        parser.error('Capture filenames differ between suites')
    if before['capture_design']['lighting'] != after['capture_design']['lighting']:
        parser.error('Lighting differs between suites')
    sections = []
    for c in after['captures']:
        for key in ('camera', 'root_pose', 'commands', 'temporarily_hidden_mesh_name_rules'):
            if c[key] != old[c['file']][key]:
                parser.error(f"Comparison differs in {key}: {c['file']}")
        images = []
        for label, manifest in [('Antes', args.before), ('Después', args.after)]:
            href = html.escape(relative_href(args.output.resolve().parent, (manifest.parent / c['file']).resolve()), quote=True)
            images.append(f'<figure><a href="{href}"><img loading="lazy" src="{href}" alt="{label}"></a><figcaption>{label}</figcaption></figure>')
        sections.append(f'<section><h2>{html.escape(c["condition"])}</h2><div class="pair">{"".join(images)}</div></section>')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ugly Stik · mejora del motor</title><style>
:root{color-scheme:dark;font:16px system-ui;background:#111820;color:#eef2f5}body{margin:24px}h1{font-size:28px}h2{font-size:19px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px;background:#25313b}section{margin:30px 0}a{color:#badaff}@media(max-width:700px){.pair{grid-template-columns:1fr}}
</style><h1>Ugly Stik · mejora del motor</h1><p>Mismas cámaras, iluminación y poses. Pulsa cada imagen para abrirla a resolución completa.</p>
''' + '\n'.join(sections) + '</html>\n', encoding='utf-8')
    print(f'Wrote {len(sections)} matched before/after comparisons: {args.output}')


if __name__ == '__main__':
    main()
