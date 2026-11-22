#!/usr/bin/env python3
"""Independent stdlib check of R8 rotor evidence against stock X-Cell data.

verify(log_text, stock_json_dict) returns JSON-serializable data or raises
AssertionError/ValueError on malformed evidence or any failed oracle. The
observations are constructed reference-evaluator snapshots and one constructed
session reset/tick; they are not measured rotor performance or proof of physical
validity. The tail residual compares one unsaturated point to the stated steady,
uniform momentum closure, including its singular-branch caveat.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path


def verify(log_text: str, stock_json_dict: dict) -> dict:
    if not isinstance(log_text, str) or not isinstance(stock_json_dict, dict):
        raise TypeError('verify needs engine log text and a parsed stock JSON object')
    checks = []

    def require(label, condition, *, actual=None, expected=None):
        if not condition:
            raise AssertionError(f'{label}: actual={actual!r}, expected={expected!r}')
        checks.append(label)

    def near(label, actual, expected, *, atol=1e-9, rtol=1e-9):
        valid = (isinstance(actual, (int, float)) and not isinstance(actual, bool)
                 and isinstance(expected, (int, float)) and not isinstance(expected, bool)
                 and math.isfinite(actual) and math.isfinite(expected))
        require(label, valid and abs(actual-expected) <= atol + rtol*abs(expected),
                actual=actual, expected=expected)

    def vector(label, actual, expected, *, atol=1e-9, rtol=1e-9):
        require(label+' shape', isinstance(actual, (list, tuple)) and len(actual)==len(expected),
                actual=actual, expected=expected)
        for i, (a, e) in enumerate(zip(actual, expected)):
            near(f'{label}[{i}]', a, e, atol=atol, rtol=rtol)

    def value(section, key):
        node = stock_json_dict[section][key]
        require(f'stock {section}.{key} value', isinstance(node, dict) and 'value' in node)
        return node['value']

    def dot(a, b):
        require('dot vector dimensions', len(a)==len(b), actual=len(a), expected=len(b))
        return sum(x*y for x,y in zip(a,b))

    def cross(a,b):
        return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]

    def tensor(j, a):
        return [j[0]*a[0]+j[3]*a[1]+j[4]*a[2],
                j[3]*a[0]+j[1]*a[1]+j[5]*a[2],
                j[4]*a[0]+j[5]*a[1]+j[2]*a[2]]

    def singleton(prefix):
        found=[line[len(prefix):] for line in log_text.splitlines() if line.startswith(prefix)]
        require(prefix+' record count',len(found)==1,actual=len(found),expected=1)
        return json.loads(found[0])

    require('stock aircraft identity',stock_json_dict.get('id')=='xcell-60-research'
            and stock_json_dict.get('vehicle')=='rotorcraft')
    markers=re.findall(r'^R8 ROTOR LEDGER: (\d+) checks, (\d+) failed$',log_text,re.MULTILINE)
    require('unique passing completion',len(markers)==1 and int(markers[0][0])>=48 and int(markers[0][1])==0,
            actual=markers,expected='one >=48-check completion with zero failures')
    require('no reported probe failures',not any(line.startswith('FAIL ') for line in log_text.splitlines()))
    tail=singleton('TAIL ')
    main=singleton('MAIN ')
    session_pre=singleton('SESSION PRE ')
    session_post=singleton('SESSION POST ')
    ledger_lines=[line[len('ENERGY_LEDGER '):] for line in log_text.splitlines() if line.startswith('ENERGY_LEDGER ')]
    require('three ledger rows',len(ledger_lines)==3,actual=len(ledger_lines),expected=3)
    ledger_rows=[json.loads(line) for line in ledger_lines]
    require('distinct expected ledger labels',sorted(row.get('label') for row in ledger_rows)==['aft','flat','tilted'])
    rows={row['label']:row for row in ledger_rows}
    mass=float(value('body','mass_kg'))
    J=value('body','inertia_kg_m2')
    require('stock body inertia tensor',isinstance(J,list) and len(J)==6)
    gravity=float(stock_json_dict['gravity_m_s2']['value'])
    main_model=stock_json_dict['main_rotor']
    rho=float(main_model['rho_kg_m3']['value'])
    radius=float(main_model['rotor_radius_m']['value'])
    chord=float(main_model['blade_chord_m']['value'])
    blades=int(main_model['rotor_blade_count']['value'])
    lift_slope=float(main_model['blade_lift_curve_slope_per_rad']['value'])
    cd0=float(main_model['blade_section_cd0']['value'])
    ct_max=float(main_model['thrust_coefficient_max']['value'])
    omega=float(main_model['omega_nominal_rad_s']['value'])
    tip=omega*radius
    area=math.pi*radius**2
    solidity=blades*chord/(math.pi*radius)
    shaft_b=[0.0,0.0,0.0]
    ispin=0.0
    shafts=stock_json_dict['shaft_elements']
    require('two stock geared rotors',len(shafts)==2)
    for shaft in shafts:
        inertia=float(shaft['inertia_kg_m2']['value'])
        ratio=float(shaft['speed_ratio']['value'])
        axis=shaft['spin_axis_body_frd']['value']
        require('stock shaft axis length',len(axis)==3)
        near('stock shaft unit axis',dot(axis,axis),1.0)
        ispin+=inertia*ratio**2
        for i in range(3): shaft_b[i]+=inertia*ratio*axis[i]
    tail_ratio=float(value('tail_rotor','tail_to_main_speed_ratio'))
    near('tail gearing agrees with inertia',float(shafts[1]['speed_ratio']['value']),tail_ratio)

    # Reconstruct normal-pitch curve and unsaturated commanded collective from
    # raw aircraft data, independently of the engine's printed control value.
    raw_electronics=stock_json_dict['electronics']
    raw_curve=raw_electronics['curves_by_mode']['normal']['pitch']['value']
    location=(-.19+1.0)*2.0
    lower=int(location)
    pitch_fraction=location-lower
    normalized_pitch=raw_curve[lower]+pitch_fraction*(raw_curve[lower+1]-raw_curve[lower])
    collective=normalized_pitch*raw_electronics['linkage']['collective_rad_per_unit']['value']
    near('main pitch summary from aircraft curve',main['pitch'],collective)
    normal_speed=15.0
    mu=normal_speed/tip
    near('main advance ratio',main['mu'],mu)
    flap_for={'flat':0.0,'tilted':-.12,'aft':.12}
    values={}
    for label,row in rows.items():
        state=row['state']; derivative=row['derivative']
        require(label+' state and derivative lengths',len(state)==19 and len(derivative)==19)
        vector(label+' body speed',state[3:6],[normal_speed,0.0,0.0])
        vector(label+' body rate',state[10:13],[0.0,0.0,0.0])
        vector(label+' quaternion',state[6:10],[1.0,0.0,0.0,0.0])
        vector(label+' zero ambient wind',row['wind_ned'],[0.0,0.0,0.0])
        near(label+' no ground effect',row['height_over_radius'],-1.0)
        near(label+' shaft speed',state[13],omega)
        near(label+' flap state',state[14],flap_for[label])
        near(label+' lateral flap',state[15],0.0)
        near(label+' mass',row['mass'],mass)
        near(label+' gravity',row['gravity'],gravity)
        vector(label+' body inertia',row['inertia'],J)
        vector(label+' coupling b',row['b'],shaft_b)
        near(label+' reflected shaft inertia',row['ispin'],ispin)
        near(label+' tail gearing',row['tail_ratio'],tail_ratio)
        require(label+' component acceptance',all(row[k]['ok'] is True for k in ('main_rotor','tail_rotor','airframe','drive','controls','coupling','inflow')))
        require(label+' unsaturated controls',not row['controls']['servo_travel_limited'] and not row['controls']['tail_saturated'])
        require(label+' reported main indicators',row['main_rotor']['within_identified_advance_ratio'] and row['main_rotor']['within_small_flap_angle_range'])
        require(label+' main torque/thrust uncapped',abs(row['main_rotor']['thrust_coefficient_ideal'])<ct_max)
        near(label+' target pitch',row['controls']['collective_75_rad'],collective)
        near(label+' main flow target equals state',row['inflow']['target'],state[16],atol=1e-8)
        near(label+' flap derivative',derivative[14],0.0,atol=1e-8)
        near(label+' induced-flow derivative',derivative[16],0.0,atol=1e-8)
        T=row['main_rotor']['thrust_n']
        vi=state[16]
        # Independent steady momentum identity, valid for this zero climb,
        # unity-loss, positive-thrust, no-ground-effect test configuration.
        near(label+' steady momentum thrust',T,2*rho*area*vi*math.hypot(normal_speed,vi),atol=1e-7)
        ct=.5*lift_slope*solidity*(collective*(1/3+mu**2/2)-vi/(2*tip))
        near(label+' thrust from stock coefficients',T,rho*area*tip**2*ct,atol=1e-7)
        near(label+' thrust coefficient',row['main_rotor']['thrust_coefficient'],ct)
        q_expected=rho*area*tip**2*radius*(ct*vi/tip+cd0*solidity/8*(1+7*mu**2/3))
        near(label+' torque from stock coefficients',row['main_rotor']['torque_nm'],q_expected,atol=1e-8)
        unit=[-math.sin(flap_for[label]),0.0,-math.cos(flap_for[label])]
        vector(label+' thrust normal',row['main_rotor']['thrust_normal_body_frd'],unit)
        vector(label+' main rotor force',row['main_rotor']['loads'][:3],[T*x for x in unit],atol=1e-8)
        parts=[row['main_rotor']['loads'],row['tail_rotor']['loads'],row['airframe']['loads']]
        require(label+' component load shapes',all(len(p)==6 for p in parts))
        component_load=[sum(p[i] for p in parts) for i in range(6)]
        vector(label+' aero sum',row['aero_loads'],component_load,atol=1e-8)
        vector(label+' no extra force',row['loads'],component_load,atol=1e-8)
        v=state[3:6]; w=state[10:13]; dv=derivative[3:6]; alpha=derivative[10:13]; om=state[13]; dom=derivative[13]
        vector(label+' reported body acceleration',row['coupling']['body_acceleration_rad_s2'],alpha,atol=1e-8)
        near(label+' reported spin acceleration',row['coupling']['spin_acceleration_rad_s2'],dom,atol=1e-8)
        q_general=row['drive']['net_main_torque_nm']-row['main_rotor']['torque_nm']-tail_ratio*row['tail_rotor']['torque_nm']
        near(label+' generalized shaft row',ispin*dom+dot(shaft_b,alpha),q_general,atol=1e-8)
        gyro=cross(w,[x+om*y for x,y in zip(tensor(J,w),shaft_b)])
        carrier=[x+shaft_b[i]*dom+gyro[i] for i,x in enumerate(tensor(J,alpha))]
        vector(label+' rotational equation',carrier,row['loads'][3:6],atol=1e-8)
        # General derivative of 0.5*m*v^2 + 0.5*w.J.w + om*b.w + 0.5*I*om^2.
        kdot=mass*dot(v,dv)+dot(w,tensor(J,alpha))+dom*dot(shaft_b,w)+om*dot(shaft_b,alpha)+ispin*om*dom
        # Quaternion is checked to be identity in this fixture; gravity work is m*g*v_z.
        gravity_work=mass*gravity*v[2]
        pmain=dot(v,parts[0][:3])+dot(w,parts[0][3:])-om*row['main_rotor']['torque_nm']
        ptail=dot(v,parts[1][:3])+dot(w,parts[1][3:])-om*tail_ratio*row['tail_rotor']['torque_nm']
        pair=dot(v,parts[2][:3])+dot(w,parts[2][3:])
        pdrive=om*row['drive']['net_main_torque_nm']
        budget=pmain+ptail+pair+pdrive+gravity_work
        near(label+' complete generalized energy balance',kdot,budget,atol=1e-7)
        values[label]={'energy_rate_w':kdot,'body_plus_shaft_budget_w':budget,'residual_w':kdot-budget,
                       'main_rotor_port_w':pmain,'tail_rotor_port_w':ptail,'airframe_work_w':pair,
                       'drive_net_work_w':pdrive,'gravity_work_w':gravity_work,
                       'main_torque_nm':row['main_rotor']['torque_nm'],'tail_torque_nm':row['tail_rotor']['torque_nm'],
                       'thrust_n':T,'vi_m_s':vi}

    flat=rows['flat']; forward=rows['tilted']; aft=rows['aft']
    for label in ('tilted','aft'):
        row=rows[label]
        for key in ('thrust_n','torque_nm'):
            near(label+' matched main '+key,row['main_rotor'][key],flat['main_rotor'][key])
        near(label+' matched tail torque',row['tail_rotor']['torque_nm'],flat['tail_rotor']['torque_nm'])
        near(label+' matched drive torque',row['drive']['net_main_torque_nm'],flat['drive']['net_main_torque_nm'])
        near(label+' matched induced state',row['state'][16],flat['state'][16])
    extra=normal_speed*flat['main_rotor']['thrust_n']*math.sin(.12)
    near('forward force work',normal_speed*forward['main_rotor']['loads'][0],extra,atol=1e-7)
    near('aft force work',normal_speed*aft['main_rotor']['loads'][0],-extra,atol=1e-7)
    near('forward total energy rate change',values['tilted']['energy_rate_w']-values['flat']['energy_rate_w'],extra,atol=1e-7)
    near('aft total energy rate change',values['aft']['energy_rate_w']-values['flat']['energy_rate_w'],-extra,atol=1e-7)
    near('summary forward velocity',main['u'],normal_speed)
    near('summary main tilt',main['tilt'],flap_for['tilted'])
    near('summary thrust',main['thrust_n'],flat['main_rotor']['thrust_n'],atol=1e-8)
    near('summary main torque',main['main_q_nm'],flat['main_rotor']['torque_nm'])
    near('summary induced flow',main['vi'],flat['state'][16])
    near('summary induced-flow derivative',main['wake_derivative'],forward['derivative'][16],atol=1e-8)
    near('summary flat cyclic bias',main['cyclic_bias_flat'],flat['controls']['trim']['cyclic_forward_bias_rad'])
    near('summary forward cyclic bias',main['cyclic_bias_forward'],forward['controls']['trim']['cyclic_forward_bias_rad'])
    near('summary forward work',main['forward_work_w'],extra,atol=1e-7)
    near('summary reverse work',main['opposite_work_w'],-extra,atol=1e-7)
    near('summary flat energy',main['kinetic_flat_w'],values['flat']['energy_rate_w'],atol=1e-7)
    near('summary tilt energy',main['kinetic_tilt_w'],values['tilted']['energy_rate_w'],atol=1e-7)
    near('summary main shaft power',main['main_shaft_power_w'],omega*flat['main_rotor']['torque_nm'],atol=1e-7)
    near('summary tail shaft power',main['tail_shaft_power_w'],omega*tail_ratio*flat['tail_rotor']['torque_nm'],atol=1e-7)
    near('summary drive power',main['drive_main_power_w'],values['flat']['drive_net_work_w'],atol=1e-7)

    # Tail input is a declared fixed component fixture: zero in-plane speed,
    # -5 m/s normal air-relative speed, zero body rates, main speed omega.
    tail_radius=float(value('tail_rotor','tail_rotor_radius_m'))
    tail_chord=float(value('tail_rotor','blade_chord_m'))
    tail_blades=int(value('tail_rotor','rotor_blade_count'))
    tail_slope=float(value('tail_rotor','blade_lift_curve_slope_per_rad'))
    tail_cd=float(value('tail_rotor','blade_section_cd0'))
    eta=float(value('tail_rotor','wake_efficiency'))
    tail_trim=float(value('tail_rotor','trim_collective_rad'))
    tail_ct_cap=float(value('tail_rotor','thrust_coefficient_max'))
    fin_area=float(value('airframe','vertical_fin_area_m2'))
    fin_arm=value('airframe','vertical_fin_cp_body_frd_m')
    fraction=float(value('integration','fin_tail_wake_fraction'))
    tail_tip=tail_ratio*omega*tail_radius
    tail_sigma=tail_blades*tail_chord/(math.pi*tail_radius)
    a_sigma=tail_slope*tail_sigma
    k=a_sigma/2
    # At zero in-plane advance, independently solve trim momentum/blade element
    # quadratic and differentiate it to obtain local pitch and normal slopes.
    drive=k*tail_trim/3
    b=k/2
    trim_lambda=2*drive/(b+math.sqrt(b*b+8*eta*drive))
    trim_ct=2*eta*trim_lambda**2
    normal_slope=(k/2)*(2*eta*trim_lambda)/(4*eta*trim_lambda+k/2)
    pitch_slope=4*normal_slope/3
    muz=-5.0/tail_tip
    theta=-.75*muz
    expected_ct=pitch_slope*theta+normal_slope*muz
    lam=muz-2*(2*expected_ct/a_sigma-theta/3)
    induced=lam*tail_tip
    ct_momentum=2*eta*lam*abs(lam-muz)
    ct_residual=expected_ct-ct_momentum
    scale=rho*math.pi*tail_radius**2*tail_tip**2
    blockage=1-.75*fin_area/(math.pi*tail_radius**2)
    tail_torque=scale*tail_radius*(expected_ct*(lam-muz)+tail_cd*tail_sigma/8)
    require('tail trim within coefficient cap',trim_ct<tail_ct_cap)
    require('tail actual coefficient unsaturated',abs(expected_ct)<tail_ct_cap)
    near('tail computed tip',tail['tip'],tail_tip)
    near('tail computed collective',tail['theta'],theta)
    near('tail root ct',tail['trim_ct'],trim_ct)
    near('tail zero actual ct',tail['ct'],expected_ct,atol=1e-12)
    near('tail blocked thrust',tail['thrust_n'],blockage*expected_ct*scale,atol=1e-10)
    near('tail reconstructed inflow',tail['vi'],induced)
    require('tail neither zero-momentum root',abs(lam)>1e-6 and abs(lam-muz)>1e-6)
    near('tail signed momentum residual',tail['momentum_residual'],ct_residual,atol=1e-12)
    near('tail dimensional unblocked residual',tail['equivalent_unblocked_residual_n'],ct_residual*scale,atol=1e-8)
    near('tail torque',tail['tail_torque_nm'],tail_torque,atol=1e-9)
    near('tail shaft power',tail['tail_power_w'],tail_torque*tail_ratio*omega,atol=1e-8)
    wake=fraction*induced
    relative=-5.0-wake
    force=-.5*rho*fin_area*abs(relative)*relative
    no_force=-.5*rho*fin_area*5.0*(-5.0)
    expected_fin=[0.0,force,0.0,*cross(fin_arm,[0.0,force,0.0])]
    expected_no_fin=[0.0,no_force,0.0,*cross(fin_arm,[0.0,no_force,0.0])]
    vector('tail fin wake loads',tail['fin_with_wake'],expected_fin)
    vector('tail fin zero-exposure loads',tail['fin_no_wake'],expected_no_fin)
    near('tail fin relative work',tail['fin_relative_power'],force*relative)
    near('tail fin wake work',tail['fin_wake_power'],force*wake)

    # The direct diagnostic must use the actual session's initial environment,
    # 19-state frame, control inputs and accepted contact; compare its recorded
    # derivative to the committed session stage before the single accepted tick.
    session_normal=-19.3
    session_theta=-.75*session_normal/tail_tip
    yaw=session_pre['required_yaw']
    require('session yaw in stick range',isinstance(yaw,(float,int)) and math.isfinite(yaw) and abs(yaw)<=1)
    state=session_pre['state']
    require('session full state length',isinstance(state,list) and len(state)==19)
    vector('session body velocity',state[3:6],[0.0,session_normal,0.0])
    vector('session quaternion',state[6:10],[1.0,0.0,0.0,0.0])
    vector('session body rates',state[10:13],[0.0,0.0,0.0])
    vector('session rotor and controller states',state[13:19],[omega,0.0,0.0,4.2,0.0,-.15])
    vector('session wind',session_pre['wind_ned'],[0.0,0.0,0.0])
    vector('session contact loads',session_pre['contact_loads'],[0.0]*6)
    vector('session recorded inputs',session_pre['inputs'],[0.0,0.0,yaw,0.5])
    require('session reference backend',session_pre['backend'].get('backend')=='gdscript_reference')
    require('session weather recorded',isinstance(session_pre['weather'],dict) and bool(session_pre['weather']))
    require('session aircraft byte identity recorded',isinstance(session_pre['aircraft_sha256'],str)
            and re.fullmatch(r'[0-9a-f]{64}',session_pre['aircraft_sha256']) is not None)
    require('session actual finite height',isinstance(session_pre['height_over_radius'],(int,float))
            and math.isfinite(session_pre['height_over_radius']) and session_pre['height_over_radius']>0)
    require('session drive hold released',session_pre['hold'] is False)
    near('session drive scale',session_pre['drive_scale'],1.0)
    require('session prepared reset committed',session_pre['reset_accepted'] is True)
    require('session diagnostic matched committed stage',session_pre['matched_stage'] is True)
    diag=session_pre['diagnostic_derivative']
    body_derivative=session_pre['body_derivative']; continuous_derivative=session_pre['continuous_derivative']
    require('session derivative shapes',len(diag)==19 and len(body_derivative)==13 and len(continuous_derivative)==6)
    vector('session stage and diagnostic derivatives',body_derivative+continuous_derivative,diag,atol=1e-10)
    near('session constructed normal velocity',session_pre['normal'],session_normal)
    near('session main advance indicator',session_pre['mu_main'],abs(session_normal)/tip)
    near('session requested pitch',session_pre['theta'],session_theta)
    near('session diagnostic reconstructed wake',session_pre['inflow'],session_normal/2)
    near('session diagnostic thrust',session_pre['thrust'],0.0,atol=1e-10)
    session_base=(value('electronics','tail_collective_trim_rad')+session_pre['trim']['tail_collective_bias_rad']
                  +value('electronics','yaw_control_sign')*value('electronics','yaw_rate_ki_rad_per_rad')*(-.15))
    near('session zero-stick diagnostic pitch',session_pre['base_theta'],session_base)
    expected_theta=session_base+value('electronics','yaw_control_sign')*value('electronics','yaw_rate_kp_rad_per_rad_s')*value('electronics','yaw_max_rate_rad_s')*yaw
    near('session diagnostic pitch from controller',session_theta,expected_theta)
    session_relative=session_normal-fraction*(session_normal/2)
    session_fin_force=-.5*rho*fin_area*abs(session_relative)*session_relative
    vector('session fin loads',session_pre['fin_load'],[0.0,session_fin_force,0.0,*cross(fin_arm,[0.0,session_fin_force,0.0])])
    require('session accepted tick',session_post['tick']==1 and session_post['flyable'] is True
            and session_post['fault']=='' and not session_post['crash'])
    require('session post-state lengths',len(session_post['body'])==13 and len(session_post['continuous'])==6)
    require('session post-state finite',all(isinstance(x,(int,float)) and math.isfinite(x)
            for x in session_post['body']+session_post['continuous']))
    near('session yaw held for tick',session_post['yaw'],yaw)
    return {'ok':True,'independent_checks':len(checks),'checks':checks,
            'results':{'generalized_energy':values,'tilted_extra_body_work_w':extra,
                       'tail':{'ct':expected_ct,'signed_momentum_residual_ct':ct_residual,
                               'unblocked_residual_n':ct_residual*scale,'induced_velocity_m_s':induced,
                               'fin_with_wake_loads':expected_fin,'fin_no_wake_loads':expected_no_fin,
                               'fin_side_force_delta_n':force-no_force,
                               'fin_yaw_moment_delta_nm':expected_fin[5]-expected_no_fin[5]},
                       'constructed_session':{'normal_m_s':session_normal,'yaw':yaw,'reported_tick':session_post['tick'],
                                              'backend':session_pre['backend'],'aircraft_sha256':session_pre['aircraft_sha256'],
                                              'height_over_radius':session_pre['height_over_radius'],'stage_matched':session_pre['matched_stage']}},
            'limitations':['Constructed single reference-evaluator snapshots, with nonzero drive; no claim of whole-helicopter energy creation or measured rotor accuracy.',
                           'The tail momentum residual tests an idealized steady uniform-flow closure; a real zero-net-thrust rotor need not have zero local wake.',
                           'The accepted high-sideslip session reset/tick is constructed with matched initial diagnostic and session-stage derivatives; it is not a pilot-reached trajectory or observed behavior over many ticks.',
                           'The main shaft-frame inflow approximation and tail local-slope extrapolation were previously documented; these are evidence upgrades, not independent new omission counts.']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--stock',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(verify(args.log.read_text(),json.loads(args.stock.read_text())),indent=2,allow_nan=False))


if __name__=='__main__':
    main()
