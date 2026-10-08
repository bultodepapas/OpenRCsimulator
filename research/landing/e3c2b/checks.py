"""Independent pose, image-presence and repeated-capture checks (not readability)."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops


def close(actual, expected, tolerance, label):
    if len(actual) != len(expected) or any(not math.isfinite(x) or abs(x-y) > tolerance for x, y in zip(actual, expected)):
        raise ValueError(label)


def render_basis(q):
    w, x, y, z = q
    r = [[1-2*(y*y+z*z), 2*(x*y-w*z), 2*(x*z+w*y)],
         [2*(x*y+w*z), 1-2*(x*x+z*z), 2*(y*z-w*x)],
         [2*(x*z-w*y), 2*(y*z+w*x), 1-2*(x*x+y*y)]]
    indices, signs = [1, 2, 0], [1, -1, -1]
    return [signs[i]*signs[j]*r[indices[i]][indices[j]] for j in range(3) for i in range(3)]


def check_records(manifest, capture, manifest_hash, pilot_eye, throws):
    if capture['manifest_sha256'] != manifest_hash:
        raise ValueError('capture used another manifest')
    expected = {(frame['id'], view): frame for frame in manifest['frames'] for view in ('pilot', 'inspect')}
    records = capture['frames']
    camera = capture['camera_contract']
    if len(records) != len(expected) or len({(r['id'], r['view']) for r in records}) != len(expected):
        raise ValueError('missing or duplicate captures')
    for record in records:
        key = record['id'], record['view']
        if key not in expected:
            raise ValueError('unexpected capture')
        frame = expected[key]
        if record['tick'] != frame['tick'] or record['time_s'] != frame['time_s']:
            raise ValueError('capture tick/time mismatch')
        close(record['state'], frame['state'], 0, 'source state mismatch')
        state = frame['state']
        cg = [state[1], -state[2], -state[0]]
        close(record['rendered_cg'], cg, 3e-5, 'CG/root datum mismatch')
        close(record['root_basis'], render_basis(state[6:10]), 1e-6, 'attitude/frame mapping mismatch')
        close([record['shader_clock_s']], [frame['time_s'] % 1024], 1e-6, 'shader clock mismatch')
        angle_error = (record['prop_angle_rad'] - frame['prop_angle_rad'] + math.pi) % math.tau - math.pi
        close([angle_error], [0], 1e-6, 'propeller phase mismatch')
        if record['surfaces'] != frame['surfaces']:
            raise ValueError('servo commands mismatch')
        c = frame['surfaces']
        # Stik's verified symmetric local hinge contract, independently applied.
        for hinge, command, axis, sign, limit in [
            ('aileron_right', c['roll'], 0, -1, throws['aileron']),
            ('aileron_left', c['roll'], 0, 1, throws['aileron']),
            ('elevator', c['pitch'], 0, -1, throws['elevator']),
            ('rudder', c['yaw'], 1, 1, throws['rudder'])]:
            expected_rotation = [0.0, 0.0, 0.0]
            expected_rotation[axis] = sign * math.radians(limit * command)
            close(record['hinge_rotations'][hinge], expected_rotation, 1e-6, 'actual hinge rotation mismatch')
        if record['sim_tick_before'] != 0 or record['sim_tick_after'] != 0:
            raise ValueError('rendering advanced simulation')
        if record['shadow_visible'] is not True or record['background_shadow_visible'] is not True:
            raise ValueError('shadow was not retained in both captures')
        if record['cg_behind'] or not (0 < record['cg_pixel'][0] < 960 and 0 < record['cg_pixel'][1] < 540):
            raise ValueError('aircraft CG outside view')
        if not math.isfinite(record['fov_deg']) or not 0 < record['fov_deg'] < 180:
            raise ValueError('invalid field of view')
        if record['view'] == 'pilot':
            close(record['camera_position'], pilot_eye, 1e-6, 'pilot eye moved')
            distance = math.dist(record['rendered_cg'], pilot_eye)
            expected_fov = math.degrees(2*math.atan(camera['auto_zoom_span']*540/(2*distance*camera['target_px'])))
            expected_fov = min(camera['base_fov_deg'], max(camera['min_fov_deg'], expected_fov))
        else:
            basis, origin, offset = record['root_basis'], record['root_origin'], camera['inspect_offset']
            expected_eye = [origin[i]+sum(basis[j*3+i]*offset[j] for j in range(3)) for i in range(3)]
            close(record['camera_position'], expected_eye, 4e-5, 'inspect camera offset mismatch')
            expected_fov = camera['base_fov_deg']
        close([record['fov_deg']], [expected_fov], 1e-5, 'camera FOV mismatch')
        close(record['cg_pixel'], [480,270], .02, 'camera aim mismatch')
        for field in ('png', 'background_png'):
            if Path(record[field]).name != record[field] or not record[field].endswith('.png'):
                raise ValueError('unsafe capture filename')


def check_images(directory, records, repeat):
    results = []
    for r in records:
        files = [Path(directory)/r[key] for key in ('png', 'background_png')]
        pictures = [Image.open(p).convert('RGB') for p in files]
        if any(im.size != (960, 540) for im in pictures):
            raise ValueError('wrong image dimensions')
        if any(max(hi-lo for lo, hi in im.getextrema()) < 8 for im in pictures):
            raise ValueError('blank capture')
        difference = ImageChops.difference(*pictures)
        mask = difference.convert('L').point(lambda v: 255 if v else 0)
        count = mask.histogram()[255]
        if count == 0:
            raise ValueError('airplane ablation has no visible pixels')
        hashes = [hashlib.sha256(p.read_bytes()).hexdigest() for p in files]
        for p, digest in zip(files, hashes):
            if hashlib.sha256((Path(repeat)/p.name).read_bytes()).hexdigest() != digest:
                raise ValueError('repeated render differs')
        results.append(dict(id=r['id'], view=r['view'], changed_pixels=count,
                            changed_bounds=difference.getbbox(), sha256=hashes[0], background_sha256=hashes[1]))
    return results


def check_kit(manifest_path, first, second, pilot_eye, throws):
    manifest_path, first, second = map(Path, (manifest_path, first, second))
    manifest = json.loads(manifest_path.read_text())
    digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    a, b = [json.loads((folder/'captures.json').read_text()) for folder in (first, second)]
    check_records(manifest, a, digest, pilot_eye, throws)
    check_records(manifest, b, digest, pilot_eye, throws)
    if a != b:
        raise ValueError('repeated camera/pose manifests differ')
    return dict(format='openrc-circuit-capture-proof v1', captures=len(a['frames']),
                manifest_sha256=digest, repeated=True, physics_advanced=False,
                images=check_images(first, a['frames'], second))
