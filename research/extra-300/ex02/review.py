"""EX-02 visual review of the Extra 300S .60 preview: metrics, plan overlays, contact sheets, gallery.

Input: a capture directory from `capture.sh --suite all` (manifest.json + PNGs).
  python3 research/extra-300/ex02/review.py CAPTURE_DIR
Writes into CAPTURE_DIR/review/: review.json (metrics), overlay_*.png, sheet_*.png and review.html.
Plan overlays need the git-ignored raster cache written by research/extra-300/ex01/measure.py; without it they
are skipped and reported as such. Requires Pillow and NumPy (system versions are recorded in review.json).
"""
import html
import json
import sys
from pathlib import Path

import numpy as np
import PIL
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CACHE = ROOT / 'references/extra-300/inspection/ex01-cache'
IN = 0.0254
SKY = np.array([155, 206, 240])
Image.MAX_IMAGE_PIXELS = None


def silhouette(image):
    """Pixels that are not the flat sky colour (the inspector has no ground or haze)."""
    a = np.asarray(image.convert('RGB')).astype(int)
    return np.abs(a - SKY).max(axis=2) > 18


def mask_metrics(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return {'pixels': 0}
    h, w = mask.shape
    return {
        'pixels': int(len(xs)),
        'bbox_px': [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
        'width_px': int(xs.max() - xs.min() + 1),
        'height_px': int(ys.max() - ys.min() + 1),
        'touches_border': bool(mask[0].any() or mask[-1].any() or mask[:, 0].any() or mask[:, -1].any()),
    }


def interp(rows, z, column):
    zs = [r[0] for r in rows]
    return float(np.interp(z, zs, [r[column] for r in rows]))


def fidelity(scale_dir, geometry):
    """Silhouette edges of the orthographic scale views against geometry.json, in millimetres."""
    side = silhouette(Image.open(scale_dir / 'scale_side_left.png'))
    H, W = side.shape
    k = H / 1.9  # px per metre: the orthographic size is the vertical extent
    cx, cy = W / 2, H / 2
    out = {'image_size': [W, H], 'px_per_m': round(k, 3), 'pixel_mm': round(1000 / k, 3)}
    stations, canopy = geometry['fuselage_stations'], geometry['canopy']['top']
    rows = []
    for z, half_width, top, bottom, *_ in stations[1:]:
        if -0.22 < z < 0.06 or z > 0.79:
            continue  # main gear legs, pants and the rudder/tail wheel extend the silhouette there
        x = int(round(cx + (z - 0.25) * k))
        column = np.nonzero(side[:, x])[0]
        expected_top = max(top, float(np.interp(z, [c[0] for c in canopy], [c[1] for c in canopy]))) if canopy[0][0] <= z <= canopy[-1][0] else top
        row = {'z_m': z, 'bottom_mm': round(((cy - column.max() - 1) / k - bottom) * 1000, 2)}
        if z < geometry['tail']['fin_root_le'][0]:  # aft of the fin LE the fin is the top of the silhouette
            row['top_mm'] = round(((cy - column.min()) / k - expected_top) * 1000, 2)
        rows.append(row)
    out['side_profile_residuals'] = rows
    top_view = silhouette(Image.open(scale_dir / 'scale_top.png'))
    rows = []
    for z, half_width, *_ in stations[1:]:
        if -0.2 < z < 0.32 or z > 0.64:
            continue  # wing, wheel pants and horizontal tail widen the silhouette there
        y = int(round(cy + (z - 0.25) * k))
        row = np.nonzero(top_view[y])[0]
        rows.append({'z_m': z, 'half_width_mm': round(((row.max() - row.min() + 1) / 2 / k - half_width) * 1000, 2)})
    out['top_width_residuals'] = rows
    w = geometry['wing']
    half = w['span'] / 2
    rows = []
    for span in [0.22, 0.3, 0.4, 0.5, 0.6, 0.7, 0.78]:
        chord = w['root_chord'] + (w['tip_chord'] - w['root_chord']) * span / half
        le = w['le_z_root'] + (w['le_z_tip'] - w['le_z_root']) * span / half
        for sign in (-1, 1):
            x = int(round(cx + sign * span * k))
            column = np.nonzero(top_view[:, x])[0]
            column = column[(column > cy + (le - 0.25) * k - 0.1 * k) & (column < cy + (le + chord - 0.25) * k + 0.1 * k)]
            rows.append({'span_m': sign * span, 'le_mm': round((0.25 + (column.min() - cy) / k - le) * 1000, 2),
                         'te_mm': round((0.25 + (column.max() + 1 - cy) / k - le - chord) * 1000, 2)})
    out['wing_edge_residuals'] = rows
    values = [abs(v) for group in ('side_profile_residuals', 'top_width_residuals', 'wing_edge_residuals')
              for r in out[group] for key, v in r.items() if key.endswith('_mm')]
    out['max_abs_mm'] = float(max(values))
    out['allowance_mm'] = round(max(2.5 * 1000 / k, 2.5), 2)  # 2.5 px of edge quantisation/antialiasing, at least 2.5 mm
    out['ok'] = bool(out['max_abs_mm'] <= out['allowance_mm'])
    return out


def overlay(render_path, sheet_path, box, affine, keep, label, output):
    """Draw plan ink (red) over a pale copy of the render, using an affine map from render to plan pixels."""
    render = Image.open(render_path).convert('RGB')
    size = render.size
    with Image.open(sheet_path) as sheet:
        crop = sheet.crop(box).convert('L')
    a, b, c, d, e, f = affine
    warped = crop.transform(size, Image.AFFINE, (a, b, c - box[0], d, e, f - box[1]), resample=Image.BILINEAR, fillcolor=255)
    ink = np.asarray(warped) < 160
    yy, xx = np.mgrid[0:size[1], 0:size[0]]
    ink &= keep(xx, yy)
    base = np.asarray(render).astype(float)
    pale = (255 - (255 - base) * 0.45).astype(np.uint8)
    edge = silhouette(render)
    edge = edge & ~(np.roll(edge, 1, 0) & np.roll(edge, -1, 0) & np.roll(edge, 1, 1) & np.roll(edge, -1, 1))
    pale[edge] = [20, 90, 220]
    pale[ink] = [215, 25, 30]
    image = Image.fromarray(pale)
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, size[0], 22], fill=(255, 255, 255))
    draw.text((6, 5), label + '   red: plan scan   blue: render silhouette', fill=(0, 0, 0))
    image.save(output)


def overlays(scale_dir, out_dir):
    if not (CACHE / 'sheet-000.png').exists():
        return {'skipped': f'no raster cache in {CACHE.relative_to(ROOT)}; run research/extra-300/ex01/measure.py'}
    picks = json.loads((ROOT / 'research/extra-300/ex01/picks.json').read_text())
    metrology = json.loads((ROOT / 'research/extra-300/ex01/metrology.json').read_text())
    s_w = metrology['scales']['wing_sheet_px_per_in']
    s_f = metrology['scales']['fuselage_sheet_px_per_in']
    with Image.open(scale_dir / 'scale_top.png') as probe:
        W, H = probe.size
    k = H / 1.9
    cx, cy = W / 2, H / 2
    le_x, _ = picks['fuselage_side']['root_airfoil_le']['px']
    y_axis = picks['fuselage_side']['spinner_tip']['px'][1]
    xs, ys = np.array(metrology['wing_fit']['samples_le']).T
    slope, intercept = np.polyfit(xs, ys, 1)
    le_2d = intercept + slope * picks['wing_sheet']['rib_2D_x']['px']
    x_cl = picks['wing_sheet']['centerline_x']['px']
    stab = picks['stab_full_size']
    root_le_z = metrology['adopted_model_values']['stab']['root_le_z']
    ff, ww = s_f / (IN * k), s_w / (IN * k)
    made = {}
    jobs = [
        ('overlay_side_fuselage_sheet.png', 'scale_side_left.png', 'sheet-000.png', (700, 1200, 17800, 8100),
         (ff, 0, le_x + 4.125 * s_f + (0.25 - cx / k) * s_f / IN, 0, ff, y_axis - cy * ff),
         lambda x, y: np.ones_like(x, bool), 'side view vs EXT6P02 side view (scale 300.56 px/in)'),
        ('overlay_top_wing_sheet.png', 'scale_top.png', 'sheet-001.png', (0, 6800, 15400, 13600),
         (-ww, 0, x_cl + cx * ww, 0, ww, le_2d + (4.125 + (0.25 - cy / k) / IN) * s_w),
         lambda x, y: x < cx - 0.02 * k, 'top view, left wing vs EXT6P01 full-size wing (ruler 399.88 px/in)'),
        ('overlay_top_stab_sheet.png', 'scale_top.png', 'sheet-001.png', (14400, 900, 18471, 11800),
         (0, ww, stab['root_le_x']['px'] + (0.25 - cy / k - root_le_z) * s_w / IN, -ww, 0, stab['centerline_y']['px'] + cx * ww),
         lambda x, y: y > cy + (0.6 - 0.25) * k, 'top view, stab/elevator vs full-size drawing on EXT6P01'),
        ('overlay_top_fuselage_bottom_view.png', 'scale_top.png', 'sheet-000.png', (0, 10200, 17000, 13000),
         (0, ff, le_x - 32 + (4.125 + (0.25 - cy / k) / IN) * s_f, ff, 0, 11600 - cx * ff),
         lambda x, y: np.abs(x - cx) < 0.11 * k, 'top view, fuselage vs EXT6P02 bottom view (mirror-symmetric)'),
    ]
    for name, render, sheet, box, affine, keep, label in jobs:
        overlay(scale_dir / render, CACHE / sheet, box, affine, keep, label, out_dir / name)
        made[name] = label
    # Enlarged regions, in model metres: side (z0, z1, y0, y1) and top (x0, x1, z0, z1).
    zooms = {
        'overlay_side_fuselage_sheet.png': {'nose': (-0.47, -0.08, -0.28, 0.1), 'canopy': (0.04, 0.44, -0.04, 0.16),
                                            'tail': (0.6, 0.97, -0.1, 0.3), 'gear': (-0.22, 0.06, -0.28, -0.06)},
        'overlay_top_wing_sheet.png': {'wing': (-0.83, 0.02, -0.16, 0.32), 'tip': (-0.83, -0.55, -0.12, 0.2)},
        'overlay_top_stab_sheet.png': {'stab': (-0.34, 0.34, 0.62, 0.9)},
        'overlay_top_fuselage_bottom_view.png': {'nose': (-0.12, 0.12, -0.46, -0.05), 'aft': (-0.12, 0.12, 0.3, 0.84)},
    }
    for name, regions in zooms.items():
        with Image.open(out_dir / name) as image:
            for region, (a0, a1, b0, b1) in regions.items():
                if name.startswith('overlay_side'):
                    box = (cx + (a0 - 0.25) * k, cy - b1 * k, cx + (a1 - 0.25) * k, cy - b0 * k)
                else:
                    box = (cx + a0 * k, cy + (b0 - 0.25) * k, cx + a1 * k, cy + (b1 - 0.25) * k)
                zoom = name.replace('.png', f'_zoom_{region}.png')
                image.crop(tuple(int(round(v)) for v in box)).save(out_dir / zoom)
                made[zoom] = f'{made[name]}: {region}'
    return made


def contact_sheet(paths, out, columns=4, tile=(400, 225), crop=None, labels=True):
    rows = (len(paths) + columns - 1) // columns
    sheet = Image.new('RGB', (columns * tile[0], rows * (tile[1] + (16 if labels else 0))), 'white')
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(paths):
        image = Image.open(path).convert('RGB')
        if crop:
            image = image.crop(crop(image))
        image = image.resize(tile, Image.NEAREST if crop else Image.LANCZOS)
        x, y = (i % columns) * tile[0], (i // columns) * (tile[1] + (16 if labels else 0))
        sheet.paste(image, (x, y + (16 if labels else 0)))
        if labels:
            draw.text((x + 4, y + 2), path.stem, fill=(0, 0, 0))
    sheet.save(out)


def main():
    capture_dir = Path(sys.argv[1]).resolve()
    manifest = json.loads((capture_dir / 'manifest.json').read_text())
    geometry = json.loads((ROOT / 'assets/aircraft/extra-300s-60/geometry.json').read_text())
    out_dir = capture_dir / 'review'
    out_dir.mkdir(exist_ok=False)
    metrics = {}
    for record in manifest['captures']:
        metrics[record['file']] = mask_metrics(silhouette(Image.open(capture_dir / record['file'])))
    cropped = [f for f, m in metrics.items() if m.get('touches_border') and not f.startswith('detail_')]
    distance = {f: {'span_px': m['width_px'], 'height_px': m['height_px'], 'pixels': m['pixels']}
                for f, m in metrics.items() if f.startswith('distance_')}
    scale_dir = capture_dir / 'scale_hr' if (capture_dir / 'scale_hr' / 'scale_top.png').exists() else capture_dir
    report = {
        'format': 'openrc-visual-review v1', 'step': 'EX-02 review',
        'captures': len(manifest['captures']), 'visual_revision': manifest['visual_revision'],
        'geometry_sha256': manifest['geometry_sha256'], 'throws_deg': manifest['throws_deg'],
        'tools': {'python_pillow': PIL.__version__, 'numpy': np.__version__},
        'cropped_non_detail_views': cropped,
        'distance_footprint': distance,
        'scale_views': str(scale_dir.relative_to(capture_dir)) or '.',
        'render_vs_geometry': fidelity(scale_dir, geometry),
        'plan_overlays': overlays(scale_dir, out_dir),
        'per_image': metrics,
    }
    names = [r['file'] for r in manifest['captures']]
    groups = {
        'inspection': [n for n in names if n.startswith('inspection_')],
        'orbit_el-25': [n for n in names if n.startswith('orbit_el-25')],
        'orbit_el+10': [n for n in names if n.startswith('orbit_el+10')],
        'orbit_el+40': [n for n in names if n.startswith('orbit_el+40')],
        'detail_a': [n for n in names if n.startswith('detail_')][:12],
        'detail_b': [n for n in names if n.startswith('detail_')][12:],
    }
    for group, files in groups.items():
        if files:
            contact_sheet([capture_dir / f for f in files], out_dir / f'sheet_{group}.png')

    def around(image):  # distance views: a 160x90 window around the airplane, enlarged 4x without smoothing
        ys, xs = np.nonzero(silhouette(image))
        cx, cy = int(xs.mean()), int(ys.mean())
        return (cx - 80, cy - 45, cx + 80, cy + 45)
    distance_files = [capture_dir / n for n in names if n.startswith('distance_')]
    if distance_files:
        contact_sheet(distance_files, out_dir / 'sheet_distance_zoom4x.png', columns=4, tile=(640, 360), crop=around)
    (out_dir / 'review.json').write_text(json.dumps(report, indent=1) + '\n')
    sections = ''.join(f'<h2>{html.escape(g)}</h2><img src="sheet_{g}.png">' for g in groups if groups[g])
    sections += '<h2>distance (4x, nearest neighbour)</h2><img src="sheet_distance_zoom4x.png">'
    sections += ''.join(f'<h2>{html.escape(label)}</h2><img src="{name}">' for name, label in report['plan_overlays'].items() if name.endswith('.png'))
    (out_dir / 'review.html').write_text(
        '<!doctype html><meta charset="utf-8"><title>Extra 300S preview review</title>'
        '<style>body{font:14px sans-serif;margin:16px;background:#fff;color:#111}img{max-width:100%;border:1px solid #ccc}</style>'
        f'<h1>Extra 300S .60 preview: {len(names)} captures</h1><pre>{html.escape(json.dumps({k: report[k] for k in ("throws_deg", "cropped_non_detail_views", "distance_footprint")}, indent=1))}</pre>'
        f'{sections}\n')
    fid = report['render_vs_geometry']
    print(f"{len(names)} captures; render vs geometry max {fid['max_abs_mm']:.2f} mm (allowance {fid['allowance_mm']} mm, ok={fid['ok']}); "
          f"cropped views: {cropped or 'none'}; overlays: {list(report['plan_overlays'])}")
    print(out_dir / 'review.html')


if __name__ == '__main__':
    main()
