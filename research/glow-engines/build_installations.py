"""Generate explicit experimental 2T/4T Stik installations from the accepted donor pipeline output.

Geometry/aerodynamics remain borrowed. Quantities not sourced to a manual are estimates.
No output of this tool establishes physical or pilot validation.
"""
import argparse
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
IDENTITY_DIR = ROOT / 'research/aircraft-standardization'
if str(IDENTITY_DIR) not in sys.path:
    sys.path.insert(0, str(IDENTITY_DIR))
from physical_identity import validate_physical_identity

EST = 'NITRO-02 experimental installation estimate; no matched hardware measurement'

FUEL_DIR = ROOT / 'research/fuel-systems'
if str(FUEL_DIR) not in sys.path:
    sys.path.insert(0, str(FUEL_DIR))
import fuel_registry  # noqa: E402
GLOW_DIR = Path(__file__).resolve().parent
if str(GLOW_DIR) not in sys.path:
    sys.path.insert(0, str(GLOW_DIR))
import carburetor  # noqa: E402
import cycle_oracle  # noqa: E402

GLOW_BLEND = 'glow_10n_18castor'
START_FILL = 1.0  # FUEL D4: finite-fuel aircraft start with a full tank
OS_FX = 'O.S. 40-91FX manual (os-engines.co.jp 50sx_40-91fx.pdf): 61FX "approx 350cc", "12-13 minute flights"'
GLOW_TANKS = {
    '55ax': {'capacity_l': .35, 'capacity_source': 'O.S. MAX-55AX manual 15612: "a fuel tank of approximately 350cc capacity is suggested"',
             'center_above_carburetor_m': 0.0, 'liquid_box_m': [.115, .065, .047],
             'height_source': 'O.S. MAX-55AX manual: tank centre even with the carburetor centre'},
    '61fx': {'capacity_l': .35, 'capacity_source': OS_FX,
             'center_above_carburetor_m': .0075 - .0235, 'liquid_box_m': [.115, .065, .047],
             'height_source': 'O.S. FX manual: top of the tank 5-10 mm above the needle valve (7.5 mm used; 47 mm box)'},
    'fs64v': {'capacity_l': .22, 'capacity_source': 'O.S. FS-64V manual 3AY00: "the suggested fuel tank size is 220cc"',
              'center_above_carburetor_m': -.010, 'liquid_box_m': [.095, .055, .043],
              'height_source': 'O.S. FS-64V manual: tank centre line about 10 mm below the needle-valve centre line'},
}

def insert_after(raw, key, new_key, value):
    """Rebuild the record with new_key placed right after key (stable, reviewable output order)."""
    out = {}
    for k, v in raw.items():
        if k == new_key:
            continue  # replace a donor's own block instead of duplicating it
        out[k] = v
        if k == key:
            out[new_key] = value
    return out

def q(value, unit='1', kind='estimated', source=EST):
    return dict(value=value, unit=unit, kind=kind, source=source)

def left_to_right_sum(values):
    """Accumulate inventory values in a Python-version-independent order."""
    total = 0.0
    for value in values:
        total += value
    return total

THROTTLE_AREA = ('NITRO-06: effective open-throttle area Cd*A from the NITRO-05 wide-open venturi depression estimate '
                 '({wot:.0f} Pa, i.e. manifold ratio {r:.4f}) through the isentropic nozzle law (Heywood 1988 sec. 7.6.2) at the '
                 'rated {rated:.0f} rpm and the profile breathing {breath:.3f}: capacity {cap:.5f} m3/s; derived from estimates, '
                 'no carburettor measurement')
IDLE_OPENING = ('NITRO-06: barrel open-area fraction at the idle stop giving the former per-cycle idle charge {charge:.2f} at the '
                'declared {idle:.0f} rpm static idle (breathing {breath:.3f}) through the choked nozzle law; derived from estimates')

def throttle_settings(two, profile_file):
    """NITRO-06: the carburettor law's two installation quantities, derived from the profile and the feed-pressure estimates."""
    profile = json.loads((ROOT/'app/data/glow'/profile_file).read_text(encoding='utf-8'))
    parameters = profile['parameters']
    displacement = parameters['displacement_m3']['value']
    breathing_table = parameters['delivery_ratio' if two else 'volumetric_efficiency']['value']
    revolutions = 1.0 if two else 2.0
    rated = profile['operation']['rated_rpm']['value']
    wot_pa = 6000. if two else 4000.           # fuel_feed() wot_drive_pressure_pa (NITRO-05 estimate)
    r_wot = 1.0 - wot_pa / 101325.0
    x_rated = 1.0 / carburetor.demand_ratio_for_charge(r_wot)
    breath_rated = carburetor.sample_table(breathing_table, rated)
    capacity = carburetor.demand_m3_s(rated, breath_rated, displacement, revolutions) / x_rated
    area = carburetor.effective_area_for_capacity(capacity)
    idle_rpm = 2800.                           # the aircraft engine block's declared static idle
    idle_charge = .28 if two else .35          # the former per-cycle idle admission (NITRO-02 estimate)
    breath_idle = carburetor.sample_table(breathing_table, idle_rpm)
    x_idle = carburetor.demand_m3_s(idle_rpm, breath_idle, displacement, revolutions) / capacity
    idle_opening = carburetor.demand_ratio_for_charge(idle_charge) * x_idle
    return {
        'throttle_effective_area_m2': q(area, 'm2', 'derived', THROTTLE_AREA.format(wot=wot_pa, r=r_wot, rated=rated, breath=breath_rated, cap=capacity)),
        'idle_opening': q(idle_opening, '1', 'derived', IDLE_OPENING.format(charge=idle_charge, idle=idle_rpm, breath=breath_idle)),
    }

HALF_STICK_RPM_RATIO = 0.81
# NITRO-61FX-R2: an installed variant differs only in its exhaust; the carburettor (venturi area, idle stop) is the
# bare engine's hardware, so its two quantities are sized on the bare profile's breathing.
CARBURETTOR_PROFILE = {'os_max_61fx_installed_candidate': 'os_max_61fx_candidate'}
TRAVEL_EXPONENT = ('NITRO-06: barrel travel exponent calibrated so the static half-stick equilibrium on this propeller sits at '
                   '{ratio:.2f} of the full-throttle static rpm ({half:.0f} of {full:.0f} rpm), the operating band Menon 2010 '
                   '(O.S. 46 FX, barrel carburettor, Fig. 7-11, read from the figure) gives for a half-open barrel on a matched '
                   'propeller (78-84 %); another engine, a derived ratio, no linkage drawing')

def static_rpm(profile, prop, area, idle_opening, exponent, servo):
    """Static torque-balance rpm of the candidate mean cycle on its propeller at a stick position (highest restoring root)."""
    two = profile['family'] == 'glow_2t'
    breathing_table = profile['parameters']['delivery_ratio' if two else 'volumetric_efficiency']['value']
    displacement = profile['parameters']['displacement_m3']['value']
    mixture = profile['operation']['nominal_mixture']['value']
    capacity = carburetor.capacity_m3_s(area)
    opening = carburetor.opening(servo, carburetor.idle_offset(idle_opening), exponent)
    def residual(rpm):
        admission = carburetor.admission(opening, rpm, carburetor.sample_table(breathing_table, rpm), displacement,
                                         1.0 if two else 2.0, capacity)
        engine = cycle_oracle.family_inputs(profile, rpm, admission=admission, mixture=mixture, rho=1.225)
        load = cycle_oracle.propeller_load(rpm, 0.0, 1.225, prop)
        return engine['candidate_mean_shaft_torque_nm'] - load['torque_nm']
    lo, hi = 1200.0, profile['operation']['max_rpm']['value']
    nodes = [lo + (hi - lo) * i / 256.0 for i in range(257)]
    root = None
    for a, b in zip(nodes, nodes[1:]):
        fa, fb = residual(a), residual(b)
        if fa > 0.0 >= fb:
            for _ in range(64):
                m = 0.5 * (a + b)
                if residual(m) > 0.0:
                    a = m
                else:
                    b = m
            root = 0.5 * (a + b)
    if root is None:
        raise SystemExit('no static torque balance for the glow installation at servo %.2f' % servo)
    return root

def travel_exponent(profile, prop, area, idle_opening):
    """NITRO-06: the exponent p of u = u_idle (1 - servo)^p that puts the half-stick static rpm at HALF_STICK_RPM_RATIO."""
    full = static_rpm(profile, prop, area, idle_opening, 1.0, 1.0)
    def ratio(p):
        return static_rpm(profile, prop, area, idle_opening, p, 0.5) / full
    lo, hi = 0.1, 10.0
    if not (ratio(lo) <= HALF_STICK_RPM_RATIO <= ratio(hi)):
        raise SystemExit('half-stick rpm ratio %.3f is not bracketed in [%.3f, %.3f]' % (HALF_STICK_RPM_RATIO, ratio(lo), ratio(hi)))
    for _ in range(48):
        mid = 0.5 * (lo + hi)
        if ratio(mid) < HALF_STICK_RPM_RATIO:
            lo = mid
        else:
            hi = mid
    p = 0.5 * (lo + hi)
    return p, static_rpm(profile, prop, area, idle_opening, p, 0.5), full

def installation(two, diameter=13, pitch=6, fx61=False, include_feed=True, section=None, profile_id=None):
    family = 'glow_2t' if two else 'glow_4t'
    profile_file = (profile_id or ('os_max_61fx_candidate' if fx61 else 'os_max_55ax_candidate' if two else 'os_fs_64v_candidate'))+'.json'
    settings = {
        **throttle_settings(two, CARBURETTOR_PROFILE.get(profile_file[:-5], profile_file[:-5])+'.json'),
        'servo_time_constant_s': q(.06, 's'),
        'air_time_constant_s': q(.045 if two else .075, 's'),
        'fuel_transport_time_constant_s': q(.12 if two else .16, 's'),
        'stall_rpm': q(1200. if two else 1500., 'rpm'),
        'minimum_start_rpm': q(2200., 'rpm'),
        'starter_prime_kg': q(1e-5, 'kg'),
        'temperature_firing_min_k': q(280., 'K'),
        'temperature_firing_full_k': q(360., 'K'),
        'temperature_firing_hot_full_k': q(450., 'K'),
        'temperature_firing_hot_zero_k': q(560., 'K'),
        'lean_misfire_zero_ratio': q(.20), 'lean_misfire_start_ratio': q(.60),
        'rich_misfire_start_ratio': q(1.25), 'rich_misfire_zero_ratio': q(1.80),
        'thermal': {
            'heat_capacity_j_k': q(140. if two else 165., 'J/K'),
            'head_heat_fraction': q(.20 if two else .24),
            'cooling_base_w_k': q(1.5, 'W/K'),
            'cooling_airflow_w_s_m_k': q(.12, 'W/(K m/s)'),
            'premix_evaporation_j_kg': q(700000., 'J/kg'),
            'evaporation_head_fraction': q(.08),
        },
    }
    out = dict(format='openrc-glow-installation v2', family=family,
                profile='res://data/glow/'+profile_file,
                fuel_inventory='usable glow premix', settings=settings,
                initial_temperature_k=q(390., 'K'),
                propeller={
                    'max_rpm':q((190000. if two or diameter==13 else 165000.)/diameter,'rpm','derived',
                                'https://www.apcprop.com/technical-information/rpm-limits/; sport 190000/diameter(in)' if two or diameter==13 else 'https://www.masterairscrew.com/pages/downloads; generic plastic-prop 165000/diameter(in), provisionally applied to K-Series glass-fiber composite; not a SKU-specific rating'),
                    'diameter_m': q(diameter*.0254,'m'), 'pitch_m':q(pitch*.0254,'m'),
                    'chord_m':q(.0211364169120926*diameter/12 if two else .030*diameter/14,'m',
                                'estimated', ('Conditional APC12x7 10330rpm fit at assumed 1.225kg/m3 for the MAX-55AX, carried to the MAX-61FX on an APC12x6 '
                                              '(different engine and pitch; predicts 12550 rpm static, above every 61FX indication); NITRO-61FX dossier') if fx61 else
                                'Conditional APC12x7 10330rpm fit at assumed 1.225kg/m3; transferred c/D for other diameters; NITRO-2T dossier' if two else EST+'; independent broad-blade 14x6 surrogate, c/D transfer to 13x6'), 'blades':q(2.),
                    'lift_slope':q(5.5,'1/rad'), 'cd0':q(.022),
                    'induced_drag':q(.06 if two else .075, source=EST if two else
                        EST+'; loss coefficient constrained to exceed ideal actuator-disk power by at least 5% over positive-thrust forward flow for both assumed geometries; not measured induced flow; NITRO-02 momentum-bound audit'),
                })
    if section is not None:
        # EX-14f: a measured-data section fit (chord and cambered zero-lift angle) replaces the transferred chord.
        out['propeller']['chord_m'] = q(section['chord_m'], 'm', 'derived', section['source'])
        out['propeller']['zero_lift_angle_rad'] = q(section['zero_lift_angle_rad'], 'rad', 'derived', section['source'])
    profile = json.loads((ROOT/'app/data/glow'/profile_file).read_text(encoding='utf-8'))
    prop = {key: out['propeller'][key]['value'] for key in ['diameter_m', 'pitch_m', 'chord_m', 'blades', 'lift_slope', 'cd0', 'induced_drag']}
    if 'zero_lift_angle_rad' in out['propeller']:
        prop['zero_lift_angle_rad'] = out['propeller']['zero_lift_angle_rad']['value']
    exponent, half_rpm, full_rpm = travel_exponent(profile, prop, settings['throttle_effective_area_m2']['value'], settings['idle_opening']['value'])
    settings['throttle_travel_exponent'] = q(exponent, '1', 'derived', TRAVEL_EXPONENT.format(ratio=HALF_STICK_RPM_RATIO, half=half_rpm, full=full_rpm))
    # Keep the authored settings order: the three carburettor quantities first.
    ordered = {key: settings[key] for key in ['throttle_effective_area_m2', 'idle_opening', 'throttle_travel_exponent']}
    ordered.update({key: value for key, value in settings.items() if key not in ordered})
    out['settings'] = ordered
    if include_feed:
        out['fuel_feed'] = fuel_feed(two)
    return out

FEED = ('NITRO-05 estimate: fuel-feed pressure at the spray bar (carburetor suction plus tank pressurization); '
        'order of magnitude from modeler practice, no measured pressure for this engine')

def fuel_feed(two):
    """NITRO-05: spray-bar position (inventory frame [aft, right, up] from the wing LE datum) and driving pressures."""
    return {
        # 2T: the carburetor sits on the front housing about 20 mm above the shaft (the Stik render places it there).
        # 4T: the FS-64V carburetor feeds the head through an intake pipe, higher and closer to the firewall.
        'carburetor_position': q([-0.24, 0.0, 0.02] if two else [-0.20, 0.0, 0.045], 'm', 'estimated',
            'NITRO-05 estimate from the engine layout (2T front-housing carburetor, 4T head-fed intake); not measured'),
        # Muffler pressure (2T) or the pulsed crankcase breather (4T) adds to the carburetor suction at full throttle.
        'idle_drive_pressure_pa': q(1500. if two else 1000., 'Pa', 'estimated', FEED),
        'wot_drive_pressure_pa': q(6000. if two else 4000., 'Pa', 'estimated', FEED),
    }

def inventory_cg(inv):
    """Authored inventory CG (the runtime body datum), summed left to right as aircraft_data.gd does."""
    mass=left_to_right_sum(i['mass']['value'] for i in inv)
    return [left_to_right_sum(i['mass']['value']*i['position']['value'][k] for i in inv)/mass for k in range(3)]

def aircraft(two, install, suffix='', fx61=False):
    raw = json.loads((ROOT/'app/data/aircraft/jensen_ugly_stik_60.json').read_text(encoding='utf-8'))
    # The hub is fixed airframe geometry; thrust_line_offset is datum-relative, so carry the hub, not the offset.
    base_offset=raw['propulsion']['propeller']['thrust_line_offset']['value']
    hub_le=[c+o for c,o in zip(inventory_cg(raw['inventory']),base_offset)]
    tag = '61fx_2t' if fx61 else '55ax_2t' if two else 'fs64v_4t'
    raw['id'] = 'stik-glow-'+tag.replace('_','-')
    raw['description'] = 'Experimental Stik with '+('O.S. MAX-61FX 2T, the default Stik engine,' if fx61 else 'O.S. MAX-55AX 2T' if two else 'O.S. FS-64V 4T')+'; inferred engine/prop/transient/thermal data, finite fuel. Generated by research/glow-engines/build_installations.py.'
    raw['capabilities']['energy'] = 'finite_glow_fuel'
    raw['start']['level_speed']=q(20.,'m/s')
    raw['balance']['configuration'] = 'virtual-glow-installation-v2-empty-tank'
    inv = raw['inventory']
    # These identities follow the inherited source records through display-name
    # and array-order changes; installation, fuel and ballast values can change
    # without changing the authored physical roles.
    replacement_ids = {
        'item_engine_main': 'item_engine_main',
        'item_muffler_main': 'item_muffler_main',
        'item_propeller_main': 'item_propeller_main',
        'item_fuel_main': 'item_fuel_main',
        'item_balance_mass_virtual': 'item_balance_mass_virtual',
    }
    for source_id, identity in replacement_ids.items():
        matches = [item for item in inv if item.get('id') == source_id]
        if len(matches) != 1:
            raise ValueError('Stik source identity is missing or duplicated: '+source_id)
        matches[0]['id'] = identity
    # FUEL-01a: select every edited record by its stable id, never by array position.
    by_id = {item.get('id'): item for item in inv}
    engine_item = by_id['item_engine_main']
    muffler_item = by_id['item_muffler_main']
    prop_item = by_id['item_propeller_main']
    fuel_item = by_id['item_fuel_main']
    ballast_item = by_id['item_balance_mass_virtual']
    diameter=install['propeller']['diameter_m']['value']
    diameter_in=round(diameter/.0254)
    pitch_in=round(install['propeller']['pitch_m']['value']/.0254)
    if not fx61:
        # The MAX-61FX variant keeps the base Stik's own sourced engine, E-4010 silencer and APC 12x6 entries.
        engine_item['name'] = 'O.S. MAX-55AX' if two else 'O.S. FS-64V'
        url = 'https://www.os-engines.co.jp/english/line_up/engine/air/'+('aircraft/catalog/15612.htm' if two else 'single/catalog/3AY00.html')
        engine_item['mass'] = q(.404 if two else .442,'kg','manual',url)
        muffler_item['name'] = 'stock silencer'
        muffler_item['mass'] = q(.121 if two else .044,'kg','borrowed' if two else 'manual',
                             'AIAA 2016-5011 Table 2: tested assembly 525 g minus engine 404 g; E-3071 revision pairing unverified' if two else url)
        prop_item['name']=('APC Sport LP%02d%03d' % (diameter_in,pitch_in*10) if two or diameter_in==13 else 'Master Airscrew K Series')+' %dx%d' % (diameter_in,pitch_in)
        prop_item['mass']=q(.0430913,'kg','manual','https://www.apcprop.com/product/12x7/; 1.52oz × 0.028349523125kg/oz') if two and diameter_in==12 else q(.050 if diameter_in==13 else .060,'kg')
    prop_item['size']=q([.01,diameter,.025],'m')
    # FUEL-05a: each engine manual's suggested tank, filled from the fuel registry, balanced with an empty tank.
    fuel_item['name']='usable glow premix'
    tank=GLOW_TANKS['61fx' if fx61 else '55ax' if two else 'fs64v']
    density=fuel_registry.blend_density(GLOW_BLEND)
    carburetor_z=fuel_feed(two)['carburetor_position']['value'][2]
    tank_z=carburetor_z+tank['center_above_carburetor_m']
    fuel_item['mass']=q(tank['capacity_l']*1e-3*density*START_FILL,'kg','derived',
        'FUEL-05a: full tank (D4): %s l %s x %s' % (tank['capacity_l'],tank['capacity_source'],fuel_registry.blend_source(GLOW_BLEND)))
    fuel_item['position']=q([-.1,0.,tank_z],'m','estimated',
        'FUEL-05a: plan fuel-tank compartment F1-F2 (x); height '+tank['height_source'])
    fuel_item['size']=q(tank['liquid_box_m'],'m','estimated',
        'FUEL-05a: uniform liquid box holding the %s l capacity; no measured tank interior' % tank['capacity_l'])
    fuel_item['energy_source']='glow_fuel'
    # The empty shell stays the base Stik's hardware record (a saleable component in the economics BOM);
    # sizing it with the tank is a later, cost-reviewed change (FUEL-05, F12).
    # Recompute the existing virtual balance fixture with the tank empty (D3); never pretend ballast was measured.
    cg=raw['balance']['plan_cg']['value']
    parts=[item for item in inv if item is not ballast_item and item is not fuel_item]
    mass=left_to_right_sum(i['mass']['value'] for i in parts)
    first=[left_to_right_sum(i['mass']['value']*i['position']['value'][k] for i in parts) for k in range(3)]
    x=.85
    ballast=(mass*cg[0]-first[0])/(x-cg[0])
    ballast_item['mass']=q(ballast,'kg','derived',EST+'; virtual first-moment balance of the empty-tank build')
    ballast_item['position']=q([x,((mass+ballast)*cg[1]-first[1])/ballast,((mass+ballast)*cg[2]-first[2])/ballast],'m','derived',EST+'; virtual empty-tank balance')
    raw['balance']['fuel_state']='empty_tanks'
    if 'tank empty' not in raw['balance']['plan_cg']['source']:
        raw['balance']['plan_cg']['source']=raw['balance']['plan_cg']['source']+'; FUEL-05a: plan CG taken with an empty tank, as RC manuals balance'
    system={'tanks':[{'id':'main_tank','fuel':GLOW_BLEND,'liquid_inventory_id':'item_fuel_main',
        'shell_inventory_id':'item_fuel_tank',
        'capacity':q(tank['capacity_l'],'l','manual',tank['capacity_source']),
        'unusable':q(.005,'l','estimated','FUEL-05a: clunk residue estimate; no published value (FUEL-00 section 6.3)'),
        'pickup':'clunk','feed':'suction_muffler'}]}
    raw=insert_after(raw,'inventory','fuel_system',system)
    profile=json.loads((ROOT/'app/data/glow'/('os_max_61fx_candidate.json' if fx61 else 'os_max_55ax_candidate.json' if two else 'os_fs_64v_candidate.json')).read_text(encoding='utf-8'))
    engine=raw['propulsion']['engine']
    engine['name']='O.S. MAX-61FX (two-stroke glow)' if fx61 else engine_item['name']
    engine['peak_power']=copy.deepcopy(profile['operation']['rated_power_w'])
    engine['peak_power_rpm']=copy.deepcopy(profile['operation']['rated_rpm'])
    if not fx61:  # the 61FX keeps the base Stik's derived legacy static rpm (unused by the glow law)
        engine['max_rpm_static']=q(13000. if two else 10000.,'rpm')
    engine['idle_rpm']=q(2800.,'rpm')
    engine['glow_installation']='res://data/glow/stik_'+tag+suffix+'.json'
    prop=raw['propulsion']['propeller']
    prop['name']=('APC Sport LP12060 12x6' if fx61 else prop_item['name'])+' (annular surrogate)'
    prop['diameter']=copy.deepcopy(install['propeller']['diameter_m'])
    # The locked-body inventory already uses this uniform rectangular propeller.
    # Its entire axial inertia rotates; add only the estimated crank polar inertia
    # contained in the engine inventory. Changing prop mass/diameter changes both
    # locked-body and relative shaft inertia, rather than only aerodynamic load.
    prop_size=prop_item['size']['value']
    prop_polar=prop_item['mass']['value']*(prop_size[1]**2+prop_size[2]**2)/12.
    crank_polar=2e-5 if two else 3e-5
    prop['rotating_inertia']=q(prop_polar+crank_polar,'kg·m2','derived',
                              EST+'; uniform-box prop polar m*(diameter^2+thickness^2)/12 plus estimated crank polar '+str(crank_polar)+' kg m^2; no measured blade mass distribution')
    prop['thrust_angles']=q([0.,0.],'deg')
    # FUEL-05a: re-reference the base Stik's hub to this build's datum (its full-tank inventory CG).
    datum=inventory_cg(inv)
    prop['thrust_line_offset']=q([round(hub_le[k]-datum[k],12)+0.0 for k in range(3)],'m','derived',
        'FUEL-05a: base Stik hub (research/propwash/e0b2/derive_geometry.py) minus this build\'s authored inventory CG, '
        'the fixed body datum, in [aft,right,up]')
    for contact in raw['landing_gear']['contacts']:
        for key in ['stiffness','damping']:
            if key in contact:
                contact[key]=q(contact[key]['value']*.8,contact[key]['unit'])
    validate_physical_identity(raw)
    return raw

def outputs():
    out={}
    for two in [True,False]:
        tag='55ax_2t' if two else 'fs64v_4t'
        for suffix,diameter,pitch in [('',12 if two else 14,7 if two else 6),('_apc_13x6',13,6)]:
            install=installation(two,diameter,pitch)
            out[ROOT/'app/data/glow'/('stik_'+tag+suffix+'.json')]=install
            out[ROOT/'app/data/aircraft'/('stik_glow_'+tag+suffix+'.json')]=aircraft(two,install,suffix)
    # NITRO-61FX: the default Stik's own engine on its own APC 12x6 (docs/research/glow-engines/NITRO-61FX).
    install=installation(True,12,6,fx61=True)
    out[ROOT/'app/data/glow'/'stik_61fx_2t.json']=install
    out[ROOT/'app/data/aircraft'/'stik_glow_61fx_2t.json']=aircraft(True,install,'',fx61=True)
    # The Extra uses the same MAX-61FX candidate and 12x6 prop diameter, but
    # its carburetor location is not established by the Stik render. Omit the
    # optional feed block until Extra-specific source/measurement exists.
    # EX-14f: the Extra flies the cambered section fitted to measured APC Sport 11x6 data (fit_section.py), transferred
    # to its 12x6 by c/D. The Stik installations keep the symmetric surrogate until their owners adopt it.
    fit=json.loads((ROOT/'research/glow-engines/section_fits.json').read_text(encoding='utf-8'))['apc_sport_11x6_uiuc']
    # EX-14g: the Extra's prototype ran a Slimline Pitts in-cowl muffler (manual p3), so it uses the muffler-installed
    # 61FX (NITRO-61FX-R2) instead of the bare catalog-rated candidate.
    out[ROOT/'app/data/glow'/'extra_61fx_2t.json']=installation(True,12,6,fx61=True,include_feed=False,profile_id='os_max_61fx_installed_candidate',section={
        'chord_m':fit['chord_over_diameter']*12*.0254,'zero_lift_angle_rad':fit['zero_lift_angle_rad'],
        'source':'EX-14f research/glow-engines/fit_section.py: chord ratio %.4f and zero-lift angle %.2f deg fitted to the '
                 'measured UIUC APC Sport 11x6 Ct/Cp(J) knots (normalized rms %.3f; symmetric section best %.3f), transferred to '
                 'the 12x6 Sport by c/D; no measured 12x6 Sport map'%(fit['chord_over_diameter'],fit['zero_lift_angle_deg'],
                 fit['normalized_rms'],fit['symmetric_section_normalized_rms'])})
    return out

def render_json(value):
    return (json.dumps(value,indent=2,ensure_ascii=False)+'\n').replace('\n','\r\n').encode('utf-8')

def write_generated_json(path,value):
    # These records are byte-identity evidence; emit the authored CRLF bytes on every host.
    path.write_bytes(render_json(value))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    for path,value in outputs().items():
        rendered=render_json(value)
        if args.check:
            if not path.exists() or path.read_bytes()!=rendered: raise SystemExit('Stale: '+str(path))
        else: path.write_bytes(rendered)
    print('Glow installations current' if args.check else 'Generated both glow installations')

if __name__=='__main__': main()
