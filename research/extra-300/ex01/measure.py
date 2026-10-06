"""EX-01: reproducible metrology of the Great Planes Extra 300S .60 (GPMA0236) plan.

Reads the local, git-ignored plan/manual PDFs (SHA-256 checked), the manual picks in
picks.json, and writes metrology.json: scales, automatic fits, reserved checks and the
model-frame values adopted by assets/aircraft/extra-300s-60/geometry.json.

Requires poppler-utils (pdfimages), Pillow and NumPy. Raster cache stays in references/.
  python3 research/extra-300/ex01/measure.py           # write metrology.json
  python3 research/extra-300/ex01/measure.py --check   # fail if metrology.json is stale
"""
import argparse
import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CACHE = ROOT / 'references/extra-300/inspection/ex01-cache'
IN = 0.0254
Image.MAX_IMAGE_PIXELS = None


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def sheets(picks):
    plan = ROOT / picks['sources']['plan']['path']
    for source in picks['sources'].values():
        path = ROOT / source['path']
        assert path.exists(), f'missing local source {path}: recover it from the Outerzone oz10977 page'
        assert sha256(path) == source['sha256'], f'unexpected source hash: {path}'
    CACHE.mkdir(parents=True, exist_ok=True)
    if not (CACHE / 'sheet-001.png').exists():
        subprocess.run(['pdfimages', '-png', str(plan), str(CACHE / 'sheet')], check=True)
    return Image.open(CACHE / 'sheet-000.png'), Image.open(CACHE / 'sheet-001.png')


def black(image, box):
    return ~np.array(image.crop(box))  # mode 1: True = white


def column_runs(column, y0, min_len=12, max_len=40):
    runs, y, n = [], 0, len(column)
    while y < n:
        if column[y]:
            start = y
            while y < n and column[y]:
                y += 1
            if min_len <= y - start <= max_len:
                runs.append(y0 + start + (y - start - 1) / 2)
        else:
            y += 1
    return runs


def ruler_scale(wing):
    # Inch band of the printed ruler: full-height ticks every inch.
    band = black(wing, (0, 14000, wing.width, 14092))
    columns = np.where(band.sum(0) >= 85)[0]
    groups = np.split(columns, np.where(np.diff(columns) > 3)[0] + 1)
    centers = np.array([g.mean() for g in groups if len(g)])
    # Longest chain of ~400 px spacing; the ruler border and label strokes break the chain.
    chains = []
    for start in centers:
        chain = [start]
        for c in centers:
            if abs(c - chain[-1] - 400) < 10:
                chain.append(c)
        chains.append(chain)
    ticks = np.array(max(chains, key=len))
    assert len(ticks) == 37, len(ticks)
    fit = np.polyfit(np.arange(37), ticks, 1)
    residual = ticks - np.polyval(fit, np.arange(37))
    return float(fit[0]), float(np.abs(residual).max()), [round(float(t), 1) for t in ticks[[0, 18, 36]]]


def edge_fit(wing, anchors, columns, tolerance=30):
    (xa, ya), (xb, yb) = anchors
    region = black(wing, (0, 6800, wing.width, 13400))
    samples = []
    for x in columns:
        expected = ya + (yb - ya) * (x - xa) / (xb - xa)
        runs = [r for r in column_runs(region[:, x], 6800) if abs(r - expected) < tolerance]
        if runs:  # a crossing rib or label can hide the edge in one column
            samples.append((x, min(runs, key=lambda r: abs(r - expected))))
    assert len(samples) >= len(columns) - 2, f'edge found in only {len(samples)} of {len(columns)} columns'
    xs, ys = np.array(samples).T
    slope, intercept = np.polyfit(xs, ys, 1)
    residual = ys - (slope * xs + intercept)
    return float(slope), float(intercept), float(np.abs(residual).max()), samples


def bottom_half_widths(fuselage, columns, center, min_len=10):
    region = black(fuselage, (0, 10300, fuselage.width, 12900))
    out = []
    for x in columns:
        column = region[:, x - 1:x + 2].all(1)
        runs, y = [], 0
        while y < len(column):
            if column[y]:
                start = y
                while y < len(column) and column[y]:
                    y += 1
                if min_len <= y - start < 40:
                    runs.append((10300 + start, 10300 + y - 1))
            else:
                y += 1
        best = None
        for a in runs:
            for b in runs:
                if b[0] > a[0] and abs((a[0] + b[1]) / 2 - center) < 20:
                    half = (b[1] - a[0]) / 2
                    best = half if best is None or half > best else best
        assert best is not None, x
        out.append((x, best))
    return out


def interp(points, x):
    points = sorted(points)
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    raise ValueError(f'{x} outside {points[0][0]}..{points[-1][0]}')


def r6(v):
    return round(float(v), 6)


def pant_profile(f, z_side, y_side, samples=24):
    """[z, top_y, bottom_y] rows along the pant, from its picked side outline (nose and tail rows have zero height).
    Cosine spacing puts more rows at the blunt nose and the truncated tail, where the outline turns fastest."""
    top, bottom = f['wheel_pant_outline']['top_px'], f['wheel_pant_outline']['bottom_px']
    x0, x1 = top[0][0], max(top[-1][0], bottom[-1][0])
    rows = []
    for i in range(samples + 1):
        x = x0 + (x1 - x0) * (1 - math.cos(math.pi * i / samples)) / 2
        t = interp(top, min(x, top[-1][0])) if x <= top[-1][0] else interp([bottom[-2], bottom[-1]], x)
        b = interp(bottom, x)
        rows.append([r6(z_side(x)), r6(y_side(min(t, b))), r6(y_side(b))])
    return rows


def main_leg(f, z_side, y_side):
    """Strap edges at the fuselage bottom (root) and at the pant top (tip): [front_z, rear_z, y]."""
    e = f['main_leg_edges']
    def at(edge, y):
        (xa, ya), (xb, yb) = e[edge]
        return xa + (xb - xa) * (y - ya) / (yb - ya)
    root_y = interp(f['bottom_profile']['px'], (at('front_px', 6150) + at('rear_px', 6150)) / 2)
    tip_y = f['wheel_pant_outline']['top_px'][4][1] + 10  # just inside the pant top, above the axle block
    return {'root': [r6(z_side(at('front_px', root_y))), r6(z_side(at('rear_px', root_y))), r6(y_side(root_y))],
            'tip': [r6(z_side(at('front_px', tip_y))), r6(z_side(at('rear_px', tip_y))), r6(y_side(tip_y))]}


def measure(picks):
    fuselage, wing = sheets(picks)
    w = picks['wing_sheet']
    s_w, ruler_residual, ruler_ticks = ruler_scale(wing)

    edge_columns = list(range(3700, 14200, 800))
    le_slope, le_icpt, le_res, le_samples = edge_fit(wing, w['le_anchor']['px'], edge_columns)
    te_slope, te_icpt, te_res, te_samples = edge_fit(wing, w['te_anchor']['px'], edge_columns)
    hinge_anchor = [[x, te_icpt + te_slope * x - w['hinge_offset_anchor_px']['px']] for x in (6900, 14100)]
    hinge_slope, hinge_icpt, hinge_res, hinge_samples = edge_fit(wing, hinge_anchor, list(range(6900, 14200, 800)), 40)

    x_cl = w['centerline_x']['px']
    le = lambda x: le_icpt + le_slope * x
    te = lambda x: te_icpt + te_slope * x
    half_span_in = (w['tip_x']['px'] - x_cl) / s_w
    x2d = w['rib_2D_x']['px']
    root_chord_cl_in = (te(x_cl) - le(x_cl)) / s_w
    tip_chord_in = (te(w['tip_x']['px']) - le(w['tip_x']['px'])) / s_w
    chord_2d_in = (te(x2d) - le(x2d)) / s_w
    area_in2 = (root_chord_cl_in + tip_chord_in) * half_span_in
    cg_marker_in = (w['cg_marker_y']['px'] - le(x2d)) / s_w
    taper = tip_chord_in / root_chord_cl_in
    mac_in = 2 / 3 * root_chord_cl_in * (1 + taper + taper ** 2) / (1 + taper)
    mac_span_in = 2 * half_span_in / 6 * (1 + 2 * taper) / (1 + taper)
    mac_le_aft_of_2d_in = (le(x_cl + mac_span_in * s_w) - le(x2d)) / s_w
    hinge_offset_in = float(np.mean([te(x) - (hinge_icpt + hinge_slope * x) for x in (6900, 14100)])) / s_w

    # Model frame: metres, +X right, +Y up, -Z nose. Origin: symmetry plane, nominal CG station
    # (4-1/8 in aft of the LE at rib 2D, manual p43) and spinner-axis height in the side view.
    cg_aft_in = 4.125
    f = picks['fuselage_side']
    le_side, te_side = f['root_airfoil_le']['px'], f['root_airfoil_te']['px']
    s_f = (te_side[0] - le_side[0]) / chord_2d_in
    y_axis = f['spinner_tip']['px'][1]
    z_side = lambda x: ((x - le_side[0]) / s_f - cg_aft_in) * IN
    y_side = lambda y: -(y - y_axis) / s_f * IN
    z_wing = lambda y: ((y - le(x2d)) / s_w - cg_aft_in) * IN
    span_wing = lambda x: (x - x_cl) / s_w * IN

    b = picks['fuselage_bottom']
    auto_widths = bottom_half_widths(fuselage, b['auto_width_columns_px'], b['centerline_y']['px'])
    offset = b['x_offset_to_side_px']['px']
    cowl_hw = b['cowl_half_width']['px']
    width_points = [(1880, cowl_hw), (f['cowl_rear_x']['px'], cowl_hw)]
    width_points += [(x + offset, hw) for x, hw in auto_widths]
    post = b['tail_post_half_width']['px']
    width_points += [(15700 + offset, post), (b['tail_post_end_x']['px'] + offset, post)]
    top, bottom = f['top_profile']['px'], f['bottom_profile']['px']
    station_x = [1880, 2340, 2620, 3300, 4100, 4620, 5650, 6200, 7200, 7760, 8500, 9300, 10225, 10850, 12100, 13000, 13700, 15000, b['tail_post_end_x']['px'] + offset]
    stations = [[r6(z_side(x)), r6(interp(width_points, x) / s_f * IN), r6(y_side(interp(top, x))), r6(y_side(interp(bottom, x)))] for x in station_x]

    airfoil = []
    c_px = te_side[0] - le_side[0]
    for x, upper, lower in f['root_airfoil_outline']['x_upper_lower_px']:
        airfoil.append([r6((x - le_side[0]) / c_px), r6((lower - upper) / 2 / c_px), r6(((upper + lower) / 2 - le_side[1]) / c_px)])

    st = picks['stab_full_size']
    st_cl = st['centerline_y']['px']
    st_half_span_in = ((st_cl - st['upper_tip_y']['px']) + (st['lower_tip_y']['px'] - st_cl)) / 2 / s_w
    st_root_le = st['root_le_x']['px']
    st_in = lambda px: (px - st_root_le) / s_w
    stab_root_le_z = z_side(f['stab_le_x']['px'])
    stab = {
        'half_span': r6(st_half_span_in * IN),
        'root_le_z': r6(stab_root_le_z),
        'y': r6(y_side(f['stab_center_y']['px'])),
        'hinge_z': r6(stab_root_le_z + st_in(st['hinge_x']['px']) * IN),
        'tip_le_z': r6(stab_root_le_z + st_in(st['tip_le_x']['px']) * IN),
        'elevator_tip_te_z': r6(stab_root_le_z + st_in(st['elevator_tip_te_x']['px']) * IN),
        'elevator_root_corner': [r6((st_cl - st['elevator_root_corner']['px'][1]) / s_w * IN), r6(stab_root_le_z + st_in(st['elevator_root_corner']['px'][0]) * IN)],
        'elevator_inner_hinge': [r6((st_cl - st['elevator_inner_hinge']['px'][1]) / s_w * IN), r6(stab_root_le_z + st_in(st['elevator_inner_hinge']['px'][0]) * IN)],
    }
    stab_chord_full_in = st_in(st['elevator_root_corner']['px'][0])
    stab_chord_side_in = (f['stab_te_x']['px'] - f['stab_le_x']['px']) / s_f

    side_point = lambda key: [r6(z_side(f[key]['px'][0])), r6(y_side(f[key]['px'][1]))]
    hinge_z = r6(z_side(f['rudder_hinge_x']['px']))
    fin = {
        'hinge_z': hinge_z,
        'root_le': side_point('fin_root_le'),
        'top_y': r6(y_side(f['fin_top_y']['px'])),
        'le_top_z': r6(z_side(f['fin_le_top_x']['px'])),
        'rudder_top_te_z': r6(z_side(f['rudder_top_te_x']['px'])),
        'balance_bottom_y': r6(y_side(f['balance_bottom_y']['px'])),
        'balance_front_z': r6(z_side(f['balance_front_x']['px'])),
        'rudder_te_low': side_point('rudder_te_low'),
        'rudder_bottom_corner': side_point('rudder_bottom_corner'),
        'rudder_bottom_hinge': side_point('rudder_bottom_hinge'),
    }

    p47 = picks['two_view_p47']
    p47_long = (f['rudder_te_max']['px'][0] - f['spinner_tip']['px'][0]) / (p47['rudder_te_x_pt'] - p47['spinner_tip_x_pt'])
    p47_side = lambda pt: (f['spinner_tip']['px'][0] + (pt[0] - p47['spinner_tip_x_pt']) * p47_long, y_axis + (pt[1] - 636.7) * p47_long)
    h47 = p47['holdout_side_points_pt']
    p47_residuals_in = {
        'cowl_joint_x': (f['spinner_tip']['px'][0] + (h47['cowl_joint_x'] - p47['spinner_tip_x_pt']) * p47_long - f['cowl_rear_x']['px']) / s_f,
        'main_axle': [(p47_side(h47['main_axle'])[i] - f['main_axle']['px'][i]) / s_f for i in (0, 1)],
        'tailwheel_axle': [(p47_side(h47['tailwheel_axle'])[i] - f['tailwheel_axle']['px'][i]) / s_f for i in (0, 1)],
        'rudder_hinge_x': (f['spinner_tip']['px'][0] + (h47['rudder_hinge_x'] - p47['spinner_tip_x_pt']) * p47_long - f['rudder_hinge_x']['px']) / s_f,
    }
    p47_width = p47['fuselage_width_at_wing_pt']['value']
    p47_canopy = p47['canopy_top_view_y_pt']['value']
    wing_root_halfwidth_in = interp(width_points, le_side[0]) / s_f

    length_in = (f['rudder_te_max']['px'][0] - f['spinner_tip']['px'][0]) / s_f
    spinner_dia_in = (f['spinner_back_top_bottom_y']['px'][1] - f['spinner_back_top_bottom_y']['px'][0]) / s_f
    spinner_to_firewall_in = (f['firewall_front_x']['px'] - f['spinner_back_x']['px']) / s_f

    def check(name, measured, reference, tolerance, unit, source, role):
        return {'name': name, 'measured': round(measured, 4), 'reference': reference, 'error': round(measured - reference, 4),
                'relative': round((measured - reference) / reference, 5), 'tolerance': tolerance, 'unit': unit,
                'ok': abs(measured - reference) <= tolerance, 'source': source, 'role': role}

    checks = [
        check('span', 2 * half_span_in, 64.0, 0.64, 'in', 'plan title block and manual p43: 64 in', 'reserved: not used to calibrate'),
        check('wing_area_trapezoid_to_centreline', area_in2, 744.0, 7.44, 'in^2', 'plan title block: 744 sq in', 'reserved: not used to calibrate'),
        check('overall_length_spinner_to_rudder_te', length_in, 54.25, 0.54, 'in', 'plan title block: 54-1/4 in', 'reserved: selects the side-view chord interpretation (centreline chord would give a 5.6 % error)'),
        check('cg_marker_aft_of_2D_le', cg_marker_in, 4.125, 0.06, 'in', 'manual p43 / plan CG note: 4-1/8 in at rib 2D', 'reserved: locates 2D on the fuselage side'),
        check('spinner_diameter', spinner_dia_in, 2.5, 0.1, 'in', 'plan label and manual p3: 2-1/2 in spinner', 'reserved'),
        check('spinner_back_to_firewall', spinner_to_firewall_in, 6.25, 0.12, 'in', 'manual p32: drive washer 6-1/4 in from firewall', 'reserved'),
        check('stab_root_chord_side_vs_full_size', stab_chord_side_in, stab_chord_full_in, 0.1, 'in', 'full-size stab drawing on the wing sheet', 'reserved: confirms side-view scale aft of the wing'),
    ]
    # Informational: p47 is a trim sketch, never a dimension source. Recorded, not a pass/fail criterion.
    sketch_checks = [
        check('fuselage_width_at_wing_p47_vs_plan', (p47_width[1] - p47_width[0]) / ((p47['span_y_pt'][1] - p47['span_y_pt'][0]) / (2 * half_span_in)), 2 * wing_root_halfwidth_in, 0.12, 'in', 'manual p47 two-view scaled by its own span', 'informational: sketch consistency'),
    ]

    adopted = {
        'frame': 'metres; +X right, +Y up, -Z nose; origin on the symmetry plane at the nominal CG station (4-1/8 in aft of the rib-2D LE) and spinner-axis height',
        'leading_z_2D': r6(-cg_aft_in * IN),
        'wing': {
            'span': r6(2 * half_span_in * IN),
            'root_chord_centreline': r6(root_chord_cl_in * IN),
            'tip_chord': r6(tip_chord_in * IN),
            'le_z_centreline': r6(z_wing(le(x_cl))),
            'le_z_tip': r6(z_wing(le(w['tip_x']['px']))),
            'te_z_centreline': r6(z_wing(te(x_cl))),
            'te_z_tip': r6(z_wing(te(w['tip_x']['px']))),
            'chord_plane_y': r6(y_side((le_side[1] + te_side[1]) / 2)),
            'aileron_inner': r6(span_wing(w['aileron_inner_x']['px'])),
            'aileron_outer': r6(span_wing(w['aileron_outer_x']['px'])),
            'aileron_chord': r6(hinge_offset_in * IN),
            'reference_chord_S_over_b': r6(area_in2 / (2 * half_span_in) * IN),
            'mac': r6(mac_in * IN),
            'mac_span_station': r6(mac_span_in * IN),
            'mac_le_z': r6(z_wing(le(x_cl + mac_span_in * s_w))),
            'cg_fraction_of_mac': r6((cg_aft_in - mac_le_aft_of_2d_in) / mac_in),
            'root_section_x_halfthickness_camber': airfoil,
        },
        'fuselage_stations': stations,
        'spinner': {'tip_z': r6(z_side(f['spinner_tip']['px'][0])), 'back_z': r6(z_side(f['spinner_back_x']['px'])), 'radius': r6(spinner_dia_in / 2 * IN)},
        'firewall_z': r6(z_side(f['firewall_front_x']['px'])),
        'cowl_rear_z': r6(z_side(f['cowl_rear_x']['px'])),
        'canopy_top': [[r6(z_side(x)), r6(y_side(y))] for x, y in f['canopy_top']['px']],
        'canopy_halfwidth_fraction_p47': r6((p47_canopy[1] - p47_canopy[0]) / (p47_width[1] - p47_width[0])),
        'stab': stab,
        'fin': fin,
        'tailwheel_axle': side_point('tailwheel_axle'),
        'main_axle': side_point('main_axle'),
        'main_leg_root': side_point('main_leg_root'),
        'wheel_pant_z': [r6(z_side(x)) for x in f['wheel_pant_x']['px']],
        'wheel_pant_profile': pant_profile(f, z_side, y_side),
        'main_leg': main_leg(f, z_side, y_side),
        'wheel_pant_y': [r6(y_side(y)) for y in f['wheel_pant_y']['px']],
        'rudder_te_z': r6(z_side(f['rudder_te_max']['px'][0])),
    }
    return {
        'format': 'openrc-metrology v1',
        'step': 'EX-01',
        'picks_sha256': sha256(HERE / 'picks.json'),
        'scales': {
            'wing_sheet_px_per_in': round(s_w, 3), 'ruler_max_tick_residual_px': round(ruler_residual, 2), 'ruler_ticks_0_18_36_px': ruler_ticks,
            'fuselage_sheet_px_per_in': round(s_f, 3), 'fuselage_scale_source': 'root rib chord drawn in the side view = wing-sheet chord at rib 2D',
            'p47_side_px_per_pt': round(p47_long, 4),
        },
        'wing_fit': {
            'le_slope_px_per_px': round(le_slope, 6), 'le_max_residual_px': round(le_res, 2),
            'te_slope_px_per_px': round(te_slope, 6), 'te_max_residual_px': round(te_res, 2),
            'hinge_slope_px_per_px': round(hinge_slope, 6), 'hinge_max_residual_px': round(hinge_res, 2),
            'root_chord_centreline_in': round(root_chord_cl_in, 4), 'chord_at_2D_in': round(chord_2d_in, 4), 'tip_chord_in': round(tip_chord_in, 4),
            'half_span_in': round(half_span_in, 4), 'taper': round(taper, 5), 'aspect_ratio': round((2 * half_span_in) ** 2 / area_in2, 4),
            'mac_in': round(mac_in, 4), 'mac_span_station_in': round(mac_span_in, 4), 'cg_percent_mac': round(100 * (cg_aft_in - mac_le_aft_of_2d_in) / mac_in, 2),
            'aileron_chord_in': round(hinge_offset_in, 4),
            'samples_le': le_samples, 'samples_te': te_samples,
        },
        'bottom_view_half_widths_px': auto_widths,
        'checks': checks,
        'p47_sketch_checks': sketch_checks,
        'p47_sketch_residuals_vs_plan_in': {k: (round(v, 3) if not isinstance(v, list) else [round(x, 3) for x in v]) for k, v in p47_residuals_in.items()},
        'adopted_model_values': adopted,
        'limits': [
            'Paper plan and scan distortion are not measured; the 36 in ruler fixes the horizontal wing-sheet scale and the vertical scale is assumed equal.',
            'The fuselage sheet is drawn at reduced scale; its scale comes from one chord and is checked by the reserved length, spinner and stab readings.',
            'The p47 two-view is a trim-planning sketch: residuals up to about 1 in show it is not used for dimensions.',
            'Fuselage cross-section shape between the side and bottom outlines is not measured here; formers are drawn but not traced.',
            'Main-gear track, wheel-pant width, propeller and the outer rib thickness are not measured.',
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    picks = json.loads((HERE / 'picks.json').read_text())
    report = json.dumps(measure(picks), indent=1) + '\n'
    target = HERE / 'metrology.json'
    if args.check:
        assert target.read_text() == report, 'metrology.json is stale: rerun measure.py'
        print('metrology.json reproduces')
    else:
        target.write_text(report)
        print(target.relative_to(ROOT))
    failed = [c['name'] for c in json.loads(report)['checks'] if not c['ok']]
    assert not failed, f'reserved checks failed: {failed}'


if __name__ == '__main__':
    main()
