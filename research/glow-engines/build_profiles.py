"""Generate standalone, explicitly estimated glow profiles and their closed contract.

These are bench candidates, not accepted aircraft data or measured engine maps.
All generated files are checked by --check. No third-party curves are redistributed.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'app/data/glow'
KINDS = ['manual', 'measured', 'borrowed', 'estimated', 'derived']
PAPER = 'https://doi.org/10.2514/6.2016-5011, Table 1; oil-inert lower bound, 25 degC'
EST = 'NITRO-01 candidate assumption; unmeasured and not physically validated'


def scalar(unit, minimum=0.0, maximum=1e100, positive=False):
    return dict(unit=unit, shape='scalar', minimum=minimum, maximum=maximum, positive=positive)


def curve(unit, maximum=1e100, positive=False, axis='rpm'):
    return dict(unit=unit, shape='curve', minimum=0.0, maximum=maximum,
                positive=positive, axis=axis)


SPEC = {
    'format': 'openrc-glow-profile-contract v1',
    'profile_format': 'openrc-glow-engine v1',
    'common': {
        'displacement_m3': scalar('m3', positive=True),
        'bore_m': scalar('m', positive=True),
        'stroke_m': scalar('m', positive=True),
        'rod_to_crank_radius_ratio': scalar('1', minimum=2.0),
        'reciprocating_mass_kg': scalar('kg', positive=True),
        'mechanical_torque_nm': curve('rpm, N·m'),
        'combustion_efficiency': curve('1, 1', 1.0, axis='mixture'),
        'indicated_efficiency': curve('rpm, 1', 1.0),
    },
    'families': {
        'glow_2t': {'delivery_ratio': curve('rpm, 1'),
                    'trapping_efficiency': curve('rpm, 1', 1.0),
                    'scavenge_pressure_pa': curve('rpm, Pa')},
        'glow_4t': {'volumetric_efficiency': curve('rpm, 1', positive=True),
                    'pumping_pressure_pa': curve('rpm, Pa'),
                    'intake_pressure_drop_pa': scalar('Pa'),
                    'valve_torque_nm': curve('rpm, N·m')},
    },
    'fuel': {
        'nitromethane_volume_fraction': scalar('1', maximum=1.0),
        'lubricant_volume_fraction': scalar('1', maximum=1.0),
        'methanol_density_kg_m3': scalar('kg/m3', positive=True),
        'nitromethane_density_kg_m3': scalar('kg/m3', positive=True),
        'lubricant_density_kg_m3': scalar('kg/m3', positive=True),
        'methanol_lhv_j_kg': scalar('J/kg', positive=True),
        'nitromethane_lhv_j_kg': scalar('J/kg', positive=True),
        'methanol_stoich_air_fuel_ratio': scalar('1', positive=True),
        'nitromethane_stoich_air_fuel_ratio': scalar('1', positive=True),
    },
    'operation': {
        'max_rpm': scalar('rpm', positive=True),
        'rated_rpm': scalar('rpm', positive=True),
        'rated_power_w': scalar('W', positive=True),
        'reference_dry_density_kg_m3': scalar('kg/m3', positive=True),
        'nominal_mixture': scalar('1', positive=True),
        'recommended_max_rpm': scalar('rpm', positive=True),
    },
}


def quantity(value, rule, kind='estimated', source=EST):
    return dict(value=value, unit=rule['unit'], kind=kind, source=source)


def fuel():
    values = [.10, .18, 792., 1137., 961., 20e6, 11.3e6, 6.429, 1.687]
    return {k: quantity(v, r, 'borrowed', PAPER) for (k, r), v in zip(SPEC['fuel'].items(), values)}


def blend(f):
    """Volume fractions -> premix mass density, inert oil fraction, combustible AFR/LHV."""
    v = {k: q['value'] for k, q in f.items()}
    nitro = v['nitromethane_volume_fraction']; oil = v['lubricant_volume_fraction']
    masses = [(1-nitro-oil)*v['methanol_density_kg_m3'],
              nitro*v['nitromethane_density_kg_m3'], oil*v['lubricant_density_kg_m3']]
    combustible = masses[0]+masses[1]; density = sum(masses)
    afr = (masses[0]*v['methanol_stoich_air_fuel_ratio'] +
           masses[1]*v['nitromethane_stoich_air_fuel_ratio'])/combustible
    lhv = (masses[0]*v['methanol_lhv_j_kg']+masses[1]*v['nitromethane_lhv_j_kg'])/combustible
    return dict(density_kg_m3=density, oil_fraction=masses[2]/density,
                stoich_air_fuel_ratio=afr, fuel_lhv_j_kg=lhv)


# NITRO-61FX: the MAX-61FX (default Stik engine) reuses the 55AX knot grid and loss laws scaled by displacement;
# justified only by equal rated BMEP (526.7 vs 525.1 kPa). Dossier: docs/research/glow-engines/NITRO-61FX/README.md.
FX61_URL = 'https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/17750.htm'
FX61_SCALE = 9.95/8.93
WINDMILL_RPM = [24000., 32000.]  # NITRO-61FX-R1 inferred support for full-throttle dives (no indicated work)
# NITRO-61FX-R2: installed (muffler) variants. An exhaust silencer's back pressure grows with the exhaust flow, about
# with its square, so at wide-open throttle with rpm squared, and it lowers the fresh charge a two-stroke delivers. The
# variant keeps every bare-candidate table except delivery_ratio, scaled by 1 - k (rpm / ref)^2 up to the last powered
# knot and held beyond it (the R1 windmill knots do no indicated work). k is solved so the wide-open brake torque at the
# anchor rpm meets a dyno reading of the installed engine.
INSTALLED = {
    'os_max_61fx_installed_candidate': dict(
        base='os_max_61fx_candidate', model='MAX-61FX (muffler-installed)', anchor_rpm=13000., ref_rpm=13000.,
        anchor_w=1.24*745.6998715822702, last_powered_rpm=20000.,
        anchor_source=('Dave Gierke, Model Airplane News 05/2003 ".60 engine shootout", O.S. 61FX with its stock muffler: '
                       '1.24 hp at 13,000 rpm, "most muffler equipped .60 make their maximum HP output at around 13,000 RPM" '
                       '(secondhand: RC Universe thread 1638558, 2004-03-21; the article itself was not found); mechanical hp'),
        check_source=('Glassock 2012 (QUT PhD) rig: an O.S. 10 cc FX on a 12x6 at 30 m/s turned 11,000 rpm with 0.617 N m shaft '
                      'torque through a geared motor (extra friction); references/rc-throttle-power/'),
    ),
}
ENGINES = ['os_max_55ax_candidate', 'os_fs_64v_candidate', 'os_max_61fx_candidate']


def candidate(engine):
    if engine in SPEC['families']:  # historical key: one engine per family
        engine = 'os_max_55ax_candidate' if engine == 'glow_2t' else 'os_fs_64v_candidate'
    fx61 = engine == 'os_max_61fx_candidate'
    two = engine != 'os_fs_64v_candidate'
    family = 'glow_2t' if two else 'glow_4t'
    name = 'MAX-61FX' if fx61 else ('MAX-55AX' if two else 'FS-64V')
    url = FX61_URL if fx61 else ('https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm'
           if two else 'https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html')
    geometry_url = FX61_URL if fx61 else ('https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15610.htm'
                    if two else 'https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html')
    bore_m, stroke_m, dry_engine_mass_kg = ((.024, .022, .550) if fx61 else (.023, .0215, .404) if two else (.025, .0213, .442))
    rated = 16000. if two else 11000.
    rated_w = (1.9 if fx61 else 1.7 if two else 1.14)*735.49875  # PS, explicitly not mechanical hp
    rpm = [0., 2000., 4000., 7000., 10000., 13000., rated, 17000.] if two else [0., 2400., 4000., 6000., 8000., 10000., rated, 13000., 15000.]
    # Net WOT torque hypotheses. Only the rated-power knot is manufacturer anchored.
    q = [0., .18, .30, .52, .70, .78, rated_w/(rated*math.tau/60), .70] if two else [0., .35, .50, .65, .80, .77, rated_w/(rated*math.tau/60), .40, .05]
    k = FX61_SCALE if fx61 else 1.
    if fx61:
        # An APC 12x6 unloads past the 17000 rpm practical limit in a full-throttle dive. As for the FS-64V, an
        # explicitly inferred tail knot (20000 rpm, torque falling past the tuned range) keeps that state inside the
        # numerical support; 17000 rpm stays the manufacturer recommendation that telemetry flags.
        rpm = rpm + [20000.]
        q = [v*k for v in q[:6]] + [q[6], q[7]*k, .45*k]
        # NITRO-61FX-R1: the faster Extra 300S still left that support in a full-throttle knife-edge dive (19,992 rpm
        # at 51.5 m/s, where the 12x6 pitch speed is reached). Two further inferred windmill knots produce no indicated
        # work (brake torque = -(friction + pumping)), so the engine stops accelerating past 24,000 rpm and a dive
        # windmills inside the support up to the 32,000 rpm pitch speed of 81 m/s. Every knot <= 20,000 is unchanged.
        rpm = rpm + WINDMILL_RPM
        q = q + [0.]*len(WINDMILL_RPM)  # placeholders: eta is set to exactly 0 at these knots below
    volume = (9.95 if fx61 else 8.93 if two else 10.46)*1e-6
    p = {
        'displacement_m3': quantity(volume, SPEC['common']['displacement_m3'], 'derived', url+'; cc × 1e-6 -> m3'),
        'bore_m': quantity(bore_m, SPEC['common']['bore_m'], 'manual', geometry_url+'; manufacturer bore specification converted from mm to m'),
        'stroke_m': quantity(stroke_m, SPEC['common']['stroke_m'], 'manual', geometry_url+'; manufacturer stroke specification converted from mm to m'),
        'rod_to_crank_radius_ratio': quantity(3.5, SPEC['common']['rod_to_crank_radius_ratio'], 'estimated',
            'NITRO-03 explicit unmeasured slider-crank geometry estimate; connecting-rod length / crank radius = 3.5; matched internal dimension unavailable'),
        'reciprocating_mass_kg': quantity(.025*dry_engine_mass_kg, SPEC['common']['reciprocating_mass_kg'], 'estimated',
            f'NITRO-03 explicit unmeasured equivalent-mass estimate: 2.5% of manufacturer dry engine mass ({dry_engine_mass_kg*1000:.0f} g); 1–5% sensitivity retained in vibration evidence; no matched component measurement; {geometry_url}'),
    }
    mech = [(.008+.000002*r)*k for r in rpm] if fx61 else [.008+.000002*r for r in rpm]
    FX61_NOTE = ('; MAX-61FX: 55AX law scaled by displacement 9.95/8.93 (equal rated BMEP 526.7 vs 525.1 kPa); '
                 'docs/research/glow-engines/NITRO-61FX/README.md')
    p['mechanical_torque_nm'] = quantity(list(map(list, zip(rpm, mech))), SPEC['common']['mechanical_torque_nm'],
        'estimated', EST+FX61_NOTE) if fx61 else quantity(list(map(list, zip(rpm, mech))), SPEC['common']['mechanical_torque_nm'])
    p['combustion_efficiency'] = quantity([[0., 0.], [.5, .5], [.8, .90], [1., .98], [1.15, 1.], [1.6, .85], [2.5, .2], [3.,0.], [20.,0.]], SPEC['common']['combustion_efficiency'])
    angle = math.tau if two else 2*math.tau
    if two:
        delivery = [.45, .55, .66, .8, .95, 1.02, 1.0, .96] + ([.85, .75, .60] if fx61 else [])
        trap = [.6, .65, .70, .74, .76, .76, .74, .72] + ([.66, .62, .55] if fx61 else [])
        scav = [2000.+.4*r for r in rpm]
        family_values = {'delivery_ratio': list(map(list, zip(rpm, delivery))),
                         'trapping_efficiency': list(map(list, zip(rpm, trap))),
                         'scavenge_pressure_pa': list(map(list, zip(rpm, scav)))}
        air_factor = [a*b for a,b in zip(delivery,trap)]
        pump = [s*volume*d/angle for s,d in zip(scav,delivery)]
        valve = [0.]*len(rpm)
    else:
        ve = [.35, .5, .68, .79, .88, .89, .85, .65, .30]
        pumping = [2000.+.3*r for r in rpm]
        valve = [.006+.000001*r for r in rpm]
        family_values = {'volumetric_efficiency': list(map(list, zip(rpm,ve))),
                         'pumping_pressure_pa': list(map(list, zip(rpm,pumping))),
                         'intake_pressure_drop_pa': 35000.,
                         'valve_torque_nm': list(map(list, zip(rpm,valve)))}
        air_factor = ve
        pump = [s*volume/angle for s in pumping]
    for key, value in family_values.items():
        p[key] = quantity(value, SPEC['families'][family][key])
    f = fuel(); b = blend(f)
    # Infer independent cycle-conversion coefficients from candidate brake torque and declared losses.
    eta = [(torque+loss+qp+qv)*angle/(1.225*volume*af/b['stoich_air_fuel_ratio']*b['fuel_lhv_j_kg'])
           for torque,loss,qp,qv,af in zip(q,mech,pump,valve,air_factor)]
    if fx61:
        eta[-len(WINDMILL_RPM):] = [0.]*len(WINDMILL_RPM)  # NITRO-61FX-R1 windmill knots: no indicated work
    assert all(0 <= e <= 1 for e in eta)
    p['indicated_efficiency'] = quantity(list(map(list, zip(rpm,eta))), SPEC['common']['indicated_efficiency'],
        'derived', 'build_profiles.py: independently inferred WOT torque knots + estimated gas-exchange/loss curves; ONLY rated-power knot constrained by '+url
        +(FX61_NOTE.replace('law', 'torque knots and losses') if fx61 else ''))
    op_values = [rpm[-1], rated, rated_w, 1.225, 1.15, 17000. if two else 11000.]
    op = {k: quantity(v, r, 'manual' if k in ['recommended_max_rpm','rated_rpm'] else 'estimated', url if k in ['recommended_max_rpm','rated_rpm'] else EST)
          for (k,r),v in zip(SPEC['operation'].items(),op_values)}
    op['rated_power_w'] = quantity(rated_w, SPEC['operation']['rated_power_w'], 'derived', url+'; metric PS × 735.49875 W/PS')
    return dict(format='openrc-glow-engine v1', id=engine,
                manufacturer='O.S. Engines', model=name, family=family, status='candidate',
                feed='naturally_aspirated', oil_model='inert', parameters=p, fuel=f, operation=op)


def installed(engine):
    """NITRO-61FX-R2: the installed variant of a bare candidate (only delivery_ratio differs)."""
    from calibration_report import evaluate  # the same mean-cycle reconstruction the calibration report uses
    spec = INSTALLED[engine]
    base = candidate(spec['base'])
    bare = base['parameters']['delivery_ratio']['value']
    def factor(k, rpm):
        return 1.0 - k * (min(rpm, spec['last_powered_rpm']) / spec['ref_rpm']) ** 2
    def build(k):
        p = json.loads(json.dumps(base))
        p['parameters']['delivery_ratio']['value'] = [[r, d * factor(k, r)] for r, d in bare]
        return p
    target = spec['anchor_w'] / (spec['anchor_rpm'] * math.tau / 60.0)
    lo, hi = 0.0, 0.6
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        if evaluate(build(mid), spec['anchor_rpm'])['brake_shaft_torque_nm'] > target:
            lo = mid
        else:
            hi = mid
    k = 0.5 * (lo + hi)
    p = build(k)
    p['id'] = engine
    p['model'] = spec['model']
    rule = SPEC['families'][p['family']]['delivery_ratio']
    p['parameters']['delivery_ratio'] = quantity(p['parameters']['delivery_ratio']['value'], rule, 'derived',
        'build_profiles.py NITRO-61FX-R2: %s delivery x (1 - %.6f (rpm/%.0f)^2), held beyond %.0f rpm; k solves wide-open brake '
        'torque %.6f N m at %.0f rpm, the installed anchor (%s). Check: %s. Back pressure modelled as a wide-open-throttle '
        'function of rpm only (part-throttle derate overstated); not a measured map'
        % (spec['base'], k, spec['ref_rpm'], spec['last_powered_rpm'], target, spec['anchor_rpm'], spec['anchor_source'], spec['check_source']))
    return p


def quantity_schema(rule):
    num = dict(type='number', maximum=rule['maximum'])
    num['exclusiveMinimum' if rule['positive'] else 'minimum'] = rule['minimum']
    if rule['shape']=='curve':
        value = dict(type='array', minItems=2, items=dict(type='array', minItems=2,maxItems=2,
            prefixItems=[dict(type='number',minimum=0),num],items=False))
    else:
        value = num
    return dict(type='object', additionalProperties=False, required=['value','unit','kind','source'],
                properties=dict(value=value, unit=dict(const=rule['unit']), kind=dict(enum=KINDS),
                                source=dict(type='string',minLength=1,pattern=r'\S')))


def group_schema(rules):
    return dict(type='object',additionalProperties=False,required=list(rules),
                properties={k:quantity_schema(v) for k,v in rules.items()})


def schema():
    root = dict(type='object',additionalProperties=False,
                required=['format','id','manufacturer','model','family','status','feed','oil_model','parameters','fuel','operation'],
                properties={k:dict(type='string',minLength=1,pattern=r'\S') for k in ['id','manufacturer','model']})
    root['properties'].update(format=dict(const='openrc-glow-engine v1'),family=dict(enum=list(SPEC['families'])),
        status=dict(const='candidate'),feed=dict(const='naturally_aspirated'),oil_model=dict(const='inert'),
        fuel=group_schema(SPEC['fuel']),operation=group_schema(SPEC['operation']),parameters=dict(type='object'))
    root['allOf'] = []
    for fam, fields in SPEC['families'].items():
        root['allOf'].append({'if':dict(properties=dict(family=dict(const=fam))),
                             'then':dict(properties=dict(parameters=group_schema(SPEC['common']|fields)))})
    root['$schema']='https://json-schema.org/draft/2020-12/schema'
    root['title']='Standalone experimental RC glow engine profile v1'
    root['description']='Generated by research/glow-engines/build_profiles.py. Runtime validates ordered support, fuel blend and derived finite output. Not an aircraft capability.'
    return root


def outputs():
    return {'profile_contract.json': SPEC, 'openrc-glow-engine-v1.schema.json': schema(),
            **{engine+'.json':candidate(engine) for engine in ENGINES},
            **{engine+'.json':installed(engine) for engine in INSTALLED}}


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    stale=[]
    for name,data in outputs().items():
        text=json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n'; path=DEST/name
        if args.check:
            if not path.exists() or path.read_text(encoding='utf-8')!=text:stale.append(name)
        else:
            DEST.mkdir(parents=True,exist_ok=True); path.write_text(text,encoding='utf-8',newline='\n')
    if stale: raise SystemExit('Stale generated profiles: '+', '.join(stale))
    print('Glow profile generator: '+('current' if args.check else 'generated')+' (%d files)' % len(outputs()))


if __name__=='__main__': main()
