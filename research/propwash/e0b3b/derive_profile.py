#!/usr/bin/env python3
"""Derive exact spanwise chord-area profiles from the E0b2 Stik tail polygons.

This writes research evidence only. It does not edit the aircraft data or enable
the runtime slipstream model. --check verifies the generated handoff is current.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'docs/research/propwash/E0b2/geometry.json'
AIRCRAFT = ROOT / 'app/data/aircraft/jensen_ugly_stik_60.json'
REPORT = ROOT / 'docs/research/propwash/E0b3b/geometry.json'
FIXTURE = ROOT / 'app/tests/fixtures/stik_wash_profile.json'
GENERATOR = 'research/propwash/e0b3b/derive_profile.py'
TOL = 1e-12


def quantity(value, unit, source, kind='derived'):
    return {'value': value, 'unit': unit, 'kind': kind, 'source': source}


def _span_coordinate(point, span_axis, side):
    return point[span_axis] * side


def _width_on_interval(points, span_axis, chord_axis, side, low, high):
    """Return polygon chord widths at one-sided slab endpoints.

    All input contours are convex. Looking at an interior station avoids the
    ambiguity at vertices where the left and right one-sided widths can differ.
    """
    mid = (low + high) * 0.5
    crossings = []
    for first, second in zip(points, points[1:] + points[:1]):
        s0 = _span_coordinate(first, span_axis, side)
        s1 = _span_coordinate(second, span_axis, side)
        if (s0 < mid < s1) or (s1 < mid < s0):
            slope = (second[chord_axis] - first[chord_axis]) / (s1 - s0)
            crossings.append((first[chord_axis] + slope * (low - s0),
                              first[chord_axis] + slope * (high - s0)))
    if not crossings:
        return None
    if len(crossings) != 2:
        raise ValueError(f'Expected two crossings in convex footprint, got {len(crossings)}')
    return (abs(crossings[0][0] - crossings[1][0]),
            abs(crossings[0][1] - crossings[1][1]))


def _raw_profile(footprints, span_axis, chord_axis, side, offset=0.0):
    polygons = [footprint['outline_le']['value'] for footprint in footprints]
    bounds = sorted({round(_span_coordinate(point, span_axis, side) - offset, 12)
                     for polygon in polygons for point in polygon})
    result = []
    for low, high in zip(bounds, bounds[1:]):
        if high - low <= TOL:
            continue
        chord_low = chord_high = 0.0
        for polygon in polygons:
            widths = _width_on_interval(polygon, span_axis, chord_axis, side,
                                        low + offset, high + offset)
            if widths is not None:
                chord_low += widths[0]
                chord_high += widths[1]
        if chord_low > TOL or chord_high > TOL:
            result.append([low, high, chord_low, chord_high])
    return result


def _merge_collinear(profile):
    """Merge adjacent segments only when both value and slope are continuous."""
    merged = []
    for row in profile:
        if merged:
            previous = merged[-1]
            h0 = previous[1] - previous[0]
            h1 = row[1] - row[0]
            slope0 = (previous[3] - previous[2]) / h0
            slope1 = (row[3] - row[2]) / h1
            continuous = abs(previous[1] - row[0]) <= TOL and abs(previous[3] - row[2]) <= TOL
            collinear = abs(slope0 - slope1) <= TOL
            if continuous and collinear:
                previous[1] = row[1]
                previous[3] = row[3]
                continue
        merged.append(list(row))
    return merged


def _integrals(profile):
    """Area and first span moment of piecewise-linear chord density."""
    area = first_moment = 0.0
    for low, high, c0, c1 in profile:
        width = high - low
        slope = (c1 - c0) / width
        local_area = c0 * width + 0.5 * slope * width * width
        local_first = low * local_area + 0.5 * c0 * width * width + slope * width ** 3 / 3.0
        area += local_area
        first_moment += local_first
    return area, first_moment


def derive(source_geometry, aircraft):
    aero = aircraft['aero']['surfaces']
    source_path = 'docs/research/propwash/E0b2/geometry.json'
    geometry_source = (source_path + ': generated from estimated visual installation geometry; '
                       'derived, not measured on the owner’s airframe')
    pieces = []
    group_definitions = [
        ('horizontal_left', 'horizontal', 1, 0, 1, -1, 0.0),
        ('horizontal_right', 'horizontal', 1, 0, 1, 1, 0.0),
        ('vertical', 'vertical', 2, 0, 2, 1, None),
    ]
    for name, surface, span_axis, chord_axis, dir_axis, side, _ in group_definitions:
        source_piece = next(piece for piece in source_geometry['pieces'] if piece['name'] == name)
        footprints = source_piece['footprints']
        offset = min(point[2] for footprint in footprints for point in footprint['outline_le']['value']) if surface == 'vertical' else 0.0
        profile = _raw_profile(footprints, span_axis, chord_axis, side, offset)
        merged = _merge_collinear(profile)
        area, span_moment = _integrals(merged)
        source_area = source_piece['area']['value']
        if abs(area - source_area) > 2e-12:
            raise ValueError(f'{name}: profile area {area:.15g} differs from source polygon area {source_area:.15g}')
        span_values = [point[span_axis] * side for footprint in footprints
                       for point in footprint['outline_le']['value']]
        span_min, span_max = min(span_values), max(span_values)
        load_position = aero[surface]['position']['value']
        if surface == 'horizontal':
            coverage_z = footprints[0]['outline_le']['value'][0][2]
            root = [load_position[0], 0.0, coverage_z]
            direction = [0.0, float(side), 0.0]
        else:
            root = [load_position[0], 0.0, offset]
            direction = [0.0, 0.0, 1.0]
        piece_source = geometry_source + f'; source group {name}, exact polygon section integration'
        pieces.append({
            'name': name,
            'surface': surface,
            'root_le': quantity(root, 'm', piece_source + '; root x uses existing aerodynamic reference, horizontal z uses neutral coverage plane'),
            'span_dir_le': quantity(direction, '1', piece_source + '; positive profile offsets run outward from root'),
            'span': quantity(span_max - span_min, 'm', piece_source),
            'area': quantity(area, 'm2', piece_source),
            'span_centroid_offset': quantity(span_moment / area, 'm', piece_source + '; exact first moment of projected contour area'),
            'profile': quantity([[round(value, 12) for value in row] for row in merged], 'm',
                                piece_source + '; rows [span_start, span_end, one-sided chord_start, one-sided chord_end]; aggregate area-equivalent width; source polygons retain chordwise gaps'),
            'profile_segment_count': {
                'before_collinear_merge': len(profile),
                'after_collinear_merge': len(merged),
                'unit': 'segments',
                'source': GENERATOR + '; merge tolerance 1e-12 m and 1e-12 m/m, with endpoint continuity required',
            },
            'source_footprints': [footprint['part'] for footprint in footprints],
            'source_geometry': source_path + '#/pieces/' + name,
            'load_reference_le': quantity(load_position, 'm', aero[surface]['position']['source'], aero[surface]['position']['kind']),
            'coverage_plane_le': quantity([root[0], root[1], root[2]], 'm', piece_source),
        })

    horizontal_z = pieces[0]['root_le']['value'][2]
    aero_horizontal_z = pieces[0]['load_reference_le']['value'][2]
    z_difference = aero_horizontal_z - horizontal_z
    return {
        'format': 'openrc-stik-wash-profile-e0b3b v1',
        'generator': GENERATOR,
        'status': 'Research geometry handoff only; no runtime aircraft configuration, wash coefficient or enablement.',
        'source_geometry_id': source_geometry['source_geometry_id'],
        'source_geometry': source_path,
        'axes': 'LE [aft,right,up], metres; profile offsets are positive outward from each piece root.',
        'representation': 'Three area-equivalent station-profile groups: mirrored horizontal halves and one vertical fin/rudder group. Each profile row is [span_start, span_end, one-sided chord_start, one-sided chord_end]. Aggregate chord is the sum of disjoint polygon widths at that span station; the source polygons remain authoritative for chordwise gaps and the open elevator notch.',
        'pieces': pieces,
        'horizontal_reference_discrepancy': {
            'neutral_coverage_z': quantity(horizontal_z, 'm', pieces[0]['root_le']['source']),
            'existing_aerodynamic_load_reference_z': quantity(aero_horizontal_z, 'm', pieces[0]['load_reference_le']['source'], pieces[0]['load_reference_le']['kind']),
            'load_minus_coverage': quantity(z_difference, 'm', 'Derived from E0b2 neutral outline and existing aerodynamic surface data; geometry plane is 5 mm above the aerodynamic load reference.'),
            'instruction': 'Use neutral_coverage_z for wake-circle intersection. Preserve existing_aerodynamic_load_reference_z for force and moment arms; do not move the calibrated aerodynamic pressure reference.',
        },
        'limits': [
            'The profile exactly preserves polygon projected area and spanwise first moment, including the hinge relief, split elevator boundary and notch area.',
            'A single runtime piece uses the existing aerodynamic reference x for wake-centre drift and load application; the span profile collapses chordwise-separated material to an aggregate chord. The E0b2 polygons preserve exact chordwise gaps, but this profile does not resolve chordwise wake coverage.',
            'Footprints and profile are derived from estimated visual geometry, not measured aircraft dimensions or validated propwash coverage.',
            'No wake strength, edge smoothing, reverse-flow fade, shielding, control deflection, decay or transport is specified.',
        ],
    }


def fixture_data(source_geometry, report):
    """Return test-only raw geometry; wash coefficients belong to the test."""
    return {
        'format': 'openrc-stik-wash-profile-fixture-e0b3b v1',
        'test_only': True,
        'generator': GENERATOR,
        'source_geometry': 'docs/research/propwash/E0b2/geometry.json',
        'hub': source_geometry['hub_le']['value'],
        'pieces': [
            {
                'surface': piece['surface'],
                'root': piece['root_le']['value'],
                'span_dir': piece['span_dir_le']['value'],
                'span': piece['span']['value'],
                'area': piece['area']['value'],
                'profile': piece['profile']['value'],
            }
            for piece in report['pieces']
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='fail if source or generated report is stale')
    args = parser.parse_args()
    source = json.loads(SOURCE.read_text())
    aircraft = json.loads(AIRCRAFT.read_text())
    report = derive(source, aircraft)
    fixture = fixture_data(source, report)
    outputs = {
        REPORT: json.dumps(report, indent=2, ensure_ascii=False) + '\n',
        FIXTURE: json.dumps(fixture, indent=2, ensure_ascii=False) + '\n',
    }
    if args.check:
        stale = [path for path, output in outputs.items()
                 if not path.exists() or path.read_text() != output]
        if stale:
            labels = ', '.join(str(path.relative_to(ROOT)) for path in stale)
            raise SystemExit('Stale E0b3b outputs (' + labels + '); run ' + GENERATOR)
        print('E0b3b: geometry report and test fixture match 3 exact projected-area profiles')
        return
    for path, output in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(output)
    print('E0b3b: wrote geometry report and test-only geometry fixture')


if __name__ == '__main__':
    main()
