"""Nested aero timers, installed only in a disposable prepared-cost project."""
from pathlib import Path

TIMERS = ('aero_blend', 'aero_global', 'aero_local', 'aero_local_setup',
          'aero_local_angles', 'aero_local_strips', 'aero_local_tails', 'aero_global_downwash')

ROUTES = ('aero_route_global_only', 'aero_route_local_only', 'aero_route_mixed')


def replace(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError(f'Expected one aero instrumentation anchor: {old!r}')
    return source.replace(old, new, 1)


def start(name, indent='\t'):
    return f'{indent}var {name}: int = Time.get_ticks_usec() if Cost.enabled else 0\n'


def stop(name, timer, indent='\t'):
    return f'{indent}if Cost.enabled:\n{indent}\tCost.add("{timer}", Time.get_ticks_usec() - {name})\n'


def instrument(app: Path):
    path = app / 'physics/aero.gd'
    source = replace(path.read_text(), 'extends RefCounted',
        'extends RefCounted\nconst Cost = preload("res://tests/e0b6p_attribution/profiler.gd")')
    source = replace(source, '\t\tvar tail: Dictionary = model.surfaces.horizontal',
        start('cost_downwash', '\t\t') + '\t\tvar tail: Dictionary = model.surfaces.horizontal')
    correction = '\t\tco_pitch -= lag_cl * (float(tail.position[0]) - float(ref.arp_le[0])) / c'
    source = replace(source, correction, correction + '\n' + stop('cost_downwash', 'aero_global_downwash', '\t\t').rstrip())
    # Restrict anchors to _local_loads; helpers also have similar strip calculations.
    left, rest = source.split('static func _local_loads(', 1)
    local, right = rest.split('\n\n## One tail surface', 1)
    local = replace(local, '\tvar p: float = s[RB.RATE]', start('cost_setup') + '\tvar p: float = s[RB.RATE]')
    local = replace(local, '\tvar angles := PackedFloat64Array()',
        stop('cost_setup', 'aero_local_setup') + start('cost_angles') + '\tvar angles := PackedFloat64Array()')
    local = replace(local, '\tvar e_map: PackedFloat64Array = env.get("induced_map", PackedFloat64Array())',
        stop('cost_angles', 'aero_local_angles') + start('cost_strips') +
        '\tvar e_map: PackedFloat64Array = env.get("induced_map", PackedFloat64Array())')
    local = replace(local, '\tvar tail_limit: float = surfaces.tail_local_limit',
        stop('cost_strips', 'aero_local_strips') + start('cost_tails') +
        '\tvar tail_limit: float = surfaces.tail_local_limit')
    local = replace(local, '\treturn PackedFloat64Array([fx_sum, fy_sum, fz_sum, mx_sum, my_sum, mz_sum])',
        stop('cost_tails', 'aero_local_tails') +
        '\treturn PackedFloat64Array([fx_sum, fy_sum, fz_sum, mx_sum, my_sum, mz_sum])')
    source = left + 'static func _local_loads(' + local + '\n\n## One tail surface' + right
    left, loads = source.split('static func loads(', 1)
    for expression, timer, varname in (
        ('var blend := local_flow_weight(s, air, d, model)', 'aero_blend', 'cost_blend'),
        ('var local := _local_loads(s, air, d, model, rho, downwash_cl)', 'aero_local', 'cost_local'),
        ('var global := _global_loads(s, air, d, model, rho, downwash_cl)', 'aero_global', 'cost_global'),
    ):
        loads = replace(loads, '\t' + expression, start(varname) + '\t' + expression + '\n' + stop(varname, timer).rstrip())
    for expression in ('_global_loads(s, air, d, model, rho)', '_global_loads(s, air, d, model, rho, downwash_cl)'):
        loads = replace(loads, '\t\treturn ' + expression,
            start('cost_return', '\t\t') + '\t\tvar cost_result := ' + expression + '\n' +
            stop('cost_return', 'aero_global', '\t\t') + '\t\tif Cost.enabled:\n\t\t\tCost.add("aero_route_global_only", 0)\n\t\treturn cost_result')
    loads = replace(loads, '\t\treturn local', '\t\tif Cost.enabled:\n\t\t\tCost.add("aero_route_local_only", 0)\n\t\treturn local')
    loads = replace(loads, '\treturn global', '\tif Cost.enabled:\n\t\tCost.add("aero_route_mixed", 0)\n\treturn global')
    path.write_text(left + 'static func loads(' + loads)


def reduce(profile, ticks):
    """Validate every nested bucket before subtraction; absent branches are zero."""
    c, e = profile['calls'], profile['elapsed_usec']
    all_calls = 4 * ticks
    if c.get('aero_blend') != all_calls:
        raise RuntimeError('Missing aero blend calls')
    local, glob = c.get('aero_local', 0), c.get('aero_global', 0)
    if not (0 <= local <= all_calls and 0 <= glob <= all_calls and all_calls <= local + glob <= 2 * all_calls):
        raise RuntimeError('Invalid local/global aero branch counts')
    global_only, local_only, mixed = (c.get(name, 0) for name in ROUTES)
    if global_only + local_only + mixed != all_calls or local != local_only + mixed or glob != global_only + mixed:
        raise RuntimeError('Aero timers disagree with independent return-branch counters')
    if any(e.get(name, 0) != 0 for name in ROUTES):
        raise RuntimeError('Aero return-branch counters cannot contain durations')
    for name in TIMERS[3:7]:
        if c.get(name, 0) != local:
            raise RuntimeError(f'Missing local aero phase: {name}')
    if c.get('aero_global_downwash', 0) != glob:
        raise RuntimeError('Missing global downwash correction calls')
    def value(name):
        return e[name] if c.get(name, 0) else 0
    result = {name: value(name) for name in TIMERS if name not in ('aero_local', 'aero_global')}
    result['aero_local_remainder'] = value('aero_local') - sum(value(n) for n in TIMERS[3:7])
    result['aero_global_other'] = value('aero_global') - value('aero_global_downwash')
    result['aero_dispatch_remainder'] = e['aero_loads'] - value('aero_local') - value('aero_global') - value('aero_blend')
    if min(result.values()) < 0 or sum(result.values()) != e['aero_loads']:
        raise RuntimeError('Overlapping aero timers')
    return {name: value / ticks for name, value in result.items()}
