#!/usr/bin/env python3
"""E0b2: derive the Stik hub and neutral tail footprints; never enable slipstream.

Owns only propulsion.propeller.thrust_line_offset in the aircraft file and the
research geometry handoff. Visual geometry and aerodynamic coefficients stay owned
by their existing sources. Use --check for read-only freshness verification.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / 'assets/aircraft/ugly-stik-60/geometry.json'
RUNTIME_GEOMETRY = ROOT / 'app/aircraft/ugly_stik_geometry.gd'
AIRCRAFT = ROOT / 'app/data/aircraft/jensen_ugly_stik_60.json'
REPORT = ROOT / 'docs/research/propwash/E0b2/geometry.json'
GENERATOR = 'research/propwash/e0b2/derive_geometry.py'
SOURCE = GENERATOR + ': assets/aircraft/ugly-stik-60/geometry.json (estimated visual installation/outline); derived, not a measured airframe'


def area(points):
    return abs(sum(a[0] * b[1] - b[0] * a[1]
                   for a, b in zip(points, points[1:] + points[:1]))) / 2


def clip(points, axis, boundary, greater):
    """Clip a planar polygon to a closed axis-aligned half-plane."""
    result = []
    if not points:
        return result
    previous = points[-1]
    inside_previous = previous[axis] >= boundary if greater else previous[axis] <= boundary
    for current in points:
        inside = current[axis] >= boundary if greater else current[axis] <= boundary
        if inside != inside_previous:
            fraction = (boundary - previous[axis]) / (current[axis] - previous[axis])
            point = [previous[k] + fraction * (current[k] - previous[k]) for k in range(2)]
            point[axis] = boundary
            result.append(point)
        if inside:
            result.append(list(current))
        previous, inside_previous = current, inside
    return result


def relieved(points, offset):
    # Match ugly_stik_model.gd:_relieved_outline, without a rendering dependency.
    return [[p[0], offset if abs(p[1]) < 1e-5 else p[1]] for p in points]


def quantity(value, unit, note=''):
    return {'value': value, 'unit': unit, 'kind': 'derived', 'source': SOURCE + ('; ' + note if note else '')}


def visual_to_le(point, geometry):
    # Visual [right, up, aft] -> LE [aft, right, up]; z_LE=0 is the shaft line.
    return [round(point[2] - geometry['wing']['leading_z'], 12), point[0],
            round(point[1] - geometry['equipment']['shaft_y'], 12)]


def derive(geometry, aircraft):
    tail, equipment = geometry['tail'], geometry['equipment']
    hub = visual_to_le([0.0, equipment['shaft_y'], equipment['prop_z']], geometry)
    cg = aircraft['balance']['plan_cg']['value']
    offset = quantity([round(hub[k] - cg[k], 12) for k in range(3)], 'm',
                      'hub minus plan CG in [aft,right,up]; visual datum subtracts wing.leading_z and equipment.shaft_y; shaft height remains zero in LE')
    pieces = []

    def piece(name, surface, contours):
        footprints, total = [], 0.0
        for role, polygon in contours:
            if len(polygon) < 3 or area(polygon) < 1e-15:
                continue
            if surface == 'horizontal':
                points = [visual_to_le([s, tail['y'], tail['hinge_z'] + c], geometry) for s, c in polygon]
            else:
                points = [visual_to_le([0.0, tail['fin_y'] + s, tail['rudder_hinge_z'] + c], geometry) for s, c in polygon]
            total += area(polygon)
            footprints.append({'part': role, 'outline_le': quantity(points, 'm'), 'area': quantity(area(polygon), 'm2')})
        span_axis = 1 if surface == 'horizontal' else 2
        stations = [p[span_axis] for f in footprints for p in f['outline_le']['value']]
        pieces.append({'name': name, 'surface': surface, 'area': quantity(total, 'm2'),
                       'span_bounds_le': quantity([min(stations), max(stations)], 'm'), 'footprints': footprints})

    gap = tail['hinge_gap'] / 2
    stab = relieved(tail['stab_outline'], -gap)
    elevator = relieved(tail['elevator_outline'], gap)
    # Match the neutral rendered elevator's open aft notch. Partition its two
    # halves into disjoint inner/outer polygons instead of inventing a trapezoid.
    for positive, name in [(False, 'horizontal_left'), (True, 'horizontal_right')]:
        half = clip(elevator, 0, 0.0, positive)
        boundary = tail['elevator_cutout_half_width'] * (1 if positive else -1)
        inner = clip(clip(half, 0, boundary, not positive), 1, tail['elevator_cutout_start'], False)
        outer = clip(half, 0, boundary, positive)
        piece(name, 'horizontal', [('stabilizer', clip(stab, 0, 0.0, positive)),
                                   ('elevator_inner', inner), ('elevator_outer', outer)])
    piece('vertical', 'vertical', [('fin', relieved(tail['fin_outline'], -gap)),
                                   ('rudder', relieved(tail['rudder_outline'], gap))])
    return offset, {
        'format': 'openrc-stik-wash-geometry-e0b2 v1', 'generator': GENERATOR,
        'scope': 'Neutral planar footprints, matching visual hinge relief/elevator notch. Geometry handoff only; no runtime slipstream configuration or wash coefficients.',
        'axes': 'LE [aft,right,up], metres; longitudinal datum wing.leading_z, vertical datum equipment.shaft_y',
        'source_geometry_id': geometry['id'], 'hub_le': quantity(hub, 'm'), 'thrust_line_offset': offset,
        'pieces': pieces,
        'existing_aero_surfaces': {key: {field: aircraft['aero']['surfaces'][key][field] for field in ['area', 'position']}
                                   for key in ['horizontal', 'vertical']},
        'excluded_ventral_area': quantity(area(tail['ventral_outline']), 'm2', 'not represented by the current vertical aerodynamic surface; preserve as an explicit exclusion'),
        'limits': ['Estimated geometry remains estimated evidence, even when its coordinates are derived exactly.',
                   'Existing aerodynamic areas and pressure centres are not recalibrated; their areas predate hinge relief and the elevator notch.',
                   'Surface footprints are not the current linear-chord slipstream loader format. E0b3 must choose and verify their load/immersion representation.',
                   'No fuselage shielding, tail thickness, deflected-control geometry, wake decay, swirl or reverse-flow model is inferred.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    geometry = json.loads(GEOMETRY.read_text())
    compiled = json.loads(RUNTIME_GEOMETRY.read_text().split('const DATA := ', 1)[1])
    if compiled != geometry:
        raise SystemExit('Visual geometry source/runtime differ; regenerate through its model-team compiler')
    aircraft = json.loads(AIRCRAFT.read_text())
    offset, report = derive(geometry, aircraft)
    output = json.dumps(report, indent=2, ensure_ascii=False) + '\n'
    if args.check:
        if aircraft['propulsion']['propeller']['thrust_line_offset'] != offset:
            raise SystemExit('Stale Stik hub: run ' + GENERATOR)
        if not REPORT.exists() or REPORT.read_text() != output:
            raise SystemExit('Stale E0b2 geometry handoff: run ' + GENERATOR)
        print('E0b2: hub and three neutral tail footprints match source/runtime geometry')
    else:
        aircraft['propulsion']['propeller']['thrust_line_offset'] = offset
        AIRCRAFT.write_text(json.dumps(aircraft, indent=2, ensure_ascii=False) + '\n')
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(output)
        print('E0b2: updated Stik thrust_line_offset and geometry handoff only')


if __name__ == '__main__':
    main()
