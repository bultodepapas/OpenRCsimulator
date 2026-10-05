"""Assembly diagnostics of the visual parameterization, not a physical aircraft.

Solve the rigid pitch needed to put the nose/main circular tires on one plane,
then measure clearance to the swept propeller disk. No ground dynamics involved.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'assets/aircraft/ugly-stik-60/geometry.json'
OUT = ROOT / 'docs/research/ugly-stik-investigations/evidence/model-assembly-current.json'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=OUT)
    args = parser.parse_args()
    data = json.loads(SOURCE.read_text())
    e = data['equipment']
    rmain = e['main_wheel_diameter'] / 2
    rnose = e['nose_wheel_diameter'] / 2
    dz = e['nose_axle_z'] - e['main_axle_z']
    pitch = math.asin(-(rnose-rmain) / dz)
    c, s = math.cos(pitch), math.sin(pitch)
    ground = c * e['wheel_y'] - s * e['main_axle_z'] - rmain
    nose_contact = c * e['wheel_y'] - s * e['nose_axle_z'] - rnose
    prop_low = c * e['shaft_y'] - s * e['prop_z'] - e['prop_diameter'] / 2 * c
    assert math.isclose(nose_contact, ground, abs_tol=1e-12)
    assert prop_low > ground, 'Visual propeller intersects ground at three-wheel rest pose'
    w = data['wing']
    result = {
        'aircraft_id': data['id'],
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'evidence_kind': 'calculation_on_estimated_visual_geometry',
        'physics_configuration_changed': False,
        'wheel_contact_assumptions': 'Rigid undeformed circular tires, parallel axles, no suspension; pose only',
        'render_rotation_x_rad': pitch,
        'render_rotation_x_deg': math.degrees(pitch),
        'ground_plane_y_m': ground,
        'nose_contact_residual_m': nose_contact-ground,
        'propeller_disk_ground_clearance_m': prop_low-ground,
        'nominal_span_m': w['span'],
        'span_centerline_horizontal_projection_m': w['span']*math.cos(math.radians(w['dihedral_deg'])),
        'rectangular_developed_planform_area_m2': w['span']*w['chord'],
        'nominal_jensen_area_m2': 720 * 0.0254**2,
        'limits': ['No flight or installation validation', '12-inch propeller and gear placement remain estimates', 'Geometry is not a mass or inertia model', 'Nominal area is not inferred from a raster or a built airplane'],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
