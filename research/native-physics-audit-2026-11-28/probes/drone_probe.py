"""Independent numerical witnesses, using the committed FPV5 configuration. No engine launch."""
import json
import math
import sys
from pathlib import Path

import numpy as np


repo = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
cfg = json.loads((repo / 'app/data/multirotors/openrc-fpv5-x1.json').read_text())
diag = cfg['provenance']['derived_diagnostics']
rotor = cfg['rotor_law']
k_t = rotor['thrust_coefficient']['value']
k_q = rotor['torque_coefficient']['value']
diameter = cfg['rotors'][0]['diameter']['value']
shaft_j = np.array([r['inertia']['value'] for r in cfg['rotors']])
spin = np.array([r['spin'] for r in cfg['rotors']])


def bench():
    # F50 2150 KV, F5146: RPM and grams observed in the manufacturer's ten-row table.
    # https://www.ligpower.com/product/f50-5inch-racing-drone-motor.html
    rpm = np.array([5436, 10238, 14754, 18746, 22194, 25601, 28392, 31026, 33213, 35042])
    grams = np.array([38, 152, 341, 572, 824, 1120, 1407, 1704, 1975, 2136])
    thrust = grams / 1000 * 9.80665
    predicted = k_t * (rpm * math.tau / 60) ** 2
    relative = (predicted / thrust - 1) * 100
    print('bench: RPM, measured/predicted N and relative error %')
    for row in zip(rpm, thrust, predicted, relative):
        print('  %5d  %.6f  %.6f  %+.3f' % row)
    # Six fitted RPM knots, four interleaved rows withheld from the interpolation.
    anchors = [0, 2, 4, 6, 8, 9]; held = [1, 3, 5, 7]
    w2 = (rpm * math.tau / 60)**2
    trial = w2[held] * np.interp(rpm[held], rpm[anchors], (thrust/w2)[anchors])
    trial_relative = trial/thrust[held] - 1
    print('RPM-coefficient interpolation held-row absolute percentage mean %.3f%% (current %.3f%%), worst %.3f%%; max N %.6f' % (
        100*np.mean(abs(trial_relative)), np.mean(abs(relative[held])), 100*np.max(abs(trial_relative)), np.max(abs(trial-thrust[held]))))
    print('stock most-loaded static hover RPM %.3f' % (diag['hover_speed_rad_s'] * 60 / math.tau))
    # Published current multiplied by row voltage equals the published electrical input power.
    voltage, i_src, kv, armature_r = 23.88, 10.97, cfg['powertrain']['kv']['value'], cfg['powertrain']['resistance']['value']
    emf = 22194 * math.tau / 60 / kv
    print('50%% source-current duty: project %.6f, ideal bridge inferred %.6f' % (
        (emf + armature_r * i_src) / voltage,
        (emf + math.sqrt(emf**2 + 4 * voltage * armature_r * i_src)) / (2 * voltage)))


def rotor_flight():
    w, climb = 1000., 15.
    out, shaft = k_t * w**2 * climb, k_q * w**3
    print('axial: T %.6f N, aerodynamic Q %.9f Nm, direction-of-travel work %.6f W; shaft %.6f W; ratio %.6f; J %.6f' % (
        k_t*w*w, k_q*w*w, out, shaft, out/shaft, climb / ((w/math.tau) * diameter)))
    hubs = np.array([r['hub_frd']['value'] for r in cfg['rotors']])
    closest = min(np.linalg.norm(hubs[a]-hubs[b]) for a in range(4) for b in range(a))
    print('stock hub separation %.8f m, separation/R %.6f, tip gap %.8f m; 1R, 2R, 4R heights %s' % (
        closest, 2*closest/diameter, closest-diameter, [round(v*diameter/2,5) for v in (1,2,4)]))


def impact(gate=False):
    # Stock front frame above the prop discs. gate=True uses the south-west top banner of Practice oval 1.
    m = diag['mass_kg']
    jxx, jyy, jzz, jxy, jxz, jyz = diag['inertia_kg_m2']
    locked = np.array([[jxx,jxy,jxz], [jxy,jyy,jyz], [jxz,jyz,jzz]])
    free = locked.copy()
    free[2,2] -= sum(shaft_j)
    radius = np.array([cfg['rotors'][1]['hub_frd']['value'][0], 0.06, -0.030])
    normal = np.array([-1.,0.,0.])
    mu = 0.5
    if gate:
        # Heading 80 degrees into gate 0 (normal heading 90); the right front edge contacts the banner midspan.
        angle = math.radians(10)
        normal = np.array([-math.cos(angle), -math.sin(angle), 0.])
        radius[1] = cfg['rotors'][1]['hub_frd']['value'][1]
        # The lower edge of the banner is 21 mm above the CG; the upper part of this frame edge overlaps it.
        # Clip the two-vertex support segment as in frame_obstacle_contact.gd:390–420, including 1-micron skin.
        z_top = min(p[2] for p in cfg['contacts']['hull']['value'])
        z_release = -0.021 + 1.e-6
        radius[2] = (z_top + 2*z_release)/3
        mu = 0.4
        print('Practice oval 1 top banner: body witness', radius, 'outward normal', normal)
    shaft0 = np.array([1600.,600.,600.,1600.])
    rates0 = np.zeros(3)
    v0 = -0.2*normal

    def kinetic(v, rates, shaft):
        body = (m * (v @ v) + rates @ locked @ rates) / 2
        coupled = body + (shaft_j @ (shaft**2)) / 2 - rates[2] * (spin*shaft_j) @ shaft
        return body, coupled

    def bounce(matrix):
        inv = np.linalg.inv(matrix)
        arm_n = np.cross(radius, normal)
        normal_speed = -normal @ (v0 + np.cross(rates0, radius))
        impulse_n = 1.2 * normal_speed / (1/m + arm_n @ inv @ arm_n)
        v = v0 + impulse_n * normal / m
        rates = rates0 + impulse_n * (inv @ arm_n)
        point = v + np.cross(rates, radius)
        tangent = point - normal * (normal @ point)
        direction = tangent / np.linalg.norm(tangent)
        arm_t = np.cross(radius, direction)
        magnitude = min(mu*impulse_n, np.linalg.norm(tangent)/(1/m + arm_t @ inv @ arm_t))
        normal_change = normal @ (-direction/m + np.cross(-inv @ arm_t,radius))
        if normal_change < 0 and normal @ point >= 0:
            magnitude = min(magnitude, (normal@point) / -normal_change)
        return v - magnitude * direction / m, rates - magnitude * (inv @ arm_t), impulse_n, magnitude

    for label, matrix in [('current',locked), ('free shafts',free)]:
        v1, rates1, n, f = bounce(matrix)
        shaft1 = shaft0 + (spin*rates1[2] if label=='free shafts' else 0.)
        sizes = np.array(kinetic(v1,rates1,shaft1)) - np.array(kinetic(v0,rates0,shaft0))
        absolute_error = np.max(np.abs((rates1[2] - spin*shaft1) - (rates0[2] - spin*shaft0)))
        print('%s: normal and friction impulses %.9f/%.9f Ns; body dK %+.9f J; coupled dK %+.9f J; max free axial speed jump %.9f rad/s; delta r %.9f rad/s' % (
            label, n, f, sizes[0], sizes[1], absolute_error, rates1[2]))


def rotor_threshold():
    # Symmetric drive and equal speeds cancel rotor yaw reaction; all four shafts use the same scalar ODE in free air.
    kv = cfg['powertrain']['kv']['value']
    r = cfg['powertrain']['resistance']['value']
    idle = cfg['powertrain']['no_load_current']['value']
    rp = cfg['battery']['resistance']['value']
    iaux = cfg['battery']['auxiliary_current']['value']
    cap = 3600 * cfg['battery']['capacity']['value']
    soc_points, voltage_points = np.array(cfg['battery']['ocv_points']['value']).T
    dt = 1/240

    # Exact line/circle intersection for a thin vertical shaft and a level prop disc on the outer side of the front right hub.
    # This is the same well-conditioned spatial case the production swept-prop code solves analytically.
    travel = 15.0 * dt
    radii = diameter/2 + 0.005
    x = 0.2 * travel
    y = math.sqrt(radii**2 - (0.1*travel)**2)
    half = math.sqrt(radii**2 - y**2)
    print('5 mm capsule relative to front right hub x=%.8f m, y=%.8f m; intersection spans fractions %.6f..%.6f' % (
        x,y,(x-half)/travel,(x+half)/travel))

    for w0, duty in [(265.,0.2),(302.,0.055)]:
        def rhs(state):
            w, charge = state
            voc = np.interp(charge/cap,soc_points,voltage_points)
            vbus = (voc - rp*iaux + rp*4*duty*(w/kv)/r) / (1 + rp*4*duty*duty/r)
            current = (duty*vbus - w/kv) / r
            pack_current = iaux+4*duty*current
            accept = max(0,cap-charge)/0.2
            assert pack_current >= -accept
            return np.array([((current-idle)/kv-k_q*w*w)/shaft_j[0],-pack_current])
        state = np.array([w0,cap]); start = state[0]; early = exit_speed = None
        for i in range(100):
            h = dt/100
            k1 = rhs(state); k2 = rhs(state+h*k1/2); k3 = rhs(state+h*k2/2); k4 = rhs(state+h*k3)
            state += h/6*(k1+2*k2+2*k3+k4)
            if i==9:
                early = state[0]
            if i==29:
                exit_speed = state[0]
        print('signed-speed strike threshold: start %.2f, duty %.3f, f=0.1/0.3 speeds %.6f/%.6f, end %.6f rad/s; early/end eligible %s/%s' % (
            start, duty, early, exit_speed, state[0], early>300, state[0]>300))


if __name__ == '__main__':
    bench(); rotor_flight(); impact(); impact(gate=True); rotor_threshold()
