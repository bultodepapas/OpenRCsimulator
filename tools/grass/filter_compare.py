#!/usr/bin/env python3
"""Photographic grass sampling versus independent LOD0 supersampled references."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

BASE_VIEWPORT = (1280, 720)
CROP = (480, 460, 320, 64)
HEIGHTS = (.55, 1.7)
STEPS = range(3)
CAMERA_STEP_M = .02
FOV_DEG = 50.0
NEAR_M = .1
FAR_M = 21000.0


def linear(rgb):
    value = np.asarray(rgb, dtype=np.float64) / 255.0
    return np.where(value <= .04045, value / 12.92, ((value + .055) / 1.055) ** 2.4)


def rms(value):
    return float(np.sqrt(np.mean(np.square(value))))


def motion_error(sequence, reference):
    return rms(np.diff(np.asarray(sequence), axis=0) - np.diff(np.asarray(reference), axis=0))


def decide(filtered_error, raw_error, disagreement, signal, motion_filtered, motion_raw, motion_disagreement):
    return {
        'visible_photo_detail': signal > .001,
        'spatial_improvement_exceeds_reference_uncertainty': raw_error - filtered_error > 2 * disagreement,
        'motion_improvement_exceeds_reference_uncertainty': motion_raw - motion_filtered > 2 * motion_disagreement,
    }


def _array(value, shape, label):
    result = np.asarray(value, dtype=np.float64)
    if result.shape != shape or not np.isfinite(result).all():
        raise ValueError(f'invalid {label}')
    return result


def _validate_projection(record, scale, height, step):
    """Check the recorded pose and its projected world point against the crop contract."""
    position = _array(record.get('position'), (3,), 'camera position')
    point = _array(record.get('projection_probe_world'), (3,), 'projection probe world point')
    basis = _array(record.get('camera_basis'), (3, 3), 'camera basis')
    projection = _array(record.get('projection_probe_px'), (2,), 'projected crop point')
    viewport = _array(record.get('viewport'), (2,), 'capture viewport')
    expected_position_delta = np.array([step * CAMERA_STEP_M, height, 45.0])
    if not np.allclose(position - point, expected_position_delta, rtol=0, atol=1e-6):
        raise ValueError('camera position does not match the planned crop pose')
    if not np.array_equal(viewport, np.asarray(CROP[2:]) * scale):
        raise ValueError('capture viewport does not match the crop scale')
    for key, expected in (('fov_deg', FOV_DEG), ('near_m', NEAR_M), ('far_m', FAR_M)):
        if not np.isclose(float(record.get(key, np.nan)), expected, rtol=0, atol=1e-8):
            raise ValueError(f'camera {key} does not match the crop contract')

    distance = np.hypot(height, 45.0)
    expected_basis = np.array([[1.0, 0.0, 0.0],
                               [0.0, 45.0 / distance, -height / distance],
                               [0.0, height / distance, 45.0 / distance]])
    if not np.allclose(basis, expected_basis, rtol=0, atol=2e-5):
        raise ValueError('camera basis does not match the planned look-at pose')

    frustum_height = 2.0 * NEAR_M * np.tan(np.deg2rad(FOV_DEG) / 2.0)
    expected_frustum_size = frustum_height * CROP[3] / BASE_VIEWPORT[1]
    expected_offset = np.array([0.0, -(CROP[1] + CROP[3] / 2 - BASE_VIEWPORT[1] / 2)
                                * frustum_height / BASE_VIEWPORT[1]])
    frustum_offset = _array(record.get('frustum_offset'), (2,), 'frustum offset')
    if not np.isclose(float(record.get('frustum_size', np.nan)), expected_frustum_size, rtol=0, atol=1e-7):
        raise ValueError('camera frustum size does not match the crop contract')
    if not np.allclose(frustum_offset, expected_offset, rtol=0, atol=1e-7):
        raise ValueError('camera frustum offset does not match the crop contract')

    # Reconstruct the uncropped 1280x720 perspective projection from the recorded
    # world-space basis, then subtract the crop origin. A supersampled viewport
    # represents the same crop at `scale` pixels per base pixel.
    delta = point - position
    local = basis @ delta
    depth = -local[2]
    if depth <= 0:
        raise ValueError('projection probe lies behind the camera')
    focal_px = BASE_VIEWPORT[1] / (2.0 * np.tan(np.deg2rad(FOV_DEG) / 2.0))
    full_pixel = np.array([BASE_VIEWPORT[0] / 2.0 + local[0] * focal_px / depth,
                           BASE_VIEWPORT[1] / 2.0 - local[1] * focal_px / depth])
    expected_crop_pixel = (full_pixel - np.array(CROP[:2])) * scale
    if not np.allclose(projection, expected_crop_pixel, rtol=0, atol=.15):
        raise ValueError(f'projected world point disagrees with base-view crop: {projection} vs {expected_crop_pixel}')


def _validate_actual_route(manifest, path):
    route = manifest.get('actual_route', {})
    expected_textures = {
        'rc_grass_albedo': 'res://assets/landscape/rc-ground/grass-albedo.jpg',
        'rc_grass_normal': 'res://assets/landscape/rc-ground/grass-normal.jpg',
        'rc_grass_roughness': 'res://assets/landscape/rc-ground/grass-roughness.jpg',
    }
    bool_parameters = route.get('bool_parameters', {})
    expected_declarations = {
        'grass_photo_enabled': 'uniform bool grass_photo_enabled = false;',
        'rc_surface_enabled': 'uniform bool rc_surface_enabled = false;',
    }
    include_path = 'res://render/rc_ground_detail.gdshaderinc'
    include_hash = manifest.get('source_sha256', {}).get(include_path)
    for name, declaration in expected_declarations.items():
        state = bool_parameters.get(name, {})
        if (not isinstance(state, dict) or 'override' not in state
                or state.get('shader_default') is not False
                or state.get('declaration') != declaration
                or state.get('declaration_count') != 1
                or state.get('source_path') != include_path
                or not isinstance(include_hash, str) or len(include_hash) != 64
                or state.get('default_source_sha256') != include_hash
                or not isinstance(state.get('value'), bool)):
            raise ValueError(f'invalid effective {name} evidence in capture: {path}')
    photo = bool_parameters['grass_photo_enabled']
    rc_surface = bool_parameters['rc_surface_enabled']
    if (photo['value'] is not True or photo['source'] != 'material_override'
            or photo['override'] is not True):
        raise ValueError(f'grass photo is not enabled by the active material override: {path}')
    rc_override_matches = (rc_surface['source'] == 'shader_default' and rc_surface['override'] is None
                           and rc_surface['value'] is False)
    rc_material_matches = (rc_surface['source'] == 'material_override' and rc_surface['override'] is False
                           and rc_surface['value'] is False)
    if not (rc_override_matches or rc_material_matches):
        raise ValueError(f'RC surface state has no verified false override/default source: {path}')
    if (route.get('ground_node') != 'Field/rough'
            or route.get('production_ground_shader') != 'res://render/ground.gdshader'
            or route.get('material_override_is_lighting_binding') is not True
            or route.get('capture_shader_matches_probe') is not True
            or route.get('capture_shader_code_sha256') not in manifest.get('probe_shader_sha256', [])
            or route.get('grass_photo_enabled') is not True
            or route.get('rc_surface_enabled') is not False
            or route.get('grass_texture_paths') != expected_textures):
        raise ValueError(f'capture did not use the active production grass-only material route: {path}')


def _validate_production_controls(folder, manifest):
    controls = manifest.get('production_controls')
    expected = {(height, step) for height in HEIGHTS for step in STEPS}
    if not isinstance(controls, list) or len(controls) != len(expected):
        raise ValueError(f'missing 6-pose production shader parity captures: {folder}')
    records = {}
    for record in controls:
        key = (record.get('height_m'), record.get('step'))
        if key not in expected or key in records:
            raise ValueError(f'duplicate/unknown production parity pose: {folder}')
        _validate_projection(record, 1, *key)
        image_path = folder / record.get('image', '')
        if image_path.parent.resolve() != folder.resolve():
            raise ValueError('production parity image must be local to its capture directory')
        image_bytes = image_path.read_bytes()
        if hashlib.sha256(image_bytes).hexdigest() != record.get('sha256'):
            raise ValueError(f'production parity image hash mismatch: {image_path}')
        with Image.open(image_path) as opened:
            image = np.asarray(opened.convert('RGB'))
        if image.shape != (CROP[3], CROP[2], 3):
            raise ValueError(f'wrong production parity image dimensions: {image_path}')
        records[key] = record
    if set(records) != expected:
        raise ValueError(f'incomplete production parity pose matrix: {folder}')
    return records


def load(folder, sampling, scale):
    path = folder / 'manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if (manifest.get('format') != 'openrc-grass-filter-reference v1'
            or manifest.get('sampling') != sampling or manifest.get('scale') != scale
            or manifest.get('backend') != 'gl_compatibility' or manifest.get('msaa_3d') != 2
            or manifest.get('viewport_hdr_2d') is not False or manifest.get('png_color_encoding') != 'sRGB'
            or manifest.get('clock') != 0 or manifest.get('wind') != [0, 0, 0]
            or manifest.get('crop') != list(CROP)
            or manifest.get('base_viewport') != list(BASE_VIEWPORT)
            or manifest.get('viewport') != [CROP[2] * scale, CROP[3] * scale]):
        raise ValueError(f'unsupported capture contract: {path}')
    _validate_actual_route(manifest, path)
    records = {(record['height_m'], record['step'], record['state']): record for record in manifest['captures']}
    expected = {(height, step, state) for height in HEIGHTS for step in STEPS for state in ('off', 'on', 'repeat')}
    if set(records) != expected or len(manifest['captures']) != len(expected):
        raise ValueError(f'incomplete/duplicate frame matrix: {path}')
    residuals, controls, geometry = {}, {}, {}
    for height in HEIGHTS:
        residuals[height], controls[height] = [], []
        for step in STEPS:
            pictures = {}
            for state in ('off', 'on', 'repeat'):
                record = records[height, step, state]
                picture_path = folder / record['image']
                if picture_path.parent.resolve() != folder.resolve():
                    raise ValueError('capture image must be local to the capture directory')
                if hashlib.sha256(picture_path.read_bytes()).hexdigest() != record['sha256']:
                    raise ValueError(f'image hash mismatch: {picture_path}')
                if record['effective_photo'] != (state != 'off'):
                    raise ValueError('effective photo state does not match capture')
                _validate_projection(record, scale, height, step)
                geometry[height, step, state] = {key: record[key] for key in
                    ('position', 'camera_transform', 'camera_basis', 'frustum_size', 'frustum_offset',
                     'fov_deg', 'near_m', 'far_m', 'viewport', 'projection_probe_world', 'projection_probe_px')}
                with Image.open(picture_path) as opened:
                    array = np.asarray(opened.convert('RGB'))
                if array.shape != (64 * scale, 320 * scale, 3):
                    raise ValueError(f'wrong capture dimensions: {picture_path}')
                if state == 'repeat':
                    if not np.array_equal(pictures['on'], array):
                        raise ValueError(f'non-repeatable on-state: {picture_path}')
                else:
                    pictures[state] = array
            off, on = [linear(pictures[state]).reshape(64, scale, 320, scale, 3).mean(axis=(1, 3))
                       for state in ('off', 'on')]
            residuals[height].append(on - off)
            controls[height].append(off)
    production_controls = _validate_production_controls(folder, manifest) if sampling == 'filtered' else {}
    return {'manifest': manifest, 'manifest_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'residuals': residuals, 'controls': controls, 'geometry': geometry, 'records': records,
            'production_controls': production_controls}


def compare(folders):
    loaded = {name: load(path, 'filtered' if name in ('filtered', 'repeat') else 'raw',
                         8 if name == 'reference8' else 16 if name == 'reference16' else 1)
              for name, path in folders.items()}
    base = loaded['filtered']
    for name, run in loaded.items():
        for key in ('engine', 'backend', 'adapter', 'source_sha256', 'crop', 'base_viewport', 'msaa_3d'):
            if run['manifest'][key] != base['manifest'][key]:
                raise ValueError(f'{name} identity mismatch: {key}')
        for geometry_key, geometry in run['geometry'].items():
            base_geometry = base['geometry'][geometry_key]
            for field in geometry:
                current = geometry[field]
                expected_geometry = base_geometry[field]
                if field == 'viewport':
                    current = np.asarray(current, dtype=float) / run['manifest']['scale']
                    expected_geometry = np.asarray(expected_geometry, dtype=float) / base['manifest']['scale']
                elif field == 'projection_probe_px':
                    current = np.asarray(current, dtype=float) / run['manifest']['scale']
                    expected_geometry = np.asarray(expected_geometry, dtype=float) / base['manifest']['scale']
                if isinstance(current, (list, tuple, np.ndarray)):
                    matches = np.allclose(np.asarray(current, dtype=float), np.asarray(expected_geometry, dtype=float),
                                          rtol=0, atol=1e-5)
                else:
                    matches = current == expected_geometry
                if not matches:
                    raise ValueError(f'{name} camera geometry mismatch: {geometry_key}/{field}')
    for key, record in base['records'].items():
        if loaded['repeat']['records'][key]['sha256'] != record['sha256']:
            raise ValueError(f'independent native repeat differs at {key}')
    rows = []
    for height in HEIGHTS:
        sequences = {name: np.asarray(run['residuals'][height]) for name, run in loaded.items()}
        reference = sequences['reference16']
        error = {name: rms(value - reference) for name, value in sequences.items()}
        temporal = {name: motion_error(value, reference) for name, value in sequences.items()}
        signal = rms(sequences['filtered'])
        gates = decide(error['filtered'], error['raw'], error['reference8'], signal,
                       temporal['filtered'], temporal['raw'], temporal['reference8'])
        rows.append({'height_m': height, 'spatial_linear_rgb_rms': error, 'temporal_residual_error_rms': temporal,
                     'photo_signal_rms': signal, 'gates': gates, 'passed': all(gates.values()),
                     'background_motion_rms': rms(np.diff(np.asarray(base['controls'][height]), axis=0))})
    # The 1x filtered probe must reproduce the active production shader's actual
    # rendered images at every camera pose. This validates the probe before using
    # its 8x/16x supersampled references as a comparison target.
    production = loaded['filtered']['production_controls']
    for key, control in production.items():
        probe = base['records'][(*key, 'on')]
        if probe['sha256'] != control['sha256']:
            raise ValueError(f'filtered 1x probe differs from active production shader at {key}')
        repeat_control = loaded['repeat']['production_controls'][key]
        if control['sha256'] != repeat_control['sha256']:
            raise ValueError(f'production shader parity capture is not reproducible at {key}')
    return {'format': 'openrc-grass-filter-comparison v1', 'complete': True,
            'passed': all(row['passed'] for row in rows),
            'independent_native_repeat_exact': True, 'views': rows,
            'filtered_1x_matches_active_production_shader': True,
            'production_parity_pose_count': len(production),
            'capture_manifests_sha256': {name: run['manifest_sha256'] for name, run in loaded.items()},
            'method': 'Decode SDR sRGB PNGs to linear, box-average raw LOD0 8x/16x references, subtract matched photo-off frame, compare native residual and camera-motion differences to the 16x reference. Improvement must exceed twice 8x/16x disagreement. Require visible photo signal >0.001 linear RMS, exact 1x production-shader image parity at all six poses, and projected-world-point crop agreement.',
            'limits': 'Two cropped ground views, three 20mm camera moves, Compatibility local device only. The supersampled reference keeps high-resolution geometric coverage and texture sampling while scaling derivative-driven photo/turf weights and terrain-relief footprint to base-pixel scale; nonlinear turf suppression interactions remain in scope. An engineering sampling check, not universal shimmer absence, actual driving, or owner preference.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('filtered', 'raw', 'reference8', 'reference16', 'repeat'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('output must be new')
    result = compare({name: getattr(args, name) for name in ('filtered', 'raw', 'reference8', 'reference16', 'repeat')})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
