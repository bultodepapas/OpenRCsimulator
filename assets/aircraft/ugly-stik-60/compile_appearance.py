#!/usr/bin/env python3
"""Deterministic original vector artwork. Run --check to validate generated sources."""
import argparse
import json
import math
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def cross(cx, cy, sx, sy, black):
    # Four flared arms with concave sides, original paths (no copied logo artwork).
    path = 'M -.30,-.5 L .30,-.5 Q .12,-.23 .085,-.085 Q .23,-.12 .5,-.30 L .5,.30 Q .23,.12 .085,.085 Q .12,.23 .30,.5 L -.30,.5 Q -.12,.23 -.085,.085 Q -.23,.12 -.5,.30 L -.5,-.30 Q -.23,-.12 -.085,-.085 Q -.12,-.23 -.30,-.5 Z'
    return f'<path d="{path}" transform="translate({cx:.4f} {cy:.4f}) scale({sx:.4f} {sy:.4f})" fill="{black}"/>'

def station(z, stations):
    """Interpolated (half width, top, bottom) of the measured fuselage at z."""
    for a, b in zip(stations, stations[1:]):
        if z <= b[0]:
            t = min(max((z - a[0]) / (b[0] - a[0]), 0.0), 1.0)
            return tuple(a[k] + (b[k] - a[k]) * t for k in (1, 2, 3))
    return tuple(stations[-1][1:4])


def side_arc(z, y, stations):
    """Skin arc length from the belly centre line to height y on the +X side (same rounded-corner section as the
    builder: bevel = min(0.16 w, 0.12 h), quarter arcs). Heights below the corner map onto the corner/bottom."""
    w, top, bottom = station(z, stations)
    b = min(w * 0.16, (top - bottom) * 0.12)
    flat = w - b
    arc = math.pi * b / 2.0
    return flat + arc + max(y - (bottom + b), 0.0)


def exhaust_residue(d, stations):
    r = d['exhaust_residue']
    if not r['enabled']:
        return []
    f = d['fuselage_unwrap']
    z0, z1 = f['z_m']
    x0, x1 = f['x_px']
    y0, y1 = f['y_px']
    def px(z, arc):
        return (x0 + (x1 - x0) * (z - z0) / (z1 - z0), y0 + (y1 - y0) * (0.5 + arc / f['perimeter_m']))
    def centre(z):
        # Down the +X side from the outlet height to the bottom corner, then inboard along the belly.
        if z <= r['corner_z_m']:
            t = (z - r['start_z_m']) / (r['corner_z_m'] - r['start_z_m'])
            w, top, bottom = station(z, stations)
            b = min(w * 0.16, (top - bottom) * 0.12)
            y = r['start_y_m'] + ((bottom + b) - r['start_y_m']) * (t * t * (3 - 2 * t))
            return side_arc(z, y, stations)
        w, top, bottom = station(r['corner_z_m'], stations)
        corner = side_arc(r['corner_z_m'], bottom, stations)
        t = (z - r['corner_z_m']) / (r['end_z_m'] - r['corner_z_m'])
        return corner + (r['belly_end_s_m'] - corner) * min(t, 1.0) ** 0.8
    def fade(z):
        t = min(max((z - r['start_z_m']) / (r['end_z_m'] - r['start_z_m']), 0.0), 1.0)
        return r['opacity'][0] + (r['opacity'][1] - r['opacity'][0]) * t ** 0.7
    def half(z):
        t = min(max((z - r['start_z_m']) / (r['end_z_m'] - r['start_z_m']), 0.0), 1.0)
        return r['half_width_m'][0] + (r['half_width_m'][1] - r['half_width_m'][0]) * math.sqrt(t)
    zs = [r['start_z_m'] + (r['end_z_m'] - r['start_z_m']) * k / 48 for k in range(49)]
    dark, brown = r['colour']
    out = []
    xs, xe = px(zs[0], 0)[0], px(zs[-1], 0)[0]
    # Fade along the fuselage: one user-space gradient per stacked wash layer.
    for layer, (scale, alpha) in enumerate(((1.0, 0.35), (0.62, 0.45), (0.3, 0.55))):
        stops = ''.join(f'<stop offset="{k / 8:.3f}" stop-color="{brown if layer == 0 else dark}" stop-opacity="{alpha * fade(zs[0] + (zs[-1] - zs[0]) * k / 8) / r["opacity"][0]:.4f}"/>' for k in range(9))
        out.append(f'<linearGradient id="oil{layer}" gradientUnits="userSpaceOnUse" x1="{xs:.3f}" y1="0" x2="{xe:.3f}" y2="0">{stops}</linearGradient>')
        upper = [px(z, centre(z) + half(z) * scale) for z in zs]
        lower = [px(z, centre(z) - half(z) * scale) for z in reversed(zs)]
        points = ' '.join(f'{x:.3f},{y:.3f}' for x, y in upper + lower)
        out.append(f'<polygon points="{points}" fill="url(#oil{layer})"/>')
    rng = random.Random(r['seed'])
    for _ in range(r['streaks']):
        offset = rng.uniform(-0.95, 0.95)
        start = rng.uniform(r['start_z_m'], r['start_z_m'] + 0.55 * (r['end_z_m'] - r['start_z_m']))
        length = rng.uniform(0.06, 0.38)
        width = rng.uniform(0.0005, 0.0018)
        strength = rng.uniform(0.25, 0.75)
        seg = [start + length * k / 10 for k in range(11)]
        upper, lower = [], []
        for k, z in enumerate(seg):
            taper = math.sin(math.pi * k / 10) ** 0.6
            c = centre(z) + offset * half(z)
            upper.append(px(z, c + width * taper))
            lower.append(px(z, c - width * taper))
        points = ' '.join(f'{x:.3f},{y:.3f}' for x, y in upper + lower[::-1])
        out.append(f'<polygon points="{points}" fill="{dark}" fill-opacity="{strength * fade(start):.4f}"/>')
    for _ in range(r['droplets']):
        z = r['start_z_m'] + rng.betavariate(1.2, 4.0) * 0.30
        c = centre(z) + rng.uniform(-1.4, 1.4) * half(z)
        x, y = px(z, c)
        radius = rng.uniform(0.0005, 0.0016) * (x1 - x0) / (z1 - z0)
        out.append(f'<ellipse cx="{x:.3f}" cy="{y:.3f}" rx="{radius * 1.8:.3f}" ry="{radius:.3f}" fill="{dark}" fill-opacity="{rng.uniform(0.25, 0.6) * fade(z) / r["opacity"][0]:.4f}"/>')
    return out


def stab_spatter(d):
    """US-V09f: light oil spray on the right (+X) stabiliser underside, strongest near the root and leading edge."""
    r = d['exhaust_residue']
    if not r['enabled']:
        return []
    t = r['stab']
    f = d['stab_unwrap']
    (xm0, xm1), (zm0, zm1) = f['x_m'], f['z_m']
    (x0, x1), (y0, y1) = f['x_px'], f['y_px']
    def px(x, z):
        return (x0 + (x1 - x0) * (x - xm0) / (xm1 - xm0), y0 + (y1 - y0) * (z - zm0) / (zm1 - zm0))
    dark, brown = r['colour']
    xa, xb = t['x_m']
    out = []
    # Wash fading outboard (gradient along x) and aft (stacked bands from the leading edge).
    ga, gb = px(xa, 0)[0], px(xb, 0)[0]
    stops = ''.join(f'<stop offset="{k / 6:.3f}" stop-color="{brown}" stop-opacity="{t["opacity"] * (1 - k / 6) ** 1.5:.4f}"/>' for k in range(7))
    out.append(f'<linearGradient id="oilstab" gradientUnits="userSpaceOnUse" x1="{ga:.3f}" y1="0" x2="{gb:.3f}" y2="0">{stops}</linearGradient>')
    for step in range(1, 9):
        z_aft = zm0 + (0.0 - zm0) * step / 8
        a, b = px(xa, zm0), px(xb, z_aft)
        out.append(f'<rect x="{a[0]:.3f}" y="{a[1]:.3f}" width="{b[0] - a[0]:.3f}" height="{b[1] - a[1]:.3f}" fill="url(#oilstab)" fill-opacity="0.22"/>')
    rng = random.Random(r['seed'] + 1)
    for _ in range(t['streaks']):
        x = xa + (xb - xa) * rng.betavariate(1.2, 2.6)
        z = zm0 + rng.uniform(0.0, 0.35) * (0.0 - zm0)
        length = rng.uniform(0.02, 0.08)
        width = rng.uniform(0.0003, 0.0008)
        fade = (1 - (x - xa) / (xb - xa)) ** 1.2
        # Tapered streak along the chord (the airflow), wider in the middle.
        pts = [px(x, z), px(x + width, z + 0.35 * length), px(x, z + length), px(x - width, z + 0.35 * length)]
        out.append(f'<polygon points="{" ".join(f"{a:.3f},{b:.3f}" for a, b in pts)}" fill="{dark}" fill-opacity="{rng.uniform(0.12, 0.32) * fade:.4f}"/>')
    for _ in range(t['droplets']):
        x = xa + (xb - xa) * rng.betavariate(1.1, 3.0)
        z = zm0 + rng.betavariate(1.0, 3.0) * (zm1 - zm0)
        cx, cy = px(x, z)
        radius = rng.uniform(0.0004, 0.0012) * (x1 - x0) / (xm1 - xm0)
        out.append(f'<ellipse cx="{cx:.3f}" cy="{cy:.3f}" rx="{radius:.3f}" ry="{radius * 1.6:.3f}" fill="{dark}" fill-opacity="{rng.uniform(0.2, 0.45) * (1 - (x - xa) / (xb - xa)):.4f}"/>')
    return out


def unwrap_px(d):
    f = d['fuselage_unwrap']
    z0, z1 = f['z_m']
    x0, x1 = f['x_px']
    y0, y1 = f['y_px']
    return lambda z, arc: (x0 + (x1 - x0) * (z - z0) / (z1 - z0), y0 + (y1 - y0) * (0.5 + arc / f['perimeter_m']))


def hatch_seams(d, stations):
    """US-V09g: seams around the 1/4 in sheet hatch (front, rear and both side edges of the flat top)."""
    h = d['hatch']
    (z0, z1), (x0, x1), (y0, y1) = h['z_m'], h['x_px'], h['y_px']
    def px(x, z):
        return (x0 + (x1 - x0) * (x + h['half_width_m']) / (2 * h['half_width_m']), y0 + (y1 - y0) * (z - z0) / (z1 - z0))
    def edge(z):
        w, top, bottom = station(z, stations)
        return w - min(w * 0.16, (top - bottom) * 0.12)
    inset = h['seam_width_m']
    corners = [px(-edge(z0) + inset, z0 + inset), px(edge(z0) - inset, z0 + inset), px(edge(z1) - inset, z1 - inset), px(-edge(z1) + inset, z1 - inset)]
    points = ' '.join(f'{x:.3f},{y:.3f}' for x, y in corners)
    width = h['seam_width_m'] * (x1 - x0) / (2 * h['half_width_m'])
    return [f'<polygon points="{points}" fill="none" stroke="{h["seam_colour"]}" stroke-opacity="{h["seam_opacity"]}" stroke-width="{width:.3f}" stroke-linejoin="round"/>']


def belly_wear(d, stations):
    """US-V09h: grass/soil spray behind the nose wheel, scuffs between the gears and tail-strike scrapes."""
    b = d['belly_wear']
    if not b['enabled']:
        return []
    px = unwrap_px(d)
    rng = random.Random(b['seed'])
    out = []
    green, soil = b['grass_colour']
    za, zb = b['grass_z_m']
    for _ in range(b['grass_spots']):
        z = za + (zb - za) * rng.betavariate(1.3, 2.2)
        arc = rng.gauss(0.0, b['grass_half_width_m'] * 0.45)
        length = rng.uniform(0.002, 0.014)
        width = rng.uniform(0.0006, 0.0022)
        (ax, ay), (bx, by) = px(z, arc - width), px(z + length, arc + width)
        colour = green if rng.random() < 0.65 else soil
        out.append(f'<ellipse cx="{(ax + bx) / 2:.3f}" cy="{(ay + by) / 2:.3f}" rx="{(bx - ax) / 2:.3f}" ry="{(by - ay) / 2:.3f}" fill="{colour}" fill-opacity="{rng.uniform(0.18, 0.5) * (1 - 0.6 * (z - za) / (zb - za)):.4f}"/>')
    def scratch(z, arc, length, width, opacity):
        pts = [px(z, arc), px(z + 0.3 * length, arc + width), px(z + length, arc), px(z + 0.3 * length, arc - width)]
        return f'<polygon points="{" ".join(f"{x:.3f},{y:.3f}" for x, y in pts)}" fill="{b["scuff_colour"]}" fill-opacity="{opacity:.4f}"/>'
    sa, sb = b['scuff_z_m']
    for _ in range(b['scuffs']):
        out.append(scratch(rng.uniform(sa, sb), rng.gauss(0.0, 0.012), rng.uniform(0.01, 0.06), rng.uniform(0.0002, 0.0007), rng.uniform(0.15, 0.4)))
    ta, tb = b['tail_scrape_z_m']
    for _ in range(b['tail_scrapes']):
        z = ta + (tb - ta) * rng.betavariate(2.5, 1.2)
        out.append(scratch(z, rng.gauss(0.0, 0.006), rng.uniform(0.008, 0.04), rng.uniform(0.0002, 0.0006), rng.uniform(0.2, 0.5)))
    return out


def build(d):
    red, white, black=(d['palette'][k] for k in ('red','white','black'))
    size=d['atlas_size_px']
    # Artwork coordinates stay in the 1024 viewBox; width/height set the raster resolution for runtime and editor import.
    s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">',f'<rect width="1024" height="1024" fill="{red}"/>']
    wing=d['wing']
    for sign in (-1,1):
        x0,x1=sorted((512+sign*512*f for f in wing['field_semispan_fraction']))
        border=1024*wing['border_width_m']/1.524
        s += [f'<rect x="{x0-border:.4f}" y="0" width="{x1-x0+border*2:.4f}" height="272" fill="{black}"/>',f'<rect x="{x0:.4f}" y="0" width="{x1-x0:.4f}" height="272" fill="{white}"/>',cross(512+sign*512*wing['cross_center_semispan_fraction'],16+224*wing['cross_center_chord_fraction'],1024*wing['cross_size_m']/1.524,224*wing['cross_size_m']/.3048,black)]
    # US-V09b: structure under the film is a normal map built from film_structure (ugly_stik_finish.gd), not drawn lines.
    s += [f'<rect x="16" y="528" width="480" height="464" fill="{white}"/>']
    fin=d['fin']
    s += [cross(32+448*(fin['cross_center_chord_z_m']+.2)/.31,976-432*fin['cross_center_height_m']/.215,448*fin['cross_size_m']/.31,432*fin['cross_size_m']/.215,black)]
    geometry=json.loads((HERE/'geometry.json').read_text())
    s += exhaust_residue(d, geometry['fuselage_stations'])
    s += stab_spatter(d)
    s += belly_wear(d, geometry['fuselage_stations'])
    s += hatch_seams(d, geometry['fuselage_stations'])
    dorsal=d['dorsal']
    w,h=464*dorsal['field_width_m']/.11,464*dorsal['field_length_m']/.12
    s += [f'<rect x="{776-w/2:.4f}" y="{776-h/2:.4f}" width="{w:.4f}" height="{h:.4f}" fill="{white}"/>',cross(776,776,464*dorsal['cross_size_m']/.11,464*dorsal['cross_size_m']/.12,black),'</svg>']
    return '\n'.join(s)+'\n'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    d=json.loads((HERE/'appearance.json').read_text())
    target=ROOT/'app/aircraft/livery.svg'; source=build(d)
    generated = '# Generated by compile_appearance.py; visual estimates only.\nextends RefCounted\n'
    generated += 'const DATA := ' + json.dumps(d,ensure_ascii=False,indent='\t') + '\n'
    for key,value in d['palette'].items():
        generated += f'const {key.upper()} := Color("{value}")\n'
    generated += 'const SVG_SOURCE := ' + json.dumps(source) + '\n'
    outputs={target:source,ROOT/'app/aircraft/ugly_stik_appearance.gd':generated}
    for path,text in outputs.items():
        if args.check:
            assert path.read_text()==text,f'Stale {path.name}; rerun compile_appearance.py'
        else: path.write_text(text)
    if args.check: print('Appearance source, generated data and SVG match')
if __name__=='__main__':main()
