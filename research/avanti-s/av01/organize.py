#!/usr/bin/env python3
"""Build the local Avanti reference desk without changing any original."""
import argparse
import hashlib
import html
import json
import math
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'references/avanti-s/organized'


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def check_data(data, selection):
    for key, fact in data['facts'].items():
        assert math.isfinite(fact['value']), key
        assert fact['unit'] and fact['kind'], key
        assert fact['source']['id'] in data['sources'], key
        assert fact['source']['pdf_page'] > 0, key
    for key, ratio in data['ratios'].items():
        a, b = [data['facts'][name]['value'] for name in ratio['inputs']]
        expected = a / b
        if ratio['operation'] == 'divide_by_mass_g0':
            expected /= ratio['g0_m_s2']
        assert math.isclose(ratio['value'], expected, rel_tol=1e-12), key
    assert len(set(selection['photos'].values())) == len(selection['photos'])
    assert len({x['name'] for x in selection['steps']}) == len(selection['steps'])
    for entry in selection['steps']:
        assert entry['page'] == (entry['step'] + 1) // 2
        assert entry['half'] == ('top' if entry['step'] % 2 else 'bottom')
    print(f"Data OK: {len(data['facts'])} facts, {len(data['ratios'])} ratios, "
          f"{len(selection['steps'])} selected steps")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-data', action='store_true')
    args = parser.parse_args()
    data = read(HERE / 'measurements.json')
    selection = read(HERE / 'selection.json')
    check_data(data, selection)
    if args.check_data:
        return
    manifest = read(ROOT / 'docs/research/avanti-s-resources.json')
    originals = [x for x in manifest['items'] if x['status'] == 'downloaded']
    missing = [x['path'] for x in originals if not (ROOT / x['path']).exists()]
    if missing:
        parser.exit(2, 'Local reference pack is absent/incomplete; app is unaffected.\n'
                    + '\n'.join(missing) + '\n')
    for exe in ['pdftoppm', 'pdftotext', 'pdfinfo']:
        if not shutil.which(exe):
            parser.exit(2, f'Required local tool: {exe}\n')
    from PIL import Image
    for item in originals:
        assert digest(ROOT / item['path']) == item['sha256'], item['path']
    for source in data['sources'].values():
        assert digest(ROOT / source['path']) == source['sha256']
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    by_path = {x['path']: x for x in originals}

    def record(dest, source, **extra):
        item = dict(path=str(dest.relative_to(ROOT)), source=source['path'],
                    source_url=source['url'], source_sha256=source['sha256'],
                    sha256=digest(dest), bytes=dest.stat().st_size, **extra)
        if dest.suffix in ['.jpg', '.png']:
            with Image.open(dest) as im:
                item['size_px'] = list(im.size)
                im.verify()
        records.append(item)

    def copy(source, target, purpose):
        dest = OUT / target
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / source['path'], dest)
        record(dest, source, operation='byte_identical_copy', purpose=purpose)

    pdf_names = {
        'avanti-s-200-intro': 'a200-01-dimensiones-mandos-cg',
        'avanti-s-200-assembly': 'a200-02-montaje-fotografico-91-paginas',
        'jetcat-p100-rx-spec': 'p100rx-vistas-ilustradas-no-tabla-prestaciones',
        'jetcat-p100-rx-dimensions': 'p100rx-plano-dimensiones-241x97mm',
        'jetcat-p100-rx-mount': 'p100rx-plano-abrazadera',
        'jetcat-catalog-2017': 'p100rx-catalogo-2017-tabla-pdf-p15',
        'jetcat-rx-manual-de': 'jetcat-rx-manual-historico-2011-comparacion',
    }
    for source in originals:
        path = Path(source['path'])
        if path.suffix == '.pdf':
            group = 'documents/comparison' if '/comparison/' in source['path'] else 'documents/baseline'
            name = pdf_names.get(path.stem, path.stem)
            copy(source, f'{group}/{name}.pdf', source['purpose'])
            text = OUT / 'documents/text' / (name + '.txt')
            text.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['pdftotext', '-layout', str(ROOT / source['path']), str(text)], check=True,
                           stderr=subprocess.PIPE)
            record(text, source, operation='pdf_text_extraction', purpose='Índice de búsqueda; cotejar cotas con imagen')
    for stem, target in selection['photos'].items():
        source = by_path[f'references/avanti-s/photos/{stem}.jpg']
        copy(source, f'images/{target}.jpg', 'Perspectiva de estudio; sin escala métrica transferible')
    fuel_names = ['kit-deposito-racores', 'pendulo-tubo-flexible', 'toma-regla-no-calibrada',
                  'tapon-tubo-rigido', 'apriete-tapon', 'conjunto-pendulo', 'introduccion-toma',
                  'tubo-rigido-union', 'tubo-regla-no-calibrada', 'montaje-toma-rigida',
                  'cierre-tapon-01', 'cierre-tapon-02', 'conexion-exterior']
    for source in originals:
        path = Path(source['path'])
        if path.suffix != '.jpg' or '/new-sources/' not in source['path']:
            continue
        if source['group'] == 'fuel':
            number = int(path.stem.rsplit('-', 1)[1])
            target = f'06-installation/tanque-a200-{number:02d}-{fuel_names[number-1]}.jpg'
        else:
            number = int(path.stem.rsplit('-', 1)[1])
            target = f'09-optional-vector/vectorial-fuera-baseline-secuencia-{number:02d}.jpg'
        copy(source, 'images/' + target, source['purpose'])

    source = by_path['references/avanti-s/manuals/avanti-s-200-assembly.pdf']
    pages = OUT / 'assembly-pages'
    pages.mkdir(exist_ok=True)
    if len(list(pages.glob('a200-montaje-p-*.jpg'))) != 91:
        subprocess.run(['pdftoppm', '-r', '60', '-jpeg', '-jpegopt', 'quality=85',
                        str(ROOT / source['path']), str(pages / 'a200-montaje-p')], check=True)
    for page in range(1, 92):
        record(pages / f'a200-montaje-p-{page:02d}.jpg', source,
               operation='pdf_page_render', pdf_page=page, dpi=60, purpose='Página completa, contexto')
    method = selection['crop_method']
    for entry in selection['steps']:
        dest = OUT / 'details' / (f"{entry['name']}-p{entry['page']:03d}-s{entry['step']:03d}.png")
        dest.parent.mkdir(parents=True, exist_ok=True)
        x, y, w, h = method[entry['half'] + '_box_px']
        subprocess.run(['pdftoppm', '-f', str(entry['page']), '-l', str(entry['page']),
                        '-r', str(method['dpi']), '-x', str(x), '-y', str(y), '-W', str(w), '-H', str(h),
                        '-singlefile', '-png', str(ROOT / source['path']), str(dest.with_suffix(''))], check=True)
        record(dest, source, operation='pdf_region_render', pdf_page=entry['page'],
               step=entry['step'], box_px=[x, y, w, h], dpi=method['dpi'],
               purpose=entry['name'].split('/')[-1], caveat='Perspectiva y rótulos originales; cotas solo donde están dibujadas')
    for key, page, name in [('a200-intro', 4, 'recorridos-mandos'), ('a200-intro', 5, 'datum-cg'),
                            ('p100-drawing', 1, 'p100rx-cotas'), ('p100-2017', 15, 'p100rx-tabla-catalogo')]:
        source = by_path[data['sources'][key]['path']]
        dest = OUT / 'details' / (name + '.png')
        subprocess.run(['pdftoppm', '-f', str(page), '-l', str(page), '-r', '120', '-singlefile',
                        '-png', str(ROOT / source['path']), str(dest.with_suffix(''))], check=True)
        record(dest, source, operation='pdf_page_render', pdf_page=page, dpi=120, purpose=name)

    esc = html.escape
    style = ('body{font:16px system-ui;margin:2rem;background:#eef1f4;color:#18222c}'
             'main{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:1rem}'
             'article{background:white;padding:1rem;border-radius:8px;overflow-wrap:anywhere}'
             'img{width:100%;height:220px;object-fit:contain}small{display:block}'
             'input{font:inherit;padding:.7rem;width:min(90%,600px)}nav{margin:1rem 0}a{color:#174f87}')
    parts = ['<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width">',
             '<title>Avanti S · mesa de referencias</title><style>' + style + '</style>',
             '<h1>Avanti S A200 · mesa de referencias</h1>',
             '<p>2000 × 2220 mm · P100-RX 2017 · originales y derivados para estudio local.</p>',
             '<nav><a href="study-board.html">Dimensiones y flaps interactivos</a> · '
             '<a href="../index.html">Archivo de originales</a> · <a href="catalog.json">Procedencia y recortes</a></nav>',
             '<p>Documentos / imágenes / detalles / 91 páginas de montaje. Los archivos se nombran por componente; '
             'vectorial y otras variantes se archivan aparte. Las fotografías tienen perspectiva.</p>',
             '<label>Filtrar por nombre, componente o paso <input id="filter" type="search" placeholder="flap, p022, tanque, p100…"></label><main>']
    for item in records:
        dest = ROOT / item['path']
        rel = str(dest.relative_to(OUT))
        src_rel = os.path.relpath(ROOT / item['source'], OUT)
        page = item.get('pdf_page')
        original_href = src_rel + (f'#page={page}' if page else '')
        parts.append('<article data-key="' + esc((rel + ' ' + item['purpose']).lower()) + '">' +
                     (f'<a href="{esc(rel)}"><img loading="lazy" src="{esc(rel)}" alt="{esc(dest.stem)}"></a>'
                      if dest.suffix in ['.jpg', '.png'] else '') +
                     f'<h3><a href="{esc(rel)}">{esc(dest.name)}</a></h3><p>{esc(item["purpose"])}</p>' +
                     f'<small>{esc(rel)}</small><small>PDF p.{page or "—"} · paso {item.get("step", "—")}</small>' +
                     f'<a href="{esc(original_href)}">Original con contexto</a> · <a href="{esc(item["source_url"])}">Fuente</a></article>')
    parts.append('</main><script>document.querySelector("#filter").addEventListener("input",e=>'
                 '{let q=e.target.value.toLowerCase();document.querySelectorAll("article").forEach(a=>'
                 'a.hidden=!a.dataset.key.includes(q));});</script></html>')
    (OUT / 'index.html').write_text('\n'.join(parts))
    template = (HERE / 'study-board.html').read_text()
    (OUT / 'study-board.html').write_text(template.replace('__STUDY_DATA__', json.dumps(data, ensure_ascii=False)))
    catalog = dict(schema='openrc-avanti-organized-v1', date='2026-10-05',
                   tools={'pdftoppm': subprocess.run(['pdftoppm', '-v'], capture_output=True, text=True).stderr.splitlines()[0]},
                   preservation='Original files unchanged; copies byte identical; PDF crops retain annotations', items=records)
    save(OUT / 'catalog.json', catalog)
    save(ROOT / 'docs/research/avanti-s-organized-catalog.json', catalog)
    paths = [str(p.relative_to(ROOT)) for p in (ROOT / 'references/avanti-s').rglob('*') if p.is_file()]
    ignored = subprocess.run(['git', 'check-ignore', '--stdin'], cwd=ROOT, input='\n'.join(paths)+'\n',
                             text=True, capture_output=True, check=True).stdout.splitlines()
    assert set(paths) == set(ignored)
    assert not subprocess.check_output(['git', 'ls-files', 'references/avanti-s'], cwd=ROOT)
    for item in originals:
        assert digest(ROOT / item['path']) == item['sha256']
    print(f'Archive OK: {len(originals)} originals unchanged; {len(records)} catalog entries; all references ignored.')


if __name__ == '__main__':
    main()
