"""Independent scalar oracles for the two gasoline props and the P100-RX model."""

import json
import math
import sys
from pathlib import Path


def value(node, key):
    return node[key]['value']


def interpolate(table, x):
    if x <= table[0][0]:
        return table[0][1]
    for (a, ya), (b, yb) in zip(table, table[1:]):
        if x <= b:
            return ya + (yb - ya) * (x - a) / (b - a)
    return table[-1][1]


def advance_power_minimum(ct, cp):
    """Exact interval minima of the dimensionless residual for linear Ct and Cp."""
    assert [a for a, _ in ct] == [a for a, _ in cp]
    samples = []
    for i in range(len(ct) - 1):
        a, ta = ct[i]
        b, tb = ct[i + 1]
        pa, pb = cp[i][1], cp[i + 1][1]
        mt = (tb - ta) / (b - a)
        mp = (pb - pa) / (b - a)
        cand = [a, b]
        if mt:
            stationary = (mp - ta + mt*a) / (2*mt)
            if a < stationary < b:
                cand.append(stationary)
        for j in cand:
            residual = pa + mp*(j-a) - j*(ta + mt*(j-a))
            samples.append((residual, j))
    return min(samples)


def gasoline(model):
    prop = model['propeller']
    shaft = model['engine']['shaft']
    diameter = value(prop, 'diameter')
    ct, cp = (value(prop, key) for key in ('ct_table', 'cp_table'))
    f0, f1 = value(shaft, 'friction_torque')
    idle = value(model['engine'], 'idle_rpm')
    idle_loss = (f0 + f1*idle/1000) * math.tau*idle/60
    aft, right, up = value(prop, 'thrust_line_offset')
    hub_pitch = [-2*up, 0, 2*aft]
    down, yaw = (math.radians(v) for v in value(prop,'thrust_angles'))
    axis = [math.cos(down)*math.cos(yaw),math.cos(down)*math.sin(yaw),math.sin(down)]
    turns = 4500/60
    j0 = 25*axis[0]/(turns*diameter)
    j1 = j0+sum(v*a for v,a in zip(hub_pitch,axis))/(turns*diameter)
    dq = (interpolate(cp,j1)-interpolate(cp,j0))*1.225*turns**2*diameter**5/math.tau
    dt = (interpolate(ct,j1)-interpolate(ct,j0))*1.225*turns**2*diameter**4

    # The stock Cp is at its minimum at the last knot, so the authored tail is constant.
    assert cp[-1][1] == min(p for _, p in cp)
    def net(n):
        j = 30/((n/60)*diameter)
        q = interpolate(cp, j) * 1.225 * (n/60)**2 * diameter**5 / math.tau
        return -(f0 + f1*n/1000) - q

    roots = []
    for n in range(1, 10000):
        if net(n)*net(n+1) >= 0:
            continue
        lo, hi = n, n+1
        for _ in range(50):
            mid = (lo+hi)/2
            if (net(lo)>0) == (net(mid)>0):
                lo = mid
            else:
                hi = mid
        root = (lo+hi)/2
        roots.append([root, net(root-1), net(root+1)])
    assert len(roots) == 2 and roots[0][1] < 0 < roots[0][2] and roots[1][2] < 0 < roots[1][1]
    return {'hub_delta_pitch2_m_s': hub_pitch, 'delta_T_N_Q_Nm': [dt,dq], 'reference_brake_idle_W':value(shaft,'idle_power')-idle_loss,
            'idle_loss_W':idle_loss,'min_Cp_minus_JCt_and_J':advance_power_minimum(ct,cp),
            'off_shaft_30m_s_roots_rpm_and_net_Nm_at_pm1rpm':roots}


def turbine(model):
    e = model['engine']
    thrust = value(e, 'static_thrust')
    tau = value(e, 'governor_tau')
    idle, full = value(e, 'idle_rpm'), value(e,'max_rpm')
    summary = {}
    for direction, initial, target, schedule in (('up',idle,full,'accel_limit'),('down',full,idle,'decel_limit')):
        limits = value(e,schedule)
        sign = 1 if target > initial else -1
        k = sign * limits[0][1]/limits[0][0]
        assert math.isclose(k,sign*limits[-1][1]/limits[-1][0])
        switch = target/(1+k*tau)
        t_switch = math.log(switch/initial)/k
        def time_at(n):
            if sign*(n-switch) <= 0:
                return math.log(n/initial)/k
            return t_switch-tau*math.log((n-target)/(switch-target))
        f0, f1 = (interpolate(thrust,n) for n in (initial,target))
        inverse_thrust = [[f,n] for n,f in thrust]
        crossings = [time_at(interpolate(inverse_thrust,f0+p*(f1-f0))) for p in (.1,.9)]
        # Integrate piecewise linear fuel flow exactly along each exponential speed branch.
        fuel = value(e,'fuel_flow')
        final = target + (switch - target)*math.exp(-(6-t_switch)/tau)
        knots = [initial,switch,final] + [n for n,_ in fuel if min(initial,final)<n<max(initial,final)]
        mass = 0
        knots = sorted(set(knots),reverse=sign<0)
        for a,b in zip(knots,knots[1:]):
            fa,fb = interpolate(fuel,a),interpolate(fuel,b)
            slope = (fb-fa)/(b-a)
            dt = time_at(b)-time_at(a)
            if sign*(b-switch)<=0:
                mass += (fa-slope*a)*dt+slope*(b-a)/k
            else:
                mass += (fa+slope*(target-a))*dt+slope*tau*(a-b)
        summary[direction] = {'switch_rpm':switch,'t10_t90_s':crossings,'six_second_burn_g':1000*mass}
    return summary


root = Path(sys.argv[1] if len(sys.argv)>1 else 'OpenRCsimulator')/'app/data/aircraft'
for name,fn in [('p51d_mustang_120',gasoline),('f4u_corsair_250',gasoline),('sebart_avanti_s_a200',turbine)]:
    print(name, json.dumps(fn(json.loads((root/(name+'.json')).read_text())['propulsion'])))
