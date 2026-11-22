#!/usr/bin/env python3
"""Inspect and validate an offline trailer shot plan; no simulator is launched.

Examples:
  python3 tools/trailer/shot_plan.py --source-root /path/to/OpenRCsimulator validate
  python3 tools/trailer/shot_plan.py --source-root /path/to/OpenRCsimulator show R4-40
  python3 tools/trailer/shot_plan.py --source-root /path/to/OpenRCsimulator map R4-40 --out /tmp/lake.svg
  python3 tools/trailer/shot_plan.py camera-recipe R4-40 --out /tmp/lake-camera.json

The file is a blocking plan, not flight, collision, camera or visual evidence.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import html
import json
import math
import re
import sys
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parents[2]
DEFAULT_PLAN = REPO / 'docs/plans/trailer-v2/shot-plan-r6.json'
FIELD = 'app/data/fields/default.json'
TRACK = 'app/data/ground_vehicle/airfield_track.json'
AIRCRAFT_CATALOG = 'app/app_state/aircraft_catalog.gd'
VEHICLE_ROSTER = 'app/app_state/vehicle_roster.gd'
AIRSHIP_CATALOG = 'app/vehicles/airship/airship_catalog.gd'
MULTIROTOR_CATALOG = 'app/vehicles/multirotor/multirotor_catalog.gd'
GROUND_DATA = 'app/physics/ground_vehicle/vehicle_data.gd'
# R5 director and --livery-cycle order; deliberately not the source manifest order.
R5_LIVERY_ORDER = ('midnight', 'p40', 'japan', 'luftwaffe', 'italy', 'scarlet',
                   'thunderbirds', 'blueangels', 'chrome', 'carbon', 'spectrum', 'splash', 'three_tone')


class PlanError(ValueError):
    pass


def fail(message):
    raise PlanError(message)


def read_snapshot(path):
    """Parse and identify one byte snapshot, including during concurrent edits."""
    def bad_constant(value):
        fail(f'{path}: non-finite JSON number {value}')
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result: fail(f'{path}: duplicate JSON key {key!r}')
            result[key] = value
        return result
    try:
        data = Path(path).read_bytes()
        parsed = json.loads(data.decode('utf-8'), parse_constant=bad_constant,
                            object_pairs_hook=unique_object)
        return parsed, hashlib.sha256(data).hexdigest()
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f'{path}: {exc}')


def read_json(path):
    return read_snapshot(path)[0]


def source_path(root, value):
    if not isinstance(value, str) or not value or '\\' in value:
        fail(f'invalid repo-relative path: {value!r}')
    p = PurePosixPath(value)
    if p.is_absolute() or any(part in ('..', '.') for part in p.parts) or str(p) != value:
        fail(f'path must be normalized and repo-relative: {value!r}')
    root = Path(root).resolve()
    resolved = (root / value).resolve()
    if not resolved.is_relative_to(root):
        fail(f'path escapes source root: {value!r}')
    if not resolved.is_file():
        fail(f'missing source file: {value} under {root}')
    return resolved


def finite(value):
    if type(value) not in (int, float): return False
    try: return math.isfinite(value)
    except OverflowError: return False


def finite_tree(value, at='$'):
    if type(value) is float and not math.isfinite(value):
        fail(f'{at}: non-finite number')
    if isinstance(value, dict):
        for key, v in value.items(): finite_tree(v, f'{at}.{key}')
    elif isinstance(value, list):
        for i, v in enumerate(value): finite_tree(v, f'{at}[{i}]')


def obj(value, at):
    if not isinstance(value, dict): fail(f'{at}: expected object')
    return value


def arr(value, at):
    if not isinstance(value, list): fail(f'{at}: expected array')
    return value


def string(value, at, empty=False):
    if not isinstance(value, str) or (not empty and not value.strip()):
        fail(f'{at}: expected {"string" if empty else "nonempty string"}')
    return value


def integer(value, at):
    if type(value) is not int: fail(f'{at}: expected integer')
    return value


def nullable_string(value, at):
    if value is not None: string(value, at, empty=True)


def required(record, keys, at):
    missing = [key for key in keys if key not in record]
    if missing: fail(f'{at}: missing required fields: {", ".join(missing)}')


def pinned_text(source_root, hashes, path):
    if path not in hashes: fail(f'stock catalog source has no pinned hash: {path}')
    return source_path(source_root, path).read_text(encoding='utf-8')


def literal_registry(source_root, hashes, path, declaration):
    """Read bounded literal fields from a pinned GDScript registry.

    Supports the present multiline array of dictionary records only. Dynamic or
    duplicate fields, a changed layout, or a missing field fail closed. The
    player's explicit selection flag is honored; nothing here proves flight eligibility.
    """
    text = pinned_text(source_root, hashes, path)
    start = re.compile(r'^const\s+' + re.escape(declaration) + r'\s*:=\s*\[\s*(?:#.*)?$', re.M)
    matches = list(start.finditer(text))
    if len(matches) != 1: fail(f'{path}: unrecognized {declaration} declaration')
    tail = text[matches[0].end():]
    end = re.search(r'^\]\s*(?:#.*)?$', tail, re.M)
    if not end: fail(f'{path}: unterminated {declaration} declaration')
    records = []; active = False; fields = {}
    for line in tail[:end.start()].splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#'): continue
        if not active:
            if stripped != '{': fail(f'{path}: unrecognized {declaration} record opening')
            active = True; fields = {}
        elif stripped in ('}', '},'):
            needs = ('id', 'data', 'visual_family') if declaration == 'ENTRIES' else ('id', 'family')
            if any(key not in fields for key in needs): fail(f'{path}: {declaration} record lacks literal {needs}')
            records.append(fields); active = False
        elif re.match(r'^(id|data|visual_family|player_selectable)\s*=', stripped):
            name = re.match(r'^([a-z_]+)\s*=', stripped).group(1)
            value = stripped.split('=', 1)[1].lstrip()
            if name in fields: fail(f'{path}: duplicate {name} in {declaration}')
            if name == 'player_selectable':
                match = re.match(r'^(true|false)\s*,', value)
                if not match: fail(f'{path}: {declaration} contains a non-literal {name}')
                fields[name] = match.group(1) == 'true'
            else:
                match = re.match(r'^"([^"\\]*)"\s*,', value)
                if not match: fail(f'{path}: {declaration} contains a non-literal {name}')
                fields[name] = match.group(1)
                if declaration == 'ACTIVITIES' and name == 'id':
                    family = re.match(r'\s*family\s*=\s*(GROUND|AIRSHIP|MULTIROTOR)\s*,', value[match.end():])
                    if not family: fail(f'{path}: unrecognized activity family binding')
                    fields['family'] = family.group(1)
        elif stripped in ('{', '[', ']', '],') or re.search(r'=\s*[\[{]\s*(?:#.*)?$', stripped):
            fail(f'{path}: unsupported nested {declaration} structure')
    ids = [record['id'] for record in records]
    if active or not records or len(set(ids)) != len(ids):
        fail(f'{path}: malformed or duplicate IDs in {declaration}')
    return records


def literal_constant(text, name, path):
    pattern = r'^const[ \t]+' + re.escape(name) + r'[ \t]*:=[ \t]*"([^"\\]*)"[ \t]*(?:#.*)?$'
    matches = re.findall(pattern, text, re.M)
    if len(matches) != 1: fail(f'{path}: unrecognized literal {name} declaration')
    return matches[0]


def res_path(value, at):
    if not value.startswith('res://'): fail(f'{at}: expected a res:// data path')
    suffix = value[len('res://'):]
    path = PurePosixPath(suffix)
    if not suffix or path.is_absolute() or '..' in path.parts or str(path) != suffix or '\\' in suffix:
        fail(f'{at}: malformed res:// data path')
    return 'app/' + suffix


def stock_bindings(source_root, hashes):
    aircraft = literal_registry(source_root, hashes, AIRCRAFT_CATALOG, 'ENTRIES')
    activities = literal_registry(source_root, hashes, VEHICLE_ROSTER, 'ACTIVITIES')
    roster_text = pinned_text(source_root, hashes, VEHICLE_ROSTER)
    for symbol, value in (('GROUND', 'ground'), ('AIRSHIP', 'airship'), ('MULTIROTOR', 'multirotor')):
        if literal_constant(roster_text, symbol, VEHICLE_ROSTER) != value:
            fail(f'{VEHICLE_ROSTER}: unsupported {symbol} family constant')
    catalog_text = pinned_text(source_root, hashes, AIRCRAFT_CATALOG)
    selectable_pattern = (r'^static func is_player_selectable\(id: String\) -> bool:[ \t]*\n'
        r'[ \t]+var e := entry\(canonical_id\(id\)\)[ \t]*\n'
        r'[ \t]+return not e\.is_empty\(\) and bool\(e\.get\("player_selectable", true\)\)[ \t]*$')
    if not re.search(selectable_pattern, catalog_text, re.M):
        fail(f'{AIRCRAFT_CATALOG}: unrecognized player-selectable default')
    bindings = {}
    for record in aircraft:
        bindings[record['id']] = {'data_path': res_path(record['data'], AIRCRAFT_CATALOG),
            'model_family': record['visual_family'], 'player_selectable': record.get('player_selectable', True)}

    airship = pinned_text(source_root, hashes, AIRSHIP_CATALOG)
    quad = pinned_text(source_root, hashes, MULTIROTOR_CATALOG)
    ground = pinned_text(source_root, hashes, GROUND_DATA)
    airship_id = literal_constant(airship, 'STOCK_ID', AIRSHIP_CATALOG)
    quad_id = literal_constant(quad, 'ID', MULTIROTOR_CATALOG)
    ground_paths = {'DEFAULT_PATH': res_path(literal_constant(ground, 'DEFAULT_PATH', GROUND_DATA), GROUND_DATA),
        'MONSTER_CAR_2_PATH': res_path(literal_constant(ground, 'MONSTER_CAR_2_PATH', GROUND_DATA), GROUND_DATA)}
    # These exact declarations are the two current load_vehicle branches; do not infer
    # mappings if the source changes shape or introduces another branch.
    body_match = re.search(r'^static func load_vehicle\(vehicle_id: String\) -> Dictionary:[ \t]*\n(.*?)(?=^static func |\Z)', ground, re.M | re.S)
    default_match = re.search(r'^static func load_default\(\) -> Dictionary:[ \t]*\n[ \t]+return load_file\(DEFAULT_PATH\)[ \t]*$', ground, re.M)
    if not body_match or not default_match: fail(f'{GROUND_DATA}: unrecognized ground loader')
    body = body_match.group(1)
    lines = [line.strip() for line in body.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    if len(lines) != 7 or lines[0] != 'match vehicle_id:' or lines[-2] != '_:' \
            or not lines[-1].startswith('return _result('):
        fail(f'{GROUND_DATA}: unrecognized ground vehicle mapping structure')
    case_pattern = r'^[ \t]*"([A-Za-z0-9_-]+)"[ \t]*:[ \t]*\n[ \t]*return[ \t]+(load_default\(\)|load_file\(MONSTER_CAR_2_PATH\))[ \t]*$'
    cases = re.findall(case_pattern, body, re.M)
    case_names = re.findall(r'^[ \t]*"([^"]+)"[ \t]*:[ \t]*$', body, re.M)
    if len(cases) != 2 or sorted(case_names) != sorted(x[0] for x in cases) \
            or sorted(x[1] for x in cases) != ['load_default()', 'load_file(MONSTER_CAR_2_PATH)'] \
            or not re.search(r'^[ \t]*_:[ \t]*$', body, re.M):
        fail(f'{GROUND_DATA}: unrecognized ground vehicle mapping')
    ground_ids = {name: ground_paths['DEFAULT_PATH' if action == 'load_default()' else 'MONSTER_CAR_2_PATH']
                  for name, action in cases}
    family_ids = {'GROUND': set(), 'AIRSHIP': set(), 'MULTIROTOR': set()}
    for record in activities:
        vid, family = record['id'], record['family']
        if vid in bindings: fail('stock catalog and activity registry contain duplicate IDs')
        family_ids[family].add(vid)
        if family == 'GROUND' and vid in ground_ids:
            data_path, visual_family = ground_ids[vid], vid
        elif family == 'AIRSHIP' and vid == airship_id:
            data_path = res_path(literal_constant(airship, 'DATA_PATH', AIRSHIP_CATALOG), AIRSHIP_CATALOG)
            visual_family = literal_constant(airship, 'VISUAL_FAMILY', AIRSHIP_CATALOG)
        elif family == 'MULTIROTOR' and vid == quad_id:
            data_path = res_path(literal_constant(quad, 'DATA_PATH', MULTIROTOR_CATALOG), MULTIROTOR_CATALOG)
            visual_family = vid
        else: fail(f'{VEHICLE_ROSTER}: unsupported activity binding for {vid!r}')
        bindings[vid] = {'data_path': data_path, 'model_family': visual_family, 'player_selectable': True}
    if family_ids != {'GROUND': set(ground_ids), 'AIRSHIP': {airship_id}, 'MULTIROTOR': {quad_id}}:
        fail(f'{VEHICLE_ROSTER}: activity bindings do not match pinned source catalogs')
    return bindings


def pointer_get(data, pointer):
    if pointer == '': return data
    if not isinstance(pointer, str) or not pointer.startswith('/'):
        fail(f'invalid JSON pointer: {pointer!r}')
    cur = data
    for part in pointer[1:].split('/'):
        if re.search(r'~(?![01])', part): fail(f'invalid JSON pointer escape: {pointer!r}')
        key = part.replace('~1', '/').replace('~0', '~')
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        elif isinstance(cur, list) and re.fullmatch(r'0|[1-9][0-9]*', key) and int(key) < len(cur):
            cur = cur[int(key)]
        else:
            fail(f'JSON pointer {pointer!r} does not exist')
    return cur


def eq_json(a, b):
    # Keep booleans distinct from numbers while allowing 1 and 1.0 as JSON numbers.
    if type(a) is bool or type(b) is bool: return type(a) is type(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(eq_json(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(eq_json(x, y) for x, y in zip(a, b))
    return a == b


def story_rows(path, fps):
    text = path.read_text(encoding='utf-8')
    rx = re.compile(r'^\|\s*(R4-\d\d[a-r]?)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*[\d.]+\s*\|\s*([GUPE])\s*\|', re.M)
    rows = []
    for shot_id, start, end, source_class in rx.findall(text):
        bounds = [float(start) * fps, float(end) * fps]
        if any(not x.is_integer() for x in bounds): fail(f'{path}: non-frame storyboard boundary for {shot_id}')
        rows.append((shot_id, *(int(x) for x in bounds), source_class))
    if len(rows) != 62 or len(set(x[0] for x in rows)) != 62:
        fail(f'{path}: expected 62 unique storyboard cut rows, found {len(rows)}')
    return rows


def points(record, at, duration, spaces):
    obj(record, at)
    if record.get('space') not in spaces: fail(f'{at}.space: unsupported coordinate space')
    string(record.get('notes'), f'{at}.notes', empty=True)
    values = arr(record.get('points'), f'{at}.points')
    if record['space'] == 'none' and values: fail(f'{at}: none space cannot contain positions')
    last = -1
    for i, p in enumerate(values):
        label = f'{at}.points[{i}]'
        obj(p, label)
        frame = integer(p.get('frame'), f'{label}.frame')
        if not 0 <= frame <= duration or frame <= last:
            fail(f'{label}.frame: local frames must increase strictly within 0..{duration}')
        last = frame
        v = arr(p.get('position_m'), f'{label}.position_m')
        if len(v) != 3 or not all(finite(x) for x in v):
            fail(f'{label}.position_m: expected three finite numbers')
    return values


def _ids_from_manifest(data, at):
    rows = arr(obj(data, at).get('liveries'), f'{at}.liveries')
    ids = [string(obj(r, at).get('id'), f'{at}.liveries.id') for r in rows]
    if not ids or len(set(ids)) != len(ids): fail(f'{at}: no liveries or duplicate livery IDs')
    return ids


def validate_skin(skin, cast, source_root, hashes, at):
    skin = obj(skin, at)
    required(skin, ('kind','asset_id','selection_value','label'), at)
    kind = skin.get('kind')
    if kind not in ('paint', 'manifest', 'factory', 'airship', 'inspector', 'source', 'none'):
        fail(f'{at}.kind: unknown skin kind {kind!r}')
    asset = skin.get('asset_id'); selection = skin.get('selection_value')
    nullable_string(asset, f'{at}.asset_id'); nullable_string(selection, f'{at}.selection_value')
    string(skin.get('label'), f'{at}.label', empty=True)
    path = skin.get('source_path')
    if path is not None:
        source_path(source_root, path)
        if path not in hashes: fail(f'{at}.source_path: source has no pinned hash: {path}')
    if kind in ('paint', 'manifest', 'airship'):
        if path is None: fail(f'{at}: {kind} requires source_path')
        string(asset, f'{at}.asset_id')
        if kind == 'paint':
            data = obj(read_json(source_path(source_root, path)), at)
            family = cast.get('model_family')
            vehicles = obj(data.get('vehicles'), f'{at}.vehicles')
            if family not in vehicles: fail(f'{at}: unknown paint family {family!r}')
            ids = [r.get('id') for r in arr(obj(vehicles[family], at).get('skins'), f'{at}.skins') if isinstance(r, dict)]
            if asset not in ids or selection != asset: fail(f'{at}: unknown paint ID or incorrect selection {asset!r}/{selection!r}')
        elif kind == 'manifest':
            data = obj(read_json(source_path(source_root, path)), at)
            if data.get('family_id') != cast.get('model_family'):
                fail(f'{at}: manifest family does not match cast model_family')
            ids = _ids_from_manifest(data, at)
            if asset not in ids or selection != ('' if asset == ids[0] else asset):
                fail(f'{at}: unknown manifest ID or incorrect selection {asset!r}/{selection!r}')
        else:
            text = source_path(source_root, path).read_text(encoding='utf-8')
            match = re.search(r'^const\s+SKIN_IDS\s*:=\s*\[([^\]]*)\]', text, re.M)
            if not match: fail(f'{at}: SKIN_IDS source declaration not found')
            try: ids = json.loads('[' + match.group(1) + ']')
            except json.JSONDecodeError: fail(f'{at}: invalid quoted SKIN_IDS declaration')
            if asset not in ids or selection != asset: fail(f'{at}: unknown airship skin or incorrect selection')
    elif kind == 'factory' and selection != '':
        fail(f'{at}: factory selection must be empty')


def _xy(p):
    return (float(p[0]), float(p[1]))


def _cross(a, b): return a[0]*b[1] - a[1]*b[0]


def _on_segment(p, a, b):
    ab = (b[0]-a[0], b[1]-a[1]); ap = (p[0]-a[0], p[1]-a[1])
    return abs(_cross(ab, ap)) < 1e-9 and min(a[0],b[0])-1e-9 <= p[0] <= max(a[0],b[0])+1e-9 and min(a[1],b[1])-1e-9 <= p[1] <= max(a[1],b[1])+1e-9


def inside_polygon(p, polygon):
    # Boundary included for this geometry estimate, not a contact or flotation test.
    inside = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if _on_segment(p, a, b): return True
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    return inside


def segment_water_length(a, b, polygon):
    """Length inside a possibly concave polygon, clipped to this finite segment."""
    a = _xy(a); b = _xy(b); d = (b[0]-a[0], b[1]-a[1]); dd = d[0]*d[0]+d[1]*d[1]
    if dd == 0: return 0.0
    ts = [0.0, 1.0]
    for c, e in zip(polygon, polygon[1:] + polygon[:1]):
        v = (e[0]-c[0],e[1]-c[1]); w = (c[0]-a[0],c[1]-a[1]); den = _cross(d,v)
        if abs(den) < 1e-12:
            if abs(_cross(w,d)) < 1e-10:
                for q in (c,e):
                    t = ((q[0]-a[0])*d[0]+(q[1]-a[1])*d[1])/dd
                    if 0 <= t <= 1: ts.append(t)
            continue
        t, u = _cross(w,v)/den, _cross(w,d)/den
        if -1e-12 <= t <= 1+1e-12 and -1e-12 <= u <= 1+1e-12: ts.append(max(0.0,min(1.0,t)))
    ts = sorted(set(round(t, 12) for t in ts))
    fraction = sum(y-x for x,y in zip(ts, ts[1:]) if inside_polygon((a[0]+d[0]*(x+y)/2,a[1]+d[1]*(x+y)/2), polygon))
    return math.sqrt(dd)*fraction


def lake_polygon(lake):
    lake = obj(lake, 'lake source'); origin = obj(lake.get('origin'), 'lake.origin')
    n,e = origin.get('north_m'),origin.get('east_m')
    if not finite(n) or not finite(e): fail('lake origin must be finite')
    offsets = arr(lake.get('shoreline_offsets_ne_m'), 'lake.shoreline_offsets_ne_m')
    if len(offsets) < 3 or any(not isinstance(p,list) or len(p)!=2 or not all(finite(x) for x in p) for p in offsets):
        fail('lake shoreline requires at least three finite NE offsets')
    return [(n+p[0],e+p[1]) for p in offsets]


def water_analysis(plan, shot, source_root):
    cfg = obj(plan.get('lake_analysis'), 'lake_analysis')
    source = string(cfg.get('source_path'), 'lake_analysis.source_path')
    speed = cfg.get('nominal_speed_mps')
    if not finite(speed) or speed <= 0: fail('lake_analysis.nominal_speed_mps must be finite and positive')
    if source not in plan['source_files']: fail('lake_analysis source has no pinned hash')
    polygon = lake_polygon(read_json(source_path(source_root, source)))
    block = shot['blocking']; ps = block['points']
    result = {'shot_id': shot['id'], 'clip_seconds': (shot['out_frame']-shot['in_frame'])/plan['fps'],
              'nominal_speed_mps': speed, 'status': 'not_applicable',
              'qualification': 'Horizontal straight segments between proposed targets at nominal speed only; altitude, flight, clearance and actual time are unverified.'}
    if block['space'] != 'NED' or len(ps)<2 or any(abs(p['position_m'][0]-ps[0]['position_m'][0])>1e-9 for p in ps):
        return result
    water = sum(segment_water_length(x['position_m'], y['position_m'], polygon) for x,y in zip(ps,ps[1:]))
    length = sum(math.hypot(y['position_m'][0]-x['position_m'][0],y['position_m'][1]-x['position_m'][1]) for x,y in zip(ps,ps[1:]))
    result.update(status='calculated', blocking_line_length_m=length, water_length_m=water,
                  nominal_water_seconds=water/speed, nominal_line_seconds=length/speed)
    return result


def validate(plan, source_root, plan_root=REPO, check_script=True):
    obj(plan, 'plan'); finite_tree(plan)
    for key, expected in [('format','openrc-trailer-shot-plan'),('version',1),('fps',60),('duration_frames',9000)]:
        if not eq_json(plan.get(key), expected): fail(f'{key}: expected {expected!r}')
    if plan.get('revision') not in ('R5', 'R6'): fail('revision: expected R5 or R6')
    if plan['revision'] == 'R6':
        string(plan.get('script_path'), 'R6 script_path')
    baseline = string(plan.get('source_baseline'), 'source_baseline')
    if not re.fullmatch(r'[0-9a-f]{40}', baseline): fail('source_baseline must be a 40-character lowercase commit ID')
    hashes = obj(plan.get('source_files'), 'source_files')
    if not hashes: fail('source_files is empty')
    for path, digest in hashes.items():
        actual_path = source_path(source_root, path)
        if not isinstance(digest,str) or not re.fullmatch(r'[0-9a-f]{64}',digest): fail(f'source_files[{path}]: invalid SHA-256')
        actual = hashlib.sha256(actual_path.read_bytes()).hexdigest()
        if actual != digest: fail(f'source hash drift for {path}: expected {digest}, got {actual}')
    stock = stock_bindings(source_root, hashes)
    for i, assertion in enumerate(arr(plan.get('source_assertions'), 'source_assertions')):
        at=f'source_assertions[{i}]'; obj(assertion,at); p=string(assertion.get('path'),at+'.path')
        if p not in hashes: fail(f'{at}: assertion source has no pinned hash: {p}')
        if 'equals' not in assertion: fail(f'{at}: missing equals')
        actual=pointer_get(read_json(source_path(source_root,p)),assertion.get('pointer'))
        if not eq_json(actual, assertion['equals']): fail(f'{at}: {p}{assertion.get("pointer")} differs: {actual!r} != {assertion["equals"]!r}')
    cast = obj(plan.get('cast'),'cast'); envs = obj(plan.get('environments'),'environments')
    if not cast or not envs: fail('cast and environments must be nonempty')
    for key, c in cast.items():
        string(key,'cast key'); obj(c,f'cast.{key}')
        required(c, ('kind','vehicle_id','data_path','model_family','skin'), f'cast.{key}')
        if c.get('kind') not in ('stock','import','inspector','editorial'): fail(f'cast.{key}: unsupported kind')
        for field in ('vehicle_id','data_path','model_family'): nullable_string(c.get(field),f'cast.{key}.{field}')
        if c.get('data_path'):
            path=c['data_path']; source_path(source_root,path)
            if path not in hashes: fail(f'cast.{key}.data_path: source has no pinned hash: {path}')
        if c['kind'] == 'stock':
            vid = c['vehicle_id']
            if not isinstance(vid, str) or vid not in stock:
                fail(f'cast.{key}.vehicle_id: unknown stock source ID {vid!r}')
            expected = stock[vid]
            if not expected['player_selectable']:
                fail(f'cast.{key}.vehicle_id: source marks {vid!r} as not player selectable')
            for field in ('data_path', 'model_family'):
                if c[field] != expected[field]:
                    fail(f'cast.{key}.{field}: {c[field]!r} does not match source binding {expected[field]!r} for {vid!r}')
        validate_skin(c.get('skin'), c, source_root, hashes, f'cast.{key}.skin')
    for key, value in envs.items(): string(key,'environment key'); obj(value,f'environments.{key}')
    shots = arr(plan.get('shots'),'shots'); ids = set(); previous = 0
    for i,s in enumerate(shots):
        at=f'shots[{i}]'; obj(s,at); sid=string(s.get('id'),at+'.id')
        if sid in ids: fail(f'{at}: duplicate ID {sid}')
        ids.add(sid); start=integer(s.get('in_frame'),at+'.in_frame'); end=integer(s.get('out_frame'),at+'.out_frame')
        if start!=previous or end<=start: fail(f'{sid}: expected contiguous positive interval beginning at frame {previous}, got {start}..{end}')
        previous=end
        if s.get('source_class') not in ('G','U','P','E'): fail(f'{sid}: unknown source_class')
        cast_id = string(s.get('cast'), f'{sid}.cast')
        environment_id = string(s.get('environment'), f'{sid}.environment')
        if cast_id not in cast: fail(f'{sid}: unknown cast reference {cast_id!r}')
        if environment_id not in envs: fail(f'{sid}: unknown environment reference {environment_id!r}')
        for field in ('setup','start_condition','exit_condition','continuity','transition'): string(s.get(field),f'{sid}.{field}')
        duration=end-start
        b=obj(s.get('blocking'),f'{sid}.blocking'); string(b.get('role'),f'{sid}.blocking.role'); points(b,f'{sid}.blocking',duration,('NED','NE_surface','model_local','none'))
        if 'heading_deg' in b and not finite(b['heading_deg']): fail(f'{sid}.blocking.heading_deg: expected finite number')
        c=obj(s.get('camera'),f'{sid}.camera'); required(c, ('fov_deg',), f'{sid}.camera'); string(c.get('mode'),f'{sid}.camera.mode'); points(c,f'{sid}.camera',duration,('NED','FRU','inspector','preview','none'))
        if c.get('fov_deg') is not None and (not finite(c['fov_deg']) or not 0<c['fov_deg']<180): fail(f'{sid}.camera.fov_deg: expected null or 0 < FOV < 180')
        if c['mode'] == 'parallel_east': validate_parallel_camera(s)
        for field in ('actions','checks'):
            values=arr(s.get(field),f'{sid}.{field}')
            if not values: fail(f'{sid}.{field}: must not be empty')
            for v in values: string(v,f'{sid}.{field} entry')
        exe=obj(s.get('execution'),f'{sid}.execution')
        for field in ('route','status','notes'): string(exe.get(field),f'{sid}.execution.{field}',empty=field=='notes')
    if previous!=9000: fail(f'timeline ends at {previous}, expected 9000')
    story = source_path(plan_root, string(plan.get('storyboard_path'),'storyboard_path'))
    expected=story_rows(story,plan['fps'])
    actual=[(s['id'],s['in_frame'],s['out_frame'],s['source_class']) for s in shots]
    if actual!=expected: fail('shot IDs, frame boundaries or source classes differ from storyboard')
    previews=[s for s in shots if re.fullmatch(r'R4-42[a-r]',s['id'])]
    if len(previews)!=18 or sum(s['out_frame']-s['in_frame'] for s in previews)!=600: fail('18 preview cuts must cover 600 frames')
    byid={s['id']:s for s in shots}
    cues=arr(plan.get('livery_cues'),'livery_cues')
    if len(cues)!=13: fail('livery_cues must contain 13 records')
    orbit=byid.get('R4-39'); lake=byid.get('R4-40')
    if not orbit or not lake: fail('R4-39 and R4-40 are required')
    orbit_cast=cast[orbit['cast']]; skin=orbit_cast['skin']
    if skin['kind']!='manifest': fail('R4-39 cast must use a manifest livery')
    manifest=_ids_from_manifest(read_json(source_path(source_root,skin['source_path'])),'R4-39 manifest')
    prev=0; cueids=[]
    for i,cue in enumerate(cues):
        at=f'livery_cues[{i}]'; obj(cue,at)
        start=integer(cue.get('start_frame'),at+'.start_frame'); end=integer(cue.get('end_frame'),at+'.end_frame')
        if cue.get('shot_id')!='R4-39' or start!=prev or end<=start: fail(f'{at}: cues must cover R4-39 continuously')
        expected_length = 45 if i < 12 else 60
        if end-start != expected_length: fail(f'{at}: expected {expected_length} frames for livery schedule')
        prev=end; aid=string(cue.get('asset_id'),at+'.asset_id'); sel=cue.get('selection_value')
        if aid not in manifest or sel!=('' if aid==manifest[0] else aid): fail(f'{at}: unknown livery or incorrect selection')
        cueids.append(aid)
    if prev!=600 or len(set(cueids))!=13 or set(cueids)!=set(manifest): fail('livery cues must cover 600 frames with all 13 unique manifest IDs')
    if tuple(cueids) != R5_LIVERY_ORDER: fail('livery cue order does not match the R5 director schedule')
    finalskin=cast[lake['cast']]['skin']; last=cues[-1]
    if (finalskin.get('asset_id'),finalskin.get('selection_value'))!=(last['asset_id'],last['selection_value']): fail('final orbit skin does not match lake cast')
    links=arr(plan.get('continuity_links'),'continuity_links')
    found=False
    for i, link in enumerate(links):
        obj(link,f'continuity_links[{i}]')
        origin = string(link.get('from'), f'continuity_links[{i}].from')
        destination = string(link.get('to'), f'continuity_links[{i}].to')
        if origin not in ids or destination not in ids: fail(f'continuity_links[{i}]: unknown shot')
        string(link.get('rule'),f'continuity_links[{i}].rule')
        if (link.get('from'),link.get('to'),link.get('rule'))==('R4-39','R4-40','final_skin'): found=True
    if not found: fail('continuity_links must include R4-39 → R4-40 final_skin')
    cfg=obj(plan.get('lake_analysis'),'lake_analysis')
    if cfg.get('shot_id')!='R4-40': fail('lake_analysis must refer to R4-40')
    analysis=water_analysis(plan,lake,source_root)
    if check_script and plan.get('script_path'):
        script = source_path(plan_root, plan['script_path']).read_text(encoding='utf-8')
        begin, end = '<!-- BEGIN GENERATED SHOT CARDS -->', '<!-- END GENERATED SHOT CARDS -->'
        if script.count(begin) != 1 or script.count(end) != 1:
            fail('shooting script requires one generated shot-card block')
        actual_cards = script.split(begin,1)[1].split(end,1)[0].strip()
        if actual_cards != render_shot_cards(plan).strip():
            fail('shooting script shot cards drifted from the numeric plan; regenerate with cards')
    return {'ok': True,'shots':len(shots),'duration_frames':previous,'source_baseline':baseline,
            'source_files_verified':len(hashes),'lake_analysis':analysis}


def enrich_shot(shot):
    result=copy.deepcopy(shot)
    for key in ('blocking','camera'):
        block=result[key]
        if block['space']=='NED':
            for point in block['points']:
                n,e,d=point['position_m']; point['render_position_m']=[e,-d,-n]
    return result


def find_shot(plan, shot_id):
    for shot in plan['shots']:
        if shot['id']==shot_id: return shot
    fail(f'unknown shot ID {shot_id!r}')


def render_shot_cards(plan):
    """Readable production cards generated from the same values as recipes."""
    def tc(frame):
        seconds, sub = divmod(frame, plan['fps'])
        minutes, seconds = divmod(seconds,60)
        return f'{minutes:02}:{seconds:02}:{sub:02}'
    def marks(block):
        if not block['points']:
            return 'Native UI/preset or actual camera readback; no invented world coordinates.'
        return ' → '.join(f"{p['frame']/plan['fps']:g}s: ({', '.join(f'{v:g}' for v in p['position_m'])})"
                          for p in block['points'])
    cards=[]
    for s in plan['shots']:
        cast=plan['cast'][s['cast']]; camera=s['camera']; block=s['blocking']
        skin=cast['skin'].get('label','Not applicable')
        fov=f"FOV {camera['fov_deg']:g}°" if camera['fov_deg'] is not None else 'native preset/readback'
        cards.append(f"### {s['id']} — {cast.get('label',s['picture'])} · {tc(s['in_frame'])}–{tc(s['out_frame'])} · {s['source_class']}\n\n"
            f"**Picture:** {s['picture']}\n\n"
            f"**Cast / paint:** {cast.get('label',s['cast'])} — {skin}. **Environment:** `{s['environment']}`.\n\n"
            f"**Preparation:** {s['setup']} **At the edit’s start:** {s['start_condition']}\n\n"
            f"**Blocking ({block['space']}):** {marks(block)} {block.get('notes','')}\n\n"
            f"**Camera:** {camera['mode']}, {camera['space']}, {fov}. {marks(camera)} {camera.get('notes','')}\n\n"
            '**Action:**\n\n' + '\n'.join('- '+a for a in s['actions']) + '\n\n'
            f"**Exit / cut:** {s['exit_condition']} {s['transition']}\n\n"
            f"**Continuity:** {s['continuity']}\n\n"
            f"**Text:** {s.get('text_reference','Use the current title plan and genuine captured indicators.')}\n\n"
            f"**Implementation:** `{s['execution']['status']}` — `{s['execution']['route']}`. {s['execution']['notes']}\n\n"
            '**Accept only when:** ' + ' '.join(s['checks']) + '\n')
    return '\n'.join(line.rstrip() for line in '\n'.join(cards).splitlines()) + '\n'


def validate_parallel_camera(shot):
    """Keep illustrative camera marks consistent with the actual-CG rig law."""
    sid = shot['id']; camera = shot['camera']; block = shot['blocking']
    if camera.get('target') != 'presented_cg' or camera['space'] != 'NED' or block['space'] != 'NED':
        fail(f'{sid}: parallel camera requires NED marks and presented_cg target')
    rig = obj(camera.get('rig'), f'{sid}.camera.rig')
    if set(rig) != {'north_m', 'down_m', 'east_offset_m'}:
        fail(f'{sid}: parallel camera rig requires north_m, down_m, east_offset_m only')
    for key, value in rig.items():
        if not finite(value) or abs(value) > 100000:
            fail(f'{sid}: parallel camera {key} must be finite and within 100000 m')
    if len(camera['points']) != len(block['points']) or len(block['points']) < 2:
        fail(f'{sid}: parallel camera requires matching subject/camera marks')
    for eye, subject in zip(camera['points'], block['points']):
        expected = [rig['north_m'], subject['position_m'][1] + rig['east_offset_m'], rig['down_m']]
        if eye['frame'] != subject['frame'] or any(abs(a-b) > 1e-8 for a,b in zip(eye['position_m'], expected)):
            fail(f'{sid}: parallel camera marks disagree with actual-CG rig law')


def camera_recipe(plan, shot_id, source_root, plan_sha256):
    """Export only presentation camera settings, never a spawn or flight path.

    The caller must validate the plan first. Source-class, vehicle, environment
    and mode checks keep ground, inspector, import and panorama routes out of
    the fixed-wing capture adapter. Numeric geometry is checked again here so
    a direct API caller cannot silently export a different rig from its marks.
    """
    if not isinstance(plan_sha256, str) or not re.fullmatch(r'[0-9a-f]{64}', plan_sha256):
        fail('camera recipe requires the source plan SHA-256')
    shot = find_shot(plan, shot_id); cast = plan['cast'][shot['cast']]
    camera = shot['camera']; env = plan['environments'][shot['environment']]
    if shot['source_class'] != 'G' or cast['kind'] != 'stock' or env.get('landscape') != 'club_field':
        fail(f'{shot_id}: camera recipe supports stock G-class Club-field airplane shots only')
    source = read_json(source_path(source_root, cast['data_path']))
    if (source.get('format') != 'openrc-aircraft v2' or source.get('vehicle', 'fixed_wing') != 'fixed_wing'
            or not all(key in source for key in ('start', 'aero', 'propulsion'))):
        fail(f'{shot_id}: camera recipe requires a fixed-wing openrc-aircraft v2 source')
    fov = camera.get('fov_deg')
    if not finite(fov) or not 2 <= fov <= 120:
        fail(f'{shot_id}: capture camera FOV must be between 2 and 120 degrees')
    if camera.get('target', 'presented_cg') != 'presented_cg':
        fail(f'{shot_id}: capture camera must target presented_cg')
    recipe = {'format': 'openrc-trailer-camera', 'version': 1, 'shot_id': shot_id,
              'vehicle_id': cast['vehicle_id'], 'source_plan_sha256': plan_sha256,
              'target': 'presented_cg', 'fov_deg': fov}
    if camera['mode'] == 'fixed_tracking':
        if camera['space'] != 'NED' or len(camera['points']) != 1:
            fail(f'{shot_id}: fixed camera requires exactly one world-space eye')
        eye = camera['points'][0]['position_m']
        if len(eye) != 3 or any(not finite(v) or abs(v) > 100000 for v in eye):
            fail(f'{shot_id}: fixed camera eye must contain three bounded finite coordinates')
        recipe.update(mode='fixed_world', eye_ned_m=copy.deepcopy(eye))
    elif camera['mode'] == 'parallel_east':
        validate_parallel_camera(shot)
        recipe.update(mode='parallel_east', **camera['rig'])
    else:
        fail(f'{shot_id}: camera mode {camera["mode"]!r} has no capture recipe adapter')
    return recipe


def map_svg(plan, shot, source_root):
    env = plan['environments'][shot['environment']]
    if env.get('landscape') != 'club_field':
        fail(f'{shot["id"]}: Club-field map requires a club_field environment')
    if FIELD not in plan['source_files']: fail(f'map requires pinned {FIELD}')
    field = obj(read_json(source_path(source_root, FIELD)), 'field source')
    surfaces = arr(field.get('surfaces'), 'field.surfaces')
    runway = next((s for s in surfaces if isinstance(s, dict) and s.get('type') == 'runway'), None)
    if runway is None: fail('field has no runway')
    try:
        rn = float(runway['center_north']['value']); reast = float(runway['center_east']['value'])
        hw = float(runway['width_north_south']['value']) / 2; hl = float(runway['length_east_west']['value']) / 2
        pilot_n = float(field['pilot']['north']['value']); pilot_e = float(field['pilot']['east']['value'])
    except (KeyError, TypeError, ValueError, OverflowError): fail('field runway geometry is malformed')
    if not all(math.isfinite(x) for x in (rn, reast, hw, hl, pilot_n, pilot_e)) or hw <= 0 or hl <= 0:
        fail('field runway or pilot geometry is invalid')
    poly = lake_polygon(read_json(source_path(source_root, plan['lake_analysis']['source_path'])))
    block = shot['blocking']; camera = shot['camera']
    bp = [_xy(p['position_m']) for p in block['points']] if block['space'] in ('NED', 'NE_surface') else []
    cp = [_xy(p['position_m']) for p in camera['points']] if camera['space'] == 'NED' else []
    if not bp and not cp: fail(f'{shot["id"]}: map requires at least one Club-field NED or NE_surface point')
    ramp = None; ramp_poly = []; deck_poly = []
    if shot['id'] in ('R4-02', 'R4-32', 'R4-34'):
        if TRACK not in plan['source_files']: fail(f'map requires pinned {TRACK}')
        ramps = arr(read_json(source_path(source_root, TRACK)).get('ramps'), 'track.ramps')
        matches = [r for r in ramps if isinstance(r, dict) and r.get('id') == 'tabletop']
        if len(matches) != 1: fail('track requires exactly one tabletop ramp')
        ramp = matches[0]
        for key in ('north_m', 'east_m', 'height_m', 'approach_m', 'deck_m', 'descent_m', 'width_m'):
            if not finite(ramp.get(key)): fail(f'tabletop.{key} must be finite')
        if any(ramp[k] <= 0 for k in ('height_m', 'approach_m', 'deck_m', 'descent_m', 'width_m')):
            fail('tabletop dimensions must be positive')
        n = ramp['north_m']; e = ramp['east_m']; half_w = ramp['width_m'] / 2; half_d = ramp['deck_m'] / 2
        ramp_poly = [(n-half_w, e-half_d-ramp['approach_m']), (n+half_w, e-half_d-ramp['approach_m']),
                     (n+half_w, e+half_d+ramp['descent_m']), (n-half_w, e+half_d+ramp['descent_m'])]
        deck_poly = [(n-half_w, e-half_d), (n+half_w, e-half_d), (n+half_w, e+half_d), (n-half_w, e+half_d)]
    # Focus on the working area; a whole-field view hides metre-scale truck staging.
    bounds = bp + cp + ramp_poly
    if shot['id'] in (plan['lake_analysis']['shot_id'], 'R4-44'): bounds += poly
    pad = 4.0 if ramp else 12.0
    min_n = min(p[0] for p in bounds)-pad; max_n = max(p[0] for p in bounds)+pad
    min_e = min(p[1] for p in bounds)-pad; max_e = max(p[1] for p in bounds)+pad
    width, height = 1000, 620
    plot_x, plot_y, plot_w, plot_h = 45, 88, 910, 440
    scale = min(plot_w/(max_e-min_e), plot_h/(max_n-min_n))
    dx = plot_x+(plot_w-(max_e-min_e)*scale)/2
    dy = plot_y+(plot_h-(max_n-min_n)*scale)/2
    def pos(p): return dx+(p[1]-min_e)*scale, dy+(max_n-p[0])*scale
    def pair(p):
        x, y = pos(p); return f'{x:.2f},{y:.2f}'
    def visible(points):
        return (max(p[0] for p in points) >= min_n and min(p[0] for p in points) <= max_n
                and max(p[1] for p in points) >= min_e and min(p[1] for p in points) <= max_e)
    def polygon(points, fill, stroke):
        return f'<polygon points="{" ".join(pair(p) for p in points)}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'
    def label(point, text, color, offset=0):
        x, y = pos(point)
        return f'<text x="{x:.2f}" y="{y+offset:.2f}" fill="{color}" font-family="sans-serif" font-size="13" text-anchor="middle">{html.escape(text)}</text>'
    def trace(points, color, prefix):
        if not points: return ''
        out = [f'<polyline points="{" ".join(pair(p) for p in points)}" fill="none" stroke="{color}" stroke-width="3" stroke-dasharray="8 5"/>']
        for i, p in enumerate(points):
            x, y = pos(p); title = html.escape(f'{prefix}{i+1} · N{p[0]:g}, E{p[1]:g}')
            out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="5" fill="{color}"><title>{title}</title></circle>')
            anchor = 'end' if x > width-210 else 'start'
            tx = x-8 if anchor == 'end' else x+8
            out.append(f'<text x="{tx:.2f}" y="{y-12-(i%3)*19:.2f}" text-anchor="{anchor}" fill="{color}" font-family="sans-serif" font-size="13">{title}</text>')
        return ''.join(out)
    geography = []; shown = []
    if visible(poly):
        geography.append(polygon(poly, '#b5dfe7', '#327e8b'))
        geography.append(label((sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly)), 'Lake shoreline', '#327e8b', 25))
        shown.append('lake shoreline')
    runway_poly = [(rn-hw, reast-hl), (rn+hw, reast-hl), (rn+hw, reast+hl), (rn-hw, reast+hl)]
    if visible(runway_poly):
        geography.append(polygon(runway_poly, '#b7cdaa', '#426447'))
        if visible([(rn, reast)]): geography.append(label((rn, reast), 'Runway', '#426447', 4))
        shown.append('runway')
    if visible([(pilot_n, pilot_e)]):
        x, y = pos((pilot_n, pilot_e))
        geography.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="4" fill="#303830"/>')
        geography.append(label((pilot_n, pilot_e), 'Pilot station', '#303830', 18)); shown.append('pilot station')
    if ramp:
        geography += [polygon(ramp_poly, '#eed6a5', '#996b26'), polygon(deck_poly, '#d9af65', '#996b26')]
        geography.append(label((ramp['north_m']-ramp['width_m']/2, ramp['east_m']),
                               f'Tabletop · height {ramp["height_m"]:g} m', '#78521a', 22))
        shown.append('tabletop footprint and deck')
    title = html.escape(f'{shot["id"]} · proposed, unflown blocking')
    source_note = html.escape('Source context shown: '+(', '.join(shown) if shown else 'none in this close view')+'. Other field landmarks are outside this view.')
    ground_note = 'NE markers specify ground locations; actual supported height must be solved.' if block['space'] == 'NE_surface' else 'NED altitude and exact camera instructions are in the shot plan.'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-label="{title}">
<title>{title}</title><desc>Generated by tools/trailer/shot_plan.py map {html.escape(shot["id"])} from the {html.escape(plan["revision"])} shot plan. Source baseline {html.escape(plan["source_baseline"])}.</desc><rect width="100%" height="100%" fill="#f3f5ed"/>
<defs><clipPath id="plot"><rect x="{plot_x}" y="{plot_y}" width="{plot_w}" height="{plot_h}"/></clipPath></defs>
<g clip-path="url(#plot)">{''.join(geography)}{trace(bp,'#b4452e','B')}{trace(cp,'#7646a1','C')}</g>
<g font-family="sans-serif" fill="#243738">
<text x="28" y="31" font-size="22" font-weight="bold">{title}</text>
<text x="28" y="59" font-size="14">North ↑ · East → · Metres · Dashed lines connect proposed targets; they are not recorded trajectories.</text>
<text x="28" y="555" font-size="13">{source_note}</text>
<text x="28" y="578" font-size="13">Red B: vehicle targets · Purple C: camera targets · {ground_note}</text>
<text x="28" y="601" font-size="13">Source geography is pinned. Flight, framing, timing, contact and clearance remain unqualified.</text>
</g></svg>\n'''

def json_text(value): return json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+'\n'


def output(text, path):
    if path is None: sys.stdout.write(text); return
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path,'x',encoding='utf-8',newline='\n') as f: f.write(text)
    except OSError as exc: fail(f'cannot create output {path}: {exc}')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,default=REPO,help='checkout containing app/ (default: this repository)')
    parser.add_argument('--plan',type=Path,default=DEFAULT_PLAN,help='shot plan JSON')
    subs=parser.add_subparsers(dest='command',required=True)
    for command in ('validate','show','export','map','camera-recipe','cards'):
        p=subs.add_parser(command)
        if command in ('show','map','camera-recipe'): p.add_argument('shot_id')
        p.add_argument('--out',type=Path,help='create a new file; never overwrite')
        # Accept these options on either side of the subcommand.
        p.add_argument('--source-root',type=Path,default=argparse.SUPPRESS)
        p.add_argument('--plan',type=Path,default=argparse.SUPPRESS)
    args=parser.parse_args(argv)
    try:
        plan, plan_digest=read_snapshot(args.plan)
        summary=validate(plan,args.source_root,check_script=args.command!='cards')
        if args.command=='validate': result=json_text(summary)
        elif args.command=='cards': result=render_shot_cards(plan)
        elif args.command=='show':
            shot=find_shot(plan,args.shot_id)
            result=json_text({'shot':enrich_shot(shot),'cast':plan['cast'][shot['cast']],
                              'environment':plan['environments'][shot['environment']],
                              **({'lake_analysis':summary['lake_analysis']} if shot['id']=='R4-40' else {})})
        elif args.command=='export':
            enriched=copy.deepcopy(plan); enriched['shots']=[enrich_shot(s) for s in plan['shots']]
            enriched['derived_lake_analysis']=summary['lake_analysis']
            result=json_text(enriched)
        elif args.command=='camera-recipe':
            result=json_text(camera_recipe(plan,args.shot_id,args.source_root,plan_digest))
        else: result=map_svg(plan,find_shot(plan,args.shot_id),args.source_root)
        output(result,args.out)
        return 0
    except (PlanError,OSError,UnicodeError) as exc:
        print(f'shot-plan: {exc}',file=sys.stderr); return 2


if __name__=='__main__': raise SystemExit(main())
