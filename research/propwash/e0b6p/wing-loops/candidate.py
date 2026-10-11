"""Loop-invariant work only; retain every floating-point expression and sum order."""


def replace(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError(f'Expected one wing-loop anchor: {old!r}')
    return source.replace(old, new, 1)


def candidate_source(source: str) -> str:
    start = 'static func wing_lift_coefficient('
    end = '\n\nstatic func loads('
    if source.count(start) != 1 or source.count(end) != 1:
        raise RuntimeError('Ambiguous wing coefficient function scope')
    before, wing = source.split(start, 1)
    wing, after = wing.split(end, 1)
    wing = replace(wing, '\tvar aileron_effect: float = surfaces.wing_aileron_effectiveness',
        '\tvar aileron_effect: float = surfaces.wing_aileron_effectiveness\n'
        '\t# E0b6p: values are constant within this evaluation; no cross-stage cache.\n'
        '\tvar da_right: float = float(d.aileron_right)\n'
        '\tvar da_left: float = float(d.aileron_left)\n'
        '\tvar has_twist: bool = not twist.is_empty()\n'
        '\tvar cl0: float = float(a.CL0)\n'
        '\tvar cla: float = float(a.CLa)')
    wing = replace(wing, 'var da: float = float(d.aileron_right) if y > 0 else float(d.aileron_left)',
                   'var da: float = da_right if y > 0 else da_left')
    wing = replace(wing, '\t\tif not twist.is_empty():', '\t\tif has_twist:')
    wing = replace(wing, 'env.get("strip_slope", a.CLa)', 'env.get("strip_slope", cla)')
    wing = replace(wing, 'base = float(a.CL0) + float(a.CLa) * effective', 'base = cl0 + cla * effective')
    source = before + start + wing + end + after
    old = '\t\t\tvar mapped := 0.0\n\t\t\tfor k in stations:\n\t\t\t\tmapped += e_map[i * stations + k] * angles[k]'
    new = '\t\t\tvar mapped := 0.0\n\t\t\tvar row_start: int = i * stations\n\t\t\tfor k in stations:\n\t\t\t\tmapped += e_map[row_start + k] * angles[k]'
    if source.count(old) != 2:
        raise RuntimeError('Expected the local-strip and wing-coefficient map loops')
    return source.replace(old, new)
